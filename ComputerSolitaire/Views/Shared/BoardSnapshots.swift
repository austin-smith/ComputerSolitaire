import Foundation

// Value projections of the session's observable surface, captured once per
// ContentView body pass. Board views render from these slices instead of
// reading the observable session, so a move that leaves a view's slice
// unchanged lets the view prune — its manual `==` sees equal inputs. CardView
// established the pattern; the pile and row views follow it.

/// The selection and drag flags every card-bearing view renders from.
nonisolated struct SelectionSnapshot: Equatable {
    let isDragging: Bool
    /// The full source, not a reduced flag — TableauPileView's highlight
    /// placement needs the `.tableau(pile:index:)` payload.
    let source: Selection.Source?
    let selectedCardIDs: Set<UUID>

    init(selection: Selection?, isDragging: Bool) {
        self.isDragging = isDragging
        self.source = selection?.source
        self.selectedCardIDs = Set(selection?.cards.map(\.id) ?? [])
    }

    func isSelected(_ card: Card) -> Bool {
        selectedCardIDs.contains(card.id)
    }

    /// The selection source while a drag is in flight; nil for tap selections.
    var dragSource: Selection.Source? {
        isDragging ? source : nil
    }
}

/// What an empty foundation renders beneath its placeholder ring.
nonisolated enum FoundationPlaceholder: Equatable {
    /// Foundations that build up from the Ace — every variant but Canfield.
    case ace
    /// Canfield's dealt base rank.
    case baseRank(Rank)
    /// Canfield before the base card exists; renders nothing.
    case blank
}

/// Everything the top row (stock, waste, foundations, discard) renders from.
nonisolated struct TopRowSnapshot: Equatable {
    let variant: GameVariant
    let foundations: [[Card]]
    let foundationPlaceholder: FoundationPlaceholder
    let stockCount: Int
    let canInteractWithStock: Bool
    /// Pyramid's remaining waste recycles; nil for every other variant.
    let stockRecyclesRemaining: Int?
    let visibleWasteCards: [Card]
    /// Pyramid's discard pile; empty for every other variant.
    let discard: [Card]
}

extension SolitaireViewModel {
    var selectionSnapshot: SelectionSnapshot {
        SelectionSnapshot(selection: selection, isDragging: isDragging)
    }

    var topRowSnapshot: TopRowSnapshot {
        TopRowSnapshot(
            variant: state.variant,
            foundations: state.foundations,
            foundationPlaceholder: foundationPlaceholder,
            stockCount: state.stock.count,
            canInteractWithStock: canInteractWithStock,
            stockRecyclesRemaining: state.variant == .pyramid ? pyramidWasteRecyclesRemaining : nil,
            visibleWasteCards: visibleWasteCards(),
            discard: state.discard
        )
    }

    private var foundationPlaceholder: FoundationPlaceholder {
        guard state.variant == .canfield else { return .ace }
        guard let baseRank = CanfieldGameRules.baseRank(in: state) else { return .blank }
        return .baseRank(baseRank)
    }
}
