// Azure HLS Video Streamer - Central India Deployment
// This template deploys a Container App with Azure Storage integration
// for serving pre-generated HLS VOD content with Managed Identity auth

param location string = 'centralindia'
param resourceGroupName string = 'dheeraj-test-grp'
param containerAppName string = 'hls-video-streamer'
param containerImageUri string = 'cld1connectors1reg.azurecr.io/hls-video-streamer:latest'
param containerRegistryName string = 'cld1connectors1reg'
param storageAccountName string = 'dheerajhospitalsa'
param storageContainerName string = 'hls-vod'
param managedEnvironmentName string = 'cae-cld-connectors'
param containerPort int = 5050
param corsAllowedOrigins array = [
  'http://localhost:*'
  'https://*.centralindia.cloudapp.azure.com'
]

// Storage account reference (existing)
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: storageAccountName
}

// Managed environment reference (existing)
resource managedEnvironment 'Microsoft.App/managedEnvironments@2023-11-02-preview' existing = {
  name: managedEnvironmentName
}

// Container registry reference (existing)
resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-01-01-preview' existing = {
  name: containerRegistryName
}

// Managed Identity for Container App
resource containerAppIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${containerAppName}-identity'
  location: location
}

// Role assignment: Storage Blob Data Reader for Managed Identity
resource storageBlobReaderRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, containerAppIdentity.id, 'Storage Blob Data Reader')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1')
    principalId: containerAppIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Role assignment: AcrPull for Managed Identity
resource acrPullRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(containerRegistry.id, containerAppIdentity.id, 'AcrPull')
  scope: containerRegistry
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
    principalId: containerAppIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Container App for HLS streaming
resource containerApp 'Microsoft.App/containerApps@2023-11-02-preview' = {
  name: containerAppName
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${containerAppIdentity.id}': {}
    }
  }
  properties: {
    managedEnvironmentId: managedEnvironment.id
    configuration: {
      ingress: {
        external: true
        targetPort: containerPort
        allowInsecure: false
        traffic: [
          {
            label: 'production'
            latestRevision: true
            weight: 100
          }
        ]
      }
      secrets: [
        {
          name: 'storage-account-name'
          value: storageAccountName
        }
        {
          name: 'storage-container-name'
          value: storageContainerName
        }
        {
          name: 'managed-identity-client-id'
          value: containerAppIdentity.properties.clientId
        }
      ]
      registries: [
        {
          server: '${containerRegistryName}.azurecr.io'
          identity: containerAppIdentity.id
        }
      ]
    }
    template: {
      revisionSuffix: 'v1'
      containers: [
        {
          name: 'hls-streamer'
          image: containerImageUri
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
          env: [
            {
              name: 'ASPNETCORE_URLS'
              value: 'http://+:${containerPort}'
            }
            {
              name: 'ASPNETCORE_ENVIRONMENT'
              value: 'Production'
            }
            {
              name: 'AZURE_STORAGE_ACCOUNT_NAME'
              secretRef: 'storage-account-name'
            }
            {
              name: 'AZURE_STORAGE_CONTAINER_NAME'
              secretRef: 'storage-container-name'
            }
            {
              name: 'AZURE_CLIENT_ID'
              secretRef: 'managed-identity-client-id'
            }
            {
              name: 'CORS_ALLOWED_ORIGINS'
              value: join(corsAllowedOrigins, ',')
            }
          ]
          probes: [
            {
              type: 'liveness'
              httpGet: {
                port: containerPort
                path: '/'
              }
              initialDelaySeconds: 30
              periodSeconds: 10
            }
            {
              type: 'readiness'
              httpGet: {
                port: containerPort
                path: '/'
              }
              initialDelaySeconds: 5
              periodSeconds: 5
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 3
        rules: [
          {
            name: 'http-requests'
            http: {
              metadata: {
                concurrentRequests: '100'
              }
            }
          }
        ]
      }
    }
  }
}

// Application Insights for monitoring (optional but recommended)
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: '${containerAppName}-insights'
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    RetentionInDays: 30
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Outputs
output containerAppFqdn string = containerApp.properties.configuration.ingress.fqdn
output containerAppUrl string = 'https://${containerApp.properties.configuration.ingress.fqdn}'
output managedIdentityClientId string = containerAppIdentity.properties.clientId
output appInsightsKey string = appInsights.properties.InstrumentationKey
output appInsightsId string = appInsights.id
