USE [RETIRE]
GO

/****** Object:  StoredProcedure [dbo].[spProcessCases]    Script Date: 6/28/2025 7:24:00 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE PROCEDURE [dbo].[spProcessCases]
    @bTestMF                BIT = NULL
   ,@bStatusUpdate          BIT = 1
   ,@bSendMail              BIT = 1
   ,@bSendFile              BIT = 1
   ,@bDebug                 BIT = 0
   ,@sDebugEmail            VARCHAR(150) = NULL
AS 
   /****************************************************************************

   PURPOSE:
      Processes triggered cases, generates the data file, sends it to the
      mainframe for the daily cycle processing, and sends email 
      notifications to various people.

   PARAMETERS
      @bTestMF          1 for test cases, 0 for production, or Null
                        to display help information.  (Default=Null)
      @bStatusUpdate    1 to update status of cases processed, 0 otherwise.
                        (Default=1)
      @sFileSuffix      Suffix for output file name, test only. (Default='a')
      @bSendMail        1 to send results by email, 0 otherwise.  (Default=1)
      @bSendFile        1 to send data file to mainframe, 0 otherwise.  (Default=1)
      @bDebug           1 to enable debug output.  (Default=0)
      @sDebugEmail      contains e-mail addresses for forwarding reports while in
                        debug-mode, or is an empty string.

   LOGIC
     CALL spGenerateMFData to generate the raw data file.
     EXECUTE ParseMFData.cmd to format the data file.
     IF (Production Data) AND (1 or more records were processed)
        EXECUTE SendFile.cmd to FTP the file to the mainframe.
     IF (records processed) AND (@bSendMail=1)
        Send email notifications.

   RETURN VALUES      
      0 - successful
      1 - error occurred

   AUTHOR
      Keith Yager
      Malathi Thadkamalla

   ----------------------------------------------------------------------------
   HISTORY:  $Log: /FACES30/DB/Mainframe/spProcessCases.sql $
   
   10    12/28/16 2:55p Dctcrmt
   SBM 170054 
   
   10     12/28/16 10:12a Dctcrmt
   SBM 170054 -- Filter non-opm emails list excluding valid whitelist
   
   9     8/28/13 10:35a Dctcrsbol
   Minor cleanup.
   
   Added Reissue Changes.
   
   Added @msg parameter when calling spQueueMail procedure.
   
   Changed the project name in the directory path.

   Initial Version.


   ****************************************************************************/

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

   IF @bTestMF IS NULL
      GOTO USAGE

   IF @bSendMail = 1 AND @bDebug = 1 AND @sDebugEmail IS NULL
   BEGIN
      PRINT '** A Debug e-mail address(es) must be specified WHEN SendMail & Debug modes are ON (1)'
      PRINT ' '
      GOTO USAGE
   END

   --***************************************************************************
   -- Retrieve directory & login data from configuration table:
   --***************************************************************************

   SET @sErrorText = ''

   EXEC dbo.spGetConfiguration @KeyName = 'MFDataDirectory', @KeyValue = @sDataDir OUTPUT, @Error = @sErrorText OUTPUT
   EXEC dbo.spGetConfiguration @KeyName = 'MFDailyCycleDataFile', @KeyValue = @sMFDatasetName OUTPUT, @Error = @sErrorText OUTPUT

   IF @sErrorText <> ''
   BEGIN
      SET @sMsg = 'Configuration data missing:  ' + @sErrorText 
      PRINT @sMsg
      INSERT INTO tblErrorLog (Process, ErrorMsg) values ('spProcessCases', @sMsg)
      RETURN 1
   END

   /***************************************************************************
    Retrieve the email address lists from the configuration table.
   ***************************************************************************/

   SET @sErrorText = ''

   IF @bSendMail = 1
   BEGIN

      EXEC spGetReportEMailAddresses 'Pending Cases: Sent to mainframe', @Recipients OUTPUT, @Copy OUTPUT, @BlindCopy OUTPUT, @ErrorRecipients OUTPUT, @AdminRecipients OUTPUT, @sMsg OUTPUT
      
      IF dbo.fIsBlank(@Recipients) = 1
         SET @sErrorText = 'Missing Recipients Information'

   END

   IF @sErrorText <> ''
   BEGIN
      SET @s = 'Configuration data is missing:  ' + @sErrorText 
      PRINT @s
      INSERT INTO tblErrorLog (Process, ErrorMsg) values ('spProcessCases', @s)
      SET @sErrorText = ''
   END

   SET @n = 0
   SET @CR = CHAR(13)
   select @StartTime = GETDATE()


   IF SUBSTRING( @sDataDir, LEN(@sDataDir), 1) <> '\'
      SET @sDataDir = @sDataDir + '\'

   SET @sMFDataDir  = @sDataDir + 'MFData\' + REPLACE(CONVERT(VARCHAR(7), @StartTime, 102), '.', '\')


   SET @sCommand = 'dir ' + @sMFDataDir
   EXEC @n = master.dbo.xp_cmdshell @sCommand
   IF @n <> 0
   BEGIN
      SET @sCommand = 'mkdir ' + @sMFDataDir
      EXEC master.dbo.xp_cmdshell @sCommand
   END

   -- Build file name:  prefix + date (MMDD)
   IF @bTestMF = 1
      SET @FPrefix = @sMFDataDir + '\mfT' + SUBSTRING(CONVERT(CHAR(6), GETDATE(), 12), 3, 4) 
   ELSE
      SET @FPrefix = @sMFDataDir + '\mfp' + SUBSTRING(CONVERT(CHAR(6), GETDATE(), 12), 3, 4) 

   IF @bDebug = 1
      SET @FPrefix = @FPrefix + '_dbg'


   /***************************************************************************
      Generate the CSA/CSF raw data file.
   ***************************************************************************/
   PRINT 'spGenerateMFData '''', ' + @FPrefix + ', ' + STR(@bTestMF,1) + ', '
         + STR(@bStatusUpdate,1)
   EXEC @n = spGenerateMFData '', @FPrefix, @bTestMF, @bStatusUpdate, @bSendMail
   PRINT ' ==> ' + LTRIM(STR(@n))

   /***************************************************************************
      Parse the file.

      ParseMFData Usage:  
         ParseMFData {data dir} {filename} {file type} [debug]
   ***************************************************************************/
   SET @FName = @FPrefix
   SET @sDataFile = @FName + '.psv'
   EXEC @bExists = spFileExists @sDataFile

   IF @bExists <> 1
   BEGIN
      IF @bExists < 1
         SET @sErrorText = 'spFileExists ''' + @sDataFile + ''' returned ' 
                           + LTRIM(STR(@bExists)) + '.'
      ELSE
         SET @sErrorText = 'Data file ''' + @sDataFile + ''' was not created.'

      GOTO ERROR_HANDLER
   END

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
            SET @sErrorText = 'spFileExists ''' + @sDataFile + ''' returned ' 
                              + LTRIM(STR(@bExists)) + '.'
         ELSE
            SET @sErrorText = 'The FTP process failed (file ''' + @sDataFile + ''' was not created.'
   
         GOTO ERROR_HANDLER
      END
      ELSE
      BEGIN
        
         DECLARE @sTrmDataFile    VARCHAR(100)
         DECLARE @sSntDataFile    VARCHAR(100)
         DECLARE @rc              INT

         -- Now compare the file sizes.
         SET @sSntDataFile = @FName + '.snt'
         SET @sTrmDataFile = @FName + '.dat'
         EXEC @rc = spCompareFileSize @FileName1 = @sTrmDataFile, @FileName2 = @sSntDataFile, @AllowedDiff = 0, @bMissingFile1 = 1, @bDebug = @bDebug
         IF @rc <> 0 
         BEGIN
            SET @sErrorText = 'The FTP process failed -- send/receive sizes do not match.'
            GOTO ERROR_HANDLER
         END

         -- If we get this far, FTP worked.  We can delete the .snt and .trm files.
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

   /***************************************************************************
      Send emails.
   ***************************************************************************/
   SET @Recipients = dbo.fExtractValidOpmEmails(@Recipients,';')
   SET @Copy = dbo.fExtractValidOpmEmails(@Copy,';')
   SET @BlindCopy = dbo.fExtractValidOpmEmails(@BlindCopy,';')
   SET @ErrorRecipients = dbo.fExtractValidOpmEmails(@ErrorRecipients,';')
   SET @AdminRecipients = dbo.fExtractValidOpmEmails(@AdminRecipients,';')  
   SET @sDebugEmail = dbo.fExtractValidOpmEmails(@sDebugEmail,';')
   
   IF @n > 0 AND @bSendMail = 1
   BEGIN
      IF @bTestMF=0  -- production:
      BEGIN
         SET @sMsg  = CONVERT(VARCHAR(20), GETDATE() , 0) + @CR + @CR +
                      LTRIM(STR(@n)) + ' records were sent to production.'
         SET @sQuery = 'select * from tblErrorLog where Date >= ''' + 
                       CONVERT(VARCHAR(20), @StartTime, 100) + ''''
         --SET @sDbName = db_name()
		  

         IF @bDebug=0
         BEGIN
            EXEC spQueueMail @Recipients
                  ,@CC = @Copy                 
                  ,@BCC = @BlindCopy                  
                  ,@message = @sMsg
                  ,@subject = 'Calculator File - Production'
                  ,@attachments = @sAttachments
                  ,@Msg = @Msg OUTPUT

            IF EXISTS (select * from tblErrorLog where Date >= @StartTime)
            BEGIN
               SET @sMsg  = CONVERT(VARCHAR(20), GETDATE() , 0) + @CR
               EXEC spQueueMail @ErrorRecipients
                     ,@message = @sMsg
                     ,@CC = @AdminRecipients                    
                     ,@subject = 'Calculator File Processing:  Error Log'
                     ,@dbuse = @sDbName
                     ,@query = @sQuery
                     ,@width = 256
                     ,@Msg = @Msg OUTPUT
            END
         END
         ELSE
         BEGIN
            SET @sMsg = @sMsg + @CR + @CR + 'Error Log:' + @CR
            EXEC spQueueMail @sDebugEmail
                  ,@message = @sMsg
                  ,@subject = 'Calculator File - Production (debug)'
                  ,@attachments = @sAttachments
                  ,@dbuse = @sDbName
                  ,@query = @sQuery
                  ,@width = 256
                  ,@Msg = @Msg OUTPUT
         END
      END --IF Production      
      ELSE  -- @bTestMF = 1  (test)
      BEGIN
         SET @sMsg  = CONVERT(VARCHAR(20), GETDATE() , 0) + @CR + @CR +
                      'There are ' + LTRIM(STR(@n)) + ' records in the attached file.'
   
         IF @bDebug=0
         BEGIN            
            EXEC spQueueMail @AdminRecipients
                  ,@message = @sMsg
                  ,@subject = 'Calculator File - Test'
                  ,@attachments = @sAttachments
                  ,@Msg = @Msg OUTPUT

            IF EXISTS (select * from tblErrorLog where Date >= @StartTime)
               SET @sMsg  = CONVERT(VARCHAR(20), GETDATE() , 0) + @CR
               EXEC spQueueMail @AdminRecipients
                     ,@message = @sMsg
                     ,@subject = 'Calculator File Processing:  Error Log'
                     ,@dbuse = @sDbName
                     ,@query = @sQuery
                     ,@width = 256
                     ,@Msg = @Msg OUTPUT
         END
         ELSE
         BEGIN
            SET @sMsg = @sMsg + @CR + @CR + 'Error Log:' + @CR
            EXEC spQueueMail @sDebugEmail
                  ,@message = @sMsg
                  ,@subject = 'Calculator File - Test (debug)'
                  ,@attachments = @sAttachments
                  ,@dbuse = @sDbName
                  ,@query = @sQuery
                  ,@width = 256
                  ,@Msg = @Msg OUTPUT
         END
      END
   END

   GOTO ENDPROC

   USAGE:
      PRINT 'Usage:  spProcessCases @bTestMF'
      PRINT '                      ,@bStatusUpdate (1)'
      PRINT '                      ,@bSendMail (1)'
      PRINT '                      ,@bSendFile (1)'
      PRINT '                      ,@bDebug (0)'
      PRINT '                      ,@sDebugEmail(null)'
   
      GOTO ENDPROC

   ERROR_HANDLER:
      INSERT INTO tblErrorLog (CaseId, Process, ErrorMsg) values (null, 'spProcessCases', @sErrorText )
      PRINT 'spProcessCases --> ' + @sErrorText 

      IF @bSendMail=1
         EXEC spQueueMail @AdminRecipients
               ,@message = @sErrorText
               ,@subject = 'spProcessCases:  ERROR'
               ,@Msg = @Msg OUTPUT
      RETURN 1
      
   ENDPROC:   
   SET NOCOUNT OFF
   RETURN 0
END
GO


