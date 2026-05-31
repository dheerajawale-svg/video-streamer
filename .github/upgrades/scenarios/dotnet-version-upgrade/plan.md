# .NET Version Upgrade Plan

## Target
- **Current Framework**: .NET 8.0
- **Target Framework**: .NET 10.0 (LTS)
- **Project**: HlsServer

## Strategy
**All-at-Once**: Single atomic upgrade of the entire project.

## Assessment Summary
- **Complexity**: Low
- **Projects**: 1 (SDK-style)
- **Packages**: 1 (Azure.Storage.Blobs 12.28.0 — compatible)
- **API Issues**: 1 (System.Uri behavioral change — low impact)
- **LOC Impact**: ~0.5% (minimal code changes expected)

## Upgrade Plan

### 01-update-tfm: Update target framework to .NET 10.0

Update HlsServer.csproj to target the new framework version. This is the primary change needed for the upgrade. The project currently targets .NET 8.0 (net8.0) and must be updated to .NET 10.0 (net10.0).

**Affected Projects**: HlsServer.csproj

**Assessment Context**: 
- No incompatible packages detected
- One behavioral change in System.Uri (low impact)
- 280 compatible APIs analyzed

**Known Risks**:
- System.Uri behavioral change may affect URL parsing in HLS streaming context
- Requires runtime validation

**Done when**:
- [ ] HlsServer.csproj updated to `<TargetFramework>net10.0</TargetFramework>`
- [ ] Solution builds without errors
- [ ] All warnings addressed
- [ ] System.Uri behavior verified through testing

### 02-validate-build: Full validation and testing

Validate that all components work correctly with .NET 10. Run the build to ensure no unexpected breaking changes, execute any existing unit tests, and verify Azure.Storage.Blobs integration.

**Affected Projects**: HlsServer.csproj

**Assessment Context**:
- Azure.Storage.Blobs 12.28.0 is compatible with .NET 10
- No code migration challenges expected

**Known Risks**:
- Runtime behavioral changes may not be caught by compilation
- HLS streaming functionality needs validation

**Done when**:
- [ ] Full solution builds without warnings
- [ ] All tests pass (if tests exist)
- [ ] HLS server functionality verified with .NET 10
- [ ] No blocking issues remain
