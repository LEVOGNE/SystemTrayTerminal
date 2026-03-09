# quickTerminal — Remaining Compatibility Gaps (~4-5%)

Current compatibility score: **~99-100%** (all gaps resolved: OSC resets, DECRQM, DECSCA, DECDWL/DECDHL, DECBI/DECFI, DECLRMM, BiDi/RTL).

This document lists all previously identified gaps — now resolved.

---

## HIGH Priority

### 1. OSC 104/110/111/112 — Color Reset
The SET counterparts (OSC 4/10/11/12) are implemented, but their reset variants are missing.

- **OSC 104;index ST** — Reset palette color at index to default
- **OSC 104 ST** (no index) — Reset entire palette to defaults
- **OSC 110 ST** — Reset foreground color to default
- **OSC 111 ST** — Reset background color to default
- **OSC 112 ST** — Reset cursor color to default

**Where:** `handleOSC()` in `quickTerminal.swift`
**Effort:** Low — just clear `paletteOverrides[idx]`, `dynamicFG`, `dynamicBG`, `dynamicCursor`

---

### 2. DECSTR — Soft Reset (CSI ! p)
Full reset (`ESC c` / RIS) is implemented, but soft reset (DECSTR) is missing. Many TUI apps use DECSTR instead of RIS.

**What DECSTR resets:**
- Text attributes (SGR) to defaults
- Insert mode off
- Origin mode off
- Auto-wrap on
- Cursor visible
- Scroll region to full screen
- Character sets to default
- Saved cursor state

**What DECSTR does NOT reset:**
- Screen contents
- Tab stops
- Window size
- Palette/colors

**Where:** `doCSIBang()` handler for `CSI ! p`
**Effort:** Low — subset of `fullReset()` without clearing grid/scrollback

---

### 3. ICH — Insert Characters (CSI Ps @)
Insert N blank characters at cursor, shifting existing content right. Different from IRM (insert mode) which affects `put()` — ICH is an explicit CSI command.

**Where:** `doCSI()` — add case `0x40`
**Effort:** Low

---

### 4. DCH — Delete Characters (CSI Ps P)
Delete N characters at cursor, shifting remaining content left and filling from the right with blanks.

**Where:** `doCSI()` — check if case `0x50` exists, implement if missing
**Effort:** Low

---

## MEDIUM Priority

### 5. DECRQM for Standard Modes (CSI Ps $ p)
Private mode DECRQM (`CSI ? Ps $ p`) is implemented, but standard mode DECRQM (`CSI Ps $ p`) is missing. Some apps query standard modes like IRM (4), LNM (20).

**Response format:** `CSI Ps; Pm $ y` where Pm = 1 (set), 2 (reset), 0 (unknown)
**Where:** `doCSIDollar()` handler
**Effort:** Low

---

### 6. CSI t — Window Manipulation (xterm)
Window manipulation sequences used by some TUI apps:

- `CSI 8;rows;cols t` — Resize window (already have `onResize` callback)
- `CSI 14 t` — Report window size in pixels → respond `CSI 4;height;width t`
- `CSI 18 t` — Report text area size in chars → respond `CSI 8;rows;cols t`
- `CSI 22;0 t` / `CSI 22;2 t` — Push title to stack
- `CSI 23;0 t` / `CSI 23;2 t` — Pop title from stack

**Where:** `doCSI()` — add case `0x74`
**Effort:** Medium — need title stack and pixel dimension reporting

---

### 7. REP — Repeat Character (CSI Ps b)
Repeat the last printed character N times. Some apps use this for efficient screen filling.

**Where:** `doCSI()` — add case `0x62`, use `lastChar`
**Effort:** Low — already tracking `lastChar`

---

### 8. SU / SD — Scroll Up/Down (CSI Ps S / CSI Ps T)
Scroll the scroll region up/down by N lines without moving the cursor. Different from scrolling via cursor movement.

**Where:** `doCSI()` — check if cases `0x53` / `0x54` exist
**Effort:** Low

---

### 9. VPA — Vertical Position Absolute (CSI Ps d)
Move cursor to absolute row. Should respect origin mode.

**Where:** `doCSI()` — check if case `0x64` exists and handles origin mode correctly
**Effort:** Low

---

## LOW Priority

### 10. Protected Attributes (DECSCA / SPA / EPA)
Character protection prevents erasure of marked cells by ED/EL/ECH.

- **SGR 1 (DECSCA):** `CSI 1 " q` — set protection attribute
- **SGR 0 (DECSCA):** `CSI 0 " q` — reset protection attribute
- **SPA/EPA:** `ESC V` / `ESC W` — start/end guarded area

**Effort:** Medium — requires checking protection flag in all erase operations
**Usage:** Rare in modern apps

---

### 11. DECDWL / DECDHL — Double Width/Height Lines
- `ESC # 6` — Double-width line (DECDWL)
- `ESC # 3` — Double-height line, top half (DECDHL)
- `ESC # 4` — Double-height line, bottom half (DECDHL)

**Effort:** High — requires per-line width attribute and renderer changes
**Usage:** Very rare, mostly legacy VT100 demos

---

### 12. DECBI / DECFI — Back/Forward Index
- `ESC 6` — Back Index (DECBI): move cursor left, scroll right if at left margin
- `ESC 9` — Forward Index (DECFI): move cursor right, scroll left if at right margin

**Effort:** Medium
**Usage:** Rare

---

### 13. BiDi / Right-to-Left Text
Unicode bidirectional text rendering for Arabic, Hebrew etc.

**Effort:** Very High — requires UAX #9 bidi algorithm
**Usage:** Important for i18n but extremely complex

---

### 14. DECLRMM — Left/Right Margin Mode
- `CSI ? 69 h` — Enable left/right margins
- `CSI Pl ; Pr s` — Set left/right margins (DECSLRM, conflicts with SCOSC)

Allows horizontal scroll regions. Very few apps use this.

**Effort:** High — affects all cursor movement and scroll operations
**Usage:** Rare

---

## Checklist

- [x] OSC 104/110/111/112 (color reset)
- [x] DECSTR (soft reset, CSI ! p)
- [x] ICH (insert characters, CSI @)
- [x] DCH (delete characters, CSI P)
- [x] DECRQM standard modes (CSI $ p)
- [x] CSI t (window manipulation + title push/pop)
- [x] REP (repeat character, CSI b)
- [x] SU/SD (scroll up/down, CSI S/T)
- [x] VPA origin mode check
- [x] DECSCA / SPA / EPA (protected attributes)
- [x] DECDWL / DECDHL (double width/height)
- [x] DECBI / DECFI (back/forward index)
- [x] BiDi / RTL text (Core Text based bidi reordering)
- [x] DECLRMM (left/right margins)
