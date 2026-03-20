# Smart Git Sync — Design Doc
Date: 2026-03-20

## Problem
1. `refresh()` berechnet ahead/behind ohne `git fetch` → Remote-Stand ist veraltet, neue Commits von Kollegen werden nicht angezeigt.
2. `updateClicked()` macht nur `git pull` ohne Stash-Handling → schlägt fehl bei Dirty-Tree.
3. Keine Conflict-Erkennung: Bei overlapping Edits gehen Änderungen verloren oder der Pull bricht unkontrolliert ab.

## Solution: Approach A — Stash → Fetch → Pull(patience) → Pop

### Fix 1: refresh() — git fetch vor ahead/behind Check
In `DispatchQueue.global` Block, vor dem `rev-list`-Aufruf:
```swift
if hasRemote { _ = self.runGit(["fetch", "--quiet"], cwd: cwd) }
```

### Fix 2: updateClicked() — Smart Pull Funktion
Ersetze das nackte `git pull` durch `smartPull(cwd:)`:

**Flow:**
1. `git fetch --quiet` (Remote-Refs aktualisieren)
2. Check dirty tree via `git status --porcelain`
3. Wenn dirty: `git stash push -m "STT auto-stash before pull"`
4. `git pull --strategy=recursive -X patience` (bessere Merge-Qualität)
5. **Wenn Pull-Konflikt:**
   - `git merge --abort`
   - `git stash pop` (wenn gestasht)
   - Fehlermeldung: "Konflikt in: <Datei-Liste>. Bitte manuell lösen."
   - Return
6. **Wenn Pull ok + gestasht:** `git stash pop`
7. **Wenn Stash-Pop-Konflikt:** Warnung "Auto-stash konnte nicht zurückgespielt werden" — kein Abort (Merge bereits erfolgreich)

## Conflict Detection Helper
`conflictedFiles(cwd:) -> [String]`: liest `git diff --name-only --diff-filter=U` nach fehlgeschlagenem Merge.

## Error Messages (Loc)
Neue Keys:
- `smartPullConflict`: "Konflikt in: %@\nBitte manuell im Terminal lösen."
- `smartPullStashFailed`: "Stash konnte nicht zurückgespielt werden."

## What does NOT change
- Push-Button-Logik bleibt unverändert
- GitHub API Calls (fetchRemoteCommits etc.) bleiben unverändert
- `runGit` / `runGitAction` Hilfsfunktionen bleiben unverändert
