import Foundation

/// Move generation shared by the tap policy, hint planners, and solver plumbing:
/// which selections a player could pick up, where each can legally go, and what the
/// state looks like after a move.
enum AutoMoveAdvisor {
    static func legalDestinations(for selection: Selection, in state: GameState) -> [Destination] {
        // Pyramid removes pairs instead of building piles, so its move set is
        // generated wholesale rather than through the pile-oriented flow below.
        if state.variant == .pyramid {
            return PyramidAutoMoveAdvisor.legalDestinations(for: selection, in: state)
        }

        guard selectionMatchesState(selection, in: state) else { return [] }
        guard let movingCard = selection.cards.first else { return [] }

        var destinations: [Destination] = []

        if selection.cards.count == 1 {
            for foundationIndex in state.foundations.indices {
                let foundation = state.foundations[foundationIndex]
                if GameRules.canMoveToFoundation(card: movingCard, foundation: foundation) {
                    destinations.append(.foundation(foundationIndex))
                }
            }
        }

        for tableauIndex in state.tableau.indices {
            if case .tableau(let sourcePile, _) = selection.source, sourcePile == tableauIndex {
                continue
            }
            let tableauPile = state.tableau[tableauIndex]
            if GameRules.canMoveToTableau(
                card: movingCard,
                destinationPile: tableauPile,
                variant: state.variant
            ) {
                guard variantAllowsTableauTransfer(
                    selection: selection,
                    destinationTableauIndex: tableauIndex,
                    in: state
                ) else {
                    continue
                }
                if isVariantRedundantEmptyColumnTransfer(
                    selection: selection,
                    destinationTableauIndex: tableauIndex,
                    in: state
                ) {
                    continue
                }
                destinations.append(.tableau(tableauIndex))
            }
        }

        appendVariantAuxiliaryDestinations(for: selection, in: state, destinations: &destinations)

        return destinations
    }

    static func candidateSelections(in state: GameState) -> [Selection] {
        if state.variant == .pyramid {
            return PyramidAutoMoveAdvisor.candidateSelections(in: state)
        }

        var selections: [Selection] = []

        if let topWasteCard = state.waste.last, state.wasteDrawCount > 0 {
            selections.append(Selection(source: .waste, cards: [topWasteCard]))
        }

        for foundationIndex in state.foundations.indices {
            guard let topFoundationCard = state.foundations[foundationIndex].last else { continue }
            selections.append(
                Selection(source: .foundation(pile: foundationIndex), cards: [topFoundationCard])
            )
        }

        for freeCellIndex in state.freeCells.indices {
            guard let freeCellCard = state.freeCells[freeCellIndex] else { continue }
            selections.append(
                Selection(source: .freeCell(slot: freeCellIndex), cards: [freeCellCard])
            )
        }

        for pileIndex in state.tableau.indices {
            let pile = state.tableau[pileIndex]
            for cardIndex in pile.indices where pile[cardIndex].isFaceUp {
                let cards = Array(pile[cardIndex...])
                guard variantAllowsTableauPickup(of: cards, in: state) else { continue }
                selections.append(
                    Selection(source: .tableau(pile: pileIndex, index: cardIndex), cards: cards)
                )
            }
        }

        return selections
    }

    static func simulatedState(
        afterMoving selection: Selection,
        to destination: Destination,
        in state: GameState,
        stockDrawCount: Int
    ) -> GameState? {
        if state.variant == .pyramid {
            return PyramidAutoMoveAdvisor.simulatedState(
                afterMoving: selection,
                to: destination,
                in: state
            )
        }

        guard selectionMatchesState(selection, in: state) else { return nil }
        guard legalDestinations(for: selection, in: state).contains(destination) else { return nil }

        var nextState = state

        switch selection.source {
        case .waste:
            _ = nextState.waste.popLast()
            if stockDrawCount == DrawMode.one.rawValue {
                nextState.wasteDrawCount = min(1, nextState.waste.count)
            } else {
                nextState.wasteDrawCount = max(0, nextState.wasteDrawCount - 1)
            }
        case .freeCell(let slot):
            nextState.freeCells[slot] = nil
        case .foundation(let pile):
            _ = nextState.foundations[pile].popLast()
        case .tableau(let pile, let index):
            nextState.tableau[pile].removeSubrange(index..<nextState.tableau[pile].count)
            applyVariantTableauSourceRemovalEffects(on: &nextState, pileIndex: pile)
        case .pyramid:
            // Unreachable: Pyramid states dispatch wholesale above.
            return nil
        }

        switch destination {
        case .foundation(let index):
            guard selection.cards.count == 1, let card = selection.cards.first else { return nil }
            nextState.foundations[index].append(card)
        case .tableau(let index):
            nextState.tableau[index].append(contentsOf: selection.cards)
        case .freeCell(let index):
            guard selection.cards.count == 1, let card = selection.cards.first else { return nil }
            nextState.freeCells[index] = card
        case .pyramid, .waste, .discard:
            // Unreachable: Pyramid states dispatch wholesale above.
            return nil
        }

        return nextState
    }

    static func selectionMatchesState(_ selection: Selection, in state: GameState) -> Bool {
        guard !selection.cards.isEmpty else { return false }

        switch selection.source {
        case .waste:
            guard selection.cards.count == 1, let topWaste = state.waste.last else { return false }
            return topWaste.id == selection.cards[0].id

        case .freeCell(let slot):
            guard selection.cards.count == 1 else { return false }
            guard state.freeCells.indices.contains(slot), let freeCellCard = state.freeCells[slot] else { return false }
            return freeCellCard.id == selection.cards[0].id

        case .foundation(let pile):
            guard selection.cards.count == 1 else { return false }
            guard state.foundations.indices.contains(pile),
                  let topFoundation = state.foundations[pile].last else { return false }
            return topFoundation.id == selection.cards[0].id

        case .tableau(let pile, let index):
            guard state.tableau.indices.contains(pile) else { return false }
            let sourcePile = state.tableau[pile]
            guard sourcePile.indices.contains(index) else { return false }
            let selectedCards = Array(sourcePile[index...])
            guard selectedCards.count == selection.cards.count else { return false }
            return zip(selectedCards, selection.cards).allSatisfy { $0.id == $1.id }

        case .pyramid(let index):
            guard selection.cards.count == 1 else { return false }
            guard state.pyramid.indices.contains(index),
                  let card = state.pyramid[index] else { return false }
            return card.id == selection.cards[0].id
        }
    }

    static func isValidTableauSequence(_ cards: [Card]) -> Bool {
        GameRules.isValidDescendingAlternatingSequence(cards)
    }

    /// Moving an entire king-led tableau stack to another empty column is a no-op
    /// for advisor quality purposes (manual play can still do this). Shared by the
    /// variants whose empty columns accept Kings only.
    static func isRedundantWholePileKingTransfer(
        selection: Selection,
        destinationTableauIndex: Int,
        in state: GameState
    ) -> Bool {
        guard case .tableau(let sourcePile, let sourceIndex) = selection.source else { return false }
        guard sourcePile != destinationTableauIndex else { return false }
        guard state.tableau.indices.contains(sourcePile),
              state.tableau.indices.contains(destinationTableauIndex) else { return false }
        guard state.tableau[destinationTableauIndex].isEmpty else { return false }
        guard sourceIndex == 0 else { return false }

        let sourceCards = state.tableau[sourcePile]
        guard selection.cards.count == sourceCards.count else { return false }
        guard let movingCard = selection.cards.first else { return false }
        return movingCard.rank == .king
    }

    /// Flips a face-down card exposed at the top of the pile a selection left,
    /// shared by the variants that deal face-down tableau cards.
    static func flipExposedFaceDownTop(on state: inout GameState, pileIndex: Int) {
        guard let topIndex = state.tableau[pileIndex].indices.last,
              !state.tableau[pileIndex][topIndex].isFaceUp else {
            return
        }
        state.tableau[pileIndex][topIndex].isFaceUp = true
    }
}

private extension AutoMoveAdvisor {
    static func variantAllowsTableauPickup(of cards: [Card], in state: GameState) -> Bool {
        switch state.variant {
        case .klondike:
            return KlondikeAutoMoveAdvisor.allowsTableauPickup(of: cards, in: state)
        case .freecell:
            return FreeCellAutoMoveAdvisor.allowsTableauPickup(of: cards, in: state)
        case .yukon:
            return YukonAutoMoveAdvisor.allowsTableauPickup(of: cards, in: state)
        case .pyramid:
            // Unreachable: Pyramid dispatches wholesale before the tableau flow.
            return false
        }
    }

    static func variantAllowsTableauTransfer(
        selection: Selection,
        destinationTableauIndex: Int,
        in state: GameState
    ) -> Bool {
        switch state.variant {
        case .klondike:
            return KlondikeAutoMoveAdvisor.allowsTableauTransfer(
                selection: selection,
                destinationTableauIndex: destinationTableauIndex,
                in: state
            )
        case .freecell:
            return FreeCellAutoMoveAdvisor.allowsTableauTransfer(
                selection: selection,
                destinationTableauIndex: destinationTableauIndex,
                in: state
            )
        case .yukon:
            return YukonAutoMoveAdvisor.allowsTableauTransfer(
                selection: selection,
                destinationTableauIndex: destinationTableauIndex,
                in: state
            )
        case .pyramid:
            // Unreachable: Pyramid dispatches wholesale before the tableau flow.
            return false
        }
    }

    static func isVariantRedundantEmptyColumnTransfer(
        selection: Selection,
        destinationTableauIndex: Int,
        in state: GameState
    ) -> Bool {
        switch state.variant {
        case .klondike:
            return KlondikeAutoMoveAdvisor.isRedundantEmptyColumnTransfer(
                selection: selection,
                destinationTableauIndex: destinationTableauIndex,
                in: state
            )
        case .freecell:
            return false
        case .yukon:
            return YukonAutoMoveAdvisor.isRedundantEmptyColumnTransfer(
                selection: selection,
                destinationTableauIndex: destinationTableauIndex,
                in: state
            )
        case .pyramid:
            // Unreachable: Pyramid dispatches wholesale before the tableau flow.
            return false
        }
    }

    static func appendVariantAuxiliaryDestinations(
        for selection: Selection,
        in state: GameState,
        destinations: inout [Destination]
    ) {
        switch state.variant {
        case .klondike:
            KlondikeAutoMoveAdvisor.appendAuxiliaryDestinations(
                for: selection,
                in: state,
                destinations: &destinations
            )
        case .freecell:
            FreeCellAutoMoveAdvisor.appendAuxiliaryDestinations(
                for: selection,
                in: state,
                destinations: &destinations
            )
        case .yukon:
            YukonAutoMoveAdvisor.appendAuxiliaryDestinations(
                for: selection,
                in: state,
                destinations: &destinations
            )
        case .pyramid:
            // Unreachable: Pyramid dispatches wholesale before the tableau flow.
            break
        }
    }

    static func applyVariantTableauSourceRemovalEffects(on state: inout GameState, pileIndex: Int) {
        switch state.variant {
        case .klondike:
            KlondikeAutoMoveAdvisor.applyTableauSourceRemovalEffects(on: &state, pileIndex: pileIndex)
        case .freecell:
            FreeCellAutoMoveAdvisor.applyTableauSourceRemovalEffects(on: &state, pileIndex: pileIndex)
        case .yukon:
            YukonAutoMoveAdvisor.applyTableauSourceRemovalEffects(on: &state, pileIndex: pileIndex)
        case .pyramid:
            // Unreachable: Pyramid dispatches wholesale before the tableau flow.
            break
        }
    }
}
