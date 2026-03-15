# Context Handover — Configurable Hotkey Shortcuts UI

**Session Date:** 2026-03-15
**Repository:** muesli
**Branch:** `main`

---

## Task

Build a "Shortcuts" page as the third sidebar tab (after Dictations, Meetings) that lets users configure which hotkey triggers dictation. Currently hardcoded to Left Cmd hold (key code 55). WisprFlow has this feature — see screenshot in the conversation for reference design.

## Current Implementation

### HotkeyMonitor.swift
- `native/MuesliNative/Sources/MuesliNativeApp/HotkeyMonitor.swift`
- **Hardcoded**: Left Cmd = key code 55 (line 88: `if keyCode == 55`)
- Two-stage activation: 150ms → `onPrepare`, 250ms → `onStart`
- Cancels if another key is pressed while Cmd held (keyboard shortcut detection)
- Uses `NSEvent.addGlobalMonitorForEvents` and `NSEvent.addLocalMonitorForEvents`

### AppConfig (Models.swift)
- `native/MuesliNative/Sources/MuesliNativeApp/Models.swift`
- Has `var hotkey: String = "left_command_hold"` field already — but it's never read by HotkeyMonitor

### DashboardTab (AppState.swift)
- `native/MuesliNative/Sources/MuesliNativeApp/AppState.swift`
- Current tabs: `.dictations`, `.meetings`, `.settings`
- Need to add `.shortcuts` case

### SidebarView.swift
- `native/MuesliNative/Sources/MuesliNativeApp/SidebarView.swift`
- Current sidebar items: Dictations (mic icon), Meetings (person.2 icon), Settings (gear icon)
- Add Shortcuts row (keyboard icon) as third item (before Settings)

## Implementation Plan

### 1. Add `.shortcuts` tab to DashboardTab
**File:** `AppState.swift`
- Add `case shortcuts` to `DashboardTab` enum

### 2. Add Shortcuts row to SidebarView
**File:** `SidebarView.swift`
- Add row with `keyboard` SF Symbol between Meetings and Settings
- Wire to `.shortcuts` tab

### 3. Route to ShortcutsView in DashboardRootView
**File:** `DashboardRootView.swift`
- Add `case .shortcuts: ShortcutsView(appState:controller:)`

### 4. Create ShortcutsView.swift (new file)
**File:** `native/MuesliNative/Sources/MuesliNativeApp/ShortcutsView.swift`

Design (matching WisprFlow screenshot):
```
Shortcuts
Choose your preferred shortcuts for using Muesli.

┌─────────────────────────────────────────────────┐
│ Push to talk                                    │
│ Hold to say something short           [Left Cmd]│
│                                                 │
│ [Change hotkey]                                 │
└─────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────┐
│ Start/Stop Meeting                              │
│ Toggle meeting recording              [  ⌘ M  ]│
│                                                 │
│ [Change hotkey]                                 │
└─────────────────────────────────────────────────┘

                [Reset to defaults]
```

The hotkey recorder component:
- When "Change hotkey" is clicked, field enters recording mode ("Press a key...")
- Captures the next `NSEvent.keyDown` or `NSEvent.flagsChanged`
- Displays the captured key combo (e.g., "Left Cmd", "Fn", "⌘ + Shift + D")
- Saves to AppConfig

### 5. Define hotkey configuration in AppConfig
**File:** `Models.swift`

Replace the single `hotkey` string with structured config:
```swift
struct HotkeyConfig: Codable {
    var keyCode: UInt16 = 55       // Left Cmd
    var modifiers: UInt = 0        // NSEvent.ModifierFlags raw value
    var mode: String = "hold"      // "hold" (push-to-talk) or "toggle" (hands-free)
    var label: String = "Left Cmd" // Display name
}
```

Add to AppConfig:
```swift
var dictationHotkey: HotkeyConfig = HotkeyConfig()
var meetingHotkey: HotkeyConfig? = nil  // Optional, nil = no shortcut
```

### 6. Update HotkeyMonitor to use configurable key code
**File:** `HotkeyMonitor.swift`

Change `if keyCode == 55` to read from config:
```swift
private var targetKeyCode: UInt16 = 55

func configure(keyCode: UInt16) {
    self.targetKeyCode = keyCode
    restart() // re-register monitors
}
```

Update `handleFlagsChanged` to use `targetKeyCode` instead of hardcoded 55.

### 7. Wire configuration changes
**File:** `MuesliController.swift`

When user changes hotkey in ShortcutsView:
- Save to config via `updateConfig`
- Call `hotkeyMonitor.configure(keyCode:)` to apply immediately

## Key Considerations

- **Modifier keys only (Left Cmd, Right Cmd, Fn, Ctrl, Option, Shift)**: These work as "hold to talk" triggers. Regular keys (A-Z) would conflict with typing.
- **Key code mapping**: `NSEvent.keyCode` values — Left Cmd=55, Right Cmd=54, Fn=63, Left Ctrl=59, Right Ctrl=62, Left Option=58, Right Option=61, Left Shift=56, Right Shift=60
- **Conflict detection**: Warn if the chosen key conflicts with common system shortcuts
- **Hands-free mode (future)**: WisprFlow has "toggle" mode (press once to start, press again to stop). Our current architecture only supports "hold" mode. The toggle mode would need VAD to auto-stop when speech ends.
- **Meeting shortcut (optional)**: Could add a keyboard shortcut to toggle meeting recording (e.g., ⌘+M). Currently only available via menu bar and floating indicator.

## Files to Create
| File | Purpose |
|---|---|
| `ShortcutsView.swift` | New SwiftUI view for hotkey configuration |

## Files to Modify
| File | Change |
|---|---|
| `AppState.swift` | Add `.shortcuts` to `DashboardTab` |
| `SidebarView.swift` | Add Shortcuts row |
| `DashboardRootView.swift` | Route `.shortcuts` to `ShortcutsView` |
| `Models.swift` | Add `HotkeyConfig` struct, update `AppConfig` |
| `HotkeyMonitor.swift` | Make key code configurable |
| `MuesliController.swift` | Wire config changes to HotkeyMonitor |

## Reference
- WisprFlow shortcuts UI: See screenshot in conversation (push-to-talk with Fn key, hands-free with Mouse 5 / Cmd+Option)
- Current hotkey: Left Cmd hold, key code 55, defined at `HotkeyMonitor.swift:88`
