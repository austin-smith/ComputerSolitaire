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

        case .freeCell:
            return evaluation.mobilityDelta >= 0 || hasImmediateForwardGain(evaluation)

        case .foundation(let sourceFoundationIndex):
            guard case .tableau(let destinationTableauIndex) = evaluation.destination else {
                return false
            }
            return isFoundationRollbackAdvisable(
                selection: selection,
                rollbackEvaluation: evaluation,
                sourceFoundationIndex: sourceFoundationIndex,
                destinationTableauIndex: destinationTableauIndex,
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

    static func isFoundationRollbackAdvisable(
        selection: Selection,
        rollbackEvaluation: MoveEvaluation,
        sourceFoundationIndex: Int,
        destinationTableauIndex: Int,
        in state: GameState,
        stockDrawCount: Int
    ) -> Bool {
        guard let movedCard = selection.cards.first else { return false }
        guard let rollbackState = simulatedState(
            afterMoving: selection,
            to: rollbackEvaluation.destination,
            in: state,
            stockDrawCount: stockDrawCount
        ) else {
            return false
        }

        let baseline = OpportunityBaseline(
            foundationCount: totalFoundationCards(in: state),
            emptyTableauCount: countEmptyTableauPiles(in: state),
            mobility: mobilityScore(in: state, stockDrawCount: stockDrawCount)
        )
        let rollbackPolicy = FoundationRollbackPolicy(
            movedCardID: movedCard.id,
            sourceFoundationIndex: sourceFoundationIndex,
            destinationTableauIndex: destinationTableauIndex
        )

        let bestBefore = bestImmediateForwardOpportunity(
            in: state,
            relativeTo: baseline,
            stockDrawCount: stockDrawCount,
            rollbackPolicy: rollbackPolicy,
            excludeMovedCardRefoundation: false
        )
        let bestAfter = bestImmediateForwardOpportunity(
            in: rollbackState,
            relativeTo: baseline,
            stockDrawCount: stockDrawCount,
            rollbackPolicy: rollbackPolicy,
            excludeMovedCardRefoundation: true
        )

        guard let bestAfter else { return false }
        guard let bestBefore else { return true }
        return ImmediateOpportunityRanking.isBetter(bestAfter, than: bestBefore)
    }

    static func bestImmediateForwardOpportunity(
        in state: GameState,
        relativeTo baseline: OpportunityBaseline,
        stockDrawCount: Int,
        rollbackPolicy: FoundationRollbackPolicy,
        excludeMovedCardRefoundation: Bool
    ) -> ImmediateOpportunity? {
        var opportunities: [ImmediateOpportunity] = []

        for followUpSelection in candidateSelections(in: state) {
            for followUpDestination in legalDestinations(for: followUpSelection, in: state) {
                if excludeMovedCardRefoundation && isImmediateMovedCardRefoundation(
                    selection: followUpSelection,
                    destination: followUpDestination,
                    rollbackPolicy: rollbackPolicy
                ) {
                    continue
                }
                guard followUpTouchesRollbackImpact(
                    selection: followUpSelection,
                    destination: followUpDestination,
                    rollbackPolicy: rollbackPolicy
                ) else {
                    continue
                }
                guard let nextState = simulatedState(
                    afterMoving: followUpSelection,
                    to: followUpDestination,
                    in: state,
                    stockDrawCount: stockDrawCount
                ) else {
                    continue
                }

                let resultingMobility = mobilityScore(in: nextState, stockDrawCount: stockDrawCount)
                let opportunity = ImmediateOpportunity(
                    selection: followUpSelection,
                    destination: followUpDestination,
                    revealsFaceDownCard: revealsFaceDownCard(selection: followUpSelection, in: state),
                    clearsSourcePile: clearsSourcePile(selection: followUpSelection, in: state),
                    netFoundationProgress: totalFoundationCards(in: nextState) - baseline.foundationCount,
                    mobilityDelta: resultingMobility - baseline.mobility,
                    netEmptyTableauGain: countEmptyTableauPiles(in: nextState) - baseline.emptyTableauCount,
                    destinationPriority: destinationPriority(for: followUpDestination, in: state),
                    resultingMobility: resultingMobility
                )
                guard opportunity.isForwardProgress else { continue }
                opportunities.append(opportunity)
            }
        }

        guard var bestOpportunity = opportunities.first else { return nil }
        for opportunity in opportunities.dropFirst() {
            if ImmediateOpportunityRanking.isBetter(opportunity, than: bestOpportunity) {
                bestOpportunity = opportunity
            }
        }
        return bestOpportunity
    }

    static func isImmediateMovedCardRefoundation(
        selection: Selection,
        destination: Destination,
        rollbackPolicy: FoundationRollbackPolicy
    ) -> Bool {
        guard case .tableau(let sourcePile, _) = selection.source,
              sourcePile == rollbackPolicy.destinationTableauIndex else {
            return false
        }
        guard selection.cards.count == 1,
              selection.cards[0].id == rollbackPolicy.movedCardID else {
            return false
        }
        guard case .foundation = destination else {
            return false
        }
        return true
    }

    static func followUpTouchesRollbackImpact(
        selection: Selection,
        destination: Destination,
        rollbackPolicy: FoundationRollbackPolicy
    ) -> Bool {
        if selection.cards.contains(where: { $0.id == rollbackPolicy.movedCardID }) {
            return true
        }

        switch selection.source {
        case .foundation(let pile):
            if pile == rollbackPolicy.sourceFoundationIndex {
                return true
            }
        case .freeCell:
            break
        case .tableau(let pile, _):
            if pile == rollbackPolicy.destinationTableauIndex {
                return true
            }
        case .waste:
            break
        }

        switch destination {
        case .foundation(let pile):
            return pile == rollbackPolicy.sourceFoundationIndex
        case .tableau(let pile):
            return pile == rollbackPolicy.destinationTableauIndex
        case .freeCell:
            return false
        }
    }

    static func hasImmediateForwardGain(_ evaluation: MoveEvaluation) -> Bool {
        evaluation.revealsFaceDownCard
            || evaluation.foundationProgressDelta > 0
            || evaluation.emptyTableauDelta > 0
    }

    struct OpportunityBaseline {
        let foundationCount: Int
        let emptyTableauCount: Int
        let mobility: Int
    }

    struct FoundationRollbackPolicy {
        let movedCardID: UUID
        let sourceFoundationIndex: Int
        let destinationTableauIndex: Int
    }

    struct ImmediateOpportunity {
        let selection: Selection
        let destination: Destination
        let revealsFaceDownCard: Bool
        let clearsSourcePile: Bool
        let netFoundationProgress: Int
        let mobilityDelta: Int
        let netEmptyTableauGain: Int
        let destinationPriority: Int
        let resultingMobility: Int

        var isForwardProgress: Bool {
            revealsFaceDownCard || netFoundationProgress > 0 || netEmptyTableauGain > 0
        }
    }

    enum ImmediateOpportunityRanking {
        static func isBetter(_ lhs: ImmediateOpportunity, than rhs: ImmediateOpportunity) -> Bool {
            if lhs.revealsFaceDownCard != rhs.revealsFaceDownCard {
                return lhs.revealsFaceDownCard && !rhs.revealsFaceDownCard
            }
            if lhs.netFoundationProgress != rhs.netFoundationProgress {
                return lhs.netFoundationProgress > rhs.netFoundationProgress
            }
            if lhs.mobilityDelta != rhs.mobilityDelta {
                return lhs.mobilityDelta > rhs.mobilityDelta
            }
            if lhs.netEmptyTableauGain != rhs.netEmptyTableauGain {
                return lhs.netEmptyTableauGain > rhs.netEmptyTableauGain
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
            return tieBreakKey(lhs) < tieBreakKey(rhs)
        }

        private static func tieBreakKey(_ opportunity: ImmediateOpportunity) -> String {
            let sourceKey = sourceSortKey(opportunity.selection.source)
            let destinationKey = destinationSortKey(opportunity.destination)
            let cardIDs = opportunity.selection.cards
                .map(\.id)
                .map(\.uuidString)
                .joined(separator: ",")
            return "\(sourceKey)|\(destinationKey)|\(cardIDs)"
        }

        private static func sourceSortKey(_ source: Selection.Source) -> Int {
            switch source {
            case .waste:
                return 0
            case .freeCell(let slot):
                return 50 + slot
            case .foundation(let pile):
                return 100 + pile
            case .tableau(let pile, let index):
                return 1000 + (pile * 100) + index
            }
        }

        private static func destinationSortKey(_ destination: Destination) -> Int {
            switch destination {
            case .foundation(let index):
                return index
            case .tableau(let index):
                return 100 + index
            case .freeCell(let index):
                return 200 + index
            }
        }
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
        switch state.variant {
        case .klondike:
            return KlondikeAutoMoveAdvisor.destinationPriority(for: destination, in: state)
        case .freecell:
            return FreeCellAutoMoveAdvisor.destinationPriority(for: destination, in: state)
        }
    }

    static func revealsFaceDownCard(selection: Selection, in state: GameState) -> Bool {
        switch state.variant {
        case .klondike:
            return KlondikeAutoMoveAdvisor.revealsFaceDownCard(selection: selection, in: state)
        case .freecell:
            return false
        }
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
        isVariantRedundantEmptyColumnTransfer(
            selection: selection,
            destinationTableauIndex: destinationTableauIndex,
            in: state
        )
    }

    static func mobilityScore(in state: GameState, stockDrawCount: Int) -> Int {
        var score = 0

        for selection in candidateSelections(in: state) {
            score += legalDestinations(for: selection, in: state).count
        }

        return score
    }

    static func isValidTableauSequence(_ cards: [Card]) -> Bool {
        GameRules.isValidDescendingAlternatingSequence(cards)
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
        case .freeCell(let slot):
            nextState.freeCells[slot] = nil
        case .foundation(let pile):
            _ = nextState.foundations[pile].popLast()
        case .tableau(let pile, let index):
            nextState.tableau[pile].removeSubrange(index..<nextState.tableau[pile].count)
            applyVariantTableauSourceRemovalEffects(on: &nextState, pileIndex: pile)
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
