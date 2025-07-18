-- ========================================
-- CONTINUATION OF spCalcGrossToNet_main
-- This is the final part after the ELSE block
-- ========================================

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
GO