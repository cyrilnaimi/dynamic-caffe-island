import AppKit
import BuiltInProfiles
import Combine
import OSLog
import SwiftUI

/// UI-only state for one island: hover, transient toast, style, and the
/// geometry of the display it is anchored to.
@MainActor
final class IslandUIModel: ObservableObject {
    enum Mode: Equatable { case hidden, idle, live, toast, expanded }
    /// Resolved shape (the `automatic` setting picks one per display).
    enum Shape: Equatable { case notch, pill }

    @Published var hovering = false
    @Published var toast: String?
    @Published var hasNotch = false
    /// Height of the menu bar / hardware notch on the anchored display.
    @Published var barHeight: CGFloat = 24
    /// Width of the hardware notch (0 on non-notched displays).
    @Published var notchWidth: CGFloat = 0
    @Published var shape: Shape = .notch
    /// "Hidden when idle": draw nothing until a session, toast or hover.
    @Published var hideWhenIdle = false

    /// Width of the concave "ears" that blend the notch into the top edge.
    static let notchEar: CGFloat = 8
    /// Height of the compact floating pill.
    static let pillHeight: CGFloat = 30
    /// Gap between the menu bar and the floating pill.
    static let pillGap: CGFloat = 6
    static let canvas = CGSize(width: 540, height: 230)

    var ear: CGFloat { shape == .notch ? Self.notchEar : 0 }
    /// Distance from the top of the screen to the top of the body.
    var topOffset: CGFloat { shape == .notch ? 0 : barHeight + Self.pillGap }
    /// Height of the compact strip (idle / live).
    var stripHeight: CGFloat { shape == .notch ? barHeight : Self.pillHeight }
    /// Only a notch on a notched display has to leave room for the hardware.
    var coversHardwareNotch: Bool { shape == .notch && hasNotch }

    func mode(for caffeine: CaffeineState) -> Mode {
        if hovering { return .expanded }
        if toast != nil { return .toast }
        switch caffeine {
        case .active, .expiring: return .live
        case .inactive, .error: return hideWhenIdle ? .hidden : .idle
        }
    }

    /// Size of the body (ears excluded).
    func bodySize(for mode: Mode) -> CGSize {
        let notchW = coversHardwareNotch ? notchWidth : 0
        switch mode {
        case .hidden, .idle:
            return CGSize(width: coversHardwareNotch ? notchWidth : (shape == .pill ? 150 : 170), height: stripHeight)
        case .live:
            return CGSize(width: coversHardwareNotch ? notchWidth + 2 * 78 : 250, height: stripHeight)
        case .toast:
            return CGSize(width: max(340, notchW + 120), height: stripHeight + 50)
        case .expanded:
            return CGSize(width: max(480, notchW + 160), height: stripHeight + 124)
        }
    }

    /// Wing gap in the top strip — the hardware notch, or a small gap.
    var stripGap: CGFloat { coversHardwareNotch ? notchWidth : 24 }
}

/// One island: a panel on one display plus its UI model.
@MainActor
private final class ScreenIsland {
    let displayID: CGDirectDisplayID
    let ui = IslandUIModel()
    let panel: IslandPanel
    var collapseWork: DispatchWorkItem?
    var overFullScreen = false

    init(displayID: CGDirectDisplayID, appState: AppState) {
        self.displayID = displayID
        let root = NotchIslandView(state: appState, ui: ui)
        let hosting = FirstMouseHostingView(rootView: root)
        let frame = NSRect(origin: .zero, size: IslandUIModel.canvas)
        hosting.frame = frame
        hosting.autoresizingMask = [.width, .height]
        panel = IslandPanel(contentView: hosting, frame: frame)
    }

    var screen: NSScreen? { NSScreen.screens.first { $0.displayID == displayID } }
}

/// Owns the island panels: one per target display (see `IslandScreenChoice`).
/// Anchors each to the top-centre of its display, simulates a notch or
/// floats a pill, tracks the pointer for hover-expand, flashes toasts,
/// and hides over full-screen apps.
@MainActor
final class IslandWindowController {
    private let logger = Logger(subsystem: "ch.dynamic-caffe-island.app", category: "island-window")

    private let appState: AppState
    private let settings: AppSettings
    private var islands: [ScreenIsland] = []
    private var started = false
    private var cancellables = Set<AnyCancellable>()
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var toastWork: DispatchWorkItem?
    private var followWork: DispatchWorkItem?
    private var fullScreenRecheck: DispatchWorkItem?
    private var lastSession: CaffeinationSession?
    /// Explains the next automatic stop (battery guard…), shown instead of
    /// the generic "coffee's over" toast.
    private var pendingEndMessage: String?
    /// For `.active`: the display currently showing the island.
    private var activeDisplayID: CGDirectDisplayID?

    init(appState: AppState, settings: AppSettings) {
        self.appState = appState
        self.settings = settings
    }

    /// Install the panels and begin tracking. Idempotent.
    func start() {
        guard !started else { return }
        started = true
        syncIslands()

        appState.$caffeineState
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.caffeineChanged($0) }
            .store(in: &cancellables)
        appState.startFailedWhileRunning
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.flash($0) }
            .store(in: &cancellables)

        // Any island setting: rebuild / restyle immediately, no relaunch.
        Publishers.MergeMany(
            settings.$islandStyle.map { _ in () }.eraseToAnyPublisher(),
            settings.$hideIslandWhenIdle.map { _ in () }.eraseToAnyPublisher(),
            settings.$islandScreen.map { _ in () }.eraseToAnyPublisher(),
            settings.$fullScreenBehavior.map { _ in () }.eraseToAnyPublisher()
        )
        .dropFirst(4)
        .receive(on: RunLoop.main)
        .sink { [weak self] in self?.syncIslands() }
        .store(in: &cancellables)

        observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification) { $0.syncIslands() }
        let ws = NSWorkspace.shared.notificationCenter
        observe(ws, NSWorkspace.activeSpaceDidChangeNotification) { $0.refreshFullScreen() }
        observe(ws, NSWorkspace.didActivateApplicationNotification) { controller in
            controller.refreshFullScreen()
            controller.followActiveWindow()
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            Task { @MainActor in self?.pointerMoved() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            Task { @MainActor in self?.pointerMoved() }
            return event
        }
        logger.info("island started on \(self.islands.count) display(s)")
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ action: @escaping (IslandWindowController) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in if let self { action(self) } }
        }
        observers.append((center, token))
    }

    // MARK: - Toasts

    func flash(_ text: String, for seconds: TimeInterval = 2.4) {
        toastWork?.cancel()
        for island in islands { island.ui.toast = text }
        updateVisibility()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            for island in self.islands { island.ui.toast = nil }
            self.updateVisibility()
        }
        toastWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    /// The next time the session ends, explain why with `message`.
    func explainNextEnd(_ message: String) {
        pendingEndMessage = message
    }

    private func caffeineChanged(_ state: CaffeineState) {
        switch state {
        case let .active(session):
            if session.id != lastSession?.id {
                lastSession = session
                flash(String(localized: "Brewing… awake \(session.duration.humanLabel)"))
            }
        case .expiring:
            break
        case .inactive:
            if let ended = lastSession {
                lastSession = nil
                flash(endMessage(for: ended), for: 2.2)
            }
        case .error:
            flash(String(localized: "Couldn’t keep the Mac awake"))
        }
        updateVisibility()
    }

    private func endMessage(for session: CaffeinationSession) -> String {
        defer { pendingEndMessage = nil }
        if let pendingEndMessage { return pendingEndMessage }
        if case let .processExited(name) = appState.caffeine.sessionManager.lastEndReason,
           session.watchedProcess != nil {
            return String(localized: "\(name) finished. Your Mac can sleep")
        }
        return String(localized: "Coffee’s over. Your Mac can sleep")
    }

    /// Expand the island without hovering (URL `caffe://peek`). The panel
    /// takes clicks while open; it collapses after `seconds` unless hovered.
    func peek(for seconds: TimeInterval = 5) {
        guard let island = islands.first(where: { $0.screen?.frame.contains(NSEvent.mouseLocation) == true }) ?? islands.first
        else { return }
        island.collapseWork?.cancel()
        island.ui.hovering = true
        island.panel.ignoresMouseEvents = false
        updateVisibility()
        let work = DispatchWorkItem { [weak self, weak island] in
            island?.collapseWork = nil
            island?.ui.hovering = false
            self?.pointerMoved()
        }
        island.collapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    // MARK: - Which displays

    private func targetScreens() -> [NSScreen] {
        let screens = NSScreen.screens
        switch settings.islandScreen {
        case .main:
            return Array(screens.prefix(1))
        case .all:
            return screens
        case .active:
            if let id = activeDisplayID, let screen = screens.first(where: { $0.displayID == id }) {
                return [screen]
            }
            let mouse = NSEvent.mouseLocation
            return [screens.first { $0.frame.contains(mouse) } ?? screens.first].compactMap { $0 }
        }
    }

    /// Create / remove panels so there is exactly one per target display,
    /// then lay each out. Called at start, on display changes (plug, unplug,
    /// resolution, clamshell) and when a setting changes.
    private func syncIslands() {
        guard started else { return }
        let targets = targetScreens()
        let ids = targets.map(\.displayID)
        activeDisplayID = settings.islandScreen == .active ? ids.first : nil

        for island in islands where !ids.contains(island.displayID) {
            island.panel.orderOut(nil)
        }
        islands.removeAll { !ids.contains($0.displayID) }
        for screen in targets where !islands.contains(where: { $0.displayID == screen.displayID }) {
            let island = ScreenIsland(displayID: screen.displayID, appState: appState)
            if let toast = islands.first?.ui.toast { island.ui.toast = toast }
            islands.append(island)
            island.panel.alphaValue = 0
            island.panel.orderFrontRegardless()
        }
        for island in islands { layout(island) }
        refreshFullScreen()
    }

    // MARK: - Geometry

    private func layout(_ island: ScreenIsland) {
        guard let screen = island.screen else { return }
        let ui = island.ui
        let top = screen.safeAreaInsets.top
        if top > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            ui.hasNotch = true
            ui.barHeight = top
            ui.notchWidth = screen.frame.width - left.width - right.width
        } else {
            ui.hasNotch = false
            ui.notchWidth = 0
            let bar = screen.frame.maxY - screen.visibleFrame.maxY
            // Menu bar set to auto-hide: visibleFrame reaches the top.
            ui.barHeight = bar > 10 ? min(bar, 44) : NSStatusBar.system.thickness
        }
        switch settings.islandStyle {
        case .notch: ui.shape = .notch
        case .pill: ui.shape = .pill
        case .automatic: ui.shape = ui.hasNotch ? .notch : .pill
        }
        ui.hideWhenIdle = settings.hideIslandWhenIdle

        let size = IslandUIModel.canvas
        island.panel.setFrame(NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        ), display: true)
    }

    // MARK: - Full screen

    /// Re-evaluate now and once more after the space-switch animation
    /// settles (the window list lags behind the notification). Event-driven:
    /// never a polling loop.
    private func refreshFullScreen() {
        evaluateFullScreen()
        fullScreenRecheck?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.evaluateFullScreen() }
        fullScreenRecheck = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    private func evaluateFullScreen() {
        for island in islands {
            guard let screen = island.screen else { continue }
            island.overFullScreen = FullScreenDetector.isFullScreenAppFront(on: screen)
        }
        updateVisibility()
    }

    /// Fade each panel in or out according to the full-screen setting.
    private func updateVisibility() {
        let alert = islands.contains { $0.ui.toast != nil }
            || { if case .expiring = appState.caffeineState { return true } else { return false } }()
        for island in islands {
            let visible: Bool
            if !island.overFullScreen {
                visible = true
            } else {
                switch settings.fullScreenBehavior {
                case .show: visible = true
                case .hide: visible = false
                case .alertsOnly: visible = alert
                }
            }
            let target: CGFloat = visible ? 1 : 0
            guard island.panel.alphaValue != target else { continue }
            if !visible {
                island.ui.hovering = false
                island.panel.ignoresMouseEvents = true
            }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = visible ? 0.25 : 0.18
                ctx.timingFunction = CAMediaTimingFunction(name: visible ? .easeOut : .easeIn)
                island.panel.animator().alphaValue = target
            }
        }
    }

    // MARK: - Following the active display

    /// `.active`: move the island to the display with the frontmost app's
    /// window when another app comes to the front.
    private func followActiveWindow() {
        guard settings.islandScreen == .active,
              let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              pid != ProcessInfo.processInfo.processIdentifier,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
              let window = list.first(where: { ($0[kCGWindowOwnerPID as String] as? pid_t) == pid && ($0[kCGWindowLayer as String] as? Int) == 0 }),
              let dict = window[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: dict),
              let primary = NSScreen.screens.first
        else { return }
        // CG (top-left origin) → AppKit (bottom-left origin).
        let center = CGPoint(x: bounds.midX, y: primary.frame.maxY - bounds.midY)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }) {
            moveActiveIsland(to: screen.displayID, debounce: 0)
        }
    }

    private func moveActiveIsland(to displayID: CGDirectDisplayID, debounce: TimeInterval) {
        guard settings.islandScreen == .active else { return }
        if displayID == activeDisplayID {
            followWork?.cancel()
            followWork = nil
            return
        }
        guard followWork == nil || debounce == 0 else { return }
        followWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.followWork = nil
            self.activeDisplayID = displayID
            self.syncIslands()
        }
        followWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + debounce, execute: work)
    }

    // MARK: - Pointer tracking

    private func pointerMoved() {
        let mouse = NSEvent.mouseLocation
        if settings.islandScreen == .active,
           let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) {
            moveActiveIsland(to: screen.displayID, debounce: 0.4)
        }
        for island in islands { track(island, mouse: mouse) }
    }

    private func track(_ island: ScreenIsland, mouse: NSPoint) {
        guard let screen = island.screen, island.panel.alphaValue > 0 else { return }
        let ui = island.ui
        let mode = ui.mode(for: appState.caffeineState)
        let hot: NSRect
        if mode == .hidden {
            // Thin hot zone at the top centre (the notch itself on notched displays).
            let w = max(ui.notchWidth, 200)
            let h = ui.hasNotch ? ui.barHeight : 3
            hot = NSRect(x: screen.frame.midX - w / 2, y: screen.frame.maxY - h, width: w, height: h)
        } else {
            let body = ui.bodySize(for: mode)
            let w = body.width + 2 * ui.ear
            hot = NSRect(x: screen.frame.midX - w / 2, y: screen.frame.maxY - ui.topOffset - body.height, width: w, height: body.height)
                .insetBy(dx: -6, dy: -6)
        }
        let inside = hot.contains(mouse)

        island.panel.ignoresMouseEvents = !inside
        if inside {
            island.collapseWork?.cancel()
            island.collapseWork = nil
            if !ui.hovering { ui.hovering = true }
        } else if ui.hovering, island.collapseWork == nil {
            let work = DispatchWorkItem { [weak island] in
                island?.ui.hovering = false
                island?.collapseWork = nil
            }
            island.collapseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
        }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}

extension CaffeinationSession.Duration {
    /// Short localised duration ("1 hr, 30 min", "1 h 30 min"…) via Foundation.
    static func durationText(_ seconds: TimeInterval) -> String {
        let f = DateComponentsFormatter()
        f.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute]
        f.unitsStyle = .short
        f.zeroFormattingBehavior = .dropAll
        return f.string(from: seconds) ?? "\(Int(seconds / 60)) min"
    }

    var humanLabel: String {
        switch self {
        case let .preset(seconds):
            return String(localized: "for \(Self.durationText(seconds))")
        case let .untilClockTime(date):
            return String(localized: "until \(date.formatted(date: .omitted, time: .shortened))")
        case .indefinite:
            return String(localized: "until you stop it")
        case let .whileProcess(_, name):
            return String(localized: "while \(name) runs")
        }
    }
}
