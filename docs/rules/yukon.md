# Yukon Rules

These rules describe Yukon as implemented in the app. Yukon resembles Klondike in its tableau building and foundation rules, with face-down cards to uncover, but all 52 cards are dealt at the start (there is no stock or waste), and any face-up card may be moved together with every card stacked on top of it, **even if those cards are not in sequence**.

## Objective
Move all 52 cards to the four foundations, building each suit from Ace to King.

## Terminology
- **Tableau:** Seven piles where cards are played and rearranged.
- **Foundations:** Four suit piles built up from Ace to King.
- **Group move:** Moving a face-up card together with every card above it as one unit, regardless of order.

## Setup
- Use a standard 52-card deck (no jokers).
- **Tableau:** Deal seven piles left to right. The first pile has 1 card face up. Each following pile has one more face-down card than the last (1 through 6), with **5 cards face up** on top of them, so the piles hold 1, 6, 7, 8, 9, 10, and 11 cards.
- **Foundations:** Four empty piles, one per suit.
- All 52 cards are dealt (21 face down, 31 face up) — there is no stock or waste.

## Play

### Tableau
- Build tableau piles **down in rank** while **alternating colors** (e.g., red 6 on black 7).
- **Any face-up card may be moved**, carrying every card stacked on top of it along as a group. The group does **not** need to be in any order.
- Only the **bottom card of the moving group** must fit the destination: one rank lower and the opposite color of the destination pile's top card.
- When the last face-up card leaves a pile, flip the newly exposed face-down card face up.
- Empty tableau spaces may be filled **only by a King** (alone or carrying a group).

### Foundations
- Foundations are built **by suit** from **Ace to King**.
- Aces start each foundation pile.
- Only the top card of a tableau pile moves to a foundation, one card at a time.

### Group moves
Group moves are what set Yukon apart:

- In Klondike, a multi-card move must be a properly ordered sequence. In Yukon, the cards riding on top of the moved card can be in **any order** — they simply come along.
- This means buried cards can be dug out by relocating whole messy stacks, at the cost of tangling the destination pile.
- Every card that lands out of sequence must eventually be moved again before the cards beneath it can reach the foundations, so group moves trade immediate access for future untangling work.

## Scoring
- Tableau to foundation: +10.
- Turning a tableau card face up: +5.
- Foundation back to tableau: −15.
- On a win, a time bonus is added: it starts at 900 and drops by one point per second of play.
- The score never drops below zero.

## Winning
You win when all 52 cards are moved to the foundations in ascending order by suit. With no stock to cycle and most cards visible or discoverable through play, skilled play wins considerably more often than in Klondike. Roughly 80% of deals are estimated to be winnable with best play.

## Rule choices
Yukon's play rules are essentially settled. The decisions this implementation makes:
- **Kings only on empty piles** (the standard Yukon rule, though some variants allow any card or group).
- **Foundation rollbacks allowed** at −15, matching Klondike. Pulling a banked card back down is sometimes the only way to untangle a pile.
- **Klondike-style scoring minus the waste rows.** Yukon has no stock or waste, so only the foundation, reveal, and rollback values apply.

## Sources
- https://en.wikipedia.org/wiki/Yukon_(solitaire)
- https://cardgames.io/yukonsolitaire/
- https://www.247solitaire.com/yukonSolitaire.php
