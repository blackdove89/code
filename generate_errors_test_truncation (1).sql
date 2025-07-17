-- ================================================================
-- GENERATE ERRORS TO TEST MESSAGE TRUNCATION FIXES
-- ================================================================

-- These tests will generate long error messages that would be truncated
-- in the original version but should be complete in the fixed version

-- ================================================================
-- TEST 1: LONG FILE PATH ERROR (spProcessCases)
-- ================================================================

-- Force a file path error with a very long directory name
-- This will generate a long error message that tests truncation

-- Step 1: Set up a very long directory path
UPDATE tblConfiguration 
SET KeyValue = 'C:\VeryLongDirectoryNameThatWillCauseTheErrorMessageToBecomeExtremelyLongAndPotentiallyTruncated\AnotherLongSubdirectory\AndAnotherOne\MFData\'
WHERE KeyName = 'MFDataDirectory'

-- Step 2: Run spProcessCases - this will fail when trying to create the long path
EXEC spProcessCases @bTestMF = 1, @bDebug = 1, @bSendMail = 0, @bSendFile = 0

-- Step 3: Check the error message length
SELECT 
    'Long File Path Error Test' AS TestType,
    Date,
    CaseId,
    Process,
    LEN(ErrorMsg) AS Message_Length,
    LEFT(ErrorMsg, 100) + '...' AS Message_Preview,
    CASE 
        WHEN LEN(ErrorMsg) > 200 THEN '✅ Long message preserved'
        WHEN LEN(ErrorMsg) < 100 THEN '❌ Message truncated'
        ELSE '❓ Medium length message'
    END AS Truncation_Test_Result
FROM tblErrorLog 
WHERE Process = 'spProcessCases'
    AND Date >= DATEADD(minute, -5, GETDATE())
ORDER BY Date DESC

-- Step 4: Restore proper directory
UPDATE tblConfiguration 
SET KeyValue = 'E:\FACESData\'
WHERE KeyName = 'MFDataDirectory'

-- ================================================================
-- TEST 2: FTP FAILURE WITH LONG DATASET NAME (spProcessCases)
-- ================================================================

-- Create a very long dataset name that will generate a long error message

-- Step 1: Set up long FTP dataset name
DECLARE @LongDatasetName VARCHAR(200)
SET @LongDatasetName = 'EXTREMELY.LONG.DATASET.NAME.THAT.WILL.CAUSE.A.VERY.LONG.ERROR.MESSAGE.WHEN.FTP.FAILS.AND.WILL.TEST.MESSAGE.TRUNCATION.ISSUES.MAINFRAME.DATASET'

UPDATE tblConfiguration 
SET KeyValue = @LongDatasetName
WHERE KeyName = 'MFDailyCycleDataFile'

-- Step 2: Ensure we have valid data directory but invalid FTP dataset
UPDATE tblConfiguration 
SET KeyValue = 'E:\FACESData\'
WHERE KeyName = 'MFDataDirectory'

-- Step 3: Run spProcessCases with production mode to trigger FTP
EXEC spProcessCases @bTestMF = 0, @bDebug = 1, @bSendMail = 0, @bSendFile = 1

-- Step 4: Check error message
SELECT 
    'Long FTP Dataset Error Test' AS TestType,
    Date,
    CaseId,
    Process,
    LEN(ErrorMsg) AS Message_Length,
    ErrorMsg AS Full_Message,
    CASE 
        WHEN ErrorMsg LIKE '%' + @LongDatasetName + '%' THEN '✅ Complete dataset name in message'
        WHEN LEN(ErrorMsg) > 300 THEN '✅ Long message preserved'
        ELSE '❌ Message may be truncated'
    END AS Truncation_Test_Result
FROM tblErrorLog 
WHERE Process = 'spProcessCases'
    AND Date >= DATEADD(minute, -5, GETDATE())
ORDER BY Date DESC

-- Step 5: Restore proper dataset name
UPDATE tblConfiguration 
SET KeyValue = 'YOUR.ACTUAL.DATASET.NAME'  -- Replace with your real dataset name
WHERE KeyName = 'MFDailyCycleDataFile'

-- ================================================================
-- TEST 3: MULTIPLE ERROR CONTEXT (spProcessCases)
-- ================================================================

-- Generate an error with multiple context pieces (CaseId + file path + operation)

-- Step 1: Prepare a case that will be processed successfully first
UPDATE tblClaim SET LockedBy = NULL WHERE LockedBy = 'TEST_USER'

-- Step 2: Set up a scenario that will fail after case processing
-- Use a valid directory but remove write permissions after file creation starts
UPDATE tblConfiguration 
SET KeyValue = 'C:\temp\TestLongErrorMessages\WithMultipleContextPieces\AndVeryLongDirectoryNames\'
WHERE KeyName = 'MFDataDirectory'

-- Step 3: Create the directory structure
EXEC master.dbo.xp_cmdshell 'mkdir "C:\temp\TestLongErrorMessages\WithMultipleContextPieces\AndVeryLongDirectoryNames"'

-- Step 4: Run spProcessCases - should succeed initially but may fail later
EXEC spProcessCases @bTestMF = 1, @bDebug = 1, @bSendMail = 0, @bSendFile = 0

-- Step 5: Check for multi-context error messages
SELECT 
    'Multi-Context Error Test' AS TestType,
    Date,
    CaseId,
    Process,
    LEN(ErrorMsg) AS Message_Length,
    ErrorMsg AS Full_Message,
    CASE 
        WHEN ErrorMsg LIKE '%CaseId%' AND LEN(ErrorMsg) > 200 THEN '✅ Complete context preserved'
        WHEN ErrorMsg LIKE '%CaseId%' THEN '❓ Has CaseId but may be truncated'
        ELSE '❌ Missing context or truncated'
    END AS Context_Test_Result
FROM tblErrorLog 
WHERE Process = 'spProcessCases'
    AND Date >= DATEADD(minute, -5, GETDATE())
ORDER BY Date DESC

-- Step 6: Cleanup
EXEC master.dbo.xp_cmdshell 'rmdir /s /q "C:\temp\TestLongErrorMessages"'
UPDATE tblConfiguration SET KeyValue = 'E:\FACESData\' WHERE KeyName = 'MFDataDirectory'

-- ================================================================
-- TEST 4: CONFIGURATION ERROR WITH LONG PATHS (spProcessReissueCases)
-- ================================================================

-- Test configuration error messages in spProcessReissueCases

-- Step 1: Create a very long invalid directory path
UPDATE tblConfiguration 
SET KeyValue = 'Z:\NonExistentDriveWithVeryLongPathNameThatWillGenerateAnExtremelyLongErrorMessageWhenTheConfigurationValidationFailsInSpProcessReissueCases\SubDirectory\'
WHERE KeyName = 'MFDataDirectory'

-- Step 2: Run spProcessReissueCases
EXEC spProcessReissueCases @bStatusUpdate = 0, @bSendMail = 0, @bSendFile = 0, @bDebug = 1

-- Step 3: Check error message
SELECT 
    'spProcessReissueCases Long Path Error' AS TestType,
    Date,
    CaseId,
    Process,
    LEN(ErrorMsg) AS Message_Length,
    ErrorMsg AS Full_Message,
    CASE 
        WHEN LEN(ErrorMsg) > 150 THEN '✅ Long configuration error preserved'
        WHEN LEN(ErrorMsg) < 100 THEN '❌ Configuration error truncated'
        ELSE '❓ Medium length error'
    END AS Truncation_Test_Result
FROM tblErrorLog 
WHERE Process = 'spProcessReissueCases'
    AND Date >= DATEADD(minute, -5, GETDATE())
ORDER BY Date DESC

-- Step 4: Restore configuration
UPDATE tblConfiguration 
SET KeyValue = 'E:\FACESData\'
WHERE KeyName = 'MFDataDirectory'

-- ================================================================
-- TEST 5: INVALID DATASET NAME ERROR (spProcessReissueCases)
-- ================================================================

-- Test with very long reissue dataset name

-- Step 1: Set invalid reissue dataset name
UPDATE tblConfiguration 
SET KeyValue = 'INVALID.REISSUE.DATASET.NAME.THAT.IS.EXTREMELY.LONG.AND.WILL.CAUSE.ERROR.MESSAGES.TO.BE.VERY.LONG.WHEN.FTP.OPERATIONS.FAIL.TESTING.TRUNCATION'
WHERE KeyName = 'MFReissueDataFile'

-- Step 2: Run spProcessReissueCases
EXEC spProcessReissueCases @bStatusUpdate = 0, @bSendMail = 0, @bSendFile = 1, @bDebug = 1

-- Step 3: Check error message
SELECT 
    'spProcessReissueCases Dataset Error' AS TestType,
    Date,
    CaseId,
    Process,
    LEN(ErrorMsg) AS Message_Length,
    ErrorMsg AS Full_Message
FROM tblErrorLog 
WHERE Process = 'spProcessReissueCases'
    AND Date >= DATEADD(minute, -5, GETDATE())
ORDER BY Date DESC

-- Step 4: Restore dataset name
UPDATE tblConfiguration 
SET KeyValue = 'YOUR.ACTUAL.REISSUE.DATASET'  -- Replace with actual name
WHERE KeyName = 'MFReissueDataFile'

-- ================================================================
-- TEST 6: FORCE FILE SIZE COMPARISON ERROR
-- ================================================================

-- This generates a very specific error with detailed file information

-- Step 1: Set up valid config
UPDATE tblConfiguration SET KeyValue = 'E:\FACESData\' WHERE KeyName = 'MFDataDirectory'
UPDATE tblConfiguration SET KeyValue = 'TEST.DATASET.WITH.VERY.LONG.NAME.FOR.TESTING.MESSAGE.TRUNCATION.ISSUES' WHERE KeyName = 'MFDailyCycleDataFile'

-- Step 2: Run spProcessCases in production mode to trigger file size comparison
EXEC spProcessCases @bTestMF = 0, @bDebug = 1, @bSendMail = 0, @bSendFile = 1

-- Step 3: Check for file size comparison errors
SELECT 
    'File Size Comparison Error' AS TestType,
    Date,
    CaseId,
    Process,
    LEN(ErrorMsg) AS Message_Length,
    ErrorMsg AS Full_Message,
    CASE 
        WHEN ErrorMsg LIKE '%size%' AND LEN(ErrorMsg) > 100 THEN '✅ Complete file operation error'
        ELSE '❓ Other error or truncated'
    END AS File_Error_Test
FROM tblErrorLog 
WHERE Process = 'spProcessCases'
    AND Date >= DATEADD(minute, -5, GETDATE())
ORDER BY Date DESC

-- ================================================================
-- COMPREHENSIVE RESULTS CHECK
-- ================================================================

-- Check all recent errors from both procedures to compare message lengths
SELECT 
    'SUMMARY: All Recent Errors' AS TestType,
    Date,
    CaseId,
    Process,
    LEN(ErrorMsg) AS Message_Length,
    CASE 
        WHEN LEN(ErrorMsg) > 300 THEN '✅ LONG (Complete)'
        WHEN LEN(ErrorMsg) BETWEEN 150 AND 300 THEN '✅ MEDIUM (Likely Complete)'
        WHEN LEN(ErrorMsg) BETWEEN 50 AND 150 THEN '❓ SHORT (Check for truncation)'
        ELSE '❌ VERY SHORT (Likely truncated)'
    END AS Length_Assessment,
    LEFT(ErrorMsg, 80) + '...' AS Message_Preview
FROM tblErrorLog 
WHERE Process IN ('spProcessCases', 'spProcessReissueCases')
    AND Date >= DATEADD(hour, -1, GETDATE())
ORDER BY Date DESC, Process

-- ================================================================
-- BEFORE/AFTER COMPARISON
-- ================================================================

-- Look for patterns that indicate truncation vs complete messages
SELECT 
    Process,
    AVG(LEN(ErrorMsg)) AS Avg_Message_Length,
    MIN(LEN(ErrorMsg)) AS Min_Length,
    MAX(LEN(ErrorMsg)) AS Max_Length,
    COUNT(*) AS Error_Count,
    COUNT(CASE WHEN LEN(ErrorMsg) > 200 THEN 1 END) AS Long_Messages,
    COUNT(CASE WHEN LEN(ErrorMsg) < 100 THEN 1 END) AS Short_Messages
FROM tblErrorLog 
WHERE Process IN ('spProcessCases', 'spProcessReissueCases')
    AND Date >= DATEADD(day, -7, GETDATE())
GROUP BY Process

PRINT ''
PRINT 'Error generation tests completed!'
PRINT 'Check the results above to verify:'
PRINT '1. Error messages are now longer and more complete'
PRINT '2. Full file paths and context are preserved'
PRINT '3. CaseId information is included when available'
PRINT '4. No messages end abruptly or show truncation patterns'