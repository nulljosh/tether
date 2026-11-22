// Tether: reconnects the paired Bluetooth mouse with no pointer needed.
// Open it from Spotlight, it connects on its own, Return closes it. Build: ./build.sh
import CoreBluetooth
import IOBluetooth
import IOKit
import os
import SwiftUI

@main struct TetherApp: App {
    @NSApplicationDelegateAdaptor private var delegate: Delegate
    var body: some Scene {
        Window("Tether", id: "main") { ContentView() }
            .windowResizability(.contentSize)
            .windowStyle(.hiddenTitleBar)
    }
}

// Tether Sans and Tether Display ship in Resources/Fonts (ATSApplicationFontsPath); scripts/gen_font.py makes them.
extension Font {
    static let heading = Font.custom("TetherDisplay-Bold", size: 22, relativeTo: .title2)
    static let detail = Font.custom("TetherSans-Regular", size: 13, relativeTo: .callout)
    static let button = Font.custom("TetherSans-Semibold", size: 15, relativeTo: .body)
}

extension Color {
    static let brand = Color(red: 0x16 / 255, green: 0x99 / 255, blue: 0x4a / 255)
}

final class Delegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }
    func applicationDidFinishLaunching(_ n: Notification) { NSApp.activate() }
}

@MainActor @Observable final class Mouse {
    enum State { case connecting, connected, missing, noMouse, bluetoothOff, noAccess }
    var state = State.connecting
    var name = "your mouse"
    private var loop: Task<Void, Never>?
    private static let defaults = UserDefaults.standard
    // Addresses with an openConnection still blocking, so a missing mouse never piles up threads.
    private nonisolated static let inFlight = OSAllocatedUnfairLock(initialState: Set<String>())

    // BLE devices report no device class to IOBluetooth, so Tether learns pointers by name from the HID registry while
    // they are connected. Re-pairing changes a mouse's address but never its name. Reading the registry needs no permission.
    private static func connectedPointerNames() -> Set<String> {
        var names = Set<String>()
        for (page, usage) in [(1, 2), (0x0D, 0x05)] { // mouse, touchpad
            let match = IOServiceMatching("IOHIDDevice") as NSMutableDictionary
            match["PrimaryUsagePage"] = page
            match["PrimaryUsage"] = usage
            var it: io_iterator_t = 0
            guard IOServiceGetMatchingServices(kIOMainPortDefault, match, &it) == KERN_SUCCESS else { continue }
            defer { IOObjectRelease(it) }
            while case let s = IOIteratorNext(it), s != 0 {
                defer { IOObjectRelease(s) }
                let prop = { (key: String) in IORegistryEntryCreateCFProperty(s, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String }
                if prop("Transport")?.hasPrefix("Bluetooth") == true, let n = prop("Product") { names.insert(n) }
            }
        }
        return names
    }

    private static var known: Set<String> { Set(defaults.stringArray(forKey: "pointers") ?? []) }

    private static func remember() {
        let seen = connectedPointerNames()
        if !seen.isSubset(of: known) { defaults.set(known.union(seen).sorted(), forKey: "pointers") }
    }

    // Every paired pointer, old addresses included, so they can all be tried at once.
    private static func mice() -> [IOBluetoothDevice] {
        let known = known
        return (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []).filter {
            let n = $0.name ?? ""
            let pointing = $0.deviceClassMajor == kBluetoothDeviceClassMajorPeripheral && $0.deviceClassMinor & 0x20 != 0 // classic only; BLE reports 0
            return pointing || known.contains(n) || ["mouse", "trackpad"].contains { n.localizedCaseInsensitiveContains($0) }
        }
    }

    private static var connected: IOBluetoothDevice? { mice().first { $0.isConnected() } }

    func start() {
        loop?.cancel()
        loop = Task {
            while !Task.isCancelled {
                Self.remember()
                if let m = Self.connected {
                    name = m.name ?? name
                    state = .connected
                } else {
                    await attempt()
                }
                try? await Task.sleep(for: .seconds(state == .connected ? 3 : 2))
            }
        }
    }

    private func attempt() async {
        if [.denied, .restricted].contains(CBManager.authorization) { state = .noAccess; return }
        guard IOBluetoothHostController.default()?.powerState == kBluetoothHCIPowerStateON else {
            state = .bluetoothOff
            return
        }
        let all = Self.mice()
        guard let first = all.first else { state = .noMouse; return }
        name = first.name ?? name
        if state != .missing { state = .connecting }
        // openConnection blocks for ~15s on a dead address, so each one runs on its own thread.
        for address in all.compactMap(\.addressString) where Self.inFlight.withLock({ $0.insert(address).inserted }) {
            Thread.detachNewThread {
                _ = IOBluetoothDevice(addressString: address)?.openConnection()
                Self.inFlight.withLock { _ = $0.remove(address) }
            }
        }
        for _ in 0..<20 {
            try? await Task.sleep(for: .milliseconds(500))
            if let m = Self.connected { name = m.name ?? name; state = .connected; return }
        }
        state = .missing
    }
}

struct ContentView: View {
    @State private var mouse = Mouse()

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: symbol)
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(tint)
                .symbolEffect(.pulse, isActive: mouse.state == .connecting)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 96, height: 96)
                .background(tint.opacity(0.14), in: .circle)
                .padding(.bottom, 20)

            Text(title)
                .font(.heading)
                .padding(.bottom, 6)

            Text(subtitle)
                .font(.detail)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 36, alignment: .top)
                .padding(.bottom, 24)

            Button(action: primary) {
                Text(buttonTitle).font(.button).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.extraLarge)
            .keyboardShortcut(.defaultAction)

            Button("Close", action: quit)
                .keyboardShortcut(.cancelAction)
                .hidden()
                .frame(height: 0)
        }
        .padding(.horizontal, 32)
        .padding(.top, 24)
        .padding(.bottom, 32)
        .frame(width: 340)
        .tint(.brand)
        .animation(.smooth, value: mouse.state)
        .onAppear { mouse.start() }
    }

    private var symbol: String {
        switch mouse.state {
        case .connected: "checkmark"
        case .bluetoothOff: "antenna.radiowaves.left.and.right.slash"
        case .noAccess: "hand.raised.fill"
        case .noMouse: "computermouse"
        default: "computermouse.fill"
        }
    }

    private var tint: Color {
        switch mouse.state {
        case .connected: .brand
        case .missing, .bluetoothOff, .noAccess: .orange
        case .connecting, .noMouse: .secondary
        }
    }

    private var title: String {
        switch mouse.state {
        case .connecting: "Connecting"
        case .connected: "Connected"
        case .missing: "Mouse Not Responding"
        case .bluetoothOff: "Bluetooth Is Off"
        case .noMouse: "No Mouse Yet"
        case .noAccess: "Bluetooth Access Is Off"
        }
    }

    private var subtitle: String {
        switch mouse.state {
        case .connecting: "Looking for \(mouse.name)."
        case .connected: "\(mouse.name) is ready to go."
        case .missing: "Turn \(mouse.name) off and on. Tether keeps trying."
        case .bluetoothOff: "Turn on Bluetooth to connect \(mouse.name)."
        case .noMouse: "Connect your mouse once while Tether is open, or pair it in Bluetooth settings. Tether remembers it after that."
        case .noAccess: "Let Tether use Bluetooth in Privacy & Security to reach your mouse."
        }
    }

    private var buttonTitle: String {
        switch mouse.state {
        case .connecting, .connected: "Done"
        case .missing, .bluetoothOff, .noMouse: "Open Bluetooth Settings"
        case .noAccess: "Open Privacy Settings"
        }
    }

    private func primary() {
        if [.connected, .connecting].contains(mouse.state) { return quit() }
        let pane = mouse.state == .noAccess ? "com.apple.preference.security?Privacy_Bluetooth" : "com.apple.BluetoothSettings"
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:\(pane)")!)
    }

    private func quit() { NSApp.terminate(nil) }
}
