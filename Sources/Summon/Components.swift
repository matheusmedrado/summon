import SwiftUI

/// The glow in the mascot's eyes; used for anything "live".
let ghostBlue = Color(red: 0.49, green: 0.61, blue: 1.0)

/// Display name for an app bundle, without the ".app".
func appName(_ url: URL?, fallback: String) -> String {
    guard let url else { return fallback }
    return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
}

struct Mascot: View {
    /// 0 to 1: how strongly the eyes' blue bleeds into the surroundings.
    var glow: Double = 0.45

    var body: some View {
        if let image = Bundle.main.image(forResource: "Mascot") {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .shadow(color: ghostBlue.opacity(glow), radius: 10 + 10 * glow)
        } else {
            Image(systemName: "command").resizable().aspectRatio(contentMode: .fit)
        }
    }
}

struct AppIcon: View {
    let url: URL?
    var size: CGFloat = 28

    var body: some View {
        Group {
            if let url {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable()
            } else {
                Image(systemName: "questionmark.app.dashed").resizable().foregroundStyle(.tertiary)
            }
        }
        .frame(width: size, height: size)
    }
}

/// A little keycap, styled after the one the mascot is holding.
struct Keycap: View {
    let label: String
    var small = false
    var dim = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let side: CGFloat = small ? 18 : 22
        Text(label)
            .font(.system(size: small ? 10.5 : 12, weight: .medium, design: .rounded))
            .foregroundStyle(scheme == .dark ? Color.white.opacity(0.88) : Color(white: 0.32))
            .padding(.horizontal, label.count > 1 ? (small ? 5 : 7) : 0)
            .frame(minWidth: side, minHeight: side)
            .background(
                RoundedRectangle(cornerRadius: small ? 4.5 : 5.5, style: .continuous)
                    .fill(LinearGradient(
                        colors: scheme == .dark
                            ? [Color(white: 0.30), Color(white: 0.22)]
                            : [.white, Color(white: 0.94)],
                        startPoint: .top, endPoint: .bottom))
                    .shadow(color: .black.opacity(scheme == .dark ? 0.45 : 0.14), radius: 0.4, y: 0.8))
            .overlay(
                RoundedRectangle(cornerRadius: small ? 4.5 : 5.5, style: .continuous)
                    .strokeBorder(Color.primary.opacity(scheme == .dark ? 0.12 : 0.08), lineWidth: 0.5))
            .opacity(dim ? 0.55 : 1)
    }
}

struct Keycaps: View {
    let combo: Combo
    var small = false

    var body: some View {
        HStack(spacing: small ? 3 : 4) {
            ForEach(Array(combo.glyphs.enumerated()), id: \.offset) { Keycap(label: $0.element, small: small) }
        }
    }
}

/// A hairline that reads the same in light and dark.
struct Hairline: View {
    var body: some View {
        Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5)
    }
}

struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}

/// On/off switch in the mascot's blue. The system switch renders grey inside
/// a panel that never becomes the active app, which reads as "off".
struct GhostSwitch: View {
    @SwiftUI.Binding var isOn: Bool

    var body: some View {
        Capsule()
            .fill(isOn ? ghostBlue : Color.primary.opacity(0.16))
            .frame(width: 32, height: 19)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
                    .padding(2)
            }
            .contentShape(Capsule())
            .onTapGesture {
                withAnimation(.spring(duration: 0.25, bounce: 0.2)) { isOn.toggle() }
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(isOn ? "On" : "Off")
    }
}
