Function Get-RemainingLogBackupsToRestore {
    [cmdletbinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        $ServerInstance,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        $Database,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        $LastLSN
   
    )

    $query = @"
    select          d.backup_path as BackupPath
                   ,d.backup_start_date as BackupStartDate
                   ,d.backup_finish_date as BackupFinishDate
                   ,d.first_lsn as FirstLSN
                   ,d.last_lsn as LastLSN
                   ,d.backup_type as BackupType
    from        msdb.managed_backup.fn_available_backups('$Database') d
    where       d.backup_type = 'Log'
    and         d.last_lsn > $LastLSN
    and         d.backup_finish_date is not null
    order by    d.last_lsn asc;
"@

    try {
        Invoke-Sqlcmd -ServerInstance $serverInstance -query $query -Database msdb 
    }

    catch {
        Write-Error "Failed to retrieve latest logs backup on $ServerInstance.$Database"
        Write-Output "Error Message: $_.Exception.Message"
        return
    }
    
    
}