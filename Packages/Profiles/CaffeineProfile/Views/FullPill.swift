import AnimationKit
import Foundation
import IslandCore
import SwiftUI

/// Full-pill renderer for the Caffeine profile.
///
/// - Active: cup icon + "mm:ss" remaining (or "∞" for indefinite) + `ringTick`.
/// - Expiring: same but with a sweep animation (handled by `.motion`).
/// - Error: warning triangle + label; never fakes success (FR).
/// - Inactive: collapsed to an empty primitive (the arbitrator won't pick
///   caffeine when it's inactive, but we still supply a non-blank rendering
///   so S-6 is honored if something ever reaches here).
public struct CaffeineFullPillView: View {
    public let state: CaffeineState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(state: CaffeineState) { self.state = state }

    public var body: some View {
        HStack(spacing: 6) {
            Image(systemName: iconName)
                .foregroundStyle(iconTint)
                .font(.system(size: 14, weight: .medium))
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.foreground)
            if case let .active(session) = state, !reduceMotion {
                CaffeineRingView(session: session)
                    .frame(width: 12, height: 12)
                    .motion(.ringTick)
            }
        }
        .padding(.horizontal, Geometry.horizontalMargin)
        .frame(maxWidth: Geometry.expandedWidth, maxHeight: Geometry.height)
        .accessibilityLabel(accessibilityLabel)
    }

    private var iconName: String {
        switch state {
        case .active, .expiring: return "cup.and.saucer.fill"
        case .inactive: return "cup.and.saucer"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    private var iconTint: Color {
        switch state {
        case .error: return Theme.warning
        default: return Theme.tint
        }
    }

    private var label: String {
        switch state {
        case let .active(session), let .expiring(session):
            return Self.format(remaining: session.remaining())
        case .inactive:
            return "Keep awake"
        case .error:
            return "Caffeine failed — retry"
        }
    }

    private var accessibilityLabel: String {
        switch state {
        case let .active(session):
            return "Caffeinated, \(Self.accessibleRemaining(session.remaining())) remaining"
        case let .expiring(session):
            return "Caffeine expiring, \(Self.accessibleRemaining(session.remaining())) remaining"
        case .inactive:
            return "Caffeine inactive"
        case let .error(message):
            return "Caffeine error: \(message)"
        }
    }

    static func format(remaining: TimeInterval?) -> String {
        guard let r = remaining else { return "∞" }
        let total = Int(r.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }

    static func accessibleRemaining(_ r: TimeInterval?) -> String {
        guard let r = r else { return "indefinite time" }
        let total = Int(r.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        if h > 0 { return "\(h) hour\(h == 1 ? "" : "s") \(m) minute\(m == 1 ? "" : "s")" }
        return "\(m) minute\(m == 1 ? "" : "s")"
    }
}

/// Circular progress ring that tracks `session.expectedEnd`.
private struct CaffeineRingView: View {
    let session: CaffeinationSession

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { context in
            let fraction = Self.fraction(session: session, now: context.date)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(Theme.tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }

    private static func fraction(session: CaffeinationSession, now: Date) -> CGFloat {
        guard case let .preset(total) = session.duration,
              let end = session.expectedEnd
        else {
            // Indefinite or until-clock — no ring fill progress, show a constant mark.
            return 0.02
        }
        let elapsed = now.timeIntervalSince(session.startedAt)
        let remaining = max(0, end.timeIntervalSince(now))
        _ = remaining
        let f = 1 - (elapsed / total)
        return CGFloat(max(0.02, min(1, f)))
    }
}
