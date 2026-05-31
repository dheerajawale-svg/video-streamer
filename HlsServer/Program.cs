using Azure;
using Azure.Storage.Blobs;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.StaticFiles;

var builder = WebApplication.CreateBuilder(args);

var azureConfig = builder.Configuration.GetSection("AzureStorage");
var connectionString = azureConfig["ConnectionString"]
    ?? throw new InvalidOperationException("AzureStorage:ConnectionString is required");
var containerName = azureConfig["Container"]
    ?? throw new InvalidOperationException("AzureStorage:Container is required");
var blobPrefix = azureConfig["BlobPrefix"] ?? string.Empty;
if (blobPrefix.Length > 0 && !blobPrefix.EndsWith('/'))
{
    blobPrefix += "/";
}

builder.Services.AddSingleton(_ => new BlobContainerClient(connectionString, containerName));

var app = builder.Build();

// Custom MIME types for HLS
var mimeProvider = new FileExtensionContentTypeProvider();
mimeProvider.Mappings[".m3u8"] = "application/vnd.apple.mpegurl";
mimeProvider.Mappings[".ts"] = "video/mp2t";
mimeProvider.Mappings[".vtt"] = "text/vtt";

string GetContentTypeFromMap(string path) =>
    mimeProvider.TryGetContentType(path, out var contentType) ? contentType : "application/octet-stream";

// Health check endpoint
app.MapGet("/", async (BlobContainerClient container) =>
{
    bool containerExists = false;
    bool manifestExists = false;
    string? error = null;

    try
    {
        containerExists = await container.ExistsAsync();
        if (containerExists)
        {
            manifestExists = await container.GetBlobClient(blobPrefix + "master.m3u8").ExistsAsync();
        }
    }
    catch (RequestFailedException ex)
    {
        error = ex.ErrorCode ?? ex.Message;
    }

    return Results.Json(new
    {
        service = "HLS Video Streamer (Azure Blob)",
        status = (containerExists && manifestExists) ? "healthy" : "degraded",
        mode = "cloud-storage",
        container = containerName,
        blobPrefix,
        accountUri = container.Uri.ToString(),
        containerExists,
        manifestExists,
        error,
        hlsUrl = "/hls/master.m3u8",
        playerUrl = "/player.html",
        markersUrl = "/hls/eeg-markers.vtt",
        variants = new[] { "240p", "360p", "480p", "720p", "1080p" },
        timestamp = DateTime.UtcNow
    });
});

// HLS streaming endpoint: /hls/{path} -> blob: {blobPrefix}{path}
app.MapMethods("/hls/{**path}", new[] { "GET", "HEAD" }, async (string? path, HttpContext context, BlobContainerClient container, ILoggerFactory loggerFactory) =>
{
    var log = loggerFactory.CreateLogger("Hls");

    if (string.IsNullOrEmpty(path))
    {
        return Results.BadRequest("Path required");
    }

    // Normalize separators and validate to prevent traversal / absolute paths
    var normalized = path.Replace('\\', '/').Trim('/');
    while (normalized.Contains("//", StringComparison.Ordinal))
    {
        normalized = normalized.Replace("//", "/");
    }
    if (normalized.Length == 0 || normalized.Split('/').Any(s => s == ".." || s == "."))
    {
        return Results.BadRequest("Invalid path");
    }

    var blobName = blobPrefix + normalized;
    var blobClient = container.GetBlobClient(blobName);

    try
    {
        if (HttpMethods.IsHead(context.Request.Method))
        {
            var props = await blobClient.GetPropertiesAsync();
            WriteHlsHeaders(context.Response, normalized, props.Value.ContentType, props.Value.ContentLength);
            return Results.Empty;
        }

        var download = await blobClient.DownloadStreamingAsync();
        // Set headers only AFTER a successful download so 404/5xx responses
        // never inherit the long-lived Cache-Control intended for segments.
        WriteHlsHeaders(context.Response, normalized, download.Value.Details.ContentType, download.Value.Details.ContentLength);
        using var payload = download.Value;
        await payload.Content.CopyToAsync(context.Response.Body, context.RequestAborted);
        return Results.Empty;
    }
    catch (RequestFailedException ex) when (ex.Status == 404)
    {
        log.LogWarning("Blob not found: {Blob}", blobName);
        return Results.NotFound();
    }
    catch (OperationCanceledException) when (context.RequestAborted.IsCancellationRequested)
    {
        return Results.Empty;
    }
    catch (RequestFailedException ex)
    {
        log.LogError(ex, "Azure error fetching {Blob}: {Status} {Code}", blobName, ex.Status, ex.ErrorCode);
        return Results.Problem(detail: ex.Message, statusCode: ex.Status);
    }
});

void WriteHlsHeaders(HttpResponse response, string normalizedPath, string? blobContentType, long contentLength)
{
    if (response.HasStarted) return;

    var resolved = !string.IsNullOrWhiteSpace(blobContentType) && blobContentType != "application/octet-stream"
        ? blobContentType!
        : GetContentTypeFromMap(normalizedPath);

    response.ContentType = resolved;
    response.ContentLength = contentLength;
    response.Headers["Access-Control-Allow-Origin"] = "*";
    response.Headers["Access-Control-Expose-Headers"] = "Content-Length, Content-Range, Date";
    response.Headers["Cache-Control"] = normalizedPath.EndsWith(".ts", StringComparison.OrdinalIgnoreCase)
        ? "public, max-age=31536000, immutable"
        : "public, max-age=30";
}

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
Console.WriteLine($"  Mode: Cloud storage (Azure Blob)");
Console.WriteLine($"  Container: {containerName}");
Console.WriteLine($"  Blob prefix: {blobPrefix}");
Console.WriteLine($"  Listen: http://+:5050");

app.Run("http://+:5050");
