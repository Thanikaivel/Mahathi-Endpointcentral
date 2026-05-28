/* =========================================================================
   Stable machine identification by hardware UUID.
   - Adds HardwareId column to dbo.Machines with a filtered unique index.
   - Adds usp_MergeMachines to consolidate duplicate machine rows
     (typically created when a hostname was changed before HardwareId tracking).
   Safe to run repeatedly.
   ========================================================================= */
USE UserActivityDB;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID(N'dbo.Machines')
      AND name = N'HardwareId'
)
BEGIN
    ALTER TABLE dbo.Machines ADD HardwareId NVARCHAR(64) NULL;
    PRINT 'Added HardwareId column to Machines';
END
ELSE
BEGIN
    PRINT 'HardwareId column already present';
END
GO

-- Unique only when HardwareId is set (so legacy rows without a UUID coexist)
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_Machines_HardwareId' AND object_id = OBJECT_ID('dbo.Machines'))
BEGIN
    CREATE UNIQUE INDEX UX_Machines_HardwareId
        ON dbo.Machines (HardwareId)
        WHERE HardwareId IS NOT NULL;
    PRINT 'Added unique filtered index UX_Machines_HardwareId';
END
GO

/* --- Merge utility: move all child rows from @OldId to @NewId, then delete @OldId. --- */
IF OBJECT_ID(N'dbo.usp_MergeMachines', N'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_MergeMachines;
GO
CREATE PROCEDURE dbo.usp_MergeMachines
    @OldMachineId INT,
    @NewMachineId INT
AS
BEGIN
    SET NOCOUNT ON;

    IF @OldMachineId = @NewMachineId
    BEGIN
        RAISERROR('Old and new machine IDs are the same; nothing to merge.', 16, 1);
        RETURN;
    END

    IF NOT EXISTS (SELECT 1 FROM dbo.Machines WHERE MachineId = @OldMachineId)
       OR NOT EXISTS (SELECT 1 FROM dbo.Machines WHERE MachineId = @NewMachineId)
    BEGIN
        RAISERROR('One or both machine IDs do not exist.', 16, 1);
        RETURN;
    END

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Re-point Sessions, SessionEvents, AppUsage, IngestBatches, BrowserHistory
        UPDATE dbo.Sessions       SET MachineId = @NewMachineId WHERE MachineId = @OldMachineId;
        UPDATE dbo.SessionEvents  SET MachineId = @NewMachineId WHERE MachineId = @OldMachineId;
        UPDATE dbo.AppUsage       SET MachineId = @NewMachineId WHERE MachineId = @OldMachineId;
        IF OBJECT_ID(N'dbo.IngestBatches', N'U') IS NOT NULL
            UPDATE dbo.IngestBatches SET MachineId = @NewMachineId WHERE MachineId = @OldMachineId;
        IF OBJECT_ID(N'dbo.BrowserHistory', N'U') IS NOT NULL
            UPDATE dbo.BrowserHistory SET MachineId = @NewMachineId WHERE MachineId = @OldMachineId;

        -- Carry over LastSeenUtc / AgentVersion if the old row is more recent
        UPDATE n
           SET n.LastSeenUtc  = CASE WHEN o.LastSeenUtc > n.LastSeenUtc THEN o.LastSeenUtc ELSE n.LastSeenUtc END,
               n.AgentVersion = COALESCE(n.AgentVersion, o.AgentVersion),
               n.OSVersion    = COALESCE(n.OSVersion,    o.OSVersion),
               n.IPAddress    = COALESCE(n.IPAddress,    o.IPAddress),
               n.HardwareId   = COALESCE(n.HardwareId,   o.HardwareId)
          FROM dbo.Machines n
          JOIN dbo.Machines o ON o.MachineId = @OldMachineId
         WHERE n.MachineId = @NewMachineId;

        -- Finally, delete the old machine row
        DELETE FROM dbo.Machines WHERE MachineId = @OldMachineId;

        COMMIT TRANSACTION;

        SELECT @OldMachineId AS MergedFromId, @NewMachineId AS MergedIntoId, 'OK' AS Status;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @msg NVARCHAR(2048) = ERROR_MESSAGE();
        RAISERROR('Merge failed: %s', 16, 1, @msg);
    END CATCH
END
GO

PRINT 'HardwareId column + merge procedure ready.';
GO
