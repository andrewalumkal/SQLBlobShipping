Function Test-DBExistsOnServer {
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
    select  name
            ,d.database_id
    from    sys.databases as d
    where   d.name = '$Database';
"@

    [bool]$DBExistsOnServer = 1

    try {
        $result = @(Invoke-Sqlcmd -ServerInstance $ServerInstance -query $query -Database master -ErrorAction Stop)

    }

    catch {
        Write-Error "Failed to check if database [$Database] exists on $ServerInstance"
        Write-Output "Error Message: $_.Exception.Message"
        return $DBExistsOnServer
    }


    if ($result.Count -eq 0){
        $DBExistsOnServer = 0
    }

    return $DBExistsOnServer
    
    
}