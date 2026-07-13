# Forty Thieves Rules

These rules describe Forty Thieves as implemented in the app: the strict classic two-deck game — tableau built down by suit, single-card moves only, locked foundations, and a draw-one stock with a single pass. The published sources offer several relaxations; the choices made here (and why) are called out below.

## Objective
Move all 104 cards onto the eight foundations, building each up by suit from Ace to King. Because two decks are in play, every suit completes two foundations.

## Terminology
- **Tableau:** Ten columns of four face-up cards; build down by suit, one card at a time.
- **Foundations:** Eight suit piles built up from Ace to King — two per suit. Cards placed here never return to play.
- **Stock:** The face-down draw pile (64 cards after the deal). One pass only — there are no recycles.
- **Waste:** Face-up cards turned from the stock; only the top card is playable.

## Setup
- Use two standard 52-card decks shuffled together (104 cards, no jokers).
- **Tableau:** Deal 40 cards face up into ten columns of four.
- **Stock:** The remaining 64 cards, face down.
- **Waste** and all eight **foundations** start empty.

## Play
### Tableau
- Build columns **down by suit**, one rank at a time — the 7♠ plays onto the 8♠ and nothing else.
- Only the **exposed top card** of a column may move. Sequences never move as a unit, however perfectly ordered.
- Any single available card — an exposed tableau card or the top waste card — may fill an **empty column**.

### Foundations
- An available Ace starts any empty foundation; each foundation then builds up in its suit to the King.
- A card placed on a foundation is **locked** — it never returns to the tableau.

### The stock
- Tap the stock to turn **one** card face up onto the waste, whenever you like.
- Only the top waste card is playable, to the tableau or a foundation.
- The stock allows a **single pass** — once it is spent, the cards left in the waste stay in play only through the waste top.

## Scoring
- Waste to tableau: +5.
- Waste to foundation: +10.
- Tableau to foundation: +10.
- Winning adds a time bonus that starts at 900 and drops one point per second.
- The score never goes below zero.

## Winning
You win by moving all 104 cards to the foundations. The game is lost when the stock is spent and no legal move remains. Strict Forty Thieves is a famously difficult game — expert play wins perhaps one deal in five — so most deals end as well-fought losses; empty columns and a carefully rationed stock are what winning deals have in common.

## Rule choices
The linked sources offer relaxations; this implementation uses:
- **Single-card movement only** — sequences never move together (Wikipedia's standard rules). Some software offers a "supermove" shortcut that relocates a suited run when enough empty columns exist to have done it card by card; the app keeps the by-the-book rule, so every multi-card relocation is played — and paid for — one move at a time.
- **Build down by suit**, not by alternating colors — the strict classic rule; color building is a different, much easier game.
- **Any card fills an empty column** (universal across sources), and columns have no depth limit.
- **Locked foundations** — a banked card never returns to play. Klondike-style rollbacks would soften the game's defining irreversibility.
- **Single pass** through the stock with no recycles (universal across sources — the pass limit is the game). The in-app **Redeal** command replays the same deal from the start; it is a fresh attempt at the layout, not a recycle of the stock.

## Sources
- https://en.wikipedia.org/wiki/Napoleon_at_St_Helena
- https://www.esolutions.se/Solitaire/forty-thieves
- https://www.bvssolitaire.com/rules/forty-thieves.htm
