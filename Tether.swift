// Tether: reconnects the paired Bluetooth mouse with no pointer needed.
// Open it from Spotlight, it connects on its own, Return closes it. Build: ./build.sh
import IOBluetooth
import SwiftUI

@main struct TetherApp: App {
    @NSApplicationDelegateAdaptor private var delegate: Delegate
    var body: some Scene {
        Window("Tether", id: "main") { ContentView() }
            .windowResizability(.contentSize)
            .windowStyle(.hiddenTitleBar)
    }
}

extension Color {
    static let brand = Color(red: 0x16 / 255, green: 0x99 / 255, blue: 0x4a / 255)
}

final class Delegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }
    func applicationDidFinishLaunching(_ n: Notification) { NSApp.activate() }
}

@MainActor @Observable final class Mouse {
    enum State { case connecting, connected, missing, bluetoothOff }
    var state = State.connecting
    var name = "Mouse"
    private var loop: Task<Void, Never>?

    // ponytail: matches by name. Re-pairing gives the mouse a new address, so every paired one gets tried at once.
    private static func mice() -> [IOBluetoothDevice] {
        (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? [])
            .filter { ($0.name ?? "").localizedCaseInsensitiveContains("mouse") }
    }

    private static var connected: IOBluetoothDevice? { mice().first { $0.isConnected() } }

    func start() {
        loop?.cancel()
        loop = Task {
            while !Task.isCancelled {
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
        guard IOBluetoothHostController.default()?.powerState == kBluetoothHCIPowerStateON else {
            state = .bluetoothOff
            return
        }
        let all = Self.mice()
        if let first = all.first { name = first.name ?? name }
        if state != .missing { state = .connecting }
        // openConnection blocks for ~15s on a dead address, so each one runs on its own thread.
        for address in all.compactMap(\.addressString) {
            Thread.detachNewThread { _ = IOBluetoothDevice(addressString: address)?.openConnection() }
        }
        for _ in 0..<20 {
            try? await Task.sleep(for: .milliseconds(500))
            if Self.connected != nil { state = .connected; return }
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
                .font(.title2.weight(.semibold))
                .padding(.bottom, 6)

            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 36, alignment: .top)
                .padding(.bottom, 24)

            Button(action: primary) {
                Text(buttonTitle).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.extraLarge)
            .keyboardShortcut(.defaultAction)
            .disabled(mouse.state == .connecting)

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
        default: "computermouse.fill"
        }
    }

    private var tint: Color {
        switch mouse.state {
        case .connected: .brand
        case .missing, .bluetoothOff: .orange
        case .connecting: .secondary
        }
    }

    private var title: String {
        switch mouse.state {
        case .connecting: "Connecting"
        case .connected: "Connected"
        case .missing: "Mouse Not Responding"
        case .bluetoothOff: "Bluetooth Is Off"
        }
    }

    private var subtitle: String {
        switch mouse.state {
        case .connecting: "Looking for \(mouse.name)."
        case .connected: "\(mouse.name) is ready to go."
        case .missing: "Flip the switch underneath off and on. Tether keeps trying."
        case .bluetoothOff: "Turn on Bluetooth to connect \(mouse.name)."
        }
    }

    private var buttonTitle: String {
        switch mouse.state {
        case .connecting, .connected: "Done"
        case .missing, .bluetoothOff: "Open Bluetooth Settings"
        }
    }

    private func primary() {
        if mouse.state == .connected { return quit() }
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")!)
    }

    private func quit() { NSApp.terminate(nil) }
}
