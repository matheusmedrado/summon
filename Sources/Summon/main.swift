import AppKit
import SwiftUI

private let logURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Logs/Summon.log")

/// Appends to ~/Library/Logs/Summon.log (readable in Console.app).
func log(_ message: String) {
    let line = Data("[\(Date())] \(message)\n".utf8)
    if let handle = try? FileHandle(forWritingTo: logURL) {
        handle.seekToEndOfFile()
        handle.write(line)
        try? handle.close()
    } else {
        try? line.write(to: logURL)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private lazy var hotkeys = Hotkeys(onTrigger: summon)
    private let finderCut = FinderCut()
    private let remapper = Remapper()
    private let store = Store()
    private var bindings: [Binding] = []
    private var configWatch: DispatchSourceFileSystemObject?
    private var fileWatch: DispatchSourceFileSystemObject?
    private var permissionPoll: Timer?
    private var activity: NSObjectProtocol?
    private var window: NSWindow?
    private var panel: QuickPanelWindow?
    private var outsideClick: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hotkeys have to answer instantly after hours of idle; never let App Nap throttle us.
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
            reason: "Listening for global hotkeys")

        if let icon = Bundle.main.image(forResource: "MenuIcon") {
            icon.isTemplate = true
            statusItem.button?.image = icon
        } else {
            statusItem.button?.image = NSImage(systemSymbolName: "command", accessibilityDescription: "Summon")
        }
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePanel)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        store.onRecording = { [weak self] in self?.hotkeys.paused = $0 }
        store.onEnabled = { [weak self] enabled in
            self?.hotkeys.enabled = enabled
            self?.updateStatusIcon()
            log(enabled ? "hotkeys resumed" : "hotkeys paused")
        }
        hotkeys.enabled = store.isEnabled
        hotkeys.interceptor = { [finderCut, remapper] combo, isRepeat in
            finderCut.handle(combo, isRepeat: isRepeat) || remapper.handle(combo, isRepeat: isRepeat)
        }

        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(showSettings), name: SingleInstance.showSettings, object: nil)

        reloadConfig()
        watchConfig()
        startHotkeys()
        LoginItem.enableOnFirstLaunch()
        store.opensAtLogin = LoginItem.isEnabled
        store.onOpensAtLogin = { LoginItem.set($0) }
    }

    /// Opening Summon.app again (Finder, Spotlight) shows the settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    private func startHotkeys() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(options), hotkeys.start() {
            log("listening, \(bindings.count) hotkeys")
            listeningChanged()
            return
        }
        // Not trusted yet: explain why in the settings window, and start the
        // moment access is granted.
        listeningChanged()
        showSettings()
        permissionPoll?.invalidate()
        permissionPoll = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self, AXIsProcessTrusted(), self.hotkeys.start() else { return }
            timer.invalidate()
            log("accessibility granted, listening")
            self.listeningChanged()
        }
    }

    private func listeningChanged() {
        store.isListening = hotkeys.isRunning
        updateStatusIcon()
    }

    private func updateStatusIcon() {
        statusItem.button?.appearsDisabled = !hotkeys.isRunning || !store.isEnabled
    }

    @objc private func reloadConfig() {
        var errors: [String] = []
        do {
            let config = try Config.load()
            let resolved = resolve(config)
            bindings = resolved.bindings
            errors = resolved.errors
            remapper.set(resolved.remaps)
            finderCut.enabled = config.finderCut ?? false
            log("config loaded: \(bindings.count) hotkeys, \(resolved.remaps.count) remaps, finder cut \(finderCut.enabled ? "on" : "off")")
            store.load(config, errors: errors)
        } catch {
            errors = ["Config error: \(error.localizedDescription)"]
            store.errors = errors
        }
        errors.forEach { log($0) }
        hotkeys.set(bindings)
    }

    /// Some editors save by replacing the file (seen as a change to the
    /// folder), others write into it in place (seen only on the file). Watch both.
    private func watchConfig() {
        let fd = open(Config.url.deletingLastPathComponent().path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in
            self?.watchFile()  // the file may be a new one now
            self?.reloadConfig()
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        configWatch = source
        watchFile()
    }

    private func watchFile() {
        fileWatch?.cancel()
        let fd = open(Config.url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename], queue: .main)
        source.setEventHandler { [weak self, weak source] in
            // replaced or moved away: follow the new file
            if let events = source?.data, !events.isDisjoint(with: [.delete, .rename]) { self?.watchFile() }
            self?.reloadConfig()
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        fileWatch = source
    }

    // MARK: menu bar panel

    @objc private func togglePanel() {
        panel?.isVisible == true ? closePanel() : showPanel()
    }

    private func showPanel() {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }
        if panel == nil {
            let view = QuickPanel(
                store: store,
                launch: { [weak self] entry in
                    self?.closePanel()
                    self?.launch(entry)
                },
                openRemap: { [weak self] remap in
                    guard let self else { return }
                    self.store.tab = .remaps
                    self.showSettings()
                    self.store.draft = remap
                },
                openSettings: { [weak self] in
                    self?.closePanel()
                    self?.showSettings()
                },
                quit: { NSApp.terminate(nil) })
            let host = NSHostingView(rootView: view)
            let panel = QuickPanelWindow(content: host)
            panel.onClose = { [weak self] in self?.closePanel() }
            self.panel = panel
        }
        guard let panel, let host = panel.contentView else { return }

        // Size to content, then hang it just under the icon, kept on screen.
        let size = host.fittingSize
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = buttonWindow.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
        var x = anchor.midX - size.width / 2
        x = min(max(x, screen.minX + 8), screen.maxX - size.width - 8)
        panel.setFrame(NSRect(x: x, y: anchor.minY - size.height - 6, width: size.width, height: size.height), display: true)

        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            panel.animator().alphaValue = 1
        }
        button.highlight(true)

        // Close on any click outside, like a real menu.
        outsideClick = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePanel()
        }
    }

    private func closePanel() {
        if let outsideClick { NSEvent.removeMonitor(outsideClick) }
        outsideClick = nil
        statusItem.button?.highlight(false)
        // Drop the panel instead of keeping it hidden: its SwiftUI animations
        // repeat forever and would keep rendering offscreen.
        guard let panel else { return }
        self.panel = nil
        guard panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.1
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }

    /// Clicking a row opens the app exactly as its hotkey would.
    private func launch(_ entry: Config.Entry) {
        guard let combo = Combo(entry.keys),
              let binding = bindings.first(where: { $0.combo == combo }) else { return }
        summon(binding)
    }

    // MARK: settings window

    @objc func showSettings() {
        closePanel()
        if window == nil {
            let view = SettingsView(store: store, openAccessibility: {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            })
            let window = NSWindow(contentRect: .zero,
                                  styleMask: [.titled, .closable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            // A hosting controller lets the window grow and shrink with its content.
            let host = NSHostingController(rootView: view)
            host.sizingOptions = [.preferredContentSize]
            window.contentViewController = host
            window.delegate = self
            window.center()
            self.window = window
        }
        store.opensAtLogin = LoginItem.isEnabled
        // Show in the Dock and ⌘-Tab while settings are open.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        store.cancelRecording()
        NSApp.setActivationPolicy(.accessory)
        // Release the window so its SwiftUI animations stop with it.
        DispatchQueue.main.async { self.window = nil }
    }
}

if CommandLine.arguments.contains("--selftest") { exit(SelfTest.run()) }
SingleInstance.handOffIfAlreadyRunning()
dropShellEnvironment()
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
