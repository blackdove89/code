-- ========================================
-- TEST ERROR LOGGING FOR CASES WITHOUT RUNRESULTS
-- ========================================

-- 1. Check what cases have status 300/700 but no RunResults
PRINT '=== Cases with Status 300/700 but Missing Data ==='
SELECT TOP 10
    a.CaseId,
    cl.Claim,
    b.Abbrev as StatusCode,
    CASE WHEN rr.CaseId IS NULL THEN 'No RunResults' ELSE 'Has RunResults' END as RunResultStatus,
    CASE WHEN fd.CaseId IS NULL THEN 'No FERSData' ELSE 'Has FERSData' END as FERSDataStatus,
    CASE WHEN gn.CaseId IS NULL THEN 'No GrossToNet' ELSE 'Has GrossToNet' END as GrossToNetStatus
FROM tblCases a
    JOIN tblClaim cl ON a.ClaimId = cl.ClaimId
    JOIN rtblCode b ON a.StatusCodeId = b.CodeId
    LEFT JOIN tblRunResults rr ON a.CaseId = rr.CaseId AND rr.Method = 0 AND rr.bTriggered = 1
    LEFT JOIN tblFERSData fd ON a.CaseId = fd.CaseId
    LEFT JOIN tblGrossToNet gn ON a.CaseId = gn.CaseId
WHERE b.Abbrev IN ('300', '700')
ORDER BY a.CaseId DESC

-- 2. OPTION A: Create minimal data to make case processable, then force error
DECLARE @TestCaseId INT = 30070  -- Your test case
DECLARE @TestClaim VARCHAR(9)

SELECT @TestClaim = cl.Claim
FROM tblCases a
    JOIN tblClaim cl ON a.ClaimId = cl.ClaimId
WHERE a.CaseId = @TestCaseId

PRINT 'Test CaseId: ' + CAST(@TestCaseId AS VARCHAR(20))
PRINT 'Test Claim: ' + ISNULL(@TestClaim, 'Not found')

-- Create minimal RunResults record to pass initial validation
IF NOT EXISTS (SELECT 1 FROM tblRunResults WHERE CaseId = @TestCaseId AND Method = 0 AND bTriggered = 1)
BEGIN
    PRINT 'Creating temporary RunResults record...'
    
    INSERT INTO tblRunResults (
        CaseId, 
        Method, 
        bTriggered, 
        TotalComputationService,
        CreatedBy,
        CreatedDate
    )
    VALUES (
        @TestCaseId,
        0,  -- Method
        1,  -- bTriggered
        '10/05/15',  -- Some valid service time
        'TestUser',
        GETDATE()
    )
END

-- 3. OPTION B: Force error in spGenerateMFData for cases that will be skipped
/*
ALTER PROCEDURE [dbo].[spGenerateMFData]
    -- parameters...
AS
BEGIN
    -- ... existing code ...
    
    -- In the main loop, modify the section where cases are skipped:
    IF LEN(@sReason) > 0
    BEGIN
        SET @nMissingData = @nMissingData + 1
        SET @sErrorMsg = @sErrorMsg + @sCR + @ClaimNumber + '  ' + @sReason
        
        -- ADD THIS: Force an error for testing
        IF @nCaseId = 30070  -- Your test case
        BEGIN
            RAISERROR('TEST ERROR: Case %d skipped due to: %s', 16, 1, @nCaseId, @sReason)
        END
    END
    
    -- ... rest of code ...
END
*/

-- 4. OPTION C: Test with a different approach - modify spGetCSAData
/*
-- Since your case might not have RunResults, it won't reach spGetCSAData
-- But you can test by adding temporary data first, then forcing error there
ALTER PROCEDURE [dbo].[spGetCSAData]
    @CaseId INT,
    @Data VARCHAR(2000) OUTPUT,
    @bDebug BIT = 0
AS
BEGIN
    -- Force error for testing
    IF @CaseId = 30070
    BEGIN
        RAISERROR('TEST ERROR in spGetCSAData for CaseId %d', 16, 1, @CaseId)
        RETURN -1
    END
    
    -- ... existing code ...
END
*/

-- 5. SIMPLEST TEST: Add error in the skipping logic
-- Add this to spGenerateMFData where it checks for missing data:
/*
-- Find this section in spGenerateMFData:
IF NOT EXISTS(SELECT 1 FROM tblRunResults WHERE CaseId = @nCaseId and Method = 0 and bTriggered = 1)
    SET @sReason = 'No runs triggered.'

-- Add right after:
IF @nCaseId = 30070 AND @sReason = 'No runs triggered.'
BEGIN
    -- Force an error that will be caught and logged with CaseId
    RAISERROR('TEST ERROR: CaseId %d has no runs triggered', 16, 1, @nCaseId)
END
*/

-- 6. Run the test
PRINT '=== Running spProcessCases ==='
EXEC spProcessCases 
    @bTestMF = 1,
    @bStatusUpdate = 0,
    @bSendMail = 0,
    @bSendFile = 0,
    @bDebug = 1  -- Enable debug to see what's happening

-- 7. Check error log
SELECT TOP 10
    LogId,
    Date,
    Process,
    CaseId,
    CASE 
        WHEN CaseId IS NULL THEN 'NULL'
        ELSE CAST(CaseId AS VARCHAR(20))
    END as CaseIdValue,
    LEFT(ErrorMsg, 200) as ErrorMsg
FROM tblErrorLog 
WHERE Date >= DATEADD(MINUTE, -5, GETDATE())
ORDER BY Date DESC

-- 8. Clean up test data if you created any
/*
DELETE FROM tblRunResults 
WHERE CaseId = @TestCaseId 
  AND CreatedBy = 'TestUser' 
  AND CreatedDate >= DATEADD(MINUTE, -10, GETDATE())
*/

-- 9. Alternative: Check what happens to skipped cases
-- Run with debug to see the skipped cases message
EXEC spGenerateMFData 
    @ClaimNumber = '',
    @Filename = 'E:\FACESData\MFData\2025\07\test',
    @bTest = 1,
    @bUpdate = 0,
    @bSendMail = 0,
    @bDebug = 1,
    @CurrentCaseId = NULL