-- ================================================================
-- CORRECT TEST FOR spCalcGrossToNet_main WITH ACTUAL TABLE SCHEMA
-- ================================================================

-- Now we know the correct data types:
-- CSRSMonthly: [int] NOT NULL
-- FERSMonthly: [int] NOT NULL  
-- AverageSalary: [decimal](9, 2) NULL
-- TotalCSRSService: [dbo].[udtSERVICE] NULL (custom UDT)
-- TotalFERSService: [dbo].[udtSERVICE] NULL (custom UDT)

-- ================================================================

-- Step 1: Investigate the udtSERVICE user-defined type
SELECT 
    'udtSERVICE Type Information' AS Info,
    t.name AS TypeName,
    t.system_type_id,
    t.user_type_id,
    t.max_length,
    t.precision,
    t.scale,
    st.name AS BaseTypeName
FROM sys.types t
    LEFT JOIN sys.types st ON t.system_type_id = st.system_type_id AND st.user_type_id = st.system_type_id
WHERE t.name = 'udtSERVICE'

-- ================================================================

-- Step 2: Look at actual data to understand the udtSERVICE format
DECLARE @TestCaseId INT = 30070  -- Replace with your test CaseId

SELECT 
    'Actual Data Investigation' AS DataType,
    CaseId,
    RunType,
    Method,
    bTriggered,
    CSRSMonthly,           -- int
    FERSMonthly,           -- int
    AverageSalary,         -- decimal(9,2)
    TotalCSRSService,      -- udtSERVICE - let's see what this looks like
    TotalFERSService,      -- udtSERVICE - let's see what this looks like
    -- Convert udtSERVICE to see its actual value
    CAST(TotalCSRSService AS VARCHAR(20)) AS CSRS_Service_String,
    CAST(TotalFERSService AS VARCHAR(20)) AS FERS_Service_String,
    TotalComputationService,
    CalcRetirementType
FROM tblRunResults 
WHERE CaseId = @TestCaseId
ORDER BY RunType, Method

-- ================================================================

-- Step 3: Find a case with good data for testing
SELECT TOP 10
    'Cases with Complete Data' AS DataType,
    rr.CaseId,
    cl.Claim,
    rr.RunType,
    rr.Method,
    rr.bTriggered,
    rr.CSRSMonthly,
    rr.FERSMonthly,
    rr.AverageSalary,
    CAST(rr.TotalCSRSService AS VARCHAR(20)) AS CSRS_Service,
    CAST(rr.TotalFERSService AS VARCHAR(20)) AS FERS_Service
FROM tblRunResults rr
    JOIN tblCases c ON rr.CaseId = c.CaseId
    JOIN tblClaim cl ON c.ClaimId = cl.ClaimId
WHERE rr.bTriggered = 1
    AND rr.Method = 0
    AND rr.CSRSMonthly > 0
    AND rr.FERSMonthly > 0
    AND rr.AverageSalary > 0
    AND rr.TotalCSRSService IS NOT NULL
    AND rr.TotalFERSService IS NOT NULL
ORDER BY rr.CaseId DESC

-- ================================================================

-- Step 4: Test spCalcGrossToNet_main with correct data types

-- Use a known good CaseId from the query above
DECLARE @GoodCaseId INT = 30070  -- Replace with a CaseId that has good data

DECLARE @CSRSRate INT
DECLARE @CSRSTime DECIMAL(5,3)
DECLARE @FERSRate INT
DECLARE @FERSTime DECIMAL(5,3)
DECLARE @AvgSalPT DECIMAL(12,2)
DECLARE @G2NCaseType TINYINT

-- Extract parameters with proper handling of udtSERVICE
SELECT 
    @CSRSRate = rr.CSRSMonthly,                    -- Already INT
    @FERSRate = rr.FERSMonthly,                    -- Already INT
    @AvgSalPT = ISNULL(rr.AverageSalary, 60000),   -- DECIMAL(9,2) -> DECIMAL(12,2)
    -- Convert udtSERVICE to decimal (assuming it represents years with decimals)
    @CSRSTime = CASE 
        WHEN rr.TotalCSRSService IS NOT NULL 
        THEN CAST(rr.TotalCSRSService AS DECIMAL(5,3))
        ELSE 0
    END,
    @FERSTime = CASE 
        WHEN rr.TotalFERSService IS NOT NULL 
        THEN CAST(rr.TotalFERSService AS DECIMAL(5,3))
        ELSE 0
    END,
    @G2NCaseType = CASE 
        WHEN rr.CalcRetirementType = 'D' THEN 1  -- Disability
        WHEN rr.CalcRetirementType = 'C' THEN 3  -- CSRS Disability
        ELSE 0  -- Regular
    END
FROM tblRunResults rr
WHERE rr.CaseId = @GoodCaseId
    AND rr.bTriggered = 1
    AND rr.Method = 0

-- Display the extracted parameters
SELECT 
    'Extracted Parameters' AS Info,
    @GoodCaseId AS CaseId,
    @CSRSRate AS CSRSRate_Monthly,
    @CSRSTime AS CSRSTime_Years,
    @FERSRate AS FERSRate_Monthly,
    @FERSTime AS FERSTime_Years,
    @AvgSalPT AS AvgSalary_Annual,
    @G2NCaseType AS G2NCaseType

-- ================================================================

-- Step 5: Execute spCalcGrossToNet_main

IF @CSRSRate IS NOT NULL AND @FERSRate IS NOT NULL
BEGIN
    PRINT 'Testing spCalcGrossToNet_main with CaseId: ' + CAST(@GoodCaseId AS VARCHAR(20))
    PRINT 'CSRS: $' + CAST(@CSRSRate AS VARCHAR) + '/month, FERS: $' + CAST(@FERSRate AS VARCHAR) + '/month'
    PRINT 'Avg Salary: $' + CAST(@AvgSalPT AS VARCHAR) + '/year'
    
    BEGIN TRY
        EXEC spCalcGrossToNet_main 
            @CaseId = @GoodCaseId,
            @CSRSRate = @CSRSRate,
            @CSRSTime = @CSRSTime,
            @FERSRate = @FERSRate,
            @FERSTime = @FERSTime,
            @AvgSalPT = @AvgSalPT,
            @G2NCaseType = @G2NCaseType,
            @SurvivorCode = 0,
            @bVoluntaryOverride = 0,
            @bDebug = 2,  -- Enable debug output
            @Login = 'TEST_USER'
            
        PRINT 'SUCCESS: spCalcGrossToNet_main completed successfully'
    END TRY
    BEGIN CATCH
        PRINT 'ERROR: ' + ERROR_MESSAGE()
        PRINT 'Error Number: ' + CAST(ERROR_NUMBER() AS VARCHAR)
        PRINT 'Error Line: ' + CAST(ERROR_LINE() AS VARCHAR)
    END CATCH
END
ELSE
BEGIN
    PRINT 'SKIPPED: No valid data found for CaseId ' + CAST(@GoodCaseId AS VARCHAR)
    PRINT 'Available data:'
    PRINT '  CSRSRate: ' + ISNULL(CAST(@CSRSRate AS VARCHAR), 'NULL')
    PRINT '  FERSRate: ' + ISNULL(CAST(@FERSRate AS VARCHAR), 'NULL')
    PRINT '  AvgSalPT: ' + ISNULL(CAST(@AvgSalPT AS VARCHAR), 'NULL')
END

-- ================================================================

-- Step 6: Check for any errors logged
SELECT 
    'Error Log Results' AS CheckType,
    Date,
    CaseId,
    Process,
    LEFT(ErrorMsg, 250) AS ErrorMsg,
    CASE 
        WHEN CaseId = @GoodCaseId THEN '✓ Correct CaseId Logged'
        WHEN CaseId IS NULL THEN '? NULL CaseId (System Error)'
        ELSE '? Different CaseId: ' + CAST(CaseId AS VARCHAR)
    END AS CaseIdStatus
FROM tblErrorLog 
WHERE Process = 'spCalcGrossToNet_main'
    AND Date >= DATEADD(minute, -5, GETDATE())
ORDER BY Date DESC

-- ================================================================

-- Step 7: Force an error to test CaseId error logging

PRINT ''
PRINT 'Testing error logging by forcing a database error...'

-- Temporarily drop a constraint or rename a table to force an error
EXEC sp_rename 'GrossToNet', 'GrossToNet_backup'

BEGIN TRY
    EXEC spCalcGrossToNet_main 
        @CaseId = @GoodCaseId,
        @CSRSRate = 2500,
        @CSRSTime = 25.0,
        @FERSRate = 1800,
        @FERSTime = 15.0,
        @AvgSalPT = 75000.00,
        @G2NCaseType = 0,
        @SurvivorCode = 0,
        @bVoluntaryOverride = 0,
        @bDebug = 2,
        @Login = 'TEST_ERROR'
END TRY
BEGIN CATCH
    PRINT 'Expected error occurred: ' + ERROR_MESSAGE()
END CATCH

-- Restore the table
EXEC sp_rename 'GrossToNet_backup', 'GrossToNet'

-- Check if the error was logged with the CaseId
SELECT 
    'Forced Error Test' AS CheckType,
    Date,
    CaseId,
    Process,
    LEFT(ErrorMsg, 200) AS ErrorMsg,
    CASE 
        WHEN CaseId = @GoodCaseId THEN '✅ CaseId logged correctly (FIXED VERSION)'
        WHEN CaseId IS NULL THEN '❌ CaseId is NULL (ORIGINAL VERSION)'
        ELSE '❓ Unexpected CaseId: ' + CAST(CaseId AS VARCHAR)
    END AS TestResult
FROM tblErrorLog 
WHERE Process = 'spCalcGrossToNet_main'
    AND Date >= DATEADD(minute, -2, GETDATE())
ORDER BY Date DESC

-- ================================================================

-- Step 8: Simple test with hardcoded values (if data extraction fails)

PRINT ''
PRINT 'Backup test with simple hardcoded values...'

BEGIN TRY
    EXEC spCalcGrossToNet_main 
        @CaseId = @GoodCaseId,      -- Use actual CaseId
        @CSRSRate = 2500,           -- $2500/month
        @CSRSTime = 25.0,           -- 25 years
        @FERSRate = 1800,           -- $1800/month
        @FERSTime = 15.0,           -- 15 years
        @AvgSalPT = 75000.00,       -- $75,000/year
        @G2NCaseType = 0,           -- Regular case
        @SurvivorCode = 0,          -- No survivor
        @bVoluntaryOverride = 0,    -- No override
        @bDebug = 2,                -- Enable debug
        @Login = 'TEST_SIMPLE'
        
    PRINT 'SUCCESS: Simple test completed'
END TRY
BEGIN CATCH
    PRINT 'ERROR in simple test: ' + ERROR_MESSAGE()
END CATCH

-- ================================================================

-- Step 9: Check any data created by the procedure

-- Check if GrossToNet data was created
SELECT 
    'GrossToNet Data Created' AS DataType,
    COUNT(*) AS RecordCount
FROM GrossToNet 
WHERE CaseId = @GoodCaseId 
    AND UserId IN ('TEST_USER', 'TEST_ERROR', 'TEST_SIMPLE')

-- Show sample GrossToNet records if created
SELECT TOP 5
    'Sample GrossToNet Records' AS DataType,
    EffectiveDate,
    Age,
    TotalGross,
    Net,
    Comment
FROM GrossToNet 
WHERE CaseId = @GoodCaseId 
    AND UserId IN ('TEST_USER', 'TEST_ERROR', 'TEST_SIMPLE')
ORDER BY EffectiveDate

-- ================================================================

-- Step 10: Cleanup (optional)

/*
-- Uncomment to clean up test data
DELETE FROM GrossToNet WHERE CaseId = @GoodCaseId AND UserId IN ('TEST_USER', 'TEST_ERROR', 'TEST_SIMPLE')
DELETE FROM LIChanges WHERE CaseId = @GoodCaseId AND UserId IN ('TEST_USER', 'TEST_ERROR', 'TEST_SIMPLE')
PRINT 'Test data cleaned up'
*/

PRINT ''
PRINT 'Test completed! Summary:'
PRINT '1. Check if spCalcGrossToNet_main runs successfully'
PRINT '2. Verify that errors are logged with the correct CaseId'
PRINT '3. Compare NULL vs actual CaseId in error logs to confirm fix'