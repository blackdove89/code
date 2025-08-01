USE [RETIRE]
GO

/****** Object:  StoredProcedure [dbo].[spGenerateMFData]    Script Date: 7/16/2025 7:41:28 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


ALTER PROCEDURE [dbo].[spGenerateMFData]
    @ClaimNumber                   VARCHAR(9)            = NULL
   ,@Filename                      VARCHAR(100)
   ,@bTest                         TINYINT               = 0
   ,@bUpdate                       TINYINT               = 0
   ,@bSendMail                     BIT                   = 0
   ,@bDebug                        TINYINT               = 0
   ,@CurrentCaseId                 INT                   = NULL OUTPUT  -- NEW PARAMETER
AS
   /****************************************************************************

   PURPOSE:
      Generates data for the file that is sent to the mainframe for the 
      daily cycle.  Usually called by spProcessCases.

   PARAMETERS:
      @ClaimNumber      IF blank, looks for all triggered cases.  IF '?',
                        display help information.  (Default='')
      @Filename         Path and name of output files (without ext.)
      @bTest            DUMMY (no longer used) 
      @bUpdate          1 to UPDATE status of cases processed, 0 otherwise.
                        (Default=0)
      @bSendMail        1 to send error email WHEN appropriate.
                        (Default=0)
      @bDebug           1 to enable debugging in stored procedures
      @CurrentCaseId    OUTPUT parameter that returns the CaseId being processed
                        when an error occurs (Default=NULL)

   LOGIC:
      SELECT cases to process.
      FOR each case
         UPDATE CASE status in tblCases.
      ENDFOR

   RETURN VALUES      
      0 - successful
      1 - error occurred

   AUTHOR
      Keith Yager
      Malathi Thadkamalla

   ----------------------------------------------------------------------------
   HISTORY:  $Log: /FACES30/DB/Mainframe/spGenerateMFData.sql $
   
   30    7/16/25 Added @CurrentCaseId OUTPUT parameter for better error tracking
   
   29    1/07/20 11:24a Dctcrctimt
   QACMS -	200109, the MF process cases did not print when there is only
   one claim.
   
   28    9/10/18 3:20p Dctcrctijc
   180158 Trailer record. On behalf of Malathi.
   
   27    12/28/16 2:55p Dctcrmt
   SBM 170054 
   
   27     12/28/16 10:12a Dctcrmt
   SBM 170054 -- Filter non-opm emails list excluding valid whitelist
   
   26    9/26/14 3:26p Dctcrsbol
   
   25    5/13/14 4:12p Dctcrsbol
   
   24    5/06/14 8:06a Dctcrsbol
   
   Cleaned up the comment section.
   
   Added Reissue Changes.
   
   Added @Msg parameter when calling spQueueMail procedure.

   Changed the project name in the directory path.
   
   Changed the order of the cases processing.

   Changed the nightly job userid name.

   ******************************************************************************/

BEGIN

   --=============================
   -- Declaration Section
   --=============================

   DECLARE @sCR                     VARCHAR(2)
   DECLARE @cs                      CURSOR
   DECLARE @dtNow                   DATETIME
   DECLARE @FName                   VARCHAR(100)
   DECLARE @sCaseType               VARCHAR(1)
   DECLARE @nWriteMode              TINYINT
   DECLARE @rec1                    VARCHAR(2000)
   DECLARE @rec2                    VARCHAR(2000)
--   DECLARE @nStatus                 SMALLINT
   DECLARE @sStatus                 VARCHAR(4)
   DECLARE @rc                      INT
   DECLARE @sData                   VARCHAR(2000)
   DECLARE @sErrorMsg               VARCHAR(2000)
   DECLARE @sReason                 VARCHAR(50)
   DECLARE @sMsg                    VARCHAR(2000)
   DECLARE @NR                      INT
   DECLARE @nDeathCases             INT
   DECLARE @nErrors                 INT
   DECLARE @nMissingData            INT
   DECLARE @nProcessed              INT
   DECLARE @nCaseId                 INT
   DECLARE @Msg                     VARCHAR(2000)

   DECLARE @Recipients              VARCHAR(1000)
   DECLARE @Copy                    VARCHAR(1000)
   DECLARE @BlindCopy               VARCHAR(1000)
   DECLARE @ErrorRecipients         VARCHAR(1000)
   DECLARE @AdminRecipients         VARCHAR(1000)
   DECLARE @rcount                  INT

   SET @sCR = CHAR(13) -- + CHAR(10)

   --=============================
   -- End of Declaration Section
   --=============================


   --=============================
   -- Validation and Usage Section
   --=============================

   -- Initialize OUTPUT parameter
   SET @CurrentCaseId = NULL

   -- Usage Section
   IF @Filename                        IS NULL
   BEGIN
      SET @Msg = 'Usage: spGenerateMFData   '

      SET @Msg = @Msg + @sCR + '   @ClaimNumber                      VARCHAR(9) = NULL       (INPUT Paramater) (Specified Value: ' + ISNULL(Cast(@ClaimNumber                   AS VARCHAR(20)) , '[NULL]')  + ')'
      SET @Msg = @Msg + @sCR + '  ,@Filename                         VARCHAR(100)            (INPUT Paramater) (Specified Value: ' + ISNULL(Cast(@Filename                      AS VARCHAR(20)) , '[NULL]')  + ')'
      SET @Msg = @Msg + @sCR + '  ,@bTest                            TINYINT = 0             (INPUT Paramater) (Specified Value: ' + ISNULL(Cast(@bTest                         AS VARCHAR(20)) , '[NULL]')  + ')'
      SET @Msg = @Msg + @sCR + '  ,@bUpdate                          TINYINT = 0             (INPUT Paramater) (Specified Value: ' + ISNULL(Cast(@bUpdate                       AS VARCHAR(20)) , '[NULL]')  + ')'
      SET @Msg = @Msg + @sCR + '  ,@bSendMail                        BIT = 0                 (INPUT Paramater) (Specified Value: ' + ISNULL(Cast(@bSendMail                     AS VARCHAR(20)) , '[NULL]')  + ')'
      SET @Msg = @Msg + @sCR + '  ,@bDebug                           TINYINT = 0             (INPUT Paramater) (Specified Value: ' + ISNULL(Cast(@bDebug                        AS VARCHAR(20)) , '[NULL]')  + ')'
      SET @Msg = @Msg + @sCR + '  ,@CurrentCaseId                    INT = NULL OUTPUT       (OUTPUT Paramater)'

      RETURN -100
   END


   --=============================
   -- End of Validation Section
   --=============================

   IF @bUpdate IS NULL
      SET @bUpdate = 0

   IF @bSendMail IS NULL
      SET @bSendMail = 0

   IF @bDebug IS NULL
      SET @bDebug = 0


   --=============================
   -- Main Code Block
   --=============================
   
   SET NOCOUNT ON

   IF dbo.fIsBlank(@ClaimNumber) = 1
      SET @cs = CURSOR SCROLL KEYSET FOR
         SELECT 
             a.CaseId
            ,Claim
            ,c.Abbrev RetirementType
            ,b.Abbrev StatusCode
         FROM 
            tblCases a
               JOIN tblClaim a1 ON a.ClaimId = a1.ClaimId
               JOIN rtblCode b ON a.StatusCodeId = b.CodeId
               JOIN vwCaseServiceSummary d ON a.CaseId = d.CaseId
                  LEFT JOIN rtblCode c ON d.RetirementTypeId = c.CodeId
         WHERE 
            b.Abbrev IN ('300', '700') -- @sStatus -- 30,300 = Trigger Pending
         ORDER BY Claim
   ELSE
      SET @cs = CURSOR SCROLL KEYSET FOR
         SELECT 
             a.CaseId
            ,Claim
            ,c.Abbrev RetirementType
            ,b.Abbrev StatusCode
         FROM 
            tblCases a
               JOIN tblClaim a1 ON a.ClaimId = a1.ClaimId
               JOIN rtblCode b ON a.StatusCodeId = b.CodeId
               JOIN vwCaseServiceSummary d ON a.CaseId = d.CaseId
                  LEFT JOIN rtblCode c ON d.RetirementTypeId = c.CodeId
         WHERE 
            Claim = @ClaimNumber AND
            Version = 0
 
 
   SET @dtNow          = GETDATE()
   SET @NR             = 0
   SET @nDeathCases    = 0
   SET @nErrors        = 0
   SET @nMissingData   = 0
   SET @nProcessed     = 0
   SET @sMsg           = ''
   SET @sErrorMsg      = ''
   SET @rcount = 0
   
   OPEN @cs
   FETCH FIRST FROM @cs INTO @nCaseId, @ClaimNumber, @sCaseType, @sStatus
   WHILE @@FETCH_STATUS = 0 
   BEGIN

         
      BEGIN TRY 
        
         -- Set the current case being processed for error tracking
         SET @CurrentCaseId = @nCaseId
         
         SET @NR = @NR + 1

         IF @bDebug = 1
            PRINT 'Processing CaseId: ' + CAST(@nCaseId AS VARCHAR(20)) + ', ClaimNumber: ' + @ClaimNumber

         /******************************************************
           First, make sure the CASE is ready to be triggered.
         ******************************************************/

         SET @sReason = ''
         SET @sData = ''
         SET @rec1 = ''
         SET @rec2 = ''
         
         IF EXISTS (SELECT 1 FROM tblCases a JOIN tblClaim b ON a.ClaimId = b.ClaimId WHERE CaseId = @nCaseId AND dbo.fIsBlank(b.LockedBy) = 0)
            SET @sReason = 'Locked.'
         ELSE 
         BEGIN
            IF @sStatus = '300' 
            BEGIN
               IF NOT EXISTS(SELECT 1 FROM tblRunResults WHERE CaseId = @nCaseId and Method = 0 and bTriggered = 1)
                  SET @sReason = 'No runs triggered.'
               ELSE
               IF @sCaseType NOT IN ('1', '4') AND 
                  NOT EXISTS(SELECT 1 FROM tblRunResults a JOIN tblFERSData b ON a.CaseId = b.CaseId JOIN vwCaseServiceSummary c ON a.CaseId = c.CaseId WHERE a.CaseId = @nCaseId AND a.Method = 0 AND a.bTriggered = 1)        
                  SET @sReason = 'No FERS data.'
               ELSE
               IF NOT EXISTS(SELECT 1 FROM tblRunResults a JOIN tblGrossToNet b ON a.CaseId = b.CaseId WHERE a.CaseId = @nCaseId and a.Method = 0 and a.bTriggered = 1)
                  SET @sReason = 'No Gross-to-net data.'
               ELSE
               IF NOT EXISTS(SELECT 1 FROM tblRunResults WHERE CaseId = @nCaseId and TotalComputationService IS NOT NULL and TotalComputationService <> '00/00/00'  and Method = 0 and bTriggered = 1)
                  SET @sReason = 'No "Total Service" specified.'
            END
            ELSE IF @sStatus = '700'
            BEGIN
               IF @sCaseType NOT IN ('1', '4') AND 
                  NOT EXISTS(SELECT 1 FROM tblFERSData b WHERE b.CaseId = @nCaseId AND b.Runtype = 255)
                  SET @sReason = 'No FERS data.'
               ELSE
               IF NOT EXISTS(SELECT 1 FROM tblGrossToNet b WHERE b.CaseId = @nCaseId AND b.Runtype = 255)
                  SET @sReason = 'No Gross-to-net data.'
               ELSE
               IF NOT EXISTS(SELECT 1 FROM tblFBData WHERE CaseId = @nCaseId and TotalService IS NOT NULL and TotalService <> '00/00/00')
                  SET @sReason = 'No "Total Service" specified.'            
            END
         END
         
         IF LEN(@sReason) > 0
         BEGIN
            SET @nMissingData = @nMissingData + 1
            SET @sErrorMsg = @sErrorMsg + @sCR + @ClaimNumber + '  ' + @sReason
            
            -- Log this as well for tracking
            IF @bDebug = 1
               PRINT 'CaseId ' + CAST(@nCaseId AS VARCHAR(20)) + ' skipped: ' + @sReason
         END
         ELSE
         BEGIN
            /******************************
              Now generate the CASE data.
            ******************************/
            
            IF @sCaseType = '8'  -- Death
            BEGIN
               EXEC @rc = spGetCSFData @nCaseId, @rec1 output, @bDebug
               SET @sMsg = 'spGetCSFData' 
            END
            ELSE
            BEGIN
               -- A Cases
               IF @sStatus = '700' 
               BEGIN
                  EXEC @rc = spGetFBCSAData @nCaseId, @rec1 output, @bDebug
                  SET @sMsg = 'spGetFBCSAData' 
               END
               ELSE
               BEGIN
                  EXEC @rc = spGetCSAData @nCaseId, @rec1 output, @bDebug
                  SET @sMsg = 'spGetCSAData' 
               END
            END

            IF @rc = 0
            BEGIN
               EXEC @rc = spGetFERSData @nCaseId, @rec2 output, @bDebug
               SET @sMsg = 'spGetFERSData' 
            END
                 
            IF @rc = 0
            BEGIN

               IF @bUpdate = 1
                  IF @sStatus = '300'
                     EXEC @rc=spSetStatus @CaseId = @nCaseId, @Status = '310', @Comment = 'Status change after generating the MF Data.', @Login  = '<system>', @Msg = @Msg OUTPUT
                  ELSE
                     EXEC @rc=spSetStatus @CaseId = @nCaseId, @Status = '710', @Comment = 'Status change after generating the MF Data.', @Login  = '<system>', @Msg = @Msg OUTPUT

               IF @rc = 0
               BEGIN
                  SET @sMsg = 'spWriteToFile ' 
                                 
                  SET @sData = @rec1 + @rec2

                  SET @FName = @Filename + '.txt'

                  EXEC @rc = spWriteToFile @FName, @ClaimNumber, @nWriteMode
                  IF @rc <> 0 
                     RAISERROR (@sMsg, 16, 1)
                                 
                  SET @nWriteMode = CASE @nProcessed WHEN 0 THEN 0 ELSE 1 END
                  SET @FName = @Filename + '.psv'

                  EXEC @rc = spWriteToFile @FName, @sData, @nWriteMode
                  SET @rcount = @rcount+1
                  SET @rcount = RIGHT(10000000000 + @rcount, 9)
                  
                  IF @rc <> 0 
                     RAISERROR (@sMsg, 16, 1)
                                       
               END
               
                  
               IF @sCaseType = '8' -- Death
                  SET @nDeathCases = @nDeathCases + 1
                              
               SET @nProcessed = @nProcessed + 1

            END
            ELSE
            BEGIN
            
               SET @sMsg = @sMsg + ' returned ' + LTRIM(STR(@rc)) + ' for CaseId ' + CAST(@nCaseId AS VARCHAR(20))

               IF @bDebug = 1
                  PRINT @sMsg

               SET @nErrors = @nErrors + 1
               INSERT INTO tblErrorLog (CaseId, Process, ErrorMsg) 
               VALUES (@nCaseId, 'spGenerateMFData', @sMsg)
                           
            END 
                        
         END

      END TRY
      
      BEGIN CATCH      
         
         -- CurrentCaseId is already set to @nCaseId, so it will be available to calling procedure
         
         IF LEN(@sMsg) > 0
            SET @sReason = 'Failed Processing (CaseId: ' + CAST(@nCaseId AS VARCHAR(10)) + ') due to error in ' + @sMsg + '(' + ERROR_MESSAGE() + ').'
         ELSE
            SET @sReason = 'Failed Processing (CaseId: ' + CAST(@nCaseId AS VARCHAR(10)) + ') due to error in ' + ERROR_MESSAGE() + '.'

         INSERT INTO tblErrorLog (CaseId, Process, ErrorMsg) 
         VALUES (@nCaseId, 'spGenerateMFData', @sReason)         
         
         BEGIN
            SET @nMissingData = @nMissingData + 1
            SET @sErrorMsg = @sErrorMsg + @sCR + @ClaimNumber + '  ' + @sReason
         END   
         
         -- Optionally, you can stop processing on first error by uncommenting these lines:
         -- CLOSE @cs
         -- DEALLOCATE @cs
         -- RETURN -1
         
      END CATCH
            
      FETCH NEXT FROM @cs INTO @nCaseId, @ClaimNumber, @sCaseType, @sStatus
   END
   
   -- Clear CurrentCaseId when done processing all cases
   SET @CurrentCaseId = NULL
   
   CLOSE @cs
   DEALLOCATE @cs

   -- Now generate error email for any triggered cases that weren't sent.

   IF @bSendMail = 1 and LEN(@sErrorMsg) > 0
   BEGIN

      EXEC spGetReportEMailAddresses 'Pending Cases: Sent to mainframe', @Recipients OUTPUT, @Copy OUTPUT, @BlindCopy OUTPUT, @ErrorRecipients OUTPUT, @AdminRecipients OUTPUT, @sMsg OUTPUT
      
      IF dbo.fIsBlank(@ErrorRecipients) = 0  
      BEGIN
         SET @sErrorMsg = CONVERT(VARCHAR(20), GETDATE() , 0) + @sCR + @sCR +
                          'CASE No.  Reason for not sending' + @sCR +
                          '--------  -------------------------------' + @sCR +
                          @sErrorMsg
		 SET @AdminRecipients = dbo.fExtractValidOpmEmails(@AdminRecipients,';') 
		 SET @ErrorRecipients = dbo.fExtractValidOpmEmails(@ErrorRecipients,';') 
		  
         EXEC spQueueMail @ErrorRecipients
                         ,@CC = @AdminRecipients
                         ,@subject = 'Pending Cases Processing:  Triggered Cases not sent to mainframe.'
                         ,@message = @sErrorMsg
                         ,@width = 256
                         ,@Msg = @Msg OUTPUT
      END
   END

   IF @bDebug = 1
   BEGIN
      PRINT ''
      PRINT LTRIM(STR(@NR)) + ' records triggered' 
          + CASE WHEN @nDeathCases > 0 
               THEN ' (incl. ' + LTRIM(STR(@nDeathCases)) + ' death cases)' 
               ELSE ''
            END + @sCR
          + LTRIM(STR(@nProcessed)) + ' processed' + @sCR
          + CASE WHEN @nErrors > 0      
               THEN LTRIM(STR(@nErrors)) + ' had errors' + @sCR 
               ELSE ''
            END
          + CASE WHEN @nMissingData > 0 
               THEN LTRIM(STR(@nMissingData)) + ' were locked or had missing data' 
               ELSE ''
            END
   
      PRINT ''
   
      IF @nErrors > 0 
         SELECT * FROM tblErrorLog WHERE Date >= @dtNow

      IF @nMissingData > 0 
         PRINT 'Locked or mising data' + @sCR
             + '----------------------------------' + @sCR
            + @sErrorMsg
   
   END
   
    DECLARE @recordA            VARCHAR(2000)
    --************************************************************** 
   
   Set @recordA ='T|'+ Convert(varchar(10), RIGHT(10000000000 + @nProcessed, 7)) +'||   |  ||| ||| |||||||||||||||||||||  || |||||| |||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||0|0|0|0| | | ||0|0|0|0| | | ||0|0|0|0| | | ||0|0|0|0| | | ||0|0|0|0| | | ||0|0|0|0| | | ||0|0|0|0| | | ||0|0|0|0| | | |0|0|0|0|0|0|0|0|0|0|0|0|0|0|0|0|0|0|0|0|0|0|0|0|0|0|0|0|    ||| || ||1||0|  | | |0|0| | |0| |** | | |0|0| | |0| |** | | |0|0| | |0| |** | | |0|0| | |0| | | | |0|0| | |0| | | | |0|0| | |0| | | | |0|0| | |0| | |0| |0||| | |0|0|||0|0|0| 0||||||0|0||0|0|||0|0||0|0|0|0|0|0|0|0|0|1|0||0|0|0|| |' 
   print Convert(varchar(10), RIGHT(10000000000 + @nProcessed, 9))
   --set @nWriteMode value 0-->no records, 1--> records
   SET @nWriteMode = CASE @nProcessed WHEN 0 THEN 0 ELSE 1 END
   EXEC @rc = spWriteToFile @FName,@recordA , @nWriteMode

   --***********************************************************************8


   --=============================
   -- End of Main Code Block
   --=============================

   SET NOCOUNT OFF
   RETURN @nProcessed

END
GO