import AppKit
import BuiltInProfiles
import Carbon.HIToolbox
import OSLog

/// Process-wide composition root. Every entry point — menu bar, island,
/// Spotlight / Shortcuts (App Intents), `caffe://` URLs, the global hotkey —
/// funnels into this one object, so they all drive the same session.
@MainActor
final class AppRuntime {
    static let shared = AppRuntime()

    let state = AppState()
    private(set) lazy var island = IslandWindowController(appState: state)
    private lazy var untilPicker = UntilPickerController(state: state)
    private let hotKey = GlobalHotKey()
    private var started = false
    private let logger = Logger(subsystem: "ch.dynamic-caffe-island.app", category: "runtime")

    private init() {}

    /// Bootstraps profiles and shows the island. Safe to call repeatedly —
    /// intents call it in case the system launched the app just for them.
    func ensureStarted() async {
        guard !started else { return }
        started = true
        await state.bootstrap()
        island.start()
        hotKey.register { [weak self] in self?.toggle() }
    }

    // MARK: - Commands shared by every entry point

    func start(minutes: Int?) {
        if let minutes, minutes > 0 {
            state.startCaffeine(duration: .preset(TimeInterval(minutes * 60)))
        } else {
            state.startCaffeine(duration: .indefinite)
        }
    }

    func stop() { state.cancelCaffeine() }

    func toggle(defaultMinutes: Int = 30) {
        if state.caffeineState.session != nil { stop() } else { start(minutes: defaultMinutes) }
    }

    func until(hour: Int, minute: Int) {
        let target = CaffeCommand.nextOccurrence(hour: hour, minute: minute)
        state.startCaffeine(duration: .untilClockTime(target))
    }

    func showUntilPicker() { untilPicker.show() }

    func perform(_ command: CaffeCommand) {
        switch command {
        case let .start(minutes): start(minutes: minutes)
        case .indefinite: start(minutes: nil)
        case let .until(h, m): until(hour: h, minute: m)
        case .stop: stop()
        case .toggle: toggle()
        case .peek: island.peek()
        case .pickTime: showUntilPicker()
        }
    }

    /// `caffe://…` — grammar lives in `CaffeCommand.parse` (unit-tested).
    func handle(url: URL) {
        guard let command = CaffeCommand.parse(url) else {
            logger.error("unrecognised url \(url.absoluteString, privacy: .public)")
            return
        }
        logger.info("url command: \(String(describing: command), privacy: .public)")
        perform(command)
    }
}

/// App delegate: launch hook + `caffe://` URL handling via Apple Events
/// (reliable for menu-bar-only SwiftUI apps with no WindowGroup).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURLEvent(_:reply:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in await AppRuntime.shared.ensureStarted() }
    }

    @objc private func handleURLEvent(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let string = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: string) else { return }
        Task { @MainActor in
            await AppRuntime.shared.ensureStarted()
            AppRuntime.shared.handle(url: url)
        }
    }
}

/// ⌃⌥C global hotkey (Carbon `RegisterEventHotKey` — no Accessibility
/// permission needed). Toggles a 30-minute session.
final class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private static var action: (() -> Void)?

    func register(action: @escaping () -> Void) {
        guard hotKeyRef == nil else { return }
        GlobalHotKey.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { GlobalHotKey.action?() }
            return noErr
        }, 1, &spec, nil, &handlerRef)
        let id = EventHotKeyID(signature: OSType(0x4341_4645), id: 1) // 'CAFE'
        RegisterEventHotKey(UInt32(kVK_ANSI_C), UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &hotKeyRef)
    }
}
