import CoreGraphics
import Foundation
import Observation

@MainActor
@Observable
final class WinCelebrationController {
    enum Phase: Equatable {
        case idle
        case animating
        case completed
    }

    private(set) var cards: [WinCascadeCardState] = []
    private(set) var hiddenFoundationCardIDs: Set<UUID> = []
    private(set) var phase: Phase = .idle
    private(set) var isDebugMode = false

    private var cascadeTask: Task<Void, Never>?

    var isAnimating: Bool {
        phase == .animating
    }

    func beginIfNeededForWin(
        foundations: [[Card]],
        dropFrames: [DropTarget: DropTargetGeometry],
        boardViewportSize: CGSize
    ) {
        guard phase == .idle else { return }
        isDebugMode = false
        begin(
            foundations: foundations,
            hiddenFoundationCardIDs: Set(foundations.flatMap { pile in pile.map(\.id) }),
            dropFrames: dropFrames,
            boardViewportSize: boardViewportSize,
            completedPhaseAfterAnimation: true
        )
    }

    func triggerDebug(
        liveFoundations: [[Card]],
        dropFrames: [DropTarget: DropTargetGeometry],
        boardViewportSize: CGSize
    ) {
        isDebugMode = true
        begin(
            foundations: Self.debugWinningFoundations(from: liveFoundations),
            hiddenFoundationCardIDs: Set(liveFoundations.flatMap { pile in pile.map(\.id) }),
            dropFrames: dropFrames,
            boardViewportSize: boardViewportSize,
            completedPhaseAfterAnimation: true
        )
    }

    func reset(to phase: Phase = .idle) {
        cascadeTask?.cancel()
        cascadeTask = nil
        cards = []
        hiddenFoundationCardIDs = []
        isDebugMode = false
        self.phase = phase
    }

    func syncForLoadedGame(isWin: Bool) {
        reset(to: isWin ? .completed : .idle)
    }

    func cancelTask() {
        cascadeTask?.cancel()
        cascadeTask = nil
    }

    private func begin(
        foundations: [[Card]],
        hiddenFoundationCardIDs: Set<UUID>,
        dropFrames: [DropTarget: DropTargetGeometry],
        boardViewportSize: CGSize,
        completedPhaseAfterAnimation: Bool
    ) {
        let boardBounds = CGRect(origin: .zero, size: boardViewportSize)
        guard boardBounds.width > 0, boardBounds.height > 0 else {
            phase = completedPhaseAfterAnimation ? .completed : .idle
            return
        }

        var launchFrames: [Int: CGRect] = [:]
        for index in 0..<4 {
            if let frame = dropFrames[.foundation(index)]?.snapFrame, frame != .zero {
                launchFrames[index] = frame
            }
        }

        let fallbackLaunchFrame = launchFrames[0]
            ?? launchFrames.values.first
            ?? CGRect(
                x: boardBounds.midX - 50,
                y: max(0, boardBounds.height * 0.22 - 72),
                width: 100,
                height: 145
            )

        let initialStates = WinCascadeCoordinator.makeInitialStates(
            foundations: foundations,
            foundationFrames: launchFrames,
            fallbackLaunchFrame: fallbackLaunchFrame
        )
        guard !initialStates.isEmpty else {
            phase = completedPhaseAfterAnimation ? .completed : .idle
            return
        }

        cascadeTask?.cancel()
        cards = initialStates
        self.hiddenFoundationCardIDs = hiddenFoundationCardIDs
        phase = .animating

        cascadeTask = Task { @MainActor in
            let tickNanos: UInt64 = 16_666_667

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: tickNanos)
                guard !Task.isCancelled else { return }
                guard phase == .animating else { return }

                let bounds = CGRect(origin: .zero, size: boardViewportSize)
                WinCascadeCoordinator.step(
                    states: &cards,
                    deltaTime: 1.0 / 60.0,
                    boardBounds: bounds
                )

                if !cards.isEmpty && cards.allSatisfy(\.isSettled) {
                    finish(completedPhaseAfterAnimation: completedPhaseAfterAnimation)
                    return
                }
            }
        }
    }

    private func finish(completedPhaseAfterAnimation: Bool) {
        cascadeTask?.cancel()
        cascadeTask = nil
        phase = completedPhaseAfterAnimation ? .completed : .idle
    }

    private static func debugWinningFoundations(from foundations: [[Card]]) -> [[Card]] {
        var pileSuits: [Suit?] = Array(repeating: nil, count: foundations.count)
        var usedSuits: Set<Suit> = []

        for pile in foundations.indices {
            if let suit = foundations[pile].first?.suit {
                pileSuits[pile] = suit
                usedSuits.insert(suit)
            }
        }

        for pile in pileSuits.indices where pileSuits[pile] == nil {
            if let suit = Suit.allCases.first(where: { !usedSuits.contains($0) }) {
                pileSuits[pile] = suit
                usedSuits.insert(suit)
            } else {
                pileSuits[pile] = Suit.allCases[pile % Suit.allCases.count]
            }
        }

        var debugFoundations = Array(repeating: [Card](), count: foundations.count)
        for pile in foundations.indices {
            let suit = pileSuits[pile] ?? Suit.allCases[pile % Suit.allCases.count]
            var existingByRank: [Rank: Card] = [:]
            for card in foundations[pile] where card.suit == suit {
                var faceUpCard = card
                faceUpCard.isFaceUp = true
                existingByRank[faceUpCard.rank] = faceUpCard
            }

            var pileCards: [Card] = []
            pileCards.reserveCapacity(Rank.allCases.count)
            for rank in Rank.allCases {
                if let existing = existingByRank[rank] {
                    pileCards.append(existing)
                } else {
                    pileCards.append(Card(suit: suit, rank: rank, isFaceUp: true))
                }
            }
            debugFoundations[pile] = pileCards
        }

        return debugFoundations
    }
}
