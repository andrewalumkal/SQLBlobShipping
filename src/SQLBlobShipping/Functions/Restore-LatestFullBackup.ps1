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

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        $LogServerInstance,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        $LogDatabase,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.PSCredential]
        $RestoreCredential,

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
        $dbfiles = Invoke-Sqlcmd -ServerInstance $TargetServerInstance -query $query -Database master -ErrorAction Stop
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
    $RestoreWithRecoveryQuery = "RESTORE DATABASE [$($TargetDatabase)] WITH RECOVERY;"


    if ($ScriptOnly -eq $true) {

        #Script only
        try {

            Write-Output "Restoring $SourceDatabase on $TargetServerInstance . Backup complete date: $($LatestFullBackup.BackupFinishDate)"

            #Script restore
            Restore-SqlDatabase `
                -ServerInstance $TargetServerInstance `
                -Database $TargetDatabase `
                -RelocateFile $relocate `
                -RestoreAction 'Database' `
                -BackupFile $BackupFiles `
                -NoRecovery `
                -Script `
                -ErrorAction Stop

            if ($RestoreWithRecovery){
                Write-Output ""
                Write-Output "Script to recover database after restore:"
                Write-Output $RestoreWithRecoveryQuery
                Write-Output ""
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

            Write-Output "Restoring $SourceDatabase on $TargetServerInstance . Backup complete date: $($LatestFullBackup.BackupFinishDate)"

            #Log operation to log server
            $LogID = $null
            $LogID = Write-NewRestoreOperationLog `
                -SourceServerInstance $SourceServerInstance `
                -SourceDatabase $SourceDatabase `
                -TargetServerInstance $TargetServerInstance `
                -TargetDatabase $TargetDatabase  `
                -LogServerInstance $LogServerInstance `
                -LogDatabase $LogDatabase `
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