import Foundation
import SwiftUI

/// Timing + curve tokens. Values locked at the animation checkpoint
/// (01-animation-vocabulary.md, Q-M1 resolution: "faster" — 150/280/3000 ms).
public enum MotionTokens {
    // Buckets (checkpoint 01 §1)
    public static let quick: TimeInterval = 0.150
    public static let present: TimeInterval = 0.280
    public static let dwell: TimeInterval = 3.0

    // Spring parameters for `present` (Q-M1 retuned to 0.28)
    public static let presentSpringResponse: Double = 0.28
    public static let presentSpringDamping: Double = 0.78

    // Reduce-Motion cross-fade (checkpoint 01 §4)
    public static let reducedMotionCrossFade: TimeInterval = 0.150

    // Specific derived tokens
    public static let pulseDuration: TimeInterval = quick * 2     // 0.300
    public static let ringTickRedraw: TimeInterval = 0.100
    public static let ringTickReduceMotion: TimeInterval = 0.0    // label-only

    // Breathing pulse for caffeine-indefinite (Q-M2 "breathe")
    public static let breathingPulsePeriod: TimeInterval = 3.0
    public static let breathingPulseAmplitude: Double = 0.08      // low-amplitude
}

public extension Animation {
    /// SwiftUI animation for the `present` bucket.
    static var presentSpring: Animation {
        .spring(
            response: MotionTokens.presentSpringResponse,
            dampingFraction: MotionTokens.presentSpringDamping
        )
    }

    /// SwiftUI animation for the `quick` bucket.
    static var quickEaseOut: Animation {
        .easeOut(duration: MotionTokens.quick)
    }

    /// Reduce-Motion cross-fade — used when `accessibilityReduceMotion == true`.
    static var reducedMotionCrossFade: Animation {
        .easeInOut(duration: MotionTokens.reducedMotionCrossFade)
    }
}
