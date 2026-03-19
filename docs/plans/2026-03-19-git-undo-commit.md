# Git Undo Last Commit Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a "↩ Undo last commit" row to the git panel's commit card that performs `git reset --soft HEAD~1` with a 2-click safety confirmation.

**Architecture:** Extend `GitResult` with `lastCommit: String?` fetched in the background refresh block. Add UI to `buildCommitCard()`. `undoCommitClicked()` handles 2-click state via a timer. All git action dispatched to `DispatchQueue.global`.

**Tech Stack:** Swift, AppKit, NSStackView, NSButton, Timer, DispatchQueue

---

### Task 1: Add lastCommit to GitResult + state var

**Files:**
- Modify: `systemtrayterminal.swift` — state section of `GitPanelView` (~line 9811) and `refresh()` (~lines 10638–10701)

**Step 1: Add state property**

In `GitPanelView`'s `// MARK: - State & Data` block, after `private var watchedGitRoot = ""` (~line 9815), add:

```swift
    private var lastCommitSummary: String?
    private var undoConfirmPending = false
    private var undoConfirmTimer: Timer?
```

**Step 2: Extend GitResult typealias**

Find (~line 10638):
```swift
            typealias GitResult = (isRepo: Bool, branch: String, hasRemote: Bool,
                                   ahead: Int, behind: Int,
                                   entries: [(path: String, x: Character, y: Character, attr: NSAttributedString)],
                                   projectName: String, topLevel: String?)
```
Replace with:
```swift
            typealias GitResult = (isRepo: Bool, branch: String, hasRemote: Bool,
                                   ahead: Int, behind: Int,
                                   entries: [(path: String, x: Character, y: Character, attr: NSAttributedString)],
                                   projectName: String, topLevel: String?, lastCommit: String?)
```

**Step 3: Fetch lastCommit in background block**

After the `entries` loop in the background block, find (~line 10688):
```swift
                    let projectName = (cwd as NSString).lastPathComponent
                    cont.resume(returning: (isRepo, branch, hasRemote, aheadCount, behindCount, entries, projectName, topLevel))
```
Replace with:
```swift
                    let projectName = (cwd as NSString).lastPathComponent
                    let lastCommit = isRepo ? self.runGit(["log", "-1", "--pretty=format:%h %s"], cwd: cwd) : nil
                    cont.resume(returning: (isRepo, branch, hasRemote, aheadCount, behindCount, entries, projectName, topLevel, lastCommit))
```

**Step 4: Store result in UI update block**

In the UI update block, after `self.fileEntries = result.entries` (~line 10700), add:
```swift
            self.lastCommitSummary = result.lastCommit
```

**Step 5: Build**
```bash
cd "/Users/l3v0/Desktop/FERTIGE PROJEKTE/SystemTrayTerminal" && bash build.sh 2>&1 | tail -8
```
Expected: 202 tests pass.

---

### Task 2: Add UI properties + build undo row in buildCommitCard()

**Files:**
- Modify: `systemtrayterminal.swift` — UI properties section (~line 9869) and `buildCommitCard()` (~line 10228)

**Step 1: Declare UI properties**

In `// MARK: - UI: Commit Card` section (~line 9869), after `private let feedbackLabel = NSTextField(labelWithString: "")`, add:
```swift
    private let undoCommitRow = NSStackView()
    private let undoCommitLabel = NSTextField(labelWithString: "")
    private let undoCommitBtn = NSButton()
```

**Step 2: Build undo row in buildCommitCard()**

In `buildCommitCard()`, find the line (~line 10280):
```swift
        let inner = NSStackView(views: [commitHeaderLabel, commitField, saveBtn, feedbackLabel])
```
Replace with:
```swift
        undoCommitLabel.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        undoCommitLabel.textColor = NSColor(calibratedWhite: 0.4, alpha: 1.0)
        undoCommitLabel.translatesAutoresizingMaskIntoConstraints = false
        undoCommitLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        undoCommitBtn.title = "↩"
        undoCommitBtn.isBordered = false
        undoCommitBtn.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        undoCommitBtn.contentTintColor = NSColor(calibratedWhite: 0.35, alpha: 1.0)
        undoCommitBtn.target = self
        undoCommitBtn.action = #selector(undoCommitClicked)
        undoCommitBtn.translatesAutoresizingMaskIntoConstraints = false
        undoCommitBtn.setContentHuggingPriority(.required, for: .horizontal)

        undoCommitRow.orientation = .horizontal
        undoCommitRow.spacing = 6
        undoCommitRow.alignment = .centerY
        undoCommitRow.translatesAutoresizingMaskIntoConstraints = false
        undoCommitRow.addArrangedSubview(undoCommitLabel)
        undoCommitRow.addArrangedSubview(undoCommitBtn)

        let inner = NSStackView(views: [commitHeaderLabel, commitField, saveBtn, feedbackLabel, undoCommitRow])
```

Also after the `inner` setup lines (spacing, alignment, etc.), add custom spacing before the undo row so it has visual separation. After `inner.spacing = 8` and `inner.translatesAutoresizingMaskIntoConstraints = false` and before `commitCard.addSubview(inner)`, add:
```swift
        inner.setCustomSpacing(12, after: feedbackLabel)
```

And add the undoCommitRow width constraint inside the `NSLayoutConstraint.activate([...])` block, after `feedbackLabel.widthAnchor.constraint(equalTo: inner.widthAnchor),`:
```swift
            undoCommitRow.widthAnchor.constraint(equalTo: inner.widthAnchor),
```

**Step 3: Build**
```bash
cd "/Users/l3v0/Desktop/FERTIGE PROJEKTE/SystemTrayTerminal" && bash build.sh 2>&1 | tail -8
```
Expected: 202 tests pass. Undo row now exists in the commit card (hidden until Step 4 wires it up).

---

### Task 3: Wire updateLayout to show/update undo row

**Files:**
- Modify: `systemtrayterminal.swift` — `updateLayout(projectName:)` (~line 10722)

**Step 1: Update undoCommitRow in updateLayout**

In `updateLayout(projectName:)`, after `updateGithubCard()` (~line 10747), add:
```swift
        if let summary = lastCommitSummary {
            let truncated = summary.count > 35 ? String(summary.prefix(35)) + "…" : summary
            undoCommitLabel.stringValue = truncated
            undoCommitRow.isHidden = false
        } else {
            undoCommitRow.isHidden = true
        }
```

**Step 2: Also reset confirm state when layout changes repo**

Just above the `undoCommitRow` update, add:
```swift
        if !isGitRepo { resetUndoConfirmState() }
```

**Step 3: Build**
```bash
cd "/Users/l3v0/Desktop/FERTIGE PROJEKTE/SystemTrayTerminal" && bash build.sh 2>&1 | tail -8
```
Expected: 202 tests pass. The undo row now shows the last commit message when inside a git repo.

---

### Task 4: Implement undoCommitClicked action + resetUndoConfirmState

**Files:**
- Modify: `systemtrayterminal.swift` — near `// MARK: - Actions: Save` (~line 10921)

**Step 1: Add the two methods after `saveClicked` action block**

Find `// MARK: - Actions: Upload (Push)` (~line 10955). Add before it:

```swift
    // MARK: - Actions: Undo Last Commit

    @objc private func undoCommitClicked() {
        if !undoConfirmPending {
            undoConfirmPending = true
            undoCommitBtn.title = "Sicher?"
            undoCommitBtn.contentTintColor = NSColor(calibratedRed: 1.0, green: 0.35, blue: 0.35, alpha: 1.0)
            undoConfirmTimer?.invalidate()
            undoConfirmTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { [weak self] _ in
                self?.resetUndoConfirmState()
            }
        } else {
            resetUndoConfirmState()
            let cwd = lastCwd
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                let result = self.runGitAction(["reset", "--soft", "HEAD~1"], cwd: cwd)
                DispatchQueue.main.async {
                    if result.success {
                        self.showFeedback("Commit zurückgesetzt", success: true)
                        self.refresh()
                    } else {
                        self.showFeedback(result.output.isEmpty ? "Reset fehlgeschlagen" : result.output, success: false)
                    }
                }
            }
        }
    }

    private func resetUndoConfirmState() {
        undoConfirmTimer?.invalidate()
        undoConfirmTimer = nil
        undoConfirmPending = false
        undoCommitBtn.title = "↩"
        undoCommitBtn.contentTintColor = NSColor(calibratedWhite: 0.35, alpha: 1.0)
    }
```

**Step 2: Also invalidate undoConfirmTimer in deinit**

Find `deinit` in `GitPanelView` (~line 11098). After `stopWatchers()` add:
```swift
        undoConfirmTimer?.invalidate()
```

**Step 3: Build + full test**
```bash
cd "/Users/l3v0/Desktop/FERTIGE PROJEKTE/SystemTrayTerminal" && bash build.sh 2>&1 | tail -8
```
Expected: 202 tests pass.

**Step 4: Manual smoke test**
1. Open a git repo in the terminal
2. Check git panel — commit card should show last commit below the save button
3. Click `↩` → button turns red, shows "Sicher?"
4. Wait 4s → button resets to `↩` (timeout works)
5. Click `↩` again, then quickly click again → `git reset --soft HEAD~1` runs, feedback appears, file list updates

---

### Task 5: Commit

```bash
cd "/Users/l3v0/Desktop/FERTIGE PROJEKTE/SystemTrayTerminal"
git add systemtrayterminal.swift docs/plans/2026-03-19-git-undo-commit.md
git commit -m "feat(git-panel): undo last commit button with 2-click soft reset"
```
