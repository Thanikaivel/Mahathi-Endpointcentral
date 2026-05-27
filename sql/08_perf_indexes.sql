/* =========================================================================
   Performance indexes — speeds up the three slow dashboard endpoints:
     /dashboard/machines           (Machines + Sessions subqueries)
     /dashboard/users/daily        (Sessions + SessionEvents lookups)
     /dashboard/apps/list          (AppUsage range filtering)
   Safe to run repeatedly.
   ========================================================================= */
USE UserActivityDB;
GO

PRINT 'Adding performance indexes...';

/* ---- AppUsage: date-range filtering by LastSeenUtc + MachineId/UserId ---- */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_AppUsage_LastSeen' AND object_id = OBJECT_ID('dbo.AppUsage'))
    CREATE INDEX IX_AppUsage_LastSeen
        ON dbo.AppUsage (LastSeenUtc DESC)
        INCLUDE (MachineId, UserId, AppName, AppPath, ForegroundSeconds, RunningSeconds, LaunchCount, FirstSeenUtc);

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_AppUsage_Machine_LastSeen' AND object_id = OBJECT_ID('dbo.AppUsage'))
    CREATE INDEX IX_AppUsage_Machine_LastSeen
        ON dbo.AppUsage (MachineId, LastSeenUtc DESC);

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_AppUsage_User_LastSeen' AND object_id = OBJECT_ID('dbo.AppUsage'))
    CREATE INDEX IX_AppUsage_User_LastSeen
        ON dbo.AppUsage (UserId, LastSeenUtc DESC);

/* ---- Sessions: covering index for the daily query (machine, user, date) ---- */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Sessions_LogonDate' AND object_id = OBJECT_ID('dbo.Sessions'))
    CREATE INDEX IX_Sessions_LogonDate
        ON dbo.Sessions (LogonTimeUtc DESC)
        INCLUDE (MachineId, UserId, LogoffTimeUtc, DurationSeconds, ActiveSeconds, IdleSeconds, LockCount, IsLocked, EndReason);

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Sessions_Machine_Logon' AND object_id = OBJECT_ID('dbo.Sessions'))
    CREATE INDEX IX_Sessions_Machine_Logon
        ON dbo.Sessions (MachineId, LogonTimeUtc DESC)
        INCLUDE (UserId, LogoffTimeUtc);

/* ---- SessionEvents: lookup by machine + event type + time ---- */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_SessionEvents_Type_Time' AND object_id = OBJECT_ID('dbo.SessionEvents'))
    CREATE INDEX IX_SessionEvents_Type_Time
        ON dbo.SessionEvents (EventType, EventTimeUtc DESC)
        INCLUDE (MachineId, UserId, Details);

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_SessionEvents_Machine_User_Time' AND object_id = OBJECT_ID('dbo.SessionEvents'))
    CREATE INDEX IX_SessionEvents_Machine_User_Time
        ON dbo.SessionEvents (MachineId, UserId, EventTimeUtc DESC)
        INCLUDE (EventType);

/* ---- Machines: speed up LastSeenUtc filtering ---- */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Machines_LastSeen' AND object_id = OBJECT_ID('dbo.Machines'))
    CREATE INDEX IX_Machines_LastSeen
        ON dbo.Machines (LastSeenUtc DESC)
        INCLUDE (MachineName, Domain, OSVersion, IPAddress, AgentVersion);

PRINT 'Indexes done. Run UPDATE STATISTICS to refresh:';
PRINT '  UPDATE STATISTICS dbo.AppUsage      WITH FULLSCAN;';
PRINT '  UPDATE STATISTICS dbo.Sessions      WITH FULLSCAN;';
PRINT '  UPDATE STATISTICS dbo.SessionEvents WITH FULLSCAN;';
PRINT '  UPDATE STATISTICS dbo.Machines      WITH FULLSCAN;';
GO
