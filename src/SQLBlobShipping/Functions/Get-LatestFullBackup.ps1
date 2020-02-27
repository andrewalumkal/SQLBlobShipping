Function Get-LatestFullBackup {
    [cmdletbinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        $ServerInstance,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        $Database
   
    )

    $query = @"
    ;with AvailableFullBackups as(
    select   d.backup_path
            ,d.backup_start_date
            ,d.backup_finish_date
            ,d.first_lsn
            ,d.last_lsn
            ,d.backup_type
            ,dense_rank() over(order by d.last_lsn desc) as [Rank]
    from        msdb.managed_backup.fn_available_backups('$Database') d
    where d.backup_type='DB')

    select '$Database' as DatabaseName
        ,afb.backup_path as BackupPath
        ,afb.backup_start_date as BackupStartDate
        ,afb.backup_finish_date as BackupFinishDate
        ,afb.first_lsn as FirstLSN
        ,afb.last_lsn as LastLSN
        ,afb.backup_type as BackupType
    from AvailableFullBackups afb
    where afb.[Rank]=1
"@

    try {
        Invoke-Sqlcmd -ServerInstance $serverInstance -query $query -Database msdb 
    }

    catch {
        Write-Error "Failed to retrieve latest full backups on $ServerInstance.$Database"
        Write-Output "Error Message: $_.Exception.Message" -ForegroundColor Red
        break
    }
    
    
}