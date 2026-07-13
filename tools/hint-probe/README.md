# Hint Quality Probe

The acceptance and regression instrument for the hint engines. It answers one
question — *is this variant's hint system actually good?* — at the three
moments that matter: when a new variant lands, when someone tunes a planner,
and when someone refactors shared code.

It exists because unit tests cannot catch a planner that plays at random-level
strength; only measured full games can.

It is a tool, not a test: statistical, takes minutes, compiled by `run.sh`
with `swiftc -O` directly against the UI-free Game sources. It is not part of
the app target, the test suite, or CI.

## Usage

From the repo root:

```bash
tools/hint-probe/run.sh all              # full study, 500 deals per run (~10 min)
tools/hint-probe/run.sh yukon 500
tools/hint-probe/run.sh klondike 500 1   # third arg is the draw count
tools/hint-probe/run.sh klondike 500 3
tools/hint-probe/run.sh freecell 500
tools/hint-probe/run.sh spider 500       # all three suit counts
tools/hint-probe/run.sh spider 500 4     # third arg narrows to one suit count
tools/hint-probe/run.sh pyramid 500
tools/hint-probe/run.sh tripeaks 500
tools/hint-probe/run.sh golf 500
tools/hint-probe/run.sh fortythieves 500
tools/hint-probe/run.sh scorpion 500
```

The number is how many seeded deals the run plays (seeds 1 through N; default
500). Deals are deterministic (SplitMix64 + Fisher–Yates, matching
`GameStateFixtures`) and the players call the planners' deterministic entry
points — no wall-clock deadlines — so every figure below is exact: the same
run produces the same numbers on any machine, every time. Deals run in
parallel across all cores (each game is self-contained, so parallelism changes
only wall-clock time); a full `all 500` pass takes about 7 minutes. Progress
streams to stderr every 100 deals.

## Players

Each run reports two players over the same deals:

- **Following every hint** — requests a hint each turn and plays exactly what
  it says. This measures the hint system itself.
- **Random legal moves (control)** — plays a uniformly random move drawn from
  the legal *forward* moves (foundation rollbacks are legal but deliberately
  excluded: a uniform player would spend the endgame yanking banked cards back
  down, and the column would measure self-sabotage instead of luck). The floor
  that calibrates each variant's deal universe: it tells you what wins are
  worth in that variant before crediting the planner with anything.

## Recorded baselines (July 2026, 500 deals per run)

Every figure below comes from a single run of the committed tool; the
hint-following column has additionally reproduced identically across five
consecutive runs, serial and parallel.

| Run | Following every hint | Random (control) |
|---|---|---|
| `yukon` | **62.0%** | 13.6% |
| `klondike` draw-1 | **44.4%** | 39.4% |
| `klondike` draw-3 | **24.0%** | 6.0% |
| `freecell` | **99.8%** | 0.2% |
| `spider` 1-suit | **95.4%** | 0.0% |
| `spider` 2-suit | **49.2%** | 0.0% |
| `spider` 4-suit | **2.8%** | 0.0% |
| `pyramid` | **80.2%** | 15.2% |
| `tripeaks` | **95.4%** | 0.0% |
| `golf` | **22.6%** | 0.0% |
| `fortythieves` | **3.4%** | 0.0% |
| `scorpion` | **14.8%** | 2.8% |

Reading the table honestly:

- **Yukon (62.0% vs 13.6%)**: theoretical winnability is ~80%. Yukon's fully
  reversible moves let even aimless play grind out wins given 600 moves, so
  the hint value is winning 4.6x as often in half the moves (median 95 vs
  184). Tuning directions already measured flat or negative: empty-pile
  weight 8, burial weight 3, inversion weight 5, depth 96, unconditional
  foundation rollbacks (53.2%).
- **Klondike draw-1 random winning 39.4%** is not a bug: with unlimited stock
  passes, even random play eventually stumbles into wins. The hint value at
  draw-1 shows up in efficiency as much as win rate — hints win in a median of
  133 moves versus random's 358. At draw-3 the win-rate gap is the story
  (24.0% vs 6.0%).
- **FreeCell (99.8%)**: the single loss is a deal the solver cannot prove
  within its node budget; the follower classifies it as a deadlock because the
  nudge fallback only circles there (a solved line is finite and cannot loop,
  so any plan-line revisit would be a real bug and trips the gate).
- **Spider (95.4% / 49.2% / 2.8% vs 0.0%)**: the random control winning zero
  at every suit count says Spider wins are never stumbled into — the entire
  hint column is planner skill. 1-suit deals are nearly always winnable and
  the planner delivers. 4-suit is honest about its class: expert play wins
  roughly a third of deals, and a greedy bounded best-first search is far
  below expert — treat 2.8% as the regression floor, not an achievement.
  Spider records a handful of *transient* position revisits per 500 deals
  (2/6/4 by suit count); they come from the deal-preparation fallback, which
  deliberately plays score-losing column fills, so a later line can re-cross
  an earlier layout once. They are reported but not gated; a third visit to
  the same layout is still a gate-tripping loop, and Spider measures zero.
  Tuning directions already measured flat or negative: suited-run bonus x2
  (0% at 4-suit), empty-pile weight 15 (2.0%), break penalty 4 (4.0%),
  early-exit floor 16384 (flat, +50% search cost), node budget 50k (flat).
  Directions that got the planner here: early-exit floor 2048 → 8192
  (+9 points at 2-suit), quadratic suited-run bonus, break penalty 2 → 3
  (+2 points at 4-suit), and the cached fill-then-deal preparation line
  (kills the fill/unfill oscillation the empty-column bonus otherwise causes).
- **Pyramid (80.2% vs 15.2%)**: the solver's own verdict sweep proves 79.5% of
  deals winnable at its default budget (0.8% proved unwinnable, 19.8% undecided
  — hard deals whose reachable graphs exceed the budget), so the follower
  converts essentially every deal the search can prove. Losses record pyramid
  cards cleared instead of foundation cards (Pyramid banks no foundations;
  median 22 of 28 cleared on lost deals), and the over-banking detector does
  not apply. Wins are efficient by structure — the whole game is bounded near
  100 actions — so the hint value is the win-rate gap, not move count.
- **TriPeaks (95.4% vs 0.0%)**: the solver's own verdict sweep proves 95.6% of
  deals winnable at its default budget (0.2% proved unwinnable, 4.1% undecided
  over 10,000 deals), so the follower converts essentially every deal the
  search can prove — and the random control winning zero says single-pass
  TriPeaks wins are never stumbled into; the entire hint column is solver
  skill. Losses record peak cards cleared (TriPeaks banks no foundations;
  median 27 of 28 cleared on lost deals — best-effort lines leave almost
  nothing behind), and the over-banking detector does not apply. The game is
  structurally bounded at 51 actions, so the hint value is the win-rate gap.
- **Golf (22.6% vs 0.0%)**: the low absolute rate is the variant, not the
  planner. Strict Golf (no wraparound, nothing plays on a King, single pass)
  leaves most deals unwinnable: the solver's own verdict sweep proves 26.1%
  of deals winnable at its default budget (66.3% proved unwinnable, 7.6%
  undecided over 10,000 deals), so the follower converts most of what the
  search can prove while still following max-clear lines on the lost majority
  (median 33 of 35 cleared on lost deals — best-effort lines leave almost
  nothing behind). The random control winning zero and clearing a median of
  11 says Golf wins are never stumbled into; the entire hint column is solver
  skill, and the cleared-at-loss gap (33 vs 11) is the per-deal quality
  signal on the lost majority. Losses record column cards cleared (Golf banks
  no foundations), and the over-banking detector does not apply. The game is
  structurally bounded at 51 actions. Budget history: the TriPeaks-sized 200k
  node cap measured 13.6% (61% of deals undecided); the shipped 1M cap with
  12-byte packed search nodes decides 92% of deals and is the baseline above.
- **Forty Thieves (3.4% vs 0.0%)**: the low absolute rate is the variant's
  class, not a broken planner — expert human play wins roughly 10–30% of
  deals, and a greedy bounded best-first search is far below expert; treat
  3.4% as the regression floor, not an achievement (the Spider 4-suit
  framing). The random control winning zero says strict Forty Thieves wins
  (same-suit building, single cards, one stock pass) are never stumbled into;
  the entire hint column is planner skill, and the banked-at-loss gap (median
  33 vs 13) is the per-deal quality signal on the lost majority. Every
  follower loss is an honest deadlock — no action caps, no loops — and
  revisit events measure zero (the no-progress fallback is a bare stock tap,
  strictly monotone, unlike Spider's score-losing deal preparation), so
  Forty Thieves revisits are gated to zero like Yukon's. `losses with >=40
  banked: 167` is legitimately high — Forty Thieves losses strand well-banked
  boards by nature — and is the recorded baseline; treat increases as
  regressions. Tuning directions already measured flat or negative:
  empty-column weight 15 (3.6%, within noise), burial weight 3 (2.4%),
  node budget 60k (flat — the early-exit floor binds first), a twin-lag
  banking penalty targeting the over-banking count (flat at 166, +40%
  wall-clock).
- **Scorpion (14.8% vs 2.8%)**: hints win 5.3x as often as random in a variant
  that is structurally brutal — kings-only empty columns, same-suit-only
  landings, and nothing banks until a full thirteen-card run assembles in
  place. That all-or-nothing shape shows in the loss column: median 0 cards
  banked at loss for *both* players (there is no partial credit to strand), so
  the over-banking detector measures zero and the win-rate gap is the whole
  story. Published practical win rates for Scorpion sit in the low teens, so
  the follower plays at the level of a good human. Revisit events measure
  zero — Scorpion's no-progress fallback (deal the stock) is monotone, unlike
  Spider's score-losing column fills — so Scorpion's revisits are gated to
  zero like Yukon's. Tuning directions already measured flat: node budget 60k
  (14.8%, searches exhaust their improvement-free regions well under 30k),
  same-suit-inversion weight 5 (15.0%, one game — noise), empty-pile weight 8
  (15.0%, noise). The shipped weights keep the Yukon/Spider precedents. The
  class-aware king-transfer prune (a correctness fix: pre-deal whole-pile
  relocations touching the three deal columns are real moves, and only
  same-class transfers are no-ops) also reproduced 14.8% exactly — the
  affected position class is rare enough that no outcome changed in 500
  deals.
- These figures use the planners' full node budgets. The app additionally
  clips each interactive search at a fraction of a second so the UI never
  hitches; that clip rarely binds, so in-app quality is at most a hair below
  these numbers on the slowest positions.

## Adding a new variant

Wire its deal into `seededDeal`, add a hint-following player for its planner,
add its sources to `run.sh`, then run 500 deals. Acceptance gates:

- The hint column must **decisively beat the random control**.
- **Zero stalemate-loops** for the hint player, machine-enforced: the probe
  exits nonzero if any hint follower loops in any variant. **Revisit events**
  are additionally gated to zero for Yukon, Forty Thieves, and Scorpion
  (their planners measure zero, so any revisit is a regression signal);
  Spider's are reported but not gated — see the baseline notes for why a few
  transients per 500 deals are structural there. (Revisits are reported
  without reclassifying the game, so win rates stay honestly measured; the
  exit code is what enforces the gates.)
- **Watch the over-banking detector** (`losses with >=40 banked`): it should
  be zero for stockless variants (Yukon and FreeCell measure zero). The
  Klondike draw-1 baseline records a single such loss, and Spider records
  6/7/1 by suit count (its losses can strand nearly-done boards); Forty
  Thieves records 167 — legitimately high, its losses strand well-banked
  boards by nature; Scorpion measures zero by structure (a loss with three
  banked runs would need 40 cards banked — never observed). Treat any
  increase as a regression.
- Record the measured numbers in the table above; they become the variant's
  regression baseline. Mechanical refactors must reproduce every figure
  exactly; deliberate quality changes must move the hint column up, never
  down. These comparisons are a human step against this ledger by design —
  the tool does not duplicate the baselines in code.

## Retired control players

Two tap-policy control players were evaluated and removed because their
columns could not vary, and a control that cannot vary carries no information:

- **Deterministic tap heuristic** (`TapMovePolicy.bestMove` every turn): lost
  500/500 in every variant — a deterministic policy with no lookahead enters a
  cycle before it can win, regardless of move quality. This is why the hint
  system's loop-freedom guarantee exists: hints are equally deterministic and
  win only because the search's strict-improvement ratchet makes revisiting
  impossible.
- **ε-greedy tap** (10% random jitter): still 0/500 everywhere (stockless
  figures measured under the earlier stop-on-first-revisit rule) — most
  tellingly at Klondike draw-1, where pure random wins 39.4%. Breaking cycles didn't
  help because the tap policy's preferences are actively bad for whole-game
  play: its eager foundation banking (correct for single-tap ergonomics)
  strands the landing cards games need. Good tap ergonomics is not strategy;
  whole-game strength requires search.

## Maintenance

`run.sh` compiles an explicit source list and fails loudly when a file is
missing. When Game-layer files are added or renamed, update the list. Session,
persistence, and view sources cannot be included — they import SwiftData,
Observation, or SwiftUI.
