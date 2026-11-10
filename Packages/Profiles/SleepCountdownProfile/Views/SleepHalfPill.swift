import AnimationKit
import Foundation
import IslandCore
import SleepClock
import SwiftUI

public struct SleepCountdownHalfPillView: View {
    public let state: SleepCountdownState

    public init(state: SleepCountdownState) { self.state = state }

    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .foregroundStyle(iconTint)
                .font(.system(size: 12, weight: .medium))
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(state.isUrgent ? Theme.warning : Theme.foreground)
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: Geometry.halfPillInnerWidth, maxHeight: Geometry.height)
        .accessibilityLabel(accessibilityLabel)
    }

    private var iconName: String {
        switch state {
        case .suppressed: return "cup.and.saucer.fill"
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

    private var label: String {
        switch state {
        case .suppressed: return "—"
        case let .idle(event):
            guard let r = event.remaining else { return "—" }
            return SleepCountdownFullPillView.format(remaining: r)
        }
    }

    private var accessibilityLabel: String {
        guard case let .idle(event) = state else { return "Sleep suppressed" }
        return event.label
    }
}
