import Foundation

public struct ProfileID: Hashable, Sendable, Codable, CustomStringConvertible {
    public let raw: String

    public init(raw: String) {
        self.raw = raw
    }

    public var description: String { raw }
}
