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

    /// `launchPiles` are the piles the cascade erupts from, with `launchTargets`
    /// naming each pile's on-board drop target (aligned by index): the four
    /// foundations for the build-up variants, the discard for Pyramid.
    func beginIfNeededForWin(
        launchPiles: [[Card]],
        launchTargets: [DropTarget],
        dropFrames: [DropTarget: DropTargetGeometry],
        boardViewportSize: CGSize
    ) {
        guard phase == .idle else { return }
        begin(
            launchPiles: launchPiles,
            launchTargets: launchTargets,
            hiddenLaunchCardIDs: Self.launchCardIDs(from: launchPiles),
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
        launchPiles: [[Card]],
        launchTargets: [DropTarget],
        isWin: Bool,
        dropFrames: [DropTarget: DropTargetGeometry],
        boardViewportSize: CGSize
    ) {
        cascadeTask?.cancel()
        cascadeTask = nil
        if isWin {
            let completedCards = completedStatesForLoadedWin(
                launchPiles: launchPiles,
                launchTargets: launchTargets,
                dropFrames: dropFrames,
                boardViewportSize: boardViewportSize
            )
            cards = completedCards
            hiddenFoundationCardIDs = completedCards.isEmpty
                ? []
                : Self.launchCardIDs(from: launchPiles)
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
        launchPiles: [[Card]],
        launchTargets: [DropTarget],
        hiddenLaunchCardIDs: Set<UUID>,
        dropFrames: [DropTarget: DropTargetGeometry],
        boardViewportSize: CGSize
    ) {
        self.hiddenFoundationCardIDs = hiddenLaunchCardIDs
        let boardBounds = CGRect(origin: .zero, size: boardViewportSize)
        guard boardBounds.width > 0, boardBounds.height > 0 else {
            phase = .completed
            return
        }

        let launchFrames = Self.launchFrames(for: launchTargets, dropFrames: dropFrames)
        let fallbackLaunchFrame = Self.fallbackLaunchFrame(
            launchFrames: launchFrames,
            boardBounds: boardBounds
        )

        let initialStates = WinCascadeCoordinator.makeInitialStates(
            foundations: launchPiles,
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

    private static func launchCardIDs(from launchPiles: [[Card]]) -> Set<UUID> {
        Set(launchPiles.flatMap { pile in pile.map(\.id) })
    }

    private static func launchFrames(
        for launchTargets: [DropTarget],
        dropFrames: [DropTarget: DropTargetGeometry]
    ) -> [Int: CGRect] {
        var launchFrames: [Int: CGRect] = [:]
        for (index, target) in launchTargets.enumerated() {
            if let frame = dropFrames[target]?.snapFrame, frame != .zero {
                launchFrames[index] = frame
            }
        }
        return launchFrames
    }

    private static func fallbackLaunchFrame(
        launchFrames: [Int: CGRect],
        boardBounds: CGRect
    ) -> CGRect {
        launchFrames[0]
            ?? launchFrames.values.first
            ?? CGRect(
                x: boardBounds.midX - 50,
                y: max(0, boardBounds.height * 0.22 - 72),
                width: 100,
                height: 145
            )
    }

    private func completedStatesForLoadedWin(
        launchPiles: [[Card]],
        launchTargets: [DropTarget],
        dropFrames: [DropTarget: DropTargetGeometry],
        boardViewportSize: CGSize
    ) -> [WinCascadeCardState] {
        let boardBounds = CGRect(origin: .zero, size: boardViewportSize)
        guard boardBounds.width > 0, boardBounds.height > 0 else { return [] }

        let launchFrames = Self.launchFrames(for: launchTargets, dropFrames: dropFrames)
        let fallbackLaunchFrame = Self.fallbackLaunchFrame(
            launchFrames: launchFrames,
            boardBounds: boardBounds
        )

        return WinCascadeCoordinator.makeCompletedStates(
            foundations: launchPiles,
            foundationFrames: launchFrames,
            fallbackLaunchFrame: fallbackLaunchFrame,
            boardBounds: boardBounds
        )
    }

}
