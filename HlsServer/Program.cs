using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.StaticFiles;

var builder = WebApplication.CreateBuilder(args);

var app = builder.Build();

// Custom MIME types for HLS
var mimeProvider = new FileExtensionContentTypeProvider();
mimeProvider.Mappings[".m3u8"] = "application/vnd.apple.mpegurl";
mimeProvider.Mappings[".ts"] = "video/mp2t";
mimeProvider.Mappings[".vtt"] = "text/vtt";

var localVideoRoot = Path.GetFullPath(Path.Combine(builder.Environment.ContentRootPath, "..", "public", "local-video"));

string GetContentType(string path) =>
    mimeProvider.TryGetContentType(path, out var contentType) ? contentType : "application/octet-stream";

// Health check endpoint
app.MapGet("/", () =>
{
    var manifestPath = Path.Combine(localVideoRoot, "master.m3u8");
    var manifestExists = File.Exists(manifestPath);

    return Results.Json(new
    {
        service = "HLS Video Streamer (Local)",
        status = manifestExists ? "healthy" : "degraded",
        mode = "local-filesystem",
        localRoot = localVideoRoot,
        hlsUrl = "/hls/master.m3u8",
        playerUrl = "/player.html",
        markersUrl = "/hls/eeg-markers.vtt",
        variants = new[] { "240p", "360p", "480p", "720p", "1080p" },
        timestamp = DateTime.UtcNow
    });
});

// HLS streaming endpoint: /hls/{path}
app.MapGet("/hls/{**path}", async (string path, HttpContext context) =>
{
    if (string.IsNullOrEmpty(path))
    {
        return Results.BadRequest("Path required");
    }

    // Security: prevent directory traversal
    if (path.Contains("..") || path.StartsWith("/"))
    {
        return Results.BadRequest("Invalid path");
    }

    var filePath = Path.GetFullPath(Path.Combine(localVideoRoot, path.Replace('/', Path.DirectorySeparatorChar)));

    if (!filePath.StartsWith(localVideoRoot, StringComparison.OrdinalIgnoreCase))
    {
        return Results.BadRequest("Invalid path");
    }

    if (!File.Exists(filePath))
    {
        return Results.NotFound();
    }

    var contentType = GetContentType(filePath);
    context.Response.Headers["Access-Control-Allow-Origin"] = "*";
    context.Response.Headers.Add("Cache-Control", 
        filePath.EndsWith(".ts", StringComparison.OrdinalIgnoreCase)
            ? "public, max-age=31536000, immutable"
            : "public, max-age=300");

    return Results.File(filePath, contentType);
});

// Static player HTML
app.MapGet("/player", () => Results.Redirect("/player.html"));
app.MapGet("/player.html", async (HttpContext context) =>
{
    var playerPath = Path.Combine(builder.Environment.ContentRootPath, "wwwroot", "player.html");
    
    if (System.IO.File.Exists(playerPath))
    {
        var content = await System.IO.File.ReadAllTextAsync(playerPath);
        return Results.Content(content, "text/html");
    }
    
    // Fallback: serve a minimal player
    var minimalPlayer = @"
<!DOCTYPE html>
<html>
<head>
    <title>HLS Video Player</title>
    <meta charset='utf-8'>
    <meta name='viewport' content='width=device-width, initial-scale=1'>
    <script src='https://cdn.jsdelivr.net/npm/hls.js@latest'></script>
    <style>
        body { margin: 0; padding: 20px; background: #000; color: #fff; font-family: Arial; }
        #video { width: 100%; max-width: 1280px; height: auto; background: #000; }
        #info { color: #aaa; font-size: 12px; margin-top: 10px; }
    </style>
</head>
<body>
    <h1>HLS Video Streamer - Local</h1>
    <video id='video' controls style='width: 100%; max-width: 1280px;'></video>
    <div id='info'></div>
    <script>
        const video = document.getElementById('video');
        const info = document.getElementById('info');
        const hlsUrl = '/hls/master.m3u8';
        
        if(Hls.isSupported()) {
            const hls = new Hls();
            hls.loadSource(hlsUrl);
            hls.attachMedia(video);
            hls.on(Hls.Events.MANIFEST_PARSED, () => {
                info.textContent = 'HLS manifest loaded. Available qualities: ' + 
                    hls.levels.map(l => l.height + 'p').join(', ');
            });
        } else if(video.canPlayType('application/vnd.apple.mpegurl')) {
            video.src = hlsUrl;
        }
    </script>
</body>
</html>";
    
    return Results.Content(minimalPlayer, "text/html");
});

// Serve wwwroot static files as fallback
app.UseDefaultFiles();
app.UseStaticFiles();

Console.WriteLine($"HLS Streamer starting...");
Console.WriteLine($"  Mode: Local filesystem");
Console.WriteLine($"  Local root: {localVideoRoot}");
Console.WriteLine($"  Listen: http://+:5050");

app.Run("http://+:5050");
