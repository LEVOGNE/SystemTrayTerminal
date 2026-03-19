# .gitignore Manager Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a `✕` hover button and right-click context menu to each file row in the git panel's file list that appends the file to `.gitignore`.

**Architecture:** Extend `ClickableFileRow` with an `onIgnore` callback, a `✕` button (alpha 0→1 on hover), and a `menu(for:)` override for right-click. Wire `row.onIgnore` in `rebuildFilesStack()`. Add `addToGitignore(path:)` to `GitPanelView` that writes to the repo's `.gitignore` atomically.

**Tech Stack:** Swift, AppKit, NSButton, NSMenu, FileManager

---

### Task 1: Extend ClickableFileRow with ignore button + right-click menu

**Files:**
- Modify: `systemtrayterminal.swift` — `ClickableFileRow` class (~line 9770)

**Step 1: Add `onIgnore` callback and `ignoreBtn` property**

Find (~line 9775):
```swift
    var onClick: (() -> Void)?
    private var trackingArea: NSTrackingArea?
```
Replace with:
```swift
    var onClick: (() -> Void)?
    var onIgnore: (() -> Void)?
    private let ignoreBtn = NSButton()
    private var trackingArea: NSTrackingArea?
```

**Step 2: Configure `ignoreBtn` and update constraints in `init`**

Find the entire `override init(frame:)` block (~line 9778–9790):
```swift
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 3
        marqueeLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(marqueeLabel)
        NSLayoutConstraint.activate([
            marqueeLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            marqueeLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            marqueeLabel.topAnchor.constraint(equalTo: topAnchor),
            marqueeLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
```
Replace with:
```swift
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 3

        ignoreBtn.title = "✕"
        ignoreBtn.isBordered = false
        ignoreBtn.font = NSFont.systemFont(ofSize: 9, weight: .regular)
        ignoreBtn.contentTintColor = NSColor(calibratedWhite: 0.45, alpha: 1.0)
        ignoreBtn.alphaValue = 0
        ignoreBtn.target = self
        ignoreBtn.action = #selector(ignoreBtnClicked)
        ignoreBtn.translatesAutoresizingMaskIntoConstraints = false
        ignoreBtn.setContentHuggingPriority(.required, for: .horizontal)

        marqueeLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(ignoreBtn)
        addSubview(marqueeLabel)
        NSLayoutConstraint.activate([
            ignoreBtn.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            ignoreBtn.centerYAnchor.constraint(equalTo: centerYAnchor),
            marqueeLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            marqueeLabel.trailingAnchor.constraint(equalTo: ignoreBtn.leadingAnchor, constant: -2),
            marqueeLabel.topAnchor.constraint(equalTo: topAnchor),
            marqueeLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
```

**Step 3: Add `ignoreBtnClicked` action + update `mouseEntered`/`mouseExited`**

Find the `mouseEntered` and `mouseExited` methods (~line 9799–9804):
```swift
    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = NSColor(calibratedWhite: 1.0, alpha: 0.06).cgColor
    }
    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = nil
    }
```
Replace with:
```swift
    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = NSColor(calibratedWhite: 1.0, alpha: 0.06).cgColor
        ignoreBtn.alphaValue = 1
    }
    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = nil
        ignoreBtn.alphaValue = 0
    }
```

Then find `override func mouseDown` (~line 9805):
```swift
    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
```
Replace with:
```swift
    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    @objc private func ignoreBtnClicked() {
        onIgnore?()
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let m = NSMenu()
        let item = NSMenuItem(title: "Zu .gitignore hinzufügen", action: #selector(ignoreBtnClicked), keyEquivalent: "")
        item.target = self
        m.addItem(item)
        return m
    }
```

**Step 4: Build**
```bash
cd "/Users/l3v0/Desktop/FERTIGE PROJEKTE/SystemTrayTerminal" && bash build.sh 2>&1 | tail -8
```
Expected: compiles, all tests pass. The `✕` button is invisible by default, appears on hover.

---

### Task 2: Wire onIgnore in rebuildFilesStack()

**Files:**
- Modify: `systemtrayterminal.swift` — `rebuildFilesStack()` (~line 10795)

**Step 1: Add `row.onIgnore` after `row.onClick`**

Find (~line 10811):
```swift
            row.onClick = { [weak self] in self?.toggleDiff(for: entry.path, x: entry.x, y: entry.y) }
            filesStack.addArrangedSubview(row)
```
Replace with:
```swift
            row.onClick = { [weak self] in self?.toggleDiff(for: entry.path, x: entry.x, y: entry.y) }
            row.onIgnore = { [weak self] in self?.addToGitignore(path: entry.path) }
            filesStack.addArrangedSubview(row)
```

**Step 2: Build**
```bash
cd "/Users/l3v0/Desktop/FERTIGE PROJEKTE/SystemTrayTerminal" && bash build.sh 2>&1 | tail -8
```
Expected: compiles (will fail until Task 3 adds `addToGitignore`). If build fails with "use of unresolved identifier", that's expected — proceed to Task 3.

---

### Task 3: Implement addToGitignore(path:)

**Files:**
- Modify: `systemtrayterminal.swift` — near `// MARK: - Actions: Upload (Push)` (~line 11033)

**Step 1: Add the method before `// MARK: - Actions: Upload (Push)`**

Find (~line 11033):
```swift
    // MARK: - Actions: Upload (Push)
```
Insert before it:
```swift
    // MARK: - Actions: .gitignore

    private func addToGitignore(path: String) {
        guard let gitRoot = watchedGitRoot else {
            showFeedback("Kein Git-Repo", success: false)
            return
        }
        let ignorePath = gitRoot + "/.gitignore"
        let fm = FileManager.default

        var existing = ""
        if fm.fileExists(atPath: ignorePath),
           let content = try? String(contentsOfFile: ignorePath, encoding: .utf8) {
            existing = content
        }

        let lines = existing.components(separatedBy: "\n")
        if lines.contains(path) {
            showFeedback("Bereits ignoriert", success: true)
            return
        }

        let newContent: String
        if existing.isEmpty || existing.hasSuffix("\n") {
            newContent = existing + path + "\n"
        } else {
            newContent = existing + "\n" + path + "\n"
        }

        do {
            try newContent.write(toFile: ignorePath, atomically: true, encoding: .utf8)
            showFeedback("→ .gitignore", success: true)
            refresh()
        } catch {
            showFeedback("Schreiben fehlgeschlagen", success: false)
        }
    }

```

**Step 2: Build + full test**
```bash
cd "/Users/l3v0/Desktop/FERTIGE PROJEKTE/SystemTrayTerminal" && bash build.sh 2>&1 | tail -8
```
Expected: all tests pass.

**Step 3: Manual smoke test**
1. Open a git repo in the terminal tab
2. Hover over a file row in the git panel → `✕` button appears on the right
3. Click `✕` → feedback "→ .gitignore", file disappears from list, `.gitignore` updated
4. Right-click a file row → context menu shows "Zu .gitignore hinzufügen"
5. Click menu item → same result
6. Try again on already-ignored file → feedback "Bereits ignoriert"

---

### Task 4: Commit

```bash
cd "/Users/l3v0/Desktop/FERTIGE PROJEKTE/SystemTrayTerminal"
git add systemtrayterminal.swift docs/plans/2026-03-19-gitignore-manager.md
git commit -m "feat(git-panel): per-file gitignore button and right-click context menu"
```
