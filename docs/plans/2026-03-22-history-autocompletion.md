# History Autocompletion Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Inline ghost-text history suggestion (like zsh-autosuggestions) + arrow-key history cycling, entirely at the terminal emulator level.

**Architecture:** `TerminalView` tracks typed chars locally (`typedBuffer`), reads `~/.zsh_history` / `~/.bash_history`, renders ghost text in `draw()` after the cursor block, and intercepts Up/Down/Tab/→ in `keyDown` when appropriate. Disabled automatically when alt screen is active (vim, htop, etc.).

**Tech Stack:** Swift, AppKit, CoreText (same as existing draw pipeline)

---

### Task 1: New properties + history loader

**Files:**
- Modify: `systemtrayterminal.swift` — add after `// MARK: Mouse selection` block (around line 4087)

**Step 1: Add properties to TerminalView**

Insert these properties after `var selStart: (row: Int, col: Int)? = nil` (line 4087):

```swift
// MARK: History Autocompletion

/// Characters typed since last prompt reset (local tracking, no PTY involvement)
var typedBuffer: String = ""
/// All history entries, newest first, deduped
var historyEntries: [String] = []
/// Index into historyMatches during Up/Down cycling (-1 = not cycling)
private var historyCycleIndex: Int = -1
/// History matches for current prefix (built when cycling starts)
private var historyMatches: [String] = []
/// Currently shown suggestion (full command), or nil
private var currentSuggestion: String? = nil

/// Whether history features should be active right now
private var historyActive: Bool {
    terminal.altGrid == nil && terminal.mouseMode == 0
}

/// Load history from shell history files. Newest entries come first.
func loadHistory() {
    DispatchQueue.global(qos: .utility).async { [weak self] in
        var entries: [String] = []

        // zsh: ~/.zsh_history — format ": timestamp:elapsed;command" or plain
        let zshURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".zsh_history")
        if let raw = try? String(contentsOf: zshURL, encoding: .utf8) {
            for line in raw.components(separatedBy: "\n") {
                let cmd: String
                if line.hasPrefix(": "), let semi = line.firstIndex(of: ";") {
                    cmd = String(line[line.index(after: semi)...]).trimmingCharacters(in: .whitespaces)
                } else {
                    cmd = line.trimmingCharacters(in: .whitespaces)
                }
                if !cmd.isEmpty { entries.append(cmd) }
            }
        }

        // bash: ~/.bash_history — plain lines
        let bashURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".bash_history")
        if let raw = try? String(contentsOf: bashURL, encoding: .utf8) {
            for line in raw.components(separatedBy: "\n") {
                let cmd = line.trimmingCharacters(in: .whitespaces)
                if !cmd.isEmpty { entries.append(cmd) }
            }
        }

        // Reverse so newest is last, dedupe preserving last occurrence, then reverse again
        var seen = Set<String>()
        var deduped: [String] = []
        for e in entries.reversed() {
            if seen.insert(e).inserted { deduped.append(e) }
        }
        // deduped is now newest-first

        DispatchQueue.main.async {
            self?.historyEntries = deduped
        }
    }
}

/// Best (most recent) history entry with typedBuffer as prefix, or nil
func bestHistorySuggestion() -> String? {
    guard !typedBuffer.isEmpty else { return nil }
    return historyEntries.first { $0.hasPrefix(typedBuffer) && $0 != typedBuffer }
}

/// All history entries that start with prefix, newest first
func historyMatchesForPrefix(_ prefix: String) -> [String] {
    historyEntries.filter { $0.hasPrefix(prefix) }
}
```

**Step 2: Call loadHistory() when PTY becomes ready**

Find the line `if !shellReady { shellReady = true }` (around line 3356). Add after it:

```swift
if !shellReady {
    shellReady = true
    loadHistory()
}
```

**Step 3: Build to verify no errors**
```bash
cd "/Users/l3v0/Desktop/FERTIGE PROJEKTE/SystemTrayTerminal" && bash build.sh 2>&1 | tail -8
```
Expected: `Results: N passed, 0 failed`

**Step 4: Commit**
```bash
git add systemtrayterminal.swift
git commit -m "feat(history): add typedBuffer properties and loadHistory()"
```

---

### Task 2: Ghost-text rendering in draw()

**Files:**
- Modify: `systemtrayterminal.swift` — cursor draw section (around line 3758, after the cursor block ends with `}`)

**Step 1: Find insertion point**

The cursor block ends with:
```swift
            }
        }
    }

    // Sixel images (only in live view)
```

Insert ghost-text rendering between cursor block end and sixel images:

```swift
        // History ghost text — dim suggestion to the right of cursor
        if !isScrolledBack, historyActive, !typedBuffer.isEmpty,
           let suggestion = bestHistorySuggestion(),
           suggestion.count > typedBuffer.count {
            let suffix = String(suggestion.dropFirst(typedBuffer.count))
            let startCol = terminal.cursorX + 1
            let available = terminal.cols - startCol
            guard available > 0 else { break }  // no space
            let display = String(suffix.prefix(available))
            let gx = CGFloat(startCol) * cellW + paddingX
            let gy = CGFloat(terminal.cursorY) * cellH + paddingY
            let ghostColor = NSColor(white: 0.55, alpha: 0.7)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: ghostColor
            ]
            let attrStr = NSAttributedString(string: display, attributes: attrs)
            let line = CTLineCreateWithAttributedString(attrStr)
            ctx.textPosition = CGPoint(x: gx, y: gy + fontDescent)
            CTLineDraw(line, ctx)
            currentSuggestion = suggestion
        } else {
            currentSuggestion = nil
        }
```

Note: `break` won't work in this context. Replace `break` with just ending the if-block. The guard pattern should be:
```swift
        // History ghost text — dim suggestion to the right of cursor
        if !isScrolledBack, historyActive, !typedBuffer.isEmpty {
            if let suggestion = bestHistorySuggestion(), suggestion.count > typedBuffer.count {
                let suffix = String(suggestion.dropFirst(typedBuffer.count))
                let startCol = terminal.cursorX + 1
                let available = terminal.cols - startCol
                if available > 0 {
                    let display = String(suffix.prefix(available))
                    let gx = CGFloat(startCol) * cellW + paddingX
                    let gy = CGFloat(terminal.cursorY) * cellH + paddingY
                    let ghostColor = NSColor(white: 0.55, alpha: 0.7)
                    let ctFont = font as CTFont
                    let attrStr = NSAttributedString(string: display, attributes: [
                        .font: font,
                        .foregroundColor: ghostColor
                    ])
                    let ctLine = CTLineCreateWithAttributedString(attrStr)
                    ctx.textPosition = CGPoint(x: gx, y: gy + fontDescent)
                    CTLineDraw(ctLine, ctx)
                    currentSuggestion = suggestion
                } else {
                    currentSuggestion = nil
                }
            } else {
                currentSuggestion = nil
            }
        } else if isScrolledBack || !historyActive || typedBuffer.isEmpty {
            currentSuggestion = nil
        }
```

**Step 2: Build**
```bash
bash build.sh 2>&1 | tail -8
```

**Step 3: Commit**
```bash
git add systemtrayterminal.swift
git commit -m "feat(history): render ghost text in draw()"
```

---

### Task 3: keyDown — track typedBuffer + accept ghost text

**Files:**
- Modify: `systemtrayterminal.swift` — `keyDown` method

**Step 1: Clear typedBuffer on Enter (case 36)**

Find `case 36: writePTY("\r")` and change to:
```swift
case 36:
    typedBuffer = ""
    historyCycleIndex = -1
    historyMatches = []
    writePTY("\r")
```

**Step 2: Update typedBuffer on Backspace (case 51)**

Find `case 51: writePTY(Data([0x7F]))` and change to:
```swift
case 51:
    if !typedBuffer.isEmpty { typedBuffer.removeLast() }
    historyCycleIndex = -1
    writePTY(Data([0x7F]))
```

**Step 3: Accept ghost text on Tab (case 48)**

Find `case 48: writePTY(nsf.contains(.shift) ? "\u{1B}[Z" : "\t")` and change to:
```swift
case 48:
    if !nsf.contains(.shift), historyActive,
       let sug = currentSuggestion, sug.count > typedBuffer.count {
        // Accept ghost: send suffix to PTY
        let suffix = String(sug.dropFirst(typedBuffer.count))
        typedBuffer = sug
        historyCycleIndex = -1
        writePTY(suffix)
    } else {
        writePTY(nsf.contains(.shift) ? "\u{1B}[Z" : "\t")
    }
```

**Step 4: Accept ghost text on Right arrow without modifier (case 124)**

Find:
```swift
case 124: writePTY(hasMod ? "\u{1B}[1;\(mod)C" : "\u{1B}\(terminal.appCursorMode ? "O" : "[")C")
```
Change to:
```swift
case 124:
    if !hasMod, historyActive,
       let sug = currentSuggestion, sug.count > typedBuffer.count {
        let suffix = String(sug.dropFirst(typedBuffer.count))
        typedBuffer = sug
        historyCycleIndex = -1
        writePTY(suffix)
    } else {
        writePTY(hasMod ? "\u{1B}[1;\(mod)C" : "\u{1B}\(terminal.appCursorMode ? "O" : "[")C")
    }
```

**Step 5: Update typedBuffer in default (printable chars)**

Find `default:` in the switch (at `if let chars = event.characters`):
```swift
default:
    if let chars = event.characters, !chars.isEmpty { writePTY(chars) }
```
Change to:
```swift
default:
    if let chars = event.characters, !chars.isEmpty {
        // Track printable chars (skip non-printable control chars)
        if historyActive, let scalar = chars.unicodeScalars.first,
           scalar.value >= 32 && scalar.value != 127 {
            typedBuffer += chars
            historyCycleIndex = -1
        }
        writePTY(chars)
    }
```

**Step 6: Clear typedBuffer on Ctrl+C and Ctrl+U**

Find the `flags.contains(.control)` block:
```swift
if flags.contains(.control) {
    if let c = event.charactersIgnoringModifiers?.unicodeScalars.first {
        let v = c.value
        if v >= 0x61 && v <= 0x7A { writePTY(Data([UInt8(v - 0x60)])); return }
```
Change to:
```swift
if flags.contains(.control) {
    if let c = event.charactersIgnoringModifiers?.unicodeScalars.first {
        let v = c.value
        // Clear typed buffer on Ctrl+C (0x63=c→0x03) and Ctrl+U (0x75=u→0x15)
        if v == 0x63 || v == 0x75 { typedBuffer = ""; historyCycleIndex = -1; historyMatches = [] }
        if v >= 0x61 && v <= 0x7A { writePTY(Data([UInt8(v - 0x60)])); return }
```

**Step 7: Build**
```bash
bash build.sh 2>&1 | tail -8
```

**Step 8: Commit**
```bash
git add systemtrayterminal.swift
git commit -m "feat(history): track typedBuffer and accept ghost text on Tab/Right"
```

---

### Task 4: keyDown — Up/Down arrow history cycling

**Files:**
- Modify: `systemtrayterminal.swift` — `keyDown` switch cases 126 (Up) and 125 (Down)

**Step 1: Replace Up arrow (case 126)**

Find:
```swift
case 126: writePTY(hasMod ? "\u{1B}[1;\(mod)A" : "\u{1B}\(terminal.appCursorMode ? "O" : "[")A")
```
Replace with:
```swift
case 126: // Up arrow
    if !hasMod, historyActive, !typedBuffer.isEmpty {
        // First Up: build match list from current typedBuffer prefix
        if historyCycleIndex == -1 {
            historyMatches = historyMatchesForPrefix(typedBuffer)
            if historyMatches.isEmpty {
                writePTY(hasMod ? "\u{1B}[1;\(mod)A" : "\u{1B}\(terminal.appCursorMode ? "O" : "[")A")
                break
            }
            historyCycleIndex = 0
        } else {
            historyCycleIndex = min(historyCycleIndex + 1, historyMatches.count - 1)
        }
        let match = historyMatches[historyCycleIndex]
        // Clear current line and replace with match
        writePTY(Data([0x15]))  // Ctrl+U: kill line
        writePTY(match)
        typedBuffer = match
        dirty = true; needsDisplay = true
    } else {
        writePTY(hasMod ? "\u{1B}[1;\(mod)A" : "\u{1B}\(terminal.appCursorMode ? "O" : "[")A")
    }
```

**Step 2: Replace Down arrow (case 125)**

Find:
```swift
case 125: writePTY(hasMod ? "\u{1B}[1;\(mod)B" : "\u{1B}\(terminal.appCursorMode ? "O" : "[")B")
```
Replace with:
```swift
case 125: // Down arrow
    if !hasMod, historyActive, historyCycleIndex >= 0 {
        historyCycleIndex -= 1
        if historyCycleIndex < 0 {
            // Back to original typed text — send Ctrl+U + original
            // We can't recover the original text easily, so just clear
            writePTY(Data([0x15]))
            typedBuffer = ""
            historyMatches = []
            historyCycleIndex = -1
        } else {
            let match = historyMatches[historyCycleIndex]
            writePTY(Data([0x15]))
            writePTY(match)
            typedBuffer = match
        }
        dirty = true; needsDisplay = true
    } else {
        writePTY(hasMod ? "\u{1B}[1;\(mod)B" : "\u{1B}\(terminal.appCursorMode ? "O" : "[")B")
    }
```

**Step 3: Build**
```bash
bash build.sh 2>&1 | tail -8
```
Expected: all tests pass.

**Step 4: Commit**
```bash
git add systemtrayterminal.swift
git commit -m "feat(history): Up/Down arrow history cycling when text is typed"
```

---

### Task 5: Refresh history on window focus + edge cases

**Files:**
- Modify: `systemtrayterminal.swift`

**Step 1: Reload history when window becomes key**

Find `override func viewDidMoveToWindow()` or `becomeFirstResponder`. If neither exists, add to `windowDidBecomeKey` or observe `NSWindow.didBecomeKeyNotification`. Best: find where `shellReady = true` was updated in Task 1, and also add a notification observer in the TerminalView init or startPTY.

Actually the simplest place: in `keyDown`, at the very top, add a lazy refresh: when `historyEntries.isEmpty && shellReady`, call `loadHistory()`. But that fires every keyDown. Better: add a `var historyLoaded = false` flag.

Change the `if !shellReady { shellReady = true; loadHistory() }` from Task 1 to:

```swift
if !shellReady {
    shellReady = true
    loadHistory()
}
```

That's already done. Add a `historyLoaded` check so we don't double-load:

Actually the current design is fine — `loadHistory()` is async and replaces the array each time. Calling it once on shellReady is sufficient.

**Step 2: Clear typedBuffer when Escape is pressed (optional cleanup)**

Find `case 53: writePTY(Data([0x1B]))`. Add:
```swift
case 53:
    typedBuffer = ""
    historyCycleIndex = -1
    historyMatches = []
    writePTY(Data([0x1B]))
```

**Step 3: Build + test**
```bash
bash build.sh 2>&1 | tail -8
```

**Step 4: Deploy to /Applications for manual testing**
```bash
bash build_app.sh && rm -rf /Applications/SystemTrayTerminal.app && cp -R SystemTrayTerminal.app /Applications/
```

Manual test checklist:
- [ ] Type "echo" → see grey ghost text showing last "echo ..." command
- [ ] Press Tab → ghost text accepted (rest of command typed into shell)
- [ ] Press → (no modifier) → ghost text accepted
- [ ] Press Up → cycles through "echo" commands, replacing line each time
- [ ] Press Down → cycles back toward newer entries, then clears
- [ ] Run `vim` → no ghost text appears (alt screen active)
- [ ] Run `htop` → no ghost text (mouseMode != 0)
- [ ] Press Ctrl+C → typedBuffer cleared, ghost text disappears
- [ ] Normal Up/Down with empty input → still sends Up/Down to shell (normal history)

**Step 5: Commit**
```bash
git add systemtrayterminal.swift
git commit -m "feat(history): Escape clears typedBuffer, edge case cleanup"
```

---

### Task 6: Update MEMORY.md

**Files:**
- Modify: `/Users/l3v0/.claude/projects/-Users-l3v0-Desktop-FERTIGE-PROJEKTE-SystemTrayTerminal/memory/MEMORY.md`

Add a section "History Autocompletion (v1.5.9+)" with:
- `typedBuffer: String` — tracks typed chars since last prompt reset
- `historyEntries: [String]` — loaded from zsh/bash history, newest first
- `historyCycleIndex: Int` — position in Up/Down cycling
- `loadHistory()` called once on shellReady=true
- `historyActive` = `terminal.altGrid == nil && terminal.mouseMode == 0`
- Ghost text rendered after cursor block in `draw()`
- Up/Down only intercepted when `!hasMod && historyActive && !typedBuffer.isEmpty`
