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
        $LogID

    )

    
    
    try {
        $query = @"
            update dbo.SQLBlobShippingLog
                set RestoreFinishDate = getutcdate()
                where  LogID = $LogID
"@

        
        Invoke-Sqlcmd -ServerInstance $LogServerInstance -query $query -Database $LogDatabase -ErrorAction Stop

    }
    catch {
        Write-Error "Failed to log restore operation as success on Log Server: $LogServerInstance , Database: $LogDatabase"
        Write-Output "Error Message: $_.Exception.Message" -ForegroundColor Red
        return
    }

    

    
}