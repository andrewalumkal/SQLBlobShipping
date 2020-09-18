Function Write-UpdateRestoreOperationLogSuccess {
    [cmdletbinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        $LogServerInstance,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        $LogDatabase,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        $LogID,

        [Parameter(Mandatory = $false)]
        [pscredential]
        $LogServerCredential,

        [Parameter(Mandatory = $false)]
        $LogServerAzureDBCertificateAuth

    )

    $query = @"
            update dbo.SQLBlobShippingLog
                set RestoreFinishDate = getutcdate()
                where  LogID = $LogID
"@
    
    try {
        
        if ($LogServerAzureDBCertificateAuth) {
            $conn = New-AzureSQLDbConnectionWithCert -AzureSQLDBServerName $LogServerInstance `
                -DatabaseName $LogDatabase `
                -TenantID $LogServerAzureDBCertificateAuth.TenantID `
                -ClientID $LogServerAzureDBCertificateAuth.ClientID `
                -FullCertificatePath $LogServerAzureDBCertificateAuth.FullCertificatePath

            #Using Invoke-Sqlcmd2 to be able to pass in an existing connection
            Invoke-Sqlcmd2 -SQLConnection $conn -query $query -ErrorAction Stop
            $conn.Close()
        }

        elseif ($LogServerCredential) {
            Invoke-Sqlcmd -ServerInstance $LogServerInstance `
                -query $query `
                -Database $LogDatabase `
                -Credential $LogServerCredential `
                -ErrorAction Stop
        }

        else {
            Invoke-Sqlcmd -ServerInstance $LogServerInstance -query $query -Database $LogDatabase -ErrorAction Stop
        }


    }
    catch {
        Write-Error "Failed to log restore operation as success on Log Server: $LogServerInstance , Database: $LogDatabase"
        Write-Output "Error Message: $_.Exception.Message" -ForegroundColor Red
        return
    }

    

    
}