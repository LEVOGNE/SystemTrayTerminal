# Git Undo Last Commit — Design

**Date:** 2026-03-19  
**Status:** Approved

## Feature
One-click soft reset of last commit from the git panel UI.

## UI
New row at bottom of commit card:
- Small label showing last commit short hash + message (truncated)
- `↩` undo button on the right

## UX Flow
1. Normal state: `↩ abc1234: Fix login bug` + grey `↩` button
2. First click: button turns red, label → `"Sicher?"`, 4s timeout to reset back
3. Second click: run `git reset --soft HEAD~1`, refresh, show feedback
4. Edge case: no parent commit → button disabled

## Git Commands
- Fetch: `git log -1 --pretty=format:%h %s` (added to GitResult in refresh)
- Action: `git reset --soft HEAD~1`

## Implementation Notes
- New state var `lastCommitSummary: String?` in GitResult
- New UI: `undoCommitRow` NSView added to commitCard
- 2-click confirmation timer (4s) matches existing reset button pattern
