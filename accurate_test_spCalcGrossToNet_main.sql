-- ================================================================
-- ACCURATE TEST FOR spCalcGrossToNet_main USING REAL COLUMN NAMES
-- ================================================================

-- Now that we know the actual column structure, let's map them correctly:

-- spCalcGrossToNet_main parameters vs tblRunResults columns:
-- @CSRSRate     -> CSRSMonthly (monthly CSRS amount)
-- @CSRSTime     -> TotalCSRSService (CSRS service time)  
-- @FERSRate     -> FERSMonthly (monthly FERS amount)
-- @FERSTime     -> TotalFERSService (FERS service time)
-- @AvgSalPT     -> AverageSalary (average salary)

-- ================================================================

-- Step 1: Find a case with actual run results data
SELECT TOP 10
    rr.CaseId,
    cl.Claim,
    s.Abbrev AS Status,
    rr.RunType,
    rr.Method,
    rr.bTriggered,
    rr.CSRSMonthly,
    rr.FERSMonthly,
    rr.AverageSalary,
    rr.TotalCSRSService,
    rr.TotalFERSService,
    rr.TotalComputationService
FROM tblRunResults rr
    JOIN tblCases c ON rr.CaseId = c.CaseId
    JOIN tblClaim cl ON c.ClaimId = cl.ClaimId
    JOIN rtblCode s ON c.StatusCodeId = s.CodeId
WHERE rr.bTriggered = 1
    AND rr.Method = 0
    AND rr.CSRSMonthly IS NOT NULL
    AND rr.FERSMonthly IS NOT NULL
    AND rr.AverageSalary IS NOT NULL
ORDER BY rr.CaseId DESC

-- ================================================================

-- Step 2: Test spCalcGrossToNet_main with real case data
DECLARE @TestCaseId INT = 30070  -- REPLACE WITH ACTUAL CASEID FROM ABOVE QUERY

-- Get the actual parameters from tblRunResults
DECLARE @CSRSRate INT
DECLARE @CSRSTime DECIMAL(5,3)
DECLARE @FERSRate INT
DECLARE @FERSTime DECIMAL(5,3)
DECLARE @AvgSalPT DECIMAL(12,2)
DECLARE @G2NCaseType TINYINT
DECLARE @SurvivorCode TINYINT
DECLARE @RetirementType VARCHAR(10)

-- Extract real parameters from the triggered run results
SELECT 
    @CSRSRate = ISNULL(CAST(rr.CSRSMonthly AS INT), 0),
    @CSRSTime = ISNULL(rr.TotalCSRSService, 0),
    @FERSRate = ISNULL(CAST(rr.FERSMonthly AS INT), 0),
    @FERSTime = ISNULL(rr.TotalFERSService, 0),
    @AvgSalPT = ISNULL(rr.AverageSalary, 0),
    @SurvivorCode = CASE WHEN rr.SurvivorRate > 0 THEN 1 ELSE 0 END,
    @RetirementType = ISNULL(rr.CalcRetirementType, ''),
    @G2NCaseType = CASE 
        WHEN rt.Abbrev = '8' THEN 2  -- Death case
        WHEN s.Abbrev LIKE '%1%' OR rr.CalcRetirementType = 'D' THEN 1  -- Disability case  
        WHEN rr.CalcRetirementType = 'C' THEN 3  -- CSRS Disability
        ELSE 0  -- Regular case
    END
FROM tblRunResults rr
    JOIN tblCases c ON rr.CaseId = c.CaseId
    JOIN rtblCode s ON c.StatusCodeId = s.CodeId
    LEFT JOIN vwCaseServiceSummary css ON c.CaseId = css.CaseId
    LEFT JOIN rtblCode rt ON css.RetirementTypeId = rt.CodeId
WHERE rr.CaseId = @TestCaseId
    AND rr.bTriggered = 1
    AND rr.Method = 0

-- Display the parameters we extracted
SELECT 
    'Parameters Extracted from tblRunResults' AS Info,
    @TestCaseId AS CaseId,
    @CSRSRate AS CSRSRate_Monthly,
    @CSRSTime AS CSRSTime_Years,
    @FERSRate AS FERSRate_Monthly,
    @FERSTime AS FERSTime_Years,
    @AvgSalPT AS AvgSalary,
    @G2NCaseType AS G2NCaseType,
    @SurvivorCode AS SurvivorCode,
    @RetirementType AS CalcRetirementType

-- ================================================================

-- Step 3: Execute spCalcGrossToNet_main with real parameters

PRINT 'Testing spCalcGrossToNet_main with real case data...'
PRINT 'CaseId: ' + CAST(@TestCaseId AS VARCHAR(20))
PRINT 'CSRS Monthly: $' + CAST(@CSRSRate AS VARCHAR) + ', FERS Monthly: $' + CAST(@FERSRate AS VARCHAR)
PRINT 'Average Salary: $' + CAST(@AvgSalPT AS VARCHAR) + ', Case Type: ' + CAST(@G2NCaseType AS VARCHAR)

BEGIN TRY
    EXEC spCalcGrossToNet_main 
        @CaseId = @TestCaseId,
        @CSRSRate = @CSRSRate,
        @CSRSTime = @CSRSTime,
        @FERSRate = @FERSRate,
        @FERSTime = @FERSTime,
        @AvgSalPT = @AvgSalPT,
        @G2NCaseType = @G2NCaseType,
        @SurvivorCode = @SurvivorCode,
        @bVoluntaryOverride = 0,
        @bDebug = 2,  -- Enable debug for spCalcGrossToNet_main
        @Login = 'TEST_USER'
        
    PRINT 'spCalcGrossToNet_main completed successfully'
END TRY
BEGIN CATCH
    PRINT 'spCalcGrossToNet_main failed with error: ' + ERROR_MESSAGE()
END CATCH

-- ================================================================

-- Step 4: Check for any errors logged
SELECT 
    'Recent Errors from spCalcGrossToNet_main' AS CheckType,
    Date,
    CaseId,
    Process,
    LEFT(ErrorMsg, 200) AS ErrorMsg
FROM tblErrorLog 
WHERE Process = 'spCalcGrossToNet_main'
    AND Date >= DATEADD(minute, -5, GETDATE())
ORDER BY Date DESC

-- ================================================================

-- Step 5: Force an error to test CaseId logging

PRINT ''
PRINT 'Testing error logging by forcing a table access error...'

-- Temporarily rename a table that spCalcGrossToNet_main uses
EXEC sp_rename 'GrossToNet', 'GrossToNet_backup'

-- Try to run spCalcGrossToNet_main again - this should cause an error
BEGIN TRY
    EXEC spCalcGrossToNet_main 
        @CaseId = @TestCaseId,
        @CSRSRate = @CSRSRate,
        @CSRSTime = @CSRSTime,
        @FERSRate = @FERSRate,
        @FERSTime = @FERSTime,
        @AvgSalPT = @AvgSalPT,
        @G2NCaseType = @G2NCaseType,
        @SurvivorCode = @SurvivorCode,
        @bVoluntaryOverride = 0,
        @bDebug = 2,
        @Login = 'TEST_USER'
END TRY
BEGIN CATCH
    PRINT 'Expected error occurred: ' + ERROR_MESSAGE()
END CATCH

-- Restore the table
EXEC sp_rename 'GrossToNet_backup', 'GrossToNet'

-- Check if the error was logged with the correct CaseId
SELECT 
    'Forced Error Test Results' AS CheckType,
    Date,
    CaseId,
    Process,
    LEFT(ErrorMsg, 200) AS ErrorMsg,
    CASE 
        WHEN CaseId = @TestCaseId THEN '✓ CaseId Logged Correctly'
        WHEN CaseId IS NULL THEN '✗ CaseId is NULL (Original Version)'
        ELSE '? CaseId is Different: ' + CAST(CaseId AS VARCHAR)
    END AS CaseIdStatus
FROM tblErrorLog 
WHERE Process = 'spCalcGrossToNet_main'
    AND Date >= DATEADD(minute, -2, GETDATE())
ORDER BY Date DESC

-- ================================================================

-- Step 6: Alternative test with simpler approach
-- If the above doesn't work due to missing case data

PRINT ''
PRINT 'Alternative test with minimal parameters...'

BEGIN TRY
    EXEC spCalcGrossToNet_main 
        @CaseId = @TestCaseId,
        @CSRSRate = 2500,        -- $2500/month
        @CSRSTime = 25.5,        -- 25.5 years of service
        @FERSRate = 1800,        -- $1800/month  
        @FERSTime = 15.0,        -- 15 years of service
        @AvgSalPT = 75000,       -- $75,000 average salary
        @G2NCaseType = 0,        -- Regular case
        @SurvivorCode = 0,       -- No survivor
        @bVoluntaryOverride = 0, -- No override
        @bDebug = 2,             -- Debug enabled
        @Login = 'TEST_USER'
        
    PRINT 'Alternative test completed successfully'
END TRY
BEGIN CATCH
    PRINT 'Alternative test failed: ' + ERROR_MESSAGE()
END CATCH

-- ================================================================

-- Step 7: Check any temporary data created

-- Check if GrossToNet data was created
SELECT 
    'GrossToNet Data Created' AS DataType,
    COUNT(*) AS RecordCount,
    MIN(EffectiveDate) AS MinDate,
    MAX(EffectiveDate) AS MaxDate
FROM GrossToNet 
WHERE CaseId = @TestCaseId 
    AND UserId = 'TEST_USER'

-- Show sample records if any were created
SELECT TOP 5
    'Sample GrossToNet Records' AS DataType,
    EffectiveDate,
    Age,
    TotalGross,
    Net,
    Comment
FROM GrossToNet 
WHERE CaseId = @TestCaseId 
    AND UserId = 'TEST_USER'
ORDER BY EffectiveDate

-- ================================================================

-- Step 8: Cleanup test data (optional)

/*
-- Uncomment to clean up test data
DELETE FROM GrossToNet WHERE CaseId = @TestCaseId AND UserId = 'TEST_USER'
DELETE FROM LIChanges WHERE CaseId = @TestCaseId AND UserId = 'TEST_USER'
PRINT 'Test data cleaned up'
*/

PRINT ''
PRINT 'Test completed. Check results above for:'
PRINT '1. Successful execution (no errors)'
PRINT '2. Error logging with correct CaseId'
PRINT '3. Data creation in GrossToNet table'

-- ================================================================

-- QUICK REFERENCE: Parameter Mapping
-- ================================================================

/*
spCalcGrossToNet_main Parameter Mapping from tblRunResults:

@CaseId             -> rr.CaseId
@CSRSRate           -> rr.CSRSMonthly (monthly amount)
@CSRSTime           -> rr.TotalCSRSService (years of service)
@FERSRate           -> rr.FERSMonthly (monthly amount)  
@FERSTime           -> rr.TotalFERSService (years of service)
@AvgSalPT           -> rr.AverageSalary (annual salary)
@G2NCaseType        -> Derived from case status/retirement type
@SurvivorCode       -> Derived from rr.SurvivorRate
@bVoluntaryOverride -> rr.bVoluntaryOverride
@bDebug             -> Set to 2 for procedure debugging
@Login              -> 'TEST_USER' or actual user
*/