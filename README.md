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

iCloud-backed sync is **enabled** by default. Both targets ship with the
`com.apple.developer.icloud-container-identifiers`,
`com.apple.developer.icloud-services` (`CloudDocuments`) and
`com.apple.developer.ubiquity-container-identifiers` entitlements
pointing at `iCloud.com.arjun.Webbed`, and the matching
`NSUbiquitousContainers` block in each `Info.plist` so the container
surfaces as "Webbed" in iCloud Drive / the Files app.

Requirements for sync to actually flow:

1. A real `DEVELOPMENT_TEAM` in `Configs/Signing.local.xcconfig` (copy
   from `Signing.local.xcconfig.example`).
2. The `iCloud.com.arjun.Webbed` container registered against that team
   (Xcode → Signing & Capabilities → iCloud, or
   developer.apple.com → Identifiers → iCloud Containers).
3. Both devices signed into the same iCloud account with iCloud Drive
   enabled.

When `StorageLocationResolver.iCloudAvailable` is true,
`AppSettings.syncWithICloud` defaults to `true` and
`effectiveSaveDirectory` resolves to the ubiquity container's
`Documents/` folder. The `iCloudChangeObserver` in `WebbedKit` then
picks up external `<uuid>.json` updates via `NSMetadataQuery` and
patches them into the in-memory `TabStore`.

If you need to build a fresh clone with **no Apple Developer account**,
re-comment the `com.apple.developer.icloud-*` keys in both
`*.entitlements` files (and the `NSUbiquitousContainers` blocks in the
`Info.plist`s) and re-run `xcodegen generate` — the app will fall back
to the local sandbox container automatically.
