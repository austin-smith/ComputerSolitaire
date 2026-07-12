import Foundation

/// Pyramid shares no foundation/tableau/free-cell move algebra with the other
/// variants, so `AutoMoveAdvisor` dispatches to it wholesale instead of threading
/// its moves through the pile-oriented hooks.
enum PyramidAutoMoveAdvisor {
    /// The top waste card (if any) plus every selectable pyramid card, each as a
    /// single-card selection.
    static func candidateSelections(in state: GameState) -> [Selection] {
        var selections: [Selection] = []

        if let wasteTop = state.waste.last {
            selections.append(Selection(source: .waste, cards: [wasteTop]))
        }

        for index in state.pyramid.indices {
            guard let card = state.pyramid[index],
                  PyramidGameRules.isSelectable(index: index, in: state.pyramid) else { continue }
            selections.append(Selection(source: .pyramid(index: index), cards: [card]))
        }

        return selections
    }

    static func legalDestinations(for selection: Selection, in state: GameState) -> [Destination] {
        guard AutoMoveAdvisor.selectionMatchesState(selection, in: state) else { return [] }

        var destinations: [Destination] = []

        switch selection.source {
        case .pyramid(let sourceIndex):
            for partnerIndex in state.pyramid.indices
            where PyramidGameRules.canRemovePair(sourceIndex, partnerIndex, in: state.pyramid) {
                destinations.append(.pyramid(partnerIndex))
            }
            if PyramidGameRules.canRemovePairWithWasteTop(pyramidIndex: sourceIndex, in: state) {
                destinations.append(.waste)
            }
        case .waste:
            for partnerIndex in state.pyramid.indices
            where PyramidGameRules.canRemovePairWithWasteTop(pyramidIndex: partnerIndex, in: state) {
                destinations.append(.pyramid(partnerIndex))
            }
        case .foundation, .freeCell, .tableau:
            return []
        }

        if PyramidGameRules.canRemoveKing(selection: selection, in: state) {
            destinations.append(.discard)
        }

        return destinations
    }

    static func simulatedState(
        afterMoving selection: Selection,
        to destination: Destination,
        in state: GameState
    ) -> GameState? {
        guard AutoMoveAdvisor.selectionMatchesState(selection, in: state) else { return nil }
        return PyramidGameRules.stateByApplying(
            selection: selection,
            destination: destination,
            to: state
        )
    }
}
