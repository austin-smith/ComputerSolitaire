# Spider Rules

These rules describe Spider as implemented in the app: **two decks (104 cards)** across **ten tableau piles**, cards building down regardless of suit while only same-suit runs move together, and the goal of assembling **eight full King-to-Ace runs**, one suit each, which bank automatically as they complete.

## Objective
Complete eight King-to-Ace runs of a single suit. Each completed run is removed from the tableau automatically — the game is won when all eight are done.

## Terminology
- **Tableau:** Ten piles where cards are played and rearranged.
- **Run:** Face-up cards of one suit in strict descending order — the only multi-card unit that moves together.
- **Completed run:** A full King-to-Ace run of one suit — it leaves the tableau on its own.
- **Stock:** The face-down pile that deals one card onto every tableau pile at once.
- **Suits (difficulty):** The two decks are composed of 1, 2, or 4 distinct suits, always 104 cards.

## Setup
- Use two standard 52-card decks (no jokers). Difficulty changes the composition: **1 suit** (eight sets of Spades), **2 suits** (four sets each of Spades and Hearts), or **4 suits** (two full decks).
- **Tableau:** Deal 54 cards left to right: the first four piles get **6 cards**, the remaining six piles get **5 cards**, only the top card of each pile face up.
- **Stock:** The remaining 50 cards, face down (five deals of ten).
- **Completed runs:** Eight spaces bank finished runs as they leave the tableau.

## Play

### Tableau
- Build tableau piles **down in rank**, **regardless of suit** (e.g., a red 6 may land on any 7).
- Nothing may be placed on an Ace.
- Several cards move together only as a **face-up, same-suit descending run**. Mixed-suit or gapped stacks move one card at a time.
- Any card or movable run may fill an **empty pile**.
- When the last face-up card leaves a pile, flip the newly exposed face-down card face up.

### The stock
- Tap the stock to deal **one face-up card onto every pile** (ten cards per deal, five deals in a game).
- Dealing is **not allowed while any pile is empty** — fill every space first.

### Completed runs
- The moment a pile's top thirteen cards form a face-up King-to-Ace run of one suit, the run is **removed automatically** and banked.
- A dealt card can complete a run, and one removal can expose another complete run beneath it.

## Scoring
- Start at **500**.
- **−1** for every move, including each stock deal.
- **+100** for each completed run.
- On a win, a time bonus is added: it starts at 900 and drops by one point per second of play.
- The score never drops below zero.

## Winning
You win when all eight runs are completed. With good play, roughly one in three 4-suit games is winnable, 2-suit games considerably more, and 1-suit games almost always.

## Rule choices
Published Spider rules differ in scoring and stock handling. This implementation uses:
- **Classic Spider scoring.** The 500-point start with −1 per move and +100 per run, rather than the per-card schemes some sites use.
- **Deals blocked over empty piles** (the standard rule, though some implementations allow dealing across gaps).
- **Suit-count difficulty** as deck composition. The two decks are made of 1, 2, or 4 suits, always totaling 104 cards, and each mode keeps its own statistics.

## Sources
- https://en.wikipedia.org/wiki/Spider_(solitaire)
- https://cardgames.io/spidersolitaire/
- https://www.247spidersolitaire.com
