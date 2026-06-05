# Changelog

All notable changes to this project will be documented in this file.

## [1.21] - 2026-06-05

### Added
- Native pull-to-refresh support on iOS 15+ by wrapping the main event list in a custom-styled `List` view.
- Support for automatic provisioning profile updates (`-allowProvisioningUpdates`) in deployment scripts.

### Fixed
- Fixed an issue where pull-to-refresh (`.refreshable`) was not triggering on iOS 15 due to SwiftUI limitation on `ScrollView`.
- Hidden the default grey disclosure chevron arrows (`>`) on iOS 15 list rows by implementing a `ZStack` transparent `NavigationLink` overlay, returning boxes to their original width.
- Updated `deploy_trollstore.sh` IP host pointer to `192.168.1.2` for direct iPhone deployments.

## [1.20] - 2025-12-29

### Added
- Added Mac Catalyst target and settings for macOS 12.0+ compatibility.
- Initial deployment scripts for automated TrollStore and iPad compilation.
