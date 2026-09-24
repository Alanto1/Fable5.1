# Raid a Base! — Game design document

Working title: **Raid a Base!** Genre tags: Simulation, Tycoon, PvP-lite. Servers of 8.
Platforms: mobile first, PC, console. Age rating target: Minimal (Kids & Select eligible).

## 1. Pitch

Your base is a plot of walls, traps, turrets and guard bots around a vault. Coin mines fill the
vault while you are away. Other players raid a *copy* of your base in 90-second heists: break in,
survive the traps, crack the vault, and sprint back to the exit with a loot sack that gets
heavier the greedier they are. When you return you see who hit you, what they took, and a
**Revenge** button.

One sentence for the store page: *Build a base. Raid theirs. Steal the loot before the clock
runs out.*

## 2. Pillars

1. **The clock is the enemy.** Every raid is 90 seconds. Greed versus time is the decision.
2. **Loss is personal, revenge is one tap.** Being raided stings; getting even is instant.
3. **Bases are self-expression.** A base is a puzzle you set for strangers, and it is watchable.
4. **Full server, empty server, same game.** Targets come from saved bases and bandits, so a
   player alone at 4am still has a queue of things to rob.
5. **Fun in 90 seconds.** The first thing a new player does is rob a bandit camp.

## 3. Core loop

```
 RAID (90s heist)  ->  bank loot  ->  BUILD/UPGRADE base  ->  earn while away  ->  get RAIDED
     ^                                                                                |
     +--------------------------------  REVENGE  <------------------------------------+
```

Session shape (10–25 min): collect vault → 2–5 raids → spend loot on upgrades → set a shield or
log off with "come back before someone empties the vault" pressure.

## 4. Systems

### 4.1 Base
- Plot: 16×16 grid, 4-stud cells, entrance on the south edge (3×3 cells kept clear).
- Pieces (v1): Vault (2×2, required, one), Coin Mine (1×1, up to 6), Walls in five tiers, six
  traps, three turrets, two guard types, decor. Full table in `05-economy.md`.
- Slots per category grow with Base Level so a base can never be a solid brick; walls have HP,
  so time, not geometry, limits a raid.
- Build mode: pick a piece, drag a ghost on the grid, tap to place, rotate, upgrade, move, sell
  (50% refund). Levels 1–3 upgrade instantly; higher levels take minutes to hours and can be
  skipped with gems.
- Vault: mines deposit into it while online or offline (accrual from the last tick, capped by
  vault capacity). **Collect** moves coins to the wallet, which is safe. Only vault coins are
  raidable, so leaving coins uncollected is the risk the game is built on.
- Shield: automatic 1 hour after losing ≥5% of the vault, 3 hours after a full wipe. Buyable
  (24h, 149 R$) or watch-an-ad (1h). Starting a raid drops your own shield.
- Themes: Classic, Candy, Neon, Ice (gems or VIP). Recolour every piece at once.

### 4.2 Raid
- Matchmaking picks, in order of preference: a live player in the server with a compatible base
  (50% chance when eligible), a saved base from the pool in the same level bracket, a
  procedurally generated **Bandit Camp** at the raider's level. One free re-roll, more cost coins.
- Pre-raid card: defender name, base level, defense rating, estimated loot (exact with Raid
  Radar pass), shield state.
- Arena: the base is rebuilt from its layout in one of eight arena slots far from the hub.
  3-second countdown, then a 90-second clock (+15s per vault level above 3).
- Raider kit: hammer (breaks walls, cracks the vault), sprint, dash (4s cooldown), loot sack.
  Each coin pile adds weight; at full sack the raider moves 40% slower.
- Loot: cracking the vault bursts 25% of stored coins (capped by sack capacity) as piles.
  Smashing a mine drops 10% of its hourly rate. Piles must be touched to collect.
- Extraction: reach the entrance zone before the clock ends. Extract = keep 100%. Timeout or
  death = keep 30%. Extracting with under 3 seconds left triggers the **CLUTCH** slow-mo.
- Co-op: up to 4 friends in one raid; loot is split evenly and the clock is shared. Defense
  rating scales guards by +1 per extra raider.
- Results: loot banked, trophies won/lost, traps triggered, time left, share prompt, next raid.

### 4.3 Defense behaviours
| Piece | Behaviour | Counter |
|---|---|---|
| Spike Trap | Pops on step: 25% HP, 0.6s stun | Jump over, hammer it (2 swings) |
| Flinger | Launches the raider 40 studs backward/up with ragdoll | Approach from the side |
| Flame Jet | 2s on / 3s off column, damage per tick | Time it |
| Freeze Pad | Slows to 30% for 3s | Dash through |
| Trapdoor Pit (2×2) | Drop in, 4s climb, spill 20% of sack | Walk around |
| Bear Trap | Roots 2.5s, 15% HP | Hammer it |
| Cannon Turret | Slow projectile, 30% HP, knockback | Break line of sight |
| Zapper | Chain arc within 12 studs, slow 50% | Sprint past |
| Goo Gun | Puddles that slow | Avoid puddles |
| Guard Bot | Patrols, chases in LOS, melee 20% HP | Out-run, dash |
| Guard Dog | Fast, low damage, bites sack (spills 5%) | Break walls to funnel |

### 4.4 Progression
- **Base Level** from XP (placing/upgrading pieces, winning raids). Unlocks pieces and slots.
- **Raider gear**: Hammer level (damage), Sack level (capacity), Boots level (speed under load).
- **Trophies** and leagues: Wood → Bronze → Silver → Gold → Diamond → Champion. Weekly league
  rewards (gems, cosmetics). Global top-100 boards for trophies and total stolen.
- **Index**: every trap type triggered, every wall tier broken, every league reached → gems.
- **Relocate** (prestige, later): reset the base for a permanent +10% income and a badge.

### 4.5 Cold start and empty servers
- Every new player's starter base enters the pool immediately.
- Bandit Camps are generated from a seed per level, so there is always a target.
- Loot from bandits decays (100% → 50%) over the last ten bandit raids in an hour, so player
  bases stay the better target.

### 4.6 Live ops
- Weekly: a new trap or decor row in the catalog, a theme, and a weekend **Double Loot** event.
- Codes: `Codes.luau` table with rewards and expiry; group membership grants a permanent +5%.
- Notifications (13+, opted in, one a day): "You were raided by X. Get revenge." and "Your vault
  is full."

## 5. Monetisation

| Item | Type | Price | Why it sells |
|---|---|---|---|
| 2x Loot | Pass | 399 R$ | The best pass in every simulator is the permanent multiplier |
| +6 Trap Slots | Pass | 299 R$ | Builders' status and defense |
| Mega Vault | Pass | 199 R$ | +50% capacity and auto-collect: sleep safely |
| Raid Radar | Pass | 149 R$ | Information, two free re-rolls |
| VIP | Pass | 449 R$ | Tag, golden hammer, exclusive theme, +10% coins |
| Gems 100–7,000 | Product | 99–4,999 R$ | Skips, shields, cosmetics, re-rolls |
| 24h Shield | Product | 149 R$ | Bought the moment a player gets wiped |
| Starter Pack | Product, once | 99 R$ | 5x value in the first session |
| Ad rewards | Rewarded video | — | 10-minute 2x loot, 1h shield (13+ only) |

Gems buy: build-timer skips, shields, theme unlocks, hammer/sack skins, trails, re-rolls,
name-your-base sign. Nothing that raids cannot earn except cosmetics.

## 6. Retention map

| Signal | Hook |
|---|---|
| D1 | Vault fills while away; first shield expires; tutorial gives a reason to come back and collect |
| D2–7 | Raid log and revenge; daily quests for gems; login streak; league placement |
| D8–28 | Weekly trap drop and weekend Double Loot; league resets; index completion; theme goals |
| Co-play | Co-op raids with split loot; "raid together" invite button; friend leaderboard |
| Session quality | 90-second raids chain into "one more"; build mode between raids |

## 7. Analytics (Creator Hub)

Funnel *Onboarding*: Spawned → TutorialRaidStarted → TutorialRaidExtracted → FirstPiecePlaced →
FirstRealRaid → FirstUpgrade → FirstRevenge. Economy events on every coin/gem flow. Custom
events: RaidResult (success, loot, time, defender type), TrapTriggered (type), BaseSaved
(pieces, rating), ShieldBought, ReRoll.

## 8. v1 cut

Ships: base building (Vault, Mine, 5 walls, 6 traps, 3 turrets, 2 guards, 6 decor), async raids
against pool bases and bandits, live-player targets in the same server, co-op raids, shields,
trophies and two leaderboards, daily quests, codes, tutorial, all passes and products wired,
rewarded video, notifications, three themes.

Later: defender-controlled traps during live raids, raid replays, clans, relocate prestige,
seasonal maps, hero meshes swapped in from Blender.
