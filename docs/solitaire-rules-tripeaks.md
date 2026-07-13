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

## Solver-backed hints
TriPeaks is a perfect-information game once dealt, so `TriPeaksPlanner` searches the exact position graph: a plays-first depth-first pass over a collision-free 37-bit packed position that returns a winning line, or — because nothing is pruned — an exhausted pass that both proves the deal unwinnable and yields the exact max-clear line, which hints then follow. Timing the stock flip is most of the strategy, so "flip the stock" is itself a hint verdict: it appears only when every available play was searched and lost. Hints go silent only when not one more peak card is clearable.

### Measured baselines
The canonical hint-quality figures live in the hint-probe ledger
(`tools/hint-probe/README.md`): over 500 seeded deals, following every hint
wins **95.4%** against a **0.0%** random-control floor, with zero loops and a
median winning game of 49 moves. The solver's own verdict sweep at its default
budget proves **95.6%** of deals winnable and **0.2%** unwinnable, with 4.1%
undecided at budget (hard deals whose reachable graphs exceed it — they still
get best-effort hints); interactive searches resolve in well under a
millisecond on the median deal. Validate planner changes against the ledger
before shipping.

## Sources
- https://en.wikipedia.org/wiki/Tri_Peaks_(game)
- https://cardgames.io/tripeakssolitaire/
- https://solitaired.com/tripeaks
- https://www.semicolon.com/Solitaire/Rules/TriPeaks.html
