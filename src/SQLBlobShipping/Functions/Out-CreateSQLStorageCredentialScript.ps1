Function Out-CreateSQLStorageCredentialScript {
    [cmdletbinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        $StorageAccountName,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        $AccountKey,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        $ContainerName,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        $PolicyName
   
    )


    Import-Module -Name AzureRM -Force 
    
    $storageContext = New-AzureStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $AccountKey  
    $sas = New-AzureStorageContainerSASToken -name $ContainerName -Policy $PolicyName -Context $storageContext 
    $secret = $($sas.Substring(1)) 
    $ContainerUri = 'https://' + $StorageAccountName + '.blob.core.windows.net/' + $ContainerName 


    
    $CreateScript = @"
                CREATE CREDENTIAL [$ContainerUri] 
                  WITH IDENTITY='SHARED ACCESS SIGNATURE' 
                  , SECRET = '$secret'
                  go
"@
    
     
    
    return $CreateScript  


}



