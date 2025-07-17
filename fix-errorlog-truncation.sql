-- ========================================
-- DIAGNOSE AND FIX ERRORLOG TRUNCATION
-- ========================================

-- 1. Check the current size of ErrorMsg column
SELECT 
    c.name AS ColumnName,
    t.name AS DataType,
    c.max_length AS MaxLength,
    CASE 
        WHEN t.name IN ('varchar', 'char') THEN c.max_length
        WHEN t.name IN ('nvarchar', 'nchar') THEN c.max_length / 2
        ELSE c.max_length
    END AS CharacterLimit
FROM sys.columns c
    JOIN sys.types t ON c.user_type_id = t.user_type_id
WHERE c.object_id = OBJECT_ID('tblErrorLog')
    AND c.name = 'ErrorMsg'

-- 2. Check the length of the error message that's trying to be inserted
DECLARE @TestErrorMsg VARCHAR(2000)
SET @TestErrorMsg = 'ParseMFData command failed with exit code 1. Command executed: "E:\FACESData\ParseMFData" "E:\FACESData\" "E:\FACESData\MFData\Reissue\2025\07\mfp_R0717" 1. Check if ParseMFData.exe exists in directory: E:\FACESData\, verify it has execute permissions, and ensure all required DLL files are present. Also verify the data directory path is accessible and the input file format is correct.'

SELECT LEN(@TestErrorMsg) AS ErrorMessageLength

-- 3. If ErrorMsg column is too small, increase it
-- First, check if we can alter it
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('tblErrorLog') AND name = 'ErrorMsg' AND max_length < 2000)
BEGIN
    PRINT 'ErrorMsg column needs to be increased'
    
    -- Option A: Alter the column (if no constraints prevent it)
    /*
    ALTER TABLE tblErrorLog 
    ALTER COLUMN ErrorMsg VARCHAR(2000)
    */
    
    -- Option B: If you can't alter, you need to truncate the message before inserting
END

-- 4. Quick fix for spProcessReissueCases - truncate error message before logging
-- This is a temporary fix until the column can be increased
ALTER PROCEDURE [dbo].[spProcessReissueCases]
    @bStatusUpdate          BIT = 1
   ,@bSendMail              BIT = 1
   ,@bSendFile              BIT = 1
   ,@bDebug                 BIT = 0
   ,@sDebugEmail            VARCHAR(150) = NULL
AS 
BEGIN
   -- ... existing code ...
   
   BEGIN CATCH
      -- Capture error details
      SET @ErrorMessage = ERROR_MESSAGE()
      SET @ErrorSeverity = ERROR_SEVERITY()
      SET @ErrorState = ERROR_STATE()
      SET @ErrorLine = ERROR_LINE()
      SET @ErrorProcedure = ERROR_PROCEDURE()
      
      -- Build comprehensive error message
      SET @sErrorText = 'Error in ' + ISNULL(@ErrorProcedure, 'spProcessReissueCases') + 
                       ' at line ' + CAST(@ErrorLine AS VARCHAR(10)) + ': ' + @ErrorMessage
      
      -- Add context if available
      IF @CurrentCaseId IS NOT NULL
         SET @sErrorText = @sErrorText + ' (CaseId: ' + CAST(@CurrentCaseId AS VARCHAR(20)) + ')'
      
      -- TRUNCATE ERROR MESSAGE TO FIT IN ERRORLOG TABLE
      DECLARE @MaxErrorLength INT
      SELECT @MaxErrorLength = 
          CASE 
              WHEN t.name IN ('varchar', 'char') THEN c.max_length
              WHEN t.name IN ('nvarchar', 'nchar') THEN c.max_length / 2
              ELSE 500 -- Default safe length
          END
      FROM sys.columns c
          JOIN sys.types t ON c.user_type_id = t.user_type_id
      WHERE c.object_id = OBJECT_ID('tblErrorLog')
          AND c.name = 'ErrorMsg'
      
      -- Log the error (truncated if necessary)
      INSERT INTO tblErrorLog (CaseId, Process, ErrorMsg) 
      VALUES (@CurrentCaseId, 'spProcessReissueCases', LEFT(@sErrorText, @MaxErrorLength))
      
      -- Print full error for debugging
      PRINT 'spProcessReissueCases --> ' + @sErrorText 
      
      -- Rest of error handling...
   END CATCH
END
GO

-- 5. Alternative approach - create a new error logging procedure
CREATE OR ALTER PROCEDURE spLogError
    @CaseId INT = NULL,
    @Process VARCHAR(100),
    @ErrorMsg VARCHAR(MAX),
    @Severity INT = 16
AS
BEGIN
    SET NOCOUNT ON
    
    -- Get the max length of ErrorMsg column
    DECLARE @MaxLength INT
    SELECT @MaxLength = 
        CASE 
            WHEN t.name IN ('varchar', 'char') THEN c.max_length
            WHEN t.name IN ('nvarchar', 'nchar') THEN c.max_length / 2
            ELSE 500
        END
    FROM sys.columns c
        JOIN sys.types t ON c.user_type_id = t.user_type_id
    WHERE c.object_id = OBJECT_ID('tblErrorLog')
        AND c.name = 'ErrorMsg'
    
    -- If message is too long, truncate it intelligently
    IF LEN(@ErrorMsg) > @MaxLength
    BEGIN
        -- Keep the beginning and end of the message
        DECLARE @TruncatedMsg VARCHAR(2000)
        DECLARE @KeepStart INT = @MaxLength * 0.7  -- Keep 70% from start
        DECLARE @KeepEnd INT = @MaxLength * 0.25   -- Keep 25% from end
        
        SET @TruncatedMsg = LEFT(@ErrorMsg, @KeepStart) + '...[TRUNCATED]...' + RIGHT(@ErrorMsg, @KeepEnd)
        SET @ErrorMsg = LEFT(@TruncatedMsg, @MaxLength)
    END
    
    -- Insert the error
    INSERT INTO tblErrorLog (CaseId, Process, ErrorMsg)
    VALUES (@CaseId, @Process, @ErrorMsg)
    
    -- Return the LogId
    RETURN SCOPE_IDENTITY()
END
GO

-- 6. Check what actually happened with ParseMFData
-- The error suggests ParseMFData.exe failed
EXEC xp_cmdshell 'dir E:\FACESData\ParseMFData*.*'

-- Check if the file was created
EXEC xp_cmdshell 'dir E:\FACESData\MFData\Reissue\2025\07\mfp_R0717*.*'

-- 7. Test the process again with better error handling
-- First, let's see the actual error without truncation
BEGIN TRY
    EXEC spProcessReissueCases 
        @bStatusUpdate = 0,
        @bSendMail = 0,
        @bSendFile = 0,
        @bDebug = 1  -- Enable debug for more info
END TRY
BEGIN CATCH
    PRINT 'Full Error Message:'
    PRINT ERROR_MESSAGE()
    PRINT 'Error Length: ' + CAST(LEN(ERROR_MESSAGE()) AS VARCHAR(10))
END CATCH