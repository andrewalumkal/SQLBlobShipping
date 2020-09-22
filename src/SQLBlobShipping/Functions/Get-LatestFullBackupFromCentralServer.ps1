Function Get-LatestFullBackupFromCentralServer {
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
        $CentralBackupHistoryServerAzureDBCertificateAuth
   
    )

    $query = @"
    exec Utility.GetLatestFullBackupFromSQLBackupHistoryConsolidated @DatabaseName = N'$RestoreDatabase'
                                                                    ,@ServerName = N'$RestoreServerInstance'
"@

    try {
        if ($CentralBackupHistoryServerAzureDBCertificateAuth) {
            $conn = New-AzureSQLDbConnectionWithCert -AzureSQLDBServerName $CentralBackupHistoryServerConfig.CentralBackupHistoryServer `
                -DatabaseName $CentralBackupHistoryServerConfig.CentralBackupHistoryDatabase `
                -TenantID $CentralBackupHistoryServerAzureDBCertificateAuth.TenantID `
                -ClientID $CentralBackupHistoryServerAzureDBCertificateAuth.ClientID `
                -FullCertificatePath $CentralBackupHistoryServerAzureDBCertificateAuth.FullCertificatePath

            #Using Invoke-Sqlcmd2 to be able to pass in an existing connection
            $LatestFullBackup = Invoke-Sqlcmd2 -SQLConnection $conn -query $query -ErrorAction Stop
            $conn.Close()
        }

        elseif ($CentralBackupHistoryCredential) {
            $LatestFullBackup = Invoke-Sqlcmd -ServerInstance $CentralBackupHistoryServerConfig.CentralBackupHistoryServer `
                -query $query `
                -Database $CentralBackupHistoryServerConfig.CentralBackupHistoryDatabase `
                -Credential $CentralBackupHistoryCredential `
                -ErrorAction Stop
        }

        else {
            $LatestFullBackup = Invoke-Sqlcmd -ServerInstance $CentralBackupHistoryServerConfig.CentralBackupHistoryServer `
                -query $query `
                -Database $CentralBackupHistoryServerConfig.CentralBackupHistoryDatabase `
                -ErrorAction Stop
        }

        return $LatestFullBackup 
    }

    catch {
        Write-Error "Failed to retrieve latest full backups from central server: $($CentralBackupHistoryServerConfig.CentralBackupHistoryServer) | Database: $($CentralBackupHistoryServerConfig.CentralBackupHistoryDatabase)"
        Write-Output "Error Message: $_.Exception.Message"

        if ($conn) {
            $conn.Close()
        }

        break
    }
    
    
}