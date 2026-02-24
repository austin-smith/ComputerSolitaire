import XCTest
@testable import Computer_Solitaire

@MainActor
final class MoveEvaluationRankingTests: XCTestCase {
    func testRankingPrefersRevealBeforeOtherSignals() {
        let reveal = evaluation(destination: .tableau(0), revealsFaceDownCard: true)
        let noReveal = evaluation(
            destination: .foundation(0),
            revealsFaceDownCard: false,
            foundationProgressDelta: 1,
            mobilityDelta: 10
        )

        XCTAssertTrue(MoveEvaluationRanking.isBetter(reveal, than: noReveal))
        XCTAssertFalse(MoveEvaluationRanking.isBetter(noReveal, than: reveal))
    }

    func testRankingThenPrefersFoundationProgressAndMobility() {
        let betterFoundation = evaluation(destination: .foundation(0), foundationProgressDelta: 2)
        let weakerFoundation = evaluation(destination: .foundation(1), foundationProgressDelta: 1)
        XCTAssertTrue(MoveEvaluationRanking.isBetter(betterFoundation, than: weakerFoundation))

        let betterMobility = evaluation(destination: .tableau(0), mobilityDelta: 2)
        let weakerMobility = evaluation(destination: .tableau(1), mobilityDelta: 1)
        XCTAssertTrue(MoveEvaluationRanking.isBetter(betterMobility, than: weakerMobility))
    }

    func testRankingFallsBackToDeterministicDestinationOrder() {
        let foundation0 = evaluation(destination: .foundation(0))
        let foundation1 = evaluation(destination: .foundation(1))
        let tableau0 = evaluation(destination: .tableau(0))

        XCTAssertTrue(MoveEvaluationRanking.isBetter(foundation0, than: foundation1))
        XCTAssertTrue(MoveEvaluationRanking.isBetter(foundation1, than: tableau0))
        XCTAssertFalse(MoveEvaluationRanking.isBetter(tableau0, than: foundation0))
    }

    private func evaluation(
        destination: Destination,
        revealsFaceDownCard: Bool = false,
        clearsSourcePile: Bool = false,
        emptyTableauDelta: Int = 0,
        foundationProgressDelta: Int = 0,
        mobilityDelta: Int = 0,
        resultingMobility: Int = 0,
        destinationPriority: Int = 0
    ) -> MoveEvaluation {
        MoveEvaluation(
            destination: destination,
            revealsFaceDownCard: revealsFaceDownCard,
            clearsSourcePile: clearsSourcePile,
            emptyTableauDelta: emptyTableauDelta,
            foundationProgressDelta: foundationProgressDelta,
            mobilityDelta: mobilityDelta,
            resultingMobility: resultingMobility,
            destinationPriority: destinationPriority
        )
    }
}
