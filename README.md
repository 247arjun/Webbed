# Webbed

Cross-platform synced browser — macOS / iPadOS / iOS. Built on `WKWebView`
with no third-party dependencies.

See [plan.md](plan.md) for the full engineering spec.

## Build

```sh
brew install xcodegen          # one-time
xcodegen generate              # regenerates Webbed.xcodeproj from project.yml
open Webbed.xcodeproj
```

Or from the command line:

```sh
xcodebuild -scheme Webbed     -configuration Debug -destination 'platform=macOS'            build
xcodebuild -scheme WebbediOS  -configuration Debug -destination 'generic/platform=iOS Simulator' build
```

The default checkout uses ad-hoc signing (`-` identity) so the project
builds without any developer account configuration.

## iCloud Sync (Phase 5)

iCloud-backed sync is implemented but the entitlement keys are commented
out in the `.entitlements` files so ad-hoc-signed builds work out of the
box. To turn iCloud sync on:

1. Copy `Configs/Signing.local.xcconfig.example` →
   `Configs/Signing.local.xcconfig` and fill in your `DEVELOPMENT_TEAM`.
2. Uncomment the `com.apple.developer.icloud-*` blocks in both
   `Webbed/Resources/Webbed.entitlements` and
   `WebbediOS/Resources/WebbediOS.entitlements`.
3. Uncomment the matching `NSUbiquitousContainers` block in both
   `Info.plist` files.
4. Re-run `xcodegen generate` and build.

Once configured, the `iCloudChangeObserver` in `WebbedKit` picks up
external `<uuid>.json` updates in the Webbed ubiquity container and
patches them into the in-memory `TabStore`.
