Function Restore-RemainingLogBackups {
    [cmdletbinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        $SourceServerInstance,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        $SourceDatabase,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        $TargetServerInstance,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        $TargetDatabase,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        $LogServerInstance,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        $LogDatabase,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [bool]
        $ScriptOnly
   
    )

    #Get last restored backup from log server
    $LastRestoredBackup = Get-LastRestoredBackup -SourceServerInstance $SourceServerInstance `
        -SourceDatabase $SourceDatabase `
        -TargetServerInstance $TargetServerInstance `
        -TargetDatabase $TargetDatabase `
        -LogServerInstance $LogServerInstance `
        -LogDatabase $LogDatabase


    if ($LastRestoredBackup -eq $null) {
        Write-Output "No log marker found on log server for SourceServer: $SourceServerInstance , SourceDB: $SourceDatabase , TargetServer: $TargetServerInstance , TargetDB: $TargetDatabase"
        Write-Output "Restore a full backup and try again"
        return
    }

    #Get all log backups to be applied
    $LogBackupsToRestore = @(Get-RemainingLogBackupsToRestore -ServerInstance $SourceServerInstance `
            -Database $SourceDatabase `
            -LastLSN $LastRestoredBackup.LastLSN | Sort-Object -Property LastLSN)

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
                Restore-SqlDatabase `
                    -ServerInstance $TargetServerInstance `
                    -Database $TargetDatabase `
                    -RestoreAction 'Log' `
                    -BackupFile $LogBackup.BackupPath `
                    -NoRecovery `
                    -Script `
                    -ErrorAction Stop
               
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
                    -BackupInfo $LogBackup `
                    -ErrorAction Stop

                #Run restore
                Restore-SqlDatabase `
                    -ServerInstance $TargetServerInstance `
                    -Database $TargetDatabase `
                    -RestoreAction 'Log' `
                    -BackupFile $LogBackup.BackupPath `
                    -NoRecovery `
                    -ErrorAction Stop
                
  
                #Update Success
                Write-UpdateRestoreOperationLogSuccess `
                    -LogServerInstance $LogServerInstance `
                    -LogDatabase $LogDatabase `
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
                        -LogID $LogID `
                        -ErrorMessage $ErrorMessage 
                }
    
                return
            }
        }


    }




   



    
    
    
}