-- ========================================
-- TEST SCENARIOS FOR CASEID ERROR LOGGING
-- ========================================

-- SCENARIO 1: TEST spProcessCases (Regular Cases)
-- ========================================

-- Step 1: Find a case with status 300 or 700
DECLARE @TestCaseId INT, @TestClaim VARCHAR(9)

SELECT TOP 1 
    @TestCaseId = a.CaseId, 
    @TestClaim = cl.Claim
FROM tblCases a
    JOIN tblClaim cl ON a.ClaimId = cl.ClaimId
    JOIN rtblCode b ON a.StatusCodeId = b.CodeId
WHERE b.Abbrev IN ('300', '700')
    AND cl.LockedBy IS NULL
ORDER BY a.CaseId DESC

PRINT 'Test CaseId: ' + ISNULL(CAST(@TestCaseId AS VARCHAR(20)), 'No cases found')
PRINT 'Test Claim: ' + ISNULL(@TestClaim, 'N/A')

-- Step 2: Choose ONE of these methods to force an error:

-- METHOD A: Temporarily modify spGenerateMFData to force an error
/*
ALTER PROCEDURE [dbo].[spGenerateMFData]
    @ClaimNumber VARCHAR(9) = NULL,
    @Filename VARCHAR(100),
    @bTest TINYINT = 0,
    @bUpdate TINYINT = 0,
    @bSendMail BIT = 0,
    @bDebug TINYINT = 0,
    @CurrentCaseId INT = NULL OUTPUT
AS
BEGIN
    -- ... existing declarations ...
    
    -- ADD THIS TEMPORARY CODE at the beginning of the main code block
    IF @ClaimNumber = 'A89880020'  -- Replace with your test claim
    BEGIN
        SET @CurrentCaseId = 30070  -- Replace with your test CaseId
        RAISERROR('TEST ERROR: Forcing error for CaseId %d to test error logging', 16, 1, 30070)
        RETURN -1
    END
    
    -- ... rest of existing code ...
END
*/

-- METHOD B: Force an error in spGetCSAData
/*
ALTER PROCEDURE [dbo].[spGetCSAData]
    @CaseId INT,
    @Data VARCHAR(2000) OUTPUT,
    @bDebug BIT = 0
AS
BEGIN
    -- ADD THIS TEMPORARY CODE at the beginning
    IF @CaseId = 30070  -- Replace with your test CaseId
    BEGIN
        RAISERROR('TEST ERROR in spGetCSAData: Testing error logging for CaseId %d', 16, 1, @CaseId)
        RETURN -1
    END
    
    -- ... rest of existing code ...
END
*/

-- METHOD C: Corrupt data temporarily to cause processing error
/*
-- Backup data first
SELECT * INTO #TempBackup FROM tblRunResults WHERE CaseId = @TestCaseId

-- Corrupt data to cause error
UPDATE tblRunResults 
SET TotalComputationService = NULL 
WHERE CaseId = @TestCaseId AND Method = 0 AND bTriggered = 1

-- Run the process
EXEC spProcessCases @bTestMF = 1, @bStatusUpdate = 0, @bSendMail = 0, @bSendFile = 0, @bDebug = 0

-- Restore data
UPDATE r
SET TotalComputationService = b.TotalComputationService
FROM tblRunResults r
    JOIN #TempBackup b ON r.CaseId = b.CaseId AND r.RunId = b.RunId
WHERE r.CaseId = @TestCaseId

DROP TABLE #TempBackup
*/

-- Step 3: Run the test
PRINT '=== Running spProcessCases Test ==='
EXEC spProcessCases 
    @bTestMF = 1,
    @bStatusUpdate = 0,
    @bSendMail = 0,
    @bSendFile = 0,
    @bDebug = 0

-- Step 4: Check error log
SELECT TOP 5 
    LogId,
    Date,
    Process,
    CaseId,
    CASE 
        WHEN CaseId IS NULL THEN 'NULL - No CaseId'
        ELSE 'CaseId: ' + CAST(CaseId AS VARCHAR(20))
    END as CaseIdInfo,
    LEFT(ErrorMsg, 200) as ErrorMsg
FROM tblErrorLog 
WHERE Date >= DATEADD(MINUTE, -5, GETDATE())
ORDER BY Date DESC

-- ========================================
-- SCENARIO 2: TEST spProcessReissueCases
-- ========================================

-- Step 1: Create a reissue case scenario (if no natural ones exist)
-- Find cases with appropriate status
SELECT TOP 5
    a.CaseId,
    cl.Claim,
    b.Abbrev as OriginalStatus,
    p.CaseId as RelatedCaseId,
    q.Abbrev as RelatedStatus
FROM tblCases a
    JOIN tblClaim cl ON a.ClaimId = cl.ClaimId
    JOIN rtblCode b ON a.StatusCodeId = b.CodeId
    LEFT JOIN tblCaseRelation e ON a.CaseId = e.GeneratedCaseId
    LEFT JOIN tblCases p ON e.OriginalCaseid = p.CaseId
    LEFT JOIN rtblCode q ON p.StatusCodeId = q.CodeId
WHERE (b.Abbrev = '500' AND q.Abbrev = '402')
   OR (b.Abbrev = '402' AND EXISTS (
       SELECT 1 FROM tblCaseRelation cr 
       JOIN tblCases c2 ON cr.GeneratedCaseId = c2.CaseId
       JOIN rtblCode r2 ON c2.StatusCodeId = r2.CodeId
       WHERE cr.OriginalCaseid = a.CaseId AND r2.Abbrev = '500'
   ))

-- Step 2: If you have reissue cases, force an error in spGenerateReissueData
/*
ALTER PROCEDURE [dbo].[spGenerateReissueData]
    @Filename VARCHAR(100),
    @bUpdate TINYINT = 0,
    @bSendMail BIT = 0,
    @bDebug TINYINT = 0,
    @CurrentCaseId INT = NULL OUTPUT
AS
BEGIN
    -- ... existing declarations ...
    
    -- ADD THIS after the cursor opens and fetches first record
    -- In the TRY block, after SET @CurrentCaseId = @nCaseId
    IF @nCaseId = [YourTestCaseId]  -- Replace with actual CaseId
    BEGIN
        RAISERROR('TEST ERROR: Testing reissue error logging for CaseId %d', 16, 1, @nCaseId)
    END
    
    -- ... rest of existing code ...
END
*/

-- Step 3: Run reissue test
PRINT '=== Running spProcessReissueCases Test ==='
EXEC spProcessReissueCases 
    @bStatusUpdate = 0,
    @bSendMail = 0,
    @bSendFile = 0,
    @bDebug = 0

-- ========================================
-- EASIEST TEST: Force error at specific point
-- ========================================

-- This is the simplest test - add a divide by zero error
/*
-- In spGenerateMFData, after SET @CurrentCaseId = @nCaseId, add:
IF @nCaseId = 30070  -- Your test case
BEGIN
    DECLARE @x INT = 0
    DECLARE @y INT = 1 / @x  -- This will cause divide by zero error
END

-- Or in spGenerateReissueData:
IF @nCaseId = [YourReissueCaseId]
BEGIN
    DECLARE @x INT = 0
    DECLARE @y INT = 1 / @x  -- This will cause divide by zero error
END
*/

-- ========================================
-- VERIFICATION QUERIES
-- ========================================

-- Check all recent errors with CaseId info
SELECT 
    el.LogId,
    el.Date,
    el.Process,
    el.CaseId,
    c.Version,
    cl.Claim,
    rc.Description as Status,
    LEFT(el.ErrorMsg, 150) as ErrorMsg
FROM tblErrorLog el
    LEFT JOIN tblCases c ON el.CaseId = c.CaseId
    LEFT JOIN tblClaim cl ON c.ClaimId = cl.ClaimId
    LEFT JOIN rtblCode rc ON c.StatusCodeId = rc.CodeId
WHERE el.Date >= DATEADD(HOUR, -1, GETDATE())
ORDER BY el.Date DESC

-- Summary of errors by process
SELECT 
    Process,
    COUNT(*) as ErrorCount,
    COUNT(CaseId) as ErrorsWithCaseId,
    COUNT(*) - COUNT(CaseId) as ErrorsWithoutCaseId,
    MAX(Date) as LastError
FROM tblErrorLog
WHERE Date >= DATEADD(DAY, -1, GETDATE())
GROUP BY Process
ORDER BY MAX(Date) DESC