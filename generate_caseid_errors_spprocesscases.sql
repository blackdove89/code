-- ================================================================
-- METHODS TO GENERATE ACTUAL CASEID ERRORS IN spProcessCases
-- ================================================================

-- Method 1: Lock a Case (RECOMMENDED - Safest)
-- This causes spGenerateMFData to fail during case processing, 
-- and spProcessCases will capture that CaseId

-- Step 1: Find an available case
SELECT TOP 5
    c.CaseId,
    cl.Claim,
    s.Abbrev AS StatusCode,
    cl.LockedBy
FROM tblCases c
    JOIN tblClaim cl ON c.ClaimId = cl.ClaimId
    JOIN rtblCode s ON c.StatusCodeId = s.CodeId
WHERE s.Abbrev IN ('300', '700')
    AND cl.LockedBy IS NULL
ORDER BY c.CaseId

-- Step 2: Lock the case (use your actual CaseId)
UPDATE tblClaim 
SET LockedBy = 'TEST_USER'
WHERE ClaimId = (
    SELECT ClaimId 
    FROM tblCases 
    WHERE CaseId = 30070  -- Replace with your actual CaseId
)

-- Step 3: Run spProcessCases 
EXEC spProcessCases @bTestMF = 1, @bDebug = 1, @bSendMail = 0, @bSendFile = 0

-- Step 4: Check error log for CaseId
SELECT TOP 5 
    Date,
    CaseId,
    Process,
    ErrorMsg
FROM tblErrorLog 
WHERE CaseId IS NOT NULL
ORDER BY Date DESC

-- Expected Result: 
-- CaseId = 30070, Process = spGenerateMFData, ErrorMsg = "A89880020  Locked."
-- And potentially: CaseId = 30070, Process = spProcessCases with file creation error

-- Step 5: Unlock the case
UPDATE tblClaim 
SET LockedBy = NULL
WHERE ClaimId = (
    SELECT ClaimId 
    FROM tblCases 
    WHERE CaseId = 30070
)

-- ================================================================

-- Method 2: Invalid File Path During Processing
-- This causes file operations to fail while processing cases

-- Step 1: Set valid config so spProcessCases starts, but invalid file path
-- First ensure basic config is valid
UPDATE tblConfiguration 
SET KeyValue = 'C:\temp\'  -- Valid directory that exists
WHERE KeyName = 'MFDataDirectory'

-- Step 2: Run spProcessCases but it will fail when trying to create files
-- The trick is to let it get past config validation but fail during case processing
EXEC spProcessCases @bTestMF = 1, @bDebug = 1, @bSendMail = 0, @bSendFile = 0

-- If the above doesn't fail, try with a path that will cause issues:
-- Step 3: Try with a path that exists but will cause file creation issues
UPDATE tblConfiguration 
SET KeyValue = 'C:\Windows\System32\'  -- No write permissions
WHERE KeyName = 'MFDataDirectory'

EXEC spProcessCases @bTestMF = 1, @bDebug = 1, @bSendMail = 0, @bSendFile = 0

-- Step 4: Check error log
SELECT TOP 5 
    Date,
    CaseId,
    Process,
    ErrorMsg
FROM tblErrorLog 
WHERE CaseId IS NOT NULL
ORDER BY Date DESC

-- Step 5: Restore proper config
UPDATE tblConfiguration 
SET KeyValue = 'E:\FACESData\'  -- Your actual data directory
WHERE KeyName = 'MFDataDirectory'

-- ================================================================

-- Method 3: Remove Required Data from a Specific Case
-- This makes spGenerateMFData fail when processing that specific case

-- Step 1: Backup FERS data for a case
SELECT * INTO #BackupFERSData 
FROM tblFERSData 
WHERE CaseId = 30070  -- Use your actual CaseId

-- Step 2: Remove the FERS data to cause "No FERS data" error
DELETE FROM tblFERSData 
WHERE CaseId = 30070

-- Step 3: Run spProcessCases
EXEC spProcessCases @bTestMF = 1, @bDebug = 1, @bSendMail = 0, @bSendFile = 0

-- Step 4: Check error log
SELECT TOP 5 
    Date,
    CaseId,
    Process,
    ErrorMsg
FROM tblErrorLog 
WHERE CaseId = 30070
ORDER BY Date DESC

-- Expected Result: CaseId = 30070, ErrorMsg about "No FERS data"

-- Step 5: Restore the FERS data
INSERT INTO tblFERSData 
SELECT * FROM #BackupFERSData

DROP TABLE #BackupFERSData

-- ================================================================

-- Method 4: Modify spWriteToFile to Fail (Advanced)
-- This requires temporarily modifying the file path in the procedure call

-- You can manually run spGenerateMFData with invalid path:
EXEC spGenerateMFData '', 'Z:\InvalidPath\test', 0, 0, 0, 1

-- This will show which CaseId was being processed when file write failed
-- Check the result:
SELECT TOP 5 
    Date,
    CaseId,
    Process,
    ErrorMsg
FROM tblErrorLog 
WHERE Process = 'spGenerateMFData'
ORDER BY Date DESC

-- ================================================================

-- Method 5: Force spGetCSAData or spGetFERSData to Fail
-- Temporarily rename a required table

-- Step 1: Rename a table that spGetCSAData needs
EXEC sp_rename 'tblRunResults', 'tblRunResults_backup'

-- Step 2: Run spProcessCases - this will fail when calling spGetCSAData
EXEC spProcessCases @bTestMF = 1, @bDebug = 1, @bSendMail = 0, @bSendFile = 0

-- Step 3: Check error log
SELECT TOP 5 
    Date,
    CaseId,
    Process,
    ErrorMsg
FROM tblErrorLog 
WHERE CaseId IS NOT NULL
ORDER BY Date DESC

-- Expected Result: CaseId number with error about invalid object name

-- Step 4: Restore table name
EXEC sp_rename 'tblRunResults_backup', 'tblRunResults'

-- ================================================================

-- Method 6: File Permission Error During Case Processing
-- Set up a scenario where files can be created initially but fail later

-- Step 1: Create a directory that initially works but will fail
-- You'll need to manually create C:\temp\readonly and set it to read-only after
-- spProcessCases starts processing

-- Step 2: Set config to use that directory
UPDATE tblConfiguration 
SET KeyValue = 'C:\temp\readonly\'
WHERE KeyName = 'MFDataDirectory'

-- Step 3: Run spProcessCases
EXEC spProcessCases @bTestMF = 1, @bDebug = 1, @bSendMail = 0, @bSendFile = 0

-- Step 4: Check results
SELECT TOP 5 
    Date,
    CaseId,
    Process,
    ErrorMsg
FROM tblErrorLog 
WHERE CaseId IS NOT NULL
ORDER BY Date DESC

-- ================================================================

-- RECOMMENDED QUICK TEST (SAFEST)
-- ================================================================

-- This is the safest and most reliable method:

-- 1. Lock a case
UPDATE tblClaim 
SET LockedBy = 'TEST_USER'
WHERE ClaimId = (SELECT ClaimId FROM tblCases WHERE CaseId = 30070)

-- 2. Run spProcessCases
EXEC spProcessCases @bTestMF = 1, @bDebug = 1, @bSendMail = 0, @bSendFile = 0

-- 3. Check for CaseId in error log
SELECT 
    Date,
    CaseId,
    Process,
    ErrorMsg,
    CASE 
        WHEN CaseId IS NULL THEN 'System Error'
        ELSE 'Case-Specific Error'
    END AS ErrorType
FROM tblErrorLog 
WHERE Date >= DATEADD(minute, -5, GETDATE())
ORDER BY Date DESC

-- 4. Unlock the case
UPDATE tblClaim 
SET LockedBy = NULL
WHERE ClaimId = (SELECT ClaimId FROM tblCases WHERE CaseId = 30070)

-- ================================================================

-- VERIFICATION QUERY
-- ================================================================

-- After running any test, use this to see the difference:
SELECT 
    'With CaseId' AS ErrorType,
    COUNT(*) AS Count,
    Process
FROM tblErrorLog 
WHERE CaseId IS NOT NULL 
    AND Date >= DATEADD(hour, -1, GETDATE())
GROUP BY Process

UNION ALL

SELECT 
    'NULL CaseId' AS ErrorType,
    COUNT(*) AS Count,
    Process
FROM tblErrorLog 
WHERE CaseId IS NULL 
    AND Date >= DATEADD(hour, -1, GETDATE())
GROUP BY Process

ORDER BY ErrorType, Process

-- Expected results should show:
-- "With CaseId" entries for spGenerateMFData (and potentially spProcessCases)
-- "NULL CaseId" entries only for true system errors