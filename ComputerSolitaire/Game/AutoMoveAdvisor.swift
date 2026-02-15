import Foundation

enum AutoMoveAdvisor {
    struct AutoFinishMove {
        let selection: Selection
        let destination: Destination
    }

    static func bestDestination(
        for selection: Selection,
        in state: GameState,
        stockDrawCount: Int
    ) -> Destination? {
        let destinations = legalDestinations(for: selection, in: state)
        guard !destinations.isEmpty else { return nil }

        let baselineMobility = mobilityScore(in: state, stockDrawCount: stockDrawCount)
        let baselineFoundationCount = totalFoundationCards(in: state)
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
            let nextFoundationCount = totalFoundationCards(in: nextState)
            let candidate = CandidateEvaluation(
                destination: destination,
                revealsFaceDownCard: revealsFaceDownCard(selection: selection, in: state),
                clearsSourcePile: clearsSourcePile(selection: selection, in: state),
                foundationProgressDelta: nextFoundationCount - baselineFoundationCount,
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

    static func canAutoFinish(in state: GameState) -> Bool {
        guard isAutoFinishCandidateState(state) else { return false }
        var simulatedState = state
        let maxSteps = simulatedState.tableau.reduce(0) { partialResult, pile in
            partialResult + pile.count
        }

        for _ in 0..<maxSteps {
            if isWin(simulatedState) {
                return true
            }
            guard let move = nextAutoFinishMoveInternal(in: simulatedState),
                  applyAutoFinishMove(move, in: &simulatedState) else {
                return false
            }
        }

        return isWin(simulatedState)
    }

    static func nextAutoFinishMove(in state: GameState) -> AutoFinishMove? {
        guard isAutoFinishCandidateState(state) else { return nil }
        return nextAutoFinishMoveInternal(in: state)
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
    static func isAutoFinishCandidateState(_ state: GameState) -> Bool {
        guard !isWin(state) else { return false }
        guard state.stock.isEmpty, state.waste.isEmpty else { return false }
        return !state.tableau.joined().contains(where: { !$0.isFaceUp })
    }

    static func isWin(_ state: GameState) -> Bool {
        state.foundations.allSatisfy { $0.count == Rank.allCases.count }
    }

    static func nextAutoFinishMoveInternal(in state: GameState) -> AutoFinishMove? {
        var candidates: [(move: AutoFinishMove, rankValue: Int, tableauPile: Int, foundationPile: Int)] = []

        for pileIndex in state.tableau.indices {
            guard let topIndex = state.tableau[pileIndex].indices.last else { continue }
            let card = state.tableau[pileIndex][topIndex]
            guard card.isFaceUp else { continue }

            for foundationIndex in state.foundations.indices {
                let foundation = state.foundations[foundationIndex]
                guard GameRules.canMoveToFoundation(card: card, foundation: foundation) else { continue }

                let selection = Selection(
                    source: .tableau(pile: pileIndex, index: topIndex),
                    cards: [card]
                )
                candidates.append(
                    (
                        move: AutoFinishMove(selection: selection, destination: .foundation(foundationIndex)),
                        rankValue: card.rank.rawValue,
                        tableauPile: pileIndex,
                        foundationPile: foundationIndex
                    )
                )
            }
        }

        let sorted = candidates.sorted { lhs, rhs in
            if lhs.rankValue != rhs.rankValue {
                return lhs.rankValue < rhs.rankValue
            }
            if lhs.tableauPile != rhs.tableauPile {
                return lhs.tableauPile < rhs.tableauPile
            }
            return lhs.foundationPile < rhs.foundationPile
        }
        return sorted.first?.move
    }

    @discardableResult
    static func applyAutoFinishMove(_ move: AutoFinishMove, in state: inout GameState) -> Bool {
        guard case .tableau(let pileIndex, let cardIndex) = move.selection.source,
              case .foundation(let foundationIndex) = move.destination else {
            return false
        }
        guard state.tableau.indices.contains(pileIndex),
              state.foundations.indices.contains(foundationIndex),
              state.tableau[pileIndex].indices.contains(cardIndex),
              cardIndex == state.tableau[pileIndex].count - 1 else {
            return false
        }
        guard let movingCard = state.tableau[pileIndex].last else { return false }
        guard move.selection.cards.count == 1,
              move.selection.cards[0].id == movingCard.id else {
            return false
        }
        guard GameRules.canMoveToFoundation(card: movingCard, foundation: state.foundations[foundationIndex]) else {
            return false
        }

        _ = state.tableau[pileIndex].popLast()
        if let newTopIndex = state.tableau[pileIndex].indices.last,
           !state.tableau[pileIndex][newTopIndex].isFaceUp {
            state.tableau[pileIndex][newTopIndex].isFaceUp = true
        }
        state.foundations[foundationIndex].append(movingCard)
        return true
    }

    struct CandidateEvaluation {
        let destination: Destination
        let revealsFaceDownCard: Bool
        let clearsSourcePile: Bool
        let foundationProgressDelta: Int
        let mobilityDelta: Int
        let resultingMobility: Int
        let destinationPriority: Int
    }

    // Priority order:
    // 1) reveal hidden cards, 2) increase foundation progress,
    // 3) improve mobility, 4) open tableau columns, 5) destination preference,
    // 6) resulting mobility, 7) deterministic tiebreak.
    static func isBetter(_ lhs: CandidateEvaluation, than rhs: CandidateEvaluation) -> Bool {
        if lhs.revealsFaceDownCard != rhs.revealsFaceDownCard {
            return lhs.revealsFaceDownCard && !rhs.revealsFaceDownCard
        }
        if lhs.foundationProgressDelta != rhs.foundationProgressDelta {
            return lhs.foundationProgressDelta > rhs.foundationProgressDelta
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

    static func totalFoundationCards(in state: GameState) -> Int {
        state.foundations.reduce(0) { partialResult, foundation in
            partialResult + foundation.count
        }
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
