'use strict';

const express = require('express');
const router = express.Router();
const { sql, getPool } = require('../db/pool');

function asInt(v, d) {
  const n = parseInt(v, 10);
  return Number.isFinite(n) ? n : d;
}

router.get('/overview', async (req, res, next) => {
  try {
    const pool = await getPool();
    const r = await pool.request().query(`
      SELECT
        (SELECT COUNT(*) FROM dbo.Machines) AS TotalMachines,
        (SELECT COUNT(*) FROM dbo.Machines WHERE LastSeenUtc > DATEADD(MINUTE,-15,SYSUTCDATETIME())) AS OnlineMachines,
        (SELECT COUNT(*) FROM dbo.Users) AS TotalUsers,
        (SELECT COUNT(*) FROM dbo.Sessions WHERE LogoffTimeUtc IS NULL) AS ActiveSessions,
        -- Machines that have been offline (no agent contact) for 3+ days
        (SELECT COUNT(*) FROM dbo.Machines
          WHERE LastSeenUtc < DATEADD(DAY, -3, SYSUTCDATETIME())) AS OfflineLast3Days,
        -- Machines that have been offline for 7+ days
        (SELECT COUNT(*) FROM dbo.Machines
          WHERE LastSeenUtc < DATEADD(DAY, -7, SYSUTCDATETIME())) AS OfflineLast7Days,
        -- Today's offline users: users who were active in the last 7 days
        -- but have NOT had a session starting today.
        (SELECT COUNT(DISTINCT u.UserId)
           FROM dbo.Users u
          WHERE EXISTS (
            SELECT 1 FROM dbo.Sessions s
             WHERE s.UserId = u.UserId
               AND s.LogonTimeUtc > DATEADD(DAY, -7, SYSUTCDATETIME())
          )
            AND NOT EXISTS (
            SELECT 1 FROM dbo.Sessions s
             WHERE s.UserId = u.UserId
               AND CAST(s.LogonTimeUtc AS DATE) = CAST(SYSUTCDATETIME() AS DATE)
          )) AS OfflineUsersToday;

      SELECT TOP 10 MachineName, LastSeenUtc, OSVersion, AgentVersion
      FROM dbo.Machines ORDER BY LastSeenUtc DESC;

      SELECT TOP 20 *
      FROM dbo.vw_ActiveSessions
      ORDER BY LogonTimeUtc DESC;
    `);
    res.json({
      stats: r.recordsets[0][0],
      recentMachines: r.recordsets[1],
      activeSessions: r.recordsets[2]
    });
  } catch (e) { next(e); }
});

router.get('/machines', async (req, res, next) => {
  try {
    const search   = (req.query.search || '').toString();
    const page     = Math.max(1,   asInt(req.query.page,     1));
    const pageSize = Math.min(500, Math.max(1, asInt(req.query.pageSize, 50)));
    const offset   = (page - 1) * pageSize;

    const pool = await getPool();
    const r = await pool.request()
      .input('Search',   sql.NVarChar(128), `%${search}%`)
      .input('Offset',   sql.Int, offset)
      .input('PageSize', sql.Int, pageSize)
      .query(`
        SELECT COUNT(*) AS Total
          FROM dbo.Machines m
         WHERE @Search = '%%' OR m.MachineName LIKE @Search;

        SELECT m.MachineId, m.MachineName, m.Domain, m.OSVersion, m.IPAddress,
               m.AgentVersion, m.FirstSeenUtc, m.LastSeenUtc,
               (SELECT COUNT(*) FROM dbo.Sessions s WHERE s.MachineId = m.MachineId) AS SessionCount,
               (SELECT COUNT(*) FROM dbo.Sessions s WHERE s.MachineId = m.MachineId AND s.LogoffTimeUtc IS NULL) AS ActiveSessionCount,
               (SELECT TOP 1 u.UserName
                  FROM dbo.Sessions s
                  JOIN dbo.Users u ON u.UserId = s.UserId
                 WHERE s.MachineId = m.MachineId
                 ORDER BY CASE WHEN s.LogoffTimeUtc IS NULL THEN 0 ELSE 1 END,
                          s.LogonTimeUtc DESC) AS LatestUserName,
               (SELECT TOP 1 u.Domain
                  FROM dbo.Sessions s
                  JOIN dbo.Users u ON u.UserId = s.UserId
                 WHERE s.MachineId = m.MachineId
                 ORDER BY CASE WHEN s.LogoffTimeUtc IS NULL THEN 0 ELSE 1 END,
                          s.LogonTimeUtc DESC) AS LatestUserDomain
        FROM dbo.Machines m
        WHERE @Search = '%%' OR m.MachineName LIKE @Search
        ORDER BY m.LastSeenUtc DESC
        OFFSET @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;
      `);
    res.json({
      rows:     r.recordsets[1],
      total:    r.recordsets[0][0].Total,
      page, pageSize
    });
  } catch (e) { next(e); }
});

router.get('/machines/:id', async (req, res, next) => {
  try {
    const id = asInt(req.params.id, 0);
    const pool = await getPool();
    const r = await pool.request().input('Id', sql.Int, id).query(`
      SELECT * FROM dbo.Machines WHERE MachineId = @Id;
      SELECT TOP 50 EventType, EventTimeUtc, Details,
             (SELECT UserName FROM dbo.Users u WHERE u.UserId = e.UserId) AS UserName
      FROM dbo.SessionEvents e WHERE MachineId = @Id ORDER BY EventTimeUtc DESC;
      SELECT TOP 25 a.AppName, SUM(a.ForegroundSeconds) AS ForegroundSeconds
      FROM dbo.AppUsage a WHERE a.MachineId = @Id
      GROUP BY a.AppName ORDER BY SUM(a.ForegroundSeconds) DESC;
    `);
    if (r.recordsets[0].length === 0) return res.status(404).json({ error: 'Not found' });
    res.json({
      machine: r.recordsets[0][0],
      recentEvents: r.recordsets[1],
      topApps: r.recordsets[2]
    });
  } catch (e) { next(e); }
});

router.get('/machines/:id/sessions', async (req, res, next) => {
  try {
    const id = asInt(req.params.id, 0);
    const limit = Math.min(asInt(req.query.limit, 50), 500);
    const pool = await getPool();
    const r = await pool.request()
      .input('Id', sql.Int, id)
      .input('Lim', sql.Int, limit)
      .query(`
        SELECT TOP (@Lim) s.SessionId, s.LogonTimeUtc, s.LogoffTimeUtc, s.DurationSeconds,
               s.IdleSeconds, s.ActiveSeconds, s.LockCount, s.EndReason,
               u.UserName, u.Domain
        FROM dbo.Sessions s
        JOIN dbo.Users u ON u.UserId = s.UserId
        WHERE s.MachineId = @Id
        ORDER BY s.LogonTimeUtc DESC;
      `);
    res.json(r.recordset);
  } catch (e) { next(e); }
});

router.get('/users', async (req, res, next) => {
  try {
    const pool = await getPool();
    const r = await pool.request().query(`
      SELECT u.UserId, u.UserName, u.Domain, u.DisplayName,
             u.FirstSeenUtc, u.LastSeenUtc,
             (SELECT COUNT(*) FROM dbo.Sessions s WHERE s.UserId = u.UserId) AS SessionCount,
             (SELECT SUM(ISNULL(s.DurationSeconds,0)) FROM dbo.Sessions s WHERE s.UserId = u.UserId) AS TotalSeconds
      FROM dbo.Users u
      ORDER BY u.LastSeenUtc DESC;
    `);
    res.json(r.recordset);
  } catch (e) { next(e); }
});

router.get('/users/daily', async (req, res, next) => {
  try {
    const today = new Date();
    const def7  = new Date(Date.now() - 7 * 86400000);
    const fmt   = (d) => d.toISOString().slice(0, 10);
    const start = (req.query.start || fmt(def7)).toString();
    const end   = (req.query.end   || fmt(today)).toString();
    const q     = (req.query.q || '').toString().trim();
    const like  = q ? `%${q}%` : '%%';
    const page     = Math.max(1,   asInt(req.query.page,     1));
    const pageSize = Math.min(500, Math.max(1, asInt(req.query.pageSize, 50)));
    const offset   = (page - 1) * pageSize;
    // Browser-supplied timezone offset in minutes (UTC+05:30 -> 330).
    let tz = parseInt(req.query.tz, 10);
    if (!Number.isFinite(tz)) tz = 0;
    if (tz < -14 * 60 || tz > 14 * 60) tz = 0;

    const pool = await getPool();
    const r = await pool.request()
      .input('Start',    sql.Date,          start)
      .input('End',      sql.Date,          end)
      .input('Search',   sql.NVarChar(128), like)
      .input('Tz',       sql.Int,           tz)
      .input('Offset',   sql.Int,           offset)
      .input('PageSize', sql.Int,           pageSize)
      .query(`
        WITH SessionsDaily AS (
          SELECT
            CAST(DATEADD(MINUTE, @Tz, s.LogonTimeUtc) AS DATE) AS [Date],
            s.MachineId, s.UserId,
            MIN(s.LogonTimeUtc) AS FirstLogin,
            SUM(ISNULL(
              s.DurationSeconds,
              DATEDIFF(SECOND, s.LogonTimeUtc, ISNULL(s.LogoffTimeUtc, SYSUTCDATETIME()))
            )) AS TotalSeconds,
            SUM(ISNULL(s.ActiveSeconds, 0)) AS ActiveSeconds
          FROM dbo.Sessions s
          WHERE CAST(DATEADD(MINUTE, @Tz, s.LogonTimeUtc) AS DATE) BETWEEN @Start AND @End
          GROUP BY CAST(DATEADD(MINUTE, @Tz, s.LogonTimeUtc) AS DATE), s.MachineId, s.UserId
        ),
        LocksDaily AS (
          SELECT
            CAST(DATEADD(MINUTE, @Tz, e.EventTimeUtc) AS DATE) AS [Date],
            e.MachineId, e.UserId,
            MAX(CASE WHEN e.EventType = 'Lock'     THEN e.EventTimeUtc END) AS LastLock,
            MAX(CASE WHEN e.EventType = 'Unlock'   THEN e.EventTimeUtc END) AS LastUnlock,
            MAX(CASE WHEN e.EventType = 'Shutdown' THEN e.EventTimeUtc END) AS LastShutdown
          FROM dbo.SessionEvents e
          WHERE e.EventType IN ('Lock','Unlock','Shutdown')
            AND CAST(DATEADD(MINUTE, @Tz, e.EventTimeUtc) AS DATE) BETWEEN @Start AND @End
          GROUP BY CAST(DATEADD(MINUTE, @Tz, e.EventTimeUtc) AS DATE), e.MachineId, e.UserId
        ),
        LatestSession AS (
          -- Pick the most-recent session per (date, machine, user) so we can
          -- decide what the "last status" was: Active, Locked, Logoff, Shutdown, Restarted, etc.
          SELECT * FROM (
            SELECT
              CAST(DATEADD(MINUTE, @Tz, s.LogonTimeUtc) AS DATE) AS [Date],
              s.MachineId, s.UserId, s.LogoffTimeUtc, s.EndReason, s.IsLocked,
              ROW_NUMBER() OVER (
                PARTITION BY CAST(DATEADD(MINUTE, @Tz, s.LogonTimeUtc) AS DATE), s.MachineId, s.UserId
                ORDER BY s.LogonTimeUtc DESC
              ) AS rn
            FROM dbo.Sessions s
            WHERE CAST(DATEADD(MINUTE, @Tz, s.LogonTimeUtc) AS DATE) BETWEEN @Start AND @End
          ) x WHERE x.rn = 1
        )
        SELECT
          sd.[Date],
          m.MachineId,
          m.MachineName,
          u.UserName,
          u.Domain,
          sd.FirstLogin,
          ld.LastLock,
          ld.LastUnlock,
          ld.LastShutdown,
          m.LastSeenUtc AS MachineLastSeen,
          sd.TotalSeconds,
          sd.ActiveSeconds,
          CASE
            -- Session row is still open, but the machine itself hasn't reported in 15 min
            -- → the agent went away without writing a Logoff. Don't lie that it's Active.
            WHEN ls.LogoffTimeUtc IS NULL
                 AND m.LastSeenUtc < DATEADD(MINUTE, -15, SYSUTCDATETIME())   THEN 'Offline'
            WHEN ls.LogoffTimeUtc IS NULL AND ls.IsLocked = 1                 THEN 'Locked'
            WHEN ls.LogoffTimeUtc IS NULL                                     THEN 'Active'
            WHEN ls.EndReason = 'Shutdown'                                    THEN 'Shutdown'
            WHEN ls.EndReason = 'Logoff'                                      THEN 'Logoff'
            WHEN ls.EndReason = 'AgentRestart'                                THEN 'Restarted'
            WHEN ls.EndReason = 'StaleTimeout'                                THEN 'Offline'
            WHEN ls.EndReason = 'LongIdle'                                    THEN 'Idle'
            WHEN ls.EndReason = 'Midnight'                                    THEN 'Day End'
            WHEN ls.EndReason IS NOT NULL                                     THEN ls.EndReason
            ELSE 'Unknown'
          END AS LastStatus,
          COUNT(*) OVER () AS TotalRows
        FROM SessionsDaily sd
        JOIN dbo.Machines m ON m.MachineId = sd.MachineId
        JOIN dbo.Users    u ON u.UserId    = sd.UserId
        LEFT JOIN LocksDaily ld
          ON ld.[Date] = sd.[Date] AND ld.MachineId = sd.MachineId AND ld.UserId = sd.UserId
        LEFT JOIN LatestSession ls
          ON ls.[Date] = sd.[Date] AND ls.MachineId = sd.MachineId AND ls.UserId = sd.UserId
        WHERE (@Search = '%%'
               OR m.MachineName LIKE @Search
               OR u.UserName    LIKE @Search)
        ORDER BY sd.[Date] DESC, m.MachineName, u.UserName
        OFFSET @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;
      `);
    // Note: total row count comes from the same query via COUNT(*) OVER () inlined below.
    // (See the modified SELECT — TotalRows is on every row, identical value.)
    const rows  = r.recordset;
    const total = rows.length > 0 && rows[0].TotalRows != null ? rows[0].TotalRows : rows.length;
    // Strip TotalRows from each row so the JSON stays clean
    for (const row of rows) delete row.TotalRows;
    res.json({ rows, total, page, pageSize });
  } catch (e) { next(e); }
});

router.get('/sessions/:id', async (req, res, next) => {
  try {
    const id = asInt(req.params.id, 0);
    const pool = await getPool();
    const r = await pool.request().input('Id', sql.BigInt, id).query(`
      SELECT s.*, m.MachineName, u.UserName, u.Domain
      FROM dbo.Sessions s
      JOIN dbo.Machines m ON m.MachineId = s.MachineId
      JOIN dbo.Users u    ON u.UserId    = s.UserId
      WHERE s.SessionId = @Id;

      SELECT EventType, EventTimeUtc, Details
      FROM dbo.SessionEvents e
      WHERE e.MachineId = (SELECT MachineId FROM dbo.Sessions WHERE SessionId = @Id)
        AND e.UserId    = (SELECT UserId    FROM dbo.Sessions WHERE SessionId = @Id)
        AND e.EventTimeUtc BETWEEN
          (SELECT LogonTimeUtc FROM dbo.Sessions WHERE SessionId = @Id) AND
          ISNULL((SELECT LogoffTimeUtc FROM dbo.Sessions WHERE SessionId = @Id), SYSUTCDATETIME())
      ORDER BY EventTimeUtc;

      SELECT AppName, AppPath, ForegroundSeconds, RunningSeconds, LaunchCount,
             FirstSeenUtc, LastSeenUtc, WindowTitleSample
      FROM dbo.AppUsage WHERE SessionId = @Id ORDER BY ForegroundSeconds DESC;
    `);
    if (r.recordsets[0].length === 0) return res.status(404).json({ error: 'Not found' });
    res.json({
      session: r.recordsets[0][0],
      events: r.recordsets[1],
      apps: r.recordsets[2]
    });
  } catch (e) { next(e); }
});

router.get('/events', async (req, res, next) => {
  try {
    const limit = Math.min(asInt(req.query.limit, 100), 1000);
    const type  = (req.query.type || '').toString();
    const pool = await getPool();
    const r = await pool.request()
      .input('Lim', sql.Int, limit)
      .input('Type', sql.NVarChar(32), type || null)
      .query(`
        SELECT TOP (@Lim) e.EventId, e.EventType, e.EventTimeUtc, e.Details,
               m.MachineName, u.UserName, u.Domain
        FROM dbo.SessionEvents e
        JOIN dbo.Machines m ON m.MachineId = e.MachineId
        LEFT JOIN dbo.Users u ON u.UserId = e.UserId
        WHERE (@Type IS NULL OR e.EventType = @Type)
        ORDER BY e.EventTimeUtc DESC;
      `);
    res.json(r.recordset);
  } catch (e) { next(e); }
});

router.get('/apps/list', async (req, res, next) => {
  try {
    const today = new Date();
    const def7  = new Date(Date.now() - 7 * 86400000);
    const fmt   = (d) => d.toISOString().slice(0, 10);
    const start = (req.query.start || fmt(def7)).toString();
    const end   = (req.query.end   || fmt(today)).toString();
    const q     = (req.query.q || '').toString().trim();
    const like  = q ? `%${q}%` : '%%';
    const page     = Math.max(1,    asInt(req.query.page,     1));
    const pageSize = Math.min(1000, Math.max(1, asInt(req.query.pageSize, 50)));
    const offset   = (page - 1) * pageSize;

    const pool = await getPool();
    const r = await pool.request()
      .input('Start',    sql.Date,          start)
      .input('End',      sql.Date,          end)
      .input('Search',   sql.NVarChar(256), like)
      .input('Offset',   sql.Int,           offset)
      .input('PageSize', sql.Int,           pageSize)
      .query(`
        WITH agg AS (
          SELECT
            a.AppName,
            a.AppPath,
            m.MachineName,
            u.UserName,
            u.Domain,
            MIN(a.FirstSeenUtc)    AS FirstSeenUtc,
            MAX(a.LastSeenUtc)     AS LastSeenUtc,
            SUM(a.ForegroundSeconds) AS ForegroundSeconds,
            SUM(a.RunningSeconds)    AS RunningSeconds,
            SUM(a.LaunchCount)       AS LaunchCount
          FROM dbo.AppUsage a
          JOIN dbo.Machines m ON m.MachineId = a.MachineId
          JOIN dbo.Users    u ON u.UserId    = a.UserId
          WHERE a.LastSeenUtc  >= @Start
            AND a.FirstSeenUtc <  DATEADD(DAY, 1, @End)
            AND (@Search = '%%'
                 OR a.AppName     LIKE @Search
                 OR m.MachineName LIKE @Search
                 OR u.UserName    LIKE @Search)
          GROUP BY a.AppName, a.AppPath, m.MachineName, u.UserName, u.Domain
        )
        SELECT *, COUNT(*) OVER () AS TotalRows
        FROM agg
        ORDER BY ForegroundSeconds DESC
        OFFSET @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;
      `);
    const rows  = r.recordset;
    const total = rows.length > 0 && rows[0].TotalRows != null ? rows[0].TotalRows : rows.length;
    for (const row of rows) delete row.TotalRows;
    res.json({ rows, total, page, pageSize });
  } catch (e) { next(e); }
});

router.get('/apps/top', async (req, res, next) => {
  try {
    const days     = Math.min(asInt(req.query.days, 7), 90);
    const usersCsv    = (req.query.users    || '').toString().trim();
    const machinesCsv = (req.query.machines || '').toString().trim();
    const userList    = usersCsv    ? usersCsv.split(',').map(s => s.trim()).filter(Boolean) : [];
    const machineList = machinesCsv ? machinesCsv.split(',').map(s => s.trim()).filter(Boolean) : [];

    const pool = await getPool();
    const reqDb = pool.request().input('Days', sql.Int, days);

    let userFilter = '';
    if (userList.length) {
      const params = userList.map((u, i) => {
        const k = 'U' + i;
        reqDb.input(k, sql.NVarChar(256), u);
        return '@' + k;
      });
      userFilter = ` AND a.UserId IN (SELECT UserId FROM dbo.Users WHERE UserName IN (${params.join(',')}))`;
    }

    let machineFilter = '';
    if (machineList.length) {
      const params = machineList.map((m, i) => {
        const k = 'M' + i;
        reqDb.input(k, sql.NVarChar(128), m);
        return '@' + k;
      });
      machineFilter = ` AND a.MachineId IN (SELECT MachineId FROM dbo.Machines WHERE MachineName IN (${params.join(',')}))`;
    }

    const r = await reqDb.query(`
      SELECT TOP 25 a.AppName,
             SUM(a.ForegroundSeconds) AS ForegroundSeconds,
             SUM(a.LaunchCount)       AS LaunchCount,
             COUNT(DISTINCT a.MachineId) AS MachineCount,
             COUNT(DISTINCT a.UserId)    AS UserCount
      FROM dbo.AppUsage a
      WHERE a.LastSeenUtc > DATEADD(DAY, -@Days, SYSUTCDATETIME())
        ${userFilter}
        ${machineFilter}
      GROUP BY a.AppName
      ORDER BY ForegroundSeconds DESC;
    `);
    res.json(r.recordset);
  } catch (e) { next(e); }
});

router.get('/reports/daily', async (req, res, next) => {
  try {
    const days = Math.min(asInt(req.query.days, 14), 90);
    const pool = await getPool();
    const r = await pool.request().input('Days', sql.Int, days).query(`
      SELECT * FROM dbo.vw_DailyMachineSummary
      WHERE [Day] >= CAST(DATEADD(DAY,-@Days,GETUTCDATE()) AS DATE)
      ORDER BY [Day] DESC, MachineName;
    `);
    res.json(r.recordset);
  } catch (e) { next(e); }
});

module.exports = router;
