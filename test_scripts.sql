-- ================================================================
-- TEST SCRIPTS TO VERIFY CASEID ERROR LOGGING
-- ================================================================

-- Test 1: Lock a case to generate an error with CaseId
-- This is the safest test as it doesn't corrupt any data

-- First, verify the case exists and is available
SELECT 
    c.CaseId,
    cl.Claim,
    s.Abbrev AS StatusCode,
    cl.LockedBy
FROM tblCases c
    JOIN tblClaim cl ON c.ClaimId = cl.ClaimId
    JOIN rtblCode s ON c.StatusCodeId = s.CodeId
WHERE c.CaseId = 30070

-- Lock the case to force an error
UPDATE tblClaim 
SET LockedBy = 'TEST_USER'
WHERE ClaimId = (
    SELECT ClaimId 
    FROM tblCases 
    WHERE CaseId = 30070
)

-- Verify the case is locked
SELECT 
    c.CaseId,
    cl.Claim,
    cl.LockedBy
FROM tblCases c
    JOIN tblClaim cl ON c.ClaimId = cl.ClaimId
WHERE c.CaseId = 30070

-- Now test spGenerateMFData - this should generate an error with CaseId 30070
EXEC spGenerateMFData 'A89880020', 'C:\temp\test', 0, 0, 0, 1

-- Check the error log to verify CaseId is captured
SELECT TOP 10 
    Date,
    CaseId,
    Process,
    ErrorMsg
FROM tblErrorLog 
WHERE Process = 'spGenerateMFData'
ORDER BY Date DESC

-- Expected result: Should show CaseId = 30070 with error message "A89880020  Locked."

-- Unlock the case when done testing
UPDATE tblClaim 
SET LockedBy = NULL
WHERE ClaimId = (
    SELECT ClaimId 
    FROM tblCases 
    WHERE CaseId = 30070
)

-- ================================================================

-- Test 2: Test spProcessCases with the locked case
-- This will test the CaseId tracking through the entire process

-- Lock the case again
UPDATE tblClaim 
SET LockedBy = 'TEST_USER'
WHERE ClaimId = (
    SELECT ClaimId 
    FROM tblCases 
    WHERE CaseId = 30070
)

-- Test spProcessCases - this should capture the CaseId when spGenerateMFData fails
EXEC spProcessCases @bTestMF = 1, @bDebug = 1, @bSendMail = 0, @bSendFile = 0

-- Check error log for both procedures
SELECT TOP 10 
    Date,
    CaseId,
    Process,
    ErrorMsg
FROM tblErrorLog 
WHERE Process IN ('spGenerateMFData', 'spProcessCases')
ORDER BY Date DESC

-- Expected result: Should show CaseId = 30070 for spGenerateMFData errors

-- Unlock the case
UPDATE tblClaim 
SET LockedBy = NULL
WHERE ClaimId = (
    SELECT ClaimId 
    FROM tblCases 
    WHERE CaseId = 30070
)

-- ================================================================

-- Test 3: Test configuration error (should show NULL CaseId)
-- This tests errors that occur before case processing

-- Temporarily corrupt configuration
DECLARE @OriginalValue VARCHAR(100)
SELECT @OriginalValue = KeyValue 
FROM tblConfiguration 
WHERE KeyName = 'MFDataDirectory'

-- Set invalid directory
UPDATE tblConfiguration 
SET KeyValue = 'Z:\InvalidPath'
WHERE KeyName = 'MFDataDirectory'

-- Test spProcessCases - this should generate configuration error with NULL CaseId
EXEC spProcessCases @bTestMF = 1, @bDebug = 1, @bSendMail = 0, @bSendFile = 0

-- Check error log
SELECT TOP 5 
    Date,
    CaseId,
    Process,
    ErrorMsg
FROM tblErrorLog 
WHERE Process = 'spProcessCases'
ORDER BY Date DESC

-- Expected result: Should show CaseId = NULL for configuration errors

-- Restore original configuration
UPDATE tblConfiguration 
SET KeyValue = @OriginalValue
WHERE KeyName = 'MFDataDirectory'

-- ================================================================

-- Test 4: Test file path error (should show CaseId)
-- This tests errors that occur during case processing

-- Use invalid file path to cause file write error
EXEC spGenerateMFData 'A89880020', 'Z:\invalid\path\test', 0, 0, 0, 1

-- Check error log
SELECT TOP 5 
    Date,
    CaseId,
    Process,
    ErrorMsg
FROM tblErrorLog 
WHERE Process = 'spGenerateMFData'
ORDER BY Date DESC

-- Expected result: Should show CaseId = 30070 (or whatever case was being processed)

-- ================================================================

-- VERIFICATION QUERIES
-- ================================================================

-- Query 1: Check recent error logs with CaseId breakdown
SELECT 
    CASE 
        WHEN CaseId IS NULL THEN 'System/Config Errors'
        ELSE 'Case-Specific Errors'
    END AS ErrorType,
    COUNT(*) AS ErrorCount,
    Process
FROM tblErrorLog 
WHERE Date >= DATEADD(hour, -1, GETDATE())
GROUP BY 
    CASE 
        WHEN CaseId IS NULL THEN 'System/Config Errors'
        ELSE 'Case-Specific Errors'
    END,
    Process
ORDER BY Process, ErrorType

-- Query 2: Show recent errors with case details
SELECT 
    el.Date,
    el.CaseId,
    el.Process,
    el.ErrorMsg,
    CASE 
        WHEN el.CaseId IS NOT NULL THEN cl.Claim
        ELSE 'N/A'
    END AS ClaimNumber
FROM tblErrorLog el
    LEFT JOIN tblCases c ON el.CaseId = c.CaseId
    LEFT JOIN tblClaim cl ON c.ClaimId = cl.ClaimId
WHERE el.Date >= DATEADD(hour, -1, GETDATE())
ORDER BY el.Date DESC

-- Query 3: Check for any remaining NULL CaseId issues
SELECT 
    Process,
    COUNT(*) AS NullCaseIdCount
FROM tblErrorLog 
WHERE CaseId IS NULL 
    AND Date >= DATEADD(day, -1, GETDATE())
    AND Process IN ('spGenerateMFData', 'spProcessCases', 'spProcessReissueCases', 'spCalcGrossToNet_main')
GROUP BY Process

-- ================================================================

-- CLEANUP SCRIPT
-- ================================================================

-- Remove test errors from error log (optional)
-- DELETE FROM tblErrorLog WHERE ErrorMsg LIKE '%TEST_USER%'
-- DELETE FROM tblErrorLog WHERE ErrorMsg LIKE '%Z:\invalid\path%'

-- Verify no cases are left locked
SELECT 
    c.CaseId,
    cl.Claim,
    cl.LockedBy
FROM tblCases c
    JOIN tblClaim cl ON c.ClaimId = cl.ClaimId
WHERE cl.LockedBy IS NOT NULL

-- Unlock any test-locked cases
-- UPDATE tblClaim SET LockedBy =