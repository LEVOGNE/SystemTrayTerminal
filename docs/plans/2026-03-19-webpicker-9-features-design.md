# WebPicker — 9 New Features Design
**Date:** 2026-03-19
**Status:** Approved

## Overview

Nine additive features for `WebPickerSidebarView` and `ChromeCDPClient`. All features are self-contained and can be shipped incrementally. No breaking changes to existing behavior.

---

## Feature List

| # | Name | Priority | Complexity |
|---|------|----------|------------|
| 1 | CSS Selector Generator | High | Low |
| 2 | Computed Style Inspector | High | Medium |
| 3 | JS Mini-REPL | High | Medium |
| 4 | Chrome Tab Switcher | Medium | Low |
| 5 | Element Screenshot | High | Medium |
| 6 | Copy Format Selector | High | Low |
| 7 | Picks Persistence | Medium | Low |
| 8 | More Picks / Scrollable | Low | Low |
| 9 | Hot Reload | High | Medium |

---

## Architecture

### PickEntry Extension

`PickEntry` struct gets three new fields extracted at pick-time via JS:

```swift
private struct PickEntry {
    let id: Int
    let html: String      // outerHTML (existing)
    let hex: String       // color hex (existing)
    let color: NSColor    // (existing, not Codable)
    var selector: String  // CSS selector path
    var innerText: String // plain text content
    var xpath: String     // XPath expression
}

// Codable version for persistence (no NSColor):
private struct PickEntryRecord: Codable {
    let id: Int
    let html: String
    let hex: String
    let selector: String
    let innerText: String
    let xpath: String
}
```

All three new fields are extracted by a single JS snippet injected alongside the existing pick JS, so no extra CDP round-trips.

### ChromeCDPClient Extensions

Two new methods:

```swift
func captureElementScreenshot(selector: String, pickId: Int, completion: @escaping (Data?) -> Void)
// Uses: DOM.getDocument → DOM.querySelector → DOM.getBoxModel → Page.captureScreenshot(clip:)

func getTabList(completion: @escaping ([[String: Any]]) -> Void)
// Uses: HTTP GET /json/list, returns array of {id, title, url, type}
```

---

## Feature Designs

### Feature 1 + 6: CSS Selector / Copy Formats

**Trigger:** Rechtsklick auf `PickRowView`
**UI:** `NSMenu` mit 5 Items:
```
✔ outerHTML          ← default (also left-click behavior)
  innerText
  CSS Selector
  XPath
──────────────────
  Screenshot kopieren
```

**JS extraction** (injected at pick time alongside existing picker JS):
```js
// Returns {selector, innerText, xpath} for target element
function getPickMeta(el) {
  return {
    selector: getCssSelector(el),
    innerText: el.innerText?.trim().substring(0, 500) ?? '',
    xpath: getXPath(el)
  };
}
function getCssSelector(el) {
  if (el.id) return '#' + CSS.escape(el.id);
  const path = [];
  while (el && el.nodeType === 1 && el !== document.body) {
    let seg = el.tagName.toLowerCase();
    const idx = [...(el.parentElement?.children ?? [])].indexOf(el) + 1;
    const sameTag = [...(el.parentElement?.children ?? [])].filter(s => s.tagName === el.tagName);
    if (sameTag.length > 1) seg += ':nth-child(' + idx + ')';
    if (el.classList.length) seg += '.' + [...el.classList].slice(0,2).map(c => CSS.escape(c)).join('.');
    if (el.id) { path.unshift('#' + CSS.escape(el.id)); break; }
    path.unshift(seg);
    el = el.parentElement;
  }
  return path.join(' > ');
}
function getXPath(el) {
  const parts = [];
  while (el && el.nodeType === 1) {
    const idx = [...(el.parentNode?.children ?? [])].filter(s => s.tagName === el.tagName).indexOf(el) + 1;
    parts.unshift(el.tagName.toLowerCase() + (idx > 1 ? '[' + idx + ']' : ''));
    el = el.parentNode;
    if (el === document.body) { parts.unshift('body'); break; }
  }
  return '/' + parts.join('/');
}
```

The result is stored alongside `html` in `PickEntry` and used by the right-click menu.

---

### Feature 2: Computed Style Inspector

**Trigger:** Click on a `PickRowView` (not the × button)
**UI:** Accordion expand below the row (like SSH form animation):
```
● <div class="card">...        ×
  ▼ font: 14px "Inter", #3c3c3c
    bg: #ffffff  pad: 8 16px  r: 8px
```

**Properties shown (6):** `font-size`, `font-family`, `color`, `background-color`, `padding`, `border-radius`

**CDP call:** `Runtime.evaluate` with:
```js
(function(sel) {
  var el = document.querySelector('[data-qt-pick-' + sel + ']');
  if (!el) return null;
  var s = getComputedStyle(el);
  return {
    fontSize: s.fontSize,
    fontFamily: s.fontFamily.split(',')[0].replace(/['"]/g,'').trim(),
    color: s.color,
    backgroundColor: s.backgroundColor,
    padding: s.padding,
    borderRadius: s.borderRadius
  };
})(PICK_ID)
```

**Row expansion:** `PickRowView` gets a collapsible `stylesLabel: NSTextField` below the main row content, height-animated from 0 → 36pt. Click toggles. `isExpanded: Bool` state per row.

---

### Feature 3: JS Mini-REPL

**Trigger:** `</>` button in WebPicker title bar (new `replBtn`)
**UI:** Collapsible panel below picks section (same `NSAnimationContext` pattern as SSH form):
```
[</> REPL ▼]
┌──────────────────────────────┐
│ → document.title             │  ← urlField-style NSTextField
│ "GitHub"                     │  ← result label (green/red)
└──────────────────────────────┘
```

**Behavior:**
- Enter key evaluates expression via `cdp.evaluate()`
- Result shown below: string values in teal, errors in red
- Last 20 expressions stored in `replHistory: [String]`, ↑/↓ keys navigate
- Only visible / interactive when `isConnected == true`
- REPL state persists across soft-disconnect/reconnect

**New properties:**
```swift
private var replExpanded = false
private let replBtn = NSButton()           // </> in title bar
private let replWrap = NSView()            // collapsible wrapper
private let replField = NSTextField()      // input
private let replResultLabel = NSTextField() // output
private var replHistory: [String] = []
private var replHistoryIdx = -1
private var replHeightConstraint: NSLayoutConstraint!
```

---

### Feature 4: Chrome Tab Switcher

**Trigger:** `⊞` button to the right of URL field
**UI:** Dropdown overlay (same mechanism as `suggestBox`):
```
[urlField              ] [⊞] [⟳]
┌───────────────────────────────┐
│ ▶ GitHub · https://github.com │  ← active tab (teal dot)
│   Google · https://google.com │
│   localhost:3000 · /          │
└───────────────────────────────┘
```

**Behavior:**
- Clicking tab item: `cdp.activateTarget(targetId:)` → reconnect to that tab via `doConnect(wsURL:)`
- Tab list refreshed each time the dropdown opens (HTTP `/json/list`)
- Active tab highlighted (current `currentTargetId`)
- Max 8 tabs shown (scroll if more)

**New properties:**
```swift
private let tabSwitcherBtn = NSButton()   // ⊞ button
private let tabBox = NSView()             // dropdown overlay (like suggestBox)
private var tabBoxH: NSLayoutConstraint!
private var tabBoxVisible = false
```

---

### Feature 5: Element Screenshot

**Trigger:** Rechtsklick → "Screenshot kopieren" menu item
**Flow:**
1. `DOM.getDocument` → get node ID for document root
2. `DOM.querySelector(nodeId:selector:)` using `data-qt-pick-N` attribute
3. `DOM.getBoxModel(nodeId:)` → get `content` quad (8 floats)
4. `Page.captureScreenshot(format: "png", clip: {x,y,width,height,scale:1})` → base64 PNG
5. Decode → `NSImage` → write to `NSPasteboard` as `.tiff`
6. Feedback: "✓ Screenshot kopiert!"

**Error handling:** If `getBoxModel` fails (element off-screen or in shadow DOM) → show "Element nicht sichtbar" in feedback label.

**New CDPClient method:**
```swift
func captureElementScreenshot(pickId: Int, completion: @escaping (Data?) -> Void) {
    // DOM.getDocument → DOM.querySelector("[data-qt-pick-N]") → DOM.getBoxModel → Page.captureScreenshot
}
```

---

### Feature 7: Picks Persistence

**Storage:** UserDefaults key `"webPickerPicks"` as JSON (`[PickEntryRecord]`)
**Save:** After every `onHTMLPicked()` call and after every pick removal
**Load:** In `showConnectedState()` — restore picks list from UserDefaults and re-apply `data-qt-pick-N` attributes to current Chrome tab
**Clear:** `clearPickList()` also clears UserDefaults
**Codable struct:** `PickEntryRecord` (html, hex, selector, innerText, xpath — no NSColor)

Re-applying picks on reconnect JS:
```js
// For each saved pick, set data-qt-pick-N on matching element
var el = document.querySelector(SELECTOR);
if (el) el.setAttribute('data-qt-pick-N', '1');
```
Falls back gracefully if element no longer exists.

---

### Feature 8: More Picks / Scrollable List

**Change:** Wrap `picksStack` in an `NSScrollView` with `maxHeight = 200pt`
**Limit:** Raise from 5 → 20 (still FIFO at 20)
**Layout:** `picksScrollView` replaces direct `picksStack` placement in NSLayoutConstraint setup
**Row widths:** `row.widthAnchor.constraint(equalTo: picksScrollView.contentView.widthAnchor)`

---

### Feature 9: Hot Reload

**Toggle:** `⟳` button right of URL field (next to tab switcher)
**States:** OFF (gray) → ON (teal, pulsing) → WATCHING (teal, label "● watching: index.html")

**For `file://` URLs:**
- Extract path: `URL(string: tabURL)?.path`
- `DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename], queue: .main)`
- On event: close + reopen fd (handles atomic save/rename pattern), call `Page.reload`

**For `localhost:` URLs:**
- Show `📁` button → NSOpenPanel → select project folder
- Poll timer every 1.0s: scan files in folder (depth ≤ 3), check `modificationDate`
- On mtime change: `Page.reload`

**Sub-row (localhost, hot reload ON):**
```
[📁 /Users/dev/project]  ● 14 files
```

**Page.reload CDP call:**
```swift
cdp.cdpCommand("Page.reload", params: ["ignoreCache": true]) { _ in }
```

**New properties:**
```swift
private var hotReloadEnabled = false
private var fileWatcher: DispatchSourceFileSystemObject?
private var hotReloadPollTimer: Timer?
private var watchedPath: String?
private var watchedFileMtimes: [String: Date] = [:]
private var watchedFileCount = 0
private let hotReloadBtn = NSButton()       // ⟳
private let watchRow = NSView()             // sub-row for localhost
private let watchFolderBtn = NSButton()     // 📁
private let watchStatusLabel = NSTextField() // "● 14 files"
private var watchRowH: NSLayoutConstraint!  // height 0 → 22
```

**Stop watching:** on `disconnect()`, `softDisconnect()`, toggle OFF, and `deinit`

---

## UI Layout (when connected)

```
┌─────────────────────────────────────────┐
│ ◈  WebPicker    [</>]  [▲][▼][✕]       │  ← replBtn added to title bar
│ chrome://inspect  localhost:9222/json   │
│─────────────────────────────────────────│
│ ● github.com               [Disconnect] │
│ [https://github.com...   ] [⊞] [⟳]     │  ← tabSwitcherBtn + hotReloadBtn
│  (watch row hidden when file://)        │
│ [Pick Element                         ] │
│─────────────────────────────────────────│
│  PICKS                       [Reset]    │
│─────────────────────────────────────────│
│ ● <div class="header">...          ×   │
│   (expanded: font 14px Inter #333)      │  ← computed style inspector
│ ● <span class="title">...          ×   │
│─────────────────────────────────────────│
│  </> REPL                    [▼ toggle] │  ← collapsible
│  → document.title                       │
│  "GitHub"                               │
│─────────────────────────────────────────│
│  ✓ Copied!                              │
└─────────────────────────────────────────┘
```

---

## Implementation Order

Recommended order (lowest risk first, builds on itself):

1. **Feature 8** — Picks Scrollable (pure layout change, no logic)
2. **Feature 7** — Picks Persistence (adds Codable, no UI)
3. **Feature 1+6** — CSS Selector extraction + Right-click menu (JS + NSMenu)
4. **Feature 4** — Tab Switcher (suggestBox pattern, low risk)
5. **Feature 9** — Hot Reload (DispatchSource + polling)
6. **Feature 2** — Computed Style Inspector (expand row UI)
7. **Feature 3** — JS REPL (new collapsible panel)
8. **Feature 5** — Element Screenshot (CDP DOM calls, highest complexity)

---

## Non-Goals

- No multi-file diff viewer
- No full Chrome DevTools panel
- No WebSocket event capture (Network tab)
- No Firefox/Safari support
