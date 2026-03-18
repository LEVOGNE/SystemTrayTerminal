# Window Positioning — Sealed Fix

**Date:** 2026-03-16
**Status:** Implemented & Sealed — NICHT anfassen!

## Problem

macOS platziert Status-Bar-Items **asynchron** nach App-Launch. Die ersten ~150ms liefert `convertToScreen` auf dem Status-Bar-Button zwei Arten von falschen Koordinaten:

1. **`y ≈ -11`** — Button noch nicht in einem echten Screen-Window platziert
2. **`x ≈ far-right`** — Item temporär ganz rechts, wird durch spätere Items nach links geschoben

Das führte (seit v1.3) zu sichtbarem Aufblitzen unten-links oder einem Sprung von rechts nach links beim App-Start.

## Root Causes & Fixes

### Fix 1 — `positionWindowUnderTrayIcon()`: Fallback bei bogus-Koordinaten

**Problem:** `guard calculatedY > 0 else { return }` beendete die Funktion ohne Fallback, obwohl `button.window` gesetzt war — nur mit falschen Koordinaten (`y ≈ -11`).

**Fix:** Wenn `button.window == nil` **oder** `calculatedY <= 0` → Screen-Fallback verwenden:

```swift
let calculatedY = round(screenRect.minY - 4 - wSize.height)
if calculatedY > 0 {
    realPosition = (y: calculatedY, midX: round(screenRect.midX))
}
// else: bogus screenRect — fall through to screen fallback

// Fallback:
let fallbackY = round(screen.visibleFrame.maxY - 4 - wSize.height)
```

`screen.visibleFrame.maxY ≈ trayIcon.minY` (praktisch identisch) → kein sichtbarer Unterschied zur echten Position.

---

### Fix 2 — Launch-Sequenz: 200ms Delay für docked Windows

**Problem:** `DispatchQueue.main.async` + 150ms-Retry zeigte das Fenster noch während macOS die Status-Bar layoutet. Bei `main.async` (≈1ms) ist der X-Wert preliminary (ganz rechts), nach 150ms ist er final — sichtbarer Sprung.

**Fix:** Docked Windows warten **200ms** bevor `showWindowAnimated()` aufgerufen wird:

```swift
// In applicationDidFinishLaunching:

// Detached: hat gespeicherte Koordinaten aus UserDefaults → sofort zeigen
DispatchQueue.main.async { [weak self] in
    guard let self = self,
          UserDefaults.standard.bool(forKey: "windowDetached") else { return }
    self.restoreDetachedWindowState()
}

// Docked: 200ms warten bis alle Status-Bar-Items platziert sind
DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) { [weak self] in
    guard let self = self, !self.isWindowDetached else { return }
    self.showWindowAnimated()
}
```

**Warum 200ms:** Alle bekannten macOS-Versionen stabilisieren Status-Bar-Positionen innerhalb von ~150ms. 200ms gibt 50ms Puffer. Das Fenster bleibt komplett unsichtbar bis die echte Position bekannt ist — kein Flash, kein Sprung möglich.

**NIEMALS zurück zu `main.async` für docked** oder Retry-Logik — das ist der kaputte Pattern seit v1.3.

---

### Fix 3 — Pre-Position bei Window-Creation

Direkt nach `window = BorderlessWindow(...)` einmalig `positionWindowUnderTrayIcon()` aufrufen, damit das Fenster nie bei `(0, 0)` sitzt. Da `button.window` zu diesem Zeitpunkt immer nil/bogus ist, greift der Screen-Fallback — das ist korrekt.

---

### Fix 4 — Crash: Dummy-TerminalView in `createEditorTab()`

**Problem:** `TerminalView.readPTY()` ruft `NSApp.terminate(nil)` wenn `onShellExit == nil` und PTY EOF erkannt wird. Das Placeholder-`TerminalView` mit `/usr/bin/true` exitiert sofort → App-Crash.

**Fix:**
```swift
let dummyTV = TerminalView(frameRect: tf, shell: "/usr/bin/true", cwd: nil, historyId: nil)
dummyTV.onShellExit = { }  // CRITICAL: leerer Handler verhindert NSApp.terminate(nil)
let placeholder = SplitContainer(frame: tf, primary: dummyTV)
placeholder.isHidden = true
```

---

### Fix 5 — `makeFirstResponder` nur wenn Fenster sichtbar

In `createEditorTab()` und `switchToTab()`:

```swift
if window.isVisible { window.makeFirstResponder(editorView.textView) }
```

Verhindert AppKit-Redraw während Session-Restore (Fenster noch unsichtbar bei Launch).

---

### Fix 6 — `reorderTab()` fehlende Parallel-Arrays

`tabTypes`, `tabEditorViews`, `tabEditorModes`, `tabEditorURLs`, `tabEditorDirty` müssen beim Tab-Reorder mitgezogen werden (waren vergessen):

```swift
if from < tabTypes.count && to < tabTypes.count {
    let tt = tabTypes.remove(at: from); tabTypes.insert(tt, at: to)
    let ev = tabEditorViews.remove(at: from); tabEditorViews.insert(ev, at: to)
    let em = tabEditorModes.remove(at: from); tabEditorModes.insert(em, at: to)
    let eu = tabEditorURLs.remove(at: from); tabEditorURLs.insert(eu, at: to)
    let ed = tabEditorDirty.remove(at: from); tabEditorDirty.insert(ed, at: to)
}
```

## Debugging-Methodik

Falls das Window-Positioning in Zukunft wieder Probleme macht: `[WINPOS]` Debug-Prints an folgenden Stellen einfügen:

- `positionWindowUnderTrayIcon()`: screenRect, calculatedY, gewählte midX/y
- `showWindowAnimated()`: finale Position vor `setFrameOrigin`
- Launch-Sequenz: Zeitstempel wann `showWindowAnimated()` aufgerufen wird

Dann App starten und Log auswerten — die Zeitstempel zeigen sofort ob macOS die Koordinaten noch nicht stabilisiert hat.
