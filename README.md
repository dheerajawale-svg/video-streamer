# Local HLS Video Streamer

Small ASP.NET Core app for local HLS playback and client testing.

## What It Serves

- `/` health/status JSON
- `/hls/{path}` files from `public/local-video`
- `/player` redirects to `/player.html`
- `/player.html` browser test player from `HlsServer/wwwroot/player.html`

## Run Locally (PowerShell)

```powershell
dotnet run --project HlsServer/HlsServer.csproj
```

Default local URLs:

- `http://localhost:5050/`
- `http://localhost:5050/hls/master.m3u8`
- `http://localhost:5050/player.html`

## Local Asset Layout

The app expects HLS files under `public/local-video`:

- `master.m3u8`
- `{240p,360p,480p,720p,1080p}/index.m3u8`
- segment `.ts` files
- `eeg-markers.vtt`

## Notes

- This workspace is configured for local-only streaming from disk.

## Deploy To Azure Container Apps

One command deploy script:

```powershell
powershell -ExecutionPolicy Bypass -File .\infra\deploy-hlsserver-containerapp.ps1
```

Optional dry run (no Azure changes):

```powershell
powershell -ExecutionPolicy Bypass -File .\infra\deploy-hlsserver-containerapp.ps1 -DryRun
```

Notes:

- Defaults match [docs/azure-resources.md](docs/azure-resources.md).
- The script reads `AZURE_STORAGE_CONNECTION_STRING` first, then falls back to `HlsServer/appsettings.Development.json`.
- You can override defaults with parameters like `-SubscriptionId`, `-ResourceGroup`, `-ContainerAppName`, and `-ImageTag`.

