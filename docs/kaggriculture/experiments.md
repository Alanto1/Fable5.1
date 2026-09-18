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

## v6: rebuilt from top-bot replays (after the first Kaggle submission scored 700)

| Version | Change | Head-to-head | Notes |
|---|---|---|---|
| v6a | recipe planner: cows/sheep/strawberries/tomatoes sized to expected demand, melons day 0-1, no geese, 2 land buys, hands schedule, fertilizer as input | **94% vs v5** (98k vs 68k) | symmetric self-play only 54k on seed 100 (both flood milk) |
| v6b | opponent-aware sizing (subtract visible opponent production), guards 90/90/80 | 56% vs v6a; 94% vs v5 | self-play 71k on seed 100 |
| v6b+fill | value-based filler (carrot/tomato/strawberry) | 0-19% vs v6b | filler overshoots strawberries (57-67 tiles) and crashes prices |
| v6b+sizing | all products incl. carrots/geese sized to residual demand | 4% vs v6b | self-play 88k but yields pools to the greedy opponent |
| +fair-share floor | never size below 55% of full-demand target | 0% vs v6b | still too polite on cows (2-3 vs v6b's 5-8) |
| +match-to-demand | full-demand sizing, reduce only for opponent excess | 4-12% vs v6b | guard still blocked cows: price model ignored future shops |
| +expected-demand pricing | marginal price model uses expected demand; guards 70/70/60 | 12% vs v6b; wins seed 2300 | two-sided compare showed $12k/game of bought feed wheat |
| **v6c** | feed wheat tiles allocated right after animals | **66% vs v6b** (90.9k vs 87.7k, 32 games); 92% vs v5; starter 124.7k | self-play 111.7k on seed 100 (was 71k) |
| sweeps | fair_share 0.7, sheep_min 3 (no-ops), feed tiles 1.3 (44%) | – | kept defaults |
| melons near shed | day-0 melons on the tiles closest to the shed | 25% vs v6c | animals lose the prime tiles for the whole game; reverted |
| **v6d** | per-zone feed pickup (units fetched wheat only when the *global* carried count was short, so zones starved while others carried 50 wheat) | **92% vs v6c** (108.4k vs 100.4k); 88% on 32 more seeds; 100% vs v5; starter 135.5k | animals lost per game 8 → 3 |
| v6d+ | wheat buffer, must-feed pickup for any wheat-less unit | 62% vs v6d | kept |
| v6e | defer non-urgent ongoing-crop harvests until hour 10 (feed/water first) | 67% vs v6d; 59% on 32 more seeds | kept |
| zones at hour 2 | assign zones only after all hires | 25% vs v6e | hour-1 hands targeted globally then walked back; reverted |
| morning re-buy | buy wheat ignoring carried stock at hours 0-2 | 17-38% vs v6e | bought ~28 wheat/day for 15 animals; the end-of-day drop overflowed the 100-item shed |
| **v6f** | zones at hour 1 for the *planned* unit count; morning purchase = per-zone shortfall; buffers trimmed; carried wheat counted in overflow checks | **75% vs v6e** (32 games); 81% vs v6d; starter 140.8k; animals lost 3 → 0 | **current submission** |
| sweeps vs v6f (24 games each) | size_k 1.0 → 25%; size_k 0.7 → 38%; straw_mult 1.8 → 71%; straw_mult 2.1 → 50%; melon 12 → 62%; melon 15 → 62%; hands 13 → 67%; cow pace 3 → 25%; harvest_hour 13 → 54%; drop_threshold 20 → 38% | – | the three "winners" combined scored 41% on 32 fresh seeds, so the individual gains were noise; v6f defaults kept |

Lesson: in a shared market, improvements that raise symmetric self-play income can lose
head-to-head if they yield pools to a greedy opponent. Head-to-head against the previous
champion is the only metric that matters for rating.


## v7: rebuilt against real ladder data (Sept 18)

The token arrived, so for the first time these numbers come from games the agent actually
played rather than from self-play. 45 real episodes: 18W/27L, rating 731, mean margin
-10,520, and **no crashes or timeouts** — the gap was entirely strategy.

Gauntlet replaces self-play. Self-play between near-identical agents returns ~50% whatever
the quality, which is what produced two mediocre submissions. The panel holds four
deliberately different opponents; the live agent scored 25% against the strawberry profile.

| Version | Change | Gauntlet | Notes |
|---|---|---|---|
| v6f (live) | — | 46.9% | 25% vs the strawberry profile |
| v7 | strawberry target 1.5 -> 2.2, melon replanting, tomatoes off, wheat filler capped at 12 | 59.4% | submitted, reached 777 rating |
| v7c | hold \$500 back for crop tiles | **68.8%** vs v7a's 60.4% on identical seeds | fixed 18.6 idle tiles at day 9 |
| v7d | wheat filler uncapped + value-based endgame | **67.7%** vs 57.3% baseline over 192 games | replicated on two seed sets |

Measured and rejected:

| Idea | Result | Why |
|---|---|---|
| Strawberries first in the allocation order | 0/48 | animals never get established |
| \$1500 fill reserve | 8/48 | starves the animals for the same reason |
| Endgame crop switch alone | 61.5% vs 60.4% | noise |
| Wheat cap alone at 999 / 18 / 30 | 62.5% / 66.7% / 63.5% | none replicate alone |

The last row is the important one: several single knobs looked like wins on one seed set and
collapsed on another. Only the combination of an uncapped wheat filler and a value-based
endgame held up across both. Anything under six points at 96 games is noise.

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
