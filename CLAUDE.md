# SystemTrayTerminal — Claude Instructions

## Swift Skills (IMMER konsultieren!)

Bevor du Swift/AppKit/SwiftUI Code schreibst oder reviewst, lies die relevanten Skills:

| Thema | Datei |
|-------|-------|
| Concurrency (@MainActor, async/await) | `swift/concurrency-reference/SKILL.md` |
| State Management (@State, @Observable) | `swift/state-management/SKILL.md` |
| Layout (SwiftUI Patterns, Image+overlay) | `swift/layout-guide/SKILL.md` |
| Navigation & Sheets | `swift/navigation-sheets/SKILL.md` |
| Modern APIs (Deprecated → iOS 18+) | `swift/modern-apis/SKILL.md` |
| HIG Design (Spacing, Typography, Touch) | `swift/hig-design/SKILL.md` |
| Capabilities & Entitlements | `swift/capabilities-entitlements/SKILL.md` |

### Wann welchen Skill lesen:
- **Neuer Code mit async/await / DispatchQueue** → `concurrency-reference`
- **Property Wrapper Entscheidung** (@State vs @Binding vs @Observable) → `state-management`
- **SwiftUI Views, Images, ScrollViews** → `layout-guide`
- **NavigationStack, Sheets, Detents** → `navigation-sheets`
- **Deprecated API Warnungen / Review** → `modern-apis`
- **UI Design, Abstände, Farben** → `hig-design`
- **App Sandbox, Berechtigungen** → `capabilities-entitlements`

## Projekt-Kurzreferenz

- **Hauptdatei**: `SystemTrayTerminal.swift` (~16500+ Zeilen, single-file macOS App)
- **Build**: `bash build.sh` nach JEDER Änderung
- **Tests**: laufen automatisch am Ende von `build.sh`
- **Architektur**: macOS Menu-Bar App, kein Dock-Icon, Cocoa + Carbon only
