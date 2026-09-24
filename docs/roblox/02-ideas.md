# Concepts, scored

Eleven concepts, each scored 1–10 on six criteria. Weights reflect what the 2026 algorithm and
the business reward: virality, retention and monetisation count double; discoverability and solo
feasibility count 1.5; originality/risk counts once. Maximum score is 100.

| Criterion | Weight | What a 10 looks like |
|---|---|---|
| Virality | 2.0 | Produces clips on its own (theft, near-miss, absurd physics, rare pull) and a social hook |
| Retention | 2.0 | Clear reasons to return on day 1, day 7 and day 28 (offline gains, notifications, collection, mastery, weekly content) |
| Monetisation | 2.0 | Permanent multipliers, consumables, cosmetics-as-status, all without gating fun |
| Discoverability | 1.5 | Readable from icon + title, playable with one person in the server, rewards playing with friends |
| Solo feasibility | 1.5 | A polished v1 can be built here with procedural art and data-driven content |
| Originality / risk | 1.0 | Not a clone, no IP or policy exposure, not riding a trend that is already falling |

## Scores

| # | Concept | One line | Vir | Ret | Mon | Disc | Feas | Orig | **Score** |
|---|---|---|---|---|---|---|---|---|---|
| 1 | **Raid a Base!** | Build a trap-filled base that earns while you're away; raid copies of other players' bases in 90-second heists and carry the loot home | 8 | 9 | 9 | 8 | 6 | 8 | **81** |
| 2 | **Catch a Bug!** | Fish It's formula with a net: swing-timing minigame, jars, biomes, weather, 1-in-X rarities, mutations, index | 6 | 8 | 8 | 8 | 8 | 5 | **73** |
| 3 | **Critter Ranch & Race** | Hatch procedurally generated critters, feed and train them, race them against other players' critters | 7 | 7 | 8 | 7 | 6 | 6 | **69.5** |
| 4 | **Merge Monsters** | Grow a Garden plot loop where crops are monsters you merge into rarer ones; neighbours can poach | 6 | 8 | 8 | 7 | 7 | 4 | **69** |
| 5 | **Night Shift** | 2–5 players run a shop through a night of escalating anomalies; scary-but-funny, upgrade the shop between nights | 9 | 7 | 6 | 6 | 5 | 7 | **67.5** |
| 6 | **Kitchen Chaos** | Overcooked-style co-op cooking with a restaurant tycoon meta | 8 | 5 | 5 | 5 | 7 | 7 | **61** |
| 7 | **Heist Crew** | 4-player PvE heists against NPC guards; Payday-lite | 7 | 6 | 6 | 6 | 5 | 6 | **60.5** |
| 8 | **+1 Strength** | "+1" incremental: every lift adds strength; strength gates what you can carry through obby stages | 5 | 4 | 6 | 9 | 9 | 2 | **59** |
| 9 | **Chained Chaos** | Tethered co-op physics escape (Chained Together pattern) | 9 | 3 | 4 | 6 | 8 | 5 | **58** |
| 10 | **AI Critter Companion** | Verity-style AI companion pet that remembers you | 7 | 6 | 5 | 7 | 4 | 3 | **55.5** |
| 11 | **Board Wars** | Async turn-based conquest with push notifications (Roblox's new "novel" push) | 3 | 6 | 5 | 4 | 5 | 8 | **49.5** |

Reasons behind the low scores, so they are not revisited:

- **+1 Strength / Chained Chaos**: cheap lottery tickets. High virality or readability but no
  week-3 reason to return and thin monetisation. Worth shipping later as side products, not as
  the flagship.
- **Kitchen Chaos / Heist Crew**: need 2–4 friends to be fun; an empty server is a dead first
  session, which kills the algorithm signal a new game depends on.
- **AI Companion**: moderation exposure, AI interaction removes rewarded-video eligibility, and
  the trend is one month old.
- **Board Wars**: the push-notification and orthographic-camera tooling it needs is "late 2026"
  and unshipped; turn-based has no proven audience on Roblox yet.
- **Merge Monsters**: the plot-idle lane is where Grow a Garden 2, Steal An Egg and Plants vs
  Brainrots already fight; a merge twist is not enough differentiation to win discovery.

## The top three

### 1. Raid a Base! (recommended)

**Pitch.** Your base is a plot of walls, traps, turrets, guard bots and a vault. Mines fill the
vault with coins while you are offline. Other players raid a *copy* of your base (loaded from a
saved layout) in a 90-second heist: breach the walls, dodge the traps, crack the vault, and sprint
to the exit with a loot sack that gets heavier the greedier you are. When you come back you see
who raided you, what they took, and a one-tap **Revenge** button. If you are online when someone
raids you, you get a **DEFEND!** alert and can fire traps by hand.

**Why it scores highest.**
- It stacks the two most proven emotions on 2025–26 Roblox (theft and carry-it-home tension)
  onto the structure Naavik flags as unexploited on Roblox (asynchronous base raiding, the loop
  behind Clash of Clans' $10B+).
- Asynchronous targets mean the game is full even when the server is empty: raid targets come
  from a saved-base pool plus procedurally generated bandit bases. This solves the new-game
  cold start that kills most co-op concepts.
- Retention hooks map one-to-one onto the algorithm's signals: offline vault fill (D1), raid log
  and revenge plus daily notification (D2–7), leagues, trap unlocks and base themes (D8–28),
  co-op raids with friends (co-play).
- Monetisation is deep without gating: 2x Loot pass, extra trap slots, vault capacity, shields
  and instant-build consumables, gem packs, cosmetics (hammer skins, sack skins, base themes,
  trails), rewarded video for a raid key or a one-hour shield.
- Content is data: every trap, wall tier, turret and theme is a config row. Weekly updates are
  new rows plus a weekend event multiplier.
- Clip engine: trap fling ragdolls, wall smash debris, last-second extractions, "my base is
  unraidable" builds, revenge raids on the person who robbed you.

**Risks and how the design handles them.**
- *Raiding a static base could feel like an obby with a hammer.* Traps are physical (fling,
  freeze, burn, pit), guard bots chase, the loot sack slows you, the clock runs, and greed is a
  real choice. Multiplayer raids add roles (breaker, looter, decoy).
- *Unraidable bases.* Every wall has HP and the vault must be pathable at save time; time, not
  geometry, is the limiter. Defence rating vs attack rating matchmaking keeps it fair.
- *Scope.* Builder + raid + async data is the most complex of the three. Mitigated by grid
  placement, part-based procedural art, and a strict v1 cut (12 pieces, 6 traps, 3 themes).
- *Prior art.* Base Raiders, Fort Wars and Build a Base and Steal exist and are small or dead;
  the space has demand signals (theft, base-building videos) but no polished incumbent.

**Working title.** "Raid a Base!" reads instantly to the Roblox audience, which already uses
"base" from Steal a Brainrot and 99 Nights. Alternative: "Raid a Fort!" if a more branded feel
is preferred.

### 2. Catch a Bug! (safer, proven formula)

Fish It's exact structure with a fresh verb and a less crowded lane: swing a net with a timing
minigame, fill jars, sell, upgrade nets and jars, unlock biomes by boat, chase 1-in-X rarities and
mutations, fill the index, auto-catch pass for AFK sessions, weekly bug drops. Highest feasibility
of the three and the best base rate on Roblox, but it is a formula the algorithm is now actively
discounting when it is thin, and it has the least clip potential. Best choice if the priority is
the shortest path to a monetising simulator rather than the highest ceiling.

### 3. Night Shift (highest clip potential)

Two to five friends keep a small shop open through a night of escalating anomalies (99 Nights'
day/night rhythm with Lethal Company's scary-but-funny co-op). Upgrade the shop between nights,
unlock roles, badges and cosmetics. The strongest clip machine of the three and the horror lane is
under-supplied, but it needs friends to shine, art demands are higher (creatures, lighting, audio),
and monetisation is mostly cosmetics and revives.

## Recommendation

Build **Raid a Base!**. It has the highest ceiling, the best fit to the 2026 discovery signals, a
clean solo-buildable art style, and a cold-start answer that the co-op concepts lack.

If the appetite is lower risk and faster to revenue, choose **Catch a Bug!** and ship
**+1 Strength** alongside it as a cheap discovery lottery ticket. Both can reuse the same
framework (data, monetisation, analytics, UI) built for the flagship.
