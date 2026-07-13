# Klondike Rules

These rules describe Klondike as implemented in the app: standard setup and play, with **1-card** and **3-card** draw modes for the stock and **unlimited passes** through it in both modes.

## Objective
Move all 52 cards to the four foundations, building each suit from Ace to King.

## Terminology
- **Tableau:** Seven piles where cards are played and rearranged.
- **Foundations:** Four suit piles built from Ace to King.
- **Stock:** Face-down draw pile.
- **Waste:** Face-up discard pile from the stock.

## Setup
- Use a standard 52-card deck (no jokers).
- **Tableau:** Deal seven piles left to right. The first pile has 1 card face up; the second has 2 cards (top card face up); continue until the seventh pile has 7 cards with only the top card face up.
- **Foundations:** Four empty piles, one per suit.
- **Stock:** Remaining cards are placed face down.
- **Waste:** Empty pile beside the stock.

## Play

### Tableau
- Build tableau piles **down in rank** while **alternating colors** (e.g., red 6 on black 7).
- You may move a face-up card or a properly ordered sequence as a unit.
- When a face-up card is moved, flip the next card in that pile face up.
- Empty tableau spaces may be filled **only by a King** (or a sequence starting with a King).

### Foundations
- Foundations are built **by suit** from **Ace to King**.
- Aces start each foundation pile.

### Stock and waste
- Tap the stock to turn **one card** (1-card draw) or **three cards** (3-card draw) onto the waste.
- Only the **top waste card** is playable.
- When the stock is exhausted, the waste turns face down to form a new stock. **Unlimited passes** are allowed in both draw modes.

## Scoring
- Waste to tableau: +5.
- Waste to foundation: +10.
- Tableau to foundation: +10.
- Turning a tableau card face up: +5.
- Foundation back to tableau: −15.
- Recycling the waste in 1-card draw: −100.
- On a win, a time bonus is added: it starts at 600 in 1-card draw and 900 in 3-card draw, and drops by one point per second of play.
- The score never drops below zero.

## Winning
You win when all cards are moved to the foundations in ascending order by suit.

## Rule choices
Published Klondike rules differ mainly in how the stock is handled; this implementation uses:
- **Unlimited stock passes in both draw modes** — several published rule sets cap 3-card draw at three passes.
- **The classic −100 recycle penalty in 1-card draw**, where unlimited free passes would otherwise remove the mode's tension; 3-card recycles are free.
- **Kings only on empty piles** (the standard rule; some variants allow any card).

## Sources
- https://en.wikipedia.org/wiki/Klondike_(solitaire)#Rules
- https://officialgamerules.org/game-rules/klondike/
- https://www.247solitaire.com/
- https://www.247solitaire.com/klondikeSolitaire3card.php
- https://bicyclecards.com/how-to-play/solitaire
