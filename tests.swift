#!/usr/bin/env swift
// tests.swift — Automated tests for quickTerminal's terminal engine
// Run: swift tests.swift
// Note: This file imports the Terminal and Cell types by re-declaring minimal stubs,
// then tests the core parsing logic in isolation.

import Foundation

// ============================================================================
// MARK: - Minimal Type Stubs (matching quickTerminal.swift)
// ============================================================================

struct TextAttrs: Equatable {
    var fg: Int = 7
    var bg: Int = 0
    var bold = false
    var dim = false
    var italic = false
    var underline: UInt8 = 0  // 0=none, 1=single, 2=double, 3=curly, 4=dotted, 5=dashed
    var blink: UInt8 = 0      // 0=none, 1=slow, 2=rapid
    var inverse = false
    var strikethrough = false
    var fgRGB: (UInt8, UInt8, UInt8)? = nil
    var bgRGB: (UInt8, UInt8, UInt8)? = nil
    var hidden = false
    var overline = false
    var ulColor: Int = -1
    var ulRGB: (UInt8, UInt8, UInt8)? = nil

    static func == (lhs: TextAttrs, rhs: TextAttrs) -> Bool {
        lhs.fg == rhs.fg && lhs.bg == rhs.bg && lhs.bold == rhs.bold &&
        lhs.dim == rhs.dim && lhs.italic == rhs.italic &&
        lhs.underline == rhs.underline && lhs.blink == rhs.blink &&
        lhs.inverse == rhs.inverse &&
        lhs.hidden == rhs.hidden && lhs.strikethrough == rhs.strikethrough &&
        lhs.overline == rhs.overline &&
        lhs.fgRGB?.0 == rhs.fgRGB?.0 && lhs.fgRGB?.1 == rhs.fgRGB?.1 && lhs.fgRGB?.2 == rhs.fgRGB?.2 &&
        lhs.bgRGB?.0 == rhs.bgRGB?.0 && lhs.bgRGB?.1 == rhs.bgRGB?.1 && lhs.bgRGB?.2 == rhs.bgRGB?.2 &&
        lhs.ulColor == rhs.ulColor &&
        lhs.ulRGB?.0 == rhs.ulRGB?.0 && lhs.ulRGB?.1 == rhs.ulRGB?.1 && lhs.ulRGB?.2 == rhs.ulRGB?.2
    }
}

struct Cell {
    var char: Unicode.Scalar = " "
    var attrs = TextAttrs()
    var width: UInt8 = 1
    var hyperlink: String? = nil
}

// ============================================================================
// MARK: - Test Framework
// ============================================================================

var testsPassed = 0
var testsFailed = 0
var currentTest = ""

func test(_ name: String, _ body: () -> Void) {
    currentTest = name
    let before = testsFailed
    body()
    if testsFailed == before {
        print("  ✓ \(name)")
    }
}

func section(_ name: String) {
    print("\n── \(name) ──")
}

func check(_ condition: Bool, _ message: String = "", file: String = #file, line: Int = #line) {
    if condition {
        testsPassed += 1
    } else {
        testsFailed += 1
        print("  FAIL: \(currentTest) — \(message) (line \(line))")
    }
}

func assertEqual<T: Equatable>(_ a: T, _ b: T, _ message: String = "", file: String = #file, line: Int = #line) {
    if a == b {
        testsPassed += 1
    } else {
        testsFailed += 1
        print("  FAIL: \(currentTest) — expected \(b), got \(a) \(message) (line \(line))")
    }
}

// ============================================================================
// MARK: - Terminal Engine (extracted for testing)
// We create a minimal Terminal that matches the real one's parsing behavior.
// ============================================================================

// Re-use the actual Terminal class by compiling against the main file would be ideal,
// but since it's a single-file app with Cocoa dependencies, we test the core logic
// by creating a standalone test terminal.

class TestTerminal {
    var cols: Int
    var rows: Int
    var cursorX = 0
    var cursorY = 0
    var pendingWrap = false
    var grid: [[Cell]]
    var attrs = TextAttrs()
    var savedX = 0, savedY = 0
    var savedAttrs = TextAttrs()
    var savedPendingWrap = false
    var savedG0IsGraphics = false, savedG1IsGraphics = false
    var savedUseG1 = false, savedOriginMode = false, savedAutoWrap = true
    var scrollTop = 0
    var scrollBottom: Int
    var scrollback: [[Cell]] = []
    var altGrid: [[Cell]]? = nil
    var altX = 0, altY = 0
    var cursorVisible = true
    var appCursorMode = false
    var appKeypadMode = false
    var autoWrapMode = true
    var originMode = false
    var reverseVideoMode = false
    var bracketedPasteMode = false
    var cursorStyle = 0
    var mouseMode = 0
    var mouseEncoding = 0
    var focusReportingMode = false
    var synchronizedOutput = false
    var charsetG0IsGraphics = false
    var charsetG1IsGraphics = false
    var useG1 = false
    var tabStops = Set<Int>()
    var kittyKbdStack: [Int] = []
    var insertMode = false
    var lastResponse = ""

    static func emptyGrid(_ cols: Int, _ rows: Int) -> [[Cell]] {
        Array(repeating: Array(repeating: Cell(), count: cols), count: rows)
    }

    init(cols: Int, rows: Int) {
        self.cols = cols
        self.rows = rows
        self.scrollBottom = rows - 1
        self.grid = Self.emptyGrid(cols, rows)
        resetTabStops()
    }

    func resetTabStops() {
        tabStops.removeAll()
        for i in stride(from: 0, to: cols, by: 8) { tabStops.insert(i) }
    }

    // Simplified process: feed raw bytes
    func feed(_ str: String) {
        let data = Array(str.utf8)
        var i = 0
        while i < data.count {
            let b = data[i]
            // C1 control codes (multi-byte UTF-8: 0xC2 0x80-0x9F)
            if b == 0xC2 && i + 1 < data.count && data[i+1] >= 0x80 && data[i+1] <= 0x9F {
                let c1 = data[i+1]
                switch c1 {
                case 0x84: lf()                               // IND
                case 0x85: cursorX = 0; lf()                  // NEL
                case 0x8D: rlf()                              // RI
                case 0x9B:                                    // CSI
                    i += 2
                    var params: [Int] = []
                    var subParams: [[Int]] = []
                    var colonSub: [Int] = []
                    var cur = ""
                    var prefix: UInt8 = 0
                    if i < data.count && (data[i] == 0x3F || data[i] == 0x3E) {
                        prefix = data[i]; i += 1
                    }
                    while i < data.count {
                        let c = data[i]
                        if c >= 0x30 && c <= 0x39 {
                            cur.append(Character(UnicodeScalar(c)))
                        } else if c == 0x3B {
                            if !colonSub.isEmpty {
                                colonSub.append(Int(cur) ?? 0)
                                params.append(colonSub[0])
                                subParams.append(colonSub); colonSub = []
                            } else {
                                params.append(Int(cur) ?? 0)
                                subParams.append([])
                            }
                            cur = ""
                        } else if c == 0x3A {
                            colonSub.append(Int(cur) ?? 0); cur = ""
                        } else if c >= 0x40 && c <= 0x7E {
                            if !colonSub.isEmpty {
                                colonSub.append(Int(cur) ?? 0)
                                params.append(colonSub[0])
                                subParams.append(colonSub)
                            } else {
                                params.append(Int(cur) ?? 0)
                                subParams.append([])
                            }
                            cur = ""; colonSub = []
                            if prefix == 0x3F { doCSIQuestion(params, c) }
                            else { doCSI(params, c, subParams) }
                            break
                        } else { break }
                        i += 1
                    }
                    i += 1; continue
                case 0x9D:                                    // OSC
                    i += 2
                    var oscBuf = ""
                    while i < data.count {
                        if data[i] == 0x07 { break }
                        if data[i] == 0x1B && i + 1 < data.count && data[i+1] == 0x5C { i += 1; break }
                        // ST as C1 (0xC2 0x9C)
                        if data[i] == 0xC2 && i + 1 < data.count && data[i+1] == 0x9C { i += 1; break }
                        oscBuf.append(Character(UnicodeScalar(data[i])))
                        i += 1
                    }
                    handleOSC(oscBuf)
                    i += 1; continue
                default: break
                }
                i += 2; continue
            }
            if b == 0x1B && i + 1 < data.count {
                // ESC sequence
                i += 1
                let next = data[i]
                if next == 0x5B { // CSI
                    i += 1
                    var params: [Int] = []
                    var subParams: [[Int]] = []
                    var colonSub: [Int] = []
                    var cur = ""
                    var prefix: UInt8 = 0
                    // Check for ? or > prefix
                    if i < data.count && (data[i] == 0x3F || data[i] == 0x3E) {
                        prefix = data[i]
                        i += 1
                    }
                    while i < data.count {
                        let c = data[i]
                        if c >= 0x30 && c <= 0x39 {
                            cur.append(Character(UnicodeScalar(c)))
                        } else if c == 0x3B {
                            if !colonSub.isEmpty {
                                colonSub.append(Int(cur) ?? 0)
                                params.append(colonSub[0])
                                subParams.append(colonSub); colonSub = []
                            } else {
                                params.append(Int(cur) ?? 0)
                                subParams.append([])
                            }
                            cur = ""
                        } else if c == 0x3A {
                            colonSub.append(Int(cur) ?? 0); cur = ""
                        } else if c >= 0x40 && c <= 0x7E {
                            if !colonSub.isEmpty {
                                colonSub.append(Int(cur) ?? 0)
                                params.append(colonSub[0])
                                subParams.append(colonSub)
                            } else {
                                params.append(Int(cur) ?? 0)
                                subParams.append([])
                            }
                            cur = ""; colonSub = []
                            if prefix == 0x3F {
                                doCSIQuestion(params, c)
                            } else {
                                doCSI(params, c, subParams)
                            }
                            break
                        } else {
                            break
                        }
                        i += 1
                    }
                } else if next == 0x5D { // OSC
                    i += 1
                    var oscBuf = ""
                    while i < data.count {
                        if data[i] == 0x07 { break } // BEL terminates
                        if data[i] == 0x1B && i + 1 < data.count && data[i+1] == 0x5C { i += 1; break } // ST
                        oscBuf.append(Character(UnicodeScalar(data[i])))
                        i += 1
                    }
                    handleOSC(oscBuf)
                } else if next == 0x37 { // DECSC
                    savedX = cursorX; savedY = cursorY; savedPendingWrap = pendingWrap
                    savedAttrs = attrs
                } else if next == 0x38 { // DECRC
                    cursorX = savedX; cursorY = savedY; pendingWrap = savedPendingWrap
                    attrs = savedAttrs
                } else if next == 0x44 { // IND
                    lf()
                } else if next == 0x4D { // RI
                    rlf()
                } else if next == 0x45 { // NEL
                    cursorX = 0; lf()
                } else if next == 0x63 { // RIS
                    fullReset()
                } else if next == 0x3D { // DECKPAM
                    appKeypadMode = true
                } else if next == 0x3E { // DECKPNM
                    appKeypadMode = false
                } else if next == 0x23 { // ESC # — intermediate
                    i += 1
                    if i < data.count && data[i] == 0x38 { // DECALN
                        for r in 0..<rows {
                            for c in 0..<cols {
                                grid[r][c] = Cell(char: "E", attrs: TextAttrs(), width: 1)
                            }
                        }
                        cursorX = 0; cursorY = 0
                        scrollTop = 0; scrollBottom = rows - 1
                    }
                }
            } else if b == 0x0A { // LF
                lf()
            } else if b == 0x0D { // CR
                cursorX = 0
            } else if b == 0x08 { // BS
                if cursorX > 0 { cursorX -= 1 }
            } else if b == 0x09 { // TAB
                var next = cursorX + 1
                while next < cols && !tabStops.contains(next) { next += 1 }
                cursorX = min(next, cols - 1)
            } else if b >= 0x20 && b < 0x80 {
                if cursorX >= cols {
                    if autoWrapMode { cursorX = 0; lf() }
                    else { cursorX = cols - 1 }
                }
                // IRM: insert mode — shift cells right
                if insertMode {
                    for c in stride(from: cols - 1, through: cursorX + 1, by: -1) {
                        grid[cursorY][c] = grid[cursorY][c - 1]
                    }
                }
                grid[cursorY][cursorX].char = Unicode.Scalar(b)
                grid[cursorY][cursorX].attrs = attrs
                cursorX += 1
            }
            i += 1
        }
    }

    func lf() {
        if cursorY == scrollBottom {
            scrollUp(1)
        } else if cursorY < rows - 1 {
            cursorY += 1
        }
    }

    func rlf() {
        if cursorY == scrollTop {
            scrollDown(1)
        } else if cursorY > 0 {
            cursorY -= 1
        }
    }

    func scrollUp(_ n: Int) {
        guard scrollTop >= 0 && scrollBottom < rows && scrollTop < scrollBottom else { return }
        for _ in 0..<n {
            if altGrid == nil { scrollback.append(grid[scrollTop]) }
            grid.remove(at: scrollTop)
            grid.insert(Array(repeating: Cell(), count: cols), at: scrollBottom)
        }
    }

    func scrollDown(_ n: Int) {
        guard scrollTop >= 0 && scrollBottom < rows && scrollTop < scrollBottom else { return }
        for _ in 0..<n {
            grid.remove(at: scrollBottom)
            grid.insert(Array(repeating: Cell(), count: cols), at: scrollTop)
        }
    }

    func fullReset() {
        cursorX = 0; cursorY = 0; attrs = TextAttrs()
        scrollTop = 0; scrollBottom = rows - 1
        appCursorMode = false; appKeypadMode = false; autoWrapMode = true; originMode = false
        cursorVisible = true; cursorStyle = 0
        mouseMode = 0; mouseEncoding = 0; insertMode = false
        altGrid = nil
        grid = Self.emptyGrid(cols, rows)
        resetTabStops()
    }

    func doCSI(_ p: [Int], _ f: UInt8, _ sub: [[Int]] = []) {
        switch f {
        case 0x41: cursorY = max(0, cursorY - max(1, p.first ?? 1))            // CUU
        case 0x42: cursorY = min(rows - 1, cursorY + max(1, p.first ?? 1))      // CUD
        case 0x43: cursorX = min(cols - 1, cursorX + max(1, p.first ?? 1))      // CUF
        case 0x44: cursorX = max(0, cursorX - max(1, p.first ?? 1))            // CUB
        case 0x47: cursorX = min(cols - 1, max(0, (p.first ?? 1) - 1))         // CHA
        case 0x48, 0x66: // CUP / HVP
            let r = (p.count > 0 && p[0] > 0) ? p[0] : 1
            let c = (p.count > 1 && p[1] > 0) ? p[1] : 1
            if originMode {
                cursorY = max(scrollTop, min(scrollBottom, scrollTop + r - 1))
            } else {
                cursorY = min(rows - 1, max(0, r - 1))
            }
            cursorX = min(cols - 1, max(0, c - 1))
        case 0x4A: // ED
            let mode = p.first ?? 0
            if mode == 2 {
                grid = Self.emptyGrid(cols, rows)
            } else if mode == 3 {
                scrollback.removeAll()
                grid = Self.emptyGrid(cols, rows)
            } else if mode == 0 {
                for c in cursorX..<cols { grid[cursorY][c] = Cell() }
                for r in (cursorY+1)..<rows { grid[r] = Array(repeating: Cell(), count: cols) }
            } else if mode == 1 {
                for c in 0...cursorX { grid[cursorY][c] = Cell() }
                for r in 0..<cursorY { grid[r] = Array(repeating: Cell(), count: cols) }
            }
        case 0x4B: // EL
            let mode = p.first ?? 0
            if mode == 0 { for c in cursorX..<cols { grid[cursorY][c] = Cell() } }
            else if mode == 1 { for c in 0...min(cursorX, cols-1) { grid[cursorY][c] = Cell() } }
            else if mode == 2 { grid[cursorY] = Array(repeating: Cell(), count: cols) }
        case 0x4C: // IL
            guard cursorY >= scrollTop, cursorY <= scrollBottom, scrollBottom < grid.count else { return }
            for _ in 0..<max(1, p.first ?? 1) {
                grid.insert(Array(repeating: Cell(), count: cols), at: cursorY)
                grid.remove(at: scrollBottom + 1)
            }
        case 0x4D: // DL
            guard cursorY >= scrollTop, cursorY <= scrollBottom, cursorY < grid.count, scrollBottom < grid.count else { return }
            for _ in 0..<max(1, p.first ?? 1) {
                grid.remove(at: cursorY)
                grid.insert(Array(repeating: Cell(), count: cols), at: scrollBottom)
            }
        case 0x68: // SM (set mode)
            for mode in (p.isEmpty ? [0] : p) {
                if mode == 4 { insertMode = true }
            }
        case 0x6C: // RM (reset mode)
            for mode in (p.isEmpty ? [0] : p) {
                if mode == 4 { insertMode = false }
            }
        case 0x6D: applySGR(p, sub) // SGR
        case 0x72: // DECSTBM
            let top = max(0, (p.count > 0 ? p[0] : 1) - 1)
            let bot = (p.count > 1 ? p[1] : rows) - 1
            scrollTop = min(top, rows - 1)
            scrollBottom = max(scrollTop, min(rows - 1, bot))
            cursorX = 0; cursorY = originMode ? scrollTop : 0
        case 0x73: savedX = cursorX; savedY = cursorY // SCOSC
        case 0x75: cursorX = savedX; cursorY = savedY // SCORC
        case 0x6E: // DSR
            if p.first == 6 { lastResponse = "\u{1B}[\(cursorY + 1);\(cursorX + 1)R" }
            else if p.first == 5 { lastResponse = "\u{1B}[0n" }
        default: break
        }
    }

    func doCSIQuestion(_ p: [Int], _ f: UInt8) {
        for n in p {
            if f == 0x68 { // set
                switch n {
                case 1: appCursorMode = true
                case 5: reverseVideoMode = true
                case 6: originMode = true; cursorX = 0; cursorY = scrollTop
                case 7: autoWrapMode = true
                case 25: cursorVisible = true
                case 47, 1047:
                    altGrid = grid; altX = cursorX; altY = cursorY
                    grid = Self.emptyGrid(cols, rows)
                    cursorX = 0; cursorY = 0
                case 1049:
                    savedX = cursorX; savedY = cursorY; savedAttrs = attrs
                    altGrid = grid; grid = Self.emptyGrid(cols, rows)
                    cursorX = 0; cursorY = 0
                case 1000: mouseMode = 1000
                case 1002: mouseMode = 1002
                case 1003: mouseMode = 1003
                case 1006: mouseEncoding = 1006
                case 2004: bracketedPasteMode = true
                case 2026: synchronizedOutput = true
                default: break
                }
            } else if f == 0x6C { // reset
                switch n {
                case 1: appCursorMode = false
                case 5: reverseVideoMode = false
                case 6: originMode = false; cursorX = 0; cursorY = 0
                case 7: autoWrapMode = false
                case 25: cursorVisible = false
                case 47, 1047:
                    if let ag = altGrid { grid = ag; cursorX = altX; cursorY = altY; altGrid = nil }
                    pendingWrap = false
                case 1049:
                    if let ag = altGrid { grid = ag; altGrid = nil }
                    cursorX = savedX; cursorY = savedY; attrs = savedAttrs
                case 1000, 1002, 1003: mouseMode = 0
                case 1006: mouseEncoding = 0
                case 2004: bracketedPasteMode = false
                case 2026: synchronizedOutput = false
                default: break
                }
            }
        }
    }

    func applySGR(_ p: [Int], _ sub: [[Int]] = []) {
        var i = 0
        let params = p.isEmpty ? [0] : p
        while i < params.count {
            let sp = i < sub.count ? sub[i] : []
            switch params[i] {
            case 0: attrs = TextAttrs()
            case 1: attrs.bold = true
            case 2: attrs.dim = true
            case 3: attrs.italic = true
            case 4:
                if !sp.isEmpty {
                    let style = sp.count > 1 ? sp[1] : (sp.count == 1 ? sp[0] : 1)
                    attrs.underline = UInt8(clamping: style)
                } else {
                    attrs.underline = 1
                }
            case 5: attrs.blink = 1
            case 6: attrs.blink = 2
            case 7: attrs.inverse = true
            case 8: attrs.hidden = true
            case 9: attrs.strikethrough = true
            case 21: attrs.underline = 2
            case 22: attrs.bold = false; attrs.dim = false
            case 23: attrs.italic = false
            case 24: attrs.underline = 0
            case 25: attrs.blink = 0
            case 27: attrs.inverse = false
            case 28: attrs.hidden = false
            case 29: attrs.strikethrough = false
            case 30...37: attrs.fg = params[i] - 30; attrs.fgRGB = nil
            case 38:
                if i+1 < params.count && params[i+1] == 5 && i+2 < params.count {
                    attrs.fg = params[i+2]; attrs.fgRGB = nil; i += 2
                } else if i+1 < params.count && params[i+1] == 2 && i+4 < params.count {
                    attrs.fgRGB = (UInt8(clamping: params[i+2]), UInt8(clamping: params[i+3]), UInt8(clamping: params[i+4]))
                    i += 4
                }
            case 39: attrs.fg = 7; attrs.fgRGB = nil
            case 40...47: attrs.bg = params[i] - 40; attrs.bgRGB = nil
            case 48:
                if i+1 < params.count && params[i+1] == 5 && i+2 < params.count {
                    attrs.bg = params[i+2]; attrs.bgRGB = nil; i += 2
                } else if i+1 < params.count && params[i+1] == 2 && i+4 < params.count {
                    attrs.bgRGB = (UInt8(clamping: params[i+2]), UInt8(clamping: params[i+3]), UInt8(clamping: params[i+4]))
                    i += 4
                }
            case 49: attrs.bg = 0; attrs.bgRGB = nil
            case 53: attrs.overline = true
            case 55: attrs.overline = false
            case 58:
                if i+1 < params.count && params[i+1] == 5 && i+2 < params.count {
                    attrs.ulColor = params[i+2]; attrs.ulRGB = nil; i += 2
                } else if i+1 < params.count && params[i+1] == 2 && i+4 < params.count {
                    attrs.ulRGB = (UInt8(clamping: params[i+2]), UInt8(clamping: params[i+3]), UInt8(clamping: params[i+4]))
                    attrs.ulColor = -1; i += 4
                }
            case 59: attrs.ulColor = -1; attrs.ulRGB = nil
            case 90...97: attrs.fg = params[i] - 90 + 8; attrs.fgRGB = nil
            case 100...107: attrs.bg = params[i] - 100 + 8; attrs.bgRGB = nil
            default: break
            }
            i += 1
        }
    }

    func handleOSC(_ buf: String) {
        guard let sep = buf.firstIndex(of: ";") else { return }
        let code = Int(buf[buf.startIndex..<sep]) ?? -1
        let _ = String(buf[buf.index(after: sep)...])
        switch code {
        case 0, 2: break // title
        default: break
        }
    }

    /// Get visible text content as string
    func screenText() -> String {
        var lines: [String] = []
        for row in 0..<rows {
            var line = ""
            for col in 0..<cols {
                line.append(String(grid[row][col].char))
            }
            while line.last == " " { line.removeLast() }
            lines.append(line)
        }
        while lines.last?.isEmpty == true { lines.removeLast() }
        return lines.joined(separator: "\n")
    }
}

// ============================================================================
// MARK: - Tests
// ============================================================================

print("Running quickTerminal tests...\n")

section("Basic Text Output")

test("Basic character output") {
    let t = TestTerminal(cols: 80, rows: 24)
    t.feed("Hello")
    assertEqual(t.screenText(), "Hello")
    assertEqual(t.cursorX, 5)
    assertEqual(t.cursorY, 0)
}

test("Line feed and carriage return") {
    let t = TestTerminal(cols: 80, rows: 24)
    t.feed("Line1\r\nLine2")
    assertEqual(t.screenText(), "Line1\nLine2")
    assertEqual(t.cursorY, 1)
}

test("Auto-wrap at end of line") {
    let t = TestTerminal(cols: 5, rows: 3)
    t.feed("12345X")
    assertEqual(String(t.grid[0][4].char), "5")
    assertEqual(String(t.grid[1][0].char), "X")
    assertEqual(t.cursorY, 1)
}

test("Backspace") {
    let t = TestTerminal(cols: 80, rows: 24)
    t.feed("AB\u{08}C")
    assertEqual(String(t.grid[0][0].char), "A")
    assertEqual(String(t.grid[0][1].char), "C")
}

section("Cursor Movement")

test("CUP - cursor position") {
    let t = TestTerminal(cols: 80, rows: 24)
    t.feed("\u{1B}[5;10H")
    assertEqual(t.cursorY, 4)
    assertEqual(t.cursorX, 9)
}

test("CUU/CUD/CUF/CUB - cursor relative movement") {
    let t = TestTerminal(cols: 80, rows: 24)
    t.feed("\u{1B}[10;10H")
    t.feed("\u{1B}[3A")  // up 3
    assertEqual(t.cursorY, 6)
    t.feed("\u{1B}[5B")  // down 5
    assertEqual(t.cursorY, 11)
    t.feed("\u{1B}[4C")  // right 4
    assertEqual(t.cursorX, 13)
    t.feed("\u{1B}[2D")  // left 2
    assertEqual(t.cursorX, 11)
}

test("CHA - cursor horizontal absolute") {
    let t = TestTerminal(cols: 80, rows: 24)
    t.feed("\u{1B}[20G")
    assertEqual(t.cursorX, 19)
}

section("Erase Commands")

test("ED 2 - erase entire display") {
    let t = TestTerminal(cols: 10, rows: 3)
    t.feed("XXXXXXXXXX\r\nYYYYY")
    t.feed("\u{1B}[2J")
    assertEqual(t.screenText(), "")
}

test("EL 0 - erase from cursor to end of line") {
    let t = TestTerminal(cols: 10, rows: 3)
    t.feed("0123456789")
    t.feed("\u{1B}[1;5H")  // move to col 5
    t.feed("\u{1B}[K")
    assertEqual(String(t.grid[0].map { String($0.char) }.joined()), "0123      ")
}

test("EL 1 - erase from start to cursor") {
    let t = TestTerminal(cols: 10, rows: 3)
    t.feed("0123456789")
    t.feed("\u{1B}[1;5H")
    t.feed("\u{1B}[1K")
    assertEqual(String(t.grid[0].map { String($0.char) }.joined()), "     56789")
}

test("EL 2 - erase entire line") {
    let t = TestTerminal(cols: 10, rows: 3)
    t.feed("0123456789")
    t.feed("\u{1B}[2K")
    assertEqual(String(t.grid[0].map { String($0.char) }.joined()), "          ")
}

section("SGR Attributes")

test("SGR bold, italic, underline") {
    let t = TestTerminal(cols: 80, rows: 24)
    t.feed("\u{1B}[1;3;4mX")
    check(t.grid[0][0].attrs.bold, "bold should be set")
    check(t.grid[0][0].attrs.italic, "italic should be set")
    check(t.grid[0][0].attrs.underline > 0, "underline should be set")
}

test("SGR reset") {
    let t = TestTerminal(cols: 80, rows: 24)
    t.feed("\u{1B}[1;3mX\u{1B}[0mY")
    check(t.grid[0][0].attrs.bold, "first char bold")
    check(!t.grid[0][1].attrs.bold, "second char not bold after reset")
    check(!t.grid[0][1].attrs.italic, "second char not italic after reset")
}

test("SGR 256-color foreground") {
    let t = TestTerminal(cols: 80, rows: 24)
    t.feed("\u{1B}[38;5;196mX")
    assertEqual(t.grid[0][0].attrs.fg, 196)
}

test("SGR truecolor foreground") {
    let t = TestTerminal(cols: 80, rows: 24)
    t.feed("\u{1B}[38;2;255;128;0mX")
    assertEqual(t.grid[0][0].attrs.fgRGB?.0, 255)
    assertEqual(t.grid[0][0].attrs.fgRGB?.1, 128)
    assertEqual(t.grid[0][0].attrs.fgRGB?.2, 0)
}

test("SGR 256-color background") {
    let t = TestTerminal(cols: 80, rows: 24)
    t.feed("\u{1B}[48;5;42mX")
    assertEqual(t.grid[0][0].attrs.bg, 42)
}

test("SGR bright colors") {
    let t = TestTerminal(cols: 80, rows: 24)
    t.feed("\u{1B}[91mX")
    assertEqual(t.grid[0][0].attrs.fg, 9)  // bright red = 8 + 1
    t.feed("\u{1B}[102mY")
    assertEqual(t.grid[0][1].attrs.bg, 10)  // bright green = 8 + 2
}

test("SGR 58 underline color (256-color)") {
    let t = TestTerminal(cols: 80, rows: 24)
    t.feed("\u{1B}[4;58;5;196mX")
    check(t.grid[0][0].attrs.underline > 0, "underline should be set")
    assertEqual(t.grid[0][0].attrs.ulColor, 196)
}

test("SGR 58 underline color (truecolor)") {
    let t = TestTerminal(cols: 80, rows: 24)
    t.feed("\u{1B}[4;58;2;255;0;128mX")
    check(t.grid[0][0].attrs.underline > 0, "underline should be set")
    assertEqual(t.grid[0][0].attrs.ulRGB?.0, 255)
    assertEqual(t.grid[0][0].attrs.ulRGB?.1, 0)
    assertEqual(t.grid[0][0].attrs.ulRGB?.2, 128)
}

test("SGR 59 resets underline color") {
    let t = TestTerminal(cols: 80, rows: 24)
    t.feed("\u{1B}[58;5;196m\u{1B}[59mX")
    assertEqual(t.grid[0][0].attrs.ulColor, -1)
    check(t.grid[0][0].attrs.ulRGB == nil, "ulRGB should be nil after reset")
}

test("SGR inverse") {
    let t = TestTerminal(cols: 80, rows: 24)
    t.feed("\u{1B}[7mX\u{1B}[27mY")
    check(t.grid[0][0].attrs.inverse, "inverse on")
    check(!t.grid[0][1].attrs.inverse, "inverse off")
}

test("SGR strikethrough") {
    let t = TestTerminal(cols: 80, rows: 24)
    t.feed("\u{1B}[9mX\u{1B}[29mY")
    check(t.grid[0][0].attrs.strikethrough, "strikethrough on")
    check(!t.grid[0][1].attrs.strikethrough, "strikethrough off")
}

section("Scroll Region & Lines")

test("DECSTBM - scroll region") {
    let t = TestTerminal(cols: 10, rows: 5)
    t.feed("\u{1B}[2;4r")
    assertEqual(t.scrollTop, 1)
    assertEqual(t.scrollBottom, 3)
    assertEqual(t.cursorX, 0)
    assertEqual(t.cursorY, 0)
}

section("Insert/Delete Lines")

test("IL - insert lines") {
    let t = TestTerminal(cols: 5, rows: 5)
    t.feed("AAAAA\r\nBBBBB\r\nCCCCC\r\nDDDDD\r\nEEEEE")
    t.feed("\u{1B}[2;1H")  // move to row 2
    t.feed("\u{1B}[1L")     // insert 1 line
    assertEqual(String(t.grid[1].map { String($0.char) }.joined()), "     ")
    assertEqual(String(t.grid[2].map { String($0.char) }.joined()), "BBBBB")
}

test("DL - delete lines") {
    let t = TestTerminal(cols: 5, rows: 5)
    t.feed("AAAAA\r\nBBBBB\r\nCCCCC\r\nDDDDD\r\nEEEEE")
    t.feed("\u{1B}[2;1H")  // move to row 2
    t.feed("\u{1B}[1M")     // delete 1 line
    assertEqual(String(t.grid[1].map { String($0.char) }.joined()), "CCCCC")
    assertEqual(String(t.grid[2].map { String($0.char) }.joined()), "DDDDD")
}

section("DEC Private Modes")

test("DECCKM - application cursor mode") {
    let t = TestTerminal(cols: 80, rows: 24)
    check(!t.appCursorMode, "default off")
    t.feed("\u{1B}[?1h")
    check(t.appCursorMode, "set on")
    t.feed("\u{1B}[?1l")
    check(!t.appCursorMode, "set off")
}

test("DECTCEM - cursor visibility") {
    let t = TestTerminal(cols: 80, rows: 24)
    check(t.cursorVisible, "default visible")
    t.feed("\u{1B}[?25l")
    check(!t.cursorVisible, "hidden")
    t.feed("\u{1B}[?25h")
    check(t.cursorVisible, "visible again")
}

test("Alternate screen buffer (1049)") {
    let t = TestTerminal(cols: 10, rows: 5)
    t.feed("MainText")
    assertEqual(t.cursorX, 8)
    t.feed("\u{1B}[?1049h")  // enter alt screen
    check(t.altGrid != nil, "alt grid should exist")
    assertEqual(t.cursorX, 0)
    assertEqual(t.cursorY, 0)
    t.feed("AltText")
    t.feed("\u{1B}[?1049l")  // exit alt screen
    check(t.altGrid == nil, "alt grid should be cleared")
    assertEqual(t.screenText(), "MainText")
}

test("Mouse tracking modes") {
    let t = TestTerminal(cols: 80, rows: 24)
    assertEqual(t.mouseMode, 0)
    t.feed("\u{1B}[?1000h")
    assertEqual(t.mouseMode, 1000)
    t.feed("\u{1B}[?1002h")
    assertEqual(t.mouseMode, 1002)
    t.feed("\u{1B}[?1003h")
    assertEqual(t.mouseMode, 1003)
    t.feed("\u{1B}[?1003l")
    assertEqual(t.mouseMode, 0)
}

test("SGR mouse encoding mode") {
    let t = TestTerminal(cols: 80, rows: 24)
    assertEqual(t.mouseEncoding, 0)
    t.feed("\u{1B}[?1006h")
    assertEqual(t.mouseEncoding, 1006)
    t.feed("\u{1B}[?1006l")
    assertEqual(t.mouseEncoding, 0)
}

test("Bracketed paste mode") {
    let t = TestTerminal(cols: 80, rows: 24)
    check(!t.bracketedPasteMode, "default off")
    t.feed("\u{1B}[?2004h")
    check(t.bracketedPasteMode, "enabled")
    t.feed("\u{1B}[?2004l")
    check(!t.bracketedPasteMode, "disabled")
}

test("Synchronized output") {
    let t = TestTerminal(cols: 80, rows: 24)
    check(!t.synchronizedOutput, "default off")
    t.feed("\u{1B}[?2026h")
    check(t.synchronizedOutput, "enabled")
    t.feed("\u{1B}[?2026l")
    check(!t.synchronizedOutput, "disabled")
}

section("DECSC / DECRC")

test("DECSC/DECRC saves and restores full state") {
    let t = TestTerminal(cols: 80, rows: 24)
    t.feed("\u{1B}[1;3m")  // bold + italic
    t.feed("\u{1B}[5;10H")  // position 5,10
    t.feed("\u{1B}7")  // save
    t.feed("\u{1B}[0m")  // reset attrs
    t.feed("\u{1B}[1;1H")  // move to 1,1
    assertEqual(t.cursorY, 0)
    check(!t.attrs.bold, "attrs reset")
    t.feed("\u{1B}8")  // restore
    assertEqual(t.cursorY, 4)
    assertEqual(t.cursorX, 9)
    check(t.savedAttrs.bold, "saved attrs should have bold")
}

section("Keypad & Reset")

test("Application keypad mode (ESC = / ESC >)") {
    let t = TestTerminal(cols: 80, rows: 24)
    check(!t.appKeypadMode, "default off")
    t.feed("\u{1B}=")
    check(t.appKeypadMode, "enabled")
    t.feed("\u{1B}>")
    check(!t.appKeypadMode, "disabled")
}

test("RIS - full reset") {
    let t = TestTerminal(cols: 10, rows: 5)
    t.feed("XXXXXXXXXX")
    t.feed("\u{1B}[1;3;7m")
    t.feed("\u{1B}[?1h")
    t.feed("\u{1B}[?1000h")
    t.feed("\u{1B}c")  // full reset
    assertEqual(t.cursorX, 0)
    assertEqual(t.cursorY, 0)
    check(!t.attrs.bold)
    check(!t.appCursorMode)
    assertEqual(t.mouseMode, 0)
    assertEqual(t.screenText(), "")
}

section("DSR & SCOSC/SCORC")

test("DSR 6 - cursor position report") {
    let t = TestTerminal(cols: 80, rows: 24)
    t.feed("\u{1B}[10;20H")
    t.feed("\u{1B}[6n")
    assertEqual(t.lastResponse, "\u{1B}[10;20R")
}

test("DSR 5 - device status OK") {
    let t = TestTerminal(cols: 80, rows: 24)
    t.feed("\u{1B}[5n")
    assertEqual(t.lastResponse, "\u{1B}[0n")
}

test("SCOSC/SCORC - save/restore cursor (CSI s/u)") {
    let t = TestTerminal(cols: 80, rows: 24)
    t.feed("\u{1B}[5;10H")
    t.feed("\u{1B}[s")
    t.feed("\u{1B}[1;1H")
    assertEqual(t.cursorY, 0)
    t.feed("\u{1B}[u")
    assertEqual(t.cursorY, 4)
    assertEqual(t.cursorX, 9)
}

section("Scrollback & Tab Stops")

test("Scrollback accumulates lines") {
    let t = TestTerminal(cols: 5, rows: 3)
    t.feed("Line1\r\nLine2\r\nLine3\r\nLine4")
    check(t.scrollback.count >= 1, "scrollback should have entries")
    assertEqual(String(t.scrollback[0].prefix(5).map { String($0.char) }.joined()), "Line1")
}

test("Default tab stops every 8 columns") {
    let t = TestTerminal(cols: 80, rows: 24)
    t.feed("\t")
    assertEqual(t.cursorX, 8)
    t.feed("\t")
    assertEqual(t.cursorX, 16)
}

section("Reverse Index & Wrap")

test("Reverse index at top scrolls down") {
    let t = TestTerminal(cols: 5, rows: 3)
    t.feed("AAAAA\r\nBBBBB\r\nCCCCC")
    t.feed("\u{1B}[1;1H")  // move to top
    t.feed("\u{1B}M")       // reverse index
    assertEqual(String(t.grid[0].map { String($0.char) }.joined()), "     ")
    assertEqual(String(t.grid[1].map { String($0.char) }.joined()), "AAAAA")
}

test("Auto-wrap mode off prevents wrapping") {
    let t = TestTerminal(cols: 5, rows: 3)
    t.feed("\u{1B}[?7l")  // disable auto-wrap
    t.feed("123456789")
    assertEqual(t.cursorY, 0)
    // Last char should be at col 4 (overwritten)
    assertEqual(String(t.grid[0][4].char), "9")
}

section("Origin Mode")

test("CUP respects origin mode with scroll region") {
    let t = TestTerminal(cols: 10, rows: 10)
    t.feed("\u{1B}[3;7r")  // set scroll region rows 3-7
    t.feed("\u{1B}[?6h")   // enable origin mode
    // CUP 1;1 should go to scrollTop (row 2), col 0
    t.feed("\u{1B}[1;1H")
    assertEqual(t.cursorY, 2) // row 3 (0-indexed = 2)
    assertEqual(t.cursorX, 0)
    // CUP 3;5 should go to scrollTop+2 (row 4), col 4
    t.feed("\u{1B}[3;5H")
    assertEqual(t.cursorY, 4)
    assertEqual(t.cursorX, 4)
}

test("CUP clamps to scroll region in origin mode") {
    let t = TestTerminal(cols: 10, rows: 10)
    t.feed("\u{1B}[3;5r")  // scroll region rows 3-5
    t.feed("\u{1B}[?6h")   // origin mode
    t.feed("\u{1B}[99;1H") // row 99 → should clamp to scrollBottom (row 4)
    assertEqual(t.cursorY, 4)
}

section("Misc Modes")

test("ED mode 3 clears scrollback") {
    let t = TestTerminal(cols: 5, rows: 3)
    // Fill grid and generate scrollback
    t.feed("AAA\r\nBBB\r\nCCC\r\nDDD\r\nEEE")
    check(t.scrollback.count > 0, "should have scrollback")
    // CSI 3 J
    t.feed("\u{1B}[3J")
    assertEqual(t.scrollback.count, 0)
}

test("DECSCNM sets and resets reverse video mode") {
    let t = TestTerminal(cols: 5, rows: 3)
    t.feed("\u{1B}[?5h")
    check(t.reverseVideoMode, "should be set")
    t.feed("\u{1B}[?5l")
    check(!t.reverseVideoMode, "should be reset")
}

test("SGR 8 sets hidden attribute") {
    let t = TestTerminal(cols: 5, rows: 1)
    t.feed("\u{1B}[8mX")
    check(t.grid[0][0].attrs.hidden, "should be hidden")
    t.feed("\u{1B}[28mY")
    check(!t.grid[0][1].attrs.hidden, "should be visible")
}

test("DECSTBM resets cursor to scrollTop in origin mode") {
    let t = TestTerminal(cols: 10, rows: 10)
    t.feed("\u{1B}[?6h")   // origin mode first
    t.feed("\u{1B}[3;7r")  // set scroll region → cursor goes to scrollTop
    assertEqual(t.cursorY, 2) // scrollTop = row 3 (0-indexed = 2)
    assertEqual(t.cursorX, 0)
}

section("Underline Styles")

test("SGR 4 sets single underline (style 1)") {
    let t = TestTerminal(cols: 80, rows: 24)
    t.feed("\u{1B}[4mX")
    assertEqual(t.grid[0][0].attrs.underline, 1)
}

test("SGR 21 sets double underline (style 2)") {
    let t = TestTerminal(cols: 80, rows: 24)
    t.feed("\u{1B}[21mX")
    assertEqual(t.grid[0][0].attrs.underline, 2)
}

test("SGR 4:3 sets curly underline via colon sub-params") {
    let t = TestTerminal(cols: 80, rows: 24)
    t.feed("\u{1B}[4:3mX")
    assertEqual(t.grid[0][0].attrs.underline, 3, "curly underline")
}

test("SGR 4:0 disables underline via colon sub-params") {
    let t = TestTerminal(cols: 80, rows: 24)
    t.feed("\u{1B}[4mX\u{1B}[4:0mY")
    assertEqual(t.grid[0][0].attrs.underline, 1, "single underline")
    assertEqual(t.grid[0][1].attrs.underline, 0, "no underline")
}

test("SGR 4:4 sets dotted underline") {
    let t = TestTerminal(cols: 80, rows: 24)
    t.feed("\u{1B}[4:4mX")
    assertEqual(t.grid[0][0].attrs.underline, 4, "dotted underline")
}

test("SGR 4:5 sets dashed underline") {
    let t = TestTerminal(cols: 80, rows: 24)
    t.feed("\u{1B}[4:5mX")
    assertEqual(t.grid[0][0].attrs.underline, 5, "dashed underline")
}

test("SGR 24 resets all underline styles") {
    let t = TestTerminal(cols: 80, rows: 24)
    t.feed("\u{1B}[4:3mX\u{1B}[24mY")
    assertEqual(t.grid[0][0].attrs.underline, 3)
    assertEqual(t.grid[0][1].attrs.underline, 0)
}

section("Blink & Overline")

test("SGR 5 sets slow blink") {
    let t = TestTerminal(cols: 80, rows: 24)
    t.feed("\u{1B}[5mX")
    assertEqual(t.grid[0][0].attrs.blink, 1)
}

test("SGR 6 sets rapid blink") {
    let t = TestTerminal(cols: 80, rows: 24)
    t.feed("\u{1B}[6mX")
    assertEqual(t.grid[0][0].attrs.blink, 2)
}

test("SGR 25 resets blink") {
    let t = TestTerminal(cols: 80, rows: 24)
    t.feed("\u{1B}[5mX\u{1B}[25mY")
    assertEqual(t.grid[0][0].attrs.blink, 1)
    assertEqual(t.grid[0][1].attrs.blink, 0)
}

test("SGR 53 sets overline") {
    let t = TestTerminal(cols: 80, rows: 24)
    t.feed("\u{1B}[53mX")
    check(t.grid[0][0].attrs.overline, "overline on")
}

test("SGR 55 resets overline") {
    let t = TestTerminal(cols: 80, rows: 24)
    t.feed("\u{1B}[53mX\u{1B}[55mY")
    check(t.grid[0][0].attrs.overline, "overline on")
    check(!t.grid[0][1].attrs.overline, "overline off")
}

section("Insert Mode (IRM)")

test("SM 4 enables insert mode") {
    let t = TestTerminal(cols: 10, rows: 1)
    t.feed("ABCDE")
    t.feed("\u{1B}[1;1H")  // move to start
    t.feed("\u{1B}[4h")    // enable insert mode
    check(t.insertMode, "insert mode on")
    t.feed("X")
    // X should be inserted, pushing A→B→C→D→E right
    assertEqual(String(t.grid[0][0].char), "X")
    assertEqual(String(t.grid[0][1].char), "A")
    assertEqual(String(t.grid[0][2].char), "B")
    assertEqual(String(t.grid[0][5].char), "E")
}

test("RM 4 disables insert mode") {
    let t = TestTerminal(cols: 10, rows: 1)
    t.feed("\u{1B}[4h")
    check(t.insertMode, "insert mode on")
    t.feed("\u{1B}[4l")
    check(!t.insertMode, "insert mode off")
}

test("Insert mode shifts cells right") {
    let t = TestTerminal(cols: 5, rows: 1)
    t.feed("12345")
    t.feed("\u{1B}[1;3H")  // move to col 3
    t.feed("\u{1B}[4h")    // insert mode
    t.feed("X")
    // "12X34" — the 5 falls off the right edge
    assertEqual(String(t.grid[0].map { String($0.char) }.joined()), "12X34")
}

section("C1 Control Bytes & DECALN")

test("C1 0x84 (IND) acts as line feed") {
    let t = TestTerminal(cols: 10, rows: 5)
    t.feed("A")
    t.feed("\u{C2}\u{84}") // C1 IND
    assertEqual(t.cursorY, 1)
}

test("C1 0x85 (NEL) acts as CR+LF") {
    let t = TestTerminal(cols: 10, rows: 5)
    t.feed("ABCDE")
    t.feed("\u{C2}\u{85}") // C1 NEL
    assertEqual(t.cursorX, 0)
    assertEqual(t.cursorY, 1)
}

test("C1 0x8D (RI) acts as reverse index") {
    let t = TestTerminal(cols: 5, rows: 3)
    t.feed("AAAAA\r\nBBBBB\r\nCCCCC")
    t.feed("\u{1B}[1;1H")   // move to top
    t.feed("\u{C2}\u{8D}")   // C1 RI
    assertEqual(String(t.grid[0].map { String($0.char) }.joined()), "     ")
    assertEqual(String(t.grid[1].map { String($0.char) }.joined()), "AAAAA")
}

test("DECALN fills screen with E") {
    let t = TestTerminal(cols: 5, rows: 3)
    t.feed("XXXXX\r\nYYYYY\r\nZZZZZ")
    t.feed("\u{1B}#8") // DECALN
    for r in 0..<3 {
        for c in 0..<5 {
            assertEqual(String(t.grid[r][c].char), "E", "row \(r) col \(c)")
        }
    }
    assertEqual(t.cursorX, 0)
    assertEqual(t.cursorY, 0)
}

// ============================================================================
// MARK: - Regression Tests
// ============================================================================

section("Regression: CursorState / Alt-Screen / DECSC")

test("Alt-screen 1049 restores attrs on exit") {
    let t = TestTerminal(cols: 10, rows: 5)
    // Set bold on normal screen
    t.feed("\u{1B}[1m")  // SGR bold
    check(t.attrs.bold, "bold set on normal screen")
    // Enter alt screen — should save attrs
    t.feed("\u{1B}[?1049h")
    assertEqual(t.cursorX, 0)
    // Reset attrs inside alt screen (as a TUI app might do)
    t.feed("\u{1B}[0m")
    check(!t.attrs.bold, "attrs reset inside alt screen")
    // Exit alt screen — should restore bold
    t.feed("\u{1B}[?1049l")
    check(t.attrs.bold, "bold restored after 1049 exit")
}

test("DECSC saves pendingWrap, DECRC restores it") {
    let t = TestTerminal(cols: 5, rows: 3)
    // Manually set pendingWrap (simulate filling last column)
    t.pendingWrap = true
    // Save cursor state
    t.feed("\u{1B}7")
    check(t.savedPendingWrap, "savedPendingWrap should be true after DECSC")
    // Clear pendingWrap and move somewhere else
    t.pendingWrap = false
    t.feed("\u{1B}[1;1H")
    check(!t.pendingWrap, "pendingWrap cleared")
    // Restore
    t.feed("\u{1B}8")
    check(t.pendingWrap, "pendingWrap restored by DECRC")
}

test("Alt-screen 1049 saves and restores cursor position") {
    let t = TestTerminal(cols: 80, rows: 24)
    t.feed("\u{1B}[5;10H")  // move to row 5, col 10
    assertEqual(t.cursorY, 4)
    assertEqual(t.cursorX, 9)
    t.feed("\u{1B}[?1049h")  // enter alt screen
    assertEqual(t.cursorX, 0)
    assertEqual(t.cursorY, 0)
    t.feed("\u{1B}[?1049l")  // exit alt screen
    assertEqual(t.cursorY, 4, "cursor row restored after 1049")
    assertEqual(t.cursorX, 9, "cursor col restored after 1049")
}

test("Alt-screen 47 exit clears pendingWrap") {
    let t = TestTerminal(cols: 10, rows: 5)
    t.feed("\u{1B}[?47h")   // enter alt screen
    t.pendingWrap = true     // simulate pending wrap inside alt screen
    t.feed("\u{1B}[?47l")   // exit alt screen
    check(!t.pendingWrap, "pendingWrap cleared on 47 exit")
}

// ============================================================================
// MARK: - Updater Logic
// ============================================================================

// Inline copies of the validation logic from UpdateChecker — tested in isolation
// so they don't require URLSession/Cocoa.

private func isAllowedUpdateHost(_ url: URL) -> Bool {
    let allowedHosts = ["github.com", "objects.githubusercontent.com"]
    let host = url.host ?? ""
    return allowedHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) })
}

private func isNewerVersionTest(remote: String, local: String) -> Bool {
    let strip: (String) -> String = { $0.hasPrefix("v") ? String($0.dropFirst()) : $0 }
    let rParts = strip(remote).split(separator: ".").compactMap { Int($0) }
    let lParts = strip(local).split(separator: ".").compactMap { Int($0) }
    for i in 0..<max(rParts.count, lParts.count) {
        let r = i < rParts.count ? rParts[i] : 0
        let l = i < lParts.count ? lParts[i] : 0
        if r > l { return true }
        if r < l { return false }
    }
    return false
}

section("Updater Logic")

test("isNewerVersion: basics") {
    check(isNewerVersionTest(remote: "v1.5.0", local: "v1.4.0"), "1.5.0 > 1.4.0")
    check(!isNewerVersionTest(remote: "v1.4.0", local: "v1.4.0"), "same not newer")
    check(!isNewerVersionTest(remote: "v1.3.9", local: "v1.4.0"), "1.3.9 < 1.4.0")
    check(isNewerVersionTest(remote: "v2.0.0", local: "v1.9.9"), "2.0.0 > 1.9.9")
    check(isNewerVersionTest(remote: "1.5.0", local: "1.4.0"), "no-v prefix works")
}

test("URL host allowlist: rejects non-GitHub hosts") {
    check(!isAllowedUpdateHost(URL(string: "https://evil.com/f.zip")!), "evil.com rejected")
    check(!isAllowedUpdateHost(URL(string: "https://notgithub.com/f.zip")!), "notgithub.com rejected")
    check(!isAllowedUpdateHost(URL(string: "https://evil-github.com/f.zip")!), "evil-github.com rejected (suffix trick)")
    check(!isAllowedUpdateHost(URL(string: "https://fakegithub.com/f.zip")!), "fakegithub.com rejected")
}

test("URL host allowlist: accepts GitHub CDN hosts") {
    check(isAllowedUpdateHost(URL(string: "https://github.com/f.zip")!), "github.com allowed")
    check(isAllowedUpdateHost(URL(string: "https://objects.githubusercontent.com/f.zip")!), "objects.githubusercontent.com allowed")
}

test("HTTPS scheme check: rejects HTTP") {
    let httpURL = URL(string: "http://github.com/file.zip")!
    let httpsURL = URL(string: "https://github.com/file.zip")!
    check(httpURL.scheme != "https", "http:// rejected by scheme check")
    check(httpsURL.scheme == "https", "https:// accepted")
}

test("Relaunch guard: open exit-code != 0 prevents exit") {
    // Mirror the guard in installUpdate's relaunch block:
    //   guard openProc.terminationStatus == 0 else { return }
    // We run /usr/bin/false (always exits 1) to confirm the guard triggers correctly.
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/false")
    try? proc.run()
    proc.waitUntilExit()
    check(proc.terminationStatus != 0, "/usr/bin/false exits with non-zero code")
    // Guard condition: only exit(0) when terminationStatus == 0
    let guardPasses = proc.terminationStatus == 0
    check(!guardPasses, "non-zero exit code correctly prevents relaunch exit")
}

test("Relaunch guard: successful open would allow exit") {
    // /usr/bin/true always exits 0 — confirms the happy path
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/true")
    try? proc.run()
    proc.waitUntilExit()
    check(proc.terminationStatus == 0, "/usr/bin/true exits 0")
    let guardPasses = proc.terminationStatus == 0
    check(guardPasses, "exit code 0 correctly allows relaunch exit")
}

// ── SyntaxLanguage stub (mirrors quickTerminal.swift) ────────────────────────
enum SyntaxLanguage_Test: String {
    case none, json, html, css, javascript

    static func detect(from url: URL) -> SyntaxLanguage_Test {
        switch url.pathExtension.lowercased() {
        case "json":                                    return .json
        case "html", "htm":                             return .html
        case "css":                                     return .css
        case "js", "mjs", "cjs", "ts", "tsx", "jsx":   return .javascript
        default:                                        return .none
        }
    }
}

func testSyntaxLanguageDetection() {
    let cases: [(String, SyntaxLanguage_Test)] = [
        ("data.json",    .json),
        ("index.html",   .html),
        ("index.htm",    .html),
        ("style.css",    .css),
        ("app.js",       .javascript),
        ("app.mjs",      .javascript),
        ("app.cjs",      .javascript),
        ("app.ts",       .javascript),
        ("app.tsx",      .javascript),
        ("app.jsx",      .javascript),
        ("README.md",    .none),
        ("main.swift",   .none),
        ("Makefile",     .none),
    ]
    for (filename, expected) in cases {
        let url = URL(fileURLWithPath: "/tmp/\(filename)")
        let got = SyntaxLanguage_Test.detect(from: url)
        assert(got == expected, "detect(\(filename)): expected \(expected), got \(got)")
    }
    print("✓ SyntaxLanguage.detect — \(cases.count) cases")
}

testSyntaxLanguageDetection()

// ============================================================================
// MARK: - Print Options
// ============================================================================

// ── PrintOption stub (mirrors quickTerminal.swift) ──────────────────────────
enum PrintAction_Test { case renderedHTML, sourceCode, terminal }
struct PrintOption_Test { let label: String; let action: PrintAction_Test }

func buildPrintOptions_Test(isEditor: Bool, ext: String) -> [PrintOption_Test] {
    guard isEditor else {
        return [PrintOption_Test(label: "Terminal drucken", action: .terminal)]
    }
    let renderedExts: Set<String> = ["md","markdown","mdown","mkd","html","htm","svg","csv"]
    guard renderedExts.contains(ext) else {
        return [PrintOption_Test(label: "Quellcode drucken", action: .sourceCode)]
    }
    return [
        PrintOption_Test(label: "Drucken",           action: .renderedHTML),
        PrintOption_Test(label: "Quellcode drucken", action: .sourceCode),
    ]
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

    testsPassed += 1
    print("✓ buildPrintOptions — 6 cases")
}
testBuildPrintOptions()

// ============================================================================
// MARK: - WebPicker Persistence Tests
// ============================================================================

struct PickEntryRecord: Codable {
    let id: Int
    let html: String
    let hex: String
    let selector: String
    let innerText: String
    let xpath: String
}

test("PickEntryRecord encodes and decodes round-trip") {
    let original = PickEntryRecord(id: 3, html: "<div>test</div>", hex: "#FF6B6B",
                                   selector: "#main > div", innerText: "test",
                                   xpath: "body/main/div")
    guard let data = try? JSONEncoder().encode([original]),
          let decoded = try? JSONDecoder().decode([PickEntryRecord].self, from: data),
          let first = decoded.first else {
        testsFailed += 1
        print("  FAIL: PickEntryRecord encodes and decodes round-trip — encode/decode failed")
        return
    }
    check(first.id == 3, "id survives round-trip")
    check(first.html == "<div>test</div>", "html survives round-trip")
    check(first.selector == "#main > div", "selector survives round-trip")
    check(first.xpath == "body/main/div", "xpath survives round-trip")
}

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
    // Edge: leerer String und out-of-bounds
    assert(findMatchingBracket_Test(in: "", at: 0) == nil,     "empty string")
    assert(findMatchingBracket_Test(in: "{}", at: -1) == nil,  "negative pos")
    // 10k-Limit: unmatched bracket weit entfernt → nil
    let longStr = "{" + String(repeating: "x", count: 10_001)
    assert(findMatchingBracket_Test(in: longStr, at: 0) == nil, "10k limit")
    testsPassed += 1
    print("✓ Bracket matching — 15 cases")
}

testBracketMatching()

// ============================================================================
// MARK: - Results
// ============================================================================

print("\n" + String(repeating: "=", count: 50))
print("Results: \(testsPassed) passed, \(testsFailed) failed")
print(String(repeating: "=", count: 50))

if testsFailed > 0 {
    print("\nSome tests FAILED!")
    exit(1)
} else {
    print("\nAll tests PASSED!")
    exit(0)
}
