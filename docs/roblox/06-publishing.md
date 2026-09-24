# Raid a Base! — Publishing and launch guide

Everything in the repo builds into one place file. This guide covers the steps that need Roblox
Studio or the Creator Hub, in order. Budget about an hour for the first publish.

## 1. Build and open the place

```bash
cd roblox
./tools/check.sh          # format, lint, type check, tests, then builds build/RaidABase.rbxl
```

Open `build/RaidABase.rbxl` in Roblox Studio. For live editing instead, run `rojo serve` and
connect with the Rojo plugin.

## 2. Studio settings (Game Settings)

| Tab | Setting | Value |
|---|---|---|
| Security | Enable Studio Access to API Services | On (real DataStores in Studio tests) |
| Security | Allow HTTP Requests | On (experience notifications) |
| Security | Allow Third Party Sales | Off |
| Options | Enable Team Create | Optional |
| Avatar | Avatar type | R15 (required for the higher DevEx rate on O18 spend) |
| Places | Max players | 8 |
| Monetization | Enable Rewarded Video Ads | On once the game has 2K monthly visitors |

Then **File > Publish to Roblox**. Name: `[🏰] Raid a Base! 💰`. Genre: Simulation. Enable all
devices. Keep the experience private until section 6 is done.

## 3. Products and passes

Create these under **Creator Hub > experience > Monetization**, then paste the ids into
`roblox/src/shared/Data/Products.luau` (the `id = 0` fields) and rebuild.

Passes: 2x Loot 399, VIP 449, +6 Trap Slots 299, Mega Vault 199, Raid Radar 149.

Developer products: Gems 100 (99), 550 (499), 1,200 (999), 3,250 (2,499), 7,000 (4,999);
24h Shield (149); Starter Pack (99); two rewarded-video products priced at 5 and 8 Robux named
"Raid Key (ad)" and "1h Shield (ad)". Rewarded products must exist as developer products even
though they are granted by ads.

## 4. Experience notifications

1. Creator Hub > experience > **Notifications** > create two strings:
   - Raided: `{raiderName} raided your base and took {amount} coins. Get revenge!`
   - VaultFull: `Your vault is full. Collect your coins before someone else does.`
2. Paste both asset ids into `GameConfig.Notifications`.
3. Creator Hub > **Open Cloud > API Keys** > create a key with `user.user-notification:write`
   for this experience. Copy it.
4. Creator Hub > experience > **Secrets** > add `OPEN_CLOUD_API_KEY` with the key value and the
   domain `apis.roblox.com`.

Without these the game runs normally; notifications are simply skipped.

## 5. Art

The place ships with generated part models, so nothing is required. To upgrade the hero pieces:

```bash
blender -b --python assets/blender/gen_props.py -- --out assets/export
```

Studio: **Home > Import 3D**, select every `.obj` in `assets/export`, Scale Unit = Studs. Copy
each `MeshId` into `src/shared/Data/AssetIds.luau` under `Meshes` keyed by piece id. Icons for
the side menu go in `AssetIds.Images` (512×512 PNG, uploaded through Asset Manager).

## 6. Store page

- **Icon**: a raider mid-sprint with a bulging loot sack, a spike trap snapping behind, gold
  coins flying, the vault door blown open in the background. Warm gold on deep navy. No text.
- **Thumbnails** (3): the same moment from a low angle; a top-down of a beautiful base at night
  with neon laser walls; a screenshot of the CLUTCH extraction banner.
- **Description**: `Build a base. Raid theirs. Steal the loot before the clock runs out. 💰
  Your mines fill your vault while you are away. 🏰 Walls, traps, turrets and guards. ⚔️
  90-second heists against real players' bases. 😈 Revenge on anyone who robs you. 🎁 Like +
  favourite for codes: LAUNCH, RAIDER. Updates every week.`
- Tags: Tycoon, Simulator, PvP, Building, Adventure.
- Kids & Select: keep the maturity questionnaire at Minimal; the game contains no user
  scrolling feeds, gambling, or free-form creation shared between players.

## 7. Test checklist (two accounts, one server)

1. New account: tutorial raid ends with an extraction and 300+ coins in the wallet.
2. BUILD: place a wall and a spike trap, upgrade the wall, sell it, move the vault.
3. RAID: re-roll once free, second re-roll costs coins; bandit raid works with nobody else online.
4. Second account raids the first's live base; the first gets the RaidAlert toast and the raid
   log shows the entry with REVENGE; revenge raid loads the right base.
5. Leave and rejoin: vault accrued coins while away, shield timer persists, layout persists.
6. Shop: gem pack prompt appears, pass prompt appears, theme purchase recolours the base.
7. Quests: "Place 3 pieces" fills, claim gives gems. Code `LAUNCH` redeems once.
8. Mobile: everything above with touch controls in the Studio device emulator (iPhone 12 size).

## 8. Launch playbook (first 30 days)

- **Day 0**: private test with 5–10 friends for one evening; fix what breaks; then public.
- **Discovery**: the algorithm needs day-1, day-7 and day-28 retention. Do not buy ads before
  D1 retention in Creator Analytics is above 30% and average session is over 8 minutes.
- **Clips**: post three 15-second clips a day on TikTok and Shorts from the game's own moments
  (flinger launches, clutch extractions, revenge raids). Send the game link to 10 mid-size
  Roblox YouTubers with a "you'll get raided on camera" hook.
- **Weekly update, every Saturday**: one new trap or decor row, one theme, and a **Double Loot
  weekend** (`Boosts.DoubleLootUntil` for everyone via a server-wide flag). Announce with a code.
- **Weekend live event** ("Admin Abuse"): the owner joins servers, triggers x5 loot for an hour,
  spawns bandit bosses. This is the single biggest CCU lever on the platform right now.
- **Read the numbers**: Economy dashboard sink/source near 0.9; funnel drop-offs between
  TutorialRaidStarted and TutorialRaidExtracted mean the tutorial base is too hard; between
  FirstPiecePlaced and FirstRealRaid means BUILD is not discoverable.

## 9. Things the repo cannot do for you

- Uploading meshes, images and audio (needs an authenticated Studio session).
- Creating passes, products, notification strings, API keys and secrets (Creator Hub).
- Filling the maturity questionnaire and enabling rewarded video (Creator Hub).
- Group creation if you want group payouts and the group-join coin bonus (`Balance.Group`).
