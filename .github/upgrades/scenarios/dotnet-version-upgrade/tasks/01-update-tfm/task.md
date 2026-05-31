# 01-update-tfm: Update target framework to .NET 10.0

Update HlsServer.csproj to target the new framework version. This is the primary change needed for the upgrade. The project currently targets .NET 8.0 (net8.0) and must be updated to .NET 10.0 (net10.0).

**Affected Projects**: HlsServer.csproj (1 file)

**Assessment Context**: 
- No incompatible packages detected
- One behavioral change in System.Uri (low impact, only 1 API affected)
- 280 compatible APIs analyzed
- Azure.Storage.Blobs 12.28.0 is fully compatible with .NET 10
- SDK-style project (simple conversion)
- 210 lines of code, 4 files

**Project Details**:
- **Current TFM**: net8.0 (single-targeted)
- **Target TFM**: net10.0 (single-targeted, no multi-targeting needed)
- **Package state**: Azure.Storage.Blobs 12.28.0 (no version bump required)
- **File location**: C:\natus\video-streamer\HlsServer\HlsServer.csproj
- **Project type**: ASP.NET Core Web project

**Known Risks**:
- System.Uri behavioral change may affect URL parsing in HLS streaming context
- Requires runtime validation of HLS streaming functionality after upgrade

**Done when**:
- [ ] HlsServer.csproj updated from `<TargetFramework>net8.0</TargetFramework>` to `<TargetFramework>net10.0</TargetFramework>`
- [ ] Solution builds without errors or warnings
- [ ] All tests pass (if any exist)
- [ ] System.Uri behavior verified through testing or code review

## Research Summary

**Project File Analysis**:
- File is SDK-style: `<Project Sdk="Microsoft.NET.Sdk.Web">`
- Single TargetFramework property (no multi-targeting needed)
- Nullable enabled, ImplicitUsings enabled
- Only one package reference: Azure.Storage.Blobs 12.28.0 (compatible)
- No custom build targets or complex properties

**API Impact Assessment**:
- System.Uri is used somewhere in the project (1 instance detected in assessment)
- URL parsing behavior may differ between .NET 8 and .NET 10
- This is the only behavioral change identified; no breaking changes

**Build Tool Decision**: Use `dotnet build` (SDK-style, modern .NET only, no special resources)

