import Foundation

/// Declarative composition of motion primitives (V-5). A sequence is a list
/// of steps with optional delays; it is introspectable at test time so the
/// motion-table entries in checkpoint 01 can be validated against real code.
public struct AnimationSequence: Sendable, Equatable {
    public struct Step: Sendable, Equatable {
        public let primitive: MotionPrimitive
        public let delay: TimeInterval
    }

    public private(set) var steps: [Step]

    public init(steps: [Step] = []) {
        self.steps = steps
    }

    public func then(_ primitive: MotionPrimitive, delay: TimeInterval = 0) -> AnimationSequence {
        var next = self
        next.steps.append(Step(primitive: primitive, delay: delay))
        return next
    }

    public var totalDuration: TimeInterval {
        steps.reduce(0) { $0 + $1.delay }
    }
}
