Function Restore-LatestFullBackup {
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

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [bool]
        $ScriptOnly
   
    )

    
    $LatestFullBackup = @(Get-LatestFullBackup -ServerInstance $SourceServerInstance -Database $SourceDatabase )
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




    if ($ScriptOnly -eq $true) {

        #Script only
        try {

            Write-Output "Restoring $SourceDatabase on $TargetServerInstance"

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

            Write-Output "Restoring $SourceDatabase on $TargetServerInstance"

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
            Restore-SqlDatabase `
                -ServerInstance $TargetServerInstance `
                -Database $TargetDatabase `
                -RelocateFile $relocate `
                -RestoreAction 'Database' `
                -BackupFile $BackupFiles `
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