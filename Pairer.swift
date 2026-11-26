import AppKit

// MARK: - Pairing a mouse that lost its bond

/// The Incase mouse drops its bond and comes back under a new address, which no public API can pair (IOBluetoothDevicePair
/// is classic only, CoreBluetooth connects but never bonds a HID mouse). What works is the Connect button on the Nearby
/// Devices row in Bluetooth settings, and that button only answers real HID mouse events. Needs Accessibility.
enum Pairer {
    private static var asked = false

    static func askOnce() {
        guard !asked, !AXIsProcessTrusted() else { return }
        asked = true
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
    }

    /// Opens Bluetooth settings and clicks Connect on the nth Nearby row named like a known pointer (a mouse can show twice).
    static func pair(names: Set<String>, nth: Int) {
        guard AXIsProcessTrusted(), !names.isEmpty, let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") else { return }
        NSWorkspace.shared.open(url)
        DispatchQueue.global().asyncAfter(deadline: .now() + 4) { // Nearby Devices takes a few seconds to fill
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences").first else { return }
            app.activate(options: [])
            let rows = nearby(AXUIElementCreateApplication(app.processIdentifier), names: names, depth: 0)
            guard !rows.isEmpty else { return }
            let (text, card) = rows[nth % rows.count]
            let y = text.midY
            // ponytail: Connect sits 42 pt in from the card's right edge in macOS 15-27 Settings; re-measure if Apple moves it.
            for i in 0..<6 { post(.mouseMoved, CGPoint(x: text.minX + 60 + CGFloat(i) * 8, y: y)); usleep(100_000) }
            usleep(600_000)
            let button = CGPoint(x: card.maxX - 42, y: y)
            post(.mouseMoved, button); usleep(500_000)
            post(.leftMouseDown, button); usleep(80_000); post(.leftMouseUp, button)
        }
    }

    private static func post(_ t: CGEventType, _ p: CGPoint) {
        CGEvent(mouseEventSource: nil, mouseType: t, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
    }

    private static func attr(_ e: AXUIElement, _ k: String) -> AnyObject? {
        var v: AnyObject?
        return AXUIElementCopyAttributeValue(e, k as CFString, &v) == .success ? v : nil
    }

    private static func frame(_ e: AXUIElement) -> CGRect? {
        guard let p = attr(e, kAXPositionAttribute), let s = attr(e, kAXSizeAttribute) else { return nil }
        var o = CGPoint.zero, z = CGSize.zero
        AXValueGetValue(p as! AXValue, .cgPoint, &o); AXValueGetValue(s as! AXValue, .cgSize, &z)
        return CGRect(origin: o, size: z)
    }

    private static func children(_ e: AXUIElement) -> [AXUIElement] { attr(e, kAXChildrenAttribute) as? [AXUIElement] ?? [] }

    /// Nearby rows are bare text in a card with no buttons; My Devices rows carry an info button.
    private static func nearby(_ e: AXUIElement, names: Set<String>, depth: Int) -> [(CGRect, CGRect)] {
        guard depth < 20 else { return [] }
        let kids = children(e)
        let roles = kids.map { attr($0, kAXRoleAttribute) as? String }
        if !roles.contains(kAXButtonRole), let card = frame(e) {
            let hits = zip(kids, roles).compactMap { k, r -> (CGRect, CGRect)? in
                guard r == kAXStaticTextRole, let v = (attr(k, kAXValueAttribute) ?? attr(k, kAXTitleAttribute)) as? String,
                      names.contains(v), let f = frame(k) else { return nil }
                return (f, card)
            }
            if !hits.isEmpty { return hits }
        }
        return kids.flatMap { nearby($0, names: names, depth: depth + 1) }
    }
}
