# Canfield Rules

These rules describe Canfield as implemented in the app: the strict classic game — known as Demon in Britain, where it was first recorded — with a thirteen-card reserve, foundations that start at a dealt base rank and wrap, whole-pile tableau moves only, and a draw-three stock with unlimited redeals. The classic sources agree on the essentials; where modern software commonly relaxes them, the choices made here (and why) are called out below.

## Objective
Move all 52 cards onto the four foundations, building each up by suit from the base rank — the rank dealt to the first foundation — and turning the corner from King to Ace along the way.

## Terminology
- **Reserve:** A packet of thirteen cards, all face down except the exposed top card, which is always playable. British sources call it *the demon*. It must fill any empty tableau pile at once.
- **Base card:** The card dealt face up to the first foundation; its rank is where all four foundations start.
- **Tableau:** Four piles built down in alternating colors, wrapping from Ace to King. A pile moves onto another only in its entirety.
- **Foundations:** Four suit piles built up from the base rank, wrapping from King to Ace. Cards placed here never return to play.
- **Stock:** The face-down draw pile (34 cards after the deal). Three cards turn at a time, with unlimited redeals.
- **Waste:** Face-up cards turned from the stock; only the top card is playable.

## Setup
- Use one standard 52-card deck (no jokers).
- **Reserve:** Deal 13 cards into one packet, the top card face up.
- **Base card:** Deal the next card face up onto the first foundation.
- **Tableau:** Deal one card face up onto each of the four piles.
- **Stock:** The remaining 34 cards, face down. The **waste** starts empty.

## Play
### Tableau
- Build piles **down in alternating colors**, turning the corner from Ace to King — the K♠ plays onto the A♥ or A♦.
- A pile moves onto another pile **only in its entirety**; a partial sequence never moves, however well packed. The exposed top card may always play to a foundation.
- An **empty pile** fills at once from the reserve's top card — this is compulsory, and the app performs it automatically. Once the reserve is empty, fill a space with the **top waste card** whenever you choose; a space never fills from another tableau pile.

### Foundations
- Each foundation starts with a card of the **base rank** and builds up in its suit, turning the corner from King to Ace, until it holds all thirteen cards.
- A card placed on a foundation is **locked** — it never returns to the tableau.

### The reserve
- The exposed top card is always available, to a foundation or onto a tableau pile. When it leaves, the next reserve card turns face up.

### The stock
- Tap the stock to turn **three** cards face up onto the waste, order preserved; fewer than three remaining turn together.
- Only the top waste card is playable, to the tableau or a foundation.
- When the stock is spent, tap again to turn the waste over — unshuffled — as the new stock. **Redeals are unlimited.**

## Scoring
- Waste to tableau: +5.
- Waste to foundation: +10.
- Reserve to tableau: +5.
- Reserve to foundation: +10.
- Tableau to foundation: +10.
- Winning adds a time bonus that starts at 900 and drops one point per second.
- The score never goes below zero.

## Winning
You win by moving all 52 cards to the foundations. The game is lost when no play exists from the reserve, tableau, or waste, and a full unchanged pass through the stock surfaces nothing playable. Canfield's reputation as a grind is earned — the casino legend has players buying the deck for $50 and winning $5 per card banked, against an average of five or six — but the deals themselves are more generous than the legend: solver studies find roughly two thirds winnable under these strict rules, with expert play converting about a third. Draining the reserve is the heart of the game.

## Rule choices
The classic sources are unusually consistent for a patience game; the choices here follow them against the relaxations common in software:
- **Whole-pile movement only** — the classic rule in every printed source (Coops' *100 Games of Solitaire*: "sequences on tableau may be moved bodily, but not parts of sequences"; Morehead & Mott-Smith agree). Much modern software permits partial-sequence moves, a measurable easing (solver studies put it at roughly four points of winnability); the app keeps the by-the-book rule.
- **Wrapping in both directions** — foundations turn King-to-Ace and tableau builds turn Ace-to-King. Both are definitional: with a random base rank, the cards just below it would otherwise be nearly unplayable.
- **Compulsory reserve fill** — a space takes the reserve's top card at once, not at the player's option; choice enters only after the reserve is out, when the top waste card may fill a space (and nothing else may — not another tableau pile).
- **Locked foundations** — a banked card never returns to play. No classic source permits "worrying back"; some apps offer it as a house option.
- **Draw three with unlimited redeals** — universal across the classic sources. Deal-one variants exist (Rainbow) but are a different, far easier game. The in-app **Redeal** command replays the same deal from the start; it is a fresh attempt at the layout, not the stock recycle, which is unlimited and free.

## Sources
- https://en.wikipedia.org/wiki/Canfield_(solitaire)
- https://politaire.com/article/canfield.html
- http://www.solitairecity.com/Demon.shtml
- https://www.goodsol.net/forum/vanilla/discussion/162/clarification-on-canfield-rules
- https://arxiv.org/abs/1906.12314
