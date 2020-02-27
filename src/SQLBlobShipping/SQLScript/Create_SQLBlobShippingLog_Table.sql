CREATE TABLE [dbo].[SQLBlobShippingLog]
(
[LogID] [int] NOT NULL IDENTITY(1, 1),
[SourceServer] [nvarchar] (100) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
[SourceDatabase] [nvarchar] (100) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
[TargetServer] [nvarchar] (100) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
[TargetDatabase] [nvarchar] (100) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
[BackupType] [nvarchar] (10) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
[BackupPath] [nvarchar] (500) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
[RestoreStartDate] [datetime2] (3) NOT NULL CONSTRAINT [DF_RestoreStartDate] DEFAULT (getutcdate()),
[RestoreFinishDate] [datetime2] (3) NULL,
[RestoreError] [bit] NOT NULL CONSTRAINT [DF_RestoreError] DEFAULT ((0)),
[RestoreErrorMessage] [nvarchar] (3000) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
[BackupStartDate] [datetime2] (3) NOT NULL,
[BackupFinishDate] [datetime2] (3) NOT NULL,
[FirstLSN] [numeric] (25, 0) NOT NULL,
[LastLSN] [numeric] (25, 0) NOT NULL
) ON [PRIMARY]
WITH
(
DATA_COMPRESSION = PAGE
)
GO
ALTER TABLE [dbo].[SQLBlobShippingLog] ADD CONSTRAINT [PK_SQLBlobShippingLog_LogID] PRIMARY KEY CLUSTERED ([LogID]) WITH (DATA_COMPRESSION = PAGE) ON [PRIMARY]
GO
CREATE NONCLUSTERED INDEX [IX_SQLBlobShipping_01] ON [dbo].[SQLBlobShippingLog] ([SourceServer], [TargetServer], [TargetDatabase]) INCLUDE ([RestoreStartDate]) WITH (DATA_COMPRESSION = PAGE) ON [PRIMARY]
GO
