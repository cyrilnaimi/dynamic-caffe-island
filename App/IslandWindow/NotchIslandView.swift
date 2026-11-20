import AppKit
import BuiltInProfiles
import SleepClock
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Palette

private enum Palette {
    static let coffee = Color(red: 0.93, green: 0.66, blue: 0.40)
    static let crema = Color(red: 1.00, green: 0.86, blue: 0.66)
    /// Secondary text on black. 0.55 white ≈ 6:1 contrast (WCAG AA needs
    /// 4.5:1); Increase Contrast raises it further.
    static func dim(_ contrast: ColorSchemeContrast) -> Color {
        Color.white.opacity(contrast == .increased ? 0.8 : 0.55)
    }
    static let chip = Color.white.opacity(0.10)
    static let chipHover = Color.white.opacity(0.18)
    static let stop = Color(red: 1.0, green: 0.42, blue: 0.38)
}

// MARK: - Island shape

/// One shape for both styles, so switching style morphs smoothly:
///
/// - **Notch** (`ear > 0`, `topRadius == 0`): flat top flush with the screen
///   edge, concave "ears" curving into the top corners.
/// - **Pill** (`ear == 0`, `topRadius > 0`): convex rounded top corners,
///   a capsule when the radii are half the height.
///
/// The top corner goes from (side ± ear ∓ topRadius, top) to
/// (side, top + ear + topRadius) around the control point (side, top), which
/// is a concave ear, a convex corner, or a blend of both while animating.
struct IslandShape: Shape {
    var ear: CGFloat
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(ear, AnimatablePair(topRadius, bottomRadius)) }
        set { ear = newValue.first; topRadius = newValue.second.first; bottomRadius = newValue.second.second }
    }

    func path(in rect: CGRect) -> Path {
        let t = max(0, ear), r = max(0, topRadius)
        let left = rect.minX + t, right = rect.maxX - t
        let vertical = r > 0 ? rect.height - t - r : (rect.height - t) / 1.2
        let b = max(0, min(bottomRadius, vertical, (right - left) / 2))
        var p = Path()
        p.move(to: CGPoint(x: left - t + r, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: left, y: rect.minY + t + r), control: CGPoint(x: left, y: rect.minY))
        p.addLine(to: CGPoint(x: left, y: rect.maxY - b))
        p.addQuadCurve(to: CGPoint(x: left + b, y: rect.maxY), control: CGPoint(x: left, y: rect.maxY))
        p.addLine(to: CGPoint(x: right - b, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: right, y: rect.maxY - b), control: CGPoint(x: right, y: rect.maxY))
        p.addLine(to: CGPoint(x: right, y: rect.minY + t + r))
        p.addQuadCurve(to: CGPoint(x: right + t - r, y: rect.minY), control: CGPoint(x: right, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Root view

/// Custom chrome, on purpose: the island mimics the hardware notch, which is
/// always pure black regardless of light/dark mode, so it uses fixed black /
/// white instead of semantic colours. Everything else (menu, Until window)
/// uses system styles.

struct NotchIslandView: View {
    @ObservedObject var state: AppState
    @ObservedObject var ui: IslandUIModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    private var mode: IslandUIModel.Mode { ui.mode(for: state.caffeineState) }

    var body: some View {
        let body = ui.bodySize(for: mode)
        let ear = ui.ear
        let large = mode == .expanded || mode == .toast
        let pill = ui.shape == .pill
        let bottomRadius: CGFloat = large ? 22 : (pill ? body.height / 2 : 9)
        let topRadius: CGFloat = pill ? (large ? 22 : body.height / 2) : 0
        let shadow = pill ? (large ? 0.45 : 0.3) : (mode == .expanded ? 0.45 : 0)
        // Reduce Motion: no scaling, just a cross-fade.
        let reveal: AnyTransition = reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.92, anchor: .top))

        ZStack(alignment: .top) {
            IslandShape(ear: ear, topRadius: topRadius, bottomRadius: bottomRadius)
                .fill(Color.black)
                .overlay(
                    IslandShape(ear: ear, topRadius: topRadius, bottomRadius: bottomRadius)
                        .stroke(Color.white.opacity(pill && contrast == .increased ? 0.5 : 0), lineWidth: 1)
                )
                .shadow(color: .black.opacity(shadow), radius: pill ? 10 : 14, y: pill ? 4 : 6)

            VStack(spacing: 0) {
                strip
                    .frame(height: ui.stripHeight)
                    .opacity(mode == .idle || mode == .live ? 1 : 0)
                if mode == .toast {
                    ToastRow(text: ui.toast ?? "")
                        .transition(reveal)
                }
                if mode == .expanded {
                    ExpandedPanel(state: state)
                        .transition(reveal)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, ear + 14)
            .clipped()
        }
        .frame(width: body.width + 2 * ear, height: body.height)
        // Hidden when idle: nothing is drawn at all.
        .opacity(mode == .hidden ? 0 : 1)
        .accessibilityHidden(mode == .hidden)
        .padding(.top, ui.topOffset)
        .frame(width: IslandUIModel.canvas.width, height: IslandUIModel.canvas.height, alignment: .top)
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.38, dampingFraction: 0.78), value: mode)
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.45, dampingFraction: 0.85), value: ui.shape)
        .preferredColorScheme(.dark)
    }

    // MARK: Top strip (wings either side of the real / simulated notch)

    @ViewBuilder
    private var strip: some View {
        HStack(spacing: 0) {
            leftWing
            Spacer(minLength: ui.stripGap)
            rightWing
        }
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(stripAccessibilityLabel))
        .accessibilityAddTraits(.updatesFrequently)
    }

    /// The same words the strip shows, as one VoiceOver sentence.
    private var stripAccessibilityLabel: String {
        if let session = state.caffeineState.session {
            if let process = session.watchedProcess {
                return String(localized: "Caffeinated while \(process.name) runs")
            }
            guard let r = session.remaining() else { return String(localized: "Caffeinated indefinitely") }
            return String(localized: "Caffeinated, \(CaffeinationSession.Duration.durationText(max(60, r))) remaining")
        }
        if case .error = state.caffeineState { return String(localized: "Couldn’t keep the Mac awake") }
        if let event = state.sleepState.nextEvent, let r = event.remaining {
            return Format.eventPhrase(event, in: CaffeinationSession.Duration.durationText(max(60, r)))
        }
        return String(localized: "Caffe Island")
    }

    @ViewBuilder
    private var leftWing: some View {
        switch state.caffeineState {
        case .active, .expiring:
            // Static in the always-on pill: a looping animation here would
            // redraw at 60 fps for the whole session (~4–5 % CPU on Intel).
            SteamingCup(size: 13, animate: false)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .inactive:
            if !ui.coversHardwareNotch || mode != .idle {
                Image(systemName: "cup.and.saucer").foregroundStyle(Palette.dim(contrast))
                    .font(.system(size: 11, weight: .medium))
            }
        }
    }

    @ViewBuilder
    private var rightWing: some View {
        if let session = state.caffeineState.session {
            if let process = session.watchedProcess {
                HStack(spacing: 6) {
                    Text(verbatim: process.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 70, alignment: .trailing)
                        .foregroundStyle(.white)
                    ProcessIcon(pid: process.pid, size: 14)
                }
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    HStack(spacing: 6) {
                        Text(Format.clock(session.remaining(now: ctx.date)))
                            .monospacedDigit()
                            .countdownTransition()
                            .foregroundStyle(.white)
                        ProgressRing(fraction: Format.fraction(session, now: ctx.date), lineWidth: 2)
                            .frame(width: 12, height: 12)
                    }
                }
            }
        } else if !ui.coversHardwareNotch || mode != .idle, let r = state.sleepState.nextEvent?.remaining {
            HStack(spacing: 4) {
                Image(systemName: "moon.zzz.fill").font(.system(size: 10))
                Text(Format.clock(r)).monospacedDigit()
            }
            .foregroundStyle(Palette.dim(contrast))
        }
    }
}

// MARK: - Toast

private struct ToastRow: View {
    let text: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 10) {
            SteamingCup(size: 18, animate: !reduceMotion)
            Text(text)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.top, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: text))
        .accessibilityAddTraits(.isStaticText)
    }
}

// MARK: - Expanded panel

private struct ExpandedPanel: View {
    @ObservedObject var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            chips
        }
        .padding(.top, 12)
    }

    private var header: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            HStack(spacing: 14) {
                ZStack {
                    ProgressRing(fraction: ringFraction(ctx.date), lineWidth: 4, smooth: !reduceMotion)
                    if let process = state.caffeineState.session?.watchedProcess {
                        ProcessIcon(pid: process.pid, size: 24)
                    } else {
                        SteamingCup(size: 18, animate: state.caffeineState.isActive && !reduceMotion)
                    }
                }
                .frame(width: 46, height: 46)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(subtitle(ctx.date))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Palette.dim(contrast))
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 0)
                if let s = state.caffeineState.session, let remaining = s.remaining(now: ctx.date) {
                    Text(Format.clock(remaining))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .countdownTransition()
                        .foregroundStyle(Palette.crema)
                        .accessibilityLabel(Text("\(CaffeinationSession.Duration.durationText(max(60, remaining))) remaining"))
                } else if state.caffeineState.session != nil {
                    Text(verbatim: "∞")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(Palette.crema)
                        .accessibilityHidden(true)
                }
                QuitButton()
            }
        }
    }

    /// Idle: duration presets. Active: adjust (+15m / +1h), Until…, Stop.
    /// Never more than 6 chips so the row fits in every language.
    @ViewBuilder
    private var chips: some View {
        HStack(spacing: 6) {
            if let session = state.caffeineState.session {
                if session.expectedEnd != nil {
                    Chip("15m", systemImage: "plus", help: "Add 15 minutes") { extend(session, by: 15) }
                    Chip("1h", systemImage: "plus", help: "Add 1 hour") { extend(session, by: 60) }
                }
                untilChip
                Spacer(minLength: 4)
                Chip("Stop", systemImage: "stop.fill", tint: Palette.stop, help: "Stop and let the Mac sleep (⌃⌥C)") {
                    state.cancelCaffeine()
                }
            } else {
                Chip("15m", help: "Keep awake for 15 minutes") { start(15) }
                Chip("30m", help: "Keep awake for 30 minutes") { start(30) }
                Chip("1h", help: "Keep awake for 1 hour") { start(60) }
                Chip("2h", help: "Keep awake for 2 hours") { start(120) }
                Chip("∞", help: "Keep awake until you stop it") { state.startCaffeine(duration: .indefinite) }
                untilChip
                Spacer(minLength: 0)
            }
        }
    }

    private var untilChip: some View {
        Chip("Until…", systemImage: "clock", help: "Keep awake until a specific time") {
            AppRuntime.shared.showUntilPicker()
        }
    }

    private func extend(_ session: CaffeinationSession, by minutes: Int) {
        let remaining = session.remaining() ?? 0
        state.startCaffeine(duration: .preset(remaining + TimeInterval(minutes * 60)))
    }

    private func start(_ minutes: Int) {
        state.startCaffeine(duration: .preset(TimeInterval(minutes * 60)))
    }

    private var title: String {
        switch state.caffeineState {
        case .active, .expiring: return String(localized: "Keeping your Mac awake")
        case .inactive: return String(localized: "Caffe Island")
        case .error: return String(localized: "Something went wrong")
        }
    }

    private func subtitle(_ now: Date) -> String {
        if let session = state.caffeineState.session {
            if let end = session.expectedEnd {
                return String(localized: "until \(end.formatted(date: .omitted, time: .shortened))")
            }
            if let process = session.watchedProcess {
                return String(localized: "while \(process.name) runs")
            }
            return String(localized: "indefinitely · tap Stop to end")
        }
        if let event = state.sleepState.nextEvent, let r = event.remaining {
            return Format.eventPhrase(event, in: Format.clock(r))
        }
        return String(localized: "Pick a duration to stay awake")
    }

    private func ringFraction(_ now: Date) -> CGFloat {
        guard let session = state.caffeineState.session else { return 0 }
        return Format.fraction(session, now: now)
    }
}

/// ⏻ at the trailing end of the header: dim until hovered so it never
/// competes with the countdown or Stop. The way out when the menu bar item
/// is hidden.
private struct QuitButton: View {
    @State private var hover = false
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Button {
            AppRuntime.shared.quit()
        } label: {
            Image(systemName: "power")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(hover ? Color.white : Palette.dim(contrast))
                .frame(width: 24, height: 24)
                .background(Circle().fill(hover ? Palette.chipHover : Color.clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help("Quit Caffe Island")
        .accessibilityLabel(Text("Quit Caffe Island"))
    }
}

private struct Chip: View {
    let label: LocalizedStringKey
    var systemImage: String?
    var tint: Color = .white
    let help: LocalizedStringKey
    let action: () -> Void
    @State private var hover = false

    init(_ label: LocalizedStringKey, systemImage: String? = nil, tint: Color = .white, help: LocalizedStringKey, action: @escaping () -> Void) {
        self.label = label
        self.systemImage = systemImage
        self.tint = tint
        self.help = help
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage { Image(systemName: systemImage).font(.system(size: 10, weight: .bold)) }
                Text(label)
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .fixedSize()            // never wrap a chip label onto two lines
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(hover ? Palette.chipHover : Palette.chip))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(help)
        .accessibilityLabel(Text(help))
    }
}

// MARK: - Building blocks

struct ProgressRing: View {
    let fraction: CGFloat
    let lineWidth: CGFloat
    /// Interpolate between per-second ticks. Off for the always-on pill so
    /// it redraws once a second instead of continuously.
    var smooth = false

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.14), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(
                    AngularGradient(colors: [Palette.coffee, Palette.crema], center: .center),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .opacity(fraction > 0.005 ? 1 : 0)   // no stray round-cap dot at 0 %
                .animation(smooth ? .linear(duration: 0.9) : nil, value: fraction)
        }
    }
}

/// Cup with three little wisps of steam rising when active.
struct SteamingCup: View {
    let size: CGFloat
    let animate: Bool
    @State private var rise = false

    var body: some View {
        ZStack {
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(Palette.coffee)
            if animate {
                HStack(spacing: size * 0.12) {
                    ForEach(0..<3, id: \.self) { i in
                        Capsule()
                            .fill(Palette.crema.opacity(rise ? 0 : 0.8))
                            .frame(width: max(1.2, size * 0.09), height: size * 0.32)
                            .offset(y: rise ? -size * 0.75 : -size * 0.35)
                            .animation(
                                .easeOut(duration: 1.6).repeatForever(autoreverses: false).delay(Double(i) * 0.35),
                                value: rise
                            )
                    }
                }
                .offset(x: -size * 0.08)
            }
        }
        .onAppear { if animate { rise = true } }
    }
}

enum Format {
    static func clock(_ remaining: TimeInterval?) -> String {
        guard let r = remaining else { return "∞" }
        let total = Int(r.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    static func fraction(_ session: CaffeinationSession, now: Date) -> CGFloat {
        guard let end = session.expectedEnd else { return 1 }
        let total = end.timeIntervalSince(session.startedAt)
        guard total > 0 else { return 0 }
        return CGFloat(max(0, min(1, end.timeIntervalSince(now) / total)))
    }

    /// Whole sentence per event so translators can reorder words freely.
    static func eventPhrase(_ event: SleepClock.NextEvent, in time: String) -> String {
        switch event {
        case .displaySleep: return String(localized: "Display sleeps in \(time)")
        case .screensaver: return String(localized: "Screensaver in \(time)")
        case .systemSleep: return String(localized: "Mac sleeps in \(time)")
        case .none, .suppressed: return String(localized: "Sleep in \(time)")
        }
    }
}

// MARK: - Accessibility / process helpers

private extension View {
    /// Digits roll instead of snapping on macOS 14+ (respects Reduce Motion).
    @ViewBuilder
    func countdownTransition() -> some View {
        if #available(macOS 14.0, *) {
            self.contentTransition(.numericText(countsDown: true))
        } else {
            self
        }
    }
}

/// Icon of the app that owns `pid` (generic app icon for a CLI process).
struct ProcessIcon: View {
    let pid: Int32
    let size: CGFloat

    var body: some View {
        Image(nsImage: NSRunningApplication(processIdentifier: pid)?.icon
            ?? NSWorkspace.shared.icon(for: .unixExecutable))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
