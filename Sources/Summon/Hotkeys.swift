import AppKit

/// Marks keystrokes Summon posts itself, so the tap lets them through.
let syntheticMarker: Int64 = 0x53554D4E // "SUMN"

/// Intercepts keyboard events at the session level, before any app sees them.
/// A matching combo is swallowed whole (key down, repeats and key up), so the
/// front app never gets a partial keystroke and can't fire its own binding.
final class Hotkeys {
    private var tap: CFMachPort?
    private var bindings: [Combo: Binding] = [:]
    private var swallowing: Set<Int64> = []
    private var watchdog: Timer?
    private let onTrigger: (Binding) -> Void

    /// While the settings window records a new combo, let every key through.
    var paused = false
    /// Off when the user pauses Summon from the menu bar panel.
    var enabled = true
    /// Gets first look at every key down (repeats included); returning true
    /// swallows the key.
    var interceptor: ((Combo, _ isRepeat: Bool) -> Bool)?

    init(onTrigger: @escaping (Binding) -> Void) {
        self.onTrigger = onTrigger
    }

    var isRunning: Bool { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

    func set(_ list: [Binding]) {
        bindings = Dictionary(list.map { ($0.combo, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Returns false when Accessibility access hasn't been granted yet.
    @discardableResult
    func start() -> Bool {
        if tap != nil { return true }
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                let hotkeys = Unmanaged<Hotkeys>.fromOpaque(refcon!).takeUnretainedValue()
                return hotkeys.handle(type, event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        tap = port
        let source = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)

        // macOS silently disables a tap it thinks is slow or stuck. The callback
        // re-enables it when told, but check on a timer too in case that
        // notification is ever missed.
        watchdog = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            guard let tap = self?.tap, !CGEvent.tapIsEnabled(tap: tap) else { return }
            log("event tap was disabled, re-enabling")
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return true
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            log("event tap disabled (\(type.rawValue)), re-enabling")
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)

        case .keyDown:
            if event.getIntegerValueField(.eventSourceUserData) == syntheticMarker {
                return Unmanaged.passUnretained(event)
            }
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            guard enabled, !paused else { return Unmanaged.passUnretained(event) }
            let combo = Combo(keyCode: code, flags: event.flags)
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0

            if interceptor?(combo, isRepeat) == true {
                swallowing.insert(code)
                return nil
            }
            // A held key we already claimed: keep swallowing, don't act again.
            if isRepeat && swallowing.contains(code) { return nil }
            guard let binding = bindings[combo] else {
                return Unmanaged.passUnretained(event)
            }
            swallowing.insert(code)
            if !isRepeat {
                // Keep the tap callback fast; do the actual work after it returns.
                DispatchQueue.main.async { self.onTrigger(binding) }
            }
            return nil

        case .keyUp:
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            return swallowing.remove(code) != nil ? nil : Unmanaged.passUnretained(event)

        default:
            return Unmanaged.passUnretained(event)
        }
    }
}
