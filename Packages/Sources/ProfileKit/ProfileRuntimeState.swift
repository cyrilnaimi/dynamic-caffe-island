import Foundation

public protocol ProfileRuntimeState: Sendable, Equatable {}

/// Type-erased profile state. The core never inspects the wrapped value beyond
/// equality; it is what the profile's renderers consume.
public enum AnyProfileState: @unchecked Sendable, Equatable {
    case empty
    case typed(AnyTypedState)

    public static func == (lhs: AnyProfileState, rhs: AnyProfileState) -> Bool {
        switch (lhs, rhs) {
        case (.empty, .empty):
            return true
        case let (.typed(a), .typed(b)):
            return a == b
        default:
            return false
        }
    }

    public static func wrap<S: ProfileRuntimeState>(_ state: S) -> AnyProfileState {
        .typed(AnyTypedState(state))
    }

    public func unwrap<S: ProfileRuntimeState>(as type: S.Type = S.self) -> S? {
        guard case let .typed(box) = self else { return nil }
        return box.value as? S
    }
}

public struct AnyTypedState: @unchecked Sendable, Equatable {
    public let value: any ProfileRuntimeState
    private let _isEqual: (any ProfileRuntimeState) -> Bool

    public init<S: ProfileRuntimeState>(_ value: S) {
        self.value = value
        self._isEqual = { other in
            guard let other = other as? S else { return false }
            return other == value
        }
    }

    public static func == (lhs: AnyTypedState, rhs: AnyTypedState) -> Bool {
        lhs._isEqual(rhs.value)
    }
}
