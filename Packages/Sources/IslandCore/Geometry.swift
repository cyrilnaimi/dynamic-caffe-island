import Foundation
import CoreGraphics

/// Geometry tokens. Values locked at the UI checkpoint (02-ui-concept.md §1).
public enum Geometry {
    public static let height: CGFloat = 32
    public static let compactWidth: CGFloat = 96
    public static let expandedWidth: CGFloat = 240
    public static let splitWidth: CGFloat = 320
    public static let splitGap: CGFloat = 4
    public static let cornerRadius: CGFloat = 16   // = height / 2
    public static let horizontalMargin: CGFloat = 10
    public static let notchClearance: CGFloat = 6
    public static let verticalOffset: CGFloat = 0

    /// Inner width of a half-pill container: (splitWidth - splitGap) / 2.
    public static var halfPillInnerWidth: CGFloat {
        (splitWidth - splitGap) / 2
    }
}
