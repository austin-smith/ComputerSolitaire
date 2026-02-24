# FreeCell Rules

## Objective
Move all 52 cards to the four foundations, building each suit from Ace to King.

## Layout
- Eight cascades (tableau columns), all cards face up.
- Four free cells (temporary one-card storage slots).
- Four foundations (built by suit).

## Setup
- Deal a standard 52-card deck across eight cascades.
- First four cascades contain 7 cards each.
- Last four cascades contain 6 cards each.

## Play
- Build cascades down by alternating colors.
- Move one exposed card at a time.
- Move cards to free cells if space is available.
- Build foundations up by suit from Ace to King.
- Any card can be moved to an empty cascade.

## Multi-card moves
- Ordered runs can be moved when enough temporary storage exists.
- Maximum transferable run length is:
  - `(emptyFreeCells + 1) * 2^(emptyCascades)`
  - If destination cascade is empty, it does not count as an available empty cascade.

## Win
You win when all 52 cards are in the foundations.
