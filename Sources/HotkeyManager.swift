import AppKit
import Carbon

enum HotkeyChoice: String, CaseIterable, Codable {
    case none
    case fn
    case rightOption
    case rightCommand
    case leftControl
    case custom

    var displayName: String {
        switch self {
        case .none: return "Disabled"
        case .fn: return "FN (Globe)"
        case .rightOption: return "Right Option"
        case .rightCommand: return "Right Command"
        case .leftControl: return "Left Control"
        case .custom: return "Custom Key…"
        }
    }

    var isModifierBased: Bool {
        switch self {
        case .fn, .rightOption, .rightCommand, .leftControl: return true
        case .none, .custom: return false
        }
    }
}

final class HotkeyManager {
    var selectedHotkey: HotkeyChoice = .none
    var customKeyCode: UInt16 = 0
    var onKeyDown: (() -> Void)?
    var onKeyUp: (() -> Void)?

    private var globalFlagsMonitor: Any?
    private var localFlagsMonitor: Any?
    private var globalKeyDownMonitor: Any?
    private var globalKeyUpMonitor: Any?
    private var localKeyDownMonitor: Any?
    private var localKeyUpMonitor: Any?
    private var isKeyDown = false

    func start() {
        stop()
        guard selectedHotkey != .none else { return }

        if selectedHotkey.isModifierBased {
            globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                self?.handleFlags(event)
            }
            localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                self?.handleFlags(event)
                return event
            }
        } else if selectedHotkey == .custom && customKeyCode > 0 {
            globalKeyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handleKeyEvent(event, pressed: true)
            }
            globalKeyUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyUp) { [weak self] event in
                self?.handleKeyEvent(event, pressed: false)
            }
            localKeyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handleKeyEvent(event, pressed: true)
                return event
            }
            localKeyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
                self?.handleKeyEvent(event, pressed: false)
                return event
            }
        }
    }

    func stop() {
        for monitor in [globalFlagsMonitor, localFlagsMonitor, globalKeyDownMonitor, globalKeyUpMonitor, localKeyDownMonitor, localKeyUpMonitor] {
            if let m = monitor { NSEvent.removeMonitor(m) }
        }
        globalFlagsMonitor = nil
        localFlagsMonitor = nil
        globalKeyDownMonitor = nil
        globalKeyUpMonitor = nil
        localKeyDownMonitor = nil
        localKeyUpMonitor = nil
        isKeyDown = false
    }

    private func handleFlags(_ event: NSEvent) {
        let pressed = isModifierPressed(event)

        if pressed && !isKeyDown {
            isKeyDown = true
            onKeyDown?()
        } else if !pressed && isKeyDown {
            isKeyDown = false
            onKeyUp?()
        }
    }

    private func handleKeyEvent(_ event: NSEvent, pressed: Bool) {
        guard event.keyCode == customKeyCode else { return }
        if pressed && !isKeyDown {
            isKeyDown = true
            onKeyDown?()
        } else if !pressed && isKeyDown {
            isKeyDown = false
            onKeyUp?()
        }
    }

    private func isModifierPressed(_ event: NSEvent) -> Bool {
        let raw = event.modifierFlags.rawValue

        switch selectedHotkey {
        case .none, .custom:
            return false
        case .fn:
            return event.keyCode == 63 && event.modifierFlags.contains(.function)
        case .rightOption:
            return raw & 0x40 != 0
        case .rightCommand:
            return raw & 0x10 != 0
        case .leftControl:
            return raw & 0x01 != 0
        }
    }

    // MARK: - Key name display

    static func displayName(forKeyCode keyCode: UInt16) -> String {
        let specialKeys: [UInt16: String] = [
            0x24: "Return", 0x30: "Tab", 0x31: "Space", 0x33: "Delete",
            0x35: "Escape", 0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4",
            0x60: "F5", 0x61: "F6", 0x62: "F7", 0x64: "F8", 0x65: "F9",
            0x6D: "F10", 0x67: "F11", 0x6F: "F12", 0x69: "F13", 0x6B: "F14",
            0x71: "F15", 0x7E: "Up", 0x7D: "Down", 0x7B: "Left", 0x7C: "Right",
            0x73: "Home", 0x77: "End", 0x74: "Page Up", 0x79: "Page Down",
            0x75: "Forward Delete", 0x47: "Clear", 0x72: "Help",
        ]

        if let name = specialKeys[keyCode] { return name }

        // Use Carbon to get the key's character
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        guard let layoutDataPtr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return "Key \(keyCode)"
        }
        let layoutData = unsafeBitCast(layoutDataPtr, to: CFData.self) as Data
        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length: Int = 0

        layoutData.withUnsafeBytes { rawBuf in
            guard let ptr = rawBuf.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return }
            UCKeyTranslate(ptr, keyCode, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                           UInt32(kUCKeyTranslateNoDeadKeysBit), &deadKeyState, 4, &length, &chars)
        }

        if length > 0 {
            return String(utf16CodeUnits: chars, count: length).uppercased()
        }
        return "Key \(keyCode)"
    }
}
