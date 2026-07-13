import XCTest
@testable import Computer_Solitaire

@MainActor
final class ScoringTests: XCTestCase {
    func testScoringDeltaValuesMatchRules() {
        XCTAssertEqual(Scoring.delta(for: .wasteToTableau), 5)
        XCTAssertEqual(Scoring.delta(for: .wasteToFoundation), 10)
        XCTAssertEqual(Scoring.delta(for: .tableauToFoundation), 10)
        XCTAssertEqual(Scoring.delta(for: .turnOverTableauCard), 5)
        XCTAssertEqual(Scoring.delta(for: .foundationToTableau), -15)
        XCTAssertEqual(Scoring.delta(for: .recycleWasteInDrawOne), -100)
    }

    func testGolfScoringDeltaValuesMatchRules() {
        XCTAssertEqual(Scoring.delta(for: .golfBoardPlay), -1)
        XCTAssertEqual(Scoring.delta(for: .golfBoardClear(remainingStockCount: 5)), -5)
        XCTAssertEqual(Scoring.delta(for: .golfBoardClear(remainingStockCount: 0)), 0)
        XCTAssertEqual(Scoring.delta(for: .golfBoardClear(remainingStockCount: -3)), 0)
    }

    func testApplyingScoreClampsAtMinimumZero() {
        XCTAssertEqual(Scoring.applying(.foundationToTableau, to: 10, variant: .klondike), 0)
        XCTAssertEqual(Scoring.applying(.recycleWasteInDrawOne, to: 99, variant: .klondike), 0)
        XCTAssertEqual(Scoring.applying(.wasteToFoundation, to: 0, variant: .klondike), 10)
    }

    func testClampIsVariantAware() {
        // Golf's stroke score legitimately goes negative on a cleared board;
        // every other variant floors at zero.
        XCTAssertEqual(Scoring.clamped(-3, for: .golf), -3)
        XCTAssertEqual(Scoring.clamped(-3, for: .klondike), 0)
        XCTAssertEqual(Scoring.applying(.golfBoardClear(remainingStockCount: 4), to: 0, variant: .golf), -4)
    }

    func testTimeBonusUsesConfiguredLossRate() {
        XCTAssertEqual(
            Scoring.timeBonus(elapsedSeconds: 10, maxBonus: 100, pointsLostPerSecond: 2),
            80
        )
    }

    func testTimeBonusHandlesBoundaryInputs() {
        XCTAssertEqual(Scoring.timeBonus(elapsedSeconds: -1, maxBonus: 100), 100)
        XCTAssertEqual(Scoring.timeBonus(elapsedSeconds: 0, maxBonus: 100), 100)
        XCTAssertEqual(Scoring.timeBonus(elapsedSeconds: 1_000, maxBonus: 100), 0)
        XCTAssertEqual(Scoring.timeBonus(elapsedSeconds: 100, maxBonus: -5), 0)
        XCTAssertEqual(Scoring.timeBonus(elapsedSeconds: 100, maxBonus: 40, pointsLostPerSecond: 0), 40)
    }

    func testTimedMaxBonusUsesDrawMode() {
        XCTAssertEqual(Scoring.timedMaxBonus(for: DrawMode.one.rawValue), Scoring.timedMaxBonusDrawOne)
        XCTAssertEqual(Scoring.timedMaxBonus(for: DrawMode.three.rawValue), Scoring.timedMaxBonusDrawThree)
        XCTAssertEqual(Scoring.timedMaxBonus(for: 999), Scoring.timedMaxBonusDrawThree)
    }
}
