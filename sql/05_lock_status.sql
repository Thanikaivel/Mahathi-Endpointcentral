/* =========================================================================
   Adds IsLocked column to Sessions so the dashboard can show
   "Working" vs "Locked" status for each active session.
   Also adds IsLocked to vw_ActiveSessions.
   Safe to run repeatedly.
   ========================================================================= */
USE UserActivityDB;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID(N'dbo.Sessions')
      AND name = N'IsLocked'
)
BEGIN
    ALTER TABLE dbo.Sessions
        ADD IsLocked BIT NOT NULL CONSTRAINT DF_Sessions_IsLocked DEFAULT 0;
    PRINT 'Added IsLocked column to Sessions.';
END
ELSE
BEGIN
    PRINT 'IsLocked column already present.';
END
GO

/* Recreate vw_ActiveSessions to expose IsLocked */
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

PRINT 'vw_ActiveSessions now exposes IsLocked.';
GO
