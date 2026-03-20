# Changelog

All notable changes to SystemTrayTerminal are documented here.

---

## v1.5.5 — 2026-03-20

### Bug Fixes

- **Auto-Updater: App quit without relaunch** — Fixed a critical bug where the app would exit after installing an update but the new version never appeared. Root cause: `open App.app` finds the running instance (same Bundle-ID) and sends it a reopen event instead of launching the new binary. Fixed by using `open -n` to force a new instance.
- **Git Panel: Stale ahead/behind count** — The panel now runs `git fetch --quiet` before computing the ahead/behind delta. Previously, remote commits pushed by collaborators were invisible until the user manually ran `git fetch` in the terminal.

### Improvements

- **Git Panel: Smart Pull** — The "Update" button now uses a safe pull sequence instead of a bare `git pull`:
  1. Fetches remote refs first
  2. Auto-stashes uncommitted local changes before pulling
  3. Pulls using the patience diff strategy for best auto-merge quality on non-overlapping edits
  4. On merge conflict: aborts cleanly, restores the stash, and shows which files conflicted
  5. On success: pops the stash so local changes are preserved
- **Git Panel: Localized error messages** — All smart-pull error states (`smartPullConflict`, `smartPullStashFailed`, `smartPullStashError`) are fully localized across all 10 supported languages.

---

## v1.5.3 — 2026-03-19

### New Features

- **Git Panel: Instant Refresh** — DispatchSource watches `.git/HEAD` and `.git/index` for file events. The panel updates within ~100ms of any `git add`, `git commit`, or `git reset` command in the terminal — no polling delay. A `↻` manual refresh button is added to the header card.
- **Git Panel: Undo Last Commit** — A new `↩` row below the commit save button shows the last commit hash + subject. Click once → button turns red and shows "Sicher?" with a 4-second auto-reset. Click again → `git reset --soft HEAD~1` runs, changes stay staged, panel refreshes.
- **Git Panel: .gitignore Manager** — Hover over any file row → a `✕` button appears on the right. Click it or right-click for "Zu .gitignore hinzufügen" to append the path to `.gitignore` instantly. Duplicate detection shows feedback "Bereits ignoriert".
- **Terminal: Cmd+Z Undo** — `Cmd+Z` sends `Ctrl+_` (ASCII 0x1F) to the PTY. readline interprets this as undo, walking back through the input line's edit history.
- **WebPicker: Chrome Tab Switcher** — Dropdown in the header lists all open Chrome tabs. Click to switch the active connection instantly.
- **WebPicker: Hot Reload** — DispatchSource watcher on `file://` pages + localhost folder polling. The connected page refreshes automatically when source files change on disk.
- **WebPicker: Computed Style Inspector** — Click any picked element to expand its full CSS computed property list. The panel height grows and shrinks with the styles.
- **WebPicker: JS REPL Panel** — Run JavaScript directly in the connected page's context. Arrow-key history navigation, spring-eased scroll.
- **WebPicker: Element Screenshot** — Right-click a picked element to capture its exact bounding box via CDP `DOM.getBoxModel` + `Page.captureScreenshot`. 2-step CDP chain (was 4).
- **WebPicker: Picks Persistence** — Picked elements are saved to UserDefaults and restored on reconnect. Pick list now scrollable with limit raised from 5 → 20 entries.
- **WebPicker: CSS Selector / XPath Extraction** — Right-click any picked element to copy its CSS selector or XPath in full/short/absolute/relative formats via context submenu.

### Internal

- `rebuildFilesStack` key now includes status chars (`x`, `y`) — was a silent bug where `git add` changed file status but the row list didn't rebuild.
- `undoConfirmPending` state removed — derived from `undoConfirmTimer != nil`.
- `addToGitignore` file I/O moved to `DispatchQueue.global` off the main thread.
- `WebPickerSidebarView.pickerCleanupJS` extracted as `private static let` — was duplicated inline in `hardDisconnect` and `softDisconnect`.
- `jsEscapeSelector(_:)` helper extracted — CSS selector escaping was duplicated at 3 call sites.
- Polling timer interval: 3s → 5s (DispatchSource watchers handle fast events).

---

## v1.5.2 — 2026-03-19

### Bug Fixes
- **Window gap below menu bar after restart** — `dockedWindowY` is no longer saved or restored. The Y position is always recalculated from the live tray-icon position on every show, preventing stale values from previous sessions causing a visible gap.
- **Window resets to center after sleep/wake** — Custom horizontal position (X) is now preserved across sleep/wake cycles. A new `NSWorkspace.didWakeNotification` handler repositions the docked window 400 ms after wake to account for tray-icon drift.
- **Window displaced after Lid close/open or monitor change** — A new `NSApplication.didChangeScreenParametersNotification` handler repositions the window whenever the screen layout changes (monitor connected/disconnected, resolution change).
- **Window height 1/5 shorter after restart** — Startup height clamp changed from `visibleFrame.height − 80` to `visibleFrame.height − 4`. The 80 px buffer was excessive; `visibleFrame` already excludes the menu bar and Dock.
- **`toggleVertical` and `snapRightFull` height mismatch** — Both now use `visibleFrame.height − 4`, matching the startup `maxH` exactly so the saved size survives restart without any clamp.
- **Feedback popup blocked UI** — `sendmail` subprocess was called with `proc.waitUntilExit()` on the main thread, freezing the UI until the process exited. Moved to `Task.detached`; UI updates dispatched back via `MainActor.run`.

### Internal
- Extracted `repositionDockedWindow()` helper — consolidated three identical X-restore + mask-update blocks (`showWindowAnimated`, `handleWakeFromSleep`, `handleScreenChange`) into one private function.
- Fallback Y clamp in `positionWindowUnderTrayIcon` changed from `max(0, fallbackY)` to `max(visibleFrame.minY, fallbackY)` to prevent overlap with a bottom Dock in the rare fallback path.
- Stale `dockedWindowY` UserDefaults key cleaned up on first launch after upgrade.
- **Concurrency migration** — All GCD callback chains replaced with `async/await`:
  - `URLSession.fetchData(for:) async throws` helper extension (macOS 11-compatible via `withCheckedThrowingContinuation`)
  - `GitHubClient`: 7 network functions converted to `async`; `fetchRemoteDataIfNeeded` uses `async let` for parallel API calls
  - `UpdateChecker`: `DispatchSemaphore` removed; `installUpdate`, `downloadAndInstall`, `verifyChecksum`, `checkForUpdate` converted to `async throws`
  - `GitStatusPanelView.refresh()` + `toggleDiff()`: `DispatchQueue.global` replaced with `Task` + `withCheckedContinuation`
  - `ChromeCDPClient`: `receiveLoop()` rewritten as async `for`-`await` loop; all HTTP calls (`isAvailable`, `getActiveTabWS`, `activateTarget`, `createBlankTab`, `closeTab`, `getTabHostname`) converted to `async`; `connect(wsURL:)` converted to `async -> Bool`
  - `AIUsageManager.fetchUsage()`: internally uses `Task` with `withCheckedThrowingContinuation`; 401/403 token-rotation logic preserved
  - `ChromeCDPClient` + `AIUsageManager` marked `@unchecked Sendable`

---

## v1.5.1 — 2026-03-18

### New Features
- **Bell Notification** — Plays a sound (Purr) and flashes the tray icon 3× when the terminal rings BEL (ASCII 7) and the window is not in focus. Toggle in Settings (default on) with a TEST button. Also accessible via quickBar command. Fully localized in all 10 languages.
- **Inactivity Alert** — Automatically triggers a bell notification after N seconds of terminal silence following user input. Useful for detecting when Claude CLI or other tools are waiting for a response. Delay configurable: 5s / 8s (default) / 15s / 30s.

### Bug Fixes
- **Docked window position not persisted** — Window position is now saved to `UserDefaults` as `dockedWindowX`/`dockedWindowY` during drag and restored on next launch. Position is not overwritten by the tray-centered fallback during show/hide cycles. Reset button clears the saved position.
- **Window position reset on hide/show** — Debounce timer cancelled at the start of `showWindowAnimated()`, preventing a race where the tray-centered position could overwrite the user's saved position.
- **Restore without screen clamp** — Saved docked position is restored without forcing the window fully on-screen, allowing intentional partial off-screen positioning.
- **Arrow offset after edge snap** — Left/right edge double-click snaps now use `pad = 24`, keeping the tray arrow correctly centered over the tray icon.

---

## v1.5.0 — 2026-03-14 … 2026-03-18

### New Features
- **Text Editor Tab** — Open a full text editor tab alongside terminal tabs. Long-press `+` → "Text Editor" or press `⌘E`. Supports open (`⌘O`), save (`⌘S`), and save-as (`⌘⇧S`) with native sheet panels.
- **Syntax Highlighting** — Live token coloring auto-detected from file extension: JSON, HTML/HTM, CSS, JavaScript/TypeScript (JS/MJS/CJS/TS/TSX/JSX), XML, Markdown, Shell, Python, YAML, TOML, Swift, SQL, INI/Dockerfile. Regex-based engine, debounced at 150ms. Colors adapt to dark/light theme automatically.
- **Live Preview** — Split-pane live preview for HTML, SVG, Markdown, and CSV files. Preview updates as you type with no manual refresh. Powered by WebKit. Toggle from the editor header.
- **File Drop on Tab Header** — Drag any text file from Finder onto the tab bar to open it in a new editor tab with syntax highlighting applied automatically.
- **Editor Modes** — Three input modes selectable via footer buttons: `NORMAL` (plain NSTextView), `NANO` (`Ctrl+S/X/K/U` shortcuts with shortcut strip), `VIM` (modal hjkl/insert/dd/yy/p/:/wq with mode indicator).
- **Vim Mode** — Minimal modal editing: `hjkl` + arrow key navigation, `i/a/o` insert, `dd` delete line, `yy` yank, `p` paste, `0/$` line start/end, `:w/:q/:wq` file operations. Status bar shows `── NORMAL ──` / `── INSERT ──`.
- **Nano Mode** — Shortcut bar with `^S Save  ^X Close  ^K Cut Line  ^U Paste`. Keys intercepted at window level.
- **Unsaved Changes Indicator** — Tab name gets a `•` dot prefix whenever the editor content has unsaved changes. Dot disappears after saving.
- **Custom Dark Alert Modal** — Replaces the system `NSAlert` when closing a tab with unsaved content. Renders in the same dark style as quickBAR: dim overlay, ⚠️ warning icon, three buttons (Save / Discard / Cancel) with hover color, press state, and pointing-hand cursor. Localized in all 10 languages.
- **SF Symbol Header Buttons** — Open, Save, and Save As editor buttons use SF Symbols (`folder`, `square.and.arrow.down`, `square.and.arrow.down.on.square`) — fully language-independent.
- **Custom Line Number Gutter** — `LineGutterView` (pure `NSView`, 44 px wide, no `NSRulerView`). Line numbers drawn via `NSLayoutManager`, right-aligned with 8 px padding at 10 pt monospaced system font. Synced to editor scroll via `NSView.boundsDidChangeNotification`. Colors adapt automatically to dark/light theme.
- **Print Modal** — Printer button (SF Symbol `printer`) in the footer bar. Tap to open a dark modal panel with context-aware print options: terminal tab → styled HTML; Markdown / HTML / SVG / CSV editor tabs → formatted preview + source-code options; all other editors → source-code only. HTML is built lazily (only when the user confirms). Prints via native macOS dialog (`NSPrintOperation` for source, `WKWebView.printOperation` for rendered HTML).
- **Search & Replace** — `⌘F` find with match highlighting, `⌘H` find & replace panel.
- **Window Size Persistence** — Last window dimensions saved on every resize and restored on next launch. Saved size is clamped to the visible screen area on startup.
- **Window Always On Screen** — `clampFrameToScreen()` ensures the window never extends outside the visible screen area, at launch and when restoring detached position.
- **Edge Double-Click Expand (docked-aware)** — Double-click any window edge to maximize in that direction. Docked: left expands left (right edge stays over tray icon), right expands right, bottom expands down. Detached: snaps to the respective screen half. Full-screen from docked mode is explicitly blocked.
- **Session Persistence** — Editor tabs (open file URL and editor mode) saved and restored across restarts.
- **Theme Sync** — Editor background and text color automatically follow the active color theme.
- **10-Language Localization** — All editor and modal strings fully translated: EN, DE, TR, ES, FR, IT, AR, JA, ZH, RU.

### Bug Fixes
- **Window opens at screen center when docked** — Startup height clamping now uses `screenVis.height - 80` instead of `× 0.95`. Bad saved heights are corrected and persisted back to `UserDefaults` on first launch.
- **`positionWindowUnderTrayIcon` silent no-op on oversized window** — `guard fallbackY > 0 else { return }` replaced: window is now resized to fit and positioned correctly instead of doing nothing.
- **Detached window could restore off-screen** — `restoreDetachedWindowState` now passes the restored frame through `clampFrameToScreen` before applying it.
- **Window positioning flash on launch** — Docked window waits 400 ms (increased from 200 ms) for status-bar item coordinates to stabilize before calling `showWindowAnimated()`.
- **Multiple editor tabs background darkening** — Each new editor tab no longer composites on top of the previous one; views are properly hidden before the new one is shown.
- **File panels appearing behind window** — `NSOpenPanel` / `NSSavePanel` now use `beginSheetModal(for:)`, attaching them as sheets to the window.
- **Version button not clickable** — Tab content views are re-added below the version button in z-order after each tab creation.
- **Text cursor over editor header buttons** — `SymbolHoverButton` / `AlertButton` override `cursorUpdate` to set `NSCursor.pointingHand`; tracking areas use `.cursorUpdate` + `.activeAlways`.
- **Hover states on alert buttons not firing** — Replaced transparent hit-area overlay (unreliable without a layer) with `AlertButton` that IS the background, `wantsLayer = true` from init, `.activeAlways` tracking.
- **`+` → Terminal opened editor** — Removed incorrect branch in `addTab()` that called `createEditorTab()` when the active tab was an editor.
- **Vim cursor invisible in normal mode** — `isEditable` stays `true` in all Vim sub-modes; key blocking handled entirely by `BorderlessWindow.sendEvent`.
- **Vim normal mode typing** — All unrecognized keyDown events in normal mode consumed by `sendEvent` before reaching NSTextView.

---

## v1.4.0 — 2026-03-14

### New Features
- **SSH Manager** — Floating sidebar for SSH profile management. Save connections (label, user@host, port, identity file), connect via new tab with one click, delete profiles. Profiles stored in UserDefaults as JSON. `SSHProfile.connectCommand` builds the correct `ssh` invocation automatically.
- **Keyboard Shortcuts: Tab Navigation** — `Ctrl+1–9` to switch directly to any tab. `Ctrl+Shift+1–9` to trigger inline rename for that tab.
- **Keyboard Shortcuts: Window Presets** — `Ctrl+⌥+1` (compact 620×340), `Ctrl+⌥+2` (medium 860×480), `Ctrl+⌥+3` (large 1200×680) — animated spring resize.
- **Color Themes** — 4 terminal color schemes in Settings: Dark (default), Light, OLED Black, System (auto-follows macOS Dark/Light Mode). System theme observes `AppleInterfaceThemeChangedNotification` for live switching.
- **Follow All Spaces** — New setting: window appears on all macOS Spaces simultaneously. Toggle in Settings or via tray right-click menu.
- **Tray Detach / Reattach** — Right-click tray icon → "Detach Window" floats the terminal freely on the desktop. Detached window is fully resizable from all 8 edges/corners. "Reattach Window" snaps it back under the tray icon. State survives hide/show cycles.
- **Terminal Right-Click Context Menu** — Right-click: Copy, Paste, Select All (respects mouse-tracking mode; falls through to app when tracking is active).
- **Sidebar Right-Click** — Right-click on any header panel button (Git, WebPicker, SSH) to toggle that panel without opening quickBAR.
- **Full 10-Language Localization Update** — All new UI strings (`showHide`, `detachWindow`, `reattachWindow`, `quitApp`) added to all 10 language dictionaries: EN, DE, TR, ES, FR, IT, AR, JA, ZH, RU.

### Security
- **Updater: SHA256 integrity check** — Downloads a `.sha256` sidecar from GitHub Releases and verifies the ZIP before installation. Absent sidecar falls back gracefully without blocking the update.
- **Updater: HTTPS + host allowlist** — Both download and checksum URLs are enforced to use `https://` and restricted to `github.com` / `objects.githubusercontent.com`. Redirects to any other host are rejected.
- **Updater: Bundle ID verification** — Extracted `.app` must match the current app's `CFBundleIdentifier` before installation proceeds.

### Bug Fixes
- **Header gap when detached** — Floating window no longer shows a 4–5 px empty strip at the top. Arrow view is hidden and `headerView.frame` repositions flush to the window top edge.
- **Terminal area when detached** — `termFrame()` now uses `effectiveArrowH = 0` when detached, so the terminal expands to fill the recovered space.
- **Sidebar drag moved window** — `isMovableByWindowBackground` removed entirely; drag-to-move is now handled exclusively in `HeaderBarView.mouseDragged` and only activates when `isWindowDetached == true`.
- **Diagonal resize when detached** — `BorderlessWindow.edgeAt()` now exposes top-left and top-right corner resize zones when `isDetached == true`.
- **First-click on sidebar divider** — `GitPanelDividerView.acceptsFirstMouse` returns `true`, fixing the two-click interaction when the window is not yet frontmost.
- **Window position saved while detached** — `windowDidMove` / `windowDidResize` guard against `isWindowDetached` to prevent the desktop position from overwriting the tray-snap coordinates.
- **Reattach position** — `toggleDetach()` clears `windowX` / `windowY` from UserDefaults before reattaching, so `positionWindowUnderTrayIcon()` always recalculates from the current tray icon position.
- **Detach state not preserved on hide/show** — `toggleWindow()` now preserves the detached state; showing a hidden detached window no longer auto-reattaches it.
- **Updater: parse error vs. "up to date"** — HTTP errors, missing data, and JSON parse failures now return `.failure(error)` instead of silently reporting no update available.
- **Updater: background-thread install** — `installUpdate` runs on `DispatchQueue.global(qos: .utility)`, eliminating UI freeze during extraction and file operations.
- **Updater: relaunch exit guarded by open exit code** — `exit(0)` is only called when `/usr/bin/open` returns exit code 0. A failed relaunch no longer terminates the running process.
- **Updater: backup preserved until relaunch confirmed** — Old `.app` backup is deleted only after `open` succeeds, retaining rollback capability on relaunch failure.
- **Auto-Check Updates: toggle reschedules timer** — Enabling/disabling in Settings now immediately schedules or cancels the repeating timer.
- **Startup window fade** — `showWindowAnimated()` is now used on first launch, ensuring consistent fade-in and correct `hideOnClickOutside` monitor setup.

---

## v1.3.0 — 2026-03-12

### New Features
- **WebPicker** — Chrome DevTools Protocol (CDP) based DOM element picker. Connects to Chrome via WebSocket, lets you hover-select any element on any webpage, copies `outerHTML` to clipboard and auto-pastes into terminal. Floating sidebar with Connect/Disconnect toggle, live hostname display, and element preview.
- **Onboarding Video** — First-launch intro panel (480×300, centered). Plays `SystemTrayTerminal.mp4` once using AVKit, auto-closes when done, has "✕ Skip" button. Never shown again after first view (UserDefaults flag).
- **Full English UI** — All UI strings translated to English: Git panel, WebPicker, GitHub auth, feedback toasts, error messages, Claude API strings.
- **Demo GIF** — `SystemTrayTerminal.gif` added to README (MP4 → GIF, 700px, 2.4 MB, auto-plays on GitHub).

### Bug Fixes
- **WebSocket silent death** — `ChromeCDPClient.receiveLoop` now fires `onDisconnected` callback on `.failure`, preventing the UI from getting stuck in "connected" state when Chrome crashes or the tab is killed externally.
- **pollTimer not reset on reconnect** — `connect()` now invalidates `pollTimer` before starting a new session, preventing duplicate polling timers when the user reconnects without disconnecting first.
- **Tab closed externally** — `refreshTabTitle` returning `nil` (tab not found in Chrome's `/json/list`) now triggers a full `handleUnexpectedDisconnect(message: "Tab was closed")` instead of incorrectly showing "Navigating" state.
- **Stale onDisconnected closure** — `disconnect()` now sets `cdp.onDisconnected = nil` before closing, preventing a stale closure race where a final WebSocket `.failure` after manual disconnect could re-trigger disconnect logic.
- **Teardown duplication** — Disconnect/cleanup logic was duplicated in 3 places. Extracted into `handleUnexpectedDisconnect(message:)` with a `guard isConnected` gate to prevent double-firing.
- **titlePollTimer churn** — `startTitlePolling()` was being recreated on every HTTP callback. Extracted into a dedicated method called once after connect, preventing timer accumulation.
- **targetId extraction** — Replaced hand-rolled `wsURL.components(separatedBy: "/").last` with `URL(string: wsURL)?.lastPathComponent` for correct and reliable target ID extraction.

### Renames / Cleanup
- `HTMLPickerSidebarView` → `WebPickerSidebarView`
- `htmlPickerSidebarView` → `webPickerSidebarView` (AppDelegate)
- `onHTMLPickerToggle` → `onWebPickerToggle` (HeaderBarView)
- `setHTMLPickerActive` → `setWebPickerActive`
- `htmlPickerRightDivider` → `webPickerRightDivider`
- `toggleHTMLPicker` → `toggleWebPicker`
- `htmlPickerBrowser` → `webPickerBrowser` (UserDefaults key)
- `htmlBtn` → `webPickerBtn` (HeaderBarView)
- Removed dead `HTMLPickerPanel` class (282 lines)
- Removed all `print("[CDP]...")` debug statements

---

## v1.2.1 — 2026-03-11

### Bug Fixes
- **Auto-updater** — Clickable toast notification for update install. `.app` guard prevents update on non-bundled binary.

---

## v1.2.0 — 2026-03-10

### New Features
- **Git Panel** — 7 new features: branch display, changed files, diff viewer, staged changes, commit history, GitHub API CI status, panel position toggle (right/bottom).
- **Claude Code Usage Badge** — Live session & weekly limits in footer. Auto-connects via local credentials, color-coded, click for detail popover.
- **Drag & Drop** — Drop files/images from Finder → shell-escaped path inserted at cursor.
- **Custom Tab Names** — Double-click tab to rename; persists across sessions.

---

## v1.1.0 — 2026-03-08

### New Features
- Session restore — tabs, shells, splits, working directories.
- quickBAR — 40-command Spotlight-style palette.
- Multi-tab with color coding and drag-to-reorder.
- Split panes — vertical and horizontal with draggable divider.
- Auto-updater — GitHub Releases check every 72h.

---

## v1.0.0 — 2026-03-01

### Initial Release
- VT100/VT220/xterm terminal emulator from scratch (13-state FSM parser).
- 60 FPS CGContext rendering. 24-bit TrueColor. Sixel graphics.
- Menu bar app, global hotkey Ctrl+<.
- Single Swift file, zero dependencies, 4.8 MB app bundle.
