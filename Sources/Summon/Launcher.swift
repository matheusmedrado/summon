import AppKit
import Carbon.HIToolbox

/// Opens the app the way clicking its Dock icon does: launches it if needed,
/// brings it forward, and lets it open a window if it has none.
/// If it's already frontmost, presses ⌘N in it for another window. With
/// `.always`, also presses ⌘N once it comes forward, unless it had no
/// windows (it opens one itself then).
func summon(_ binding: Binding) {
    if binding.newWindow != .off, let id = binding.bundleID,
       NSWorkspace.shared.frontmostApplication?.bundleIdentifier == id {
        press(kVK_ANSI_N, .maskCommand)
        return
    }
    if binding.newWindow == .always, let id = binding.bundleID,
       let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first,
       hasWindows(app.processIdentifier) {
        whenFrontmost(id) { press(kVK_ANSI_N, .maskCommand) }
    }
    let config = NSWorkspace.OpenConfiguration()
    config.activates = true
    NSWorkspace.shared.openApplication(at: binding.appURL, configuration: config) { _, error in
        if let error { log("couldn't open \(binding.appURL.lastPathComponent): \(error.localizedDescription)") }
    }
}

/// True when the process has a regular window, on any Space or minimized.
private func hasWindows(_ pid: pid_t) -> Bool {
    let windows = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    return windows.contains {
        ($0[kCGWindowOwnerPID as String] as? pid_t) == pid && ($0[kCGWindowLayer as String] as? Int) == 0
    }
}

/// Runs `action` once the app is in front, checking for up to a second.
private func whenFrontmost(_ id: String, tries: Int = 50, _ action: @escaping () -> Void) {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == id {
            action()
        } else if tries > 0 {
            whenFrontmost(id, tries: tries - 1, action)
        } else {
            log("\(id) didn't come forward, no new window")
        }
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
