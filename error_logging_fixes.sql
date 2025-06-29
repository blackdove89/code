-- =================================================================
-- ERROR LOGGING FIXES FOR STORED PROCEDURES
-- =================================================================

-- 1. INCREASE VARIABLE SIZES TO PREVENT TRUNCATION
-- =================================================================

-- In spProcessCases - Change line ~25:
DECLARE @sErrorText VARCHAR(500)  -- Increased from VARCHAR(100)

-- In spProcessReissueCases - Change line ~40:
DECLARE @sErrorText VARCHAR(500)  -- Increased from VARCHAR(100)

-- In spCalcGrossToNet_main - Change line ~120:
DECLARE @str VARCHAR(1000)  -- Increased from VARCHAR(250)

-- 2. FIX MISSING CASEID IN ERROR LOGGING
-- =================================================================

-- spProcessCases - Replace error logging calls:
-- OLD:
-- INSERT INTO tblErrorLog (CaseId, Process, ErrorMsg) values (null, 'spProcessCases', @sErrorText)

-- NEW: Add CaseId parameter and track it
ALTER PROCEDURE [dbo].[spProcessCases]
    @bTestMF                BIT = NULL
   ,@bStatusUpdate          BIT = 1
   ,@bSendMail              BIT = 1
   ,@bSendFile              BIT = 1
   ,@bDebug                 BIT = 0
   ,@sDebugEmail            VARCHAR(150) = NULL
   ,@CaseId                 INT = NULL  -- ADD THIS PARAMETER
AS 
BEGIN
   -- ... existing code ...
   
   -- Replace error logging with:
   INSERT INTO tblErrorLog (CaseId, Process, ErrorMsg) 
   VALUES (@CaseId, 'spProcessCases', @sErrorText)
END

-- spProcessReissueCases - Same fix:
ALTER PROCEDURE [dbo].[spProcessReissueCases]
    @bStatusUpdate          BIT = 1
   ,@bSendMail              BIT = 1
   ,@bSendFile              BIT = 1
   ,@bDebug                 BIT = 0
   ,@sDebugEmail            VARCHAR(150) = NULL
   ,@CaseId                 INT = NULL  -- ADD THIS PARAMETER
AS 
BEGIN
   -- ... existing code ...
   
   -- Replace error logging with:
   INSERT INTO tblErrorLog (CaseId, Process, ErrorMsg) 
   VALUES (@CaseId, 'spProcessReissueCases', @sErrorText)
END

-- spCalcGrossToNet_main - Fix existing error logging:
-- FIND these lines (around lines 450, 480):
INSERT INTO tblErrorLog (Process, ErrorMsg) VALUES ('spCalcGrossToNet_main', @str)

-- REPLACE with:
INSERT INTO tblErrorLog (CaseId, Process, ErrorMsg) VALUES (@CaseId, 'spCalcGrossToNet_main', @str)

-- 3. ADD ERROR MESSAGE LENGTH CHECKING
-- =================================================================

-- Before each INSERT INTO tblErrorLog, add length checking:

-- For spProcessCases and spProcessReissueCases:
IF LEN(@sErrorText) > 500
   SET @sErrorText = LEFT(@sErrorText, 497) + '...'

INSERT INTO tblErrorLog (CaseId, Process, ErrorMsg) 
VALUES (@CaseId, 'spProcessCases', @sErrorText)

-- For spCalcGrossToNet_main:
IF LEN(@str) > 1000
   SET @str = LEFT(@str, 997) + '...'

INSERT INTO tblErrorLog (CaseId, Process, ErrorMsg) 
VALUES (@CaseId, 'spCalcGrossToNet_main', @str)

-- 4. SPECIFIC FIXES FOR spCalcGrossToNet_main
-- =================================================================

-- Around line 450 - Fix spAddGrossToNetHB error logging:
IF @rc < 0
BEGIN
   SET @str = 'spAddGrossToNetHB returned ' + LTRIM(STR(@rc))
   IF LEN(@str) > 1000
      SET @str = LEFT(@str, 997) + '...'
   INSERT INTO tblErrorLog (CaseId, Process, ErrorMsg) VALUES (@CaseId, 'spCalcGrossToNet_main', @str)
   DEALLOCATE @cs
   RETURN @rc
END

-- Around line 480 - Fix spAddGrossToNetCSRS error logging:
IF @rc < 0
BEGIN
   SET @str = 'spAddGrossToNetCSRS returned ' + LTRIM(STR(@rc))
   IF LEN(@str) > 1000
      SET @str = LEFT(@str, 997) + '...'
   INSERT INTO tblErrorLog (CaseId, Process, ErrorMsg) VALUES (@CaseId, 'spCalcGrossToNet_main', @str)
   RETURN @rc
END

-- Around line 510 - Fix spAddGrossToNetFERS error logging:
IF @rc < 0
BEGIN
   SET @str = 'spAddGrossToNetFERS Returned ' + ISNULL(LTRIM(STR(@rc)), '')
   IF LEN(@str) > 1000
      SET @str = LEFT(@str, 997) + '...'
   INSERT INTO tblErrorLog (CaseId, Process, ErrorMsg) VALUES (@CaseId, 'spCalcGrossToNet_main', @str)
   RETURN @rc
END

-- Around line 750 - Fix spAddGrossToNetLI error logging:
IF @rc < 0 
BEGIN
   SET @str = 'spAddGrossToNetLI returned ' + LTRIM(STR(@rc))
   IF LEN(@str) > 1000
      SET @str = LEFT(@str, 997) + '...'
   INSERT INTO tblErrorLog (CaseId, Process, ErrorMsg) VALUES (@CaseId, 'spCalcGrossToNet_main', @str)
   DEALLOCATE @cs
   RETURN @rc
END

-- 5. ALTERNATIVE: CREATE HELPER PROCEDURE FOR CONSISTENT ERROR LOGGING
-- =================================================================

CREATE PROCEDURE spLogError
    @CaseId INT = NULL,
    @Process VARCHAR(100),
    @ErrorMsg VARCHAR(MAX)
AS
BEGIN
    -- Truncate message if too long for the column
    DECLARE @TruncatedMsg VARCHAR(1000)
    
    IF LEN(@ErrorMsg) > 1000
        SET @TruncatedMsg = LEFT(@ErrorMsg, 997) + '...'
    ELSE
        SET @TruncatedMsg = @ErrorMsg
    
    INSERT INTO tblErrorLog (CaseId, Process, ErrorMsg, Date) 
    VALUES (@CaseId, @Process, @TruncatedMsg, GETDATE())
END

-- Then replace all error logging calls with:
EXEC spLogError @CaseId, 'spCalcGrossToNet_main', @str
EXEC spLogError @CaseId, 'spProcessCases', @sErrorText
EXEC spLogError @CaseId, 'spProcessReissueCases', @sErrorText