-- ========================================
-- TEST SCRIPT FOR REISSUE ERROR TRACKING
-- ========================================

-- 1. First, check if there are any reissue cases to process
SELECT TOP 10
    a.CaseId,
    cl.Claim,
    b.Abbrev as StatusCode,
    c.Abbrev as RetirementType,
    'Reissue Case' as CaseType
FROM tblCases a
    JOIN tblClaim cl ON a.ClaimId = cl.ClaimId
    JOIN rtblCode b ON a.StatusCodeId = b.CodeId
    JOIN vwCaseServiceSummary d ON a.CaseId = d.CaseId
    LEFT JOIN rtblCode c ON d.RetirementTypeId = c.CodeId
    JOIN tblCaseRelation e ON a.CaseId = e.GeneratedCaseId
    JOIN tblCases p ON e.OriginalCaseid = p.CaseId
    JOIN rtblCode q ON p.StatusCodeId = q.CodeId 
WHERE b.Abbrev = '500' AND q.Abbrev = '402'

-- 2. To test error in spGenerateReissueData, temporarily add this at the beginning:
/*
ALTER PROCEDURE [dbo].[spGenerateReissueData]
    @Filename VARCHAR(100),
    @bUpdate TINYINT = 0,
    @bSendMail BIT = 0,
    @bDebug TINYINT = 0,
    @CurrentCaseId INT = NULL OUTPUT
AS
BEGIN
    -- TEMPORARY TEST CODE - Force error for testing
    IF @Filename LIKE '%R0717%'  -- Today's reissue file
    BEGIN
        SET @CurrentCaseId = 88888  -- Test CaseId
        RAISERROR('TEST ERROR: Testing reissue error logging with CaseId', 16, 1)
        RETURN -1
    END
    
    -- Rest of your procedure...
END
*/

-- 3. Run the reissue process
PRINT '=== Testing spProcessReissueCases ==='
EXEC spProcessReissueCases 
    @bStatusUpdate = 0,
    @bSendMail = 0,
    @bSendFile = 0,
    @bDebug = 0

-- 4. Check error logs
PRINT '=== Checking Error Logs ==='
SELECT TOP 10
    LogId,
    Date,
    Process,
    CaseId,
    CASE 
        WHEN CaseId IS NULL THEN 'NULL - No CaseId captured'
        ELSE 'CaseId: ' + CAST(CaseId AS VARCHAR(20))
    END as CaseIdStatus,
    LEFT(ErrorMsg, 200) as ErrorMsg
FROM tblErrorLog 
WHERE Process IN ('spProcessReissueCases', 'spGenerateReissueData')
    AND Date >= DATEADD(MINUTE, -10, GETDATE())
ORDER BY Date DESC

-- 5. Test specific error scenarios
PRINT '=== Test Scenario: Force error in called procedure ==='

-- Add this to spGetCSAData temporarily:
/*
IF @CaseId = [YourTestCaseId]
BEGIN
    RAISERROR('TEST ERROR in spGetCSAData for Reissue CaseId %d', 16, 1, @CaseId)
    RETURN -1
END
*/

-- 6. Test with missing data scenario
-- Find a reissue case and remove required data
DECLARE @TestCaseId INT

SELECT TOP 1 @TestCaseId = a.CaseId
FROM tblCases a
    JOIN rtblCode b ON a.StatusCodeId = b.CodeId
WHERE b.Abbrev = '500'

IF @TestCaseId IS NOT NULL
BEGIN
    PRINT 'Test CaseId for reissue: ' + CAST(@TestCaseId AS VARCHAR(20))
    
    -- Temporarily remove required data
    -- DELETE FROM tblGrossToNet WHERE CaseId = @TestCaseId AND RunType = 0
    -- Run process
    -- Restore data
END

-- 7. Comprehensive test with all scenarios
PRINT '=== Comprehensive Error Tracking Test ==='

-- Test 1: Directory creation error (already tested)
-- Test 2: File not found error
-- Test 3: Processing error

-- Check all recent errors
SELECT 
    el.LogId,
    el.Date,
    el.Process,
    el.CaseId,
    c.Version,
    cl.Claim,
    CASE 
        WHEN el.CaseId IS NULL THEN 'No CaseId'
        WHEN c.CaseId IS NULL THEN 'CaseId: ' + CAST(el.CaseId AS VARCHAR(20)) + ' (not found)'
        ELSE 'CaseId: ' + CAST(el.CaseId AS VARCHAR(20)) + ', Claim: ' + cl.Claim
    END as CaseInfo,
    LEFT(el.ErrorMsg, 100) as ErrorMsgStart,
    LEN(el.ErrorMsg) as FullMsgLength
FROM tblErrorLog el
    LEFT JOIN tblCases c ON el.CaseId = c.CaseId
    LEFT JOIN tblClaim cl ON c.ClaimId = cl.ClaimId
WHERE el.Date >= DATEADD(HOUR, -1, GETDATE())
    AND el.Process LIKE '%Reissue%'
ORDER BY el.Date DESC

-- 8. Verify the procedures have OUTPUT parameter
SELECT 
    pr.name as ProcedureName,
    p.name as ParameterName,
    p.is_output,
    t.name as DataType
FROM sys.procedures pr
    JOIN sys.parameters p ON pr.object_id = p.object_id
    JOIN sys.types t ON p.user_type_id = t.user_type_id
WHERE pr.name IN ('spGenerateReissueData', 'spGenerateMFData')
    AND p.name = '@CurrentCaseId'
ORDER BY pr.name