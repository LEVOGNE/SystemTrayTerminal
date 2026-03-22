# History Autocompletion — Design

**Date:** 2026-03-22
**Status:** Approved

## Overview

Inline ghost-text history suggestion + arrow-key history cycling, entirely at the terminal emulator level (no shell configuration needed).

## Components

### typedBuffer: String
Tracks locally what the user has typed since the last prompt reset.

- Printable key → append
- Backspace → remove last char
- Enter / Ctrl+C / Ctrl+U → clear
- Only active when `terminal.altScreenActive == false` AND `terminal.mouseMode == 0`

### historyEntries: [String]
Loaded from `~/.zsh_history` (`:timestamp:0;command` format) or `~/.bash_history` (plain lines). Deduplicated, preserving recency order (newest at front after dedup). Loaded on init, refreshed when window becomes key.

### Ghost-Text Rendering (draw())
When `typedBuffer` is non-empty and a history match exists:
- Find best match = most recent entry with `typedBuffer` as prefix
- Render suffix (match.dropFirst(typedBuffer.count)) right of cursor, in dim ANSI color 8 (dark grey)
- Does NOT modify actual terminal grid — overlay-only

## Arrow Key History Cycling

- `typedBuffer` empty → send raw Up/Down to PTY (normal shell behavior)
- `typedBuffer` non-empty → intercept:
  - Build `historyMatches` = all entries starting with `typedBuffer` prefix, newest first
  - Up → cycle to next older match: send `Ctrl+U` + match to PTY, update `typedBuffer = match`
  - Down → cycle to next newer match, or back to original `typedBuffer` if at start

State: `historyCycleIndex: Int = -1` (-1 = not cycling)

## Accepting Ghost-Text

Tab or → (without modifier, only when ghost-text is visible):
- Send suffix characters to PTY
- Update `typedBuffer` to full match

## Deactivation

Feature is fully disabled when:
- `terminal.altScreenActive == true` (vim, htop, less, etc.)
- `terminal.mouseMode != 0` (TUI app active)

These checks happen in `keyDown` before interception logic.

## Files Changed

- `systemtrayterminal.swift`: new properties + methods in `TerminalView`, updated `keyDown`, updated `draw()`
