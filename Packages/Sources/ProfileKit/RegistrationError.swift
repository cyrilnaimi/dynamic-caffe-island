import Foundation

public enum RegistrationError: Error, Equatable, CustomStringConvertible {
    case duplicate(ProfileID)
    case incompatibleContractVersion(ProfileID, SemanticVersion)
    case bundleInvalid(URL, reason: String)

    public var description: String {
        switch self {
        case let .duplicate(id):
            return "RegistrationError.duplicate(\(id))"
        case let .incompatibleContractVersion(id, v):
            return "RegistrationError.incompatibleContractVersion(\(id), \(v))"
        case let .bundleInvalid(url, reason):
            return "RegistrationError.bundleInvalid(\(url.path), \(reason))"
        }
    }
}
