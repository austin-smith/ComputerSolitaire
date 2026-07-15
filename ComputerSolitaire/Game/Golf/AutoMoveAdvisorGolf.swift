import Foundation

/// Golf shares no foundation/tableau/free-cell move algebra with the building
/// variants — its only move is exposed column card onto the waste — so
/// `AutoMoveAdvisor` dispatches to it wholesale instead of threading its moves
/// through the pile-oriented hooks.
nonisolated enum GolfAutoMoveAdvisor {
    /// The exposed (last) card of every non-empty column, each as a
    /// single-card selection. The waste top is never a selection: in Golf it
    /// is the match target, not a mover.
    static func candidateSelections(in state: GameState) -> [Selection] {
        var selections: [Selection] = []

        for pileIndex in state.tableau.indices {
            guard let card = state.tableau[pileIndex].last else { continue }
            selections.append(
                Selection(
                    source: .tableau(pile: pileIndex, index: state.tableau[pileIndex].count - 1),
                    cards: [card]
                )
            )
        }

        return selections
    }

    /// `[.waste]` when the selection is rank-adjacent to a non-King waste top;
    /// the waste is Golf's only destination.
    static func legalDestinations(for selection: Selection, in state: GameState) -> [Destination] {
        guard AutoMoveAdvisor.selectionMatchesState(selection, in: state) else { return [] }
        guard case .tableau(let pile, let index) = selection.source,
              index == state.tableau[pile].count - 1 else { return [] }
        guard GolfGameRules.canPlay(column: pile, in: state) else { return [] }
        return [.waste]
    }

    static func simulatedState(
        afterMoving selection: Selection,
        to destination: Destination,
        in state: GameState
    ) -> GameState? {
        guard AutoMoveAdvisor.selectionMatchesState(selection, in: state) else { return nil }
        return GolfGameRules.stateByApplying(
            selection: selection,
            destination: destination,
            to: state
        )
    }
}
