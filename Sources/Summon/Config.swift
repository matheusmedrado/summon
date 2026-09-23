import AppKit

struct Config: Codable {
    struct Entry: Codable, Equatable, Identifiable {
        var id = UUID()
        var keys: String
        var app: String
        /// When the app is already frontmost, press ⌘N in it for a fresh window.
        var newWindow: Bool?

        enum CodingKeys: String, CodingKey { case keys, app, newWindow }
    }

    /// Press one combo, Summon sends others instead.
    struct Remap: Codable, Equatable, Identifiable {
        var id = UUID()
        var keys: String
        /// One or more combos separated by spaces, sent in order.
        var send: String
        /// Only in this app (name, bundle ID or path); nil means everywhere.
        var app: String?
        /// Leave the keys alone while a text field has focus.
        var notWhileTyping: Bool?

        enum CodingKeys: String, CodingKey { case keys, send, app, notWhileTyping }
    }

    var bindings: [Entry]
    var remaps: [Remap]?
    /// ⌘X / ⌘V moves files in Finder (see FinderCut).
    var finderCut: Bool?

    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/summon/config.json")

    static let starter = """
    {
      "bindings": [
        { "keys": "cmd+e",      "app": "Finder" },
        { "keys": "cmd+b",      "app": "Safari" },
        { "keys": "cmd+return", "app": "Ghostty" }
      ],
      "finderCut": true
    }

    """

    static func load() throws -> Config {
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try starter.write(to: url, atomically: true, encoding: .utf8)
        }
        return try JSONDecoder().decode(Config.self, from: Data(contentsOf: url))
    }

    /// Writes one object per line with the first field padded so the rest
    /// line up, the same shape as the starter file, so it stays pleasant to
    /// edit by hand.
    func save(to url: URL = Config.url) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        func quoted(_ s: String) -> String {
            String(data: try! encoder.encode(s), encoding: .utf8)!
        }

        func list(_ name: String, _ rows: [[(key: String, value: String)]]) -> String {
            guard !rows.isEmpty else { return "  \"\(name)\": []" }
            let width = (rows.map { ($0.first?.value.count ?? 0) + 1 }.max() ?? 0)
            let lines = rows.map { fields -> String in
                var line = "    { "
                for (i, field) in fields.enumerated() {
                    let last = i == fields.count - 1
                    if i == 0 && !last {
                        line += "\"\(field.key)\": " + (field.value + ",").padding(toLength: width, withPad: " ", startingAt: 0) + " "
                    } else {
                        line += "\"\(field.key)\": \(field.value)" + (last ? " " : ", ")
                    }
                }
                return line + "}"
            }
            return "  \"\(name)\": [\n" + lines.joined(separator: ",\n") + "\n  ]"
        }

        var sections = [list("bindings", bindings.map { entry in
            var fields = [("keys", quoted(entry.keys)), ("app", quoted(entry.app))]
            if entry.newWindow == false { fields.append(("newWindow", "false")) }
            return fields.map { (key: $0.0, value: $0.1) }
        })]
        if let remaps, !remaps.isEmpty {
            sections.append(list("remaps", remaps.map { remap in
                var fields = [("keys", quoted(remap.keys)), ("send", quoted(remap.send))]
                if let app = remap.app { fields.append(("app", quoted(app))) }
                if remap.notWhileTyping == true { fields.append(("notWhileTyping", "true")) }
                return fields.map { (key: $0.0, value: $0.1) }
            }))
        }
        if let finderCut { sections.append("  \"finderCut\": \(finderCut)") }

        let text = "{\n" + sections.joined(separator: ",\n") + "\n}\n"
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}

/// A config entry that parsed and whose app exists.
struct Binding {
    let combo: Combo
    let keys: String
    let appURL: URL
    let bundleID: String?
    let newWindow: Bool
}

struct Resolved {
    var bindings: [Binding] = []
    var remaps: [ResolvedRemap] = []
    var errors: [String] = []
}

/// Turns config entries into bindings and remaps, collecting a readable
/// error for each bad one.
func resolve(_ config: Config) -> Resolved {
    var out = Resolved()
    for entry in config.bindings {
        guard let combo = Combo(entry.keys) else {
            out.errors.append("Unknown keys \"\(entry.keys)\"")
            continue
        }
        guard let url = findApp(entry.app) else {
            out.errors.append("App not found: \"\(entry.app)\"")
            continue
        }
        out.bindings.append(Binding(combo: combo, keys: entry.keys, appURL: url,
                                    bundleID: Bundle(url: url)?.bundleIdentifier,
                                    newWindow: entry.newWindow ?? true))
    }
    for remap in config.remaps ?? [] {
        guard let trigger = Combo(remap.keys) else {
            out.errors.append("Unknown keys \"\(remap.keys)\"")
            continue
        }
        guard let send = Combo.sequence(remap.send) else {
            out.errors.append("Unknown keys to send \"\(remap.send)\"")
            continue
        }
        var bundleID: String?
        if let app = remap.app {
            guard let url = findApp(app), let id = Bundle(url: url)?.bundleIdentifier else {
                out.errors.append("App not found: \"\(app)\"")
                continue
            }
            bundleID = id
        }
        out.remaps.append(ResolvedRemap(trigger: trigger, send: send, bundleID: bundleID,
                                        notWhileTyping: remap.notWhileTyping ?? false))
    }
    return out
}

/// Accepts an absolute path, a bundle ID, or a plain app name.
/// Symlinks are resolved (/Applications/Safari.app is one on recent macOS).
func findApp(_ name: String) -> URL? {
    lookupApp(name)?.resolvingSymlinksInPath()
}

private func lookupApp(_ name: String) -> URL? {
    let fm = FileManager.default
    if name.hasPrefix("/") || name.hasPrefix("~") {
        let path = (name as NSString).expandingTildeInPath
        return fm.fileExists(atPath: path) ? URL(fileURLWithPath: path) : nil
    }
    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: name) { return url }
    let dirs = ["/Applications", "/Applications/Utilities", "/System/Applications",
                "/System/Applications/Utilities", "/System/Library/CoreServices",
                fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path]
    for dir in dirs {
        let path = "\(dir)/\(name).app"
        if fm.fileExists(atPath: path) { return URL(fileURLWithPath: path) }
    }
    return nil
}
