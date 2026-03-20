# Editor Features v1.5.6 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add 3 editor features: (1) fix Cmd+X cut + other shortcuts, (2) Find & Replace panel (VS Code style), (3) auto-detect language on paste into empty document.

**Architecture:** All changes in `systemtrayterminal.swift`. Feature 1: 8 lines in `BorderlessWindow.sendEvent`. Feature 2: new `FindReplaceBar` class + changes to `EditorView`. Feature 3: `SyntaxLanguage.detectFromContent()` + `EditorTextView.paste()` override.

**Tech Stack:** Swift, AppKit, macOS (NSTextView, NSLayoutManager temporary attributes for highlighting)

---

### Task 1: Fix Cmd+X + other editor shortcuts

**Files:**
- Modify: `systemtrayterminal.swift` — `BorderlessWindow.sendEvent`, around line 5040

**Context:** NSTextView handles cut/copy/undo natively, but editor tabs may not reliably receive these because the sendEvent pipeline intercepts keyDown. Adding explicit routing ensures they always work.

**Step 1: Find the Cmd+S block**

Find this block (around line 5028):
```swift
            // Cmd+S / Cmd+Shift+S / Cmd+O: file operations (only when editor tab active)
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

**Step 2: Add cut/undo/redo/selectAll after the existing Cmd+O block**

Replace the block above with:
```swift
            // Cmd+S / Cmd+Shift+S / Cmd+O: file operations (only when editor tab active)
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
                // Standard editing shortcuts — route explicitly so they reach NSTextView
                // even when the terminal event pipeline would otherwise consume them
                let tv = (d.activeTab < d.tabEditorViews.count ? d.tabEditorViews[d.activeTab] : nil)?.textView
                if let tv = tv {
                    if flags2 == .command, event.charactersIgnoringModifiers == "x" {
                        tv.cut(nil); return
                    }
                    if flags2 == .command, event.charactersIgnoringModifiers == "a" {
                        tv.selectAll(nil); return
                    }
                    if flags2 == .command, event.charactersIgnoringModifiers == "z" {
                        tv.undoManager?.undo(); return
                    }
                    if flags2 == [.command, .shift], event.charactersIgnoringModifiers == "z" {
                        tv.undoManager?.redo(); return
                    }
                    if flags2 == .command, event.charactersIgnoringModifiers == "f" {
                        (d.activeTab < d.tabEditorViews.count ? d.tabEditorViews[d.activeTab] : nil)?.showFindBar()
                        return
                    }
                }
            }
```

**Step 3: Build**
```bash
bash build.sh
```
Expected: BUILD SUCCEEDED

---

### Task 2: Add FindReplaceBar class

**Files:**
- Modify: `systemtrayterminal.swift` — insert new class before `class EditorView` (around line 17210)

**Step 1: Insert FindReplaceBar class**

Find this line (around 17209):
```swift
// ---------------------------------------------------------------------------

class EditorView: NSView {
```

Insert before it:
```swift
// ---------------------------------------------------------------------------
// MARK: - Find & Replace Bar

private class FindReplaceBar: NSView {

    // Callbacks
    var onSearch: ((String, Bool) -> Void)?   // (query, wrap)
    var onReplace: ((String) -> Void)?
    var onReplaceAll: ((String, String) -> Void)?
    var onClose: (() -> Void)?

    private(set) var findField:    NSTextField!
    private(set) var replaceField: NSTextField!
    private var matchLabel:        NSTextField!
    private var prevBtn:           NSButton!
    private var nextBtn:           NSButton!
    private var replaceBtn:        NSButton!
    private var replaceAllBtn:     NSButton!
    private var closeBtn:          NSButton!

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func makeMiniButton(_ title: String, action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.bezelStyle = .rounded
        b.controlSize = .small
        b.font = .systemFont(ofSize: 11)
        return b
    }

    private func makeField(placeholder: String) -> NSTextField {
        let f = NSTextField()
        f.placeholderString = placeholder
        f.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        f.bezelStyle = .roundedBezel
        f.controlSize = .small
        f.focusRingType = .default
        return f
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.95).cgColor

        // Top separator line
        let sep = NSView(frame: NSRect(x: 0, y: 0, width: bounds.width, height: 1))
        sep.wantsLayer = true
        sep.layer?.backgroundColor = NSColor.separatorColor.cgColor
        sep.autoresizingMask = [.width, .maxYMargin]
        addSubview(sep)

        findField    = makeField(placeholder: "Find")
        replaceField = makeField(placeholder: "Replace")

        matchLabel = NSTextField(labelWithString: "")
        matchLabel.font = .systemFont(ofSize: 11)
        matchLabel.textColor = .secondaryLabelColor
        matchLabel.alignment = .right

        prevBtn       = makeMiniButton("↑", action: #selector(prevClicked))
        nextBtn       = makeMiniButton("↓", action: #selector(nextClicked))
        replaceBtn    = makeMiniButton("Replace", action: #selector(replaceClicked))
        replaceAllBtn = makeMiniButton("All", action: #selector(replaceAllClicked))
        closeBtn      = makeMiniButton("✕", action: #selector(closeClicked))
        closeBtn.bezelStyle = .inline

        for v in [findField, replaceField, matchLabel,
                  prevBtn, nextBtn, replaceBtn, replaceAllBtn, closeBtn] as [NSView] {
            addSubview(v)
        }

        findField.delegate = self
        replaceField.delegate = self

        // Enter in findField → next
        findField.target = self
        findField.action = #selector(nextClicked)
    }

    override func layout() {
        super.layout()
        let w = bounds.width
        let row1Y: CGFloat = 4
        let row2Y: CGFloat = 32
        let rowH:  CGFloat = 24
        let fieldW = w - 220

        findField.frame    = NSRect(x: 8, y: row1Y, width: max(100, fieldW), height: rowH)
        replaceField.frame = NSRect(x: 8, y: row2Y, width: max(100, fieldW), height: rowH)

        let btnX = findField.frame.maxX + 6
        prevBtn.frame       = NSRect(x: btnX,      y: row1Y, width: 28, height: rowH)
        nextBtn.frame       = NSRect(x: btnX + 30, y: row1Y, width: 28, height: rowH)
        matchLabel.frame    = NSRect(x: btnX + 60, y: row1Y, width: 80, height: rowH)
        closeBtn.frame      = NSRect(x: w - 28,    y: row1Y, width: 24, height: rowH)

        replaceBtn.frame    = NSRect(x: btnX,       y: row2Y, width: 60, height: rowH)
        replaceAllBtn.frame = NSRect(x: btnX + 64,  y: row2Y, width: 36, height: rowH)
    }

    func setMatchInfo(_ current: Int, _ total: Int) {
        matchLabel.stringValue = total == 0 ? "No matches" : "\(current)/\(total)"
        matchLabel.textColor = total == 0 ? .systemRed : .secondaryLabelColor
    }

    @objc private func nextClicked()       { onSearch?(findField.stringValue, true) }
    @objc private func prevClicked()       { onSearch?(findField.stringValue, false) }
    @objc private func replaceClicked()    { onReplace?(replaceField.stringValue) }
    @objc private func replaceAllClicked() { onReplaceAll?(findField.stringValue, replaceField.stringValue) }
    @objc private func closeClicked()      { onClose?() }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.keyCode == 53 { onClose?(); return true }  // Esc
        return super.performKeyEquivalent(with: event)
    }
}

extension FindReplaceBar: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        guard (obj.object as? NSTextField) === findField else { return }
        onSearch?(findField.stringValue, true)
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) { onClose?(); return true }
        if selector == #selector(NSResponder.insertNewline(_:)) {
            if (control as? NSTextField) === findField { onSearch?(findField.stringValue, true); return true }
        }
        return false
    }
}

// ---------------------------------------------------------------------------

class EditorView: NSView {
```

**Step 3: Build**
```bash
bash build.sh
```
Expected: BUILD SUCCEEDED

---

### Task 3: Wire FindReplaceBar into EditorView

**Files:**
- Modify: `systemtrayterminal.swift` — `EditorView` class (around lines 17211-17585)

**Step 1: Add findBar property and match state**

Find in `EditorView` class (after the existing vars, around line 17229):
```swift
    var vimYankBuffer: String = ""
    var vimPendingColon: Bool = false
```

Replace with:
```swift
    var vimYankBuffer: String = ""
    var vimPendingColon: Bool = false

    private var findBar: FindReplaceBar?
    private var findMatches: [NSRange] = []
    private var findMatchIndex: Int = 0
```

**Step 2: Add showFindBar / hideFindBar / search logic methods to EditorView**

Find the end of `EditorView` where `layout()` is, just before the closing `}`. Find this code:
```swift
    override func layout() {
        super.layout()
        guard let sv = scrollView, let tv = textView, let mb = modeBar else { return }
        let modeBarH: CGFloat = mb.isHidden ? 0 : 26
        let gutterW:  CGFloat = 44
        let availH = max(0, bounds.height - modeBarH)

        // Gutter: left strip
        lineGutter?.frame = NSRect(x: 0, y: modeBarH, width: gutterW, height: availH)

        // ScrollView: remainder to the right
        sv.frame = NSRect(x: gutterW, y: modeBarH,
                          width: max(0, bounds.width - gutterW),
                          height: availH)
        mb.frame.size.width = bounds.width
        let w = sv.contentSize.width
        tv.frame = NSRect(x: 0, y: 0, width: w,
                          height: max(tv.frame.height, sv.contentSize.height))
        tv.textContainer?.containerSize = NSSize(width: w, height: CGFloat.greatestFiniteMagnitude)
    }
}
```

Replace with:
```swift
    override func layout() {
        super.layout()
        guard let sv = scrollView, let tv = textView, let mb = modeBar else { return }
        let modeBarH: CGFloat = mb.isHidden ? 0 : 26
        let findBarH: CGFloat = findBar != nil ? 62 : 0
        let gutterW:  CGFloat = 44
        let availH = max(0, bounds.height - modeBarH - findBarH)

        // Gutter: left strip
        lineGutter?.frame = NSRect(x: 0, y: modeBarH + findBarH, width: gutterW, height: availH)

        // ScrollView: remainder to the right
        sv.frame = NSRect(x: gutterW, y: modeBarH + findBarH,
                          width: max(0, bounds.width - gutterW),
                          height: availH)
        mb.frame.size.width = bounds.width
        findBar?.frame = NSRect(x: 0, y: modeBarH, width: bounds.width, height: findBarH)
        let w = sv.contentSize.width
        tv.frame = NSRect(x: 0, y: 0, width: w,
                          height: max(tv.frame.height, sv.contentSize.height))
        tv.textContainer?.containerSize = NSSize(width: w, height: CGFloat.greatestFiniteMagnitude)
    }

    func showFindBar() {
        guard findBar == nil else { findBar?.findField.window?.makeFirstResponder(findBar?.findField); return }
        let bar = FindReplaceBar(frame: NSRect(x: 0, y: 26, width: bounds.width, height: 62))
        bar.onSearch = { [weak self] query, forward in
            self?.performFind(query: query, forward: forward)
        }
        bar.onReplace = { [weak self] replacement in
            self?.replaceCurrentMatch(with: replacement)
        }
        bar.onReplaceAll = { [weak self] query, replacement in
            self?.replaceAllMatches(query: query, with: replacement)
        }
        bar.onClose = { [weak self] in self?.hideFindBar() }
        addSubview(bar)
        findBar = bar
        needsLayout = true
        window?.makeFirstResponder(bar.findField)
    }

    func hideFindBar() {
        guard let bar = findBar else { return }
        clearFindHighlights()
        bar.removeFromSuperview()
        findBar = nil
        findMatches = []
        findMatchIndex = 0
        needsLayout = true
        window?.makeFirstResponder(textView)
    }

    private func performFind(query: String, forward: Bool) {
        clearFindHighlights()
        guard !query.isEmpty, let lm = textView.layoutManager, let ts = textView.textStorage else { return }
        let text = ts.string
        var ranges: [NSRange] = []
        var searchRange = text.startIndex..<text.endIndex
        let opts: String.CompareOptions = [.caseInsensitive]
        while let r = text.range(of: query, options: opts, range: searchRange) {
            let nsRange = NSRange(r, in: text)
            ranges.append(nsRange)
            guard r.upperBound < text.endIndex else { break }
            searchRange = r.upperBound..<text.endIndex
        }
        findMatches = ranges
        // Highlight all matches
        let allColor = NSColor.systemYellow.withAlphaComponent(0.35)
        for r in ranges {
            lm.addTemporaryAttributes([.backgroundColor: allColor], forCharacterRange: r)
        }
        if ranges.isEmpty {
            findBar?.setMatchInfo(0, 0)
            return
        }
        // Advance index
        if forward {
            findMatchIndex = (findMatchIndex + 1) % ranges.count
        } else {
            findMatchIndex = (findMatchIndex - 1 + ranges.count) % ranges.count
        }
        // Highlight current match brighter
        let curColor = NSColor.systemOrange.withAlphaComponent(0.7)
        lm.addTemporaryAttributes([.backgroundColor: curColor], forCharacterRange: ranges[findMatchIndex])
        textView.scrollRangeToVisible(ranges[findMatchIndex])
        textView.setSelectedRange(ranges[findMatchIndex])
        findBar?.setMatchInfo(findMatchIndex + 1, ranges.count)
    }

    private func clearFindHighlights() {
        guard let lm = textView.layoutManager, let ts = textView.textStorage else { return }
        let fullRange = NSRange(location: 0, length: ts.length)
        lm.removeTemporaryAttribute(.backgroundColor, forCharacterRange: fullRange)
    }

    private func replaceCurrentMatch(with replacement: String) {
        guard !findMatches.isEmpty else { return }
        let range = findMatches[findMatchIndex]
        textView.insertText(replacement, replacementRange: range)
        performFind(query: findBar?.findField.stringValue ?? "", forward: true)
    }

    private func replaceAllMatches(query: String, with replacement: String) {
        guard !query.isEmpty else { return }
        let text = (textView.textStorage?.string ?? "")
        var result = text
        var offset = 0
        let opts: String.CompareOptions = [.caseInsensitive]
        var searchRange = text.startIndex..<text.endIndex
        var replacements: [(NSRange, String)] = []
        while let r = text.range(of: query, options: opts, range: searchRange) {
            replacements.append((NSRange(r, in: text), replacement))
            guard r.upperBound < text.endIndex else { break }
            searchRange = r.upperBound..<text.endIndex
        }
        // Apply from end to start to preserve ranges
        for (nsRange, repl) in replacements.reversed() {
            let start = result.index(result.startIndex, offsetBy: nsRange.location + offset)
            let end   = result.index(start, offsetBy: nsRange.length)
            result.replaceSubrange(start..<end, with: repl)
        }
        _ = offset // suppress warning
        textView.textStorage?.replaceCharacters(in: NSRange(location: 0, length: textView.textStorage?.length ?? 0),
                                                with: result)
        clearFindHighlights()
        findMatches = []
        findBar?.setMatchInfo(0, replacements.count)
    }
}
```

**Step 4: Build**
```bash
bash build.sh
```
Expected: BUILD SUCCEEDED

---

### Task 4: Auto-detect language on paste

**Files:**
- Modify: `systemtrayterminal.swift`
  - `SyntaxLanguage` enum: add `detectFromContent` (around line 16144)
  - `EditorTextView` class: add `onPaste` callback + `paste` override (around line 16076)
  - `EditorView.setup()`: wire `onPaste` callback

**Step 1: Add detectFromContent to SyntaxLanguage**

Find (line 16143):
```swift
        default:                                        return .none
        }
    }
}
```

Replace with:
```swift
        default:                                        return .none
        }
    }

    /// Heuristic language detection from text content (used for paste into empty document).
    static func detectFromContent(_ text: String) -> SyntaxLanguage {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return .none }
        let lower = t.lowercased()
        // Shell scripts
        if t.hasPrefix("#!/bin/") || t.hasPrefix("#!/usr/bin/env") { return .shell }
        // HTML
        if lower.hasPrefix("<!doctype html") || lower.hasPrefix("<html") { return .html }
        // XML / plist (generic tags, not html)
        if t.hasPrefix("<?xml") || t.hasPrefix("<plist") { return .xml }
        // JSON — starts with { or [ and has key:"value" pairs
        if (t.hasPrefix("{") || t.hasPrefix("[")) {
            if t.contains("\":") || t.contains("\": ") { return .json }
        }
        // SQL keywords
        let sqlKeywords = ["select ", "insert into", "create table", "drop table", "update ", "delete from"]
        if sqlKeywords.contains(where: { lower.hasPrefix($0) }) { return .sql }
        // Python
        if lower.contains("def ") && (lower.contains("import ") || lower.contains("print(") || lower.contains("self.")) { return .python }
        if lower.hasPrefix("import ") && (lower.contains("\ndef ") || lower.contains("\nclass ")) { return .python }
        // Swift
        if lower.contains("import foundation") || lower.contains("import uikit") || lower.contains("import swiftui") { return .swift }
        if lower.contains("func ") && lower.contains("var ") && lower.contains("let ") { return .swift }
        // YAML — frequent ": " pairs and starts with --- or key: value pattern
        if t.hasPrefix("---\n") { return .yaml }
        let yamlLines = t.split(separator: "\n").prefix(10)
        let yamlMatch = yamlLines.filter { $0.contains(": ") && !$0.hasPrefix(" ") && !$0.hasPrefix("<") }.count
        if yamlMatch > 2 { return .yaml }
        // TOML — [section] headers + key = value
        if t.contains("\n[") && t.contains(" = ") { return .toml }
        // INI — [section] headers
        if t.hasPrefix("[") && t.contains("]\n") && t.contains("=") { return .ini }
        // CSS — selector { ... }
        if t.contains("{") && t.contains("}") && (lower.contains("color:") || lower.contains("margin:") || lower.contains("padding:") || lower.contains("font-")) { return .css }
        // JavaScript — common patterns
        if lower.contains("function ") || lower.contains("const ") && lower.contains("=>") || lower.contains("document.") { return .javascript }
        if lower.contains("export default") || lower.contains("import {") { return .javascript }
        // Markdown — starts with # heading or has ## headings
        let firstLine = t.components(separatedBy: "\n").first ?? ""
        if firstLine.hasPrefix("# ") || firstLine.hasPrefix("## ") { return .markdown }
        if t.contains("\n## ") || t.contains("\n# ") { return .markdown }
        return .none
    }
}
```

**Step 2: Add onPaste callback to EditorTextView**

Find `private class EditorTextView: NSTextView {` (around line 16076). After the class opening and any existing methods, add before the closing `}`:

Find:
```swift
private class EditorTextView: NSTextView {
    override func mouseMoved(with event: NSEvent) {
```

Replace with:
```swift
private class EditorTextView: NSTextView {
    /// Called after paste; receives true if the document was empty before the paste.
    var onPaste: ((_ wasEmpty: Bool) -> Void)?

    override func paste(_ sender: Any?) {
        let wasEmpty = string.isEmpty
        super.paste(sender)
        onPaste?(wasEmpty)
    }

    override func mouseMoved(with event: NSEvent) {
```

**Step 3: Wire onPaste in EditorView.setup()**

In `EditorView.setup()`, find where `textView` is created and assigned (around line 17264):
```swift
        textView = EditorTextView(frame: NSRect(origin: .zero, size: NSSize(width: tw, height: th)),
                                  textContainer: container)
```

After this line (after `textView = ...`), but before `scrollView.documentView = textView`, find the block and add:

Find:
```swift
        scrollView.documentView = textView
```

Replace with:
```swift
        // Auto-detect language when pasting into empty document
        (textView as? EditorTextView)?.onPaste = { [weak self] wasEmpty in
            guard wasEmpty, let self = self, let storage = self.syntaxStorage,
                  storage.language == .none else { return }
            let detected = SyntaxLanguage.detectFromContent(storage.string)
            if detected != .none { self.setLanguage(detected) }
        }

        scrollView.documentView = textView
```

**Step 4: Build**
```bash
bash build.sh
```
Expected: BUILD SUCCEEDED, all tests pass

---

### Task 5: Version bump to v1.5.6

**Files:**
- Modify: `systemtrayterminal.swift` — `kAppVersion` constant
- Modify: `build.sh` — VERSION variable
- Modify: `build_app.sh` — VERSION variable
- Modify: `build_zip.sh` — VERSION variable
- Modify: `SystemTrayTerminal.app/Contents/Info.plist` — CFBundleVersion + CFBundleShortVersionString
- Modify: `CHANGELOG.md` — add v1.5.6 entry
- Modify: `README.md` — version header + download link
- Modify: `docs/index.html` — softwareVersion, badges, download links, changelog

**Step 1: Bump version in systemtrayterminal.swift**
Find `let kAppVersion = "1.5.5"`, replace with `"1.5.6"`

**Step 2: Bump version in build scripts**
In `build.sh`, `build_app.sh`, `build_zip.sh`: find `VERSION="1.5.5"`, replace with `"1.5.6"`

**Step 3: Update Info.plist**
Replace both `1.5.5` strings with `1.5.6`

**Step 4: Update CHANGELOG.md**
Add v1.5.6 section at top (after the `## Changelog` header):
```markdown
## v1.5.6 — 2026-03-20

### New Features
- **Editor: Cmd+X Cut** — Explicit routing ensures cut, select-all, undo and redo (Cmd+X/A/Z/Shift+Z) always work in editor tabs
- **Editor: Find & Replace** (Cmd+F) — VS Code-style inline panel with real-time match highlighting, Next/Previous navigation, Replace and Replace All. Esc closes.
- **Editor: Auto language detection** — Pasting code into an empty document automatically detects and applies syntax highlighting (HTML, Python, Swift, JSON, CSS, JS, SQL, YAML, Markdown, Shell, TOML, INI, XML)
```

**Step 5: Update README.md**
Update version badge/link from `1.5.5` → `1.5.6`

**Step 6: Update docs/index.html**
Update all version references `1.5.5` → `1.5.6`, add changelog entry for v1.5.6

**Step 7: Build app + zip**
```bash
bash build_app.sh && bash build_zip.sh
```

**Step 8: Git commit + push + GitHub release**
```bash
git add -A
git commit -m "feat(editor): Cmd+X, Find & Replace, auto language detection — v1.5.6"
git push
gh release create v1.5.6 SystemTrayTerminal_v1.5.6.zip --title "v1.5.6 — Editor: Cut, Find & Replace, Auto Language" --notes "..."
```

---

### Task 6: Manual smoke tests

- [ ] Editor tab: select text → Cmd+X → paste elsewhere: clipboard has the text, editor lost it
- [ ] Editor tab: Cmd+A → selects all text
- [ ] Editor tab: type text → Cmd+Z → undoes; Cmd+Shift+Z → redoes
- [ ] Cmd+F → find bar appears at bottom, focus in search field
- [ ] Type search term → matches highlight yellow in real time
- [ ] Enter / ↓ → moves to next match; ↑ → previous
- [ ] Click Replace → replaces current, advances
- [ ] Click All → replaces all matches
- [ ] Esc → find bar closes, highlights cleared
- [ ] New empty editor tab → paste HTML → syntax highlighting activates automatically
- [ ] New empty editor tab → paste Python → Python highlighting activates
