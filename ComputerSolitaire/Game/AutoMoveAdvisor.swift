import Foundation

enum AutoMoveAdvisor {
    static func bestDestination(
        for selection: Selection,
        in state: GameState,
        stockDrawCount: Int
    ) -> Destination? {
        bestMoveEvaluation(
            for: selection,
            in: state,
            stockDrawCount: stockDrawCount
        )?.destination
    }

    static func bestAdvisableDestination(
        for selection: Selection,
        in state: GameState,
        stockDrawCount: Int
    ) -> Destination? {
        bestAdvisableMoveEvaluation(
            for: selection,
            in: state,
            stockDrawCount: stockDrawCount
        )?.destination
    }

    static func bestMoveEvaluation(
        for selection: Selection,
        in state: GameState,
        stockDrawCount: Int
    ) -> MoveEvaluation? {
        let baselineMobility = mobilityScore(in: state, stockDrawCount: stockDrawCount)
        let baselineFoundationCount = totalFoundationCards(in: state)
        let baselineEmptyTableauCount = countEmptyTableauPiles(in: state)
        return bestEvaluation(
            for: selection,
            in: state,
            stockDrawCount: stockDrawCount,
            baselineMobility: baselineMobility,
            baselineFoundationCount: baselineFoundationCount,
            baselineEmptyTableauCount: baselineEmptyTableauCount,
            requireAdvisable: false
        )
    }

    static func bestAdvisableMoveEvaluation(
        for selection: Selection,
        in state: GameState,
        stockDrawCount: Int
    ) -> MoveEvaluation? {
        let baselineMobility = mobilityScore(in: state, stockDrawCount: stockDrawCount)
        let baselineFoundationCount = totalFoundationCards(in: state)
        let baselineEmptyTableauCount = countEmptyTableauPiles(in: state)
        return bestEvaluation(
            for: selection,
            in: state,
            stockDrawCount: stockDrawCount,
            baselineMobility: baselineMobility,
            baselineFoundationCount: baselineFoundationCount,
            baselineEmptyTableauCount: baselineEmptyTableauCount,
            requireAdvisable: true
        )
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
                if isRedundantEmptyColumnTransfer(
                    selection: selection,
                    destinationTableauIndex: tableauIndex,
                    in: state
                ) {
                    continue
                }
                destinations.append(.tableau(tableauIndex))
            }
        }

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
}

private extension AutoMoveAdvisor {
    static func bestEvaluation(
        for selection: Selection,
        in state: GameState,
        stockDrawCount: Int,
        baselineMobility: Int,
        baselineFoundationCount: Int,
        baselineEmptyTableauCount: Int,
        requireAdvisable: Bool
    ) -> MoveEvaluation? {
        let evaluations = allEvaluations(
            for: selection,
            in: state,
            stockDrawCount: stockDrawCount,
            baselineMobility: baselineMobility,
            baselineFoundationCount: baselineFoundationCount,
            baselineEmptyTableauCount: baselineEmptyTableauCount
        )
        let filteredEvaluations = requireAdvisable
            ? evaluations.filter {
                isAdvisableMove(
                    selection: selection,
                    evaluation: $0,
                    in: state,
                    stockDrawCount: stockDrawCount
                )
            }
            : evaluations

        guard var bestEvaluation = filteredEvaluations.first else { return nil }
        for evaluation in filteredEvaluations.dropFirst() {
            if MoveEvaluationRanking.isBetter(evaluation, than: bestEvaluation) {
                bestEvaluation = evaluation
            }
        }
        return bestEvaluation
    }

    static func allEvaluations(
        for selection: Selection,
        in state: GameState,
        stockDrawCount: Int,
        baselineMobility: Int,
        baselineFoundationCount: Int,
        baselineEmptyTableauCount: Int
    ) -> [MoveEvaluation] {
        let destinations = legalDestinations(for: selection, in: state)
        guard !destinations.isEmpty else { return [] }

        var evaluations: [MoveEvaluation] = []
        evaluations.reserveCapacity(destinations.count)

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
            let nextEmptyTableauCount = countEmptyTableauPiles(in: nextState)
            let evaluation = MoveEvaluation(
                destination: destination,
                revealsFaceDownCard: revealsFaceDownCard(selection: selection, in: state),
                clearsSourcePile: clearsSourcePile(selection: selection, in: state),
                emptyTableauDelta: nextEmptyTableauCount - baselineEmptyTableauCount,
                foundationProgressDelta: nextFoundationCount - baselineFoundationCount,
                mobilityDelta: nextMobility - baselineMobility,
                resultingMobility: nextMobility,
                destinationPriority: destinationPriority(for: destination, in: state)
            )
            evaluations.append(evaluation)
        }

        return evaluations
    }

    static func isAdvisableMove(
        selection: Selection,
        evaluation: MoveEvaluation,
        in state: GameState,
        stockDrawCount: Int
    ) -> Bool {
        if case .foundation = selection.source,
           case .foundation = evaluation.destination {
            return false
        }

        if hasImmediateForwardGain(evaluation) {
            return true
        }

        switch selection.source {
        case .waste:
            // Waste moves are resource-limited and usually unblock future draws.
            return true

        case .foundation(let sourceFoundationIndex):
            guard case .tableau(let destinationTableauIndex) = evaluation.destination else {
                return false
            }
            guard let movedCard = selection.cards.first else { return false }
            return foundationMoveUnlocksForwardFollowUp(
                movedCardID: movedCard.id,
                sourceFoundationIndex: sourceFoundationIndex,
                destinationTableauIndex: destinationTableauIndex,
                afterApplying: selection,
                using: evaluation.destination,
                in: state,
                stockDrawCount: stockDrawCount
            )

        case .tableau:
            break
        }

        if case .tableau = evaluation.destination {
            // Avoid neutral tableau reshuffles unless they strongly improve options.
            return evaluation.mobilityDelta > 1
        }

        return evaluation.mobilityDelta > 0
    }

    static func foundationMoveUnlocksForwardFollowUp(
        movedCardID: UUID,
        sourceFoundationIndex: Int,
        destinationTableauIndex: Int,
        afterApplying selection: Selection,
        using destination: Destination,
        in state: GameState,
        stockDrawCount: Int
    ) -> Bool {
        guard let nextState = simulatedState(
            afterMoving: selection,
            to: destination,
            in: state,
            stockDrawCount: stockDrawCount
        ) else {
            return false
        }

        let baselineMobility = mobilityScore(in: nextState, stockDrawCount: stockDrawCount)
        let baselineFoundationCount = totalFoundationCards(in: nextState)
        let baselineEmptyTableauCount = countEmptyTableauPiles(in: nextState)

        for followUpSelection in candidateSelections(in: nextState) {
            let followUpEvaluations = allEvaluations(
                for: followUpSelection,
                in: nextState,
                stockDrawCount: stockDrawCount,
                baselineMobility: baselineMobility,
                baselineFoundationCount: baselineFoundationCount,
                baselineEmptyTableauCount: baselineEmptyTableauCount
            )

            for followUpEvaluation in followUpEvaluations {
                if isImmediateFoundationReversal(
                    followUpSelection: followUpSelection,
                    followUpEvaluation: followUpEvaluation,
                    movedCardID: movedCardID,
                    sourceFoundationIndex: sourceFoundationIndex,
                    destinationTableauIndex: destinationTableauIndex
                ) {
                    continue
                }

                if hasImmediateForwardGain(followUpEvaluation) {
                    return true
                }
            }
        }

        return false
    }

    static func isImmediateFoundationReversal(
        followUpSelection: Selection,
        followUpEvaluation: MoveEvaluation,
        movedCardID: UUID,
        sourceFoundationIndex: Int,
        destinationTableauIndex: Int
    ) -> Bool {
        guard case .tableau(let sourcePile, _) = followUpSelection.source,
              sourcePile == destinationTableauIndex else {
            return false
        }
        guard followUpSelection.cards.count == 1,
              followUpSelection.cards[0].id == movedCardID else {
            return false
        }
        guard case .foundation(let destinationFoundationIndex) = followUpEvaluation.destination else {
            return false
        }
        return destinationFoundationIndex == sourceFoundationIndex
    }

    static func hasImmediateForwardGain(_ evaluation: MoveEvaluation) -> Bool {
        evaluation.revealsFaceDownCard
            || evaluation.foundationProgressDelta > 0
            || evaluation.emptyTableauDelta > 0
    }

    static func totalFoundationCards(in state: GameState) -> Int {
        state.foundations.reduce(0) { partialResult, foundation in
            partialResult + foundation.count
        }
    }

    static func countEmptyTableauPiles(in state: GameState) -> Int {
        state.tableau.reduce(0) { partialResult, pile in
            partialResult + (pile.isEmpty ? 1 : 0)
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

    static func isRedundantEmptyColumnTransfer(
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

        // Moving an entire king-led tableau stack to another empty column is a no-op
        // for advisor quality purposes (manual play can still do this).
        return movingCard.rank == .king
    }

    static func mobilityScore(in state: GameState, stockDrawCount: Int) -> Int {
        var score = 0

        for selection in candidateSelections(in: state) {
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
