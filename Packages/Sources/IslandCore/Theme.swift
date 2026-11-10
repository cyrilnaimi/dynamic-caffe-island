import SwiftUI

/// Semantic color tokens. Real values are resolved per system appearance at
/// runtime; profiles must only use these tokens, never raw colors (S-5).
public enum Theme {
    public static let surface: Color = Color(nsColor: .windowBackgroundColor)
    public static let foreground: Color = Color(nsColor: .labelColor)
    public static let tint: Color = .accentColor
    public static let accent: Color = .accentColor
    public static let warning: Color = .orange
    public static let focusRing: Color = Color(nsColor: .keyboardFocusIndicatorColor)
}
