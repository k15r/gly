import AppKit
import Carbon.HIToolbox

/// A system-wide shortcut via Carbon's hot-key API: works in the sandbox without Accessibility permission
/// (quick-capture Q2). One shortcut at a time.
@MainActor
final class GlobalHotKey {
    static let shared = GlobalHotKey()
    var action: (() -> Void)?
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    /// Registers the shortcut, replacing the previous one; false when the system or another app has taken it.
    @discardableResult
    func register(_ shortcut: CaptureShortcut) -> Bool {
        unregister()
        if handler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                DispatchQueue.main.async { MainActor.assumeIsolated { GlobalHotKey.shared.action?() } }
                return noErr
            }, 1, &spec, nil, &handler)
        }
        let id = EventHotKeyID(signature: OSType(0x5744_4351), id: 1)   // 'WDCQ'
        return RegisterEventHotKey(shortcut.keyCode, shortcut.carbonModifiers, id, GetApplicationEventTarget(), 0, &hotKey) == noErr
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
    }
}

/// The capture shortcut as stored per Mac (key code + modifier flags).
struct CaptureShortcut: Equatable {
    var keyCode: UInt32
    var modifiers: NSEvent.ModifierFlags

    static let `default` = CaptureShortcut(keyCode: UInt32(kVK_Space), modifiers: [.control, .option])

    var carbonModifiers: UInt32 {
        var m: UInt32 = 0
        if modifiers.contains(.command) { m |= UInt32(cmdKey) }
        if modifiers.contains(.option) { m |= UInt32(optionKey) }
        if modifiers.contains(.control) { m |= UInt32(controlKey) }
        if modifiers.contains(.shift) { m |= UInt32(shiftKey) }
        return m
    }

    /// "⌃⌥Space"
    var display: String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option) { s += "⌥" }
        if modifiers.contains(.shift) { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        return s + Self.keyName(keyCode)
    }

    static func keyName(_ code: UInt32) -> String {
        switch Int(code) {
        case kVK_Space: return "Space"
        case kVK_Return: return "Return"
        case kVK_Tab: return "Tab"
        default:
            // The character the key produces with the current layout, unshifted.
            guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
                  let data = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return "#\(code)" }
            let layout = unsafeBitCast(data, to: CFData.self)
            var dead: UInt32 = 0, length = 0
            var chars = [UniChar](repeating: 0, count: 4)
            let status = CFDataGetBytePtr(layout).withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) {
                UCKeyTranslate($0, UInt16(code), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                               &dead, chars.count, &length, &chars)
            }
            return status == noErr && length > 0 ? String(utf16CodeUnits: chars, count: length).uppercased() : "#\(code)"
        }
    }

    // Persistence in the app's own defaults (per Mac).
    static func load() -> CaptureShortcut {
        let d = UserDefaults.standard
        guard d.object(forKey: "captureKeyCode") != nil else { return .default }
        return CaptureShortcut(keyCode: UInt32(d.integer(forKey: "captureKeyCode")),
                               modifiers: NSEvent.ModifierFlags(rawValue: UInt(d.integer(forKey: "captureModifiers"))))
    }

    func save() {
        UserDefaults.standard.set(Int(keyCode), forKey: "captureKeyCode")
        UserDefaults.standard.set(Int(modifiers.rawValue), forKey: "captureModifiers")
    }
}
