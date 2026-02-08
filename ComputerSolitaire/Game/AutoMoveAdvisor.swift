import Foundation

enum AutoMoveAdvisor {
    static func bestDestination(
        for selection: Selection,
        in state: GameState,
        stockDrawCount: Int
    ) -> Destination? {
        let destinations = legalDestinations(for: selection, in: state)
        guard !destinations.isEmpty else { return nil }

        let baselineMobility = mobilityScore(in: state, stockDrawCount: stockDrawCount)
        var bestCandidate: CandidateEvaluation?

        for destination in destinations {
            guard let nextState = simulatedState(
                afterMoving: selection,
                to: destination,
                in: state,
                stockDrawCount: stockDrawCount
            ) else {
                continue
            }

            let nextMobility = mobilityScore(in: nextState, stockDrawCount: stockDrawCount)
            let candidate = CandidateEvaluation(
                destination: destination,
                revealsFaceDownCard: revealsFaceDownCard(selection: selection, in: state),
                clearsSourcePile: clearsSourcePile(selection: selection, in: state),
                mobilityDelta: nextMobility - baselineMobility,
                resultingMobility: nextMobility,
                destinationPriority: destinationPriority(for: destination, in: state)
            )

            if let currentBest = bestCandidate {
                if isBetter(candidate, than: currentBest) {
                    bestCandidate = candidate
                }
            } else {
                bestCandidate = candidate
            }
        }

        return bestCandidate?.destination
    }

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
            if GameRules.canMoveToTableau(card: movingCard, destinationPile: tableauPile) {
                destinations.append(.tableau(tableauIndex))
            }
        }

        return destinations
    }
}

private extension AutoMoveAdvisor {
    struct CandidateEvaluation {
        let destination: Destination
        let revealsFaceDownCard: Bool
        let clearsSourcePile: Bool
        let mobilityDelta: Int
        let resultingMobility: Int
        let destinationPriority: Int
    }

    // Priority order:
    // 1) reveal hidden cards, 2) improve mobility, 3) open tableau columns,
    // 4) destination preference, 5) resulting mobility, 6) deterministic tiebreak.
    static func isBetter(_ lhs: CandidateEvaluation, than rhs: CandidateEvaluation) -> Bool {
        if lhs.revealsFaceDownCard != rhs.revealsFaceDownCard {
            return lhs.revealsFaceDownCard && !rhs.revealsFaceDownCard
        }
        if lhs.mobilityDelta != rhs.mobilityDelta {
            return lhs.mobilityDelta > rhs.mobilityDelta
        }
        if lhs.clearsSourcePile != rhs.clearsSourcePile {
            return lhs.clearsSourcePile && !rhs.clearsSourcePile
        }
        if lhs.destinationPriority != rhs.destinationPriority {
            return lhs.destinationPriority > rhs.destinationPriority
        }
        if lhs.resultingMobility != rhs.resultingMobility {
            return lhs.resultingMobility > rhs.resultingMobility
        }
        return destinationSortKey(lhs.destination) < destinationSortKey(rhs.destination)
    }

    static func destinationPriority(for destination: Destination, in state: GameState) -> Int {
        switch destination {
        case .tableau(let index):
            return state.tableau[index].isEmpty ? 0 : 2
        case .foundation:
            return 1
        }
    }

    static func destinationSortKey(_ destination: Destination) -> Int {
        switch destination {
        case .foundation(let index):
            return index
        case .tableau(let index):
            return 100 + index
        }
    }

    static func revealsFaceDownCard(selection: Selection, in state: GameState) -> Bool {
        guard case .tableau(let pile, let index) = selection.source else { return false }
        guard index > 0 else { return false }
        return !state.tableau[pile][index - 1].isFaceUp
    }

    static func clearsSourcePile(selection: Selection, in state: GameState) -> Bool {
        guard case .tableau(let pile, let index) = selection.source else { return false }
        let sourcePile = state.tableau[pile]
        return index == 0 && !sourcePile.isEmpty
    }

    static func mobilityScore(in state: GameState, stockDrawCount: Int) -> Int {
        var score = 0

        if let topWasteCard = state.waste.last, state.wasteDrawCount > 0 {
            let wasteSelection = Selection(source: .waste, cards: [topWasteCard])
            score += legalDestinations(for: wasteSelection, in: state).count
        }

        for pileIndex in state.tableau.indices {
            let pile = state.tableau[pileIndex]
            for cardIndex in pile.indices where pile[cardIndex].isFaceUp {
                let cards = Array(pile[cardIndex...])
                guard isValidTableauSequence(cards) else { continue }
                let selection = Selection(source: .tableau(pile: pileIndex, index: cardIndex), cards: cards)
                score += legalDestinations(for: selection, in: state).count
            }
        }

        for foundationIndex in state.foundations.indices {
            guard let topCard = state.foundations[foundationIndex].last else { continue }
            let selection = Selection(source: .foundation(pile: foundationIndex), cards: [topCard])
            score += legalDestinations(for: selection, in: state).count
        }

        return score
    }

    static func isValidTableauSequence(_ cards: [Card]) -> Bool {
        guard cards.count > 1 else { return true }
        for index in 0..<(cards.count - 1) {
            let upper = cards[index]
            let lower = cards[index + 1]
            guard upper.suit.isRed != lower.suit.isRed else { return false }
            guard upper.rank.rawValue == lower.rank.rawValue + 1 else { return false }
        }
        return true
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

        switch selection.source {
        case .waste:
            _ = nextState.waste.popLast()
            if stockDrawCount == DrawMode.one.rawValue {
                nextState.wasteDrawCount = min(1, nextState.waste.count)
            } else {
                nextState.wasteDrawCount = max(0, nextState.wasteDrawCount - 1)
            }
        case .foundation(let pile):
            _ = nextState.foundations[pile].popLast()
        case .tableau(let pile, let index):
            nextState.tableau[pile].removeSubrange(index..<nextState.tableau[pile].count)
            if let topIndex = nextState.tableau[pile].indices.last,
               !nextState.tableau[pile][topIndex].isFaceUp {
                nextState.tableau[pile][topIndex].isFaceUp = true
            }
        }

        switch destination {
        case .foundation(let index):
            guard selection.cards.count == 1, let card = selection.cards.first else { return nil }
            nextState.foundations[index].append(card)
        case .tableau(let index):
            nextState.tableau[index].append(contentsOf: selection.cards)
        }

        return nextState
    }

    static func selectionMatchesState(_ selection: Selection, in state: GameState) -> Bool {
        guard !selection.cards.isEmpty else { return false }

        switch selection.source {
        case .waste:
            guard selection.cards.count == 1, let topWaste = state.waste.last else { return false }
            return topWaste.id == selection.cards[0].id

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
        }
    }
}
