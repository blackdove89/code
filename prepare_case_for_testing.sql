-- ================================================================
-- PREPARE A CASE FOR CASEID ERROR TESTING
-- ================================================================

-- Step 1: Find a candidate case to modify
-- Look for cases with basic structure but missing some requirements

SELECT TOP 10
    c.CaseId,
    cl.Claim,
    s.Abbrev AS CurrentStatus,
    cl.LockedBy,
    CASE WHEN EXISTS(SELECT 1 FROM tblRunResults WHERE CaseId = c.CaseId) THEN 'Has Runs' ELSE 'No Runs' END AS RunStatus,
    CASE WHEN EXISTS(SELECT 1 FROM tblFERSData WHERE CaseId = c.CaseId) THEN 'Has FERS' ELSE 'No FERS' END AS FERSStatus,
    CASE WHEN EXISTS(SELECT 1 FROM tblGrossToNet WHERE CaseId = c.CaseId) THEN 'Has G2N' ELSE 'No G2N' END AS G2NStatus
FROM tblCases c
    JOIN tblClaim cl ON c.ClaimId = cl.ClaimId
    JOIN rtblCode s ON c.StatusCodeId = s.CodeId
WHERE s.Abbrev NOT IN ('300', '700')  -- Cases not currently ready
ORDER BY c.CaseId DESC

-- ================================================================

-- Step 2: Choose a case and modify it step by step
-- Replace 30070 with your chosen CaseId throughout this script

DECLARE @TestCaseId INT = 30070  -- CHANGE THIS TO YOUR CHOSEN CASEID

PRINT 'Preparing CaseId ' + CAST(@TestCaseId AS VARCHAR(10)) + ' for testing...'

-- ================================================================

-- Step 2A: Set the case to correct status (300 = Trigger Pending)

UPDATE tblCases 
SET StatusCodeId = dbo.fGetCodeId('300', 'StatusCodes')
WHERE CaseId = @TestCaseId

PRINT '✓ Step 2A: Set status to 300 (Trigger Pending)'

-- ================================================================

-- Step 2B: Ensure case is not locked

UPDATE tblClaim 
SET LockedBy = NULL
WHERE ClaimId = (SELECT ClaimId FROM tblCases WHERE CaseId = @TestCaseId)

PRINT '✓ Step 2B: Unlocked case'

-- ================================================================

-- Step 2C: Create triggered run results if missing

-- Check if run results exist
IF NOT EXISTS(SELECT 1 FROM tblRunResults WHERE CaseId = @TestCaseId AND Method = 0 AND bTriggered = 1)
BEGIN
    -- Insert basic run results record
    INSERT INTO tblRunResults (
        CaseId,
        Method,
        bTriggered,
        TotalComputationService,
        RunType,
        Created,
        CreatedBy
    )
    VALUES (
        @TestCaseId,
        0,  -- Method = 0
        1,  -- bTriggered = 1
        '30/00/00',  -- Sample total service
        0,  -- RunType
        GETDATE(),
        'TEST_SETUP'
    )
    
    PRINT '✓ Step 2C: Created triggered run results'
END
ELSE
BEGIN
    -- Update existing run results to be triggered
    UPDATE tblRunResults 
    SET bTriggered = 1,
        TotalComputationService = CASE 
            WHEN TotalComputationService IS NULL OR TotalComputationService = '00/00/00' 
            THEN '30/00/00' 
            ELSE TotalComputationService 
        END
    WHERE CaseId = @TestCaseId AND Method = 0
    
    PRINT '✓ Step 2C: Updated existing run results to triggered'
END

-- ================================================================

-- Step 2D: Create FERS data if missing

-- First check what retirement type this case has
DECLARE @RetirementType VARCHAR(1)
SELECT @RetirementType = rt.Abbrev
FROM tblCases c
    JOIN vwCaseServiceSummary css ON c.CaseId = css.CaseId
    LEFT JOIN rtblCode rt ON css.RetirementTypeId = rt.CodeId
WHERE c.CaseId = @TestCaseId

IF @RetirementType NOT IN ('1', '4')  -- Case types 1 and 4 don't need FERS data
BEGIN
    IF NOT EXISTS(SELECT 1 FROM tblFERSData WHERE CaseId = @TestCaseId)
    BEGIN
        -- Insert basic FERS data
        INSERT INTO tblFERSData (
            CaseId,
            RunType,
            Created,
            CreatedBy,
            BasicPay,
            FERSDeduction,
            StartDate,
            EndDate
        )
        VALUES (
            @TestCaseId,
            0,  -- Match the RunType from tblRunResults
            GETDATE(),
            'TEST_SETUP',
            50000.00,  -- Sample basic pay
            4000.00,   -- Sample FERS deduction
            '2020-01-01',  -- Sample start date
            '2024-12-31'   -- Sample end date
        )
        
        PRINT '✓ Step 2D: Created FERS data'
    END
    ELSE
    BEGIN
        PRINT '✓ Step 2D: FERS data already exists'
    END
END
ELSE
BEGIN
    PRINT '✓ Step 2D: FERS data not required for retirement type ' + ISNULL(@RetirementType, 'Unknown')
END

-- ================================================================

-- Step 2E: Create Gross-to-Net data if missing

IF NOT EXISTS(SELECT 1 FROM tblGrossToNet WHERE CaseId = @TestCaseId)
BEGIN
    -- Insert basic Gross-to-Net data
    INSERT INTO tblGrossToNet (
        CaseId,
        UserId,
        Age,
        EffectiveDate,
        Comment,
        TotalGross,
        Net,
        Created
    )
    VALUES (
        @TestCaseId,
        'TEST_SETUP',
        65,  -- Sample age
        GETDATE(),
        'Test data for error testing',
        2500.00,  -- Sample gross amount
        2200.00,  -- Sample net amount
        GETDATE()
    )
    
    PRINT '✓ Step 2E: Created Gross-to-Net data'
END
ELSE
BEGIN
    PRINT '✓ Step 2E: Gross-to-Net data already exists'
END

-- ================================================================

-- Step 3: Verify the case is now ready for processing

SELECT 
    'FINAL VERIFICATION' AS CheckType,
    c.CaseId,
    cl.Claim,
    s.Abbrev AS Status,
    
    -- Check each requirement
    CASE WHEN s.Abbrev IN ('300', '700') THEN '✓' ELSE '✗' END AS Status_OK,
    CASE WHEN cl.LockedBy IS NULL THEN '✓' ELSE '✗' END AS NotLocked_OK,
    CASE WHEN EXISTS(SELECT 1 FROM tblRunResults WHERE CaseId = c.CaseId AND Method = 0 AND bTriggered = 1) 
         THEN '✓' ELSE '✗' END AS RunResults_OK,
    CASE WHEN @RetirementType IN ('1', '4') OR 
              EXISTS(SELECT 1 FROM tblRunResults a JOIN tblFERSData b ON a.CaseId = b.CaseId 
                     WHERE a.CaseId = c.CaseId AND a.Method = 0 AND a.bTriggered = 1)
         THEN '✓' ELSE '✗' END AS FERSData_OK,
    CASE WHEN EXISTS(SELECT 1 FROM tblRunResults a JOIN tblGrossToNet b ON a.CaseId = b.CaseId 
                     WHERE a.CaseId = c.CaseId AND a.Method = 0 AND a.bTriggered = 1)
         THEN '✓' ELSE '✗' END AS GrossToNet_OK,
    CASE WHEN EXISTS(SELECT 1 FROM tblRunResults WHERE CaseId = c.CaseId AND TotalComputationService IS NOT NULL 
                     AND TotalComputationService <> '00/00/00' AND Method = 0 AND bTriggered = 1)
         THEN '✓' ELSE '✗' END AS TotalService_OK,
         
    -- Overall readiness
    CASE WHEN s.Abbrev IN ('300', '700') 
              AND cl.LockedBy IS NULL
              AND EXISTS(SELECT 1 FROM tblRunResults WHERE CaseId = c.CaseId AND Method = 0 AND bTriggered = 1)
              AND (@RetirementType IN ('1', '4') OR 
                   EXISTS(SELECT 1 FROM tblRunResults a JOIN tblFERSData b ON a.CaseId = b.CaseId 
                          WHERE a.CaseId = c.CaseId AND a.Method = 0 AND a.bTriggered = 1))
              AND EXISTS(SELECT 1 FROM tblRunResults a JOIN tblGrossToNet b ON a.CaseId = b.CaseId 
                         WHERE a.CaseId = c.CaseId AND a.Method = 0 AND a.bTriggered = 1)
              AND EXISTS(SELECT 1 FROM tblRunResults WHERE CaseId = c.CaseId AND TotalComputationService IS NOT NULL 
                         AND TotalComputationService <> '00/00/00' AND Method = 0 AND bTriggered = 1)
         THEN '🎯 READY FOR TESTING'
         ELSE '❌ STILL NOT READY'
    END AS OverallStatus

FROM tblCases c
    JOIN tblClaim cl ON c.ClaimId = cl.ClaimId
    JOIN rtblCode s ON c.StatusCodeId = s.CodeId
WHERE c.CaseId = @TestCaseId

-- ================================================================

-- Step 4: Test the prepared case

PRINT ''
PRINT 'Case preparation complete. Now testing CaseId error generation...'

-- Test 1: Lock the case and try to process it
UPDATE tblClaim 
SET LockedBy = 'TEST_USER'
WHERE ClaimId = (SELECT ClaimId FROM tblCases WHERE CaseId = @TestCaseId)

-- Run spGenerateMFData to generate CaseId error
DECLARE @CurrentCaseId INT
EXEC spGenerateMFData '', 'C:\temp\test_caseid', 0, 0, 0, 1, @CurrentCaseId = @CurrentCaseId OUTPUT

-- Check the results
SELECT 
    'TEST RESULTS' AS ResultType,
    Date,
    CaseId,
    Process,
    LEFT(ErrorMsg, 100) AS ErrorMsg
FROM tblErrorLog 
WHERE CaseId = @TestCaseId
    AND Date >= DATEADD(minute, -2, GETDATE())

-- Unlock the case
UPDATE tblClaim 
SET LockedBy = NULL
WHERE ClaimId = (SELECT ClaimId FROM tblCases WHERE CaseId = @TestCaseId)

PRINT 'Test completed. Check results above.'

-- ================================================================

-- ALTERNATIVE: MINIMAL DATA APPROACH
-- If the above creates too much data, use this minimal approach:

/*
-- Minimal approach - just add the essential missing pieces:

-- 1. Set status to 300
UPDATE tblCases SET StatusCodeId = dbo.fGetCodeId('300', 'StatusCodes') WHERE CaseId = @TestCaseId

-- 2. Add minimal run results
IF NOT EXISTS(SELECT 1 FROM tblRunResults WHERE CaseId = @TestCaseId AND Method = 0 AND bTriggered = 1)
INSERT INTO tblRunResults (CaseId, Method, bTriggered, TotalComputationService, RunType, Created, CreatedBy)
VALUES (@TestCaseId, 0, 1, '30/00/00', 0, GETDATE(), 'TEST')

-- 3. Add minimal gross-to-net
IF NOT EXISTS(SELECT 1 FROM tblGrossToNet WHERE CaseId = @TestCaseId)
INSERT INTO tblGrossToNet (CaseId, UserId, Age, EffectiveDate, Comment, Created)
VALUES (@TestCaseId, 'TEST', 65, GETDATE(), 'Test', GETDATE())

-- 4. Add minimal FERS data (if needed based on retirement type)
-- Check retirement type first, then add if needed
*/

-- ================================================================

-- CLEANUP SCRIPT (Run this after testing to clean up test data)
-- ================================================================

/*
-- To remove test data after testing:

DELETE FROM tblRunResults WHERE CaseId = @TestCaseId AND CreatedBy = 'TEST_SETUP'
DELETE FROM tblFERSData WHERE CaseId = @TestCaseId AND CreatedBy = 'TEST_SETUP'  
DELETE FROM tblGrossToNet WHERE CaseId = @TestCaseId AND UserId = 'TEST_SETUP'

-- Reset case status if needed
UPDATE tblCases SET StatusCodeId = dbo.fGetCodeId('210', 'StatusCodes') WHERE CaseId = @TestCaseId

PRINT 'Test data cleaned up'
*/