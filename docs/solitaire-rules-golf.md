# Golf Rules

These rules describe Golf as implemented in the app: strict classic Golf — exposed column cards one rank above or below the waste top are played onto it, with no wraparound, a draw-one stock, and a single pass — scored like its namesake across a nine-hole match. The published sources offer several relaxations; the choices made here (and why) are called out below.

## Objective
Clear all 35 column cards by playing them onto the waste, one rank up or down at a time, in as few strokes as possible. The stock and waste do **not** need to be emptied. A hole's score is the cards left on the board — or better, below zero for a cleared board — and nine holes make a match. Lower is better throughout.

## Terminology
- **Columns:** Seven face-up piles of five cards; only each column's exposed (last-dealt) card may play.
- **Stock:** The face-down draw pile (16 cards after the deal). One pass only — there are no recycles.
- **Waste:** The face-up pile every played and drawn card lands on; its top card is the match target.
- **Hole:** One deal. Nine holes make a match.
- **Par:** 45 strokes for a nine-hole match — five per hole, matching a hole where a straightforward game clears most of the board.

## Card Values
Rank order runs Ace, 2 … 10, Jack, Queen, King, and does **not** wrap: an Ace connects only to a 2, and a King only to a Queen. Nothing may be played on a King — once a King tops the waste, only a stock flip revives the board. Suits never matter.

## Setup
- Use a standard 52-card deck (no jokers).
- **Columns:** Deal 35 cards face up into seven columns of five.
- **Waste:** Flip one card face up to start the waste.
- **Stock:** The remaining 16 cards, face down.

## Play
- Play any **exposed** column card that is one rank above or below the top waste card, regardless of suit. It becomes the new match target.
- Ranks never wrap, and nothing plays on a King.
- Tap the stock to flip **one** card onto the waste. The stock allows a **single pass** — there are no recycles.
- Cards never leave the waste, and there is no building.
- The hole ends when the board is cleared, or when the stock is spent and nothing plays.

## Scoring
- Your hole score is the number of cards still on the board — it starts at 35 and each play removes a stroke.
- Flipping a stock card costs nothing; its price is the plays it didn't make.
- Clearing the board subtracts one point per stock card left, so scores below zero are the best results.
- There is no time bonus — strokes are the whole score.
- A match is nine consecutive holes; the totals sum, and par for the match is 45.
- **New Game** abandons the match and starts a fresh one at hole 1; **Redeal** replays the current hole. Switching games keeps the match — every game's session is stashed, and Golf resumes where it left off.

## Winning
You win a hole the moment the last column card is played, regardless of the stock and waste. Most holes are not winnable under strict rules — that is the classic game — so the match score is the real contest: clear what the deal allows and beat par across nine holes.

## Rule choices
The linked sources offer relaxations; this implementation uses:
- **Strict adjacency** — no Ace↔King wraparound and nothing plays on a King (Wikipedia's standard rules). The relaxed "Turn the Corner" variant raises winnability dramatically but is a different, easier game.
- **Single pass** through the stock with no recycles (universal across sources — the pass limit is the game).
- **Traditional golf scoring** — one stroke per card left, minus one per banked stock card on a clear, totaled across a nine-hole match with par at 45 (Wikipedia's scoring). Lower is better, unlike every other variant in the app, and this is the app's only multi-deal structure.

## Sources
- https://en.wikipedia.org/wiki/Golf_(patience)
- https://cardgames.io/golfsolitaire/
- https://solitaired.com/golf
