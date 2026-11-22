// Tether: keeps your Bluetooth mouse connected, and brings it back with no pointer needed.
// Lives in the menu bar. Control Option Command M (or Spotlight) shows it and reconnects now; Return hides it.
// Plain AppKit, one timer, no SwiftUI or async runtime: runs on macOS 10.15 (Intel) and 11 (Apple silicon) up.
import AppKit
import Carbon.HIToolbox
import CoreBluetooth
import IOBluetooth
import IOKit
import ServiceManagement

let brand = NSColor(srgbRed: 0x0b / 255, green: 0x66 / 255, blue: 0xe4 / 255, alpha: 1)

// MARK: - The mouse

final class Mouse: NSObject {
    enum State { case connecting, connected, missing, noMouse, bluetoothOff, noAccess }
    private(set) var state = State.connecting
    private(set) var name = "your mouse"
    var onChange: (() -> Void)?
    private var polls = 0 // half-second polls left in the current attempt
    private var attempting = false
    private var missingSince: Date?
    private var timer: Timer?
    private var watch: IOBluetoothUserNotification?
    private let defaults = UserDefaults.standard
    // Addresses with an openConnection still blocking, so a missing mouse never piles up threads.
    private static let lock = NSLock()
    private static var inFlight = Set<String>()

    func start() { tick() }

    /// Reconnect right now: the hotkey, the menu, a relaunch.
    func now() { missingSince = nil; polls = 0; attempting = false; tick() }

    private func set(_ s: State) { state = s; onChange?() }

    // One timer at a time, with slack so macOS can coalesce wakeups.
    private func after(_ seconds: TimeInterval) {
        timer?.invalidate()
        let t = Timer(timeInterval: seconds, repeats: false) { [weak self] _ in self?.tick() }
        t.tolerance = seconds * 0.25
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        remember()
        if let m = connected() {
            name = m.name ?? name
            polls = 0; attempting = false; missingSince = nil
            if watch == nil { watch = m.register(forDisconnectNotification: self, selector: #selector(dropped(_:device:))) }
            set(.connected)
            return after(30) // the disconnect notification does the real watching; this is the fallback
        }
        if polls > 0 { polls -= 1; return after(0.5) }
        if attempting {
            attempting = false
            if missingSince == nil { missingSince = Date() }
            set(.missing)
            // Mouse switched off for the night: stop paging the radio every few seconds after two minutes.
            return after(Date().timeIntervalSince(missingSince!) > 120 ? 60 : 2)
        }
        attempt()
    }

    @objc private func dropped(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        watch?.unregister(); watch = nil
        now()
    }

    private func attempt() {
        if #available(macOS 10.15, *), [.denied, .restricted].contains(CBManager.authorization) { set(.noAccess); return after(5) }
        guard IOBluetoothHostController.default()?.powerState == kBluetoothHCIPowerStateON else { set(.bluetoothOff); return after(5) }
        let all = mice()
        guard let first = all.first else { set(.noMouse); return after(5) }
        name = first.name ?? name
        // openConnection blocks for ~15s on a dead address, so each one runs on its own thread, one per address.
        for address in all.compactMap({ $0.addressString }) where Mouse.claim(address) {
            Thread.detachNewThread {
                _ = IOBluetoothDevice(addressString: address)?.openConnection()
                Mouse.lock.lock(); Mouse.inFlight.remove(address); Mouse.lock.unlock()
            }
        }
        polls = 20
        attempting = true
        if state != .missing { set(.connecting) } else { onChange?() }
        after(0.5)
    }

    private static func claim(_ address: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return inFlight.insert(address).inserted
    }

    // BLE devices report no device class to IOBluetooth, so Tether learns pointers by name from the HID registry while
    // they are connected. Re-pairing changes a mouse's address but never its name. Reading the registry needs no permission.
    private func connectedPointerNames() -> Set<String> {
        var names = Set<String>()
        for (page, usage) in [(1, 2), (0x0D, 0x05)] { // mouse, touchpad
            let match = IOServiceMatching("IOHIDDevice") as NSMutableDictionary
            match["PrimaryUsagePage"] = page
            match["PrimaryUsage"] = usage
            var it: io_iterator_t = 0
            guard IOServiceGetMatchingServices(0, match, &it) == KERN_SUCCESS else { continue } // 0: the default main port
            defer { IOObjectRelease(it) }
            while case let s = IOIteratorNext(it), s != 0 {
                defer { IOObjectRelease(s) }
                let prop = { (key: String) in IORegistryEntryCreateCFProperty(s, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String }
                if prop("Transport")?.hasPrefix("Bluetooth") == true, let n = prop("Product") { names.insert(n) }
            }
        }
        return names
    }

    private var known: Set<String> { Set(defaults.stringArray(forKey: "pointers") ?? []) }

    private func remember() {
        let seen = connectedPointerNames(), known = known
        if !seen.isSubset(of: known) { defaults.set(known.union(seen).sorted(), forKey: "pointers") }
    }

    // Every paired pointer, old addresses included, so they can all be tried at once.
    private func mice() -> [IOBluetoothDevice] {
        let known = known
        return (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []).filter {
            let n = $0.name ?? ""
            let pointing = $0.deviceClassMajor == kBluetoothDeviceClassMajorPeripheral && $0.deviceClassMinor & 0x20 != 0 // classic only; BLE reports 0
            return pointing || known.contains(n) || ["mouse", "trackpad"].contains { n.localizedCaseInsensitiveContains($0) }
        }
    }

    private func connected() -> IOBluetoothDevice? { mice().first { $0.isConnected() } }
}

// MARK: - The screen

/// The mouse glyph, drawn by hand so it looks the same on every macOS, in the window badge and the menu bar.
enum Glyph {
    case mouse, outline, check, slash

    static func draw(_ g: Glyph, center c: NSPoint, scale k: CGFloat) {
        switch g {
        case .check:
            let p = NSBezierPath()
            p.move(to: NSPoint(x: c.x - 16 * k, y: c.y + 1 * k)); p.line(to: NSPoint(x: c.x - 5 * k, y: c.y - 11 * k)); p.line(to: NSPoint(x: c.x + 17 * k, y: c.y + 13 * k))
            p.lineWidth = 5 * k; p.lineCapStyle = .round; p.lineJoinStyle = .round; p.stroke()
        case .mouse, .outline, .slash:
            let body = NSRect(x: c.x - 13 * k, y: c.y - 20 * k, width: 26 * k, height: 40 * k)
            let shape = NSBezierPath(roundedRect: body, xRadius: 13 * k, yRadius: 13 * k)
            let seam = NSBezierPath(); seam.move(to: NSPoint(x: c.x, y: body.maxY)); seam.line(to: NSPoint(x: c.x, y: body.maxY - 12 * k))
            seam.lineWidth = 2.5 * k; seam.lineCapStyle = .round
            if g == .mouse {
                shape.fill()
                NSGraphicsContext.current?.compositingOperation = .destinationOut
                seam.stroke()
                NSGraphicsContext.current?.compositingOperation = .sourceOver
            } else {
                shape.lineWidth = 3 * k; shape.stroke(); seam.stroke()
            }
            if g == .slash {
                let s = NSBezierPath(); s.move(to: NSPoint(x: c.x - 22 * k, y: c.y + 22 * k)); s.line(to: NSPoint(x: c.x + 22 * k, y: c.y - 22 * k))
                s.lineWidth = 3.5 * k; s.lineCapStyle = .round; s.stroke()
            }
        }
    }

    /// A template image for the menu bar, so macOS tints it for light, dark and highlighted.
    static func menuBar(_ g: Glyph) -> NSImage {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { r in
            NSColor.black.set()
            draw(g, center: NSPoint(x: r.midX, y: r.midY), scale: 0.36)
            return true
        }
        img.isTemplate = true
        return img
    }
}

/// The round badge: a tinted disc with the glyph.
final class Badge: NSView {
    var tint = NSColor.secondaryLabelColor { didSet { needsDisplay = true } }
    var glyph = Glyph.mouse { didSet { needsDisplay = true } }
    override var intrinsicContentSize: NSSize { NSSize(width: 96, height: 96) }
    override func viewDidChangeEffectiveAppearance() { needsDisplay = true }

    override func draw(_ rect: NSRect) {
        tint.withAlphaComponent(0.14).setFill()
        NSBezierPath(ovalIn: bounds).fill()
        tint.set()
        Glyph.draw(glyph, center: NSPoint(x: bounds.midX, y: bounds.midY), scale: 1)
    }
}

final class Panel: NSWindow {
    override func cancelOperation(_ sender: Any?) { orderOut(nil) } // Escape hides it; Tether stays in the menu bar
}

final class Controller: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let mouse = Mouse()
    let badge = Badge()
    let title = NSTextField(labelWithString: "")
    let detail = NSTextField(wrappingLabelWithString: "")
    lazy var button = NSButton(title: "Done", target: self, action: #selector(primary))
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    let status = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    var login: NSMenuItem?
    var window: Panel!
    var hotKey: EventHotKeyRef?

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.mainMenu = mainMenu()
        buildWindow()
        buildMenuBar()
        registerHotKey()
        mouse.onChange = { [weak self] in self?.render() }
        render()
        show()
        mouse.start()
    }

    // Opening Tether again (Spotlight, Finder) while it runs: show it and reconnect now.
    func applicationShouldHandleReopen(_ app: NSApplication, hasVisibleWindows: Bool) -> Bool { summon(); return false }
    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { false }

    @objc func summon() { show(); mouse.now() }

    private func show() {
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildWindow() {
        // Tether Sans and Tether Display ship in Resources/Fonts (ATSApplicationFontsPath); scripts/gen_font.py makes them.
        title.font = NSFont(name: "TetherDisplay-Bold", size: 22) ?? .boldSystemFont(ofSize: 22)
        detail.font = NSFont(name: "TetherSans-Regular", size: 13) ?? .systemFont(ofSize: 13)
        detail.textColor = .secondaryLabelColor
        detail.alignment = .center
        detail.preferredMaxLayoutWidth = 276
        button.font = NSFont(name: "TetherSans-Semibold", size: 15) ?? .boldSystemFont(ofSize: 15)
        button.keyEquivalent = "\r"
        button.bezelColor = brand
        if #available(macOS 11, *) { button.controlSize = .large }
        badge.wantsLayer = true

        let stack = NSStackView(views: [badge, title, detail, button])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 6
        stack.setCustomSpacing(20, after: badge)
        stack.setCustomSpacing(24, after: detail)
        stack.edgeInsets = NSEdgeInsets(top: 44, left: 32, bottom: 32, right: 32)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.widthAnchor.constraint(equalToConstant: 340),
            detail.heightAnchor.constraint(greaterThanOrEqualToConstant: 36),
            button.widthAnchor.constraint(equalToConstant: 276),
        ])

        window = Panel(contentRect: .zero, styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Tether"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.contentView = stack
        window.setContentSize(stack.fittingSize)
    }

    private func buildMenuBar() {
        let menu = NSMenu()
        menu.delegate = self
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())
        let reconnect = menu.addItem(withTitle: "Reconnect Now", action: #selector(summon), keyEquivalent: "m")
        reconnect.keyEquivalentModifierMask = [.control, .option, .command] // shown for the global hotkey
        reconnect.target = self
        if #available(macOS 13, *) {
            login = menu.addItem(withTitle: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")
            login?.target = self
        }
        menu.addItem(withTitle: "Bluetooth Settings…", action: #selector(openBluetooth), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Tether", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        if #available(macOS 13, *) { login?.state = SMAppService.mainApp.status == .enabled ? .on : .off }
    }

    @objc private func toggleLogin() {
        guard #available(macOS 13, *) else { return }
        let app = SMAppService.mainApp
        try? (app.status == .enabled ? app.unregister() : app.register())
    }

    // Control Option Command M from anywhere. Carbon hot keys need no permission and work back to the first Mac OS X.
    private func registerHotKey() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, ctx in
            guard let ctx else { return OSStatus(eventNotHandledErr) }
            let c = Unmanaged<Controller>.fromOpaque(ctx).takeUnretainedValue()
            DispatchQueue.main.async { c.summon() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)
        RegisterEventHotKey(UInt32(kVK_ANSI_M), UInt32(controlKey | optionKey | cmdKey), EventHotKeyID(signature: 0x5448_5452, id: 1),
                            GetApplicationEventTarget(), 0, &hotKey)
    }

    private func render() {
        let s = mouse.state, n = mouse.name
        let (glyph, tint, head, body, action): (Glyph, NSColor, String, String, String) = {
            switch s {
            case .connecting: return (.mouse, .secondaryLabelColor, "Connecting", "Looking for \(n).", "Done")
            case .connected: return (.check, brand, "Connected", "\(n) is ready to go.", "Done")
            case .missing: return (.mouse, .systemOrange, "Mouse Not Responding", "Turn \(n) off and on. Tether keeps trying.", "Open Bluetooth Settings")
            case .noMouse: return (.outline, .secondaryLabelColor, "No Mouse Yet", "Connect your mouse once while Tether is open, or pair it in Bluetooth settings. Tether remembers it after that.", "Open Bluetooth Settings")
            case .bluetoothOff: return (.slash, .systemOrange, "Bluetooth Is Off", "Turn on Bluetooth to connect \(n).", "Open Bluetooth Settings")
            case .noAccess: return (.slash, .systemOrange, "Bluetooth Access Is Off", "Let Tether use Bluetooth in Privacy & Security to reach your mouse.", "Open Privacy Settings")
            }
        }()
        badge.glyph = glyph
        badge.tint = tint
        title.stringValue = head
        detail.stringValue = body
        button.title = action
        pulse(s == .connecting)
        item.button?.image = Glyph.menuBar(s == .connected ? .mouse : s == .connecting ? .outline : .slash)
        item.button?.toolTip = "Tether: \(head)"
        status.title = s == .connected ? "\(n): Connected" : head
    }

    private func pulse(_ on: Bool) {
        guard let layer = badge.layer else { return }
        if !on { return layer.removeAnimation(forKey: "pulse") }
        guard layer.animation(forKey: "pulse") == nil, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let a = CABasicAnimation(keyPath: "opacity")
        a.fromValue = 1; a.toValue = 0.45; a.duration = 0.7
        a.autoreverses = true; a.repeatCount = .infinity
        a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(a, forKey: "pulse")
    }

    @objc private func primary() {
        switch mouse.state {
        case .connected, .connecting: window.orderOut(nil)
        case .noAccess: open("x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth")
        default: openBluetooth()
        }
    }

    @objc private func openBluetooth() { open("x-apple.systempreferences:com.apple.BluetoothSettings") }
    private func open(_ url: String) { if let u = URL(string: url) { NSWorkspace.shared.open(u) } }

    // Not shown (Tether has no Dock icon), but it keeps Command Q and Command W working while the window is up.
    private func mainMenu() -> NSMenu {
        let bar = NSMenu(), app = NSMenuItem(), sub = NSMenu()
        sub.addItem(withTitle: "Quit Tether", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        sub.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        app.submenu = sub
        bar.addItem(app)
        return bar
    }
}

let app = NSApplication.shared
let controller = Controller()
app.delegate = controller
app.setActivationPolicy(.accessory) // menu bar only, no Dock icon
app.run()
