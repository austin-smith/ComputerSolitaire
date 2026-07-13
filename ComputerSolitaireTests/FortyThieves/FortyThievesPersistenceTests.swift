import XCTest
@testable import Computer_Solitaire

@MainActor
final class FortyThievesPersistenceTests: XCTestCase {
    private func payload(
        for state: GameState,
        score: Int = 0,
        stockDrawCount: Int = DrawMode.one.rawValue
    ) -> SavedGamePayload {
        SavedGamePayload(
            state: state,
            movesCount: 0,
            score: score,
            stockDrawCount: stockDrawCount,
            history: []
        )
    }

    /// A mid-game shape: two stock cards flipped, the first played onto a
    /// column, and one of the deal's aces banked onto a foundation — pulled
    /// from wherever the deal put it so the 104-card census stays intact.
    private func midGameState() -> GameState {
        var state = GameStateFixtures.seededFortyThievesDeal(seed: 2)
        for _ in 0..<2 {
            var drawn = state.stock.removeLast()
            drawn.isFaceUp = true
            state.waste.append(drawn)
        }
        let played = state.waste.removeFirst()
        state.tableau[0].append(played)
        if let stockIndex = state.stock.lastIndex(where: { $0.rank == .ace }) {
            var ace = state.stock.remove(at: stockIndex)
            ace.isFaceUp = true
            state.foundations[0] = [ace]
        } else if let pileIndex = state.tableau.firstIndex(where: { $0.last?.rank == .ace }),
                  let ace = state.tableau[pileIndex].popLast() {
            state.foundations[0] = [ace]
        }
        state.wasteDrawCount = 1
        return state
    }

    func testFreshDealRoundTripsThroughSanitization() throws {
        let state = GameState.newFortyThievesGame()
        let sanitized = payload(for: state).sanitizedForRestore(at: DateFixtures.reference)

        let restored = try XCTUnwrap(sanitized)
        XCTAssertEqual(restored.state, state)
        XCTAssertEqual(restored.stockDrawCount, DrawMode.one.rawValue)
        XCTAssertEqual(restored.scoringDrawCount, DrawMode.three.rawValue)
    }

    func testMidGameStateSurvivesEncodeDecode() throws {
        let state = midGameState()

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(GameState.self, from: data)
        XCTAssertEqual(decoded, state)

        let sanitized = payload(for: state).sanitizedForRestore(at: DateFixtures.reference)
        XCTAssertEqual(try XCTUnwrap(sanitized).state, state)
    }

    func testSanitizationForcesFortyThievesDrawCounts() throws {
        let state = GameState.newFortyThievesGame()
        let sanitized = payload(for: state, stockDrawCount: DrawMode.three.rawValue)
            .sanitizedForRestore(at: DateFixtures.reference)

        let restored = try XCTUnwrap(sanitized)
        XCTAssertEqual(
            restored.stockDrawCount,
            DrawMode.one.rawValue,
            "Forty Thieves always draws a single card"
        )
        XCTAssertEqual(restored.scoringDrawCount, DrawMode.three.rawValue)
    }

    func testSanitizationRejectsCorruptFortyThievesStates() {
        func assertRejected(
            _ message: String,
            mutate: (inout GameState) -> Void
        ) {
            var state = midGameState()
            mutate(&state)
            XCTAssertNil(
                payload(for: state).sanitizedForRestore(at: DateFixtures.reference),
                message
            )
        }

        assertRejected("Wrong column count") { state in
            state.tableau.removeLast()
        }
        assertRejected("Wrong foundation count") { state in
            state.foundations.removeLast()
        }
        assertRejected("A face-down board card breaks the all-face-up invariant") { state in
            state.tableau[1][0].isFaceUp = false
        }
        assertRejected("A face-up stock card breaks the stock invariant") { state in
            state.stock[0].isFaceUp = true
        }
        assertRejected("A stock beyond 64 cards exceeds the deal") { state in
            var card = state.tableau[0].removeLast()
            card.isFaceUp = false
            state.stock.append(card)
            while state.stock.count <= FortyThievesGameRules.dealStockCardCount {
                var filler = state.tableau[1].removeLast()
                filler.isFaceUp = false
                state.stock.append(filler)
            }
        }
        assertRejected("A missing card breaks deck composition") { state in
            state.tableau[2].removeLast()
        }
        assertRejected("A third copy of one identity breaks deck composition") { state in
            let copied = state.tableau[6][0]
            state.tableau[7][0] = TestCards.make(copied.suit, copied.rank)
        }
        assertRejected("Cards stranded in the pyramid field are invisible") { state in
            state.pyramid = [state.waste.removeLast()]
            state.wasteDrawCount = 0
        }
        assertRejected("Cards stranded in the triPeaks field are invisible") { state in
            state.triPeaks = [state.waste.removeLast()]
            state.wasteDrawCount = 0
        }
        assertRejected("Cards stranded in the discard are invisible") { state in
            state.discard = [state.waste.removeLast()]
            state.wasteDrawCount = 0
        }
        assertRejected("Cards stranded in a free cell are invisible") { state in
            state.freeCells[0] = state.waste.removeLast()
            state.wasteDrawCount = 0
        }
        assertRejected("Forty Thieves never recycles the waste") { state in
            state.wasteRecyclesUsed = 1
        }
        assertRejected("A fanned card the waste does not hold") { state in
            state.tableau[0].append(contentsOf: state.waste)
            state.waste = []
            state.wasteDrawCount = 1
        }
    }

    func testLayoutRuleRejectsCorruptFoundationPiles() {
        // Census-independent checks against the layout rule directly: a
        // foundation grows one suit from the Ace up, or it is corrupt.
        let nonAceBase = GameStateFixtures.fortyThievesState(
            columns: [],
            foundations: [[TestCards.make(.spades, .two)]]
        )
        XCTAssertFalse(FortyThievesPersistenceRules.hasValidLayout(state: nonAceBase))

        let offSuitRun = GameStateFixtures.fortyThievesState(
            columns: [],
            foundations: [[TestCards.make(.spades, .ace), TestCards.make(.hearts, .two)]]
        )
        XCTAssertFalse(FortyThievesPersistenceRules.hasValidLayout(state: offSuitRun))

        let skippedRank = GameStateFixtures.fortyThievesState(
            columns: [],
            foundations: [[TestCards.make(.spades, .ace), TestCards.make(.spades, .three)]]
        )
        XCTAssertFalse(FortyThievesPersistenceRules.hasValidLayout(state: skippedRank))

        let validRun = GameStateFixtures.fortyThievesState(
            columns: [],
            foundations: [[TestCards.make(.spades, .ace), TestCards.make(.spades, .two)]]
        )
        XCTAssertTrue(FortyThievesPersistenceRules.hasValidLayout(state: validRun))
    }

    func testLayoutRuleRejectsWrongWasteDrawCount() {
        // The waste always fans exactly one card while it holds any; both a
        // hidden waste top and a Klondike-style multi-card fan are corrupt.
        var state = midGameState()
        state.wasteDrawCount = 0
        XCTAssertFalse(FortyThievesPersistenceRules.hasValidLayout(state: state))

        state = midGameState()
        state.wasteDrawCount = 2
        XCTAssertFalse(FortyThievesPersistenceRules.hasValidLayout(state: state))
    }

    func testViewModelRestoresFortyThievesPayload() throws {
        let state = midGameState()
        let viewModel = SolitaireViewModel()
        XCTAssertTrue(viewModel.restore(from: payload(for: state)))
        XCTAssertEqual(viewModel.gameVariant, .fortyThieves)
        XCTAssertEqual(viewModel.gameMode, .fortyThieves)
        XCTAssertEqual(viewModel.state, state)
        XCTAssertEqual(viewModel.stockDrawCount, DrawMode.one.rawValue)
    }
}
