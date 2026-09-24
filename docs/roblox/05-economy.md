# Raid a Base! — Economy v1

All numbers live in `roblox/src/shared/Data/Balance.luau` and `Pieces.luau`; this document
explains the intent so tuning stays coherent. Coins are the soft currency (earned and stolen);
gems are premium (bought, quested, league rewards).

## Curves

| Curve | Formula | Note |
|---|---|---|
| Piece cost | `base × 1.6^(level−1)` | Doubles roughly every 1.5 levels |
| Mine income | `120 × 1.45^(level−1)` coins/hour | L5 ≈ 530/h, L10 ≈ 3,400/h |
| Vault capacity | `2,000 × 1.8^(level−1)` | L5 ≈ 21K, L10 ≈ 400K |
| Wall HP | 100 / 300 / 800 / 2,000 / 5,000 by tier, `× 1.25^(level−1)` | |
| Hammer damage | `50 × 1.5^(level−1)` per swing, 0.45s cooldown | L1 breaks wood in 2 swings |
| Sack capacity | `500 × 1.6^(level−1)` | Caps stolen coins per raid |
| Gear upgrade cost | `400 × 1.7^(level−1)` | Hammer, sack, boots |
| Base XP to level | `100 × level^1.6` | L10 ≈ 4K XP, L20 ≈ 12K |
| Upgrade time | levels 1–3 instant; `60 × 2^(level−4)` seconds after | L6 = 4 min, L10 = 64 min |
| Gem skip price | `ceil(secondsLeft / 120)` gems, min 1 | Same rate as most mobile tycoons |

## Raid maths

- Stealable = `min(25% of vault stored, sack capacity × raiders)`; each mine smashed adds 10% of
  its hourly income.
- Timeout or death keeps 30% of what is in the sack.
- Bandit loot = `level × 350` coins, multiplied by the bandit decay factor
  (`1.0 − 0.05 × min(10, banditRaidsLastHour)`).
- Trophies: win `+30 − 2 × (raiderLevel − defenderLevel)` clamped 10–50; loss `−20`.
- Shield: 1h after losing ≥5%, 3h after losing ≥60%. Raiding drops your own shield.
- Defense rating = Σ piece rating (`Pieces[id].rating × level`). Attack rating =
  `hammer × 3 + sack × 2 + boots`. Bracket = `floor(baseLevel / 3)`.

## Piece catalog (level 1 values)

| Id | Category | Size | Cost | Unlock | HP | Stat | Rating |
|---|---|---|---|---|---|---|---|
| Vault | Structure | 2×2 | — | 1 | 400 | capacity 2,000 | 10 |
| Mine | Structure | 1×1 | 150 | 1 | 120 | 120 c/h | 2 |
| WallWood | Wall | 1×1 | 25 | 1 | 100 | | 1 |
| WallStone | Wall | 1×1 | 100 | 3 | 300 | | 2 |
| WallSteel | Wall | 1×1 | 400 | 6 | 800 | | 4 |
| WallTitanium | Wall | 1×1 | 1,600 | 10 | 2,000 | | 7 |
| WallLaser | Wall | 1×1 | 6,400 | 15 | 5,000 | | 12 |
| SpikeTrap | Trap | 1×1 | 150 | 1 | 60 | 25% dmg, 0.6s stun | 3 |
| Flinger | Trap | 1×1 | 400 | 2 | 80 | 40-stud launch | 5 |
| FlameJet | Trap | 1×1 | 600 | 4 | 80 | 8%/tick | 6 |
| FreezePad | Trap | 1×1 | 500 | 5 | 60 | 30% speed 3s | 5 |
| Pit | Trap | 2×2 | 900 | 7 | 150 | 4s, spill 20% | 8 |
| BearTrap | Trap | 1×1 | 700 | 8 | 60 | root 2.5s, 15% | 6 |
| Cannon | Turret | 1×1 | 1,200 | 6 | 200 | 30% dmg, knockback | 9 |
| Zapper | Turret | 1×1 | 2,000 | 9 | 200 | chain slow 50% | 11 |
| GooGun | Turret | 1×1 | 3,000 | 12 | 200 | slow puddles | 12 |
| GuardBot | Guard | 1×1 | 1,500 | 5 | 250 | melee 20% | 10 |
| GuardDog | Guard | 1×1 | 2,500 | 11 | 180 | bite spills 5% | 12 |
| Flag, Torch, Statue, Bush, Rock, Fountain | Decor | 1×1 | 50–500 | 1–8 | 40 | cosmetic | 0 |

Slots by base level: walls `20 + 4×level`, traps `2 + level`, turrets `floor(level / 3)`,
guards `floor(level / 5)`, mines `min(6, 1 + floor(level / 2))`, decor `10 + level`.

## Sinks and sources per hour (target, mid game, level 8)

| Source | Coins/h | Sink | Coins/h |
|---|---|---|---|
| Mines (4 × L4) | ~1,500 | Wall upgrades | ~2,000 |
| Raids (6/h, 60% wins) | ~4,500 | Trap/turret purchases | ~2,500 |
| Quests (gems) | 30 gems/day | Gear upgrades | ~1,500 |
| | | Re-rolls | ~200 |

Net positive by design; the cost curve absorbs the surplus. Watch `Coins` economy graphs in
Creator Hub for sink/source ratio near 0.85–0.95 after week one.

## Price points

Gem packs 99 / 499 / 999 / 2,499 / 4,999 R$ with escalating bonus; 24h shield 149 R$; starter
pack 99 R$ (one-time, 300 gems + 5,000 coins); passes 149–449 R$ as listed in the GDD. Cosmetic
gem prices: theme 500, hammer skin 150–800, trail 100–600, base sign 50.
