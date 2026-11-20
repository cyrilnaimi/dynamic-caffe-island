import AppKit
import BuiltInProfiles
import Carbon.HIToolbox
import Combine
import Darwin
import OSLog
import PowerAssertions

/// Process-wide composition root. Every entry point — menu bar, island,
/// Spotlight / Shortcuts (App Intents), `caffe://` URLs, the global hotkey —
/// funnels into this one object, so they all drive the same session.
@MainActor
final class AppRuntime {
    static let shared = AppRuntime()

    let state = AppState()
    let settings = AppSettings.shared
    private(set) lazy var island = IslandWindowController(appState: state, settings: settings)
    private lazy var untilPicker = UntilPickerController(state: state)
    private lazy var settingsWindow = SettingsWindowController(settings: settings)
    private let hotKey = GlobalHotKey()
    private var started = false
    private var cancellables = Set<AnyCancellable>()
    private var keyMonitor: Any?
    private var badgeTimer: Timer?
    private let logger = Logger(subsystem: "ch.dynamic-caffe-island.app", category: "runtime")

    private init() {}

    /// Bootstraps profiles and shows the island. Safe to call repeatedly —
    /// intents call it in case the system launched the app just for them.
    func ensureStarted() async {
        guard !started else { return }
        started = true
        await state.bootstrap()
        island.start()

        settings.$hotKeyEnabled
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled {
                    self.hotKey.register { [weak self] in self?.toggle() }
                } else {
                    self.hotKey.unregister()
                }
            }
            .store(in: &cancellables)

        // Battery guard: re-check on every power-source change, when a
        // session starts, and when the setting changes.
        PowerSourceMonitor.shared.start { [weak self] power in
            self?.applyBatteryGuard(power)
            self?.powerSourceChanged(power)
        }
        lastOnACPower = PowerSourceMonitor.snapshot().onACPower
        // (`applyBatteryGuard` reads the manager's live state: inside this
        // sink `state.caffeineState` still holds the previous value.)
        state.$caffeineState
            .filter(\.isActive)
            .map { $0.session?.id }
            .removeDuplicates()
            .sink { [weak self] _ in self?.applyBatteryGuard(PowerSourceMonitor.snapshot()) }
            .store(in: &cancellables)
        Publishers.CombineLatest(settings.$batteryThreshold, settings.$onlyOnPowerAdapter)
            .dropFirst()
            .sink { [weak self] _, _ in
                DispatchQueue.main.async { self?.applyBatteryGuard(PowerSourceMonitor.snapshot()) }
            }
            .store(in: &cancellables)

        // Dock icon on/off without a relaunch, and its remaining-time badge.
        // `@Published` emits before the property changes, so the sinks use
        // the emitted values rather than reading `settings`.
        settings.$showInDock
            .removeDuplicates()
            .sink { [weak self] show in self?.applyDockPresence(show) }
            .store(in: &cancellables)
        Publishers.CombineLatest3(state.$caffeineState, settings.$showInDock, settings.$dockBadge)
            .sink { [weak self] caffeine, show, badge in
                self?.updateDockBadge(session: caffeine.session, show: show, badge: badge)
            }
            .store(in: &cancellables)

        // After sleep: end a session whose time ran out while the lid was
        // closed, and correct the Dock badge (run-loop timers don't count
        // time asleep).
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.systemDidWake() }
            .store(in: &cancellables)

        // ⌘, opens Settings whenever one of our windows is in front. In
        // menu-bar-only and island-only modes (activation policy
        // `.accessory`) there is no main menu to carry the shortcut, so this
        // monitor handles it. In Dock mode the App menu's Settings… ⌘, does,
        // and the monitor stays out of the way.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if NSApp.activationPolicy() != .regular,
               event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
               event.charactersIgnoringModifiers == "," {
                self?.showSettings()
                return nil
            }
            return event
        }
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

    /// Ends a running session first so the Mac can sleep again right away,
    /// then quits (the power assertion dies with the process anyway).
    func quit() {
        if state.liveCaffeineState.session != nil { stop() }
        NSApp.terminate(nil)
    }

    /// ⌃⌥C and `caffe toggle`: stop, or start the default duration from Settings.
    func toggle() {
        if state.liveCaffeineState.session != nil { stop() } else { start(minutes: settings.defaultMinutes) }
    }

    /// Keep awake until process `pid` exits. Returns the started session.
    @discardableResult
    func keepAwake(whileProcess pid: Int32) -> CaffeinationSession? {
        guard CaffeineSessionManager.isProcessRunning(pid) else {
            island.flash(String(localized: "That process has already finished"))
            return nil
        }
        return state.startCaffeine(duration: .whileProcess(pid: pid, name: Self.processName(pid)))
    }

    /// Keep awake while an app runs. `app` is a display name or bundle id.
    /// Returns the started session, `nil` if the app isn't running.
    @discardableResult
    func keepAwake(whileApp app: String) -> CaffeinationSession? {
        let running = NSWorkspace.shared.runningApplications.filter { !$0.isTerminated }
        let match = running.first { $0.bundleIdentifier?.caseInsensitiveCompare(app) == .orderedSame }
            ?? running.first { $0.localizedName?.caseInsensitiveCompare(app) == .orderedSame }
            ?? running.first { $0.activationPolicy == .regular && ($0.localizedName?.localizedCaseInsensitiveContains(app) ?? false) }
        guard let match else {
            island.flash(String(localized: "\(app) isn’t running"))
            return nil
        }
        return keepAwake(whileProcess: match.processIdentifier)
    }

    /// App name for a pid, or the executable name for a CLI process.
    static func processName(_ pid: Int32) -> String {
        if let name = NSRunningApplication(processIdentifier: pid)?.localizedName { return name }
        var buffer = [CChar](repeating: 0, count: 256)
        if proc_name(pid, &buffer, UInt32(buffer.count)) > 0 { return String(cString: buffer) }
        return "#\(pid)"
    }

    func showSettings() { settingsWindow.show() }

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
        case let .whileProcess(pid): keepAwake(whileProcess: pid)
        case let .whileApp(app): keepAwake(whileApp: app)
        case .settings: showSettings()
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

    // MARK: - Sleep, wake, power source

    private var lastOnACPower: Bool?

    private func systemDidWake() {
        state.caffeine.sessionManager.systemDidWake()
        updateDockBadge(session: state.liveCaffeineState.session,
                        show: settings.showInDock,
                        badge: settings.dockBadge)
    }

    /// Plugging in or unplugging switches macOS to the other set of sleep
    /// settings; re-read them so the sleep countdown follows. Battery-level
    /// changes alone don't re-run `pmset`.
    private func powerSourceChanged(_ power: PowerSourceSnapshot) {
        guard power.onACPower != lastOnACPower else { return }
        lastOnACPower = power.onACPower
        let reader = state.sleep.reader
        DispatchQueue.global(qos: .utility).async { reader.refresh() }
    }

    // MARK: - Dock

    /// `.regular` shows the Dock icon, ⌘⇥ and the main menu; `.accessory`
    /// is the menu-bar-only default (`LSUIElement`).
    private func applyDockPresence(_ show: Bool) {
        let policy: NSApplication.ActivationPolicy = show ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        let wasActive = NSApp.isActive
        NSApp.setActivationPolicy(policy)
        logger.info("dock icon \(show ? "shown" : "hidden", privacy: .public)")
        guard show, wasActive else {
            // Changing the policy deactivates the app; keep an open Settings
            // window (where the switch was flipped) in front.
            DispatchQueue.main.async { [weak self] in self?.settingsWindow.bringToFrontIfOpen() }
            return
        }
        // An app that is already active doesn't get its main menu installed
        // when it becomes `.regular`: macOS only rebuilds the menu bar on
        // activation. Hand activation to the Dock for a moment, then take
        // it back, so App › Settings… ⌘, and Quit ⌘Q appear at once.
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            NSApp.activate(ignoringOtherApps: true)
            self?.settingsWindow.bringToFrontIfOpen()
        }
    }

    /// Remaining time on the Dock icon, refreshed only when the shown
    /// minute changes (no per-second Dock redraws).
    private func updateDockBadge(session: CaffeinationSession?, show: Bool, badge: Bool) {
        badgeTimer?.invalidate()
        badgeTimer = nil
        guard show, badge, let session else {
            if NSApp.dockTile.badgeLabel != nil { NSApp.dockTile.badgeLabel = nil }
            return
        }
        let remaining = session.remaining()
        let text = DockBadge.text(remaining: remaining)
        if NSApp.dockTile.badgeLabel != text { NSApp.dockTile.badgeLabel = text }
        guard let delay = DockBadge.secondsUntilChange(remaining: remaining) else { return }
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.updateDockBadge(session: self.state.caffeineState.session,
                                     show: self.settings.showInDock,
                                     badge: self.settings.dockBadge)
            }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        badgeTimer = timer
    }

    // MARK: - Battery guard

    private func applyBatteryGuard(_ power: PowerSourceSnapshot) {
        guard state.liveCaffeineState.session != nil else { return }
        switch settings.batteryGuard.verdict(for: power) {
        case .allow:
            return
        case let .batteryLow(percent, _):
            logger.info("battery guard: \(percent)% → stop")
            island.explainNextEnd(String(localized: "Battery at \(percent)%. Your Mac can sleep"))
        case .onBattery:
            logger.info("battery guard: on battery → stop")
            island.explainNextEnd(String(localized: "On battery. Your Mac can sleep"))
        }
        stop()
    }
}

/// App delegate: launch hook + `caffe://` URL handling via Apple Events
/// (reliable for menu-bar-only SwiftUI apps with no WindowGroup).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Info.plist keeps LSUIElement, so a menu-bar-only launch never
        // flashes a Dock icon; Dock mode switches the policy before any UI.
        if AppSettings.launchShowsDock() {
            NSApp.setActivationPolicy(.regular)
        }
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

    /// Opening the app again (Finder, Spotlight, Launchpad) while it runs
    /// shows Settings — the way back when the menu bar item is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Task { @MainActor in AppRuntime.shared.showSettings() }
        return false
    }

    /// Right-click on the Dock icon (Dock mode): same commands as the menu bar.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        MainActor.assumeIsolated { DockMenu.make() }
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
/// permission needed). Toggles a session of the default duration.
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

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        hotKeyRef = nil
        handlerRef = nil
    }
}
