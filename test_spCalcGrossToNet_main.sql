-- ================================================================
-- TEST spCalcGrossToNet_main WITH ACTUAL CASEID
-- ================================================================

-- Step 1: Find a suitable case to test with
SELECT TOP 10
    c.CaseId,
    cl.Claim,
    s.Abbrev AS Status,
    rt.Abbrev AS RetirementType,
    CASE WHEN EXISTS(SELECT 1 FROM tblResults WHERE CaseId = c.CaseId) 
         THEN 'Has Results' ELSE 'No Results' END AS ResultsStatus
FROM tblCases c
    JOIN tblClaim cl ON c.ClaimId = cl.ClaimId
    JOIN rtblCode s ON c.StatusCodeId = s.CodeId
    LEFT JOIN vwCaseServiceSummary css ON c.CaseId = css.CaseId
    LEFT JOIN rtblCode rt ON css.RetirementTypeId = rt.CodeId
WHERE s.Abbrev IN ('200', '210', '300', '400', '410')  -- Cases in various processing stages
ORDER BY c.CaseId DESC

-- ================================================================

-- Step 2: Get the parameters needed for spCalcGrossToNet_main from a real case
DECLARE @TestCaseId INT = 30070  -- REPLACE WITH YOUR ACTUAL CASEID

-- Get the case parameters that spCalcGrossToNet_main expects
SELECT 
    'Case Parameters for spCalcGrossToNet_main' AS Info,
    c.CaseId,
    cl.Claim,
    -- These are the typical parameters passed to spCalcGrossToNet_main
    ISNULL(rr.CSRSRate, 0) AS CSRSRate,
    ISNULL(rr.CSRSTime, 0) AS CSRSTime,
    ISNULL(rr.FERSRate, 0) AS FERSRate, 
    ISNULL(rr.FERSTime, 0) AS FERSTime,
    ISNULL(rr.AvgSalPT, 0) AS AvgSalPT,
    CASE 
        WHEN rt.Abbrev = '8' THEN 2  -- Death case
        WHEN s.Abbrev LIKE '%1%' THEN 1  -- Disability case  
        WHEN rt.Abbrev = 'C' THEN 3  -- CSRS Disability
        ELSE 0  -- Regular case
    END AS G2NCaseType,
    0 AS SurvivorCode,  -- Usually 0 unless it's a survivor case
    0 AS bVoluntaryOverride,
    1 AS bDebug,  -- Enable debug for testing
    'TEST_USER' AS Login
FROM tblCases c
    JOIN tblClaim cl ON c.ClaimId = cl.ClaimId
    JOIN rtblCode s ON c.StatusCodeId = s.CodeId
    LEFT JOIN vwCaseServiceSummary css ON c.CaseId = css.CaseId
    LEFT JOIN rtblCode rt ON css.RetirementTypeId = rt.CodeId
    LEFT JOIN tblRunResults rr ON c.CaseId = rr.CaseId AND rr.Method = 0
WHERE c.CaseId = @TestCaseId

-- ================================================================

-- Step 3: Test spCalcGrossToNet_main with actual case data

-- First, let's get the actual parameters for the case
DECLARE @CaseId INT = 30070  -- REPLACE WITH YOUR CASEID
DECLARE @CSRSRate INT
DECLARE @CSRSTime DECIMAL(5,3)
DECLARE @FERSRate INT
DECLARE @FERSTime DECIMAL(5,3)
DECLARE @AvgSalPT DECIMAL(12,2)
DECLARE @G2NCaseType TINYINT
DECLARE @SurvivorCode TINYINT
DECLARE @bVoluntaryOverride BIT
DECLARE @bDebug TINYINT
DECLARE @Login VARCHAR(20)

-- Get parameters from the actual case data
SELECT 
    @CSRSRate = ISNULL(rr.CSRSRate, 0),
    @CSRSTime = ISNULL(rr.CSRSTime, 0),
    @FERSRate = ISNULL(rr.FERSRate, 0),
    @FERSTime = ISNULL(rr.FERSTime, 0),
    @AvgSalPT = ISNULL(rr.AvgSalPT, 0),
    @G2NCaseType = CASE 
        WHEN rt.Abbrev = '8' THEN 2  -- Death case
        WHEN s.Abbrev LIKE '%1%' THEN 1  -- Disability case  
        WHEN rt.Abbrev = 'C' THEN 3  -- CSRS Disability
        ELSE 0  -- Regular case
    END,
    @SurvivorCode = 0,
    @bVoluntaryOverride = 0,
    @bDebug = 2,  -- Enable debug for spCalcGrossToNet_main
    @Login = 'TEST_USER'
FROM tblCases c
    JOIN tblClaim cl ON c.ClaimId = cl.ClaimId
    JOIN rtblCode s ON c.StatusCodeId = s.CodeId
    LEFT JOIN vwCaseServiceSummary css ON c.CaseId = css.CaseId
    LEFT JOIN rtblCode rt ON css.RetirementTypeId = rt.CodeId
    LEFT JOIN tblRunResults rr ON c.CaseId = rr.CaseId AND rr.Method = 0
WHERE c.CaseId = @CaseId

-- Display the parameters we're about to use
SELECT 
    'Parameters for Test' AS Info,
    @CaseId AS CaseId,
    @CSRSRate AS CSRSRate,
    @CSRSTime AS CSRSTime,
    @FERSRate AS FERSRate,
    @FERSTime AS FERSTime,
    @AvgSalPT AS AvgSalPT,
    @G2NCaseType AS G2NCaseType,
    @SurvivorCode AS SurvivorCode,
    @bVoluntaryOverride AS bVoluntaryOverride,
    @bDebug AS bDebug,
    @Login AS Login

-- ================================================================

-- Step 4: Execute spCalcGrossToNet_main

PRINT 'Testing spCalcGrossToNet_main with CaseId: ' + CAST(@CaseId AS VARCHAR(20))
PRINT 'Parameters: CSRSRate=' + CAST(@CSRSRate AS VARCHAR) + ', FERSRate=' + CAST(@FERSRate AS VARCHAR) + ', G2NCaseType=' + CAST(@G2NCaseType AS VARCHAR)

EXEC spCalcGrossToNet_main 
    @CaseId = @CaseId,
    @CSRSRate = @CSRSRate,
    @CSRSTime = @CSRSTime,
    @FERSRate = @FERSRate,
    @FERSTime = @FERSTime,
    @AvgSalPT = @AvgSalPT,
    @G2NCaseType = @G2NCaseType,
    @SurvivorCode = @SurvivorCode,
    @bVoluntaryOverride = @bVoluntaryOverride,
    @bDebug = @bDebug,
    @Login = @Login

-- ================================================================

-- Step 5: Check for any errors logged
SELECT 
    'Error Check Results' AS CheckType,
    Date,
    CaseId,
    Process,
    ErrorMsg
FROM tblErrorLog 
WHERE Process = 'spCalcGrossToNet_main'
    AND CaseId = @CaseId
    AND Date >= DATEADD(minute, -5, GETDATE())
ORDER BY Date DESC

-- ================================================================

-- Step 6: Force an error to test CaseId logging

PRINT ''
PRINT 'Now testing error logging by forcing an error...'

-- Temporarily rename a table that spCalcGrossToNet_main needs
EXEC sp_rename 'rtblLIPremiums', 'rtblLIPremiums_backup'

-- Try to run spCalcGrossToNet_main again - this should cause an error
BEGIN TRY
    EXEC spCalcGrossToNet_main 
        @CaseId = @CaseId,
        @CSRSRate = @CSRSRate,
        @CSRSTime = @CSRSTime,
        @FERSRate = @FERSRate,
        @FERSTime = @FERSTime,
        @AvgSalPT = @AvgSalPT,
        @G2NCaseType = @G2NCaseType,
        @SurvivorCode = @SurvivorCode,
        @bVoluntaryOverride = @bVoluntaryOverride,
        @bDebug = @bDebug,
        @Login = @Login
END TRY
BEGIN CATCH
    PRINT 'Caught expected error: ' + ERROR_MESSAGE()
END CATCH

-- Restore the table
EXEC sp_rename 'rtblLIPremiums_backup', 'rtblLIPremiums'

-- Check if the error was logged with CaseId
SELECT 
    'Forced Error Test Results' AS CheckType,
    Date,
    CaseId,
    Process,
    LEFT(ErrorMsg, 200) AS ErrorMsg,
    CASE 
        WHEN CaseId = @CaseId THEN '✓ CaseId Logged Correctly'
        WHEN CaseId IS NULL THEN '✗ CaseId is NULL'
        ELSE '? CaseId is Different'
    END AS CaseIdStatus
FROM tblErrorLog 
WHERE Process = 'spCalcGrossToNet_main'
    AND Date >= DATEADD(minute, -2, GETDATE())
ORDER BY Date DESC

-- ================================================================

-- ALTERNATIVE: Test with simpler parameters if you don't have complex case data
-- ================================================================

/*
-- Simple test with minimal parameters
EXEC spCalcGrossToNet_main 
    @CaseId = 30070,         -- Your test CaseId
    @CSRSRate = 2500,        -- $2500/month
    @CSRSTime = 0,           -- 0 years CSRS time
    @FERSRate = 1500,        -- $1500/month  
    @FERSTime = 0,           -- 0 years FERS time
    @AvgSalPT = 60000,       -- $60,000 average salary
    @G2NCaseType = 0,        -- Regular case
    @SurvivorCode = 0,       -- No survivor
    @bVoluntaryOverride = 0, -- No override
    @bDebug = 2,             -- Debug spCalcGrossToNet_main
    @Login = 'TEST_USER'
*/

-- ================================================================

-- Step 7: View any temporary data created by the procedure
-- ================================================================

-- Check if any temporary Gross-to-Net data was created
SELECT 
    'Temporary Data Created' AS DataType,
    *
FROM GrossToNet 
WHERE CaseId = @CaseId 
    AND UserId = @Login
ORDER BY EffectiveDate

-- Check if any LI changes data was created  
SELECT 
    'LI Changes Data' AS DataType,
    *
FROM LIChanges
WHERE CaseId = @CaseId
    AND UserId = @Login

-- ================================================================

-- Cleanup temporary data (optional)
-- ================================================================

/*
-- Clean up test data if needed
DELETE FROM GrossToNet WHERE CaseId = @CaseId AND UserId = 'TEST_USER'
DELETE FROM LIChanges WHERE CaseId = @CaseId AND UserId = 'TEST_USER'
*/

PRINT 'Test completed. Check results above.'