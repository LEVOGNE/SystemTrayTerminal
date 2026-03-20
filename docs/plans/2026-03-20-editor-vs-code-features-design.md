# Editor VS Code Features — Design Document

**Datum:** 2026-03-20
**Version:** v1.5.8 (geplant)

---

## Überblick

Drei neue Editor-Features nach VS Code Vorbild:

1. **Matching Bracket Highlight** — Gegenstück-Klammer automatisch hervorheben
2. **Auto-Indent beim Enter** — Einrückung beibehalten + Smart Indent für `{`, `(`, `[`
3. **Code Formatter (Beautify)** — Shift+Opt+F oder `{ }` Footer-Button

---

## Feature 1: Matching Bracket Highlight

### Verhalten
- Cursor bewegt sich auf/neben `{` `}` `(` `)` `[` `]` → beide Brackets bekommen Hintergrund-Highlight
- Nächste Cursor-Bewegung → alter Highlight wird entfernt
- Automatisch, kein Shortcut nötig

### Implementierung
- **Klasse:** `EditorTextView` (bereits vorhanden, private NSTextView Subklasse)
- **Trigger:** `NSTextView.didChangeSelection` Notification (observe in `setup()`)
- **Highlight:** `layoutManager.addTemporaryAttribute(.backgroundColor, value: bracketColor, forCharacterRange: range)`
- **Farbe:** `NSColor.selectedTextBackgroundColor.withAlphaComponent(0.4)` (theme-aware)
- **Nesting:** Zähler-basierter Scan — vorwärts für öffnende, rückwärts für schließende Brackets
- **Performance:** Scan maximal 10.000 Zeichen in jede Richtung (verhindert Hänger bei riesigen Dateien)

### Dateien
- Modify: `systemtrayterminal.swift` — `EditorTextView` Klasse

---

## Feature 2: Auto-Indent beim Enter

### Verhalten
1. **Basis:** Enter → neue Zeile mit gleicher führender Whitespace wie die aktuelle Zeile
2. **Smart:** Zeile endet mit `{` `(` `[` → eine Einrückebene mehr (2 Spaces, oder Tab wenn `editorUseTabs`)
3. **Split:** Cursor direkt vor `}` `)` `]` → schließende Klammer auf eigene Zeile mit Basis-Indent

### Implementierung
- **Klasse:** `EditorTextView`
- **Override:** `override func insertNewline(_ sender: Any?)`
- **Einrückeinheit:** liest `UserDefaults.standard.bool(forKey: "editorUseTabs")` (bereits vorhanden)
- **Indent-Größe:** 2 Spaces (Standard) / 4 Spaces / Tab je nach Setting
- **Keine Auswirkung auf:** Nano-Modus / Vim-Modus (diese überschreiben Enter selbst)

### Dateien
- Modify: `systemtrayterminal.swift` — `EditorTextView` Klasse

---

## Feature 3: Code Formatter (Beautify)

### Trigger
- **Keyboard:** `Shift+Opt+F` — in `BorderlessWindow.performKeyEquivalent` (`.command` Flags Check)
- **Button:** `{ }` Button im `FooterBarView` neben NORMAL/NANO/VIM Buttons (nur sichtbar bei Editor-Tabs)

### Sprachen & Tools

| Sprache | Tool | Kommando |
|---------|------|----------|
| JSON | Intern | `JSONSerialization` pretty-print (kein externes Tool) |
| HTML | prettier | `npx prettier --parser html --stdin-filepath file.html` |
| CSS | prettier | `npx prettier --parser css --stdin-filepath file.css` |
| JavaScript/TS | prettier | `npx prettier --parser babel --stdin-filepath file.js` |
| Python | black | `black --quiet -` (stdin/stdout) |
| Swift | swift-format | `xcrun swift-format` (stdin/stdout) |
| Alle anderen | — | Toast: `"Kein Formatter für <Sprache>"` |

### Flow
1. `formatCurrentDocument()` in `AppDelegate` aufrufen
2. Aktive Sprache des Editor-Tabs ermitteln (`tabEditorViews[activeTab]?.syntaxStorage?.language`)
3. Tool-Pfad suchen (JSON: sofort, externe Tools: `which npx` / `which black` / `xcrun --find swift-format`)
4. Tool nicht gefunden → `showGenericToast(badge: "FORMAT", text: "prettier nicht gefunden — npm install -g prettier")`
5. Prozess starten: aktueller Inhalt → stdin, formatierter Code ← stdout
6. Exit-Code 0 → `textView.shouldChangeText / replaceCharacters / didChangeText` (Undo-fähig!)
7. Exit-Code ≠ 0 → Toast mit stderr als Fehlermeldung (z.B. Syntax-Fehler im Code)

### Undo
Kompletter Inhalt-Replace als **ein** Undo-Step, sodass `Cmd+Z` den gesamten Format-Vorgang rückgängig macht.

### Dateien
- Modify: `systemtrayterminal.swift`
  - `FooterBarView` — `{ }` Button hinzufügen
  - `BorderlessWindow.performKeyEquivalent` — Shift+Opt+F
  - `AppDelegate` — `formatCurrentDocument()` Methode

---

## Implementierungsreihenfolge (Ansatz B — Incremental)

| Task | Feature | Risiko | Abhängigkeiten |
|------|---------|--------|----------------|
| 1 | Bracket Highlight | Niedrig | Keine |
| 2 | Auto-Indent | Niedrig | Keine |
| 3 | Code Formatter | Mittel | Externe Tools |

---

## Nicht in diesem Release (YAGNI)

- Tab-Größe als Setting (separates Feature)
- Minimap
- LSP / Code-Completion
- Multi-Cursor

---

## Versionsplan

- v1.5.8: Alle 3 Features (Bracket Highlight + Auto-Indent + Formatter)
