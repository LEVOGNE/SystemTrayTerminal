# Smart Git Sync Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix stale ahead/behind detection and add smart pull with auto-stash, patience merge, and conflict abort+report.

**Architecture:** Three changes in `systemtrayterminal.swift`: (1) `git fetch` before `rev-list` in `refresh()`, (2) new `smartPull(cwd:)` + `conflictedFiles(cwd:)` helpers, (3) new Loc strings in all 10 languages. `updateClicked()` calls `smartPull` instead of bare `git pull`.

**Tech Stack:** Swift, AppKit, macOS git CLI (`/usr/bin/git`)

---

### Task 1: Add Loc strings (static vars + all 10 language dicts)

**Files:**
- Modify: `systemtrayterminal.swift:205` (static vars)
- Modify: `systemtrayterminal.swift:299` (EN dict)
- Modify: `systemtrayterminal.swift:368` (DE dict)
- Modify: `systemtrayterminal.swift:437` (TR dict)
- Modify: `systemtrayterminal.swift:506` (ES dict)
- Modify: `systemtrayterminal.swift:575` (FR dict)
- Modify: `systemtrayterminal.swift:644` (IT dict)
- Modify: `systemtrayterminal.swift:713` (AR dict)
- Modify: `systemtrayterminal.swift:782` (JA dict)
- Modify: `systemtrayterminal.swift:851` (ZH dict)
- Modify: `systemtrayterminal.swift:920` (RU dict)

**Step 1: Add static vars after line 205**

After:
```swift
    static var upToDate: String     { t("upToDate") }
```
Insert:
```swift
    static func smartPullConflict(_ files: String) -> String { String(format: t("smartPullConflict"), files) }
    static var smartPullStashFailed: String { t("smartPullStashFailed") }
```

**Step 2: Add to EN dict (after line 299)**

After:
```
            "upToDate": "✓  All up to date",
```
Insert:
```
            "smartPullConflict": "⚠  Conflict in: %@\nPlease resolve manually in Terminal.",
            "smartPullStashFailed": "⚠  Pull ok, but auto-stash could not be restored. Check `git stash list`.",
```

**Step 3: Add to DE dict (after line 368)**

After:
```
            "upToDate": "✓  Alles auf dem aktuellen Stand",
```
Insert:
```
            "smartPullConflict": "⚠  Konflikt in: %@\nBitte manuell im Terminal lösen.",
            "smartPullStashFailed": "⚠  Pull ok, aber Auto-Stash konnte nicht zurückgespielt werden. Prüfe `git stash list`.",
```

**Step 4: Add to TR dict (after line 437)**

After:
```
            "upToDate": "✓  Her şey güncel",
```
Insert:
```
            "smartPullConflict": "⚠  Çakışma: %@\nLütfen terminalde manuel olarak çöz.",
            "smartPullStashFailed": "⚠  Pull tamam, ancak otomatik stash geri yüklenemedi. `git stash list` kontrol et.",
```

**Step 5: Add to ES dict (after line 506)**

After:
```
            "upToDate": "✓  Todo al día",
```
Insert:
```
            "smartPullConflict": "⚠  Conflicto en: %@\nPor favor, resuélvelo manualmente en Terminal.",
            "smartPullStashFailed": "⚠  Pull ok, pero no se pudo restaurar el auto-stash. Comprueba `git stash list`.",
```

**Step 6: Add to FR dict (after line 575)**

After:
```
            "upToDate": "✓  Tout à jour",
```
Insert:
```
            "smartPullConflict": "⚠  Conflit dans : %@\nVeuillez résoudre manuellement dans le Terminal.",
            "smartPullStashFailed": "⚠  Pull ok, mais l'auto-stash n'a pas pu être restauré. Vérifiez `git stash list`.",
```

**Step 7: Add to IT dict (after line 644)**

After:
```
            "upToDate": "✓  Tutto aggiornato",
```
Insert:
```
            "smartPullConflict": "⚠  Conflitto in: %@\nRisolvi manualmente nel Terminale.",
            "smartPullStashFailed": "⚠  Pull ok, ma l'auto-stash non è stato ripristinato. Controlla `git stash list`.",
```

**Step 8: Add to AR dict (after line 713)**

After:
```
            "upToDate": "✓  كل شيء محدث",
```
Insert:
```
            "smartPullConflict": "⚠  تعارض في: %@\nيرجى الحل يدوياً في الطرفية.",
            "smartPullStashFailed": "⚠  Pull ناجح، لكن تعذّر استعادة الـ stash التلقائي. تحقق من `git stash list`.",
```

**Step 9: Add to JA dict (after line 782)**

After:
```
            "upToDate": "✓  すべて最新",
```
Insert:
```
            "smartPullConflict": "⚠  コンフリクト: %@\nターミナルで手動解決してください。",
            "smartPullStashFailed": "⚠  Pull成功、ただし自動stashを復元できませんでした。`git stash list` を確認。",
```

**Step 10: Add to ZH dict (after line 851)**

After:
```
            "upToDate": "✓  一切都是最新的",
```
Insert:
```
            "smartPullConflict": "⚠  冲突文件: %@\n请在终端手动解决。",
            "smartPullStashFailed": "⚠  Pull 成功，但自动 stash 无法恢复。请检查 `git stash list`。",
```

**Step 11: Add to RU dict (after line 920)**

After:
```
            "upToDate": "✓  Всё актуально",
```
Insert:
```
            "smartPullConflict": "⚠  Конфликт в: %@\nПожалуйста, разрешите вручную в Терминале.",
            "smartPullStashFailed": "⚠  Pull выполнен, но auto-stash не восстановлен. Проверь `git stash list`.",
```

**Step 12: Build to verify no compile errors**

```bash
bash build.sh
```
Expected: BUILD SUCCEEDED, all tests pass

---

### Task 2: Add git fetch to refresh()

**Files:**
- Modify: `systemtrayterminal.swift:10710`

**Step 1: Insert fetch before rev-list**

Find this block (around line 10710):
```swift
                    var aheadCount = 0, behindCount = 0
                    if hasRemote, let ab = self.runGit(["rev-list", "--left-right", "--count", "HEAD...@{upstream}"], cwd: cwd) {
```

Replace with:
```swift
                    var aheadCount = 0, behindCount = 0
                    if hasRemote { _ = self.runGit(["fetch", "--quiet"], cwd: cwd) }
                    if hasRemote, let ab = self.runGit(["rev-list", "--left-right", "--count", "HEAD...@{upstream}"], cwd: cwd) {
```

**Step 2: Build**

```bash
bash build.sh
```
Expected: BUILD SUCCEEDED

---

### Task 3: Add smartPull + conflictedFiles helpers

**Files:**
- Modify: `systemtrayterminal.swift` — insert after `runGitAction` function (around line 10683)

**Step 1: Insert after closing brace of `runGitAction` (line 10683)**

After:
```swift
    private func runGitAction(_ args: [String], cwd: String) -> (success: Bool, output: String) {
        ...
    }
```

Insert this new block:
```swift
    // Returns files with unresolved merge conflicts (diff-filter U = Unmerged)
    private func conflictedFiles(cwd: String) -> [String] {
        guard let out = runGit(["diff", "--name-only", "--diff-filter=U"], cwd: cwd), !out.isEmpty else { return [] }
        return out.split(separator: "\n").map(String.init)
    }

    // Smart pull: fetch → optional stash → pull(patience) → pop stash
    // Returns (success, userFacingMessage)
    private func smartPull(cwd: String) -> (success: Bool, message: String) {
        // 1. Fetch to update remote refs (so @{upstream} is current)
        _ = runGitAction(["fetch", "--quiet"], cwd: cwd)

        // 2. Stash dirty working tree if needed
        let porcelain = runGit(["status", "--porcelain"], cwd: cwd) ?? ""
        let isDirty = !porcelain.isEmpty
        var stashed = false
        if isDirty {
            let s = runGitAction(["stash", "push", "-m", "STT auto-stash before pull"], cwd: cwd)
            if !s.success { return (false, "Could not stash local changes:\n\(s.output)") }
            stashed = true
        }

        // 3. Pull with recursive+patience for best auto-merge quality
        let pull = runGitAction(["pull", "--strategy=recursive", "-X", "patience"], cwd: cwd)

        if !pull.success {
            // Abort the pending merge, restore stash, report conflicted files
            _ = runGitAction(["merge", "--abort"], cwd: cwd)
            if stashed { _ = runGitAction(["stash", "pop"], cwd: cwd) }
            let files = conflictedFiles(cwd: cwd)
            let fileList = files.isEmpty ? pull.output : files.joined(separator: ", ")
            return (false, Loc.smartPullConflict(fileList))
        }

        // 4. Restore stash
        if stashed {
            let pop = runGitAction(["stash", "pop"], cwd: cwd)
            if !pop.success { return (true, Loc.smartPullStashFailed) }
        }

        return (true, Loc.updated)
    }
```

**Step 2: Build**

```bash
bash build.sh
```
Expected: BUILD SUCCEEDED

---

### Task 4: Wire updateClicked() to smartPull

**Files:**
- Modify: `systemtrayterminal.swift:11114`

**Step 1: Replace updateClicked body**

Find:
```swift
    @objc private func updateClicked() {
        updateBtn.isEnabled = false
        let cwd = lastCwd
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let result = self.runGitAction(["pull"], cwd: cwd)
            DispatchQueue.main.async {
                self.updateBtn.isEnabled = true
                self.showFeedback(result.success ? Loc.updated : "Error: \(result.output)", success: result.success)
                self.github.cache.lastFetch = .distantPast
                self.refresh()
            }
        }
    }
```

Replace with:
```swift
    @objc private func updateClicked() {
        updateBtn.isEnabled = false
        let cwd = lastCwd
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let result = self.smartPull(cwd: cwd)
            DispatchQueue.main.async {
                self.updateBtn.isEnabled = true
                self.showFeedback(result.message, success: result.success)
                self.github.cache.lastFetch = .distantPast
                self.refresh()
            }
        }
    }
```

**Step 2: Final build + tests**

```bash
bash build.sh
```
Expected: BUILD SUCCEEDED, all 180 tests pass

---

### Task 5: Manual smoke test checklist

Open STT, navigate to a git repo with a remote, then verify:

- [ ] Git panel opens → ahead/behind count is current (fetch happens in background)
- [ ] Colleague pushes a commit → clicking Refresh in panel shows "↓ 1 new change available"
- [ ] Clicking Update with clean working tree → `✓  Updated!` (or localized equivalent)
- [ ] Clicking Update with local uncommitted changes → stash is created, pull succeeds, stash is popped, local changes still present
- [ ] Simulated conflict (manually create a MERGE_HEAD conflict scenario) → Feedback shows "⚠  Konflikt in: filename.swift\n..."
