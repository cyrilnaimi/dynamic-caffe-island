import BuiltInProfiles
import SleepClock
import SwiftUI

// MARK: - Palette

private enum Palette {
    static let coffee = Color(red: 0.93, green: 0.66, blue: 0.40)
    static let crema = Color(red: 1.00, green: 0.86, blue: 0.66)
    static let dim = Color.white.opacity(0.45)
    static let chip = Color.white.opacity(0.10)
    static let chipHover = Color.white.opacity(0.18)
    static let stop = Color(red: 1.0, green: 0.42, blue: 0.38)
}

// MARK: - Notch shape

/// A notch silhouette: flat top flush with the screen edge, concave "ears"
/// curving into the top corners, rounded bottom corners.
struct NotchShape: Shape {
    var ear: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(ear, bottomRadius) }
        set { ear = newValue.first; bottomRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let t = ear
        let b = min(bottomRadius, (rect.height - t) / 1.2, (rect.width - 2 * t) / 2)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + t, y: rect.minY + t), control: CGPoint(x: rect.minX + t, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + t, y: rect.maxY - b))
        p.addQuadCurve(to: CGPoint(x: rect.minX + t + b, y: rect.maxY), control: CGPoint(x: rect.minX + t, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - t - b, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - t, y: rect.maxY - b), control: CGPoint(x: rect.maxX - t, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - t, y: rect.minY + t))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.maxX - t, y: rect.minY))
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

    private var mode: IslandUIModel.Mode { ui.mode(for: state.caffeineState) }

    var body: some View {
        let body = ui.bodySize(for: mode)
        let ear = IslandUIModel.ear
        let radius: CGFloat = mode == .expanded || mode == .toast ? 22 : 9

        ZStack(alignment: .top) {
            NotchShape(ear: ear, bottomRadius: radius)
                .fill(Color.black)
                .shadow(color: .black.opacity(mode == .expanded ? 0.45 : 0), radius: 14, y: 6)

            VStack(spacing: 0) {
                strip
                    .frame(height: ui.barHeight)
                    .opacity(mode == .idle || mode == .live ? 1 : 0)
                if mode == .toast {
                    ToastRow(text: ui.toast ?? "")
                        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .top)))
                }
                if mode == .expanded {
                    ExpandedPanel(state: state)
                        .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .top)))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, ear + 14)
            .clipped()
        }
        .frame(width: body.width + 2 * ear, height: body.height)
        .frame(width: IslandUIModel.canvas.width, height: IslandUIModel.canvas.height, alignment: .top)
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.38, dampingFraction: 0.78), value: mode)
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
            if !ui.hasNotch || mode != .idle {
                Image(systemName: "cup.and.saucer").foregroundStyle(Palette.dim)
                    .font(.system(size: 11, weight: .medium))
            }
        }
    }

    @ViewBuilder
    private var rightWing: some View {
        if let session = state.caffeineState.session {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                HStack(spacing: 6) {
                    Text(Format.clock(session.remaining(now: ctx.date)))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                    ProgressRing(fraction: Format.fraction(session, now: ctx.date), lineWidth: 2)
                        .frame(width: 12, height: 12)
                }
            }
        } else if !ui.hasNotch || mode != .idle, let r = state.sleepState.nextEvent?.remaining {
            HStack(spacing: 4) {
                Image(systemName: "moon.zzz.fill").font(.system(size: 10))
                Text(Format.clock(r)).monospacedDigit()
            }
            .foregroundStyle(Palette.dim)
        }
    }
}

// MARK: - Toast

private struct ToastRow: View {
    let text: String
    var body: some View {
        HStack(spacing: 10) {
            SteamingCup(size: 18, animate: true)
            Text(text)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.top, 10)
    }
}

// MARK: - Expanded panel

private struct ExpandedPanel: View {
    @ObservedObject var state: AppState

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
                    ProgressRing(fraction: ringFraction(ctx.date), lineWidth: 4, smooth: true)
                    SteamingCup(size: 18, animate: state.caffeineState.isActive)
                }
                .frame(width: 46, height: 46)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(subtitle(ctx.date))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Palette.dim)
                }
                Spacer(minLength: 0)
                if let s = state.caffeineState.session {
                    Text(Format.clock(s.remaining(now: ctx.date)))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Palette.crema)
                }
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
