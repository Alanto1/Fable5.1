# Raid a Base! — Technical architecture

Single place, Rojo-managed, server-authoritative. Server size 8, one hub island with eight
plots and eight raid arenas. Everything below lives in `roblox/src`.

## 1. Module map

```
shared/
  Config/GameConfig          platform constants, store names, notification ids
  Data/Balance               every tunable number (steal %, timers, XP, trophies)
  Data/Pieces                piece catalog: category, footprint, cost/HP/stats per level, unlock level
  Data/Products              passes and developer products
  Data/Themes, Cosmetics     palettes, skins, trails
  Data/AssetIds              mesh ids for Blender props (empty = use part models)
  Data/ProfileTemplate       saved data shape
  Grid                       pure: cell<->world, footprints, rotation, bounds
  BaseLayout                 pure: validate/normalise a layout, slots, ratings, serialisation
  RaidRules                  pure: loot maths, trophies, brackets, timers, guard scaling
  BanditBases                pure: seeded procedural layouts per level
  Net/Net, Net/Guard         remotes with validation and rate limits
  Util/*                     Signal, TableUtil, Format
server/
  Bootstrap.server           init order
  Services/DataService       session-locked profiles
  Services/InboxService      offline effects (raid results applied to the owner)
  Services/PlayerService     currency, leaderstats, snapshot
  Services/MonetizationService, AnalyticsService, NotificationService
  Services/BaseService       plots, build/upgrade/sell/move, vault accrual, collect, shields, snapshots, pool
  Services/RaidService       matchmaking, arenas, raid lifecycle, loot, extraction, results
  Services/LeaderboardService  OrderedDataStore boards
  Services/QuestService      daily quests
  Services/CodesService      promo codes and group bonus
  Services/TutorialService   first-session steps
  Base/BaseRenderer          spawns a layout into a plot or arena from piece templates
  Defense/Traps, Turrets, Guards   runtime behaviours, only active in arenas
client/
  Controllers/ClientData, InputController, HudController
  Controllers/HubController  plot UI, RAID button, collect, raid log
  Controllers/BuildController  build mode: ghost placement, rotate, upgrade/move/sell
  Controllers/RaidController   raid HUD, hammer/dash input, sack, results, clutch
  Controllers/EffectsController  camera shake, coin fountain, hit flashes, sounds
  Controllers/TutorialController arrows and prompts
  Screens/*                  Shop, Base, League, Quests, Settings, Codes
  UI/*                       Theme, Make, Components, Toast
```

## 2. Data

### Profile additions
```lua
Base = {
  Level = 1, XP = 0, Theme = "Classic", Name = "",
  Layout = { { id = "Vault", x = 7, z = 7, r = 0, lvl = 1 }, ... },  -- grid coords 0..15, r in 0..3
  Vault = { Stored = 0, LastTick = 0 },          -- raidable coins and accrual timestamp
  ShieldUntil = 0, LastRaidedAt = 0,
  Pending = { { index = 3, toLevel = 4, readyAt = 0 } }, -- timed upgrades
  RaidLog = { { name, userId, amount, success, time, revenged } },  -- last 10
}
Raider = { Hammer = 1, Sack = 1, Boots = 1, Trophies = 0, League = "Wood",
           Raids = 0, Wins = 0, Stolen = 0, BanditRaidTimes = {} }
Index = { Traps = {}, Walls = {}, Leagues = {} }
```

### Base snapshot store (`BaseSnapshots_v1`, key `b_<userId>`)
Written by BaseService on every save. Not session-locked; it is a read-mostly copy for
matchmaking: `{ layout, level, rating, stored, shieldUntil, lastRaidedAt, name, updatedAt }`.
RaidService updates `stored` and `lastRaidedAt` after a raid so the same coins are not stolen
twice before the owner reconciles.

### Raid pool (`MemoryStoreSortedMap "RaidPool"`)
Key `<bracket:02d>:<userId>`, value `{ userId, level, rating }`, TTL 24h, refreshed on save.
Matchmaking reads a range for the bracket, samples up to 20 candidates, filters shields and
recent raids, then loads the snapshot. In Studio without API access both stores fall back to
in-memory tables and bandit bases fill the queue.

### Inbox entries
`RaidResult { raiderName, raiderId, amount, success, trophies, time }` → BaseService handler
deducts `Vault.Stored`, applies the shield rule, appends the raid log, sends a notification.

## 3. Raid lifecycle (server)

1. `RequestRaid(mode)` → RaidService.match(player): candidate → `RaidOffer` to client.
2. `AcceptRaid(offerId)` → allocate arena slot, `BaseRenderer.spawn(layout, arenaCFrame, {active = true})`,
   move raider(s), start countdown, then `RaidStarted { endsAt, lootTotal, target }`.
3. Inputs: `Swing(targetInstance)` (server checks distance ≤ 8, cooldown 0.45s, applies hammer
   damage; walls/mines/vault have `HP` attributes), `Dash()`, `UseItem(key)`.
4. Traps and guards run server-side and act on any raider in the arena. Damage is applied to
   the Humanoid; speed effects are attributes read by the client movement layer and enforced by
   the server through `Humanoid.WalkSpeed`.
5. Vault HP → 0: spawn coin piles (server parts with `Touched` + distance check), each pile a
   fixed value; sack fill tracked server-side; `SackUpdated` events to the client.
6. Extraction: raider touches the exit zone → `RaidEnded { result = "Extracted" }`. Timer end or
   death → `Timeout`/`Died` with 30% keep. Loot banked via `PlayerService.addCurrency`.
7. Results: trophies via `RaidRules.trophyDelta`, `InboxService.push(defenderId, RaidResult)`,
   snapshot update, analytics, arena cleared after 5s, raider teleported to the hub.

## 4. Anti-exploit
- All loot, HP, timers and purchases are server state. The client only sends intents.
- Every remote has guards and per-player rate limits (`Net`).
- Distance checks on swings and pickups; position sanity (>80 studs/s for 2s → raid voided).
- Receipts are idempotent (purchase history ring), grants persist before `PurchaseGranted`.
- Layout validation on the server (`BaseLayout.validate`) for every build action.

## 5. Performance budgets
- Base ≤ 120 pieces, ≤ 6 parts per piece → ≤ 720 parts per base, ≤ 12 bases live → < 9K parts.
- Guards ≤ 4 Humanoids per arena, pathfinding every 0.5s.
- Traps use `Touched` with a 0.3s per-player debounce; turrets raycast at 4 Hz.
- StreamingEnabled with arenas 1,500 studs apart; hub within 512 studs.
- UI is built once and toggled; no per-frame layout work.

## 6. Remotes
| Name | Direction | Guarded args |
|---|---|---|
| ProfileSnapshot, CurrencyChanged, PassesUpdated | S→C | |
| BaseState, VaultTick, RaidLogUpdated | S→C | |
| PlacePiece, MovePiece, UpgradePiece, SellPiece, SkipUpgrade, SetTheme | C→S | piece id, cell ints, rotation 0–3, index |
| CollectVault, BuyShield, Rename | C→S | |
| RequestRaid, ReRoll, AcceptRaid, LeaveRaid, Swing, Dash, UseItem | C→S | offer id, instance, item key |
| RaidOffer, RaidStarted, RaidTick, SackUpdated, HitFx, TrapFx, RaidEnded | S→C | |
| ClaimQuest, RedeemCode, PromptPass, PromptProduct, ShowRewardedAd | C→S | keys |

## 7. Build pipeline
- `tools/gen_props.py` → `assets/models/Pieces/<Id>.model.json` (part-built, attributes for
  HP anchors, trap trigger parts, guard spawn points).
- `tools/gen_map.py` → `assets/map/*.model.json` (island, plots, arenas, spawn, plaza).
- `assets/blender/gen_props.py` → OBJ meshes and `manifest.json`; ids pasted into `AssetIds`.
- `tools/check.sh` → stylua, luau-lsp analyze (Roblox defs + sourcemap), lune tests, rojo build.
