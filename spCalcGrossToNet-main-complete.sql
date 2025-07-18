USE [RETIRE]
GO

/****** Object:  StoredProcedure [dbo].[spCalcGrossToNet_main]    Script Date: 6/28/2025 7:38:46 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


ALTER PROCEDURE [dbo].[spCalcGrossToNet_main]
    @CaseId                        INT
   ,@CSRSRate                      INT
   ,@CSRSTime                      DECIMAL(5,3)
   ,@FERSRate                      INT
   ,@FERSTime                      DECIMAL(5,3)
   ,@AvgSalPT                      DECIMAL(12,2)
   ,@G2NCaseType                   TINYINT
   ,@SurvivorCode                  TINYINT
   ,@bVoluntaryOverride            BIT = 0
   ,@bDebug                        TINYINT = 0
   ,@Login                         VARCHAR(20)
as


   /****************************************************************************

   PURPOSE: 
      Creates PROCEDURE spCalcGrossToNet_main, which is called by
      spCalcGrossToNet, spCalcGrossToNetDs, AND xpSetGrossToNet.

     spCalcGrossToNet_main
       Parameter           Non-disabiliby      FERS Disability       Death                 CSRS Disability
       -----------------   -----------------   -------------------   -------------------   -------------------
       @CaseId             @CaseId             @CaseId               @CaseId               @CaseId
       @CSRSRate           @CSRSRate           @CSRSEarned           @CSRSEarned           @CSRSRate
       @CSRSTime           0                   @CSRSTime             0                     @CSRSTime
       @FERSRate           @FERSRate           @FERSEarned           @FERSEarned           @FERSEarned
       @FERSTime           0                   @FERSTime             0                     @FERSTime
       @AvgSalPT           0                   @AvgSalPT             0                     @AvgSalPT
       @G2NCaseType        0                   1                     2                     3        
       @SurvivorCode       0                   @SurvivorCode         0                     @SurvivorCode
       @bVoluntaryOverride 0                   @bVoluntaryOverride   0                     @bVoluntaryOverride
       @bDebug             @bDebug             @bDebug               @bDebug               @bDebug     
   
     For the bDebug parameter, use the following --
                  0 - no debug
                  1 - display debug help
                  2 - debug spCalcGrossToNet_main
                  4 - debug HB
                  8 - debug LI
                 16 - debug CSRS COLA
                 32 - debug FERS COLA
                255 - debug all

   RETURN VALUES: 

   AUTHOR: 
      Satish Bollempalli (Orginal PROCEDURE FROM Keith Yager)

   ----------------------------------------------------------------------------
   HISTORY:  $Log: /FACES30/DB/RetireDB/GrossToNet/spCalcGrossToNet_main.sql $
   
   36    7/17/25 Enhanced error logging with CaseId tracking
   
   35    9/10/21 8:47 Dctcrctimt
   The effective date is 10/01/2021 for LIChanges Year-end 210381
   
   34    9/10/21 8:00 Dctcrctimt
   Year End -- Added LI changes for 2022
   
   33    7/16/19 2:12p Dctcrctimt
   Prod copy
   
   24   01/09/2018 2:09p dctcrctimt
   User Story 1156:  Generate Correct OWCP Enhancement PRC (961/962) When Disability PRC is 261/262
   Disability PRC is 261/262 and There is OWCP  
   Added this logic to handle new OWCP DISABILTY ProvCode 
   
   1     6/10/16 10:29a Dctcrjc
   
   23    6/10/16 10:27a Dctcrjc
   Add 1/1/2016 LI
   
   22    8/21/13 11:16a Dctcrsbol
   Changed to DATE fields/variables.
   
   21    6/28/12 2:53p Dctcrsbol
   
   20    4/19/12 4:51p Ctcrsbol
   
   19    1/10/12 3:36p Ctcrsbol
   Fixed the bug added while fixing PR-Tracker 780.
   
   18    11/30/11 5:36p Ctcrsbol
   Added 1/1/2005 and 1/1/2012 hard coded LI lines. This needs to be
   improved (table driven) in the next release.
   
   17    11/22/11 4:14p Ctcrsbol
   Increased login to 20 characters long.
   
   16    8/26/11 11:53a Ctcrsbol
   Added Changes for 780.
   
   15    11/13/09 4:00p Ctcrsbol
   Added 0% cola changes.
   
   14    10/02/08 9:52a Ctcrsbol
   Added 284 and 285 PRC changes.
   
   13    5/31/06 1:26p Ctcrsbol
   Made changes related to Saving the LI codes Information.
   
   12    5/16/06 3:24p Ctcrsbol
   Added 9 digit Claim Changes.
   
   11    3/28/06 3:51p Ctcrsbol
   Fixed the 011 HB Code issue.
   
   10    12/21/05 2:14p Ctcrsbol
   Added Reissue Changes.
   
   9     10/28/04 10:24a Ctcrsbol
   Fixed "FERS Cola issue on 12/1 & 40% rate"
   
   8     9/21/04 2:55p Ctcrsbol
   Maded changes for PR tracker 64.
   
   7     3/09/04 11:07a Ctcrsbol
   Added two more validations.
   
   6     1/08/04 10:11a Ctcrsbol
   Fixed the Primary Survivor logic and Set FERS Disability amount to 0 if
   it is negative.
   
   5     10/29/03 11:15a Ctcrsbol
   Changed ProvRetCode return value for all cases.
   
   4     7/18/03 2:38p Ctcrsbol
   
   3     5/01/03 1:20p Ctcrsbol
   
   2     5/01/03 11:19a Ctcrsbol
   Per Keith, Changed the AnnuityStartDate for Death Cases taken from
   DateOfDeath + 1.
   
   1     4/25/03 9:38a Ctcrsbol
   RBE 1.0 Version.


   ****************************************************************************/

BEGIN

   DECLARE @age                     TINYINT
   DECLARE @Age62Date               DATE
   DECLARE @AvgSalPT62              DECIMAL(12,2)
   DECLARE @bDebug_local            BIT
   DECLARE @cola                    DECIMAL(3,3)
   DECLARE @cs                      CURSOR
   DECLARE @CSRSEarnedRate          INT
   DECLARE @CSRSRemainder           DECIMAL(3,2)
   DECLARE @dt                      DATE
   DECLARE @d1                      DECIMAL(12,4)
   DECLARE @d2                      DECIMAL(12,4)
   DECLARE @FERSEarnedRate          INT
   DECLARE @FERSRemainder           DECIMAL(3,2)
   DECLARE @FERSRateNS              DECIMAL(12,2) -- w/o survivor ded. (used in FERS data file)
   DECLARE @MaxAge                  TINYINT
   DECLARE @n                       TINYINT
   DECLARE @rc                      INT   
   DECLARE @SurvivorRate            DECIMAL(3,2)
   DECLARE @val                     DECIMAL(14,5)
   DECLARE @str                     VARCHAR(1000)  -- INCREASED FROM 250


   DECLARE @LIBase                  SMALLINT
   DECLARE @OptionA                 TINYINT
   DECLARE @OptionB                 TINYINT
   DECLARE @bOptionB_Reduced        BIT
   DECLARE @OptionC                 TINYINT
   DECLARE @bOptionC_Reduced        BIT
   DECLARE @DateOfBirth             DATE
   DECLARE @HBCode                  VARCHAR(3)
   DECLARE @SSADate                 DATE
   DECLARE @SSAAmount               DECIMAL(12,2)
   DECLARE @AnnuityStart            DATE

   DECLARE @PRRCode                 VARCHAR(1)
   DECLARE @OptionBCode             VARCHAR(1)
   DECLARE @OptionCCode             VARCHAR(1)

   SET NOCOUNT ON

   IF @bDebug = 1
   BEGIN
      PRINT 'Debug usage:'
      PRINT '     0 - no debug'
      PRINT '     1 - display debug help'
      PRINT '     2 - debug spCalcGrossToNet_main'
      PRINT '     4 - debug HB'
      PRINT '     8 - debug LI'
      PRINT '    16 - debug CSRS COLA'
      PRINT '    32 - debug FERS COLA'
      PRINT '   255 - debug all'

      RETURN -1
   END

   SET @bDebug_local = CASE WHEN @bDebug & 2 = 2 THEN 1 ELSE 0 END

   IF @bDebug_local=1
   BEGIN                     
      PRINT 'spCalcGrossToNet_main:'
      PRINT '  @CaseId        - ' + LTRIM(STR(@CaseId))
      PRINT '  @CSRSRate      - ' + LTRIM(STR(@CSRSRate))
      PRINT '  @CSRSTime      - ' + LTRIM(STR(@CSRSTime)) 
      PRINT '  @FERSRate      - ' + LTRIM(STR(@FERSRate)) 
      PRINT '  @FERSTime      - ' + LTRIM(STR(@FERSTime)) 
      PRINT '  @AvgSalPT      - ' + LTRIM(STR(@AvgSalPT))
      PRINT '  @G2NCaseType   - ' + LTRIM(STR(@G2NCaseType)) 
      PRINT '  @SurvivorCode  - ' + LTRIM(STR(@SurvivorCode))
      PRINT '  @bDebug        - ' + LTRIM(STR(@bDebug))                                                    
      PRINT ''
   END

   -- Initialize variables

   IF @G2NCaseType <> 2 
   BEGIN

      SELECT
          @DateOfBirth = a.DateOfBirth
         ,@HBCode = PlanCode                     
         ,@LIBase = ISNULL(b.Basic, 0)
         ,@OptionA = ISNULL(b.Standard, 0)
         ,@OptionB = CASE 
                        WHEN b.Additional BETWEEN 'A' AND 'E' THEN 1 + ASCII(b.Additional) - ASCII('A')
                        WHEN b.Additional BETWEEN 'F' AND 'J' THEN 1 + ASCII(b.Additional) - ASCII('F')
                        ELSE 0
                     END
         ,@OptionC = CASE
                        WHEN b.Family IS NULL THEN 0 
                        WHEN b.Family BETWEEN 'F' AND 'J' THEN 1 + ASCII(b.Family) - ASCII('F')                                           
                        ELSE b.Family
                     END                            
         ,@SSADate = StartDate
         ,@SSAAmount = ISNULL(DisabilityRate, 0)
      FROM
         tblCases a   
            LEFT JOIN vwCaseHBChanges d ON a.CaseId = d.CaseId AND d.EffectiveDate IS NULL
            LEFT JOIN vwCaseLifeInsurance b ON a.CaseId = b.CaseId AND a.DateOfBirth = b.EffectiveDate
            LEFT JOIN vwCaseDisability c ON a.CaseId = c.CaseId
      WHERE 
          a.CaseId = @CaseId


      -- Get Annuity start date.
      SELECT 
         @AnnuityStart = AnnuityStartDate
      FROM
         tblResults
      WHERE 
         CaseId = @CaseId

   END
   ELSE
   BEGIN
      -- only diff between above SQL and the following SQL is 
      -- DateOfBirth comes from the Primary Survivor not from the annuitant.

      SELECT
          @DateOfBirth = d.DateOfBirth
         ,@HBCode      = PlanCode                     
         ,@LIBase      = ISNULL(b.Basic, 0)
         ,@OptionA     = ISNULL(b.Standard, 0)
         ,@OptionB = CASE 
                        WHEN b.Additional BETWEEN 'A' AND 'E' THEN 1 + ASCII(b.Additional) - ASCII('A')
                        WHEN b.Additional BETWEEN 'F' AND 'J' THEN 1 + ASCII(b.Additional) - ASCII('F')
                        ELSE 0
                     END
         ,@OptionC = CASE
                        WHEN b.Family IS NULL THEN 0 
                        WHEN b.Family BETWEEN 'F' AND 'J' THEN 1 + ASCII(b.Family) - ASCII('F')                                           
                        ELSE b.Family
                     END              
         ,@SSADate     = StartDate
         ,@SSAAmount   = ISNULL(DisabilityRate, 0)
      FROM
         tblCases a
            LEFT JOIN vwCaseHBChanges g ON a.CaseId = g.CaseId AND g.EffectiveDate IS NULL         
            LEFT JOIN vwCaseLifeInsurance b ON a.CaseId = b.CaseId AND a.DateOfBirth = b.EffectiveDate
            LEFT JOIN vwCaseDisability c ON a.CaseId = c.CaseId
            JOIN vwCaseSurvivors d ON a.CaseId = d.CaseId 
               JOIN rtblCode e ON d.SurvivorTypeId = e.CodeId
      WHERE 
          a.CaseId = @CaseId AND
          e.Abbrev = '0'
      ORDER BY
         d.DateOfBirth


      -- Get Annuity start date.
      SELECT 
         @AnnuityStart = DateAdd(dd, 1, DateOfDeath)
      FROM
         tblCases
      WHERE 
         CaseId = @CaseId
   END

      
   DELETE FROM GrossToNet WHERE UserId = @Login AND CaseId = @CaseId
   DELETE FROM LIChanges WHERE UserId = @Login AND CaseId = @CaseId

   INSERT INTO GrossToNet(CaseId, Age, EffectiveDate, Comment, UserId)
   VALUES (@CaseId, 0, @DateOfBirth, 'Birth Date', @Login)

   SET @Age62Date = DATEADD(yy, 62, @DateOfBirth )


   IF @G2NCaseType IN (0, 3) -- Regular & CSRS Disability cases
   BEGIN
      SET @CSRSEarnedRate = 0
      SET @CSRSRemainder  = 0
      SET @FERSEarnedRate = 0
      SET @FERSRemainder  = 0
      SET @FERSRateNS     = 0.0

      SET @CSRSTime = 0
      SET @FERSTime = 0
      SET @AvgSalPT = 0
      SET @SSADate = NULL
      SET @SSAAmount = 0
      SET @SurvivorCode = 0
      SET @bVoluntaryOverride = 0
   END
   ELSE
   IF @G2NCaseType = 1
   BEGIN
      Set @SurvivorRate = CASE @SurvivorCode WHEN 1 THEN 0.9 WHEN 2 THEN 0.95 ELSE 1.0 END
      SET @AvgSalPT62 = @AvgSalPT

      SET @val = @FERSRate / 100.0
      SET @FERSEarnedRate = @val
      SET @FERSRemainder = @val - @FERSEarnedRate

      SET @val = @CSRSRate / 100.0
      SET @CSRSEarnedRate = @val
      SET @CSRSRemainder = @val - @CSRSEarnedRate

      SET @CSRSRate   = 0
      SET @FERSRateNS = @AvgSalPT * 0.6 
      SET @FERSRate   = @AvgSalPT * 0.6 * @SurvivorRate / 12
   END
   ELSE
   IF @G2NCaseType = 2
   BEGIN
      SET @CSRSEarnedRate = 0
      SET @CSRSRemainder  = 0
      SET @FERSEarnedRate = 0
      SET @FERSRemainder  = 0
      SET @FERSRateNS     = 0.0

      SET @LIBase         = 0
      SET @OptionA        = 0
      SET @OptionB        = 0
      SET @OptionC        = 0

      SET @CSRSTime = 0
      SET @FERSTime = 0
      SET @AvgSalPT = 0
      SET @SSADate = NULL
      SET @SSAAmount = 0
      SET @SurvivorCode = 0
      SET @bVoluntaryOverride = 0
   END


   IF @FERSRemainder + @CSRSRemainder >= 1 
      SET @FERSEarnedRate = @FERSEarnedRate + 1

   IF @bDebug_local = 1
      PRINT ISNULL(CONVERT(VARCHAR(20), @FERSEarnedRate), '') +  ' @FERSEarnedRate, ' +  ISNULL(CONVERT(VARCHAR(20), @CSRSEarnedRate), '') + ' @CSRSEarnedRate'

   /******************************************************************
     Build AND initialize temporary tables.

     We'll start by adding entries FOR each life insurance change
     (FROM ages 0 to the maximum we have premiums FOR (currently 70).
   ******************************************************************/

   SELECT 
      @MaxAge = MAX(AgeGroup) 
   FROM 
      rtblLIPremiums

   IF @bDebug_local = 1
      PRINT 'Adding Life Insurance data:'


   -- Create another temporary table with an identical structure.
   SELECT * INTO #t2 FROM GrossToNet WHERE 1 = 2

   SET @n = 0
   WHILE @n <= @MaxAge
   BEGIN

      SET @dt = DATEADD(yy, @n, @DateOfBirth ) 

      /************************************************************************
         Effective April 24, 1999, WHEN an annuitant GOes FROM one age group
         to the next, his premiums will increase at the BEGINning of the month
         after his birthday.  But IF his birthday causes age group changes
         between January 1 AND April 30, 1999, the higher premiums BEGIN with
         the June 1, 1999, payment.

         Previously, the higher premiums began with the BEGINning of the next
         year.  At 65, they began with the BEGINning of the month following 
         his birthday.
      ************************************************************************/

      SET @dt = CASE 
                  WHEN @n < 65 AND @dt < '1/1/1999' THEN dbo.fSetDate(@dt, 12, 1)
                  WHEN @n < 65 AND @dt < '5/1/1999' THEN '5/1/1999'
                  ELSE dbo.fSetDate(@dt, 10, 1)
                END


      SET @age = dbo.fGetAge(@DateOfBirth, @dt)

      IF @bDebug_local = 1
         PRINT '  ' + ISNULL(LTRIM(STR(@age)), '') + '  ' + ISNULL(CONVERT(VARCHAR(11), @dt,101), '')

      INSERT INTO GrossToNet 
      (
          CaseId
         ,Age                                
         ,EffectiveDate                      
         ,CSRSRate                           
         ,CSRSEarnedRate                           
         ,FERSRate                           
         ,FERSRateNS
         ,FERSEarnedRate                           
         ,HBCode
         ,UserId
         ,Comment
      )
      VALUES 
      (
          @CaseId
         ,@age
         ,@dt
         ,@CSRSRate
         ,@CSRSEarnedRate
         ,@FERSRate
         ,@FERSRateNS
         ,@FERSEarnedRate
         ,@HBCode
         ,@Login
         ,CASE WHEN @age = 0 THEN '' ELSE 'LI change' END
      )



      INSERT INTO LIChanges VALUES (@Login, @n, @dt, @CaseId)

      SELECT @n = CASE @n WHEN 0 THEN 35 ELSE @n + 5 END
   END -- while


   -- Add an entry FOR Jan 1, 1993
   IF @OptionA + @OptionB + @OptionC > 0 AND
      NOT EXISTS (SELECT * FROM GrossToNet WHERE EffectiveDate = '1/1/1993' AND UserId = @Login AND CaseId = @CaseId)
   BEGIN
      IF @bDebug_local = 1
         PRINT 'Adding entry FOR 1/1/1993.'

      SET @dt = '1/1/1993'
      SET @age = dbo.fGetAge(@DateOfBirth, @dt)

      INSERT INTO GrossToNet 
      (
          CaseId
         ,Age                                
         ,EffectiveDate                      
         ,CSRSRate                           
         ,CSRSEarnedRate                           
         ,FERSRate                           
         ,FERSRateNS
         ,FERSEarnedRate                           
         ,HBCode
         ,UserId
         ,Comment
      )
      VALUES 
      (
          @CaseId
         ,@age
         ,@dt
         ,@CSRSRate
         ,@CSRSEarnedRate
         ,@FERSRate
         ,@FERSRateNS
         ,@FERSEarnedRate
         ,@HBCode
         ,@Login
         ,'1/1/1993'
      )

   END

   -- Add an entry FOR May 1, 1999

   IF @LIBase + @OptionA + @OptionB + @OptionC > 0
   BEGIN
      IF @bDebug_local = 1
         PRINT 'Adding entry FOR 5/1/1999.'

      SET @dt = '5/1/1999'
      IF EXISTS (SELECT * FROM GrossToNet WHERE EffectiveDate = @dt AND UserId = @Login AND CaseId = @CaseId)
         UPDATE GrossToNet
         SET Comment = '5/1/1999'
         WHERE EffectiveDate = @dt AND UserId = @Login AND CaseId = @CaseId
      ELSE
      BEGIN

         SET @age = dbo.fGetAge(@DateOfBirth,@dt)

         INSERT INTO GrossToNet 
         (  
             CaseId
            ,Age                                
            ,EffectiveDate                      
            ,CSRSRate                           
            ,CSRSEarnedRate                           
            ,FERSRate
            ,FERSRateNS
            ,FERSEarnedRate                           
            ,HBCode
            ,Comment
            ,UserId
         )
         VALUES 
         (
             @CaseId
            ,@age
            ,'5/1/1999'
            ,@CSRSRate
            ,@CSRSEarnedRate
            ,@FERSRate
            ,@FERSRateNS
            ,@FERSEarnedRate
            ,@HBCode
            ,'5/1/1999'
            ,@Login
         )
       END
   END

   -- Add an entry FOR May 1, 2000
   IF @OptionB + @OptionC > 0
   BEGIN
      IF @bDebug_local = 1
         PRINT 'Adding entry FOR 5/1/2000.'

      SET @dt = '5/1/2000'
      IF EXISTS(SELECT 1 FROM GrossToNet WHERE EffectiveDate = @dt AND UserId = @Login AND CaseId = @CaseId)
         UPDATE GrossToNet
         SET Comment = Comment + ', LI change'
         WHERE EffectiveDate = @dt AND UserId = @Login AND CaseId = @CaseId AND Comment NOT LIKE '%LI Change%'
      ELSE
      BEGIN
         
         SET @age = dbo.fGetAge(@DateOfBirth,@dt)

         INSERT INTO GrossToNet 
         (  
             CaseId
            ,Age                                
            ,EffectiveDate                      
            ,CSRSRate                           
            ,CSRSEarnedRate                           
            ,FERSRate
            ,FERSRateNS
            ,FERSEarnedRate                           
            ,HBCode
            ,Comment
            ,UserId
         )
         VALUES 
         (
             @CaseId
            ,@age
            ,'5/1/2000'
            ,@CSRSRate
            ,@CSRSEarnedRate
            ,@FERSRate
            ,@FERSRateNS
            ,@FERSEarnedRate
            ,@HBCode
            ,'LI change'
            ,@Login
         )
      END
   END

   -- Add an entry for January 1, 2003
   BEGIN
      IF @bDebug_local = 1
         PRINT 'Adding entry FOR 1/1/2003.'

      SET @dt = '1/1/2003'
      IF EXISTS(SELECT 1 FROM GrossToNet WHERE EffectiveDate = @dt AND UserId = @Login AND CaseId = @CaseId)
         UPDATE GrossToNet
         SET Comment = Comment + ', LI change'
         WHERE EffectiveDate = @dt AND UserId = @Login AND CaseId = @CaseId AND Comment NOT LIKE '%LI Change%'
      ELSE
      BEGIN
         
         SET @age = dbo.fGetAge(@DateOfBirth,@dt)

         INSERT INTO GrossToNet 
         (  
             CaseId
            ,Age                                
            ,EffectiveDate                      
            ,CSRSRate                           
            ,CSRSEarnedRate                           
            ,FERSRate
            ,FERSRateNS
            ,FERSEarnedRate                           
            ,HBCode
            ,Comment
            ,UserId
         )
         VALUES 
         (
             @CaseId
            ,@age
            ,'1/1/2003'
            ,@CSRSRate
            ,@CSRSEarnedRate
            ,@FERSRate
            ,@FERSRateNS
            ,@FERSEarnedRate
            ,@HBCode
            ,'LI change'
            ,@Login
         )
      END
   END

   -- Add an entry for January 1, 2005
   BEGIN
      IF @bDebug_local = 1
         PRINT 'Adding entry FOR 1/1/2005.'

      SET @dt = '1/1/2005'
      IF EXISTS(SELECT 1 FROM GrossToNet WHERE EffectiveDate = @dt AND UserId = @Login AND CaseId = @CaseId)
         UPDATE GrossToNet
         SET Comment = Comment + ', LI change'
         WHERE EffectiveDate = @dt AND UserId = @Login AND CaseId = @CaseId AND Comment NOT LIKE '%LI Change%'
      ELSE
      BEGIN
         
         SET @age = dbo.fGetAge(@DateOfBirth,@dt)

         INSERT INTO GrossToNet 
         (  
             CaseId
            ,Age                                
            ,EffectiveDate                      
            ,CSRSRate                           
            ,CSRSEarnedRate                           
            ,FERSRate
            ,FERSRateNS
            ,FERSEarnedRate                           
            ,HBCode
            ,Comment
            ,UserId
         )
         VALUES 
         (
             @CaseId
            ,@age
            ,'1/1/2005'
            ,@CSRSRate
            ,@CSRSEarnedRate
            ,@FERSRate
            ,@FERSRateNS
            ,@FERSEarnedRate
            ,@HBCode
            ,'LI change'
            ,@Login
         )
      END
   END

   -- Add an entry for January 1, 2012
   BEGIN
      IF @bDebug_local = 1
         PRINT 'Adding entry FOR 1/1/2012.'

      SET @dt = '1/1/2012'
      IF EXISTS(SELECT 1 FROM GrossToNet WHERE EffectiveDate = @dt AND UserId = @Login AND CaseId = @CaseId)
         UPDATE GrossToNet
         SET Comment = Comment + ', LI change'
         WHERE EffectiveDate = @dt AND UserId = @Login AND CaseId = @CaseId AND Comment NOT LIKE '%LI Change%'
      ELSE
      BEGIN
         
         SET @age = dbo.fGetAge(@DateOfBirth,@dt)

         INSERT INTO GrossToNet 
         (  
             CaseId
            ,Age                                
            ,EffectiveDate                      
            ,CSRSRate                           
            ,CSRSEarnedRate                           
            ,FERSRate
            ,FERSRateNS
            ,FERSEarnedRate                           
            ,HBCode
            ,Comment
            ,UserId
         )
         VALUES 
         (
             @CaseId
            ,@age
            ,'1/1/2012'
            ,@CSRSRate
            ,@CSRSEarnedRate
            ,@FERSRate
            ,@FERSRateNS
            ,@FERSEarnedRate
            ,@HBCode
            ,'LI change'
            ,@Login
         )
      END
   END

   -- Add an entry for January 1, 2016
   BEGIN
      IF @bDebug_local = 1
         PRINT 'Adding entry FOR 1/1/2016.'

      SET @dt = '1/1/2016'
      IF EXISTS(SELECT 1 FROM GrossToNet WHERE EffectiveDate = @dt AND UserId = @Login AND CaseId = @CaseId)
         UPDATE GrossToNet
         SET Comment = Comment + ', LI change'
         WHERE EffectiveDate = @dt AND UserId = @Login AND CaseId = @CaseId AND Comment NOT LIKE '%LI Change%'
      ELSE
      BEGIN
         
         SET @age = dbo.fGetAge(@DateOfBirth,@dt)

         INSERT INTO GrossToNet 
         (  
             CaseId
            ,Age                                
            ,EffectiveDate                      
            ,CSRSRate                           
            ,CSRSEarnedRate                           
            ,FERSRate
            ,FERSRateNS
            ,FERSEarnedRate                           
            ,HBCode
            ,Comment
            ,UserId
         )
         VALUES 
         (
             @CaseId
            ,@age
            ,'1/1/2016'
            ,@CSRSRate
            ,@CSRSEarnedRate
            ,@FERSRate
            ,@FERSRateNS
            ,@FERSEarnedRate
            ,@HBCode
            ,'LI change'
            ,@Login
         )
      END
   END

    -- Add an entry for October 1, 2021
   BEGIN
      IF @bDebug_local = 1
         PRINT 'Adding entry FOR 10/01/2021.'

      SET @dt = '10/01/2021'
      IF EXISTS(SELECT 1 FROM GrossToNet WHERE EffectiveDate = @dt AND UserId = @Login AND CaseId = @CaseId)
         UPDATE GrossToNet
         SET Comment = Comment + ', LI change'
         WHERE EffectiveDate = @dt AND UserId = @Login AND CaseId = @CaseId AND Comment NOT LIKE '%LI Change%'
      ELSE
      BEGIN
         
         SET @age = dbo.fGetAge(@DateOfBirth,@dt)

         INSERT INTO GrossToNet 
         (  
             CaseId
            ,Age                                
            ,EffectiveDate                      
            ,CSRSRate                           
            ,CSRSEarnedRate                           
            ,FERSRate
            ,FERSRateNS
            ,FERSEarnedRate                           
            ,HBCode
            ,Comment
            ,UserId
         )
         VALUES 
         (
             @CaseId
            ,@age
            ,'10/01/2021'
            ,@CSRSRate
            ,@CSRSEarnedRate
            ,@FERSRate
            ,@FERSRateNS
            ,@FERSEarnedRate
            ,@HBCode
            ,'LI change'
            ,@Login
         )
      END
   END

   -- Add an entry FOR the annuity start date.
   IF @bDebug_local = 1
      PRINT 'Adding entry FOR annuity start date.'

   SET @dt = @AnnuityStart
   SET @age = dbo.fGetAge(@DateOfBirth, @dt)

   IF NOT EXISTS(SELECT * FROM GrossToNet WHERE EffectiveDate = @AnnuityStart AND UserId = @Login AND CaseId = @CaseId)
      INSERT INTO GrossToNet 
      (  
          CaseId
         ,Age                                
         ,EffectiveDate                      
         ,CSRSRate                           
         ,CSRSEarnedRate                           
         ,CSRSRemainder
         ,FERSRate
         ,FERSRateNS
         ,FERSEarnedRate                           
         ,FERSRemainder
         ,HBCode
         ,Comment
         ,UserId
      )
      VALUES 
      (
          @CaseId 
         ,@age
         ,@AnnuityStart
         ,@CSRSRate
         ,@CSRSEarnedRate
         ,@CSRSRemainder
         ,@FERSRate
         ,@FERSRateNS
         ,@FERSEarnedRate
         ,@FERSRemainder
         ,@HBCode
         ,'Annuity start date'
         ,@Login
      )
   ELSE
      UPDATE 
         GrossToNet
      SET 
         Comment = 'Annuity start date'
      WHERE 
         EffectiveDate = @AnnuityStart AND 
         UserId = @Login AND 
         CaseId = @CaseId

   -- If disability case, add entries FOR: 62nd birthday, 40%, AND SSA

   IF @G2NCaseType = 1
   BEGIN
      IF @bDebug_local = 1
         PRINT 'Adding entries FOR 62nd birthday, 40%, AND SSA.'

      UPDATE 
         GrossToNet
      SET 
         Comment = Comment + ' (60%)'
      WHERE 
         EffectiveDate = @AnnuityStart AND 
         EffectiveDate < @Age62Date AND 
         UserId = @Login AND 
         CaseId = @CaseId

      -- Add time on disability to FERS time.
      SET @FERSTime = @FERSTime + (DATEDIFF(mm, @AnnuityStart, @Age62Date) / 12.0)

      INSERT INTO GrossToNet 
      (  
          CaseId
         ,Age                                
         ,EffectiveDate                      
         ,CSRSRate                           
         ,CSRSEarnedRate                           
         ,FERSRate                           
         ,FERSRateNS
         ,FERSEarnedRate                           
         ,HBCode
         ,Comment
         ,UserId
      )
      VALUES 
      (
          @CaseId
         ,62
         ,@Age62Date
         ,@CSRSRate
         ,@CSRSEarnedRate
         ,@FERSRate
         ,@FERSRateNS
         ,@FERSEarnedRate
         ,@HBCode
         ,'Age-62 adjustment'
         ,@Login
      )

      -- Set effective date to 1 year after annuity start date.
      IF DAY(@dt) > 1
         SET @dt = dbo.fSetDate(DATEADD(yy, 1, @AnnuityStart), 10, 1)
      ELSE
         SET @dt = dbo.fSetDate(DATEADD(yy, 1, @AnnuityStart), 10, 0)


      SET @age = dbo.fGetAge(@DateOfBirth, @dt)

      IF @age < 62
      BEGIN
         IF NOT EXISTS(SELECT * FROM GrossToNet WHERE EffectiveDate = @dt AND UserId = @Login AND CaseId = @CaseId)
            INSERT INTO GrossToNet 
            (
                CaseId
               ,Age                                
               ,EffectiveDate                      
               ,CSRSRate                           
               ,CSRSEarnedRate                           
               ,FERSRate                           
               ,FERSRateNS
               ,FERSEarnedRate                           
               ,HBCode
               ,Comment
               ,UserId
            )
            VALUES 
            (
                @CaseId
               ,@age
               ,@dt
               ,@CSRSRate
               ,@CSRSEarnedRate
               ,@FERSRate
               ,@FERSRateNS
               ,@FERSEarnedRate
               ,@HBCode
               ,'40% Adjustment'
               ,@Login
            )
         ELSE
            UPDATE GrossToNet
            SET Comment = Comment + ', 40% Adjustment'
            WHERE EffectiveDate = @dt AND UserId = @Login AND CaseId = @CaseId
       END

      IF @SSAAmount > 0 AND @SSADate is NOT null
      BEGIN
         SET @dt = @SSADate
         SET @age = dbo.fGetAge(@DateOfBirth,@dt)

         IF NOT EXISTS (SELECT * FROM GrossToNet WHERE EffectiveDate = @SSADate AND UserId = @Login AND CaseId = @CaseId)
            INSERT INTO GrossToNet 
            (  
                CaseId
               ,Age                                
               ,EffectiveDate                      
               ,CSRSRate                           
               ,CSRSEarnedRate                           
               ,FERSRate                           
               ,FERSRateNS
               ,FERSEarnedRate                           
               ,HBCode
               ,Comment
               ,UserId
            )
            VALUES 
            (
                @CaseId
               ,@age
               ,@SSADate
               ,@CSRSRate
               ,@CSRSEarnedRate
               ,@FERSRate
               ,@FERSRateNS
               ,@FERSEarnedRate
               ,@HBCode
               ,'SSA Benefit Adjustment'
               ,@Login
            )
         ELSE
            UPDATE GrossToNet
            SET Comment = Comment + ', SSA Benefit Adjustment'
            WHERE EffectiveDate = @SSADate AND UserId = @Login AND CaseId = @CaseId
      END
   END



   /******************************************************************
     Add HB Premiums, IF any.
   ******************************************************************/

   SET @cs = CURSOR SCROLL KEYSET FOR 
               SELECT 
               PlanCode
              ,EffectiveDate
            FROM 
               vwCaseHBChanges
            WHERE 
               CaseId = @CaseId AND
               (  
               EffectiveDate IS NOT NULL OR                
                  (
                  PlanCode <> '011' AND EffectiveDate IS NULL    
                  )
               )

            ORDER BY 
               EffectiveDate
            
   OPEN @cs
   FETCH FIRST FROM @cs INTO @HBCode, @dt

   WHILE @@FETCH_STATUS = 0
   BEGIN

      --IF NOT (@HBCode IS NULL OR @HBCode = '011')
      BEGIN

         IF @dt IS NULL
            SET @dt = @AnnuityStart      
   
         IF @bDebug_local = 1
            PRINT 'Processing HB premiums.'
   
         EXEC @rc = spAddGrossToNetHB @CaseId
                                     ,@HBCode
                                     ,@dt
                                     ,@bDebug
                                     ,@Login
         IF @rc < 0
         BEGIN
            SET @str = 'spAddGrossToNetHB returned ' + LTRIM(STR(@rc)) + 
                       ' for CaseId ' + LTRIM(STR(@CaseId)) +
                       ' with HBCode ' + ISNULL(@HBCode, 'NULL') +
                       ' and EffectiveDate ' + ISNULL(CONVERT(VARCHAR(10), @dt, 101), 'NULL')
            INSERT INTO tblErrorLog (CaseId, Process, ErrorMsg) VALUES (@CaseId, 'spCalcGrossToNet_main', @str)
            DEALLOCATE @cs
            RETURN @rc
         END
   
      END

      FETCH NEXT FROM @cs INTO @HBCode, @dt
   END
   CLOSE @cs

   /******************************************************************
     Figure out CSRS COLAs
   ******************************************************************/
   IF (@CSRSEarnedRate > 0 OR @CSRSRate > 0) AND @AnnuityStart is NOT null
   BEGIN
      IF @bDebug_local = 1
         PRINT 'Calling spAddGrossToNetCSRS'

      exec @rc = spAddGrossToNetCSRS @CaseId
                                    ,@AnnuityStart
                                    ,@DateOfBirth
                                    ,@CSRSRate
                                    ,@CSRSEarnedRate = @CSRSEarnedRate OUTPUT
                                    ,@CSRSRemainder = @CSRSRemainder OUTPUT
                                    ,@bDebug = @bDebug
                                    ,@Login = @Login
      IF @rc < 0
      BEGIN
         SET @str = 'spAddGrossToNetCSRS returned ' + LTRIM(STR(@rc)) + 
                    ' for CaseId ' + LTRIM(STR(@CaseId)) +
                    ' with AnnuityStart ' + ISNULL(CONVERT(VARCHAR(10), @AnnuityStart, 101), 'NULL')
         INSERT INTO tblErrorLog (CaseId, Process, ErrorMsg) VALUES (@CaseId, 'spCalcGrossToNet_main', @str)
         RETURN @rc
      END
   END


   /******************************************************************
     Figure out FERS COLAs
   ******************************************************************/
   IF @G2NCaseType <> 3 AND (@FERSRate > 0) AND NOT (@AnnuityStart IS NULL)
   BEGIN
      IF @bDebug_local = 1
         PRINT 'Calling spAddGrossToNetFERS'

      exec @rc = spAddGrossToNetFERS @CaseId
                                    ,@AnnuityStart
                                    ,@DateOfBirth
                                    ,@Age62Date
                                    ,@G2NCaseType   
                                    ,@AvgSalPT62    
                                    ,@FERSEarnedRate = @FERSEarnedRate OUTPUT
                                    ,@FERSRemainder = @FERSRemainder OUTPUT
                                    ,@bDebug = @bDebug
                                    ,@Login = @Login
      IF @rc < 0
       BEGIN
         SET @str = 'spAddGrossToNetFERS returned ' + ISNULL(LTRIM(STR(@rc)), '') + 
                    ' for CaseId ' + LTRIM(STR(@CaseId)) +
                    ' with G2NCaseType ' + LTRIM(STR(@G2NCaseType))
         INSERT INTO tblErrorLog (CaseId, Process, ErrorMsg) VALUES (@CaseId, 'spCalcGrossToNet_main', @str)
         RETURN @rc
       END
   END


   /******************************************************************
     For disability, calculate adjustments on FERS disability rate.
   ******************************************************************/

   IF @G2NCaseType = 1
   BEGIN
      DECLARE @bFirstCOLA BIT
      DECLARE @bUseSSA    BIT
      DECLARE @DisAmount  DECIMAL(12,4)
      DECLARE @DisRate    DECIMAL(2,1)
      DECLARE @DisRateSSA DECIMAL(2,1)
      DECLARE @comment    VARCHAR(200)
      DECLARE @Date40     DATE

      IF @bDebug_local = 1
         PRINT 'Calculating adjustments on FERS disability rate.' 

      SET @bFirstCOLA = 1
      SET @bUseSSA = 0
      SET @DisRate = 0.6
      SET @DisRateSSA = 1.0
      SET @cs = CURSOR SCROLL KEYSET FOR
                  SELECT 
                     EffectiveDate, FERSCola/100, Comment
                  FROM 
                     GrossToNet
                  WHERE 
                     EffectiveDate < @Age62Date AND 
                     UserId = @Login AND 
                     CaseId = @CaseId
                     --and EffectiveDate >= @AnnuityStart
                  ORDER BY 
                     EffectiveDate
      OPEN @cs
      FETCH FIRST FROM @cs INTO @dt, @cola, @comment
      WHILE @@FETCH_STATUS = 0
      BEGIN
         IF @comment LIKE '%40[%]%'
         BEGIN
            SET @DisRate = 0.4
            SET @DisRateSSA = 0.6
            SET @Date40 = @dt
         END

         IF @comment LIKE '%SSA Benefit%'
         BEGIN
            SET @bUseSSA = 1

            UPDATE 
               GrossToNet
            SET 
               SSAMonthly = @SSAAmount
            WHERE 
               EffectiveDate >= @SSADate AND 
               UserId = @Login AND 
               CaseId = @CaseId
         END

         IF @cola > 0
         BEGIN                       
            IF (
               YEAR(@dt) BETWEEN 1994 AND 1996 AND 
               MONTH(@dt) = 3 AND 
               DAY(@dt) = 1 AND 
               @comment LIKE '%FERS COLA%' AND
               DATEADD(MM, -3, @dt) >= DATEADD(yy, 1, @AnnuityStart)
               ) OR
               (
               NOT (YEAR(@dt) BETWEEN 1994 AND 1996 AND 
               MONTH(@dt) = 3 AND 
               DAY(@dt) = 1 AND 
               @comment LIKE '%FERS COLA%') AND
               @dt >= DATEADD(yy, 1, @AnnuityStart)
               )
            BEGIN
               SET @AvgSalPT = CASE 
                                  WHEN (@AvgSalPT * @cola) < 1 THEN @AvgSalPT + 1.0
                                  ELSE @AvgSalPT * (1.0 + @cola)
                               END                   
                               
                               
               IF @bUseSSA = 1 AND @dt >= @Date40 AND NOT (@comment LIKE '%SSA Benefit%' AND @comment LIKE '%Fers Cola%')
               BEGIN
                  -- For SSA, the first COLA is NOT prorated.
                  IF @bFirstCOLA=1
                  BEGIN
                     SELECT 
                        @cola = COLA
                     FROM 
                        rtblCOLAs
                     WHERE 
                        RetirementSystem = 2 AND 
                        AnnuityDate = @dt AND
                        COLA > 0

                     SET @bFirstCOLA = 0
                  END

                  SET @SSAAmount = floor(@SSAAmount * (1.0 + @cola))
               END
               
               
            END
         END

         SET @d1 = @AvgSalPT * @DisRate 
         SET @d2 = 0
         IF @bUseSSA = 1
            SET @d2 = @SSAAmount * 12 *  @DisRateSSA

         SET @DisAmount = ((@d1 - @d2) * @SurvivorRate) / 12
         if @DisAmount < 0
            set @DisAmount = 0


         IF @bUseSSA = 1
            UPDATE GrossToNet
            SET FERSRate = ROUND(@DisAmount,1,1) --truncate
               ,FERSRateNS = @d1
               ,SSAMonthly = @SSAAmount
            WHERE 
               EffectiveDate = @dt AND 
               UserId = @Login AND 
               CaseId = @CaseId
         ELSE
            UPDATE GrossToNet
            SET FERSRate = ROUND(@DisAmount,1,1) --truncate
               ,FERSRateNS = @d1
            WHERE 
               EffectiveDate = @dt AND 
               UserId = @Login AND 
               CaseId = @CaseId

         FETCH NEXT FROM @cs INTO @dt, @cola, @comment
      END



      /******************************************************************
        Age 62 Recalculation.
      ******************************************************************/
      IF @Age62Date > @AnnuityStart
      BEGIN
         DECLARE @CSRSCola   DECIMAL(3,3)
         DECLARE @FERSCola   DECIMAL(3,3)
         
         UPDATE 
            GrossToNet
         SET 
            FERSRate = 0
         WHERE 
            EffectiveDate >= @Age62Date AND 
            EffectiveDate >= @AnnuityStart AND
            UserId = @Login AND 
            CaseId = @CaseId
            
         IF @bDebug_local=1 AND @@rowcount > 0
            PRINT 'Age 62 recalculation:  FERSTime=' + ISNULL(LTRIM(STR(@FERSTime)), '') + ';  CSRSTime=' + ISNULL(LTRIM(STR(@CSRSTime)), '')
   
         SET @cs = CURSOR SCROLL KEYSET FOR
                     SELECT    
                        EffectiveDate, CSRSCola/100, FERSCola/100
                     FROM 
                        GrossToNet
                     WHERE 
                        (EffectiveDate = @Age62Date OR 
                        (EffectiveDate > @Age62Date AND Comment LIKE '%COLA')) AND 
                        EffectiveDate >= @AnnuityStart AND 
                        UserId = @Login AND 
                        CaseId = @CaseId
                     ORDER BY 
                        EffectiveDate
         OPEN @cs
         FETCH FIRST FROM @cs INTO @dt, @CSRSCola, @FERSCola
         WHILE @@FETCH_STATUS = 0
         BEGIN
            IF @dt = @Age62Date
            BEGIN

               SET @d1 = @AvgSalPT62 * @FERSTime * CASE WHEN @FERSTime >= 20 THEN .011 ELSE .01 END

               SET @FERSEarnedRate = (@d1 * @SurvivorRate / 12.0) 
   
               IF @CSRSTime < 5      
                  SET @d1 = @AvgSalPT62 * .015 * @CSRSTime
               ELSE IF @CSRSTime < 10
                  SET @d1 = @AvgSalPT62 * .015 * 5 + 
                            (@AvgSalPT62 * .0175 * (@CSRSTime - 5))
               ELSE
                  SET @d1 = @AvgSalPT62 * .015 * 5 + 
                            (@AvgSalPT62 * .0175 * 5) +
                            (@AvgSalPT62 * .02   * (@CSRSTime - 10))
   
               SET @CSRSEarnedRate = (@d1 * @SurvivorRate / 12.0) 

               IF @bDebug_local=1
               BEGIN
                  PRINT '  FERSEarnedRate:  ' + ISNULL(LTRIM(STR(@FERSEarnedRate)), '')
                  PRINT '  CSRSEarnedRate:  ' + ISNULL(LTRIM(STR(@CSRSEarnedRate)), '')
               END
            END
            ELSE
            BEGIN
               IF @CSRSCola > 0
                  SET @CSRSEarnedRate = CASE 
                                         WHEN (@CSRSEarnedRate * @CSRSCola) < 1 THEN @CSRSEarnedRate + 1
                                         ELSE @CSRSEarnedRate * (1.0 + @CSRSCola)
                                        END
               IF @FERSCola > 0
                  SET @FERSEarnedRate = CASE 
                                         WHEN (@FERSEarnedRate * @FERSCola) < 1 THEN @FERSEarnedRate + 1
                                         ELSE @FERSEarnedRate * (1.0 + @FERSCola)
                                        END
               IF @bDebug_local=1
               BEGIN
                  PRINT '  FERSEarnedRate:  ' + ISNULL(LTRIM(STR(@FERSEarnedRate)), '')
                  PRINT '  CSRSEarnedRate:  ' + ISNULL(LTRIM(STR(@CSRSEarnedRate)), '')
               END
            END
   
            UPDATE GrossToNet
            SET 
                CSRSEarnedRate = @CSRSEarnedRate
               ,FERSEarnedRate = @FERSEarnedRate
            WHERE 
               EffectiveDate >= @dt AND 
               EffectiveDate >= @AnnuityStart AND
               UserId = @Login AND 
               CaseId = @CaseId
   
            FETCH NEXT FROM @cs INTO @dt, @CSRSCola, @FERSCola
         END
      END
   END
   
   /******************************************************************
     End of FERS disability calculations.
   ******************************************************************/

   IF @bDebug_local = 1
    BEGIN
      PRINT ''
      PRINT ' Checking life insurance options.'
      PRINT ''
    END

   /******************************************************************
     Calculate life insurance premiums, IF required.
   ******************************************************************/

   IF @G2NCaseType <> 2
   BEGIN

      SET @cs = CURSOR SCROLL KEYSET FOR 
               SELECT
                   Basic
                  ,EffectiveDate
                  ,PostRetReduction
                  ,Standard
                  ,CASE 
                     WHEN Additional BETWEEN 'A' AND 'E' THEN 1 + ASCII(Additional) - ASCII('A')
                     WHEN Additional BETWEEN 'F' AND 'J' THEN 1 + ASCII(Additional) - ASCII('F')
                     ELSE 0
                   END
                  ,CASE WHEN Additional BETWEEN 'A' AND 'E' THEN 1 ELSE 0 END 
                  ,CASE
                     WHEN Family BETWEEN 'F' AND 'J' THEN 1 + ASCII(Family) - ASCII('F')                   
                     WHEN Family = 'None' THEN 0 
                     ELSE Family
                   END                     
                  ,CASE WHEN Family BETWEEN '1' AND '5' THEN 1 ELSE 0 END 
                  ,Additional 
                  ,Family
               FROM
                   vwCaseLifeInsurance
               WHERE 
                   CaseId = @CaseId -- AND EffectiveDate <> @DateOfBirth
               ORDER BY 
                   EffectiveDate
   
      OPEN @cs
      FETCH FIRST FROM @cs INTO @LIBase, @dt, @PRRCode, @OptionA, @OptionB, @bOptionB_Reduced, @OptionC, @bOptionC_Reduced, @OptionBCode, @OptionCCode


      -- CLEAN UP the ZERO LI default (inserted at standard above dates) value records if case does not have LI information..
      IF @@FETCH_STATUS <> 0
      BEGIN
         DELETE FROM GrossToNet
         WHERE 
            Comment = 'LI Change' AND 
            UserId = @Login AND 
            CaseId = @CaseId AND
            (Basic + OptionA + OptionB + OptionC) = 0

         UPDATE GrossToNet
         SET Comment = REPLACE (Comment, 'LI Change, ', '' )
         WHERE 
            Comment like 'LI Change,%' AND 
            UserId = @Login AND 
            CaseId = @CaseId AND
            (Basic + OptionA + OptionB + OptionC) = 0
      END


      WHILE @@FETCH_STATUS = 0
      BEGIN


   
         IF @dt = @DateOfBirth
            SET @dt = @AnnuityStart
   
         EXEC  @rc = spAddGrossToNetLI @CaseId
                                  ,@dt
                                  ,@LIBase
                                  ,@OptionA
                                  ,@OptionB
                                  ,@bOptionB_Reduced
                                  ,@OptionC
                                  ,@bOptionC_Reduced
                                  ,@PRRCode
                                  ,@OptionBCode
                                  ,@OptionCCode
                                  ,@bDebug
                                  ,@Login = @Login
         IF @rc < 0 
         BEGIN
            SET @str = 'spAddGrossToNetLI returned ' + LTRIM(STR(@rc)) + 
                       ' for CaseId ' + LTRIM(STR(@CaseId)) +
                       ' with LIBase ' + LTRIM(STR(@LIBase)) +
                       ' and OptionA ' + LTRIM(STR(@OptionA))
            INSERT INTO tblErrorLog (CaseId, Process, ErrorMsg) VALUES (@CaseId, 'spCalcGrossToNet_main', @str)
            DEALLOCATE @cs
            RETURN @rc
         END
   
         FETCH NEXT FROM @cs INTO @LIBase, @dt, @PRRCode, @OptionA, @OptionB, @bOptionB_Reduced, @OptionC, @bOptionC_Reduced, @OptionBCode, @OptionCCode
      END
      CLOSE @cs
   END
   ELSE 
   BEGIN
      -- Cleanup blank LI records for the DEATH cases.
      DELETE FROM GrossToNet
      WHERE 
         Comment = 'LI Change' AND 
         UserId = @Login AND 
         CaseId = @CaseId AND
         (Basic + OptionA + OptionB + OptionC) = 0

      UPDATE GrossToNet
      SET Comment = REPLACE (Comment, 'LI Change, ', '' )
      WHERE 
         Comment like 'LI Change,%' AND 
         UserId = @Login AND 
         CaseId = @CaseId AND
         (Basic + OptionA + OptionB + OptionC) = 0
   END



   /******************************************************************
     Calculate net (this is the easy part).
   ******************************************************************/

   IF @G2NCaseType =1
   BEGIN
      
      DECLARE @RunProvCode   VARCHAR(10)
      
      SELECT 
         @RunProvCode = ProvRetCode 
      FROM 
         tblRunResults 
      WHERE 
         CaseId =  @CaseId AND
         RunType = 0
         
      
      IF @RunProvCode IN (284, 285)  -- Added this logic to handle new FERS DISABILTY ProvCode for Customs and Border Protection Officers
      BEGIN      
      
         UPDATE 
            GrossToNet
         SET TotalGross  = CASE WHEN @bVoluntaryOverride <> 0 OR
                                     EffectiveDate >= @Age62Date OR
                                     CSRSEarnedRate + FERSEarnedRate > FERSRate
                                THEN 
                                     CSRSEarnedRate + FERSEarnedRate
                                ELSE 
                                     FERSRate
                           END
            ,ProvRetCode = CASE WHEN @bVoluntaryOverride <> 0 OR
                                     EffectiveDate >= @Age62Date OR
                                     CSRSEarnedRate + FERSEarnedRate > FERSRate
                                THEN 
                                     261
                                ELSE 
                                     262
                           END
         WHERE 
            UserId = @Login AND 
            CaseId = @CaseId

      END                    
   END
   ELSE
   BEGIN
      UPDATE 
         GrossToNet
      SET 
         TotalGross  = CSRSRate + FERSRate
        ,ProvRetCode = CASE WHEN @G2NCaseType = 2 THEN 981 ELSE 0 END
      WHERE 
          UserId = @Login AND CaseId = @CaseId
   END


   IF CURSOR_status('local','@cs') >= -1
      deallocate @cs

--   CLOSE @cs
   DROP table #t2


   /******************************************************************
     Return Result SET back.
   ******************************************************************/
   DECLARE @CutoffDate DATE
   
   SELECT 
      @AnnuityStart = EffectiveDate 
   FROM 
      GrossToNet
   WHERE 
      Comment LIKE 'Annuity start date%' AND
      UserId = @Login AND CaseId = @CaseId

   SELECT 
      @CutoffDate = MIN(CutoffDate)
   FROM 
      rtblCutoff
   WHERE 
      CutoffDate >= CONVERT(CHAR(10), GetDate(), 102)

   UPDATE 
      GrossToNet
   SET 
      Net = TotalGross - (HBPremium + Basic + PRR + OptionA + OptionB + OptionC)	
   WHERE 
      UserId = @Login AND CaseId = @CaseId


   IF EXISTS (SELECT 1 FROM tblCases WHERE StatusCodeId = dbo.fGetCodeId('101', 'StatusCodes') AND CaseId = @CaseId) AND
      EXISTS (SELECT 1 FROM GrossToNet WHERE UserId = @Login AND CaseId = @CaseId)
   BEGIN
      -- set the HB premium based on the most recent year.
      UPDATE 
        GrossToNet
      SET 
         HBPremium = dbo.fGetHBPremium(HBCode, YEAR(EffectiveDate), 1),
         Comment = Comment + ' [*] '
      WHERE 
         Comment like '%Annuity start date%' AND 
         HBCode IS NOT NULL AND
         HBPremium = 0.00 AND
         UserId = @Login AND 
         CaseId = @CaseId 

      UPDATE 
         GrossToNet
      SET 
         Net = TotalGross - (HBPremium + Basic + PRR + OptionA + OptionB + OptionC)	
      WHERE 
         UserId = @Login AND CaseId = @CaseId

      SELECT
          EffectiveDate
         ,Age
         ,CSRSCola
         ,0 CSRSRate
         ,CSRSEarnedRate
         ,FERSCola
         ,FERSRate
         ,FERSRateNS
         ,FERSEarnedRate
         ,TotalGross
         ,CSRSEarnedRate + FERSEarnedRate 'TotalEarnedRate'
         ,ProvRetCode
         ,HBCode
         ,HBPremium
         ,Basic
         ,PRR
         ,OptionA
         ,OptionB
         ,OptionC
         ,BasicValue
         ,PRRCode
         ,OptionACode
         ,OptionBCode
         ,OptionCCode
         ,SSAMonthly
         ,Net
         ,Comment 
      FROM 
         GrossToNet
      WHERE 
         (EffectiveDate = @AnnuityStart OR
         (EffectiveDate > @AnnuityStart AND Age IN (62, 65))) AND
         UserId = @Login AND CaseId = @CaseId 
      ORDER BY 
         EffectiveDate
   END
   ELSE 
   BEGIN
      IF (SELECT count(*) FROM GrossToNet WHERE Comment LIKE 'Age-62%' AND UserId = @Login AND CaseId = @CaseId) > 0
         -- SET @cResults = CURSOR FOR
         SELECT
             EffectiveDate
            ,Age
            ,CSRSCola
            ,0 CSRSRate
            ,CSRSEarnedRate
            ,FERSCola
            ,FERSRate
            ,FERSRateNS
            ,FERSEarnedRate
            ,TotalGross
            ,CSRSEarnedRate + FERSEarnedRate 'TotalEarnedRate'
            ,ProvRetCode
            ,HBCode
            ,HBPremium
            ,Basic
            ,PRR
            ,OptionA
            ,OptionB
            ,OptionC
            ,BasicValue
            ,PRRCode
            ,OptionACode
            ,OptionBCode
            ,OptionCCode
            ,SSAMonthly
            ,Net
            ,Comment 
         FROM 
            GrossToNet
         WHERE 
            EffectiveDate BETWEEN @AnnuityStart AND @CutoffDate AND
            UserId = @Login AND CaseId = @CaseId
         ORDER BY 
            EffectiveDate
      ELSE
         -- SET @cResults = CURSOR FOR
         SELECT 
             EffectiveDate
            ,Age
            ,CSRSCola
            ,CSRSRate
            ,0 CSRSEarnedRate
            ,FERSCola
            ,FERSRate
            ,0 FERSRateNS
            ,0 FERSEarnedRate
            ,TotalGross
            ,0 TotalEarnedRate
            ,ProvRetCode
            ,HBCode
            ,HBPremium
            ,Basic
            ,PRR
            ,OptionA
            ,OptionB
            ,OptionC
            ,BasicValue
            ,PRRCode
            ,OptionACode
            ,OptionBCode
            ,OptionCCode
            ,0 SSAMonthly
            ,Net
            ,Comment
         FROM 
            GrossToNet
         WHERE 
            EffectiveDate BETWEEN @AnnuityStart AND @CutoffDate AND
            UserId = @Login AND CaseId = @CaseId
         ORDER BY 
            EffectiveDate
   END
END
GO CASE WHEN @bVoluntaryOverride <> 0 OR
                                     EffectiveDate >= @Age62Date OR
                                     CSRSEarnedRate + FERSEarnedRate > FERSRate
                                THEN 
                                     CSRSEarnedRate + FERSEarnedRate
                                ELSE 
                                     FERSRate
                           END
            ,ProvRetCode = CASE WHEN @bVoluntaryOverride <> 0 OR
                                     EffectiveDate >= @Age62Date OR
                                     CSRSEarnedRate + FERSEarnedRate > FERSRate
                                THEN 
                                     284
                                ELSE 
                                     285
                           END
         WHERE 
            UserId = @Login AND 
            CaseId = @CaseId

      END
      ELSE IF @RunProvCode IN (961, 962)      ---- Added this logic to handle new OWCP DISABILTY ProvCode 
      BEGIN
		  UPDATE 
				GrossToNet
			 SET TotalGross  = CASE WHEN @bVoluntaryOverride <> 0 OR
										 EffectiveDate >= @Age62Date OR
										 CSRSEarnedRate + FERSEarnedRate > FERSRate
									THEN 
										 CSRSEarnedRate + FERSEarnedRate
									ELSE 
										 FERSRate
							   END
				,ProvRetCode = CASE WHEN @bVoluntaryOverride <> 0 OR
										 EffectiveDate >= @Age62Date OR
										 CSRSEarnedRate + FERSEarnedRate > FERSRate
									THEN 
										 961
									ELSE 
										 962
							   END
			 WHERE 
				UserId = @Login AND 
				CaseId = @CaseId
      END  
      ELSE       
      BEGIN      
      
         UPDATE 
            GrossToNet
         SET TotalGross  =