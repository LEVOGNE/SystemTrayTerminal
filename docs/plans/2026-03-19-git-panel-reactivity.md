# Git Panel Reactivity Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Git panel reacts instantly (< 100ms) to terminal git commands via DispatchSource file watchers, plus a manual refresh button and a 5s safety-net timer.

**Architecture:** Add two `DispatchSourceFileSystemObject` watchers on `.git/HEAD` + `.git/index`. Each watcher calls `refresh()` on `.main` queue when files change. Refresh button added to header card. Timer interval: 3s → 5s.

**Tech Stack:** Swift, AppKit, POSIX `open(O_EVTONLY)`, `DispatchSource.makeFileSystemObjectSource`

---

### Task 1: Add watcher properties + helper methods to GitPanelView

**Files:**
- Modify: `systemtrayterminal.swift` — `GitPanelView` state section (~line 9808)

**Step 1: Add properties**

Find the `// MARK: - State & Data` block at ~line 9808. After `private var feedbackTimer: Timer?` add:

```swift
    private var gitWatchers: [DispatchSourceFileSystemObject] = []
    private var watchedGitRoot = ""
```

**Step 2: Add `stopWatchers()` helper**

Add right before `// MARK: - Public API (called by AppDelegate)` (~line 10517):

```swift
    private func stopWatchers() {
        gitWatchers.forEach { $0.cancel() }
        gitWatchers = []
        watchedGitRoot = ""
    }

    private func startWatchers(gitRoot: String) {
        guard gitRoot != watchedGitRoot else { return }
        stopWatchers()
        watchedGitRoot = gitRoot
        let paths = [gitRoot + "/.git/HEAD", gitRoot + "/.git/index"]
        for path in paths {
            let fd = open(path, O_EVTONLY)
            guard fd >= 0 else { continue }
            let src = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd, eventMask: .write, queue: .main)
            src.setEventHandler { [weak self] in self?.refresh() }
            src.setCancelHandler { close(fd) }
            src.resume()
            gitWatchers.append(src)
        }
    }
```

**Step 3: Build and check for compile errors**

```bash
bash build.sh 2>&1 | head -30
```
Expected: compiles fine (no errors).

---

### Task 2: Wire stopWatchers into stopRefreshing + updateCwd

**Files:**
- Modify: `systemtrayterminal.swift` — `stopRefreshing()` and `updateCwd()` (~lines 10535, 10528)

**Step 1: Update `stopRefreshing()`**

Current code (~line 10535):
```swift
    func stopRefreshing() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
```
Replace with:
```swift
    func stopRefreshing() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        stopWatchers()
    }
```

**Step 2: Update `updateCwd()`**

Current code (~line 10528):
```swift
    func updateCwd(_ cwd: String) {
        guard cwd != lastCwd else { return }
        lastCwd = cwd
        github.cache = GitHubClient.RemoteCache()
        refresh()
    }
```
Replace with:
```swift
    func updateCwd(_ cwd: String) {
        guard cwd != lastCwd else { return }
        lastCwd = cwd
        github.cache = GitHubClient.RemoteCache()
        stopWatchers()
        refresh()
    }
```

**Step 3: Build**
```bash
bash build.sh 2>&1 | head -30
```

---

### Task 3: Pass topLevel through GitResult + start watchers after refresh

**Files:**
- Modify: `systemtrayterminal.swift` — `refresh()` method (~lines 10595–10668)

**Step 1: Extend GitResult typealias**

Find (~line 10595):
```swift
            typealias GitResult = (isRepo: Bool, branch: String, hasRemote: Bool,
                                   ahead: Int, behind: Int,
                                   entries: [(path: String, x: Character, y: Character, attr: NSAttributedString)],
                                   projectName: String)
```
Replace with:
```swift
            typealias GitResult = (isRepo: Bool, branch: String, hasRemote: Bool,
                                   ahead: Int, behind: Int,
                                   entries: [(path: String, x: Character, y: Character, attr: NSAttributedString)],
                                   projectName: String, topLevel: String?)
```

**Step 2: Pass topLevel in `cont.resume`**

Find (~line 10646):
```swift
                    cont.resume(returning: (isRepo, branch, hasRemote, aheadCount, behindCount, entries, projectName))
```
Replace with:
```swift
                    cont.resume(returning: (isRepo, branch, hasRemote, aheadCount, behindCount, entries, projectName, topLevel))
```

**Step 3: Start watchers in UI update block**

After `self.updateLayout(...)` and `self.refreshGithubStatus(...)` (~line 10659), add:

```swift
            if result.isRepo, let top = result.topLevel {
                self.startWatchers(gitRoot: top)
            } else {
                self.stopWatchers()
            }
```

**Step 4: Change timer interval 3s → 5s**

Find (~line 10661):
```swift
            let newInterval: TimeInterval = result.isRepo ? 3.0 : 30.0
```
Replace with:
```swift
            let newInterval: TimeInterval = result.isRepo ? 5.0 : 30.0
```

Also in `startRefreshing(cwd:)` (~line 10523):
```swift
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
```
Change `3.0` → `5.0`.

**Step 5: Build**
```bash
bash build.sh 2>&1 | head -30
```

---

### Task 4: Add refresh button to header card

**Files:**
- Modify: `systemtrayterminal.swift` — `GitPanelView` properties (~line 9851) + `buildHeaderCard()` (~line 10093)

**Step 1: Declare refreshBtn property**

In `// MARK: - UI: Header Card` section (~line 9851), add after `private let statusLabel`:

```swift
    private let refreshBtn = NSButton()
```

**Step 2: Configure and wire in `buildHeaderCard()`**

In `buildHeaderCard()`, find the `topRow` creation (~line 10117):
```swift
        let topRow = NSStackView(views: [projectLabel, branchBadge])
        topRow.orientation = .horizontal
        topRow.spacing = 8
        topRow.alignment = .centerY
        topRow.translatesAutoresizingMaskIntoConstraints = false
```
Replace with:
```swift
        refreshBtn.title = "↻"
        refreshBtn.font = NSFont.systemFont(ofSize: 14, weight: .regular)
        refreshBtn.isBordered = false
        refreshBtn.contentTintColor = NSColor(calibratedWhite: 0.35, alpha: 1.0)
        refreshBtn.target = self
        refreshBtn.action = #selector(refreshBtnTapped)
        refreshBtn.translatesAutoresizingMaskIntoConstraints = false
        refreshBtn.setContentHuggingPriority(.required, for: .horizontal)

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let topRow = NSStackView(views: [projectLabel, branchBadge, spacer, refreshBtn])
        topRow.orientation = .horizontal
        topRow.spacing = 8
        topRow.alignment = .centerY
        topRow.translatesAutoresizingMaskIntoConstraints = false
```

**Step 3: Add `@objc func refreshBtnTapped()`**

Add near other `@objc` actions in the class:
```swift
    @objc private func refreshBtnTapped() {
        refresh()
    }
```

**Step 4: Build + test**
```bash
bash build.sh
```
Expected: Git panel now has a `↻` button in the top-right of the header card.

---

### Task 5: Manual smoke test

1. Open SystemTrayTerminal, navigate to a git repo in the terminal
2. Run `git reset HEAD~1` in the terminal tab
3. **Expected:** Git panel updates within ~1 second (watcher fires)
4. Click `↻` button → panel refreshes immediately
5. Run `git add .` → panel updates instantly
6. Run `git commit -m "test"` → panel updates instantly

---

### Task 6: Commit

```bash
cd "/Users/l3v0/Desktop/FERTIGE PROJEKTE/SystemTrayTerminal"
git add systemtrayterminal.swift docs/plans/2026-03-19-git-panel-reactivity.md docs/plans/2026-03-19-git-panel-reactivity-design.md
git commit -m "feat(git-panel): instant refresh via DispatchSource file watchers + refresh button"
```
