Function Restore-RemainingLogBackups {
    [cmdletbinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        $SourceServerInstance,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        $SourceDatabase,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [bool]
        $UseCentralBackupHistoryServer = 0,

        [Parameter(Mandatory = $false)]
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



    if ($LastRestoredBackup -eq $null) {
        Write-Error "No log marker found on log server for SourceServer: $SourceServerInstance , SourceDB: $SourceDatabase , TargetServer: $TargetServerInstance , TargetDB: $TargetDatabase . Restore a full backup and try again."
        return
    }



    try {

        #Get all log backups to be applied
        if ($UseCentralBackupHistoryServer) {

            #Remove FQDN
            $SourceServerCleansed = @($SourceServerInstance -split "\.")

            $LogBackupsToRestore = @(Get-RemainingLogBackupsToRestoreFromCentralServer -CentralBackupHistoryServerConfig $CentralBackupHistoryServerConfig `
                    -RestoreServerInstance $SourceServerCleansed[0] `
                    -RestoreDatabase $SourceDatabase `
                    -CentralBackupHistoryCredential $CentralBackupHistoryCredential `
                    -CentralBackupHistoryServerAzureDBCertificateAuth $CentralBackupHistoryServerAzureDBCertificateAuth `
                    -LastLSN $LastRestoredBackup.LastLSN | Sort-Object -Property LastLSN)
        }

        else {

            $LogBackupsToRestore = @(Get-RemainingLogBackupsToRestore -ServerInstance $SourceServerInstance `
                    -Database $SourceDatabase `
                    -LastLSN $LastRestoredBackup.LastLSN | Sort-Object -Property LastLSN)
        }

    }
    catch {
        
        Write-Error "Failed to retrieve latest logs backups"
        Write-Output "Error Message: $_.Exception.Message"
        return
    }
    
    

    if ($LogBackupsToRestore.Count -eq 0) {
        Write-Output "No more logs to restore on TargetServer: $TargetServerInstance , Database: $TargetDatabase"
        return
    }                                


    foreach ($LogBackup in $LogBackupsToRestore) {

        if ($ScriptOnly -eq $true) {
            
            #Script Only
            try {
    
                Write-Output "Restoring log with LastLSN: $($LogBackup.LastLSN) on $TargetServerInstance - $TargetDatabase"
                
                #Script restore
                if ($RestoreCredential -eq $null) {
                    Restore-SqlDatabase `
                        -ServerInstance $TargetServerInstance `
                        -Database $TargetDatabase `
                        -RestoreAction 'Log' `
                        -BackupFile $LogBackup.BackupPath `
                        -NoRecovery `
                        -Script `
                        -ErrorAction Stop
                }

                else {
                    Restore-SqlDatabase `
                        -ServerInstance $TargetServerInstance `
                        -Database $TargetDatabase `
                        -RestoreAction 'Log' `
                        -BackupFile $LogBackup.BackupPath `
                        -Credential $RestoreCredential `
                        -NoRecovery `
                        -Script `
                        -ErrorAction Stop
                }
                
               
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
    
                Write-Output "Restoring log with LastLSN: $($LogBackup.LastLSN) on $TargetServerInstance - $TargetDatabase"
                                
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
                    -BackupInfo $LogBackup `
                    -ErrorAction Stop

                #Run restore
                if ($RestoreCredential -eq $null) {
                    Restore-SqlDatabase `
                        -ServerInstance $TargetServerInstance `
                        -Database $TargetDatabase `
                        -RestoreAction 'Log' `
                        -BackupFile $LogBackup.BackupPath `
                        -NoRecovery `
                        -ErrorAction Stop
                }

                else {
                    Restore-SqlDatabase `
                        -ServerInstance $TargetServerInstance `
                        -Database $TargetDatabase `
                        -RestoreAction 'Log' `
                        -BackupFile $LogBackup.BackupPath `
                        -Credential $RestoreCredential `
                        -NoRecovery `
                        -ErrorAction Stop
                }
                
                
  
                #Update Success
                Write-UpdateRestoreOperationLogSuccess `
                    -LogServerInstance $LogServerInstance `
                    -LogDatabase $LogDatabase `
                    -LogServerCredential $LogServerCredential `
                    -LogServerAzureDBCertificateAuth $LogServerAzureDBCertificateAuth `
                    -LogID $LogID `
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




    
    
}