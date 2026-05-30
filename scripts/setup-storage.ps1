param(
    [string]$SubscriptionId = "e1e63070-eac9-4df6-8590-c5f50ceef3c1",
    [string]$ResourceGroupName = "dheeraj-test-grp",
    [string]$StorageAccountName = "dheerajhospitalsa",
    [string]$HlsContainerName = "hls-vod",
    [string]$LocalHlsPath = "public/local-video"
)

Write-Host "Setting up Azure Storage for HLS streaming..."
az account set --subscription $SubscriptionId
$storageKey = az storage account keys list --account-name $StorageAccountName --resource-group $ResourceGroupName --query '[0].value' -o tsv

Write-Host "Creating HLS container..."
az storage container create --name $HlsContainerName --account-name $StorageAccountName --account-key $storageKey --public-access blob

Write-Host "Configuring CORS..."
az storage cors add --services b --methods GET HEAD OPTIONS --origins "*" --allowed-headers "*" --exposed-headers "*" --max-age 3600 --account-name $StorageAccountName --account-key $storageKey

Write-Host "Uploading HLS content..."
$files = Get-ChildItem -Path $LocalHlsPath -Recurse -File
$count = 0

foreach ($file in $files) {
    $count = $count + 1
    $rel = $file.FullName.Substring($LocalHlsPath.Length).TrimStart('\').Replace('\', '/')
    
    $ctype = "application/octet-stream"
    if ($file.Extension -eq ".m3u8") { $ctype = "application/vnd.apple.mpegurl" }
    if ($file.Extension -eq ".ts") { $ctype = "video/mp2t" }
    if ($file.Extension -eq ".vtt") { $ctype = "text/vtt" }
    if ($file.Extension -eq ".mp4") { $ctype = "video/mp4" }
    
    az storage blob upload --file $file.FullName --container-name $HlsContainerName --name $rel --account-name $StorageAccountName --account-key $storageKey --content-type $ctype --overwrite
    
    if ($file.Extension -eq ".ts") {
        az storage blob update --container-name $HlsContainerName --name $rel --account-name $StorageAccountName --account-key $storageKey --content-cache-control "public, max-age=31536000, immutable"
    }
    
    if ($file.Extension -eq ".m3u8") {
        az storage blob update --container-name $HlsContainerName --name $rel --account-name $StorageAccountName --account-key $storageKey --content-cache-control "public, max-age=300"
    }
    
    if ($count % 50 -eq 0) {
        Write-Host "Uploaded $count files..."
    }
}

Write-Host "Complete! Uploaded $count files"
$url = "https://$StorageAccountName.blob.core.windows.net/$HlsContainerName/master.m3u8"
Write-Host "Master: $url"
