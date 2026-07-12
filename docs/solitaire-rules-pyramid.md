# Pyramid Rules

These rules describe Pyramid as implemented in the app: pairs of exposed cards totaling 13 are removed from a 28-card pyramid, with a draw-one stock and up to three passes. The published sources disagree on several points; the choices made here (and why) are called out below.

## Objective
Remove all 28 pyramid cards by discarding exposed pairs whose ranks total 13, and Kings alone. The stock and waste do **not** need to be emptied.

## Terminology
- **Pyramid:** Twenty-eight face-up cards in seven overlapping rows; each card except the bottom row is covered by two cards below it.
- **Exposed:** A card with neither covering card remaining. Only exposed cards can be played.
- **Stock:** The face-down draw pile (24 cards after the deal).
- **Waste:** Face-up cards drawn from the stock; only the top card is playable.
- **Discard:** Where removed pairs and Kings go; cards there are out of play permanently.
- **Recycle:** Turning the exhausted stock's waste back into the stock for another pass.

## Card Values
Ace = 1, number cards = face value, Jack = 11, Queen = 12, King = 13.

## Setup
- Use a standard 52-card deck (no jokers).
- **Pyramid:** Deal 28 cards face up in seven rows — one card in the first row, two in the second, and so on to seven — each row overlapping the row above.
- **Stock:** The remaining 24 cards, face down.

## Play
- Remove any two **exposed** cards whose ranks total 13: two pyramid cards, or a pyramid card and the top waste card.
- **Kings** total 13 alone and are removed singly.
- **Cover pair:** a pyramid card whose only remaining cover is its rank-13 partner (itself exposed) may be removed together with it in one move.
- Tap the stock to draw **one** card to the waste.
- When the stock is empty, the waste may be recycled into the stock — at most **twice** (three passes total). Recycling preserves draw order.
- Gaps in the pyramid are never refilled, and there is no building.

## Scoring
- Removing a pair: +10.
- Removing a King: +5.
- No recycle penalty — the pass limit is the cost.
- On a win, a time bonus is added (same basis as the other stockless-choice variants).

## Winning
You win the moment the last pyramid card is removed, regardless of the stock and waste.

## Rule choices
The linked sources disagree; this implementation uses:
- **Win = pyramid cleared** (cardgames.io, solitaired.com, and most digital implementations), not Wikipedia's strict all-52-cards variant (~1 in 50 winnable).
- **Three passes** through the stock (solitaired.com; Wikipedia's "Par Pyramid"), not one pass (strict) or unlimited (cardgames.io).
- **Cover pairs allowed** (cardgames.io and most digital implementations).

## Solver-backed hints
Pyramid is a perfect-information game once dealt, so `PyramidPlanner` searches the exact position graph: stage one runs weighted A* for a full winning line, with a partner-count prune that can prove a deal unwinnable; stage two finds the line clearing the most pyramid cards when no win exists, and hints follow it — unlike the other variants, lost Pyramid deals are common and still played for cards cleared. Hints go silent only when not one more pyramid card is clearable.

### Measured baselines
The canonical hint-quality figures live in the hint-probe ledger
(`tools/hint-probe/README.md`): over 500 seeded deals, following every hint
wins **80.2%** against a **15.2%** random-control floor, with zero loops and a
median winning game of 67 moves. The solver's own verdict sweep at its default
budget proves **79.5%** of deals winnable and **0.8%** unwinnable, with 19.8%
undecided at budget (hard deals whose reachable graphs exceed it — they still
get best-effort hints); interactive searches resolve in well under a
millisecond on the median deal. Validate planner changes against the ledger
before shipping.

## Sources
- https://en.wikipedia.org/wiki/Pyramid_(solitaire)
- https://cardgames.io/pyramidsolitaire/
- https://solitaired.com/pyramid-solitaire
