# .NET Version Upgrade to .NET 10

## Preferences
- **Flow Mode**: Automatic
- **Target Framework**: net10.0 (LTS)

## Source Control
- **Source Branch**: cloud-stream
- **Working Branch**: dotnet-upgrade-net10
- **Commit Strategy**: After Each Task

## Strategy
**Selected**: All-at-Once  
**Rationale**: Single SDK-style project on modern .NET with no incompatible packages or architectural dependencies.

### Execution Constraints
- Single atomic upgrade of project target framework
- Full solution build validation after TFM update
- System.Uri behavioral change requires runtime testing
- No multi-project ordering or phasing needed

## Key Decisions Log
- **Target**: .NET 10.0 LTS (May 2031 EOL) selected over .NET 9.0 STS
- **Strategy**: All-at-Once (single project, straightforward)
- **Scope**: Upgrade HlsServer project target framework
- **Date**: 2025-01-15
