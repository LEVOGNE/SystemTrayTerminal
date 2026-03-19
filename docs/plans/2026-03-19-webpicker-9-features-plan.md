# WebPicker 9 Features — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task.

**Goal:** Add 9 new features to `WebPickerSidebarView` and `ChromeCDPClient`: scrollable picks, persistence, CSS selector/copy formats, tab switcher, hot reload, computed style inspector, JS REPL, and element screenshot.

**Architecture:** All changes are additive and confined to `// MARK: - WebPicker Sidebar View` and `// MARK: - Chrome CDP Client` sections (lines ~11074–13087 in `systemtrayterminal.swift`). No changes to terminal engine, SSH manager, or editor. PickEntry gets new fields. Two new CDP methods added to ChromeCDPClient.

**Tech Stack:** Swift/AppKit, Chrome DevTools Protocol (CDP via WebSocket), DispatchSource (kqueue), Timer-based polling, NSMenu, NSScrollView.

**Build command:** `bash build.sh` (runs compiler + swift tests.swift automatically)

---

## Task 1: Scrollable Picks List (Feature 8)

**Files:**
- Modify: `systemtrayterminal.swift:12258` (picksStack declaration)
- Modify: `systemtrayterminal.swift:12518-12525` (layout constraints)
- Modify: `systemtrayterminal.swift:12924-12930` (FIFO limit)
- Modify: `systemtrayterminal.swift:12950-12951` (row width anchor)

**Step 1: Replace picksStack direct layout with scroll-wrapped layout**

In the properties block (around line 12258), replace:
```swift
    private let picksStack         = NSStackView()
```
with:
```swift
    private let picksStack         = NSStackView()
    private let picksScrollView    = NSScrollView()
```

**Step 2: In `setupUI()`, after `picksStack` setup (around line 12441–12446), configure the scroll view**

Replace the existing picksStack addSubview + setup block:
```swift
        picksStack.orientation = .vertical
        picksStack.spacing = 2
        picksStack.alignment = .leading
        picksStack.distribution = .fillProportionally
        picksStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(picksStack)
```
with:
```swift
        picksStack.orientation = .vertical
        picksStack.spacing = 2
        picksStack.alignment = .leading
        picksStack.distribution = .fillProportionally
        picksStack.translatesAutoresizingMaskIntoConstraints = false

        picksScrollView.drawsBackground = false
        picksScrollView.hasVerticalScroller = true
        picksScrollView.scrollerStyle = .overlay
        picksScrollView.autohidesScrollers = true
        picksScrollView.automaticallyAdjustsContentInsets = false
        picksScrollView.translatesAutoresizingMaskIntoConstraints = false
        let picksClip = FlippedClipView()
        picksClip.drawsBackground = false
        picksScrollView.contentView = picksClip
        picksScrollView.documentView = picksStack
        addSubview(picksScrollView)

        picksStack.widthAnchor.constraint(equalTo: picksScrollView.contentView.widthAnchor).isActive = true
        picksStack.topAnchor.constraint(equalTo: picksClip.topAnchor).isActive = true
```
Note: `FlippedClipView` is already defined in the file (used by SSHManagerView). No new class needed.

**Step 3: Update constraints block (~line 12518–12525)**

Replace:
```swift
            // ── Picks list ──
            picksStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            picksStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            picksStack.topAnchor.constraint(equalTo: picksSep.bottomAnchor, constant: 5),
            // ── Feedback ──
            feedbackLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            feedbackLabel.topAnchor.constraint(equalTo: picksStack.bottomAnchor, constant: 6),
```
with:
```swift
            // ── Picks scroll view ──
            picksScrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            picksScrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            picksScrollView.topAnchor.constraint(equalTo: picksSep.bottomAnchor, constant: 5),
            picksScrollView.heightAnchor.constraint(lessThanOrEqualToConstant: 200),
            // ── Feedback ──
            feedbackLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            feedbackLabel.topAnchor.constraint(equalTo: picksScrollView.bottomAnchor, constant: 6),
```

**Step 4: Raise FIFO limit from 5 → 20 (line 12926)**

Replace:
```swift
        if picks.count >= 5, let oldest = picks.first {
```
with:
```swift
        if picks.count >= 20, let oldest = picks.first {
```

**Step 5: Update row width anchor in `onHTMLPicked` (line 12951)**

Replace:
```swift
        row.widthAnchor.constraint(equalTo: picksStack.widthAnchor).isActive = true
```
with:
```swift
        row.widthAnchor.constraint(equalTo: picksScrollView.contentView.widthAnchor).isActive = true
```

**Step 6: Build and test**
```bash
bash build.sh
```
Expected: compiles, all tests pass. Manually: connect WebPicker, pick 6+ elements → list scrolls.

**Step 7: Commit**
```bash
git add systemtrayterminal.swift
git commit -m "feat(webpicker): scrollable picks list, raise limit 5→20"
```

---

## Task 2: PickEntry Codable + Persistence (Feature 7)

**Files:**
- Modify: `systemtrayterminal.swift:12262–12264` (PickEntry struct + picks array)
- Modify: `systemtrayterminal.swift:12924` (`onHTMLPicked`)
- Modify: `systemtrayterminal.swift:12601` (`showConnectedState`)
- Modify: `systemtrayterminal.swift:12901` (`clearPickList`)
- Modify: `tests.swift` (add round-trip test)

**Step 1: Write failing test in `tests.swift`**

Add before the final `print` summary at end of tests.swift:
```swift
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
          let first = decoded.first else { fail("encode/decode failed"); return }
    expect(first.id, 3, "id survives round-trip")
    expect(first.html, "<div>test</div>", "html survives round-trip")
    expect(first.selector, "#main > div", "selector survives round-trip")
    expect(first.xpath, "body/main/div", "xpath survives round-trip")
}
```

**Step 2: Run tests to verify new test fails**
```bash
swift tests.swift 2>&1 | tail -5
```
Expected: the new test passes immediately (it's pure Swift Codable, no stubs needed) — but confirms the struct compiles. If it fails, fix before proceeding.

**Step 3: Extend `PickEntry` and add `PickEntryRecord` in main file**

Replace the PickEntry struct at line 12262:
```swift
    private struct PickEntry { let id: Int; let html: String; let hex: String; let color: NSColor }
```
with:
```swift
    private struct PickEntry {
        let id: Int; let html: String; let hex: String; let color: NSColor
        var selector: String = ""; var innerText: String = ""; var xpath: String = ""
    }
    private struct PickEntryRecord: Codable {
        let id: Int; let html: String; let hex: String
        let selector: String; let innerText: String; let xpath: String
    }
    private static let picksKey = "webPickerPicks"
```

**Step 4: Add persistence helpers after `clearPickList()` (around line 12908)**

Insert after the closing `}` of `clearPickList()`:
```swift
    private func savePicksToDisk() {
        let records = picks.map { PickEntryRecord(id: $0.id, html: $0.html, hex: $0.hex,
                                                  selector: $0.selector, innerText: $0.innerText, xpath: $0.xpath) }
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: Self.picksKey)
        }
    }

    private func restorePicksFromDisk() {
        guard let data = UserDefaults.standard.data(forKey: Self.picksKey),
              let records = try? JSONDecoder().decode([PickEntryRecord].self, from: data) else { return }
        for r in records {
            let colorIdx = r.id % Self.pickColors.count
            let (color, _) = Self.pickColors[colorIdx]
            var entry = PickEntry(id: r.id, html: r.html, hex: r.hex, color: color)
            entry.selector = r.selector; entry.innerText = r.innerText; entry.xpath = r.xpath
            picks.append(entry)
            nextPickId = max(nextPickId, r.id + 1)
            addPickRow(entry: entry)
            // Re-apply marker in Chrome (best-effort, element may no longer exist)
            cdp.evaluate("(function(){var e=document.querySelector(\(jsonString(r.selector)));if(e)e.setAttribute('data-qt-pick-\(r.id)','1');})()", completion: { _ in })
        }
        if !picks.isEmpty {
            picksHeaderLabel.isHidden = false; picksSep.isHidden = false; clearPicksBtn.isHidden = false
        }
    }
```

Also add this helper below:
```swift
    private func jsonString(_ s: String) -> String {
        // Produces a JSON-safe quoted string for injection into JS evaluate calls
        let escaped = s.replacingOccurrences(of: "\\", with: "\\\\")
                       .replacingOccurrences(of: "\"", with: "\\\"")
                       .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }
```

**Step 5: Extract row-creation into helper `addPickRow(entry:)`**

In `onHTMLPicked`, the row creation block is duplicated between first-add and restore. Extract it:

After `jsonString` helper, add:
```swift
    private func addPickRow(entry: PickEntry) {
        let id = entry.id; let hex = entry.hex; let color = entry.color
        let row = PickRowView(html: entry.html, color: color)
        row.onHighlight   = { [weak self] in self?.highlightPick(id: id, hex: hex) }
        row.onUnhighlight = { [weak self] in self?.unhighlightPick(id: id) }
        row.onCopied      = { [weak self] in self?.showCopiedFeedback() }
        row.onRemove = { [weak self] in
            guard let self = self else { return }
            self.cdp.evaluate("var e=document.querySelector('[data-qt-pick-\(id)]');if(e)e.removeAttribute('data-qt-pick-\(id)');") { _ in }
            self.picks.removeAll { $0.id == id }
            row.removeFromSuperview()
            self.savePicksToDisk()
        }
        picksStack.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: picksScrollView.contentView.widthAnchor).isActive = true
    }
```

**Step 6: Simplify `onHTMLPicked` to use `addPickRow` and call `savePicksToDisk`**

Replace the row-creation block in `onHTMLPicked` (lines 12939–12951):
```swift
        // Add row to picks list
        let row = PickRowView(html: html, color: color)
        row.onHighlight   = { [weak self] in self?.highlightPick(id: id, hex: hex) }
        row.onUnhighlight = { [weak self] in self?.unhighlightPick(id: id) }
        row.onCopied      = { [weak self] in self?.showCopiedFeedback() }
        row.onRemove = { [weak self] in
            guard let self = self else { return }
            self.cdp.evaluate("var e=document.querySelector('[data-qt-pick-\(id)]');if(e)e.removeAttribute('data-qt-pick-\(id)');") { _ in }
            self.picks.removeAll { $0.id == id }
            row.removeFromSuperview()
        }
        picksStack.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: picksStack.widthAnchor).isActive = true
```
with:
```swift
        addPickRow(entry: picks.last!)
        savePicksToDisk()
```

**Step 7: Call `restorePicksFromDisk()` in `showConnectedState`**

In `showConnectedState(hostname:navigating:)` (around line 12601), after `previewSep.isHidden = false`, add:
```swift
        if picks.isEmpty { restorePicksFromDisk() }
```

**Step 8: Clear UserDefaults in `clearPickList()`**

After `clearPicksBtn.isHidden = true` in `clearPickList()`, add:
```swift
        UserDefaults.standard.removeObject(forKey: Self.picksKey)
```

**Step 9: Build and run tests**
```bash
bash build.sh
```
Expected: all tests pass including new round-trip test.

**Step 10: Commit**
```bash
git add systemtrayterminal.swift tests.swift
git commit -m "feat(webpicker): picks persistence — save/restore across disconnect"
```

---

## Task 3: CSS Selector + Copy Formats (Features 1 + 6)

**Files:**
- Modify: `systemtrayterminal.swift:12835–12875` (pickerJS — extend to capture meta)
- Modify: `systemtrayterminal.swift:12876–12888` (polling loop — read meta too)
- Modify: `systemtrayterminal.swift:12924` (`onHTMLPicked` — accept meta)
- Modify: `systemtrayterminal.swift:12106` (`PickRowView` — add right-click callback)
- Modify: `systemtrayterminal.swift:12940` (`addPickRow` — wire right-click)

**Step 1: Extend pickerJS to also capture selector/innerText/xpath**

In `startPicking()`, find this line inside the JS (around line 12865):
```js
            window.__qtPickedHTML=e.target.outerHTML; window.__qtPickerActive=false;
```
Replace with:
```js
            window.__qtPickedHTML=e.target.outerHTML;
            window.__qtPickedMeta=(function(el){
              function sel(el){
                if(el.id)return'#'+CSS.escape(el.id);
                var p=[];
                while(el&&el.nodeType===1&&el!==document.body){
                  var seg=el.tagName.toLowerCase();
                  var sib=[].filter.call(el.parentElement?el.parentElement.children:[],function(s){return s.tagName===el.tagName;});
                  if(sib.length>1)seg+=':nth-child('+([].indexOf.call(el.parentElement.children,el)+1)+')';
                  if(el.classList.length)seg+='.'+[].slice.call(el.classList,0,2).map(function(c){return CSS.escape(c);}).join('.');
                  if(el.id){p.unshift('#'+CSS.escape(el.id));break;}
                  p.unshift(seg);el=el.parentElement;
                }
                return p.join(' > ');
              }
              function xp(el){
                var parts=[];
                while(el&&el.nodeType===1){
                  var idx=[].filter.call(el.parentNode?el.parentNode.children:[],function(s){return s.tagName===el.tagName;}).indexOf(el)+1;
                  parts.unshift(el.tagName.toLowerCase()+(idx>1?'['+idx+']':''));
                  el=el.parentNode;
                  if(el===document.body){parts.unshift('body');break;}
                }
                return '/'+parts.join('/');
              }
              return {selector:sel(el),innerText:(el.innerText||'').trim().substring(0,500),xpath:xp(el)};
            })(e.target);
            window.__qtPickerActive=false;
```

**Step 2: Extend the polling query to also read meta**

Replace the polling evaluate call (line 12880):
```swift
                self?.cdp.evaluate("typeof window.__qtPickedHTML!=='undefined'&&window.__qtPickedHTML!==null?window.__qtPickedHTML:null") { [weak self] result in
                    guard let self = self,
                          let inner = (result?["result"] as? [String: Any]),
                          let val = inner["value"] as? String, !val.isEmpty else { return }
                    self.pollTimer?.invalidate(); self.pollTimer = nil
                    self.onHTMLPicked(val)
```
with:
```swift
                self?.cdp.evaluate("""
                    (function(){
                      if(typeof window.__qtPickedHTML==='undefined'||window.__qtPickedHTML===null)return null;
                      return JSON.stringify({html:window.__qtPickedHTML,meta:window.__qtPickedMeta||{}});
                    })()
                    """) { [weak self] result in
                    guard let self = self,
                          let inner = (result?["result"] as? [String: Any]),
                          let jsonStr = inner["value"] as? String, !jsonStr.isEmpty,
                          let data = jsonStr.data(using: .utf8),
                          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let html = obj["html"] as? String, !html.isEmpty else { return }
                    self.pollTimer?.invalidate(); self.pollTimer = nil
                    let meta = obj["meta"] as? [String: Any] ?? [:]
                    let selector = meta["selector"] as? String ?? ""
                    let innerText = meta["innerText"] as? String ?? ""
                    let xpath     = meta["xpath"] as? String ?? ""
                    self.onHTMLPicked(html, selector: selector, innerText: innerText, xpath: xpath)
```

**Step 3: Update `onHTMLPicked` signature and PickEntry construction**

Replace:
```swift
    private func onHTMLPicked(_ html: String) {
```
with:
```swift
    private func onHTMLPicked(_ html: String, selector: String = "", innerText: String = "", xpath: String = "") {
```

And replace the `picks.append` line:
```swift
        picks.append(PickEntry(id: id, html: html, hex: hex, color: color))
```
with:
```swift
        var entry = PickEntry(id: id, html: html, hex: hex, color: color)
        entry.selector = selector; entry.innerText = innerText; entry.xpath = xpath
        picks.append(entry)
```

**Step 4: Add right-click callback to `PickRowView`**

In `PickRowView` class (around line 12106), add property:
```swift
    var onRightClick: ((_ html: String, _ selector: String, _ innerText: String, _ xpath: String) -> Void)?
```

Add `mouseDown` override that checks for right-click:
After the existing `mouseDown(with:)` method, add:
```swift
    override func rightMouseDown(with event: NSEvent) {
        onRightClick?(html, selector, innerText, xpath)
    }
```

Store selector/innerText/xpath as properties in PickRowView:
```swift
    private var selector: String = ""
    private var innerText: String = ""
    private var xpath: String = ""
```

Update `PickRowView.init` to accept and store them:
```swift
    init(html: String, color: NSColor, selector: String = "", innerText: String = "", xpath: String = "") {
        self.html = html
        self.selector = selector
        self.innerText = innerText
        self.xpath = xpath
        ...
    }
```

**Step 5: Update `addPickRow(entry:)` to pass meta to PickRowView and wire right-click**

Replace the `let row = PickRowView(html: entry.html, color: color)` line:
```swift
        let row = PickRowView(html: entry.html, color: color,
                              selector: entry.selector, innerText: entry.innerText, xpath: entry.xpath)
        row.onRightClick = { [weak self] html, selector, innerText, xpath in
            self?.showPickContextMenu(html: html, selector: selector, innerText: innerText, xpath: xpath, pickId: id)
        }
```

**Step 6: Add `showPickContextMenu` method**

Add before `showCopiedFeedback()`:
```swift
    private func showPickContextMenu(html: String, selector: String, innerText: String, xpath: String, pickId: Int) {
        let menu = NSMenu()
        let htmlItem = NSMenuItem(title: "outerHTML", action: #selector(menuCopyHTML(_:)), keyEquivalent: "")
        htmlItem.representedObject = html
        htmlItem.target = self
        let textItem = NSMenuItem(title: "innerText", action: #selector(menuCopyText(_:)), keyEquivalent: "")
        textItem.representedObject = innerText
        textItem.target = self
        let selectorItem = NSMenuItem(title: "CSS Selector", action: #selector(menuCopyText(_:)), keyEquivalent: "")
        selectorItem.representedObject = selector
        selectorItem.target = self
        let xpathItem = NSMenuItem(title: "XPath", action: #selector(menuCopyText(_:)), keyEquivalent: "")
        xpathItem.representedObject = xpath
        xpathItem.target = self
        menu.addItem(htmlItem)
        menu.addItem(textItem)
        menu.addItem(selectorItem)
        menu.addItem(xpathItem)
        menu.addItem(NSMenuItem.separator())
        let ssItem = NSMenuItem(title: "Screenshot kopieren", action: #selector(menuScreenshot(_:)), keyEquivalent: "")
        ssItem.representedObject = pickId
        ssItem.target = self
        menu.addItem(ssItem)
        // Popup at current mouse location
        NSMenu.popUpContextMenu(menu, with: NSApp.currentEvent ?? NSEvent(), for: self)
    }

    @objc private func menuCopyHTML(_ item: NSMenuItem) {
        guard let s = item.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
        showCopiedFeedback()
    }

    @objc private func menuCopyText(_ item: NSMenuItem) {
        guard let s = item.representedObject as? String, !s.isEmpty else {
            feedbackLabel.stringValue = "–– not available"; feedbackLabel.isHidden = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.feedbackLabel.isHidden = true }
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
        showCopiedFeedback()
    }

    @objc private func menuScreenshot(_ item: NSMenuItem) {
        guard let pickId = item.representedObject as? Int else { return }
        triggerElementScreenshot(pickId: pickId)
    }
```

**Step 7: Build**
```bash
bash build.sh
```
Expected: compiles, tests pass. Manual: pick element → right-click row → CSS Selector in menu → copies to clipboard.

**Step 8: Commit**
```bash
git add systemtrayterminal.swift
git commit -m "feat(webpicker): CSS selector/XPath extraction, right-click copy format menu"
```

---

## Task 4: Chrome Tab Switcher (Feature 4)

**Files:**
- Modify: `systemtrayterminal.swift:12252–12253` (add tab switcher properties near urlBg)
- Modify: `systemtrayterminal.swift:setupUI()` — URL bar area
- Modify: `systemtrayterminal.swift:12486–12495` (URL bar constraints)

**Step 1: Add new properties near urlBg declaration (line 12252)**

After `private let urlField = NSTextField()`, add:
```swift
    private let tabSwitcherBtn    = NSButton()
    private let hotReloadBtn      = NSButton()
    private let tabBox            = NSView()
    private var tabBoxH: NSLayoutConstraint!
    private var tabBoxVisible     = false
```

**Step 2: In `setupUI()`, configure the two icon buttons and reduced urlField width**

Find the urlBg/urlField setup section (around line 12372–12395). After the urlField setup, add:
```swift
        // ── Tab switcher button ──
        tabSwitcherBtn.title = "⊞"
        tabSwitcherBtn.font = NSFont.systemFont(ofSize: 11)
        tabSwitcherBtn.isBordered = false
        tabSwitcherBtn.toolTip = "Switch Chrome tab"
        tabSwitcherBtn.contentTintColor = NSColor(calibratedWhite: 0.45, alpha: 1)
        tabSwitcherBtn.target = self; tabSwitcherBtn.action = #selector(toggleTabSwitcher)
        tabSwitcherBtn.isHidden = true
        tabSwitcherBtn.translatesAutoresizingMaskIntoConstraints = false
        addSubview(tabSwitcherBtn)

        // ── Hot reload button ──
        hotReloadBtn.title = "⟳"
        hotReloadBtn.font = NSFont.systemFont(ofSize: 12)
        hotReloadBtn.isBordered = false
        hotReloadBtn.toolTip = "Toggle hot reload"
        hotReloadBtn.contentTintColor = NSColor(calibratedWhite: 0.45, alpha: 1)
        hotReloadBtn.target = self; hotReloadBtn.action = #selector(toggleHotReload)
        hotReloadBtn.isHidden = true
        hotReloadBtn.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hotReloadBtn)
```

**Step 3: Update URL bar constraints to shorten urlField and add 2 buttons**

Replace the URL bar constraints block (lines 12488–12495):
```swift
            urlBg.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            urlBg.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            urlBg.topAnchor.constraint(equalTo: statusDot.bottomAnchor, constant: 8),
            urlBg.heightAnchor.constraint(equalToConstant: 24),
            urlField.leadingAnchor.constraint(equalTo: urlBg.leadingAnchor, constant: 10),
            urlField.trailingAnchor.constraint(equalTo: urlBg.trailingAnchor, constant: -8),
            urlField.topAnchor.constraint(equalTo: urlBg.topAnchor),
            urlField.bottomAnchor.constraint(equalTo: urlBg.bottomAnchor),
```
with:
```swift
            urlBg.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            urlBg.trailingAnchor.constraint(equalTo: hotReloadBtn.leadingAnchor, constant: -4),
            urlBg.topAnchor.constraint(equalTo: statusDot.bottomAnchor, constant: 8),
            urlBg.heightAnchor.constraint(equalToConstant: 24),
            urlField.leadingAnchor.constraint(equalTo: urlBg.leadingAnchor, constant: 10),
            urlField.trailingAnchor.constraint(equalTo: urlBg.trailingAnchor, constant: -8),
            urlField.topAnchor.constraint(equalTo: urlBg.topAnchor),
            urlField.bottomAnchor.constraint(equalTo: urlBg.bottomAnchor),
            // ── Tab switcher + hot reload buttons ──
            hotReloadBtn.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            hotReloadBtn.centerYAnchor.constraint(equalTo: urlBg.centerYAnchor),
            hotReloadBtn.widthAnchor.constraint(equalToConstant: 20),
            tabSwitcherBtn.trailingAnchor.constraint(equalTo: hotReloadBtn.leadingAnchor, constant: -4),
            tabSwitcherBtn.centerYAnchor.constraint(equalTo: urlBg.centerYAnchor),
            tabSwitcherBtn.widthAnchor.constraint(equalToConstant: 20),
```

**Step 4: Add tab dropdown overlay after suggestBox setup (end of setupUI, before showDisconnectedState)**

After `suggestBoxH.isActive = true`, add:
```swift
        // ── Tab switcher dropdown (added last, floats on top) ──
        tabBox.wantsLayer = true
        tabBox.layer?.backgroundColor = NSColor(calibratedWhite: 0.10, alpha: 0.97).cgColor
        tabBox.layer?.cornerRadius = 5
        tabBox.layer?.borderColor = NSColor(calibratedWhite: 0.22, alpha: 1).cgColor
        tabBox.layer?.borderWidth = 0.5
        tabBox.isHidden = true
        tabBox.translatesAutoresizingMaskIntoConstraints = false
        addSubview(tabBox)
        NSLayoutConstraint.activate([
            tabBox.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            tabBox.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            tabBox.topAnchor.constraint(equalTo: urlBg.bottomAnchor, constant: 2),
        ])
        tabBoxH = tabBox.heightAnchor.constraint(equalToConstant: 0)
        tabBoxH.isActive = true
```

**Step 5: Show/hide tab+hotreload buttons with connection state**

In `showConnectedState(hostname:navigating:)`, after `urlBg.isHidden = false`, add:
```swift
        tabSwitcherBtn.isHidden = false
        hotReloadBtn.isHidden = false
```

In `showDisconnectedState()` and `showConnectingState(_:)`, add:
```swift
        tabSwitcherBtn.isHidden = true
        hotReloadBtn.isHidden = true
```

**Step 6: Implement tab switcher logic**

Add after `openDebugJSON()`:
```swift
    @objc private func toggleTabSwitcher() {
        if tabBoxVisible { hideTabBox(); return }
        tabBoxVisible = true
        tabBox.subviews.forEach { $0.removeFromSuperview() }
        Task { [weak self] in
            guard let self = self else { return }
            guard let url = URL(string: "http://localhost:\(ChromeCDPClient.debugPort)/json/list") else { return }
            var req = URLRequest(url: url); req.timeoutInterval = 3
            guard let data = try? await URLSession.shared.fetchData(for: req),
                  let tabs = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
            let pages = tabs.filter { ($0["type"] as? String) == "page" }.prefix(8)
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                let rowH: CGFloat = 24
                for (i, tab) in pages.enumerated() {
                    let title = tab["title"] as? String ?? ""
                    let tabURL = tab["url"] as? String ?? ""
                    let tabId  = tab["id"] as? String ?? ""
                    let wsURL  = tab["webSocketDebuggerUrl"] as? String ?? ""
                    let isActive = tabId == self.currentTargetId
                    let btn = NSButton(title: "\(isActive ? "▶ " : "  ")\(title.isEmpty ? tabURL : title)",
                                       target: self, action: #selector(self.selectTab(_:)))
                    btn.isBordered = false
                    btn.alignment = .left
                    btn.font = NSFont.monospacedSystemFont(ofSize: 9, weight: isActive ? .semibold : .regular)
                    btn.contentTintColor = isActive ? Self.teal : NSColor(calibratedWhite: 0.72, alpha: 1)
                    btn.lineBreakMode = .byTruncatingTail
                    btn.toolTip = tabURL
                    btn.identifier = NSUserInterfaceItemIdentifier(rawValue: wsURL)
                    btn.translatesAutoresizingMaskIntoConstraints = false
                    self.tabBox.addSubview(btn)
                    NSLayoutConstraint.activate([
                        btn.leadingAnchor.constraint(equalTo: self.tabBox.leadingAnchor, constant: 6),
                        btn.trailingAnchor.constraint(equalTo: self.tabBox.trailingAnchor, constant: -6),
                        btn.topAnchor.constraint(equalTo: self.tabBox.topAnchor, constant: CGFloat(i) * rowH + 2),
                        btn.heightAnchor.constraint(equalToConstant: rowH),
                    ])
                }
                self.tabBoxH.constant = CGFloat(pages.count) * rowH + 4
                self.tabBox.isHidden = false
            }
        }
    }

    private func hideTabBox() {
        tabBoxVisible = false
        tabBox.isHidden = true
        tabBox.subviews.forEach { $0.removeFromSuperview() }
        tabBoxH.constant = 0
    }

    @objc private func selectTab(_ sender: NSButton) {
        let wsURL = sender.identifier?.rawValue ?? ""
        hideTabBox()
        guard !wsURL.isEmpty else { return }
        // Disconnect from current tab (soft — no cleanup) and connect to selected tab
        cdp.disconnect()
        isConnected = false
        doConnect(to: wsURL)
    }
```

**Step 7: Hide tab box when navigating or disconnecting**

Add `hideTabBox()` calls in `showDisconnectedState()`, `disconnect()`, and `softDisconnect()`.

**Step 8: Build**
```bash
bash build.sh
```
Expected: compiles, tests pass. Manual: connect → click ⊞ → tab list dropdown appears → click tab → reconnects.

**Step 9: Commit**
```bash
git add systemtrayterminal.swift
git commit -m "feat(webpicker): Chrome tab switcher dropdown"
```

---

## Task 5: Hot Reload (Feature 9)

**Files:**
- Modify: `systemtrayterminal.swift` — add properties, methods, hook into disconnect/deinit

**Step 1: Add Hot Reload properties after `tabBoxVisible` declaration**

```swift
    // ── Hot Reload ──
    private var hotReloadEnabled  = false
    private var fileWatcher: DispatchSourceFileSystemObject?
    private var hotReloadPollTimer: Timer?
    private var watchedPath: String?
    private var watchedFileMtimes: [String: Date] = [:]
    private var watchedFileCount  = 0
    private let watchRow          = NSView()
    private let watchFolderBtn    = NSButton()
    private let watchStatusLabel  = NSTextField(labelWithString: "")
    private var watchRowH: NSLayoutConstraint!
    private static let watchFolderKey = "webPickerWatchFolder"
```

**Step 2: Add watch row UI in setupUI(), after tab dropdown setup**

Add before `showDisconnectedState()`:
```swift
        // ── Watch row (appears under URL bar when hot reload active on localhost) ──
        watchRow.isHidden = true
        watchRow.translatesAutoresizingMaskIntoConstraints = false
        addSubview(watchRow)

        watchFolderBtn.title = "📁"
        watchFolderBtn.isBordered = false
        watchFolderBtn.font = NSFont.systemFont(ofSize: 11)
        watchFolderBtn.toolTip = "Select project folder to watch"
        watchFolderBtn.target = self; watchFolderBtn.action = #selector(selectWatchFolder)
        watchFolderBtn.translatesAutoresizingMaskIntoConstraints = false
        watchRow.addSubview(watchFolderBtn)

        watchStatusLabel.font = NSFont.monospacedSystemFont(ofSize: 8.5, weight: .regular)
        watchStatusLabel.textColor = Self.teal.withAlphaComponent(0.7)
        watchStatusLabel.lineBreakMode = .byTruncatingHead
        watchStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        watchRow.addSubview(watchStatusLabel)

        NSLayoutConstraint.activate([
            watchRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            watchRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            watchRow.topAnchor.constraint(equalTo: urlBg.bottomAnchor, constant: 2),
            watchFolderBtn.leadingAnchor.constraint(equalTo: watchRow.leadingAnchor),
            watchFolderBtn.centerYAnchor.constraint(equalTo: watchRow.centerYAnchor),
            watchFolderBtn.widthAnchor.constraint(equalToConstant: 22),
            watchStatusLabel.leadingAnchor.constraint(equalTo: watchFolderBtn.trailingAnchor, constant: 4),
            watchStatusLabel.trailingAnchor.constraint(equalTo: watchRow.trailingAnchor),
            watchStatusLabel.centerYAnchor.constraint(equalTo: watchRow.centerYAnchor),
        ])
        watchRowH = watchRow.heightAnchor.constraint(equalToConstant: 0)
        watchRowH.isActive = true
```

Also update the `pickBtn` top constraint to use `watchRow` instead of `urlBg`:
Replace:
```swift
            pickBtn.topAnchor.constraint(equalTo: urlBg.bottomAnchor, constant: 8),
            connectBtn.topAnchor.constraint(equalTo: urlBg.bottomAnchor, constant: 8),
```
with:
```swift
            pickBtn.topAnchor.constraint(equalTo: watchRow.bottomAnchor, constant: 6),
            connectBtn.topAnchor.constraint(equalTo: urlBg.bottomAnchor, constant: 8),
```

**Step 3: Implement hot reload toggle**

Add after `selectTab(_:)`:
```swift
    @objc private func toggleHotReload() {
        hotReloadEnabled = !hotReloadEnabled
        if hotReloadEnabled {
            hotReloadBtn.contentTintColor = Self.teal
            startAutoDetectWatch()
        } else {
            hotReloadBtn.contentTintColor = NSColor(calibratedWhite: 0.45, alpha: 1)
            stopWatching()
            hideWatchRow()
        }
    }

    private func startAutoDetectWatch() {
        guard let tid = currentTargetId else { hideWatchRow(); return }
        Task { [weak self] in
            guard let self = self else { return }
            let hostname = await self.cdp.getTabHostname(targetId: tid)
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                // Try to get current URL from /json/list
                Task { [weak self] in
                    guard let self = self,
                          let url = URL(string: "http://localhost:\(ChromeCDPClient.debugPort)/json/list") else { return }
                    var req = URLRequest(url: url); req.timeoutInterval = 2
                    guard let data = try? await URLSession.shared.fetchData(for: req),
                          let tabs = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                          let tab = tabs.first(where: { ($0["id"] as? String) == self.currentTargetId }),
                          let tabURL = tab["url"] as? String else { return }
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        if tabURL.hasPrefix("file://"),
                           let path = URL(string: tabURL)?.path {
                            self.startFileWatcher(path: path)
                        } else {
                            // localhost — need folder selection
                            let saved = UserDefaults.standard.string(forKey: Self.watchFolderKey)
                            if let saved = saved, FileManager.default.fileExists(atPath: saved) {
                                self.startPollingWatcher(directory: saved)
                            } else {
                                self.showWatchRow(forLocalhost: true)
                            }
                        }
                    }
                }
            }
        }
    }

    @objc private func selectWatchFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.prompt = "Watch"
        panel.begin { [weak self] response in
            guard let self = self, response == .OK, let url = panel.url else { return }
            UserDefaults.standard.set(url.path, forKey: Self.watchFolderKey)
            self.startPollingWatcher(directory: url.path)
        }
    }

    private func startFileWatcher(path: String) {
        stopWatching()
        watchedPath = path
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else {
            watchStatusLabel.stringValue = "⚠ can't open file"; showWatchRow(forLocalhost: false); return
        }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd,
                                                            eventMask: [.write, .rename, .delete],
                                                            queue: .main)
        src.setEventHandler { [weak self] in
            guard let self = self else { return }
            // File was renamed/deleted + recreated: re-open watcher
            let mask = src.data
            if mask.contains(.delete) || mask.contains(.rename) {
                self.startFileWatcher(path: path)  // re-arm on recreated file
            } else {
                self.triggerHotReload()
            }
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        fileWatcher = src
        let name = URL(fileURLWithPath: path).lastPathComponent
        watchStatusLabel.stringValue = "● \(name)"
        showWatchRow(forLocalhost: false)
    }

    private func startPollingWatcher(directory: String) {
        stopWatching()
        watchedPath = directory
        // Snapshot current mtimes
        watchedFileMtimes = scanMtimes(directory: directory)
        watchedFileCount = watchedFileMtimes.count
        hotReloadPollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, let dir = self.watchedPath else { return }
            let current = self.scanMtimes(directory: dir)
            if current != self.watchedFileMtimes {
                self.watchedFileMtimes = current
                self.triggerHotReload()
            }
        }
        let dirName = URL(fileURLWithPath: directory).lastPathComponent
        watchStatusLabel.stringValue = "● \(watchedFileCount) files in \(dirName)"
        showWatchRow(forLocalhost: true)
    }

    private func scanMtimes(directory: String) -> [String: Date] {
        var result: [String: Date] = [:]
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: directory) else { return result }
        var depth = 0
        for case let file as String in enumerator {
            if enumerator.level > 3 { enumerator.skipDescendants(); continue }
            let fullPath = (directory as NSString).appendingPathComponent(file)
            if let attrs = try? fm.attributesOfItem(atPath: fullPath),
               let mtime = attrs[.modificationDate] as? Date {
                result[fullPath] = mtime
            }
        }
        return result
    }

    private func triggerHotReload() {
        guard hotReloadEnabled, isConnected else { return }
        cdp.cdpCommand("Page.reload", params: ["ignoreCache": true]) { _ in }
        // Brief flash on status label
        let prev = watchStatusLabel.stringValue
        watchStatusLabel.stringValue = "↺ reloaded"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.watchStatusLabel.stringValue = prev
        }
    }

    private func showWatchRow(forLocalhost: Bool) {
        watchFolderBtn.isHidden = !forLocalhost
        watchRow.isHidden = false
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            self.watchRowH.animator().constant = 20
        }
    }

    private func hideWatchRow() {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            self.watchRowH.animator().constant = 0
        } completionHandler: { [weak self] in
            self?.watchRow.isHidden = true
        }
    }

    private func stopWatching() {
        fileWatcher?.cancel(); fileWatcher = nil
        hotReloadPollTimer?.invalidate(); hotReloadPollTimer = nil
        watchedFileMtimes = [:]
        watchedPath = nil
    }
```

**Step 4: Stop watching on disconnect/deinit**

In `disconnect()` and `softDisconnect()`, add:
```swift
        stopWatching()
        hotReloadEnabled = false
        hotReloadBtn.contentTintColor = NSColor(calibratedWhite: 0.45, alpha: 1)
        hideWatchRow()
```

In `deinit`, add:
```swift
        stopWatching()
```

**Step 5: Build**
```bash
bash build.sh
```
Expected: compiles, tests pass. Manual: open `file://` page → connect → toggle ⟳ → edit file in editor → Chrome reloads automatically.

**Step 6: Commit**
```bash
git add systemtrayterminal.swift
git commit -m "feat(webpicker): hot reload — file:// watcher + localhost folder polling"
```

---

## Task 6: Computed Style Inspector (Feature 2)

**Files:**
- Modify: `systemtrayterminal.swift` — `PickRowView` class

**Step 1: Add expand state and styles view to PickRowView**

In `PickRowView` (class declaration around line 12106), add new properties:
```swift
    private var isStylesExpanded = false
    private let stylesWrap = NSView()
    private var stylesH: NSLayoutConstraint!
    private let stylesLabel = NSTextField(labelWithString: "")
    var onStylesRequested: ((Int) -> Void)?  // passes pick id
    private var pickId: Int = 0
```

Update `init` to store pickId:
```swift
    init(html: String, color: NSColor, selector: String = "", innerText: String = "", xpath: String = "", pickId: Int = 0) {
        ...
        self.pickId = pickId
    }
```

In `setupRow(profile:)` (or equivalent in PickRowView), after adding all current subviews, add:
```swift
        // ── Styles expand area ──
        stylesWrap.wantsLayer = true
        stylesWrap.layer?.masksToBounds = true
        stylesWrap.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stylesWrap)

        stylesLabel.font = NSFont.monospacedSystemFont(ofSize: 7.5, weight: .regular)
        stylesLabel.textColor = NSColor(calibratedWhite: 0.55, alpha: 1)
        stylesLabel.maximumNumberOfLines = 2
        stylesLabel.translatesAutoresizingMaskIntoConstraints = false
        stylesWrap.addSubview(stylesLabel)

        NSLayoutConstraint.activate([
            stylesWrap.leadingAnchor.constraint(equalTo: leadingAnchor),
            stylesWrap.trailingAnchor.constraint(equalTo: trailingAnchor),
            stylesWrap.topAnchor.constraint(equalTo: bottomAnchor),
            stylesLabel.leadingAnchor.constraint(equalTo: stylesWrap.leadingAnchor, constant: 12),
            stylesLabel.trailingAnchor.constraint(equalTo: stylesWrap.trailingAnchor, constant: -8),
            stylesLabel.centerYAnchor.constraint(equalTo: stylesWrap.centerYAnchor),
        ])
        stylesH = stylesWrap.heightAnchor.constraint(equalToConstant: 0)
        stylesH.isActive = true
```

**Step 2: Toggle styles on mouseDown (not on x button)**

In `mouseDown(with:)` of PickRowView, add toggle logic:
```swift
    override func mouseDown(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        if !xBtn.frame.contains(pt) {
            if isStylesExpanded {
                collapseStyles()
            } else {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(html, forType: .string)
                onCopied?()
                onStylesRequested?(pickId)
            }
        }
        super.mouseDown(with: event)
    }
```

**Step 3: Add `showStyles(text:)` and `collapseStyles()` methods to PickRowView**

```swift
    func showStyles(text: String) {
        stylesLabel.stringValue = text
        isStylesExpanded = true
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            self.stylesH.animator().constant = 34
        }
    }

    func collapseStyles() {
        isStylesExpanded = false
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            self.stylesH.animator().constant = 0
        }
    }
```

**Step 4: Wire `onStylesRequested` in `addPickRow(entry:)`**

```swift
        row.onStylesRequested = { [weak self] _ in
            self?.fetchComputedStyle(pickId: id)
        }
```

**Step 5: Add `fetchComputedStyle` to `WebPickerSidebarView`**

```swift
    private func fetchComputedStyle(pickId: Int) {
        let js = """
        (function(){
          var el=document.querySelector('[data-qt-pick-\(pickId)]');
          if(!el)return null;
          var s=getComputedStyle(el);
          var ff=s.fontFamily.split(',')[0].replace(/['"]/g,'').trim();
          return s.fontSize+' '+ff+' | '+s.color+' bg:'+s.backgroundColor+' | pad:'+s.padding+(s.borderRadius!=='0px'?' r:'+s.borderRadius:'');
        })()
        """
        cdp.evaluate(js) { [weak self] result in
            guard let self = self,
                  let inner = result?["result"] as? [String: Any],
                  let text = inner["value"] as? String else { return }
            // Find the row for this pickId and show styles
            let rows = self.picksStack.arrangedSubviews.compactMap { $0 as? PickRowView }
            rows.first(where: { $0.currentPickId == pickId })?.showStyles(text: text)
        }
    }
```

Also expose `currentPickId` from PickRowView:
```swift
    var currentPickId: Int { pickId }
```

**Step 6: Build**
```bash
bash build.sh
```
Manual: pick element → click row → shows font/color/padding inline below the row.

**Step 7: Commit**
```bash
git add systemtrayterminal.swift
git commit -m "feat(webpicker): computed style inspector — click pick row to expand"
```

---

## Task 7: JS Mini-REPL (Feature 3)

**Files:**
- Modify: `systemtrayterminal.swift` — `WebPickerSidebarView` properties + setupUI + new methods

**Step 1: Add REPL properties**

After `watchRowH` declaration, add:
```swift
    // ── JS REPL ──
    private var replExpanded      = false
    private let replBtn           = NSButton()
    private let replWrap          = NSView()
    private var replHeightC: NSLayoutConstraint!
    private let replField         = NSTextField()
    private let replResultLabel   = NSTextField(labelWithString: "")
    private var replHistory: [String] = []
    private var replHistoryIdx    = -1
    private static let replH: CGFloat = 56
```

**Step 2: Add replBtn to title bar in setupUI()**

Add after `closeBtn` setup in setupUI():
```swift
        replBtn.title = "</>"
        replBtn.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .medium)
        replBtn.isBordered = false
        replBtn.contentTintColor = NSColor(calibratedWhite: 0.35, alpha: 1)
        replBtn.toolTip = "Toggle JS REPL"
        replBtn.target = self; replBtn.action = #selector(toggleREPL)
        replBtn.isHidden = true
        replBtn.translatesAutoresizingMaskIntoConstraints = false
        addSubview(replBtn)
```

Add to the title bar constraints (after `moveUpBtn` constraints):
```swift
            replBtn.trailingAnchor.constraint(equalTo: moveUpBtn.leadingAnchor, constant: -4),
            replBtn.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            replBtn.widthAnchor.constraint(equalToConstant: 26),
```

**Step 3: Add REPL panel UI at end of setupUI() (after tabBox, before showDisconnectedState)**

```swift
        // ── JS REPL panel ──
        replWrap.wantsLayer = true
        replWrap.layer?.masksToBounds = true
        replWrap.translatesAutoresizingMaskIntoConstraints = false
        addSubview(replWrap)

        let replInner = NSView()
        replInner.wantsLayer = true
        replInner.layer?.backgroundColor = NSColor(calibratedWhite: 1.0, alpha: 0.03).cgColor
        replInner.layer?.borderColor = NSColor(calibratedWhite: 1, alpha: 0.07).cgColor
        replInner.layer?.borderWidth = 1
        replInner.translatesAutoresizingMaskIntoConstraints = false
        replWrap.addSubview(replInner)

        let replPrompt = NSTextField(labelWithString: "›")
        replPrompt.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        replPrompt.textColor = Self.teal
        replPrompt.translatesAutoresizingMaskIntoConstraints = false
        replInner.addSubview(replPrompt)

        let replCell = VertCenteredTextFieldCell(textCell: "")
        replCell.placeholderString = "document.title"
        replCell.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        replCell.textColor = NSColor(calibratedWhite: 0.9, alpha: 1)
        replCell.isBezeled = false; replCell.isEditable = true
        replCell.drawsBackground = false; replCell.focusRingType = .none
        replField.cell = replCell
        replField.target = self; replField.action = #selector(evaluateREPL)
        replField.delegate = self
        replField.translatesAutoresizingMaskIntoConstraints = false
        replInner.addSubview(replField)

        replResultLabel.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .regular)
        replResultLabel.textColor = Self.teal.withAlphaComponent(0.8)
        replResultLabel.maximumNumberOfLines = 1
        replResultLabel.lineBreakMode = .byTruncatingTail
        replResultLabel.translatesAutoresizingMaskIntoConstraints = false
        replInner.addSubview(replResultLabel)

        NSLayoutConstraint.activate([
            replWrap.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            replWrap.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            replWrap.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            replInner.topAnchor.constraint(equalTo: replWrap.topAnchor),
            replInner.leadingAnchor.constraint(equalTo: replWrap.leadingAnchor),
            replInner.trailingAnchor.constraint(equalTo: replWrap.trailingAnchor),
            replInner.heightAnchor.constraint(equalToConstant: Self.replH),
            replPrompt.leadingAnchor.constraint(equalTo: replInner.leadingAnchor, constant: 8),
            replPrompt.topAnchor.constraint(equalTo: replInner.topAnchor, constant: 6),
            replPrompt.widthAnchor.constraint(equalToConstant: 14),
            replField.leadingAnchor.constraint(equalTo: replPrompt.trailingAnchor, constant: 4),
            replField.trailingAnchor.constraint(equalTo: replInner.trailingAnchor, constant: -8),
            replField.topAnchor.constraint(equalTo: replInner.topAnchor, constant: 4),
            replField.heightAnchor.constraint(equalToConstant: 22),
            replResultLabel.leadingAnchor.constraint(equalTo: replInner.leadingAnchor, constant: 10),
            replResultLabel.trailingAnchor.constraint(equalTo: replInner.trailingAnchor, constant: -8),
            replResultLabel.topAnchor.constraint(equalTo: replField.bottomAnchor, constant: 4),
        ])
        replHeightC = replWrap.heightAnchor.constraint(equalToConstant: 0)
        replHeightC.isActive = true
```

**Step 4: Implement REPL toggle and evaluate**

```swift
    @objc private func toggleREPL() {
        replExpanded = !replExpanded
        replBtn.contentTintColor = replExpanded ? Self.teal : NSColor(calibratedWhite: 0.35, alpha: 1)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
            self.replHeightC.animator().constant = self.replExpanded ? Self.replH : 0
        }
        if replExpanded { window?.makeFirstResponder(replField) }
    }

    @objc private func evaluateREPL() {
        let expr = replField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !expr.isEmpty, isConnected else { return }
        replHistory.insert(expr, at: 0)
        if replHistory.count > 20 { replHistory.removeLast() }
        replHistoryIdx = -1
        replResultLabel.textColor = Self.teal.withAlphaComponent(0.8)
        replResultLabel.stringValue = "…"
        cdp.evaluate(expr) { [weak self] result in
            guard let self = self else { return }
            if let inner = result?["result"] as? [String: Any] {
                if let exc = result?["exceptionDetails"] as? [String: Any],
                   let msg = (exc["exception"] as? [String: Any])?["description"] as? String {
                    self.replResultLabel.textColor = NSColor(calibratedRed: 0.9, green: 0.35, blue: 0.35, alpha: 1)
                    self.replResultLabel.stringValue = "✕ \(msg)"
                } else {
                    let t = inner["type"] as? String ?? ""
                    let val: String
                    switch t {
                    case "undefined": val = "undefined"
                    case "null":      val = "null"
                    case "string":    val = "\"\(inner["value"] as? String ?? "")\""
                    case "number":    val = "\(inner["value"] ?? "?")"
                    case "boolean":   val = "\(inner["value"] ?? "?")"
                    case "object":
                        if let sub = inner["subtype"] as? String, sub == "null" { val = "null" }
                        else { val = inner["description"] as? String ?? "{…}" }
                    default:          val = inner["description"] as? String ?? t
                    }
                    self.replResultLabel.textColor = Self.teal.withAlphaComponent(0.8)
                    self.replResultLabel.stringValue = "= \(val)"
                }
            } else {
                self.replResultLabel.textColor = NSColor(calibratedWhite: 0.4, alpha: 1)
                self.replResultLabel.stringValue = "– no response"
            }
        }
    }
```

**Step 5: Handle ↑/↓ history navigation in NSTextFieldDelegate**

In the existing `extension WebPickerSidebarView: NSTextFieldDelegate`, add:
```swift
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard control === replField else { return false }
        if commandSelector == #selector(moveUp(_:)) {
            let next = min(replHistoryIdx + 1, replHistory.count - 1)
            if next >= 0 { replHistoryIdx = next; replField.stringValue = replHistory[next] }
            return true
        }
        if commandSelector == #selector(moveDown(_:)) {
            let next = replHistoryIdx - 1
            if next < 0 { replHistoryIdx = -1; replField.stringValue = "" }
            else { replHistoryIdx = next; replField.stringValue = replHistory[next] }
            return true
        }
        return false
    }
```

**Step 6: Show/hide replBtn with connection state**

In `showConnectedState`, add: `replBtn.isHidden = false`
In `showDisconnectedState` and `showConnectingState`, add: `replBtn.isHidden = true`

If REPL is open when disconnecting, collapse it: add in `showDisconnectedState()`:
```swift
        if replExpanded { toggleREPL() }
```

**Step 7: Build**
```bash
bash build.sh
```
Manual: connect → click </> → panel slides up → type `document.title` → Enter → shows result.

**Step 8: Commit**
```bash
git add systemtrayterminal.swift
git commit -m "feat(webpicker): JS REPL panel with history navigation"
```

---

## Task 8: Element Screenshot via CDP (Feature 5)

**Files:**
- Modify: `systemtrayterminal.swift:11307` — `ChromeCDPClient` (add new method)
- Modify: `systemtrayterminal.swift` — `WebPickerSidebarView` (add `triggerElementScreenshot`)

**Step 1: Add `captureElementScreenshot` to `ChromeCDPClient`**

After `setChromeWindowBounds` method (around line 11315), add:
```swift
    /// Captures a screenshot of a specific element identified by its data-qt-pick-N attribute.
    /// Flow: DOM.getDocument → DOM.querySelector → DOM.getBoxModel → Page.captureScreenshot(clip)
    func captureElementScreenshot(pickId: Int, completion: @escaping (Data?) -> Void) {
        // Step 1: get root node ID
        cdpCommand("DOM.getDocument", params: ["depth": 0]) { [weak self] docResult in
            guard let self = self,
                  let root = docResult?["root"] as? [String: Any],
                  let rootId = root["nodeId"] as? Int else { completion(nil); return }
            // Step 2: find element node by attribute selector
            self.cdpCommand("DOM.querySelector",
                            params: ["nodeId": rootId, "selector": "[data-qt-pick-\(pickId)]"]) { [weak self] qResult in
                guard let self = self,
                      let nodeId = qResult?["nodeId"] as? Int, nodeId != 0 else { completion(nil); return }
                // Step 3: get bounding box
                self.cdpCommand("DOM.getBoxModel", params: ["nodeId": nodeId]) { [weak self] boxResult in
                    guard let self = self,
                          let model = boxResult?["model"] as? [String: Any],
                          let content = model["content"] as? [Double], content.count >= 6 else { completion(nil); return }
                    // content = [x1,y1, x2,y1, x2,y2, x1,y2] (quad)
                    let x = content[0]; let y = content[1]
                    let w = content[2] - content[0]; let h = content[5] - content[1]
                    guard w > 0, h > 0 else { completion(nil); return }
                    // Step 4: capture screenshot with clip
                    let clip: [String: Any] = ["x": x, "y": y, "width": w, "height": h, "scale": 1]
                    self.cdpCommand("Page.captureScreenshot",
                                    params: ["format": "png", "clip": clip]) { ssResult in
                        guard let b64 = ssResult?["data"] as? String,
                              let data = Data(base64Encoded: b64) else { completion(nil); return }
                        completion(data)
                    }
                }
            }
        }
    }
```

**Step 2: Implement `triggerElementScreenshot` in WebPickerSidebarView**

Add before `showCopiedFeedback()`:
```swift
    private func triggerElementScreenshot(pickId: Int) {
        feedbackLabel.stringValue = "📷 capturing…"; feedbackLabel.isHidden = false
        cdp.captureElementScreenshot(pickId: pickId) { [weak self] data in
            guard let self = self else { return }
            if let data = data, let image = NSImage(data: data) {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.writeObjects([image])
                self.feedbackLabel.stringValue = "✓ Screenshot kopiert!"
            } else {
                self.feedbackLabel.stringValue = "⚠ Element nicht sichtbar"
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                self?.feedbackLabel.isHidden = true
            }
        }
    }
```

Note: `menuScreenshot(_:)` was already stubbed in Task 3 as:
```swift
    @objc private func menuScreenshot(_ item: NSMenuItem) {
        guard let pickId = item.representedObject as? Int else { return }
        triggerElementScreenshot(pickId: pickId)
    }
```
This is now fully implemented.

**Step 3: Build**
```bash
bash build.sh
```
Manual: pick element → right-click → "Screenshot kopieren" → paste in any app → shows cropped element PNG.

**Step 4: Commit**
```bash
git add systemtrayterminal.swift
git commit -m "feat(webpicker): element screenshot via CDP DOM.getBoxModel + Page.captureScreenshot"
```

---

## Final: Verify all 9 features

```bash
bash build.sh
```

Manual test checklist:
- [ ] Picks list scrolls when > 5 items picked (Feature 8)
- [ ] Picks survive soft-disconnect (Feature 7)
- [ ] Right-click pick row shows outerHTML/innerText/CSS Selector/XPath/Screenshot menu (Features 1+6)
- [ ] ⊞ button shows Chrome tab list, clicking switches tab (Feature 4)
- [ ] ⟳ button on file:// URL watches file and reloads on save (Feature 9)
- [ ] ⟳ button on localhost shows 📁 picker, polls directory (Feature 9)
- [ ] Click pick row expands computed style (font, color, bg, padding) (Feature 2)
- [ ] </> button opens REPL, Enter evaluates, ↑↓ navigate history (Feature 3)
- [ ] Right-click → Screenshot kopieren → paste PNG in Figma (Feature 5)

**Final commit:**
```bash
git add systemtrayterminal.swift
git commit -m "feat(webpicker): all 9 features complete — scroll, persist, CSS selector, tab switcher, hot reload, computed style, REPL, screenshot"
```
