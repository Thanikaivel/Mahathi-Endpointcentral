/* =========================================================================
   User Activity Monitoring - Schema
   Target: UserActivityDB on MSSQL Server
   Run AFTER 01_create_database.sql
   ========================================================================= */

USE UserActivityDB;
GO

/* -----------------------------------------------------------------
   Machines: one row per Windows client machine reporting in.
   ----------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.Machines', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Machines (
        MachineId       INT IDENTITY(1,1) PRIMARY KEY,
        MachineName     NVARCHAR(128)  NOT NULL UNIQUE,
        Domain          NVARCHAR(128)  NULL,
        OSVersion       NVARCHAR(128)  NULL,
        IPAddress       NVARCHAR(64)   NULL,
        AgentVersion    NVARCHAR(32)   NULL,
        FirstSeenUtc    DATETIME2(0)   NOT NULL CONSTRAINT DF_Machines_FirstSeen DEFAULT SYSUTCDATETIME(),
        LastSeenUtc     DATETIME2(0)   NOT NULL CONSTRAINT DF_Machines_LastSeen  DEFAULT SYSUTCDATETIME()
    );
    CREATE INDEX IX_Machines_LastSeen ON dbo.Machines(LastSeenUtc DESC);
END
GO

/* -----------------------------------------------------------------
   Users: one row per Windows user observed on any machine.
   ----------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.Users', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Users (
        UserId          INT IDENTITY(1,1) PRIMARY KEY,
        UserName        NVARCHAR(256)  NOT NULL,
        Domain          NVARCHAR(128)  NULL,
        DisplayName     NVARCHAR(256)  NULL,
        FirstSeenUtc    DATETIME2(0)   NOT NULL CONSTRAINT DF_Users_FirstSeen DEFAULT SYSUTCDATETIME(),
        LastSeenUtc     DATETIME2(0)   NOT NULL CONSTRAINT DF_Users_LastSeen  DEFAULT SYSUTCDATETIME(),
        CONSTRAINT UQ_Users_DomainUser UNIQUE (Domain, UserName)
    );
END
GO

/* -----------------------------------------------------------------
   SessionEvents: raw event stream from clients.
   EventType: Logon, Logoff, Lock, Unlock, Shutdown, Startup,
              SessionStart, SessionEnd, IdleStart, IdleEnd
   ----------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.SessionEvents', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.SessionEvents (
        EventId         BIGINT IDENTITY(1,1) PRIMARY KEY,
        MachineId       INT            NOT NULL,
        UserId          INT            NULL,
        EventType       NVARCHAR(32)   NOT NULL,
        EventTimeUtc    DATETIME2(0)   NOT NULL,
        ClientEventId   NVARCHAR(64)   NULL,   -- de-duplication key from client
        Details         NVARCHAR(1024) NULL,
        ReceivedUtc     DATETIME2(0)   NOT NULL CONSTRAINT DF_SessionEvents_Received DEFAULT SYSUTCDATETIME(),
        CONSTRAINT FK_SessionEvents_Machine FOREIGN KEY (MachineId) REFERENCES dbo.Machines(MachineId),
        CONSTRAINT FK_SessionEvents_User    FOREIGN KEY (UserId)    REFERENCES dbo.Users(UserId)
    );
    CREATE INDEX IX_SessionEvents_Machine_Time ON dbo.SessionEvents(MachineId, EventTimeUtc DESC);
    CREATE INDEX IX_SessionEvents_User_Time    ON dbo.SessionEvents(UserId,    EventTimeUtc DESC);
    CREATE INDEX IX_SessionEvents_Type_Time    ON dbo.SessionEvents(EventType, EventTimeUtc DESC);
    CREATE UNIQUE INDEX UX_SessionEvents_ClientEventId
        ON dbo.SessionEvents(ClientEventId)
        WHERE ClientEventId IS NOT NULL;
END
GO

/* -----------------------------------------------------------------
   Sessions: aggregated per-logon session.
   Created/closed by backend based on Logon/Logoff/Shutdown events.
   ----------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.Sessions', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Sessions (
        SessionId           BIGINT IDENTITY(1,1) PRIMARY KEY,
        MachineId           INT            NOT NULL,
        UserId              INT            NOT NULL,
        ClientSessionId     NVARCHAR(64)   NOT NULL,   -- agent-generated GUID
        LogonTimeUtc        DATETIME2(0)   NOT NULL,
        LogoffTimeUtc       DATETIME2(0)   NULL,
        DurationSeconds     INT            NULL,
        IdleSeconds         INT            NOT NULL CONSTRAINT DF_Sessions_Idle DEFAULT 0,
        ActiveSeconds       INT            NOT NULL CONSTRAINT DF_Sessions_Active DEFAULT 0,
        LockCount           INT            NOT NULL CONSTRAINT DF_Sessions_Locks DEFAULT 0,
        EndReason           NVARCHAR(32)   NULL,       -- Logoff, Shutdown, Timeout
        UpdatedUtc          DATETIME2(0)   NOT NULL CONSTRAINT DF_Sessions_Updated DEFAULT SYSUTCDATETIME(),
        CONSTRAINT FK_Sessions_Machine FOREIGN KEY (MachineId) REFERENCES dbo.Machines(MachineId),
        CONSTRAINT FK_Sessions_User    FOREIGN KEY (UserId)    REFERENCES dbo.Users(UserId),
        CONSTRAINT UQ_Sessions_ClientSessionId UNIQUE (ClientSessionId)
    );
    CREATE INDEX IX_Sessions_Machine_Logon ON dbo.Sessions(MachineId, LogonTimeUtc DESC);
    CREATE INDEX IX_Sessions_User_Logon    ON dbo.Sessions(UserId,    LogonTimeUtc DESC);
END
GO

/* -----------------------------------------------------------------
   AppUsage: per (Session, App) aggregated foreground time.
   Clients send rolling deltas; backend upserts on (SessionId, AppName).
   ----------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.AppUsage', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.AppUsage (
        AppUsageId          BIGINT IDENTITY(1,1) PRIMARY KEY,
        SessionId           BIGINT         NOT NULL,
        MachineId           INT            NOT NULL,
        UserId              INT            NOT NULL,
        AppName             NVARCHAR(256)  NOT NULL,
        AppPath             NVARCHAR(1024) NULL,
        WindowTitleSample   NVARCHAR(512)  NULL,
        FirstSeenUtc        DATETIME2(0)   NOT NULL,
        LastSeenUtc         DATETIME2(0)   NOT NULL,
        ForegroundSeconds   INT            NOT NULL CONSTRAINT DF_AppUsage_Fg DEFAULT 0,
        RunningSeconds      INT            NOT NULL CONSTRAINT DF_AppUsage_Run DEFAULT 0,
        LaunchCount         INT            NOT NULL CONSTRAINT DF_AppUsage_Launches DEFAULT 0,
        CONSTRAINT FK_AppUsage_Session FOREIGN KEY (SessionId) REFERENCES dbo.Sessions(SessionId),
        CONSTRAINT FK_AppUsage_Machine FOREIGN KEY (MachineId) REFERENCES dbo.Machines(MachineId),
        CONSTRAINT FK_AppUsage_User    FOREIGN KEY (UserId)    REFERENCES dbo.Users(UserId),
        CONSTRAINT UQ_AppUsage_Session_App UNIQUE (SessionId, AppName)
    );
    CREATE INDEX IX_AppUsage_Machine_LastSeen ON dbo.AppUsage(MachineId, LastSeenUtc DESC);
    CREATE INDEX IX_AppUsage_App ON dbo.AppUsage(AppName);
END
GO

/* -----------------------------------------------------------------
   IngestBatches: audit trail of every batch the agent pushed.
   ----------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.IngestBatches', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.IngestBatches (
        BatchId         BIGINT IDENTITY(1,1) PRIMARY KEY,
        MachineId       INT            NULL,
        MachineName     NVARCHAR(128)  NOT NULL,
        ClientBatchId   NVARCHAR(64)   NOT NULL,
        EventCount      INT            NOT NULL,
        SessionCount    INT            NOT NULL,
        AppUsageCount   INT            NOT NULL,
        ReceivedUtc     DATETIME2(0)   NOT NULL CONSTRAINT DF_IngestBatches_Recv DEFAULT SYSUTCDATETIME(),
        Status          NVARCHAR(16)   NOT NULL CONSTRAINT DF_IngestBatches_Status DEFAULT N'OK',
        ErrorMessage    NVARCHAR(2000) NULL,
        CONSTRAINT UQ_IngestBatches_Client UNIQUE (MachineName, ClientBatchId)
    );
END
GO

/* -----------------------------------------------------------------
   Views for dashboard convenience
   ----------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.vw_ActiveSessions', N'V') IS NOT NULL DROP VIEW dbo.vw_ActiveSessions;
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
    DATEDIFF(SECOND, s.LogonTimeUtc, SYSUTCDATETIME()) AS LiveDurationSeconds
FROM dbo.Sessions s
JOIN dbo.Machines m ON m.MachineId = s.MachineId
JOIN dbo.Users    u ON u.UserId    = s.UserId
WHERE s.LogoffTimeUtc IS NULL;
GO

IF OBJECT_ID(N'dbo.vw_DailyMachineSummary', N'V') IS NOT NULL DROP VIEW dbo.vw_DailyMachineSummary;
GO
CREATE VIEW dbo.vw_DailyMachineSummary AS
SELECT
    CAST(s.LogonTimeUtc AS DATE)       AS [Day],
    m.MachineName,
    COUNT(*)                            AS Sessions,
    SUM(ISNULL(s.DurationSeconds, 0))   AS TotalSeconds,
    SUM(s.ActiveSeconds)                AS ActiveSeconds,
    SUM(s.IdleSeconds)                  AS IdleSeconds
FROM dbo.Sessions s
JOIN dbo.Machines m ON m.MachineId = s.MachineId
GROUP BY CAST(s.LogonTimeUtc AS DATE), m.MachineName;
GO

PRINT 'Schema created / verified successfully.';
GO
