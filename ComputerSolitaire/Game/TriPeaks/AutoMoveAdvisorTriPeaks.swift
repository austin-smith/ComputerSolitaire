import Foundation

/// TriPeaks shares no foundation/tableau/free-cell move algebra with the other
/// variants, so `AutoMoveAdvisor` dispatches to it wholesale instead of threading
/// its moves through the pile-oriented hooks.
enum TriPeaksAutoMoveAdvisor {
    /// Every uncovered peak card (uncovered cards are always face up), each as a
    /// single-card selection. The waste top is never a selection: in TriPeaks it
    /// is the match target, not a mover.
    static func candidateSelections(in state: GameState) -> [Selection] {
        var selections: [Selection] = []

        for index in state.triPeaks.indices {
            guard let card = state.triPeaks[index],
                  TriPeaksGeometry.isUncovered(index, in: state.triPeaks) else { continue }
            selections.append(Selection(source: .triPeaks(index: index), cards: [card]))
        }

        return selections
    }

    /// `[.waste]` when the selection is rank-adjacent to the waste top; the
    /// waste is TriPeaks' only destination.
    static func legalDestinations(for selection: Selection, in state: GameState) -> [Destination] {
        guard AutoMoveAdvisor.selectionMatchesState(selection, in: state) else { return [] }
        guard case .triPeaks(let index) = selection.source else { return [] }
        guard TriPeaksGameRules.canPlay(index: index, in: state) else { return [] }
        return [.waste]
    }

    static func simulatedState(
        afterMoving selection: Selection,
        to destination: Destination,
        in state: GameState
    ) -> GameState? {
        guard AutoMoveAdvisor.selectionMatchesState(selection, in: state) else { return nil }
        return TriPeaksGameRules.stateByApplying(
            selection: selection,
            destination: destination,
            to: state
        )
    }
}
