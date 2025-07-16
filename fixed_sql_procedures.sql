-- ==============================================================
-- FIXED: spProcessCases - Proper CaseId tracking in error logs
-- ==============================================================

ALTER PROCEDURE [dbo].[spProcessCases]
    @bTestMF                BIT = NULL
   ,@bStatusUpdate          BIT = 1
   ,@bSendMail              BIT = 1
   ,@bSendFile              BIT = 1
   ,@bDebug                 BIT = 0
   ,@sDebugEmail            VARCHAR(150) = NULL
AS 
BEGIN
   SET NOCOUNT ON

   DECLARE @bExists                 SMALLINT
   DECLARE @CR                      CHAR(1)
   DECLARE @FName                   VARCHAR(100)
   DECLARE @FPrefix                 VARCHAR(100)
   DECLARE @s                       VARCHAR(20)
   DECLARE @sAttachments            VARCHAR(150) = ''
   DECLARE @sCommand                VARCHAR(128)
   DECLARE @sDataDir                VARCHAR(30)
   DECLARE @sDataFile               VARCHAR(100)
   DECLARE @sDbName                 VARCHAR(30) = db_name()
   DECLARE @sMFDataDir              VARCHAR(30)
   DECLARE @sMFDatasetName          VARCHAR(100)
   DECLARE @sMsg                    VARCHAR(200)
   DECLARE @sQuery                  VARCHAR(200) = ''
   DECLARE @n                       INT
   DECLARE @sErrorText              VARCHAR(100)
   DECLARE @StartTime               DATETIME
   DECLARE @Recipients              VARCHAR(1000) = ''
   DECLARE @Copy                    VARCHAR(1000) = ''
   DECLARE @BlindCopy               VARCHAR(1000) = ''
   DECLARE @ErrorRecipients         VARCHAR(1000) = ''
   DECLARE @AdminRecipients         VARCHAR(1000) = ''
   DECLARE @Msg                     VARCHAR(2000)
   
   -- FIXED: Add variable to track current CaseId for better error logging
   DECLARE @CurrentCaseId           INT = NULL

   IF @bTestMF IS NULL
      GOTO USAGE

   IF @bSendMail = 1 AND @bDebug = 1 AND @sDebugEmail IS NULL
   BEGIN
      PRINT '** A Debug e-mail address(es) must be specified WHEN SendMail & Debug modes are ON (1)'
      PRINT ' '
      GOTO USAGE
   END

   -- Configuration retrieval
   SET @sErrorText = ''
   EXEC dbo.spGetConfiguration @KeyName = 'MFDataDirectory', @KeyValue = @sDataDir OUTPUT, @Error = @sErrorText OUTPUT
   EXEC dbo.spGetConfiguration @KeyName = 'MFDailyCycleDataFile', @KeyValue = @sMFDatasetName OUTPUT, @Error = @sErrorText OUTPUT

   IF @sErrorText <> ''
   BEGIN
      SET @sMsg = 'Configuration data missing: ' + @sErrorText 
      PRINT @sMsg
      -- FIXED: Include CaseId in error log (NULL for configuration errors)
      INSERT INTO tblErrorLog (CaseId, Process, ErrorMsg) VALUES (NULL, 'spProcessCases', @sMsg)
      RETURN 1
   END

   -- Email configuration
   SET @sErrorText = ''
   IF @bSendMail = 1
   BEGIN
      EXEC spGetReportEMailAddresses 'Pending Cases: Sent to mainframe', @Recipients OUTPUT, @Copy OUTPUT, @BlindCopy OUTPUT, @ErrorRecipients OUTPUT, @AdminRecipients OUTPUT, @sMsg OUTPUT
      
      IF dbo.fIsBlank(@Recipients) = 1
         SET @sErrorText = 'Missing Recipients Information'
   END

   IF @sErrorText <> ''
   BEGIN
      SET @s = 'Configuration data is missing: ' + @sErrorText 
      PRINT @s
      -- FIXED: Include CaseId in error log (NULL for configuration errors)
      INSERT INTO tblErrorLog (CaseId, Process, ErrorMsg) VALUES (NULL, 'spProcessCases', @s)
      SET @sErrorText = ''
   END

   SET @n = 0
   SET @CR = CHAR(13)
   SELECT @StartTime = GETDATE()

   -- Directory setup
   IF SUBSTRING(@sDataDir, LEN(@sDataDir), 1) <> '\'
      SET @sDataDir = @sDataDir + '\'

   SET @sMFDataDir = @sDataDir + 'MFData\' + REPLACE(CONVERT(VARCHAR(7), @StartTime, 102), '.', '\')

   SET @sCommand = 'dir ' + @sMFDataDir
   EXEC @n = master.dbo.xp_cmdshell @sCommand
   IF @n <> 0
   BEGIN
      SET @sCommand = 'mkdir ' + @sMFDataDir
      EXEC master.dbo.xp_cmdshell @sCommand
   END

   -- Build file name
   IF @bTestMF = 1
      SET @FPrefix = @sMFDataDir + '\mfT' + SUBSTRING(CONVERT(CHAR(6), GETDATE(), 12), 3, 4) 
   ELSE
      SET @FPrefix = @sMFDataDir + '\mfp' + SUBSTRING(CONVERT(CHAR(6), GETDATE(), 12), 3, 4) 

   IF @bDebug = 1
      SET @FPrefix = @FPrefix + '_dbg'

   -- Generate MF data
   PRINT 'spGenerateMFData '''', ' + @FPrefix + ', ' + STR(@bTestMF,1) + ', ' + STR(@bStatusUpdate,1)
         
   -- FIXED: Include CurrentCaseId OUTPUT parameter to track which case caused errors
   EXEC @n = spGenerateMFData '', @FPrefix, @bTestMF, @bStatusUpdate, @bSendMail, @bDebug,
                              @CurrentCaseId = @CurrentCaseId OUTPUT
                              
   PRINT ' ==> ' + LTRIM(STR(@n))
   
   -- FIXED: If error occurred and we have a CaseId, include it in debug output
   IF @CurrentCaseId IS NOT NULL AND @bDebug = 1
   BEGIN
      PRINT 'Error occurred while processing CaseId: ' + CAST(@CurrentCaseId AS VARCHAR(20))
   END

   -- File processing
   SET @FName = @FPrefix
   SET @sDataFile = @FName + '.psv'
   EXEC @bExists = spFileExists @sDataFile

   IF @bExists <> 1
   BEGIN
      IF @bExists < 1
         SET @sErrorText = 'spFileExists ''' + @sDataFile + ''' returned ' + LTRIM(STR(@bExists)) + '.'
      ELSE
         SET @sErrorText = 'Data file ''' + @sDataFile + ''' was not created.'
         
      -- FIXED: Include CaseId if available
      IF @CurrentCaseId IS NOT NULL
         SET @sErrorText = @sErrorText + ' (Last CaseId processed: ' + CAST(@CurrentCaseId AS VARCHAR(20)) + ')'

      GOTO ERROR_HANDLER
   END

   -- Continue with file parsing and FTP logic...
   SET @sCommand = @sDataDir + '\ParseMFData ' + @sDataDir + ' ' + @FName + ' 1'
   IF @bDebug=1
      SET @sCommand = @sCommand + ' 1'
   EXEC master.dbo.xp_cmdshell @sCommand

   IF (@bSendFile = 1) AND (@bTestMF = 0) AND (@n > 0)
   BEGIN
      SET @sCommand = @sDataDir + '\sendfile ' + @FName + ' ' + @sMFDatasetName 
      PRINT @sCommand
      EXEC master.dbo.xp_cmdshell @sCommand

      SET @sDataFile = @FName + '.snt'
      EXEC @bExists = spFileExists @sDataFile
   
      IF @bExists <> 1
      BEGIN
         IF @bExists < 1
            SET @sErrorText = 'spFileExists ''' + @sDataFile + ''' returned ' + LTRIM(STR(@bExists)) + '.'
         ELSE
            SET @sErrorText = 'The FTP process failed (file ''' + @sDataFile + ''' was not created.'
   
         GOTO ERROR_HANDLER
      END
      ELSE
      BEGIN
         DECLARE @sTrmDataFile VARCHAR(100)
         DECLARE @sSntDataFile VARCHAR(100)
         DECLARE @rc INT

         SET @sSntDataFile = @FName + '.snt'
         SET @sTrmDataFile = @FName + '.dat'
         EXEC @rc = spCompareFileSize @FileName1 = @sTrmDataFile, @FileName2 = @sSntDataFile, @AllowedDiff = 0, @bMissingFile1 = 1, @bDebug = @bDebug
         IF @rc <> 0 
         BEGIN
            SET @sErrorText = 'The FTP process failed -- send/receive sizes do not match.'
            GOTO ERROR_HANDLER
         END

         SET @sCommand = 'del ' + @FName + '.snt'
         EXEC master.dbo.xp_cmdshell @sCommand
      END
   
      IF dbo.fIsBlank(@sAttachments) = 1
         SET @sAttachments = @FName + '.txt'
      ELSE
         SET @sAttachments = @sAttachments + ';' + @FName + '.txt'

      IF @bTestMF = 1
         SET @sAttachments = @sAttachments + ';' + @FName + '.dat'
   END

   -- Email sending logic (simplified for brevity)
   -- ... [Email logic continues as before] ...

   GOTO ENDPROC

   USAGE:
      PRINT 'Usage: spProcessCases @bTestMF'
      PRINT '                     ,@bStatusUpdate (1)'
      PRINT '                     ,@bSendMail (1)'
      PRINT '                     ,@bSendFile (1)'
      PRINT '                     ,@bDebug (0)'
      PRINT '                     ,@sDebugEmail(null)'
      GOTO ENDPROC

   ERROR_HANDLER:
      -- FIXED: Log with actual CaseId if available, otherwise NULL
      INSERT INTO tblErrorLog (CaseId, Process, ErrorMsg) 
      VALUES (@CurrentCaseId, 'spProcessCases', @sErrorText)
      
      PRINT 'spProcessCases --> ' + @sErrorText 

      IF @bSendMail=1
      BEGIN
         -- FIXED: Include CaseId in error email if available
         DECLARE @DetailedErrorMsg VARCHAR(500)
         SET @DetailedErrorMsg = @sErrorText
         
         IF @CurrentCaseId IS NOT NULL
         BEGIN
            SET @DetailedErrorMsg = @DetailedErrorMsg + 
                                   ' (Error occurred while processing CaseId: ' + 
                                   CAST(@CurrentCaseId AS VARCHAR(20)) + ')'
         END
         
         EXEC spQueueMail @AdminRecipients
               ,@message = @DetailedErrorMsg
               ,@subject = 'spProcessCases: ERROR'
               ,@Msg = @Msg OUTPUT
      END
      RETURN 1
      
   ENDPROC:   
   SET NOCOUNT OFF
   RETURN 0
END

-- ==============================================================
-- FIXED: spProcessReissueCases - Proper CaseId handling
-- ==============================================================

ALTER PROCEDURE [dbo].[spProcessReissueCases]
    @bStatusUpdate          BIT = 1
   ,@bSendMail              BIT = 1
   ,@bSendFile              BIT = 1
   ,@bDebug                 BIT = 0
   ,@sDebugEmail            VARCHAR(150) = NULL
AS 
BEGIN
   SET NOCOUNT ON

   DECLARE @bExists                    SMALLINT
   DECLARE @CR                         CHAR(1)
   DECLARE @FName                      VARCHAR(100)
   DECLARE @FPrefix                    VARCHAR(100)
   DECLARE @s                          VARCHAR(20)
   DECLARE @sAttachments               VARCHAR(150)
   DECLARE @sCommand                   VARCHAR(128)
   DECLARE @sDataDir                   VARCHAR(30)
   DECLARE @sDataFile                  VARCHAR(100)
   DECLARE @sDbName                    VARCHAR(30)
   DECLARE @sMFDataDir                 VARCHAR(100)
   DECLARE @sMFDatasetName             VARCHAR(100)
   DECLARE @sMsg                       VARCHAR(200)
   DECLARE @sQuery                     VARCHAR(200)
   DECLARE @n                          INT
   DECLARE @sErrorText                 VARCHAR(100)
   DECLARE @StartTime                  DATETIME
   DECLARE @Recipients                 VARCHAR(1000)
   DECLARE @Copy                       VARCHAR(1000)
   DECLARE @BlindCopy                  VARCHAR(1000)
   DECLARE @ErrorRecipients            VARCHAR(1000)
   DECLARE @AdminRecipients            VARCHAR(1000)
   DECLARE @Msg                        VARCHAR(2000)

   IF @bSendMail = 1 AND @bDebug = 1 AND @sDebugEmail IS NULL
   BEGIN
      PRINT '** A Debug e-mail address(es) must be specified WHEN SendMail & Debug modes are ON (1)'
      PRINT ' '
      GOTO USAGE
   END

   -- Configuration retrieval
   SET @sErrorText = ''
   EXEC dbo.spGetConfiguration @KeyName = 'MFDataDirectory', @KeyValue = @sDataDir OUTPUT, @Error = @sErrorText OUTPUT
   EXEC dbo.spGetConfiguration @KeyName = 'MFReissueDataFile', @KeyValue = @sMFDatasetName OUTPUT, @Error = @sErrorText OUTPUT

   IF @sErrorText <> ''
   BEGIN
      SET @sMsg = 'Configuration data missing: ' + @sErrorText 
      PRINT @sMsg
      -- FIXED: Properly specify CaseId column (NULL for configuration errors)
      INSERT INTO tblErrorLog (CaseId, Process, ErrorMsg) VALUES (NULL, 'spProcessReissueCases', @sMsg)
      RETURN 1
   END

   -- Email configuration
   SET @sErrorText = ''
   IF @bSendMail = 1
   BEGIN
      EXEC spGetReportEMailAddresses 'Reissue Cases: Sent to mainframe', @Recipients OUTPUT, @Copy OUTPUT, @BlindCopy OUTPUT, @ErrorRecipients OUTPUT, @AdminRecipients OUTPUT, @sMsg OUTPUT
      
      IF dbo.fIsBlank(@Recipients) = 1
         SET @sErrorText = 'Missing Recipients Information'
   END

   IF @sErrorText <> ''
   BEGIN
      SET @s = 'Configuration data is missing: ' + @sErrorText 
      PRINT @s
      -- FIXED: Properly specify CaseId column (NULL for configuration errors)
      INSERT INTO tblErrorLog (CaseId, Process, ErrorMsg) VALUES (NULL, 'spProcessReissueCases', @s)
      SET @sErrorText = ''
   END

   -- Continue with rest of procedure logic...
   -- [Rest of procedure continues as before]

   GOTO ENDPROC

   USAGE:
      PRINT 'Usage: spProcessReissueCases '
      PRINT '                     ,@bStatusUpdate (1)'
      PRINT '                     ,@bSendMail (1)'
      PRINT '                     ,@bSendFile (1)'
      PRINT '                     ,@bDebug (0)'
      PRINT '                     ,@sDebugEmail(null)'
      GOTO ENDPROC

   ERROR_HANDLER:
      -- FIXED: Properly specify CaseId column (NULL since no specific case)
      INSERT INTO tblErrorLog (CaseId, Process, ErrorMsg) VALUES (NULL, 'spProcessReissueCases', @sErrorText)
      PRINT 'spProcessReissueCases --> ' + @sErrorText 

      IF @bSendMail=1
         EXEC spQueueMail @AdminRecipients
               ,@message = @sErrorText
               ,@subject = 'spProcessReissueCases: ERROR'
               ,@Msg = @Msg OUTPUT
      RETURN 1
      
   ENDPROC:   
   SET NOCOUNT OFF
   RETURN 0
END

-- ==============================================================
-- FIXED: spCalcGrossToNet_main - Proper CaseId in error logging
-- ==============================================================

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
AS
BEGIN
   DECLARE @str VARCHAR(250)
   DECLARE @rc INT
   
   -- ... [Main procedure logic] ...
   
   BEGIN TRY
      -- Example of where errors might occur
      EXEC @rc = spAddGrossToNetHB @CaseId, @HBCode, @dt, @bDebug, @Login
      IF @rc < 0
      BEGIN
         SET @str = 'spAddGrossToNetHB returned ' + LTRIM(STR(@rc))
         -- FIXED: Include CaseId in error log
         INSERT INTO tblErrorLog (CaseId, Process, ErrorMsg) VALUES (@CaseId, 'spCalcGrossToNet_main', @str)
         RETURN @rc
      END
   END TRY
   BEGIN CATCH
      -- FIXED: Include CaseId in error log for exceptions
      SET @str = 'Error in spCalcGrossToNet_main: ' + ERROR_MESSAGE()
      INSERT INTO tblErrorLog (CaseId, Process, ErrorMsg) VALUES (@CaseId, 'spCalcGrossToNet_main', @str)
      RETURN -1
   END CATCH
   
   -- ... [Rest of procedure continues] ...
END