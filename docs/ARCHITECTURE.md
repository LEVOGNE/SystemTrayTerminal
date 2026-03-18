# quickTerminal — Architecture & Developer Notes

## Overview

Single-file macOS menu-bar terminal emulator (`quickTerminal.swift`, ~16 500 lines).
No external dependencies — only Cocoa + Carbon frameworks.

---

## Build Pipeline

| Script | Purpose |
|--------|---------|
| `bash build.sh` | Local test build (fast `swiftc`) + runs `swift tests.swift` |
| `bash build_app.sh` | Creates `.app` bundle with icon, fonts, shell configs |
| `bash build_zip.sh` | Packs `.app` + `install.sh` + `FIRST_READ.txt` → `quickTerminal.zip` |

**VERSION** must be kept in sync: `kAppVersion` (Swift) + all 3 build scripts.

---

## Key Architecture

- **VT100/VT220/xterm parser**: 13-state FSM in `Terminal` class
- **Rendering**: `TerminalView` (NSView), direct CGContext drawing at 60 fps
- **Menu-bar app**: no dock icon, global hotkey `Ctrl+<`
- **Alternate screen**: `terminal.altGrid`
- **Mouse tracking**: `terminal.mouseMode` (0/1000/1002/1003), `terminal.mouseEncoding` (0/1005/1006)

---

## Tab System

AppDelegate maintains **parallel arrays** — all must stay in sync at every insert/remove/reorder:

| Array | Type | Purpose |
|-------|------|---------|
| `termViews` | `[TerminalView?]` | `nil` for editor tabs |
| `splitContainers` | `[SplitContainer]` | placeholder for editor tabs |
| `tabTypes` | `[TabType]` | `.terminal` / `.editor` |
| `tabEditorViews` | `[EditorView?]` | `nil` for terminal tabs |
| `tabEditorURLs` | `[URL?]` | open file URL per editor tab |
| `tabEditorDirty` | `[Bool]` | unsaved changes flag |
| `tabEditorModes` | `[EditorInputMode]` | `.normal` / `.nano` / `.vim` |
| `tabColors` | `[NSColor]` | tab indicator color |
| `tabCustomNames` | `[String?]` | user-renamed tab labels |
| `tabGitPositions` | `[GitPanelPosition]` | git panel position per tab |
| `tabGitPanels` | `[GitPanelView?]` | git panel view per tab |
| `tabGitDividers` | `[NSView?]` | divider view per tab |
| `tabGitRatios*` | `[CGFloat]` | panel size ratios |

**CRITICAL**: `reorderTab(from:to:)` must reorder **all** arrays. Missing one = index desync = crash.

---

## Window Positioning — SEALED LOGIC (do not change!)

### Root Cause

macOS places status-bar items **asynchronously** after launch (~150 ms). During that time
`convertToScreen` on the status-bar button returns bogus coordinates in two ways:

1. `y ≈ -11` — button not yet in a real screen window
2. `x ≈ far-right` — item temporarily at right edge while others are being added

### Fixed Behaviour

**`positionWindowUnderTrayIcon()`**
- If `button.window == nil` **or** `calculatedY <= 0` → use screen fallback:
  `screen.visibleFrame.maxY - 4 - windowHeight`
- `visibleFrame.maxY ≈ trayIcon.minY` in practice → no visible jump

**Launch sequence in `applicationDidFinishLaunching`**:
```swift
// Detached window: uses saved X/Y from UserDefaults → show immediately
DispatchQueue.main.async { [weak self] in
    guard let self = self,
          UserDefaults.standard.bool(forKey: "windowDetached") else { return }
    self.restoreDetachedWindowState()
}

// Docked window: wait 200 ms until ALL status-bar items are placed and coords are stable
DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) { [weak self] in
    guard let self = self, !self.isWindowDetached else { return }
    self.showWindowAnimated()
}
```

**NEVER revert to `main.async` for docked windows** — that was the broken pattern causing
the flash/jump since v1.3. The 200 ms delay is intentional and must stay.

**`createEditorTab()`**: call `makeFirstResponder` only when `window.isVisible`
(avoids AppKit redraw during session restore while window is still hidden).

**Dummy TerminalView in `createEditorTab()`**:
```swift
let dummyTV = TerminalView(frameRect: tf, shell: "/usr/bin/true", cwd: nil, historyId: nil)
dummyTV.onShellExit = { }  // CRITICAL — prevents NSApp.terminate(nil) when /usr/bin/true exits
```
`TerminalView.readPTY()` calls `NSApp.terminate(nil)` when `onShellExit == nil` at PTY EOF.

---

## Text Editor Tab

- **`// MARK: - Text Editor`** section before `// MARK: - App Delegate`
- Classes: `TabType`, `SyntaxHighlighter`, `EditorTextStorage`, `EditorLayoutManager`,
  `GutterView`, `EditorFooter`, `EditorSearchPanel`, `EditorView`
- **CRITICAL**: NSTextView must be initialised with
  `NSTextView(frame: NSRect(x:0,y:0,width:tw,height:th), textContainer: textContainer)`
  — NOT `NSTextView()` or `frame: .zero`. Zero frame = invisible, can't type.
- `containerSize` must be `NSSize(width: tw, height: .greatestFiniteMagnitude)` (not max width)
- `layout()` override syncs textView frame/containerSize on window resize

### Editor Modes (Normal / Nano / Vim)

- **Nano**: key intercepts in `BorderlessWindow.sendEvent` — `Ctrl+S/X/K/U`
- **Vim**: `handleVimKey` / `handleVimTwoKeyOp` / `handleVimColonCommand`; colon always consumes key
- Pending flags (`vimPendingD/Y/Colon`) cleared in `setVimMode(.normal)`
- File ops capture `activeTab` **before** opening panel to avoid tab-switch race

---

## Themes

- 4 themes: Dark / Light / OLED / System
- Global color vars are `var` (not `let`): `kDefaultBG`, `kDefaultFG`, `kTermBgCGColor`, etc.
- `applyTheme(_:)` syncs colors to all open EditorViews
- System theme: `DistributedNotificationCenter` → `@objc systemAppearanceChanged`

---

## Session Persistence

- Saved to `~/.quickterminal/session.json`
- Editor tabs: `type: "editor"`, `editorURL`, `editorMode`
- `restoreSession()` calls `createEditorTab()` synchronously during launch (window not visible yet)

---

## CI / Testing

- `bash build.sh` auto-runs `swift tests.swift` (~200 tests, ~1 s)
- `.github/workflows/ci.yml`: GitHub Actions on macOS-15, build + tests on every push/PR to `main`
- Tests are standalone stubs in `tests.swift` (no Cocoa required)
