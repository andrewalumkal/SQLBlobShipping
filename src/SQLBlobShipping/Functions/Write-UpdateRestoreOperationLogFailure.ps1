Function Write-UpdateRestoreOperationLogFailure {
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

        [ValidateNotNullOrEmpty()]
        $ErrorMessage

    )

    $ErrorMessage = $ErrorMessage -replace "'", ""
    $ErrorMessage = $ErrorMessage -replace '"', ""
    
    try {
        $query = @"
            update dbo.SQLBlobShippingLog
                set RestoreError = 1,
                    RestoreErrorMessage = '$ErrorMessage'
                where  LogID = $LogID
"@

        Invoke-Sqlcmd -ServerInstance $LogServerInstance -query $query -Database $LogDatabase -ErrorAction Stop

    }
    catch {
        Write-Error "Failed to log restore operation as failed on Log Server: $LogServerInstance , Database: $LogDatabase"
        Write-Output "Error Message: $_.Exception.Message" -ForegroundColor Red
        return
    }

    

    
}