import XCTest
@testable import Computer_Solitaire

@MainActor
final class HintSearchTests: XCTestCase {
    private var savedStatistics: [String: Data] = [:]

    override func setUp() async throws {
        for mode in GameMode.allCases {
            let key = GameStatisticsStore.defaultsKey(for: mode)
            savedStatistics[key] = UserDefaults.standard.data(forKey: key)
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    override func tearDown() async throws {
        for mode in GameMode.allCases {
            let key = GameStatisticsStore.defaultsKey(for: mode)
            if let data = savedStatistics[key] {
                UserDefaults.standard.set(data, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        savedStatistics = [:]
    }

    func testSearchSuspendsWithoutBlockingGameplayAndCoalescesRequests() async throws {
        let search = ControlledHintSearch()
        let model = SolitaireViewModel(hintSearch: search)
        let originalState = model.state
        let task = try XCTUnwrap(model.requestHint())
        await search.waitForRequests(1)
        let duplicate = try XCTUnwrap(model.requestHint())

        XCTAssertTrue(model.isSearchingForHint)
        XCTAssertNil(model.activeHint)
        XCTAssertEqual(model.persistencePayload().hintRequestsInCurrentGame, 0)
        let requests = await search.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.state, originalState)
        XCTAssertEqual(requests.first?.drawCount, 3)

        // This main-actor action completes while the search is still suspended.
        model.drawFromStock()
        XCTAssertNotEqual(model.state, originalState)
        XCTAssertFalse(model.isSearchingForHint)
        XCTAssertTrue(task.isCancelled)
        await search.finish(0, with: .success(.stockTap))
        await task.value
        await duplicate.value
        XCTAssertNil(model.activeHint)
        XCTAssertEqual(model.persistencePayload().hintRequestsInCurrentGame, 0)
    }

    func testCompletedHintIsPublishedAndCountedOnce() async throws {
        let search = ControlledHintSearch()
        let model = SolitaireViewModel(hintSearch: search)
        let token = model.hintWiggleToken
        let task = try XCTUnwrap(model.requestHint())
        await search.waitForRequests(1)
        await search.finish(0, with: .success(.stockTap))
        await task.value

        XCTAssertEqual(model.activeHint, .stockTap)
        XCTAssertNotEqual(model.hintWiggleToken, token)
        XCTAssertFalse(model.isSearchingForHint)
        XCTAssertEqual(model.persistencePayload().hintRequestsInCurrentGame, 1)
    }

    func testOldCompletionCannotFinishOrDisableNewRequest() async throws {
        for oldResult: Result<HintAdvisor.Hint?, CancellationError> in [
            .success(.stockTap), .success(nil), .failure(CancellationError())
        ] {
            let search = ControlledHintSearch()
            let model = SolitaireViewModel(hintSearch: search)
            let oldTask = try XCTUnwrap(model.requestHint())
            await search.waitForRequests(1)
            model.clearHint()
            let newTask = try XCTUnwrap(model.requestHint())
            await search.waitForRequests(2)
            await search.finish(0, with: oldResult)
            await oldTask.value

            XCTAssertTrue(model.isSearchingForHint)
            XCTAssertTrue(model.isHintAvailable)
            XCTAssertNil(model.activeHint)
            XCTAssertEqual(model.persistencePayload().hintRequestsInCurrentGame, 0)

            await search.finish(1, with: .success(.stockTap))
            await newTask.value
            XCTAssertEqual(model.activeHint, .stockTap)
            XCTAssertFalse(model.isSearchingForHint)
            XCTAssertEqual(model.persistencePayload().hintRequestsInCurrentGame, 1)
        }
    }

    func testEmptySearchDisablesHintsOnlyForUnchangedBoard() async throws {
        for changeBoard in [false, true] {
            let search = ControlledHintSearch()
            let model = SolitaireViewModel(hintSearch: search)
            let task = try XCTUnwrap(model.requestHint())
            await search.waitForRequests(1)
            if changeBoard {
                // Bypass normal mutation methods to exercise the snapshot guard.
                model.state.stock.swapAt(0, 1)
            }
            await search.finish(0, with: .success(nil))
            await task.value
            XCTAssertEqual(model.isHintAvailable, changeBoard)
            XCTAssertFalse(model.isSearchingForHint)
            XCTAssertEqual(model.persistencePayload().hintRequestsInCurrentGame, 0)
        }
    }

    func testChangedSnapshotRejectsSuccessfulHint() async throws {
        let search = ControlledHintSearch()
        let model = SolitaireViewModel(hintSearch: search)
        let task = try XCTUnwrap(model.requestHint())
        await search.waitForRequests(1)
        model.state.stock.swapAt(0, 1)
        await search.finish(0, with: .success(.stockTap))
        await task.value
        XCTAssertNil(model.activeHint)
        XCTAssertFalse(model.isSearchingForHint)
        XCTAssertEqual(model.persistencePayload().hintRequestsInCurrentGame, 0)
    }

    func testOldResultCannotReplaceAlreadyPublishedNewHint() async throws {
        let search = ControlledHintSearch()
        let model = SolitaireViewModel(hintSearch: search)
        let oldTask = try XCTUnwrap(model.requestHint())
        await search.waitForRequests(1)
        model.clearHint()
        let newTask = try XCTUnwrap(model.requestHint())
        await search.waitForRequests(2)
        await search.finish(1, with: .success(.stockTap))
        await newTask.value
        let token = model.hintWiggleToken

        await search.finish(0, with: .success(nil))
        await oldTask.value
        XCTAssertEqual(model.activeHint, .stockTap)
        XCTAssertEqual(model.hintWiggleToken, token)
        XCTAssertTrue(model.isHintAvailable)
        XCTAssertEqual(model.persistencePayload().hintRequestsInCurrentGame, 1)
    }

    func testSessionTransitionsCancelPendingHints() async throws {
        let transitions: [(SolitaireViewModel) -> Void] = [
            { $0.newGame() },
            { $0.redeal() },
            { $0.undo() },
            { _ = $0.restore(from: $0.persistencePayload()) },
            { $0.activateGame(.freecell, restoringFrom: nil) },
            { _ = $0.pauseTimeScoring() },
            { $0.resetStatisticsTracking() },
            { _ = $0.startDragFromTableau(pileIndex: 0, cardIndex: 0) }
        ]
        for transition in transitions {
            let search = ControlledHintSearch()
            let model = SolitaireViewModel(hintSearch: search)
            model.drawFromStock() // Gives undo a history entry.
            let task = try XCTUnwrap(model.requestHint())
            await search.waitForRequests(1)
            transition(model)
            XCTAssertTrue(task.isCancelled)
            XCTAssertFalse(model.isSearchingForHint)
            await search.finish(0, with: .success(.stockTap))
            await task.value
            XCTAssertNil(model.activeHint)
            XCTAssertEqual(model.persistencePayload().hintRequestsInCurrentGame, 0)
        }
    }

    func testCancellationDoesNotDisableHintsAndAllowsRetry() async throws {
        let search = ControlledHintSearch()
        let model = SolitaireViewModel(hintSearch: search)
        let task = try XCTUnwrap(model.requestHint())
        await search.waitForRequests(1)
        await search.finish(0, with: .failure(CancellationError()))
        await task.value
        XCTAssertFalse(model.isSearchingForHint)
        XCTAssertTrue(model.isHintAvailable)

        let retry = try XCTUnwrap(model.requestHint())
        await search.waitForRequests(2)
        await search.finish(1, with: .success(.stockTap))
        await retry.value
        XCTAssertEqual(model.activeHint, .stockTap)
    }

    func testPendingSearchDoesNotRetainSession() async throws {
        let search = ControlledHintSearch()
        var model: SolitaireViewModel? = SolitaireViewModel(hintSearch: search)
        weak let weakModel = model
        let task = try XCTUnwrap(model?.requestHint())
        await search.waitForRequests(1)
        model = nil
        XCTAssertNil(weakModel)
        XCTAssertTrue(task.isCancelled)
        await search.finish(0, with: .success(.stockTap))
        await task.value
    }

    func testRealWorkerReturnsLegalHint() async throws {
        let ace = TestCards.make(.spades, .ace, isFaceUp: true)
        let state = GameState(
            stock: [], waste: [ace], wasteDrawCount: 1,
            foundations: Array(repeating: [], count: 4),
            tableau: Array(repeating: [], count: 7)
        )
        let hint = try await HintSearchWorker().bestHint(in: state, stockDrawCount: 3)
        guard case .move(let move) = hint else { return XCTFail("Expected an ace move") }
        XCTAssertEqual(move.selection.cards, [ace])
        XCTAssertEqual(move.destination, .foundation(0))
    }

    func testAllPlannersStopWithoutClaimingExhaustiveSearchWhenCancelled() async {
        let states = Dictionary(uniqueKeysWithValues: GameVariant.allCases.map {
            ($0, GameState.newGame(variant: $0))
        })
        let task = Task {
            XCTAssertTrue(Task.isCancelled)
            XCTAssertNil(KlondikePlanner.bestHint(in: states[.klondike]!, stockDrawCount: 3))
            XCTAssertNil(FreeCellSolver.solve(states[.freecell]!))
            if case .noProgress(searchWasExhaustive: false) = YukonPlanner.bestLine(in: states[.yukon]!) {
                // Cancellation must never be reported as proof that no move exists.
            } else {
                XCTFail("Yukon search did not stop on cancellation")
            }
            if case .noProgress(searchWasExhaustive: false) = SpiderPlanner.bestLine(in: states[.spider]!) {
                // Cancellation must never be reported as proof that no move exists.
            } else {
                XCTFail("Spider search did not stop on cancellation")
            }
            if case .noProgress(searchWasExhaustive: false) = PyramidPlanner.bestLine(in: states[.pyramid]!) {
                // Cancellation must never be reported as proof that no move exists.
            } else {
                XCTFail("Pyramid search did not stop on cancellation")
            }
            if case .noProgress(searchWasExhaustive: false) = TriPeaksPlanner.bestLine(in: states[.tripeaks]!) {
                // Cancellation must never be reported as proof that no move exists.
            } else {
                XCTFail("TriPeaks search did not stop on cancellation")
            }
            if case .noProgress(searchWasExhaustive: false) = GolfPlanner.bestLine(in: states[.golf]!) {
                // Cancellation must never be reported as proof that no move exists.
            } else {
                XCTFail("Golf search did not stop on cancellation")
            }
            if case .noProgress(searchWasExhaustive: false) = FortyThievesPlanner.bestLine(in: states[.fortyThieves]!) {
                // Cancellation must never be reported as proof that no move exists.
            } else {
                XCTFail("FortyThieves search did not stop on cancellation")
            }
            if case .noProgress(searchWasExhaustive: false) = ScorpionPlanner.bestLine(in: states[.scorpion]!) {
                // Cancellation must never be reported as proof that no move exists.
            } else {
                XCTFail("Scorpion search did not stop on cancellation")
            }
            if case .noProgress(searchWasExhaustive: false) = CanfieldPlanner.bestLine(in: states[.canfield]!) {
                // Cancellation must never be reported as proof that no move exists.
            } else {
                XCTFail("Canfield search did not stop on cancellation")
            }
        }
        task.cancel()
        await task.value
    }

    func testCancelledWorkerRejectsResult() async {
        let state = GameState.newGame()
        // Inherits the main actor, so cancellation happens before the body starts.
        let task = Task {
            try await HintSearchWorker().bestHint(in: state, stockDrawCount: 3)
        }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("A cancelled worker must throw")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }
}

/// Deliberately ignores cancellation to exercise late and out-of-order results.
private actor ControlledHintSearch: HintSearching {
    struct Request: Sendable {
        let state: GameState
        let drawCount: Int
    }
    private(set) var requests: [Request] = []
    private var pending: [Int: CheckedContinuation<HintAdvisor.Hint?, any Error>] = [:]
    private var waiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func bestHint(in state: GameState, stockDrawCount: Int) async throws -> HintAdvisor.Hint? {
        try await withCheckedThrowingContinuation { continuation in
            let index = requests.count
            requests.append(Request(state: state, drawCount: stockDrawCount))
            pending[index] = continuation
            let ready = waiters.filter { $0.count <= requests.count }
            waiters.removeAll { $0.count <= requests.count }
            for waiter in ready { waiter.continuation.resume() }
        }
    }

    func waitForRequests(_ count: Int) async {
        guard requests.count < count else { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }

    func finish(_ index: Int, with result: Result<HintAdvisor.Hint?, CancellationError>) {
        guard let continuation = pending.removeValue(forKey: index) else {
            preconditionFailure("No pending request at index \(index)")
        }
        switch result {
        case .success(let hint): continuation.resume(returning: hint)
        case .failure(let error): continuation.resume(throwing: error)
        }
    }
}
