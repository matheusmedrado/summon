import AppKit
import ServiceManagement

/// Starts Summon at login through launchd, from the agent plist inside the
/// app bundle: it runs as soon as you log in and is restarted if it crashes.
enum LoginItem {
    private static let service = SMAppService.agent(plistName: "com.matheusmedrado.summon.plist")

    static var isEnabled: Bool { service.status == .enabled }
    static var needsApproval: Bool { service.status == .requiresApproval }

    static func set(_ on: Bool) {
        do {
            if on { try service.register() } else { try service.unregister() }
            log(on ? "open at login on" : "open at login off")
        } catch {
            log("couldn't change open at login: \(error.localizedDescription)")
        }
    }

    /// On by default: turned on once, on first launch, and left to the user after.
    static func enableOnFirstLaunch() {
        log("open at login status: \(service.status.rawValue) (0 not registered, 1 enabled, 2 needs approval, 3 not found)")
        let key = "loginItemConfigured"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        if !isEnabled { set(true) }
    }
}

/// Only one Summon at a time. A second copy (opened from Finder, or started
/// by launchd while one is already running) hands over and quits.
enum SingleInstance {
    static let showSettings = Notification.Name("com.matheusmedrado.summon.show")

    static func handOffIfAlreadyRunning() {
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: "com.matheusmedrado.summon")
            .filter { $0 != .current }
        guard !others.isEmpty else { return }
        // Opened by hand: show the running copy's settings. Started by
        // launchd: nothing to show, just step aside.
        if ProcessInfo.processInfo.environment["SUMMON_AGENT"] == nil {
            DistributedNotificationCenter.default().postNotificationName(
                showSettings, object: nil, userInfo: nil, deliverImmediately: true)
        }
        exit(0)
    }
}
