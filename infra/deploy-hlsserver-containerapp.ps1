[CmdletBinding()]
param(
    [string] $SubscriptionId = "e1e63070-eac9-4df6-8590-c5f50ceef3c1",
    [string] $ResourceGroup = "dheeraj-test-grp",
    [string] $Location = "",
    [string] $ContainerAppName = "hls-server",
    [string] $ContainerAppsEnvironment = "hls-server-env",
    [string] $AcrName = "",
    [string] $ManagedIdentityName = "hls-server-pull-identity",
    [string] $ImageRepository = "hls-server",
    [string] $ImageTag = "",
    [string] $DevelopmentSettingsPath = "",
    [string] $DockerfilePath = "",
    [int] $TargetPort = 5050,
    [string[]] $SecretPathPatterns = @("ConnectionString", "Password", "Secret", "Token", "Key"),
    [switch] $SkipContainerAppExtensionUpgrade
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Invoke-Az {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]] $Arguments)

    Write-Host "az $(Format-AzArgumentsForLog -Arguments $Arguments)"
    & az @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Azure CLI command failed with exit code $LASTEXITCODE."
    }
}

function Format-AzArgumentsForLog {
    param([Parameter(Mandatory = $true)][string[]] $Arguments)

    $formatted = New-Object System.Collections.Generic.List[string]
    $redactUntilNextOption = $false

    foreach ($argument in $Arguments) {
        if ($argument.StartsWith("--") -and $argument -ne "--secrets") {
            $redactUntilNextOption = $false
        }

        if ($redactUntilNextOption -and -not $argument.StartsWith("--")) {
            $formatted.Add("<redacted-secret>")
            continue
        }

        $formatted.Add($argument)

        if ($argument -eq "--secrets") {
            $redactUntilNextOption = $true
        }
    }

    return ($formatted -join " ")
}

function Get-RepoRoot {
    $scriptRoot = Split-Path -Parent $PSCommandPath
    return (Resolve-Path (Join-Path $scriptRoot "..")).Path
}

function ConvertTo-FlatSetting {
    param(
        [Parameter(Mandatory = $true)] $Node,
        [string] $Prefix = ""
    )

    $items = @{}

    if ($null -eq $Node) {
        return $items
    }

    if ($Node -is [System.Management.Automation.PSCustomObject]) {
        foreach ($property in $Node.PSObject.Properties) {
            $name = if ([string]::IsNullOrWhiteSpace($Prefix)) { $property.Name } else { "$Prefix`:$($property.Name)" }
            foreach ($entry in (ConvertTo-FlatSetting -Node $property.Value -Prefix $name).GetEnumerator()) {
                $items[$entry.Key] = $entry.Value
            }
        }
        return $items
    }

    if ($Node -is [System.Array]) {
        for ($i = 0; $i -lt $Node.Count; $i++) {
            $name = "$Prefix`:$i"
            foreach ($entry in (ConvertTo-FlatSetting -Node $Node[$i] -Prefix $name).GetEnumerator()) {
                $items[$entry.Key] = $entry.Value
            }
        }
        return $items
    }

    $items[$Prefix] = [string] $Node
    return $items
}

function ConvertTo-SecretName {
    param([Parameter(Mandatory = $true)][string] $ConfigPath)

    $name = $ConfigPath.ToLowerInvariant() -replace "[^a-z0-9]+", "-"
    $name = $name.Trim("-")
    if ($name.Length -gt 63) {
        $name = $name.Substring(0, 63).Trim("-")
    }
    if ([string]::IsNullOrWhiteSpace($name)) {
        throw "Unable to derive a Container Apps secret name from '$ConfigPath'."
    }
    return $name
}

function Test-IsSecretPath {
    param(
        [Parameter(Mandatory = $true)][string] $ConfigPath,
        [Parameter(Mandatory = $true)][string[]] $Patterns
    )

    foreach ($pattern in $Patterns) {
        if ($ConfigPath -match "(^|:)$([regex]::Escape($pattern))$") {
            return $true
        }
    }
    return $false
}

function New-StableAcrName {
    param([Parameter(Mandatory = $true)][string] $Seed)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Seed)
    $hash = ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString("x2") }) -join ""
    return "hlsstreamer$($hash.Substring(0, 12))"
}

function Assert-NoPlaceholderSecret {
    param(
        [Parameter(Mandatory = $true)][string] $ConfigPath,
        [Parameter(Mandatory = $true)][string] $Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        throw "Secret '$ConfigPath' is empty in appsettings.Development.json."
    }

    if ($Value -match "<[^>]+>" -or $Value -match "PASTE_|TODO|REPLACE_ME") {
        throw "Secret '$ConfigPath' still looks like a placeholder. Update appsettings.Development.json before deploying."
    }
}

$repoRoot = Get-RepoRoot
if ([string]::IsNullOrWhiteSpace($DevelopmentSettingsPath)) {
    $DevelopmentSettingsPath = Join-Path $repoRoot "HlsServer/appsettings.Development.json"
}
if ([string]::IsNullOrWhiteSpace($DockerfilePath)) {
    $DockerfilePath = Join-Path $repoRoot "HlsServer/Dockerfile"
}
if ([string]::IsNullOrWhiteSpace($ImageTag)) {
    $ImageTag = (Get-Date -Format "yyyyMMddHHmmss")
}
if ([string]::IsNullOrWhiteSpace($AcrName)) {
    $AcrName = New-StableAcrName -Seed "$SubscriptionId/$ResourceGroup/$ContainerAppName"
}

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw "Azure CLI 'az' was not found on PATH."
}
if (-not (Test-Path $DevelopmentSettingsPath)) {
    throw "Settings file not found: $DevelopmentSettingsPath"
}
if (-not (Test-Path $DockerfilePath)) {
    throw "Dockerfile not found: $DockerfilePath"
}

$settingsJson = Get-Content $DevelopmentSettingsPath -Raw | ConvertFrom-Json
$flatSettings = ConvertTo-FlatSetting -Node $settingsJson
$secretArgs = @()
$envArgs = @(
    "ASPNETCORE_ENVIRONMENT=Production",
    "ASPNETCORE_URLS=http://+:$TargetPort"
)

foreach ($entry in ($flatSettings.GetEnumerator() | Sort-Object Name)) {
    if ([string]::IsNullOrWhiteSpace($entry.Value)) {
        continue
    }

    $envName = $entry.Key.Replace(":", "__")
    if (Test-IsSecretPath -ConfigPath $entry.Key -Patterns $SecretPathPatterns) {
        Assert-NoPlaceholderSecret -ConfigPath $entry.Key -Value $entry.Value
        $secretName = ConvertTo-SecretName -ConfigPath $entry.Key
        $secretArgs += "$secretName=$($entry.Value)"
        $envArgs += "$envName=secretref:$secretName"
    }
    else {
        $envArgs += "$envName=$($entry.Value)"
    }
}

if ($secretArgs.Count -eq 0) {
    throw "No secret-like settings were found in appsettings.Development.json. Checked patterns: $($SecretPathPatterns -join ', ')."
}

if ($ContainerAppName.Length -ge 32) {
    throw "Container Apps name must be less than 32 characters: '$ContainerAppName'."
}
if ($AcrName -notmatch "^[a-z0-9]{5,50}$") {
    throw "ACR name must be 5-50 lowercase alphanumeric characters: '$AcrName'."
}

Push-Location $repoRoot
try {
    Invoke-Az account set --subscription $SubscriptionId

    if (-not $SkipContainerAppExtensionUpgrade) {
        Invoke-Az extension add --name containerapp --upgrade
    }

    $resourceGroupLocation = (& az group show --name $ResourceGroup --query location --output tsv)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($resourceGroupLocation)) {
        throw "Resource group '$ResourceGroup' was not found in subscription '$SubscriptionId'."
    }
    if ([string]::IsNullOrWhiteSpace($Location)) {
        $Location = $resourceGroupLocation.Trim()
    }

    $acrExists = (& az acr show --name $AcrName --resource-group $ResourceGroup --query name --output tsv 2>$null)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($acrExists)) {
        Invoke-Az acr create --name $AcrName --resource-group $ResourceGroup --location $Location --sku Basic --admin-enabled false
    }

    $environmentExists = (& az containerapp env show --name $ContainerAppsEnvironment --resource-group $ResourceGroup --query name --output tsv 2>$null)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($environmentExists)) {
        Invoke-Az containerapp env create --name $ContainerAppsEnvironment --resource-group $ResourceGroup --location $Location
    }

    $identityExists = (& az identity show --name $ManagedIdentityName --resource-group $ResourceGroup --query id --output tsv 2>$null)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($identityExists)) {
        Invoke-Az identity create --name $ManagedIdentityName --resource-group $ResourceGroup --location $Location --output none
    }

    $identityId = (& az identity show --name $ManagedIdentityName --resource-group $ResourceGroup --query id --output tsv)
    $principalId = (& az identity show --name $ManagedIdentityName --resource-group $ResourceGroup --query principalId --output tsv)
    $acrId = (& az acr show --name $AcrName --resource-group $ResourceGroup --query id --output tsv)
    $loginServer = (& az acr show --name $AcrName --resource-group $ResourceGroup --query loginServer --output tsv)
    if ([string]::IsNullOrWhiteSpace($identityId) -or [string]::IsNullOrWhiteSpace($principalId) -or [string]::IsNullOrWhiteSpace($acrId) -or [string]::IsNullOrWhiteSpace($loginServer)) {
        throw "Unable to resolve ACR or managed identity details."
    }

    $roleAssignmentExists = (& az role assignment list --assignee $principalId --scope $acrId --role AcrPull --query "[0].id" --output tsv)
    if ([string]::IsNullOrWhiteSpace($roleAssignmentExists)) {
        Invoke-Az role assignment create --assignee-object-id $principalId --assignee-principal-type ServicePrincipal --role AcrPull --scope $acrId --output none
    }

    $imageName = "$loginServer/$ImageRepository`:$ImageTag"
    Invoke-Az acr build --registry $AcrName --image "$ImageRepository`:$ImageTag" --file $DockerfilePath .

    $containerAppExists = (& az containerapp show --name $ContainerAppName --resource-group $ResourceGroup --query name --output tsv 2>$null)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($containerAppExists)) {
        $createArgs = @(
            "containerapp", "create",
            "--name", $ContainerAppName,
            "--resource-group", $ResourceGroup,
            "--environment", $ContainerAppsEnvironment,
            "--image", $imageName,
            "--target-port", $TargetPort,
            "--ingress", "external",
            "--user-assigned", $identityId,
            "--registry-identity", $identityId,
            "--registry-server", $loginServer,
            "--secrets"
        ) + $secretArgs + @("--env-vars") + $envArgs
        Invoke-Az @createArgs
    }
    else {
        $secretSetArgs = @(
            "containerapp", "secret", "set",
            "--name", $ContainerAppName,
            "--resource-group", $ResourceGroup,
            "--secrets"
        ) + $secretArgs
        Invoke-Az @secretSetArgs
        Invoke-Az containerapp registry set --name $ContainerAppName --resource-group $ResourceGroup --identity $identityId --server $loginServer
        $updateArgs = @(
            "containerapp", "update",
            "--name", $ContainerAppName,
            "--resource-group", $ResourceGroup,
            "--image", $imageName,
            "--set-env-vars"
        ) + $envArgs
        Invoke-Az @updateArgs
        Invoke-Az containerapp ingress enable --name $ContainerAppName --resource-group $ResourceGroup --type external --target-port $TargetPort
    }

    $fqdn = (& az containerapp show --name $ContainerAppName --resource-group $ResourceGroup --query properties.configuration.ingress.fqdn --output tsv)
    Write-Host ""
    Write-Host "Deployment complete."
    Write-Host "Container app: $ContainerAppName"
    Write-Host "Image: $imageName"
    Write-Host "URL: https://$fqdn"
    Write-Host "Player: https://$fqdn/player.html"
    Write-Host "HLS manifest: https://$fqdn/hls/master.m3u8"
}
finally {
    Pop-Location
}
