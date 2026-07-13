import Foundation

enum PyramidGameRules {
    /// Two cards pair when their ranks sum to this; a King reaches it alone.
    static let pairSum = 13
    /// The waste may be recycled into the stock this many times (three total passes).
    static let maxWasteRecycles = 2

    static func isPair(_ first: Card, _ second: Card) -> Bool {
        first.rank.rawValue + second.rank.rawValue == pairSum
    }

    static func isKing(_ card: Card) -> Bool {
        card.rank == .king
    }

    /// The cover-pair rule: `child` directly covers `parent`, is `parent`'s only
    /// remaining cover, is itself exposed, and the two ranks sum to 13 — so both
    /// may be removed together in one move.
    static func isCoverPair(parent: Int, child: Int, in pyramid: [Card?]) -> Bool {
        guard let parentCard = pyramid[parent], let childCard = pyramid[child] else { return false }
        guard isPair(parentCard, childCard) else { return false }
        guard let covering = PyramidGeometry.coveringIndices(of: parent) else { return false }
        guard child == covering.left || child == covering.right else { return false }
        let otherCover = child == covering.left ? covering.right : covering.left
        guard pyramid[otherCover] == nil else { return false }
        return PyramidGeometry.isExposed(child, in: pyramid)
    }

    /// A slot the player may pick up: exposed, or a cover-pair parent (its sole
    /// remaining cover is its exposed rank-13 partner).
    static func isSelectable(index: Int, in pyramid: [Card?]) -> Bool {
        guard pyramid.indices.contains(index), pyramid[index] != nil else { return false }
        if PyramidGeometry.isExposed(index, in: pyramid) { return true }
        guard let covering = PyramidGeometry.coveringIndices(of: index) else { return false }
        return isCoverPair(parent: index, child: covering.left, in: pyramid)
            || isCoverPair(parent: index, child: covering.right, in: pyramid)
    }

    static func canRemovePair(_ first: Int, _ second: Int, in pyramid: [Card?]) -> Bool {
        guard first != second else { return false }
        guard pyramid.indices.contains(first), pyramid.indices.contains(second) else { return false }
        guard let firstCard = pyramid[first], let secondCard = pyramid[second] else { return false }
        guard isPair(firstCard, secondCard) else { return false }
        if PyramidGeometry.isExposed(first, in: pyramid),
           PyramidGeometry.isExposed(second, in: pyramid) {
            return true
        }
        return isCoverPair(parent: first, child: second, in: pyramid)
            || isCoverPair(parent: second, child: first, in: pyramid)
    }

    static func canRemovePairWithWasteTop(pyramidIndex: Int, in state: GameState) -> Bool {
        guard state.pyramid.indices.contains(pyramidIndex),
              let pyramidCard = state.pyramid[pyramidIndex],
              let wasteTop = state.waste.last else { return false }
        guard PyramidGeometry.isExposed(pyramidIndex, in: state.pyramid) else { return false }
        return isPair(pyramidCard, wasteTop)
    }

    static func canRemoveKing(selection: Selection, in state: GameState) -> Bool {
        guard selection.cards.count == 1, let card = selection.cards.first else { return false }
        guard isKing(card) else { return false }
        switch selection.source {
        case .pyramid(let index):
            return PyramidGeometry.isExposed(index, in: state.pyramid)
        case .waste:
            return state.waste.last?.id == card.id
        case .foundation, .freeCell, .tableau, .triPeaks:
            return false
        }
    }

    static func canRecycleWaste(in state: GameState) -> Bool {
        state.stock.isEmpty
            && !state.waste.isEmpty
            && state.wasteRecyclesUsed < maxWasteRecycles
    }

    /// Single source of truth for applying a Pyramid move; used by the session and
    /// the advisor so their outcomes can never drift. Removed cards land on the
    /// discard in selection-first order. Returns nil for illegal moves.
    static func stateByApplying(
        selection: Selection,
        destination: Destination,
        to state: GameState
    ) -> GameState? {
        guard state.variant == .pyramid else { return nil }
        guard selection.cards.count == 1, let selectedCard = selection.cards.first else { return nil }

        var nextState = state

        switch (selection.source, destination) {
        case (.pyramid(let sourceIndex), .pyramid(let partnerIndex)):
            guard canRemovePair(sourceIndex, partnerIndex, in: state.pyramid) else { return nil }
            guard state.pyramid[sourceIndex]?.id == selectedCard.id else { return nil }
            guard let partnerCard = state.pyramid[partnerIndex] else { return nil }
            nextState.pyramid[sourceIndex] = nil
            nextState.pyramid[partnerIndex] = nil
            nextState.discard.append(contentsOf: [selectedCard, partnerCard])

        case (.pyramid(let sourceIndex), .waste):
            guard canRemovePairWithWasteTop(pyramidIndex: sourceIndex, in: state) else { return nil }
            guard state.pyramid[sourceIndex]?.id == selectedCard.id else { return nil }
            guard let wasteTop = nextState.waste.popLast() else { return nil }
            nextState.pyramid[sourceIndex] = nil
            nextState.discard.append(contentsOf: [selectedCard, wasteTop])

        case (.waste, .pyramid(let partnerIndex)):
            guard canRemovePairWithWasteTop(pyramidIndex: partnerIndex, in: state) else { return nil }
            guard state.waste.last?.id == selectedCard.id else { return nil }
            guard let partnerCard = state.pyramid[partnerIndex] else { return nil }
            _ = nextState.waste.popLast()
            nextState.pyramid[partnerIndex] = nil
            nextState.discard.append(contentsOf: [selectedCard, partnerCard])

        case (.pyramid(let sourceIndex), .discard):
            guard canRemoveKing(selection: selection, in: state) else { return nil }
            guard state.pyramid[sourceIndex]?.id == selectedCard.id else { return nil }
            nextState.pyramid[sourceIndex] = nil
            nextState.discard.append(selectedCard)

        case (.waste, .discard):
            guard canRemoveKing(selection: selection, in: state) else { return nil }
            _ = nextState.waste.popLast()
            nextState.discard.append(selectedCard)

        default:
            return nil
        }

        // The single visible waste card follows the new top.
        nextState.wasteDrawCount = min(1, nextState.waste.count)
        return nextState
    }
}
