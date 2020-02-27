Function Write-NewRestoreOperationLog {
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

    
    
    try {
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
        
        $InsertedLogID = Invoke-Sqlcmd -ServerInstance $LogServerInstance -query $query -Database $LogDatabase -ErrorAction Stop
        return $InsertedLogID.LogID

    }
    catch {
        Write-Error "Failed to log restore operation on Log Server: $LogServerInstance , Database: $LogDatabase"
        Write-Output "Error Message: $_.Exception.Message" -ForegroundColor Red
        return
    }

    

    
}