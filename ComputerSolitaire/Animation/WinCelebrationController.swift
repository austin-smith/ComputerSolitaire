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
        begin(
            foundations: foundations,
            hiddenFoundationCardIDs: Self.foundationCardIDs(from: foundations),
            dropFrames: dropFrames,
            boardViewportSize: boardViewportSize
        )
    }

    func reset(to phase: Phase = .idle) {
        cascadeTask?.cancel()
        cascadeTask = nil
        cards = []
        hiddenFoundationCardIDs = []
        self.phase = phase
    }

    func syncForLoadedGame(
        foundations: [[Card]],
        isWin: Bool,
        dropFrames: [DropTarget: DropTargetGeometry],
        boardViewportSize: CGSize
    ) {
        cascadeTask?.cancel()
        cascadeTask = nil
        if isWin {
            let completedCards = completedStatesForLoadedWin(
                foundations: foundations,
                dropFrames: dropFrames,
                boardViewportSize: boardViewportSize
            )
            cards = completedCards
            hiddenFoundationCardIDs = completedCards.isEmpty
                ? []
                : Self.foundationCardIDs(from: foundations)
            phase = .completed
        } else {
            cards = []
            hiddenFoundationCardIDs = []
            phase = .idle
        }
    }

    func cancelTask() {
        cascadeTask?.cancel()
        cascadeTask = nil
    }

    private func begin(
        foundations: [[Card]],
        hiddenFoundationCardIDs: Set<UUID>,
        dropFrames: [DropTarget: DropTargetGeometry],
        boardViewportSize: CGSize
    ) {
        self.hiddenFoundationCardIDs = hiddenFoundationCardIDs
        let boardBounds = CGRect(origin: .zero, size: boardViewportSize)
        guard boardBounds.width > 0, boardBounds.height > 0 else {
            phase = .completed
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
            phase = .completed
            return
        }

        cascadeTask?.cancel()
        cards = initialStates
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
                    finish()
                    return
                }
            }
        }
    }

    private func finish() {
        cascadeTask?.cancel()
        cascadeTask = nil
        phase = .completed
    }

    private static func foundationCardIDs(from foundations: [[Card]]) -> Set<UUID> {
        Set(foundations.flatMap { pile in pile.map(\.id) })
    }

    private func completedStatesForLoadedWin(
        foundations: [[Card]],
        dropFrames: [DropTarget: DropTargetGeometry],
        boardViewportSize: CGSize
    ) -> [WinCascadeCardState] {
        let boardBounds = CGRect(origin: .zero, size: boardViewportSize)
        guard boardBounds.width > 0, boardBounds.height > 0 else { return [] }

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

        return WinCascadeCoordinator.makeCompletedStates(
            foundations: foundations,
            foundationFrames: launchFrames,
            fallbackLaunchFrame: fallbackLaunchFrame,
            boardBounds: boardBounds
        )
    }

}
