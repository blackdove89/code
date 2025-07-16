-- ================================================================
-- CONDITIONS FOR CASEID TO GENERATE NON-SYSTEM ERRORS
-- ================================================================

-- BASIC REQUIREMENTS FOR CASE TO BE PROCESSED
-- A case must meet ALL these conditions to be picked up by spGenerateMFData:

-- 1. CASE STATUS REQUIREMENTS
SELECT 
    c.CaseId,
    cl.Claim,
    s.Abbrev AS StatusCode,
    'Case must have status 300 or 700' AS Requirement
FROM tblCases c
    JOIN tblClaim cl ON c.ClaimId = cl.ClaimId
    JOIN rtblCode s ON c.StatusCodeId = s.CodeId
WHERE c.CaseId = 30070  -- Replace with your CaseId

-- Required: StatusCode must be '300' (Trigger Pending) or '700' (Reissue Trigger Pending)

-- ================================================================

-- 2. CASE MUST NOT BE LOCKED
SELECT 
    c.CaseId,
    cl.Claim,
    cl.LockedBy,
    CASE 
        WHEN cl.LockedBy IS NULL THEN 'PASS - Case is not locked'
        ELSE 'FAIL - Case is locked by: ' + cl.LockedBy
    END AS LockStatus
FROM tblCases c
    JOIN tblClaim cl ON c.ClaimId = cl.ClaimId
WHERE c.CaseId = 30070

-- Required: LockedBy must be NULL

-- ================================================================

-- 3. CASE MUST HAVE TRIGGERED RUN RESULTS (for Status 300)
SELECT 
    c.CaseId,
    cl.Claim,
    CASE 
        WHEN EXISTS(SELECT 1 FROM tblRunResults WHERE CaseId = c.CaseId AND Method = 0 AND bTriggered = 1)
        THEN 'PASS - Has triggered run results'
        ELSE 'FAIL - No triggered run results'
    END AS RunResultsStatus
FROM tblCases c
    JOIN tblClaim cl ON c.ClaimId = cl.ClaimId
WHERE c.CaseId = 30070

-- Required: Must have tblRunResults with Method = 0 and bTriggered = 1

-- ================================================================

-- 4. CASE MUST HAVE FERS DATA (for most case types)
SELECT 
    c.CaseId,
    cl.Claim,
    rt.Abbrev AS RetirementType,
    CASE 
        WHEN rt.Abbrev IN ('1', '4') THEN 'SKIP - Case types 1 and 4 do not require FERS data'
        WHEN EXISTS(SELECT 1 FROM tblRunResults a 
                   JOIN tblFERSData b ON a.CaseId = b.CaseId 
                   WHERE a.CaseId = c.CaseId AND a.Method = 0 AND a.bTriggered = 1)
        THEN 'PASS - Has FERS data with triggered runs'
        ELSE 'FAIL - Missing FERS data or not linked to triggered runs'
    END AS FERSDataStatus
FROM tblCases c
    JOIN tblClaim cl ON c.ClaimId = cl.ClaimId
    JOIN vwCaseServiceSummary css ON c.CaseId = css.CaseId
    LEFT JOIN rtblCode rt ON css.RetirementTypeId = rt.CodeId
WHERE c.CaseId = 30070

-- Required: Must have FERS data linked to triggered runs (except for case types 1 and 4)

-- ================================================================

-- 5. CASE MUST HAVE GROSS-TO-NET DATA
SELECT 
    c.CaseId,
    cl.Claim,
    CASE 
        WHEN EXISTS(SELECT 1 FROM tblRunResults a 
                   JOIN tblGrossToNet b ON a.CaseId = b.CaseId 
                   WHERE a.CaseId = c.CaseId AND a.Method = 0 AND a.bTriggered = 1)
        THEN 'PASS - Has Gross-to-Net data with triggered runs'
        ELSE 'FAIL - Missing Gross-to-Net data or not linked to triggered runs'
    END AS GrossToNetStatus
FROM tblCases c
    JOIN tblClaim cl ON c.ClaimId = cl.ClaimId
WHERE c.CaseId = 30070

-- Required: Must have Gross-to-Net data linked to triggered runs

-- ================================================================

-- 6. CASE MUST HAVE TOTAL SERVICE SPECIFIED
SELECT 
    c.CaseId,
    cl.Claim,
    rr.TotalComputationService,
    CASE 
        WHEN rr.TotalComputationService IS NOT NULL AND rr.TotalComputationService <> '00/00/00'
        THEN 'PASS - Has valid Total Service: ' + rr.TotalComputationService
        ELSE 'FAIL - Missing or invalid Total Service'
    END AS TotalServiceStatus
FROM tblCases c
    JOIN tblClaim cl ON c.ClaimId = cl.ClaimId
    LEFT JOIN tblRunResults rr ON c.CaseId = rr.CaseId AND rr.Method = 0 AND rr.bTriggered = 1
WHERE c.CaseId = 30070

-- Required: TotalComputationService must be NOT NULL and not '00/00/00'

-- ================================================================

-- COMPREHENSIVE CASE READINESS CHECK
-- This query checks ALL requirements at once:

SELECT 
    c.CaseId,
    cl.Claim,
    s.Abbrev AS StatusCode,
    rt.Abbrev AS RetirementType,
    
    -- Check each requirement
    CASE WHEN s.Abbrev IN ('300', '700') THEN '✓' ELSE '✗' END AS Status_OK,
    CASE WHEN cl.LockedBy IS NULL THEN '✓' ELSE '✗' END AS NotLocked_OK,
    CASE WHEN EXISTS(SELECT 1 FROM tblRunResults WHERE CaseId = c.CaseId AND Method = 0 AND bTriggered = 1) 
         THEN '✓' ELSE '✗' END AS RunResults_OK,
    CASE WHEN rt.Abbrev IN ('1', '4') OR 
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
              AND (rt.Abbrev IN ('1', '4') OR 
                   EXISTS(SELECT 1 FROM tblRunResults a JOIN tblFERSData b ON a.CaseId = b.CaseId 
                          WHERE a.CaseId = c.CaseId AND a.Method = 0 AND a.bTriggered = 1))
              AND EXISTS(SELECT 1 FROM tblRunResults a JOIN tblGrossToNet b ON a.CaseId = b.CaseId 
                         WHERE a.CaseId = c.CaseId AND a.Method = 0 AND a.bTriggered = 1)
              AND EXISTS(SELECT 1 FROM tblRunResults WHERE CaseId = c.CaseId AND TotalComputationService IS NOT NULL 
                         AND TotalComputationService <> '00/00/00' AND Method = 0 AND bTriggered = 1)
         THEN 'READY FOR PROCESSING'
         ELSE 'NOT READY - Missing Requirements'
    END AS OverallStatus

FROM tblCases c
    JOIN tblClaim cl ON c.ClaimId = cl.ClaimId
    JOIN rtblCode s ON c.StatusCodeId = s.CodeId
    JOIN vwCaseServiceSummary css ON c.CaseId = css.CaseId
    LEFT JOIN rtblCode rt ON css.RetirementTypeId = rt.CodeId
WHERE c.CaseId = 30070  -- Replace with your CaseId

-- ================================================================

-- FIND CASES THAT MEET ALL CONDITIONS
-- Use this to find cases that would actually be processed:

SELECT TOP 10
    c.CaseId,
    cl.Claim,
    s.Abbrev AS StatusCode,
    rt.Abbrev AS RetirementType,
    'READY FOR PROCESSING' AS Status
FROM tblCases c
    JOIN tblClaim cl ON c.ClaimId = cl.ClaimId
    JOIN rtblCode s ON c.StatusCodeId = s.CodeId
    JOIN vwCaseServiceSummary css ON c.CaseId = css.CaseId
    LEFT JOIN rtblCode rt ON css.RetirementTypeId = rt.CodeId
WHERE s.Abbrev IN ('300', '700')  -- Correct status
    AND cl.LockedBy IS NULL  -- Not locked
    AND EXISTS(SELECT 1 FROM tblRunResults WHERE CaseId = c.CaseId AND Method = 0 AND bTriggered = 1)  -- Has triggered runs
    AND (rt.Abbrev IN ('1', '4') OR  -- Either case type 1/4 (no FERS needed) OR has FERS data
         EXISTS(SELECT 1 FROM tblRunResults a JOIN tblFERSData b ON a.CaseId = b.CaseId 
                WHERE a.CaseId = c.CaseId AND a.Method = 0 AND a.bTriggered = 1))
    AND EXISTS(SELECT 1 FROM tblRunResults a JOIN tblGrossToNet b ON a.CaseId = b.CaseId 
               WHERE a.CaseId = c.CaseId AND a.Method = 0 AND a.bTriggered = 1)  -- Has Gross-to-Net
    AND EXISTS(SELECT 1 FROM tblRunResults WHERE CaseId = c.CaseId AND TotalComputationService IS NOT NULL 
               AND TotalComputationService <> '00/00/00' AND Method = 0 AND bTriggered = 1)  -- Has Total Service
ORDER BY c.CaseId

-- ================================================================

-- SCENARIOS THAT GENERATE CASEID ERRORS (NON-SYSTEM ERRORS)
-- ================================================================

/*
Once a case meets all the above conditions, these scenarios will generate 
errors with actual CaseId numbers:

1. LOCK THE CASE:
   - Case passes all validation checks
   - spGenerateMFData starts processing it (sets @CurrentCaseId = CaseId)
   - Discovers case is locked
   - Logs error with CaseId: "Locked."

2. CORRUPT CASE DATA AFTER VALIDATION:
   - Remove FERS data after validation but before data generation
   - spGenerateMFData will fail during data generation with CaseId

3. FILE OPERATION FAILURES:
   - Case processes successfully through data generation
   - spWriteToFile fails due to file system issues
   - Error logged with CaseId

4. STORED PROCEDURE FAILURES:
   - spGetCSAData, spGetFERSData, or spGetCSFData fail
   - Error logged with the CaseId being processed

5. EXCEPTION HANDLING:
   - Any unexpected error during case processing
   - TRY/CATCH blocks log error with current CaseId

The key is: ERROR OCCURS AFTER @CurrentCaseId = @nCaseId IS SET
but BEFORE the case processing completes successfully.
*/

-- ================================================================

-- QUICK TEST TO ENSURE YOUR CASE IS READY
-- ================================================================

-- Run this to verify your test case meets all conditions:
DECLARE @TestCaseId INT = 30070  -- Change this to your test case

SELECT 
    'Case Readiness Check' AS TestType,
    @TestCaseId AS CaseId,
    CASE 
        WHEN EXISTS(
            SELECT 1 
            FROM tblCases c
                JOIN tblClaim cl ON c.ClaimId = cl.ClaimId
                JOIN rtblCode s ON c.StatusCodeId = s.CodeId
                JOIN vwCaseServiceSummary css ON c.CaseId = css.CaseId
                LEFT JOIN rtblCode rt ON css.RetirementTypeId = rt.CodeId
            WHERE c.CaseId = @TestCaseId
                AND s.Abbrev IN ('300', '700')
                AND cl.LockedBy IS NULL
                AND EXISTS(SELECT 1 FROM tblRunResults WHERE CaseId = c.CaseId AND Method = 0 AND bTriggered = 1)
                AND (rt.Abbrev IN ('1', '4') OR 
                     EXISTS(SELECT 1 FROM tblRunResults a JOIN tblFERSData b ON a.CaseId = b.CaseId 
                            WHERE a.CaseId = c.CaseId AND a.Method = 0 AND a.bTriggered = 1))
                AND EXISTS(SELECT 1 FROM tblRunResults a JOIN tblGrossToNet b ON a.CaseId = b.CaseId 
                           WHERE a.CaseId = c.CaseId AND a.Method = 0 AND a.bTriggered = 1)
                AND EXISTS(SELECT 1 FROM tblRunResults WHERE CaseId = c.CaseId AND TotalComputationService IS NOT NULL 
                           AND TotalComputationService <> '00/00/00' AND Method = 0 AND bTriggered = 1)
        )
        THEN 'READY - This case will be processed and can generate CaseId errors'
        ELSE 'NOT READY - This case will be skipped during processing'
    END AS Result