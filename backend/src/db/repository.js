'use strict';

/**
 * All SQL access lives here. Keeps routes clean and queries reviewable.
 */
const { sql, getPool } = require('./pool');

async function upsertMachine({ machineName, hardwareId, domain, osVersion, ipAddress, agentVersion }) {
  const pool = await getPool();

  // Identify the row using HardwareId first (stable across hostname renames).
  // Fall back to MachineName only when the agent didn't provide a HardwareId
  // (legacy agent, or a machine whose BIOS doesn't expose a UUID).
  //
  // The MERGE's ON clause must be DETERMINISTIC for MSSQL, so we cleanly
  // express the "match by HardwareId OR (no HardwareId and match by name)"
  // priority by first resolving the target MachineId in a separate SELECT.
  const r = await pool
    .request()
    .input('MachineName',  sql.NVarChar(128), machineName)
    .input('HardwareId',   sql.NVarChar(64),  hardwareId || null)
    .input('Domain',       sql.NVarChar(128), domain || null)
    .input('OSVersion',    sql.NVarChar(128), osVersion || null)
    .input('IPAddress',    sql.NVarChar(64),  ipAddress || null)
    .input('AgentVersion', sql.NVarChar(32),  agentVersion || null)
    .query(`
      DECLARE @MatchedId INT;
      -- Prefer match by HardwareId (stable across rename)
      IF @HardwareId IS NOT NULL
        SELECT TOP 1 @MatchedId = MachineId
          FROM dbo.Machines
         WHERE HardwareId = @HardwareId;
      -- Fall back to MachineName if no HardwareId match
      IF @MatchedId IS NULL
        SELECT TOP 1 @MatchedId = MachineId
          FROM dbo.Machines
         WHERE MachineName = @MachineName
           AND (HardwareId IS NULL OR @HardwareId IS NULL);

      IF @MatchedId IS NOT NULL
      BEGIN
        UPDATE dbo.Machines
           SET MachineName  = @MachineName,
               HardwareId   = COALESCE(@HardwareId, HardwareId),
               Domain       = COALESCE(@Domain, Domain),
               OSVersion    = COALESCE(@OSVersion, OSVersion),
               IPAddress    = COALESCE(@IPAddress, IPAddress),
               AgentVersion = COALESCE(@AgentVersion, AgentVersion),
               LastSeenUtc  = SYSUTCDATETIME()
         WHERE MachineId = @MatchedId;
        SELECT @MatchedId AS MachineId;
      END
      ELSE
      BEGIN
        INSERT INTO dbo.Machines (MachineName, HardwareId, Domain, OSVersion, IPAddress, AgentVersion)
        OUTPUT inserted.MachineId
        VALUES (@MachineName, @HardwareId, @Domain, @OSVersion, @IPAddress, @AgentVersion);
      END
    `);
  return r.recordset[0].MachineId;
}

async function upsertUser({ userName, domain, displayName }) {
  if (!userName) return null;
  const pool = await getPool();
  const r = await pool
    .request()
    .input('UserName', sql.NVarChar(256), userName)
    .input('Domain', sql.NVarChar(128), domain || null)
    .input('DisplayName', sql.NVarChar(256), displayName || null)
    .query(`
      MERGE dbo.Users AS T
      USING (SELECT @UserName AS UserName, @Domain AS Domain) AS S
        ON ISNULL(T.Domain,'') = ISNULL(S.Domain,'') AND T.UserName = S.UserName
      WHEN MATCHED THEN UPDATE SET
          DisplayName = COALESCE(@DisplayName, T.DisplayName),
          LastSeenUtc = SYSUTCDATETIME()
      WHEN NOT MATCHED THEN INSERT (UserName, Domain, DisplayName)
                          VALUES (@UserName, @Domain, @DisplayName)
      OUTPUT inserted.UserId;
    `);
  return r.recordset[0].UserId;
}

async function insertEvent(tx, { machineId, userId, eventType, eventTimeUtc, clientEventId, details }) {
  const r = await new sql.Request(tx)
    .input('MachineId', sql.Int, machineId)
    .input('UserId', sql.Int, userId)
    .input('EventType', sql.NVarChar(32), eventType)
    .input('EventTimeUtc', sql.DateTime2, new Date(eventTimeUtc))
    .input('ClientEventId', sql.NVarChar(64), clientEventId || null)
    .input('Details', sql.NVarChar(1024), details || null)
    .query(`
      IF @ClientEventId IS NOT NULL AND EXISTS (
        SELECT 1 FROM dbo.SessionEvents WHERE ClientEventId = @ClientEventId
      )
        SELECT CAST(0 AS BIT) AS Inserted;
      ELSE
      BEGIN
        INSERT INTO dbo.SessionEvents (MachineId, UserId, EventType, EventTimeUtc, ClientEventId, Details)
        VALUES (@MachineId, @UserId, @EventType, @EventTimeUtc, @ClientEventId, @Details);
        SELECT CAST(1 AS BIT) AS Inserted;
      END
    `);
  return r.recordset[0].Inserted;
}

async function upsertSession(tx, {
  machineId, userId, clientSessionId, logonTimeUtc, logoffTimeUtc,
  idleSeconds, activeSeconds, lockCount, isLocked, endReason
}) {
  const r = await new sql.Request(tx)
    .input('MachineId', sql.Int, machineId)
    .input('UserId', sql.Int, userId)
    .input('ClientSessionId', sql.NVarChar(64), clientSessionId)
    .input('LogonTimeUtc', sql.DateTime2, new Date(logonTimeUtc))
    .input('LogoffTimeUtc', sql.DateTime2, logoffTimeUtc ? new Date(logoffTimeUtc) : null)
    .input('IdleSeconds', sql.Int, idleSeconds || 0)
    .input('ActiveSeconds', sql.Int, activeSeconds || 0)
    .input('LockCount', sql.Int, lockCount || 0)
    .input('IsLocked', sql.Bit, isLocked ? 1 : 0)
    .input('EndReason', sql.NVarChar(32), endReason || null)
    .query(`
      MERGE dbo.Sessions AS T
      USING (SELECT @ClientSessionId AS ClientSessionId) AS S
        ON T.ClientSessionId = S.ClientSessionId
      WHEN MATCHED THEN UPDATE SET
          -- Agent is the source of truth for session liveness:
          -- if the agent sends LogoffTimeUtc=NULL, the session is alive — clear any
          -- LogoffTimeUtc that stale-cleanup may have set, so the session reopens.
          LogoffTimeUtc = @LogoffTimeUtc,
          DurationSeconds = CASE
              WHEN @LogoffTimeUtc IS NOT NULL THEN DATEDIFF(SECOND, T.LogonTimeUtc, @LogoffTimeUtc)
              ELSE NULL END,
          IdleSeconds   = CASE WHEN @IdleSeconds   > T.IdleSeconds   THEN @IdleSeconds   ELSE T.IdleSeconds   END,
          ActiveSeconds = CASE WHEN @ActiveSeconds > T.ActiveSeconds THEN @ActiveSeconds ELSE T.ActiveSeconds END,
          LockCount     = CASE WHEN @LockCount     > T.LockCount     THEN @LockCount     ELSE T.LockCount     END,
          IsLocked      = @IsLocked,
          EndReason     = CASE WHEN @LogoffTimeUtc IS NOT NULL THEN COALESCE(@EndReason, T.EndReason) ELSE NULL END,
          UpdatedUtc    = SYSUTCDATETIME()
      WHEN NOT MATCHED THEN INSERT
        (MachineId, UserId, ClientSessionId, LogonTimeUtc, LogoffTimeUtc, DurationSeconds,
         IdleSeconds, ActiveSeconds, LockCount, IsLocked, EndReason)
        VALUES
        (@MachineId, @UserId, @ClientSessionId, @LogonTimeUtc, @LogoffTimeUtc,
         CASE WHEN @LogoffTimeUtc IS NOT NULL THEN DATEDIFF(SECOND, @LogonTimeUtc, @LogoffTimeUtc) ELSE NULL END,
         @IdleSeconds, @ActiveSeconds, @LockCount, @IsLocked, @EndReason)
      OUTPUT inserted.SessionId;
    `);
  return r.recordset[0].SessionId;
}

async function upsertAppUsage(tx, {
  sessionId, machineId, userId, appName, appPath, windowTitleSample,
  firstSeenUtc, lastSeenUtc, foregroundSeconds, runningSeconds, launchCount
}) {
  await new sql.Request(tx)
    .input('SessionId', sql.BigInt, sessionId)
    .input('MachineId', sql.Int, machineId)
    .input('UserId', sql.Int, userId)
    .input('AppName', sql.NVarChar(256), appName)
    .input('AppPath', sql.NVarChar(1024), appPath || null)
    .input('WindowTitleSample', sql.NVarChar(512), windowTitleSample || null)
    .input('FirstSeenUtc', sql.DateTime2, new Date(firstSeenUtc))
    .input('LastSeenUtc', sql.DateTime2, new Date(lastSeenUtc))
    .input('ForegroundSeconds', sql.Int, foregroundSeconds || 0)
    .input('RunningSeconds', sql.Int, runningSeconds || 0)
    .input('LaunchCount', sql.Int, launchCount || 0)
    .query(`
      MERGE dbo.AppUsage AS T
      USING (SELECT @SessionId AS SessionId, @AppName AS AppName) AS S
        ON T.SessionId = S.SessionId AND T.AppName = S.AppName
      WHEN MATCHED THEN UPDATE SET
          AppPath = COALESCE(@AppPath, T.AppPath),
          WindowTitleSample = COALESCE(@WindowTitleSample, T.WindowTitleSample),
          LastSeenUtc = CASE WHEN @LastSeenUtc > T.LastSeenUtc THEN @LastSeenUtc ELSE T.LastSeenUtc END,
          ForegroundSeconds = T.ForegroundSeconds + @ForegroundSeconds,
          RunningSeconds    = T.RunningSeconds    + @RunningSeconds,
          LaunchCount       = T.LaunchCount       + @LaunchCount
      WHEN NOT MATCHED THEN INSERT
        (SessionId, MachineId, UserId, AppName, AppPath, WindowTitleSample,
         FirstSeenUtc, LastSeenUtc, ForegroundSeconds, RunningSeconds, LaunchCount)
        VALUES
        (@SessionId, @MachineId, @UserId, @AppName, @AppPath, @WindowTitleSample,
         @FirstSeenUtc, @LastSeenUtc, @ForegroundSeconds, @RunningSeconds, @LaunchCount);
    `);
}

async function getSessionIdByClientGuid(tx, clientSessionId) {
  const r = await new sql.Request(tx)
    .input('ClientSessionId', sql.NVarChar(64), clientSessionId)
    .query('SELECT SessionId FROM dbo.Sessions WHERE ClientSessionId = @ClientSessionId');
  return r.recordset[0] ? r.recordset[0].SessionId : null;
}

async function recordBatch({ machineId, machineName, clientBatchId, eventCount, sessionCount, appUsageCount, status, errorMessage }) {
  const pool = await getPool();
  await pool
    .request()
    .input('MachineId', sql.Int, machineId)
    .input('MachineName', sql.NVarChar(128), machineName)
    .input('ClientBatchId', sql.NVarChar(64), clientBatchId)
    .input('EventCount', sql.Int, eventCount)
    .input('SessionCount', sql.Int, sessionCount)
    .input('AppUsageCount', sql.Int, appUsageCount)
    .input('Status', sql.NVarChar(16), status || 'OK')
    .input('ErrorMessage', sql.NVarChar(2000), errorMessage || null)
    .query(`
      IF NOT EXISTS (SELECT 1 FROM dbo.IngestBatches WHERE MachineName = @MachineName AND ClientBatchId = @ClientBatchId)
      INSERT INTO dbo.IngestBatches (MachineId, MachineName, ClientBatchId, EventCount, SessionCount, AppUsageCount, Status, ErrorMessage)
      VALUES (@MachineId, @MachineName, @ClientBatchId, @EventCount, @SessionCount, @AppUsageCount, @Status, @ErrorMessage);
    `);
}

async function batchAlreadyProcessed(machineName, clientBatchId) {
  if (!clientBatchId) return false;
  const pool = await getPool();
  const r = await pool
    .request()
    .input('MachineName', sql.NVarChar(128), machineName)
    .input('ClientBatchId', sql.NVarChar(64), clientBatchId)
    .query('SELECT 1 AS Found FROM dbo.IngestBatches WHERE MachineName = @MachineName AND ClientBatchId = @ClientBatchId');
  return r.recordset.length > 0;
}

module.exports = {
  sql,
  getPool,
  upsertMachine,
  upsertUser,
  insertEvent,
  upsertSession,
  upsertAppUsage,
  getSessionIdByClientGuid,
  recordBatch,
  batchAlreadyProcessed
};
