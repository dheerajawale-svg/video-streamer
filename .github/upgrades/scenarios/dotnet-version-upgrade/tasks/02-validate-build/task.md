# 02-validate-build: Full validation and testing

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

