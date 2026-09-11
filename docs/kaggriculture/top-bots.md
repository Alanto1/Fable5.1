# What the top Kaggriculture bots actually do (replay analysis)

Source: the public imitation-learning corpus `KiroSamurai/kaggriculture-il` on Hugging Face,
built from Kaggle's daily episode dumps (20,494 replays, Aug 7 – Sep 5 2026, engine 1.32.7).
I analysed `index.csv` (Elo per game) and 60 of the highest-Elo recent replays
(seeds 100456070…105550812; players "Crop Dusta", "Milan Leonard", "keiz", "Jesse Bullard", …).
Replays are competition data and are not stored in this repo.

## Scale of the ladder

| Statistic (games among ~2,800-3,050 Elo bots, Aug 27 – Sep 5) | Value |
|---|---|
| Median final bank | $87,640 |
| 90th / 99th percentile final bank | $122k / $149k |
| Best observed | $275k (Crop Dusta), $205k |
| Top players' Elo | 2,880 – 3,050 |
| Typical unit-actions per game | 7,200 – 7,500 (movement 43-54%) |

## The winning recipe (Milan Leonard $156.9k vs Crop Dusta $151.4k, episode 102694950)

Day 0 orders: `BUY_SEED WHEAT 7`, `BUY_SEED MELON 12`, `BUY_ANIMAL COW 2`, `BUY_ANIMAL SHEEP 2`,
`BUY_PRODUCT WHEAT 5`, `HIRE` ×4-5.

| Day | Money | Farm (Milan Leonard) | Notes |
|---|---|---|---|
| 1 | $142 | 12 melon, 7 wheat, 2 cows, 2 sheep | 4-5 hands |
| 3 | $258 | +1 cow/day | |
| 6 | $133 | 12 melon, 4 wheat, 4 strawberry, 4 cows | **BUY_LAND (NE)** + 3 cows |
| 9 | $1.5k | 20 strawberry, 12 melon, 9 cows, 4 sheep | 8 hands |
| 11 | – | melons sold ($16k) → `BUY_SEED STRAWBERRY 23`, **BUY_LAND (SW)** | |
| 12 | $20k | 36 strawberry, 22 wheat, 9 cows, 4 sheep | 11 hands |
| 18 | $50k | same | 12 hands |
| 21 | $76k | same | |
| 24 | $107k | 36 wheat, 20 strawberry, 9 cows | strawberries replaced by wheat |
| 27 | $134k | 42 wheat, 9 strawberry, 9 cows, 4 sheep | 7-9 wheat seeds/day rotation |
| 29 | $153k | 57 empty tiles, everything sold | |

Revenue: strawberries 287 units / $62k (avg $217), milk 270 / $58k ($214), fertilizer 299 / $17k,
melon 72 / $16k ($227), wheat 402 / $14k, wool 103 / $12k. **No geese, no SE quadrant.**

## Demand sizing across 25 winning games (≥ $115k)

| Product | Town demand/day at day 22 | Tiles/animals the winner ran |
|---|---|---|
| Milk | 36 / 24 / 18 / 12 / 6 | 9-17 / 7-10 / 4-11 / 5 / 1-3 cows |
| Wool | 60 / 48 / 36 / 12 / 0 | 12 / 14-18 / 12 / 4-9 / 2-4 sheep |
| Strawberry | 36 / 30 / 18 / 6 | 28-40 / 31-33 / 14-22 / 11-25 tiles |
| Tomato | 24-30 / ≤ 12 | 11-25 / 0 tiles |
| Carrot | any | 0-4 tiles (late filler only) |
| Wheat | – | 8-35 tiles |
| Geese | – | 0 |

## Mechanics they exploit

- **Fertilizer doubles ongoing crops.** One FERTILIZE at strawberry age 9 covers the refreshes at
  ages 9-11, so both the age-10 and age-12 productions are doubled; another at age 13 covers 14
  and 16. Two fertilizers → 8 berries per plant. Crop Dusta issued 148 FERTILIZE actions
  (strawberry at ages 9/13, some wheat/carrot at age 2 when fertilizer was cheap).
- **Sell at the town's absorption rate.** Strawberries and milk fetched ~$212 average in the
  best game; production was sized so the deficit stayed high.
- **Melons only as an opening** (5-12 tiles), sold on day 10-11 for $12-19k; none afterwards.
- **Two land purchases** (NE ~day 5-6, SW ~day 8-11); the $4,000 SE quadrant is never bought.
- **12 hands from day ~10**, 4-5 before that, 8 from day 6.
- Crop Dusta's alternating `SELL WHEAT 19` / `BUY_PRODUCT WHEAT 19` every other turn is a bug
  that loses ~$150/day, not a trick (buy price is quoted one unit ahead of the sell price).

## How this changed the agent (v6)

Recipe-driven targets sized from expected demand (current shops + discounted future unlocks)
minus the opponent's visible production; fertilizer treated as an input with a shed reserve;
value-based filler choice among wheat/carrot/tomato/strawberry; land capped at two quadrants.
