import Foundation
import XCTest
@testable import Computer_Solitaire

@MainActor
enum TestCards {
    static func make(
        _ suit: Suit,
        _ rank: Rank,
        isFaceUp: Bool = true,
        id: UUID = UUID()
    ) -> Card {
        Card(id: id, suit: suit, rank: rank, isFaceUp: isFaceUp)
    }

    static func fullDeck(faceUp: Bool = false) -> [Card] {
        Suit.allCases.flatMap { suit in
            Rank.allCases.map { rank in
                Card(suit: suit, rank: rank, isFaceUp: faceUp)
            }
        }
    }
}

@MainActor
enum GameStateFixtures {
    static func emptyBoard() -> GameState {
        GameState(
            stock: [],
            waste: [],
            wasteDrawCount: 0,
            foundations: Array(repeating: [], count: 4),
            tableau: Array(repeating: [], count: 7)
        )
    }

    static func validPersistenceState(
        stockDrawCount: Int = DrawMode.three.rawValue,
        wasteDrawCount: Int = 0
    ) -> GameState {
        var deck = TestCards.fullDeck(faceUp: false)
        let stock = Array(deck.prefix(24))
        deck.removeFirst(24)

        var tableau: [[Card]] = Array(repeating: [], count: 7)
        var index = 0
        for pileIndex in 0..<7 {
            let count = pileIndex + 1
            var pile = Array(deck[index..<(index + count)])
            index += count
            for cardIndex in pile.indices {
                pile[cardIndex].isFaceUp = cardIndex == pile.count - 1
            }
            tableau[pileIndex] = pile
        }

        return GameState(
            stock: stock,
            waste: [],
            wasteDrawCount: min(max(0, wasteDrawCount), 0),
            foundations: Array(repeating: [], count: 4),
            tableau: tableau
        )
    }

    static func almostWonForAutoFinish() -> GameState {
        var foundations = Array(repeating: [Card](), count: 4)
        for (foundationIndex, suit) in Suit.allCases.enumerated() {
            foundations[foundationIndex] = Rank.allCases
                .filter { $0 != .king }
                .map { rank in
                    TestCards.make(suit, rank, isFaceUp: true)
                }
        }

        return GameState(
            stock: [],
            waste: [],
            wasteDrawCount: 0,
            foundations: foundations,
            tableau: [
                [TestCards.make(.spades, .king, isFaceUp: true)],
                [TestCards.make(.hearts, .king, isFaceUp: true)],
                [TestCards.make(.diamonds, .king, isFaceUp: true)],
                [TestCards.make(.clubs, .king, isFaceUp: true)],
                [],
                [],
                []
            ]
        )
    }
}

@MainActor
enum DateFixtures {
    static let reference = Date(timeIntervalSince1970: 1_700_000_000)

    static func plus(_ seconds: TimeInterval, from date: Date = reference) -> Date {
        date.addingTimeInterval(seconds)
    }
}

@MainActor
enum TestAssertions {
    static func assertSingleVisibleWasteCard(
        _ viewModel: SolitaireViewModel,
        expected: Card,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let visible = viewModel.visibleWasteCards()
        XCTAssertEqual(visible.count, 1, file: file, line: line)
        XCTAssertEqual(visible.first?.id, expected.id, file: file, line: line)
    }
}
