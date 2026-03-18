# Project Rename: quickTerminal → SystemTrayTerminal Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Vollständiges Rename von quickTerminal zu SystemTrayTerminal (Abkürzung: STT) — Dateinamen, Bundle-ID, Config-Pfade, Display-Strings, Build-Scripts, Docs.

**Architecture:** Batch-Ersetzungen in Swift-Datei + Build-Scripts, Migrations-Logik für bestehende Installs, dann Directory-Rename als letzter Schritt.

**Tech Stack:** Swift, Bash, git mv

---

## Übersicht der Änderungen

| Was | Alt | Neu |
|---|---|---|
| Source-Datei | `quickTerminal.swift` | `systemtrayterminal.swift` |
| Binary | `quickTerminal` | `SystemTrayTerminal` |
| App-Bundle | `quickTerminal.app` | `SystemTrayTerminal.app` |
| Bundle-ID | `com.l3v0.quickterminal` | `com.l3v0.systemtrayterminal` |
| CFBundleName | `quickTerminal` | `SystemTrayTerminal` |
| CFBundleDisplayName | `quickTERMINAL` | `SystemTrayTerminal` |
| Config-Dir | `~/.quickterminal/` | `~/.systemtrayterminal/` |
| LaunchAgent Label | `com.quickterminal.autostart` | `com.systemtrayterminal.autostart` |
| Keychain Service | `com.quickTerminal.github` | `com.SystemTrayTerminal.github` |
| Footer-Text | `quickTERMINAL v…` | `STT v…` |
| About-Titel / Badge | `quickTERMINAL` | `SystemTrayTerminal` |
| Settings-Titel | `quickTERMINAL` | `SystemTrayTerminal` |
| Menü-Items | `About/Quit quickTerminal` | `About/Quit SystemTrayTerminal` |
| Onboarding-Video | `quickTERMINAL.mp4` | `SystemTrayTerminal.mp4` |
| Projekt-Verzeichnis | `quickTerminal/` | `SystemTrayTerminal/` |

---

### Task 1: git mv Source-Datei

**Files:**
- Rename: `quickTerminal.swift` → `systemtrayterminal.swift`

**Step 1: Datei umbenennen mit git**

```bash
cd "/Users/l3v0/Desktop/FERTIGE PROJEKTE/quickTerminal"
git mv quickTerminal.swift systemtrayterminal.swift
```

**Step 2: Verifizieren**

```bash
git status
```
Expected: `renamed: quickTerminal.swift -> systemtrayterminal.swift`

**Step 3: Commit**

```bash
git commit -m "chore: rename quickTerminal.swift → systemtrayterminal.swift"
```

---

### Task 2: Build-Scripts aktualisieren

**Files:**
- Modify: `build.sh`
- Modify: `build_app.sh`
- Modify: `build_zip.sh`

**Step 1: `build.sh` komplett ersetzen**

```bash
#!/bin/bash
set -e
cd "$(dirname "$0")"

echo "Building SystemTrayTerminal..."
swiftc -O systemtrayterminal.swift -o SystemTrayTerminal -framework Cocoa -framework Carbon -framework AVKit -framework WebKit \
  -Xlinker -sectcreate -Xlinker __FONTS -Xlinker __jbmono -Xlinker _JetBrainsMono-LightItalic-terminal.ttf \
  -Xlinker -sectcreate -Xlinker __FONTS -Xlinker __monocraft -Xlinker _Monocraft-terminal.ttf \
  -Xlinker -sectcreate -Xlinker __DATA -Xlinker __readme -Xlinker README.md \
  -Xlinker -sectcreate -Xlinker __DATA -Xlinker __commands -Xlinker COMMANDS.md \
  -Xlinker -sectcreate -Xlinker __DATA -Xlinker __changelog -Xlinker CHANGELOG.md
echo "Done! Run with: ./SystemTrayTerminal"

echo ""
echo "Running tests..."
swift tests.swift
echo ""
```

**Step 2: `build_app.sh` — Ersetzungen**

1. Zeile 5: `APP_NAME="quickTerminal"` → `APP_NAME="SystemTrayTerminal"`
2. Zeile 8: `BUNDLE_ID="com.l3v0.quickterminal"` → `BUNDLE_ID="com.l3v0.systemtrayterminal"`
3. Zeile 11: `quickTerminal.swift` → `systemtrayterminal.swift` (VERSION extraction sed)
4. Zeile 12: Error-Msg `quickTerminal.swift` → `systemtrayterminal.swift`
5. Zeile 40: `swiftc -O quickTerminal.swift` → `swiftc -O systemtrayterminal.swift`
6. Zeile 72: `cp quickTERMINAL.mp4` → `cp SystemTrayTerminal.mp4`
7. Zeile 86: `<string>quickTERMINAL</string>` (CFBundleDisplayName) → `<string>SystemTrayTerminal</string>`
8. Zeile 112: `quickTERMINAL needs accessibility...` → `SystemTrayTerminal needs accessibility...`

**Step 3: `build_zip.sh` — Ersetzungen**

1. Zeile 6: `quickTerminal.swift` → `systemtrayterminal.swift`
2. Zeile 7: Error-Msg `quickTerminal.swift` → `systemtrayterminal.swift`
3. Zeile 8: `ZIP_NAME="quickTERMINAL_v${VERSION}.zip"` → `ZIP_NAME="SystemTrayTerminal_v${VERSION}.zip"`
4. Zeile 19: `ditto -ck ... quickTerminal.app` → `SystemTrayTerminal.app`
5. Zeile 29: Echo `quickTerminal.app` → `SystemTrayTerminal.app`

**Step 4: Commit**

```bash
git add build.sh build_app.sh build_zip.sh
git commit -m "chore: update build scripts for SystemTrayTerminal rename"
```

---

### Task 3: Onboarding-Video umbenennen

**Files:**
- Rename: `quickTERMINAL.mp4` → `SystemTrayTerminal.mp4`

**Step 1: Datei umbenennen**

```bash
cd "/Users/l3v0/Desktop/FERTIGE PROJEKTE/quickTerminal"
git mv quickTERMINAL.mp4 SystemTrayTerminal.mp4
```

**Step 2: Commit**

```bash
git commit -m "chore: rename quickTERMINAL.mp4 → SystemTrayTerminal.mp4"
```

---

### Task 4: In-App Display-Strings in systemtrayterminal.swift

**Files:**
- Modify: `systemtrayterminal.swift`

**Step 1: Datei-Header (Zeile 1)**

Alt: `// quickTerminal.swift — A simple native terminal emulator for macOS`
Neu: `// systemtrayterminal.swift — SystemTrayTerminal — A native macOS menu bar terminal`

**Step 2: Footer-Text (Zeile 4315)**

Alt: `string: "quickTERMINAL v\(kAppVersion) — LEVOGNE © 2026"`
Neu: `string: "STT v\(kAppVersion) — LEVOGNE © 2026"`

**Step 3: About-Titel (Zeile 13237)**

Alt: `l.append(StyledLine(text: "quickTERMINAL", style: .title))`
Neu: `l.append(StyledLine(text: "SystemTrayTerminal", style: .title))`

**Step 4: NSMenu-Items (Zeilen 20466, 20468)**

Alt: `"About quickTerminal"` → Neu: `"About SystemTrayTerminal"`
Alt: `"Quit quickTerminal"` → Neu: `"Quit SystemTrayTerminal"`

**Step 5: fullDiskAccessMsg in allen Sprachen (Zeilen 289, 358, 427, 496, 565, 634, 703, 772, 841, 910)**

Replace all: `quickTERMINAL` in `fullDiskAccessMsg` strings → `SystemTrayTerminal`

**Step 6: quitApp-Strings in allen Sprachen**

Replace all:
- `"Quit quickTerminal"` → `"Quit SystemTrayTerminal"`
- `"quickTerminal beenden"` → `"SystemTrayTerminal beenden"`
- `"quickTerminal'i Kapat"` → `"SystemTrayTerminal'i Kapat"`
- `"Salir de quickTerminal"` → `"Salir de SystemTrayTerminal"`
- `"Quitter quickTerminal"` → `"Quitter SystemTrayTerminal"`
- `"Esci da quickTerminal"` → `"Esci da SystemTrayTerminal"`
- `"إنهاء quickTerminal"` → `"إنهاء SystemTrayTerminal"`
- `"quickTerminal を終了"` → `"SystemTrayTerminal を終了"`
- `"退出 quickTerminal"` → `"退出 SystemTrayTerminal"`
- `"Выйти из quickTerminal"` → `"Выйти из SystemTrayTerminal"`

**Step 7: Feedback-Email (Zeilen 8002–8004, 8053)**

Alt:
```swift
let subject = "quickTERMINAL Feedback"
let hostname = Host.current().localizedName ?? "quickTerminal-user"
let email = "From: quickTerminal@\(hostname)\r\n..."
```
Neu:
```swift
let subject = "SystemTrayTerminal Feedback"
let hostname = Host.current().localizedName ?? "SystemTrayTerminal-user"
let email = "From: SystemTrayTerminal@\(hostname)\r\n..."
```
(Zeile 8053: `let subject = "quickTERMINAL Feedback"` → `"SystemTrayTerminal Feedback"`)

**Step 8: Device Attribute Response (Zeile 2248)**

Alt: `onResponse?("\u{1B}P>|quickTerminal(1.0)\u{1B}\\")`
Neu: `onResponse?("\u{1B}P>|SystemTrayTerminal(1.0)\u{1B}\\")`

**Step 9: Crash-Log / Lock-Datei (Zeilen 20403, 20415, 20428, 20441)**

Alt: `let lockPath = NSTemporaryDirectory() + "quickTerminal.lock"`
Neu: `let lockPath = NSTemporaryDirectory() + "SystemTrayTerminal.lock"`

Alt (20415, 20428): `NSHomeDirectory() + "/.quickterminal"`
Neu: `NSHomeDirectory() + "/.systemtrayterminal"`

Alt (20441): `var msg = "quickTerminal crashed with signal \(sigNum)\n"`
Neu: `var msg = "SystemTrayTerminal crashed with signal \(sigNum)\n"`

**Step 10: GitHub Token Description (Zeile 10834)**

Suche: `scopes=repo&description=quickTerminal`
Neu: `scopes=repo&description=SystemTrayTerminal`

**Step 11: SVG-Kommentar (Zeile 16636)**

Alt: `// Exact reproduction of quickTERMINAL.svg`
Neu: `// Exact reproduction of SystemTrayTerminal.svg`

**Step 12: Commit**

```bash
git add systemtrayterminal.swift
git commit -m "feat: update all in-app display strings for SystemTrayTerminal rename"
```

---

### Task 5: System-Identifiers in systemtrayterminal.swift

**Files:**
- Modify: `systemtrayterminal.swift`

**Step 1: LaunchAgent Label (Zeilen 8580, 8588)**

Alt:
```swift
let plistPath = "\(agentDir)/com.quickterminal.autostart.plist"
"Label": "com.quickterminal.autostart",
```
Neu:
```swift
let plistPath = "\(agentDir)/com.systemtrayterminal.autostart.plist"
"Label": "com.systemtrayterminal.autostart",
```

**Step 2: Keychain Service (Zeile 8605)**

Alt: `private static let service = "com.quickTerminal.github"`
Neu: `private static let service = "com.SystemTrayTerminal.github"`

**Step 3: Config-Dir (Zeile 3158)**

Alt: `let histDir = "\(homeDir)/.quickterminal/history"`
Neu: `let histDir = "\(homeDir)/.systemtrayterminal/history"`

**Step 4: Update-Installer Temp-Pfade (Zeilen 14623, 14682, 14745)**

Alt: `"quickTerminal_update_\(UUID().uuidString).zip"`
Neu: `"SystemTrayTerminal_update_\(UUID().uuidString).zip"`

Alt: `"quickTerminal_extract_\(UUID().uuidString)"`
Neu: `"SystemTrayTerminal_extract_\(UUID().uuidString)"`

Alt: `"quickTerminal_backup_\(UUID().uuidString).app"`
Neu: `"SystemTrayTerminal_backup_\(UUID().uuidString).app"`

**Step 4b: Exec-Pfad dynamisch machen (Zeilen 14711–14717) — KRITISCH für Backward-Compat**

Das ist der Fix der alten `quickTerminal.app` Usern erlaubt auf `SystemTrayTerminal.app` zu updaten.
Die Info.plist wird ohnehin kurz danach gelesen (Zeile 14720) — wir ziehen das vor:

Alt (Zeilen 14711–14729):
```swift
// Verify executable exists
let execPath = appBundle.appendingPathComponent("Contents/MacOS/quickTerminal")
guard fm.isExecutableFile(atPath: execPath.path) else {
    complete(.failure(NSError(domain: "UpdateChecker", code: 5,
                             userInfo: [NSLocalizedDescriptionKey: "Invalid app bundle — no executable"])))
    try? fm.removeItem(at: extractDir)
    return
}

// [P0] Verify bundle identifier matches current app
let infoPlistURL = appBundle.appendingPathComponent("Contents/Info.plist")
if let plist = NSDictionary(contentsOf: infoPlistURL),
   let newBundleId = plist["CFBundleIdentifier"] as? String,
   let currentBundleId = Bundle.main.bundleIdentifier,
   !currentBundleId.isEmpty, newBundleId != currentBundleId {
    complete(.failure(NSError(domain: "UpdateChecker", code: 9,
                             userInfo: [NSLocalizedDescriptionKey: "Bundle identifier mismatch — aborting update"])))
    try? fm.removeItem(at: extractDir)
    return
}
```

Neu:
```swift
// Read Info.plist once for exec name + bundle ID check
let infoPlistURL = appBundle.appendingPathComponent("Contents/Info.plist")
let plist = NSDictionary(contentsOf: infoPlistURL)

// Verify executable exists — name read dynamically from CFBundleExecutable
let execName = (plist?["CFBundleExecutable"] as? String) ?? "SystemTrayTerminal"
let execPath = appBundle.appendingPathComponent("Contents/MacOS/\(execName)")
guard fm.isExecutableFile(atPath: execPath.path) else {
    complete(.failure(NSError(domain: "UpdateChecker", code: 5,
                             userInfo: [NSLocalizedDescriptionKey: "Invalid app bundle — no executable"])))
    try? fm.removeItem(at: extractDir)
    return
}

// [P0] Verify bundle identifier — allow known migration: quickterminal → systemtrayterminal
let knownMigration = ("com.l3v0.quickterminal", "com.l3v0.systemtrayterminal")
if let newBundleId = plist?["CFBundleIdentifier"] as? String,
   let currentBundleId = Bundle.main.bundleIdentifier,
   !currentBundleId.isEmpty, newBundleId != currentBundleId {
    let isMigration = (currentBundleId == knownMigration.0 && newBundleId == knownMigration.1)
    if !isMigration {
        complete(.failure(NSError(domain: "UpdateChecker", code: 9,
                                 userInfo: [NSLocalizedDescriptionKey: "Bundle identifier mismatch — aborting update"])))
        try? fm.removeItem(at: extractDir)
        return
    }
}
```

**Step 5: GitHub API URL (Zeile 14537)**

Alt: `https://api.github.com/repos/LEVOGNE/quickTerminal/releases/latest`
Neu: `https://api.github.com/repos/LEVOGNE/SystemTrayTerminal/releases/latest`

> **Hinweis:** Diese URL funktioniert erst nach dem GitHub-Repo-Rename auf github.com!

**Step 6: Onboarding-Video Resource (Zeile 14894)**

Alt: `Bundle.main.url(forResource: "quickTERMINAL", withExtension: "mp4")`
Neu: `Bundle.main.url(forResource: "SystemTrayTerminal", withExtension: "mp4")`

**Step 7: Factory Reset (Zeilen 17882–17910)**

Alt:
```swift
// --- Full factory reset: delete ALL quickTerminal data from system ---
// A) Delete ~/.quickterminal/ directory (shell history files)
try? fm.removeItem(atPath: home + "/.quickterminal")
```
Neu:
```swift
// --- Full factory reset: delete ALL SystemTrayTerminal data from system ---
// A) Delete ~/.systemtrayterminal/ directory (shell history files)
try? fm.removeItem(atPath: home + "/.systemtrayterminal")
```

Zeile 17908:
Alt: `cachesDir + "/com.l3v0.quickterminal"`
Neu: `cachesDir + "/com.l3v0.systemtrayterminal"`

**Step 8: Commit**

```bash
git add systemtrayterminal.swift
git commit -m "feat: update system identifiers for SystemTrayTerminal (bundle, LaunchAgent, keychain, paths)"
```

---

### Task 6: Migrations-Logik hinzufügen

**Files:**
- Modify: `systemtrayterminal.swift` — direkt vor `applicationDidFinishLaunching`

**Step 1: Migrations-Funktion hinzufügen**

```swift
private func migrateLegacyData() {
    let fm = FileManager.default
    let home = NSHomeDirectory()
    let oldConfigDir = home + "/.quickterminal"
    let newConfigDir = home + "/.systemtrayterminal"

    // 1. Migrate config directory
    if fm.fileExists(atPath: oldConfigDir) && !fm.fileExists(atPath: newConfigDir) {
        do {
            try fm.copyItem(atPath: oldConfigDir, toPath: newConfigDir)
            try fm.removeItem(atPath: oldConfigDir)
        } catch {
            // Migration failed — leave old dir intact
        }
    }

    // 2. Migrate UserDefaults from old domain to new domain
    let oldDomain = "com.l3v0.quickterminal"
    let newDomain = "com.l3v0.systemtrayterminal"
    let defaults = UserDefaults.standard
    if let oldPrefs = UserDefaults(suiteName: oldDomain)?.dictionaryRepresentation(),
       !oldPrefs.isEmpty {
        let newDefaults = UserDefaults(suiteName: newDomain)
        for (key, value) in oldPrefs {
            if newDefaults?.object(forKey: key) == nil {
                newDefaults?.set(value, forKey: key)
            }
        }
        newDefaults?.synchronize()
        defaults.removePersistentDomain(forName: oldDomain)
    }

    // 3. Migrate LaunchAgent (unload old label, new label registered on next autostart toggle)
    let agentDir = home + "/Library/LaunchAgents"
    let oldPlist = agentDir + "/com.quickterminal.autostart.plist"
    if fm.fileExists(atPath: oldPlist) {
        let task = Process()
        task.launchPath = "/bin/launchctl"
        task.arguments = ["unload", oldPlist]
        try? task.run()
        task.waitUntilExit()
        try? fm.removeItem(atPath: oldPlist)
    }
}
```

**Step 2: Aufruf in `applicationDidFinishLaunching` (nach Zeile 16619)**

```swift
// Migrate legacy data from quickTerminal → SystemTrayTerminal
migrateLegacyData()
```

**Step 3: Build und Test**

```bash
bash build.sh
```
Expected: Kompiliert ohne Fehler, Tests grün.

**Step 4: Commit**

```bash
git add systemtrayterminal.swift
git commit -m "feat: add legacy data migration quickTerminal → SystemTrayTerminal"
```

---

### Task 7: install.sh und FIRST_READ.txt aktualisieren

**Files:**
- Modify: `install.sh`
- Modify: `FIRST_READ.txt`

**Step 1: `install.sh`**

Ersetze alle Vorkommen:
- `quickTerminal.app` → `SystemTrayTerminal.app`
- `quickTERMINAL Installer` → `SystemTrayTerminal Installer`

**Step 2: `FIRST_READ.txt`**

Ersetze:
- `quickTERMINAL` → `SystemTrayTerminal` (alle Vorkommen)
- `quickTerminal.app` → `SystemTrayTerminal.app`
- `xattr -cr quickTerminal.app` → `xattr -cr SystemTrayTerminal.app`
- GitHub-URL: `LEVOGNE/quickTerminal` → `LEVOGNE/SystemTrayTerminal`

**Step 3: Commit**

```bash
git add install.sh FIRST_READ.txt
git commit -m "docs: update install.sh and FIRST_READ.txt for SystemTrayTerminal"
```

---

### Task 8: Dokumentation aktualisieren

**Files:**
- Modify: `README.md`, `CHANGELOG.md`, `COMMANDS.md`, `ROADMAP.md`, `MARKETING.md`, `CONTRIBUTING.md`, `SECURITY.md`, `CLAUDE.md`, `CODE_OF_CONDUCT.md`, `REMAINING_COMPAT.md`
- Modify: `docs/index.html`

**Step 1: Batch-Ersetzung**

```bash
cd "/Users/l3v0/Desktop/FERTIGE PROJEKTE/quickTerminal"
for f in README.md CHANGELOG.md COMMANDS.md ROADMAP.md MARKETING.md CONTRIBUTING.md SECURITY.md CLAUDE.md CODE_OF_CONDUCT.md REMAINING_COMPAT.md; do
    [ -f "$f" ] || continue
    sed -i '' \
        -e 's/quickTERMINAL/SystemTrayTerminal/g' \
        -e 's/quickTerminal/SystemTrayTerminal/g' \
        -e 's/quickterminal/systemtrayterminal/g' \
        "$f"
done
[ -f docs/index.html ] && sed -i '' \
    -e 's/quickTERMINAL/SystemTrayTerminal/g' \
    -e 's/quickTerminal/SystemTrayTerminal/g' \
    -e 's/quickterminal/systemtrayterminal/g' \
    docs/index.html
```

> **ACHTUNG**: CHANGELOG.md danach manuell prüfen — historische Versionsnamen sollen korrekt bleiben.

**Step 2: CLAUDE.md Hauptdatei-Referenz**

In `CLAUDE.md`: `quickTerminal.swift` → `systemtrayterminal.swift`

**Step 3: Commit**

```bash
git add README.md CHANGELOG.md COMMANDS.md ROADMAP.md MARKETING.md CONTRIBUTING.md SECURITY.md CLAUDE.md docs/
git commit -m "docs: rename quickTerminal → SystemTrayTerminal throughout all documentation"
```

---

### Task 9: Build und vollständigen Test durchführen

**Step 1: Build**

```bash
cd "/Users/l3v0/Desktop/FERTIGE PROJEKTE/quickTerminal"
bash build.sh
```
Expected: `Done! Run with: ./SystemTrayTerminal`, alle Tests grün.

**Step 2: Alte Binaries aufräumen**

```bash
rm -f quickTerminal quickTerminal_debug.dSYM 2>/dev/null || true
```

**Step 3: App-Bundle testen**

```bash
bash build_app.sh
```
Expected: `SystemTrayTerminal.app` wird erstellt.

**Step 4: Commit wenn nötig**

```bash
git status
git add -A && git commit -m "chore: clean up old build artifacts"
```

---

### Task 10: Verzeichnis umbenennen

> **WICHTIG:** Dieser Task kommt ZULETZT!

**Step 1: Verzeichnis umbenennen**

```bash
mv "/Users/l3v0/Desktop/FERTIGE PROJEKTE/quickTerminal" "/Users/l3v0/Desktop/FERTIGE PROJEKTE/SystemTrayTerminal"
```

**Step 2: Memory-Verzeichnis für neuen Pfad vorbereiten**

```bash
mkdir -p "/Users/l3v0/.claude/projects/-Users-l3v0-Desktop-FERTIGE-PROJEKTE-SystemTrayTerminal/memory"
cp "/Users/l3v0/.claude/projects/-Users-l3v0-Desktop-FERTIGE-PROJEKTE-quickTerminal/memory/MEMORY.md" \
   "/Users/l3v0/.claude/projects/-Users-l3v0-Desktop-FERTIGE-PROJEKTE-SystemTrayTerminal/memory/MEMORY.md"
```

**Step 3: MEMORY.md im neuen Pfad aktualisieren**

Ersetze in der kopierten MEMORY.md:
- `quickTerminal.swift` → `systemtrayterminal.swift`
- `/quickTerminal/` → `/SystemTrayTerminal/`
- `~/.quickterminal/` → `~/.systemtrayterminal/`
- `com.l3v0.quickterminal` → `com.l3v0.systemtrayterminal`
- `FERTIGE-PROJEKTE-quickTerminal` → `FERTIGE-PROJEKTE-SystemTrayTerminal`

**Step 4: Verifizieren**

```bash
cd "/Users/l3v0/Desktop/FERTIGE PROJEKTE/SystemTrayTerminal"
git log --oneline -5
bash build.sh
```

---

### Task 11: Dual-Repo Setup (Parallel bis v1.6.0)

**Strategie:** Alter `quickTerminal` Repo bleibt live. Neues `SystemTrayTerminal` Repo wird erstellt.
Beide bekommen denselben Code + dieselben Releases. Nach v1.6.0 wird `quickTerminal` archiviert/gelöscht.

**Warum das funktioniert:**
- Alte User prüfen `LEVOGNE/quickTerminal` auf Updates → finden neues Release → laden `SystemTrayTerminal.app`
- Dank der Fixes in Task 5 (dynamischer Exec-Name + Migration-Bundle-ID-Exception) läuft das Update durch
- Nach dem Update zeigt ihre App auf `LEVOGNE/SystemTrayTerminal` für alle künftigen Updates
- Alter Repo kann nach v1.6.0 archiviert werden

**Step 1: Neues GitHub-Repo erstellen**

Manuell auf github.com:
1. `https://github.com/new` → Name: `SystemTrayTerminal` → Create

**Step 2: Zweite Remote hinzufügen**

```bash
cd "/Users/l3v0/Desktop/FERTIGE PROJEKTE/SystemTrayTerminal"
git remote add stt https://github.com/LEVOGNE/SystemTrayTerminal.git
```

Verifizieren:
```bash
git remote -v
```
Expected:
```
origin   https://github.com/LEVOGNE/quickTerminal.git (fetch)
origin   https://github.com/LEVOGNE/quickTerminal.git (push)
stt      https://github.com/LEVOGNE/SystemTrayTerminal.git (fetch)
stt      https://github.com/LEVOGNE/SystemTrayTerminal.git (push)
```

**Step 3: Erstmalig beide Repos befüllen**

```bash
git push origin main      # alter quickTerminal Repo
git push stt main         # neuer SystemTrayTerminal Repo
```

**Step 4: Push-Script erstellen (für täglichen Workflow)**

Erstelle `push.sh` im Projekt-Root:
```bash
#!/bin/bash
set -e
echo "Pushing to quickTerminal (legacy)..."
git push origin main
echo "Pushing to SystemTrayTerminal (new)..."
git push stt main
echo "Done."
```
```bash
chmod +x push.sh
git add push.sh
git commit -m "chore: add push.sh for dual-repo workflow"
```

**Step 5: Releases auf beiden Repos veröffentlichen**

Bei jedem Release:
```bash
bash build_zip.sh   # erzeugt SystemTrayTerminal_v1.x.x.zip

# Auf neuem Repo publizieren
gh release create v1.x.x SystemTrayTerminal_v1.x.x.zip \
  --title "v1.x.x" --repo LEVOGNE/SystemTrayTerminal

# Auf altem Repo AUCH publizieren (damit alte User das Update finden)
gh release create v1.x.x SystemTrayTerminal_v1.x.x.zip \
  --title "v1.x.x" --repo LEVOGNE/quickTerminal
```

**Ab v1.6.0: Alter Repo archivieren**

Manuell auf github.com:
1. `https://github.com/LEVOGNE/quickTerminal` → Settings → Archive this repository

---

## Reihenfolge der Commits

1. `chore: rename quickTerminal.swift → systemtrayterminal.swift`
2. `chore: update build scripts for SystemTrayTerminal rename`
3. `chore: rename quickTERMINAL.mp4 → SystemTrayTerminal.mp4`
4. `feat: update all in-app display strings for SystemTrayTerminal rename`
5. `feat: update system identifiers + backward-compat updater (dynamic exec, migration bundle ID)`
6. `feat: add legacy data migration quickTerminal → SystemTrayTerminal`
7. `docs: update install.sh and FIRST_READ.txt for SystemTrayTerminal`
8. `docs: rename quickTerminal → SystemTrayTerminal throughout all documentation`
9. `chore: add push.sh for dual-repo workflow`
10. *(Directory-Rename ist kein git-commit)*
