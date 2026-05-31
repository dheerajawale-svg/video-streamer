# 02-validate-build: Full validation and testing

Validate that all components work correctly with .NET 10. Run the build to ensure no unexpected breaking changes, execute any existing unit tests, and verify Azure.Storage.Blobs integration. This is the final validation task after the framework upgrade.

**Affected Projects**: HlsServer.csproj

**Assessment Context**:
- Azure.Storage.Blobs 12.28.0 is compatible with .NET 10
- No code migration challenges expected
- System.Uri behavioral change identified (low impact, needs runtime validation)
- 280 APIs analyzed, all compatible

**Validation Scope**:
1. Full solution build with warnings check
2. Test execution (if any tests exist)
3. Runtime validation of HLS streaming functionality
4. Package integration verification (Azure.Storage.Blobs)

**Known Risks**:
- Runtime behavioral changes may not be caught by compilation
- System.Uri URL parsing may behave differently in .NET 10
- HLS streaming functionality needs validation

**Done when**:
- [ ] Full solution builds without errors or warnings
- [ ] All tests pass (if tests exist)
- [ ] HLS server can start and handle requests with .NET 10
- [ ] No blocking issues remain
- [ ] System.Uri behavior verified (code review or manual testing)

## Research Summary

**Task Strategy**:
1. Execute full solution build (not just project build) to catch any transitive issues
2. Run test suite if available
3. Perform manual/runtime validation of HLS streaming server
4. Verify package compatibility at runtime

**Build Tool**: Use `dotnet build` for full solution (SDK-style, modern .NET)

**Prior State**: Task 01 successfully updated TargetFramework to net10.0; project builds individually. This task validates full solution and integration.

