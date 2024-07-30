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

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        $LogServerInstance,

        [Parameter(Mandatory = $false)]
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

    #If not in script only mode, ensure log db info is passed in
    if (!$ScriptOnly) {   

        if ([string]::IsNullOrEmpty($LogServerInstance) -or [string]::IsNullOrEmpty($LogDatabase)) {   
            Write-Error "Please provide LogServerInstance and LogDatabase parameters. Or run this command in script only mode."
            return
        }
    }


    try {

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
        
    }
    catch {

        Write-Error "Failed to retrieve latest full backup for $SourceServerInstance - $SourceDatabase"
        Write-Error "Error Message: $_.Exception.Message"
        return
        
    }

    

    if ($LatestFullBackup.Count -eq 0) {
        Write-Error "No available backup file found"
        return
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
            $dbfiles = Invoke-Sqlcmd -ServerInstance $TargetServerInstance -query $query -Database master -TrustServerCertificate -ErrorAction Stop
        }

        else {
            $dbfiles = Invoke-Sqlcmd -ServerInstance $TargetServerInstance -query $query -Database master -Credential $RestoreCredential -TrustServerCertificate -ErrorAction Stop
        }
        
    }
    catch {
        Write-Error "Error Message: $_.Exception.Message"
        return
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


    try {

        [bool]$DBAlreadyExistsOnServer = Test-DBExistsOnServer -ServerInstance $TargetServerInstance -Database $TargetDatabase
    }
    catch {
        Write-Output ""
        Write-Error "ERROR: Database:[$TargetDatabase] may already exist on target server:[$TargetServerInstance] or the command was not able to check if database already exists. Restore attempt ABORTED to prevent overwrite."
        Write-Output ""
        return
    }


    if ($ScriptOnly -eq $true) {

        #Script only
        try {

            Write-Output "--------------------------SCRIPT ONLY MODE--------------------------"

            Write-Output "Restoring $TargetDatabase on $TargetServerInstance . Backup complete date: $($LatestFullBackup.BackupFinishDate[0])"

            if ($DBAlreadyExistsOnServer) {
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
            

            if ($RestoreWithRecovery) {
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

            Write-Output "Restoring $TargetDatabase on $TargetServerInstance . Backup complete date: $($LatestFullBackup.BackupFinishDate[0])"

            if ($DBAlreadyExistsOnServer) {
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
                    
                if ($RestoreWithRecovery) {
                    Write-Output "Running restore with recovery for $TargetDatabase on $TargetServerInstance"
                    Invoke-Sqlcmd -ServerInstance $TargetServerInstance -query $RestoreWithRecoveryQuery -Database master -QueryTimeout 600 -TrustServerCertificate -ErrorAction Stop
                } 
            
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

                if ($RestoreWithRecovery) {
                    Write-Output "Running restore with recovery for $TargetDatabase on $TargetServerInstance"
                    Invoke-Sqlcmd -ServerInstance $TargetServerInstance -query $RestoreWithRecoveryQuery -Database master -QueryTimeout 600 -Credential $RestoreCredential -TrustServerCertificate -ErrorAction Stop
                } 
            
                    
            }


            #Update Success
            Write-UpdateRestoreOperationLogSuccess `
                -LogServerInstance $LogServerInstance `
                -LogDatabase $LogDatabase `
                -LogID $LogID `
                -LogServerCredential $LogServerCredential `
                -LogServerAzureDBCertificateAuth $LogServerAzureDBCertificateAuth `
                -ErrorAction Stop
            
            Write-Output "Restore for $TargetDatabase on $TargetServerInstance completed on $(Get-Date)"
            
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
