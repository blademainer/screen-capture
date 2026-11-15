# GitHub Actions Release Implementation Plan

**Goal:** Test and package pushes and pull requests, publish successful `v*` tags to GitHub Releases, and commit and push the configuration.

**Architecture:** Use the existing Swift package for tests and both release architectures. One macOS job uploads ZIP, DMG, checksums, and test logs; a separate tag-only job publishes those exact packages with scoped write permission.

**Constraints:** macOS 15 minimum; stable bundle identifier `com.blademainer.MacScreenCapture`; arm64 and x86_64; ad-hoc signing only, no Developer ID credentials or notarization. Manual dispatch builds artifacts without creating a release.

## Implementation

- [x] Replace the stale Xcode release script with fail-fast Swift package builds, universal binary assembly, staged bundle versioning, ad-hoc verification, ZIP, DMG, and SHA-256 checksums.
- [x] Replace the existing tag-only workflow with push/PR/manual CI and tag-only publication after successful tests and packaging. Keep repository write permission only in the publication job.
- [x] Update the existing universal-build regression check and release documentation to match the actual build interface and signing limitations.

## Verification

- [x] Validate shell/workflow syntax and reject invalid package arguments before building.
- [x] Run all Swift tests and the real universal packaging script; verify both binary slices, resources, bundle metadata, code signature, extracted ZIP, mounted DMG, and checksums.
- [x] Install the verified app at `/Applications/MacScreenCapture.app` for local use.
- [ ] Commit and push to `main`, then inspect the triggered GitHub Actions run and downloaded artifacts. Do not invent a release tag without user approval.

## Review Focus

- Failed tests or builds must prevent publication.
- Branch pushes and manual dispatch must never create releases.
- Prerelease tags must not become the latest stable release.
- Source plist must remain unchanged by packaging.
- Fork PR jobs must not receive repository write permission or signing credentials.
