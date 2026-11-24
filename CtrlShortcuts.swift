import AppKit
import ApplicationServices

final class ScreenshotChord {
    enum Decision { case pass, consume, capture }
    var held = false

    func handle(_ event: CGEvent, type: CGEventType) -> Decision {
        guard event.getIntegerValueField(.keyboardEventKeycode) == 1 else { return .pass } // S
        if type == .keyUp {
            guard held else { return .pass }
            held = false
            return .consume
        }
        guard type == .keyDown else { return .pass }
        if held { return .consume }
        guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0,
              event.flags.intersection(ChordMapper.relevant) == [.maskControl, .maskAlternate] else { return .pass }
        held = true
        return .capture
    }
}

// Consume the physical chord before Office can turn Option+= into the character ≠.
final class EquationChord {
    enum Decision { case pass, consume, insert }
    static let powerpoint = "com.microsoft.Powerpoint"
    var held = false

    func handle(_ event: CGEvent, type: CGEventType, bundle: String) -> Decision {
        guard event.getIntegerValueField(.keyboardEventKeycode) == 24 else { return .pass }
        if type == .keyUp {
            guard held else { return .pass }
            held = false
            return .consume
        }
        guard type == .keyDown else { return .pass }
        // Repeats and the matching release stay consumed even if focus changes.
        if held { return .consume }
        guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0,
              bundle == Self.powerpoint,
              event.flags.intersection(ChordMapper.relevant) == .maskAlternate else { return .pass }
        held = true
        return .insert
    }
}

final class EquationCommand {
    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
    static func children(_ element: AXUIElement) -> [AXUIElement] {
        attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }
    static func title(_ element: AXUIElement) -> String {
        (attribute(element, kAXTitleAttribute) as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func perform(pid: pid_t) -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier == pid, app.bundleIdentifier == EquationChord.powerpoint else { return false }
        let root = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(root, 0.15)
        if let window = attribute(root, kAXFocusedWindowAttribute), CFGetTypeID(window) == AXUIElementGetTypeID() {
            let focusedWindow = unsafeBitCast(window, to: AXUIElement.self)
            guard attribute(focusedWindow, kAXModalAttribute) as? Bool != true,
                  (attribute(focusedWindow, "AXSheets") as? [AXUIElement] ?? []).isEmpty else { return false }
        }
        guard let barValue = attribute(root, kAXMenuBarAttribute), CFGetTypeID(barValue) == AXUIElementGetTypeID() else { return false }
        let bar = unsafeBitCast(barValue, to: AXUIElement.self)
        guard let insert = children(bar).first(where: { ["插入", "Insert"].contains(title($0)) }),
              let menu = children(insert).first,
              let equation = children(menu).first(where: { ["公式", "Equation", "方程式"].contains(title($0)) }),
              attribute(equation, kAXEnabledAttribute) as? Bool == true,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return false }
        return AXUIElementPerformAction(equation, kAXPressAction as CFString) == .success
    }
}

// Convert only editing chords; never change the physical modifier keys.
final class ChordMapper {
    static let control: CGEventFlags = .maskControl
    static let command: CGEventFlags = .maskCommand
    static let shift: CGEventFlags = .maskShift
    static let relevant: CGEventFlags = [.maskControl, .maskCommand, .maskAlternate, .maskShift, .maskSecondaryFn]
    static let letters: Set<Int64> = [0, 6, 7, 8, 9] // A Z X C V
    static let terminalApps: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "com.termius-dmg.mac",
        "com.termius.mac", "com.mitchellh.ghostty", "dev.warp.Warp-Stable",
        "net.kovidgoyal.kitty", "org.alacritty", "co.zeit.hyper", "com.tabby",
        "com.royalapps.RoyalTSX", "com.panic.Prompt"
    ]
    static let uuRemoteBundle = "com.netease.uuremote"
    static func preservesCtrl(in bundle: String) -> Bool {
        terminalApps.contains(bundle) || bundle == uuRemoteBundle || bundle.hasPrefix(uuRemoteBundle + ".")
    }
    var held = Set<Int64>()

    func convert(_ event: CGEvent, type: CGEventType, excluded: Bool) -> Bool {
        let key = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .keyUp {
            guard held.remove(key) != nil else { return false }
        } else {
            guard type == .keyDown else { return false }
            let modifiers = event.flags.intersection(Self.relevant)
            let editingChord = modifiers == Self.control ||
                (key == 6 && modifiers == [Self.control, Self.shift])
            guard !excluded, Self.letters.contains(key), editingChord else { return false }
            held.insert(key)
        }
        event.flags.remove(.maskControl)
        event.flags.insert(.maskCommand)
        // Strip device-specific left/right Control bits too.
        event.flags = CGEventFlags(rawValue: event.flags.rawValue & ~UInt64(0x2001))
        return true
    }
}

// Remove old menu-only overrides while the mapper is active, so Cmd keeps working.
final class MenuOverrides {
    let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Ctrl Shortcuts")
    let expected = ["拷贝":"^c", "复制":"^c", "Copy":"^c", "粘贴":"^v", "Paste":"^v",
                    "撤销":"^z", "Undo":"^z", "剪切":"^x", "Cut":"^x", "重做":"^$z", "Redo":"^$z",
                    "全选":"^a", "Select All":"^a"]
    var state: URL { directory.appendingPathComponent("menu-overrides-backup.plist") }
    func defaults(_ arguments: [String]) throws -> Data {
        let process = Process(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw NSError(domain: "CtrlShortcuts.defaults", code: Int(process.terminationStatus)) }
        return data
    }
    func read() throws -> [String:String] {
        let data = try defaults(["export", "NSGlobalDomain", "-"])
        let root = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String:Any]
        return root?["NSUserKeyEquivalents"] as? [String:String] ?? [:]
    }
    func write(_ values: [String:String]) throws {
        var args = ["write", "-g", "NSUserKeyEquivalents", "-dict"]
        for key in values.keys.sorted() { args += [key, values[key]!] }
        _ = try defaults(args)
    }
    func activate() throws {
        var current = try read()
        let removed = current.filter { expected[$0.key] == $0.value }
        if !FileManager.default.fileExists(atPath: state.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: removed, format: .xml, options: 0)
            try data.write(to: state, options: .atomic)
        }
        guard !removed.isEmpty else { return }
        for key in removed.keys { current.removeValue(forKey: key) }
        try write(current)
    }
    func restore() throws {
        guard FileManager.default.fileExists(atPath: state.path) else { return }
        let saved = try PropertyListSerialization.propertyList(from: Data(contentsOf: state), format: nil) as? [String:String] ?? [:]
        var current = try read()
        for (key, value) in saved where current[key] == nil { current[key] = value }
        try write(current)
        try FileManager.default.removeItem(at: state)
    }
}

final class Controller: NSObject, NSApplicationDelegate {
    let mapper = ChordMapper()
    let equationChord = EquationChord()
    let screenshotChord = ScreenshotChord()
    let equationQueue = DispatchQueue(label: "local.xin.ctrlshortcuts.equation")
    var equationResult = "PowerPoint：Alt+= 插入公式"
    static let screenshotLabel = "Flameshot：Ctrl+Alt+S 截图"
    var screenshotStatus = screenshotLabel
    var launchingScreenshot = false
    let overrides = MenuOverrides()
    var tap: CFMachPort?
    var source: CFRunLoopSource?
    var item: NSStatusItem!
    var enabled = false
    var status = "等待辅助功能权限"
    var timer: Timer?
    var frontBundle = ""
    var activationObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        frontBundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            self?.frontBundle = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier ?? ""
        }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "Ctrl"
        refreshMenu()
        start()
        if !enabled {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                guard let self, AXIsProcessTrusted() else { return }
                self.start()
                if self.enabled { self.timer?.invalidate(); self.timer = nil }
            }
        }
    }

    func start() {
        guard tap == nil else { return }
        guard AXIsProcessTrusted() else { status = "等待辅助功能权限"; refreshMenu(); return }
        let callback: CGEventTapCallBack = { _, type, event, context in
            let owner = Unmanaged<Controller>.fromOpaque(context!).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                owner.mapper.held.removeAll()
                owner.equationChord.held = false
                owner.screenshotChord.held = false
                if owner.enabled, let tap = owner.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            if owner.enabled {
                switch owner.screenshotChord.handle(event, type: type) {
                case .capture:
                    DispatchQueue.main.async { owner.launchScreenshot() }
                    return nil
                case .consume: return nil
                case .pass: break
                }
                let equationBundle = event.getIntegerValueField(.keyboardEventKeycode) == 24
                    ? (NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "") : owner.frontBundle
                switch owner.equationChord.handle(event, type: type, bundle: equationBundle) {
                case .insert:
                    if let app = NSWorkspace.shared.frontmostApplication,
                       app.bundleIdentifier == EquationChord.powerpoint {
                        owner.insertEquation(pid: app.processIdentifier)
                    }
                    return nil
                case .consume: return nil
                case .pass: break
                }
                let key = event.getIntegerValueField(.keyboardEventKeycode)
                // Check current focus on editing chords so switching to UU Remote takes effect immediately.
                let candidate = type == .keyDown && ChordMapper.letters.contains(key) && event.flags.contains(.maskControl)
                let frontApp = candidate ? NSWorkspace.shared.frontmostApplication : nil
                let excluded = candidate && (ChordMapper.preservesCtrl(in: frontApp?.bundleIdentifier ?? owner.frontBundle)
                    || owner.focusedTerminal(in: frontApp))
                _ = owner.mapper.convert(event, type: type, excluded: excluded)
            }
            return Unmanaged.passUnretained(event)
        }
        guard let created = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue),
            callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            status = "无法启用，请检查辅助功能权限"; refreshMenu(); return
        }
        tap = created
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        do {
            try overrides.activate()
            enabled = true
            CGEvent.tapEnable(tap: created, enable: true)
            status = "已启用：Ctrl+A/C/V/X/Z、Ctrl+Shift+Z"
        } catch {
            CFMachPortInvalidate(created); tap = nil
            if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
            source = nil
            status = "设置备份失败，未更改按键"
        }
        refreshMenu()
    }

    func launchScreenshot() {
        guard enabled, !launchingScreenshot else { return }
        let workspace = NSWorkspace.shared
        guard let flameshot = workspace.urlForApplication(withBundleIdentifier: "org.flameshot.Flameshot") else {
            screenshotStatus = "Flameshot：未找到应用"
            refreshMenu()
            NSSound.beep()
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = ["gui"]
        configuration.createsNewApplicationInstance = true
        launchingScreenshot = true
        workspace.openApplication(at: flameshot, configuration: configuration) { [weak self] app, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.launchingScreenshot = false
                if let error { NSLog("Flameshot: %@", error.localizedDescription) }
                let succeeded = app != nil && error == nil
                self.screenshotStatus = succeeded ? Self.screenshotLabel : "Flameshot：启动失败"
                if !succeeded { NSSound.beep() }
                self.refreshMenu()
            }
        }
    }

    func insertEquation(pid: pid_t) {
        let requested = ProcessInfo.processInfo.systemUptime
        equationQueue.async { [weak self] in
            guard let self else { return }
            guard ProcessInfo.processInfo.systemUptime - requested < 0.8,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
            let succeeded = EquationCommand.perform(pid: pid)
            DispatchQueue.main.async {
                self.equationResult = succeeded ? "PowerPoint：Alt+= 已插入公式" : "PowerPoint：当前窗口无法插入公式"
                self.refreshMenu()
                if !succeeded, NSWorkspace.shared.frontmostApplication?.processIdentifier == pid { NSSound.beep() }
            }
        }
    }

    // Check accessibility labels only, never the text being edited.
    func focusedTerminal(in app: NSRunningApplication?) -> Bool {
        guard let app else { return false }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.01)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(root, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused else { return false }
        var node = unsafeBitCast(focused, to: AXUIElement.self)
        for _ in 0..<5 {
            for key in [kAXTitleAttribute, kAXDescriptionAttribute, kAXIdentifierAttribute, kAXRoleDescriptionAttribute] {
                var value: CFTypeRef?
                if AXUIElementCopyAttributeValue(node, key as CFString, &value) == .success, let label = value as? String {
                    let text = label.lowercased()
                    if text.contains("terminal") || text.contains("终端") { return true }
                }
            }
            var parent: CFTypeRef?
            guard AXUIElementCopyAttributeValue(node, kAXParentAttribute as CFString, &parent) == .success,
                  let parent else { break }
            node = unsafeBitCast(parent, to: AXUIElement.self)
        }
        return false
    }

    func refreshMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: status, action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "UU 远程和终端保留 Ctrl 原键", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: equationResult, action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: screenshotStatus, action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        let toggle = NSMenuItem(title: enabled ? "暂停转换" : "启用转换", action: #selector(toggleMapping), keyEquivalent: "")
        toggle.target = self; menu.addItem(toggle)
        let permission = NSMenuItem(title: "打开辅助功能设置…", action: #selector(openPermissions), keyEquivalent: "")
        permission.target = self; menu.addItem(permission)
        let quit = NSMenuItem(title: "退出并恢复原快捷键", action: #selector(quitApp), keyEquivalent: "")
        quit.target = self; menu.addItem(quit)
        item.menu = menu
        item.button?.appearsDisabled = !enabled
    }
    @objc func toggleMapping() {
        if enabled {
            do { try overrides.restore() } catch { status = "恢复设置失败"; refreshMenu(); return }
            enabled = false
            mapper.held.removeAll()
            equationChord.held = false
            screenshotChord.held = false
            if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
            if let tap { CFMachPortInvalidate(tap) }
            tap = nil
            if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
            source = nil
            status = "已暂停"
            refreshMenu()
        } else { start() }
    }
    @objc func openPermissions() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    @objc func quitApp() {
        do { try overrides.restore() }
        catch { status = "恢复设置失败"; refreshMenu(); return }
        NSApp.terminate(nil)
    }
    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        if let tap { CFMachPortInvalidate(tap) }
        // Logout/shutdown also terminates this app. Keep native Command menu
        // defaults across sessions, so apps that reopen before us use them.
        // Only the explicit Pause and Quit-and-Restore actions restore overrides.
    }
}

func selfTest() {
    let mapper = ChordMapper()
    func event(_ key: Int64, _ flags: CGEventFlags) -> CGEvent {
        let e = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(key), keyDown: true)!
        e.flags = flags; return e
    }
    for key: Int64 in [0,6,7,8,9] {
        let e = event(key, .maskControl)
        assert(mapper.convert(e, type: .keyDown, excluded: false))
        assert(e.flags.contains(.maskCommand) && !e.flags.contains(.maskControl))
        let up = event(key, [])
        assert(mapper.convert(up, type: .keyUp, excluded: true))
        assert(up.flags.contains(.maskCommand))
    }
    for flags: CGEventFlags in [.maskCommand, [.maskControl,.maskAlternate], [.maskControl,.maskCommand], [.maskControl,.maskShift], []] {
        assert(!mapper.convert(event(8, flags), type: .keyDown, excluded: false))
    }
    assert(!mapper.convert(event(8, .maskControl), type: .keyDown, excluded: true))
    assert(!mapper.convert(event(1, .maskControl), type: .keyDown, excluded: false))
    assert(mapper.convert(event(6, [.maskControl,.maskShift]), type: .keyDown, excluded: false))
    assert(!mapper.convert(event(9, []), type: .keyUp, excluded: false))
    let device = event(8, CGEventFlags(rawValue: CGEventFlags.maskControl.rawValue | 0x2001))
    assert(mapper.convert(device, type: .keyDown, excluded: false))
    assert(device.flags.rawValue & 0x2001 == 0)
    print("PASS: editing chords, redo, original Command, modifier combinations, terminal exclusion, paired key release")

    let remoteMapper = ChordMapper()
    for bundle in ["com.netease.uuremote", "com.netease.uuremote.helper", "com.apple.Terminal"] {
        for key in ChordMapper.letters {
            let flags: CGEventFlags = key == 6 ? [.maskControl, .maskShift] : .maskControl
            let excluded = ChordMapper.preservesCtrl(in: bundle)
            for type: CGEventType in [.keyDown, .keyUp] {
                let e = event(key, flags)
                assert(!remoteMapper.convert(e, type: type, excluded: excluded) && e.flags == flags)
            }
        }
    }
    for bundle in ["com.netease.uuremoteOther", "com.qodercn.app", "com.openai.codex"] {
        let e = event(8, .maskControl)
        assert(remoteMapper.convert(e, type: .keyDown, excluded: ChordMapper.preservesCtrl(in: bundle)))
        assert(e.flags == .maskCommand)
        _ = remoteMapper.convert(event(8, []), type: .keyUp, excluded: false)
    }
    print("PASS: UU Remote and related bundles keep the original Ctrl key events")

    let equation = EquationChord()
    let physical = event(24, CGEventFlags(rawValue: CGEventFlags.maskAlternate.rawValue | 0x20))
    var unequal: [UniChar] = [0x2260]
    physical.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unequal)
    assert(equation.handle(physical, type: .keyDown, bundle: EquationChord.powerpoint) == .insert)
    assert(equation.handle(physical, type: .keyDown, bundle: "other") == .consume)
    assert(equation.handle(event(24, []), type: .keyUp, bundle: "other") == .consume)
    for bundle in ["com.apple.TextEdit", "com.microsoft.Word", "com.apple.Terminal", ""] {
        assert(equation.handle(physical, type: .keyDown, bundle: bundle) == .pass)
    }
    for flags: CGEventFlags in [[], .maskControl, .maskCommand, [.maskAlternate,.maskShift], [.maskAlternate,.maskControl], [.maskAlternate,.maskCommand]] {
        assert(equation.handle(event(24, flags), type: .keyDown, bundle: EquationChord.powerpoint) == .pass)
    }
    assert(equation.handle(event(23, .maskAlternate), type: .keyDown, bundle: EquationChord.powerpoint) == .pass)
    let repeatEvent = event(24, .maskAlternate)
    repeatEvent.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
    assert(equation.handle(repeatEvent, type: .keyDown, bundle: EquationChord.powerpoint) == .pass)
    assert(equation.handle(physical, type: .keyDown, bundle: EquationChord.powerpoint) == .insert)
    assert(equation.handle(repeatEvent, type: .keyDown, bundle: EquationChord.powerpoint) == .consume)
    assert(equation.handle(event(24, []), type: .keyUp, bundle: EquationChord.powerpoint) == .consume)
    print("PASS: PowerPoint-only physical Option+= (≠), exact modifiers, repeats, focus changes, paired release")

    let screenshot = ScreenshotChord()
    let captureFlags: CGEventFlags = [.maskControl, .maskAlternate]
    for flags: CGEventFlags in [[], .maskControl, .maskAlternate, [.maskControl, .maskAlternate, .maskShift],
                               [.maskControl, .maskAlternate, .maskCommand]] {
        assert(screenshot.handle(event(1, flags), type: .keyDown) == .pass)
    }
    assert(screenshot.handle(event(0, captureFlags), type: .keyDown) == .pass)
    let repeatedS = event(1, captureFlags)
    repeatedS.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
    assert(screenshot.handle(repeatedS, type: .keyDown) == .pass)
    assert(screenshot.handle(event(1, captureFlags), type: .keyDown) == .capture)
    assert(screenshot.handle(repeatedS, type: .keyDown) == .consume)
    assert(screenshot.handle(event(1, []), type: .keyUp) == .consume)
    assert(screenshot.handle(event(1, []), type: .keyUp) == .pass)
    assert(screenshot.handle(event(1, captureFlags), type: .keyDown) == .capture)
    print("PASS: physical Ctrl+Option+S, exact modifiers, repeats, paired release, and retrigger")
}

if CommandLine.arguments.contains("--self-test") { selfTest() }
else {
    let app = NSApplication.shared
    let controller = Controller()
    app.delegate = controller
    withExtendedLifetime(controller) { app.run() }
}
