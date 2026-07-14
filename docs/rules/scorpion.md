# Scorpion Rules

These rules describe Scorpion as implemented in the app: **one deck** across **seven tableau piles**, cards building down **by suit** while any face-up card moves with everything stacked on it, and the goal of assembling **four full King-to-Ace runs**, one per suit, built in place and banked automatically as they complete. A **three-card stock** deals onto the first three piles, once, at any time.

## Objective
Complete four King-to-Ace runs, one per suit, built in place on the tableau. Each completed run is removed from the tableau automatically — the game is won when all four are done.

## Terminology
- **Tableau:** Seven piles where all building happens.
- **Group move:** Any face-up card together with every card stacked on top of it, moved as one, even out of order. Only the selected (bottom) card must connect at the destination.
- **Completed run:** A full King-to-Ace run of one suit at the end of a pile — it leaves the tableau on its own. Four complete the game.
- **Stock:** Three face-down cards, dealt face up onto the first three piles at any time — but only once.

## Setup
- Use a standard 52-card deck (no jokers).
- **Tableau:** Deal 49 cards into seven piles of seven. In each of the **first four piles** the bottom three cards are face down, while the **last three piles** are entirely face up.
- **Stock:** The remaining 3 cards, face down.
- **Completed runs:** Four spaces bank finished runs as they leave the tableau.

## Play

### Tableau
- A card lands only on the card **one rank higher of its own suit**, which must be face up at the end of a pile (e.g., 7♣ onto 8♣ only). Nothing may be placed on an Ace.
- Move **any face-up card** along with all cards on top of it, even if they are not in sequence — only the selected card must connect at the destination.
- Only **Kings** (with any cards stacked on them) can fill an empty pile.
- When a face-down card becomes the top of its pile, it flips face up.

### The stock
- Tap the stock to deal its **three cards face up, one onto each of the first three piles**, empty or mid-run piles included.
- The stock may be dealt **at any time** — but only once. There is no waste and no redeal.

### Completed runs
- The moment a pile's top thirteen cards form a face-up King-to-Ace run of one suit, the run is **removed automatically** and banked.
- A dealt card can complete a run, and one removal can expose another complete run beneath it.

## Scoring
- **+5** for turning a tableau card face up.
- **+100** for each completed run.
- Tableau moves and the stock deal are free.
- On a win, a time bonus is added: it starts at 900 and drops by one point per second of play.
- The score never drops below zero.

## Winning
You win the moment the fourth run banks. The game is lost when the stock is spent and no legal move remains before all four runs are complete.

## Rule choices
Published Scorpion rules genuinely disagree on what happens to finished runs and when the stock may be dealt. This implementation uses:
- **Automatic banking of completed runs.** The common digital convention, matching this app's Spider, rather than the traditional description that leaves finished runs lying in the tableau.
- **Deal the stock at any time** (Solitaire Network's "or sooner if desired" and most digital versions), not only when play is blocked.
- **Kings only** on empty piles (universal for Scorpion — the any-card variant is a different game, Wasp).
- **Three face-down cards in each of the first four piles** (the standard deal — Scorpion II, which hides cards in only three piles, is not implemented).

## Sources
- https://en.wikipedia.org/wiki/Scorpion_(solitaire)
- https://www.solitairenetwork.com/solitaire/scorpion-solitaire-game.html
- https://www.solsuite.com/games/scorpion.htm
- https://www.solitairebliss.com/scorpion
