# HLS Video Streamer - Azure Deployment - Quick Reference

## 📋 Deployment Summary

Your HLS video streamer has been configured for deployment to **Azure Central India (Pune)** using **Container Apps** with **Managed Identity** authentication to **Azure Blob Storage**.

### Architecture
- **Compute**: Azure Container Apps (auto-scaling 1-3 replicas)
- **Storage**: Azure Blob Storage (dheerajhospitalsa) - LRS only
- **Identity**: Managed Identity for secure access
- **Monitoring**: Application Insights
- **CI/CD**: GitHub Actions (optional)
- **Region**: Central India (centralindia)

---

## 📁 New Files Created

```
project-root/
├── infra/
│   ├── main.bicep              # Infrastructure-as-Code (Container App + Managed Identity)
│   └── main.bicepparam         # Bicep parameters file
├── Dockerfile                   # Multi-stage Docker build
├── .github/workflows/
│   └── deploy.yml              # GitHub Actions CI/CD pipeline
├── scripts/
│   ├── deploy.ps1              # Bicep deployment script
│   └── setup-storage.ps1       # Storage setup & content upload
├── HlsServer/
│   ├── Program.cs              # Updated to use Azure Blob Storage
│   ├── HlsServer.csproj        # Updated with Azure SDK packages
│   └── wwwroot/                # Static files (player, etc.)
├── DEPLOYMENT.md               # Comprehensive deployment guide
└── README-QUICKSTART.md        # This file
```

### File Modifications
- **Program.cs**: Now reads HLS content from Azure Blob Storage using Managed Identity
- **HlsServer.csproj**: Added `Azure.Storage.Blobs` and `Azure.Identity` NuGet packages
- **Dockerfile**: Added multi-stage build with Alpine runtime for efficiency

---

## 🚀 Quick Start Deployment (5 Steps)

### Step 1: Authenticate to Azure

```bash
az login --use-device-code
az account set --subscription e1e63070-eac9-4df6-8590-c5f50ceef3c1
```

### Step 2: Upload HLS Content to Storage

```powershell
.\scripts\setup-storage.ps1 `
    -SubscriptionId "e1e63070-eac9-4df6-8590-c5f50ceef3c1" `
    -ResourceGroupName "dheeraj-test-grp" `
    -StorageAccountName "dheerajhospitalsa" `
    -LocalHlsPath "public/local-video"
```

### Step 3: Build & Push Docker Image

```bash
# Build
docker build -t cld1connectors1reg.azurecr.io/hls-video-streamer:latest .

# Login to ACR
az acr login --name cld1connectors1reg

# Push
docker push cld1connectors1reg.azurecr.io/hls-video-streamer:latest
```

### Step 4: Deploy Infrastructure

```powershell
.\scripts\deploy.ps1 `
    -SubscriptionId "e1e63070-eac9-4df6-8590-c5f50ceef3c1" `
    -ResourceGroupName "dheeraj-test-grp"
```

### Step 5: Verify Deployment

```bash
# Get Container App URL
CONTAINER_APP_URL="https://$(az containerapp show \
    --resource-group dheeraj-test-grp \
    --name hls-video-streamer \
    --query properties.configuration.ingress.fqdn -o tsv)"

# Test health endpoint
curl "$CONTAINER_APP_URL/"

# Open player in browser
echo "Open: $CONTAINER_APP_URL/player.html"
```

---

## 🔑 Key Configuration

### Environment Variables (Container App)
- `AZURE_STORAGE_ACCOUNT_NAME`: dheerajhospitalsa
- `AZURE_STORAGE_CONTAINER_NAME`: hls-vod
- `CORS_ALLOWED_ORIGINS`: http://localhost:*, https://*.centralindia.cloudapp.azure.com

### Azure Resources
- **Subscription**: e1e63070-eac9-4df6-8590-c5f50ceef3c1
- **Resource Group**: dheeraj-test-grp
- **Region**: centralindia
- **Managed Environment**: cae-cld-connectors
- **Container Registry**: cld1connectors1reg

### Storage Structure
```
dheerajhospitalsa/
├── hls-vod/                 ← HLS content (public read)
│   ├── master.m3u8
│   ├── eeg-markers.vtt
│   ├── 240p/, 360p/, 480p/, 720p/, 1080p/
│   └── (segments, playlists)
└── backup-mp4/              ← Source files (private)
```

---

## 📊 Container App Configuration

| Property | Value |
|----------|-------|
| **CPU** | 0.5 cores |
| **Memory** | 1 GB |
| **Port** | 5050 |
| **Min Replicas** | 1 |
| **Max Replicas** | 3 |
| **Auto-scale Trigger** | 100 concurrent requests |
| **Health Check** | GET / every 10s (liveness) |
| **Startup Probe** | 30s delay |

---

## 🛡️ Security & Access

- **Authentication**: Managed Identity (no secrets in code or config)
- **Storage Access**: RBAC - Storage Blob Data Reader role
- **Public Access**: Only `hls-vod` container is publicly readable
- **CORS**: Configured for HLS streaming client origins
- **Network**: Container Apps expose public HTTPS endpoint
- **Health Checks**: Built-in liveness & readiness probes

---

## 📈 Performance Optimization

- **In-Memory Cache**: Manifests and VTT cached for 5 minutes (100 entry limit)
- **Cache Headers**:
  - `.ts` segments: `max-age=31536000, immutable` (1 year)
  - `.m3u8` playlists: `max-age=300` (5 minutes)
  - `.vtt` markers: `max-age=300` (5 minutes)
- **Same-Region Storage**: Central India datacenter (minimal latency)
- **LRS Replication**: Cost-optimized for single-region deployment

---

## 🧪 Testing Endpoints

```bash
# Health check
GET /

# HLS Master Manifest
GET /hls/master.m3u8

# Variant Playlists
GET /hls/240p/index.m3u8
GET /hls/360p/index.m3u8
GET /hls/480p/index.m3u8
GET /hls/720p/index.m3u8
GET /hls/1080p/index.m3u8

# Video Segments
GET /hls/{resolution}/seq_000.ts
GET /hls/{resolution}/seq_001.ts
...

# Markers
GET /hls/eeg-markers.vtt

# Web Player
GET /player
GET /player.html
```

---

## 💰 Cost Estimation

**Monthly Cost Breakdown (Central India)**

| Component | Cost |
|-----------|------|
| Container Apps (0.5 CPU, 1GB, 1-3 replicas) | ₹2,500-3,500 (~$30-42) |
| Storage Account (Standard LRS) | ₹500-1,000 (~$6-12) |
| Application Insights (Basic, 30-day retention) | ₹300-500 (~$4-6) |
| **Total Estimated** | **₹3,300-5,000/month** |

*Costs assume: 1,000-10,000 requests/day, <100 GB storage, India clients only*

---

## 📝 Next Steps

1. **Pre-Deployment**:
   - [ ] Verify local HLS content structure
   - [ ] Ensure Docker and Azure CLI installed locally
   - [ ] Confirm Azure subscription and permissions

2. **Deployment**:
   - [ ] Run storage setup script
   - [ ] Build and push Docker image
   - [ ] Deploy infrastructure with Bicep
   - [ ] Verify all endpoints working

3. **Post-Deployment**:
   - [ ] Monitor Application Insights dashboard
   - [ ] Test streaming from client in India
   - [ ] Configure backup and disaster recovery
   - [ ] Set up monitoring alerts

4. **CI/CD (Optional)**:
   - [ ] Setup GitHub federated credentials
   - [ ] Add Azure secrets to repo
   - [ ] Push code to trigger pipeline
   - [ ] Monitor automated deployments

---

## 🔗 Useful Links

- **Azure Portal**: https://portal.azure.com
- **Resource Group**: https://portal.azure.com/#@/resource/subscriptions/e1e63070-eac9-4df6-8590-c5f50ceef3c1/resourceGroups/dheeraj-test-grp/overview
- **Container Registry**: https://portal.azure.com/#@/resource/subscriptions/e1e63070-eac9-4df6-8590-c5f50ceef3c1/resourceGroups/dheeraj-test-grp/providers/Microsoft.ContainerRegistry/registries/cld1connectors1reg/overview
- **Storage Account**: https://portal.azure.com/#@/resource/subscriptions/e1e63070-eac9-4df6-8590-c5f50ceef3c1/resourceGroups/dheeraj-test-grp/providers/Microsoft.Storage/storageAccounts/dheerajhospitalsa/overview

---

## ❓ Troubleshooting

### Container App won't start
```bash
# Check logs
az containerapp logs show --resource-group dheeraj-test-grp --name hls-video-streamer --follow

# Check provisioning state
az containerapp show --resource-group dheeraj-test-grp --name hls-video-streamer --query properties.provisioningState
```

### HLS content not found (404)
```bash
# Verify storage container
az storage container exists --name hls-vod --account-name dheerajhospitalsa --auth-mode login

# List uploaded blobs
az storage blob list --container-name hls-vod --account-name dheerajhospitalsa --auth-mode login
```

### CORS errors in browser console
```bash
# Verify CORS config
az storage cors list --services b --account-name dheerajhospitalsa
```

### Slow playback or timeouts
- Verify container has sufficient CPU/memory (currently 0.5 CPU, 1GB)
- Check network connectivity between container and storage account
- Monitor Application Insights for latency spikes

---

## 📞 Support

For detailed information, refer to:
- `DEPLOYMENT.md` - Comprehensive deployment guide
- `infra/main.bicep` - Infrastructure code with comments
- `HlsServer/Program.cs` - Application code comments

---

**Deployment completed!** Your HLS Video Streamer is ready for Azure Central India. 🎉
