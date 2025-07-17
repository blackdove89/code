-- ================================================================
-- FIX spProcessReissueCases TO LOG XP_CMDSHELL ERRORS
-- ================================================================

-- PROBLEM: spProcessReissueCases shows "cannot find the path specified" 
-- but doesn't log this error to tblErrorLog because xp_cmdshell errors
-- are not automatically caught by SQL Server error handling

-- SOLUTION: Add error checking after xp_cmdshell calls

-- ================================================================
-- FIXED spProcessReissueCases WITH PROPER ERROR LOGGING
-- ================================================================

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
   DECLARE @s                          VARCHAR(100)
   DECLARE @sAttachments               VARCHAR(150)
   DECLARE @sCommand                   VARCHAR(128)
   DECLARE @sDataDir                   VARCHAR(30)
   DECLARE @sDataFile                  VARCHAR(100)
   DECLARE @sDbName                    VARCHAR(30)
   DECLARE @sMFDataDir                 VARCHAR(100)
   DECLARE @sMFDatasetName             VARCHAR(100)
   DECLARE @sMsg                       VARCHAR(1000)
   DECLARE @sQuery                     VARCHAR(200)
   DECLARE @n                          INT
   DECLARE @sErrorText                 VARCHAR(1000)
   DECLARE @StartTime                  DATETIME

   DECLARE @Recipients                 VARCHAR(1000)
   DECLARE @Copy                       VARCHAR(1000)
   DECLARE @BlindCopy                  VARCHAR(1000)
   DECLARE @ErrorRecipients            VARCHAR(1000)
   DECLARE @AdminRecipients            VARCHAR(1000)

   DECLARE @Msg                        VARCHAR(2000)

   -- NEW: Add variables for command shell error handling
   DECLARE @cmdResult                  INT
   DECLARE @cmdOutput                  TABLE (output VARCHAR(255))

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
      INSERT INTO tblErrorLog (CaseId, Process, ErrorMsg) VALUES (NULL, 'spProcessReissueCases', @s)
      SET @sErrorText = ''
   END

   SET @n = 0
   SET @CR = CHAR(13)
   select @StartTime = GETDATE()

   IF SUBSTRING(@sDataDir, LEN(@sDataDir), 1) <> '\'
      SET @sDataDir = @sDataDir + '\'

   SET @sMFDataDir = @sDataDir + 'MFData\Reissue\' + REPLACE(CONVERT(VARCHAR(7), @StartTime, 102), '.', '\')

   -- FIXED: Add error checking for directory operations
   SET @sCommand = 'dir ' + @sMFDataDir
   EXEC @cmdResult = master.dbo.xp_cmdshell @sCommand
   
   IF @cmdResult <> 0
   BEGIN
      -- Directory doesn't exist, try to create it
      SET @sCommand = 'mkdir "' + @sMFDataDir + '"'
      EXEC @cmdResult = master.dbo.xp_cmdshell @sCommand
      
      -- FIXED: Check if directory creation failed and log the error
      IF @cmdResult <> 0
      BEGIN
         SET @sErrorText = 'Failed to create directory: ' + @sMFDataDir + 
                          '. Command: ' + @sCommand + 
                          '. This may be due to invalid path, insufficient permissions, or network issues.'
         
         IF @bDebug = 1
            PRINT 'ERROR: ' + @sErrorText
            
         INSERT INTO tblErrorLog (CaseId, Process, ErrorMsg) VALUES (NULL, 'spProcessReissueCases', @sErrorText)
         GOTO ERROR_HANDLER
      END
      ELSE
      BEGIN
         IF @bDebug = 1
            PRINT 'Successfully created directory: ' + @sMFDataDir
      END
   END
   ELSE
   BEGIN
      IF @bDebug = 1
         PRINT 'Directory already exists: ' + @sMFDataDir
   END

   -- Build file name
   SET @FPrefix = @sMFDataDir + '\mfp_R' + SUBSTRING(CONVERT(CHAR(6), GETDATE(), 12), 3, 4) 

   IF @bDebug = 1
      SET @FPrefix = @FPrefix + '_dbg'

   -- Generate reissue data
   PRINT 'spGenerateReissueData ' + @FPrefix + ', ' + STR(@bStatusUpdate,1)
   EXEC @n = spGenerateReissueData @FPrefix, @bStatusUpdate, @bSendMail
   SET @n = @n / 2
 
   PRINT ' ==> ' + LTRIM(STR(@n))

   IF @n = 0 
   BEGIN
      GOTO ENDPROC
   END
   
   -- File existence check
   SET @FName = @FPrefix
   SET @sDataFile = @FName + '.psv'
   EXEC @bExists = spFileExists @sDataFile

   IF @bExists <> 1
   BEGIN
      IF @bExists < 1
         SET @sErrorText = 'spFileExists returned error code ' + LTRIM(STR(@bExists)) + 
                          ' for file: ' + @sDataFile + 
                          '. This indicates a file system or path access problem.'
      ELSE
         SET @sErrorText = 'Required data file was not created: ' + @sDataFile + 
                          '. Check spGenerateReissueData execution and file system permissions.'

      INSERT INTO tblErrorLog (CaseId, Process, ErrorMsg) VALUES (NULL, 'spProcessReissueCases', @sErrorText)
      GOTO ERROR_HANDLER
   END

   -- FIXED: Add error checking for ParseMFData command
   SET @sCommand = @sDataDir + '\ParseMFData "' + @sDataDir + '" "' + @FName + '" 1'

   IF @bDebug=1
      SET @sCommand = @sCommand + ' 1'

   IF @bDebug = 1
      PRINT 'Executing: ' + @sCommand

   -- Execute ParseMFData and check for errors
   EXEC @cmdResult = master.dbo.xp_cmdshell @sCommand

   -- FIXED: Check if ParseMFData command failed and log the error
   IF @cmdResult <> 0
   BEGIN
      SET @sErrorText = 'ParseMFData command failed with exit code ' + LTRIM(STR(@cmdResult)) + 
                       '. Command: ' + @sCommand + 
                       '. Check if ParseMFData.exe exists in ' + @sDataDir + 
                       ' and has proper permissions. Verify data directory path is accessible.'
      
      IF @bDebug = 1
         PRINT 'ERROR: ' + @sErrorText
         
      INSERT INTO tblErrorLog (CaseId, Process, ErrorMsg) VALUES (NULL, 'spProcessReissueCases', @sErrorText)
      GOTO ERROR_HANDLER
   END

   -- File sending operations
   IF (@bSendFile = 1) AND (@n > 0)
   BEGIN
      SET @sCommand = @sDataDir + '\sendfile "' + @FName + '" "' + @sMFDatasetName + '"'

      PRINT @sCommand
      
      -- FIXED: Add error checking for sendfile command
      EXEC @cmdResult = master.dbo.xp_cmdshell @sCommand

      -- Check if sendfile command failed
      IF @cmdResult <> 0
      BEGIN
         SET @sErrorText = 'Sendfile command failed with exit code ' + LTRIM(STR(@cmdResult)) + 
                          '. Command: ' + @sCommand + 
                          '. Check if sendfile.exe exists, FTP configuration is correct, ' +
                          'and target dataset "' + @sMFDatasetName + '" is accessible.'
         
         IF @bDebug = 1
            PRINT 'ERROR: ' + @sErrorText
            
         INSERT INTO tblErrorLog (CaseId, Process, ErrorMsg) VALUES (NULL, 'spProcessReissueCases', @sErrorText)
         GOTO ERROR_HANDLER
      END

      -- Check for .snt file creation
      SET @sDataFile = @FName + '.snt'
      EXEC @bExists = spFileExists @sDataFile
   
      IF @bExists <> 1
      BEGIN
         IF @bExists < 1
            SET @sErrorText = 'spFileExists returned error ' + LTRIM(STR(@bExists)) + 
                             ' when checking for FTP confirmation file: ' + @sDataFile
         ELSE
            SET @sErrorText = 'FTP confirmation file was not created: ' + @sDataFile + 
                             '. The FTP operation may have failed silently. ' +
                             'Check FTP logs and mainframe dataset accessibility.'
   
         INSERT INTO tblErrorLog (CaseId, Process, ErrorMsg) VALUES (NULL, 'spProcessReissueCases', @sErrorText)
         GOTO ERROR_HANDLER
      END
      ELSE
      BEGIN
         -- File size comparison
         DECLARE @sTrmDataFile VARCHAR(100)
         DECLARE @sSntDataFile VARCHAR(100)
         DECLARE @rc INT

         SET @sSntDataFile = @FName + '.snt'
         SET @sTrmDataFile = @FName + '.dat'
         EXEC @rc = spCompareFileSize @FileName1 = @sTrmDataFile, @FileName2 = @sSntDataFile, @AllowedDiff = 0, @bMissingFile1 = 1, @bDebug = @bDebug
         
         IF @rc <> 0 
         BEGIN
            SET @sErrorText = 'File size comparison failed between transmitted file "' + @sTrmDataFile + 
                             '" and received confirmation "' + @sSntDataFile + 
                             '". Return code: ' + LTRIM(STR(@rc)) + 
                             '. This indicates data transmission corruption or incomplete transfer.'
            
            INSERT INTO tblErrorLog (CaseId, Process, ErrorMsg) VALUES (NULL, 'spProcessReissueCases', @sErrorText)
            GOTO ERROR_HANDLER
         END

         -- Clean up temporary files
         SET @sCommand = 'del "' + @FName + '.snt"'
         EXEC @cmdResult = master.dbo.xp_cmdshell @sCommand
         
         -- Note: We don't fail on cleanup errors, but we could log them if needed
         IF @cmdResult <> 0 AND @bDebug = 1
            PRINT 'Warning: Failed to delete temporary file ' + @FName + '.snt'
      END
   
      IF dbo.fIsBlank(@sAttachments) = 1
         SET @sAttachments = @FName + '.txt'
      ELSE
         SET @sAttachments = @sAttachments + ';' + @FName + '.txt'
   END

   -- Email sending logic continues...
   IF @n > 0 AND @bSendMail = 1
   BEGIN
      SET @sMsg = CONVERT(VARCHAR(20), GETDATE() , 0) + @CR + @CR +
                  LTRIM(STR(@n)) + ' records were sent to production.'
      SET @sQuery = 'select * from tblErrorLog where Date >= ''' + 
                    CONVERT(VARCHAR(20), @StartTime, 100) + ''''
      SET @sDbName = db_name()

      IF @bDebug=0
      BEGIN
         EXEC spQueueMail @Recipients
               ,@CC = @Copy                 
               ,@BCC = @BlindCopy 
               ,@message = @sMsg
               ,@subject = 'Calculator Reissue File - Production'
               ,@attachments = @sAttachments
               ,@Msg = @Msg OUTPUT

         IF EXISTS (select * from tblErrorLog where Date >= @StartTime)
         BEGIN
            SET @sMsg = CONVERT(VARCHAR(20), GETDATE() , 0) + @CR
            EXEC spQueueMail @ErrorRecipients
                  ,@message = @sMsg
                  ,@CC = @AdminRecipients  
                  ,@subject = 'Calculator Reissue File Processing:  Error Log'
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
               ,@subject = 'Calculator Reissue File - Production (debug)'
               ,@attachments = @sAttachments
               ,@dbuse = @sDbName
               ,@query = @sQuery
               ,@width = 256
               ,@Msg = @Msg OUTPUT
      END
   END

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

-- ================================================================
-- TEST THE FIXED VERSION
-- ================================================================

-- Test 1: Force directory creation failure
UPDATE tblConfiguration 
SET KeyValue = 'Z:\InvalidDrive\NonExistentPath\'
WHERE KeyName = 'MFDataDirectory'

EXEC spProcessReissueCases @bSendMail = 0, @bSendFile = 0, @bDebug = 1

-- Check if error was logged
SELECT 
    'Directory Creation Error Test' AS TestType,
    Date,
    CaseId,
    Process,
    ErrorMsg
FROM tblErrorLog 
WHERE Process = 'spProcessReissueCases'
    AND Date >= DATEADD(minute, -5, GETDATE())
ORDER BY Date DESC

-- ================================================================

-- Test 2: Force ParseMFData command failure
UPDATE tblConfiguration 
SET KeyValue = 'C:\temp\'
WHERE KeyName = 'MFDataDirectory'

-- Temporarily rename ParseMFData to cause command failure
EXEC master.dbo.xp_cmdshell 'rename C:\temp\ParseMFData.exe ParseMFData.exe.bak'

EXEC spProcessReissueCases @bSendMail = 0, @bSendFile = 0, @bDebug = 1

-- Check if error was logged
SELECT 
    'ParseMFData Command Error Test' AS TestType,
    Date,
    CaseId,
    Process,
    ErrorMsg
FROM tblErrorLog 
WHERE Process = 'spProcessReissueCases'
    AND Date >= DATEADD(minute, -2, GETDATE())
ORDER BY Date DESC

-- Restore ParseMFData
EXEC master.dbo.xp_cmdshell 'rename C:\temp\ParseMFData.exe.bak ParseMFData.exe'

-- ================================================================

-- Restore proper configuration
UPDATE tblConfiguration 
SET KeyValue = 'E:\FACESData\'
WHERE KeyName = 'MFDataDirectory'

-- ================================================================
-- SUMMARY OF CHANGES
-- ================================================================

/*
KEY IMPROVEMENTS MADE:

1. ADDED ERROR CHECKING FOR XP_CMDSHELL COMMANDS:
   - Check return codes from directory creation (mkdir)
   - Check return codes from ParseMFData execution
   - Check return codes from sendfile operations

2. COMPREHENSIVE ERROR LOGGING:
   - Log specific command failures with full context
   - Include command line that failed
   - Provide detailed error descriptions and troubleshooting hints

3. ENHANCED ERROR MESSAGES:
   - Include full file paths and command details
   - Suggest possible causes (permissions, missing files, network issues)
   - Provide specific error codes and context

4. BETTER DEBUG OUTPUT:
   - Show commands being executed
   - Report success/failure of each operation
   - Include detailed error information

NOW THE PROCEDURE WILL LOG:
- "Failed to create directory: Z:\InvalidDrive\NonExistentPath\MFData\Reissue\2025\07"
- "ParseMFData command failed with exit code 1. Command: E:\FACESData\ParseMFData..."
- "Sendfile command failed with exit code 2. Check if sendfile.exe exists..."

INSTEAD OF JUST SHOWING CONSOLE OUTPUT WITHOUT LOGGING
*/