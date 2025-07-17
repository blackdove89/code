-- ================================================================
-- FIX TYPE CONVERSION ISSUES FOR spCalcGrossToNet_main TEST
-- ================================================================

-- Step 1: Investigate the actual data types and values in tblRunResults
DECLARE @TestCaseId INT = 30070  -- Replace with your test CaseId

-- Check what the actual data looks like and identify problematic values
SELECT 
    'Data Type Investigation' AS CheckType,
    CaseId,
    RunType,
    Method,
    bTriggered,
    
    -- Check CSRSMonthly
    CSRSMonthly,
    CASE 
        WHEN CSRSMonthly IS NULL THEN 'NULL'
        WHEN ISNUMERIC(CSRSMonthly) = 1 THEN 'NUMERIC'
        ELSE 'NON-NUMERIC: [' + CSRSMonthly + ']'
    END AS CSRSMonthly_Status,
    
    -- Check FERSMonthly  
    FERSMonthly,
    CASE 
        WHEN FERSMonthly IS NULL THEN 'NULL'
        WHEN ISNUMERIC(FERSMonthly) = 1 THEN 'NUMERIC'
        ELSE 'NON-NUMERIC: [' + FERSMonthly + ']'
    END AS FERSMonthly_Status,
    
    -- Check AverageSalary
    AverageSalary,
    CASE 
        WHEN AverageSalary IS NULL THEN 'NULL'
        WHEN ISNUMERIC(AverageSalary) = 1 THEN 'NUMERIC'
        ELSE 'NON-NUMERIC: [' + CAST(AverageSalary AS VARCHAR(50)) + ']'
    END AS AverageSalary_Status,
    
    -- Check Service fields
    TotalCSRSService,
    TotalFERSService
FROM tblRunResults 
WHERE CaseId = @TestCaseId
ORDER BY RunType, Method

-- ================================================================

-- Step 2: Find cases with clean numeric data
SELECT TOP 10
    'Cases with Clean Data' AS DataType,
    rr.CaseId,
    cl.Claim,
    rr.RunType,
    rr.Method,
    rr.bTriggered,
    rr.CSRSMonthly,
    rr.FERSMonthly,
    rr.AverageSalary,
    rr.TotalCSRSService,
    rr.TotalFERSService
FROM tblRunResults rr
    JOIN tblCases c ON rr.CaseId = c.CaseId
    JOIN tblClaim cl ON c.ClaimId = cl.ClaimId
WHERE rr.bTriggered = 1
    AND rr.Method = 0
    -- Only include records where all key fields are numeric
    AND ISNUMERIC(ISNULL(rr.CSRSMonthly, '0')) = 1
    AND ISNUMERIC(ISNULL(rr.FERSMonthly, '0')) = 1
    AND ISNUMERIC(ISNULL(CAST(rr.AverageSalary AS VARCHAR), '0')) = 1
    AND rr.CSRSMonthly <> ''
    AND rr.FERSMonthly <> ''
ORDER BY rr.CaseId DESC

-- ================================================================

-- Step 3: Safe parameter extraction with proper type conversion
DECLARE @SafeTestCaseId INT = 30070  -- Use a CaseId from the clean data above

DECLARE @CSRSRate INT
DECLARE @CSRSTime DECIMAL(5,3)
DECLARE @FERSRate INT
DECLARE @FERSTime DECIMAL(5,3)
DECLARE @AvgSalPT DECIMAL(12,2)
DECLARE @G2NCaseType TINYINT

-- Safe extraction with TRY_CONVERT (SQL Server 2012+) or CASE statements
SELECT 
    @CSRSRate = CASE 
        WHEN ISNUMERIC(ISNULL(rr.CSRSMonthly, '0')) = 1 
        THEN CAST(ROUND(CAST(rr.CSRSMonthly AS DECIMAL(12,2)), 0) AS INT)
        ELSE 0 
    END,
    @FERSRate = CASE 
        WHEN ISNUMERIC(ISNULL(rr.FERSMonthly, '0')) = 1 
        THEN CAST(ROUND(CAST(rr.FERSMonthly AS DECIMAL(12,2)), 0) AS INT)
        ELSE 0 
    END,
    @AvgSalPT = CASE 
        WHEN ISNUMERIC(ISNULL(CAST(rr.AverageSalary AS VARCHAR), '0')) = 1 
        THEN CAST(rr.AverageSalary AS DECIMAL(12,2))
        ELSE 60000.00 
    END,
    @CSRSTime = ISNULL(rr.TotalCSRSService, 0),
    @FERSTime = ISNULL(rr.TotalFERSService, 0),
    @G2NCaseType = 0  -- Default to regular case
FROM tblRunResults rr
WHERE rr.CaseId = @SafeTestCaseId
    AND rr.bTriggered = 1
    AND rr.Method = 0

-- Display the safely converted parameters
SELECT 
    'Safely Converted Parameters' AS Info,
    @SafeTestCaseId AS CaseId,
    @CSRSRate AS CSRSRate,
    @CSRSTime AS CSRSTime,
    @FERSRate AS FERSRate,
    @FERSTime AS FERSTime,
    @AvgSalPT AS AvgSalPT,
    @G2NCaseType AS G2NCaseType

-- ================================================================

-- Step 4: Test spCalcGrossToNet_main with safe parameters

IF @CSRSRate IS NOT NULL AND @FERSRate IS NOT NULL AND @AvgSalPT IS NOT NULL
BEGIN
    PRINT 'Testing spCalcGrossToNet_main with safely converted parameters...'
    
    BEGIN TRY
        EXEC spCalcGrossToNet_main 
            @CaseId = @SafeTestCaseId,
            @CSRSRate = @CSRSRate,
            @CSRSTime = @CSRSTime,
            @FERSRate = @FERSRate,
            @FERSTime = @FERSTime,
            @AvgSalPT = @AvgSalPT,
            @G2NCaseType = @G2NCaseType,
            @SurvivorCode = 0,
            @bVoluntaryOverride = 0,
            @bDebug = 2,
            @Login = 'TEST_USER'
            
        PRINT 'SUCCESS: spCalcGrossToNet_main completed without errors'
    END TRY
    BEGIN CATCH
        PRINT 'ERROR in spCalcGrossToNet_main: ' + ERROR_MESSAGE()
        PRINT 'Error Number: ' + CAST(ERROR_NUMBER() AS VARCHAR)
        PRINT 'Error Line: ' + CAST(ERROR_LINE() AS VARCHAR)
    END CATCH
END
ELSE
BEGIN
    PRINT 'SKIPPED: Could not safely convert all required parameters'
    PRINT 'CSRSRate: ' + ISNULL(CAST(@CSRSRate AS VARCHAR), 'NULL')
    PRINT 'FERSRate: ' + ISNULL(CAST(@FERSRate AS VARCHAR), 'NULL') 
    PRINT 'AvgSalPT: ' + ISNULL(CAST(@AvgSalPT AS VARCHAR), 'NULL')
END

-- ================================================================

-- Step 5: Alternative test with hardcoded safe values

PRINT ''
PRINT 'Alternative test with known safe values...'

BEGIN TRY
    EXEC spCalcGrossToNet_main 
        @CaseId = @SafeTestCaseId,
        @CSRSRate = 2500,        -- Safe integer
        @CSRSTime = 25.0,        -- Safe decimal
        @FERSRate = 1800,        -- Safe integer
        @FERSTime = 15.0,        -- Safe decimal
        @AvgSalPT = 75000.00,    -- Safe decimal
        @G2NCaseType = 0,        -- Safe tinyint
        @SurvivorCode = 0,       -- Safe tinyint
        @bVoluntaryOverride = 0, -- Safe bit
        @bDebug = 2,             -- Safe tinyint
        @Login = 'TEST_USER'     -- Safe varchar
        
    PRINT 'SUCCESS: Alternative test completed without errors'
END TRY
BEGIN CATCH
    PRINT 'ERROR in alternative test: ' + ERROR_MESSAGE()
    PRINT 'This suggests an issue with the procedure itself, not parameter conversion'
END CATCH

-- ================================================================

-- Step 6: Check for errors logged with CaseId

SELECT 
    'Error Log Check' AS CheckType,
    Date,
    CaseId,
    Process,
    LEFT(ErrorMsg, 250) AS ErrorMsg,
    CASE 
        WHEN CaseId = @SafeTestCaseId THEN '✓ Correct CaseId'
        WHEN CaseId IS NULL THEN '? NULL CaseId'
        ELSE '? Different CaseId'
    END AS CaseIdStatus
FROM tblErrorLog 
WHERE Process = 'spCalcGrossToNet_main'
    AND Date >= DATEADD(minute, -10, GETDATE())
ORDER BY Date DESC

-- ================================================================

-- Step 7: Force an error to test CaseId logging (if previous tests worked)

PRINT ''
PRINT 'Testing error logging by forcing an invalid table access...'

-- Temporarily rename a required table
EXEC sp_rename 'rtblLIPremiums', 'rtblLIPremiums_backup'

BEGIN TRY
    EXEC spCalcGrossToNet_main 
        @CaseId = @SafeTestCaseId,
        @CSRSRate = 2500,
        @CSRSTime = 25.0,
        @FERSRate = 1800,
        @FERSTime = 15.0,
        @AvgSalPT = 75000.00,
        @G2NCaseType = 0,
        @SurvivorCode = 0,
        @bVoluntaryOverride = 0,
        @bDebug = 2,
        @Login = 'TEST_USER'
END TRY
BEGIN CATCH
    PRINT 'Expected error occurred: ' + ERROR_MESSAGE()
END CATCH

-- Restore the table
EXEC sp_rename 'rtblLIPremiums_backup', 'rtblLIPremiums'

-- Check if error was logged with CaseId
SELECT 
    'Forced Error Results' AS CheckType,
    Date,
    CaseId,
    Process,
    LEFT(ErrorMsg, 200) AS ErrorMsg,
    CASE 
        WHEN CaseId = @SafeTestCaseId THEN '✓ CaseId Logged Correctly'
        WHEN CaseId IS NULL THEN '✗ CaseId is NULL (unfixed version)'
        ELSE '? Wrong CaseId: ' + CAST(CaseId AS VARCHAR)
    END AS Result
FROM tblErrorLog 
WHERE Process = 'spCalcGrossToNet_main'
    AND Date >= DATEADD(minute, -2, GETDATE())
ORDER BY Date DESC

-- ================================================================

-- Step 8: Common problematic values investigation

-- Check for common non-numeric values that cause conversion errors
SELECT 
    'Common Problematic Values' AS Issue,
    CSRSMonthly,
    COUNT(*) AS Occurrences
FROM tblRunResults 
WHERE ISNUMERIC(ISNULL(CSRSMonthly, '0')) = 0
    AND CSRSMonthly IS NOT NULL
    AND CSRSMonthly <> ''
GROUP BY CSRSMonthly
ORDER BY COUNT(*) DESC

UNION ALL

SELECT 
    'FERSMonthly Issues' AS Issue,
    FERSMonthly,
    COUNT(*) AS Occurrences
FROM tblRunResults 
WHERE ISNUMERIC(ISNULL(FERSMonthly, '0')) = 0
    AND FERSMonthly IS NOT NULL
    AND FERSMonthly <> ''
GROUP BY FERSMonthly
ORDER BY COUNT(*) DESC

-- ================================================================

PRINT ''
PRINT 'Type conversion test completed.'
PRINT 'Check the results above to see:'
PRINT '1. Which values are causing conversion errors'
PRINT '2. Whether the procedure runs successfully with safe values'
PRINT '3. Whether CaseId is properly logged in errors'