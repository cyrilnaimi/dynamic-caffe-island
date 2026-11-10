import AnimationKit
import Foundation
import IslandCore
import SleepClock
import SwiftUI

public struct SleepCountdownFullPillView: View {
    public let state: SleepCountdownState

    public init(state: SleepCountdownState) { self.state = state }

    public var body: some View {
        HStack(spacing: 6) {
            Image(systemName: iconName)
                .foregroundStyle(iconTint)
                .font(.system(size: 14, weight: .medium))
            if case let .idle(event) = state, event.remaining != nil {
                Text(label(for: event))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(state.isUrgent ? Theme.warning : Theme.foreground)
            } else {
                Text(emptyLabel)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.foreground)
            }
        }
        .padding(.horizontal, Geometry.horizontalMargin)
        .frame(maxWidth: Geometry.expandedWidth, maxHeight: Geometry.height)
        .accessibilityLabel(accessibilityLabel)
    }

    private var iconName: String {
        switch state {
        case .suppressed: return "cup.and.saucer.fill"       // shouldn't render (yielded to caffeine)
        case let .idle(event):
            switch event {
            case .displaySleep: return "display"
            case .screensaver: return "lock.display"
            case .systemSleep: return "moon.zzz.fill"
            case .none: return "moon.slash"
            case .suppressed: return "cup.and.saucer.fill"
            }
        }
    }

    private var iconTint: Color {
        state.isUrgent ? Theme.warning : Theme.tint
    }

    private func label(for event: SleepClock.NextEvent) -> String {
        guard let r = event.remaining else { return "—" }
        return Self.format(remaining: r)
    }

    private var emptyLabel: String {
        if case .idle(.none) = state { return "Sleep disabled" }
        return "—"
    }

    private var accessibilityLabel: String {
        switch state {
        case .suppressed: return "Sleep countdown suppressed while caffeinated"
        case let .idle(event):
            switch event {
            case .none: return "Sleep is disabled; idle display"
            case let .displaySleep(t): return "Display sleep in \(Self.accessibleRemaining(t))"
            case let .screensaver(t): return "Screensaver in \(Self.accessibleRemaining(t))"
            case let .systemSleep(t): return "System sleep in \(Self.accessibleRemaining(t))"
            case .suppressed: return "Sleep countdown suppressed"
            }
        }
    }

    static func format(remaining: TimeInterval) -> String {
        let total = Int(remaining.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }

    static func accessibleRemaining(_ r: TimeInterval) -> String {
        let total = Int(r.rounded())
        let m = total / 60
        let s = total % 60
        if m > 0 { return "\(m) minute\(m == 1 ? "" : "s")" }
        return "\(s) second\(s == 1 ? "" : "s")"
    }
}
