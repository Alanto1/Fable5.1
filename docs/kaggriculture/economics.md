# Kaggriculture economics (derived from the engine source)

All numbers come from `kaggle_environments/envs/kaggriculture/kaggriculture.py` (v1.32.7) and
were verified numerically with the engine's own `market_price` function.

## Season structure

- 30 days × 24 turns = 720 steps; the last processed step is 718 (day 29, hour 22). Anything
  not sold by then is worth nothing. Reward = bank balance.
- Start: $3,000, one 5×5 quadrant (NW). Land: NE $1,000, SW $2,000, SE $4,000.
- One farmer (24 actions/day) plus hired hands. The n-th hire of a day costs fib(n):
  1, 1, 2, 3, 5, 8, 13, 21, 34, 55, 89, 144, 233, 377, 610, ... Hands hired at hour 0 act
  from hour 1 (23 actions) and vanish at end of day.
- Shed holds 100 non-seed items; end-of-day inventory drop discards overflow.
- Max 10 market orders per turn; orders processed index by index, one unit at a time, in
  lockstep with the opponent (both see the same price for the same unit index).

## Production per tile

| Option | Cost | First output | Steady output | Actions/day (feed/care/collect/harvest/water + 1 move) |
|---|---|---|---|---|
| Wheat | 10 | day 4 (4 units) | 1 wheat/day (replant same day) | ~2.2 |
| Carrot | 20 | day 3 (3 units) | 1 carrot/day | ~2.3 |
| Melon | 80 | day 10 (6 units) | 0.6 melon/day, one shot | ~2.0 |
| Tomato | 50 | day 8 | 1/day for 4 days (2/day fertilized+watered) | ~2.2 |
| Strawberry | 100 | day 10 | 1 every 2 days ×4 (2 if fertilized) | ~2.1 |
| Goose | 300 + coop | end of day 3 (4 eggs) | **2 eggs/day** with daily CARE, +1 fertilizer/day | ~4.3 |
| Cow | 400 + pasture | end of day 7 | 3 milk / 2 days with CARE, +1 fertilizer/day | ~4.3 |
| Sheep | 500 + pasture | end of day 5 | 4 wool / 3 days with CARE, +1 fertilizer/day | ~4.3 |

CARE banks +1 unit per fed-and-cared day and pays it on the next production, so every
animal with daily care produces `1 + interval` units per production. Animals must be fed
1 wheat/day (survive one unfed day, escape after two). Plants must be watered daily (the
planting day counts as unwatered).

## Market: pots and floors

Sell price = `base ± amp · f(|inv − 10000|)`, floored at $1. Cumulative revenue selling x units
into an untouched market (both players share it):

| Product | Base | Price → $1 after | Revenue for first 50 / 100 / 150 units | Character |
|---|---|---|---|---|
| Wheat | 25 | never (log) | 1,149 / 2,214 / 3,264 | staple, ~$20 floor |
| Egg | 50 | never (log) | 2,287 / 4,413 / 6,501 | staple, ~$38 floor |
| Carrot | 35 | 842 | 1,509 / 2,761 / 3,864 | soft |
| Tomato | 60 | 529 | 2,453 / 4,353 / 5,929 | soft |
| Fertilizer | 100 | 493 | 4,845 / 9,090 / 12,835 | **$25k pot**, first come first served |
| Melon | 250 | 158 | 12,323 / 21,871 / 26,394 | **$26k pot**, crashes hard |
| Wool | 200 | 59 | 7,710 / 7,970 / 8,020 | small pot |
| Milk | 160 | 76 | 5,485 / 6,206 / 6,256 | small pot |
| Strawberry | 120 | 62 | 3,672 / 3,848 / 3,898 | tiny pot |

Scarcity side (town consumes without supply): hinge-shaped goods explode past their knee:
carrot $385 at deficit 900, tomato $414 at deficit 450, egg $190 at deficit 600. Milk and
strawberry rise with sqrt (milk $344 at deficit 450); melon and wool barely rise (log).

## Town demand (the only thing that restores prices)

Town center: 1 of every product per day. Each unlocked shop instance consumes its products
every 4 turns (6/day), single-product shops 2× (12/day). Shops unlock on days 3, 6, ..., 24
(8 instances, drawn with replacement):

| Shop | Consumes per day |
|---|---|
| Bakery | 6 egg, 6 wheat |
| Pizza shop | 6 milk, 6 tomato, 6 wheat |
| Brunch spot | 6 egg, 6 wheat, 6 strawberry |
| Yarn store | 12 wool |
| Ice cream shop | 6 strawberry, 6 milk, 6 wheat |
| Pet cafe | 12 carrot |
| Smoothie shop | 6 strawberry, 6 milk |
| Farmers market | 6 wheat, 6 carrot, 6 tomato, 6 strawberry |

Consequences used by the agent:

- Premium goods (milk, wool, strawberry) are only worth their base price up to the town's
  consumption rate; every unit beyond that is sold into a cliff. Cows are worth ~4 per milk
  shop, sheep ~9 per yarn store.
- Eggs and wheat never crash, so geese and wheat are the unbounded fallback; their margin is
  thin (egg ~$40, feed wheat $25-60) so labor efficiency decides.
- Fertilizer is a shared $25k pot that every animal drains at 1/day; sell early.
- Melons are a shared $26k pot; the first ~100 melons sold take $22k of it.
- The shop RNG shares its stream with weed spawning on both farms, so the shop sequence is
  not purely a function of the seed.

## Labor economics

One hand ≈ 20 useful actions/day. Value per action: goose ≈ $18-25, cow with milk demand
≈ $70, wheat ≈ $15-20, melon (pot open) ≈ $50+. The 11th-13th hands cost $89-$233/day
($4-12 per action) and pay off; the 15th costs $610/day and rarely does.
