# .gitignore Manager — Design

**Date:** 2026-03-19  
**Status:** Approved

## Feature
Per-file "add to .gitignore" from the git panel file list.

## UI
- Each ClickableFileRow: `✕` button at trailing edge, alpha 0 default, 1.0 on hover
- Right-click → context menu "Zu .gitignore hinzufügen"
- Both trigger the same `onIgnore` callback

## Logic (addToGitignore)
1. Read `<gitRoot>/.gitignore` (or empty string if not exists)
2. Check if path already present → feedback if so
3. Append path + newline, write atomically
4. showFeedback + refresh()

## Changes
- `ClickableFileRow`: onIgnore callback, ignoreBtn, menu(for:) override, hover alpha
- `rebuildFilesStack()`: set row.onIgnore
- New `addToGitignore(path:)` in GitPanelView
