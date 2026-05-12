import AppKit
import Carbon.HIToolbox
import Foundation

struct HotKeySpec: Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let displayString: String

    static func == (lhs: HotKeySpec, rhs: HotKeySpec) -> Bool {
        lhs.keyCode == rhs.keyCode && lhs.modifiers == rhs.modifiers
    }

    static func parse(_ raw: String) -> HotKeySpec? {
        let parts = raw
            .lowercased()
            .split(separator: "+")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !parts.isEmpty else { return nil }

        var modifiers: UInt32 = 0
        var keyCode: UInt32?

        for part in parts {
            switch part {
            case "option", "alt":
                modifiers |= UInt32(optionKey)
            case "shift":
                modifiers |= UInt32(shiftKey)
            case "command", "cmd":
                modifiers |= UInt32(cmdKey)
            case "control", "ctrl":
                modifiers |= UInt32(controlKey)
            default:
                keyCode = keyCodeForToken(part)
            }
        }

        guard let keyCode else { return nil }
        return HotKeySpec(
            keyCode: keyCode,
            modifiers: modifiers,
            displayString: canonicalDisplayString(keyCode: keyCode, modifiers: modifiers) ?? raw
        )
    }

    static func from(event: NSEvent) -> HotKeySpec? {
        let keyCode = UInt32(event.keyCode)
        guard keyToken(for: keyCode) != nil else { return nil }

        let modifiers = UInt32(event.modifierFlags.intersection(.deviceIndependentFlagsMask).carbonHotKeyModifiers)
        guard hasRequiredShortcutModifier(modifiers) else { return nil }
        guard let displayString = canonicalDisplayString(keyCode: keyCode, modifiers: modifiers) else { return nil }

        return HotKeySpec(keyCode: keyCode, modifiers: modifiers, displayString: displayString)
    }

    var userVisibleString: String {
        Self.userVisibleString(keyCode: keyCode, modifiers: modifiers) ?? displayString
    }

    func matches(_ event: NSEvent) -> Bool {
        let eventModifiers = UInt32(event.modifierFlags.intersection(.deviceIndependentFlagsMask).carbonHotKeyModifiers)
        return UInt32(event.keyCode) == keyCode && eventModifiers == modifiers
    }

    private static func canonicalDisplayString(keyCode: UInt32, modifiers: UInt32) -> String? {
        guard let key = keyToken(for: keyCode) else { return nil }
        let modifierTokens = modifierDefinitions
            .filter { modifiers & $0.mask != 0 }
            .map(\.token)
        return (modifierTokens + [key.token])
            .joined(separator: "+")
    }

    private static func userVisibleString(keyCode: UInt32, modifiers: UInt32) -> String? {
        guard let key = keyToken(for: keyCode) else { return nil }
        let modifierSymbols = modifierDefinitions
            .filter { modifiers & $0.mask != 0 }
            .map(\.symbol)
            .joined()
        return modifierSymbols + key.display
    }

    private static func hasRequiredShortcutModifier(_ modifiers: UInt32) -> Bool {
        modifiers & UInt32(cmdKey) != 0 ||
            modifiers & UInt32(optionKey) != 0 ||
            modifiers & UInt32(controlKey) != 0
    }

    private static func keyCodeForToken(_ token: String) -> UInt32? {
        if token == "enter" { return keyTokenMap["return"]?.keyCode }
        return keyTokenMap[token]?.keyCode
    }

    private static func keyToken(for keyCode: UInt32) -> KeyToken? {
        keyCodeMap[keyCode]
    }
}

private struct KeyToken {
    let token: String
    let display: String
    let keyCode: UInt32
}

private let modifierDefinitions: [(token: String, symbol: String, mask: UInt32)] = [
    ("control", "⌃", UInt32(controlKey)),
    ("option", "⌥", UInt32(optionKey)),
    ("shift", "⇧", UInt32(shiftKey)),
    ("command", "⌘", UInt32(cmdKey))
]

private let keyTokens: [KeyToken] = [
    KeyToken(token: "a", display: "A", keyCode: UInt32(kVK_ANSI_A)),
    KeyToken(token: "b", display: "B", keyCode: UInt32(kVK_ANSI_B)),
    KeyToken(token: "c", display: "C", keyCode: UInt32(kVK_ANSI_C)),
    KeyToken(token: "d", display: "D", keyCode: UInt32(kVK_ANSI_D)),
    KeyToken(token: "e", display: "E", keyCode: UInt32(kVK_ANSI_E)),
    KeyToken(token: "f", display: "F", keyCode: UInt32(kVK_ANSI_F)),
    KeyToken(token: "g", display: "G", keyCode: UInt32(kVK_ANSI_G)),
    KeyToken(token: "h", display: "H", keyCode: UInt32(kVK_ANSI_H)),
    KeyToken(token: "i", display: "I", keyCode: UInt32(kVK_ANSI_I)),
    KeyToken(token: "j", display: "J", keyCode: UInt32(kVK_ANSI_J)),
    KeyToken(token: "k", display: "K", keyCode: UInt32(kVK_ANSI_K)),
    KeyToken(token: "l", display: "L", keyCode: UInt32(kVK_ANSI_L)),
    KeyToken(token: "m", display: "M", keyCode: UInt32(kVK_ANSI_M)),
    KeyToken(token: "n", display: "N", keyCode: UInt32(kVK_ANSI_N)),
    KeyToken(token: "o", display: "O", keyCode: UInt32(kVK_ANSI_O)),
    KeyToken(token: "p", display: "P", keyCode: UInt32(kVK_ANSI_P)),
    KeyToken(token: "q", display: "Q", keyCode: UInt32(kVK_ANSI_Q)),
    KeyToken(token: "r", display: "R", keyCode: UInt32(kVK_ANSI_R)),
    KeyToken(token: "s", display: "S", keyCode: UInt32(kVK_ANSI_S)),
    KeyToken(token: "t", display: "T", keyCode: UInt32(kVK_ANSI_T)),
    KeyToken(token: "u", display: "U", keyCode: UInt32(kVK_ANSI_U)),
    KeyToken(token: "v", display: "V", keyCode: UInt32(kVK_ANSI_V)),
    KeyToken(token: "w", display: "W", keyCode: UInt32(kVK_ANSI_W)),
    KeyToken(token: "x", display: "X", keyCode: UInt32(kVK_ANSI_X)),
    KeyToken(token: "y", display: "Y", keyCode: UInt32(kVK_ANSI_Y)),
    KeyToken(token: "z", display: "Z", keyCode: UInt32(kVK_ANSI_Z)),
    KeyToken(token: "0", display: "0", keyCode: UInt32(kVK_ANSI_0)),
    KeyToken(token: "1", display: "1", keyCode: UInt32(kVK_ANSI_1)),
    KeyToken(token: "2", display: "2", keyCode: UInt32(kVK_ANSI_2)),
    KeyToken(token: "3", display: "3", keyCode: UInt32(kVK_ANSI_3)),
    KeyToken(token: "4", display: "4", keyCode: UInt32(kVK_ANSI_4)),
    KeyToken(token: "5", display: "5", keyCode: UInt32(kVK_ANSI_5)),
    KeyToken(token: "6", display: "6", keyCode: UInt32(kVK_ANSI_6)),
    KeyToken(token: "7", display: "7", keyCode: UInt32(kVK_ANSI_7)),
    KeyToken(token: "8", display: "8", keyCode: UInt32(kVK_ANSI_8)),
    KeyToken(token: "9", display: "9", keyCode: UInt32(kVK_ANSI_9)),
    KeyToken(token: "space", display: "Space", keyCode: UInt32(kVK_Space)),
    KeyToken(token: "return", display: "↩", keyCode: UInt32(kVK_Return)),
    KeyToken(token: "tab", display: "Tab", keyCode: UInt32(kVK_Tab)),
    KeyToken(token: "delete", display: "⌫", keyCode: UInt32(kVK_Delete)),
    KeyToken(token: "forward-delete", display: "⌦", keyCode: UInt32(kVK_ForwardDelete)),
    KeyToken(token: "escape", display: "Esc", keyCode: UInt32(kVK_Escape)),
    KeyToken(token: "comma", display: ",", keyCode: UInt32(kVK_ANSI_Comma)),
    KeyToken(token: "period", display: ".", keyCode: UInt32(kVK_ANSI_Period)),
    KeyToken(token: "slash", display: "/", keyCode: UInt32(kVK_ANSI_Slash)),
    KeyToken(token: "semicolon", display: ";", keyCode: UInt32(kVK_ANSI_Semicolon)),
    KeyToken(token: "quote", display: "'", keyCode: UInt32(kVK_ANSI_Quote)),
    KeyToken(token: "minus", display: "-", keyCode: UInt32(kVK_ANSI_Minus)),
    KeyToken(token: "equal", display: "=", keyCode: UInt32(kVK_ANSI_Equal)),
    KeyToken(token: "left-bracket", display: "[", keyCode: UInt32(kVK_ANSI_LeftBracket)),
    KeyToken(token: "right-bracket", display: "]", keyCode: UInt32(kVK_ANSI_RightBracket)),
    KeyToken(token: "backslash", display: "\\", keyCode: UInt32(kVK_ANSI_Backslash)),
    KeyToken(token: "grave", display: "`", keyCode: UInt32(kVK_ANSI_Grave)),
    KeyToken(token: "f1", display: "F1", keyCode: UInt32(kVK_F1)),
    KeyToken(token: "f2", display: "F2", keyCode: UInt32(kVK_F2)),
    KeyToken(token: "f3", display: "F3", keyCode: UInt32(kVK_F3)),
    KeyToken(token: "f4", display: "F4", keyCode: UInt32(kVK_F4)),
    KeyToken(token: "f5", display: "F5", keyCode: UInt32(kVK_F5)),
    KeyToken(token: "f6", display: "F6", keyCode: UInt32(kVK_F6)),
    KeyToken(token: "f7", display: "F7", keyCode: UInt32(kVK_F7)),
    KeyToken(token: "f8", display: "F8", keyCode: UInt32(kVK_F8)),
    KeyToken(token: "f9", display: "F9", keyCode: UInt32(kVK_F9)),
    KeyToken(token: "f10", display: "F10", keyCode: UInt32(kVK_F10)),
    KeyToken(token: "f11", display: "F11", keyCode: UInt32(kVK_F11)),
    KeyToken(token: "f12", display: "F12", keyCode: UInt32(kVK_F12))
]

private let keyTokenMap = Dictionary(uniqueKeysWithValues: keyTokens.map { ($0.token, $0) })
private let keyCodeMap = Dictionary(uniqueKeysWithValues: keyTokens.map { ($0.keyCode, $0) })

final class GlobalHotKeyManager {
    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var eventHandlerRef: EventHandlerRef?
    private let signature = OSType(0x514d444b)
    private var handlers: [UInt32: () -> Void] = [:]

    func register(_ spec: HotKeySpec, id: UInt32, handler: @escaping () -> Void) -> Bool {
        unregister(id: id)
        handlers[id] = handler

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return noErr }

            let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )

            guard status == noErr,
                  hotKeyID.signature == manager.signature else {
                return noErr
            }

            manager.handlers[hotKeyID.id]?()
            return noErr
        }

        if eventHandlerRef == nil {
            let installStatus = InstallEventHandler(
                GetApplicationEventTarget(),
                callback,
                1,
                &eventType,
                UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
                &eventHandlerRef
            )

            guard installStatus == noErr else {
                handlers[id] = nil
                return false
            }
        }

        let hotKeyID = EventHotKeyID(signature: signature, id: id)
        var hotKeyRef: EventHotKeyRef?
        let registerStatus = RegisterEventHotKey(
            spec.keyCode,
            spec.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if registerStatus != noErr {
            handlers[id] = nil
            if handlers.isEmpty, let eventHandlerRef {
                RemoveEventHandler(eventHandlerRef)
                self.eventHandlerRef = nil
            }
            return false
        }

        if let hotKeyRef {
            hotKeyRefs[id] = hotKeyRef
        }
        return true
    }

    func unregister(id: UInt32) {
        handlers[id] = nil

        if let hotKeyRef = hotKeyRefs[id] {
            UnregisterEventHotKey(hotKeyRef)
            hotKeyRefs[id] = nil
        }

        if handlers.isEmpty, let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    func unregisterAll() {
        let ids = Array(hotKeyRefs.keys)
        ids.forEach(unregister(id:))
        handlers.removeAll()
    }

    deinit {
        unregisterAll()
    }
}

private extension NSEvent.ModifierFlags {
    var carbonHotKeyModifiers: Int {
        var result = 0
        if contains(.command) { result |= cmdKey }
        if contains(.option) { result |= optionKey }
        if contains(.shift) { result |= shiftKey }
        if contains(.control) { result |= controlKey }
        return result
    }
}
