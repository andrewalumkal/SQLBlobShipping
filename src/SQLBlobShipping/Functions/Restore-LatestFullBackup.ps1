Function Restore-LatestFullBackup {
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

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        $TargetDataPath,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        $TargetLogPath,

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

        [Parameter(Mandatory = $false)]
        [Switch]$RestoreWithRecovery,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [bool]
        $ScriptOnly
   
    )

    if ($UseCentralBackupHistoryServer) {

        #Remove FQDN
        $SourceServerCleansed = @($SourceServerInstance -split "\.")

        $LatestFullBackup = @(Get-LatestFullBackupFromCentralServer -CentralBackupHistoryServerConfig $CentralBackupHistoryServerConfig `
                -RestoreServerInstance $SourceServerCleansed[0] `
                -RestoreDatabase $SourceDatabase `
                -CentralBackupHistoryCredential $CentralBackupHistoryCredential `
                -CentralBackupHistoryServerAzureDBCertificateAuth $CentralBackupHistoryServerAzureDBCertificateAuth)
    }

    else {
        $LatestFullBackup = @(Get-LatestFullBackup -ServerInstance $SourceServerInstance -Database $SourceDatabase )
    }

    
    if ($LatestFullBackup.Count -eq 0) {
        Write-Error "No available backup file found"
        break
    }



    $BackupFiles = @()
    foreach ($file in $LatestFullBackup) {

        $BackupFiles += $file.BackupPath
    }

    $FirstFile = $BackupFiles[0]

    # Relocate files
    $dbfiles = @()
    $relocate = @()

    try {
        $query = "RESTORE FileListOnly FROM  URL='$FirstFile'"

        if ($RestoreCredential -eq $null) {
            $dbfiles = Invoke-Sqlcmd -ServerInstance $TargetServerInstance -query $query -Database master -ErrorAction Stop
        }

        else {
            $dbfiles = Invoke-Sqlcmd -ServerInstance $TargetServerInstance -query $query -Database master -Credential $RestoreCredential -ErrorAction Stop
        }
        
    }
    catch {
        Write-Output "Error Message: $_.Exception.Message" -ForegroundColor Red
        break
    }

    

    foreach ($dbfile in $dbfiles) {
        $DbFileName = $dbfile.PhysicalName | Split-Path -Leaf
    
        if ($dbfile.Type -eq 'L') {
            $newfile = [IO.Path]::Combine($TargetLogPath, $DbFileName)
        }
        else {
            $newfile = [IO.Path]::Combine($TargetDataPath, $DbFileName)
        }
        $relocate += New-Object Microsoft.SqlServer.Management.Smo.RelocateFile ($dbfile.LogicalName, $newfile.ToString())
    }

    #Set restore with recovery query
    $RestoreWithRecoveryQuery = "RESTORE DATABASE [$($TargetDatabase)] WITH RECOVERY, KEEP_CDC, ENABLE_BROKER;"

    [bool]$DBAlreadyExistsOnServer = Test-DBExistsOnServer -ServerInstance $TargetServerInstance -Database $TargetDatabase

    if ($ScriptOnly -eq $true) {

        #Script only
        try {

            Write-Output "--------------------------SCRIPT ONLY MODE--------------------------"

            Write-Output "Restoring $SourceDatabase on $TargetServerInstance . Backup complete date: $($LatestFullBackup.BackupFinishDate)"

            if ($DBAlreadyExistsOnServer){
                Write-Output ""
                Write-Output "WARNING: Database:[$TargetDatabase] may already exist on target server:[$TargetServerInstance] or the command was not able to check if database already exists."
                Write-Output ""
            }

            #Script restore
            if ($RestoreCredential -eq $null) {
                Restore-SqlDatabase `
                -ServerInstance $TargetServerInstance `
                -Database $TargetDatabase `
                -RelocateFile $relocate `
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
                -RelocateFile $relocate `
                -RestoreAction 'Database' `
                -BackupFile $BackupFiles `
                -Credential $RestoreCredential `
                -NoRecovery `
                -Script `
                -ErrorAction Stop
            }
            

            if ($RestoreWithRecovery){
                Write-Output ""
                Write-Output "Script to recover database after restore:"
                Write-Output $RestoreWithRecoveryQuery
                Write-Output ""
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

            Write-Output "Restoring $SourceDatabase on $TargetServerInstance . Backup complete date: $($LatestFullBackup.BackupFinishDate)"

            if ($DBAlreadyExistsOnServer){
                Write-Output ""
                Write-Error "ERROR: Database:[$TargetDatabase] may already exist on target server:[$TargetServerInstance] or the command was not able to check if database already exists. Restore attempt ABORTED to prevent overwrite."
                Write-Output ""
                return
            }

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
                -BackupInfo $LatestFullBackup[0] `
                -ErrorAction Stop

            #Run restore
            if ($RestoreCredential -eq $null) {

                Restore-SqlDatabase `
                    -ServerInstance $TargetServerInstance `
                    -Database $TargetDatabase `
                    -RelocateFile $relocate `
                    -RestoreAction 'Database' `
                    -BackupFile $BackupFiles `
                    -NoRecovery `
                    -ErrorAction Stop   
            }

            else {

                Restore-SqlDatabase `
                    -ServerInstance $TargetServerInstance `
                    -Database $TargetDatabase `
                    -RelocateFile $relocate `
                    -RestoreAction 'Database' `
                    -BackupFile $BackupFiles `
                    -NoRecovery `
                    -Credential $RestoreCredential `
                    -ErrorAction Stop
                    
            }

            #Restore with recovery if switch is on
            if ($RestoreWithRecovery){
                Invoke-Sqlcmd -ServerInstance $TargetServerInstance -query $RestoreWithRecoveryQuery -Database master -ErrorAction Stop
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
