import Foundation

enum ScorpionAutoMoveAdvisor {
    static func allowsTableauPickup(of cards: [Card], in state: GameState) -> Bool {
        // Scorpion moves groups Yukon-style: any face-up card can be picked up
        // together with every card above it, regardless of whether they form a
        // sequence. Only the picked card must connect at the destination.
        true
    }

    static func allowsTableauTransfer(
        selection: Selection,
        destinationTableauIndex: Int,
        in state: GameState
    ) -> Bool {
        true
    }

    static func isRedundantEmptyColumnTransfer(
        selection: Selection,
        destinationTableauIndex: Int,
        in state: GameState
    ) -> Bool {
        guard AutoMoveAdvisor.isRedundantWholePileKingTransfer(
            selection: selection,
            destinationTableauIndex: destinationTableauIndex,
            in: state
        ) else {
            return false
        }
        // While the stock is undealt, each of the first `stock.count` columns
        // awaits its own specific dealt card, so relocating a whole king pile
        // into or out of one changes the position the deal produces — vacating
        // a target column lands its card in the open, filling one buries the
        // card on the pile. Only transfers between the interchangeable columns
        // are no-ops (all of them, once the stock is spent). Mirrors the
        // interchangeability classes in `ScorpionPlanner.stateHash`.
        guard case .tableau(let sourcePile, _) = selection.source else { return false }
        let positionalCount = state.stock.count
        return sourcePile >= positionalCount && destinationTableauIndex >= positionalCount
    }

    static func appendAuxiliaryDestinations(
        for selection: Selection,
        in state: GameState,
        destinations: inout [Destination]
    ) {
        // Scorpion has no auxiliary destination type; completed runs bank
        // themselves.
    }

    static func applyTableauSourceRemovalEffects(on state: inout GameState, pileIndex: Int) {
        AutoMoveAdvisor.flipExposedFaceDownTop(on: &state, pileIndex: pileIndex)
    }

    static func applyTableauDestinationEffects(on state: inout GameState, pileIndex: Int) {
        ScorpionGameRules.resolveCompletedRuns(in: &state)
    }
}
