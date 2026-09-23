import AppKit

/// A remap whose keys parsed and whose app (if any) was found.
struct ResolvedRemap {
    let trigger: Combo
    let send: [Combo]
    /// nil means every app.
    let bundleID: String?
    let notWhileTyping: Bool
}

/// Press one combo, send others instead.
final class Remapper {
    private var byTrigger: [Combo: [ResolvedRemap]] = [:]

    func set(_ remaps: [ResolvedRemap]) {
        byTrigger = Dictionary(grouping: remaps, by: \.trigger)
    }

    /// Called from the event tap on key down. Returns true to swallow the key.
    func handle(_ combo: Combo, isRepeat: Bool) -> Bool {
        guard let candidates = byTrigger[combo] else { return false }
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        // A rule for the app in front beats one that applies everywhere.
        guard let rule = candidates.first(where: { $0.bundleID != nil && $0.bundleID == front })
                ?? candidates.first(where: { $0.bundleID == nil })
        else { return false }
        if rule.notWhileTyping && isTypingInTextField() { return false }

        // Holding a single-combo remap repeats it like a real key; a sequence
        // fires once per press.
        if isRepeat && rule.send.count > 1 { return true }
        let send = rule.send
        DispatchQueue.main.async {
            for combo in send { press(Int(combo.keyCode), combo.flags) }
        }
        return true
    }
}
