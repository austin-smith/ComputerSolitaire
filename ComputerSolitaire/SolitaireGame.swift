import Foundation
import Observation

enum Suit: CaseIterable {
    case spades
    case hearts
    case diamonds
    case clubs

    var isRed: Bool {
        switch self {
        case .hearts, .diamonds:
            return true
        case .spades, .clubs:
            return false
        }
    }

    var symbolName: String {
        switch self {
        case .spades:
            return "suit.spade.fill"
        case .hearts:
            return "suit.heart.fill"
        case .diamonds:
            return "suit.diamond.fill"
        case .clubs:
            return "suit.club.fill"
        }
    }
}

enum Rank: Int, CaseIterable, Comparable {
    case ace = 1
    case two = 2
    case three = 3
    case four = 4
    case five = 5
    case six = 6
    case seven = 7
    case eight = 8
    case nine = 9
    case ten = 10
    case jack = 11
    case queen = 12
    case king = 13

    static func < (lhs: Rank, rhs: Rank) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var label: String {
        switch self {
        case .ace:
            return "A"
        case .jack:
            return "J"
        case .queen:
            return "Q"
        case .king:
            return "K"
        default:
            return String(rawValue)
        }
    }
}

struct Card: Identifiable, Equatable {
    let id: UUID
    let suit: Suit
    let rank: Rank
    var isFaceUp: Bool

    init(id: UUID = UUID(), suit: Suit, rank: Rank, isFaceUp: Bool = false) {
        self.id = id
        self.suit = suit
        self.rank = rank
        self.isFaceUp = isFaceUp
    }
}

struct GameState: Equatable {
    var stock: [Card]
    var waste: [Card]
    var wasteDrawCount: Int
    var foundations: [[Card]]
    var tableau: [[Card]]

    static func newGame() -> GameState {
        var deck = Card.fullDeck().shuffled()
        var tableau = Array(repeating: [Card](), count: 7)

        for pileIndex in 0..<7 {
            for cardIndex in 0...pileIndex {
                var card = deck.removeLast()
                card.isFaceUp = cardIndex == pileIndex
                tableau[pileIndex].append(card)
            }
        }

        return GameState(
            stock: deck,
            waste: [],
            wasteDrawCount: 0,
            foundations: Array(repeating: [], count: 4),
            tableau: tableau
        )
    }
}

extension Card {
    static func fullDeck() -> [Card] {
        var deck: [Card] = []
        for suit in Suit.allCases {
            for rank in Rank.allCases {
                deck.append(Card(suit: suit, rank: rank))
            }
        }
        return deck
    }
}

struct Selection: Equatable {
    enum Source: Equatable {
        case waste
        case foundation(pile: Int)
        case tableau(pile: Int, index: Int)
    }

    let source: Source
    let cards: [Card]
}

enum Destination: Equatable {
    case foundation(Int)
    case tableau(Int)
}

struct GameSnapshot {
    let state: GameState
    let movesCount: Int
}

@Observable
final class SolitaireViewModel {
    private(set) var state: GameState
    var selection: Selection?
    var isDragging: Bool = false
    private(set) var movesCount: Int = 0

    private var history: [GameSnapshot] = []

    init() {
        state = GameState.newGame()
    }

    var isWin: Bool {
        state.foundations.allSatisfy { $0.count == Rank.allCases.count }
    }

    var canUndo: Bool {
        !history.isEmpty
    }

    func newGame() {
        state = GameState.newGame()
        selection = nil
        isDragging = false
        movesCount = 0
        history.removeAll()
    }

    func undo() {
        guard let snapshot = history.popLast() else { return }
        state = snapshot.state
        movesCount = snapshot.movesCount
        selection = nil
        isDragging = false
    }

    func handleStockTap() {
        selection = nil
        isDragging = false
        if state.stock.isEmpty {
            recycleWaste()
        } else {
            drawFromStock()
        }
    }

    func handleWasteTap() {
        guard let top = state.waste.last, state.wasteDrawCount > 0 else { return }
        if selection?.source == .waste {
            selection = nil
            return
        }
        isDragging = false
        selection = Selection(source: .waste, cards: [top])
    }

    func handleFoundationTap(index: Int) {
        if selection != nil {
            if tryMoveSelection(to: .foundation(index)) {
                return
            }
        }
        isDragging = false
        selectFromFoundation(index: index)
    }

    func handleTableauTap(pileIndex: Int, cardIndex: Int?) {
        if let cardIndex {
            let pile = state.tableau[pileIndex]
            guard cardIndex < pile.count else { return }
            let card = pile[cardIndex]

            if !card.isFaceUp {
                if cardIndex == pile.count - 1 {
                    pushHistory()
                    state.tableau[pileIndex][cardIndex].isFaceUp = true
                    movesCount += 1
                }
                selection = nil
                return
            }

            if let selection {
                if selection.source == .tableau(pile: pileIndex, index: cardIndex) {
                    self.selection = nil
                    return
                }
                if tryMoveSelection(to: .tableau(pileIndex)) {
                    return
                }
            }

            isDragging = false
            selectFromTableau(pileIndex: pileIndex, cardIndex: cardIndex)
        } else {
            if selection != nil {
                _ = tryMoveSelection(to: .tableau(pileIndex))
            }
        }
    }

    func isSelected(card: Card) -> Bool {
        selection?.cards.contains(where: { $0.id == card.id }) == true
    }

    @discardableResult
    func startDragFromWaste() -> Bool {
        guard let top = state.waste.last, state.wasteDrawCount > 0 else { return false }
        selection = Selection(source: .waste, cards: [top])
        isDragging = true
        return true
    }

    @discardableResult
    func startDragFromFoundation(index: Int) -> Bool {
        guard let top = state.foundations[index].last else { return false }
        selection = Selection(source: .foundation(pile: index), cards: [top])
        isDragging = true
        return true
    }

    @discardableResult
    func startDragFromTableau(pileIndex: Int, cardIndex: Int) -> Bool {
        let pile = state.tableau[pileIndex]
        guard cardIndex < pile.count else { return false }
        let card = pile[cardIndex]
        guard card.isFaceUp else { return false }
        let cards = Array(pile[cardIndex...])
        selection = Selection(source: .tableau(pile: pileIndex, index: cardIndex), cards: cards)
        isDragging = true
        return true
    }

    @discardableResult
    func handleDrop(to destination: Destination) -> Bool {
        let moved = tryMoveSelection(to: destination)
        if !moved {
            selection = nil
        }
        isDragging = false
        return moved
    }

    func cancelDrag() {
        selection = nil
        isDragging = false
    }

    private func drawFromStock() {
        guard !state.stock.isEmpty else { return }
        pushHistory()
        let drawCount = min(3, state.stock.count)
        for _ in 0..<drawCount {
            var card = state.stock.removeLast()
            card.isFaceUp = true
            state.waste.append(card)
        }
        state.wasteDrawCount = drawCount
        movesCount += 1
    }

    private func recycleWaste() {
        guard state.stock.isEmpty, !state.waste.isEmpty else { return }
        pushHistory()
        var newStock: [Card] = []
        for card in state.waste.reversed() {
            var newCard = card
            newCard.isFaceUp = false
            newStock.append(newCard)
        }
        state.stock = newStock
        state.waste.removeAll()
        state.wasteDrawCount = 0
        movesCount += 1
    }

    private func selectFromTableau(pileIndex: Int, cardIndex: Int) {
        let pile = state.tableau[pileIndex]
        guard cardIndex < pile.count else { return }
        let card = pile[cardIndex]
        guard card.isFaceUp else { return }
        let cards = Array(pile[cardIndex...])
        selection = Selection(source: .tableau(pile: pileIndex, index: cardIndex), cards: cards)
    }

    private func selectFromFoundation(index: Int) {
        guard let top = state.foundations[index].last else { return }
        selection = Selection(source: .foundation(pile: index), cards: [top])
    }

    private func tryMoveSelection(to destination: Destination) -> Bool {
        guard let selection, let movingCard = selection.cards.first else { return false }

        switch destination {
        case .foundation(let index):
            guard selection.cards.count == 1 else { return false }
            guard canMoveToFoundation(card: movingCard, foundationIndex: index) else { return false }
            pushHistory()
            removeSelection(selection)
            state.foundations[index].append(movingCard)
            movesCount += 1
            self.selection = nil
            return true

        case .tableau(let index):
            guard canMoveToTableau(card: movingCard, destinationPile: state.tableau[index]) else { return false }
            pushHistory()
            removeSelection(selection)
            state.tableau[index].append(contentsOf: selection.cards)
            movesCount += 1
            self.selection = nil
            return true
        }
    }

    private func canMoveToFoundation(card: Card, foundationIndex: Int) -> Bool {
        let foundation = state.foundations[foundationIndex]
        if foundation.isEmpty {
            return card.rank == .ace
        }
        guard let top = foundation.last else { return false }
        return top.suit == card.suit && card.rank.rawValue == top.rank.rawValue + 1
    }

    private func canMoveToTableau(card: Card, destinationPile: [Card]) -> Bool {
        if destinationPile.isEmpty {
            return card.rank == .king
        }
        guard let top = destinationPile.last else { return false }
        return top.isFaceUp && top.suit.isRed != card.suit.isRed && card.rank.rawValue == top.rank.rawValue - 1
    }

    private func removeSelection(_ selection: Selection) {
        switch selection.source {
        case .waste:
            _ = state.waste.popLast()
            state.wasteDrawCount = max(0, state.wasteDrawCount - 1)
        case .foundation(let pile):
            _ = state.foundations[pile].popLast()
        case .tableau(let pile, let index):
            var cards = state.tableau[pile]
            cards.removeSubrange(index..<cards.count)
            state.tableau[pile] = cards
            flipTopCardIfNeeded(in: pile)
        }
    }

    private func flipTopCardIfNeeded(in pileIndex: Int) {
        guard let lastIndex = state.tableau[pileIndex].indices.last else { return }
        if !state.tableau[pileIndex][lastIndex].isFaceUp {
            state.tableau[pileIndex][lastIndex].isFaceUp = true
        }
    }

    private func pushHistory() {
        history.append(GameSnapshot(state: state, movesCount: movesCount))
        if history.count > 200 {
            history.removeFirst()
        }
    }
}
