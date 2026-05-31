[CmdletBinding()]
param(
    [string]$SubscriptionId = "e1e63070-eac9-4df6-8590-c5f50ceef3c1",
    [string]$ResourceGroup = "dheeraj-test-grp",
    [string]$ContainerAppName = "hls-server",
    [string]$ContainerAppsEnvironment = "cae-cld-connectors",
    [string]$AcrName = "cld1connectors1reg",
    [string]$ManagedIdentityName = "hls-server-pull-identity",
    [string]$ImageRepository = "hls-server",
    [string]$ImageTag = (Get-Date -Format "yyyyMMddHHmmss"),
    [int]$TargetPort = 5050,
    [string]$Cpu = "0.5",
    [string]$Memory = "1.0Gi",
    [int]$MinReplicas = 0,
    [int]$MaxReplicas = 1,
    [string]$AzureStorageContainer = "hls-vod",
    [string]$AzureStorageBlobPrefix = "eamer/public/local-video/",
    [string]$AzureStorageConnectionString,
    [switch]$SkipHealthCheck,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

function Invoke-Az {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,
        [switch]$JsonOutput,
        [switch]$AllowFailure,
        [switch]$ContainsSecret
    )

    if ($DryRun) {
        if ($ContainsSecret) {
            Write-Host ("[DryRun] az {0} <secret-redacted>" -f (($Arguments | Select-Object -First 2) -join " "))
        } else {
            Write-Host ("[DryRun] az {0}" -f ($Arguments -join " "))
        }
        if ($JsonOutput) {
            return @{}
        }
        return $null
    }

    $result = & az @Arguments 2>&1
    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 0 -and -not $AllowFailure) {
        if ($ContainsSecret) {
            throw ("az command failed ({0}) with secret-bearing arguments. Output:`n{1}" -f $exitCode, ($result -join [Environment]::NewLine))
        }
        throw ("az command failed ({0}): az {1}`n{2}" -f $exitCode, ($Arguments -join " "), ($result -join [Environment]::NewLine))
    }

    if ($JsonOutput) {
        if ($exitCode -ne 0) {
            return $null
        }
        if (-not $result) {
            return $null
        }
        return ($result -join [Environment]::NewLine) | ConvertFrom-Json
    }

    return $result
}

function Get-StorageConnectionString {
    param([string]$ProvidedValue)

    if (-not [string]::IsNullOrWhiteSpace($ProvidedValue)) {
        return $ProvidedValue
    }

    if (-not [string]::IsNullOrWhiteSpace($env:AZURE_STORAGE_CONNECTION_STRING)) {
        return $env:AZURE_STORAGE_CONNECTION_STRING
    }

    $configPath = Join-Path $repoRoot "HlsServer\appsettings.Development.json"
    if (-not (Test-Path $configPath)) {
        throw "Could not find HlsServer/appsettings.Development.json. Provide -AzureStorageConnectionString or set AZURE_STORAGE_CONNECTION_STRING."
    }

    $config = Get-Content $configPath -Raw | ConvertFrom-Json
    $conn = $config.AzureStorage.ConnectionString
    if ([string]::IsNullOrWhiteSpace($conn)) {
        throw "AzureStorage.ConnectionString is empty. Provide -AzureStorageConnectionString or set AZURE_STORAGE_CONNECTION_STRING."
    }

    return $conn
}

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw "Azure CLI (az) is not installed or not in PATH."
}

$storageConnectionString = Get-StorageConnectionString -ProvidedValue $AzureStorageConnectionString
$image = "$AcrName.azurecr.io/$ImageRepository`:$ImageTag"

Write-Host "Starting deployment for $ContainerAppName"
Write-Host "Subscription: $SubscriptionId"
Write-Host "Resource Group: $ResourceGroup"
Write-Host "Image: $image"

Invoke-Az -Arguments @("account", "set", "--subscription", $SubscriptionId)

$null = Invoke-Az -Arguments @("group", "show", "--name", $ResourceGroup, "-o", "none")
$null = Invoke-Az -Arguments @("containerapp", "env", "show", "--name", $ContainerAppsEnvironment, "--resource-group", $ResourceGroup, "-o", "none")
if ($DryRun) {
    $acr = [pscustomobject]@{
        id = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.ContainerRegistry/registries/$AcrName"
        loginServer = "$AcrName.azurecr.io"
    }
    $identity = [pscustomobject]@{
        id = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.ManagedIdentity/userAssignedIdentities/$ManagedIdentityName"
        principalId = "00000000-0000-0000-0000-000000000000"
    }
} else {
    $acr = Invoke-Az -Arguments @("acr", "show", "--name", $AcrName, "--resource-group", $ResourceGroup, "--query", "{id:id,loginServer:loginServer}", "-o", "json") -JsonOutput

    $identity = Invoke-Az -Arguments @("identity", "show", "--name", $ManagedIdentityName, "--resource-group", $ResourceGroup, "--query", "{id:id,principalId:principalId}", "-o", "json") -JsonOutput -AllowFailure
    if ($null -eq $identity) {
        Write-Host "Managed identity not found. Creating $ManagedIdentityName..."
        $identity = Invoke-Az -Arguments @("identity", "create", "--name", $ManagedIdentityName, "--resource-group", $ResourceGroup, "--query", "{id:id,principalId:principalId}", "-o", "json") -JsonOutput
    }

    $roleCountOutput = Invoke-Az -Arguments @("role", "assignment", "list", "--assignee-object-id", $identity.principalId, "--scope", $acr.id, "--role", "AcrPull", "--query", "length(@)", "-o", "tsv")
    $roleCount = [int](($roleCountOutput -join "").Trim())
    if ($roleCount -eq 0) {
        Write-Host "Assigning AcrPull role on $AcrName to managed identity..."
        $null = Invoke-Az -Arguments @("role", "assignment", "create", "--assignee-object-id", $identity.principalId, "--assignee-principal-type", "ServicePrincipal", "--role", "AcrPull", "--scope", $acr.id, "-o", "none")
    }
}

Write-Host "Building and pushing image to ACR..."
$null = Invoke-Az -Arguments @("acr", "build", "--registry", $AcrName, "--file", "HlsServer/Dockerfile", "--image", "$ImageRepository`:$ImageTag", ".")

$appIdOutput = Invoke-Az -Arguments @("containerapp", "show", "--name", $ContainerAppName, "--resource-group", $ResourceGroup, "--query", "id", "-o", "tsv") -AllowFailure
$appExists = $false
if ($appIdOutput) {
    $appExists = -not [string]::IsNullOrWhiteSpace(($appIdOutput -join "").Trim())
}

if (-not $appExists) {
    Write-Host "Creating container app..."
    $null = Invoke-Az -Arguments @(
        "containerapp", "create",
        "--name", $ContainerAppName,
        "--resource-group", $ResourceGroup,
        "--environment", $ContainerAppsEnvironment,
        "--image", $image,
        "--target-port", "$TargetPort",
        "--ingress", "external",
        "--transport", "auto",
        "--min-replicas", "$MinReplicas",
        "--max-replicas", "$MaxReplicas",
        "--cpu", $Cpu,
        "--memory", $Memory,
        "--user-assigned", $identity.id,
        "--registry-server", $acr.loginServer,
        "--registry-identity", $identity.id,
        "--secrets", "azure-storage-connection-string=$storageConnectionString",
        "--env-vars", "AzureStorage__ConnectionString=secretref:azure-storage-connection-string", "AzureStorage__Container=$AzureStorageContainer", "AzureStorage__BlobPrefix=$AzureStorageBlobPrefix",
        "-o", "none"
    ) -ContainsSecret
} else {
    Write-Host "Updating existing container app..."
    $null = Invoke-Az -Arguments @("containerapp", "identity", "assign", "--name", $ContainerAppName, "--resource-group", $ResourceGroup, "--user-assigned", $identity.id, "-o", "none")
    $null = Invoke-Az -Arguments @("containerapp", "registry", "set", "--name", $ContainerAppName, "--resource-group", $ResourceGroup, "--server", $acr.loginServer, "--identity", $identity.id, "-o", "none")
    $null = Invoke-Az -Arguments @("containerapp", "secret", "set", "--name", $ContainerAppName, "--resource-group", $ResourceGroup, "--secrets", "azure-storage-connection-string=$storageConnectionString", "-o", "none") -ContainsSecret
    $null = Invoke-Az -Arguments @(
        "containerapp", "update",
        "--name", $ContainerAppName,
        "--resource-group", $ResourceGroup,
        "--image", $image,
        "--cpu", $Cpu,
        "--memory", $Memory,
        "--min-replicas", "$MinReplicas",
        "--max-replicas", "$MaxReplicas",
        "--set-env-vars", "AzureStorage__ConnectionString=secretref:azure-storage-connection-string", "AzureStorage__Container=$AzureStorageContainer", "AzureStorage__BlobPrefix=$AzureStorageBlobPrefix",
        "-o", "none"
    )
    $null = Invoke-Az -Arguments @("containerapp", "ingress", "update", "--name", $ContainerAppName, "--resource-group", $ResourceGroup, "--target-port", "$TargetPort", "--type", "external", "-o", "none")
}

$fqdnOut = Invoke-Az -Arguments @("containerapp", "show", "--name", $ContainerAppName, "--resource-group", $ResourceGroup, "--query", "properties.configuration.ingress.fqdn", "-o", "tsv")
$fqdn = ($fqdnOut -join "").Trim()
$deployedUrl = if ([string]::IsNullOrWhiteSpace($fqdn)) { "" } else { "https://$fqdn" }

if (-not $SkipHealthCheck -and -not [string]::IsNullOrWhiteSpace($deployedUrl)) {
    if ($DryRun) {
        Write-Host "[DryRun] Would call health endpoint: $deployedUrl/"
    } else {
        Write-Host "Running health check..."
        $health = Invoke-RestMethod -Uri "$deployedUrl/" -Method Get -TimeoutSec 30
        Write-Host "Health status: $($health.status)"
    }
}

Write-Host ""
Write-Host "Deployment complete."
Write-Host "Image: $image"
Write-Host "URL: $deployedUrl"
Write-Host ""
Write-Host "Azure Portal RG: https://portal.azure.com/#view/HubsExtension/BrowseResourceGroups/resourceGroupId/%2Fsubscriptions%2F$SubscriptionId%2FresourceGroups%2F$ResourceGroup"
