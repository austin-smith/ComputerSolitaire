# TriPeaks Rules

These rules describe TriPeaks as implemented in the app: uncovered peak cards one rank above or below the waste top are played onto it, with a draw-one stock and a single pass. The published sources disagree on several points; the choices made here (and why) are called out below.

## Objective
Clear all 28 peak cards by playing them onto the waste, one rank up or down at a time. The stock and waste do **not** need to be emptied.

## Terminology
- **Peaks:** Twenty-eight cards in three overlapping peaks — face-down rows of three, six, and nine over a face-up base row of ten; each card except the base row is covered by two cards below it.
- **Uncovered:** A card with neither covering card remaining. Only uncovered cards can be played.
- **Stock:** The face-down draw pile (23 cards after the deal).
- **Waste:** The face-up pile every played and drawn card lands on; its top card is the match target.
- **Chain:** Consecutive discards without flipping the stock; each discard in a chain is worth one more point than the last.

## Card Values
Rank order runs Ace, 2 … 10, Jack, Queen, King, and wraps around: King and Ace are adjacent, as are Ace and 2. Suits never matter.

## Setup
- Use a standard 52-card deck (no jokers).
- **Peaks:** Deal 28 cards into the three-peak layout — three face-down rows (three peak cards, then six, then nine), topped by the face-up ten-card base row that the peaks share.
- **Waste:** Flip one card face up to start the waste.
- **Stock:** The remaining 23 cards, face down.

## Play
- Play any **uncovered** card that is one rank above or below the top waste card, regardless of suit. It becomes the new match target.
- Ranks **wrap**: a King plays on an Ace, and an Ace plays on a King or a Two.
- A face-down card flips face up the moment both cards covering it are removed.
- Tap the stock to flip **one** card onto the waste. The stock allows a **single pass** — there are no recycles.
- Cards never leave the waste, and there is no building.

## Scoring
- The n-th consecutive discard in a chain: +n (1, 2, 3, …).
- Flipping a stock card: −5, and the chain resets.
- Clearing a peak: +15 for each of the first two; the third — which always clears the board — pays +30 instead.
- On a win, a time bonus is added (same basis as the other stockless-choice variants).
- The score never drops below zero.

## Winning
You win the moment the last peak card is played, regardless of the stock and waste.

## Rule choices
The linked sources disagree; this implementation uses:
- **Wrapping allowed** (cardgames.io/semicolon.com and most digital implementations, including the original 1989 game), not the no-wrap variant some sites reserve for their "hard" mode.
- **Single pass** through the stock with no recycles (universal across sources — the pass limit is the game).
- **Chain scoring with peak bonuses** (the conventional scheme from the original game: escalating discards, −5 flips, 15/15/30 peak bonuses), not plain per-card scoring.

## Sources
- https://en.wikipedia.org/wiki/Tri_Peaks_(game)
- https://cardgames.io/tripeakssolitaire/
- https://solitaired.com/tripeaks
- https://www.semicolon.com/Solitaire/Rules/TriPeaks.html
