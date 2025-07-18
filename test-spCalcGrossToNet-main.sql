-- ========================================
-- TEST ERROR LOGGING FOR spCalcGrossToNet_main
-- ========================================

-- 1. Find a case to test with
DECLARE @TestCaseId INT = 30070  -- Your test case
DECLARE @TestLogin VARCHAR(20) = 'TestUser'

-- Check if case exists
SELECT 
    a.CaseId,
    a.DateOfBirth,
    a.StatusCodeId,
    b.Abbrev as StatusCode,
    cl.Claim
FROM tblCases a
    JOIN rtblCode b ON a.StatusCodeId = b.CodeId
    JOIN tblClaim cl ON a.ClaimId = cl.ClaimId
WHERE a.CaseId = @TestCaseId

-- 2. METHOD 1: Test with invalid parameters that will cause errors
PRINT '=== Test 1: Force divide by zero error ==='

-- This should cause a divide by zero error in FERS calculations
EXEC spCalcGrossToNet_main 
    @CaseId = @TestCaseId,
    @CSRSRate = 100,
    @CSRSTime = 10.5,
    @FERSRate = 0,      -- This might cause divide by zero
    @FERSTime = 0,      
    @AvgSalPT = 0,      -- This might cause issues
    @G2NCaseType = 1,   -- FERS Disability
    @SurvivorCode = 0,
    @bVoluntaryOverride = 0,
    @bDebug = 255,      -- Full debug
    @Login = @TestLogin

-- 3. METHOD 2: Force error in called procedures
PRINT '=== Test 2: Add error trigger to spAddGrossToNetHB ==='
/*
-- Temporarily add this to spAddGrossToNetHB:
ALTER PROCEDURE [dbo].[spAddGrossToNetHB]
    @CaseId INT,
    @HBCode VARCHAR(3),
    @EffectiveDate DATE,
    @bDebug TINYINT,
    @Login VARCHAR(20)
AS
BEGIN
    -- TEMPORARY TEST CODE
    IF @CaseId = 30070
    BEGIN
        RAISERROR('TEST ERROR in spAddGrossToNetHB for CaseId %d', 16, 1, @CaseId)
        RETURN -1
    END
    
    -- ... rest of procedure
END
*/

-- Then run:
EXEC spCalcGrossToNet_main 
    @CaseId = @TestCaseId,
    @CSRSRate = 100,
    @CSRSTime = 10.5,
    @FERSRate = 100,
    @FERSTime = 5.0,
    @AvgSalPT = 50000,
    @G2NCaseType = 0,   -- Regular case
    @SurvivorCode = 0,
    @bVoluntaryOverride = 0,
    @bDebug = 4,        -- Debug HB
    @Login = @TestLogin

-- 4. METHOD 3: Test with missing required data
PRINT '=== Test 3: Missing case data ==='

-- Use a non-existent CaseId
EXEC spCalcGrossToNet_main 
    @CaseId = 99999,    -- Non-existent case
    @CSRSRate = 100,
    @CSRSTime = 10.5,
    @FERSRate = 100,
    @FERSTime = 5.0,
    @AvgSalPT = 50000,
    @G2NCaseType = 0,
    @SurvivorCode = 0,
    @bVoluntaryOverride = 0,
    @bDebug = 2,
    @Login = @TestLogin

-- 5. METHOD 4: Force error in spAddGrossToNetCSRS
PRINT '=== Test 4: Add error trigger to spAddGrossToNetCSRS ==='
/*
-- Temporarily add this to spAddGrossToNetCSRS:
IF @CaseId = 30070
BEGIN
    RAISERROR('TEST ERROR in spAddGrossToNetCSRS for CaseId %d', 16, 1, @CaseId)
    RETURN -1
END
*/

-- 6. METHOD 5: Force error in spAddGrossToNetFERS
PRINT '=== Test 5: Add error trigger to spAddGrossToNetFERS ==='
/*
-- Temporarily add this to spAddGrossToNetFERS:
IF @CaseId = 30070
BEGIN
    RAISERROR('TEST ERROR in spAddGrossToNetFERS for CaseId %d', 16, 1, @CaseId)
    RETURN -1
END
*/

-- 7. METHOD 6: Force error in spAddGrossToNetLI
PRINT '=== Test 6: Add error trigger to spAddGrossToNetLI ==='
/*
-- Temporarily add this to spAddGrossToNetLI:
IF @CaseId = 30070
BEGIN
    RAISERROR('TEST ERROR in spAddGrossToNetLI for CaseId %d', 16, 1, @CaseId)
    RETURN -1
END
*/

-- 8. Check error log results
PRINT ''
PRINT '=== Checking Error Log Results ==='
SELECT TOP 10
    LogId,
    Date,
    Process,
    CaseId,
    CASE 
        WHEN CaseId IS NULL THEN '❌ No CaseId'
        WHEN CaseId = @TestCaseId THEN '✓ Test CaseId captured'
        ELSE '✓ CaseId: ' + CAST(CaseId AS VARCHAR(20))
    END as CaseIdStatus,
    LEFT(ErrorMsg, 200) as ErrorMsg
FROM tblErrorLog 
WHERE Process = 'spCalcGrossToNet_main'
    AND Date >= DATEADD(MINUTE, -10, GETDATE())
ORDER BY Date DESC

-- 9. Clean up test data
DELETE FROM GrossToNet WHERE UserId = @TestLogin AND CaseId IN (@TestCaseId, 99999)
DELETE FROM LIChanges WHERE UserId = @TestLogin AND CaseId IN (@TestCaseId, 99999)

-- 10. SIMPLEST TEST: Add a direct error in spCalcGrossToNet_main
/*
-- Add this after the variable declarations in spCalcGrossToNet_main:
IF @CaseId = 30070
BEGIN
    SET @str = 'TEST ERROR: Forcing error for CaseId ' + CAST(@CaseId AS VARCHAR(20)) + 
               ' with CSRSRate=' + CAST(@CSRSRate AS VARCHAR(20)) + 
               ', FERSRate=' + CAST(@FERSRate AS VARCHAR(20))
    INSERT INTO tblErrorLog (CaseId, Process, ErrorMsg) 
    VALUES (@CaseId, 'spCalcGrossToNet_main', @str)
    RETURN -999  -- Special test return code
END
*/

-- Then simply run:
EXEC spCalcGrossToNet_main 
    @CaseId = 30070,
    @CSRSRate = 100,
    @CSRSTime = 0,
    @FERSRate = 100,
    @FERSTime = 0,
    @AvgSalPT = 0,
    @G2NCaseType = 0,
    @SurvivorCode = 0,
    @bVoluntaryOverride = 0,
    @bDebug = 0,
    @Login = 'TestUser'

-- Check if it logged
SELECT TOP 1 * FROM tblErrorLog 
WHERE CaseId = 30070 
  AND Process = 'spCalcGrossToNet_main'
  AND ErrorMsg LIKE '%TEST ERROR%'
ORDER BY Date DESC