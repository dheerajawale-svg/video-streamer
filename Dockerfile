# Multi-stage build for HLS Video Streamer
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build

WORKDIR /src

# Copy project files
COPY ["HlsServer/HlsServer.csproj", "HlsServer/"]
RUN dotnet restore "HlsServer/HlsServer.csproj"

# Copy application code
COPY ["HlsServer/", "HlsServer/"]
COPY ["HlsServer/wwwroot/", "HlsServer/wwwroot/"]

WORKDIR "/src/HlsServer"
RUN dotnet build "HlsServer.csproj" -c Release -o /app/build

# Publish stage
FROM build AS publish
RUN dotnet publish "HlsServer.csproj" -c Release -o /app/publish /p:UseAppHost=false

# Runtime stage
FROM mcr.microsoft.com/dotnet/aspnet:8.0-alpine

WORKDIR /app
COPY --from=publish /app/publish .
COPY HlsServer/wwwroot ./wwwroot

# Create non-root user
RUN addgroup -g 1001 -S appgroup && \
    adduser -u 1001 -S appuser -G appgroup

USER appuser

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget -q -O- http://localhost:5050/ || exit 1

EXPOSE 5050

ENTRYPOINT ["dotnet", "HlsServer.dll"]
