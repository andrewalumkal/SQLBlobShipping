Function Get-LastRestoredBackup {
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
        $TargetDatabase

    )

    
    
    
    $query = @"
            
        select     top 1 arl.BackupType
           ,arl.BackupPath
           ,arl.RestoreStartDate
           ,arl.RestoreFinishDate
           ,arl.FirstLSN
           ,arl.LastLSN
        from        dbo.SQLBlobShippingLog as arl
        where       arl.SourceServer = N'$SourceServerInstance'
        and         arl.SourceDatabase = N'$SourceDatabase'
        and         arl.TargetServer = N'$TargetServerInstance'
        and         arl.TargetDatabase = N'$TargetDatabase'
        and         arl.RestoreError <> 1
        and         arl.RestoreFinishDate is not null
        order by    arl.RestoreFinishDate desc;
        
"@

    try {
        $LastRestoredBackup = Invoke-Sqlcmd -ServerInstance $LogServerInstance -query $query -Database $LogDatabase -ErrorAction Stop
        return $LastRestoredBackup
        
    }
    
    catch {
        Write-Error "Failed to retrieve last restored backup from Log Server: $LogServerInstance , Database: $LogDatabase"
        Write-Output "Error Message: $_.Exception.Message" -ForegroundColor Red
        break
    }

    

    
}