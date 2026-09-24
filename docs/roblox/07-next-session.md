# Handoff — "make it actually fun" pass (paused 2026-09-24)

The user paused the session so the next one can run with **Roblox Studio connected as an MCP
tool**. This note is the exact state and the plan so the next session starts in minutes.

## What the user asked for

Their brief (uploaded as `raid-a-base-update1.md`) in one line: the v1 "looks awful, functions
nothing interesting and doesn't even seem like a game". Six numbered tasks: (0) inspect and
play-test in Studio first, (1) visual identity with Blender-built models, post-processing, real
hub layout, before/after screenshots; (2) satisfying building: palette with icons, ghost preview,
5–6 traps and 2–3 guards with personality, "earned while away" moment; (3) tense raids: timer,
music ramp, trap feedback, counters, success and failure sequences, visible revenge; (4) shop with
real previews, quest tracker HUD, physical leaderboards, visible base tiers; (5) SFX for every
action, lobby/raid music, juice; (6) play the loop like a player, fix everything, clean console,
check mobile. Rule: never claim done without seeing it in Studio.

## What exists right now (all pushed on `claude/compassionate-keller-qsi9a1`)

- v1 game as described in `04-architecture.md`. Type-checks, 44 tests pass, builds.
- **New this pass**
  - `assets/blender/gen_props.py` rewritten: 28 placeable pieces (incl. new traps SpinningBlade,
    DartLauncher, GasVent and guard Sentinel) + 11 hub props (Tree, PalmTree, LampPost, Signpost,
    PortalArch, ShopStall, Bench, FlowerBed, Board, Crate, Fence), each built from named material
    groups with behaviour attributes (Spike, Paddle, Jaw, Head, Door, Flame, Blade, Vent).
    Output `assets/export/meshes.json` (39 meshes, 37.9K triangles). Generated and committed.
  - `tools/gen_meshdata.py` packs it into `src/shared/Data/MeshData/*.luau` (generated, committed).
  - `src/server/Base/MeshFactory.luau`: EditableMesh → `CreateDataModelContentAsync` →
    `CreateMeshPartAsync` templates under `ReplicatedStorage.Assets.Meshes`, falling back to the
    part-built models when Mesh APIs are not enabled. **Not wired yet** (not in `SystemsList`,
    `BaseRenderer` does not prefer mesh templates yet).
  - `tools/render_previews.py`: Blender script for before/after renders (hub, base, vault,
    catalogue). Written, **not yet run**.
  - `tools/setup_env.sh`: installs every tool a fresh container needs (Rojo, luau-lsp + defs,
    StyLua, Selene, Lune, Blender 5.2).

## Facts established (do not re-research)

- No Roblox Studio connector existed in the paused session; the user says it will be connected
  next time. Use it for: inspecting the tree, screenshots, play mode, console output.
- Runtime meshes without uploads: server builds `EditableMesh`, bakes with
  `AssetService:CreateDataModelContentAsync(Content.fromObject(em))` → returns
  `(Enum.CreateContentResult, Content)`; `CreateMeshPartAsync(content, {CollisionFidelity=...})`.
  Data-model content replicates server → client and does not count against Editable memory.
  Requires owner ID verification and **Game Settings > Security > Allow Mesh / Image APIs**.
  Server data-model content limit is 200 MB.
- Character physics is client-owned: impulses are sent to the owning client (`ApplyImpulse`).
- Rojo model.json: 12-number CFrames, `Rojo_Id`/`Rojo_Target_PrimaryPart` for PrimaryPart,
  attachments must live under a BasePart to follow `PivotTo`.

## Plan for the next session, in order

0. `bash roblox/tools/setup_env.sh`, then `cd roblox && ./tools/check.sh` (expect green).
   With Studio connected: open `dist/RaidABase.rbxl`, screenshot hub/base/shop, play the loop,
   read the console. Fix runtime errors first; everything below assumes a running game.
1. Wire meshes: add `MeshFactory` to `SystemsList` (first), make `BaseRenderer.buildPiece` use
   `MeshFactory.template(id)` when present, add a `HubDresser` that spawns hub props from
   markers. Convert `tools/gen_map.py` to emit `Prop` markers plus paths, signposts (BUILD/RAID/
   SHOP), lamp posts, flower beds, fences, benches. Lighting: warmer sun, `SunRays`, `Atmosphere`
   tuned, stronger bloom/contrast. Run `render_previews.py --mode before` (before changing gen_map)
   and `--mode after`, attach PNGs to the summary. In Studio: verify meshes appear (or the fallback
   warning if the Mesh API toggle is off; enable it and re-test).
2. Building: ViewportFrame icons in the palette (clone `Assets.Meshes[id]` or `Assets.Pieces[id]`
   into a ViewportFrame with a fitted camera), hover/press feedback, undo-last, cell highlight.
   New trap behaviours in `Defense/Traps.luau`: SpinningBlade (rotating `Blade` group, sweep
   damage + knockback, counter: wait for the gap), DartLauncher (fires along facing every 1.5s,
   counter: break line of sight / dash across), GasVent (cloud radius, slow + tick damage,
   counter: don't linger). `Sentinel` in `Defense/Guards.luau`: stationary, shielded from the
   front, fires orbs; hammer hits from behind only. Add rows to `Pieces.luau` and
   `05-economy.md`. Offline earnings: server sends `WelcomeBack {earned, seconds}` on load,
   client shows count-up modal with coin rain and a Collect button.
3. Raids: `MusicController` ramp (tempo/pitch/volume as time drops), stagger via
   `Humanoid:ChangeState(FallingDown)` on trap hits, shield consumable (`UseItem`), DISARM prompt
   near traps (hammer disables), alarm + red light flashes on vault crack, fullscreen success/
   failure overlays (`EXTRACTED!`, `KNOCKED OUT`, `TIME'S UP`) before the results modal,
   revenge modal on login when raided while away ("X took N coins — GET REVENGE").
4. Progression: shop ViewportFrame previews, HUD quest tracker (top-left mini panel), plaza
   leaderboard `Board` props filled by SurfaceGui from `GetLeaderboards`, base tiers: Camp/Fort/
   Castle/Citadel dressing per base level (ground material, border style, banners, level sign).
5. Sound: `SoundController` categories, hooks on place/upgrade/collect/buy/level-up/raid events;
   music ids are placeholders in `AssetIds.Sounds`/`Music` until verified in Studio.
6. Play the whole loop again in Studio with two clients, fix what breaks, clean the console,
   test the mobile emulator, then update `06-publishing.md` and commit.

## Commands

```bash
cd roblox
./tools/check.sh                                   # format, typecheck, tests, build
/opt/blender/blender -b --python assets/blender/gen_props.py -- --out assets/export   # meshes.json
python3 tools/gen_meshdata.py                      # -> src/shared/Data/MeshData
/opt/blender/blender -b --python tools/render_previews.py -- --mode after --out assets/export/previews
```
