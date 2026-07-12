import Foundation
import XCTest
@testable import Computer_Solitaire

/// Validates the screenshot fixtures shipped in the app bundle (see `ScreenshotFixtures`).
@MainActor
final class ScreenshotFixtureBundleTests: XCTestCase {
    func testBundledFixturesDecodeAndRestore() throws {
        let bundle = Bundle(for: SolitaireViewModel.self)
        for board in ScreenshotFixtures.bundled {
            let name = board.name
            let payload = try XCTUnwrap(
                ScreenshotFixtures.payload(named: name, in: bundle),
                "\(name).json is missing from the app bundle or failed to decode"
            )
            XCTAssertFalse(
                payload.hasStartedTrackedGame,
                "\(name): fixtures must not contribute to statistics"
            )
            XCTAssertNotNil(
                payload.sanitizedForRestore(),
                "\(name): fixture failed the persistence validity gate"
            )
            let viewModel = SolitaireViewModel()
            XCTAssertTrue(viewModel.restore(from: payload), "\(name): restore failed")
            XCTAssertFalse(viewModel.isWin, "\(name): a screenshot fixture should be mid-game")
        }
    }
}

/// Generates the staged `SavedGamePayload` JSON behind the `-screenshotFixture`
/// launch argument. Skipped in normal runs; to regenerate:
///
///   TEST_RUNNER_GENERATE_SCREENSHOT_FIXTURES=1 xcodebuild test \
///     -project ComputerSolitaire.xcodeproj -scheme ComputerSolitaire \
///     -destination 'platform=macOS' \
///     -only-testing:ComputerSolitaireTests/ScreenshotFixtureGeneratorTests
///
/// then copy the file printed after `SCREENSHOT-FIXTURE-OUTPUT:` into
/// `ComputerSolitaire/Fixtures/` and add an entry to
/// `ScreenshotFixtures.bundled`.
@MainActor
final class ScreenshotFixtureGeneratorTests: XCTestCase {
    private static let candidateSeeds: ClosedRange<UInt64> = 1...500
    /// Elapsed time the HUD timer shows when the fixture loads: a freshly
    /// dealt board a few seconds in.
    private static let stagedElapsedSeconds: TimeInterval = 3

    /// The staged board is a clean new deal with the first three-card draw
    /// fanned in the waste. Seeds are scanned for the most photogenic spread
    /// of visible cards; the winner is then played through the real view model
    /// so the HUD numbers are authentic.
    func testGenerateKlondikeDrawThreeFixture() throws {
        try skipUnlessGenerating()

        var bestSeed: UInt64?
        var bestScore = Int.min
        for seed in Self.candidateSeeds {
            let deal = GameStateFixtures.seededKlondikeDeal(seed: seed)
            let score = freshDealScore(of: deal)
            if score > bestScore {
                bestScore = score
                bestSeed = seed
            }
        }
        let seed = try XCTUnwrap(bestSeed)

        let viewModel = SolitaireViewModel()
        viewModel.state = GameStateFixtures.seededKlondikeDeal(seed: seed)
        viewModel.configureKlondikeNewGame(drawMode: .three)
        viewModel.handleStockTap()
        let winner = Candidate(
            seed: seed,
            state: viewModel.state,
            movesCount: viewModel.movesCount,
            gameScore: viewModel.score,
            photogenicScore: bestScore
        )

        let savedAt = DateFixtures.reference
        let payload = SavedGamePayload(
            savedAt: savedAt,
            state: winner.state,
            movesCount: winner.movesCount,
            score: winner.gameScore,
            gameStartedAt: savedAt.addingTimeInterval(-Self.stagedElapsedSeconds),
            stockDrawCount: DrawMode.three.rawValue,
            history: [],
            hasStartedTrackedGame: false
        )

        XCTAssertNotNil(payload.sanitizedForRestore(), "Generated fixture failed the validity gate")
        let restoredViewModel = SolitaireViewModel()
        XCTAssertTrue(restoredViewModel.restore(from: payload), "Generated fixture failed to restore")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("klondike-draw3.json")
        try data.write(to: outputURL)

        print("SCREENSHOT-FIXTURE-OUTPUT: \(outputURL.path)")
        print(summary(of: winner))
    }

    /// The staged FreeCell board is a fresh deal — every card face up, free
    /// cells and foundations empty. Seeds are scanned for the most photogenic
    /// spread across the cascade tails (the cards the eye lands on).
    func testGenerateFreeCellFixture() throws {
        try skipUnlessGenerating()

        var bestSeed: UInt64?
        var bestScore = Int.min
        for seed in Self.candidateSeeds {
            let deal = GameStateFixtures.seededFreeCellDeal(seed: seed)
            let score = freeCellDealScore(of: deal)
            if score > bestScore {
                bestScore = score
                bestSeed = seed
            }
        }
        let seed = try XCTUnwrap(bestSeed)

        let viewModel = SolitaireViewModel()
        viewModel.state = GameStateFixtures.seededFreeCellDeal(seed: seed)
        viewModel.configureWastelessNewGame()

        let savedAt = DateFixtures.reference
        let payload = SavedGamePayload(
            savedAt: savedAt,
            state: viewModel.state,
            movesCount: viewModel.movesCount,
            score: viewModel.score,
            gameStartedAt: savedAt.addingTimeInterval(-Self.stagedElapsedSeconds),
            stockDrawCount: DrawMode.three.rawValue,
            history: [],
            hasStartedTrackedGame: false
        )

        XCTAssertNotNil(payload.sanitizedForRestore(), "Generated fixture failed the validity gate")
        let restoredViewModel = SolitaireViewModel()
        XCTAssertTrue(restoredViewModel.restore(from: payload), "Generated fixture failed to restore")
        XCTAssertEqual(restoredViewModel.gameVariant, .freecell, "Fixture did not restore as FreeCell")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("freecell.json")
        try data.write(to: outputURL)

        print("SCREENSHOT-FIXTURE-OUTPUT: \(outputURL.path)")
        print("FreeCell fixture — seed \(seed), photogenic \(bestScore)")
    }

    /// The staged Yukon board is a fresh deal — face-down ramps under five-card
    /// face-up fans. Seeds are scanned for the most photogenic spread across the
    /// fan tails (the cards the eye lands on).
    func testGenerateYukonFixture() throws {
        try skipUnlessGenerating()

        var bestSeed: UInt64?
        var bestScore = Int.min
        for seed in Self.candidateSeeds {
            let deal = GameStateFixtures.seededYukonDeal(seed: seed)
            let score = yukonDealScore(of: deal)
            if score > bestScore {
                bestScore = score
                bestSeed = seed
            }
        }
        let seed = try XCTUnwrap(bestSeed)

        let viewModel = SolitaireViewModel()
        viewModel.state = GameStateFixtures.seededYukonDeal(seed: seed)
        viewModel.configureWastelessNewGame()

        let savedAt = DateFixtures.reference
        let payload = SavedGamePayload(
            savedAt: savedAt,
            state: viewModel.state,
            movesCount: viewModel.movesCount,
            score: viewModel.score,
            gameStartedAt: savedAt.addingTimeInterval(-Self.stagedElapsedSeconds),
            stockDrawCount: DrawMode.three.rawValue,
            history: [],
            hasStartedTrackedGame: false
        )

        XCTAssertNotNil(payload.sanitizedForRestore(), "Generated fixture failed the validity gate")
        let restoredViewModel = SolitaireViewModel()
        XCTAssertTrue(restoredViewModel.restore(from: payload), "Generated fixture failed to restore")
        XCTAssertEqual(restoredViewModel.gameVariant, .yukon, "Fixture did not restore as Yukon")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("yukon.json")
        try data.write(to: outputURL)

        print("SCREENSHOT-FIXTURE-OUTPUT: \(outputURL.path)")
        print("Yukon fixture — seed \(seed), photogenic \(bestScore)")
    }

    /// The staged Spider board is a fresh 2-suit deal — ten piles with a single
    /// face-up top each and a full stock. Seeds are scanned for the most
    /// photogenic spread across the ten tops (the cards the eye lands on).
    func testGenerateSpiderFixture() throws {
        try skipUnlessGenerating()

        var bestSeed: UInt64?
        var bestScore = Int.min
        for seed in Self.candidateSeeds {
            let deal = GameStateFixtures.seededSpiderDeal(seed: seed, suitCount: .two)
            let score = spiderDealScore(of: deal)
            if score > bestScore {
                bestScore = score
                bestSeed = seed
            }
        }
        let seed = try XCTUnwrap(bestSeed)

        let viewModel = SolitaireViewModel()
        viewModel.state = GameStateFixtures.seededSpiderDeal(seed: seed, suitCount: .two)
        viewModel.configureSpiderNewGame()

        let savedAt = DateFixtures.reference
        let payload = SavedGamePayload(
            savedAt: savedAt,
            state: viewModel.state,
            movesCount: viewModel.movesCount,
            score: viewModel.score,
            gameStartedAt: savedAt.addingTimeInterval(-Self.stagedElapsedSeconds),
            stockDrawCount: DrawMode.three.rawValue,
            history: [],
            hasStartedTrackedGame: false
        )

        XCTAssertNotNil(payload.sanitizedForRestore(), "Generated fixture failed the validity gate")
        let restoredViewModel = SolitaireViewModel()
        XCTAssertTrue(restoredViewModel.restore(from: payload), "Generated fixture failed to restore")
        XCTAssertEqual(restoredViewModel.gameVariant, .spider, "Fixture did not restore as Spider")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("spider.json")
        try data.write(to: outputURL)

        print("SCREENSHOT-FIXTURE-OUTPUT: \(outputURL.path)")
        print("Spider fixture — seed \(seed), photogenic \(bestScore)")
    }

    // MARK: - Photogenic scoring

    private struct Candidate {
        let seed: UInt64
        let state: GameState
        let movesCount: Int
        let gameScore: Int
        let photogenicScore: Int
    }

    /// Scores a fresh FreeCell deal by the sixteen cards on the cascade tails
    /// (the last two rows): rank variety, red/black balance, all four suits,
    /// a few face cards, and an ace on a tail read well.
    private func freeCellDealScore(of deal: GameState) -> Int {
        let visible = deal.tableau.flatMap { $0.suffix(2) }
        var score = 0
        score += Set(visible.map(\.rank)).count * 6
        let redCount = visible.count(where: { $0.suit.isRed })
        score -= abs(redCount * 2 - visible.count) * 4
        score += Set(visible.map(\.suit)).count == Suit.allCases.count ? 8 : 0
        score += visible.count(where: { $0.rank >= .jack }) >= 3 ? 6 : 0
        score += deal.tableau.compactMap { $0.last }.contains(where: { $0.rank == .ace }) ? 6 : 0
        return score
    }

    /// Scores a fresh Yukon deal by the cards on the fan tails (the last two
    /// face-up cards of each pile): rank variety, red/black balance, all four
    /// suits, a few face cards, and an ace on a tail read well.
    private func yukonDealScore(of deal: GameState) -> Int {
        let visible = deal.tableau.flatMap { $0.suffix(2).filter(\.isFaceUp) }
        var score = 0
        score += Set(visible.map(\.rank)).count * 6
        let redCount = visible.count(where: { $0.suit.isRed })
        score -= abs(redCount * 2 - visible.count) * 4
        score += Set(visible.map(\.suit)).count == Suit.allCases.count ? 8 : 0
        score += visible.count(where: { $0.rank >= .jack }) >= 3 ? 6 : 0
        score += deal.tableau.compactMap { $0.last }.contains(where: { $0.rank == .ace }) ? 6 : 0
        return score
    }

    /// Scores a fresh Spider deal by its ten face-up tops: rank variety,
    /// red/black balance, both composed suits, a few face cards, and an ace
    /// on a top read well.
    private func spiderDealScore(of deal: GameState) -> Int {
        let visible = deal.tableau.compactMap { $0.last }
        var score = 0
        score += Set(visible.map(\.rank)).count * 6
        let redCount = visible.count(where: { $0.suit.isRed })
        score -= abs(redCount * 2 - visible.count) * 4
        score += Set(visible.map(\.suit)).count == 2 ? 8 : 0
        score += visible.count(where: { $0.rank >= .jack }) >= 3 ? 6 : 0
        score += visible.contains(where: { $0.rank == .ace }) ? 6 : 0
        return score
    }

    /// Scores a fresh deal by the ten cards a first draw makes visible: the
    /// seven tableau tops plus the three stock cards that land in the waste.
    /// Rank variety, red/black balance, all four suits, and a couple of face
    /// cards make the spread read well.
    private func freshDealScore(of deal: GameState) -> Int {
        let tableauTops = deal.tableau.compactMap { $0.last }
        let drawnCards = Array(deal.stock.suffix(DrawMode.three.rawValue))
        let visible = tableauTops + drawnCards

        var score = 0
        score += Set(visible.map(\.rank)).count * 6
        let redCount = visible.count(where: { $0.suit.isRed })
        score -= abs(redCount * 2 - visible.count) * 4
        score += Set(visible.map(\.suit)).count == Suit.allCases.count ? 8 : 0
        score += visible.count(where: { $0.rank >= .jack }) >= 2 ? 6 : 0
        score += visible.contains(where: { $0.rank == .ace }) ? 4 : 0
        return score
    }

    // MARK: - Reporting

    private func summary(of candidate: Candidate) -> String {
        func label(_ card: Card) -> String {
            let suits: [Suit: String] = [.spades: "♠", .hearts: "♥", .diamonds: "♦", .clubs: "♣"]
            return card.isFaceUp ? "\(card.rank.label)\(suits[card.suit] ?? "?")" : "··"
        }
        var lines = [
            "Fixture candidate — seed \(candidate.seed), " +
            "moves \(candidate.movesCount), score \(candidate.gameScore), " +
            "photogenic \(candidate.photogenicScore)"
        ]
        let foundations = candidate.state.foundations
            .map { $0.last.map(label) ?? "—" }
            .joined(separator: "  ")
        lines.append("Foundations: \(foundations)")
        let visibleWaste = candidate.state.waste
            .suffix(candidate.state.wasteDrawCount)
            .map(label)
            .joined(separator: " ")
        lines.append("Stock: \(candidate.state.stock.count) cards, waste fan: \(visibleWaste)")
        for (index, pile) in candidate.state.tableau.enumerated() {
            lines.append("Pile \(index + 1): \(pile.map(label).joined(separator: " "))")
        }
        return lines.joined(separator: "\n")
    }

    private func skipUnlessGenerating() throws {
        // The documented command sets TEST_RUNNER_GENERATE_SCREENSHOT_FIXTURES;
        // xcodebuild strips the TEST_RUNNER_ prefix when passing environment
        // variables into the test process, so the name checked here is correct.
        guard ProcessInfo.processInfo.environment["GENERATE_SCREENSHOT_FIXTURES"] == "1" else {
            throw XCTSkip(
                "Fixture generator; set TEST_RUNNER_GENERATE_SCREENSHOT_FIXTURES=1 to regenerate."
            )
        }
    }
}
