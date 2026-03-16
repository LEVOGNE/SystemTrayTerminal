# Editor Modes (Normal/Nano/Vim) + File Ops Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add three editor input modes (Normal/Nano/Vim) with footer mode-selector buttons, a vim/nano status bar inside EditorView, and file operation buttons (Open/Save/Save As) in the header.

**Architecture:** `EditorInputMode` + `VimSubMode` enums drive key intercepts in `BorderlessWindow.sendEvent`. `EditorView` gets a bottom mode-bar strip. Footer adds 3 mode-selector `ShellButton`s; Header adds 3 file-op `HoverButton`s — both only visible for editor tabs. A `tabEditorModes: [EditorInputMode]` parallel array tracks mode per tab.

**Tech Stack:** Swift, Cocoa/AppKit — no external dependencies. Single file `quickTerminal.swift`.

---

### Context for implementer

**Key classes and locations:**
- `EditorView` class: line ~14191 in `quickTerminal.swift`
- `TabType` enum: line ~14257
- `AppDelegate` class: starts ~line 14264
- `AppDelegate.tabEditorViews`: line ~14270
- `AppDelegate.createEditorTab()`: line ~14801
- `AppDelegate.closeTab(index:)`: line ~14853
- `AppDelegate.updateFooter()`: line ~15526
- `FooterBarView` class: line ~6447
- `FooterBarView.setEditorMode(_:)`: line ~6676
- `FooterBarView.linksContent` (left scroll area): where shell buttons live
- `HeaderBarView` class: line ~5330
- `HeaderBarView` constraints block: line ~5455
- `BorderlessWindow.sendEvent`: line ~4719 (`.keyDown` case at ~4789)
- `ShellButton` class (reusable for mode buttons): line ~5824
- `HoverButton` class: line ~4841
- Build: `bash build.sh` — runs tests automatically

**Parallel arrays in AppDelegate** (all must be kept in sync):
`termViews`, `tabTypes`, `tabEditorViews`, `splitContainers`, `tabColors`, `tabCustomNames`, `tabGitPositions`, `tabGitPanels`, `tabGitDividers`, `tabGitRatios`, `tabGitRatiosV`, `tabGitRatiosH`

Add `tabEditorModes: [EditorInputMode]` to this list.

---

### Task 1: Add `EditorInputMode` enum, `VimSubMode` enum, and `tabEditorModes` array

**Files:**
- Modify: `quickTerminal.swift` — insert enums near `TabType` (~line 14257), add array to AppDelegate

**Step 1: Insert enums right BEFORE `// MARK: - Tab Types` (line ~14257)**

```swift
// MARK: - Editor Modes

enum EditorInputMode { case normal, nano, vim }
enum VimSubMode      { case normal, insert }
```

**Step 2: Add `tabEditorModes` to AppDelegate properties (right after `tabEditorViews` line ~14270)**

```swift
var tabEditorModes: [EditorInputMode] = []
```

**Step 3: Add `.normal` entry in `createEditorTab()` (line ~14824, after `tabEditorViews.append(editorView)`)**

```swift
tabEditorModes.append(.normal)
```

**Step 4: Add `nil`-equivalent entry in `createTab()` (line ~14778, after `tabEditorViews.append(nil)`)**

```swift
tabEditorModes.append(.normal)
```

**Step 5: Remove from `closeTab(index:)` (line ~14864, after `tabEditorViews.remove`)**

```swift
if index < tabEditorModes.count { tabEditorModes.remove(at: index) }
```

**Step 6: Build**

```bash
bash build.sh
```
Expected: 197 passed, 0 failed.

**Step 7: Commit**

```bash
git add quickTerminal.swift
git commit -m "feat: add EditorInputMode/VimSubMode enums + tabEditorModes array"
```

---

### Task 2: Add mode bar to `EditorView`

The mode bar is a 28px-tall strip at the bottom of EditorView showing nano shortcuts OR vim mode indicator. Hidden in Normal mode.

**Files:**
- Modify: `quickTerminal.swift` — `EditorView` class (~line 14191)

**Step 1: Add properties to `EditorView` (after `private var scrollView: NSScrollView!`)**

```swift
private var modeBar: NSView!
private var modeBarLabel: NSTextField!
var vimMode: VimSubMode = .normal
var vimYankBuffer: String = ""
var vimPendingColon: Bool = false
```

**Step 2: Update `setup()` — shrink scrollView and add modeBar**

Replace the scrollView frame line:
```swift
scrollView = NSScrollView(frame: bounds)
```
With:
```swift
let modeBarH: CGFloat = 26
scrollView = NSScrollView(frame: NSRect(x: 0, y: modeBarH, width: bounds.width,
                                        height: max(0, bounds.height - modeBarH)))
```

Also add autoresizing (after `scrollView.drawsBackground = false`):
```swift
scrollView.autoresizingMask = [.width, .height]  // already present — keep as-is
```

After `scrollView.documentView = textView`, add:

```swift
// Mode bar (hidden by default — shown for nano/vim)
modeBar = NSView(frame: NSRect(x: 0, y: 0, width: bounds.width, height: modeBarH))
modeBar.wantsLayer = true
modeBar.layer?.backgroundColor = NSColor(calibratedWhite: 0.0, alpha: 0.35).cgColor
modeBar.autoresizingMask = [.width]
modeBar.isHidden = true

let sep2 = NSView(frame: NSRect(x: 0, y: modeBarH - 1, width: bounds.width, height: 1))
sep2.wantsLayer = true
sep2.layer?.backgroundColor = NSColor(calibratedWhite: 1.0, alpha: 0.1).cgColor
sep2.autoresizingMask = [.width]
modeBar.addSubview(sep2)

modeBarLabel = NSTextField(labelWithString: "")
modeBarLabel.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .medium)
modeBarLabel.textColor = NSColor(calibratedWhite: 0.65, alpha: 1.0)
modeBarLabel.alignment = .center
modeBarLabel.translatesAutoresizingMaskIntoConstraints = false
modeBar.addSubview(modeBarLabel)
NSLayoutConstraint.activate([
    modeBarLabel.centerXAnchor.constraint(equalTo: modeBar.centerXAnchor),
    modeBarLabel.centerYAnchor.constraint(equalTo: modeBar.centerYAnchor),
])
addSubview(modeBar)
```

**Step 3: Update `layout()` to account for modeBar height**

Replace entire `layout()` body:

```swift
override func layout() {
    super.layout()
    guard let sv = scrollView, let tv = textView else { return }
    let modeBarH: CGFloat = modeBar?.isHidden == false ? 26 : 0
    // Resize scrollView: top of view down to above modeBar
    sv.frame = NSRect(x: 0, y: modeBarH, width: bounds.width,
                      height: max(0, bounds.height - modeBarH))
    modeBar?.frame.size.width = bounds.width
    let w = sv.contentSize.width
    tv.frame = NSRect(x: 0, y: 0, width: w,
                      height: max(tv.frame.height, sv.contentSize.height))
    tv.textContainer?.containerSize = NSSize(width: w, height: CGFloat.greatestFiniteMagnitude)
}
```

**Step 4: Add public method `setInputMode(_:)`**

Add after `applyColors(bg:fg:)`:

```swift
func setInputMode(_ mode: EditorInputMode) {
    switch mode {
    case .normal:
        modeBar.isHidden = true
        textView.isEditable = true
    case .nano:
        modeBar.isHidden = false
        modeBarLabel.stringValue = "^S Save   ^X Close   ^K Cut Line   ^U Paste"
        modeBarLabel.textColor = NSColor(calibratedRed: 0.5, green: 0.85, blue: 0.5, alpha: 1.0)
        textView.isEditable = true
    case .vim:
        modeBar.isHidden = false
        updateVimModeBar()
        // start in normal mode — disable direct text editing
        setVimMode(.normal)
    }
    needsLayout = true
}

func setVimMode(_ vm: VimSubMode) {
    vimMode = vm
    textView.isEditable = (vm == .insert)
    updateVimModeBar()
}

private func updateVimModeBar() {
    switch vimMode {
    case .normal:
        modeBarLabel.stringValue = "── NORMAL ──"
        modeBarLabel.textColor = NSColor(calibratedRed: 0.4, green: 0.7, blue: 1.0, alpha: 1.0)
    case .insert:
        modeBarLabel.stringValue = "── INSERT ──"
        modeBarLabel.textColor = NSColor(calibratedRed: 0.4, green: 0.9, blue: 0.5, alpha: 1.0)
    }
}
```

**Step 5: Build**

```bash
bash build.sh
```
Expected: 197 passed, 0 failed.

**Step 6: Commit**

```bash
git add quickTerminal.swift
git commit -m "feat: EditorView mode bar — nano shortcuts strip + vim mode indicator"
```

---

### Task 3: Add mode-selector buttons to FooterBarView

Three `ShellButton`s (NORMAL / NANO / VIM) added to `linksContent`, only visible during editor tabs.

**Files:**
- Modify: `quickTerminal.swift` — `FooterBarView` class (~line 6447)

**Step 1: Add array property to `FooterBarView` (after `private var shellButtons: [ShellButton] = []`)**

```swift
private var editorModeButtons: [ShellButton] = []
var onEditorModeChange: ((EditorInputMode) -> Void)?
```

**Step 2: Create and add mode buttons in `init` — insert BEFORE the shell buttons creation block (right before `let shellItems:` line ~6535)**

```swift
// Editor mode buttons (hidden until editor tab is active)
let modeItems: [(String, NSColor)] = [
    ("NORMAL", NSColor(calibratedWhite: 0.55, alpha: 1.0)),
    ("NANO",   NSColor(calibratedRed: 0.5, green: 0.85, blue: 0.5, alpha: 1.0)),
    ("VIM",    NSColor(calibratedRed: 0.4, green: 0.7, blue: 1.0, alpha: 1.0)),
]
for (i, item) in modeItems.enumerated() {
    let btn = ShellButton(title: item.0, accent: item.1)
    btn.isHidden = true
    let mode: EditorInputMode = [.normal, .nano, .vim][i]
    btn.onClick = { [weak self] in
        self?.onEditorModeChange?(mode)
        self?.setActiveEditorMode(mode)
    }
    linksContent.addSubview(btn)
    editorModeButtons.append(btn)
}
```

**Step 3: Add `setActiveEditorMode` helper to `FooterBarView` (after `setEditorMode(_:)` function ~line 6685)**

```swift
func setActiveEditorMode(_ mode: EditorInputMode) {
    let idx: Int
    switch mode {
    case .normal: idx = 0
    case .nano:   idx = 1
    case .vim:    idx = 2
    }
    for (i, btn) in editorModeButtons.enumerated() {
        btn.setActive(i == idx)
    }
}
```

**Step 4: Update `setEditorMode(_ isEditor: Bool)` to show/hide editor mode buttons**

In the existing `setEditorMode` method, add at the start:

```swift
for btn in editorModeButtons { btn.isHidden = !isEditor }
if isEditor {
    // Show NORMAL active by default when entering editor mode
    if editorModeButtons.first?.isActiveShell == false &&
       editorModeButtons.dropFirst().allSatisfy({ !$0.isActiveShell }) {
        editorModeButtons.first?.setActive(true)
    }
}
```

**Step 5: Update `layout()` — insert editor mode buttons into the left layout BEFORE shell buttons**

In the layout's left side loop (`for btn in shellButtons`), insert before it:

```swift
let modeBtnW: CGFloat = 56
for btn in editorModeButtons {
    if btn.isHidden { continue }
    btn.frame = NSRect(x: lx, y: cy - itemH / 2, width: modeBtnW, height: itemH)
    lx += modeBtnW + gap
}
```

**Step 6: Build**

```bash
bash build.sh
```
Expected: 197 passed, 0 failed.

**Step 7: Wire in AppDelegate's `updateFooter()` (~line 15526)**

In `updateFooter()`, after `footerView.setEditorMode(isEditor)`, add:

```swift
if isEditor, activeTab < tabEditorModes.count {
    footerView.setActiveEditorMode(tabEditorModes[activeTab])
}
```

Wire the callback in `applicationDidFinishLaunching` where footerView callbacks are set (~line 14599):

```swift
footerView.onEditorModeChange = { [weak self] mode in
    guard let self = self else { return }
    if self.activeTab < self.tabEditorModes.count {
        self.tabEditorModes[self.activeTab] = mode
    }
    if let ev = self.activeTab < self.tabEditorViews.count ? self.tabEditorViews[self.activeTab] : nil {
        ev?.setInputMode(mode)
    }
}
```

**Step 8: Build**

```bash
bash build.sh
```
Expected: 197 passed, 0 failed.

**Step 9: Commit**

```bash
git add quickTerminal.swift
git commit -m "feat: footer editor mode buttons (NORMAL/NANO/VIM)"
```

---

### Task 4: Add file operation buttons to HeaderBarView

Three small `HoverButton`s to the left of `+`: `Open` · `Save` · `Save As`.

**Files:**
- Modify: `quickTerminal.swift` — `HeaderBarView` class (~line 5330)

**Step 1: Add properties to `HeaderBarView` (after `private var addBtn: HoverButton!` ~line 5379)**

```swift
private var fileOpenBtn: HoverButton!
private var fileSaveBtn: HoverButton!
private var fileSaveAsBtn: HoverButton!
var onFileOpen:   (() -> Void)?
var onFileSave:   (() -> Void)?
var onFileSaveAs: (() -> Void)?
```

**Step 2: Create file buttons in `init` — insert BEFORE `// Buttons kept initialized` line (~5439)**

```swift
// File operation buttons (shown only for editor tabs)
let fileGray = NSColor(calibratedWhite: 0.5, alpha: 1.0)
let fileHover = NSColor(calibratedRed: 0.35, green: 0.65, blue: 1.0, alpha: 1.0)
let fileHoverBg = NSColor(calibratedRed: 0.3, green: 0.55, blue: 1.0, alpha: 0.12)
let filePressedBg = NSColor(calibratedRed: 0.3, green: 0.55, blue: 1.0, alpha: 0.25)

fileOpenBtn = HoverButton(title: "Open", fontSize: 9, weight: .bold,
    normalColor: fileGray, hoverColor: fileHover, hoverBg: fileHoverBg,
    pressBg: filePressedBg, cornerRadius: 4)
fileOpenBtn.onClick = { [weak self] in self?.onFileOpen?() }
fileOpenBtn.translatesAutoresizingMaskIntoConstraints = false
fileOpenBtn.isHidden = true
addSubview(fileOpenBtn)

fileSaveBtn = HoverButton(title: "Save", fontSize: 9, weight: .bold,
    normalColor: fileGray, hoverColor: fileHover, hoverBg: fileHoverBg,
    pressBg: filePressedBg, cornerRadius: 4)
fileSaveBtn.onClick = { [weak self] in self?.onFileSave?() }
fileSaveBtn.translatesAutoresizingMaskIntoConstraints = false
fileSaveBtn.isHidden = true
addSubview(fileSaveBtn)

fileSaveAsBtn = HoverButton(title: "Save As", fontSize: 9, weight: .bold,
    normalColor: fileGray, hoverColor: fileHover, hoverBg: fileHoverBg,
    pressBg: filePressedBg, cornerRadius: 4)
fileSaveAsBtn.onClick = { [weak self] in self?.onFileSaveAs?() }
fileSaveAsBtn.translatesAutoresizingMaskIntoConstraints = false
fileSaveAsBtn.isHidden = true
addSubview(fileSaveAsBtn)
```

**Step 3: Update constraints block (~line 5455)**

Change:
```swift
tabScrollView.trailingAnchor.constraint(equalTo: addBtn.leadingAnchor, constant: -4),
```
To:
```swift
tabScrollView.trailingAnchor.constraint(equalTo: fileOpenBtn.leadingAnchor, constant: -4),
```

Add new constraints inside `NSLayoutConstraint.activate([...])` (before the `addBtn` constraints):

```swift
fileOpenBtn.trailingAnchor.constraint(equalTo: fileSaveBtn.leadingAnchor, constant: -4),
fileOpenBtn.centerYAnchor.constraint(equalTo: centerYAnchor),
fileOpenBtn.widthAnchor.constraint(equalToConstant: 34),
fileOpenBtn.heightAnchor.constraint(equalToConstant: 20),

fileSaveBtn.trailingAnchor.constraint(equalTo: fileSaveAsBtn.leadingAnchor, constant: -4),
fileSaveBtn.centerYAnchor.constraint(equalTo: centerYAnchor),
fileSaveBtn.widthAnchor.constraint(equalToConstant: 34),
fileSaveBtn.heightAnchor.constraint(equalToConstant: 20),

fileSaveAsBtn.trailingAnchor.constraint(equalTo: addBtn.leadingAnchor, constant: -6),
fileSaveAsBtn.centerYAnchor.constraint(equalTo: centerYAnchor),
fileSaveAsBtn.widthAnchor.constraint(equalToConstant: 50),
fileSaveAsBtn.heightAnchor.constraint(equalToConstant: 20),
```

**Step 4: Add public method to show/hide file buttons (after existing `setGitActive`/`setSplitActive` methods ~line 5625)**

```swift
func setFileButtonsVisible(_ visible: Bool) {
    fileOpenBtn.isHidden = !visible
    fileSaveBtn.isHidden = !visible
    fileSaveAsBtn.isHidden = !visible
}
```

**Step 5: Build**

```bash
bash build.sh
```
Expected: 197 passed, 0 failed.

**Step 6: Wire in AppDelegate — in `applicationDidFinishLaunching` (after existing headerView callback wiring ~line 14557)**

```swift
headerView.onFileOpen   = { [weak self] in self?.openEditorFile() }
headerView.onFileSave   = { [weak self] in self?.saveCurrentEditor() }
headerView.onFileSaveAs = { [weak self] in self?.saveCurrentEditorAs() }
```

Also call `setFileButtonsVisible` from `updateHeaderTabs()` (~line 15506). At the end of `updateHeaderTabs()`, add:

```swift
let editorActive = activeTab < tabTypes.count && tabTypes[activeTab] == .editor
headerView.setFileButtonsVisible(editorActive)
```

**Step 7: Build**

```bash
bash build.sh
```
Expected: 197 passed, 0 failed.

**Step 8: Commit**

```bash
git add quickTerminal.swift
git commit -m "feat: header file operation buttons (Open/Save/Save As) for editor tabs"
```

---

### Task 5: Implement file operations (Open / Save / Save As)

**Files:**
- Modify: `quickTerminal.swift` — AppDelegate, add three methods after `createEditorTab()` (~line 14851)

**Step 1: Add `tabEditorURLs` and `tabEditorDirty` arrays to AppDelegate (after `tabEditorModes` property)**

```swift
var tabEditorURLs:  [URL?] = []
var tabEditorDirty: [Bool] = []
```

**Step 2: Append in `createEditorTab()` (after `tabEditorModes.append(.normal)`)**

```swift
tabEditorURLs.append(nil)
tabEditorDirty.append(false)
```

**Step 3: Append in `createTab()` (after `tabEditorModes.append(.normal)`)**

```swift
tabEditorURLs.append(nil)
tabEditorDirty.append(false)
```

**Step 4: Remove in `closeTab(index:)` (after `tabEditorModes.remove`)**

```swift
if index < tabEditorURLs.count  { tabEditorURLs.remove(at: index) }
if index < tabEditorDirty.count { tabEditorDirty.remove(at: index) }
```

**Step 5: Add the three file operation methods (insert after `createEditorTab()` closing brace)**

```swift
func openEditorFile() {
    guard activeTab < tabEditorViews.count, let ev = tabEditorViews[activeTab] else { return }
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.begin { [weak self] result in
        guard let self = self, result == .OK, let url = panel.url else { return }
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }
        ev.textView.string = content
        if self.activeTab < self.tabEditorURLs.count {
            self.tabEditorURLs[self.activeTab] = url
        }
        if self.activeTab < self.tabCustomNames.count {
            self.tabCustomNames[self.activeTab] = url.lastPathComponent
        }
        self.updateHeaderTabs()
    }
}

func saveCurrentEditor() {
    guard activeTab < tabEditorViews.count, let ev = tabEditorViews[activeTab] else { return }
    if activeTab < tabEditorURLs.count, let url = tabEditorURLs[activeTab] {
        try? ev.textView.string.write(to: url, atomically: true, encoding: .utf8)
        if activeTab < tabEditorDirty.count { tabEditorDirty[activeTab] = false }
    } else {
        saveCurrentEditorAs()
    }
}

func saveCurrentEditorAs() {
    guard activeTab < tabEditorViews.count, let ev = tabEditorViews[activeTab] else { return }
    let panel = NSSavePanel()
    panel.begin { [weak self] result in
        guard let self = self, result == .OK, let url = panel.url else { return }
        try? ev.textView.string.write(to: url, atomically: true, encoding: .utf8)
        if self.activeTab < self.tabEditorURLs.count {
            self.tabEditorURLs[self.activeTab] = url
        }
        if self.activeTab < self.tabCustomNames.count {
            self.tabCustomNames[self.activeTab] = url.lastPathComponent
        }
        if self.activeTab < self.tabEditorDirty.count {
            self.tabEditorDirty[self.activeTab] = false
        }
        self.updateHeaderTabs()
    }
}
```

**Step 6: Wire Cmd+S / Cmd+Shift+S in `BorderlessWindow.sendEvent` `.keyDown` block (after the Ctrl+1-9 block, ~line 4799)**

```swift
// Cmd+S / Cmd+Shift+S: save editor (only when editor tab active)
if let d = NSApp.delegate as? AppDelegate,
   d.activeTab < d.tabTypes.count, d.tabTypes[d.activeTab] == .editor {
    let flags2 = event.modifierFlags.intersection([.command, .shift])
    if flags2 == [.command, .shift], event.charactersIgnoringModifiers == "s" {
        d.saveCurrentEditorAs(); return
    }
    if flags2 == .command, event.charactersIgnoringModifiers == "s" {
        d.saveCurrentEditor(); return
    }
    if flags2 == .command, event.charactersIgnoringModifiers == "o" {
        d.openEditorFile(); return
    }
}
```

**Step 7: Build**

```bash
bash build.sh
```
Expected: 197 passed, 0 failed.

**Step 8: Commit**

```bash
git add quickTerminal.swift
git commit -m "feat: editor file operations — open, save, save as (Cmd+O/S/Shift+S)"
```

---

### Task 6: Implement Nano mode key intercepts

**Files:**
- Modify: `quickTerminal.swift` — `BorderlessWindow.sendEvent` `.keyDown` block (~line 4789)

**Step 1: Add nano key handling in `BorderlessWindow.sendEvent` `.keyDown` block (after the Cmd+S block from Task 5)**

```swift
// Nano mode key intercepts
if let d = NSApp.delegate as? AppDelegate,
   d.activeTab < d.tabTypes.count, d.tabTypes[d.activeTab] == .editor,
   d.activeTab < d.tabEditorModes.count, d.tabEditorModes[d.activeTab] == .nano {
    let nFlags = event.modifierFlags.intersection([.command, .control, .option, .shift])
    if nFlags == .control {
        switch event.keyCode {
        case 1:  // Ctrl+S — save
            d.saveCurrentEditor(); return
        case 7:  // Ctrl+X — close tab
            d.closeCurrentTab(); return
        case 40: // Ctrl+K — cut current line
            if let ev = d.activeTab < d.tabEditorViews.count ? d.tabEditorViews[d.activeTab] : nil {
                ev?.cutCurrentLine()
            }
            return
        case 32: // Ctrl+U — paste
            if let ev = d.activeTab < d.tabEditorViews.count ? d.tabEditorViews[d.activeTab] : nil {
                ev?.textView.paste(nil)
            }
            return
        default: break
        }
    }
}
```

**Step 2: Add `cutCurrentLine()` helper to `EditorView` (after `setVimMode(_:)`)**

```swift
func cutCurrentLine() {
    guard let tv = textView, let text = tv.string as NSString? else { return }
    let sel = tv.selectedRange()
    let lineRange = text.lineRange(for: NSRange(location: sel.location, length: 0))
    let lineText = text.substring(with: lineRange)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(lineText, forType: .string)
    tv.replaceCharacters(in: lineRange, with: "")
}
```

**Step 3: Build**

```bash
bash build.sh
```
Expected: 197 passed, 0 failed.

**Step 4: Commit**

```bash
git add quickTerminal.swift
git commit -m "feat: nano mode key intercepts (Ctrl+S/X/K/U)"
```

---

### Task 7: Implement Vim mode key handling

Vim Normal mode intercepts ALL keys via `sendEvent`. Insert mode only intercepts `Esc`.

**Files:**
- Modify: `quickTerminal.swift` — `EditorView` class + `BorderlessWindow.sendEvent`

**Step 1: Add `handleVimKey(_:)` to `EditorView` (after `cutCurrentLine()`)**

```swift
/// Returns true if the key was consumed (Normal mode only).
func handleVimKey(_ event: NSEvent) -> Bool {
    guard vimMode == .normal else {
        // Insert mode: only handle Esc
        if event.keyCode == 53 { setVimMode(.normal); return true }
        return false
    }

    vimPendingColon = false  // reset colon buffer on any non-colon key (handled below)

    let ch = event.charactersIgnoringModifiers ?? ""
    let tv = textView!
    let text = tv.string as NSString
    let sel = tv.selectedRange()
    let lineRange = text.lineRange(for: NSRange(location: sel.location, length: 0))

    switch ch {
    // ── Mode transitions ─────────────────────────────────────────
    case "i":
        setVimMode(.insert); return true
    case "a":
        // Insert after cursor
        let newLoc = min(sel.location + 1, text.length)
        tv.setSelectedRange(NSRange(location: newLoc, length: 0))
        setVimMode(.insert); return true
    case "o":
        // New line below current line
        let insertPos = lineRange.location + lineRange.length
        let insertStr: String
        // If line ends with newline, insert after it; else add newline
        if lineRange.length > 0 && text.character(at: insertPos - 1) == UInt16(("\n" as UnicodeScalar).value) {
            tv.setSelectedRange(NSRange(location: insertPos, length: 0))
            insertStr = "\n"
        } else {
            tv.setSelectedRange(NSRange(location: insertPos, length: 0))
            insertStr = "\n"
        }
        tv.insertText(insertStr, replacementRange: tv.selectedRange())
        setVimMode(.insert); return true

    // ── Navigation ───────────────────────────────────────────────
    case "h":
        let newLoc = max(0, sel.location - 1)
        tv.setSelectedRange(NSRange(location: newLoc, length: 0)); return true
    case "l":
        let newLoc = min(text.length, sel.location + 1)
        tv.setSelectedRange(NSRange(location: newLoc, length: 0)); return true
    case "j":
        tv.moveDown(nil); return true
    case "k":
        tv.moveUp(nil); return true
    case "0":
        tv.setSelectedRange(NSRange(location: lineRange.location, length: 0)); return true
    case "$":
        // End of line (before newline)
        let endPos = lineRange.location + lineRange.length
        let nlAdjust = lineRange.length > 0 &&
            text.character(at: endPos - 1) == UInt16(("\n" as UnicodeScalar).value) ? 1 : 0
        tv.setSelectedRange(NSRange(location: max(lineRange.location, endPos - nlAdjust), length: 0))
        return true

    // ── Line operations ──────────────────────────────────────────
    case "d":
        // "dd" — we need two 'd' presses; use vimPendingColon flag re-purposed as pendingD
        // Actually use a dedicated property: handled below via pendingD flag
        break  // handled by pendingD logic below

    case "y":
        // Similar to dd — handled by pendingY below
        break

    case "p":
        // Paste yanked line below current line
        if !vimYankBuffer.isEmpty {
            let insertPos = lineRange.location + lineRange.length
            tv.setSelectedRange(NSRange(location: insertPos, length: 0))
            let pasteStr = vimYankBuffer.hasSuffix("\n") ? vimYankBuffer : vimYankBuffer + "\n"
            tv.insertText(pasteStr, replacementRange: tv.selectedRange())
            // Move cursor to start of pasted line
            tv.setSelectedRange(NSRange(location: insertPos, length: 0))
        }
        return true

    // ── Colon commands ───────────────────────────────────────────
    case ":":
        vimPendingColon = true; return true

    default: break
    }
    return false
}

// dd / yy require two keypresses — track with these helpers
private var vimPendingD = false
private var vimPendingY = false

func handleVimTwoKeyOp(_ event: NSEvent) -> Bool {
    guard vimMode == .normal else { return false }
    let ch = event.charactersIgnoringModifiers ?? ""
    let tv = textView!
    let text = tv.string as NSString
    let sel = tv.selectedRange()
    let lineRange = text.lineRange(for: NSRange(location: sel.location, length: 0))

    if ch == "d" {
        if vimPendingD {
            // dd — delete line
            vimPendingD = false
            tv.replaceCharacters(in: lineRange, with: "")
            return true
        } else {
            vimPendingD = true
            vimPendingY = false
            return true
        }
    }
    if ch == "y" {
        if vimPendingY {
            // yy — yank line
            vimPendingY = false
            vimYankBuffer = text.substring(with: lineRange)
            return true
        } else {
            vimPendingY = true
            vimPendingD = false
            return true
        }
    }
    // Any other key resets pending state
    vimPendingD = false
    vimPendingY = false
    return false
}

func handleVimColonCommand(_ nextCh: String) -> Bool {
    vimPendingColon = false
    guard let d = NSApp.delegate as? AppDelegate else { return false }
    switch nextCh {
    case "w":
        d.saveCurrentEditor(); return true
    case "q":
        d.closeCurrentTab(); return true
    case "x": // :x = save and quit
        d.saveCurrentEditor(); d.closeCurrentTab(); return true
    default: return false
    }
}
```

**Step 2: Add Vim intercepts in `BorderlessWindow.sendEvent` `.keyDown` block (after nano block)**

```swift
// Vim mode key intercepts
if let d = NSApp.delegate as? AppDelegate,
   d.activeTab < d.tabTypes.count, d.tabTypes[d.activeTab] == .editor,
   d.activeTab < d.tabEditorModes.count, d.tabEditorModes[d.activeTab] == .vim,
   let ev = d.activeTab < d.tabEditorViews.count ? d.tabEditorViews[d.activeTab] : nil {
    let vimFlags = event.modifierFlags.intersection([.command, .control, .option, .shift])
    // Only intercept bare key presses (no modifiers) in vim
    if vimFlags.isEmpty || vimFlags == .shift {
        // Check colon command buffer
        if ev.vimPendingColon {
            let ch = event.charactersIgnoringModifiers ?? ""
            if ev.handleVimColonCommand(ch) { return }
        }
        // Check two-key ops (dd/yy) first
        if ev.handleVimTwoKeyOp(event) { return }
        // Then general vim key
        if ev.handleVimKey(event) { return }
    }
    // In insert mode, allow Esc to pass through to handleVimKey
    if ev.vimMode == .insert, event.keyCode == 53 {
        if ev.handleVimKey(event) { return }
    }
}
```

**Step 3: Build**

```bash
bash build.sh
```
Expected: 197 passed, 0 failed.

**Step 4: Commit**

```bash
git add quickTerminal.swift
git commit -m "feat: vim mode — Normal/Insert, hjkl, i/a/o, dd/yy/p, :w/:q/:x"
```

---

### Task 8: Final integration — reset mode when switching tabs

When switching to a non-editor tab or a different editor tab, the mode bar should reset correctly.

**Files:**
- Modify: `quickTerminal.swift` — `switchToTab()` (~line 15457)

**Step 1: In `switchToTab()`, after `footerView.setEditorMode(isEditor)` logic fires via `updateFooter()` — ensure mode is applied when switching to an editor tab**

Find `func switchToTab(_ index: Int)` and locate where `updateFooter()` is called at the end. Before or after that call, add:

```swift
// Restore editor input mode when switching to editor tab
if index < tabTypes.count, tabTypes[index] == .editor,
   index < tabEditorModes.count, index < tabEditorViews.count,
   let ev = tabEditorViews[index] {
    ev.setInputMode(tabEditorModes[index])
}
```

**Step 2: Also reset vim state when switching AWAY from a vim editor tab to non-editor**

In the same function, where the old tab's editor view is hidden:

```swift
// Reset vim/nano mode bar visibility when leaving editor tab
if activeTab < tabEditorViews.count, let oldEv = tabEditorViews[activeTab] {
    // nothing to reset — mode persists per tab via tabEditorModes
}
```
(This is already handled — no action needed. The mode is stored in `tabEditorModes`.)

**Step 3: Apply mode when `createEditorTab()` finishes — add before `saveSession()` at end of `createEditorTab()` (~line 14848)**

```swift
// Apply initial mode (always .normal for new tabs)
editorView.setInputMode(.normal)
```

**Step 4: Build**

```bash
bash build.sh
```
Expected: 197 passed, 0 failed.

**Step 5: Commit**

```bash
git add quickTerminal.swift
git commit -m "feat: restore editor input mode on tab switch"
```

---

### Task 9: Final smoke test + build app

**Step 1: Build app bundle**

```bash
bash build_app.sh
```
Expected: `quickTerminal.app` builds without errors.

**Step 2: Manual test checklist**

- [ ] Open editor tab → footer shows NORMAL/NANO/VIM buttons, header shows Open/Save/Save As
- [ ] Click NANO → modeBar appears with shortcut hints, typing works normally
- [ ] In NANO: Ctrl+S triggers save (NSSavePanel appears for new file), Ctrl+X closes tab
- [ ] Click VIM → modeBar shows `── NORMAL ──`, can't type directly
- [ ] In VIM Normal: press `i` → modeBar shows `── INSERT ──`, can type
- [ ] In VIM Insert: press Esc → back to Normal
- [ ] In VIM Normal: `hjkl` navigation works, `dd` deletes line, `yy` + `p` yanks and pastes
- [ ] `:w` saves, `:q` closes tab
- [ ] Click Open button → NSOpenPanel opens, file loads
- [ ] Click Save button → saves to current file (or triggers Save As)
- [ ] Cmd+S saves, Cmd+Shift+S → Save As, Cmd+O → Open
- [ ] Switch between tabs: mode persists per tab
- [ ] Switch to terminal tab → NORMAL/NANO/VIM buttons hide, file buttons hide
- [ ] Click NORMAL → plain editing restored

**Step 3: Commit**

```bash
git add quickTerminal.swift
git commit -m "feat: editor modes (Normal/Nano/Vim) + file ops — working v1"
```
