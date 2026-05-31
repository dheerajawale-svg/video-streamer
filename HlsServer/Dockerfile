FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

COPY HlsServer/HlsServer.csproj HlsServer/
RUN dotnet restore HlsServer/HlsServer.csproj

COPY HlsServer/ HlsServer/
RUN dotnet publish HlsServer/HlsServer.csproj -c Release -o /app/publish /p:UseAppHost=false
RUN rm -f /app/publish/appsettings.Development.json

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS final
WORKDIR /app
EXPOSE 5050
ENV ASPNETCORE_URLS=http://+:5050

COPY --from=build /app/publish .
ENTRYPOINT ["dotnet", "HlsServer.dll"]
