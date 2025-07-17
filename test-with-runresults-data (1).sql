-- ========================================
-- TEST CASEID ERROR LOGGING WITH PROPER DATA
-- ========================================

-- 1. Find a test case with status 300 or 700
DECLARE @TestCaseId INT = 30070  -- Your test case
DECLARE @TestClaim VARCHAR(9)

SELECT 
    @TestCaseId = a.CaseId,
    @TestClaim = cl.Claim
FROM tblCases a
    JOIN tblClaim cl ON a.ClaimId = cl.ClaimId
    JOIN rtblCode b ON a.StatusCodeId = b.CodeId
WHERE a.CaseId = @TestCaseId

PRINT 'Test CaseId: ' + CAST(@TestCaseId AS VARCHAR(20))
PRINT 'Test Claim: ' + ISNULL(@TestClaim, 'Not found')

-- 2. Create minimal RunResults data to make case processable
IF NOT EXISTS (SELECT 1 FROM tblRunResults WHERE CaseId = @TestCaseId AND Method = 0 AND bTriggered = 1)
BEGIN
    PRINT 'Creating test RunResults data...'
    
    INSERT INTO tblRunResults (
        RunType,
        Method,
        CaseId,
        AverageSalary,
        AnnualBenefit,
        CSRSMonthly,
        FERSMonthly,
        bTriggered,
        CSRSEarnedRate,
        FERSEarnedRate,
        totalserviceold,
        UnreducedEarnedRate,
        bVoluntaryOverride,
        ProvRetCode,
        ServicePurchasedCode,
        TotalComputationService  -- This is required!
    )
    VALUES (
        0,          -- RunType
        0,          -- Method
        @TestCaseId,-- CaseId
        50000.00,   -- AverageSalary
        25000.00,   -- AnnualBenefit
        1000,       -- CSRSMonthly
        500,        -- FERSMonthly
        1,          -- bTriggered (MUST be 1)
        0,          -- CSRSEarnedRate
        0,          -- FERSEarnedRate
        0,          -- totalserviceold
        0,          -- UnreducedEarnedRate
        0,          -- bVoluntaryOverride
        0,          -- ProvRetCode
        '01',       -- ServicePurchasedCode
        '10/05/15'  -- TotalComputationService (REQUIRED - can't be NULL or '00/00/00')
    )
    
    PRINT 'RunResults created successfully'
END

-- 3. Create minimal FERSData if needed (for non-CSRS cases)
DECLARE @RetirementType VARCHAR(1)
SELECT @RetirementType = c.Abbrev
FROM tblCases a
    JOIN vwCaseServiceSummary d ON a.CaseId = d.CaseId
    LEFT JOIN rtblCode c ON d.RetirementTypeId = c.CodeId
WHERE a.CaseId = @TestCaseId

IF @RetirementType NOT IN ('1', '4')  -- Not CSRS
BEGIN
    IF NOT EXISTS (SELECT 1 FROM tblFERSData WHERE CaseId = @TestCaseId)
    BEGIN
        PRINT 'Creating test FERSData...'
        -- You'll need to create FERSData record here if required
        -- INSERT INTO tblFERSData (...) VALUES (...)
    END
END

-- 4. Create minimal GrossToNet data
IF NOT EXISTS (SELECT 1 FROM tblGrossToNet WHERE CaseId = @TestCaseId)
BEGIN
    PRINT 'Creating test GrossToNet data...'
    -- You'll need to create GrossToNet record here if required
    -- INSERT INTO tblGrossToNet (...) VALUES (...)
END

-- 5. Now test with different error scenarios

-- SCENARIO A: Force error in spGenerateMFData
PRINT '=== Scenario A: Add error trigger to spGenerateMFData ==='
/*
ALTER PROCEDURE [dbo].[spGenerateMFData]
AS
BEGIN
    -- ... existing code ...
    
    -- In the main loop, after SET @CurrentCaseId = @nCaseId, add:
    IF @nCaseId = 30070  -- Your test case
    BEGIN
        RAISERROR('TEST ERROR: Testing error logging for CaseId %d in spGenerateMFData', 16, 1, @nCaseId)
    END
    
    -- ... rest of code ...
END
*/

-- SCENARIO B: Force error in spGetCSAData
PRINT '=== Scenario B: Add error trigger to spGetCSAData ==='
/*
ALTER PROCEDURE [dbo].[spGetCSAData]
    @CaseId INT,
    @Data VARCHAR(2000) OUTPUT,
    @bDebug BIT = 0
AS
BEGIN
    IF @CaseId = 30070  -- Your test case
    BEGIN
        RAISERROR('TEST ERROR: Testing error logging for CaseId %d in spGetCSAData', 16, 1, @CaseId)
        RETURN -1
    END
    
    -- ... existing code ...
END
*/

-- SCENARIO C: Force divide by zero error
PRINT '=== Scenario C: Force divide by zero in spGenerateMFData ==='
/*
-- In spGenerateMFData, after SET @CurrentCaseId = @nCaseId:
IF @nCaseId = 30070
BEGIN
    DECLARE @x INT = 0
    DECLARE @y INT = 1 / @x  -- Divide by zero error
END
*/

-- 6. Run the test
PRINT ''
PRINT '=== Running spProcessCases Test ==='
EXEC spProcessCases 
    @bTestMF = 1,
    @bStatusUpdate = 0,
    @bSendMail = 0,
    @bSendFile = 0,
    @bDebug = 0

-- 7. Check error log
PRINT ''
PRINT '=== Checking Error Log ==='
SELECT TOP 5
    LogId,
    Date,
    Process,
    CaseId,
    CASE 
        WHEN CaseId IS NULL THEN '❌ NULL - No CaseId captured'
        WHEN CaseId = @TestCaseId THEN '✓ SUCCESS - CaseId ' + CAST(CaseId AS VARCHAR(20)) + ' captured!'
        ELSE '✓ CaseId ' + CAST(CaseId AS VARCHAR(20)) + ' captured'
    END as Result,
    LEFT(ErrorMsg, 150) as ErrorMsg
FROM tblErrorLog 
WHERE Date >= DATEADD(MINUTE, -5, GETDATE())
ORDER BY Date DESC

-- 8. Cleanup test data
PRINT ''
PRINT '=== Cleanup Test Data ==='
PRINT 'To cleanup, run these commands:'
PRINT 'DELETE FROM tblRunResults WHERE CaseId = ' + CAST(@TestCaseId AS VARCHAR(20)) + ' AND AverageSalary = 50000.00'
PRINT 'DELETE FROM tblFERSData WHERE CaseId = ' + CAST(@TestCaseId AS VARCHAR(20)) + ' AND [identify test record]'
PRINT 'DELETE FROM tblGrossToNet WHERE CaseId = ' + CAST(@TestCaseId AS VARCHAR(20)) + ' AND [identify test record]'

-- Optional: Actually cleanup
/*
DELETE FROM tblRunResults 
WHERE CaseId = @TestCaseId 
  AND AverageSalary = 50000.00  -- Identifies our test record
  AND RunType = 0 
  AND Method = 0
*/

-- 9. Alternative test without modifying procedures
PRINT ''
PRINT '=== Alternative: Test with bad data ==='
-- Update the TotalComputationService to NULL to cause an error
/*
UPDATE tblRunResults 
SET TotalComputationService = NULL
WHERE CaseId = @TestCaseId AND Method = 0 AND bTriggered = 1

-- Run process - this should cause an error
EXEC spProcessCases @bTestMF = 1, @bStatusUpdate = 0, @bSendMail = 0, @bSendFile =