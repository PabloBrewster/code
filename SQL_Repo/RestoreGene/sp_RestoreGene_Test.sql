USE master;
GO

IF OBJECT_ID('TestLog','U') IS NOT NULL
	DROP TABLE TestLog

CREATE TABLE [dbo].[TestLog](
	ID INT IDENTITY(1,1),
	[Backup_Date] [datetime] NULL,
	[Backup Type] [varchar](50) NULL,
	[FileSequence] [int] NULL,
	[FileName1] [varchar](250) NULL,
	[FileName2] [varchar](250) NULL,
	[TestCase] [varchar](250) NULL
) ON [PRIMARY]
GO

EXEC msdb.dbo.sp_delete_backuphistory  @oldest_date =  '2199-12-31'

-------------------------------------------------
-- V8.16 History generator
-------------------------------------------------
-- Create Primary Database
:SETVAR DatabaseName "RestoreGene_Test"

:SETVAR DataDrive "C:\MSSQL\Data"
:SETVAR DataDrive1 "C:\MSSQL\Data\LUN1\"
:SETVAR DataDrive2 "C:\MSSQL\Data\LUN2\"
:SETVAR DataDrive3 "C:\MSSQL\Data\LUN3\"
:SETVAR DataDrive4 "C:\MSSQL\Data\LUN4\"
:SETVAR DataDrive5 "C:\MSSQL\Data\LUN5\"
:SETVAR DataDrive6 "C:\MSSQL\Data\LUN6\"

:SETVAR LogDrive "C:\MSSQL\Logs\"
:SETVAR BackupFull "C:\MSSQL\"
:SETVAR BackupDiff "C:\MSSQL\"
:SETVAR BackupLog "C:\MSSQL\"


IF DATABASEPROPERTYEX(N'$(databasename)','Status') IS NOT NULL
BEGIN
	BEGIN TRY
		ALTER DATABASE $(DatabaseName) SET SINGLE_USER WITH ROLLBACK IMMEDIATE
	END TRY
	BEGIN CATCH
		PRINT 'No problem'
	END CATCH
	DROP DATABASE $(DatabaseName)
END;

CREATE DATABASE $(DatabaseName)
ON
(	
	NAME = $(DatabaseName)_data,
	FILENAME = N'$(DataDrive)\$(DatabaseName)_data.mdf',
	SIZE = 10,
	MAXSIZE = 5000MB,
	FILEGROWTH = 5 
)

LOG ON
( 
	NAME = $(DatabaseName)_log,
	FILENAME = N'$(LogDrive)\$(DatabaseName).ldf',
	SIZE = 5MB,
	MAXSIZE = 5000MB,
	FILEGROWTH = 5MB
); 

GO

ALTER DATABASE $(DatabaseName)
ADD LOG FILE
(
	NAME = $(DatabaseName)_log2,
	FILENAME = N'$(LogDrive)\$(DatabaseName)_2.ldf',
	SIZE = 5MB,
	MAXSIZE = 5000MB,
	FILEGROWTH = 5MB

)

ALTER DATABASE $(DatabaseName) SET RECOVERY FULL;

-----------------------------------------------------------------------------------  
-- Add file groups and files, add complexity to tests 
-----------------------------------------------------------------------------------  
DECLARE @nSQL NVARCHAR(2000) ;  
DECLARE @x INT = 1;   
 
WHILE @x <= 6
BEGIN   
 
	SELECT @nSQL =  
	'ALTER DATABASE $(DatabaseName)  
	ADD FILEGROUP $(DatabaseName)_fg' + RTRIM(CAST(@x AS CHAR(5))) + ';   
 
	ALTER DATABASE $(DatabaseName)  
	ADD FILE  
	(  
	NAME= ''$(DatabaseName)' + CAST(@x AS CHAR(5)) + ''',  
	FILENAME = ''$(DataDrive)' + '\LUN' + CAST(@x AS CHAR(1)) + '\$(DatabaseName)_f' + RTRIM(CAST(@x AS CHAR(5))) + '.ndf''  
	)  
	TO FILEGROUP $(DatabaseName)_fg' + RTRIM(CAST(@x AS CHAR(5))) + ';'   
 
	EXEC sp_executeSQL @nSQL;   

	SET @x = @x + 1;  
END   
GO

-------------------------------------------------
CREATE TABLE $(DatabaseName).[dbo].[TestTable](
[GUID_PK] [uniqueidentifier] NOT NULL,
[CreateDate] [datetime] NULL,
[CreateServer] [nvarchar](50) NULL,
[RandomNbr] [int] NULL,
[TestCase] VARCHAR(500)
CONSTRAINT [PK_TestTable] PRIMARY KEY CLUSTERED
(
[GUID_PK] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY];

ALTER TABLE $(DatabaseName).[dbo].[TestTable] ADD CONSTRAINT [DF_TestTable_GUID_PK] DEFAULT (newsequentialid()) FOR [GUID_PK];
ALTER TABLE $(DatabaseName).[dbo].[TestTable] ADD CONSTRAINT [DF_TestTable_CreateDate] DEFAULT (getdate()) FOR [CreateDate];
ALTER TABLE $(DatabaseName).[dbo].[TestTable] ADD CONSTRAINT [DF_TestTable_CreateServer] DEFAULT (@@servername) FOR [CreateServer];
GO
--==================================================================================================

-------------------------------------------------
-- Create backup history
:SETVAR DatabaseName "RestoreGene_Test"
:SETVAR DataDrive "C:\MSSQL\Data"
:SETVAR LogDrive "C:\MSSQL\Logs\"
:SETVAR BackupFull "C:\MSSQL\"
:SETVAR BackupDiff "C:\MSSQL\"
:SETVAR BackupLog "C:\MSSQL\"


DECLARE @nSQL NVARCHAR(200);
DECLARE @x INT = 0;

BACKUP DATABASE $(DatabaseName)
TO DISK = '$(BackupFull)\$(DatabaseName)_Full_A1.bak'
WITH CHECKSUM;

INSERT INTO [dbo].[TestLog] ([Backup_Date], [Backup Type], [FileSequence], [FileName1])
VALUES (GETDATE(), 'FULL', 0, 'Full_A1.bak')

SET @x += 1

WAITFOR DELAY '00:00:003';
INSERT INTO $(DatabaseName).[dbo].[TestTable]  ([RandomNbr],[TestCase]) VALUES	(@x,'');


-----------------------------------------
-- Logs
DECLARE @FileName VARCHAR(50)  -- Need to set this

WHILE @x < 11
BEGIN

INSERT INTO $(DatabaseName).[dbo].[TestTable]  ([RandomNbr],[TestCase]) VALUES	(@x,'');

SET @FileName = CAST((DATEPART(year,GETDATE()) * 1000) + (DATEPART(month,GETDATE()) * 100) + DATEPART(day,GETDATE()) AS VARCHAR(8)) + CAST((DATEPART(hour,GETDATE()) * 1000) + (DATEPART(minute,GETDATE()) * 100) + DATEPART(second,GETDATE()) AS VARCHAR(8))

SET @nSQL = 
'BACKUP LOG $(DatabaseName) 
TO DISK = ' 
+ '''' + '$(BackupLog)\$(DatabaseName)_Log_A1' 
+ @FileName
+ '.trn' + '''' 
+ ' WITH CHECKSUM;'

--SELECT @nSQL
EXEC sp_executesql @nSQL

WAITFOR DELAY '00:00:004'

INSERT INTO [dbo].[TestLog] ([Backup_Date], [Backup Type], [FileSequence], [FileName1])
VALUES (GETDATE(), 'LOG', 0, @FileName);

SET @x += 1
END


-----------------------------------------
-- DIFF
SET @nSQL = 
'BACKUP  DATABASE $(DatabaseName) 
TO DISK = ' + '''' + '$(BackupLog)\$(DatabaseName)_DIFF_' 
+ CAST((DATEPART(year,GETDATE()) * 1000) + (DATEPART(month,GETDATE()) * 100) + DATEPART(day,GETDATE()) AS VARCHAR(8)) + CAST((DATEPART(hour,GETDATE()) * 1000) + (DATEPART(minute,GETDATE()) * 100) + DATEPART(second,GETDATE()) AS VARCHAR(8))
+ '.bak' + '''' 
+ ' WITH CHECKSUM, DIFFERENTIAL;'

--SELECT @nSQL
EXEC sp_executesql @nSQL

INSERT INTO [dbo].[TestLog] ([Backup_Date], [Backup Type], [FileSequence], [FileName1])
VALUES (GETDATE(), 'DIFF', 0, CAST((DATEPART(year,GETDATE()) * 1000) + (DATEPART(month,GETDATE()) * 100) + DATEPART(day,GETDATE()) AS VARCHAR(8)) + CAST((DATEPART(hour,GETDATE()) * 1000) + (DATEPART(minute,GETDATE()) * 100) + DATEPART(second,GETDATE()) AS VARCHAR(8)))


-----------------------------------------
-- Logs again
SET @x = 0
WHILE @x < 11
BEGIN

INSERT INTO $(DatabaseName).[dbo].[TestTable]  ([RandomNbr],[TestCase]) VALUES	(@x,'');

SET @FileName = CAST((DATEPART(year,GETDATE()) * 1000) + (DATEPART(month,GETDATE()) * 100) + DATEPART(day,GETDATE()) AS VARCHAR(8)) + CAST((DATEPART(hour,GETDATE()) * 1000) + (DATEPART(minute,GETDATE()) * 100) + DATEPART(second,GETDATE()) AS VARCHAR(8))

SET @nSQL = 
'BACKUP LOG $(DatabaseName) 
TO DISK = ' + '''' + '$(BackupLog)\$(DatabaseName)_Log_B1' 
+ @FileName
+ '.trn' + '''' 
+ ' WITH CHECKSUM;'

EXEC sp_executesql @nSQL

WAITFOR DELAY '00:00:004';

INSERT INTO [dbo].[TestLog] ([Backup_Date], [Backup Type], [FileSequence], [FileName1])
VALUES (GETDATE(), 'LOG', 0, @FileName);

SET @x += 1
END



:SETVAR DatabaseName "RestoreGene_Test"
SELECT 
	ID,
	CONVERT(VARCHAR(19),Backup_Date,120) AS RecoveryPoint,
	[Backup Type],
	FileName1,
	FileSequence
FROM [dbo].[TestLog]
ORDER BY ID
GO

----==================================================================================================
---------------------------------------------------
---- Create more backup history
--:SETVAR DatabaseName "RestoreGene_Test"

--:SETVAR DataDrive "C:\MSSQL\Data"
--:SETVAR LogDrive "C:\MSSQL\Logs\"
--:SETVAR BackupFull "C:\MSSQL\"
--:SETVAR BackupDiff "C:\MSSQL\"
--:SETVAR BackupLog "C:\MSSQL\"

--DECLARE @x INT = 1;
--DECLARE @nSQL NVARCHAR(200);

--WAITFOR DELAY '00:00:004';
--INSERT INTO $(DatabaseName).[dbo].[TestTable]  ([RandomNbr],[TestCase]) VALUES	(@x,'');

--WHILE @x < 11
--BEGIN

--SET @nSQL = 
--'BACKUP LOG $(DatabaseName) 
--TO DISK = ' + '''' + '$(BackupLog)\$(DatabaseName)_Log_A1' 
--+ CAST((DATEPART(year,GETDATE()) * 1000) + (DATEPART(month,GETDATE()) * 100) + DATEPART(day,GETDATE()) AS VARCHAR(8)) + CAST((DATEPART(hour,GETDATE()) * 1000) + (DATEPART(minute,GETDATE()) * 100) + DATEPART(second,GETDATE()) AS VARCHAR(8))
--+ '.trn' + '''' 
--+ ' WITH CHECKSUM;'

--EXEC sp_executesql @nSQL

--INSERT INTO [dbo].[TestLog] ([Backup_Date], [Backup Type], [FileSequence], [FileName1])
--VALUES (GETDATE(), 'LOG', 0, CAST((DATEPART(year,GETDATE()) * 1000) + (DATEPART(month,GETDATE()) * 100) + DATEPART(day,GETDATE()) AS VARCHAR(8)) + CAST((DATEPART(hour,GETDATE()) * 1000) + (DATEPART(minute,GETDATE()) * 100) + DATEPART(second,GETDATE()) AS VARCHAR(8)))

--WAITFOR DELAY '00:00:004';
--INSERT INTO $(DatabaseName).[dbo].[TestTable]  ([RandomNbr],[TestCase]) VALUES	(@x,'');

--SET @x += 1
--END

--:SETVAR DatabaseName "RestoreGene_Test"
--SELECT 
--	ID,
--	CONVERT(VARCHAR(19),Backup_Date,120) AS BackupDate,
--	[Backup Type],
--	FileName1,
--	FileSequence
--FROM [dbo].[TestLog]
--ORDER BY ID


