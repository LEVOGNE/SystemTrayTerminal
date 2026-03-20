# Editor VS Code Features (v1.5.8) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Drei VS Code-ähnliche Editor-Features: Matching Bracket Highlight, Auto-Indent beim Enter, und Code Formatter (Beautify mit Shift+Opt+F).

**Architecture:** Alle Änderungen in `systemtrayterminal.swift` (single-file App). Feature 1+2 erweitern `EditorTextView` (privat, ~Zeile 16097). Feature 3 fügt einen Button in `FooterBarView` und eine Methode in `AppDelegate` hinzu. Keyboard-Shortcut in `BorderlessWindow.sendEvent` (~Zeile 5028).

**Tech Stack:** Swift + AppKit (NSTextView, NSLayoutManager), JSONSerialization für internen JSON-Formatter, externe Prozesse (npx/black/swift-format) via Foundation.Process.

---

## Kontext für den Implementierer

- **Hauptdatei:** `systemtrayterminal.swift` (~16.800+ Zeilen, alles in einer Datei)
- **Build:** `bash build.sh` nach JEDER Änderung — kompiliert und führt 202 Tests aus
- **Tests:** `tests.swift` — standalone Swift-Stubs (kein Cocoa), am Ende von `build.sh` automatisch ausgeführt
- **`EditorTextView`** (~Zeile 16097): private NSTextView-Subklasse, hat bereits `onPaste`-Callback und `paste()` Override
- **`EditorView`** (~Zeile 17415): NSView mit `textView`, `syntaxStorage`, `lineGutter`, `findBar`. Hat bereits `showFindBar()`
- **`FooterBarView`** (~Zeile 7064): Hat `editorModeButtons` (NORMAL/NANO/VIM), `setEditorMode(_ isEditor: Bool)`, Layout in `layout()`
- **`BorderlessWindow.sendEvent`** (~Zeile 5019): Editor-Shortcuts werden explizit hier geroutet (Cmd+S/O/X/A/Z/F)
- **`AppDelegate`** (~Zeile 17919): Hat `tabEditorViews: [EditorView?]`, `activeTab: Int`, `showGenericToast(badge:text:badgeColor:dismissAfter:)`
- **`SyntaxLanguage`** enum (~Zeile 16146): `none, json, html, css, javascript, xml, markdown, shell, python, yaml, toml, swift, sql, ini, dockerfile`
- **Existing tests** (~Zeile 1363 in tests.swift): `testSyntaxLanguageDetection()`, `testBuildPrintOptions()` als Muster

---

## Task 1: Matching Bracket Highlight

**Files:**
- Modify: `systemtrayterminal.swift:16097–16142` (EditorTextView Klasse)
- Modify: `tests.swift` (neue Test-Funktion am Ende)

### Schritt 1: Test für die Bracket-Matching-Logik schreiben

In `tests.swift` NACH der letzten Zeile einfügen:

```swift
// ============================================================================
// MARK: - Bracket Matching
// ============================================================================

func findMatchingBracket_Test(in text: String, at pos: Int) -> Int? {
    let chars = Array(text)
    guard pos >= 0 && pos < chars.count else { return nil }
    let ch = chars[pos]
    let (open, close, forward): (Character, Character, Bool)
    switch ch {
    case "{": (open, close, forward) = ("{", "}", true)
    case "}": (open, close, forward) = ("{", "}", false)
    case "(": (open, close, forward) = ("(", ")", true)
    case ")": (open, close, forward) = ("(", ")", false)
    case "[": (open, close, forward) = ("[", "]", true)
    case "]": (open, close, forward) = ("[", "]", false)
    default: return nil
    }
    var depth = 1
    let limit = 10_000
    if forward {
        var i = pos + 1
        while i < chars.count && i - pos <= limit {
            if chars[i] == open  { depth += 1 }
            if chars[i] == close { depth -= 1; if depth == 0 { return i } }
            i += 1
        }
    } else {
        var i = pos - 1
        while i >= 0 && pos - i <= limit {
            if chars[i] == close { depth += 1 }
            if chars[i] == open  { depth -= 1; if depth == 0 { return i } }
            i -= 1
        }
    }
    return nil
}

func testBracketMatching() {
    // Einfach
    assert(findMatchingBracket_Test(in: "{}", at: 0) == 1,     "{ → }")
    assert(findMatchingBracket_Test(in: "{}", at: 1) == 0,     "} → {")
    assert(findMatchingBracket_Test(in: "(())", at: 0) == 3,   "outer (")
    assert(findMatchingBracket_Test(in: "(())", at: 1) == 2,   "inner (")
    // Nested
    assert(findMatchingBracket_Test(in: "{{}}", at: 0) == 3,   "outer {")
    assert(findMatchingBracket_Test(in: "{{}}", at: 1) == 2,   "inner {")
    assert(findMatchingBracket_Test(in: "{{}}", at: 2) == 1,   "inner }")
    assert(findMatchingBracket_Test(in: "{{}}", at: 3) == 0,   "outer }")
    // Kein Match
    assert(findMatchingBracket_Test(in: "{",  at: 0) == nil,   "unmatched {")
    assert(findMatchingBracket_Test(in: ")",  at: 0) == nil,   "unmatched )")
    // Kein Bracket
    assert(findMatchingBracket_Test(in: "abc", at: 0) == nil,  "no bracket")
    // Eckige Klammern
    assert(findMatchingBracket_Test(in: "[1,2]", at: 0) == 4,  "[ → ]")
    print("✓ Bracket matching — 12 cases")
}

testBracketMatching()
```

### Schritt 2: Test ausführen und prüfen dass er FEHLSCHLÄGT

```bash
cd "/Users/l3v0/Desktop/FERTIGE PROJEKTE/SystemTrayTerminal"
swift tests.swift 2>&1 | tail -5
```

Erwartet: Fehler weil `findMatchingBracket_Test` noch nicht existiert.

### Schritt 3: `findMatchingBracket` als statische Hilfsfunktion in `EditorTextView` implementieren

In `EditorTextView` (~Zeile 16142, vor der schließenden `}` der Klasse) einfügen:

```swift
    // MARK: Bracket Highlight

    /// Finds the matching bracket position in `text` starting at `pos`.
    /// Returns nil if no bracket at pos or no match found within 10k characters.
    static func findMatchingBracket(in text: NSString, at pos: Int) -> Int? {
        guard pos >= 0 && pos < text.length else { return nil }
        let ch = text.character(at: pos)
        let openChars:  [unichar] = [UInt16(ascii: "{"), UInt16(ascii: "("), UInt16(ascii: "[")]
        let closeChars: [unichar] = [UInt16(ascii: "}"), UInt16(ascii: ")"), UInt16(ascii: "]")]
        let forward: Bool
        let open, close: unichar
        if let idx = openChars.firstIndex(of: ch) {
            forward = true;  open = openChars[idx];  close = closeChars[idx]
        } else if let idx = closeChars.firstIndex(of: ch) {
            forward = false; close = closeChars[idx]; open = openChars[idx]
        } else { return nil }
        var depth = 1
        let limit = 10_000
        if forward {
            var i = pos + 1
            while i < text.length && i - pos <= limit {
                let c = text.character(at: i)
                if c == open  { depth += 1 }
                if c == close { depth -= 1; if depth == 0 { return i } }
                i += 1
            }
        } else {
            var i = pos - 1
            while i >= 0 && pos - i <= limit {
                let c = text.character(at: i)
                if c == close { depth += 1 }
                if c == open  { depth -= 1; if depth == 0 { return i } }
                i -= 1
            }
        }
        return nil
    }

    private var bracketHighlightRanges: [NSRange] = []

    func updateBracketHighlight() {
        guard let lm = layoutManager, let ts = textStorage else { return }
        // Clear previous highlights
        for r in bracketHighlightRanges {
            lm.removeTemporaryAttribute(.backgroundColor, forCharacterRange: r)
        }
        bracketHighlightRanges = []
        let sel = selectedRange()
        // Check position of cursor (sel.location) and one before (sel.location - 1)
        let candidates = [sel.location, sel.location > 0 ? sel.location - 1 : -1]
        let text = ts.string as NSString
        for pos in candidates where pos >= 0 && pos < text.length {
            if let matchPos = EditorTextView.findMatchingBracket(in: text, at: pos) {
                let r1 = NSRange(location: pos, length: 1)
                let r2 = NSRange(location: matchPos, length: 1)
                let color = NSColor.selectedTextBackgroundColor.withAlphaComponent(0.45)
                lm.addTemporaryAttributes([.backgroundColor: color], forCharacterRange: r1)
                lm.addTemporaryAttributes([.backgroundColor: color], forCharacterRange: r2)
                bracketHighlightRanges = [r1, r2]
                return  // nur einmal highlighten
            }
        }
    }
```

Dann in der `paste()` Methode (Zeile 16101) — NACH dem `override func paste` Block, DIREKT vor `cursorUpdate` — eine `NSTextView.didChangeSelection` Notification registrieren. Dafür den **EditorView.setup()** Abschnitt nutzen (weiter unten in Task 1, Schritt 5).

### Schritt 4: Test ausführen → PASS

```bash
cd "/Users/l3v0/Desktop/FERTIGE PROJEKTE/SystemTrayTerminal"
bash build.sh 2>&1 | tail -5
```

Erwartet: `203 passed, 0 failed`

**Wichtig:** Der Test in `tests.swift` nutzt den Stub `findMatchingBracket_Test` — die echte Implementierung in `EditorTextView` nutzt `NSString`. Beide Logiken sind identisch, nur der Typ unterscheidet sich.

### Schritt 5: Notification Observer in `EditorView.setup()` anschließen

In `EditorView.setup()` (~Zeile 17480, nach der Zeile wo `onPaste` gesetzt wird) einfügen:

```swift
        // Bracket highlight — update on every cursor move
        NotificationCenter.default.addObserver(
            forName: NSTextView.didChangeSelectionNotification,
            object: textView,
            queue: .main
        ) { [weak self] _ in
            (self?.textView as? EditorTextView)?.updateBracketHighlight()
        }
```

### Schritt 6: Build + Test

```bash
bash build.sh 2>&1 | tail -10
```

Erwartet: `203 passed, 0 failed` und kein Compiler-Fehler.

### Schritt 7: Manuell testen

App starten, Editor-Tab öffnen, `{` `}` tippen, Cursor auf `{` setzen → beide Brackets werden hervorgehoben.

### Schritt 8: Commit

```bash
cd "/Users/l3v0/Desktop/FERTIGE PROJEKTE/SystemTrayTerminal"
git add systemtrayterminal.swift tests.swift
git commit -m "feat(editor): matching bracket highlight"
```

---

## Task 2: Auto-Indent beim Enter

**Files:**
- Modify: `systemtrayterminal.swift:16097–16142` (EditorTextView)
- Modify: `tests.swift` (neue Test-Funktion)

### Schritt 1: Test für Auto-Indent-Logik schreiben

In `tests.swift` nach `testBracketMatching()` einfügen:

```swift
// ============================================================================
// MARK: - Auto Indent
// ============================================================================

/// Berechnet die neue Einrückung für die Zeile nach Enter.
/// - text: gesamter Dokumentinhalt
/// - cursorPos: Position des Cursors (nach der letzten getippten Zeile)
/// - useTab: true → Tab, false → 2 Spaces
/// Gibt die Einrückung als String zurück (Whitespace der neuen Zeile).
func autoIndent_Test(_ text: String, cursorPos: Int, useTab: Bool) -> String {
    let indentUnit = useTab ? "\t" : "  "
    let nsText = text as NSString
    let lineRange = nsText.lineRange(for: NSRange(location: cursorPos, length: 0))
    let line = nsText.substring(with: lineRange)
    // Leading whitespace
    var baseIndent = ""
    for ch in line { if ch == " " || ch == "\t" { baseIndent.append(ch) } else { break } }
    // Smart indent: endet Zeile (ohne Newline) mit öffnender Klammer?
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    if let last = trimmed.last, "{([".contains(last) {
        return baseIndent + indentUnit
    }
    return baseIndent
}

func testAutoIndent() {
    // Basis: leere Zeile → keine Einrückung
    assert(autoIndent_Test("hello\n", cursorPos: 5, useTab: false) == "", "no indent")
    // Basis: eingerückte Zeile → gleiche Einrückung
    assert(autoIndent_Test("  hello\n", cursorPos: 7, useTab: false) == "  ", "2-space indent")
    assert(autoIndent_Test("    hello\n", cursorPos: 9, useTab: false) == "    ", "4-space indent")
    // Smart: Zeile endet mit {
    assert(autoIndent_Test("function() {\n", cursorPos: 12, useTab: false) == "  ", "smart { indent")
    // Smart: eingerückte Zeile mit {
    assert(autoIndent_Test("  if (x) {\n", cursorPos: 10, useTab: false) == "    ", "nested { indent")
    // Smart: Zeile endet mit (
    assert(autoIndent_Test("func foo(\n", cursorPos: 8, useTab: false) == "  ", "smart ( indent")
    // Tabs
    assert(autoIndent_Test("function() {\n", cursorPos: 12, useTab: true) == "\t", "tab indent")
    print("✓ Auto-indent logic — 7 cases")
}

testAutoIndent()
```

### Schritt 2: Test ausführen → FAIL

```bash
swift tests.swift 2>&1 | tail -5
```

Erwartet: Fehler weil `autoIndent_Test` nicht existiert.

### Schritt 3: `insertNewline` Override in `EditorTextView` implementieren

In `EditorTextView` (~Zeile 16142, vor der schließenden `}`) einfügen:

```swift
    override func insertNewline(_ sender: Any?) {
        let nsText = string as NSString
        let sel = selectedRange()
        // Leading whitespace der aktuellen Zeile bestimmen
        let lineRange = nsText.lineRange(for: NSRange(location: sel.location, length: 0))
        let line = nsText.substring(with: lineRange)
        var baseIndent = ""
        for ch in line { if ch == " " || ch == "\t" { baseIndent.append(ch) } else { break } }
        // Einrückeinheit aus Settings
        let useTab = UserDefaults.standard.bool(forKey: "editorUseTabs")
        let indentUnit = useTab ? "\t" : "  "
        // Smart indent: endet Zeile mit öffnender Klammer?
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let smartIndent = (trimmed.last.map { "{([".contains($0) } ?? false)
        // Bracket-Split: steht unmittelbar nach Cursor eine schließende Klammer?
        let nextChar: Character? = sel.location < nsText.length
            ? Character(UnicodeScalar(nsText.character(at: sel.location))!) : nil
        let isSplit = nextChar.map { "})]".contains($0) } ?? false
        let newIndent = baseIndent + (smartIndent ? indentUnit : "")
        if isSplit && smartIndent {
            // Cursor zwischen { und } → beide auf eigene Zeilen aufteilen
            super.insertNewline(sender)
            insertText(newIndent, replacementRange: selectedRange())
            let savedSel = selectedRange()
            super.insertNewline(sender)
            insertText(baseIndent, replacementRange: selectedRange())
            setSelectedRange(savedSel)
        } else {
            super.insertNewline(sender)
            if !newIndent.isEmpty {
                insertText(newIndent, replacementRange: selectedRange())
            }
        }
    }
```

### Schritt 4: Build + Test

```bash
bash build.sh 2>&1 | tail -10
```

Erwartet: `204 passed, 0 failed`

### Schritt 5: Manuell testen

App starten, Editor-Tab öffnen. Tippe `function() {` dann Enter → Cursor steht mit 2 Spaces Einrückung.

### Schritt 6: Commit

```bash
git add systemtrayterminal.swift tests.swift
git commit -m "feat(editor): auto-indent on Enter with smart bracket detection"
```

---

## Task 3: Code Formatter (Beautify)

**Files:**
- Modify: `systemtrayterminal.swift` — `FooterBarView` (~Zeile 7064), `BorderlessWindow.sendEvent` (~Zeile 5028), `AppDelegate` (neue Methode)
- Modify: `tests.swift` (JSON Formatter Test)

### Schritt 1: Test für internen JSON-Formatter schreiben

In `tests.swift` nach `testAutoIndent()` einfügen:

```swift
// ============================================================================
// MARK: - JSON Formatter
// ============================================================================

func formatJSON_Test(_ input: String) -> Result<String, String> {
    guard let data = input.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data),
          let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
          let result = String(data: pretty, encoding: .utf8)
    else { return .failure("Invalid JSON") }
    return .success(result)
}

func testJSONFormatter() {
    // Kompakt → Pretty
    let compact = #"{"b":2,"a":1}"#
    if case .success(let out) = formatJSON_Test(compact) {
        assert(out.contains("\"a\""), "has key a")
        assert(out.contains("\"b\""), "has key b")
        assert(out.contains("\n"), "has newlines")
    } else { assert(false, "valid JSON should format") }
    // Array
    if case .success(let out) = formatJSON_Test("[1,2,3]") {
        assert(out.contains("1"), "array element 1")
        assert(out.contains("\n"), "array has newlines")
    } else { assert(false, "array should format") }
    // Ungültiges JSON → Fehler
    if case .failure(_) = formatJSON_Test("not json") {
        // erwartet
    } else { assert(false, "invalid JSON should fail") }
    print("✓ JSON formatter — 3 cases")
}

testJSONFormatter()
```

### Schritt 2: Test ausführen → PASS (Foundation ist verfügbar in tests.swift)

```bash
bash build.sh 2>&1 | tail -5
```

Erwartet: `205 passed, 0 failed`

### Schritt 3: `{ }` Format-Button in `FooterBarView` hinzufügen

**3a.** In `FooterBarView` nach `var onPrint: (() -> Void)?` (~Zeile 7073) die neue Callback-Property einfügen:

```swift
    var onFormatDocument: (() -> Void)?
    private var formatBtn: SymbolHoverButton!
```

**3b.** In `FooterBarView.init` (~Zeile 7219, direkt NACH `printerBtn` Setup) einfügen:

```swift
        formatBtn = SymbolHoverButton(
            symbolName: "curlybraces",
            size: 12,
            normalColor: NSColor(calibratedWhite: 0.50, alpha: 1.0),
            hoverColor:  NSColor(calibratedWhite: 0.88, alpha: 1.0),
            hoverBg: NSColor(calibratedWhite: 1.0, alpha: 0.08),
            pressBg: NSColor(calibratedWhite: 1.0, alpha: 0.16))
        formatBtn.toolTip = "Format Document (⇧⌥F)"
        formatBtn.isHidden = true  // nur bei Editor-Tabs sichtbar
        formatBtn.onClick = { [weak self] in self?.onFormatDocument?() }
        rechtsContent.addSubview(formatBtn)
```

**3c.** In `FooterBarView.layout()` (~Zeile 7291, nach `printerBtn.frame` Zuweisung) einfügen:

```swift
        if !formatBtn.isHidden {
            let fmtSize: CGFloat = 24
            formatBtn.frame = NSRect(x: rx, y: cy - fmtSize / 2,
                                     width: fmtSize, height: fmtSize)
            rx += fmtSize + gap
        }
```

**3d.** In `FooterBarView.setEditorMode(_:)` (~Zeile 7339) `formatBtn.isHidden` steuern:

```swift
    func setEditorMode(_ isEditor: Bool) {
        for btn in editorModeButtons { btn.isHidden = !isEditor }
        for btn in shellButtons { btn.isHidden = isEditor }
        formatBtn.isHidden = !isEditor  // ← NEU
        // ... (Rest unverändert)
```

### Schritt 4: Build nach Footer-Änderungen

```bash
bash build.sh 2>&1 | tail -5
```

Erwartet: `205 passed, 0 failed`

### Schritt 5: `formatCurrentDocument()` in `AppDelegate` implementieren

In `AppDelegate` nach `saveCurrentEditorAs()` (suche `func saveCurrentEditorAs`) einfügen:

```swift
    func formatCurrentDocument() {
        guard activeTab < tabEditorViews.count,
              let ev = tabEditorViews[activeTab],
              let storage = ev.syntaxStorage else {
            showGenericToast(badge: "FORMAT", text: "Kein Editor-Tab aktiv",
                             badgeColor: NSColor(calibratedWhite: 0.35, alpha: 1.0))
            return
        }
        let lang = storage.language
        let content = ev.textView.string

        // JSON: intern formatieren (kein externes Tool)
        if lang == .json {
            guard let data = content.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data),
                  let pretty = try? JSONSerialization.data(withJSONObject: obj,
                                                           options: [.prettyPrinted]),
                  let result = String(data: pretty, encoding: .utf8) else {
                showGenericToast(badge: "FORMAT", text: "Ungültiges JSON — Formatierung fehlgeschlagen",
                                 badgeColor: NSColor(calibratedRed: 0.6, green: 0.2, blue: 0.18, alpha: 1.0),
                                 dismissAfter: 5.0)
                return
            }
            replaceEditorContent(ev, with: result)
            showGenericToast(badge: "FORMAT", text: "JSON formatiert",
                             badgeColor: NSColor(calibratedRed: 0.18, green: 0.55, blue: 0.34, alpha: 1.0),
                             dismissAfter: 2.0)
            return
        }

        // Externe Tools für andere Sprachen
        let (toolPath, args, notFoundHint): (String?, [String], String)
        switch lang {
        case .html:
            let ext = tabEditorURLs[activeTab]?.pathExtension ?? "html"
            toolPath = findExecutable("npx")
            args = ["prettier", "--parser", "html", "--stdin-filepath", "file.\(ext)"]
            notFoundHint = "npm install -g prettier"
        case .css:
            toolPath = findExecutable("npx")
            args = ["prettier", "--parser", "css", "--stdin-filepath", "file.css"]
            notFoundHint = "npm install -g prettier"
        case .javascript:
            toolPath = findExecutable("npx")
            args = ["prettier", "--parser", "babel", "--stdin-filepath", "file.js"]
            notFoundHint = "npm install -g prettier"
        case .python:
            toolPath = findExecutable("black")
            args = ["--quiet", "-"]
            notFoundHint = "pip install black"
        case .swift:
            toolPath = findExecutable("swift-format") ?? xcrunFind("swift-format")
            args = []
            notFoundHint = "Xcode installieren (enthält swift-format)"
        default:
            showGenericToast(badge: "FORMAT", text: "Kein Formatter für \(lang.rawValue)",
                             badgeColor: NSColor(calibratedWhite: 0.35, alpha: 1.0), dismissAfter: 3.0)
            return
        }

        guard let tool = toolPath else {
            showGenericToast(badge: "FORMAT",
                             text: "Tool nicht gefunden — \(notFoundHint)",
                             badgeColor: NSColor(calibratedRed: 0.6, green: 0.2, blue: 0.18, alpha: 1.0),
                             dismissAfter: 6.0)
            return
        }

        // Prozess starten: stdin → formatter → stdout
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                let result = try await runFormatter(tool: tool, args: args, input: content)
                self.replaceEditorContent(ev, with: result)
                self.showGenericToast(badge: "FORMAT", text: "Fertig",
                                      badgeColor: NSColor(calibratedRed: 0.18, green: 0.55, blue: 0.34, alpha: 1.0),
                                      dismissAfter: 2.0)
            } catch {
                self.showGenericToast(badge: "FORMAT",
                                      text: error.localizedDescription,
                                      badgeColor: NSColor(calibratedRed: 0.6, green: 0.2, blue: 0.18, alpha: 1.0),
                                      dismissAfter: 6.0)
            }
        }
    }

    /// Ersetzt den gesamten Inhalt des Editors als einzelner Undo-Step.
    private func replaceEditorContent(_ ev: EditorView, with newText: String) {
        let tv = ev.textView!
        guard tv.shouldChangeText(in: NSRange(location: 0, length: tv.string.utf16.count),
                                  replacementString: newText) else { return }
        tv.textStorage?.replaceCharacters(in: NSRange(location: 0, length: tv.string.utf16.count),
                                          with: newText)
        tv.didChangeText()
    }

    /// Sucht ein ausführbares Tool in PATH-Standardorten.
    private func findExecutable(_ name: String) -> String? {
        let paths = ["/usr/local/bin", "/usr/bin", "/opt/homebrew/bin",
                     "/opt/homebrew/sbin", "/Users/\(NSUserName())/.nvm/current/bin"]
        return paths.compactMap { dir -> String? in
            let full = "\(dir)/\(name)"
            return FileManager.default.isExecutableFile(atPath: full) ? full : nil
        }.first
    }

    /// Sucht ein Tool via xcrun (Xcode Command Line Tools).
    private func xcrunFind(_ name: String) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        proc.arguments = ["--find", name]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        guard (try? proc.run()) != nil else { return nil }
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (path?.isEmpty == false) ? path : nil
    }

    /// Führt einen externen Formatter aus: input via stdin, Ergebnis von stdout.
    private func runFormatter(tool: String, args: [String], input: String) async throws -> String {
        return try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: tool)
                proc.arguments = args
                let inPipe  = Pipe()
                let outPipe = Pipe()
                let errPipe = Pipe()
                proc.standardInput  = inPipe
                proc.standardOutput = outPipe
                proc.standardError  = errPipe
                do {
                    try proc.run()
                    if let data = input.data(using: .utf8) {
                        inPipe.fileHandleForWriting.write(data)
                    }
                    inPipe.fileHandleForWriting.closeFile()
                    proc.waitUntilExit()
                    guard proc.terminationStatus == 0 else {
                        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                        let errMsg  = String(data: errData, encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Fehler"
                        cont.resume(throwing: NSError(
                            domain: "Formatter", code: Int(proc.terminationStatus),
                            userInfo: [NSLocalizedDescriptionKey: errMsg.isEmpty ? "Formatter fehlgeschlagen" : errMsg]))
                        return
                    }
                    let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                    let result  = String(data: outData, encoding: .utf8) ?? input
                    cont.resume(returning: result)
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }
```

### Schritt 6: Shortcut Shift+Opt+F in `BorderlessWindow.sendEvent` eintragen

Im Editor-Shortcut-Block (~Zeile 5057, nach dem Cmd+F Block) einfügen:

```swift
                    if flags2 == [.command, .option], event.charactersIgnoringModifiers == "f" {
                        d.formatCurrentDocument(); return
                    }
```

**Wichtig:** `flags2` wird momentan nur aus `[.command, .shift]` gebildet. Den Block erweitern:

```swift
                let flags2 = event.modifierFlags.intersection([.command, .shift, .option])
```

(War: `intersection([.command, .shift])` — `.option` hinzufügen)

### Schritt 7: `onFormatDocument` Callback in AppDelegate verdrahten

In `AppDelegate` wo `footerView.onEditorModeChange` gesetzt wird (~Zeile 18347) danach einfügen:

```swift
        footerView.onFormatDocument = { [weak self] in
            self?.formatCurrentDocument()
        }
```

### Schritt 8: Build + Test

```bash
bash build.sh 2>&1 | tail -10
```

Erwartet: `205 passed, 0 failed`

### Schritt 9: Manuell testen

1. Editor-Tab öffnen, `{"b":2,"a":1}` tippen, Shift+Opt+F → Code wird formatiert
2. JSON mit Syntax-Fehler → Toast "Ungültiges JSON"
3. Python-Datei öffnen, `black` nicht installiert → Toast mit Hinweis

### Schritt 10: Commit

```bash
git add systemtrayterminal.swift tests.swift
git commit -m "feat(editor): code formatter — JSON intern, HTML/JS/CSS/Python/Swift via external tools"
```

---

## Task 4: Version bump + Release

**Files:**
- Modify: `systemtrayterminal.swift` (kAppVersion → "1.5.8")
- Modify: `SystemTrayTerminal.app/Contents/Info.plist`
- Modify: `CHANGELOG.md`, `README.md`, `docs/index.html`

### Schritt 1: Version hochsetzen

In `systemtrayterminal.swift` Zeile 14:
```swift
let kAppVersion = "1.5.8"
```

In `SystemTrayTerminal.app/Contents/Info.plist`:
```xml
<string>1.5.8</string>  <!-- CFBundleVersion -->
<string>1.5.8</string>  <!-- CFBundleShortVersionString -->
```

### Schritt 2: CHANGELOG.md eintragen (oben einfügen)

```markdown
## v1.5.8 — DATUM

### New Features

- **Editor: Matching Bracket Highlight** — Cursor auf `{` `}` `(` `)` `[` `]` → Gegenstück wird sofort hervorgehoben. Automatisch, kein Shortcut nötig.
- **Editor: Auto-Indent beim Enter** — Neue Zeile übernimmt Einrückung der aktuellen Zeile. Smart Indent wenn Zeile mit `{`, `(`, `[` endet. Bracket-Split für `}` direkt nach Cursor.
- **Editor: Code Formatter (Shift+Opt+F)** — JSON intern, HTML/CSS/JS via prettier, Python via black, Swift via swift-format. Fehlermeldung mit Install-Hinweis wenn Tool fehlt. Vollständig Undo-fähig.
```

### Schritt 3: README + Landing Page aktualisieren

`README.md`: Download-Link auf v1.5.8 setzen.
`docs/index.html`: `softwareVersion`, Hero-Badge, Download-Button, Changelog-Eintrag, Terminal-Animation auf v1.5.8.

### Schritt 4: App-Bundle + Zip bauen

```bash
bash build_zip.sh 2>&1
```

### Schritt 5: Alles committen + pushen

```bash
git add systemtrayterminal.swift SystemTrayTerminal.app/Contents/Info.plist \
        CHANGELOG.md README.md docs/index.html SystemTrayTerminal_v1.5.8.zip.sha256
git commit -m "chore(release): v1.5.8"
git push
```

### Schritt 6: GitHub Release erstellen

```bash
gh release create v1.5.8 SystemTrayTerminal_v1.5.8.zip SystemTrayTerminal_v1.5.8.zip.sha256 \
   --title "v1.5.8" --notes "Bracket Highlight, Auto-Indent, Code Formatter"
```

---

## Testmatrix

| Feature | Unit-Test | Manueller Test |
|---------|-----------|----------------|
| Bracket Matching | ✓ `testBracketMatching()` | Cursor auf `{` → beide Brackets leuchten |
| Auto-Indent | ✓ `testAutoIndent()` | Enter nach `function() {` → Einrückung |
| JSON Formatter | ✓ `testJSONFormatter()` | Kompaktes JSON → pretty-printed |
| Extern-Formatter | Kein Unit-Test (Process nötig) | prettier mit HTML-Datei testen |
| Tool-nicht-gefunden | Kein Unit-Test | `findExecutable("nonexistent")` → Toast |
