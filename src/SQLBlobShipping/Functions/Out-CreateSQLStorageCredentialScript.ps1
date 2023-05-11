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


     Install-Module -Name Az.Storage -Force -AllowClobber

     Import-Module -Name Az.Storage -Force 

    
    $storageContext = New-AzStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $AccountKey  
    $sas = New-AzStorageContainerSASToken -name $ContainerName -Policy $PolicyName -Context $storageContext 
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
