# Roblox market research — September 2026

Purpose: decide what to build. Every number below is a snapshot from the week of 2026-09-24 and
comes from the linked source. Third-party revenue figures are modelled estimates, not disclosures.

## 1. Platform state

| Metric | Value | Source |
|---|---|---|
| Daily active users | 132M in Q1 2026 (+35% YoY); ~123M by Aug 2026, down from the 152M summer-2025 peak | [Q1 letter](https://www.sec.gov/Archives/edgar/data/1315098/000162828026028882/ex991-q12026earningsshar.htm), [IGN](https://www.ign.com/articles/roblox-blames-falling-player-numbers-and-in-game-spending-on-its-push-to-recommend-less-slop-to-kids-and-there-being-no-replacement-for-last-years-viral-hit-grow-a-garden) |
| Age mix (age-checked) | 35% under 13, 38% 13–17, 27% over 18 | [Q2 letter](https://www.sec.gov/Archives/edgar/data/1315098/000162828026051059/ex991-robloxq22026earnin.htm) |
| Over-18 cohort | US 18–34 DAU +42% YoY; O18 monetise >50% higher than U18 | Q2 letter |
| Monthly unique payers | 27M (+15% YoY) in Q2 | Q2 letter |
| Concentration | Top 10 games = ~20% of hours (30% three years ago); 65% of Robux spend growth came from outside the top 10 in Q1 | Q1/Q2 letters |
| DevEx | $0.0038 per Robux; 70% creator share on passes/products; from 8 Jun 2026 an effective 37.8% (vs 26.6%) on spend by age-checked US O18 users in R15 games | [ROLearn](https://rolearn.dev/insights/roblox-developer-revenue-share-2026/), Q1 letter |

Roblox's own explanation for the 2026 DAU and spend slump: the discovery algorithm now
de-emphasises short-term monetisation, and nothing has replaced Grow a Garden. That is the
opening: the algorithm is actively looking for retention-first games.

## 2. What the discovery algorithm rewards (June 2026 change)

Source: [Optimizing Discovery](https://about.roblox.com/newsroom/2026/06/optimizing-discovery-great-games-reach-millions-players-roblox).

- Recommended For You moved from a 7-day to a **28-day retention** view. Signals are split into
  day 1, days 2–7 and days 8–28 retention.
- "Qualified play-through" was split into **play-through, session quality, and spend**, measured
  separately.
- A **co-play** signal (Dec 2025) rewards players who intentionally join with friends, not random
  matchmaking.
- Metrics are **per-user averages**, so a small game with strong retention can out-rank a big one.
- New games routinely stay under 15K impressions for their first two weeks; organic retention and
  off-platform clips (TikTok, Shorts) are what break the loop ([CreatorXP](https://creatorxp.gg/guides/roblox-game-ideas-to-avoid), [Robipedia](https://robipedia.com/blog/surprise-hits)).
- Kids & Select accounts (June 2026) gate ~30K games for younger users. Roblox banned
  reward-for-scrolling mechanics from those catalogues after Steal An Egg's "Reels" treadmill
  ([Kotaku](https://kotaku.com/roblox-cracks-down-on-doomscrolling-games-like-steal-an-egg-that-forces-players-to-watch-reels-while-running-on-a-treadmill-2000727952)).

Design consequence: the game must (a) be fun inside 90 seconds, (b) give a concrete reason to
come back tomorrow and in week 3, (c) be better with friends but playable alone, and (d)
monetise through aspiration and convenience rather than gates.

## 3. Who is on top right now and why

| Game | CCU (Sep 2026) | Launched | Loop | Why it works |
|---|---|---|---|---|
| Steal An Egg | 1.2–2.0M, #1 | 25 Jul 2026 | Train speed → run into guarded biome → steal egg → carry home → hatch pet → idle income → rebirth | Fuses Steal a Brainrot's theft with pet gacha; speed is the single readable stat; carrying loot home under threat is the shareable moment |
| Brookhaven RP | 330–560K | 2020 | Life-sim sandbox | Evergreen social world, weekly updates |
| Blox Fruits | 210–450K | 2019 | Anime MMO | Deep progression, update cadence |
| Murder Mystery 2 | 225–320K | 2014 | Round-based social deduction | Trading economy, evergreen |
| RIVALS | 170–250K | 2024 | Mobile-first FPS | Skill expression, polish |
| 99 Nights in the Forest | 120–316K (peak 14M) | Jun 2025 | Co-op survive-the-night with base building, classes, badges | Longest sessions among leaders; scary-but-funny; base-building videos pull 9M+ views; movie deal |
| +1 Speed Keyboard Escape | 125–175K avg, spikes to 3.7M on event weekends | Apr 2026 | Every step = +1 speed; speed gates obby stages; rebirth; trails; treadmills | Instantly readable title; ASMR feel; Admin Abuse weekend events; 97% like ratio |
| Adopt Me! | 118–280K | 2017 | Pet collecting/trading | Evergreen economy |
| Steal a Brainrot | 165–215K (peak 24M) | May 2025 | Steal-and-defend tycoon | Settled after a 99% drop; est. $64M lifetime; devs now sue clones |
| Fish It! | 88–92K, −32% since Aug (peak 2.7M) | Oct 2024 | Cast → forgiving minigame → sell → upgrade rods/boats → new islands; auto-fish AFK | Simplified copy of Fisch; 1-in-X odds; guided quests; 30-min sessions |
| Animal Hospital, Ride A Pet, Slayers 2, Jujutsu Shenanigans, Plants vs Brainrots | 85–165K | 2025–26 | Various | Newer wave: care sims, pet riding, anime fighters, tower-defence-meets-farming |

Sources: [RoMonitor](https://romonitorstats.com/), [Blox Prices](https://www.bloxprices.com/roblox-top-earning-games/), [rblxdb](https://rblxdb.com/charts/most-played), [Polygon](https://www.polygon.com/steal-an-egg-roblox-what-happened-discord-black-mirror-netflix/), [maxpowergaming on 99 Nights](https://www.maxpowergaming.co/post/99-nights-in-the-forest-surpasses-grow-a-garden-roblox-s-september-breakout), [maxpowergaming on Fish It](https://www.maxpowergaming.co/post/fish-it-how-a-simplified-copycat-became-one-of-roblox-s-biggest-hits), [Death Gamer on +1 Speed](https://deathgamer.com/2026/06/02/1-speed-keyboard-escape-how-did-this-become-robloxs-8-game/).

Modelled monthly net revenue (Blox Prices, treat as order-of-magnitude): Steal An Egg $8.6–14M,
Blox Fruits $6–9.5M, Fish It $5.5–8.2M, 99 Nights $4–6.5M, Adopt Me $4.5–7M, RIVALS $2.5–4.5M,
Brookhaven $2.1–3.5M.

## 4. Mechanics that keep recurring in 2025–26 hits

1. **Theft with consequences** (Steal a Brainrot, Steal An Egg): the loss is personal, the escape
   is the clip.
2. **Carry-it-home tension**: loot only counts once it reaches your base.
3. **One readable stat** (speed) that gates content and is the thing you buy.
4. **Offline income** (Grow a Garden, Build a Base and Steal): "earn while away" is in every
   description.
5. **Rarity → mutation → index → fuse**: infinite collectible variety from a small base set.
6. **Rebirth** as the free prestige loop; ~40% of +1 Speed players rebirth at least once.
7. **Weekly update + weekend "Admin Abuse" live event** cadence; CCU spikes 10–20x on event days.
8. **Social freebies**: like + join group + Discord code = free boost. Cheap acquisition of likes
   and group members (both discovery signals).
9. **Small servers** (5–22 players) and 90–120s rounds for social games.
10. **"Verb a Noun" titles** with emoji tags: Grow a Garden, Steal a Brainrot, Steal An Egg, Ride
    A Pet, Escape Tsunami for Brainrots.

## 5. Genre supply vs demand (Feb 2026 tracker)

| Genre | Tracked CCU | Games | CCU per game |
|---|---|---|---|
| Brainrot | 1.4M | 29 | 48K (saturated, legally hostile) |
| Escape | 764K | 15 | 51K (peaked; Escape Tsunami −78% in a week) |
| Simulator | 336K | 17 | 20K |
| Anime | 143K | 12 | 12K |
| Horror | 78K | 5 | 16K (demand, few suppliers) |
| Tower defence | 59K | 6 | 10K |
| Fighting | 45K | 2 | 23K (underserved) |
| FPS | 38K | 3 | 13K (underserved) |
| Pets | 36K | 6 | 6K |

Source: [devforum market report](https://devforum.roblox.com/t/market-friday-an-ml-tool-that-tracks-roblox-genre-trends-%E2%80%94-heres-this-weeks-full-market-report/4413816).
Its calls: a differentiated Town & City game is the highest-confidence play; Brainrot + Fighting the
highest upside; another Brainrot escape clone the worst.

Naavik's structural read ([Predicting the next big hits](https://naavik.co/digest/predicting-the-next-big-hits-on-roblox/)):
Roblox hits are proven free-to-play loops re-cut for a walkable third-person world. Genres that
have not had their Roblox moment: base-raiding 4X (Clash of Clans / Whiteout Survival), coin
looters (Coin Master), MOBA/Brawl Stars.

## 6. Monetisation playbook (2026)

- 3–5 gamepasses at spread price points (49 / 149 / 399 / 999). Best sellers are permanent
  multipliers ("2x Money" 399 R$ in Steal An Egg, "2x Coins" 399 R$ in Fish It) and AFK/auto
  passes.
- Developer products for consumables: currency packs, shields, speed-ups, luck potions,
  re-rolls. These carry most simulator revenue.
- Cosmetics that are also status: trails, auras, skins. +1 Speed sells 16 trails from 19 to
  2,399 R$.
- Rewarded video ads: 13+ users only, need 2K monthly uniques, reward must be a dev product worth
  3–10 R$ and cannot be random. Roblox expects a 3–10% revenue uplift and reports that ad
  watchers spend more Robux ([announcement](https://devforum.roblox.com/t/rewarded-video-ads-are-now-available-to-all-ads-eligible-creators/4063278)).
- Engagement-based Creator Rewards and Premium payouts reward session length and return visits.
- Cross-game pass sales disabled since 30 May 2026. Roblox Wallet (daily USD payouts) late 2026.
- Experience notifications: one per user per day to opted-in 13+ players, sent server-side via
  Open Cloud ([docs](https://create.roblox.com/docs/production/promotion/experience-notifications)).
  A "you were raided" or "your crop is ready" notification is a proven retention lever.

## 7. Platform roadmap relevant to a new build (RDC 2026, 10–12 Sep)

Late 2026: UI blur/text shadows/gradients, new primitives (cone, capsule, disc), auto collision
geometry, extended draw distance on low-end devices, Web Play in Chrome, push notifications for
async games, pre-roll ads, Roblox Wallet, NPC dynamic behaviour prompts. Early–mid 2027: offline
play, terrain scattering/splines, material layering, avatar motion matching.
Source: [RDC26: What we announced](https://devforum.roblox.com/t/rdc26-what-we-announced/4865880).

Roblox's Fall 2026 spotlight is all "novel" games: anime FPS, 8-player asymmetric horror, goat
football, open-world racing, extraction ARPG, paper turn-based RPG, 2D pixel farming
([Fall preview](https://about.roblox.com/newsroom/2026/09/roblox-fall-games-preview)).

## 8. Constraints that shape the choice

- Solo build with procedural art: the look must come from geometry, colour and motion, not from
  hand-painted assets. Chunky, toy-like, high-saturation styles fit; realistic styles do not.
- Must be fun with 1 player in the server and better with 2–4 friends (co-play signal, cold start).
- No meme IP, no anime IP, no "Steal a" branding (active lawsuits), nothing that trips Kids &
  Select policy.
- Content must be data-driven so weekly updates are config additions, not new systems.
- Mobile first: ~70% of Roblox sessions are touch. Everything must work with one thumb.
