-- ========================================
-- DEBUG AND FIX INCOMPLETE ERROR MESSAGES
-- ========================================

-- 1. First, let's check what's actually in the error log
SELECT TOP 10
    LogId,
    Date,
    Process,
    CaseId,
    LEN(ErrorMsg) as MsgLength,
    ErrorMsg,
    CASE 
        WHEN ErrorMsg LIKE '%Error:%' THEN 'Has Error Detail'
        WHEN ErrorMsg LIKE '%due to error in%' THEN 'Old Format - Missing Detail'
        WHEN ErrorMsg LIKE '%Failed Processing%' AND ErrorMsg NOT LIKE '%Error:%' THEN 'Missing Error Detail'
        ELSE 'Other Format'
    END as MessageFormat
FROM tblErrorLog
WHERE Process = 'spGenerateMFData'
    AND CaseId = 30070
ORDER BY Date DESC

-- 2. Test ERROR_MESSAGE() function directly
-- Run this to make sure ERROR_MESSAGE() works in your environment
BEGIN TRY
    RAISERROR('Test error message', 16, 1)
END TRY
BEGIN CATCH
    SELECT 
        ERROR_MESSAGE() as ErrorMessage,
        ERROR_LINE() as ErrorLine,
        ERROR_PROCEDURE() as ErrorProcedure,
        ERROR_SEVERITY() as ErrorSeverity
END CATCH

-- 3. DEBUG VERSION: Modify spGenerateMFData with extensive debugging
ALTER PROCEDURE [dbo].[spGenerateMFData]
    @ClaimNumber                   VARCHAR(9)            = NULL
   ,@Filename                      VARCHAR(100)
   ,@bTest                         TINYINT               = 0
   ,@bUpdate                       TINYINT               = 0
   ,@bSendMail                     BIT                   = 0
   ,@bDebug                        TINYINT               = 0
   ,@CurrentCaseId                 INT                   = NULL OUTPUT
AS
BEGIN
    -- ... existing declarations ...
    
    -- ... existing code up to the main loop ...
    
    WHILE @@FETCH_STATUS = 0 
    BEGIN
        BEGIN TRY 
            -- Set the current case being processed
            SET @CurrentCaseId = @nCaseId
            
            -- TEST: Force an error for debugging
            IF @nCaseId = 30070
            BEGIN
                -- Print debug info before error
                IF @bDebug = 1
                BEGIN
                    PRINT '=== BEFORE ERROR ==='
                    PRINT 'CaseId: ' + CAST(@nCaseId AS VARCHAR(20))
                    PRINT 'Claim: ' + @ClaimNumber
                    PRINT 'About to raise error...'
                END
                
                -- Raise a clear test error
                RAISERROR('TEST ERROR: This is a test error for CaseId %d with claim %s', 16, 1, @nCaseId, @ClaimNumber)
            END
            
            -- ... rest of TRY block ...
            
        END TRY
        BEGIN CATCH
            -- ENHANCED DEBUG CATCH BLOCK
            DECLARE @DebugErrorMsg NVARCHAR(4000)
            DECLARE @DebugErrorLine INT
            DECLARE @DebugErrorProc NVARCHAR(128)
            
            -- Capture error details immediately
            SET @DebugErrorMsg = ERROR_MESSAGE()
            SET @DebugErrorLine = ERROR_LINE()
            SET @DebugErrorProc = ERROR_PROCEDURE()
            
            -- Print debug info
            IF @bDebug = 1
            BEGIN
                PRINT '=== IN CATCH BLOCK ==='
                PRINT 'ERROR_MESSAGE(): ' + ISNULL(@DebugErrorMsg, 'NULL')
                PRINT 'ERROR_LINE(): ' + ISNULL(CAST(@DebugErrorLine AS VARCHAR(20)), 'NULL')
                PRINT 'ERROR_PROCEDURE(): ' + ISNULL(@DebugErrorProc, 'NULL')
                PRINT '@sMsg value: ' + ISNULL(@sMsg, 'NULL')
                PRINT '@nCaseId: ' + CAST(@nCaseId AS VARCHAR(20))
                PRINT '@ClaimNumber: ' + ISNULL(@ClaimNumber, 'NULL')
            END
            
            -- Build error message step by step
            SET @sReason = 'Failed Processing (CaseId: ' + CAST(@nCaseId AS VARCHAR(10)) + ', Claim: ' + ISNULL(@ClaimNumber, 'Unknown') + ')'
            
            -- Add error message
            IF @DebugErrorMsg IS NOT NULL AND LEN(@DebugErrorMsg) > 0
            BEGIN
                SET @sReason = @sReason + ' - Error: ' + @DebugErrorMsg
            END
            ELSE
            BEGIN
                SET @sReason = @sReason + ' - Error: Unknown error (ERROR_MESSAGE was empty)'
            END
            
            -- Add context
            IF @sMsg IS NOT NULL AND LEN(@sMsg) > 0
                SET @sReason = @sReason + ' [Context: ' + @sMsg + ']'
                
            -- Add line number
            IF @DebugErrorLine IS NOT NULL
                SET @sReason = @sReason + ' [Line: ' + CAST(@DebugErrorLine AS VARCHAR(10)) + ']'
            
            -- Debug print the final message
            IF @bDebug = 1
            BEGIN
                PRINT 'Final @sReason: ' + @sReason
                PRINT '=== END CATCH BLOCK ==='
            END
            
            -- Log the error
            INSERT INTO tblErrorLog (CaseId, Process, ErrorMsg) 
            VALUES (@nCaseId, 'spGenerateMFData', @sReason)
            
            -- Update counters
            SET @nMissingData = @nMissingData + 1
            SET @sErrorMsg = @sErrorMsg + @sCR + @ClaimNumber + '  ' + @sReason
            
        END CATCH
        
        FETCH NEXT FROM @cs INTO @nCaseId, @ClaimNumber, @sCaseType, @sStatus
    END
    
    -- ... rest of procedure ...
END
GO

-- 4. Test with debug enabled
PRINT '=== Running test with debug enabled ==='
EXEC spProcessCases 
    @bTestMF = 1,
    @bStatusUpdate = 0,
    @bSendMail = 0,
    @bSendFile = 0,
    @bDebug = 1  -- This will show debug output

-- 5. Check the results
SELECT TOP 5
    LogId,
    Date,
    Process,
    CaseId,
    ErrorMsg
FROM tblErrorLog 
WHERE CaseId = 30070
    AND Date >= DATEADD(MINUTE, -5, GETDATE())
ORDER BY Date DESC

-- 6. ALTERNATIVE: Simple error logging procedure for testing
CREATE OR ALTER PROCEDURE spTestErrorLogging
    @TestCaseId INT = 30070
AS
BEGIN
    BEGIN TRY
        -- Force an error
        RAISERROR('Test error for CaseId %d', 16, 1, @TestCaseId)
    END TRY
    BEGIN CATCH
        DECLARE @ErrorMsg VARCHAR(2000)
        SET @ErrorMsg = 'Failed Processing (CaseId: ' + CAST(@TestCaseId AS VARCHAR(10)) + ') - Error: ' + ERROR_MESSAGE()
        
        PRINT 'Error message to be logged: ' + @ErrorMsg
        
        INSERT INTO tblErrorLog (CaseId, Process, ErrorMsg)
        VALUES (@TestCaseId, 'spTestErrorLogging', @ErrorMsg)
    END CATCH
END
GO

-- Test it
EXEC spTestErrorLogging 30070

-- Check result
SELECT TOP 1 * FROM tblErrorLog 
WHERE Process = 'spTestErrorLogging' 
ORDER BY Date DESC