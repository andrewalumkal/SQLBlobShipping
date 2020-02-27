# SQLBlobShipping

Replay SQL Backups from blob (managed backups) to target servers.

This tool provides a seamless way to replay log backups to multiple targets. This is useful when setting up a complex AlwaysOn set up / migration, especially for larger databases that may take hours to auto seed. Currently only supports source databases that are configured with [SQL Server Managed Backup to Azure](https://docs.microsoft.com/en-us/sql/relational-databases/backup-restore/sql-server-managed-backup-to-microsoft-azure?view=sql-server-2014). A logging table is used to track last applied log on a given target.

Requires the `SqlServer` module.

## Example Usage

Import the module.

```powershell
Import-Module .\src\SQLBlobShipping -Force
```

The config files can live anywhere so it can be source controlled independently. Set the path to the config files. Sample config files are available in this repo (.\src\SQLBlobShipping\Config). 
```powershell
$LogServerConfigPath = 'C:\DBSyncRestore\src\DBSyncRestore\Config\LogServer.config.json'
$RestoreConfigPath = 'C:\DBSyncRestore\src\DBSyncRestore\Config\SampleRestore.config.json'

$LogServerConfig = @(Read-RestoreConfig -Path $LogServerConfigPath).LogServerConfig
$RestoreConfig = @(Read-RestoreConfig -Path $RestoreConfigPath).RestoreConfig
```

#### Restore latest available full backup on all targets
```powershell
foreach ($Config in $RestoreConfig) {
    foreach ($TargetServer in $Config.TargetServers) {
    
        Restore-LatestFullBackup -SourceServerInstance $Config.SourceServer `
            -SourceDatabase $Config.SourceDatabaseName `
            -TargetServerInstance $TargetServer `
            -TargetDatabase $Config.TargetDatabaseName `
            -TargetDataPath $Config.TargetDataPath `
            -TargetLogPath $Config.TargetLogPath `
            -LogServerInstance $LogServerConfig.LogServer `
            -LogDatabase $LogServerConfig.LogDatabase `
            -ScriptOnly $false 
    }
}
```

#### Apply all available transaction logs to all targets

`Restore-RemainingLogBackups` will apply available transaction logs to all targets. Running the script below on a schedule will constantly replay any new logs found to all targets

```powershell
foreach ($Config in $RestoreConfig) {
    foreach ($TargetServer in $Config.TargetServers) {
    
        Restore-RemainingLogBackups -SourceServerInstance $Config.SourceServer `
            -SourceDatabase $Config.SourceDatabaseName `
            -TargetServerInstance $TargetServer `
            -TargetDatabase $Config.TargetDatabaseName `
            -LogServerInstance $LogServerConfig.LogServer `
            -LogDatabase $LogServerConfig.LogDatabase `
            -ScriptOnly $true
    }
}
```

## Sample config

Sample JSON config

```JSON
{
    "RestoreConfig": [
        {
            "SourceDatabaseName": "AGDB1",
            "SourceServer": "AG1-listener.company.corp",
            "TargetServers": [
                "dbserver01.company.corp",
                "dbserver02.company.corp"
            ],
            "TargetDatabaseName": "AGDB1",
            "TargetDataPath": "F:\\data",
            "TargetLogPath": "G:\\log"
        },
        {
            "SourceDatabaseName": "DBADatabase",
            "SourceServer": "dbserver01.company.corp",
            "TargetServers": [
                "dbserver02.company.corp",
                "dbserver03.company.corp",
                "dbserver04.company.corp"
            ],
            "TargetDatabaseName": "DBADatabase_Restored",
            "TargetDataPath": "F:\\data",
            "TargetLogPath": "G:\\log"
        }
    ]
}
```

## Logging table
A log table (dbo.SQLBlobShippingLog) is used to log all restore operations along with errors. The table can be created on any SQL Server instance using the script located in `.\src\SQLBlobShipping\SQLScript`.
Once created, the log server / database needs to be configured in a JSON file

```JSON
{
    "LogServerConfig": {
        "LogServer": "loggingserver.prod",
        "LogDatabase": "DBADatabase"
    }
}
```

