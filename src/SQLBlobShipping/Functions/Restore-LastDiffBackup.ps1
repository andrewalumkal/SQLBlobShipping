Function Restore-LastDiffBackup {
    [cmdletbinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        $SourceServerInstance,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        $SourceDatabase,

        [Parameter(Mandatory = $true)]
        $CentralBackupHistoryServerConfig,

        [Parameter(Mandatory = $false)]
        [pscredential]
        $CentralBackupHistoryCredential,

        [Parameter(Mandatory = $false)]
        $CentralBackupHistoryServerAzureDBCertificateAuth,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        $TargetServerInstance,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        $TargetDatabase,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.PSCredential]
        $RestoreCredential,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        $LogServerInstance,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        $LogDatabase,

        [Parameter(Mandatory = $false)]
        [pscredential]
        $LogServerCredential,

        [Parameter(Mandatory = $false)]
        $LogServerAzureDBCertificateAuth,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [bool]
        $ScriptOnly
   
    )

    #Central backup history information is REQUIRED for this function since Azure Managed backup does NOT support differential backups
    #This function currently only supports reading backup history from a central server


    try {
        #Get last restored backup from log server
        $LastRestoredBackup = Get-LastRestoredBackup -SourceServerInstance $SourceServerInstance `
            -SourceDatabase $SourceDatabase `
            -TargetServerInstance $TargetServerInstance `
            -TargetDatabase $TargetDatabase `
            -LogServerInstance $LogServerInstance `
            -LogDatabase $LogDatabase `
            -LogServerCredential $LogServerCredential `
            -LogServerAzureDBCertificateAuth $LogServerAzureDBCertificateAuth

    }
    catch {
        Write-Error "Failed to retrieve last restored backup from Log Server: $LogServerInstance , Database: $LogDatabase"
        Write-Output "Error Message: $_.Exception.Message"
        return
    }

    #Check if last restored backup was a diff backup
    $DiffBackupRestoredLast = @($LastRestoredBackup | Where-Object { $_.BackupType -eq "Diff" })
    if ($DiffBackupRestoredLast.Count -gt 0) {
        Write-Error "The last log marker found was for a previously restored differential backup. Either try restoring a new full backup prior to restoring this differential backup, or there is no further work to do. Last restored diff backup LastLSN: $($LastRestoredBackup.LastLSN) | SourceServer: $SourceServerInstance , SourceDB: $SourceDatabase , TargetServer: $TargetServerInstance , TargetDB: $TargetDatabase ."
        return
    }


    #Check if it is a full backup    
    $FullBackupRestoredLast = @($LastRestoredBackup | Where-Object { $_.BackupType -eq "Full" })
    if ($FullBackupRestoredLast.Count -lt 1) {
        Write-Error "A full backup log marker was not found on log server for SourceServer: $SourceServerInstance , SourceDB: $SourceDatabase , TargetServer: $TargetServerInstance , TargetDB: $TargetDatabase . Restore a full backup and try again.  Ensure this is not a copy-only backup if you need to restore a subsequent differential backup."
        return
    }



    ##Get last diff backup to be applied

    #Remove FQDN
    $SourceServerCleansed = @($SourceServerInstance -split "\.")

    try {

        $DiffBackupToRestore = @(Get-LastDiffBackupToRestoreFromCentralServer -CentralBackupHistoryServerConfig $CentralBackupHistoryServerConfig `
                -RestoreServerInstance $SourceServerCleansed[0] `
                -RestoreDatabase $SourceDatabase `
                -CentralBackupHistoryCredential $CentralBackupHistoryCredential `
                -CentralBackupHistoryServerAzureDBCertificateAuth $CentralBackupHistoryServerAzureDBCertificateAuth `
                -LastLSN $LastRestoredBackup.LastLSN )


    }
    catch {
        Write-Error "Failed to retrieve latest diff backup from central server: $($CentralBackupHistoryServerConfig.CentralBackupHistoryServer) | Database: $($CentralBackupHistoryServerConfig.CentralBackupHistoryDatabase)"
        Write-Output "Error Message: $_.Exception.Message"
        return
    }

    

    if ($DiffBackupToRestore.Count -eq 0) {
        Write-Error "No diff backups found to restore after the last restored full backup with LastLSN: $($LastRestoredBackup.LastLSN) | TargetServer: $TargetServerInstance , Database: $TargetDatabase"
        return
    }   


    
    #Cater for striped diff backups
    $BackupFiles = @()
    foreach ($file in $DiffBackupToRestore) {

        $BackupFiles += $file.BackupPath
    }


    
    if ($ScriptOnly -eq $true) {

        #Script only
        try {

            Write-Output "--------------------------SCRIPT ONLY MODE--------------------------"

            Write-Output "Restoring last diff backup for [$TargetDatabase] on [$TargetServerInstance] . Backup complete date: $($DiffBackupToRestore.BackupFinishDate[0])"

            #Script restore
            if ($RestoreCredential -eq $null) {
                Restore-SqlDatabase `
                    -ServerInstance $TargetServerInstance `
                    -Database $TargetDatabase `
                    -RestoreAction 'Database' `
                    -BackupFile $BackupFiles `
                    -NoRecovery `
                    -Script `
                    -ErrorAction Stop
            }

            else {
                Restore-SqlDatabase `
                    -ServerInstance $TargetServerInstance `
                    -Database $TargetDatabase `
                    -RestoreAction 'Database' `
                    -BackupFile $BackupFiles `
                    -Credential $RestoreCredential `
                    -NoRecovery `
                    -Script `
                    -ErrorAction Stop
            }
            
            
            Write-Output "--------------------------END OF SCRIPT--------------------------"
            Write-Output ""
            
        }

        catch {
            $ErrorMessage = $_.Exception.Message
            Write-Error "Error Message: $ErrorMessage"
            return
        }
    
    }

    #Perform restore on target
    else {
        
        try {

            Write-Output "Restoring last diff backup for [$TargetDatabase] on [$TargetServerInstance] . Backup complete date: $($DiffBackupToRestore.BackupFinishDate[0])"

            #Log operation to log server
            $LogID = $null
            $LogID = Write-NewRestoreOperationLog `
                -SourceServerInstance $SourceServerInstance `
                -SourceDatabase $SourceDatabase `
                -TargetServerInstance $TargetServerInstance `
                -TargetDatabase $TargetDatabase  `
                -LogServerInstance $LogServerInstance `
                -LogDatabase $LogDatabase `
                -LogServerCredential $LogServerCredential `
                -LogServerAzureDBCertificateAuth $LogServerAzureDBCertificateAuth `
                -BackupInfo $DiffBackupToRestore[0] `
                -ErrorAction Stop

            #Run restore
            if ($RestoreCredential -eq $null) {

                Restore-SqlDatabase `
                    -ServerInstance $TargetServerInstance `
                    -Database $TargetDatabase `
                    -RestoreAction 'Database' `
                    -BackupFile $BackupFiles `
                    -NoRecovery `
                    -ErrorAction Stop  
            }

            else {

                Restore-SqlDatabase `
                    -ServerInstance $TargetServerInstance `
                    -Database $TargetDatabase `
                    -RestoreAction 'Database' `
                    -BackupFile $BackupFiles `
                    -NoRecovery `
                    -Credential $RestoreCredential `
                    -ErrorAction Stop    
            }


            #Update Success
            Write-UpdateRestoreOperationLogSuccess `
                -LogServerInstance $LogServerInstance `
                -LogDatabase $LogDatabase `
                -LogID $LogID `
                -LogServerCredential $LogServerCredential `
                -LogServerAzureDBCertificateAuth $LogServerAzureDBCertificateAuth `
                -ErrorAction Stop

        }


        catch {
            $ErrorMessage = $_.Exception.Message
            Write-Error "Error Message: $ErrorMessage"

            if ($LogID -ne $null) {

                Write-UpdateRestoreOperationLogFailure `
                    -LogServerInstance $LogServerInstance `
                    -LogDatabase $LogDatabase `
                    -LogServerCredential $LogServerCredential `
                    -LogServerAzureDBCertificateAuth $LogServerAzureDBCertificateAuth `
                    -LogID $LogID `
                    -ErrorMessage $ErrorMessage 
            }

            return

        }

    }
    


    
}