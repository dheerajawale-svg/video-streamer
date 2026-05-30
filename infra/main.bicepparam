// Bicep parameters for HLS Video Streamer deployment
using './main.bicep'

param location = 'centralindia'
param resourceGroupName = 'dheeraj-test-grp'
param containerAppName = 'hls-video-streamer'
param containerImageUri = 'cld1connectors1reg.azurecr.io/hls-video-streamer:latest'
param containerRegistryName = 'cld1connectors1reg'
param storageAccountName = 'dheerajhospitalsa'
param storageContainerName = 'hls-vod'
param managedEnvironmentName = 'cae-cld-connectors'
param containerPort = 5050
param corsAllowedOrigins = [
  'http://localhost:*'
  'https://*.centralindia.cloudapp.azure.com'
]
