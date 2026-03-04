# Diagnostics Bundle Versioning

This diagnostics bundle follows Semantic Versioning (`MAJOR.MINOR.PATCH`).

- **MAJOR**: incompatible output format changes (telemetry schema, RESULT contract).
- **MINOR**: backward-compatible new checks/verifiers/signatures.
- **PATCH**: bug fixes and safe script-level improvements.

Release process requires a bump to `bundle_version.txt` and corresponding `CHANGELOG.md` entry.
