# Text Editor Tab Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a full-featured plain-text/code editor as a first-class tab type in quickTerminal, opened via drag-onto-tab-bar, Cmd+O, or Cmd+N.

**Architecture:** All code lives in `quickTerminal.swift`. A new `// MARK: - Text Editor` section (inserted before `// MARK: - App Delegate`, ~line 14226) contains all editor classes. The tab system is extended with parallel arrays (`tabTypes`, `tabEditorViews`, `tabEditorURLs`, `tabEditorDirty`) alongside the existing `termViews`/`splitContainers` arrays. `termViews` becomes `[TerminalView?]` (nil for editor tabs) to keep indices aligned. `EditorView` is added directly to `window.contentView` — no SplitContainer (SplitContainer is typed to TerminalView internally).

**Tech Stack:** Cocoa/AppKit — NSTextView, NSTextStorage, NSLayoutManager, NSScrollView, CGContext (GutterView), NSPressGestureRecognizer (long-press), NSDraggingDestination (drag-onto-tab-bar).

---

## Overview of New Classes

| Class | Role |
|---|---|
| `TabType` | `enum { case terminal, editor }` |
| `SyntaxToken` | Pure struct: `range: NSRange`, `type: TokenType` |
| `SyntaxHighlighter` | Static methods: `detectLanguage(from:)`, `tokenize(source:language:)` |
| `EditorTextStorage` | `NSTextStorage` subclass, calls `SyntaxHighlighter` in `processEditing()` |
| `EditorLayoutManager` | `NSLayoutManager` subclass, tracks line count |
| `GutterView` | `NSView`, draws line numbers + fold triangles via CGContext |
| `EditorSearchPanel` | `NSView`, search/replace bar (Cmd+F/H) |
| `EditorFooter` | `NSView`, shows Zeile:Spalte | Encoding | Language |
| `EditorView` | Container `NSView`: GutterView + NSScrollView(NSTextView) + EditorFooter |

---

## Task 1: SyntaxHighlighter — pure Swift, no AppKit

**Files:**
- Modify: `quickTerminal.swift` — insert after `// MARK: - Onboarding Panel` (~line 14225), before `// MARK: - App Delegate`
- Test: `tests.swift` — append new test cases

**Step 1: Insert MARK and TokenType + SyntaxToken structs**

Find `// MARK: - App Delegate` and insert BEFORE it:

```swift
// MARK: - Text Editor

enum TabType { case terminal, editor }

// ── Syntax Highlighting ────────────────────────────────────────────────────

enum TokenType {
    case keyword, string, comment, number, operator_, type_, identifier
    case punctuation, literal, attribute, plain
}

struct SyntaxToken {
    let range: NSRange
    let type: TokenType
}

enum EditorLanguage: String {
    case swift, json, yaml, javascript, typescript, python
    case shell, markdown, html, css, go, rust, ruby, xml, plain
}
```

**Step 2: Insert SyntaxHighlighter struct**

Append immediately after the above:

```swift
struct SyntaxHighlighter {

    // ── Language detection ─────────────────────────────────────────────────
    static func detectLanguage(from url: URL?) -> EditorLanguage {
        guard let ext = url?.pathExtension.lowercased() else { return .plain }
        switch ext {
        case "swift":               return .swift
        case "json":                return .json
        case "yaml", "yml":         return .yaml
        case "js", "mjs":           return .javascript
        case "ts", "tsx":           return .typescript
        case "py":                  return .python
        case "sh", "bash", "zsh":   return .shell
        case "md", "markdown":      return .markdown
        case "html", "htm":         return .html
        case "css", "scss", "less": return .css
        case "go":                  return .go
        case "rs":                  return .rust
        case "rb":                  return .ruby
        case "xml", "plist":        return .xml
        default:                    return .plain
        }
    }

    // ── Tokenize ───────────────────────────────────────────────────────────
    static func tokenize(source: String, language: EditorLanguage) -> [SyntaxToken] {
        switch language {
        case .swift:      return tokenizeSwift(source)
        case .json:       return tokenizeJSON(source)
        case .yaml:       return tokenizeYAML(source)
        case .javascript, .typescript: return tokenizeJS(source)
        case .python:     return tokenizePython(source)
        case .shell:      return tokenizeShell(source)
        case .markdown:   return tokenizeMarkdown(source)
        case .html:       return tokenizeHTML(source)
        case .css:        return tokenizeCSS(source)
        case .go:         return tokenizeGo(source)
        case .rust:       return tokenizeRust(source)
        case .ruby:       return tokenizeRuby(source)
        case .xml:        return tokenizeHTML(source)   // reuse HTML tokenizer
        case .plain:      return []
        }
    }

    // ── Helper: apply regex patterns ───────────────────────────────────────
    private static func tokens(source: String,
                                patterns: [(String, TokenType)]) -> [SyntaxToken] {
        var result: [SyntaxToken] = []
        for (pattern, type_) in patterns {
            guard let rx = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { continue }
            let ns = source as NSString
            let matches = rx.matches(in: source, range: NSRange(location: 0, length: ns.length))
            for m in matches {
                // Use first capture group if present, else full match
                let r = m.numberOfRanges > 1 ? m.range(at: 1) : m.range
                if r.location != NSNotFound { result.append(SyntaxToken(range: r, type: type_)) }
            }
        }
        // Sort by location, remove overlaps (first wins)
        result.sort { $0.range.location < $1.range.location }
        var clean: [SyntaxToken] = []
        var cursor = 0
        for tok in result {
            if tok.range.location >= cursor {
                clean.append(tok)
                cursor = tok.range.location + tok.range.length
            }
        }
        return clean
    }

    // ── Swift ──────────────────────────────────────────────────────────────
    private static func tokenizeSwift(_ s: String) -> [SyntaxToken] {
        let kw = "\\b(func|class|struct|enum|protocol|extension|var|let|if|else|guard|return|for|while|in|import|typealias|associatedtype|where|switch|case|default|break|continue|throw|throws|rethrows|try|catch|defer|do|init|deinit|subscript|override|final|static|mutating|nonmutating|open|public|internal|fileprivate|private|weak|unowned|lazy|indirect|as|is|nil|true|false|self|Self|super|any|some|async|await|actor|nonisolated|isolated)\\b"
        return tokens(source: s, patterns: [
            ("//[^\n]*",                            .comment),
            ("/\\*[\\s\\S]*?\\*/",                  .comment),
            ("\"\"\"[\\s\\S]*?\"\"\"",              .string),
            ("\"(?:[^\"\\\\]|\\\\.)*\"",            .string),
            ("#?\"(?:[^\"\\\\]|\\\\.)*\"",          .string),
            (kw,                                    .keyword),
            ("\\b[A-Z][A-Za-z0-9_]*\\b",           .type_),
            ("@\\w+",                               .attribute),
            ("\\b[0-9]+(?:\\.[0-9]+)?\\b",          .number),
            ("[+\\-*/=<>!&|^~%?:,;.()\\[\\]{}]+",  .operator_),
        ])
    }

    // ── JSON ───────────────────────────────────────────────────────────────
    private static func tokenizeJSON(_ s: String) -> [SyntaxToken] {
        return tokens(source: s, patterns: [
            ("\"(?:[^\"\\\\]|\\\\.)*\"\\s*(?=:)",   .keyword),   // keys
            ("\"(?:[^\"\\\\]|\\\\.)*\"",            .string),
            ("\\b(true|false|null)\\b",             .keyword),
            ("\\b-?[0-9]+(?:\\.[0-9]+)?(?:[eE][+-]?[0-9]+)?\\b", .number),
            ("[{}\\[\\]:,]",                        .operator_),
        ])
    }

    // ── YAML ───────────────────────────────────────────────────────────────
    private static func tokenizeYAML(_ s: String) -> [SyntaxToken] {
        return tokens(source: s, patterns: [
            ("#[^\n]*",                             .comment),
            ("^\\s*([\\w-]+)\\s*(?=:)",            .keyword),
            ("\"(?:[^\"\\\\]|\\\\.)*\"",            .string),
            ("'(?:[^'\\\\]|\\\\.)*'",              .string),
            ("\\b(true|false|null|yes|no)\\b",     .keyword),
            ("\\b-?[0-9]+(?:\\.[0-9]+)?\\b",       .number),
            ("^---",                                .operator_),
        ])
    }

    // ── JavaScript / TypeScript ────────────────────────────────────────────
    private static func tokenizeJS(_ s: String) -> [SyntaxToken] {
        let kw = "\\b(function|const|let|var|if|else|return|for|while|do|switch|case|break|continue|class|extends|new|this|import|export|default|from|async|await|try|catch|finally|throw|typeof|instanceof|in|of|null|undefined|true|false|void|delete|yield|super|static|get|set|type|interface|enum|implements|readonly|abstract|declare|module|namespace|keyof|as|is|any|never|unknown|infer)\\b"
        return tokens(source: s, patterns: [
            ("//[^\n]*",                            .comment),
            ("/\\*[\\s\\S]*?\\*/",                  .comment),
            ("`[^`]*`",                             .string),
            ("\"(?:[^\"\\\\]|\\\\.)*\"",            .string),
            ("'(?:[^'\\\\]|\\\\.)*'",              .string),
            (kw,                                    .keyword),
            ("\\b[A-Z][A-Za-z0-9_]*\\b",           .type_),
            ("\\b[0-9]+(?:\\.[0-9]+)?\\b",          .number),
        ])
    }

    // ── Python ─────────────────────────────────────────────────────────────
    private static func tokenizePython(_ s: String) -> [SyntaxToken] {
        let kw = "\\b(def|class|if|elif|else|for|while|in|return|import|from|as|with|try|except|finally|raise|pass|break|continue|lambda|yield|global|nonlocal|del|assert|not|and|or|is|None|True|False|async|await)\\b"
        return tokens(source: s, patterns: [
            ("#[^\n]*",                             .comment),
            ("\"\"\"[\\s\\S]*?\"\"\"",              .string),
            ("'''[\\s\\S]*?'''",                    .string),
            ("\"(?:[^\"\\\\]|\\\\.)*\"",            .string),
            ("'(?:[^'\\\\]|\\\\.)*'",              .string),
            (kw,                                    .keyword),
            ("@\\w+",                               .attribute),
            ("\\b[A-Z][A-Za-z0-9_]*\\b",           .type_),
            ("\\b[0-9]+(?:\\.[0-9]+)?\\b",          .number),
        ])
    }

    // ── Shell ──────────────────────────────────────────────────────────────
    private static func tokenizeShell(_ s: String) -> [SyntaxToken] {
        let kw = "\\b(if|then|else|elif|fi|for|do|done|while|case|esac|in|function|return|export|local|source|echo|cd|ls|grep|awk|sed|cat|rm|cp|mv|mkdir|chmod|chown)\\b"
        return tokens(source: s, patterns: [
            ("#[^\n]*",                             .comment),
            ("\"(?:[^\"\\\\]|\\\\.)*\"",            .string),
            ("'[^']*'",                             .string),
            (kw,                                    .keyword),
            ("\\$[\\w{][\\w}]*",                   .type_),
            ("\\b[0-9]+\\b",                        .number),
        ])
    }

    // ── Markdown ───────────────────────────────────────────────────────────
    private static func tokenizeMarkdown(_ s: String) -> [SyntaxToken] {
        return tokens(source: s, patterns: [
            ("^#{1,6} [^\n]+",                      .keyword),
            ("`{3}[\\s\\S]*?`{3}",                  .string),
            ("`[^`]+`",                             .string),
            ("\\*\\*[^*]+\\*\\*",                   .type_),
            ("__[^_]+__",                           .type_),
            ("\\*[^*]+\\*",                         .comment),
            ("_[^_]+_",                             .comment),
            ("\\[[^\\]]+\\]\\([^)]+\\)",            .attribute),
            ("^[-*+] ",                             .operator_),
            ("^\\d+\\. ",                           .operator_),
        ])
    }

    // ── HTML ───────────────────────────────────────────────────────────────
    private static func tokenizeHTML(_ s: String) -> [SyntaxToken] {
        return tokens(source: s, patterns: [
            ("<!--[\\s\\S]*?-->",                   .comment),
            ("<[/!]?[A-Za-z][A-Za-z0-9-]*",        .keyword),
            ("[A-Za-z-]+(?=\\s*=)",                 .type_),
            ("\"[^\"]*\"",                          .string),
            ("'[^']*'",                             .string),
            (">",                                   .keyword),
            ("&[A-Za-z0-9#]+;",                    .number),
        ])
    }

    // ── CSS ────────────────────────────────────────────────────────────────
    private static func tokenizeCSS(_ s: String) -> [SyntaxToken] {
        return tokens(source: s, patterns: [
            ("/\\*[\\s\\S]*?\\*/",                  .comment),
            ("[.#]?[A-Za-z][A-Za-z0-9_-]*\\s*(?=\\{)", .keyword),
            ("[A-Za-z-]+(?=\\s*:)",                 .type_),
            ("\"[^\"]*\"|'[^']*'",                  .string),
            ("#[0-9A-Fa-f]{3,8}\\b",               .number),
            ("\\b[0-9]+(?:\\.[0-9]+)?(?:px|em|rem|%|vh|vw|pt|s|ms)?\\b", .number),
            ("@[A-Za-z-]+",                         .attribute),
        ])
    }

    // ── Go ─────────────────────────────────────────────────────────────────
    private static func tokenizeGo(_ s: String) -> [SyntaxToken] {
        let kw = "\\b(func|var|const|type|struct|interface|map|chan|go|defer|select|case|default|break|continue|return|if|else|for|range|switch|import|package|fallthrough|goto|nil|true|false|iota|make|new|append|len|cap|close|delete|copy|panic|recover|print|println)\\b"
        return tokens(source: s, patterns: [
            ("//[^\n]*",                            .comment),
            ("/\\*[\\s\\S]*?\\*/",                  .comment),
            ("`[^`]*`",                             .string),
            ("\"(?:[^\"\\\\]|\\\\.)*\"",            .string),
            (kw,                                    .keyword),
            ("\\b[A-Z][A-Za-z0-9_]*\\b",           .type_),
            ("\\b[0-9]+(?:\\.[0-9]+)?\\b",          .number),
        ])
    }

    // ── Rust ───────────────────────────────────────────────────────────────
    private static func tokenizeRust(_ s: String) -> [SyntaxToken] {
        let kw = "\\b(fn|let|mut|const|static|struct|enum|trait|impl|type|where|use|mod|pub|crate|super|self|Self|if|else|match|loop|for|while|in|return|break|continue|as|ref|move|async|await|dyn|extern|unsafe|true|false|None|Some|Ok|Err)\\b"
        return tokens(source: s, patterns: [
            ("//[^\n]*",                            .comment),
            ("/\\*[\\s\\S]*?\\*/",                  .comment),
            ("r#?\"[\\s\\S]*?\"#?",                .string),
            ("\"(?:[^\"\\\\]|\\\\.)*\"",            .string),
            (kw,                                    .keyword),
            ("#\\[.*?\\]",                          .attribute),
            ("\\b[A-Z][A-Za-z0-9_]*\\b",           .type_),
            ("\\b[0-9]+(?:\\.[0-9]+)?\\b",          .number),
            ("'[a-z_]+",                            .type_),  // lifetimes
        ])
    }

    // ── Ruby ───────────────────────────────────────────────────────────────
    private static func tokenizeRuby(_ s: String) -> [SyntaxToken] {
        let kw = "\\b(def|class|module|if|elsif|else|unless|end|do|begin|rescue|ensure|raise|return|yield|require|include|extend|attr_reader|attr_writer|attr_accessor|puts|print|true|false|nil|self|super|and|or|not|in|then|case|when)\\b"
        return tokens(source: s, patterns: [
            ("#[^\n]*",                             .comment),
            ("\"(?:[^\"\\\\]|\\\\.)*\"",            .string),
            ("'(?:[^'\\\\]|\\\\.)*'",              .string),
            (kw,                                    .keyword),
            (":[A-Za-z_]\\w*",                     .type_),    // symbols
            ("@{1,2}[A-Za-z_]\\w*",               .attribute),
            ("\\b[A-Z][A-Za-z0-9_]*\\b",           .type_),
            ("\\b[0-9]+(?:\\.[0-9]+)?\\b",          .number),
        ])
    }

    // ── Syntax colors from active theme ───────────────────────────────────
    static func color(for type_: TokenType, dark: Bool) -> NSColor {
        switch type_ {
        case .keyword:    return dark ? NSColor(calibratedRed: 0.80, green: 0.45, blue: 0.90, alpha: 1) : NSColor(calibratedRed: 0.55, green: 0.10, blue: 0.70, alpha: 1)
        case .string:     return dark ? NSColor(calibratedRed: 0.90, green: 0.65, blue: 0.35, alpha: 1) : NSColor(calibratedRed: 0.70, green: 0.30, blue: 0.10, alpha: 1)
        case .comment:    return dark ? NSColor(calibratedWhite: 0.45, alpha: 1) : NSColor(calibratedWhite: 0.55, alpha: 1)
        case .number:     return dark ? NSColor(calibratedRed: 0.65, green: 0.90, blue: 0.65, alpha: 1) : NSColor(calibratedRed: 0.10, green: 0.50, blue: 0.10, alpha: 1)
        case .type_:      return dark ? NSColor(calibratedRed: 0.40, green: 0.80, blue: 0.95, alpha: 1) : NSColor(calibratedRed: 0.05, green: 0.40, blue: 0.65, alpha: 1)
        case .attribute:  return dark ? NSColor(calibratedRed: 0.95, green: 0.75, blue: 0.40, alpha: 1) : NSColor(calibratedRed: 0.65, green: 0.40, blue: 0.05, alpha: 1)
        case .operator_:  return dark ? NSColor(calibratedWhite: 0.65, alpha: 1) : NSColor(calibratedWhite: 0.40, alpha: 1)
        case .identifier, .punctuation, .literal, .plain:
            return dark ? NSColor(calibratedWhite: 0.90, alpha: 1) : NSColor(calibratedWhite: 0.10, alpha: 1)
        }
    }
}
```

**Step 3: Add tests to tests.swift**

Append at the end of `tests.swift` (before the final print/results section):

```swift
// ── SyntaxHighlighter tests ────────────────────────────────────────────────
test("SyntaxHighlighter: detectLanguage swift") {
    let url = URL(fileURLWithPath: "/tmp/foo.swift")
    let lang = SyntaxHighlighter.detectLanguage(from: url)
    expect(lang == .swift, "Expected .swift got \(lang)")
}
test("SyntaxHighlighter: detectLanguage json") {
    let url = URL(fileURLWithPath: "/tmp/data.json")
    expect(SyntaxHighlighter.detectLanguage(from: url) == .json, "json")
}
test("SyntaxHighlighter: detectLanguage plain") {
    let url = URL(fileURLWithPath: "/tmp/Makefile")
    expect(SyntaxHighlighter.detectLanguage(from: url) == .plain, "plain")
}
test("SyntaxHighlighter: tokenize swift keywords") {
    let src = "func hello() -> String { return \"world\" }"
    let tokens = SyntaxHighlighter.tokenize(source: src, language: .swift)
    let kwTokens = tokens.filter { $0.type == .keyword }
    expect(!kwTokens.isEmpty, "Should have keyword tokens")
    let funcTok = kwTokens.first
    let range = funcTok?.range ?? NSRange(location: 0, length: 0)
    let word = (src as NSString).substring(with: range)
    expect(word == "func", "First keyword should be 'func', got '\(word)'")
}
test("SyntaxHighlighter: tokenize swift string") {
    let src = "let x = \"hello world\""
    let tokens = SyntaxHighlighter.tokenize(source: src, language: .swift)
    let strToks = tokens.filter { $0.type == .string }
    expect(!strToks.isEmpty, "Should have string token")
}
test("SyntaxHighlighter: tokenize JSON keys vs values") {
    let src = "{\"name\": \"Alice\", \"age\": 30}"
    let tokens = SyntaxHighlighter.tokenize(source: src, language: .json)
    let kwToks = tokens.filter { $0.type == .keyword }
    let numToks = tokens.filter { $0.type == .number }
    expect(!kwToks.isEmpty, "JSON key tokens")
    expect(!numToks.isEmpty, "JSON number tokens")
}
test("SyntaxHighlighter: no overlapping tokens") {
    let src = "func foo() { return 42 }"
    let tokens = SyntaxHighlighter.tokenize(source: src, language: .swift)
    var cursor = 0
    var ok = true
    for t in tokens {
        if t.range.location < cursor { ok = false; break }
        cursor = t.range.location + t.range.length
    }
    expect(ok, "Tokens must not overlap")
}
```

**Step 4: Run build to verify compilation**

```bash
bash build.sh
```
Expected: Compiles and all tests pass (including 7 new SyntaxHighlighter tests).

**Step 5: Commit**

```bash
git add quickTerminal.swift tests.swift
git commit -m "feat: add SyntaxHighlighter with 13-language support + tests"
```

---

## Task 2: EditorTextStorage + EditorLayoutManager

**Files:**
- Modify: `quickTerminal.swift` — append to `// MARK: - Text Editor` section

**Step 1: Insert EditorTextStorage**

Append after `SyntaxHighlighter` closing brace:

```swift
// ── EditorTextStorage ──────────────────────────────────────────────────────

class EditorTextStorage: NSTextStorage {
    private var _backing = NSMutableAttributedString()
    var language: EditorLanguage = .plain
    var isDark: Bool = true   // updated by EditorView when theme changes

    // Required NSTextStorage overrides
    override var string: String { _backing.string }

    override func attributes(at location: Int,
                              effectiveRange range: NSRangePointer?) -> [NSAttributedString.Key: Any] {
        return _backing.attributes(at: location, effectiveRange: range)
    }

    override func replaceCharacters(in range: NSRange, with str: String) {
        beginEditing()
        _backing.replaceCharacters(in: range, with: str)
        edited(.editedCharacters, range: range,
               changeInLength: str.utf16.count - range.length)
        endEditing()
    }

    override func setAttributes(_ attrs: [NSAttributedString.Key: Any]?, range: NSRange) {
        beginEditing()
        _backing.setAttributes(attrs, range: range)
        edited(.editedAttributes, range: range, changeInLength: 0)
        endEditing()
    }

    // Called after every edit — applies syntax highlighting
    override func processEditing() {
        super.processEditing()
        guard editedMask.contains(.editedCharacters) else { return }
        applyHighlighting()
    }

    func applyHighlighting() {
        let full = NSRange(location: 0, length: _backing.length)
        guard full.length > 0 else { return }
        let fg = isDark ? NSColor(calibratedWhite: 0.90, alpha: 1) : NSColor(calibratedWhite: 0.10, alpha: 1)
        // Reset all to plain
        beginEditing()
        _backing.setAttributes([.foregroundColor: fg], range: full)
        // Apply tokens
        let tokens = SyntaxHighlighter.tokenize(source: _backing.string, language: language)
        for tok in tokens {
            guard tok.range.location + tok.range.length <= _backing.length else { continue }
            let c = SyntaxHighlighter.color(for: tok.type, dark: isDark)
            _backing.addAttribute(.foregroundColor, value: c, range: tok.range)
        }
        edited(.editedAttributes, range: full, changeInLength: 0)
        endEditing()
    }
}
```

**Step 2: Insert EditorLayoutManager**

Append after `EditorTextStorage`:

```swift
// ── EditorLayoutManager ────────────────────────────────────────────────────

class EditorLayoutManager: NSLayoutManager {
    weak var gutterView: GutterView?

    override func processEditing(for textStorage: NSTextStorage,
                                  edited editMask: NSTextStorage.EditActions,
                                  range newCharRange: NSRange,
                                  changeInLength delta: Int,
                                  invalidatedRange invalidatedCharRange: NSRange) {
        super.processEditing(for: textStorage, edited: editMask,
                              range: newCharRange, changeInLength: delta,
                              invalidatedRange: invalidatedCharRange)
        DispatchQueue.main.async { [weak self] in
            self?.gutterView?.needsDisplay = true
        }
    }
}
```

**Step 3: Build**

```bash
bash build.sh
```
Expected: Compiles cleanly.

**Step 4: Commit**

```bash
git add quickTerminal.swift
git commit -m "feat: add EditorTextStorage and EditorLayoutManager"
```

---

## Task 3: GutterView

**Files:**
- Modify: `quickTerminal.swift` — append to `// MARK: - Text Editor` section

**Step 1: Insert GutterView**

Append after `EditorLayoutManager`:

```swift
// ── GutterView ─────────────────────────────────────────────────────────────

class GutterView: NSView {
    static let width: CGFloat = 52
    weak var textView: NSTextView?
    weak var layoutManager: EditorLayoutManager?
    var isDark: Bool = true

    private var bgColor:   NSColor { isDark ? NSColor(calibratedWhite: 0.09, alpha: 1) : NSColor(calibratedWhite: 0.93, alpha: 1) }
    private var numColor:  NSColor { isDark ? NSColor(calibratedWhite: 0.38, alpha: 1) : NSColor(calibratedWhite: 0.60, alpha: 1) }
    private var curColor:  NSColor { isDark ? NSColor(calibratedWhite: 0.75, alpha: 1) : NSColor(calibratedWhite: 0.25, alpha: 1) }
    private var borderCol: NSColor { isDark ? NSColor(calibratedWhite: 0.16, alpha: 1) : NSColor(calibratedWhite: 0.82, alpha: 1) }

    override func draw(_ dirtyRect: NSRect) {
        guard let lm = layoutManager,
              let tc = lm.textContainers.first,
              let tv = textView,
              let ctx = NSGraphicsContext.current?.cgContext else { return }

        // Background
        ctx.setFillColor(bgColor.cgColor)
        ctx.fill(bounds)

        // Right border
        ctx.setFillColor(borderCol.cgColor)
        ctx.fill(NSRect(x: bounds.width - 1, y: 0, width: 1, height: bounds.height))

        let font = tv.font ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: numColor
        ]
        let curAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: curColor
        ]

        // Get the visible rect of the text view translated to layout coordinates
        let visibleRect = tv.visibleRect
        let insetY = tv.textContainerInset.height

        // Find first visible glyph
        let glyphRange = lm.glyphRange(forBoundingRect: visibleRect, in: tc)
        let charRange  = lm.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

        // Determine line range in the text
        let str = lm.textStorage?.string ?? ""
        let nsStr = str as NSString
        var lineNum = 1
        var charIdx = 0

        // Count lines before visible range
        if charRange.location > 0 {
            let before = nsStr.substring(to: charRange.location)
            lineNum = before.components(separatedBy: "\n").count
        }

        // Get cursor line for highlight
        let cursorLine = currentLineNumber(in: tv)

        // Walk through visible lines
        var glyphIdx = glyphRange.location
        while glyphIdx < NSMaxRange(glyphRange) {
            var lineGlyphRange = NSRange()
            let lineRect = lm.lineFragmentRect(forGlyphAt: glyphIdx, effectiveRange: &lineGlyphRange)
            let y = lineRect.minY + insetY - visibleRect.minY

            // Draw line number right-aligned
            let label = "\(lineNum)" as NSString
            let a = lineNum == cursorLine ? curAttrs : attrs
            let size = label.size(withAttributes: a)
            label.draw(at: NSPoint(x: bounds.width - size.width - 10, y: y), withAttributes: a)

            lineNum += 1
            glyphIdx = NSMaxRange(lineGlyphRange)
        }
    }

    private func currentLineNumber(in tv: NSTextView) -> Int {
        let loc = tv.selectedRange().location
        let str = tv.string as NSString
        var line = 1
        var i = 0
        while i < loc && i < str.length {
            if str.character(at: i) == 0x0A { line += 1 }
            i += 1
        }
        return line
    }
}
```

**Step 2: Build**

```bash
bash build.sh
```

**Step 3: Commit**

```bash
git add quickTerminal.swift
git commit -m "feat: add GutterView with CGContext line number rendering"
```

---

## Task 4: EditorFooter + EditorSearchPanel

**Files:**
- Modify: `quickTerminal.swift` — append to `// MARK: - Text Editor` section

**Step 1: Insert EditorFooter**

Append after `GutterView`:

```swift
// ── EditorFooter ───────────────────────────────────────────────────────────

class EditorFooter: NSView {
    static let height: CGFloat = 24
    private let infoLabel = NSTextField(labelWithString: "")
    private let encBtn    = NSButton()
    private let leBtn     = NSButton()
    var isDark: Bool = true {
        didSet { updateColors() }
    }
    var onEncodingClick:    (() -> Void)?
    var onLineEndingClick:  (() -> Void)?

    var line: Int = 1        { didSet { updateLabel() } }
    var column: Int = 1      { didSet { updateLabel() } }
    var encoding: String = "UTF-8"  { didSet { updateLabel() } }
    var lineEnding: String = "LF"   { didSet { updateLabel() } }
    var language: EditorLanguage = .plain { didSet { updateLabel() } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        infoLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        infoLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(infoLabel)

        for (btn, action) in [(encBtn, #selector(clickEnc)), (leBtn, #selector(clickLE))] {
            btn.isBordered = false
            btn.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            btn.translatesAutoresizingMaskIntoConstraints = false
            btn.target = self
            btn.action = action
            addSubview(btn)
        }

        NSLayoutConstraint.activate([
            infoLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            infoLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            leBtn.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            leBtn.centerYAnchor.constraint(equalTo: centerYAnchor),
            encBtn.trailingAnchor.constraint(equalTo: leBtn.leadingAnchor, constant: -12),
            encBtn.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        updateColors()
        updateLabel()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func updateColors() {
        layer?.backgroundColor = (isDark ? NSColor(calibratedWhite: 0.09, alpha: 1)
                                         : NSColor(calibratedWhite: 0.93, alpha: 1)).cgColor
        let fg = isDark ? NSColor(calibratedWhite: 0.45, alpha: 1) : NSColor(calibratedWhite: 0.55, alpha: 1)
        infoLabel.textColor = fg
        encBtn.contentTintColor = fg
        leBtn.contentTintColor = fg
    }

    private func updateLabel() {
        let langName = language == .plain ? "Plain Text" : language.rawValue.capitalized
        infoLabel.stringValue = "Ln \(line), Col \(column)  ·  \(langName)"
        encBtn.title = encoding
        leBtn.title  = lineEnding
    }

    @objc private func clickEnc() { onEncodingClick?() }
    @objc private func clickLE()  { onLineEndingClick?() }
}
```

**Step 2: Insert EditorSearchPanel**

Append after `EditorFooter`:

```swift
// ── EditorSearchPanel ──────────────────────────────────────────────────────

class EditorSearchPanel: NSView {
    static let height: CGFloat = 36
    private let findField    = NSTextField()
    private let replaceField = NSTextField()
    private let closeBtn     = NSButton()
    private let nextBtn      = NSButton()
    private let prevBtn      = NSButton()
    private let replaceBtn   = NSButton()
    private let replaceAllBtn = NSButton()
    private let modeLabel    = NSTextField(labelWithString: "Find")
    var isReplaceMode = false { didSet { updateLayout() } }
    var isDark: Bool = true   { didSet { updateColors() } }

    var onFind:       ((String, Bool) -> Void)?   // (query, forward)
    var onReplace:    ((String, String) -> Void)?
    var onReplaceAll: ((String, String) -> Void)?
    var onClose:      (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        findField.placeholderString = "Suchen…"
        findField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        findField.translatesAutoresizingMaskIntoConstraints = false

        replaceField.placeholderString = "Ersetzen…"
        replaceField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        replaceField.translatesAutoresizingMaskIntoConstraints = false
        replaceField.isHidden = true

        for (btn, title) in [(closeBtn, "✕"), (prevBtn, "↑"), (nextBtn, "↓"),
                              (replaceBtn, "Ersetzen"), (replaceAllBtn, "Alle")] {
            btn.title = title
            btn.isBordered = false
            btn.font = NSFont.systemFont(ofSize: 11)
            btn.translatesAutoresizingMaskIntoConstraints = false
            addSubview(btn)
        }
        replaceBtn.isHidden = true
        replaceAllBtn.isHidden = true

        [findField, replaceField, modeLabel].forEach { addSubview($0) }

        closeBtn.target = self; closeBtn.action = #selector(tapClose)
        nextBtn.target  = self; nextBtn.action  = #selector(tapNext)
        prevBtn.target  = self; prevBtn.action  = #selector(tapPrev)
        replaceBtn.target    = self; replaceBtn.action    = #selector(tapReplace)
        replaceAllBtn.target = self; replaceAllBtn.action = #selector(tapReplaceAll)

        NSLayoutConstraint.activate([
            closeBtn.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            closeBtn.centerYAnchor.constraint(equalTo: centerYAnchor),
            modeLabel.leadingAnchor.constraint(equalTo: closeBtn.trailingAnchor, constant: 8),
            modeLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            findField.leadingAnchor.constraint(equalTo: modeLabel.trailingAnchor, constant: 8),
            findField.widthAnchor.constraint(equalToConstant: 180),
            findField.centerYAnchor.constraint(equalTo: centerYAnchor),
            prevBtn.leadingAnchor.constraint(equalTo: findField.trailingAnchor, constant: 4),
            prevBtn.centerYAnchor.constraint(equalTo: centerYAnchor),
            nextBtn.leadingAnchor.constraint(equalTo: prevBtn.trailingAnchor, constant: 4),
            nextBtn.centerYAnchor.constraint(equalTo: centerYAnchor),
            replaceField.leadingAnchor.constraint(equalTo: nextBtn.trailingAnchor, constant: 8),
            replaceField.widthAnchor.constraint(equalToConstant: 160),
            replaceField.centerYAnchor.constraint(equalTo: centerYAnchor),
            replaceBtn.leadingAnchor.constraint(equalTo: replaceField.trailingAnchor, constant: 4),
            replaceBtn.centerYAnchor.constraint(equalTo: centerYAnchor),
            replaceAllBtn.leadingAnchor.constraint(equalTo: replaceBtn.trailingAnchor, constant: 4),
            replaceAllBtn.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        updateColors()
    }
    required init?(coder: NSCoder) { fatalError() }

    func focusFind() { window?.makeFirstResponder(findField) }

    private func updateLayout() {
        modeLabel.stringValue = isReplaceMode ? "Ersetzen" : "Suchen"
        replaceField.isHidden = !isReplaceMode
        replaceBtn.isHidden   = !isReplaceMode
        replaceAllBtn.isHidden = !isReplaceMode
    }

    private func updateColors() {
        layer?.backgroundColor = (isDark ? NSColor(calibratedWhite: 0.11, alpha: 0.97)
                                         : NSColor(calibratedWhite: 0.91, alpha: 0.97)).cgColor
        let fg = isDark ? NSColor(calibratedWhite: 0.80, alpha: 1) : NSColor(calibratedWhite: 0.20, alpha: 1)
        modeLabel.textColor = fg
        [closeBtn, nextBtn, prevBtn, replaceBtn, replaceAllBtn].forEach { $0.contentTintColor = fg }
    }

    @objc private func tapClose()      { onClose?() }
    @objc private func tapNext()       { onFind?(findField.stringValue, true) }
    @objc private func tapPrev()       { onFind?(findField.stringValue, false) }
    @objc private func tapReplace()    { onReplace?(findField.stringValue, replaceField.stringValue) }
    @objc private func tapReplaceAll() { onReplaceAll?(findField.stringValue, replaceField.stringValue) }
}
```

**Step 3: Build**

```bash
bash build.sh
```

**Step 4: Commit**

```bash
git add quickTerminal.swift
git commit -m "feat: add EditorFooter and EditorSearchPanel"
```

---

## Task 5: EditorView (container — assembles all editor sub-views)

**Files:**
- Modify: `quickTerminal.swift` — append to `// MARK: - Text Editor` section

**Step 1: Insert EditorView**

Append after `EditorSearchPanel`:

```swift
// ── EditorView ─────────────────────────────────────────────────────────────

class EditorView: NSView, NSTextViewDelegate, NSTextStorageDelegate {

    // ── Sub-views ──────────────────────────────────────────────────────────
    private let gutterView    = GutterView()
    private let scrollView    = NSScrollView()
    let textView              = NSTextView()
    private let footer        = EditorFooter()
    private let searchPanel   = EditorSearchPanel()
    private var searchVisible = false

    // ── State ──────────────────────────────────────────────────────────────
    private let storage       = EditorTextStorage()
    private let layoutMgr     = EditorLayoutManager()
    private let textContainer = NSTextContainer()

    var fileURL: URL? {
        didSet {
            storage.language = SyntaxHighlighter.detectLanguage(from: fileURL)
            footer.language  = storage.language
            storage.applyHighlighting()
        }
    }

    var isDirty: Bool = false {
        didSet { onDirtyChanged?(isDirty) }
    }
    var onDirtyChanged: ((Bool) -> Void)?
    var onCursorMoved:  (() -> Void)?

    // ── Encoding / Line ending ─────────────────────────────────────────────
    var fileEncoding: String.Encoding = .utf8
    var lineEnding: String = "LF"

    // ── Dark/light ─────────────────────────────────────────────────────────
    var isDark: Bool = true {
        didSet { applyColors() }
    }

    // ── Init ───────────────────────────────────────────────────────────────
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        // Wire up text stack
        storage.addLayoutManager(layoutMgr)
        layoutMgr.addTextContainer(textContainer)
        textContainer.widthTracksTextView = true
        textContainer.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled  = false
        textView.isAutomaticDashSubstitutionEnabled   = false
        textView.isAutomaticLinkDetectionEnabled      = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.delegate = self

        layoutMgr.gutterView = gutterView
        gutterView.textView  = textView
        gutterView.layoutManager = layoutMgr

        scrollView.documentView = textView
        scrollView.hasVerticalScroller   = true
        scrollView.hasHorizontalScroller = false
        scrollView.autoresizingMask      = []
        scrollView.drawsBackground       = false

        searchPanel.isHidden = true
        searchPanel.onClose      = { [weak self] in self?.hideSearch() }
        searchPanel.onFind       = { [weak self] q, fwd in self?.findNext(query: q, forward: fwd) }
        searchPanel.onReplace    = { [weak self] q, r in self?.replaceOne(query: q, replacement: r) }
        searchPanel.onReplaceAll = { [weak self] q, r in self?.replaceAll(query: q, replacement: r) }

        footer.onEncodingClick   = { [weak self] in self?.showEncodingMenu() }
        footer.onLineEndingClick = { [weak self] in self?.showLineEndingMenu() }

        [gutterView, scrollView, footer, searchPanel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        NSLayoutConstraint.activate([
            gutterView.leadingAnchor.constraint(equalTo: leadingAnchor),
            gutterView.topAnchor.constraint(equalTo: topAnchor),
            gutterView.widthAnchor.constraint(equalToConstant: GutterView.width),
            gutterView.bottomAnchor.constraint(equalTo: footer.topAnchor),

            scrollView.leadingAnchor.constraint(equalTo: gutterView.trailingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: footer.topAnchor),

            footer.leadingAnchor.constraint(equalTo: leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: bottomAnchor),
            footer.heightAnchor.constraint(equalToConstant: EditorFooter.height),

            searchPanel.leadingAnchor.constraint(equalTo: gutterView.trailingAnchor),
            searchPanel.trailingAnchor.constraint(equalTo: trailingAnchor),
            searchPanel.bottomAnchor.constraint(equalTo: footer.topAnchor),
            searchPanel.heightAnchor.constraint(equalToConstant: EditorSearchPanel.height),
        ])

        // Sync gutter scroll with text scroll
        NotificationCenter.default.addObserver(
            self, selector: #selector(scrollDidChange),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView)

        applyColors()
    }
    required init?(coder: NSCoder) { fatalError() }

    // ── Load / Save ────────────────────────────────────────────────────────
    func loadFile(url: URL) throws {
        // Detect encoding: try UTF-8, fall back to latin1
        var enc: String.Encoding = .utf8
        var content: String
        if let s = try? String(contentsOf: url, encoding: .utf8) {
            content = s; enc = .utf8
        } else if let s = try? String(contentsOf: url, encoding: .isoLatin1) {
            content = s; enc = .isoLatin1
        } else {
            content = try String(contentsOf: url, encoding: .utf8)  // will throw
        }
        fileEncoding = enc
        let encName: String
        switch enc {
        case .utf8:      encName = "UTF-8"
        case .isoLatin1: encName = "Latin-1"
        default:         encName = "UTF-8"
        }
        footer.encoding = encName

        // Detect line endings
        if content.contains("\r\n") { lineEnding = "CRLF" }
        else if content.contains("\r") { lineEnding = "CR" }
        else { lineEnding = "LF" }
        footer.lineEnding = lineEnding

        fileURL = url
        setContent(content)
        isDirty = false
    }

    func saveFile(to url: URL? = nil) throws {
        let target = url ?? fileURL
        guard let target else { return }
        var text = textView.string
        // Normalize line endings
        if lineEnding == "CRLF" { text = text.replacingOccurrences(of: "\n", with: "\r\n") }
        else if lineEnding == "CR" { text = text.replacingOccurrences(of: "\n", with: "\r") }
        try text.write(to: target, atomically: true, encoding: fileEncoding)
        fileURL = target
        isDirty = false
    }

    func setContent(_ text: String) {
        // Replace storage content
        let range = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.replaceCharacters(in: range, with: text)
        storage.endEditing()
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        gutterView.needsDisplay = true
        updateFooterCursor()
    }

    // ── Colors / Theme ─────────────────────────────────────────────────────
    func applyColors() {
        let bg: NSColor = isDark ? NSColor(calibratedWhite: 0.10, alpha: 1) : NSColor(calibratedWhite: 0.97, alpha: 1)
        let fg: NSColor = isDark ? NSColor(calibratedWhite: 0.90, alpha: 1) : NSColor(calibratedWhite: 0.10, alpha: 1)
        layer?.backgroundColor = bg.cgColor
        textView.backgroundColor = bg
        textView.textColor = fg
        textView.insertionPointColor = isDark ? .white : .black
        storage.isDark = isDark
        storage.applyHighlighting()
        gutterView.isDark = isDark
        gutterView.needsDisplay = true
        footer.isDark = isDark
        searchPanel.isDark = isDark
    }

    // ── NSTextViewDelegate ─────────────────────────────────────────────────
    func textDidChange(_ notification: Notification) {
        if !isDirty { isDirty = true }
        updateFooterCursor()
        gutterView.needsDisplay = true
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        updateFooterCursor()
        gutterView.needsDisplay = true
    }

    private func updateFooterCursor() {
        let sel = textView.selectedRange()
        let str = textView.string as NSString
        let line   = str.substring(to: sel.location).components(separatedBy: "\n").count
        let lineStart = str.range(of: "\n",
            options: .backwards,
            range: NSRange(location: 0, length: sel.location)).upperBound
        let col = sel.location - (lineStart == NSNotFound ? 0 : lineStart) + 1
        footer.line   = line
        footer.column = col
    }

    // ── Scroll sync ────────────────────────────────────────────────────────
    @objc private func scrollDidChange() {
        gutterView.needsDisplay = true
    }

    // ── Search ─────────────────────────────────────────────────────────────
    func showSearch(replace: Bool = false) {
        searchPanel.isReplaceMode = replace
        searchPanel.isHidden = false
        searchVisible = true
        searchPanel.focusFind()
    }

    func hideSearch() {
        searchPanel.isHidden = true
        searchVisible = false
        window?.makeFirstResponder(textView)
    }

    private func findNext(query: String, forward: Bool) {
        guard !query.isEmpty else { return }
        let text = textView.string as NSString
        let sel  = textView.selectedRange()
        let start = forward ? NSMaxRange(sel) : sel.location > 0 ? sel.location - 1 : text.length - 1
        let searchRange = forward
            ? NSRange(location: start, length: text.length - start)
            : NSRange(location: 0, length: start)
        let opts: NSString.CompareOptions = forward ? [] : .backwards
        let found = text.range(of: query, options: opts, range: searchRange)
        if found.location != NSNotFound {
            textView.setSelectedRange(found)
            textView.scrollRangeToVisible(found)
        } else {
            // Wrap around
            let wrapRange = forward
                ? NSRange(location: 0, length: text.length)
                : NSRange(location: 0, length: text.length)
            let wrapped = text.range(of: query, options: opts, range: wrapRange)
            if wrapped.location != NSNotFound {
                textView.setSelectedRange(wrapped)
                textView.scrollRangeToVisible(wrapped)
            }
        }
    }

    private func replaceOne(query: String, replacement: String) {
        guard !query.isEmpty else { return }
        let sel = textView.selectedRange()
        let current = (textView.string as NSString).substring(with: sel)
        if current == query {
            textView.insertText(replacement, replacementRange: sel)
        }
        findNext(query: query, forward: true)
    }

    private func replaceAll(query: String, replacement: String) {
        guard !query.isEmpty else { return }
        let text = textView.string
        let new  = text.replacingOccurrences(of: query, with: replacement)
        if new != text { setContent(new); isDirty = true }
    }

    // ── Encoding / Line ending menus ───────────────────────────────────────
    private func showEncodingMenu() {
        let menu = NSMenu()
        for (title, enc): (String, String.Encoding) in [("UTF-8", .utf8), ("Latin-1", .isoLatin1), ("UTF-16", .utf16)] {
            let item = NSMenuItem(title: title, action: #selector(pickEncoding(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = enc
            menu.addItem(item)
        }
        let loc = NSEvent.mouseLocation
        menu.popUp(positioning: nil, at: window!.convertPoint(fromScreen: loc), in: self)
    }

    @objc private func pickEncoding(_ item: NSMenuItem) {
        if let enc = item.representedObject as? String.Encoding {
            fileEncoding = enc
            footer.encoding = item.title
        }
    }

    private func showLineEndingMenu() {
        let menu = NSMenu()
        for le in ["LF", "CRLF", "CR"] {
            let item = NSMenuItem(title: le, action: #selector(pickLineEnding(_:)), keyEquivalent: "")
            item.target = self; menu.addItem(item)
        }
        let loc = NSEvent.mouseLocation
        menu.popUp(positioning: nil, at: window!.convertPoint(fromScreen: loc), in: self)
    }

    @objc private func pickLineEnding(_ item: NSMenuItem) {
        lineEnding = item.title
        footer.lineEnding = lineEnding
    }

    // ── Tab / Spaces override ──────────────────────────────────────────────
    var useTabs: Bool = true   // set from Settings

    func textView(_ tv: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertTab(_:)) {
            let insert = useTabs ? "\t" : String(repeating: " ", count: 4)
            tv.insertText(insert, replacementRange: tv.selectedRange())
            return true
        }
        return false
    }

    // ── Multiple cursors: Option+click ─────────────────────────────────────
    override func mouseDown(with event: NSEvent) {
        guard event.modifierFlags.contains(.option) else {
            super.mouseDown(with: event)
            return
        }
        // Convert click to text position
        let pt = textView.convert(event.locationInWindow, from: nil)
        let frac = UnsafeMutablePointer<CGFloat>.allocate(capacity: 1)
        frac.initialize(to: 0)
        defer { frac.deallocate() }
        let glyphIdx = layoutMgr.glyphIndex(for: pt, in: textContainer, fractionOfDistanceThroughGlyph: frac)
        let charIdx  = layoutMgr.characterIndexForGlyph(at: glyphIdx)
        let newRange = NSValue(range: NSRange(location: charIdx, length: 0))
        var ranges   = textView.selectedRanges
        ranges.append(newRange)
        textView.selectedRanges = ranges
    }

    // ── Code folding (Phase 1: gutter triangle only) ───────────────────────
    // Full folding via NSLayoutManager hidden glyphs implemented in Task 15
    // For now, clicking a triangle in the gutter is a no-op placeholder

    // ── Key handling: Cmd+S, Cmd+F, Cmd+H ─────────────────────────────────
    // These are handled at AppDelegate level — EditorView only exposes
    // showSearch/hideSearch, and loadFile/saveFile.
}
```

**Step 2: Build**

```bash
bash build.sh
```
Expected: Compiles cleanly.

**Step 3: Commit**

```bash
git add quickTerminal.swift
git commit -m "feat: add EditorView container with text stack, search, and footer"
```

---

## Task 6: Tab System Extension in AppDelegate

**Files:**
- Modify: `quickTerminal.swift` — AppDelegate property declarations (~line 14230)

**Step 1: Change termViews to optional, add editor parallel arrays**

Find (line ~14230):
```swift
    var termViews: [TerminalView] = []
```
Replace with:
```swift
    var termViews: [TerminalView?] = []  // nil for editor tabs
    var tabTypes: [TabType] = []
    var tabEditorViews: [EditorView?] = []
    var tabEditorURLs: [URL?] = []
    var tabEditorDirty: [Bool] = []
```

**Step 2: Fix all termViews usages that assume non-optional**

Search for every `termViews[` usage and wrap in optional access. Key locations:

1. `switchToTab` (~line 15367): `window.makeFirstResponder(termViews[activeTab])`
   → `if let tv = termViews[activeTab] { window.makeFirstResponder(tv) } else if let ev = tabEditorViews[activeTab] { window.makeFirstResponder(ev.textView) }`

2. `updateHeaderTabs` (~line 15395): `termViews.enumerated().map { (i, tv) -> String in`
   → Handle both terminal and editor titles:
   ```swift
   func updateHeaderTabs() {
       let home = NSHomeDirectory()
       let titles = (0..<splitContainers.count).map { i -> String in
           if i < tabTypes.count && tabTypes[i] == .editor {
               let dirty = i < tabEditorDirty.count && tabEditorDirty[i]
               if let url = i < tabEditorURLs.count ? tabEditorURLs[i] : nil {
                   let name = url.lastPathComponent
                   return dirty ? "● \(name)" : name
               }
               return dirty ? "● Untitled" : "Untitled"
           }
           if let custom = i < tabCustomNames.count ? tabCustomNames[i] : nil { return custom }
           if let tv = i < termViews.count ? termViews[i] : nil {
               let pid = tv.childPid
               if pid > 0 {
                   let cwd = cwdForPid(pid)
                   if cwd == home { return "~" }
                   return (cwd as NSString).lastPathComponent
               }
           }
           return "~"
       }
       headerView.updateTabs(count: splitContainers.count, activeIndex: activeTab,
                             titles: titles, colors: tabColors)
   }
   ```

3. `closeTab` (~line 14754): `termViews.remove(at: index)` stays as-is (optional array handles it); add cleanup:
   ```swift
   // Inside closeTab, after removing from termViews:
   if index < tabTypes.count {
       if tabTypes[index] == .editor {
           tabEditorViews[index]?.removeFromSuperview()
       }
       tabTypes.remove(at: index)
   }
   if index < tabEditorViews.count { tabEditorViews.remove(at: index) }
   if index < tabEditorURLs.count  { tabEditorURLs.remove(at: index)  }
   if index < tabEditorDirty.count { tabEditorDirty.remove(at: index) }
   ```

4. `termViews.firstIndex` in `onShellExit` — this finds the TerminalView object directly, still works since it's comparing object identity.

5. `termViews.count` guard checks in switchToTab1-9 — replace with `splitContainers.count`.

6. `var termViews.count > 0` checks elsewhere — replace with `splitContainers.count > 0`.

**Step 3: Update switchToTab to handle editor tabs**

In `switchToTab` after the crossfade, replace `window.makeFirstResponder(termViews[activeTab])` with:
```swift
if let ev = tabEditorViews[activeTab] {
    ev.isHidden = false
    window.makeFirstResponder(ev.textView)
} else if let tv = termViews[activeTab] {
    window.makeFirstResponder(tv)
}
// Also hide/show editor views for old/new tab:
if oldTab < tabEditorViews.count { tabEditorViews[oldTab]?.isHidden = true }
```

**Step 4: Build**

```bash
bash build.sh
```

**Step 5: Commit**

```bash
git add quickTerminal.swift
git commit -m "feat: extend tab system with TabType, optional termViews, editor arrays"
```

---

## Task 7: createEditorTab() + openEditorTab(url:) in AppDelegate

**Files:**
- Modify: `quickTerminal.swift` — AppDelegate, after `closeTab` method (~line 14825)

**Step 1: Insert createEditorTab**

```swift
func createEditorTab(url: URL? = nil) {
    let tf = termFrame()
    let ev = EditorView(frame: tf)
    ev.autoresizingMask = [.width, .height]
    ev.isDark = { // detect current theme
        let key = UserDefaults.standard.integer(forKey: "colorTheme")
        if key == 0 || key == 2 { return true }
        if key == 1 { return false }
        return NSApp.effectiveAppearance.name == .darkAqua
    }()

    ev.onDirtyChanged = { [weak self, weak ev] dirty in
        guard let self, let ev else { return }
        if let idx = self.tabEditorViews.firstIndex(where: { $0 === ev }) {
            if idx < self.tabEditorDirty.count { self.tabEditorDirty[idx] = dirty }
        }
        self.updateHeaderTabs()
    }

    if let url {
        try? ev.loadFile(url: url)
    }

    // Build a dummy tab color
    let hue = CGFloat.random(in: 0...1)
    tabColors.append(NSColor(calibratedHue: hue, saturation: 0.65, brightness: 0.85, alpha: 1.0))
    tabCustomNames.append(nil)
    tabGitPositions.append(.none)
    tabGitPanels.append(nil)
    tabGitDividers.append(nil)
    tabGitRatios.append(gitDefaultRatioH)
    tabGitRatiosV.append(gitDefaultRatioV)
    tabGitRatiosH.append(gitDefaultRatioH)

    // No SplitContainer for editor — add EditorView directly
    // We still need a SplitContainer slot for index alignment:
    // Create a minimal placeholder container (never shown, no PTY)
    // Instead, we add EditorView directly to contentView and track it
    // in splitContainers as a wrapper NSView
    let placeholder = NSView(frame: tf)
    placeholder.isHidden = true
    placeholder.autoresizingMask = [.width, .height]

    // Hide current content
    if !splitContainers.isEmpty && activeTab < splitContainers.count {
        splitContainers[activeTab].isHidden = true
        if activeTab < tabGitPanels.count {
            tabGitPanels[activeTab]?.isHidden = true
            tabGitDividers[activeTab]?.isHidden = true
        }
        tabEditorViews.indices.contains(activeTab) ? tabEditorViews[activeTab]?.isHidden = true : ()
    }

    termViews.append(nil)
    splitContainers.append(placeholder)
    tabTypes.append(.editor)
    tabEditorViews.append(ev)
    tabEditorURLs.append(url)
    tabEditorDirty.append(false)

    activeTab = splitContainers.count - 1
    window.contentView?.addSubview(ev)
    ev.frame = tf
    ev.alphaValue = 0
    NSAnimationContext.runAnimationGroup({ ctx in
        ctx.duration = 0.2
        ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
        ev.animator().alphaValue = 1
    })
    window.makeFirstResponder(ev.textView)

    updateHeaderTabs()
    updateFooter()
    saveSession()
}

@objc func openEditorTab() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.begin { [weak self] resp in
        guard resp == .OK, let url = panel.url else { return }
        DispatchQueue.main.async { self?.createEditorTab(url: url) }
    }
}

@objc func newEditorTab() {
    createEditorTab(url: nil)
}

func saveCurrentEditor() {
    guard activeTab < tabEditorViews.count,
          let ev = tabEditorViews[activeTab] else { return }
    if ev.fileURL != nil {
        try? ev.saveFile()
        updateHeaderTabs()
    } else {
        saveCurrentEditorAs()
    }
}

func saveCurrentEditorAs() {
    guard activeTab < tabEditorViews.count,
          let ev = tabEditorViews[activeTab] else { return }
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "Untitled.txt"
    panel.begin { resp in
        guard resp == .OK, let url = panel.url else { return }
        try? ev.saveFile(to: url)
        DispatchQueue.main.async { [weak self] in
            self?.tabEditorURLs[self!.activeTab] = url
            self?.updateHeaderTabs()
        }
    }
}
```

**Step 2: Build**

```bash
bash build.sh
```

**Step 3: Commit**

```bash
git add quickTerminal.swift
git commit -m "feat: add createEditorTab, openEditorTab, saveCurrentEditor to AppDelegate"
```

---

## Task 8: HeaderBarView — Long-press `+` dropdown + drag-onto-tab-bar

**Files:**
- Modify: `quickTerminal.swift` — HeaderBarView (~line 5359 onwards)

**Step 1: Add onAddEditorTab callback and long-press to HeaderBarView**

After `var onAddTab: (() -> Void)?` (~line 5359), add:
```swift
    var onAddEditorTab: (() -> Void)?
```

In `setupUI()` after `addBtn.onClick = ...` (~line 5418), add:
```swift
        // Long-press on + → dropdown
        let press = NSPressGestureRecognizer(target: self, action: #selector(addBtnLongPress(_:)))
        press.minimumPressDuration = 0.4
        addBtn.addGestureRecognizer(press)
```

Add the handler method inside `HeaderBarView`:
```swift
    @objc private func addBtnLongPress(_ gr: NSPressGestureRecognizer) {
        guard gr.state == .began else { return }
        let menu = NSMenu()
        let termItem = NSMenuItem(title: "Terminal", action: #selector(addTerminalTab), keyEquivalent: "")
        termItem.target = self
        let editorItem = NSMenuItem(title: "Text Editor", action: #selector(addEditorTab), keyEquivalent: "")
        editorItem.target = self
        menu.addItem(termItem)
        menu.addItem(editorItem)
        let btnBounds = addBtn.bounds
        menu.popUp(positioning: nil,
                   at: NSPoint(x: btnBounds.midX, y: btnBounds.minY),
                   in: addBtn)
    }
    @objc private func addTerminalTab()  { onAddTab?() }
    @objc private func addEditorTab()    { onAddEditorTab?() }
```

**Step 2: Wire onAddEditorTab in AppDelegate**

In `AppDelegate.setupUI()` or wherever `headerView.onAddTab` is set (~line 14502):
```swift
        headerView.onAddEditorTab = { [weak self] in self?.newEditorTab() }
```

**Step 3: Make HeaderBarView a NSDraggingDestination for file URLs**

Add to `HeaderBarView.setupUI()` (end of `setupUI`):
```swift
        registerForDraggedTypes([.fileURL])
```

Add drag methods to `HeaderBarView`:
```swift
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let pb = sender.draggingPasteboard
        if pb.canReadObject(forClasses: [NSURL.self],
                            options: [.urlReadingFileURLsOnly: true]) {
            return .copy
        }
        return []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pb = sender.draggingPasteboard
        guard let urls = pb.readObjects(forClasses: [NSURL.self],
                                        options: [.urlReadingFileURLsOnly: true]) as? [URL],
              let url = urls.first else { return false }
        DispatchQueue.main.async {
            (NSApp.delegate as? AppDelegate)?.createEditorTab(url: url)
        }
        return true
    }
```

**Step 4: Build**

```bash
bash build.sh
```

**Step 5: Commit**

```bash
git add quickTerminal.swift
git commit -m "feat: HeaderBarView long-press + dropdown and file drag-onto-tab-bar"
```

---

## Task 9: Global Keyboard Shortcuts — Cmd+S, Cmd+N, Cmd+O for editor

**Files:**
- Modify: `quickTerminal.swift` — AppDelegate `keyDown` or `BorderlessWindow` (~search for Cmd+T / Cmd+W handling)

**Step 1: Find where global Cmd shortcuts are handled**

Search for: `NSEvent.keyCode` or `"t"` in AppDelegate keyDown. Likely around the `@objc func addTab()` area or window delegate.

**Step 2: Add Cmd+S, Cmd+Shift+S, Cmd+O, Cmd+N intercept**

In `AppDelegate`, find where `NSApp.sendAction` or `performKeyEquivalent` happens. Add to `BorderlessWindow.performKeyEquivalent`:

```swift
override func performKeyEquivalent(with event: NSEvent) -> Bool {
    let cmd  = event.modifierFlags.contains(.command)
    let shft = event.modifierFlags.contains(.shift)
    let del  = NSApp.delegate as? AppDelegate
    if cmd && !shft && event.charactersIgnoringModifiers == "s" {
        // Cmd+S: save editor OR pass through to terminal
        if let del, del.activeTab < del.tabTypes.count,
           del.tabTypes[del.activeTab] == .editor {
            del.saveCurrentEditor()
            return true
        }
    }
    if cmd && shft && event.charactersIgnoringModifiers == "s" {
        if let del, del.activeTab < del.tabTypes.count,
           del.tabTypes[del.activeTab] == .editor {
            del.saveCurrentEditorAs()
            return true
        }
    }
    if cmd && !shft && event.charactersIgnoringModifiers == "n" {
        del?.newEditorTab()
        return true
    }
    if cmd && !shft && event.charactersIgnoringModifiers == "o" {
        del?.openEditorTab()
        return true
    }
    return super.performKeyEquivalent(with: event)
}
```

Note: Cmd+N and Cmd+T may already be bound. Check existing `keyDown`/`performKeyEquivalent` for conflicts first and adjust if needed.

**Step 3: Add Cmd+F / Cmd+H for editor search**

In the same `performKeyEquivalent`:
```swift
    if cmd && !shft && event.charactersIgnoringModifiers == "f" {
        if let del, del.activeTab < del.tabTypes.count,
           del.tabTypes[del.activeTab] == .editor,
           let ev = del.tabEditorViews[del.activeTab] {
            ev.showSearch(replace: false)
            return true
        }
    }
    if cmd && !shft && event.charactersIgnoringModifiers == "h" {
        if let del, del.activeTab < del.tabTypes.count,
           del.tabTypes[del.activeTab] == .editor,
           let ev = del.tabEditorViews[del.activeTab] {
            ev.showSearch(replace: true)
            return true
        }
    }
```

**Step 4: Build**

```bash
bash build.sh
```

**Step 5: Commit**

```bash
git add quickTerminal.swift
git commit -m "feat: global Cmd+S/N/O/F/H shortcuts for editor tabs"
```

---

## Task 10: FooterBarView adaptation for editor tabs

**Files:**
- Modify: `quickTerminal.swift` — AppDelegate `updateFooter()` method

**Step 1: Find updateFooter**

Search for `func updateFooter()` in AppDelegate. It updates the footer bar with shell/keyboard info.

**Step 2: Extend updateFooter to hide shell switcher for editor tabs**

```swift
func updateFooter() {
    // If active tab is an editor, show minimal footer (encoding etc handled by EditorFooter)
    if activeTab < tabTypes.count && tabTypes[activeTab] == .editor {
        footerView.setEditorMode(true)
        return
    }
    footerView.setEditorMode(false)
    // ... existing footer update logic ...
}
```

**Step 3: Add setEditorMode to FooterBarView**

Find `class FooterBarView` and add:
```swift
    func setEditorMode(_ on: Bool) {
        // Hide shell switcher, keyboard badge row when in editor mode
        shellSwitcher?.isHidden = on
        badgeRow?.isHidden = on
        newTabBtn?.isHidden = on
    }
```
(Adjust property names to match the actual ivar names in FooterBarView — search for the shell picker segmented control and badge container.)

**Step 4: Build**

```bash
bash build.sh
```

**Step 5: Commit**

```bash
git add quickTerminal.swift
git commit -m "feat: FooterBarView hides shell/badge UI for editor tabs"
```

---

## Task 11: Theme integration — applyTheme triggers EditorView.applyColors

**Files:**
- Modify: `quickTerminal.swift` — `applyTheme(_:)` free function or wherever it notifies views

**Step 1: Find applyTheme**

Search for `func applyTheme(` — it's a free function that sets global color vars and redraws terminal views.

**Step 2: Notify all editor views**

At the end of `applyTheme(_:)`, add:
```swift
    // Update all editor tabs
    if let del = NSApp.delegate as? AppDelegate {
        let dark = t.name != "Light"
        for ev in del.tabEditorViews.compactMap({ $0 }) {
            ev.isDark = dark
        }
    }
```

**Step 3: Build + Commit**

```bash
bash build.sh
git add quickTerminal.swift
git commit -m "feat: editor tabs respond to theme changes via applyTheme"
```

---

## Task 12: Tabs vs Spaces setting

**Files:**
- Modify: `quickTerminal.swift` — SettingsOverlay + AppDelegate createEditorTab

**Step 1: Add UserDefaults key "editorUseTabs"**

In `SettingsOverlay`, find where other toggles are set (e.g. autoCheckUpdates toggle). Add a toggle row:
```swift
// In SettingsOverlay buildUI or equivalent:
let tabsToggle = NSButton(checkboxWithTitle: "Tabs verwenden (statt Spaces)", target: nil, action: nil)
tabsToggle.state = UserDefaults.standard.bool(forKey: "editorUseTabs") ? .on : .off
tabsToggle.target = self
// action: saves to UserDefaults and updates all open editors
```

**Step 2: Apply to EditorView on creation**

In `createEditorTab()`, after `let ev = EditorView(frame: tf)`:
```swift
        ev.useTabs = UserDefaults.standard.bool(forKey: "editorUseTabs")
```

**Step 3: Build + Commit**

```bash
bash build.sh
git add quickTerminal.swift
git commit -m "feat: Tabs vs Spaces setting for editor (editorUseTabs UserDefaults key)"
```

---

## Task 13: Session persistence for editor tabs

**Files:**
- Modify: `quickTerminal.swift` — `saveSession()` and `restoreSession()` in AppDelegate

**Step 1: Find saveSession (~line 17239)**

It serializes tabs as `[String: Any]` dicts. Add editor tab serialization:
```swift
// Inside saveSession, in the tab loop:
if i < tabTypes.count && tabTypes[i] == .editor {
    var t: [String: Any] = ["type": "editor"]
    if let url = i < tabEditorURLs.count ? tabEditorURLs[i] : nil {
        t["editorURL"] = url.path
    }
    tabs.append(t)
    continue
}
// existing terminal tab serialization...
```

**Step 2: Find restoreSession**

Add editor tab restoration:
```swift
// Inside restoreSession, in the tab loop:
if let type_ = tab["type"] as? String, type_ == "editor" {
    let url = (tab["editorURL"] as? String).map { URL(fileURLWithPath: $0) }
    createEditorTab(url: url)
    continue
}
// existing terminal tab restoration...
```

**Step 3: Build + Commit**

```bash
bash build.sh
git add quickTerminal.swift
git commit -m "feat: session persistence for editor tabs (save/restore URL)"
```

---

## Task 14: Code Folding (Phase 2 — clickable triangles)

**Files:**
- Modify: `quickTerminal.swift` — GutterView + EditorLayoutManager + EditorView

This task implements actual fold/unfold by hiding NSLayoutManager glyph ranges.

**Step 1: Track fold state**

In `EditorView`, add:
```swift
    private var foldedRanges: [NSRange] = []

    func toggleFold(at lineStart: NSRange) {
        // Find the matching closing brace/indent block
        let str = textView.string as NSString
        guard lineStart.location < str.length else { return }
        let lineEnd = str.range(of: "\n", range:
            NSRange(location: lineStart.location, length: str.length - lineStart.location))
        let foldEnd = findBlockEnd(from: lineEnd.location, in: str)
        let foldRange = NSRange(location: lineEnd.location,
                                length: foldEnd - lineEnd.location)
        if let existing = foldedRanges.firstIndex(where: { $0.location == lineEnd.location }) {
            // Unfold
            foldedRanges.remove(at: existing)
            layoutMgr.invalidateGlyphs(forCharacterRange: foldRange, changeInLength: 0, actualCharacterRange: nil)
        } else {
            // Fold
            foldedRanges.append(foldRange)
            layoutMgr.invalidateGlyphs(forCharacterRange: foldRange, changeInLength: 0, actualCharacterRange: nil)
        }
        gutterView.needsDisplay = true
    }

    private func findBlockEnd(from start: Int, in str: NSString) -> Int {
        // Simple brace-matching for { } blocks
        var depth = 0
        var i = start
        while i < str.length {
            let c = str.character(at: i)
            if c == 0x7B { depth += 1 }
            else if c == 0x7D { depth -= 1; if depth <= 0 { return i + 1 } }
            i += 1
        }
        return str.length
    }
```

**Step 2: Override generateGlyphs in EditorLayoutManager**

```swift
override func generateGlyphs(forGlyphRange glyphsToProcess: NSRange,
                               desiredNumberOfCharacters desiredNumChars: Int) {
    super.generateGlyphs(forGlyphRange: glyphsToProcess,
                          desiredNumberOfCharacters: desiredNumChars)
    // Hide glyphs in folded ranges
    guard let ev = gutterView?.superview as? EditorView else { return }
    for range in ev.foldedRanges {
        let glyphRange = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        setNotShownAttribute(true, forGlyphRange: glyphRange)
    }
}
```

**Step 3: GutterView mouse-down for fold triangles**

```swift
override func mouseDown(with event: NSEvent) {
    let pt = convert(event.locationInWindow, from: nil)
    // Determine which line was clicked
    // ... find lineNum from Y coordinate, call editorView.toggleFold(at:)
    // This is a placeholder — full implementation maps Y → line → char range
    super.mouseDown(with: event)
}
```

**Step 4: Build + Commit**

```bash
bash build.sh
git add quickTerminal.swift
git commit -m "feat: basic code folding skeleton (fold/unfold brace blocks)"
```

---

## Final Integration Checklist

After all tasks are complete:

- [ ] Drag a `.swift` file onto the tab bar → opens editor tab with syntax highlighting
- [ ] Long-press `+` → dropdown shows "Terminal" / "Text Editor"
- [ ] Cmd+N → new empty editor tab
- [ ] Cmd+O → file picker → opens in editor tab
- [ ] Edit text → tab title shows `●`
- [ ] Cmd+S → saves, `●` disappears
- [ ] Cmd+Shift+S → save-as panel
- [ ] Cmd+F → search panel appears at bottom
- [ ] Cmd+H → search + replace panel
- [ ] Option+click → adds second cursor
- [ ] Switch themes → editor colors update
- [ ] Restart app → editor tabs with file paths are restored
- [ ] Footer bar hides shell/badge row when editor tab is active
- [ ] Gutter shows correct line numbers, updates on scroll

**Final build + full test run:**
```bash
bash build.sh
```

**Final commit:**
```bash
git add quickTerminal.swift tests.swift
git commit -m "feat: text editor tab — complete implementation v1"
```
