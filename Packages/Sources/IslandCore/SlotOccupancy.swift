import Foundation
import ProfileKit

public enum SlotOccupancy: Sendable, Equatable {
    case empty
    case occupied(
        profileID: ProfileID,
        state: AnyProfileState,
        enteredAt: Date,
        variant: RenderVariant
    )

    public var profileID: ProfileID? {
        if case let .occupied(id, _, _, _) = self { return id }
        return nil
    }

    public var isEmpty: Bool {
        if case .empty = self { return true }
        return false
    }

    public var enteredAt: Date? {
        if case let .occupied(_, _, enteredAt, _) = self { return enteredAt }
        return nil
    }
}

public struct SlotState: Sendable, Equatable {
    public var primary: SlotOccupancy
    public var secondary: SlotOccupancy

    public init(primary: SlotOccupancy = .empty, secondary: SlotOccupancy = .empty) {
        self.primary = primary
        self.secondary = secondary
    }

    public static let empty = SlotState(primary: .empty, secondary: .empty)

    public var isAllEmpty: Bool { primary.isEmpty && secondary.isEmpty }
}
