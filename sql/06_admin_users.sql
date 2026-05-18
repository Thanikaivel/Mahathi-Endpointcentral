/* =========================================================================
   AdminUsers table for dashboard authentication.
   Stores bcrypt password hashes.
   Safe to run repeatedly.
   ========================================================================= */
USE UserActivityDB;
GO

IF OBJECT_ID(N'dbo.AdminUsers', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.AdminUsers (
        AdminUserId   INT IDENTITY(1,1) PRIMARY KEY,
        Username      NVARCHAR(64)  NOT NULL UNIQUE,
        PasswordHash  NVARCHAR(256) NOT NULL,
        DisplayName   NVARCHAR(128) NULL,
        IsEnabled     BIT           NOT NULL DEFAULT 1,
        CreatedUtc    DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
        LastLoginUtc  DATETIME2     NULL
    );
    PRINT 'Created dbo.AdminUsers';
END
ELSE
BEGIN
    PRINT 'dbo.AdminUsers already exists';
END
GO

/* Create an initial 'admin' row with a placeholder hash that won't match
   any password. You MUST set the real password before logging in:
   run from backend folder:   node scripts/set-admin-password.js admin <new-password> */
IF NOT EXISTS (SELECT 1 FROM dbo.AdminUsers WHERE Username = N'admin')
BEGIN
    INSERT INTO dbo.AdminUsers (Username, PasswordHash, DisplayName)
    VALUES (N'admin',
            N'$2a$10$placeholder.must.set.via.script.before.login.placeholder.',
            N'Default Admin');
    PRINT 'Created admin row. Set its password with: node scripts/set-admin-password.js admin <password>';
END
GO
