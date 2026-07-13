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

    /// The staged Pyramid board is a fresh deal with the first card drawn to the
    /// waste. All 28 pyramid cards are visible, but the eye lands on the bottom
    /// two rows, so seeds are scanned for the most photogenic spread there.
    func testGeneratePyramidFixture() throws {
        try skipUnlessGenerating()

        var bestSeed: UInt64?
        var bestScore = Int.min
        for seed in Self.candidateSeeds {
            let deal = GameStateFixtures.seededPyramidDeal(seed: seed)
            let score = pyramidDealScore(of: deal)
            if score > bestScore {
                bestScore = score
                bestSeed = seed
            }
        }
        let seed = try XCTUnwrap(bestSeed)

        let viewModel = SolitaireViewModel()
        viewModel.state = GameStateFixtures.seededPyramidDeal(seed: seed)
        viewModel.configurePyramidNewGame()
        viewModel.handleStockTap()

        let savedAt = DateFixtures.reference
        let payload = SavedGamePayload(
            savedAt: savedAt,
            state: viewModel.state,
            movesCount: viewModel.movesCount,
            score: viewModel.score,
            gameStartedAt: savedAt.addingTimeInterval(-Self.stagedElapsedSeconds),
            stockDrawCount: DrawMode.one.rawValue,
            history: [],
            hasStartedTrackedGame: false
        )

        XCTAssertNotNil(payload.sanitizedForRestore(), "Generated fixture failed the validity gate")
        let restoredViewModel = SolitaireViewModel()
        XCTAssertTrue(restoredViewModel.restore(from: payload), "Generated fixture failed to restore")
        XCTAssertEqual(restoredViewModel.gameVariant, .pyramid, "Fixture did not restore as Pyramid")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pyramid.json")
        try data.write(to: outputURL)

        print("SCREENSHOT-FIXTURE-OUTPUT: \(outputURL.path)")
        print("Pyramid fixture — seed \(seed), photogenic \(bestScore)")
    }

    /// The staged TriPeaks board is a fresh deal — face-up base row, one waste
    /// starter. Seeds are scanned for the most photogenic base row with a first
    /// play available off the waste top.
    func testGenerateTriPeaksFixture() throws {
        try skipUnlessGenerating()

        var bestSeed: UInt64?
        var bestScore = Int.min
        for seed in Self.candidateSeeds {
            let deal = GameStateFixtures.seededTriPeaksDeal(seed: seed)
            let score = triPeaksDealScore(of: deal)
            if score > bestScore {
                bestScore = score
                bestSeed = seed
            }
        }
        let seed = try XCTUnwrap(bestSeed)

        let viewModel = SolitaireViewModel()
        viewModel.state = GameStateFixtures.seededTriPeaksDeal(seed: seed)
        viewModel.configureTriPeaksNewGame()

        let savedAt = DateFixtures.reference
        let payload = SavedGamePayload(
            savedAt: savedAt,
            state: viewModel.state,
            movesCount: viewModel.movesCount,
            score: viewModel.score,
            gameStartedAt: savedAt.addingTimeInterval(-Self.stagedElapsedSeconds),
            stockDrawCount: DrawMode.one.rawValue,
            history: [],
            hasStartedTrackedGame: false
        )

        XCTAssertNotNil(payload.sanitizedForRestore(), "Generated fixture failed the validity gate")
        let restoredViewModel = SolitaireViewModel()
        XCTAssertTrue(restoredViewModel.restore(from: payload), "Generated fixture failed to restore")
        XCTAssertEqual(restoredViewModel.gameVariant, .tripeaks, "Fixture did not restore as TriPeaks")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tripeaks.json")
        try data.write(to: outputURL)

        print("SCREENSHOT-FIXTURE-OUTPUT: \(outputURL.path)")
        print("TriPeaks fixture — seed \(seed), photogenic \(bestScore)")
    }

    /// The staged Golf board is a fresh deal — seven face-up columns, one
    /// waste starter. All 35 cards are visible, but the eye lands on the
    /// exposed column ends, so seeds are scanned for the most photogenic
    /// spread there with a first play available off the waste top.
    func testGenerateGolfFixture() throws {
        try skipUnlessGenerating()

        var bestSeed: UInt64?
        var bestScore = Int.min
        for seed in Self.candidateSeeds {
            let deal = GameStateFixtures.seededGolfDeal(seed: seed)
            let score = golfDealScore(of: deal)
            if score > bestScore {
                bestScore = score
                bestSeed = seed
            }
        }
        let seed = try XCTUnwrap(bestSeed)

        let viewModel = SolitaireViewModel()
        viewModel.state = GameStateFixtures.seededGolfDeal(seed: seed)
        viewModel.configureGolfNewGame()

        let savedAt = DateFixtures.reference
        let payload = SavedGamePayload(
            savedAt: savedAt,
            state: viewModel.state,
            movesCount: viewModel.movesCount,
            score: viewModel.score,
            gameStartedAt: savedAt.addingTimeInterval(-Self.stagedElapsedSeconds),
            stockDrawCount: DrawMode.one.rawValue,
            history: [],
            hasStartedTrackedGame: false,
            golfMatch: GolfMatchState()
        )

        XCTAssertNotNil(payload.sanitizedForRestore(), "Generated fixture failed the validity gate")
        let restoredViewModel = SolitaireViewModel()
        XCTAssertTrue(restoredViewModel.restore(from: payload), "Generated fixture failed to restore")
        XCTAssertEqual(restoredViewModel.gameVariant, .golf, "Fixture did not restore as Golf")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("golf.json")
        try data.write(to: outputURL)

        print("SCREENSHOT-FIXTURE-OUTPUT: \(outputURL.path)")
        print("Golf fixture — seed \(seed), photogenic \(bestScore)")
    }

    /// The staged Forty Thieves board is a fresh deal with the first card
    /// drawn to the waste. All forty board cards are visible, but the eye
    /// lands on the ten exposed column ends, so seeds are scanned for the
    /// most photogenic spread there with a first build available.
    func testGenerateFortyThievesFixture() throws {
        try skipUnlessGenerating()

        var bestSeed: UInt64?
        var bestScore = Int.min
        for seed in Self.candidateSeeds {
            let deal = GameStateFixtures.seededFortyThievesDeal(seed: seed)
            let score = fortyThievesDealScore(of: deal)
            if score > bestScore {
                bestScore = score
                bestSeed = seed
            }
        }
        let seed = try XCTUnwrap(bestSeed)

        let viewModel = SolitaireViewModel()
        viewModel.state = GameStateFixtures.seededFortyThievesDeal(seed: seed)
        viewModel.configureFortyThievesNewGame()
        viewModel.handleStockTap()

        let savedAt = DateFixtures.reference
        let payload = SavedGamePayload(
            savedAt: savedAt,
            state: viewModel.state,
            movesCount: viewModel.movesCount,
            score: viewModel.score,
            gameStartedAt: savedAt.addingTimeInterval(-Self.stagedElapsedSeconds),
            stockDrawCount: DrawMode.one.rawValue,
            history: [],
            hasStartedTrackedGame: false
        )

        XCTAssertNotNil(payload.sanitizedForRestore(), "Generated fixture failed the validity gate")
        let restoredViewModel = SolitaireViewModel()
        XCTAssertTrue(restoredViewModel.restore(from: payload), "Generated fixture failed to restore")
        XCTAssertEqual(
            restoredViewModel.gameVariant,
            .fortyThieves,
            "Fixture did not restore as Forty Thieves"
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("fortythieves.json")
        try data.write(to: outputURL)

        print("SCREENSHOT-FIXTURE-OUTPUT: \(outputURL.path)")
        print("Forty Thieves fixture — seed \(seed), photogenic \(bestScore)")
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

    /// Scores a fresh Pyramid deal by the bottom two pyramid rows (the fully and
    /// nearly exposed cards the eye lands on): rank variety, red/black balance,
    /// all four suits, a few face cards, and an exposed pair or King to suggest a
    /// first move.
    private func pyramidDealScore(of deal: GameState) -> Int {
        let visible = deal.pyramid.suffix(13).compactMap { $0 }
        let exposed = deal.pyramid.indices
            .filter { PyramidGeometry.isExposed($0, in: deal.pyramid) }
            .compactMap { deal.pyramid[$0] }
        var score = 0
        score += Set(visible.map(\.rank)).count * 6
        let redCount = visible.count(where: { $0.suit.isRed })
        score -= abs(redCount * 2 - visible.count) * 4
        score += Set(visible.map(\.suit)).count == Suit.allCases.count ? 8 : 0
        score += visible.count(where: { $0.rank >= .jack }) >= 3 ? 6 : 0
        let exposedRanks = Set(exposed.map(\.rank.rawValue))
        let hasExposedPair = exposedRanks.contains { exposedRanks.contains(PyramidGameRules.pairSum - $0) }
        score += hasExposedPair ? 8 : 0
        score += exposed.contains(where: { $0.rank == .king }) ? 4 : 0
        return score
    }

    /// Scores a fresh TriPeaks deal by its face-up cards (the ten-card base row
    /// plus the waste starter): rank variety, red/black balance, all four
    /// suits, a few face cards, and several playable base cards to suggest an
    /// opening chain.
    private func triPeaksDealScore(of deal: GameState) -> Int {
        let visible = deal.triPeaks.compactMap { $0 }.filter(\.isFaceUp)
        var score = 0
        score += Set(visible.map(\.rank)).count * 6
        let redCount = visible.count(where: { $0.suit.isRed })
        score -= abs(redCount * 2 - visible.count) * 4
        score += Set(visible.map(\.suit)).count == Suit.allCases.count ? 8 : 0
        score += visible.count(where: { $0.rank >= .jack }) >= 3 ? 6 : 0
        if let wasteTop = deal.waste.last {
            let playableCount = visible.count { card in
                TriPeaksGameRules.ranksAdjacentWithWrap(card.rank, wasteTop.rank)
            }
            score += min(playableCount, 3) * 4
        }
        return score
    }

    /// Scores a fresh Golf deal by the eight cards the eye lands on (the seven
    /// exposed column ends plus the waste starter): rank variety, red/black
    /// balance, all four suits, a few face cards, and several playable exposed
    /// cards to suggest an opening run.
    private func golfDealScore(of deal: GameState) -> Int {
        let exposed = deal.tableau.compactMap { $0.last }
        let visible = exposed + Array(deal.waste.suffix(1))
        var score = 0
        score += Set(visible.map(\.rank)).count * 6
        let redCount = visible.count(where: { $0.suit.isRed })
        score -= abs(redCount * 2 - visible.count) * 4
        score += Set(visible.map(\.suit)).count == Suit.allCases.count ? 8 : 0
        score += visible.count(where: { $0.rank >= .jack }) >= 3 ? 6 : 0
        if let wasteTop = deal.waste.last {
            let playableCount = exposed.count { card in
                GolfGameRules.canPlayRank(card.rank.rawValue, ontoWasteTop: wasteTop.rank.rawValue)
            }
            score += min(playableCount, 3) * 4
        }
        return score
    }

    /// Scores a fresh Forty Thieves deal by the eleven cards the eye lands on
    /// (the ten exposed column ends plus the first drawn stock card): rank
    /// variety, red/black balance, all four suits, a few face cards, and a
    /// couple of same-suit builds among the tops to suggest a first move.
    private func fortyThievesDealScore(of deal: GameState) -> Int {
        let exposed = deal.tableau.compactMap { $0.last }
        let visible = exposed + Array(deal.stock.suffix(1))
        var score = 0
        score += Set(visible.map(\.rank)).count * 6
        let redCount = visible.count(where: { $0.suit.isRed })
        score -= abs(redCount * 2 - visible.count) * 4
        score += Set(visible.map(\.suit)).count == Suit.allCases.count ? 8 : 0
        score += visible.count(where: { $0.rank >= .jack }) >= 3 ? 6 : 0
        let buildCount = exposed.count { card in
            exposed.contains { top in
                FortyThievesGameRules.canMoveToTableau(card: card, destinationPile: [top])
            }
        }
        score += min(buildCount, 2) * 4
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
