Function Get-LastDiffBackupToRestoreFromCentralServer {
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
    exec Utility.GetLastDiffBackupFromSQLBackupHistoryConsolidated  @DatabaseName = N'$RestoreDatabase'
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
            $LatestDiffBackups = Invoke-Sqlcmd2 -SQLConnection $conn -query $query -ErrorAction Stop
            $conn.Close()
        }

        elseif ($CentralBackupHistoryCredential) {
            $LatestDiffBackups = Invoke-Sqlcmd -ServerInstance $CentralBackupHistoryServerConfig.CentralBackupHistoryServer `
                -query $query `
                -Database $CentralBackupHistoryServerConfig.CentralBackupHistoryDatabase `
                -Credential $CentralBackupHistoryCredential `
                -TrustServerCertificate `
                -ErrorAction Stop
        }

        else {
            $LatestDiffBackups = Invoke-Sqlcmd -ServerInstance $CentralBackupHistoryServerConfig.CentralBackupHistoryServer `
                -query $query `
                -Database $CentralBackupHistoryServerConfig.CentralBackupHistoryDatabase `
                -TrustServerCertificate `
                -ErrorAction Stop
        }

        return $LatestDiffBackups 
    }

    catch {
        Write-Error "Failed to retrieve latest diff backup from central server: $($CentralBackupHistoryServerConfig.CentralBackupHistoryServer) | Database: $($CentralBackupHistoryServerConfig.CentralBackupHistoryDatabase)"
        Write-Output "Error Message: $_.Exception.Message"

        if ($conn) {
            $conn.Close()
        }

        break
    }
    
    
}