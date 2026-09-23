import SwiftUI

/// The panel that drops from the menu bar icon, styled after Control Center.
struct QuickPanel: View {
    @ObservedObject var store: Store
    var launch: (Config.Entry) -> Void
    var openRemap: (Config.Remap?) -> Void
    var openSettings: () -> Void
    var quit: () -> Void

    private let maxRemaps = 6

    private var ready: [Config.Entry] { store.entries.filter { Combo($0.keys) != nil } }
    private var remaps: [Config.Remap] { store.remaps.filter { Combo($0.keys) != nil } }
    private var hasRemapSection: Bool { !remaps.isEmpty || store.finderCut }
    private var dimmed: Bool { !store.isEnabled || !store.isListening }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 10)

            Hairline().padding(.horizontal, 12)

            VStack(spacing: 1) {
                if hasRemapSection && !ready.isEmpty { SectionTitle("Open Apps") }
                if ready.isEmpty && !hasRemapSection {
                    Text("No hotkeys yet")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                ForEach(ready) { entry in
                    LaunchRow(entry: entry, dimmed: dimmed) { launch(entry) }
                }

                if hasRemapSection {
                    SectionTitle("Remaps").padding(.top, ready.isEmpty ? 0 : 6)
                    ForEach(remaps.prefix(maxRemaps)) { remap in
                        RemapPanelRow(remap: remap, dimmed: dimmed) { openRemap(remap) }
                    }
                    if remaps.count > maxRemaps {
                        MoreRow(count: remaps.count - maxRemaps) { openRemap(nil) }
                    }
                    if store.finderCut {
                        FinderCutPanelRow(dimmed: dimmed) { openRemap(nil) }
                    }
                }
            }
            .padding(6)

            Hairline().padding(.horizontal, 12)

            VStack(spacing: 1) {
                PanelButton(title: "Settings…", shortcut: "⌘,", action: openSettings)
                    .keyboardShortcut(",", modifiers: .command)
                PanelButton(title: "Quit Summon", shortcut: "⌘Q", action: quit)
                    .keyboardShortcut("q", modifiers: .command)
            }
            .padding(6)
        }
        .frame(width: 300)
        .background(VisualEffect(material: .popover))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Mascot(glow: store.isEnabled && store.isListening ? 0.5 : 0.1)
                .frame(width: 26, height: 34)
                .saturation(store.isEnabled && store.isListening ? 1 : 0.2)

            VStack(alignment: .leading, spacing: 1) {
                Text("Summon")
                    .font(.system(size: 13, weight: .semibold))
                StatusLine(store: store, size: 11)
            }

            Spacer()

            if store.isListening {
                GhostSwitch(isOn: $store.isEnabled)
                    .help(store.isEnabled ? "Pause all hotkeys" : "Resume hotkeys")
            }
        }
        .animation(.easeInOut(duration: 0.25), value: store.isEnabled)
    }
}

private struct LaunchRow: View {
    let entry: Config.Entry
    let dimmed: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let url = findApp(entry.app)
        Button(action: action) {
            HStack(spacing: 10) {
                AppIcon(url: url, size: 22)
                Text(appName(url, fallback: entry.app))
                    .font(.system(size: 13))
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let combo = Combo(entry.keys) {
                    Keycaps(combo: combo, small: true)
                        .opacity(dimmed ? 0.4 : 1)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(hovering ? 0.08 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Open \(appName(url, fallback: entry.app))")
    }
}

private struct SectionTitle: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.top, 4)
            .padding(.bottom, 2)
    }
}

/// Hover-highlighted row, shared by everything clickable in the panel.
private struct PanelRow<Content: View>: View {
    let help: String
    let action: () -> Void
    @ViewBuilder var content: Content
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) { content }
                .padding(.horizontal, 8)
                .frame(height: 34)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(hovering ? 0.08 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

private struct RemapPanelRow: View {
    let remap: Config.Remap
    let dimmed: Bool
    let action: () -> Void

    var body: some View {
        let url = remap.app.flatMap(findApp)
        PanelRow(help: remap.app == nil ? "Everywhere · click to edit"
                                        : "In \(appName(url, fallback: remap.app!)) · click to edit",
                 action: action) {
            ScopeIcon(url: url, everywhere: remap.app == nil, size: 22)
            RemapKeys(trigger: remap.keys, send: remap.send)
                .opacity(dimmed ? 0.4 : 1)
            Spacer(minLength: 0)
        }
    }
}

private struct FinderCutPanelRow: View {
    let dimmed: Bool
    let action: () -> Void

    var body: some View {
        PanelRow(help: "⌘X then ⌘V moves files in Finder", action: action) {
            SymbolTile(symbol: "scissors", size: 22)
            Text("Cut files in Finder")
                .font(.system(size: 13))
            Spacer(minLength: 8)
            Keycaps(combo: Combo("cmd+x")!, small: true)
                .opacity(dimmed ? 0.4 : 1)
        }
    }
}

private struct MoreRow: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        PanelRow(help: "Show all remaps in Settings", action: action) {
            Text("\(count) more…")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.leading, 32)
            Spacer()
        }
    }
}

private struct PanelButton: View {
    let title: String
    let shortcut: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).font(.system(size: 13))
                Spacer()
                Text(shortcut).font(.system(size: 12)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(hovering ? 0.08 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Borderless panel that can take key focus (for Esc and ⌘,) without
/// activating Summon or stealing focus from the app you're in.
final class QuickPanelWindow: NSPanel {
    var onClose: () -> Void = {}

    init(content: NSView) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        hidesOnDeactivate = false
        contentView = content
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onClose()
    }
}
