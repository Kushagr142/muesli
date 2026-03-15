# Context Handover — Post-Notarization OTA Update via Sparkle

**Session Date:** 2026-03-15
**Repository:** muesli
**Branch:** `main`
**Prerequisite:** App must be notarized before implementing this.

---

## Task

Add over-the-air (OTA) auto-update capability using the Sparkle framework so users receive new versions without manual reinstallation.

## What Sparkle Provides

- Update check (manual + automatic on schedule)
- Download progress dialog with release notes
- Signature verification (EdDSA)
- App replacement + relaunch
- Delta updates (only download changed bytes between versions)

## Implementation Plan

### 1. Add Sparkle dependency

**File:** `native/MuesliNative/Package.swift`

```swift
dependencies: [
    .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
],
targets: [
    .executableTarget(
        name: "MuesliNativeApp",
        dependencies: [
            .product(name: "Sparkle", package: "Sparkle"),
        ],
        // ...
    ),
]
```

### 2. Generate EdDSA signing key pair

```bash
# One-time setup — store private key securely, never commit it
./native/MuesliNative/.build/checkouts/Sparkle/bin/generate_keys
# Outputs: private key (save to Keychain) + public key (embed in app)
```

### 3. Add to Info.plist

**File:** `scripts/build_native_app.sh` (in the Info.plist heredoc)

```xml
<key>SUFeedURL</key>
<string>https://pHequals7.github.io/muesli/appcast.xml</string>
<key>SUPublicEDKey</key>
<string>YOUR_PUBLIC_EDKEY_HERE</string>
```

### 4. Initialize Sparkle updater in AppDelegate

**File:** `native/MuesliNative/Sources/MuesliNativeApp/AppDelegate.swift`

```swift
import Sparkle

private var updaterController: SPUStandardUpdaterController?

func applicationDidFinishLaunching(_ notification: Notification) {
    updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )
    // ... existing setup
}
```

### 5. Add "Check for Updates" to StatusBarController menu

**File:** `native/MuesliNative/Sources/MuesliNativeApp/StatusBarController.swift`

Add before the Quit item:
```swift
menu.addItem(actionItem(title: "Check for Updates…", action: #selector(MuesliController.checkForUpdates)))
```

**File:** `native/MuesliNative/Sources/MuesliNativeApp/MuesliController.swift`

```swift
@objc func checkForUpdates() {
    updaterController?.checkForUpdates(nil)
}
```

### 6. Add update settings to SettingsView

**File:** `native/MuesliNative/Sources/MuesliNativeApp/SettingsView.swift`

New "Updates" section:
```
Updates
  Automatically check for updates    [toggle]
  Current version: 0.2.0
  [Check for Updates]
```

- Toggle binds to `updater.automaticallyChecksForUpdates`
- Version reads from `Bundle.main.infoDictionary?["CFBundleShortVersionString"]`
- Button calls `updater.checkForUpdates(nil)`

### 7. Create appcast hosting

**Option A: GitHub Pages**
- Create `docs/appcast.xml` in repo
- Enable GitHub Pages on `docs/` folder
- URL: `https://pHequals7.github.io/muesli/appcast.xml`

**Option B: GitHub Releases**
- Upload signed `.dmg` to GitHub Releases
- Point appcast to release asset URLs

### 8. Release workflow

For each new version:
```bash
# 1. Bump version in build_native_app.sh
# 2. Build + bundle + sign + notarize
./scripts/bundle_python.sh
./scripts/build_native_app.sh
# 3. Create signed DMG
hdiutil create -volname Muesli -srcfolder /Applications/Muesli.app -ov Muesli-v0.3.0.dmg
# 4. Sign the update with Sparkle's EdDSA key
./Sparkle/bin/sign_update Muesli-v0.3.0.dmg
# 5. Update appcast.xml with new version + signature + download URL
# 6. Push appcast.xml to GitHub Pages
# 7. Upload DMG to GitHub Releases
```

## Delta Updates

Sparkle supports binary delta updates — instead of re-downloading the full 230MB app, users download only the changed files (~2-5MB for typical code changes). This requires:
- Keeping the previous version's `.dmg` available
- Running `generate_appcast` tool which computes deltas automatically

This is critical for Muesli because the bundled Python runtime (207MB) rarely changes between updates. Only the Swift binary (~1MB) and Python scripts change.

## Key Considerations

- **Sparkle requires hardened runtime + notarization** — the update verification chain won't work without it
- **Bundled Python runtime increases update size** — delta updates are essential
- **EdDSA private key must be secured** — store in macOS Keychain, never commit to git
- **appcast.xml versioning** — use `CFBundleVersion` (build number) for comparison, `CFBundleShortVersionString` for display
- **Sandboxing**: Muesli is not sandboxed, so Sparkle's standard (non-XPC) mode works fine

## Files to Create
| File | Purpose |
|---|---|
| `docs/appcast.xml` | Update feed hosted on GitHub Pages |

## Files to Modify
| File | Change |
|---|---|
| `Package.swift` | Add Sparkle dependency |
| `AppDelegate.swift` | Initialize `SPUStandardUpdaterController` |
| `MuesliController.swift` | Add `checkForUpdates()` method, hold updater reference |
| `StatusBarController.swift` | Add "Check for Updates…" menu item |
| `SettingsView.swift` | Add "Updates" section with toggle + version + button |
| `build_native_app.sh` | Add `SUFeedURL` and `SUPublicEDKey` to Info.plist |
