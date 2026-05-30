# Workspace Notes

This workspace is a local multi-variant HLS video streamer used for quick browser
testing and for client apps that need a local HLS manifest.

## Key Resources

- `HlsServer/` is a small ASP.NET Core `net8.0` web app.
- `HlsServer/Program.cs` enables CORS, serves the browser player from
  `HlsServer/wwwroot`, and exposes `public/local-video` at `/hls`.
- `HlsServer/wwwroot/player.html` is the browser-based test player. It loads
  `/hls/master.m3u8`, uses hls.js when needed, shows quality levels, and reads
  marker metadata from `/hls/eeg-markers.vtt`.
- `public/local-video/master.m3u8` is the HLS master playlist.
- `public/local-video/{240p,360p,480p,720p,1080p}/index.m3u8` are the variant
  playlists. Each variant currently has matching `.ts` segments.
- `public/local-video/eeg-markers.vtt` contains marker metadata cues.
- `public/local-video/rmplive-livesource_*.mp4` are the source MP4 files used
  to regenerate missing HLS segments.
- `ffmpeg/bin/ffmpeg.exe` is the bundled FFmpeg binary used by the server when
  variant playlists are missing.

## Run And Test

From the workspace root:

```powershell
dotnet run --project HlsServer/HlsServer.csproj
```

Default local endpoints:

- `http://localhost:5050/` returns server status JSON.
- `http://localhost:5050/player.html` opens the browser test player.
- `http://localhost:5050/player` redirects to the test player.
- `http://localhost:5050/hls/master.m3u8` serves the HLS manifest.

Client apps running on another localhost port can use:

```env
VITE_SAMPLE_VIDEO_URL=http://localhost:5050/hls/master.m3u8
```

## Working Rules

- Refer to this file before changing the workspace.
- Do not generate unit tests.
- Do not run unit tests.
- Use the codebase-retrieval tool when available to find project context.
- Do not run the dev/server process unless the user asks.
- For small changes, do not run a build unless the user specifically asks.
