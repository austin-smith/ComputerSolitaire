# FreeCell Rules

These rules describe standard FreeCell setup and play. Unlike Klondike, all cards are dealt face up at the start, there is no stock or waste, and nearly every deal is winnable with correct play.

## Objective
Move all 52 cards to the four foundations, building each suit from Ace to King.

## Terminology
- **Cascades:** Eight tableau columns where cards are played and rearranged.
- **Free cells:** Four slots that each hold one card temporarily.
- **Foundations:** Four suit piles built from Ace to King.
- **Supermove:** Moving an ordered run of cards at once, as a shortcut for a series of single-card moves through free cells and empty cascades.

## Layout
- Eight cascades (tableau columns), all cards face up.
- Four free cells (temporary one-card storage slots).
- Four foundations (built by suit).
- There is no stock or waste — every card is visible and in play from the start.

## Setup
- Use a standard 52-card deck (no jokers).
- Deal all 52 cards face up across the eight cascades, left to right.
- The first four cascades receive **7 cards** each; the last four receive **6 cards** each.
- The four free cells and four foundations start empty.

## Cascade Play
- Build cascades **down in rank** while **alternating colors** (e.g., red 6 on black 7).
- You may move the **bottom (exposed) card** of a cascade, or a properly ordered run of cards ending with it (see Multi-Card Moves below).
- An exposed card may move to:
  - another cascade, onto a card one rank higher of the opposite color;
  - an empty free cell;
  - its foundation, if it is the next card in that suit's sequence.
- **Any card** may be placed on an empty cascade — unlike Klondike, empty spaces are not restricted to Kings.

## Free Cells
- Each free cell holds **exactly one card**.
- Any exposed card may be moved to an empty free cell at any time.
- A card in a free cell may return to a cascade (following the normal build rule), move to an empty cascade, or move to its foundation.
- Free cells are the game's main maneuvering space; keeping them open preserves mobility.

## Foundations
- Foundations are built **by suit** from **Ace to King**.
- Aces start each foundation pile.
- Cards may move to foundations from cascades or free cells.

## Multi-Card Moves (Supermoves)
Formally, FreeCell only allows moving one card at a time. Moving a run of cards is a shortcut for a series of single-card moves through free cells and empty cascades, so the length of a movable run is limited by the available space:

- Maximum run length = `(empty free cells + 1) × 2^(empty cascades)`
- Example: 2 empty free cells and 1 empty cascade allow a run of up to (2 + 1) × 2 = **6 cards**.
- With no free cells or empty cascades available, only **one card** may be moved at a time.
- The run itself must already be properly ordered (descending rank, alternating colors), and its destination must follow the normal build rule.
- **When moving a run onto an empty cascade**, that destination cascade does not count as an available empty cascade, since it cannot be used as an intermediate stop for its own move.

## Winning
You win when all 52 cards are moved to the foundations in ascending order by suit. Because all cards are visible from the deal, FreeCell is a game of near-complete information — of the original 32,000 Microsoft deals, only one (#11982) is unwinnable.

## Sources
- https://en.wikipedia.org/wiki/FreeCell
- https://www.247freecell.com/news/mastering-the-freecell-rules-a-beginners-guide/
