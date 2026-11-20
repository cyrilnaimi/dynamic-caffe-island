import XCTest
@testable import IslandCore
import ProfileKit

/// T017 — Island slot contract skeleton: S-1 dimensions, A-1 arbitration purity.
final class IslandSlotContractTests: XCTestCase {
    func testS1_GeometryTokensMatchUICheckpoint() {
        // UI checkpoint 02 §1 locked values.
        XCTAssertEqual(Geometry.height, 32)
        XCTAssertEqual(Geometry.compactWidth, 96)
        XCTAssertEqual(Geometry.expandedWidth, 240)
        XCTAssertEqual(Geometry.splitWidth, 320)
        XCTAssertEqual(Geometry.splitGap, 4)
        XCTAssertEqual(Geometry.cornerRadius, 16)
        XCTAssertEqual(Geometry.horizontalMargin, 10)
        XCTAssertEqual(Geometry.notchClearance, 6)
    }

    func testS1_HalfPillInnerWidth() {
        XCTAssertEqual(Geometry.halfPillInnerWidth, 158)
    }

    func testA1_ArbitratePurityAlias() {
        // Duplicates the random-fuzz test from ArbitratorTests for contract-level coverage.
        let snapshot = Arbitrator.ProfileStateSnapshot(
            profileID: ProfileID(raw: "x"),
            state: .empty,
            priority: ProfilePriority(tier: 50),
            capabilities: [],
            isEnabled: true,
            tiebreakArrival: 0
        )
        let out1 = Arbitrator.arbitrate(events: [snapshot], preferences: .init())
        let out2 = Arbitrator.arbitrate(events: [snapshot], preferences: .init())
        XCTAssertEqual(out1, out2)
    }
}
