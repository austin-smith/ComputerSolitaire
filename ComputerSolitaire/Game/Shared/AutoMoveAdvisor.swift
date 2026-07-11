import Foundation

/// Move generation shared by the tap policy, hint planners, and solver plumbing:
/// which selections a player could pick up, where each can legally go, and what the
/// state looks like after a move.
enum AutoMoveAdvisor {
    static func legalDestinations(for selection: Selection, in state: GameState) -> [Destination] {
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
                guard isValidTableauSequence(cards) else { continue }
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
        guard selectionMatchesState(selection, in: state) else { return nil }
        guard legalDestinations(for: selection, in: state).contains(destination) else { return nil }

        var nextState = state
        remove(selection, from: &nextState, stockDrawCount: stockDrawCount)
        guard append(selection.cards, to: destination, in: &nextState) else { return nil }
        return nextState
    }

    static func selectionMatchesState(_ selection: Selection, in state: GameState) -> Bool {
        guard !selection.cards.isEmpty else { return false }

        switch selection.source {
        case .waste:
            return matchesWaste(selection, in: state)
        case .freeCell(let slot):
            return matchesFreeCell(selection, slot: slot, in: state)
        case .foundation(let pile):
            return matchesFoundation(selection, pile: pile, in: state)
        case .tableau(let pile, let index):
            return matchesTableau(selection, pile: pile, index: index, in: state)
        }
    }

    static func isValidTableauSequence(_ cards: [Card]) -> Bool {
        GameRules.isValidDescendingAlternatingSequence(cards)
    }
}

private extension AutoMoveAdvisor {
    static func remove(_ selection: Selection, from state: inout GameState, stockDrawCount: Int) {
        switch selection.source {
        case .waste:
            _ = state.waste.popLast()
            state.wasteDrawCount = stockDrawCount == DrawMode.one.rawValue
                ? min(1, state.waste.count)
                : max(0, state.wasteDrawCount - 1)
        case .freeCell(let slot):
            state.freeCells[slot] = nil
        case .foundation(let pile):
            _ = state.foundations[pile].popLast()
        case .tableau(let pile, let index):
            state.tableau[pile].removeSubrange(index..<state.tableau[pile].count)
            applyVariantTableauSourceRemovalEffects(on: &state, pileIndex: pile)
        }
    }

    static func append(_ cards: [Card], to destination: Destination, in state: inout GameState) -> Bool {
        switch destination {
        case .foundation(let index):
            guard cards.count == 1, let card = cards.first else { return false }
            state.foundations[index].append(card)
        case .tableau(let index):
            state.tableau[index].append(contentsOf: cards)
        case .freeCell(let index):
            guard cards.count == 1, let card = cards.first else { return false }
            state.freeCells[index] = card
        }
        return true
    }

    static func matchesWaste(_ selection: Selection, in state: GameState) -> Bool {
        guard selection.cards.count == 1, let topWaste = state.waste.last else { return false }
        return topWaste.id == selection.cards[0].id
    }

    static func matchesFreeCell(_ selection: Selection, slot: Int, in state: GameState) -> Bool {
        guard selection.cards.count == 1,
              state.freeCells.indices.contains(slot),
              let card = state.freeCells[slot] else { return false }
        return card.id == selection.cards[0].id
    }

    static func matchesFoundation(_ selection: Selection, pile: Int, in state: GameState) -> Bool {
        guard selection.cards.count == 1,
              state.foundations.indices.contains(pile),
              let card = state.foundations[pile].last else { return false }
        return card.id == selection.cards[0].id
    }

    static func matchesTableau(
        _ selection: Selection,
        pile: Int,
        index: Int,
        in state: GameState
    ) -> Bool {
        guard state.tableau.indices.contains(pile) else { return false }
        let sourcePile = state.tableau[pile]
        guard sourcePile.indices.contains(index) else { return false }
        let selectedCards = Array(sourcePile[index...])
        guard selectedCards.count == selection.cards.count else { return false }
        return zip(selectedCards, selection.cards).allSatisfy { $0.id == $1.id }
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
        }
    }

    static func applyVariantTableauSourceRemovalEffects(on state: inout GameState, pileIndex: Int) {
        switch state.variant {
        case .klondike:
            KlondikeAutoMoveAdvisor.applyTableauSourceRemovalEffects(on: &state, pileIndex: pileIndex)
        case .freecell:
            FreeCellAutoMoveAdvisor.applyTableauSourceRemovalEffects(on: &state, pileIndex: pileIndex)
        }
    }
}
