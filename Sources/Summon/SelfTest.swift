import AppKit

/// `Summon --selftest`: checks key parsing and the config file round trip
/// without touching the real config or the keyboard.
enum SelfTest {
    private static var failures = 0

    private static func check(_ name: String, _ ok: Bool) {
        print(ok ? "  ok    \(name)" : "  FAIL  \(name)")
        if !ok { failures += 1 }
    }

    static func run() -> Int32 {
        print("Summon self test")

        // keys
        let combo = Combo("cmd+shift+return")
        check("parses modifiers and named keys", combo != nil)
        check("writes combos back in a fixed order", combo?.text == "shift+cmd+return")
        check("draws keycaps in Apple's order", combo?.glyphs == ["⇧", "⌘", "↩"])
        check("modifier order doesn't matter", Combo("shift+cmd+return") == combo)
        check("rejects unknown modifiers", Combo("hyper+x") == nil)
        check("rejects unknown keys", Combo("cmd+nope") == nil)
        check("parses a sequence", Combo.sequence("cmd+a delete")?.count == 2)
        check("rejects a sequence with a bad step", Combo.sequence("cmd+a nope") == nil)
        check("Home is a valid bare trigger", Combo("home")?.isValidTrigger == true)
        check("F5 is a valid bare trigger", Combo("f5")?.isValidTrigger == true)
        check("a bare letter isn't a trigger", Combo("a")?.isValidTrigger == false)

        // config round trip
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("summon-selftest.json")
        let config = Config(
            bindings: [.init(keys: "cmd+e", app: "Finder"),
                       .init(keys: "cmd+shift+return", app: "/Applications/My \"Odd\" App.app", newWindow: .off),
                       .init(keys: "cmd+return", app: "Ghostty", newWindow: .always)],
            remaps: [.init(keys: "ctrl+delete", send: "opt+delete"),
                     .init(keys: "cmd+shift+k", send: "cmd+a cmd+c", app: "Safari", notWhileTyping: true)],
            finderCut: true)
        do {
            try config.save(to: url)
            let text = try String(contentsOf: url, encoding: .utf8)
            let back = try JSONDecoder().decode(Config.self, from: Data(contentsOf: url))
            check("saves one entry per line", text.contains("{ \"keys\": \"cmd+e\","))
            check("keeps slashes readable", !text.contains("\\/"))
            check("round trips app hotkeys", back.bindings.map(\.app) == config.bindings.map(\.app)
                  && back.bindings[1].newWindow == .off && back.bindings[2].newWindow == .always)
            check("round trips remaps", back.remaps?.map(\.send) == ["opt+delete", "cmd+a cmd+c"]
                  && back.remaps?[1].app == "Safari" && back.remaps?[1].notWhileTyping == true)
            check("round trips Finder cut", back.finderCut == true)
        } catch {
            check("config round trip (\(error.localizedDescription))", false)
        }
        try? FileManager.default.removeItem(at: url)

        // resolving
        let resolved = resolve(Config(bindings: [.init(keys: "cmd+e", app: "No Such App 12345")],
                                      remaps: [.init(keys: "cmd+nope", send: "cmd+c")]))
        check("reports a missing app", resolved.errors.contains { $0.contains("No Such App") })
        check("reports bad remap keys", resolved.errors.contains { $0.contains("cmd+nope") })
        check("finds Finder by name", findApp("Finder") != nil)

        print(failures == 0 ? "All good." : "\(failures) failed.")
        return failures == 0 ? 0 : 1
    }
}
