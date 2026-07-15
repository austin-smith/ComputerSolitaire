import XCTest
@testable import Computer_Solitaire

/// Pins `GameRules.canSelectTableauCards(_:within:variant:)` — the pure,
/// pile-scoped check the board views render from — to the session's
/// `canSelectTableauCards(_:)` for every suffix of every pile. The pure form
/// exists so views never read the observable session while rendering; these
/// tests are the proof the two can never drift.
@MainActor
final class TableauPickupParityTests: XCTestCase {
    func testEverySuffixOfEverySeededDealMatchesTheSessionRule() {
        for variant in GameVariant.allCases {
            for seed in UInt64(1)...4 {
                var generator = SeededRandomNumberGenerator(seed: seed)
                let session = SolitaireViewModel(variant: variant)
                var state = session.state
                state.tableau = state.tableau.map { $0.shuffled(using: &generator) }
                session.state = state
                assertSuffixParity(for: session)
            }
        }
    }

    func testCanfieldWholePileAndPartialRunParity() {
        // A packed two-card pile: the whole pile may move, a suffix may not.
        let pile = [
            TestCards.make(.spades, .nine),
            TestCards.make(.hearts, .eight),
        ]
        let session = makeSession(variant: .canfield, tableau: [pile, [], [], []])
        assertSuffixParity(for: session)
        XCTAssertTrue(
            GameRules.canSelectTableauCards(pile, within: pile, variant: .canfield)
        )
        // A packed suffix that is not the entire pile must not move.
        let deeperPile = [TestCards.make(.diamonds, .ten)] + pile
        let deeperSession = makeSession(variant: .canfield, tableau: [deeperPile, [], [], []])
        assertSuffixParity(for: deeperSession)
        XCTAssertFalse(
            GameRules.canSelectTableauCards(pile, within: deeperPile, variant: .canfield)
        )
    }

    func testFreeCellRunAndBrokenRunParity() {
        let run = [
            TestCards.make(.spades, .nine),
            TestCards.make(.hearts, .eight),
            TestCards.make(.clubs, .seven),
        ]
        let broken = [
            TestCards.make(.spades, .nine),
            TestCards.make(.clubs, .eight),
        ]
        let session = makeSession(variant: .freecell, tableau: [run, broken, [], [], [], [], [], []])
        assertSuffixParity(for: session)
    }

    func testSpiderSameSuitRunParity() {
        let sameSuit = [
            TestCards.make(.spades, .five),
            TestCards.make(.spades, .four),
        ]
        let mixedSuit = [
            TestCards.make(.spades, .five),
            TestCards.make(.hearts, .four),
        ]
        let session = makeSession(
            variant: .spider,
            tableau: [sameSuit, mixedSuit] + Array(repeating: [Card](), count: 8)
        )
        assertSuffixParity(for: session)
    }

    private func assertSuffixParity(
        for session: SolitaireViewModel,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let state = session.state
        for pile in state.tableau where !pile.isEmpty {
            for startIndex in pile.indices {
                let suffix = Array(pile[startIndex...])
                XCTAssertEqual(
                    GameRules.canSelectTableauCards(suffix, within: pile, variant: state.variant),
                    session.canSelectTableauCards(suffix),
                    "variant \(state.variant), pile of \(pile.count), suffix from \(startIndex)",
                    file: file,
                    line: line
                )
            }
        }
    }

    private func makeSession(variant: GameVariant, tableau: [[Card]]) -> SolitaireViewModel {
        let session = SolitaireViewModel(variant: variant)
        var state = session.state
        state.tableau = tableau
        session.state = state
        return session
    }
}
