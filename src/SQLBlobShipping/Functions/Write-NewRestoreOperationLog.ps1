Function Write-NewRestoreOperationLog {
    [cmdletbinding()]
    Param(
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
        $BackupInfo

    )

    $query = @"
        insert into dbo.SQLBlobShippingLog
        (
            SourceServer
           ,SourceDatabase
           ,TargetServer
           ,TargetDatabase
           ,BackupType
           ,BackupPath
           ,BackupStartDate
           ,BackupFinishDate
           ,FirstLSN
           ,LastLSN
        )
        OUTPUT inserted.LogID
        values
        (   N'$SourceServerInstance'             -- SourceServer 
           ,N'$SourceDatabase'             -- SourceDatabase 
           ,N'$TargetServerInstance'             -- TargetServer 
           ,N'$TargetDatabase'             -- TargetDatabase 
           ,N'$($BackupInfo.BackupType)'             -- BackupType 
           ,N'$($BackupInfo.BackupPath)'             -- BackupPath 
           ,'$($BackupInfo.BackupStartDate)'   -- BackupStartDate 
           ,'$($BackupInfo.BackupFinishDate)'   -- BackupFinishDate 
           ,$($BackupInfo.FirstLSN)            -- FirstLSN 
           ,$($BackupInfo.LastLSN)            -- LastLSN 
        )
"@
    
    try {
        
        if ($LogServerAzureDBCertificateAuth) {
            $conn = New-AzureSQLDbConnectionWithCert -AzureSQLDBServerName $LogServerInstance `
                -DatabaseName $LogDatabase `
                -TenantID $LogServerAzureDBCertificateAuth.TenantID `
                -ClientID $LogServerAzureDBCertificateAuth.ClientID `
                -FullCertificatePath $LogServerAzureDBCertificateAuth.FullCertificatePath

            #Using Invoke-Sqlcmd2 to be able to pass in an existing connection
            $InsertedLogID = Invoke-Sqlcmd2 -SQLConnection $conn -query $query -ErrorAction Stop
            $conn.Close()
        }

        elseif ($LogServerCredential) {
            $InsertedLogID = Invoke-Sqlcmd -ServerInstance $LogServerInstance `
                -query $query `
                -Database $LogDatabase `
                -Credential $LogServerCredential `
                -ErrorAction Stop
        }

        else {
            $InsertedLogID = Invoke-Sqlcmd -ServerInstance $LogServerInstance -query $query -Database $LogDatabase -ErrorAction Stop
        }
        
        
        return $InsertedLogID.LogID

    }
    catch {
        Write-Error "Failed to log restore operation on Log Server: $LogServerInstance , Database: $LogDatabase"
        Write-Output "Error Message: $_.Exception.Message"
        return
    }

    

    
}