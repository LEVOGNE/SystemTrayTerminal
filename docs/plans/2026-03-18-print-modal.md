# Print Modal Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Drucker-Icon im Footer öffnet ein custom dunkles Modal, User wählt was gedruckt wird, dann nativer macOS-Druckdialog.

**Architecture:** `PrintModal: NSView` (analog zu `EditorAlertOverlay`) zeigt 1–2 Aktions-Buttons je nach Tab-Typ (Terminal / Markdown / HTML / SVG / CSV / sonstige Editoren). Gerenderte Typen nutzen eine temporäre WKWebView; Quellcode nutzt `textView.printOperation(with:)` direkt. Build-Befehl: `bash build.sh`.

**Tech Stack:** Swift, AppKit, WebKit (bereits importiert), SF Symbols, `NSPrintOperation`, `WKWebView.printOperation(with:)`

---

### Task 1: Test für `buildPrintOptions` in `tests.swift`

**Files:**
- Modify: `tests.swift` — vor `// MARK: - Results` (Zeile ~1389)

Diese Funktion (die wir in Task 3 implementieren) bestimmt anhand von Tab-Typ und Dateiendung welche Print-Optionen angezeigt werden. Da sie pure Logik ist, kann sie in `tests.swift` als Stub getestet werden.

**Step 1: Stub + Test in `tests.swift` einfügen** (direkt vor `// MARK: - Results`):

```swift
// ── PrintOption stub (mirrors quickTerminal.swift) ──────────────────────────
enum PrintAction_Test { case renderedHTML, sourceCode, terminal }
struct PrintOption_Test { let label: String; let action: PrintAction_Test }

func buildPrintOptions_Test(isEditor: Bool, ext: String) -> [PrintOption_Test] {
    // Stub — replace with real logic in Task 3
    return []
}

func testBuildPrintOptions() {
    // Terminal tab
    let t = buildPrintOptions_Test(isEditor: false, ext: "")
    assert(t.count == 1 && t[0].action == .terminal, "terminal: 1 option .terminal")

    // Markdown
    let md = buildPrintOptions_Test(isEditor: true, ext: "md")
    assert(md.count == 2, "markdown: 2 options")
    assert(md[0].action == .renderedHTML, "markdown[0] = renderedHTML")
    assert(md[1].action == .sourceCode,   "markdown[1] = sourceCode")

    // HTML
    let html = buildPrintOptions_Test(isEditor: true, ext: "html")
    assert(html.count == 2 && html[0].action == .renderedHTML, "html: 2 options, first rendered")

    // SVG
    let svg = buildPrintOptions_Test(isEditor: true, ext: "svg")
    assert(svg.count == 2 && svg[0].action == .renderedHTML, "svg: 2 options, first rendered")

    // CSV
    let csv = buildPrintOptions_Test(isEditor: true, ext: "csv")
    assert(csv.count == 2 && csv[0].action == .renderedHTML, "csv: 2 options, first rendered")

    // Swift (source only)
    let sw = buildPrintOptions_Test(isEditor: true, ext: "swift")
    assert(sw.count == 1 && sw[0].action == .sourceCode, "swift: 1 option sourceCode")

    print("✓ buildPrintOptions — 6 cases")
}
testBuildPrintOptions()
```

**Step 2: Tests laufen lassen — müssen FEHLSCHLAGEN**

```bash
cd "/Users/l3v0/Desktop/FERTIGE PROJEKTE/quickTerminal"
swift tests.swift 2>&1 | tail -5
```

Erwartet: `Assertion failed` bei `terminal: 1 option .terminal` (Stub gibt `[]` zurück).

---

### Task 2: `PrintModal` Klasse + Typen in `quickTerminal.swift`

**Files:**
- Modify: `quickTerminal.swift` — einfügen **direkt vor** `// MARK: - Editor Alert Overlay` (Zeile ~15354)

**Step 1: Typen und Klasse einfügen**

Füge diesen Block direkt vor `// MARK: - Editor Alert Overlay` ein:

```swift
// MARK: - Print Modal

enum PrintAction {
    case renderedHTML(String, URL?)   // html string + optional base URL
    case sourceCode                   // textView.printOperation
    case terminal                     // terminal buffer as HTML
}

struct PrintOption {
    let label:  String
    let action: PrintAction
}

class PrintModal: NSView {
    private let panel = NSView()
    private var onSelect: ((PrintAction) -> Void)?
    private var onCancel: (() -> Void)?

    override var isFlipped: Bool { true }
    override func mouseDown(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
    override func scrollWheel(with event: NSEvent) {}

    static func show(in contentView: NSView,
                     options: [PrintOption],
                     onSelect: @escaping (PrintAction) -> Void,
                     onCancel: @escaping () -> Void) {
        let v = PrintModal(frame: contentView.bounds)
        v.onSelect = onSelect
        v.onCancel = onCancel
        v.autoresizingMask = [.width, .height]
        v.build(options: options)
        contentView.addSubview(v)
        v.alphaValue = 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            v.animator().alphaValue = 1
        }
    }

    private func dismissAnimated() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            self.animator().alphaValue = 0
        }, completionHandler: { self.removeFromSuperview() })
    }

    private func build(options: [PrintOption]) {
        // Backdrop
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor

        // Panel sizing
        let btnH: CGFloat = 36
        let btnGap: CGFloat = 8
        let padV: CGFloat = 20
        let padH: CGFloat = 20
        let iconH: CGFloat = 28
        let titleH: CGFloat = 20
        let cancelH: CGFloat = 28
        let panelW: CGFloat = 320
        let panelH = padV + iconH + 10 + titleH + 16
                    + CGFloat(options.count) * (btnH + btnGap)
                    + cancelH + padV

        // Panel
        panel.wantsLayer = true
        panel.layer?.backgroundColor = NSColor(calibratedRed: 0.08, green: 0.08,
                                               blue: 0.10, alpha: 0.97).cgColor
        panel.layer?.cornerRadius  = 10
        panel.layer?.borderColor   = NSColor(calibratedWhite: 1, alpha: 0.09).cgColor
        panel.layer?.borderWidth   = 0.5
        panel.layer?.shadowOpacity = 0.7
        panel.layer?.shadowRadius  = 22
        panel.layer?.shadowOffset  = CGSize(width: 0, height: -8)
        panel.layer?.shadowColor   = NSColor.black.cgColor
        panel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(panel)
        NSLayoutConstraint.activate([
            panel.centerXAnchor.constraint(equalTo: centerXAnchor),
            panel.centerYAnchor.constraint(equalTo: centerYAnchor),
            panel.widthAnchor.constraint(equalToConstant: panelW),
            panel.heightAnchor.constraint(equalToConstant: panelH),
        ])

        var y = padV

        // Printer icon
        let cfg = NSImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        if let img = NSImage(systemSymbolName: "printer", accessibilityDescription: nil)?
                .withSymbolConfiguration(cfg) {
            let iv = NSImageView(image: img)
            iv.contentTintColor = NSColor(calibratedWhite: 0.75, alpha: 1)
            iv.frame = NSRect(x: (panelW - iconH) / 2, y: y, width: iconH, height: iconH)
            panel.addSubview(iv)
        }
        y += iconH + 10

        // Title
        let title = NSTextField(labelWithString: "Drucken")
        title.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        title.textColor = NSColor(calibratedWhite: 0.92, alpha: 1)
        title.alignment = .center
        title.frame = NSRect(x: padH, y: y, width: panelW - padH * 2, height: titleH)
        panel.addSubview(title)
        y += titleH + 16

        // Action buttons
        for opt in options {
            let btn = makePanelButton(label: opt.label, width: panelW - padH * 2)
            btn.frame = NSRect(x: padH, y: y, width: panelW - padH * 2, height: btnH)
            let action = opt.action
            (btn as? PrintPanelButton)?.onTap = { [weak self] in
                self?.dismissAnimated()
                self?.onSelect?(action)
            }
            panel.addSubview(btn)
            y += btnH + btnGap
        }

        // Cancel
        let cancelBtn = NSButton(title: "Abbrechen", target: nil, action: nil)
        cancelBtn.bezelStyle = .inline
        cancelBtn.isBordered = false
        cancelBtn.font = NSFont.systemFont(ofSize: 12)
        cancelBtn.contentTintColor = NSColor(calibratedWhite: 0.45, alpha: 1)
        cancelBtn.frame = NSRect(x: padH, y: y, width: panelW - padH * 2, height: cancelH)
        cancelBtn.alignment = .center
        cancelBtn.target = self
        cancelBtn.action = #selector(cancelTapped)
        panel.addSubview(cancelBtn)
    }

    @objc private func cancelTapped() {
        dismissAnimated()
        onCancel?()
    }

    private func makePanelButton(label: String, width: CGFloat) -> NSView {
        let btn = PrintPanelButton(frame: .zero)
        btn.labelText = label
        return btn
    }
}

private class PrintPanelButton: NSView {
    var labelText: String = "" { didSet { labelField.stringValue = labelText } }
    var onTap: (() -> Void)?
    private let labelField = NSTextField(labelWithString: "")
    private var trackingArea: NSTrackingArea?
    private var isHovered = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.backgroundColor = NSColor(calibratedWhite: 1, alpha: 0.06).cgColor

        labelField.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        labelField.textColor = NSColor(calibratedWhite: 0.88, alpha: 1)
        labelField.alignment = .center
        labelField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(labelField)
        NSLayoutConstraint.activate([
            labelField.centerXAnchor.constraint(equalTo: centerXAnchor),
            labelField.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        trackingArea = NSTrackingArea(rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp], owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }
    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        animateBg(to: NSColor(calibratedWhite: 1, alpha: 0.12).cgColor)
    }
    override func mouseExited(with event: NSEvent) {
        isHovered = false
        animateBg(to: NSColor(calibratedWhite: 1, alpha: 0.06).cgColor)
    }
    override func mouseDown(with event: NSEvent) {
        animateBg(to: NSColor(calibratedWhite: 1, alpha: 0.20).cgColor, duration: 0.06)
    }
    override func mouseUp(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        animateBg(to: isHovered
            ? NSColor(calibratedWhite: 1, alpha: 0.12).cgColor
            : NSColor(calibratedWhite: 1, alpha: 0.06).cgColor)
        if bounds.contains(loc) { onTap?() }
    }
    private func animateBg(to color: CGColor, duration: CFTimeInterval = 0.15) {
        let anim = CABasicAnimation(keyPath: "backgroundColor")
        anim.fromValue = layer?.presentation()?.backgroundColor ?? layer?.backgroundColor
        anim.toValue = color; anim.duration = duration
        anim.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer?.add(anim, forKey: "bg"); layer?.backgroundColor = color
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
}
```

**Step 2: Kompilieren (kein Test nötig — UI-only)**

```bash
cd "/Users/l3v0/Desktop/FERTIGE PROJEKTE/quickTerminal"
cp quickTerminal.swift /tmp/qt_build.swift
swiftc -O /tmp/qt_build.swift -o /tmp/qt_test \
  -framework Cocoa -framework Carbon -framework AVKit -framework WebKit 2>&1 | head -20
```

Erwartet: keine Ausgabe (kein Fehler).

---

### Task 3: `buildPrintOptions`, `printCurrentTab`, `executePrintAction` in AppDelegate

**Files:**
- Modify: `quickTerminal.swift` — im AppDelegate, direkt nach dem `// MARK: - Preview` Block (nach `buildPreviewHTML` und `isTabPreviewable`)

**Step 1: Block einfügen** — nach der schließenden `}` von `buildPreviewHTML`:

```swift
// MARK: - Print

private func buildPrintOptions(isEditor: Bool, ext: String) -> [PrintOption] {
    guard isEditor else {
        return [PrintOption(label: "Terminal drucken", action: .terminal)]
    }
    let rendered: PrintAction
    switch ext {
    case "md", "markdown", "mdown", "mkd":
        rendered = .renderedHTML(buildPreviewHTML(for: activeTab) ?? "", tabEditorURLs[safe: activeTab] ?? nil)
        return [
            PrintOption(label: "Formatiert drucken", action: rendered),
            PrintOption(label: "Quellcode drucken",  action: .sourceCode),
        ]
    case "html", "htm":
        rendered = .renderedHTML(buildPreviewHTML(for: activeTab) ?? "", tabEditorURLs[safe: activeTab] ?? nil)
        return [
            PrintOption(label: "Vorschau drucken",   action: rendered),
            PrintOption(label: "Quellcode drucken",  action: .sourceCode),
        ]
    case "svg":
        rendered = .renderedHTML(buildPreviewHTML(for: activeTab) ?? "", tabEditorURLs[safe: activeTab] ?? nil)
        return [
            PrintOption(label: "SVG-Grafik drucken", action: rendered),
            PrintOption(label: "Quellcode drucken",  action: .sourceCode),
        ]
    case "csv":
        rendered = .renderedHTML(buildPreviewHTML(for: activeTab) ?? "", tabEditorURLs[safe: activeTab] ?? nil)
        return [
            PrintOption(label: "Als Tabelle drucken", action: rendered),
            PrintOption(label: "Quellcode drucken",   action: .sourceCode),
        ]
    default:
        return [PrintOption(label: "Quellcode drucken", action: .sourceCode)]
    }
}

func printCurrentTab() {
    guard !termViews.isEmpty, activeTab < termViews.count else { return }
    let isEditor = activeTab < tabTypes.count && tabTypes[activeTab] == .editor
    let ext: String
    if isEditor, activeTab < tabEditorURLs.count, let u = tabEditorURLs[activeTab] {
        ext = u.pathExtension.lowercased()
    } else {
        ext = ""
    }
    let options = buildPrintOptions(isEditor: isEditor, ext: ext)
    guard let cv = window.contentView else { return }
    PrintModal.show(in: cv, options: options, onSelect: { [weak self] action in
        self?.executePrintAction(action)
    }, onCancel: {})
}

private var printWebView: WKWebView?   // retained until print completes

func executePrintAction(_ action: PrintAction) {
    switch action {

    case .sourceCode:
        guard activeTab < tabEditorViews.count,
              let ev = tabEditorViews[activeTab] else { return }
        let op = ev.textView.printOperation(with: NSPrintInfo.shared)
        op.showsPrintPanel = true
        op.showsProgressPanel = true
        op.run(for: window, delegate: nil, didRun: nil, contextInfo: nil)

    case .terminal:
        let isDark = NSColor(cgColor: kTermBgCGColor)?.brightnessComponent ?? 0 < 0.5
        let html = buildTerminalPrintHTML(isDark: isDark)
        printHTML(html, baseURL: nil)

    case .renderedHTML(let html, let baseURL):
        printHTML(html, baseURL: baseURL)
    }
}

private func buildTerminalPrintHTML(isDark: Bool) -> String {
    // Grab the active terminal's visible + scrollback content
    let lines: [String]
    if activeTab < termViews.count, let tv = termViews[activeTab] {
        let grid = tv.terminal.grid
        lines = grid.map { row in
            String(row.map { $0.char == "\0" ? " " : $0.char })
                .replacingOccurrences(of: "  +$", with: "", options: .regularExpression)
        }
    } else { lines = [] }
    let bg  = isDark ? "#0d0d10" : "#ffffff"
    let fg  = isDark ? "#d0d0d0" : "#1a1a1a"
    let escaped = lines.map { l in
        l.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
    }.joined(separator: "\n")
    return """
    <!DOCTYPE html><html><head><meta charset="utf-8">
    <style>
    body{background:\(bg);color:\(fg);font-family:Menlo,monospace;font-size:11px;
         white-space:pre;margin:16px;line-height:1.4}
    </style></head><body>\(escaped)</body></html>
    """
}

private func printHTML(_ html: String, baseURL: URL?) {
    let wk = WKWebView(frame: window.contentView?.bounds ?? .zero)
    wk.isHidden = true
    window.contentView?.addSubview(wk)
    printWebView = wk

    class NavDelegate: NSObject, WKNavigationDelegate {
        weak var delegate: AppDelegate?
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let d = delegate, let w = d.window else { return }
            let op = webView.printOperation(with: NSPrintInfo.shared)
            op.showsPrintPanel   = true
            op.showsProgressPanel = true
            op.run(for: w, delegate: d,
                   didRun: #selector(AppDelegate.printOperationDidRun(_:success:contextInfo:)),
                   contextInfo: nil)
        }
    }
    let nav = NavDelegate(); nav.delegate = self
    wk.navigationDelegate = nav
    // Retain nav delegate alongside webview
    objc_setAssociatedObject(wk, "nav", nav, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    wk.loadHTMLString(html, baseURL: baseURL)
}

@objc func printOperationDidRun(_ op: NSPrintOperation,
                                success: Bool,
                                contextInfo: UnsafeMutableRawPointer?) {
    printWebView?.removeFromSuperview()
    printWebView = nil
}
```

**Wichtig — `[safe:]` Subscript:** Der Code nutzt `tabEditorURLs[safe: activeTab]`. Falls dieser Subscript noch nicht existiert, stattdessen `activeTab < tabEditorURLs.count ? tabEditorURLs[activeTab] : nil` schreiben. Prüfe ob `[safe:]` im Projekt existiert:

```bash
grep -n "subscript.*safe" "/Users/l3v0/Desktop/FERTIGE PROJEKTE/quickTerminal/quickTerminal.swift" | head -3
```

Falls kein Ergebnis → ersetze alle `tabEditorURLs[safe: activeTab] ?? nil` durch `(activeTab < tabEditorURLs.count ? tabEditorURLs[activeTab] : nil)`.

**Step 2: Kompilieren**

```bash
cp quickTerminal.swift /tmp/qt_build.swift
swiftc -O /tmp/qt_build.swift -o /tmp/qt_test \
  -framework Cocoa -framework Carbon -framework AVKit -framework WebKit 2>&1 | head -20
```

---

### Task 4: Stub in `tests.swift` mit echter Logik synchronisieren + Tests grün

**Files:**
- Modify: `tests.swift` — `buildPrintOptions_Test` Stub durch korrekte Logik ersetzen

**Step 1: Stub durch echte Logik ersetzen**

Ersetze den `buildPrintOptions_Test` Stub:

```swift
func buildPrintOptions_Test(isEditor: Bool, ext: String) -> [PrintOption_Test] {
    guard isEditor else {
        return [PrintOption_Test(label: "Terminal drucken", action: .terminal)]
    }
    let renderedExts: Set<String> = ["md","markdown","mdown","mkd","html","htm","svg","csv"]
    guard renderedExts.contains(ext) else {
        return [PrintOption_Test(label: "Quellcode drucken", action: .sourceCode)]
    }
    return [
        PrintOption_Test(label: "Drucken",         action: .renderedHTML),
        PrintOption_Test(label: "Quellcode drucken", action: .sourceCode),
    ]
}
```

**Step 2: Tests laufen lassen — müssen GRÜN sein**

```bash
swift tests.swift 2>&1 | grep -E "buildPrint|Results|failed"
```

Erwartet:
```
✓ buildPrintOptions — 6 cases
Results: 198 passed, 0 failed
```

---

### Task 5: Printer-Button in FooterBarView

**Files:**
- Modify: `quickTerminal.swift` — `FooterBarView` Klasse (Zeilen ~6924–7206)

**Step 1: Property + Callback deklarieren**

Im Properties-Block von `FooterBarView` (nach `var gearBtn: GearButton!`):

```swift
private var printerBtn: SymbolHoverButton!
var onPrint: (() -> Void)?
```

**Step 2: Button in `init` initialisieren**

Direkt **vor** `gearBtn = GearButton(...)`:

```swift
printerBtn = SymbolHoverButton(
    symbolName: "printer", size: 12,
    normalColor: NSColor(calibratedWhite: 0.50, alpha: 1.0),
    hoverColor:  NSColor(calibratedWhite: 0.88, alpha: 1.0),
    hoverBg: NSColor(calibratedWhite: 1.0, alpha: 0.08),
    pressBg: NSColor(calibratedWhite: 1.0, alpha: 0.16))
printerBtn.toolTip = "Drucken"
printerBtn.onClick = { [weak self] in self?.onPrint?() }
rechtsContent.addSubview(printerBtn)
```

**Step 3: Layout in `layout()` einfügen**

Im `layout()` Override, direkt **vor** der Zeile `gearBtn.frame = ...` (Zeile ~7139):

```swift
let printerSize: CGFloat = 24
printerBtn.frame = NSRect(x: rx, y: cy - printerSize / 2,
                          width: printerSize, height: printerSize)
rx += printerSize + gap
```

**Step 4: `onPrint` im AppDelegate verdrahten**

In `applicationDidFinishLaunching`, nach `footerView.onSettings = ...` (Zeile ~16450):

```swift
footerView.onPrint = { [weak self] in self?.printCurrentTab() }
```

**Step 5: Kompilieren**

```bash
cp quickTerminal.swift /tmp/qt_build.swift
swiftc -O /tmp/qt_build.swift -o /tmp/qt_test \
  -framework Cocoa -framework Carbon -framework AVKit -framework WebKit 2>&1 | head -20
```

Erwartet: keine Ausgabe.

---

### Task 6: Finaler Build + alle Tests

**Step 1: Vollständiger Build mit Tests**

```bash
cd "/Users/l3v0/Desktop/FERTIGE PROJEKTE/quickTerminal"
bash build.sh 2>&1 | tail -10
```

Erwartet:
```
Results: 198 passed, 0 failed
All tests PASSED!
```

**Step 2: Manuell testen**

1. App starten: `./quickTerminal`
2. Terminal-Tab aktiv → Drucker-Icon im Footer klicken → Modal zeigt "Terminal drucken"
3. Editor-Tab mit `.md`-Datei → Modal zeigt "Formatiert drucken" + "Quellcode drucken"
4. Formatiert drucken → macOS Druckdialog öffnet sich
5. Modal "Abbrechen" → Modal schließt, kein Druck
6. `editor`-Tab ohne previewbare Datei (z.B. `.swift`) → Modal zeigt nur "Quellcode drucken"

**Step 3: Commit**

```bash
git add quickTerminal.swift tests.swift build.sh
git commit -m "feat: print modal with per-tab-type options and native macOS print dialog"
```

---

## Bekannte Stolperfallen

| Problem | Lösung |
|---|---|
| `[safe:]` Subscript existiert nicht | `(i < arr.count ? arr[i] : nil)` verwenden |
| WKWebView print braucht geladenes HTML | NavDelegate `.didFinish` abwarten — im Plan korrekt gelöst |
| `objc_setAssociatedObject` nicht importiert | `import ObjectiveC` am Anfang der Datei prüfen (oder `Foundation` reicht) |
| Build schlägt fehl mit "modified during build" | Immer via `cp quickTerminal.swift /tmp/qt_build.swift` bauen |
| `terminal.grid` nicht erreichbar | Prüfe ob `terminal` Property auf `TerminalView` public ist; alternativ `termViews[activeTab]?.terminal.grid` |
