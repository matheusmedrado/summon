import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: Store
    var openAccessibility: () -> Void

    enum Tab: String, CaseIterable, Identifiable {
        case apps = "Open Apps", remaps = "Remap Keys"
        var id: Self { self }
    }

    var body: some View {
        VStack(spacing: 0) {
            Hero(store: store)
                .padding(.top, 38)
                .padding(.bottom, 20)

            if !store.isListening {
                PermissionBanner(open: openAccessibility)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            TabPicker(tab: $store.tab)
                .padding(.bottom, 14)

            Group {
                switch store.tab {
                case .apps: HotkeyCard(store: store)
                case .remaps: RemapsTab(store: store)
                }
            }
            .padding(.horizontal, 20)

            ForEach(store.errors, id: \.self) { error in
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 26)
                    .padding(.top, 8)
            }

            FooterLinks(store: store)
                .padding(.top, 14)
                .padding(.bottom, 16)
        }
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .background(alignment: .top) {
            // a faint wash of the mascot's blue behind the header
            RadialGradient(colors: [ghostBlue.opacity(0.16), .clear],
                           center: .top, startRadius: 0, endRadius: 240)
                .frame(height: 260)
                .allowsHitTesting(false)
        }
        .background(VisualEffect().ignoresSafeArea())
        .animation(.spring(duration: 0.35), value: store.entries.count)
        .animation(.spring(duration: 0.35), value: store.remaps.count)
        .animation(.spring(duration: 0.35), value: store.isListening)
        .sheet(item: $store.draft) { draft in
            RemapEditor(store: store, remap: draft,
                        isNew: !store.remaps.contains { $0.id == draft.id })
        }
    }
}

// MARK: header

private struct Hero: View {
    @ObservedObject var store: Store
    @State private var floating = false

    private var recording: Bool { store.recordingID != nil }

    var body: some View {
        VStack(spacing: 12) {
            Mascot(glow: recording ? 0.95 : 0.4)
                .frame(height: 84)
                .offset(y: floating ? -3 : 3)
                .animation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true), value: floating)
                .animation(.easeInOut(duration: 0.4), value: recording)
                .onAppear { floating = true }

            VStack(spacing: 5) {
                Text("Summon")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                StatusLine(store: store)
            }
        }
    }
}

struct StatusLine: View {
    @ObservedObject var store: Store
    var size: CGFloat = 12
    @State private var pulse = false

    private var summary: String {
        let hotkeys = store.entries.filter { !$0.keys.isEmpty }.count
        let remaps = store.remaps.count
        var parts = ["\(hotkeys) hotkey\(hotkeys == 1 ? "" : "s")"]
        if remaps > 0 { parts.append("\(remaps) remap\(remaps == 1 ? "" : "s")") }
        return parts.joined(separator: ", ")
    }

    private var state: (text: String, color: Color) {
        if !store.isListening { return ("Waiting for permission", .orange) }
        if store.recordingID != nil { return ("Press the keys", ghostBlue) }
        if !store.isEnabled { return ("Paused", .secondary) }
        return ("Listening · \(summary)", ghostBlue)
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(state.color)
                .frame(width: 6, height: 6)
                .shadow(color: state.color.opacity(pulse ? 0.9 : 0.1), radius: pulse ? 4 : 0)
                .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: pulse)
                .onAppear { pulse = true }
            Text(state.text)
                .font(.system(size: size))
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)
        }
        .animation(.easeInOut(duration: 0.2), value: state.text)
    }
}

private struct PermissionBanner: View {
    var open: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 20))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Allow Accessibility access")
                    .font(.system(size: 12.5, weight: .semibold))
                Text("Lets Summon catch hotkeys before other apps do.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Open Settings", action: open)
                .controlSize(.small)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.orange.opacity(0.09)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.orange.opacity(0.22), lineWidth: 0.5))
    }
}

private struct TabPicker: View {
    @SwiftUI.Binding var tab: SettingsView.Tab
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(SettingsView.Tab.allCases) { option in
                Button {
                    withAnimation(.spring(duration: 0.3)) { tab = option }
                } label: {
                    Text(option.rawValue)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(tab == option ? .primary : .secondary)
                        .padding(.horizontal, 14)
                        .frame(height: 24)
                        .background {
                            if tab == option {
                                Capsule()
                                    .fill(Color.primary.opacity(0.09))
                                    .matchedGeometryEffect(id: "tab", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.primary.opacity(0.04)))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
    }
}

/// Rounded container with a hairline border, shared by every list.
private struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.035)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: open apps tab

private struct HotkeyCard: View {
    @ObservedObject var store: Store
    private let maxVisible = 7

    var body: some View {
        Card {
            if store.entries.isEmpty {
                EmptyNote(text: "No hotkeys yet. Add one to summon any app.")
            } else if store.entries.count <= maxVisible {
                rows
            } else {
                ScrollView { rows }.frame(height: CGFloat(maxVisible) * 49)
            }
            Hairline()
            AddRow(title: "Add Hotkey…", add: store.addApp)
        }
    }

    private var rows: some View {
        VStack(spacing: 0) {
            ForEach(Array(store.entries.enumerated()), id: \.element.id) { index, entry in
                if index > 0 { Hairline().padding(.leading, 54) }
                HotkeyRow(entry: entry, store: store)
                    .transition(.opacity)
            }
        }
    }
}

private struct HotkeyRow: View {
    let entry: Config.Entry
    @ObservedObject var store: Store
    @State private var hovering = false

    private var appURL: URL? { findApp(entry.app) }

    private var note: (String, Color)? {
        if appURL == nil { return ("App not found", .orange) }
        if store.conflicts(entry) { return ("Same keys as another hotkey or remap", .orange) }
        if entry.newWindow == .off { return ("Only brings it forward", .secondary) }
        if entry.newWindow == .always { return ("New window every time", .secondary) }
        return nil
    }

    var body: some View {
        HStack(spacing: 12) {
            AppIcon(url: appURL, size: 30)

            VStack(alignment: .leading, spacing: 1) {
                Text(appName(appURL, fallback: entry.app))
                    .font(.system(size: 13))
                if let (text, color) = note {
                    Text(text).font(.system(size: 11)).foregroundStyle(color)
                }
            }

            Spacer(minLength: 8)

            ComboRecorder(store: store, id: entry.id, combo: Combo(entry.keys),
                          onCommit: { store.setKeys($0, for: entry.id) },
                          onCancel: store.cancelRecording)

            Menu {
                Picker("New Window", selection: SwiftUI.Binding(
                    get: { entry.newWindow ?? .whenInFront },
                    set: { store.setNewWindow($0, for: entry.id) })) {
                    Text("Never").tag(NewWindow.off)
                    Text("When Already in Front").tag(NewWindow.whenInFront)
                    Text("Every Time").tag(NewWindow.always)
                }
                Button("Change App…") { store.changeApp(entry.id) }
                Divider()
                Button("Remove Hotkey", role: .destructive) { store.remove(entry.id) }
            } label: {
                MoreIcon()
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .opacity(hovering ? 1 : 0)
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .frame(minHeight: 48)
        .background(Color.primary.opacity(hovering ? 0.03 : 0))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

// MARK: remap keys tab

private struct RemapsTab: View {
    @ObservedObject var store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Card {
                if store.remaps.isEmpty {
                    EmptyNote(text: "Press one combo, send another. Start from scratch or a preset.")
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(store.remaps.enumerated()), id: \.element.id) { index, remap in
                            if index > 0 { Hairline().padding(.leading, 54) }
                            RemapRow(remap: remap, store: store)
                                .transition(.opacity)
                        }
                    }
                }
                Hairline()
                HStack(spacing: 0) {
                    AddRow(title: "Add Remap…", add: store.newRemap)
                    PresetMenu(store: store)
                        .padding(.trailing, 10)
                }
            }

            Text("Built in")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
                .padding(.top, 8)

            Card {
                FinderCutRow(store: store)
            }
        }
    }
}

private struct RemapRow: View {
    let remap: Config.Remap
    @ObservedObject var store: Store
    @State private var hovering = false

    private var appURL: URL? { remap.app.flatMap(findApp) }

    private var detail: (String, Color) {
        if remap.app != nil && appURL == nil { return ("App not found", .orange) }
        if let conflict = store.conflict(for: remap) { return (conflict, .orange) }
        var parts = [remap.app == nil ? "Everywhere" : "In \(appName(appURL, fallback: remap.app!))"]
        if remap.notWhileTyping == true { parts.append("not while typing") }
        return (parts.joined(separator: " · "), .secondary)
    }

    var body: some View {
        HStack(spacing: 12) {
            ScopeIcon(url: appURL, everywhere: remap.app == nil)

            VStack(alignment: .leading, spacing: 4) {
                RemapKeys(trigger: remap.keys, send: remap.send)
                Text(detail.0)
                    .font(.system(size: 11))
                    .foregroundStyle(detail.1)
            }

            Spacer(minLength: 8)

            Menu {
                Button("Edit…") { store.edit(remap) }
                Divider()
                Button("Remove Remap", role: .destructive) { store.removeRemap(remap.id) }
            } label: {
                MoreIcon()
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .opacity(hovering ? 1 : 0)
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .padding(.vertical, 9)
        .background(Color.primary.opacity(hovering ? 0.03 : 0))
        .contentShape(Rectangle())
        .onTapGesture { store.edit(remap) }
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help("Click to edit")
    }
}

/// "⌃⌫ → ⌥⌫" drawn as keycaps.
struct RemapKeys: View {
    let trigger: String
    let send: String

    var body: some View {
        HStack(spacing: 6) {
            if let combo = Combo(trigger) { Keycaps(combo: combo, small: true) }
            Image(systemName: "arrow.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.tertiary)
            ForEach(Array((Combo.sequence(send) ?? []).enumerated()), id: \.offset) { index, combo in
                if index > 0 {
                    Text("then").font(.system(size: 10)).foregroundStyle(.tertiary)
                }
                Keycaps(combo: combo, small: true)
            }
        }
    }
}

/// Where a remap applies: a globe for everywhere, else the app's icon.
struct ScopeIcon: View {
    let url: URL?
    let everywhere: Bool
    var size: CGFloat = 30

    var body: some View {
        if everywhere || url == nil {
            SymbolTile(symbol: "globe", size: size)
        } else {
            AppIcon(url: url, size: size)
        }
    }
}

/// A symbol on a soft blue rounded square, sized like an app icon.
struct SymbolTile: View {
    let symbol: String
    var size: CGFloat = 30

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.43, weight: .medium))
            .foregroundStyle(ghostBlue)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.23, style: .continuous).fill(ghostBlue.opacity(0.14)))
    }
}

private struct PresetMenu: View {
    @ObservedObject var store: Store

    var body: some View {
        Menu {
            Section("Presets") {
                ForEach(Store.presets) { preset in
                    Button {
                        store.add(preset)
                    } label: {
                        if store.isAdded(preset) {
                            Label(preset.title, systemImage: "checkmark")
                        } else {
                            Text(preset.title)
                        }
                    }
                    .disabled(store.isAdded(preset))
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                Text("Presets")
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

private struct FinderCutRow: View {
    @ObservedObject var store: Store

    var body: some View {
        HStack(spacing: 12) {
            SymbolTile(symbol: "scissors")

            VStack(alignment: .leading, spacing: 4) {
                Text("Cut and paste files in Finder")
                    .font(.system(size: 13))
                HStack(spacing: 4) {
                    Keycaps(combo: Combo("cmd+x")!, small: true)
                    Text("then").font(.system(size: 10)).foregroundStyle(.tertiary)
                    Keycaps(combo: Combo("cmd+v")!, small: true)
                    Text("moves files").font(.system(size: 11)).foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 8)

            GhostSwitch(isOn: SwiftUI.Binding(get: { store.finderCut }, set: { store.setFinderCut($0) }))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
    }
}

// MARK: remap editor

struct RemapEditor: View {
    @ObservedObject var store: Store
    @State var remap: Config.Remap
    let isNew: Bool

    /// One recorder per combo to send.
    private struct Step: Identifiable {
        let id = UUID()
        var keys: String
    }
    @State private var steps: [Step] = []
    @State private var triggerID = UUID()

    private var canSave: Bool {
        guard let trigger = Combo(remap.keys), trigger.isValidTrigger else { return false }
        let filled = steps.filter { !$0.keys.isEmpty }
        return !filled.isEmpty && filled.allSatisfy { Combo($0.keys) != nil }
    }

    private var sendText: String {
        steps.map(\.keys).filter { !$0.isEmpty }.joined(separator: " ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(isNew ? "New Remap" : "Edit Remap")
                .font(.system(size: 15, weight: .semibold, design: .rounded))

            Field("When you press") {
                ComboRecorder(store: store, id: triggerID, combo: Combo(remap.keys),
                              placeholder: "Record keys", boxed: true,
                              onCommit: { remap.keys = $0.text; store.recordingID = nil },
                              onCancel: { store.recordingID = nil })
            }

            Field("Send instead") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                        HStack(spacing: 6) {
                            Text(index == 0 ? "" : "then")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                                .frame(width: 28, alignment: .leading)
                                .opacity(steps.count > 1 ? 1 : 0)
                                .frame(width: steps.count > 1 ? 28 : 0)
                            ComboRecorder(store: store, id: step.id, combo: Combo(step.keys),
                                          placeholder: "Record keys",
                                          allowAnyKey: true, boxed: true,
                                          onCommit: { combo in
                                              if let i = steps.firstIndex(where: { $0.id == step.id }) { steps[i].keys = combo.text }
                                              store.recordingID = nil
                                          },
                                          onCancel: {
                                              store.recordingID = nil
                                              if steps.count > 1 { steps.removeAll { $0.id == step.id && $0.keys.isEmpty } }
                                          })
                            if steps.count > 1 {
                                Button {
                                    steps.removeAll { $0.id == step.id }
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.tertiary)
                                }
                                .buttonStyle(.plain)
                                .help("Remove this step")
                            }
                        }
                    }
                    Button {
                        let step = Step(keys: "")
                        steps.append(step)
                        store.recordingID = step.id
                    } label: {
                        Label("Then send more keys", systemImage: "plus")
                            .font(.system(size: 11.5))
                            .foregroundStyle(ghostBlue)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            }

            Field("Works in") {
                ScopePicker(app: $remap.app)
            }

            HStack(spacing: 10) {
                GhostSwitch(isOn: SwiftUI.Binding(
                    get: { remap.notWhileTyping ?? false },
                    set: { remap.notWhileTyping = $0 ? true : nil }))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Not while typing")
                        .font(.system(size: 12.5))
                    Text("Leave the keys alone in text fields.")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }

            if let conflict = store.conflict(for: Config.Remap(id: remap.id, keys: remap.keys, send: sendText, app: remap.app)) {
                Label(conflict, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }

            HStack {
                if !isNew {
                    Button("Remove", role: .destructive) {
                        store.removeRemap(remap.id)
                        store.draft = nil
                    }
                }
                Spacer()
                Button("Cancel") {
                    store.recordingID = nil
                    store.draft = nil
                }
                .keyboardShortcut(.cancelAction)
                Button(isNew ? "Add Remap" : "Save") {
                    store.recordingID = nil
                    remap.send = sendText
                    store.saveRemap(remap)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
            .padding(.top, 4)
        }
        .padding(22)
        .frame(width: 400)
        .onAppear {
            steps = remap.send.split(separator: " ").map { Step(keys: String($0)) }
            if steps.isEmpty { steps = [Step(keys: "")] }
            // A brand-new remap starts by recording its trigger.
            if remap.keys.isEmpty { store.recordingID = triggerID }
        }
    }
}

private struct Field<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            content
        }
    }
}

/// "Any App", the apps that are running, or any other app. A plain button
/// that pops a native menu: SwiftUI's Menu flattens a custom label on macOS,
/// which would lose the field look.
private struct ScopePicker: View {
    @SwiftUI.Binding var app: String?
    @State private var hovering = false

    var body: some View {
        let url = app.flatMap(findApp)
        Button(action: showMenu) {
            HStack(spacing: 8) {
                if app == nil {
                    Image(systemName: "globe").foregroundStyle(ghostBlue).frame(width: 18)
                    Text("Any App")
                } else {
                    AppIcon(url: url, size: 18)
                    Text(appName(url, fallback: app ?? ""))
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .font(.system(size: 12.5))
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(hovering ? 0.07 : 0.05)))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private func showMenu() {
        let actions = MenuActions()
        let menu = NSMenu()
        menu.addItem(actions.item("Any App", image: NSImage(systemSymbolName: "globe", accessibilityDescription: nil),
                                  checked: app == nil) { app = nil })
        menu.addItem(.separator())
        let running = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleURL != nil && $0 != .current }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
        for other in running {
            let name = Store.configName(for: other.bundleURL!)
            let icon = NSWorkspace.shared.icon(forFile: other.bundleURL!.path)
            icon.size = NSSize(width: 16, height: 16)
            menu.addItem(actions.item(other.localizedName ?? name, image: icon, checked: app == name) { app = name })
        }
        menu.addItem(.separator())
        menu.addItem(actions.item("Other App…") {
            if let url = Store.pickApp() { app = Store.configName(for: url) }
        })

        guard let event = NSApp.currentEvent, let view = event.window?.contentView else { return }
        // popUp blocks until the menu closes, which keeps `actions` alive.
        menu.popUp(positioning: nil, at: view.convert(event.locationInWindow, from: nil), in: view)
    }
}

/// Target for NSMenu items that run closures.
private final class MenuActions: NSObject {
    private var handlers: [() -> Void] = []

    func item(_ title: String, image: NSImage? = nil, checked: Bool = false, _ handler: @escaping () -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(run(_:)), keyEquivalent: "")
        item.target = self
        item.tag = handlers.count
        item.image = image
        item.state = checked ? .on : .off
        handlers.append(handler)
        return item
    }

    @objc private func run(_ sender: NSMenuItem) {
        handlers[sender.tag]()
    }
}

// MARK: shared bits

private struct EmptyNote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
    }
}

private struct AddRow: View {
    let title: String
    var add: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: add) {
            HStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 30)
                Text(title)
                    .font(.system(size: 13))
                Spacer()
            }
            .foregroundStyle(ghostBlue)
            .padding(.leading, 12)
            .frame(height: 42)
            .background(Color.primary.opacity(hovering ? 0.03 : 0))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct MoreIcon: View {
    var body: some View {
        Image(systemName: "ellipsis.circle")
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .frame(width: 20, height: 26)
            .contentShape(Rectangle())
    }
}

// MARK: recorder

/// Shows a combo as keycaps; click to record a new one. While any recorder is
/// active the event tap stands aside, so even ⌘E or ⌘X can be recorded.
private struct ComboRecorder: View {
    @ObservedObject var store: Store
    let id: UUID
    let combo: Combo?
    var placeholder = "Set shortcut"
    /// Keys to send can be anything (↩, ←, even Esc); triggers need a modifier
    /// unless they're keys like F5 or Home that are safe on their own.
    var allowAnyKey = false
    /// Form style for the editor: left-aligned inside a visible field.
    var boxed = false
    let onCommit: (Combo) -> Void
    let onCancel: () -> Void

    @State private var held: [String] = []
    @State private var hint: String?
    @State private var shake: CGFloat = 0
    @State private var hovering = false
    @State private var caret = false
    @State private var monitor: Any?

    private var recording: Bool { store.recordingID == id }

    var body: some View {
        Button {
            if recording { onCancel() } else { store.recordingID = id }
        } label: {
            HStack(spacing: 4) {
                if recording {
                    if held.isEmpty {
                        HStack(spacing: 2) {
                            Text(hint ?? "Type keys")
                                .foregroundStyle(hint == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
                            if hint == nil {
                                Rectangle().fill(ghostBlue).frame(width: 1.5, height: 13).opacity(caret ? 1 : 0)
                            }
                        }
                        .font(.system(size: 12))
                    } else {
                        ForEach(held, id: \.self) { Keycap(label: $0, dim: true) }
                    }
                } else if let combo {
                    Keycaps(combo: combo)
                } else {
                    Text(placeholder).font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 7)
            .frame(minWidth: 104, maxWidth: boxed ? .infinity : nil, minHeight: 30,
                   alignment: boxed ? .leading : .trailing)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(recording ? ghostBlue.opacity(0.10)
                          : Color.primary.opacity(boxed ? (hovering ? 0.07 : 0.05) : (hovering ? 0.05 : 0))))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(recording ? ghostBlue.opacity(0.75) : Color.primary.opacity(boxed ? 0.08 : 0),
                                  lineWidth: recording ? 1 : 0.5))
            .shadow(color: ghostBlue.opacity(recording ? 0.35 : 0), radius: 6)
            .modifier(Shake(amount: shake))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(recording
              ? (allowAnyKey ? "Press the keys to send; click again to cancel" : "Press the new keys, or Esc to cancel")
              : "Click to record")
        .animation(.easeOut(duration: 0.15), value: recording)
        .onChange(of: recording) { _, isRecording in
            isRecording ? startMonitor() : stopMonitor()
        }
        .onAppear { if recording { startMonitor() } }
        .onDisappear { stopMonitor() }
    }

    private func startMonitor() {
        held = []
        hint = nil
        stopMonitor()
        withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) { caret = true }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            handle(event)
            return nil
        }
    }

    private func stopMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        held = []
        caret = false
    }

    private func handle(_ event: NSEvent) {
        if event.type == .flagsChanged {
            held = Array(Combo(keyCode: 0, flags: cgFlags(event.modifierFlags)).glyphs.dropLast())
            return
        }
        guard let combo = Combo(event: event) else { return reject("Key not supported") }
        if !allowAnyKey {
            if !combo.hasModifier && combo.name == "escape" { return onCancel() }
            guard combo.isValidTrigger else { return reject("Add ⌘ ⌥ ⌃ or ⇧") }
        }
        onCommit(combo)
    }

    private func reject(_ message: String) {
        hint = message
        held = []
        withAnimation(.linear(duration: 0.35)) { shake += 1 }
    }

    private func cgFlags(_ mods: NSEvent.ModifierFlags) -> CGEventFlags {
        var flags: CGEventFlags = []
        if mods.contains(.command) { flags.insert(.maskCommand) }
        if mods.contains(.option) { flags.insert(.maskAlternate) }
        if mods.contains(.control) { flags.insert(.maskControl) }
        if mods.contains(.shift) { flags.insert(.maskShift) }
        return flags
    }
}

private struct Shake: GeometryEffect {
    var amount: CGFloat
    var animatableData: CGFloat {
        get { amount }
        set { amount = newValue }
    }
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 4 * sin(amount * .pi * 4), y: 0))
    }
}

// MARK: footer

private struct FooterLinks: View {
    @ObservedObject var store: Store

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    var body: some View {
        HStack(spacing: 8) {
            Button {
                store.setOpensAtLogin(!store.opensAtLogin)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: store.opensAtLogin ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(store.opensAtLogin ? AnyShapeStyle(ghostBlue) : AnyShapeStyle(.tertiary))
                    Text("Open at login")
                }
            }
            .buttonStyle(.plain)
            .help("Start Summon when you log in, and restart it if it ever crashes")
            Text("·")
            Button("Open Config File") {
                NSWorkspace.shared.activateFileViewerSelecting([Config.url])
            }
            .buttonStyle(.plain)
            .onHover { inside in inside ? NSCursor.pointingHand.push() : NSCursor.pop() }
            Text("·")
            Text("Version \(version)")
        }
        .font(.system(size: 11))
        .foregroundStyle(.tertiary)
    }
}
