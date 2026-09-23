import AppKit
import UniformTypeIdentifiers

/// What the settings window shows and edits. Saving writes config.json; the
/// folder watcher then reloads it into the hotkey tap like any other edit.
final class Store: ObservableObject {
    @Published var entries: [Config.Entry] = []
    @Published var remaps: [Config.Remap] = []
    @Published var finderCut = false
    @Published var errors: [String] = []
    @Published var isListening = false
    /// Which tab the settings window shows.
    @Published var tab = SettingsView.Tab.apps
    /// The remap open in the editor sheet.
    @Published var draft: Config.Remap?
    @Published var recordingID: UUID? {
        didSet { onRecording(recordingID != nil) }
    }

    /// The on/off switch in the menu bar panel; remembered across launches.
    @Published var isEnabled = UserDefaults.standard.object(forKey: "enabled") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "enabled")
            onEnabled(isEnabled)
        }
    }

    @Published var opensAtLogin = false

    var onRecording: (Bool) -> Void = { _ in }
    var onEnabled: (Bool) -> Void = { _ in }
    var onOpensAtLogin: (Bool) -> Void = { _ in }

    func setOpensAtLogin(_ on: Bool) {
        opensAtLogin = on
        onOpensAtLogin(on)
    }

    /// Takes a freshly loaded config. Lists that only echo our own save are
    /// left alone, so rows keep their identity (and an in-progress recording
    /// survives).
    func load(_ config: Config, errors: [String]) {
        self.errors = errors
        finderCut = config.finderCut ?? false
        if !Store.sameEntries(entries.filter { !$0.keys.isEmpty }, config.bindings) {
            entries = config.bindings
        }
        let loaded = config.remaps ?? []
        if !Store.sameRemaps(remaps, loaded) {
            remaps = loaded
        }
    }

    func save() {
        do {
            try Config(bindings: entries.filter { !$0.keys.isEmpty },
                       remaps: remaps,
                       finderCut: finderCut).save()
        } catch {
            errors = ["Couldn't save: \(error.localizedDescription)"]
        }
    }

    // MARK: app hotkeys

    func setKeys(_ combo: Combo, for id: UUID) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[i].keys = combo.text
        recordingID = nil
        save()
    }

    func cancelRecording() {
        // a row added but never given keys has nothing to keep
        entries.removeAll { $0.id == recordingID && $0.keys.isEmpty }
        recordingID = nil
    }

    func toggleNewWindow(_ id: UUID) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[i].newWindow = !(entries[i].newWindow ?? true) ? nil : false
        save()
    }

    func remove(_ id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }

    /// Picks an app, adds a row for it and starts recording its hotkey.
    func addApp() {
        guard let url = Store.pickApp() else { return }
        let entry = Config.Entry(keys: "", app: Store.configName(for: url))
        entries.append(entry)
        recordingID = entry.id
    }

    func changeApp(_ id: UUID) {
        guard let url = Store.pickApp(),
              let i = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[i].app = Store.configName(for: url)
        save()
    }

    /// Another app hotkey, or a remap that applies everywhere, uses the same keys.
    func conflicts(_ entry: Config.Entry) -> Bool {
        guard let combo = Combo(entry.keys) else { return false }
        return entries.contains { $0.id != entry.id && Combo($0.keys) == combo }
            || remaps.contains { $0.app == nil && Combo($0.keys) == combo }
    }

    // MARK: remaps

    func newRemap() {
        draft = Config.Remap(keys: "", send: "")
    }

    func edit(_ remap: Config.Remap) {
        draft = remap
    }

    func saveRemap(_ remap: Config.Remap) {
        if let i = remaps.firstIndex(where: { $0.id == remap.id }) {
            remaps[i] = remap
        } else {
            remaps.append(remap)
        }
        draft = nil
        save()
    }

    func removeRemap(_ id: UUID) {
        remaps.removeAll { $0.id == id }
        save()
    }

    func setFinderCut(_ on: Bool) {
        finderCut = on
        save()
    }

    /// Why this remap clashes with something else, if it does.
    func conflict(for remap: Config.Remap) -> String? {
        guard let combo = Combo(remap.keys) else { return nil }
        if remaps.contains(where: { $0.id != remap.id && $0.app == remap.app && Combo($0.keys) == combo }) {
            return "Another remap already uses these keys here"
        }
        if remap.app == nil, entries.contains(where: { Combo($0.keys) == combo }) {
            return "Also an app hotkey; this remap wins"
        }
        return nil
    }

    // MARK: presets

    struct Preset: Identifiable {
        let id: String
        let title: String
        let remaps: [Config.Remap]
    }

    static let presets = [
        Preset(id: "home-end", title: "Home and End jump to line start and end", remaps: [
            .init(keys: "home", send: "cmd+left"),
            .init(keys: "end", send: "cmd+right"),
            .init(keys: "shift+home", send: "shift+cmd+left"),
            .init(keys: "shift+end", send: "shift+cmd+right"),
        ]),
        Preset(id: "ctrl-delete", title: "⌃⌫ deletes the previous word", remaps: [
            .init(keys: "ctrl+delete", send: "opt+delete"),
        ]),
    ]

    func isAdded(_ preset: Preset) -> Bool {
        preset.remaps.allSatisfy { p in remaps.contains { Store.sameRemap($0, p) } }
    }

    func add(_ preset: Preset) {
        for remap in preset.remaps where !remaps.contains(where: { Store.sameRemap($0, remap) }) {
            remaps.append(Config.Remap(keys: remap.keys, send: remap.send, app: remap.app,
                                       notWhileTyping: remap.notWhileTyping))
        }
        save()
    }

    // MARK: helpers

    private static func sameEntries(_ a: [Config.Entry], _ b: [Config.Entry]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy {
            $0.keys == $1.keys && $0.app == $1.app && ($0.newWindow ?? true) == ($1.newWindow ?? true)
        }
    }

    private static func sameRemap(_ a: Config.Remap, _ b: Config.Remap) -> Bool {
        a.keys == b.keys && a.send == b.send && a.app == b.app
            && (a.notWhileTyping ?? false) == (b.notWhileTyping ?? false)
    }

    private static func sameRemaps(_ a: [Config.Remap], _ b: [Config.Remap]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy(sameRemap)
    }

    static func pickApp() -> URL? {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.prompt = "Choose"
        panel.message = "Pick an app"
        NSApp.activate(ignoringOtherApps: true)
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// The plain app name when that resolves back to the same app, else the full path.
    static func configName(for url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
        return findApp(name)?.standardizedFileURL == url.resolvingSymlinksInPath().standardizedFileURL ? name : url.path
    }
}
