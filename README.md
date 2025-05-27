DECLARE @nCaseId       INT
DECLARE @sClaim        VARCHAR(100)
DECLARE @sStatus       VARCHAR(10)
DECLARE @sSpecialist   VARCHAR(200)
DECLARE @sReviewer     VARCHAR(200)
DECLARE @sRecipients   VARCHAR(400)

DECLARE @sSubject      VARCHAR(100)
DECLARE @sMessage      VARCHAR(1000)
DECLARE @CutOffDate DATETIME
DECLARE @CheckDate DATETIME

DECLARE @rc            INT
DECLARE @Msg           VARCHAR(1000)

   /*
   Start - Get REPORT Email information
   */
   
   --DECLARE @rc int
   DECLARE @Recipients                       VARCHAR(1000)
   DECLARE @Copy                                VARCHAR(1000)
   DECLARE @BlindCopy                         VARCHAR(1000)
   DECLARE @ErrorRecipients                 VARCHAR(1000)
   DECLARE @AdminRecipients               VARCHAR(1000)
   DECLARE @sMsg VARCHAR(2000)
   EXEC spGetReportEMailAddresses '', @Recipients OUTPUT, @Copy OUTPUT, @BlindCopy OUTPUT, @ErrorRecipients OUTPUT, @AdminRecipients OUTPUT, @sMsg OUTPUT
   
   /*
   Complete - Get REPORT Email information
   */

SELECT
   @CutOffDate = MIN(CutOffDate)
FROM
   rtblCutOff WHERE CutOffDate > GetDate() - 1  

SET @CutOffDate = DATEADD(m, 1, @CutOffDate)

SET @CheckDate = CAST(MONTH(@CutOffDate) AS VARCHAR(2)) + '/01/' + CAST(YEAR(@CutOffDate) AS VARCHAR(4))

-- Set the Job for the FACES Security database.
DECLARE cCase CURSOR FOR
   SELECT    
      DISTINCT d.CaseId, d.Claim, Status, k.Email Specialist, l.Email Reviewer
   FROM        
      dbo.vwCases d
         JOIN vwCaseServiceSummary e ON d.caseid = e.caseid
            JOIN vwCodeList m ON e.RetirementTypeId = m.CodeId
         JOIN dbo.tblResults A ON a.CaseId = d.CaseId
         JOIN dbo.tblAdjustments b ON d.CaseId = b.CaseId
            JOIN dbo.vwCodeList c ON b.AddDeductCodeId = c.CodeId      
         LEFT JOIN tblAnnuitySupplement h on d.Caseid = h.CaseId
         JOIN rvwUserList k on d.specialist = k.login
         JOIN rvwUserList l on d.reviewer = l.login
   WHERE    
      d.Status = '300' AND
      c.CodeType = 'AddDeductCodes' AND
      c.CodeAbbrev = '67' AND
      b.RunType = (SELECT o.RunType FROM tblRunResults o WHERE b.CaseId = o.CaseId AND btriggered = 1) AND -- incluse AS fromn the trigger run
      e.CaseType IN(2, 3) AND
      RetirementTypeId <> (select [dbo].[fGetCodeId]('C','SepCodes')) AND -- exclude old 6C
      EXISTS(SELECT 1 FROM tblRunResults f where d.caseid = f.caseid and (CalcRetirementType <> 'C' OR CalcRetirementType IS NULL) AND bTriggered = 1) AND  -- exclude new 6C
      a.ASSystem_BeginDate > a.AnnuityStartDate AND
      ISNULL(ASUser_BeginDate, a.ASSystem_BeginDate) >= @CheckDate    

BEGIN
   OPEN cCase

   FETCH FROM cCase INTO @nCaseId, @sClaim, @sStatus, @sSpecialist, @sReviewer

   WHILE @@fetch_status = 0

   BEGIN
     
      PRINT @sClaim
      IF @sStatus = '300'
      BEGIN
         EXEC @rc = spSetStatus @CaseId = @nCaseId, @Status = '210', @Login  = '<system>', @Msg = @Msg OUTPUT
      END
      ELSE
      BEGIN  
         EXEC @rc = spSetStatus @CaseId = @nCaseId, @Status = '410', @Login  = '<system>', @Msg = @Msg OUTPUT
      END

      SET @sRecipients = ISNULL(@sSpecialist + ';', '') + ISNULL(@sReviewer + ';', '')
      SET @sSubject = 'Case ' + @sClaim + ' moved back.'
      SET @sMessage = 'The Annuity Supplement start date is after the current payment date.  Check the Contributions Tab Override box to remove the Annuity Supplement and re-submit the case to review.'

      EXEC @rc = spQueueMail @Recipients = @sRecipients, @BCC = @BlindCopy, @Subject = @sSubject, @Message = @sMessage, @bTimeStamp = 1, @Msg = @Msg OUTPUT

      FETCH FROM cCase INTO @nCaseId, @sClaim, @sStatus, @sSpecialist, @sReviewer
   END
   CLOSE cCase
   DEALLOCATE cCase
END
GO
