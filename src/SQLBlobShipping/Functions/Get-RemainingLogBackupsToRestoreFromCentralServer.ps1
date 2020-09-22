Function Get-RemainingLogBackupsToRestoreFromCentralServer {
    [cmdletbinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        $RestoreServerInstance,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        $RestoreDatabase,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        $CentralBackupHistoryServerConfig,

        [Parameter(Mandatory = $false)]
        [pscredential]
        $CentralBackupHistoryCredential,

        [Parameter(Mandatory = $false)]
        $CentralBackupHistoryServerAzureDBCertificateAuth,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        $LastLSN
   
    )

    $query = @"
    exec Utility.GetRemainingLogBackupsFromSQLBackupHistoryConsolidated @DatabaseName = N'$RestoreDatabase'
                                                                        ,@ServerName = N'$RestoreServerInstance'
                                                                        ,@LastLSN = $LastLSN
"@

    try {
        if ($CentralBackupHistoryServerAzureDBCertificateAuth) {
            $conn = New-AzureSQLDbConnectionWithCert -AzureSQLDBServerName $CentralBackupHistoryServerConfig.CentralBackupHistoryServer `
                -DatabaseName $CentralBackupHistoryServerConfig.CentralBackupHistoryDatabase `
                -TenantID $CentralBackupHistoryServerAzureDBCertificateAuth.TenantID `
                -ClientID $CentralBackupHistoryServerAzureDBCertificateAuth.ClientID `
                -FullCertificatePath $CentralBackupHistoryServerAzureDBCertificateAuth.FullCertificatePath

            #Using Invoke-Sqlcmd2 to be able to pass in an existing connection
            $LatestLogBackups = Invoke-Sqlcmd2 -SQLConnection $conn -query $query -ErrorAction Stop
            $conn.Close()
        }

        elseif ($CentralBackupHistoryCredential) {
            $LatestLogBackups = Invoke-Sqlcmd -ServerInstance $CentralBackupHistoryServerConfig.CentralBackupHistoryServer `
                -query $query `
                -Database $CentralBackupHistoryServerConfig.CentralBackupHistoryDatabase `
                -Credential $CentralBackupHistoryCredential `
                -ErrorAction Stop
        }

        else {
            $LatestLogBackups = Invoke-Sqlcmd -ServerInstance $CentralBackupHistoryServerConfig.CentralBackupHistoryServer `
                -query $query `
                -Database $CentralBackupHistoryServerConfig.CentralBackupHistoryDatabase `
                -ErrorAction Stop
        }

        return $LatestLogBackups 
    }

    catch {
        Write-Error "Failed to retrieve latest log backups from central server: $($CentralBackupHistoryServerConfig.CentralBackupHistoryServer) | Database: $($CentralBackupHistoryServerConfig.CentralBackupHistoryDatabase)"
        Write-Output "Error Message: $_.Exception.Message"

        if ($conn) {
            $conn.Close()
        }

        break
    }
    
    
}