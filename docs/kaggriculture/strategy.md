# Kaggriculture agent – strategy and architecture

> v6 (current): the daily planner is **recipe-driven**, built from the replay analysis in
> `top-bots.md`. Targets per product are sized to expected town demand (current shops plus a
> discounted expectation of future unlocks), reduced only when the opponent's visible production
> already exceeds the demand alone: cows ≈ milk demand / 1.5, sheep ≈ wool demand / 1.33,
> strawberries ≈ 1.5 × strawberry demand (cap 44), tomatoes when tomato demand ≥ 18/day,
> carrots ≥ 10/day, geese when egg demand ≥ 8/day, 10 melons on day 0-1, wheat tiles equal to
> the animal count plus two (feed self-sufficiency) and wheat as filler, no fourth quadrant,
> 4-5 hands early and 12 from day 11. Fertilizer is an input (strawberries at ages 9/13,
> tomatoes at 7/10) with a shed reserve. The sections below describe the shared execution
> machinery (economy model, tasks, scheduler, market), which is unchanged.

The agent (`kaggriculture/main.py`, ~1,100 lines, no dependencies beyond the standard library)
runs in ~0.6 ms per turn (max ~60 ms on replan turns) against a 1 s limit.

## 1. Economy model (`Econ`)

- Exact copies of the engine's price curves; a prefix-sum table gives the average price over
  any inventory range in O(1).
- `projected_supply`: units of every product that our farm will deliver by the end of the
  season (animals with care bonus, crop cycles, unplanted seeds, shed contents).
- `opponent_supply`: the same from the opponent's visible tiles (their shed is hidden).
- Town demand per day from `unlocked_shops` (shops consume 6/day per product, single-product
  shops 12/day, town center 1/day).
- `marginal(item, units)`: the average price of `units` more of `item` given the projected
  inventory path. One-time crops (melon, carrot, wheat) are priced as a lump sold at the end of
  the path; continuous producers over the later half of the path. This is what stops the
  planner from planting the 30th melon tile or buying the 17th cow into a milk glut.
- `wheat_feed_price`: what the marginal feed wheat will cost given our own purchases push the
  price up (`25 + sqrt(deficit)`), capped at $60.

## 2. Daily planner (`plan_day`, hour 0 and every 3 hours)

1. Keep old plan entries only while they are funded (seed or animal already in stock).
2. Place sunk assets first (animals in shed/inventory, unplanted seeds) on the nearest free
   tiles, reusing empty coops/pastures.
3. Greedy allocation of free tiles: evaluate every option (goose, cow, sheep, wheat, carrot,
   melon, tomato, strawberry) with `option_value` = discounted net cash flow of one tile
   (product revenue at marginal prices, fertilizer revenue, minus seed/animal cost, feed and
   labor priced at the marginal hand's Fibonacci cost / 20 actions). After each allocation the
   projected supply is updated and everything is re-priced.
4. Labor: the planned hand count `H` starts from the load of the existing farm and grows one
   hand at a time while some option is still profitable at the higher labor price
   (`fib(H)/20` per action), capped at 13 hands and $400 per hire.
5. Discount rate 10%/day when cash-poor, 2% when cash-rich (cash is the binding constraint
   only in the first week).
6. Cash reserve: two days of feed for every animal (including those about to be bought) plus
   tomorrow's hires. Purchases never breach it; if cash cannot cover feed, everything in the
   shed is sold at any price.
7. Land: bought when no free tile remains, the best option's value × 25 × 0.6 exceeds the
   price, and cash covers the price plus three more tiles of stock.
8. Marginal prices are cached for task valuation (so care/harvest of a glutted product gets low
   priority).

## 3. Task generation (`gen_tasks`)

Per tile, value-weighted tasks: FEED (100k if the animal missed yesterday, else ~2k),
WATER (50k if missed yesterday, else ~600 + bonus), CARE (= marginal product price), COLLECT
(fertilizer marginal price), HARVEST (full value when the next production would overflow
`max_held`, otherwise low), FERTILIZE ongoing crops and wheat/carrot windows when fertilizer
sells below $40, DIG weeds, and BUILD/PLACE/PLANT for planned tiles (valued at the option's
gross value so carriers go and place what they carry).

## 4. Scheduler (`schedule_units`)

- Zones: the unlocked quadrants are traversed in a serpentine path starting next to the shed;
  the path is cut into contiguous strips of equal load, one per unit (recomputed daily once
  hands exist).
- Each unit: at the shed it drops products when carrying ≥14 (or at the end of the last day),
  picks up feed wheat for the unfed animals of its zone, picks up animals it can place before
  the day ends, and fertilizer when cheap. Otherwise it does the best task on its tile, or
  moves to the nearest tile with work in its zone (nearest-first sweep; value-first in the last
  6 hours). Tiles outside its zone are penalized ×0.25 unless it carries the item they need.
- Last day: targets must leave time to walk back and drop by step 718; sells include what is
  dropped in the same turn.

## 5. Market (`market_orders`, `sell_orders`)

- Order priority under the 10-order cap: hires (hours 0-1, ≤6 per turn), feed wheat, up to
  four sells, land, animals, seeds, remaining sells.
- Eggs and wheat surplus (beyond a feed reserve) sell immediately (log-shaped curves never
  crash). Crash-prone goods sell down to a reserve price (30% of base; 12% for fertilizer),
  except that units beyond what the town can still absorb before the end are sold at any
  price; reserves fade to $1 over the last three days and everything is sold at step 718.
- Feed wheat is bought just in time each morning for all unfed animals (plus pending ones).

## What made the biggest differences (see experiments.md)

1. Hiring driven by the marginal value of labor instead of a fixed cap (+$20k/game).
2. Sweeping zones nearest-first instead of chasing the highest-value task (+$15-30k/game).
3. Consistent discounting of costs and revenue (before the fix, every long-lived option
   looked unprofitable once hands cost > $100).
4. Selling what is dropped on the last turn and returning one step earlier (+$5-9k/game).
5. Two-day feed reserve and emergency selling (eliminated animal starvation).
