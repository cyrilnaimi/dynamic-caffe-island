import Foundation

public struct ProfileMetadata: Sendable {
    public let displayName: LocalizedStringResource
    public let iconSystemName: String
    public let summary: LocalizedStringResource

    public init(
        displayName: LocalizedStringResource,
        iconSystemName: String,
        summary: LocalizedStringResource
    ) {
        self.displayName = displayName
        self.iconSystemName = iconSystemName
        self.summary = summary
    }
}
