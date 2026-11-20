import AnimationKit
import Foundation
import IslandCore
import SwiftUI

/// Compact renderer for the secondary slot. Stays inside
/// `Geometry.halfPillInnerWidth` (= 158 pt). Icon + compact mm:ss only.
public struct CaffeineHalfPillView: View {
    public let state: CaffeineState

    public init(state: CaffeineState) { self.state = state }

    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .foregroundStyle(iconTint)
                .font(.system(size: 12, weight: .medium))
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.foreground)
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: Geometry.halfPillInnerWidth, maxHeight: Geometry.height)
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
        if case .error = state { return Theme.warning }
        return Theme.tint
    }

    private var label: String {
        switch state {
        case let .active(session), let .expiring(session):
            return CaffeineFullPillView.format(remaining: session.remaining())
        case .inactive: return "—"
        case .error: return "!"
        }
    }

    private var accessibilityLabel: String {
        switch state {
        case let .active(session):
            return "Caffeinated, \(CaffeineFullPillView.accessibleRemaining(session.remaining())) remaining"
        case .inactive: return "Caffeine inactive"
        case .expiring: return "Caffeine expiring"
        case let .error(message): return "Caffeine error: \(message)"
        }
    }
}
