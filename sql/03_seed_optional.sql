/* =========================================================================
   Optional seed data for local testing.
   Safe to run multiple times.
   ========================================================================= */
USE UserActivityDB;
GO

IF NOT EXISTS (SELECT 1 FROM dbo.Machines WHERE MachineName = N'DEMO-PC-01')
    INSERT INTO dbo.Machines (MachineName, Domain, OSVersion, IPAddress, AgentVersion)
    VALUES (N'DEMO-PC-01', N'CORP', N'Windows 11 Pro 23H2', N'10.0.0.10', N'1.0.0');

IF NOT EXISTS (SELECT 1 FROM dbo.Users WHERE UserName = N'demo.user' AND Domain = N'CORP')
    INSERT INTO dbo.Users (UserName, Domain, DisplayName)
    VALUES (N'demo.user', N'CORP', N'Demo User');
GO
