import XCTest
@testable import AnimationKit

/// T017 — Animation vocabulary contract skeleton (V-1 greps are in a Polish task).
final class AnimationVocabularyTests: XCTestCase {
    func testTimingBucketsMatchCheckpoint01() {
        // Q-M1 resolution: faster buckets — 150/280/3000 ms.
        XCTAssertEqual(MotionTokens.quick, 0.150, accuracy: 0.0001)
        XCTAssertEqual(MotionTokens.present, 0.280, accuracy: 0.0001)
        XCTAssertEqual(MotionTokens.dwell, 3.0, accuracy: 0.0001)
        XCTAssertEqual(MotionTokens.presentSpringResponse, 0.28, accuracy: 0.0001)
    }

    func testEveryPrimitiveHasName() {
        let primitives: [MotionPrimitive] = [
            .pillExpand, .pillCollapse, .pillSplit, .pillRejoin,
            .pulse, .ringTick, .sweep(.leading), .icon(.warning), .label(.center),
        ]
        for p in primitives {
            XCTAssertFalse(p.name.isEmpty)
        }
    }

    func testAnimationSequenceComposes() {
        let seq = AnimationSequence()
            .then(.pillExpand)
            .then(.pulse, delay: 0.1)
            .then(.pillCollapse, delay: 3.0)
        XCTAssertEqual(seq.steps.count, 3)
        XCTAssertEqual(seq.totalDuration, 3.1, accuracy: 0.001)
    }
}
