using System.Collections.Concurrent;
using Azure.Identity;
using Azure.Storage.Blobs;
using Azure.Storage.Blobs.Models;
using Microsoft.AspNetCore.StaticFiles;

var builder = WebApplication.CreateBuilder(args);

// Configuration from environment
var storageAccountName = Environment.GetEnvironmentVariable("AZURE_STORAGE_ACCOUNT_NAME") ?? "dheerajhospitalsa";
var containerName = Environment.GetEnvironmentVariable("AZURE_STORAGE_CONTAINER_NAME") ?? "hls-vod";
var corsOriginsEnv = Environment.GetEnvironmentVariable("CORS_ALLOWED_ORIGINS") ?? "http://localhost:*";
var corsOrigins = corsOriginsEnv.Split(',').Select(o => o.Trim()).ToArray();

// CORS: allow configured origins so client apps can access HLS streams
builder.Services.AddCors(options =>
{
    options.AddDefaultPolicy(policy =>
    {
        policy
            .WithOrigins(corsOrigins)
            .AllowAnyHeader()
            .AllowAnyMethod();
    });
});

// Azure Blob Storage client using Managed Identity
var blobServiceClient = new BlobServiceClient(
    new Uri($"https://{storageAccountName}.blob.core.windows.net"),
    new DefaultAzureCredential()
);

var containerClient = blobServiceClient.GetBlobContainerClient(containerName);

// In-memory cache for frequently accessed blobs (manifests, VTT)
var blobCache = new ConcurrentDictionary<string, CachedBlob>();
var cacheMaxEntries = 100;

var app = builder.Build();

app.UseCors();

// Custom MIME types for HLS
var mimeProvider = new FileExtensionContentTypeProvider();
mimeProvider.Mappings[".m3u8"] = "application/vnd.apple.mpegurl";
mimeProvider.Mappings[".ts"] = "video/mp2t";
mimeProvider.Mappings[".vtt"] = "text/vtt";

// Helper to get content type
string GetContentType(string path)
{
    if (mimeProvider.TryGetContentType(path, out var contentType))
        return contentType;
    return "application/octet-stream";
}

// Helper to cache and retrieve blobs
async Task<CachedBlob?> GetBlobWithCache(string blobPath)
{
    // Check cache first
    if (blobCache.TryGetValue(blobPath, out var cached))
    {
        // If cached less than 5 minutes ago, return (short cache for manifests/markers)
        if (DateTime.UtcNow - cached.CachedAt.UtcDateTime < TimeSpan.FromMinutes(5))
            return cached;
        else
            blobCache.TryRemove(blobPath, out _);
    }

    try
    {
        var blobClient = containerClient.GetBlobClient(blobPath);
        var download = await blobClient.DownloadAsync();
        
        using var ms = new MemoryStream();
        await download.Value.Content.CopyToAsync(ms);
        var content = ms.ToArray();
        
        var contentType = GetContentType(blobPath);
        var cached_blob = new CachedBlob(content, contentType, DateTimeOffset.UtcNow);
        
        // Keep cache size reasonable (evict oldest if over limit)
        if (blobCache.Count >= cacheMaxEntries)
        {
            var oldest = blobCache.OrderBy(x => x.Value.CachedAt).First();
            blobCache.TryRemove(oldest.Key, out _);
        }
        
        blobCache[blobPath] = cached_blob;
        return cached_blob;
    }
    catch (Azure.RequestFailedException ex) when (ex.Status == 404)
    {
        return null;
    }
}

// Health check endpoint
app.MapGet("/", async () =>
{
    var manifest = await GetBlobWithCache("master.m3u8");
    return Results.Json(new
    {
        service = "HLS Video Streamer (Azure)",
        status = manifest != null ? "healthy" : "degraded",
        region = "Central India",
        storageAccount = storageAccountName,
        hlsUrl = $"/hls/master.m3u8",
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

    var blobPath = path;
    var cached = await GetBlobWithCache(blobPath);
    
    if (cached == null)
    {
        return Results.NotFound();
    }

    context.Response.Headers.Add("Access-Control-Allow-Origin", "*");
    context.Response.Headers.Add("Cache-Control", 
        blobPath.EndsWith(".ts") 
            ? "public, max-age=31536000, immutable"  // Segments are immutable
            : "public, max-age=300");  // Manifests and markers cache shorter
    
    return Results.File(cached.Content, cached.ContentType);
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
    <h1>HLS Video Streamer - Central India</h1>
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
Console.WriteLine($"  Region: Central India");
Console.WriteLine($"  Storage: {storageAccountName}/{containerName}");
Console.WriteLine($"  CORS Origins: {string.Join(", ", corsOrigins)}");
Console.WriteLine($"  Listen: http://+:5050");

app.Run("http://+:5050");

record CachedBlob(byte[] Content, string ContentType, DateTimeOffset CachedAt);
