-- ========================================
-- FIX ERROR MESSAGE DETAIL IN spGenerateMFData
-- ========================================

-- The issue is in the CATCH block of spGenerateMFData
-- Here's what's happening and how to fix it:

-- CURRENT CODE (problematic):
/*
BEGIN CATCH      
    IF LEN(@sMsg) > 0
        SET @sReason = 'Failed Processing (CaseId: ' + CAST(@nCaseId AS VARCHAR(10)) + ') due to error in ' + @sMsg + '(' + ERROR_MESSAGE() + ').'
    ELSE
        SET @sReason = 'Failed Processing (CaseId: ' + CAST(@nCaseId AS VARCHAR(10)) + ') due to error in ' + ERROR_MESSAGE() + '.'
END CATCH
*/

-- The problem: @sMsg might be getting reset or might not contain what you expect

-- SOLUTION: Modify the CATCH block in spGenerateMFData
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
    
    -- ... existing code ...
    
    -- In the main processing loop:
    BEGIN TRY 
        -- ... existing code ...
    END TRY
    BEGIN CATCH      
        -- Enhanced error handling with better detail
        DECLARE @ErrorMessage NVARCHAR(4000)
        DECLARE @ErrorSeverity INT
        DECLARE @ErrorState INT
        DECLARE @ErrorProcedure NVARCHAR(200)
        DECLARE @ErrorLine INT
        
        -- Capture all error details
        SET @ErrorMessage = ERROR_MESSAGE()
        SET @ErrorSeverity = ERROR_SEVERITY()
        SET @ErrorState = ERROR_STATE()
        SET @ErrorProcedure = ERROR_PROCEDURE()
        SET @ErrorLine = ERROR_LINE()
        
        -- Build comprehensive error message
        SET @sReason = 'Failed Processing CaseId: ' + CAST(@nCaseId AS VARCHAR(10)) + 
                      ', Claim: ' + @ClaimNumber +
                      ', Error: ' + @ErrorMessage
        
        -- Add location info if available
        IF LEN(ISNULL(@sMsg, '')) > 0
            SET @sReason = @sReason + ' (Last operation: ' + @sMsg + ')'
            
        -- Add line number for debugging
        IF @ErrorLine IS NOT NULL
            SET @sReason = @sReason + ' at line ' + CAST(@ErrorLine AS VARCHAR(10))
            
        -- Log the full error
        INSERT INTO tblErrorLog (CaseId, Process, ErrorMsg) 
        VALUES (@nCaseId, 'spGenerateMFData', @sReason)
        
        -- Also print for debugging
        IF @bDebug = 1
        BEGIN
            PRINT '=== ERROR DETAILS ==='
            PRINT 'CaseId: ' + CAST(@nCaseId AS VARCHAR(10))
            PRINT 'Claim: ' + @ClaimNumber
            PRINT 'Error Message: ' + @ErrorMessage
            PRINT 'Error at Line: ' + CAST(@ErrorLine AS VARCHAR(10))
            PRINT 'Last Operation: ' + ISNULL(@sMsg, 'Unknown')
            PRINT '=================='
        END
        
        -- Update error count
        SET @nMissingData = @nMissingData + 1
        SET @sErrorMsg = @sErrorMsg + @sCR + @ClaimNumber + '  ' + @sReason
        
    END CATCH
    
    -- ... rest of procedure ...
END
GO

-- ========================================
-- DIAGNOSTIC: Check what's in @sMsg
-- ========================================

-- Add debug output to track @sMsg value
-- In spGenerateMFData, add these debug prints:

/*
-- Before calling spGetCSAData:
IF @bDebug = 1
    PRINT 'About to call spGetCSAData for CaseId: ' + CAST(@nCaseId AS VARCHAR(10))

EXEC @rc = spGetCSAData @nCaseId, @rec1 output, @bDebug
SET @sMsg = 'spGetCSAData'  -- This sets @sMsg

IF @bDebug = 1
    PRINT '@sMsg is now: ' + @sMsg

-- If there's an error after this, @sMsg should contain 'spGetCSAData'
*/

-- ========================================
-- TEST: Force a detailed error
-- ========================================

-- Add this to spGenerateMFData to test the enhanced error handling:
/*
-- After SET @CurrentCaseId = @nCaseId:
IF @nCaseId = 30070
BEGIN
    SET @sMsg = 'Testing error location tracking'
    RAISERROR('TEST ERROR: This is a detailed error message for CaseId %d', 16, 1, @nCaseId)
END
*/

-- ========================================
-- VIEW RECENT ERRORS
-- ========================================

-- Check recent errors to see the detail level
SELECT TOP 10
    LogId,
    Date,
    Process,
    CaseId,
    ErrorMsg,
    CASE 
        WHEN ErrorMsg LIKE '%due to error in' AND ErrorMsg NOT LIKE '%due to error in %(%' THEN 'Missing Error Detail'
        WHEN ErrorMsg LIKE '%Last operation:%' THEN 'Has Operation Detail'
        WHEN ErrorMsg LIKE '%at line%' THEN 'Has Line Number'
        ELSE 'Check Format'
    END as ErrorQuality
FROM tblErrorLog
WHERE Process = 'spGenerateMFData'
    AND Date >= DATEADD(HOUR, -24, GETDATE())
ORDER BY Date DESC

-- ========================================
-- ALTERNATIVE: Add error context tracking
-- ========================================

-- Create a context variable at the beginning of spGenerateMFData:
/*
DECLARE @ErrorContext VARCHAR(500) = ''

-- Update it throughout the procedure:
SET @ErrorContext = 'Checking case readiness'
-- ... validation code ...

SET @ErrorContext = 'Calling spGetCSAData'
EXEC @rc = spGetCSAData @nCaseId, @rec1 output, @bDebug

SET @ErrorContext = 'Calling spGetFERSData'
EXEC @rc = spGetFERSData @nCaseId, @rec2 output, @bDebug

-- In the CATCH block:
SET @sReason = 'Failed Processing CaseId: ' + CAST(@nCaseId AS VARCHAR(10)) + 
              ' during: ' + @ErrorContext +
              ', Error: ' + ERROR_MESSAGE()
*/