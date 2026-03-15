# Text Editor Tab — Design Document
Date: 2026-03-15

## Overview

Add a full-featured plain-text/code editor as a first-class tab type in quickTerminal.
Editor tabs live alongside terminal tabs in the same tab bar.
Files can be opened via drag-onto-tab-bar, Cmd+O, or Cmd+N (new empty file).
The `+` button shows a long-press dropdown: "Terminal" or "Text Editor".

---

## 1. Tab System Extension

```swift
enum TabType { case terminal, editor }

struct TabState {
    // existing fields ...
    var tabType: TabType = .terminal
    var editorView: EditorView?
    var editorURL: URL?      // nil = unsaved new file
    var isDirty: Bool = false
}
```

- `isDirty == true` → tab title shows `● filename.json`
- Drag a file onto the tab bar → `openEditorTab(url:)` (HeaderBarView becomes NSDraggingDestination)
- `+` button: tap → terminal tab (unchanged), hold >0.4s → NSMenu dropdown ["Terminal", "Text Editor"]

---

## 2. EditorView Architecture

```
EditorView: NSView
├── GutterView: NSView           (~50px, line numbers + fold markers, CGContext drawing)
├── 1px divider
├── NSScrollView
│   └── NSTextView               (backed by EditorTextStorage)
└── EditorFooter: NSView         (Zeile:Spalte | Encoding | Line Ending | Language)
```

**GutterView**
- Draws line numbers with CGContext (same style as TerminalView for visual consistency)
- Triangle fold markers per foldable block
- Syncs scroll via NSScrollView bounds-change notification

**EditorTextStorage: NSTextStorage**
- Backed by NSMutableAttributedString
- `processEditing()` triggers `SyntaxHighlighter.highlight(storage:language:theme:)`
- Highlights only the changed range for performance

**EditorLayoutManager: NSLayoutManager**
- Tracks line count → notifies GutterView to redraw
- Manages hidden ranges for code folding

**Theme Integration**
- EditorView reacts to `applyTheme(_:)` — BG, FG, gutter BG, all syntax colors from active theme

---

## 3. Syntax Highlighting

**SyntaxHighlighter** — no external dependencies, regex-based

Supported languages (detected by file extension):
`.swift`, `.json`, `.yaml/.yml`, `.js/.ts`, `.py`, `.sh/.bash`,
`.md`, `.html`, `.css`, `.go`, `.rs`, `.rb`, `.xml`

Token types: `keyword`, `string`, `comment`, `number`, `operator`, `type`

Colors come from the active terminal theme (Dark/Light/OLED/System).

---

## 4. Features

| Feature | Implementation |
|---|---|
| Line numbers | GutterView, CGContext |
| Syntax highlighting | EditorTextStorage + SyntaxHighlighter |
| Search & Replace | Bottom panel, Cmd+F / Cmd+H, same style as terminal search |
| Multiple cursors | NSTextView.selectedRanges (Option+click adds cursor) |
| Code folding | GutterView markers + hidden ranges in EditorLayoutManager |
| Tabs vs Spaces | Toggle setting, override tab key insertion |
| Encoding | Detected on open, shown in EditorFooter, changeable via dropdown |
| Unsaved indicator | ● prefix in tab title |
| Save | Cmd+S → write to editorURL, isDirty = false |
| Save As | Cmd+Shift+S → NSSavePanel |
| Open file | Cmd+O → NSOpenPanel → openEditorTab(url:) |
| New file | Cmd+N → empty editor tab |
| Drag to tab bar | HeaderBarView drop target → openEditorTab(url:) |

**EditorFooter** (below editor area):
- Displays: `Zeile 12, Spalte 4 | UTF-8 | LF | Swift`
- Click encoding → dropdown to change
- Click line ending → LF / CRLF / CR

---

## 5. Integration Points

**AppDelegate**
- `openEditorTab(url: URL?)` — creates editor tab, reads file with encoding detection
- `saveCurrentEditor()` — called on Cmd+S when active tab is editor
- `newEditorTab()` — called on Cmd+N

**HeaderBarView**
- `+` button: add long-press NSGestureRecognizer → NSMenu
- Implement NSDraggingDestination for `NSPasteboard.PasteboardType.fileURL`

**FooterBarView**
- When active tab is `.editor`: hide shell switcher, show EditorFooter info instead

**Tab Switching (switchToTab)**
- Terminal tab → TerminalView visible, EditorView hidden
- Editor tab → EditorView visible, TerminalView hidden

**Cmd+S global**
- Intercept in keyDown (AppDelegate or BorderlessWindow)
- If active tab is `.editor` → saveCurrentEditor()
- Otherwise → pass through to terminal

---

## 6. New Classes Summary

| Class | Role |
|---|---|
| `TabType` | Enum: .terminal / .editor |
| `EditorView` | Container NSView: gutter + scroll + footer |
| `GutterView` | Line numbers + fold markers (CGContext) |
| `EditorFooter` | Status bar: line/col, encoding, language |
| `EditorTextStorage` | NSTextStorage subclass, triggers highlighting |
| `EditorLayoutManager` | NSLayoutManager subclass, fold + line tracking |
| `SyntaxHighlighter` | Regex tokenizer, no external deps |
| `LanguageGrammar` | Per-language token rules |
