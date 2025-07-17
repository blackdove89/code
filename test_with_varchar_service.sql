-- ================================================================
-- TEST spCalcGrossToNet_main WITH VARCHAR SERVICE FIELDS (udtSERVICE)
-- ================================================================

-- Now we know udtSERVICE is VARCHAR, so service time is stored as text
-- Need to handle conversion from text to decimal carefully

-- ================================================================

-- Step 1: Investigate the actual service time format
DECLARE @TestCaseId INT = 30070  -- Replace with your test CaseId

SELECT 
    'Service Time Format Investigation' AS DataType,
    CaseId,
    RunType,
    Method,
    bTriggered,
    CSRSMonthly,
    FERSMonthly,
    AverageSalary,
    -- Show the actual string format of service time
    TotalCSRSService AS CSRS_Service_Text,
    TotalFERSService AS FERS_Service_Text,
    LEN(TotalCSRSService) AS CSRS_Length,
    LEN(TotalFERSService) AS FERS_Length,
    -- Check if they're numeric
    CASE WHEN ISNUMERIC(TotalCSRSService) = 1 THEN 'NUMERIC' ELSE 'NOT NUMERIC' END AS CSRS_Numeric_Check,
    CASE WHEN ISNUMERIC(TotalFERSService) = 1 THEN 'NUMERIC' ELSE 'NOT NUMERIC' END AS FERS_Numeric_Check
FROM tblRunResults 
WHERE CaseId = @TestCaseId
ORDER BY RunType, Method

-- ================================================================

-- Step 2: Look at various service time formats across different cases
SELECT TOP 20
    'Service Time Format Examples' AS DataType,
    CaseId,
    TotalCSRSService,
    TotalFERSService,
    CASE WHEN ISNUMERIC(TotalCSRSService) = 1 THEN 'NUMERIC' ELSE 'TEXT FORMAT' END AS CSRS_Format,
    CASE WHEN ISNUMERIC(TotalFERSService) = 1 THEN 'NUMERIC' ELSE 'TEXT FORMAT' END AS FERS_Format
FROM tblRunResults 
WHERE bTriggered = 1 
    AND Method = 0
    AND TotalCSRSService IS NOT NULL 
    AND TotalFERSService IS NOT NULL
    AND TotalCSRSService <> ''
    AND TotalFERSService <> ''
GROUP BY CaseId, TotalCSRSService, TotalFERSService
ORDER BY CaseId

-- ================================================================

-- Step 3: Safe parameter extraction with varchar service handling

-- Function to convert service time text to decimal years
-- Common formats might be:
-- "25.5" = 25.5 years
-- "25/06/15" = 25 years, 6 months, 15 days
-- "30/00/00" = 30 years exactly

DECLARE @GoodCaseId INT = 30070  -- Use a case from the examples above
DECLARE @CSRSRate INT
DECLARE @CSRSTime DECIMAL(5,3) 
DECLARE @FERSRate INT
DECLARE @FERSTime DECIMAL(5,3)
DECLARE @AvgSalPT DECIMAL(12,2)
DECLARE @G2NCaseType TINYINT

SELECT 
    @CSRSRate = CSRSMonthly,
    @FERSRate = FERSMonthly,
    @AvgSalPT = ISNULL(AverageSalary, 60000),
    -- Safe conversion of service time from varchar to decimal
    @CSRSTime = CASE 
        WHEN TotalCSRSService IS NULL OR TotalCSRSService = '' THEN 0
        WHEN ISNUMERIC(TotalCSRSService) = 1 THEN CAST(TotalCSRSService AS DECIMAL(5,3))
        WHEN TotalCSRSService LIKE '%/%/%' THEN 
            -- Handle YY/MM/DD format: convert to decimal years
            CAST(LEFT(TotalCSRSService, CHARINDEX('/', TotalCSRSService) - 1) AS DECIMAL(5,3)) +
            CAST(SUBSTRING(TotalCSRSService, CHARINDEX('/', TotalCSRSService) + 1, 
                 CHARINDEX('/', TotalCSRSService, CHARINDEX('/', TotalCSRSService) + 1) - CHARINDEX('/', TotalCSRSService) - 1) AS DECIMAL(5,3)) / 12.0
        ELSE 0  -- Default if can't parse
    END,
    @FERSTime = CASE 
        WHEN TotalFERSService IS NULL OR TotalFERSService = '' THEN 0
        WHEN ISNUMERIC(TotalFERSService) = 1 THEN CAST(TotalFERSService AS DECIMAL(5,3))
        WHEN TotalFERSService LIKE '%/%/%' THEN 
            -- Handle YY/MM/DD format: convert to decimal years
            CAST(LEFT(TotalFERSService, CHARINDEX('/', TotalFERSService) - 1) AS DECIMAL(5,3)) +
            CAST(SUBSTRING(TotalFERSService, CHARINDEX('/', TotalFERSService) + 1, 
                 CHARINDEX('/', TotalFERSService, CHARINDEX('/', TotalFERSService) + 1) - CHARINDEX('/', TotalFERSService) - 1) AS DECIMAL(5,3)) / 12.0
        ELSE 0  -- Default if can't parse
    END,
    @G2NCaseType = CASE 
        WHEN CalcRetirementType = 'D' THEN 1  -- Disability
        WHEN CalcRetirementType = 'C' THEN 3  -- CSRS Disability  
        ELSE 0  -- Regular
    END
FROM tblRunResults 
WHERE CaseId = @GoodCaseId AND bTriggered = 1 AND Method = 0

-- Show what we extracted
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

-- Step 4: Test spCalcGrossToNet_main with properly converted parameters

IF @CSRSRate IS NOT NULL AND @FERSRate IS NOT NULL AND @AvgSalPT IS NOT NULL
BEGIN
    PRINT 'Testing spCalcGrossToNet_main with varchar service conversion...'
    PRINT 'CaseId: ' + CAST(@GoodCaseId AS VARCHAR(20))
    PRINT 'CSRS: $' + CAST(@CSRSRate AS VARCHAR) + '/month (' + CAST(@CSRSTime AS VARCHAR) + ' years)'
    PRINT 'FERS: $' + CAST(@FERSRate AS VARCHAR) + '/month (' + CAST(@FERSTime AS VARCHAR) + ' years)'
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
            @bDebug = 2,
            @Login = 'TEST_USER'
            
        PRINT 'SUCCESS: spCalcGrossToNet_main completed successfully'
    END TRY
    BEGIN CATCH
        PRINT 'ERROR: ' + ERROR_MESSAGE()
        PRINT 'Error Number: ' + CAST(ERROR_NUMBER() AS VARCHAR)
        PRINT 'Error State: ' + CAST(ERROR_STATE() AS VARCHAR)
        PRINT 'Error Line: ' + CAST(ERROR_LINE() AS VARCHAR)
    END CATCH
END
ELSE
BEGIN
    PRINT 'SKIPPED: Could not extract valid parameters'
    PRINT 'CSRSRate: ' + ISNULL(CAST(@CSRSRate AS VARCHAR), 'NULL')
    PRINT 'FERSRate: ' + ISNULL(CAST(@FERSRate AS VARCHAR), 'NULL')
    PRINT 'AvgSalPT: ' + ISNULL(CAST(@AvgSalPT AS VARCHAR), 'NULL')
END

-- ================================================================

-- Step 5: Alternative test with simple hardcoded values

PRINT ''
PRINT 'Alternative test with hardcoded safe values...'

BEGIN TRY
    EXEC spCalcGrossToNet_main 
        @CaseId = @GoodCaseId,
        @CSRSRate = 2500,        -- $2500/month
        @CSRSTime = 25.0,        -- 25 years
        @FERSRate = 1800,        -- $1800/month
        @FERSTime = 15.0,        -- 15 years
        @AvgSalPT = 75000.00,    -- $75,000/year
        @G2NCaseType = 0,        -- Regular case
        @SurvivorCode = 0,       -- No survivor
        @bVoluntaryOverride = 0,
        @bDebug = 2,
        @Login = 'TEST_SIMPLE'
        
    PRINT 'SUCCESS: Hardcoded test completed successfully'
END TRY
BEGIN CATCH
    PRINT 'ERROR in hardcoded test: ' + ERROR_MESSAGE()
    PRINT 'This suggests an issue with the procedure itself'
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
        WHEN CaseId = @GoodCaseId THEN '✓ Correct CaseId Logged'
        WHEN CaseId IS NULL THEN '? NULL CaseId (System Error or Original Version)'
        ELSE '? Different CaseId: ' + CAST(CaseId AS VARCHAR)
    END AS CaseIdStatus
FROM tblErrorLog 
WHERE Process = 'spCalcGrossToNet_main'
    AND Date >= DATEADD(minute, -10, GETDATE())
ORDER BY Date DESC

-- ================================================================

-- Step 7: Force an error to test CaseId logging

PRINT ''
PRINT 'Testing CaseId error logging by forcing a table rename error...'

-- Temporarily rename a table that the procedure needs
EXEC sp_rename 'rtblLIPremiums', 'rtblLIPremiums_backup'

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
EXEC sp_rename 'rtblLIPremiums_backup', 'rtblLIPremiums'

-- Check if the error was logged with the correct CaseId
SELECT 
    'Forced Error Test Results' AS CheckType,
    Date,
    CaseId,
    Process,
    LEFT(ErrorMsg, 200) AS ErrorMsg,
    CASE 
        WHEN CaseId = @GoodCaseId THEN '✅ SUCCESS: CaseId logged correctly (FIXED VERSION)'
        WHEN CaseId IS NULL THEN '❌ FAILURE: CaseId is NULL (ORIGINAL VERSION)'
        ELSE '❓ UNEXPECTED: Different CaseId = ' + CAST(CaseId AS VARCHAR)
    END AS TestResult
FROM tblErrorLog 
WHERE Process = 'spCalcGrossToNet_main'
    AND Date >= DATEADD(minute, -2, GETDATE())
ORDER BY Date DESC

-- ================================================================

-- Step 8: Service time conversion helper for future reference

-- Create a helper function concept for service time conversion
SELECT 
    'Service Time Conversion Examples' AS Info,
    TotalCSRSService AS Original_Text,
    CASE 
        WHEN TotalCSRSService IS NULL OR TotalCSRSService = '' THEN 0
        WHEN ISNUMERIC(TotalCSRSService) = 1 THEN CAST(TotalCSRSService AS DECIMAL(5,3))
        WHEN TotalCSRSService LIKE '%/%/%' THEN 
            -- Convert YY/MM/DD to decimal years
            CAST(LEFT(TotalCSRSService, CHARINDEX('/', TotalCSRSService) - 1) AS DECIMAL(5,3)) +
            CAST(SUBSTRING(TotalCSRSService, CHARINDEX('/', TotalCSRSService) + 1, 
                 CHARINDEX('/', TotalCSRSService, CHARINDEX('/', TotalCSRSService) + 1) - CHARINDEX('/', TotalCSRSService) - 1) AS DECIMAL(5,3)) / 12.0
        ELSE 0
    END AS Converted_Years
FROM tblRunResults 
WHERE TotalCSRSService IS NOT NULL 
    AND TotalCSRSService <> ''
    AND bTriggered = 1
    AND Method = 0
GROUP BY TotalCSRSService
ORDER BY TotalCSRSService

-- ================================================================

PRINT ''
PRINT 'Test completed!'
PRINT 'Key findings:'
PRINT '1. udtSERVICE is VARCHAR - service time stored as text'
PRINT '2. Need to convert text service time to decimal years'
PRINT '3. Check error logs for CaseId vs NULL to verify fix'
PRINT '4. Fixed version should show actual CaseId in error logs'