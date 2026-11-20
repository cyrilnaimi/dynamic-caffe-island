import SwiftUI

/// `.motion(_:)` view modifier — the public entry point profiles use instead
/// of `withAnimation` (V-1). Reduce Motion is honored automatically (V-3):
/// when `accessibilityReduceMotion == true` the animation is substituted
/// with a cross-fade of `MotionTokens.reducedMotionCrossFade`.
public extension View {
    func motion(_ primitive: MotionPrimitive) -> some View {
        modifier(MotionModifier(primitive: primitive))
    }
}

private struct MotionModifier: ViewModifier {
    let primitive: MotionPrimitive
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let animation = reduceMotion ? Animation.reducedMotionCrossFade : animation(for: primitive)
        return content.animation(animation, value: primitive.name)
    }

    private func animation(for primitive: MotionPrimitive) -> Animation {
        switch primitive {
        case .pillExpand, .pillCollapse, .pillSplit, .pillRejoin, .sweep:
            return .presentSpring
        case .pulse:
            return .easeInOut(duration: MotionTokens.pulseDuration)
        case .ringTick:
            return .linear(duration: MotionTokens.ringTickRedraw)
        case .icon, .label:
            return .quickEaseOut
        }
    }
}
