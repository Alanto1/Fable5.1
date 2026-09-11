# Kaggriculture – experiments log

All games: 720 steps, default configuration, seat-swapped every other game, 4 workers.
"vs starter" = the built-in carrot-loop agent (passive market). "vs champ" = the previous
frozen version of this agent (contested market, the realistic case).

| Version | Change | vs starter (mean $) | Head-to-head | Notes |
|---|---|---|---|---|
| v1 | first value planner, greedy tasks | 61k (1 seed) | – | never bought land, animals left unplaced, 45 animals starved |
| v2 | sunk assets, O(1) pricing, feed reserve, zones | 98k (12 seeds, 100% wins) | self-play ~70k | frozen as `champ_v2` |
| v2+ | labor-driven hiring, seeds in supply, cull | 89k | 33% vs v2 | culling and 2-day-feed removal hurt |
| ablations | no-cull / feed 2 days / labor caps / spot prices | – | 56% / 50% / 38% / 38% vs v2 (16 games) | culling was the main harm |
| sweep | discount_hi ∈ {0.05,0.08,0.12}, hands 13-14 | – | 58-75% vs v2 (24 games each) | all no-cull variants beat v2 |
| v3 | discount_hi 0.10, 13 hands, $400 hire cap, no cull, 2-day feed | 94k (12 seeds) | **88% vs v2** (28/32, 83.8k vs 71.2k) | frozen as `champ_v3` |
| v4 | nearest-first sweeps, endgame liquidation, carried-item routing, purchase guards | **110.6k** (12 seeds, 100% wins) | **84% vs v3** (27/32, 93.9k vs 79.1k) | seed 1: 110k → 144k; unsold at end: $0 |
| v4.1 | last-day hires sized for a full harvest sweep | 145.5k / 67.5k on seeds 1 / 5 (+1.4k / −0.1k) | 38% vs v4 (16 games, income equal) | neutral, kept |
| v4.2 | placement tasks value-first + placement labor budget + unplaced-animal cap | 92k on seed 1 | **0% vs v4** (0/32) | value-first placement wrecked the sweeps |
| ablations | each of the three v4.2 changes alone (vs v4, 16-24 games) | – | no-priority 50%, no-labor-budget 54%, no-cap 25% | placement priority and labor budget were the harm; the cap is fine |
| v5 | unplaced-animal cap (4), placement labor 0, harvest all in the last 2 days, crash-prone goods first in sell list, robustness wrapper, 13 hands on the last day | **120.7k** (12 seeds, 100% wins) | **66-67% vs v4** (21/32 and 16/24; +5-6k mean) | seed 1: 155k; seed 5: 67k → 97k; produce left on tiles at the end: $4.7k → $0.2k |

## Opening A/B (16 games each vs the auto planner)

| Forced day-0 opening | v2 planner: income / auto / win | v5 planner: income / auto / win |
|---|---|---|
| 9 geese | 49k / 84k / 0% | 61k / 102k / 0% |
| 12 melons + 6 geese | 61k / 77k / 6% | 86k / 89k / 44% |
| 25 melons + 2 geese | 60k / 81k / 0% | 79k / 92k / 12% |
| 4 sheep + 3 geese | – | 66k / 104k / 6% |

The planner's own mixed opening (≈8 melons, 2 geese, 2 sheep, 1 cow, carrots) beat every
forced opening under both planners; forced openings also starved animals because they left
no feed cash.

## Diagnostics that drove the design

- Action mix (audit, v3): 53% of unit-actions were movement; CARE/COLLECT/FEED/WATER ~35%.
  v4 cut movement to ~48% by sweeping nearest-first; the remaining movement is mostly the
  unavoidable one move per tile per day.
- Planner debug (v3): from day 12 `labor_left ≤ 0` while $80k sat unused → labor, not
  money, was the bottleneck → value-driven hiring.
- Probe of option values (v3): labor cost was undiscounted while revenue was discounted at
  10%/day, so every long-lived option went negative at λ > $10/action.
- Endgame trace (v4-): sell orders were computed from the pre-drop shed, so everything
  dropped at step 718 was never sold (~$5k), and two units were still walking.

## Known remaining inefficiencies

- A few animals bought late and never placed (capped at 4 unplaced; seed 1 ends with 3 cows in the shed).
- ~$2-5k of produce left on tiles at the end of the last day.
- Town shop RNG depends on both farms' empty-tile counts, so evaluation noise is high;
  32-game samples are needed to resolve differences under ~5%.
