Function Read-RestoreConfig {
    [cmdletbinding()]
    Param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [System.IO.FileInfo]
        $Path
    )
    Process {
        Get-Content -Path $Path -Raw | ConvertFrom-Json
    }
}