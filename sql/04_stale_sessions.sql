/* =========================================================================
   Stale-session handling
   - Updates vw_ActiveSessions to only show sessions whose machine has
     reported in within the last 10 minutes (so the dashboard never lies).
   - Adds usp_CloseStaleSessions which closes any session whose machine has
     not reported in 15 minutes. Backend calls this periodically.
   Safe to run repeatedly.
   ========================================================================= */
USE UserActivityDB;
GO

/* --- Updated active-sessions view --- */
IF OBJECT_ID(N'dbo.vw_ActiveSessions', N'V') IS NOT NULL
    DROP VIEW dbo.vw_ActiveSessions;
GO
CREATE VIEW dbo.vw_ActiveSessions AS
SELECT
    s.SessionId,
    m.MachineName,
    u.UserName,
    u.Domain,
    s.LogonTimeUtc,
    s.IdleSeconds,
    s.ActiveSeconds,
    s.LockCount,
    s.IsLocked,
    DATEDIFF(SECOND, s.LogonTimeUtc,
             CASE WHEN s.UpdatedUtc < SYSUTCDATETIME() THEN s.UpdatedUtc ELSE SYSUTCDATETIME() END
    ) AS LiveDurationSeconds,
    m.LastSeenUtc AS MachineLastSeenUtc,
    s.UpdatedUtc  AS SessionLastUpdatedUtc
FROM dbo.Sessions s
JOIN dbo.Machines m ON m.MachineId = s.MachineId
JOIN dbo.Users    u ON u.UserId    = s.UserId
WHERE s.LogoffTimeUtc IS NULL
  AND m.LastSeenUtc > DATEADD(MINUTE, -10, SYSUTCDATETIME());
GO

/* --- Cleanup procedure: close sessions whose machine is silent --- */
IF OBJECT_ID(N'dbo.usp_CloseStaleSessions', N'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_CloseStaleSessions;
GO
CREATE PROCEDURE dbo.usp_CloseStaleSessions
    @StaleMinutes INT = 15
AS
BEGIN
    SET NOCOUNT ON;

    /* (1) Close ORPHAN sessions — sessions that are open but a NEWER open
       session exists for the same (machine, user). Each agent restart creates
       a new clientSessionId; only the newest one is the "real" current session.
       The older ones are orphans from previous agent runs. */
    WITH ranked AS (
        SELECT s.SessionId,
               s.LogonTimeUtc,
               ROW_NUMBER() OVER (
                   PARTITION BY s.MachineId, s.UserId
                   ORDER BY s.LogonTimeUtc DESC
               ) AS rn
          FROM dbo.Sessions s
         WHERE s.LogoffTimeUtc IS NULL
    )
    UPDATE s
       SET s.LogoffTimeUtc   = s.UpdatedUtc,
           s.DurationSeconds = DATEDIFF(SECOND, s.LogonTimeUtc, s.UpdatedUtc),
           s.EndReason       = N'AgentRestart',
           s.UpdatedUtc      = SYSUTCDATETIME()
      FROM dbo.Sessions s
      JOIN ranked r ON r.SessionId = s.SessionId
     WHERE r.rn > 1;

    /* (2) Close sessions whose whole machine has gone cold (agent stopped). */
    UPDATE s
       SET s.LogoffTimeUtc   = m.LastSeenUtc,
           s.DurationSeconds = DATEDIFF(SECOND, s.LogonTimeUtc, m.LastSeenUtc),
           s.EndReason       = N'StaleTimeout',
           s.UpdatedUtc      = SYSUTCDATETIME()
      FROM dbo.Sessions s
      JOIN dbo.Machines m ON m.MachineId = s.MachineId
     WHERE s.LogoffTimeUtc IS NULL
       AND m.LastSeenUtc < DATEADD(MINUTE, -@StaleMinutes, SYSUTCDATETIME());

    -- Also emit a synthetic 'StaleEnd' event for the audit trail
    INSERT INTO dbo.SessionEvents (MachineId, UserId, EventType, EventTimeUtc, Details)
    SELECT s.MachineId, s.UserId, N'StaleEnd', m.LastSeenUtc,
           N'Session auto-closed: agent stopped reporting'
      FROM dbo.Sessions s
      JOIN dbo.Machines m ON m.MachineId = s.MachineId
     WHERE s.EndReason = N'StaleTimeout'
       AND s.UpdatedUtc > DATEADD(SECOND, -2, SYSUTCDATETIME())
       AND NOT EXISTS (
           SELECT 1 FROM dbo.SessionEvents e
            WHERE e.MachineId = s.MachineId
              AND e.UserId    = s.UserId
              AND e.EventType = N'StaleEnd'
              AND e.EventTimeUtc = m.LastSeenUtc
       );

    SELECT @@ROWCOUNT AS Closed;
END
GO

PRINT 'Stale-session view and cleanup procedure are in place.';
GO
