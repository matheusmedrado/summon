import AppKit
import Carbon.HIToolbox

/// A key plus the exact set of modifiers that must be held.
struct Combo: Hashable {
    let keyCode: Int64
    let modifiers: CGEventFlags.RawValue

    /// Only these count when matching; caps lock, fn and friends are ignored.
    static let relevant: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]

    init(keyCode: Int64, flags: CGEventFlags) {
        self.keyCode = keyCode
        self.modifiers = flags.intersection(Combo.relevant).rawValue
    }

    /// Parses strings like "cmd+e", "cmd+shift+return", "ctrl+opt+space".
    init?(_ text: String) {
        let parts = text.lowercased().split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let keyName = parts.last, let code = Combo.keyCodes[keyName] else { return nil }
        var flags: CGEventFlags = []
        for mod in parts.dropLast() {
            switch mod {
            case "cmd", "command", "⌘": flags.insert(.maskCommand)
            case "opt", "option", "alt", "⌥": flags.insert(.maskAlternate)
            case "ctrl", "control", "⌃": flags.insert(.maskControl)
            case "shift", "⇧": flags.insert(.maskShift)
            default: return nil
            }
        }
        self.init(keyCode: Int64(code), flags: flags)
    }

    init?(event: NSEvent) {
        var flags: CGEventFlags = []
        let mods = event.modifierFlags
        if mods.contains(.command) { flags.insert(.maskCommand) }
        if mods.contains(.option) { flags.insert(.maskAlternate) }
        if mods.contains(.control) { flags.insert(.maskControl) }
        if mods.contains(.shift) { flags.insert(.maskShift) }
        let code = Int64(event.keyCode)
        guard Combo.names[Int(code)] != nil else { return nil }
        self.init(keyCode: code, flags: flags)
    }

    var flags: CGEventFlags { CGEventFlags(rawValue: modifiers) }
    var hasModifier: Bool { modifiers != 0 }
    var name: String { Combo.names[Int(keyCode)] ?? "?" }

    /// Keys that can be a trigger with no modifier held. Letters, digits,
    /// arrows and the like can't: remapping them bare would break typing.
    var canBeBareTrigger: Bool {
        (name.hasPrefix("f") && Int(name.dropFirst()) != nil)
            || ["home", "end", "pageup", "pagedown", "forwarddelete"].contains(name)
    }

    /// Usable as a trigger: has a modifier, or is a key that's safe bare.
    var isValidTrigger: Bool { hasModifier || canBeBareTrigger }

    /// Parses "cmd+a cmd+c": one or more combos separated by spaces.
    static func sequence(_ text: String) -> [Combo]? {
        let combos = text.split(separator: " ").map { Combo(String($0)) }
        guard !combos.isEmpty, !combos.contains(where: { $0 == nil }) else { return nil }
        return combos.compactMap { $0 }
    }

    /// Config spelling, e.g. "cmd+shift+return".
    var text: String {
        var parts: [String] = []
        if flags.contains(.maskControl) { parts.append("ctrl") }
        if flags.contains(.maskAlternate) { parts.append("opt") }
        if flags.contains(.maskShift) { parts.append("shift") }
        if flags.contains(.maskCommand) { parts.append("cmd") }
        parts.append(Combo.names[Int(keyCode)] ?? "?")
        return parts.joined(separator: "+")
    }

    /// Keycap labels in Apple's order: ⌃ ⌥ ⇧ ⌘ then the key.
    var glyphs: [String] {
        var out: [String] = []
        if flags.contains(.maskControl) { out.append("⌃") }
        if flags.contains(.maskAlternate) { out.append("⌥") }
        if flags.contains(.maskShift) { out.append("⇧") }
        if flags.contains(.maskCommand) { out.append("⌘") }
        let name = Combo.names[Int(keyCode)] ?? "?"
        out.append(Combo.symbols[name] ?? name.uppercased())
        return out
    }

    static let symbols: [String: String] = [
        "return": "↩", "space": "Space", "tab": "⇥", "escape": "⎋", "delete": "⌫",
        "forwarddelete": "⌦", "home": "↖", "end": "↘", "pageup": "⇞", "pagedown": "⇟",
        "left": "←", "right": "→", "up": "↑", "down": "↓",
        "minus": "-", "equal": "=", "grave": "`", "comma": ",", "period": ".", "slash": "/",
        "semicolon": ";", "quote": "'", "backslash": "\\", "leftbracket": "[", "rightbracket": "]",
    ]

    /// One canonical name per key code, for writing configs back out.
    static let names: [Int: String] = {
        let aliases: Set = ["enter", "esc", "backspace"]
        return Dictionary(keyCodes.filter { !aliases.contains($0.key) }.map { ($0.value, $0.key) },
                          uniquingKeysWith: { a, _ in a })
    }()

    // Virtual key codes are physical positions (ANSI layout).
    static let keyCodes: [String: Int] = [
        "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E,
        "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J,
        "k": kVK_ANSI_K, "l": kVK_ANSI_L, "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O,
        "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
        "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X, "y": kVK_ANSI_Y,
        "z": kVK_ANSI_Z,
        "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4,
        "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
        "return": kVK_Return, "enter": kVK_Return, "space": kVK_Space, "tab": kVK_Tab,
        "escape": kVK_Escape, "esc": kVK_Escape, "delete": kVK_Delete, "backspace": kVK_Delete,
        "minus": kVK_ANSI_Minus, "equal": kVK_ANSI_Equal, "grave": kVK_ANSI_Grave,
        "comma": kVK_ANSI_Comma, "period": kVK_ANSI_Period, "slash": kVK_ANSI_Slash,
        "semicolon": kVK_ANSI_Semicolon, "quote": kVK_ANSI_Quote, "backslash": kVK_ANSI_Backslash,
        "leftbracket": kVK_ANSI_LeftBracket, "rightbracket": kVK_ANSI_RightBracket,
        "left": kVK_LeftArrow, "right": kVK_RightArrow, "up": kVK_UpArrow, "down": kVK_DownArrow,
        "home": kVK_Home, "end": kVK_End, "pageup": kVK_PageUp, "pagedown": kVK_PageDown,
        "forwarddelete": kVK_ForwardDelete,
        "f1": kVK_F1, "f2": kVK_F2, "f3": kVK_F3, "f4": kVK_F4, "f5": kVK_F5, "f6": kVK_F6,
        "f7": kVK_F7, "f8": kVK_F8, "f9": kVK_F9, "f10": kVK_F10, "f11": kVK_F11, "f12": kVK_F12,
        "f13": kVK_F13, "f14": kVK_F14, "f15": kVK_F15, "f16": kVK_F16, "f17": kVK_F17,
        "f18": kVK_F18, "f19": kVK_F19, "f20": kVK_F20,
    ]
}
