-- ================================================================
-- METHODS TO FORCE spProcessCases TO LOG CASEID ERRORS
-- ================================================================

-- Method 1: Force File Creation Failure After spGenerateMFData Succeeds
-- This makes spProcessCases fail AFTER it gets CaseId from spGenerateMFData

-- Step 1: Ensure we have a valid case that will process successfully
-- First unlock any locked cases
UPDATE tblClaim SET LockedBy = NULL WHERE LockedBy = 'TEST_USER'

-- Step 2: Verify the case exists and has required data
SELECT 
    c.CaseId,
    cl.Claim,
    s.Abbrev AS StatusCode,
    CASE WHEN rr.CaseId IS NOT NULL THEN 'Has RunResults' ELSE 'Missing RunResults' END AS RunStatus,
    CASE WHEN fd.CaseId IS NOT NULL THEN 'Has FERS Data' ELSE 'Missing FERS Data' END AS FERSStatus
FROM tblCases c
    JOIN tblClaim cl ON c.ClaimId = cl.ClaimId
    JOIN rtblCode s ON c.StatusCodeId = s.CodeId
    LEFT JOIN tblRunResults rr ON c.CaseId = rr.CaseId AND rr.Method = 0 AND rr.bTriggered = 1
    LEFT JOIN tblFERSData fd ON c.CaseId = fd.CaseId
WHERE c.CaseId = 30070

-- Step 3: Set up configuration that will let spGenerateMFData succeed initially
-- but cause spProcessCases to fail during file operations
UPDATE tblConfiguration 
SET KeyValue = 'C:\temp\'
WHERE KeyName = 'MFDataDirectory'

-- Step 4: Create the temp directory if it doesn't exist
EXEC master.dbo.xp_cmdshell 'mkdir C:\temp'

-- Step 5: Run spProcessCases - but we need to make it fail AFTER getting CaseId
-- The trick is to let spGenerateMFData succeed, then make subsequent operations fail

-- Actually, let's use a different approach...
-- Set an invalid file path for the data file name itself
UPDATE tblConfiguration 
SET KeyValue = 'C:\temp\'
WHERE KeyName = 'MFDataDirectory'

-- Set an invalid dataset name that will cause FTP operations to fail
UPDATE tblConfiguration 
SET KeyValue = 'INVALID.DATASET.NAME.THAT.WILL.FAIL'
WHERE KeyName = 'MFDailyCycleDataFile'

-- Step 6: Run spProcessCases with file sending enabled
EXEC spProcessCases @bTestMF = 0, @bDebug = 1, @bSendMail = 0, @bSendFile = 1

-- This should:
-- 1. spGenerateMFData succeeds and returns CaseId
-- 2. spProcessCases tries to FTP the file and fails
-- 3. spProcessCases logs error with the CaseId it got from spGenerateMFData

-- ================================================================

-- Method 2: Force spFileExists to Fail 
-- Make spGenerateMFData create files, but then delete them before spProcessCases checks

-- Step 1: Set valid configuration
UPDATE tblConfiguration 
SET KeyValue = 'C:\temp\'
WHERE KeyName = 'MFDataDirectory'

-- Step 2: Run this in two parts with manual file deletion in between
-- First, let's see what files spGenerateMFData would create:
DECLARE @TestCaseId INT = 30070
DECLARE @CurrentCaseId INT

-- Run spGenerateMFData directly first to see what it creates
EXEC spGenerateMFData '', 'C:\temp\test', 1, 0, 0, 1, @CurrentCaseId = @CurrentCaseId OUTPUT

-- Check what files were created
EXEC master.dbo.xp_cmdshell 'dir C:\temp\test*.*'

-- Now delete the .psv file to make spProcessCases fail
EXEC master.dbo.xp_cmdshell 'del C:\temp\test.psv'

-- Now run spProcessCases - it should fail at spFileExists check
-- But this won't work because spProcessCases calls spGenerateMFData again

-- ================================================================

-- Method 3: Modify File Permissions During Execution (Advanced)
-- This requires quick timing or a helper script

-- Step 1: Set up a directory with files
UPDATE tblConfiguration 
SET KeyValue = 'C:\temp\testdir\'
WHERE KeyName = 'MFDataDirectory'

EXEC master.dbo.xp_cmdshell 'mkdir C:\temp\testdir'

-- Step 2: Run spProcessCases and quickly change permissions
-- (This would require manual intervention during execution)

-- ================================================================

-- Method 4: Force ParseMFData Command to Fail
-- Create a scenario where the external command fails

-- Step 1: Ensure spGenerateMFData will succeed
UPDATE tblConfiguration 
SET KeyValue = 'C:\temp\'
WHERE KeyName = 'MFDataDirectory'

-- Step 2: Temporarily rename or remove the ParseMFData.cmd file
-- This will cause the xp_cmdshell call to fail
EXEC master.dbo.xp_cmdshell 'rename C:\temp\ParseMFData.cmd ParseMFData.cmd.bak'

-- Step 3: Run spProcessCases
EXEC spProcessCases @bTestMF = 1, @bDebug = 1, @bSendMail = 0, @bSendFile = 0

-- This might not log to tblErrorLog though, as it's an external command failure

-- ================================================================

-- Method 5: BEST APPROACH - Force spCompareFileSize to Fail
-- This happens after spGenerateMFData succeeds but during spProcessCases file operations

-- Step 1: Set up valid configuration
UPDATE tblConfiguration 
SET KeyValue = 'C:\temp\'
WHERE KeyName = 'MFDataDirectory'

UPDATE tblConfiguration 
SET KeyValue = 'VALID.DATASET.NAME'
WHERE KeyName = 'MFDailyCycleDataFile'

-- Step 2: The key is to enable file sending (@bSendFile = 1) and production mode (@bTestMF = 0)
-- This will cause spProcessCases to try FTP operations that will likely fail
EXEC spProcessCases @bTestMF = 0, @bDebug = 1, @bSendMail = 0, @bSendFile = 1

-- ================================================================

-- Method 6: SIMPLEST APPROACH - Corrupt Configuration After spGenerateMFData
-- Use a modified version of spProcessCases temporarily

-- Actually, let's try the direct approach:
-- Look at the spProcessCases code - we need to make it reach ERROR_HANDLER section

-- The ERROR_HANDLER gets triggered when:
-- 1. spFileExists fails
-- 2. FTP process fails  
-- 3. File size comparison fails

-- Let's force a file size comparison failure:

-- Step 1: Valid setup
UPDATE tblConfiguration 
SET KeyValue = 'C:\temp\'
WHERE KeyName = 'MFDataDirectory'

UPDATE tblConfiguration 
SET KeyValue = 'TEST.DATASET'
WHERE KeyName = 'MFDailyCycleDataFile'

-- Step 2: Run with production mode and file sending
-- This will try to FTP and likely fail, triggering ERROR_HANDLER
EXEC spProcessCases @bTestMF = 0, @bDebug = 1, @bSendMail = 0, @bSendFile = 1

-- ================================================================

-- Method 7: GUARANTEED METHOD - Temporary Procedure Modification
-- Temporarily modify spProcessCases to force an error after getting CaseId

-- You could temporarily add this after the spGenerateMFData call in spProcessCases:
/*
IF @CurrentCaseId IS NOT NULL
BEGIN
   -- Force an error to test CaseId logging
   SET @sErrorText = 'TEST ERROR: Forced error with CaseId ' + CAST(@CurrentCaseId AS VARCHAR(20))
   GOTO ERROR_HANDLER
END
*/

-- ================================================================

-- VERIFICATION QUERIES
-- ================================================================

-- Check what spProcessCases errors we have
SELECT 
    Date,
    CaseId,
    Process,
    ErrorMsg
FROM tblErrorLog 
WHERE Process = 'spProcessCases'
    AND Date >= DATEADD(hour, -1, GETDATE())
ORDER BY Date DESC

-- Check both processes together
SELECT 
    Date,
    CaseId,
    Process,
    ErrorMsg
FROM tblErrorLog 
WHERE Process IN ('spProcessCases', 'spGenerateMFData')
    AND Date >= DATEADD(hour, -1, GETDATE())
ORDER BY Date DESC

-- ================================================================

-- RECOMMENDED TEST SEQUENCE
-- ================================================================

-- Test 1: Try the FTP failure approach
UPDATE tblConfiguration SET KeyValue = 'C:\temp\' WHERE KeyName = 'MFDataDirectory'
UPDATE tblConfiguration SET KeyValue = 'INVALID.DATASET.NAME' WHERE KeyName = 'MFDailyCycleDataFile'

EXEC spProcessCases @bTestMF = 0, @bDebug = 1, @bSendMail = 0, @bSendFile = 1

SELECT TOP 5 Date, CaseId, Process, ErrorMsg 
FROM tblErrorLog 
WHERE Date >= DATEADD(minute, -5, GETDATE())
ORDER BY Date DESC

-- Test 2: If that doesn't work, try file permission error
-- Set directory to one without write permissions
UPDATE tblConfiguration SET KeyValue = 'C:\Windows\System32\' WHERE KeyName = 'MFDataDirectory'

EXEC spProcessCases @bTestMF = 1, @bDebug = 1, @bSendMail = 0, @bSendFile = 0

SELECT TOP 5 Date, CaseId, Process, ErrorMsg 
FROM tblErrorLog 
WHERE Date >= DATEADD(minute, -5, GETDATE())
ORDER BY Date DESC

-- Restore proper configuration
UPDATE tblConfiguration SET KeyValue = 'E:\FACESData\' WHERE KeyName = 'MFDataDirectory'
UPDATE tblConfiguration SET KeyValue = 'your.actual.dataset.name' WHERE KeyName = 'MFDailyCycleDataFile'