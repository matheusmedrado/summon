import AppKit
import Carbon.HIToolbox

/// Opens the app the way clicking its Dock icon does: launches it if needed,
/// brings it forward, and lets it open a window if it has none.
/// If it's already frontmost, presses ⌘N in it for another window.
func summon(_ binding: Binding) {
    if binding.newWindow, let id = binding.bundleID,
       NSWorkspace.shared.frontmostApplication?.bundleIdentifier == id {
        press(kVK_ANSI_N, .maskCommand)
        return
    }
    let config = NSWorkspace.OpenConfiguration()
    config.activates = true
    NSWorkspace.shared.openApplication(at: binding.appURL, configuration: config) { _, error in
        if let error { log("couldn't open \(binding.appURL.lastPathComponent): \(error.localizedDescription)") }
    }
}

/// Apps opened with NSWorkspace inherit Summon's environment. When Summon
/// itself was started from a terminal (`open`, `./build.sh install`), that
/// is the shell's: TERM, prompt settings, whatever the terminal session set.
/// Keep only what launchd gives an app opened from the Dock, so summoned
/// apps start as if clicked there.
func dropShellEnvironment() {
    let keep: Set<String> = [
        "HOME", "USER", "LOGNAME", "SHELL", "PATH", "TMPDIR", "LANG",
        "SSH_AUTH_SOCK", "COMMAND_MODE", "XPC_FLAGS", "XPC_SERVICE_NAME",
        "__CF_USER_TEXT_ENCODING", "__CFBundleIdentifier", "SUMMON_AGENT",
    ]
    for name in ProcessInfo.processInfo.environment.keys where !keep.contains(name) {
        unsetenv(name)
    }
}

/// Posts a key press that Summon's own tap will let through.
func press(_ key: Int, _ flags: CGEventFlags) {
    var flags = flags
    // Real arrow and navigation keys always carry these; some apps check.
    if [kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow].contains(key) {
        flags.formUnion([.maskNumericPad, .maskSecondaryFn])
    } else if [kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown, kVK_ForwardDelete].contains(key) {
        flags.insert(.maskSecondaryFn)
    }
    let source = CGEventSource(stateID: .hidSystemState)
    for down in [true, false] {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(key), keyDown: down) else { continue }
        event.flags = flags
        event.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
        event.post(tap: .cgSessionEventTap)
    }
}
