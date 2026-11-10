public struct ProfileCapabilities: OptionSet, Sendable, Hashable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let halfPillRenderer = ProfileCapabilities(rawValue: 1 << 0)
    public static let keyboardActivation = ProfileCapabilities(rawValue: 1 << 1)
    public static let userConfigurable = ProfileCapabilities(rawValue: 1 << 2)
}
