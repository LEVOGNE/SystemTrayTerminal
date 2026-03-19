# Git Panel Reactivity — Design

**Date:** 2026-03-19  
**Status:** Approved

## Problem
Git panel polls every 3s. After terminal git commands (reset, add, commit), user waits up to 3s for update.

## Solution

### 1. File System Watcher
- `DispatchSource.makeFileSystemObjectSource` on `.git/HEAD` + `.git/index`
- Events: `.write` → main queue → `refresh()`
- Cleanup on `stopRefreshing()` and `updateCwd()`

### 2. Refresh Button (↻)
- Small button in header card, right side next to branch badge
- Calls `refresh()` on tap
- Animated rotation while `isRefreshing == true`

### 3. Timer
- Interval: 3s → 5s (watcher handles real-time, timer is safety-net only)
