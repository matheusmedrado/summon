import AppKit
import Carbon.HIToolbox

/// ⌘X / ⌘V for files in Finder, the way Linux file managers do it.
/// Finder can only move files through ⌘C then ⌥⌘V, so ⌘X becomes a copy that
/// arms a move, and the next ⌘V in Finder becomes ⌥⌘V. Copying anything else
/// in between disarms it, and text fields (rename, search) keep normal cut/paste.
final class FinderCut {
    var enabled = false

    /// Pasteboard change count of the copy our ⌘X made; nil when nothing is armed.
    private var armed: Int?

    /// Called from the event tap on key down. Returns true to swallow the key.
    func handle(_ combo: Combo, isRepeat: Bool) -> Bool {
        guard enabled, !isRepeat,
              combo.modifiers == CGEventFlags.maskCommand.rawValue,
              combo.keyCode == Int64(kVK_ANSI_X) || combo.keyCode == Int64(kVK_ANSI_V),
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder",
              !isTypingInTextField()
        else { return false }

        if combo.keyCode == Int64(kVK_ANSI_X) {
            cut()
            return true
        }

        // ⌘V: only a move if our cut is still what's on the pasteboard.
        let cutIsCurrent = armed == NSPasteboard.general.changeCount
        armed = nil
        guard cutIsCurrent else { return false }
        DispatchQueue.main.async { press(kVK_ANSI_V, [.maskCommand, .maskAlternate]) }
        return true
    }

    private func cut() {
        let before = NSPasteboard.general.changeCount
        armed = nil
        DispatchQueue.main.async { press(kVK_ANSI_C, .maskCommand) }
        waitForCopy(since: before, tries: 20)
    }

    /// Finder fills the pasteboard asynchronously; arm as soon as it has.
    /// If nothing changes (no files selected), nothing gets armed.
    private func waitForCopy(since before: Int, tries: Int) {
        guard tries > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            let now = NSPasteboard.general.changeCount
            if now != before {
                self?.armed = now
            } else {
                self?.waitForCopy(since: before, tries: tries - 1)
            }
        }
    }
}
