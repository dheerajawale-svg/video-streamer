# Bicep Deployment Script for HLS Video Streamer
# Deploys infrastructure to Azure using Bicep

param(
    [string]$SubscriptionId = "e1e63070-eac9-4df6-8590-c5f50ceef3c1",
    [string]$ResourceGroupName = "dheeraj-test-grp",
    [string]$Location = "centralindia",
    [string]$DeploymentName = "hls-streamer-deploy",
    [string]$BicepFilePath = "infra/main.bicep",
    [string]$ParameterFilePath = "infra/main.bicepparam",
    [switch]$ValidateOnly,
    [switch]$WhatIf
)

Write-Host "======================================"
Write-Host "HLS Video Streamer - Bicep Deployment"
Write-Host "======================================"
Write-Host ""

# Set subscription
Write-Host "Setting subscription..."
az account set --subscription $SubscriptionId

# Ensure resource group exists
Write-Host "Ensuring resource group exists..."
az group create `
    --name $ResourceGroupName `
    --location $Location `
    --only-show-errors

Write-Host ""

# Validate template
Write-Host "Validating Bicep template..."
az deployment group validate `
    --resource-group $ResourceGroupName `
    --template-file $BicepFilePath `
    --parameters $ParameterFilePath

if ($LASTEXITCODE -ne 0) {
    Write-Host "Template validation failed"
    exit 1
}

Write-Host "Template validation passed"
Write-Host ""

# Check what-if if requested
if ($WhatIf) {
    Write-Host "Running what-if deployment..."
    az deployment group what-if `
        --resource-group $ResourceGroupName `
        --template-file $BicepFilePath `
        --parameters $ParameterFilePath
    
    Write-Host ""
    Write-Host "This was a what-if preview. Use without -WhatIf to deploy."
    exit 0
}

# Validate only if requested
if ($ValidateOnly) {
    Write-Host "Validation only mode - no deployment performed"
    exit 0
}

# Deploy
Write-Host "Deploying infrastructure..."
$deploymentOutput = az deployment group create `
    --resource-group $ResourceGroupName `
    --template-file $BicepFilePath `
    --parameters $ParameterFilePath `
    --name $DeploymentName `
    --query "properties.outputs" -o json

if ($LASTEXITCODE -ne 0) {
    Write-Host "Deployment failed"
    exit 1
}

Write-Host "Deployment completed successfully"
Write-Host ""

# Parse and display outputs
$outputs = $deploymentOutput | ConvertFrom-Json
Write-Host "Deployment Outputs:"
Write-Host "==================="
Write-Host ""
Write-Host "Container App FQDN: $($outputs.containerAppFqdn.value)"
Write-Host "Container App URL: $($outputs.containerAppUrl.value)"
Write-Host "Managed Identity Client ID: $($outputs.managedIdentityClientId.value)"
Write-Host ""
Write-Host "Application Insights:"
Write-Host "  Key: $($outputs.appInsightsKey.value)"
Write-Host "  ID: $($outputs.appInsightsId.value)"
Write-Host ""

Write-Host "Next steps:"
Write-Host "1. Upload HLS content to storage:"
Write-Host "   .\scripts\setup-storage.ps1"
Write-Host ""
Write-Host "2. Build and push Docker image:"
Write-Host "   docker build -t cld1connectors1reg.azurecr.io/hls-video-streamer:latest ."
Write-Host "   az acr login --name cld1connectors1reg"
Write-Host "   docker push cld1connectors1reg.azurecr.io/hls-video-streamer:latest"
Write-Host ""
Write-Host "3. Container App will pull and deploy the image automatically"
Write-Host ""
