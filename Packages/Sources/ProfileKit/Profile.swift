import Foundation
import SwiftUI

/// The single surface every island profile — built-in or future — implements.
/// See `contracts/profile-contract.md` for the behavioral contract (B-1..B-8).
public protocol Profile: AnyObject, Sendable {
    static var id: ProfileID { get }
    static var metadata: ProfileMetadata { get }
    static var capabilities: ProfileCapabilities { get }
    static var priority: ProfilePriority { get }

    init()

    func makeEventSource() -> any EventSource
    func makeFullPillView(state: AnyProfileState) -> AnyView
    func makeHalfPillView(state: AnyProfileState) -> AnyView?
    func performPrimaryInteraction(from state: AnyProfileState)
    func tearDown()
}

public extension Profile {
    /// Default no-op tearDown. Profiles with OS handles override.
    func tearDown() {}
}
