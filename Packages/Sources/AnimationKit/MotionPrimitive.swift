import Foundation

public enum Direction: Sendable, Equatable {
    case leading, trailing, up, down
}

public enum IslandSlot: Sendable, Equatable {
    case leading, center, trailing
}

public enum SystemIcon: Sendable, Equatable {
    case named(String)
    public static let warning = SystemIcon.named("exclamationmark.triangle.fill")
}

/// The finite set of motion primitives profiles may compose.
/// Adding a new primitive is a minor-version bump to AnimationKit and
/// requires an animation-checkpoint update (V-2).
public enum MotionPrimitive: Sendable, Equatable {
    case pillExpand
    case pillCollapse
    case pillSplit
    case pillRejoin
    case pulse
    case ringTick
    case sweep(Direction)
    case icon(SystemIcon)
    case label(IslandSlot)

    public var name: String {
        switch self {
        case .pillExpand: return "pillExpand"
        case .pillCollapse: return "pillCollapse"
        case .pillSplit: return "pillSplit"
        case .pillRejoin: return "pillRejoin"
        case .pulse: return "pulse"
        case .ringTick: return "ringTick"
        case .sweep: return "sweep"
        case .icon: return "icon"
        case .label: return "label"
        }
    }
}
