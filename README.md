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
- No cloud deployment scripts or infrastructure files are required.

