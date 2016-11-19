#
# CreateAzureFileShare.ps1
# 
$storageaName = 'diorgcommontools'
$rgNameStorage = 'diglobalresources'
$stoctx = New-AzureStorageContext -StorageAccountName $storageaName -StorageAccountKey (Get-AzureRmStorageAccountKey -ResourceGroupName $rgNameStorage -Name $storageaName).Value[0] 
New-AzureStorageShare -Name octopusshare -Context $stoctx -Verbose