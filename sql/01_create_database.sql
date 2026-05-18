/* =========================================================================
   User Activity Monitoring - Database Bootstrap
   Run this script once on the SQL Server (Localhost) as 'sa'.
   It creates the database UserActivityDB if it does not already exist.
   ========================================================================= */

IF DB_ID(N'UserActivityDB') IS NULL
BEGIN
    PRINT 'Creating database UserActivityDB...';
    CREATE DATABASE UserActivityDB;
END
ELSE
BEGIN
    PRINT 'Database UserActivityDB already exists. Skipping CREATE.';
END
GO
