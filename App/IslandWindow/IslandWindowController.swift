import AppKit
import BuiltInProfiles
import Combine
import OSLog
import SwiftUI

/// UI-only state for the notch island: hover, transient toast, and the
/// geometry of the display it is anchored to.
@MainActor
final class IslandUIModel: ObservableObject {
    enum Mode: Equatable { case idle, live, toast, expanded }

    @Published var hovering = false
    @Published var toast: String?
    @Published var hasNotch = false
    /// Height of the menu bar / hardware notch on the anchored display.
    @Published var barHeight: CGFloat = 24
    /// Width of the hardware notch (0 on non-notched displays).
    @Published var notchWidth: CGFloat = 0

    /// Width of the concave "ears" that blend the shape into the top edge.
    static let ear: CGFloat = 8
    static let canvas = CGSize(width: 540, height: 200)

    func mode(for caffeine: CaffeineState) -> Mode {
        if hovering { return .expanded }
        if toast != nil { return .toast }
        switch caffeine {
        case .active, .expiring: return .live
        case .inactive, .error: return .idle
        }
    }

    /// Size of the black body (ears excluded).
    func bodySize(for mode: Mode) -> CGSize {
        switch mode {
        case .idle:
            return CGSize(width: hasNotch ? notchWidth : 170, height: barHeight)
        case .live:
            return CGSize(width: hasNotch ? notchWidth + 2 * 78 : 250, height: barHeight)
        case .toast:
            return CGSize(width: max(340, notchWidth + 120), height: barHeight + 50)
        case .expanded:
            return CGSize(width: max(480, notchWidth + 160), height: barHeight + 124)
        }
    }

    /// Wing gap in the top strip — the hardware notch, or a small gap.
    var stripGap: CGFloat { hasNotch ? notchWidth : 24 }
}

/// Owns the island `NSPanel`: anchors it to the top-centre of the primary
/// display, simulates a notch on displays that don't have one, tracks the
/// pointer for hover-expand, and flashes a toast when a session starts/stops.
@MainActor
final class IslandWindowController {
    private let logger = Logger(subsystem: "ch.dynamic-caffe-island.app", category: "island-window")

    private let appState: AppState
    let ui = IslandUIModel()

    private var panel: IslandPanel?
    private var cancellables = Set<AnyCancellable>()
    private var observers: [NSObjectProtocol] = []
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var collapseWork: DispatchWorkItem?
    private var toastWork: DispatchWorkItem?
    private var lastSessionID: UUID?

    init(appState: AppState) {
        self.appState = appState
    }

    /// Install the panel and begin tracking. Idempotent.
    func start() {
        guard panel == nil else { return }

        let root = NotchIslandView(state: appState, ui: ui)
        let hosting = FirstMouseHostingView(rootView: root)
        let frame = NSRect(origin: .zero, size: IslandUIModel.canvas)
        hosting.frame = frame
        hosting.autoresizingMask = [.width, .height]

        let p = IslandPanel(contentView: hosting, frame: frame)
        panel = p
        relayout()
        p.orderFrontRegardless()

        appState.$caffeineState
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.caffeineChanged($0) }
            .store(in: &cancellables)

        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.relayout() } })

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            Task { @MainActor in self?.pointerMoved() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            Task { @MainActor in self?.pointerMoved() }
            return event
        }
        logger.info("island started (notch=\(self.ui.hasNotch), bar=\(self.ui.barHeight))")
    }

    // MARK: - Toasts

    func flash(_ text: String, for seconds: TimeInterval = 2.4) {
        toastWork?.cancel()
        ui.toast = text
        let work = DispatchWorkItem { [weak self] in self?.ui.toast = nil }
        toastWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func caffeineChanged(_ state: CaffeineState) {
        switch state {
        case let .active(session):
            if session.id != lastSessionID {
                lastSessionID = session.id
                flash(String(localized: "Brewing… awake \(session.duration.humanLabel)"))
            }
        case .expiring:
            break
        case .inactive:
            if lastSessionID != nil {
                lastSessionID = nil
                flash(String(localized: "Coffee’s over. Your Mac can sleep"), for: 1.8)
            }
        case .error:
            flash(String(localized: "Couldn’t keep the Mac awake"))
        }
    }

    /// Expand the island without hovering (URL `caffe://peek`). The panel
    /// takes clicks while open; it collapses after `seconds` unless hovered.
    func peek(for seconds: TimeInterval = 5) {
        collapseWork?.cancel()
        ui.hovering = true
        panel?.ignoresMouseEvents = false
        let work = DispatchWorkItem { [weak self] in
            self?.collapseWork = nil
            self?.ui.hovering = false
            self?.pointerMoved()
        }
        collapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    // MARK: - Pointer tracking

    private func pointerMoved() {
        guard let panel, let screen = anchorScreen() else { return }
        let mode = ui.mode(for: appState.caffeineState)
        let body = ui.bodySize(for: mode)
        let w = body.width + 2 * IslandUIModel.ear
        let hot = NSRect(x: screen.frame.midX - w / 2, y: screen.frame.maxY - body.height, width: w, height: body.height)
            .insetBy(dx: -6, dy: -6)
        let inside = hot.contains(NSEvent.mouseLocation)

        panel.ignoresMouseEvents = !inside
        if inside {
            collapseWork?.cancel()
            collapseWork = nil
            if !ui.hovering { ui.hovering = true }
        } else if ui.hovering, collapseWork == nil {
            let work = DispatchWorkItem { [weak self] in
                self?.ui.hovering = false
                self?.collapseWork = nil
            }
            collapseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
        }
    }

    // MARK: - Geometry

    /// The primary display (the one with the menu bar).
    private func anchorScreen() -> NSScreen? {
        NSScreen.screens.first ?? NSScreen.main
    }

    private func relayout() {
        guard let panel, let screen = anchorScreen() else { return }
        let top = screen.safeAreaInsets.top
        if top > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            ui.hasNotch = true
            ui.barHeight = top
            ui.notchWidth = screen.frame.width - left.width - right.width
        } else {
            ui.hasNotch = false
            ui.notchWidth = 0
            let bar = screen.frame.maxY - screen.visibleFrame.maxY
            ui.barHeight = bar > 10 ? bar : 24
        }
        let size = IslandUIModel.canvas
        let frame = NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
        panel.setFrame(frame, display: true)
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
        }
    }
}
