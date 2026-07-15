import Foundation

/// Move generation shared by the tap policy, hint planners, and solver plumbing:
/// which selections a player could pick up, where each can legally go, and what the
/// state looks like after a move.
nonisolated enum AutoMoveAdvisor {
    static func legalDestinations(for selection: Selection, in state: GameState) -> [Destination] {
        // Pyramid, TriPeaks, and Golf remove cards instead of building piles,
        // so their move sets are generated wholesale rather than through the
        // pile-oriented flow below.
        if state.variant == .pyramid {
            return PyramidAutoMoveAdvisor.legalDestinations(for: selection, in: state)
        }
        if state.variant == .tripeaks {
            return TriPeaksAutoMoveAdvisor.legalDestinations(for: selection, in: state)
        }
        if state.variant == .golf {
            return GolfAutoMoveAdvisor.legalDestinations(for: selection, in: state)
        }

        guard selectionMatchesState(selection, in: state) else { return [] }
        guard let movingCard = selection.cards.first else { return [] }

        var destinations: [Destination] = []

        if selection.cards.count == 1, state.variant.playerBuildsFoundations {
            for foundationIndex in state.foundations.indices {
                let foundation = state.foundations[foundationIndex]
                if GameRules.canMoveToFoundation(card: movingCard, foundation: foundation, in: state) {
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
        if state.variant == .tripeaks {
            return TriPeaksAutoMoveAdvisor.candidateSelections(in: state)
        }
        if state.variant == .golf {
            return GolfAutoMoveAdvisor.candidateSelections(in: state)
        }

        var selections: [Selection] = []

        if let topWasteCard = state.waste.last, state.wasteDrawCount > 0 {
            selections.append(Selection(source: .waste, cards: [topWasteCard]))
        }

        if state.variant.allowsFoundationRollback {
            for foundationIndex in state.foundations.indices {
                guard let topFoundationCard = state.foundations[foundationIndex].last else { continue }
                selections.append(
                    Selection(source: .foundation(pile: foundationIndex), cards: [topFoundationCard])
                )
            }
        }

        for freeCellIndex in state.freeCells.indices {
            guard let freeCellCard = state.freeCells[freeCellIndex] else { continue }
            selections.append(
                Selection(source: .freeCell(slot: freeCellIndex), cards: [freeCellCard])
            )
        }

        // Canfield's reserve; empty for the other variants. Only its exposed
        // top card is ever available.
        if let topReserveCard = state.reserve.last, topReserveCard.isFaceUp {
            selections.append(Selection(source: .reserve, cards: [topReserveCard]))
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
        if state.variant == .tripeaks {
            return TriPeaksAutoMoveAdvisor.simulatedState(
                afterMoving: selection,
                to: destination,
                in: state
            )
        }
        if state.variant == .golf {
            return GolfAutoMoveAdvisor.simulatedState(
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
            if state.variant == .canfield {
                nextState.wasteDrawCount = CanfieldGameRules.wasteDrawCountAfterWastePlay(in: nextState)
            } else if stockDrawCount == DrawMode.one.rawValue {
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
        case .reserve:
            _ = nextState.reserve.popLast()
            if let newTopIndex = nextState.reserve.indices.last {
                nextState.reserve[newTopIndex].isFaceUp = true
            }
        case .pyramid, .triPeaks:
            // Unreachable: Pyramid and TriPeaks states dispatch wholesale above.
            return nil
        }

        switch destination {
        case .foundation(let index):
            guard selection.cards.count == 1, let card = selection.cards.first else { return nil }
            nextState.foundations[index].append(card)
        case .tableau(let index):
            nextState.tableau[index].append(contentsOf: selection.cards)
            applyVariantTableauDestinationEffects(on: &nextState, pileIndex: index)
        case .freeCell(let index):
            guard selection.cards.count == 1, let card = selection.cards.first else { return nil }
            nextState.freeCells[index] = card
        case .pyramid, .waste, .discard:
            // Unreachable: Pyramid and TriPeaks states dispatch wholesale above.
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

        case .triPeaks(let index):
            guard selection.cards.count == 1 else { return false }
            guard state.triPeaks.indices.contains(index),
                  let card = state.triPeaks[index] else { return false }
            return card.id == selection.cards[0].id

        case .reserve:
            guard selection.cards.count == 1, let topReserve = state.reserve.last else { return false }
            return topReserve.id == selection.cards[0].id
        }
    }

    static func isValidTableauSequence(_ cards: [Card]) -> Bool {
        GameRules.isValidDescendingAlternatingSequence(cards)
    }

    /// Moving an entire tableau pile to another empty column is a no-op for
    /// advisor quality purposes (manual play can still do this).
    static func isRedundantWholePileTransfer(
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
        return selection.cards.count == state.tableau[sourcePile].count
    }

    /// The whole-pile no-op restricted to king-led stacks, for the variants
    /// whose empty columns accept Kings only.
    static func isRedundantWholePileKingTransfer(
        selection: Selection,
        destinationTableauIndex: Int,
        in state: GameState
    ) -> Bool {
        guard selection.cards.first?.rank == .king else { return false }
        return isRedundantWholePileTransfer(
            selection: selection,
            destinationTableauIndex: destinationTableauIndex,
            in: state
        )
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

nonisolated private extension AutoMoveAdvisor {
    static func variantAllowsTableauPickup(of cards: [Card], in state: GameState) -> Bool {
        switch state.variant {
        case .klondike:
            return KlondikeAutoMoveAdvisor.allowsTableauPickup(of: cards, in: state)
        case .freecell:
            return FreeCellAutoMoveAdvisor.allowsTableauPickup(of: cards, in: state)
        case .yukon:
            return YukonAutoMoveAdvisor.allowsTableauPickup(of: cards, in: state)
        case .spider:
            return SpiderAutoMoveAdvisor.allowsTableauPickup(of: cards, in: state)
        case .fortyThieves:
            return FortyThievesAutoMoveAdvisor.allowsTableauPickup(of: cards, in: state)
        case .scorpion:
            return ScorpionAutoMoveAdvisor.allowsTableauPickup(of: cards, in: state)
        case .canfield:
            return CanfieldAutoMoveAdvisor.allowsTableauPickup(of: cards, in: state)
        case .pyramid, .tripeaks, .golf:
            // Unreachable: Pyramid, TriPeaks, and Golf dispatch wholesale
            // before the tableau flow.
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
        case .spider:
            return SpiderAutoMoveAdvisor.allowsTableauTransfer(
                selection: selection,
                destinationTableauIndex: destinationTableauIndex,
                in: state
            )
        case .fortyThieves:
            return FortyThievesAutoMoveAdvisor.allowsTableauTransfer(
                selection: selection,
                destinationTableauIndex: destinationTableauIndex,
                in: state
            )
        case .scorpion:
            return ScorpionAutoMoveAdvisor.allowsTableauTransfer(
                selection: selection,
                destinationTableauIndex: destinationTableauIndex,
                in: state
            )
        case .canfield:
            return CanfieldAutoMoveAdvisor.allowsTableauTransfer(
                selection: selection,
                destinationTableauIndex: destinationTableauIndex,
                in: state
            )
        case .pyramid, .tripeaks, .golf:
            // Unreachable: Pyramid, TriPeaks, and Golf dispatch wholesale
            // before the tableau flow.
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
        case .spider:
            return SpiderAutoMoveAdvisor.isRedundantEmptyColumnTransfer(
                selection: selection,
                destinationTableauIndex: destinationTableauIndex,
                in: state
            )
        case .fortyThieves:
            return FortyThievesAutoMoveAdvisor.isRedundantEmptyColumnTransfer(
                selection: selection,
                destinationTableauIndex: destinationTableauIndex,
                in: state
            )
        case .scorpion:
            return ScorpionAutoMoveAdvisor.isRedundantEmptyColumnTransfer(
                selection: selection,
                destinationTableauIndex: destinationTableauIndex,
                in: state
            )
        case .canfield:
            return CanfieldAutoMoveAdvisor.isRedundantEmptyColumnTransfer(
                selection: selection,
                destinationTableauIndex: destinationTableauIndex,
                in: state
            )
        case .pyramid, .tripeaks, .golf:
            // Unreachable: Pyramid, TriPeaks, and Golf dispatch wholesale
            // before the tableau flow.
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
        case .spider:
            SpiderAutoMoveAdvisor.appendAuxiliaryDestinations(
                for: selection,
                in: state,
                destinations: &destinations
            )
        case .fortyThieves:
            FortyThievesAutoMoveAdvisor.appendAuxiliaryDestinations(
                for: selection,
                in: state,
                destinations: &destinations
            )
        case .scorpion:
            ScorpionAutoMoveAdvisor.appendAuxiliaryDestinations(
                for: selection,
                in: state,
                destinations: &destinations
            )
        case .canfield:
            CanfieldAutoMoveAdvisor.appendAuxiliaryDestinations(
                for: selection,
                in: state,
                destinations: &destinations
            )
        case .pyramid, .tripeaks, .golf:
            // Unreachable: Pyramid, TriPeaks, and Golf dispatch wholesale
            // before the tableau flow.
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
        case .spider:
            SpiderAutoMoveAdvisor.applyTableauSourceRemovalEffects(on: &state, pileIndex: pileIndex)
        case .fortyThieves:
            FortyThievesAutoMoveAdvisor.applyTableauSourceRemovalEffects(on: &state, pileIndex: pileIndex)
        case .scorpion:
            ScorpionAutoMoveAdvisor.applyTableauSourceRemovalEffects(on: &state, pileIndex: pileIndex)
        case .canfield:
            CanfieldAutoMoveAdvisor.applyTableauSourceRemovalEffects(on: &state, pileIndex: pileIndex)
        case .pyramid, .tripeaks, .golf:
            // Unreachable: Pyramid, TriPeaks, and Golf dispatch wholesale
            // before the tableau flow.
            break
        }
    }

    /// Effects a landing triggers on the destination pile. Spider and Scorpion
    /// bank any run the landing completed; the other variants have none.
    static func applyVariantTableauDestinationEffects(on state: inout GameState, pileIndex: Int) {
        switch state.variant {
        case .klondike, .freecell, .yukon, .pyramid, .tripeaks, .golf, .fortyThieves, .canfield:
            break
        case .spider:
            SpiderAutoMoveAdvisor.applyTableauDestinationEffects(on: &state, pileIndex: pileIndex)
        case .scorpion:
            ScorpionAutoMoveAdvisor.applyTableauDestinationEffects(on: &state, pileIndex: pileIndex)
        }
    }
}
