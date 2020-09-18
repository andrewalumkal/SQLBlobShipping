# SQLBlobShipping

Replay SQL Backups from blob / managed backups to target servers.

This tool provides a seamless way to replay log backups to multiple targets. This is useful when setting up a complex AlwaysOn set up / migration, especially for larger databases that may take hours to auto seed. Currently only supports source databases that are configured with [SQL Server Managed Backup to Azure](https://docs.microsoft.com/en-us/sql/relational-databases/backup-restore/sql-server-managed-backup-to-microsoft-azure?view=sql-server-2014) or databases backed up to Azure blobs with a [central backup server solution](https://github.com/andrewalumkal/SQLBackupHistoryETL). A logging table is used to track last applied log on a given target.


This solution can also be used to restore and recover the latest available full backup for integrity checks. Just use the `-RestoreWithRecovery` switch when calling `Restore-LatestFullBackup`

A sample all-in-one set-up:
- Use the [SQLBackupHistoryETL](https://github.com/andrewalumkal/SQLBackupHistoryETL) solution to consolidate all your backup history into a single SQL Server / Azure SQL Database
- Create SQLBlobShipping logging table on the same server
- Start SQLBlobShipping

This set up provides an easy, resilient way to:
- Restore your databases to any target server in the event of disaster - you don't require the source msdb to run restores
- Restores for backup integrity checks
- Continously run SQLBlobShipping for migration / setting up new replicas. A restoring replica can be kept in sync and simply joined when ready

Requires the `SqlServer` module. 

Optionally requires `Invoke-SqlCmd2` if using an Azure SQL DB as a [central backup history server]((https://github.com/andrewalumkal/SQLBackupHistoryETL)) with certificate authentication.

## Example Usage

Import the module.

```powershell
Import-Module .\src\SQLBlobShipping -Force
```

### Example using SQL managed backups
The config files can live anywhere so it can be source controlled independently. Set the path to the config files. Sample config files are available in this repo (.\src\SQLBlobShipping\Config). 
```powershell
$LogServerConfigPath = 'C:\SQLBlobShipping\src\SQLBlobShipping\Config\LogServer.config.json'
$RestoreConfigPath = 'C:\SQLBlobShipping\src\SQLBlobShipping\Config\SampleRestore.config.json'

$LogServerConfig = @(Read-RestoreConfig -Path $LogServerConfigPath).LogServerConfig
$RestoreConfig = @(Read-RestoreConfig -Path $RestoreConfigPath).RestoreConfig
[bool]$UseCentralBackupHistoryServer = @(Read-RestoreConfig -Path $RestoreConfigPath).UseCentralBackupHistoryServer #this will be set to 0 in the config
```

#### Restore latest available full backup on all targets
```powershell
foreach ($Config in $RestoreConfig) {
    foreach ($TargetServer in $Config.TargetServers) {
    
        Restore-LatestFullBackup -SourceServerInstance $Config.SourceServer `
            -SourceDatabase $Config.SourceDatabaseName `
            -UseCentralBackupHistoryServer $UseCentralBackupHistoryServer `
            -TargetServerInstance $TargetServer `
            -TargetDatabase $Config.TargetDatabaseName `
            -TargetDataPath $Config.TargetDataPath `
            -TargetLogPath $Config.TargetLogPath `
            -LogServerInstance $LogServerConfig.LogServer `
            -LogDatabase $LogServerConfig.LogDatabase `
            -ScriptOnly $false 
            #-RestoreWithRecovery
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
            -UseCentralBackupHistoryServer $UseCentralBackupHistoryServer `
            -TargetServerInstance $TargetServer `
            -TargetDatabase $Config.TargetDatabaseName `
            -LogServerInstance $LogServerConfig.LogServer `
            -LogDatabase $LogServerConfig.LogDatabase `
            -ScriptOnly $false
    }
}
```


### Example using central backup history server
This solution works well with a central backup history server that consolidates backup history from all your sql server machines. If using this [solution](https://github.com/andrewalumkal/SQLBackupHistoryETL), some additional parameters need to be passed in. An example of config files for this is available in this repo. This example also uses the central backup history server as the log server. This gives an all-in-one solution - for example, use a standalone Azure SQL DB as the central backup history + log server and SQLBlobShip to on any target.

```powershell
$LogServerConfigPath = 'C:\SQLBlobShipping\src\SQLBlobShipping\Config\LogServer.config.json'
$RestoreConfigPath = 'C:\SQLBlobShipping\src\SQLBlobShipping\Config\SampleRestoreCentralServer.config.json'
$CentralBackupServerConfigPath = 'C:\SQLBlobShipping\src\SQLBlobShipping\Config\CentralBackupHistoryServer.config.json'

$LogServerConfig = @(Read-RestoreConfig -Path $LogServerConfigPath).LogServerConfig
$RestoreConfig = @(Read-RestoreConfig -Path $RestoreConfigPath).RestoreConfig
[bool]$UseCentralBackupHistoryServer = @(Read-RestoreConfig -Path $RestoreConfigPath).UseCentralBackupHistoryServer
$CentralBackupServerConfig = @(Read-RestoreConfig -Path $CentralBackupServerConfigPath).CentralBackupHistoryServerConfig

#Create credential to central server
[string]$userName = 'myuser'
[string]$userPassword = 'mypass'
[securestring]$secStringPassword = ConvertTo-SecureString $userPassword -AsPlainText -Force
[pscredential]$credObject = New-Object System.Management.Automation.PSCredential ($userName, $secStringPassword)

#You can also pass in certificate authentication instead for Azure DBs
#$AzureDBCertificateAuth = @{TenantID = <AzureTenantIDHere>; ClientID = <AzureClientIDHere>; FullCertificatePath = "Cert:\LocalMachine\My\<CertificateThumbprintHere>"}


```

#### Restore latest available full backup on all targets
```powershell
foreach ($Config in $RestoreConfig) {
    foreach ($TargetServer in $Config.TargetServers) {
    
        Restore-LatestFullBackup -SourceServerInstance $Config.SourceServer `
            -SourceDatabase $Config.SourceDatabaseName `
            -UseCentralBackupHistoryServer $UseCentralBackupHistoryServer `
            -CentralBackupHistoryServerConfig $CentralBackupServerConfig `
            -CentralBackupHistoryCredential $credObject `
            -TargetServerInstance $TargetServer `
            -TargetDatabase $Config.TargetDatabaseName `
            -TargetDataPath $Config.TargetDataPath `
            -TargetLogPath $Config.TargetLogPath `
            -LogServerInstance $LogServerConfig.LogServer `
            -LogDatabase $LogServerConfig.LogDatabase `
            -LogServerCredential $credObject `
            -ScriptOnly $false
            #-CentralBackupHistoryServerAzureDBCertificateAuth $AzureDBCertificateAuth #Optionally can pass in certificate authentication
            #-RestoreWithRecovery
    }
}
```

#### Apply all available transaction logs to all targets

```powershell
foreach ($Config in $RestoreConfig) {
    foreach ($TargetServer in $Config.TargetServers) {
    
        Restore-RemainingLogBackups -SourceServerInstance $Config.SourceServer `
            -SourceDatabase $Config.SourceDatabaseName `
            -UseCentralBackupHistoryServer $UseCentralBackupHistoryServer `
            -CentralBackupHistoryServerConfig $CentralBackupServerConfig `
            -CentralBackupHistoryCredential $credObject `
            -TargetServerInstance $TargetServer `
            -TargetDatabase $Config.TargetDatabaseName `
            -LogServerInstance $LogServerConfig.LogServer `
            -LogDatabase $LogServerConfig.LogDatabase `
            -LogServerCredential $credObject `
            -ScriptOnly $false
            #-CentralBackupHistoryServerAzureDBCertificateAuth $AzureDBCertificateAuth #Optionally can pass in certificate authentication
    }
}
```

## Prerequisites

Create the logging table on the log server located in .\src\SQLBlobShipping\SQLScript folder of this repo

Prior to restoring backups on target servers, ensure that credentials to the storage container are created on all target servers in order to access the storage account/blob files. A helper function `Out-CreateSQLStorageCredentialScript` is available in this repo to output the TSQL create script by passing in the storage/container/key information. This function requires the `AzureRM` module to be installed.


## Sample config

Sample JSON config

```JSON
{
    "UseCentralBackupHistoryServer": 0,
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

## Credentials
Databases may need to be restored using specific credentials (ex. SA) to ensure db owner is the same as the source database. Restore credentials can be *optionally* passed in using the `-RestoreCredential` parameter when calling `Restore-LatestFullBackup`. 

