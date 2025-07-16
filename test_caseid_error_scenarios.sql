-- ================================================================
-- TEST SCENARIOS TO GENERATE ERRORS WITH CASEID VALUES
-- ================================================================

-- Option 1: Lock a case to force a "Locked" error
-- This is the safest option as it doesn't corrupt data
UPDATE tblClaim 
SET LockedBy = 'TEST_USER'
WHERE ClaimId = (
    SELECT ClaimId 
    FROM tblCases 
    WHERE CaseId = 30070  -- Use your test CaseId here
)

-- Test by running spGenerateMFData with this case
EXEC spGenerateMFData 'A89880020', 'C:\temp\test', 0, 0, 0, 1

-- To unlock the case afterward:
UPDATE tblClaim 
SET LockedBy = NULL
WHERE ClaimId = (
    SELECT ClaimId 
    FROM tblCases 
    WHERE CaseId = 30070
)

-- ================================================================

-- Option 2: Temporarily remove required data to force "No FERS data" error
-- First, backup the data
SELECT * INTO #backup_FERSData 
FROM tblFERSData 
WHERE CaseId = 30070

-- Remove the FERS data
DELETE FROM tblFERSData WHERE CaseId = 30070

-- Test spGenerateMFData - this should generate error with CaseId
EXEC spGenerateMFData 'A89880020', 'C:\temp\test', 0, 0, 0, 1

-- Restore the data
INSERT INTO tblFERSData 
SELECT * FROM #backup_FERSData

DROP TABLE #backup_FERSData

-- ================================================================

-- Option 3: Temporarily remove Gross-to-Net data
-- Backup first
SELECT * INTO #backup_GrossToNet 
FROM tblGrossToNet 
WHERE CaseId = 30070

-- Remove the data
DELETE FROM tblGrossToNet WHERE CaseId = 30070

-- Test - should generate "No Gross-to-net data" error
EXEC spGenerateMFData 'A89880020', 'C:\temp\test', 0, 0, 0, 1

-- Restore
INSERT INTO tblGrossToNet 
SELECT * FROM #backup_GrossToNet

DROP TABLE #backup_GrossToNet

-- ================================================================

-- Option 4: Force an error in one of the called stored procedures
-- This simulates what happens when spGetCSAData, spGetFERSData, etc. fail

-- Temporarily rename a required table to cause spGetCSAData to fail
-- (Do this only in a test environment!)
EXEC sp_rename 'tblRunResults', 'tblRunResults_backup'

-- Test - this will cause spGetCSAData to fail with CaseId context
EXEC spGenerateMFData 'A89880020', 'C:\temp\test', 0, 0, 0, 1

-- Restore the table name
EXEC sp_rename 'tblRunResults_backup', 'tblRunResults'

-- ================================================================

-- Option 5: Create invalid file path to test file writing errors
-- This should cause spWriteToFile to fail
EXEC spGenerateMFData 'A89880020', 'Z:\invalid\path\test', 0, 0, 0, 1

-- ================================================================

-- Option 6: Set TotalComputationService to invalid value
-- Backup first
DECLARE @originalService VARCHAR(20)
SELECT @originalService = TotalComputationService 
FROM tblRunResults 
WHERE CaseId = 30070 AND Method = 0 AND bTriggered = 1

-- Set to invalid value
UPDATE tblRunResults 
SET TotalComputationService = '00/00/00'
WHERE CaseId = 30070 AND Method = 0 AND bTriggered = 1

-- Test - should generate "No Total Service specified" error
EXEC spGenerateMFData 'A89880020', 'C:\temp\test', 0, 0, 0, 1

-- Restore original value
UPDATE tblRunResults 
SET TotalComputationService = @originalService
WHERE CaseId = 30070 AND Method = 0 AND bTriggered = 1

-- ================================================================

-- VERIFICATION QUERIES
-- ================================================================

-- Check the error log for CaseId values
SELECT TOP 10 
    Date,
    CaseId,
    Process,
    ErrorMsg
FROM tblErrorLog 
WHERE Process IN ('spGenerateMFData', 'spProcessCases')
ORDER BY Date DESC

-- Check which cases are available for testing
SELECT TOP 5
    c.CaseId,
    cl.Claim,
    s.Abbrev AS StatusCode,
    rt.Abbrev AS RetirementType
FROM tblCases c
    JOIN tblClaim cl ON c.ClaimId = cl.ClaimId
    JOIN rtblCode s ON c.StatusCodeId = s.CodeId
    JOIN vwCaseServiceSummary css ON c.CaseId = css.CaseId
    LEFT JOIN rtblCode rt ON css.RetirementTypeId = rt.CodeId
WHERE s.Abbrev IN ('300', '700')
ORDER BY c.CaseId

-- Check if case has required data
SELECT 
    c.CaseId,
    cl.Claim,
    CASE WHEN rr.CaseId IS NOT NULL THEN 'Has RunResults' ELSE 'Missing RunResults' END AS RunStatus,
    CASE WHEN fd.CaseId IS NOT NULL THEN 'Has FERS Data' ELSE 'Missing FERS Data' END AS FERSStatus,
    CASE WHEN gtn.CaseId IS NOT NULL THEN 'Has Gross-to-Net' ELSE 'Missing Gross-to-Net' END AS GrossToNetStatus
FROM tblCases c
    JOIN tblClaim cl ON c.ClaimId = cl.ClaimId
    LEFT JOIN tblRunResults rr ON c.CaseId = rr.CaseId AND rr.Method = 0 AND rr.bTriggered = 1
    LEFT JOIN tblFERSData fd ON c.CaseId = fd.CaseId
    LEFT JOIN tblGrossToNet gtn ON c.CaseId = gtn.CaseId
WHERE c.CaseId = 30070

-- ================================================================

-- RECOMMENDED TEST SEQUENCE
-- ================================================================

/*
1. First, verify the case has the required data:
   - Run the verification queries above
   
2. Use Option 1 (Lock the case) as it's the safest:
   - Lock the case
   - Run spGenerateMFData
   - Check error log for CaseId
   - Unlock the case

3. If you need to test other error conditions, use Options 2-6
   but make sure to backup and restore data properly

4. Always check the error log after each test:
   SELECT * FROM tblErrorLog WHERE CaseId IS NOT NULL ORDER BY Date DESC
*/