import AppKit
import ServiceManagement

/// Starts Summon at login as a regular login item, like any other app.
enum LoginItem {
    private static let service = SMAppService.mainApp
    /// Older versions started at login through a launchd agent. Without a
    /// Team ID, launchd pins that agent to the exact build it was registered
    /// from, so after any update it refused to start Summon at login. Its
    /// plist stays in the bundle only so the old registration can be removed.
    private static let oldAgent = SMAppService.agent(plistName: "com.matheusmedrado.summon.plist")

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
        migrateFromAgent()
        log("open at login status: \(service.status.rawValue) (0 not registered, 1 enabled, 2 needs approval, 3 not found)")
        let key = "loginItemConfigured"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        if !isEnabled { set(true) }
    }

    /// Moves an old agent registration over to the login item, keeping the
    /// user's on/off choice. Skipped when the agent itself started this copy,
    /// since unregistering the agent would stop it; the next launch by hand
    /// (or after an update breaks the agent) does it instead.
    private static func migrateFromAgent() {
        guard ProcessInfo.processInfo.environment["SUMMON_AGENT"] == nil else { return }
        let status = oldAgent.status
        guard status == .enabled || status == .requiresApproval else { return }
        do {
            try oldAgent.unregister()
            log("removed old launchd agent")
        } catch {
            log("couldn't remove old launchd agent: \(error.localizedDescription)")
        }
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
