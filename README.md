PRINT 'apCopyClaimOldNew'
GO

IF object_id(N'dbo.apCopyClaimOldNew') > 0
BEGIN
   DROP PROCEDURE dbo.apCopyClaimOldNew
   PRINT '   ... Dropping.'
END
GO

CREATE PROCEDURE [dbo].[apCopyClaimOldNew]
    @ClaimNumber                    VARCHAR(9)              = NULL
   ,@SSN                            VARCHAR(9)              = NULL
   ,@DBName                         VARCHAR(40)             = NULL
   ,@ToClaimNumber                  VARCHAR(9)              = NULL
   ,@ToSpecialist                   VARCHAR(20)             = NULL
   ,@bDebug                         BIT                     = 0
   ,@Msg                            VARCHAR(2000) OUTPUT
AS

   /****************************************************************************

   PURPOSE:
      This routine is to copy Claim from previous release database data model and new data model. This routine should help copying claims  during the new development. 
      If copying across servers, see the Copying Cases SOP. 
      Except Claim number, Data Of Birth, and Date Of Death, mask other PII data. 
      
      Notes:
         - This routine needs to be updated for data model changes.

      Assumption:
         Expects either Claim or SSN is passed. If both are passed, then uses Claim number.
         make sure these attributes belong to the same case.

         Cases is copied
            -- if the Claim number does not exist in the target database.
            -- if the SSN does not present with more than one WEB case in the current database.
            -- When copy a Composite Claim, also copies the Phased Claim. 
            -- If "ToClaimNumber" is specified for a composite case, the phased claim number corresponding to the "ClaimNumber" gets copied.
            -- When copying Phased or Composite Claim, check tblPhasedClaims table for the phased to composite relation and make necessary relation adjustments.



   RETURN VALUES:
      0             : For Sucessful Execution.
      -1 to -999    : For Execution and Validation Errors.

   AUTHOR:
      Satish Bollempalli
      Malathi Thadkamalla

   ----------------------------------------------------------------------------
   HISTORY:  $Log: /FACES30/DB/RetireDB/Admin/apCopyClaimOldNew.sql $
   
   51    4/26/23 13:18 Dctcrctecvb
   
   50    4/25/23 11:10 Dctcrctecvb
   Added the following Calculated tables.
      tblAverageSalaries
      tblBenefitOutputReportData
      tblFERSData
      tblGrossToNet
      tblHighSalaries
      tblPost56Military
      tblResults
      tblRunResults
      tblXLReportData
      tblDepositReport 
   
   Cleaned up code.
   Fixed a bug related to FIT column in tblSurvivor table.
   Fixed bad columns and Added missing columns
   Fixed bug related copying Lumpsum Payment without LS payees.
   Fixed hard coded value for IRS_PVF
   Masked using same strategy as declassify script.
   
   48    1/14/21 14:51 Dctcrctivb
   Checkin code after cleaning the code for the re purpose code.
   


   ****************************************************************************/

BEGIN

   SET NOCOUNT ON

   DECLARE @nId             INT
   DECLARE @rc              INT
   DECLARE @sSQL            VARCHAR(4000)
   DECLARE @sClaim          VARCHAR(9)
   --DECLARE @sSSN            VARCHAR(9)
   DECLARE @sSSNScramble    VARCHAR(9)
   --DECLARE @sSurvivorSSNScramble VARCHAR(9)

   DECLARE @sAbbrev         VARCHAR(4)

   DECLARE @cs              CURSOR
   DECLARE @csCaseRecords CURSOR
   DECLARE @sToCaseId       VARCHAR(20)
   DECLARE @sToClaimId      VARCHAR(20)
   DECLARE @sToCustomerId   VARCHAR(20)

   DECLARE @sFromCaseId     VARCHAR(20)
   DECLARE @sFromClaimId    VARCHAR(20)
   DECLARE @sFromCustomerId VARCHAR(20)
   DECLARE @ServerName      VARCHAR(100)

   /*
   DECLARE @bScrambleData     BIT

   --Always Scramble PII data.
   SET @bScrambleData = 1

   IF @bDebug = 1
      PRINT 'Scramble: ' + CAST(@bScrambleData AS VARCHAR(10))
   */
   
   SET @ServerName = @@ServerName
   SET @ServerName = '[' + @ServerName + ']'

   -- Check this
   IF dbo.fIsBlank(@DBName) = 1
      SET @DBName = DB_NAME()

   DECLARE @nCount INT

   CREATE TABLE #tmp_HeaderRecords
   (
      CaseId            INT        NULL,
      Claim             VARCHAR(9) NULL,
      ClaimId           INT        NULL,
      CustomerId        INT        NULL,
      Version           INT        NULL,
      PhasedIndicator   VARCHAR(1) NULL
   )

   CREATE TABLE #tmp_LSRecords
   (
       PaymentId      INT        NULL
      ,PayeeId        INT        NULL
      ,ToClaimId      INT        NULL
   )

   CREATE TABLE #tmp_CustomerRecords
   (
      FromCustomerId    INT,
      ToCustomerId      INT,
      RecordType        VARCHAR(100),
      FromRecordId      INT,
      ToRecordId        INT
   )

   DECLARE @RecordType        VARCHAR(40)
         , @sFromRecordId     VARCHAR(40)
         , @csCustomerRecords CURSOR

   DECLARE @sPhasedClaim      VARCHAR(9)
   DECLARE @tmp_PhasedClaim   TABLE
   (
      PhasedClaim    VARCHAR(9)
   )

   CREATE TABLE #tmp_CasesMapping
   (
       FromCustomerId          INT
      ,ToCustomerId           INT
      --,LocalSSN                  VARCHAR(9)
      ,FromClaimId             INT
      ,ToClaimId              INT
      ,FromCaseId              INT
      ,ToCaseId               INT
   )

   IF dbo.fIsBlank(@ToClaimNumber) = 1
      SET @ToClaimNumber = @ClaimNumber

   IF EXISTS(SELECT 1 FROM tblClaim WHERE Claim = @ToClaimNumber)
   BEGIN
      SET @Msg = 'Claim ' + @ToClaimNumber + ' can not be copied since it exists in the current database.'
      RETURN -1611
   END

   IF EXISTS(SELECT 1 FROM vwCases WHERE SSN = @SSN AND Claim IS NULL)
   BEGIN
      SET @Msg = 'SSN ' + @SSN + ' can not be copied since it exists in the current database.'
      RETURN -1612
   END

   --
   -- Use Claim Number if it is provided. Otherwise try SSN.
   --
   BEGIN
      IF dbo.fIsBlank(@ClaimNumber) <> 1
      BEGIN
         INSERT INTO #tmp_HeaderRecords
         EXEC('
            SELECT
                CaseId
               ,''' + @ToClaimNumber + '''
               ,ClaimId
               ,CustomerId
               ,a.Version
               ,a.PhasedIndicator
            FROM
               ' + @ServerName + '.' + @DBName + '.dbo.vwCases a
            WHERE
               Claim = ''' + @ClaimNumber + ''''
         )
      END
      ELSE IF dbo.fIsBlank(@SSN) <> 1
      BEGIN
         INSERT INTO #tmp_HeaderRecords
         EXEC('
            SELECT
                CaseId
               ,Claim
               ,ClaimId
               ,CustomerId
               ,a.Version
               ,a.PhasedIndicator
            FROM
               ' + @ServerName + '.' + @DBName + '.dbo.vwCases a
            WHERE
               SSN = ''' + @SSN + ''''
         )
      END

   END

   --IF @bDebug = 1 
   --BEGIN
   --   PRINT 'Header Records...'
   --   SELECT * FROM #tmp_HeaderRecords
   --END

   BEGIN -- Claim Validations
      SELECT @nCount = COUNT(DISTINCT ClaimId) FROM #tmp_HeaderRecords

      IF @nCount = 0
      BEGIN
         SET @Msg = 'No Claim exist with the specified criteria.'
         RETURN -1613
      END

      IF @nCount > 1
      BEGIN
         SET @Msg = 'More than one Claim Id present for this Claim in the source database.'
         RETURN -1614
      END
   END


   -- Get the Phased Claim information from the main claim
   IF EXISTS(SELECT 1 FROM #tmp_HeaderRecords WHERE PhasedIndicator = 'C' AND Claim IS NOT NULL)  AND
      @ToClaimNumber IS NOT NULL -- Just skip RBE cases.
   BEGIN

      IF @bDebug = 1
         PRINT 'Gathering Phased Case for Composite Case...'

      SET @sSQL = 'SELECT Claim FROM ' + @ServerName + '.' + @DBName + '.dbo.tblPhasedClaims WHERE OtherClaim = ''' + @ClaimNumber + ''''

      INSERT INTO @tmp_PhasedClaim(PhasedClaim)
      EXEC (@sSQL)
      SET @sSQL = ''
      SELECT @sPhasedClaim = PhasedClaim FROM @tmp_PhasedClaim

      IF @bDebug = 1
         PRINT @sPhasedClaim

      IF dbo.fIsBlank(@sPhasedClaim) = 0 AND 
      NOT EXISTS(SELECT 1 FROM vwCases WHERE Claim = @sPhasedClaim) -- Copy Phased claim for given Compsite Claim if it does not present in the target datasbase.
      BEGIN

         IF @bDebug = 1
            PRINT 'Setting up to copy Phased Claim ...'

         INSERT INTO #tmp_HeaderRecords
         EXEC('
            SELECT
                  CaseId
               ,''' + @sPhasedClaim + '''
               ,ClaimId
               ,CustomerId
               ,a.Version
               ,a.PhasedIndicator
            FROM
               ' + @ServerName + '.' + @DBName + '.dbo.vwCases a
                  JOIN ' + @ServerName + '.' + @DBName + '.dbo.rtblCode b ON a.StatusCodeId = b.CodeId
            WHERE
               Claim = ''' + @sPhasedClaim + ''''
         )
      END

   END

   --IF @bDebug = 1
   --   SELECT * FROM #tmp_HeaderRecords


   BEGIN TRAN
   BEGIN TRY

      BEGIN -- Begin establish the master mapping between the Remote and Local databases for CustomerId, ClaimId and CaaseIds.
         SET @cs = CURSOR SCROLL KEYSET FOR SELECT CaseId, ClaimId, CustomerId, Claim --, SSN, StatusCode
               FROM #tmp_HeaderRecords ORDER BY CustomerId, Claim, CaseId, Version

         OPEN @cs

         FETCH FIRST FROM @cs INTO @sFromCaseId, @sFromClaimId, @sFromCustomerId, @sClaim --, @sSSN, @sAbbrev
         WHILE @@FETCH_STATUS = 0
         BEGIN

               IF NOT EXISTS(SELECT 1 FROM #tmp_CasesMapping a WHERE a.FromCustomerId = @sFromCustomerId AND a.ToCustomerId IS NOT NULL)
               BEGIN

                  IF @bDebug = 1
                     PRINT 'Started Processing Customer Info...'


                  IF dbo.fIsBlank(@sClaim) = 1 -- Blank Claim means it is a WEB case.
                  BEGIN
                     SET @sSQL = '
                        SELECT
                            ISNULL(Left(LastName, 1), ''X'') + ''XXXXX''      -- Scramble
                           ,ISNULL(Left(FirstName, 1), ''X'') + ''XXXXX''     -- Scramble
                           ,''X''        -- Scramble
                           ,DateOfBirth
                           ,DateOfDeath
                           ,bCitizen
                           ,dbo.fGetCodeId(b.Abbrev, ''FIT_Basis'')
                           ,Sex
                           ,bMarried
                           ,''000000000''       -- temp setting for SSN
                           ,ModifiedBy
                           ,ModifiedTime
                        FROM
                           ' + @ServerName + '.' + @DBName + '.dbo.tblCustomer a
                              LEFT JOIN ' + @ServerName + '.' + @DBName + '.dbo.rtblCode b ON a.FIT_Basis = b.CodeId
                        WHERE
                           CustomerId = ' + @sFromCustomerId
                  END
                  ELSE
                  BEGIN

                     SET @sSQL = '
                        SELECT
                            ISNULL(Left(LastName, 1), ''X'') + ''XXXXX''      -- Scramble
                           ,ISNULL(Left(FirstName, 1), ''X'') + ''XXXXX''     -- Scramble
                           ,''X''        -- Scramble
                           ,DateOfBirth
                           ,DateOfDeath
                           ,bCitizen
                           ,dbo.fGetCodeId(b.Abbrev, ''FIT_Basis'')
                           ,Sex
                           ,bMarried
                           ,''000000000''       -- temp setting for SSN
                           ,ModifiedBy
                           ,ModifiedTime
                        FROM
                           ' + @ServerName + '.' + @DBName + '.dbo.tblCustomer a
                              LEFT JOIN ' + @ServerName + '.' + @DBName + '.dbo.rtblCode b ON a.FIT_Basis = b.CodeId
                        WHERE
                           CustomerId = ' + @sFromCustomerId

                  END


                  INSERT INTO tblCustomer
                  (
                      LastName
                     ,FirstName
                     ,MiddleInitial
                     ,DateOfBirth
                     ,DateOfDeath
                     ,bCitizen
                     ,FIT_Basis
                     ,Sex
                     ,bMarried
                     ,SSN
                     ,ModifiedBy
                     ,ModifiedTime
                  )
                  EXEC(@sSQL)

                  SELECT @nId = SCOPE_IDENTITY()
                  SELECT @sToCustomerId = CAST(@nId AS VARCHAR(20))

                  SET @sSSNScramble = REPLICATE('0', 9 - LEN(CAST(@sToCustomerId AS VARCHAR(8)))) + CAST(@sToCustomerId AS VARCHAR(8))
                  UPDATE tblCustomer SET SSN = @sSSNScramble WHERE CustomerId = @nId

                  SET @nId = NULL


                  IF @bDebug = 1
                  BEGIN
                     PRINT 'Finished Processing Customer Info...'
                     PRINT 'CustomerId : ' + @sToCustomerId
                  END

               END

               IF NOT EXISTS(SELECT 1 FROM #tmp_CasesMapping a WHERE a.FromClaimId = @sFromClaimId AND a.ToClaimId IS NOT NULL)
               BEGIN

                  IF @bDebug = 1
                  BEGIN
                     PRINT 'Started Processing Claim Info...'
                  END

                  SET @sSQL = '
                     SELECT
                         ' + NULLIF ('''' + ISNULL(@sClaim, '') + '''', '''') + '
                        ,' + @sToCustomerId + '
                        ,dbo.fGetCodeId(e.Abbrev, ''AgencyCodes'')
                        ,dbo.fGetCodeId(c.Abbrev, ''StatusCodes'')
                        ,CSRSOffsetYears
                        ,bWindFall
                        ,ModifiedBy
                        ,ModifiedTime
                     FROM
                        ' + @ServerName + '.' + @DBName + '.dbo.tblClaim a
                           LEFT JOIN ' + @ServerName + '.' + @DBName + '.dbo.rtblCode c ON a.StatusCodeId = c.CodeId
                           LEFT JOIN ' + @ServerName + '.' + @DBName + '.dbo.rtblCode e ON a.AgencyCodeId = e.CodeId
                     WHERE
                        ClaimId = ' + @sFromClaimId

                  INSERT INTO tblClaim
                  (
                      Claim
                     ,CustomerId
                     ,AgencyCodeId
                     ,StatusCodeId
                     ,CSRSOffsetYears
                     ,bWindFall
                     ,ModifiedBy
                     ,ModifiedTime
                  )
                  EXEC(@sSQL)

                  SELECT @nId = SCOPE_IDENTITY()
                  SELECT @sToClaimId = CAST(@nId AS VARCHAR(20))
                  SET @nId = NULL


                  -- Set basic tblPhasedClaims table
                  IF EXISTS(SELECT 1 FROM #tmp_HeaderRecords a WHERE a.Claim = @sClaim AND a.PhasedIndicator = 'P') AND
                     @sClaim IS NOT NULL -- Just skip RBE cases.
                  BEGIN
                     IF NOT EXISTS(SELECT 1 FROM tblPhasedClaims WHERE Claim = @sClaim)
                     BEGIN
                        INSERT INTO tblPhasedClaims (Claim, PhasedType) VALUES (@sClaim, 1)
                     END
                  END

                  IF EXISTS(SELECT 1 FROM #tmp_HeaderRecords a WHERE a.Claim = @sClaim AND a.PhasedIndicator = 'C') AND
                     @sClaim IS NOT NULL -- Just skip RBE cases.
                  BEGIN
                     IF NOT EXISTS(SELECT 1 FROM tblPhasedClaims WHERE Claim = @sClaim) 
                     BEGIN
                        INSERT INTO tblPhasedClaims (Claim, PhasedType, OtherClaim) VALUES (@sClaim, 4, @sPhasedClaim)
                        UPDATE tblPhasedClaims SET OtherClaim = @sClaim, PhasedType = 2 WHERE Claim = @sPhasedClaim
                     END
                  END

                  SET @sSQL = ''

                  INSERT INTO #tmp_LSRecords
                  (
                      PaymentId
                     ,PayeeId
                     ,ToClaimId
                  )
                  EXEC('
                     SELECT
                         b.LumpsumPaymentId
                        ,c.LumpsumPayeeId
                        ,' + @sToClaimId + ' 
                     FROM
                        ' + @ServerName + '.' + @DBName + '.dbo.vwCases a
                           JOIN ' + @ServerName + '.' + @DBName + '.dbo.tblLumpSumPayment b ON a.ClaimId = b.ClaimId
                           LEFT JOIN ' + @ServerName + '.' + @DBName + '.dbo.tblLumpSumPayee c ON b.LumpsumPaymentId = c.LumpsumPaymentId
                     WHERE
                        a.ClaimId = ' + @sFromClaimId
                  )

                  IF @bDebug = 1
                  BEGIN
                     PRINT 'Finished Processing Claim Info...'
                     PRINT 'ClaimId :' + @sToClaimId
                  END

               END

               IF NOT EXISTS(SELECT 1 FROM #tmp_CasesMapping a WHERE a.FromCaseId = @sFromCaseId AND a.ToCaseId IS NOT NULL)
               BEGIN

                  IF @bDebug = 1
                  BEGIN
                     PRINT 'Started Processing Case Info...'
                  END

                  SET @sSQL = '
                     SELECT
                         Section
                        ,DateOfBirth
                        ,CASE WHEN dbo.fIsBlank(HBControlNumber) = 0 AND
   HBControlNumber <> ''000000000'' THEN ''' + @sSSNScramble + ''' ELSE HBControlNumber END       -- Scramble HB Control Number same as SSN
                        ,dbo.fGetCodeId(c.Abbrev, ''StatusCodes'')
                        ,AgencySCD
                        ,Post56MilCode
                        ,ErrorCode
                        ,dbo.fGetCodeId(d.Abbrev, ''PayStatusCodes'')
                        ,a.AddedDate
                        ,a.UpdatedDate
                        ,a.AddedBy
                        ,a.UpdatedBy
                        ,ActuaryCode
                        ,Specialist
                        ,Reviewer
                        ,RetireLawCode
                        ,DateOfDeath
                        ,' + @sToClaimId + '
                        ,Version
                        ,VersionComment
                        ,VersionDate
                        ,bVersionLock
                        ,a.bVisible
                        ,DateTriggered
                        ,EstimatedAnnualBenefit
                        ,PhasedIndicator
                        ,PhasedFactor
                        ,ModifiedBy
                        ,ModifiedTime
                     FROM
                        ' + @ServerName + '.' + @DBName + '.dbo.tblCases a
                           LEFT JOIN ' + @ServerName + '.' + @DBName + '.dbo.rtblCode c ON a.StatusCodeId = c.CodeId
                           LEFT JOIN ' + @ServerName + '.' + @DBName + '.dbo.rtblCode d ON a.PayStatusCodeId = d.CodeId
                     WHERE
                        CaseId = ' + @sFromCaseId

                  INSERT INTO tblCases
                  (
                      Section
                     ,DateOfBirth
                     ,HBControlNumber
                     ,StatusCodeId
                     ,AgencySCD
                     ,Post56milCode
                     ,ErrorCode
                     ,PayStatusCodeId
                     ,AddedDate
                     ,UpdatedDate
                     ,AddedBy
                     ,UpdatedBy
                     ,ActuaryCode
                     ,Specialist
                     ,Reviewer
                     ,RetireLawCode
                     ,DateOfDeath
                     ,ClaimId
                     ,Version
                     ,VersionComment
                     ,VersionDate
                     ,bVersionLock
                     ,bVisible
                     ,DateTriggered
                     ,EstimatedAnnualBenefit
                     ,PhasedIndicator
                     ,PhasedFactor
                     ,ModifiedBy
                     ,ModifiedTime
                  )
                  EXEC(@sSQL)

                  SELECT @nId = SCOPE_IDENTITY()
                  SET @sToCaseId = CAST(@nId AS VARCHAR(20))
                  SET @nId = NULL


                  BEGIN -- Begin setting specialist information if required.
                     IF dbo.fIsBlank(@ToSpecialist) <> 1 AND
                        EXISTS(SELECT 1 FROM rvwUserList where Login = @ToSpecialist)
                     BEGIN
                        UPDATE tblCases set Specialist = @ToSpecialist WHERE CaseId = @sToCaseId
                     END
                  END

                  IF @bDebug = 1
                  BEGIN
                     PRINT 'Finished Processing Case Info...'
                     PRINT 'CaseId : ' + @sToCaseId
                  END

               END

               INSERT INTO #tmp_CasesMapping
               (
                   FromCustomerId
                  ,ToCustomerId
                  ,FromClaimId
                  ,ToClaimId
                  ,FromCaseId
                  ,ToCaseId
               )
               VALUES
               (
                   @sFromCustomerId
                  ,@sToCustomerId
                  ,@sFromClaimId
                  ,@sToClaimId
                  ,@sFromCaseId
                  ,@sToCaseId

               )


            FETCH NEXT FROM @cs INTO @sFromCaseId, @sFromClaimId, @sFromCustomerId, @sClaim --, @sSSN, @sAbbrev
         END
         CLOSE @cs
         DEALLOCATE @cs
      END

      --IF @bDebug = 1
      --   SELECT * FROM #tmp_CasesMapping
      
       SET @sToClaimId = NULL
       SET @sToCustomerId  = NULL


      BEGIN -- Begin copy information associated with CustomerId (such as tblService, tblSalaries, tblContributionSummary....

         -- Note: UNION removes the duplicates in FromCustomerId in the #tmp_CasesMapping
         SELECT DISTINCT FromCustomerId, ToCustomerId INTO #tmp_UniqueCustomerMapping FROM #tmp_CasesMapping

         SET @sSQL = '   SELECT FromCustomerId, ToCustomerId, ''Service'', b.ServiceId
                  FROM #tmp_UniqueCustomerMapping a JOIN ' + @ServerName + '.' + @DBName + '.dbo.tblService b on a.FromCustomerId = b.CustomerId
                  union
                  SELECT FromCustomerId, ToCustomerId, ''Salaries'', b.SalaryId
                  FROM #tmp_UniqueCustomerMapping a JOIN ' + @ServerName + '.' + @DBName + '.dbo.tblSalaries b on a.FromCustomerId = b.CustomerId
                  union
                  SELECT FromCustomerId, ToCustomerId, ''Contributions'', b.ContributionId
                  FROM #tmp_UniqueCustomerMapping a JOIN ' + @ServerName + '.' + @DBName + '.dbo.tblContributions b on a.FromCustomerId = b.CustomerId
                  union
                  SELECT FromCustomerId, ToCustomerId, ''LifeInsurance'', b.LifeInsuranceId
                  FROM #tmp_UniqueCustomerMapping a JOIN ' + @ServerName + '.' + @DBName + '.dbo.tblLifeInsurance b on a.FromCustomerId = b.CustomerId
                  union
                  SELECT FromCustomerId, ToCustomerId, ''HBChanges'', b.HBChangeId
                  FROM #tmp_UniqueCustomerMapping a JOIN ' + @ServerName + '.' + @DBName + '.dbo.tblHBChanges b on a.FromCustomerId = b.CustomerId
                  union
                  SELECT FromCustomerId, ToCustomerId, ''MilitaryInfo'', b.MilitaryId
                  FROM #tmp_UniqueCustomerMapping a JOIN ' + @ServerName + '.' + @DBName + '.dbo.tblMilitaryInfo b on a.FromCustomerId = b.CustomerId
                  union
                  SELECT FromCustomerId, ToCustomerId, ''Survivors'', b.SurvivorId
                  FROM #tmp_UniqueCustomerMapping a JOIN ' + @ServerName + '.' + @DBName + '.dbo.tblSurvivors b on a.FromCustomerId = b.CustomerId
                  union
                  SELECT FromCustomerId, ToCustomerId, ''ContributionSummary'', b.ContributionSummaryId
                  FROM #tmp_UniqueCustomerMapping a JOIN ' + @ServerName + '.' + @DBName + '.dbo.tblContributionSummary b on a.FromCustomerId = b.CustomerId
                  union
                  SELECT FromCustomerId, ToCustomerId, ''ServiceSummary'', b.ServiceSummaryId
                  FROM #tmp_UniqueCustomerMapping a JOIN ' + @ServerName + '.' + @DBName + '.dbo.tblServiceSummary b on a.FromCustomerId = b.CustomerId
                  union
                  SELECT FromCustomerId, ToCustomerId, ''SalarySummary'', b.SalarySummaryId
                  FROM #tmp_UniqueCustomerMapping a JOIN ' + @ServerName + '.' + @DBName + '.dbo.tblSalarySummary b on a.FromCustomerId = b.CustomerId
                  union
                  SELECT FromCustomerId, ToCustomerId, ''ExcessDeductions'', b.ExcessDeductionId
                  FROM #tmp_UniqueCustomerMapping a JOIN ' + @ServerName + '.' + @DBName + '.dbo.tblExcessDeductions b on a.FromCustomerId = b.CustomerId
                  union
                  SELECT FromCustomerId, ToCustomerId, ''Disability'', b.DisabilityId
                  FROM #tmp_UniqueCustomerMapping a JOIN ' + @ServerName + '.' + @DBName + '.dbo.tblDisability b on a.FromCustomerId = b.CustomerId
                  union
                  SELECT FromCustomerId, ToCustomerId, ''ContactData'', b.ContactId
                  FROM #tmp_UniqueCustomerMapping a JOIN ' + @ServerName + '.' + @DBName + '.dbo.tblContactData b on a.FromCustomerId = b.CustomerId
                  union
                  SELECT FromCustomerId, ToCustomerId, ''TimeConverterData'', b.TimeConverterId
                  FROM #tmp_UniqueCustomerMapping a JOIN ' + @ServerName + '.' + @DBName + '.dbo.tblTimeConverterData b on a.FromCustomerId = b.CustomerId
               '

         TRUNCATE TABLE #tmp_CustomerRecords

         --IF @bDebug = 1
         --   PRINT @sSQL

         INSERT INTO #tmp_CustomerRecords(FromCustomerId, ToCustomerId, RecordType, FromRecordId)
         EXEC(@sSQL)

         --IF @bDebug = 1
         --   SELECT * FROM #tmp_CustomerRecords
      END

      SET @csCustomerRecords = CURSOR SCROLL KEYSET FOR
      SELECT Distinct FromCustomerId, ToCustomerId, RecordType, FromRecordId
         FROM #tmp_CustomerRecords ORDER BY FromCustomerId, ToCustomerId, RecordType, FromRecordId

      OPEN @csCustomerRecords

      FETCH FIRST FROM @csCustomerRecords INTO @sFromCustomerId, @sToCustomerId, @RecordType, @sFromRecordId
      WHILE @@FETCH_STATUS = 0
      BEGIN

         IF @bDebug = 1
         BEGIN
            PRINT 'Started Processing ' + @RecordType + ' [CustomerId: ' + @sFromCustomerId + ', Id: ' + @sFromRecordId + '].'
         END

         SET @nId = NULL
         SET @sSQL = ''

         IF @RecordType = 'Salaries'
         BEGIN
                SET @sSQL = '
                  SELECT DISTINCT
                     ' + @sToCustomerId + '
                     ,SalaryDate
                     ,bActual
                     ,Salary
                     ,Deposit
                     ,TourA
                     ,TourB
                     ,dbo.fGetCodeId(b.Abbrev, ''SalaryTypes'')
                     ,ModifiedBy
                     ,ModifiedTime
                  FROM
                     ' + @ServerName + '.' + @DBName + '.dbo.tblSalaries a
                        LEFT JOIN ' + @ServerName + '.' + @DBName + '.dbo.rtblCode b ON a.SalaryTypeId = b.CodeId
                  WHERE
                     CustomerId = ' + @sFromCustomerId + ' and
                     SalaryId = ' + @sFromRecordId

               --IF @bDebug = 1
               --   PRINT @sSQL

               INSERT INTO tblSalaries
               (

                   CustomerId
                  ,SalaryDate
                  ,bActual
                  ,Salary
                  ,Deposit
                  ,TourA
                  ,TourB
                  ,SalaryTypeId
                  ,ModifiedBy
                  ,ModifiedTime
               )
               EXEC(@sSQL)

         END
         ELSE IF @RecordType = 'Contributions'
         BEGIN
               SET @sSQL = '
                  SELECT
                     ' + @sToCustomerId + '
                     ,RetirementSystem
                     ,Amount
                     ,ContributionYear
                     ,Earnings
                     ,ISNULL(dbo.fGetCodeId(b.Abbrev, ''AS_YearlyMultiplier''), dbo.fGetCodeId(b.Abbrev, ''AS_StaticMultiplier''))
                     ,ModifiedBy
                     ,ModifiedTime
                  FROM
                     ' + @ServerName + '.' + @DBName + '.dbo.tblContributions a
                        LEFT JOIN ' + @ServerName + '.' + @DBName + '.dbo.rtblCode b ON a.ASCodeId = b.CodeId
                  WHERE
                     CustomerId = ' + @sFromCustomerId + ' and
                     ContributionId = ' + @sFromRecordId

               --IF @bDebug = 1
               --   PRINT @sSQL

               INSERT INTO tblContributions
               (
                   CustomerId
                  ,RetirementSystem
                  ,Amount
                  ,ContributionYear
                  ,Earnings
                  ,ASCodeId
                  ,ModifiedBy
                  ,ModifiedTime
               )
               EXEC(@sSQL)
         END
         ELSE IF @RecordType = 'LifeInsurance'
         BEGIN
               SET @sSQL = '
                  SELECT
                     ' + @sToCustomerId + '
                     ,EffectiveDate
                     ,Basic
                     ,dbo.fGetCodeId(b.Abbrev, ''Post-RetirementReductionCodes'')
                     ,Standard
                     ,dbo.fGetCodeId(c.Abbrev, ''AdditionalCodes'')
                     ,dbo.fGetCodeId(d.abbrev, ''FamilyCodes'')
                     ,LivingBenefitsDate
                     ,ModifiedBy
                     ,ModifiedTime
                  FROM
                     ' + @ServerName + '.' + @DBName + '.dbo.tblLifeInsurance a
                        LEFT JOIN ' + @ServerName + '.' + @DBName + '.dbo.rtblCode b ON a.PRReductionCodeId = b.CodeId
                        LEFT JOIN ' + @ServerName + '.' + @DBName + '.dbo.rtblCode c ON a.AdditionalCodeId = c.CodeId
                        LEFT JOIN ' + @ServerName + '.' + @DBName + '.dbo.rtblCode d ON a.FamilyCodeId = d.CodeId
                  WHERE
                     CustomerId = ' + @sFromCustomerId + ' and
                     LifeInsuranceId = ' + @sFromRecordId

               --IF @bDebug = 1
               --   PRINT @sSQL

               INSERT INTO tblLifeInsurance
               (
                   CustomerId
                  ,EffectiveDate
                  ,Basic
                  ,PRReductionCodeId
                  ,Standard
                  ,AdditionalCodeId
                  ,FamilyCodeId
                  ,LivingBenefitsDate
                  ,ModifiedBy
                  ,ModifiedTime
               )
               EXEC(@sSQL)

         END
         ELSE IF @RecordType = 'HBChanges'
         BEGIN
            SET @sSQL = '
               SELECT
                  ' + @sToCustomerId + '
                  ,EffectiveDate
                  ,PlanCode
                  ,ModifiedBy
                  ,ModifiedTime
               FROM
                  ' + @ServerName + '.' + @DBName + '.dbo.tblHBChanges
               WHERE
                  CustomerId = ' + @sFromCustomerId + ' and
                  HBChangeId = ' + @sFromRecordId

            --IF @bDebug = 1
            --   PRINT @sSQL

            INSERT INTO tblHBChanges
            (
                CustomerId
               ,EffectiveDate
               ,PlanCode
               ,ModifiedBy
               ,ModifiedTime
            )
            EXEC(@sSQL)
         END
         ELSE IF @RecordType = 'MilitaryInfo'
         BEGIN
            SET @sSQL = 'SELECT
                      ' + @sToCustomerId + '
                      ,MilitaryBranch
                      ,MRP_Status
                      ,MilitarySurvivorBenefit
                      ,ModifiedBy
                      ,ModifiedTime
                  FROM
                    ' + @ServerName + '.' + @DBName + '.dbo.tblMilitaryInfo
                  WHERE
                    CustomerId = ' + @sFromCustomerId + ' and
                    MilitaryId = ' + @sFromRecordId

            --IF @bDebug = 1
            --   PRINT @sSQL

            INSERT INTO tblMilitaryInfo
            (
                CustomerId
               ,MilitaryBranch
               ,MRP_Status
               ,MilitarySurvivorBenefit
               ,ModifiedBy
               ,ModifiedTime
            )
            EXEC(@sSQL)

         END
         ELSE IF @RecordType = 'Survivors'
         BEGIN
               SET @sSQL = '
                  SELECT
                     ' + @sToCustomerId + '
                     ,''000000000''
                     ,ISNULL(Left(LastName, 1), ''X'') + ''XXXXX''
                     ,ISNULL(Left(FirstName, 1), ''X'') + ''XXXXX''
                     ,''X''
                     ,DateOfBirth
                     ,dbo.fGetCodeId(e.Abbrev, ''SurvivorCodes'')
                     ,bCitizen
                     ,dbo.fGetCodeId(d.Abbrev, ''Survivor_FIT_Basis'')
                     ,PartialAmount
                     ,dbo.fGetCodeId(b.Abbrev, ''SurvivorTypes'')
                     ,dbo.fGetCodeId(c.Abbrev, ''RelationTypes'')
                     ,ModifiedBy
                     ,ModifiedTime
                  FROM
                     ' + @ServerName + '.' + @DBName + '.dbo.tblSurvivors a
                        LEFT JOIN ' + @ServerName + '.' + @DBName + '.dbo.rtblCode b ON a.SurvivorTypeId = b.CodeId
                        LEFT JOIN ' + @ServerName + '.' + @DBName + '.dbo.rtblCode c ON a.RelationCodeId = c.CodeId
                        LEFT JOIN ' + @ServerName + '.' + @DBName + '.dbo.rtblCode e ON a.BaseTypeId = e.CodeId
                        LEFT JOIN ' + @ServerName + '.' + @DBName + '.dbo.rtblCode d ON a.Survivor_FIT_Basis = d.CodeId
                  WHERE
                    CustomerId = ' + @sFromCustomerId + ' and
                    SurvivorId = ' + @sFromRecordId

               --IF @bDebug = 1
               --   PRINT @sSQL

               INSERT INTO tblSurvivors
               (
                   CustomerId
                  ,SSN
                  ,LastName
                  ,FirstName
                  ,MiddleInitial
                  ,DateOfBirth
                  ,BaseTypeId
                  ,bCitizen
                  ,Survivor_FIT_Basis
                  ,PartialAmount
                  ,SurvivorTypeId
                  ,RelationCodeId
                  ,ModifiedBy
                  ,ModifiedTime
               )

               EXEC(@sSQL)

         END
         ELSE IF @RecordType = 'ContributionSummary'
         BEGIN
               SET @sSQL = '
                  SELECT
                     ' + @sToCustomerId + '
                     ,TotalExcess
                     ,StartDateOfDeductions
                     ,VoluntaryContrib
                     ,Interest
                     ,PaidDeposit
                     ,PaidRedeposit
                     ,TotalDue
                     ,StartDateOfContributions
                     ,EndDateOfContributions
                     ,BEDB_DepositAmount
                     ,BEDB_DepositStartDate
                     ,BEDB_DepositEndDate
                     ,ModifiedBy
                     ,ModifiedTime
                  FROM
                     ' + @ServerName + '.' + @DBName + '.dbo.tblContributionSummary
                  WHERE
                     CustomerId = ' + @sFromCustomerId + ' and
                     ContributionSummaryId = ' + @sFromRecordId

               --IF @bDebug = 1
               --   PRINT @sSQL

               INSERT INTO tblContributionSummary
               (
                   CustomerId
                  ,TotalExcess
                  ,StartDateOfDeductions
                  ,VoluntaryContrib
                  ,Interest
                  ,PaidDeposit
                  ,PaidRedeposit
                  ,TotalDue
                  ,StartDateOfContributions
                  ,EndDateOfContributions
                  ,BEDB_DepositAmount
                  ,BEDB_DepositStartDate
                  ,BEDB_DepositEndDate
                  ,ModifiedBy
                  ,ModifiedTime
               )
               EXEC (@sSQL)

         END
         ELSE IF @RecordType = 'ServiceSummary'
         BEGIN
               SET @sSQL = '
                  SELECT
                     ' + @sToCustomerId + '
                     ,FERSYears
                     ,FERSMonths
                     ,CSRSYears
                     ,CSRSMonths
                     ,OWCPYears
                     ,OWCPMonths
                     ,OWCPEnhancement
                     ,CaseType
                     ,dbo.fGetCodeId(c.Abbrev, ''SepCodes'')
                     ,FrozenUSL
                     ,FinalUSL
                     ,ProjectedSickLeave
                     ,bCalcWithUSL
                     ,PartTimeService
                     ,ModifiedBy
                     ,ModifiedTime
                     ,LastDayOfPay
                  FROM
                     ' + @ServerName + '.' + @DBName + '.dbo.tblServiceSummary b
                        JOIN ' + @ServerName + '.' + @DBName + '.dbo.rtblCode c ON b.RetirementTypeId = c.CodeId
                  WHERE
                     CustomerId = ' + @sFromCustomerId + ' AND
                     ServiceSummaryId = ' + @sFromRecordId

               --IF @bDebug = 1
               --   PRINT @sSQL

               INSERT INTO tblServiceSummary
               (
                   CustomerId
                  ,FERSYears
                  ,FERSMonths
                  ,CSRSYears
                  ,CSRSMonths
                  ,OWCPYears
                  ,OWCPMonths
                  ,OWCPEnhancement
                  ,CaseType
                  ,RetirementTypeId
                  ,FrozenUSL
                  ,FinalUSL
                  ,ProjectedSickLeave
                  ,bCalcWithUSL
                  ,PartTimeService
                  ,ModifiedBy
                  ,ModifiedTime
                  ,LastDayOfPay
               )
               EXEC(@sSQL)
         END
         ELSE IF @RecordType = 'SalarySummary'
         BEGIN
               SET @sSQL = '
                  SELECT
                     ' + @sToCustomerId + '
                     ,DepositTime
                     ,AvgSalaryComparison
                     ,PartTimeSalary
                     ,PartTimeSalCompare
                     ,BEDB_FinalSalary
                     ,ModifiedBy
                     ,ModifiedTime
                  FROM
                     ' + @ServerName + '.' + @DBName + '.dbo.tblSalarySummary
                  WHERE
                     CustomerId = ' + @sFromCustomerId + ' AND
                     SalarySummaryId = ' + @sFromRecordId

               --IF @bDebug = 1
               --   PRINT @sSQL

               INSERT INTO tblSalarySummary
               (
                   CustomerId
                  ,DepositTime
                  ,AvgSalaryComparison
                  ,PartTimeSalary
                  ,PartTimeSalCompare
                  ,BEDB_FinalSalary
                  ,ModifiedBy
                  ,ModifiedTime
               )
               EXEC(@sSQL)
         END
         ELSE IF @RecordType = 'ExcessDeductions'
         BEGIN
            SET @sSQL = '
                  SELECT
                     ' + @sToCustomerId + '
                     ,DeductionYear
                     ,Amount
                     ,ModifiedBy
                     ,ModifiedTime
                  FROM
                     ' + @ServerName + '.' + @DBName + '.dbo.tblExcessDeductions
                  WHERE
                     CustomerId = ' + @sFromCustomerId + ' AND
                     ExcessDeductionId = ' + @sFromRecordId


               --IF @bDebug = 1
               --   PRINT @sSQL

               INSERT INTO tblExcessDeductions
               (
                   CustomerId
                  ,DeductionYear
                  ,Amount
                  ,ModifiedBy
                  ,ModifiedTime
               )
               EXEC(@sSQL)
         END
         ELSE IF @RecordType = 'Disability'
         BEGIN
               SET @sSQL = '
                  SELECT
                     ' + @sToCustomerId + '
                     ,StartDate
                     ,DisabilityCode
                     ,DisabilityRate
                     ,ExamInterval
                     ,NextExamDate
                     ,FiledByDept
                     ,ModifiedBy
                     ,ModifiedTime
                  FROM
                     ' + @ServerName + '.' + @DBName + '.dbo.tblDisability
                  WHERE
                     CustomerId = ' + @sFromCustomerId + ' and
                     DisabilityId = ' + @sFromRecordId

               --IF @bDebug = 1
               --   PRINT @sSQL

               INSERT INTO tblDisability
               (
                   CustomerId
                  ,StartDate
                  ,DisabilityCode
                  ,DisabilityRate
                  ,ExamInterval
                  ,NextExamDate
                  ,FiledByDept
                  ,ModifiedBy
                  ,ModifiedTime
               )
               EXEC(@sSQL)
         END
         ELSE IF @RecordType = 'ContactData'
         BEGIN
               SET @sSQL = '
                  SELECT
                     ' + @sToCustomerId + '
                     ,CASE WHEN Address1 IS NOT NULL THEN LEFT(Address1, 1) + ''XXXXX'' ELSE NULL END
                     ,CASE WHEN Address2 IS NOT NULL THEN ''0 No Street'' ELSE NULL END
                     ,CASE WHEN Address3 IS NOT NULL THEN ''No City, DC 20415'' ELSE NULL END
                     ,'' ''
                     ,'' ''
                     ,'' ''
                     ,CASE WHEN FullAddress1 IS NOT NULL THEN LEFT(FullAddress1, 1) + ''XXXXX'' ELSE NULL END
                     ,CASE WHEN FullAddress2 IS NOT NULL THEN ''0 No Street'' ELSE NULL END
                     ,CASE WHEN FullAddress3 IS NOT NULL THEN ''No City, DC 20415'' ELSE NULL END
                     ,'' ''
                     ,'' ''
                     ,'' ''
                     ,CASE WHEN PhoneNumber IS NOT NULL THEN ''000000000'' ELSE '' '' END
                     ,CASE WHEN EMail IS NOT NULL THEN ''FACES@opm.dev'' ELSE '' '' END
                     ,''000000000''
                     ,''000000000''
                     ,''C''
                     ,AddressChangeDate
                     ,dbo.fGetCodeId(''500'', ''GeoCodes'')
                     ,''20415''
                     ,dbo.fGetCodeId(b.Abbrev, ''PayeeTypes'')
                     ,bForeignAddress
                     ,MFAddressChangeDate
                     ,ModifiedBy
                     ,ModifiedTime
                  FROM
                     ' + @ServerName + '.' + @DBName + '.dbo.tblContactData a
                        LEFT JOIN ' + @ServerName + '.' + @DBName + '.dbo.rtblCode b ON a.PayeeTypeId = b.CodeId
                  WHERE
                     CustomerId = ' + @sFromCustomerId + ' and
                     ContactId = ' + @sFromRecordId

               --IF @bDebug = 1
               --   PRINT @sSQL

               INSERT INTO tblContactData
               (
                   CustomerId
                  ,Address1
                  ,Address2
                  ,Address3
                  ,Address4
                  ,Address5
                  ,Address6
                  ,FullAddress1
                  ,FullAddress2
                  ,FullAddress3
                  ,FullAddress4
                  ,FullAddress5
                  ,FullAddress6
                  ,PhoneNumber
                  ,EMail
                  ,EFTRoutingNumber
                  ,BankAccountNumber
                  ,AccountType
                  ,AddressChangeDate
                  ,GeoCodeId
                  ,ZipCode
                  ,PayeeTypeId
                  ,bForeignAddress
                  ,MFAddressChangeDate
                  ,ModifiedBy
                  ,ModifiedTime
               )
               EXEC (@sSQL)

         END
         ELSE IF @RecordType = 'TimeConverterData'
         BEGIN
             SET @sSQL = '
                  SELECT
                     ' + @sToCustomerId + '
                     ,cast(Period as int) as Period
                     ,Multiplier
                     ,RetirementSystem
                     ,Calculation
                     ,StartDate
                     ,EndDate
                     ,TimeWorked
                     ,PartTimeMultiplier
                     ,SpecialCases
                     ,NonDutyDate
                     ,DutyDate
                     ,TourA1
                     ,TourB1
                     ,ModifiedBy
                     ,ModifiedTime
                  FROM
                     ' + @ServerName + '.' + @DBName + '.dbo.tblTimeConverterData
                  WHERE
                     CustomerId = ' + @sFromCustomerId + ' AND
                     TimeConverterId = ' + @sFromRecordId

            --IF @bDebug = 1
            --   PRINT @sSQL

            INSERT INTO tblTimeConverterData
            (
                CustomerId
               ,Period
               ,Multiplier
               ,RetirementSystem
               ,Calculation
               ,StartDate
               ,EndDate
               ,TimeWorked
               ,PartTimeMultiplier
               ,SpecialCases
               ,NonDutyDate
               ,DutyDate
               ,TourA1
               ,TourB1
               ,ModifiedBy
               ,ModifiedTime
            )
            EXEC(@sSQL)

         END
         ELSE IF @RecordType = 'Service'
         BEGIN
            SET @sSQL = '
               SELECT
                  ' + @sToCustomerId + '
                  ,ServiceDate
                  ,Amount
                  ,PartTime
                  ,Hours
                  ,TourA1
                  ,TourB1
                  ,GroupId
                  ,dbo.fGetCodeId(b.Abbrev, ''ServiceDesc'')
                  ,dbo.fGetCodeId(c.Abbrev, ''AmountTypes'')
                  ,dbo.fGetCodeId(d.Abbrev, ''RetSystems'')
                  ,dbo.fGetMultiplierCodeId(e.BeginDate, f.CodeAbbrev, f.CodeType)
                  ,ModifiedBy
                  ,ModifiedTime
               FROM
                  ' + @ServerName + '.' + @DBName + '.dbo.tblService a
                     LEFT JOIN ' + @ServerName + '.' + @DBName + '.dbo.rtblCode b ON a.ServiceTypeId = b.CodeId
                     LEFT JOIN ' + @ServerName + '.' + @DBName + '.dbo.rtblCode c ON a.AmountTypeId = c.CodeId
                     LEFT JOIN ' + @ServerName + '.' + @DBName + '.dbo.rtblCode d ON a.RetirementSystemId = d.CodeId
                     LEFT JOIN ' + @ServerName + '.' + @DBName + '.dbo.rtblMultiplierCodes e ON a.MultiplierCodeId = e.MultiplierCodeId
                        LEFT JOIN ' + @ServerName + '.' + @DBName + '.dbo.vwCodeList f ON e.CodeId = f.CodeId
               WHERE
                  CustomerId = ' + @sFromCustomerId + ' and
                  ServiceId = ' + @sFromRecordId

            --IF @bDebug = 1
            --   PRINT @sSQL

            INSERT INTO tblService
            (
                CustomerId
               ,ServiceDate
               ,Amount
               ,PartTime
               ,Hours
               ,TourA1
               ,TourB1
               ,GroupId
               ,ServiceTypeId
               ,AmountTypeId
               ,RetirementSystemId
               ,MultiplierCodeId
               ,ModifiedBy
               ,ModifiedTime
            )
            EXEC(@sSQL)

         END



         SELECT @nId = SCOPE_IDENTITY()
         -- the following build out the mapping with the inserted record.
         UPDATE #tmp_CustomerRecords set ToRecordId =  @nId where RecordType = @RecordType and FromCustomerId = @sFromCustomerId and FromRecordId = @sFromRecordId


         -- Post processing for certain records.
         IF @RecordType = 'Salaries'
         BEGIN
            IF @bDebug = 1
               PRINT 'Updating New ' + @RecordType + ' [CustomerId  ' + @sToCustomerId + ', Id: ' + CAST(@nId AS VARCHAR(10)) + '].'

            UPDATE
                  tblSalaries
               SET
                  MultiplierCodeId = AveSalCodeId
               FROM
                  rtblAveSalCodes a
                     JOIN rtblCode b ON a.CodeId = b.CodeId
               WHERE
                  CustomerId = @sToCustomerId AND
                  SalaryId  = @nId AND
                  tblSalaries.SalaryTypeId = b.CodeId AND
                  a.BeginDate = (
                     SELECT
                        MAX(BeginDate)
                     FROM
                        rtblAveSalCodes a1
                     WHERE
                        a1.CodeId = b.CodeId AND
                        a1.BeginDate <= tblSalaries.SalaryDate)
         END
         ELSE IF @RecordType = 'Survivors'
         BEGIN
            IF @bDebug = 1
               PRINT 'Updating New ' + @RecordType + ' [CustomerId  ' + @sToCustomerId + ', Id: ' + CAST(@nId AS VARCHAR(10)) + '].'

               UPDATE
                  tblSurvivors
               SET
                  SSN = REPLICATE('0', 9 - LEN(CAST(SurvivorId AS VARCHAR(8)))) + CAST(SurvivorId AS VARCHAR(8))
               WHERE
                  CustomerId = @sToCustomerId AND
                  SurvivorId  = @nId
         END
         FETCH NEXT FROM @csCustomerRecords INTO @sFromCustomerId, @sToCustomerId, @RecordType, @sFromRecordId
       END
      CLOSE @csCustomerRecords
      DEALLOCATE @csCustomerRecords

      --IF @bDebug = 1
      --   SELECT * FROM #tmp_CustomerRecords


      BEGIN -- Begin copy case table information.
         SET @csCaseRecords = CURSOR SCROLL KEYSET FOR SELECT FromCaseId, ToCaseId, ToClaimId FROM #tmp_CasesMapping ORDER BY FromCaseId, ToCaseId

         OPEN @csCaseRecords

         FETCH FIRST FROM @csCaseRecords INTO @sFromCaseId, @sToCaseId, @sToClaimId
         WHILE @@FETCH_STATUS = 0
         BEGIN

            SET @sSQL = 'SELECT
                  b.ToRecordId
               ,' + @sToCaseId + '
               ,a.ModifiedBy
               ,a.ModifiedTime
            FROM
               ' + @ServerName + '.' + @DBName + '.dbo.vwCaseMilitaryInfo a
                  JOIN #tmp_CustomerRecords b ON b.RecordType = ''MilitaryInfo'' and a.MilitaryId = b.FromRecordId and a.CustomerId = b.FromCustomerId
            WHERE
               CaseId = ' + @sFromCaseId

            --IF @bDebug = 1
            --   PRINT @sSQL

            INSERT INTO txCaseMilitaryInfo
            (
                MilitaryId
               ,CaseId
               ,ModifiedBy
               ,ModifiedTime
            )
            EXEC (@sSQL)

            SET @sSQL = 'SELECT
                  b.ToRecordId
               ,' + @sToCaseId + '
               ,a.ModifiedBy
               ,a.ModifiedTime
            FROM
               ' + @ServerName + '.' + @DBName + '.dbo.vwCaseHBChanges a
                  JOIN #tmp_CustomerRecords b ON b.RecordType = ''HBChanges'' and a.HBChangeId = b.FromRecordId and a.CustomerId = b.FromCustomerId
            WHERE
               CaseId = ' + @sFromCaseId

            --IF @bDebug = 1
            --   PRINT @sSQL

            INSERT INTO txCaseHBChanges
            (
                HBChangeId
               ,CaseId
               ,ModifiedBy
               ,ModifiedTime
            )
            EXEC (@sSQL)

            SET @sSQL = 'SELECT
                  b.ToRecordId
               ,' + @sToCaseId + '
               ,a.ModifiedBy
               ,a.ModifiedTime
            FROM
               ' + @ServerName + '.' + @DBName + '.dbo.vwCaseDisability a
                  JOIN #tmp_CustomerRecords b ON b.RecordType = ''Disability'' and a.DisabilityId = b.FromRecordId and a.CustomerId = b.FromCustomerId
            WHERE
               CaseId = ' + @sFromCaseId

            --IF @bDebug = 1
            --   PRINT @sSQL

            INSERT INTO txCaseDisability
            (
                DisabilityId
               ,CaseId
               ,ModifiedBy
               ,ModifiedTime
            )
            EXEC (@sSQL)


            SET @sSQL = 'SELECT
                  b.ToRecordId
               ,' + @sToCaseId + '
               ,a.ModifiedBy
               ,a.ModifiedTime
            FROM
               ' + @ServerName + '.' + @DBName + '.dbo.vwCaseContributionSummary a
                  JOIN #tmp_CustomerRecords b ON b.RecordType = ''ContributionSummary'' and a.ContributionSummaryId = b.FromRecordId and a.CustomerId = b.FromCustomerId
            WHERE
               CaseId = ' + @sFromCaseId

            --IF @bDebug = 1
            --   PRINT @sSQL

            INSERT INTO txCaseContributionSummary
            (
                ContributionSummaryId
               ,CaseId
               ,ModifiedBy
               ,ModifiedTime
            )
            EXEC (@sSQL)

            SET @sSQL = 'SELECT
                  b.ToRecordId
               ,' + @sToCaseId + '
               ,a.ModifiedBy
               ,a.ModifiedTime
            FROM
               ' + @ServerName + '.' + @DBName + '.dbo.vwCaseServiceSummary a
                  JOIN #tmp_CustomerRecords b ON b.RecordType = ''ServiceSummary'' and a.ServiceSummaryId = b.FromRecordId and a.CustomerId = b.FromCustomerId
            WHERE
               CaseId = ' + @sFromCaseId

            --IF @bDebug = 1
            --   PRINT @sSQL

            INSERT INTO txCaseServiceSummary
            (
                ServiceSummaryId
               ,CaseId
               ,ModifiedBy
               ,ModifiedTime
            )
            EXEC (@sSQL)


            SET @sSQL = 'SELECT
                  b.ToRecordId
               ,' + @sToCaseId + '
               ,a.ModifiedBy
               ,a.ModifiedTime
            FROM
               ' + @ServerName + '.' + @DBName + '.dbo.vwCaseSalarySummary a
                  JOIN #tmp_CustomerRecords b ON b.RecordType = ''SalarySummary'' and a.SalarySummaryId = b.FromRecordId and a.CustomerId = b.FromCustomerId
            WHERE
               CaseId = ' + @sFromCaseId

            --IF @bDebug = 1
            --   PRINT @sSQL

            INSERT INTO txCaseSalarySummary
            (
                SalarySummaryId
               ,CaseId
               ,ModifiedBy
               ,ModifiedTime
            )
            EXEC (@sSQL)


            SET @sSQL = 'SELECT
                  b.ToRecordId
               ,' + @sToCaseId + '
               ,a.ModifiedBy
               ,a.ModifiedTime
            FROM
               ' + @ServerName + '.' + @DBName + '.dbo.vwCaseContactData a
                  JOIN #tmp_CustomerRecords b ON b.RecordType = ''ContactData'' and a.ContactId = b.FromRecordId and a.CustomerId = b.FromCustomerId
            WHERE
               CaseId = ' + @sFromCaseId

            --IF @bDebug = 1
            --   PRINT @sSQL

            INSERT INTO txCaseContactData
            (
                ContactId
               ,CaseId
               ,ModifiedBy
               ,ModifiedTime
            )
            EXEC (@sSQL)


            SET @sSQL = 'SELECT
                  b.ToRecordId
               ,' + @sToCaseId + '
               ,a.ModifiedBy
               ,a.ModifiedTime
            FROM
               ' + @ServerName + '.' + @DBName + '.dbo.vwCaseService a
                  JOIN #tmp_CustomerRecords b ON b.RecordType = ''Service'' and a.ServiceId = b.FromRecordId and a.CustomerId = b.FromCustomerId
            WHERE
               CaseId = ' + @sFromCaseId

            --IF @bDebug = 1
            --   PRINT @sSQL

            INSERT INTO txCaseService
            (
                ServiceId
               ,CaseId
               ,ModifiedBy
               ,ModifiedTime
            )
            EXEC (@sSQL)


            SET @sSQL = 'SELECT
                  b.ToRecordId
               ,' + @sToCaseId + '
               ,a.ModifiedBy
               ,a.ModifiedTime
            FROM
               ' + @ServerName + '.' + @DBName + '.dbo.vwCaseSalaries a
                  JOIN #tmp_CustomerRecords b ON b.RecordType = ''Salaries'' and a.SalaryId = b.FromRecordId and a.CustomerId = b.FromCustomerId
            WHERE
               CaseId = ' + @sFromCaseId

            --IF @bDebug = 1
            --   PRINT @sSQL

            INSERT INTO txCaseSalaries
            (
                SalaryId
               ,CaseId
               ,ModifiedBy
               ,ModifiedTime
            )
            EXEC (@sSQL)

            SET @sSQL = 'SELECT
                  b.ToRecordId
               ,' + @sToCaseId + '
               ,a.ModifiedBy
               ,a.ModifiedTime
            FROM
               ' + @ServerName + '.' + @DBName + '.dbo.vwCaseContributions a
                  JOIN #tmp_CustomerRecords b ON b.RecordType = ''Contributions'' and a.ContributionId = b.FromRecordId and a.CustomerId = b.FromCustomerId
            WHERE
               CaseId = ' + @sFromCaseId

            --IF @bDebug = 1
            --   PRINT @sSQL

            INSERT INTO txCaseContributions
            (
                ContributionId
               ,CaseId
               ,ModifiedBy
               ,ModifiedTime
            )
            EXEC (@sSQL)


            SET @sSQL = 'SELECT
                  b.ToRecordId
               ,' + @sToCaseId + '
               ,a.ModifiedBy
               ,a.ModifiedTime
            FROM
               ' + @ServerName + '.' + @DBName + '.dbo.vwCaseExcessDeductions a
                  JOIN #tmp_CustomerRecords b ON b.RecordType = ''ExcessDeductions'' and a.ExcessDeductionId = b.FromRecordId and a.CustomerId = b.FromCustomerId
            WHERE
               CaseId = ' + @sFromCaseId

            --IF @bDebug = 1
            --   PRINT @sSQL

            INSERT INTO txCaseExcessDeductions
            (
                ExcessDeductionId
               ,CaseId
               ,ModifiedBy
               ,ModifiedTime
            )
            EXEC (@sSQL)


            SET @sSQL = 'SELECT
                  b.ToRecordId
               ,' + @sToCaseId + '
               ,a.ModifiedBy
               ,a.ModifiedTime
            FROM
               ' + @ServerName + '.' + @DBName + '.dbo.vwCaseLifeInsurance a
                  JOIN #tmp_CustomerRecords b ON b.RecordType = ''LifeInsurance'' and a.LifeInsuranceId = b.FromRecordId and a.CustomerId = b.FromCustomerId
            WHERE
               CaseId = ' + @sFromCaseId

            --IF @bDebug = 1
            --   PRINT @sSQL

            INSERT INTO txCaseLifeInsurance
            (
                LifeInsuranceId
               ,CaseId
               ,ModifiedBy
               ,ModifiedTime
            )
            EXEC (@sSQL)


            SET @sSQL = 'SELECT
                  b.ToRecordId
               ,' + @sToCaseId + '
               ,a.ModifiedBy
               ,a.ModifiedTime
            FROM
               ' + @ServerName + '.' + @DBName + '.dbo.vwCaseTimeConverterData a
                  JOIN #tmp_CustomerRecords b ON b.RecordType = ''TimeConverterData'' and a.TimeConverterId = b.FromRecordId and a.CustomerId = b.FromCustomerId
            WHERE
               CaseId = ' + @sFromCaseId

            --IF @bDebug = 1
            --   PRINT @sSQL

            INSERT INTO txCaseTimeConverterData
            (
                TimeConverterId
               ,CaseId
               ,ModifiedBy
               ,ModifiedTime
            )
            EXEC (@sSQL)


            SET @sSQL = 'SELECT
                  b.ToRecordId
               ,' + @sToCaseId + '
               ,a.ModifiedBy
               ,a.ModifiedTime
            FROM
               ' + @ServerName + '.' + @DBName + '.dbo.vwCaseSurvivors a
                  JOIN #tmp_CustomerRecords b ON b.RecordType = ''Survivors'' and a.SurvivorId = b.FromRecordId and a.CustomerId = b.FromCustomerId
            WHERE
               CaseId = ' + @sFromCaseId

            --IF @bDebug = 1
            --   PRINT @sSQL

            INSERT INTO txCaseSurvivors
            (
                SurvivorId
               ,CaseId
               ,ModifiedBy
               ,ModifiedTime
            )
            EXEC (@sSQL)


            SET @sSQL = '
               SELECT DISTINCT
                   ' + @sToCaseId + '
                  ,' + @sToClaimId + '
                  ,DateAdded
                  ,dbo.fGetCodeId(b.Abbrev, ''StatusCodes'')
                  ,UserId
                  ,Action
                  ,RBCVersion
                  ,a.bVisible
               FROM
                  ' + @ServerName + '.' + @DBName + '.dbo.tblClaimHistory a
                     LEFT JOIN ' + @ServerName + '.' + @DBName + '.dbo.rtblCode b ON a.StatusCodeId = b.CodeId
               WHERE
                  CaseId = ' + @sFromCaseId

            --IF @bDebug = 1
            --   PRINT @sSQL

            INSERT INTO tblClaimHistory
            (
                CaseId
               ,ClaimId
               ,DateAdded
               ,StatusCodeId
               ,UserId
               ,Action
               ,RBCVersion
               ,bVisible)
            EXEC(@sSQL)

            SET @sSQL = '
               SELECT DISTINCT
                   ' + @sToCaseId + '
                  ,RunType
                  ,dbo.fGetCodeId(b.Abbrev, ''AddDeductCodes'')
                  ,Amount
                  ,Installments
                  ,bGenerated
                  ,bAlternate
               FROM
                  ' + @ServerName + '.' + @DBName + '.dbo.tblAdjustments a
                     LEFT JOIN ' + @ServerName + '.' + @DBName + '.dbo.rtblCode b ON a.AddDeductCodeId = b.CodeId
               WHERE
                  CaseId = ' + @sFromCaseId

            --IF @bDebug = 1
            --   PRINT @sSQL

            INSERT INTO tblAdjustments
            (
                CaseId
               ,RunType
               ,AddDeductCodeId
               ,Amount
               ,Installments
               ,bGenerated
               ,bAlternate)
            EXEC(@sSQL)

            SET @sSQL = '
               SELECT DISTINCT
                   ' + @sToCaseId + '
                  ,TotalService
                  ,FinalSalary
                  ,AverageSalary
                  ,TotalContribution
                  ,ProvRetCode
                  ,ServicePurchasedCode
                  ,dbo.fGetCodeId(b.Abbrev, ''FACE BRIEF - SepCodes'')
                  ,LIBasic
                  ,LIOptionBBase
                  ,LIStandard
                  ,LILivingBenefitsDate
                  ,MilitaryBranch
                  ,TotalMilitaryService
                  ,Post56Service
                  ,MilitaryContributions
                  ,VolContributions
                  ,VolContributionsInt
                  ,ContributionEmployee
                  ,VolContributionsAmt
                  ,DisabilityCode
                  ,DisabilityExamInterval
                  ,DisabilityNextExam
                  ,AATotal
                  ,AAFirstInstall
                  ,AATotalPre57Int
                  ,AAFirstPre57Int
                  ,CASE WHEN dbo.fIsBlank(CCN) = 0 THEN ''000000000'' ELSE NULL END
                  ,MilitaryLenOfService
                  ,Rate
                  ,bVCContributions
                  ,TotalUSL
                  ,bPopulated
                  ,LIOptionBBase_Org
                  ,RetirementType_Org
                  ,AAReduction
                  ,bCongressionalSurvivor
                  ,FERSUSLHours
                  ,CSRSUSLHours
                  ,FERSEligibleUSLHours
                  ,CSRSEligibleUSLHours
                  ,FERSUSLService
                  ,CSRSUSLService
                  ,IRS_PVF
               FROM
                  ' + @ServerName + '.' + @DBName + '.dbo.tblFBData a
                     LEFT JOIN ' + @ServerName + '.' + @DBName + '.dbo.rtblCode b ON a.RetirementTypeId = b.CodeId
               WHERE
                  CaseId = ' + @sFromCaseId

            --IF @bDebug = 1
            --   PRINT @sSQL

            INSERT INTO tblFBData
            (
                CaseId
               ,TotalService
               ,FinalSalary
               ,AverageSalary
               ,TotalContribution
               ,ProvRetCode
               ,ServicePurchasedCode
               ,RetirementTypeId
               ,LIBasic
               ,LIOptionBBase
               ,LIStandard
               ,LILivingBenefitsDate
               ,MilitaryBranch
               ,TotalMilitaryService
               ,Post56Service
               ,MilitaryContributions
               ,VolContributions
               ,VolContributionsInt
               ,ContributionEmployee
               ,VolContributionsAmt
               ,DisabilityCode
               ,DisabilityExamInterval
               ,DisabilityNextExam
               ,AATotal
               ,AAFirstInstall
               ,AATotalPre57Int
               ,AAFirstPre57Int
               ,CCN  -- CCN same as SSN
               ,MilitaryLenOfService
               ,Rate
               ,bVCContributions
               ,TotalUSL
               ,bPopulated
               ,LIOptionBBase_Org
               ,RetirementType_Org
               ,AAReduction
               ,bCongressionalSurvivor
               ,FERSUSLHours
               ,CSRSUSLHours
               ,FERSEligibleUSLHours
               ,CSRSEligibleUSLHours
               ,FERSUSLService
               ,CSRSUSLService
               ,IRS_PVF
            )
            EXEC(@sSQL)

            UPDATE tblFBData
            SET
����            CCN = (SELECT REPLICATE('0', 9 - LEN(CAST(b.CustomerId AS VARCHAR(8)))) + CAST(b.CustomerId AS VARCHAR(8)) 
                        FROM tblCustomer a join tblClaim b on a.CustomerId = b.CustomerId join tblCases c on b.ClaimId = c.ClaimId WHERE tblFBData.CaseId = c.CaseId)
            WHERE
����            CaseId = @sToCaseId AND
                CCN IS NOT NULL
            ;


            SET @sSQL = '
               SELECT DISTINCT
                   ' + @sToCaseId + '
                  ,ASUser_ContrYear
                  ,ASUser_BeginDate
                  ,bAnnuitySupplement
                  ,bOverRideAS
                  ,Installments
                  ,InstallmentBegin
               FROM
                  ' + @ServerName + '.' + @DBName + '.dbo.tblAnnuitySupplement
               WHERE
                  CaseId = ' + @sFromCaseId

            --IF @bDebug = 1
            --   PRINT @sSQL

            INSERT INTO tblAnnuitySupplement
            (
                CaseId
               ,ASUser_ContrYear
               ,ASUser_BeginDate
               ,bAnnuitySupplement
               ,bOverRideAS
               ,Installments
               ,InstallmentBegin
            )
            EXEC(@sSQL)

            SET @sSQL = '
                  SELECT DISTINCT
                      b.ToCaseId
                     ,' + @sToCaseId + '
                     ,bReissueCase
                  FROM
                     ' + @ServerName + '.' + @DBName + '.dbo.tblCaseRelation a
                        JOIN #tmp_CasesMapping b ON a.OriginalCaseId = b.FromCaseId
                  WHERE
                     GeneratedCaseId = ' + @sFromCaseId 


            --IF @bDebug = 1
            --   PRINT @sSQL

            INSERT INTO tblCaseRelation
            (
                OriginalCaseId
               ,GeneratedCaseId
               ,bReissueCase
            )
            EXEC(@sSQL)

            SET @sSQL = '
               SELECT DISTINCT
                   ' + @sToCaseId + '
                  ,ViewIndex
                  ,AverageSalary
                  ,Description
               FROM
                  ' + @ServerName + '.' + @DBName + '.dbo.tblAverageSalaries a
               WHERE
                  CaseId = ' + @sFromCaseId

            --IF @bDebug = 1
            --   PRINT @sSQL

            INSERT INTO tblAverageSalaries
            (
                CaseId
               ,ViewIndex
               ,AverageSalary
               ,Description
            )
            EXEC(@sSQL)

            SET @sSQL = '
               SELECT DISTINCT
                   ' + @sToCaseId + '
                  ,RunType
                  ,CSRSPrePhasedAnnual
                  ,FERSPrePhasedAnnual
                  ,CombinedPrePhasedAnnual
                  ,CSRSPhasedAnnual
                  ,FERSPhasedAnnual
                  ,PhasedActuarialReductionWithCola
                  ,CSRSPhasedAnnualUser
                  ,FERSPhasedAnnualUser
                  ,CSRSPhasedAnnualWithCOLA
                  ,FERSPhasedAnnualWithCOLA
                  ,FinalAnnual
                  ,IRS_1099R
               FROM
                  ' + @ServerName + '.' + @DBName + '.dbo.tblBenefitOutputReportData a
               WHERE
                  CaseId = ' + @sFromCaseId

            --IF @bDebug = 1
            --   PRINT @sSQL

            INSERT INTO tblBenefitOutputReportData
            (
                CaseId
               ,RunType
               ,CSRSPrePhasedAnnual
               ,FERSPrePhasedAnnual
               ,CombinedPrePhasedAnnual
               ,CSRSPhasedAnnual
               ,FERSPhasedAnnual
               ,PhasedActuarialReductionWithCola
               ,CSRSPhasedAnnualUser
               ,FERSPhasedAnnualUser
               ,CSRSPhasedAnnualWithCOLA
               ,FERSPhasedAnnualWithCOLA
               ,FinalAnnual
               ,IRS_1099R
            )
            EXEC(@sSQL)


            /* Jenn confirmed on 4/14/2023 that there is no PII in the ReportData columns. */
            SET @sSQL = '
               SELECT DISTINCT
                   ' + @sToCaseId + '
                  ,SeqNo
                  ,DateAdded
                  ,ReportData
               FROM
                  ' + @ServerName + '.' + @DBName + '.dbo.tblDepositReport a
               WHERE
                  CaseId = ' + @sFromCaseId

            --IF @bDebug = 1
            --   PRINT @sSQL

            INSERT INTO tblDepositReport
            (
                CaseId
               ,SeqNo
               ,DateAdded
               ,ReportData
            )
            EXEC(@sSQL)

            SET @sSQL = '
               SELECT DISTINCT
                   ' + @sToCaseId + '
                  ,CSRSLengthOfService
                  ,FERSLengthOfService
                  ,CSRSCurrentGross
                  ,FERSCurrentGross
                  ,FERSCurrentEffDate
                  ,CSRSAA
                  ,FERSAA
                  ,RateType
                  ,RateTypeDate
                  ,DisabilityAnnuityAmt
                  ,SSAMonthlyGross
                  ,SSAEffectiveDate
                  ,CSRSPTAvgSal
                  ,FTAvgSal
                  ,FERSProration
                  ,EndingTourDuty
                  ,FERSFTHours
                  ,FERSActualHrs
                  ,CSRSProration
                  ,CSRSPre86Svc
                  ,DisabilityMonthlyGross
                  ,CSRSCurrentEffDate
                  ,UnreducedSupp
                  ,ChildCount
                  ,PrimarySurvivorAmount
                  ,ChildSSAMonthlyAmount
                  ,ChildComputedRate
                  ,ChildPaidRate
                  ,RunType
                  ,OWCPEnhancement
               FROM
                  ' + @ServerName + '.' + @DBName + '.dbo.tblFERSData a
               WHERE
                  CaseId = ' + @sFromCaseId

            --IF @bDebug = 1
            --   PRINT @sSQL

            INSERT INTO tblFERSData
            (
                CaseId
               ,CSRSLengthOfService
               ,FERSLengthOfService
               ,CSRSCurrentGross
               ,FERSCurrentGross
               ,FERSCurrentEffDate
               ,CSRSAA
               ,FERSAA
               ,RateType
               ,RateTypeDate
               ,DisabilityAnnuityAmt
               ,SSAMonthlyGross
               ,SSAEffectiveDate
               ,CSRSPTAvgSal
               ,FTAvgSal
               ,FERSProration
               ,EndingTourDuty
               ,FERSFTHours
               ,FERSActualHrs
               ,CSRSProration
               ,CSRSPre86Svc
               ,DisabilityMonthlyGross
               ,CSRSCurrentEffDate
               ,UnreducedSupp
               ,ChildCount
               ,PrimarySurvivorAmount
               ,ChildSSAMonthlyAmount
               ,ChildComputedRate
               ,ChildPaidRate
               ,RunType
               ,OWCPEnhancement
            )
            EXEC(@sSQL)


            SET @sSQL = '
               SELECT DISTINCT
                   ' + @sToCaseId + '
                  ,RunType
                  ,PayLine
                  ,EffectiveDate
                  ,Age
                  ,CSRSCola
                  ,CSRSRate
                  ,CSRSEarnedRate
                  ,FERSCola
                  ,FERSRate
                  ,FERSRateNS
                  ,FERSEarnedRate
                  ,TotalGross
                  ,TotalEarnedRate
                  ,ProvRetCode
                  ,HBCode
                  ,HBPremium
                  ,Basic
                  ,PRR
                  ,OptionA
                  ,OptionB
                  ,OptionC
                  ,SSAMonthly
                  ,bMedicare
                  ,Net
                  ,Comment
                  ,BasicValue
                  ,PRRCode
                  ,OptionACode
                  ,OptionBCode
                  ,OptionCCode
               FROM
                  ' + @ServerName + '.' + @DBName + '.dbo.tblGrossToNet a
               WHERE
                  CaseId = ' + @sFromCaseId

            --IF @bDebug = 1
            --   PRINT @sSQL

            INSERT INTO tblGrossToNet
            (
                CaseId
               ,RunType
               ,PayLine
               ,EffectiveDate
               ,Age
               ,CSRSCola
               ,CSRSRate
               ,CSRSEarnedRate
               ,FERSCola
               ,FERSRate
               ,FERSRateNS
               ,FERSEarnedRate
               ,TotalGross
               ,TotalEarnedRate
               ,ProvRetCode
               ,HBCode
               ,HBPremium
               ,Basic
               ,PRR
               ,OptionA
               ,OptionB
               ,OptionC
               ,SSAMonthly
               ,bMedicare
               ,Net
               ,Comment
               ,BasicValue
               ,PRRCode
               ,OptionACode
               ,OptionBCode
               ,OptionCCode

            )
            EXEC(@sSQL)

            SET @sSQL = '
               SELECT DISTINCT
                  ' + @sToCaseId + '
                  ,BeginDate
                  ,EndDate
                  ,Days
                  ,Salary
                  ,Factor
                  ,PartTimeFactor

               FROM
                  ' + @ServerName + '.' + @DBName + '.dbo.tblHighSalaries a
               WHERE
                  CaseId = ' + @sFromCaseId

            --IF @bDebug = 1
            --   PRINT @sSQL

            INSERT INTO tblHighSalaries
            (
                CaseId
               ,BeginDate
               ,EndDate
               ,Days
               ,Salary
               ,Factor
               ,PartTimeFactor

            )
            EXEC(@sSQL)

            SET @sSQL = '
               SELECT DISTINCT
                   ' + @sToCaseId + '
                  ,FirstCoveredDate
                  ,Amount
                  ,dbo.fGetCodeId(b.Abbrev, ''Post56ServiceTypes'')
                  ,ServiceBeginDate
                  ,ServiceEndDate
                  ,LastYearOfInterest
                  ,FutureInterestRate
                  ,DeductionCommencementDate
                  ,DeductionAmount
                  ,dbo.fGetCodeId(c.Abbrev, ''PayrollDeductionTypes'')
               FROM
                  ' + @ServerName + '.' + @DBName + '.dbo.tblPost56Military a
                     LEFT JOIN ' + @ServerName + '.' + @DBName + '.dbo.rtblCode b ON a.ServiceTypeId = b.CodeId
                     LEFT JOIN ' + @ServerName + '.' + @DBName + '.dbo.rtblCode c ON a.DeductionTypeId = c.CodeId
               WHERE
                  CaseId = ' + @sFromCaseId

            --IF @bDebug = 1
            --   PRINT @sSQL

            INSERT INTO tblPost56Military
            (
                CaseId
               ,FirstCoveredDate
               ,Amount
               ,ServiceTypeId
               ,ServiceBeginDate
               ,ServiceEndDate
               ,LastYearOfInterest
               ,FutureInterestRate
               ,DeductionCommencementDate
               ,DeductionAmount
               ,DeductionTypeId

            )
            EXEC(@sSQL)

            SET @sSQL = '
               SELECT DISTINCT
                   ' + @sToCaseId + '
                  ,RunType
                  ,CaseType
                  ,FromDate
                  ,ToDate
                  ,RetirementSystem
                  ,FTService
                  ,Multiplier
                  ,FTHours
                  ,TourA1
                  ,TourB1
                  ,TourHours
                  ,Hours
                  ,CreditableHours
               FROM
                  ' + @ServerName + '.' + @DBName + '.dbo.tblPTCData a
               WHERE
                  CaseId = ' + @sFromCaseId
                  
            --IF @bDebug = 1
            --   PRINT @sSQL

            INSERT INTO tblPTCData
            (
                CaseId
               ,RunType
               ,CaseType
               ,FromDate
               ,ToDate
               ,RetirementSystem
               ,FTService
               ,Multiplier
               ,FTHours
               ,TourA1
               ,TourB1
               ,TourHours
               ,Hours
               ,CreditableHours

            )
            EXEC(@sSQL)

            SET @sSQL = '
               SELECT DISTINCT
                   ' + @sToCaseId + '
                  ,AnnuityStartDate
                  ,AnnuityStartDateMF
                  ,FinalSalary
                  ,OverpaymentReason
                  ,CalculatedSCD
                  ,BEDB_PaymentOption
                  ,BEDB_LumpSumAmount
                  ,BEDB_LumpSumAmountDepPaid
                  ,BEDB_DepositType
                  ,InitialRate
                  ,DateofCalculation
                  ,bNotEligible
                  ,bNotEligibleDep
                  ,BEDB_DepositElection
                  ,Post82StartDate
                  ,Post82EndDate
                  ,Pre89StartDate
                  ,Pre89EndDate
                  ,Pre90StartDate
                  ,Pre90EndDate
                  ,FlippedRedepositStartDate
                  ,FlippedRedepositEndDate
                  ,bUnPaidMilitary
                  ,CSRSUSLService
                  ,CSRSMilService
                  ,FERSMilService
                  ,ASSystem_BeginDate
                  ,FERSUSLService
                  ,FERSUSLHours
                  ,CSRSUSLHours
                  ,FERSEligibleUSLHours
                  ,CSRSEligibleUSLHours
                  ,IRS_PVF
               FROM
                  ' + @ServerName + '.' + @DBName + '.dbo.tblResults a
               WHERE
                  CaseId = ' + @sFromCaseId

            --IF @bDebug = 1
            --   PRINT @sSQL

            INSERT INTO tblResults
            (
                CaseId
               ,AnnuityStartDate
               ,AnnuityStartDateMF
               ,FinalSalary
               ,OverpaymentReason
               ,CalculatedSCD
               ,BEDB_PaymentOption
               ,BEDB_LumpSumAmount
               ,BEDB_LumpSumAmountDepPaid
               ,BEDB_DepositType
               ,InitialRate
               ,DateofCalculation
               ,bNotEligible
               ,bNotEligibleDep
               ,BEDB_DepositElection
               ,Post82StartDate
               ,Post82EndDate
               ,Pre89StartDate
               ,Pre89EndDate
               ,Pre90StartDate
               ,Pre90EndDate
               ,FlippedRedepositStartDate
               ,FlippedRedepositEndDate
               ,bUnPaidMilitary
               ,CSRSUSLService
               ,CSRSMilService
               ,FERSMilService
               ,ASSystem_BeginDate
               ,FERSUSLService
               ,FERSUSLHours
               ,CSRSUSLHours
               ,FERSEligibleUSLHours
               ,CSRSEligibleUSLHours
               ,IRS_PVF

            )
            EXEC(@sSQL)

            SET @sSQL = '
               SELECT DISTINCT
                   ' + @sToCaseId + '
                  ,RunType
                  ,Method
                  ,AverageSalary
                  ,AnnualBenefit
                  ,CSRSMonthly
                  ,FERSMonthly
                  ,SurvivorRate
                  ,Pre82Deposit
                  ,Post82Deposit
                  ,Post82DepositInterest
                  ,FERSDeposit
                  ,FERSDepositInterest
                  ,Pre90Redeposit
                  ,Pre90RedepositInterest
                  ,Post90RedepositInterest
                  ,Age62Rate
                  ,CSRSProration
                  ,FERSProration
                  ,bTriggered
                  ,CSRSEarnedRate
                  ,FERSEarnedRate
                  ,MFEarnedRate
                  ,totalserviceold
                  ,UnreducedEarnedRate
                  ,bVoluntaryOverride
                  ,AgeReduction
                  ,SurvivorReduction
                  ,TotalCSRSService
                  ,TotalFERSService
                  ,CSRSService
                  ,FERSService
                  ,Age62Service
                  ,LawCSRSService
                  ,LawFERSService
                  ,bASEligible
                  ,ProvRetCode
                  ,ColaSurvivorRate
                  ,ServicePurchasedCode
                  ,Pre82DepositInterest
                  ,Post90Redeposit
                  ,CalcRetirementType
                  ,FERSReDeposit
                  ,FERSReDepositInterest
                  ,TotalTitleService
                  ,TotalComputationService
                  ,CSRSSurvivorAnnualReduced
                  ,FERSSurvivorAnnualReduced
                  ,FERSOWCPEnhancement
                  ,FERSAnnual
                  ,CSRSAnnual
                  ,CombinedOWCPEnhancement
                  ,FERSAgeReduction
                  ,TotalOWCPEnhancement
                  ,OWCPFactor
               FROM
                  ' + @ServerName + '.' + @DBName + '.dbo.tblRunResults a
               WHERE
                  CaseId = ' + @sFromCaseId

            --IF @bDebug = 1
            --   PRINT @sSQL

            INSERT INTO tblRunResults
            (
                CaseId
               ,RunType
               ,Method
               ,AverageSalary
               ,AnnualBenefit
               ,CSRSMonthly
               ,FERSMonthly
               ,SurvivorRate
               ,Pre82Deposit
               ,Post82Deposit
               ,Post82DepositInterest
               ,FERSDeposit
               ,FERSDepositInterest
               ,Pre90Redeposit
               ,Pre90RedepositInterest
               ,Post90RedepositInterest
               ,Age62Rate
               ,CSRSProration
               ,FERSProration
               ,bTriggered
               ,CSRSEarnedRate
               ,FERSEarnedRate
               ,MFEarnedRate
               ,totalserviceold
               ,UnreducedEarnedRate
               ,bVoluntaryOverride
               ,AgeReduction
               ,SurvivorReduction
               ,TotalCSRSService
               ,TotalFERSService
               ,CSRSService
               ,FERSService
               ,Age62Service
               ,LawCSRSService
               ,LawFERSService
               ,bASEligible
               ,ProvRetCode
               ,ColaSurvivorRate
               ,ServicePurchasedCode
               ,Pre82DepositInterest
               ,Post90Redeposit
               ,CalcRetirementType
               ,FERSReDeposit
               ,FERSReDepositInterest
               ,TotalTitleService
               ,TotalComputationService
               ,CSRSSurvivorAnnualReduced
               ,FERSSurvivorAnnualReduced
               ,FERSOWCPEnhancement
               ,FERSAnnual
               ,CSRSAnnual
               ,CombinedOWCPEnhancement
               ,FERSAgeReduction
               ,TotalOWCPEnhancement
               ,OWCPFactor

            )
            EXEC(@sSQL)

            SET @sSQL = '
               SELECT DISTINCT
                   ' + @sToCaseId + '
                  ,bBothDepRedep
                  ,bCSRSDeposit
                  ,bEitherDep
                  ,bEitherRed
                  ,bFERSDeposit
                  ,bFlippedRedeposits
                  ,bPost90Dates
                  ,bPost90Redep
                  ,bPre89Lines
                  ,bPre90Lines
                  ,bPre90Redep
                  ,cCSRSRedAge
                  ,cCSRSRedDep
                  ,cCSRSUnreduced
                  ,cFERSRedAge
                  ,cFERSUnreduced
                  ,cRedepAmountDue
                  ,objRngBox1
                  ,objRngBox2
                  ,objRngBox3
                  ,objRngBox4
                  ,objRngbox5
                  ,objRngbox6
                  ,cCostOfSurvivorAnnuity
                  ,cSurvivorBase
                  ,tAgeYears
                  ,tAgeMonths
                  ,sAgeReductionType
                  ,cActuarialReduction
                  ,bFERSRedeposit
                  ,objRngbox7

               FROM
                  ' + @ServerName + '.' + @DBName + '.dbo.tblXLReportData a
               WHERE
                  CaseId = ' + @sFromCaseId

            --IF @bDebug = 1
            --   PRINT @sSQL

            INSERT INTO tblXLReportData
            (
                CaseId
               ,bBothDepRedep
               ,bCSRSDeposit
               ,bEitherDep
               ,bEitherRed
               ,bFERSDeposit
               ,bFlippedRedeposits
               ,bPost90Dates
               ,bPost90Redep
               ,bPre89Lines
               ,bPre90Lines
               ,bPre90Redep
               ,cCSRSRedAge
               ,cCSRSRedDep
               ,cCSRSUnreduced
               ,cFERSRedAge
               ,cFERSUnreduced
               ,cRedepAmountDue
               ,objRngBox1
               ,objRngBox2
               ,objRngBox3
               ,objRngBox4
               ,objRngbox5
               ,objRngbox6
               ,cCostOfSurvivorAnnuity
               ,cSurvivorBase
               ,tAgeYears
               ,tAgeMonths
               ,sAgeReductionType
               ,cActuarialReduction
               ,bFERSRedeposit
               ,objRngbox7

            )
            EXEC(@sSQL)

            FETCH NEXT FROM @csCaseRecords INTO @sFromCaseId, @sToCaseId, @sToClaimId
         END
         CLOSE @csCaseRecords
         DEALLOCATE @csCaseRecords

      END

      BEGIN -- Begin copying lumpsum information.
         DECLARE @csLSRecords CURSOR
         DECLARE @PaymentId INT
         DECLARE @PreviousPaymentId INT     = -1

         DECLARE @PayeeId INT

         DECLARE @sToPaymentId VARCHAR(20)
         DECLARE @sToPayeeId VARCHAR(20)

         DECLARE @sPayeeSSNScramble VARCHAR(9)

         --IF @bDebug = 1
         --   SELECT * FROM #tmp_LSRecords

         SET @csLSRecords = CURSOR SCROLL KEYSET FOR SELECT DISTINCT PaymentId, PayeeId, ToClaimId FROM #tmp_LSRecords order by PaymentId

         OPEN @csLSRecords

         FETCH FIRST FROM @csLSRecords INTO @PaymentId, @PayeeId, @sToClaimId
         WHILE @@FETCH_STATUS = 0
         BEGIN

            SET @sToPayeeId = ''
            SET @sPayeeSSNScramble = ''

            --select @PreviousPaymentId, @PaymentId
            IF @PreviousPaymentId <> @PaymentId
            BEGIN

               SET @sToPaymentId = ''

               SET @sSQL = '
               SELECT DISTINCT
                   ' + @sToClaimId + '
                  ,dbo.fGetCodeId(b.Abbrev, ''PaymentType'')
                  ,DateAdded
                  ,GrossAmount
                  ,AmountInterest
                  ,bEqualShares
                  ,HBAdj
                  ,HBGovShareAdj
                  ,RHBPrivateAdj
                  ,MedicareAdj
                  ,LIAdj
                  ,HBCode
                  ,LICode
                  ,bSurvivorPayable
                  ,LastDayOfInterest
                  ,bHBTerm
               FROM
                  ' + @ServerName + '.' + @DBName + '.dbo.tblLumpsumPayment a
                     LEFT JOIN ' + @ServerName + '.' + @DBName + '.dbo.rtblCode b ON a.PaymentTypeId = b.CodeId
               WHERE
                  LumpsumPaymentId = ' + CAST(@PaymentId AS VARCHAR(20))

               --IF @bDebug = 1
               --   PRINT @sSQL

               INSERT INTO tblLumpsumPayment
               (
                   ClaimId
                  ,PaymentTypeId
                  ,DateAdded
                  ,GrossAmount
                  ,AmountInterest
                  ,bEqualShares
                  ,HBAdj
                  ,HBGovShareAdj
                  ,RHBPrivateAdj
                  ,MedicareAdj
                  ,LIAdj
                  ,HBCode
                  ,LICode
                  ,bSurvivorPayable
                  ,LastDayOfInterest
                  ,bHBTerm)
               EXEC(@sSQL)

               SELECT @nId = SCOPE_IDENTITY()
               SELECT @sToPaymentId = CAST(@nId AS VARCHAR(20))
               SET @nId = NULL

               SET @PreviousPaymentId = @PaymentId
            END

            IF @PayeeId IS NOT NULL -- This is to exlude any payments without payee condition.
            BEGIN

               SET @sSQL = '
                  SELECT DISTINCT
                        ' + @sToPaymentId + '
                     ,''000000000''
                     ,Suffix
                     ,bForeignAddress
                     ,bUSCitizen
                     ,bPaidToIRA
                     ,dbo.fGetCodeId(b.Abbrev, ''BeneficiaryType'')
                     ,Share
                     ,bPercent
                     ,AmountTotal
                     ,AmountInterest
                     ,AmountFIT
                     ,CASE WHEN AddressLine1 IS NOT NULL THEN Left(AddressLine1, 1) + ''XXXXX'' ELSE NULL END
                     ,CASE WHEN AddressLine2 IS NOT NULL THEN ''0 No Street'' ELSE NULL END
                     ,CASE WHEN AddressLine3 IS NOT NULL THEN ''APT'' ELSE NULL END
                     ,CASE WHEN AddressLine4 IS NOT NULL THEN '''' ELSE NULL END
                     ,CASE WHEN AddressLine5 IS NOT NULL THEN '''' ELSE NULL END
                     ,''No City''
                     ,''DC''
                     ,''20415''
                     ,CASE WHEN dbo.fIsBlank(VoucherNumber) = 0 THEN ''000000000'' ELSE NULL END
                     ,MFPassDate
                     ,MFVoucherDate
                     ,DateAdded
                     ,dbo.fGetCodeId(d.Abbrev, ''StatusCodes'')
                     ,dbo.fGetCodeId(c.Abbrev, ''WaiverType'')
                     ,Specialist
                     ,Reviewer
                     ,''C''
                     ,''000000000''
                     ,''000000000''
                     ,''0 No Street||||No City|DC|20415|''
                     ,WithHoldingTaxRate
                  FROM
                     ' + @ServerName + '.' + @DBName + '.dbo.tblLumpsumPayee a
                        LEFT JOIN ' + @ServerName + '.' + @DBName + '.dbo.rtblCode b ON a.BeneficiaryTypeID = b.CodeId
                        LEFT JOIN ' + @ServerName + '.' + @DBName + '.dbo.rtblCode c ON a.WaiverIndicatorCodeId = c.CodeId
                        LEFT JOIN ' + @ServerName + '.' + @DBName + '.dbo.rtblCode d ON a.StatusCodeId = d.CodeId
                  WHERE
                     LumpsumPayeeId = ' + CAST(@PayeeId AS VARCHAR(20))

               --IF @bDebug = 1
               --   PRINT @sSQL
         
               INSERT INTO tblLumpsumPayee
               (
                  LumpsumPaymentId
                 ,PayeeSSN
                 ,Suffix
                 ,bForeignAddress
                 ,bUSCitizen
                 ,bPaidToIRA
                 ,BeneficiaryTypeID
                 ,Share
                 ,bPercent
                 ,AmountTotal
                 ,AmountInterest
                 ,AmountFIT
                 ,AddressLine1
                 ,AddressLine2
                 ,AddressLine3
                 ,AddressLine4
                 ,AddressLine5
                 ,AddressCity
                 ,AddressState
                 ,AddressZIP
                 ,VoucherNumber
                 ,MFPassDate
                 ,MFVoucherDate
                 ,DateAdded
                 ,StatusCodeId
                 ,WaiverIndicatorCodeId
                 ,Specialist
                 ,Reviewer
                 ,AccountType
                 ,BankAccountNumber
                 ,EFTRoutingNumber
                 ,BankAddress
                 ,WithHoldingTaxRate)
               EXEC(@sSQL)


               SELECT @nId = SCOPE_IDENTITY()
               SELECT @sToPayeeId = CAST(@nId AS VARCHAR(20))

               SET @sPayeeSSNScramble = REPLICATE('0', 9 - LEN(CAST(@sToPayeeId AS VARCHAR(8)))) + CAST(@sToPayeeId AS VARCHAR(8))
               UPDATE tblLumpSumPayee
               SET PayeeSSN = @sPayeeSSNScramble,
                     VoucherNumber = CASE WHEN VoucherNumber IS NOT NULL THEN @sPayeeSSNScramble ELSE NULL END
               WHERE LumpsumPayeeId = @sToPayeeId

               SET @nId = NULL


               BEGIN -- Begin setting specialist information if required.
                  IF dbo.fIsBlank(@ToSpecialist) <> 1 AND
                     EXISTS(SELECT 1 FROM rvwUserList where Login = @ToSpecialist)
                  BEGIN
                     UPDATE tblLumpsumPayee set Specialist = @ToSpecialist WHERE LumpsumPayeeId = @sToPayeeId
                  END
               END

               SET @sSQL = '
                  SELECT DISTINCT
                      ' + @sToPayeeId + '
                    ,DateAdded
                    ,UserId
                    ,Action
                    ,dbo.fGetCodeId(b.Abbrev, ''StatusCodes'')
                  FROM
                     ' + @ServerName + '.' + @DBName + '.dbo.tblLumpsumPayeeHistory a
                        LEFT JOIN ' + @ServerName + '.' + @DBName + '.dbo.rtblCode b ON a.StatusCodeId = b.CodeId
                  WHERE
                     LumpsumPayeeId = ' + CAST(@PayeeId AS VARCHAR(20))

               INSERT INTO tblLumpsumPayeeHistory
               (
                     LumpSumPayeeId
                    ,DateAdded
                    ,UserId
                    ,Action
                    ,StatusCodeId
               )
               EXEC(@sSQL)

            END

            SET @sSQL = ''

            FETCH NEXT FROM @csLSRecords INTO @PaymentId, @PayeeId, @sToClaimId
         END

         CLOSE @csLSRecords
         DEALLOCATE @csLSRecords

      END
      --declare @ii int = 1/0

      COMMIT TRAN

      SET @rc = 0

   END TRY

   BEGIN CATCH

      IF CURSOR_STATUS('variable','@cs') = 1
      BEGIN
         CLOSE @cs
         DEALLOCATE @cs
      END

      IF CURSOR_STATUS('variable','@csCaseRecords') = 1
      BEGIN
         CLOSE @csCaseRecords
         DEALLOCATE @csCaseRecords
      END

      IF CURSOR_STATUS('variable','@@csCustomerRecords') = 1
      BEGIN
         CLOSE @csCustomerRecords
         DEALLOCATE @csCustomerRecords
      END

      IF CURSOR_STATUS('variable','@csLSRecords') = 1
      BEGIN
         CLOSE @csLSRecords
         DEALLOCATE @csLSRecords
      END


      SET @Msg = 'Copy Claim Failed (' + ERROR_MESSAGE() + ').'
      SET @rc = -1615

      ROLLBACK TRAN

   END CATCH

   RETURN @rc

END

GO

IF object_id(N'dbo.apCopyClaimOldNew') > 0
BEGIN
   PRINT '   ... Created'
END
GO

GRANT EXECUTE ON dbo.apCopyClaimOldNew TO APP_RBC
GO

/*
DECLARE @rc int
DECLARE @Msg varchar(2000)
EXEC @rc = apCopyClaimOldNew @ClaimNumber = 'A89880230', @DBName = 'RETIRE_REISSUE', @Msg = @Msg OUTPUT
SELECT @rc, @Msg
*/
