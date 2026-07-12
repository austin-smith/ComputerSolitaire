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
tools/hint-probe/run.sh all              # full study, 500 deals per run (~7 min)
tools/hint-probe/run.sh yukon 500
tools/hint-probe/run.sh klondike 500 1   # third arg is the draw count
tools/hint-probe/run.sh klondike 500 3
tools/hint-probe/run.sh freecell 500
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
- These figures use the planners' full node budgets. The app additionally
  clips each interactive search at a fraction of a second so the UI never
  hitches; that clip rarely binds, so in-app quality is at most a hair below
  these numbers on the slowest positions.

## Adding a new variant

Wire its deal into `seededDeal`, add a hint-following player for its planner,
add its sources to `run.sh`, then run 500 deals. Acceptance gates:

- The hint column must **decisively beat the random control**.
- **Zero stalemate-loops and zero revisit events** for the hint player. Both
  are machine-enforced: the probe exits nonzero if any hint follower loops in
  any variant, or if Yukon records a single position revisit. (Revisits are
  reported without reclassifying the game, so win rates stay honestly
  measured; the exit code is what enforces the gate.)
- **Watch the over-banking detector** (`losses with >=40 banked`): it should
  be zero for stockless variants (Yukon and FreeCell measure zero). The
  Klondike draw-1 baseline records a single such loss; treat any increase as
  a regression.
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
