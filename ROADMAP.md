# SystemTrayTerminal Roadmap

This roadmap reflects current priorities and may change.

## ✅ 1.0 Stabilization (Done)

- Fixed PTY write-path reliability for large input bursts.
- Removed retain cycles in tab/split closure wiring.
- Tightened tab reorder consistency with repeated titles.
- Improved split restore correctness and persistence behavior.
- Added regression checks for parser and interaction edge cases.

## ✅ 1.1 Packaging and Distribution (Done)

- App bundle build pipeline (`build_app.sh`, `build_zip.sh`).
- Auto-updater via GitHub Releases (every 72h, clickable toast, session-preserving restart).
- Versioned changelog and release artifacts.

## ✅ 1.2 UX and Terminal Fidelity (Done)

- ~~Better scrollback/search ergonomics.~~ **Done** — scrollback search with match highlighting (quickBAR `Search` command).
- ~~Expanded diagnostics.~~ **Done** — parser diagnostics overlay (quickBAR `Parser` command).
- ~~Performance instrumentation.~~ **Done** — performance monitor overlay (quickBAR `Perf` command).
- ~~Git panel.~~ **Done** — branch, status, diff, commit history, GitHub API support, 7 new features in v1.2.0.
- ~~Claude Code usage badge.~~ **Done** — live session & weekly limits in footer, auto-connected.
- ~~Auto-updater.~~ **Done** — clickable toast, `.app` guard, session-preserving restart.

## ✅ 1.3 Developer Tools & Onboarding (Done)

- ~~WebPicker.~~ **Done** — CDP-based Chrome element picker via floating sidebar. Connect/Disconnect toggle, live hostname, DOM element selection, outerHTML → clipboard. Robust WebSocket handling.
- ~~Full English UI.~~ **Done** — all UI strings translated to English (Git panel, WebPicker, auth, feedback).
- ~~Onboarding video.~~ **Done** — first-launch AVKit video panel (480×300, auto-close, skip button, plays once).
- ~~Demo GIF.~~ **Done** — MP4 → GIF in README, 2.4 MB at 700px width.

## ✅ 1.4 Developer UX & Customization (Done)

- ~~SSH Manager.~~ **Done** — floating sidebar, save/connect/delete SSH profiles, `SSHProfile.connectCommand`, UserDefaults persistence.
- ~~Keyboard shortcuts: tab navigation.~~ **Done** — `Ctrl+1–9` switch, `Ctrl+Shift+1–9` rename, `Ctrl+⌥+1/2/3` window presets.
- ~~Color themes.~~ **Done** — Dark, Light, OLED Black, System (follows macOS appearance). Live switching via `AppleInterfaceThemeChangedNotification`.
- ~~Follow All Spaces.~~ **Done** — window visible on all macOS Spaces, toggleable in Settings.
- ~~Tray detach / reattach.~~ **Done** — float freely on desktop, all 8 resize handles, snap back to tray icon.
- ~~Right-click context menu.~~ **Done** — Copy, Paste, Select All (respects mouse-tracking mode).
- ~~Sidebar right-click to toggle panels.~~ **Done** — Git, WebPicker, SSH buttons respond to right-click.
- ~~Full 10-language localization update.~~ **Done** — all new strings in EN, DE, TR, ES, FR, IT, AR, JA, ZH, RU.
- ~~Updater security hardening.~~ **Done** — SHA256 sidecar verification, HTTPS + host allowlist, bundle-ID guard, background-thread install, relaunch bound to open exit code, backup preserved until relaunch confirmed.
- ~~Test coverage.~~ **Done** — 197 tests; new Updater Logic section covers version comparison, host allowlist, HTTPS check, relaunch guard.

## 1.5 Upcoming

- Signed app bundle and notarization flow (resolves remaining updater trust-anchor gap).
- Homebrew formula support.
- Safari WebPicker support (Web Inspector Protocol).
- More quickBAR commands and inline prompt improvements.

## Community and Project Health

- Triage labels and issue templates in active use.
- Contributor onboarding docs maintained.
- Security response process with release notes.
