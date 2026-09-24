# Roblox game project

Source-controlled Roblox game built with [Rojo](https://rojo.space). Everything that ships is
generated from this folder: Luau code, part-built props, map layout and Blender meshes.

## Layout

| Path | What lives there |
|---|---|
| `default.project.json` | Rojo tree: how `src/` and `assets/` map into the place |
| `src/shared` | Code both sides use: config, data catalogs, networking (`Net`, `Guard`), utilities |
| `src/server` | `Bootstrap.server.luau` plus `Services/` (data, inbox, analytics, monetization, notifications, player, game systems) |
| `src/client` | `Bootstrap.client.luau` plus `Controllers/` and the `UI/` toolkit (Theme, Make, Components, Toast) |
| `assets/models` | Generated part-built props (`.model.json`) so the game runs with zero uploads |
| `assets/map` | Generated map layout |
| `assets/blender` | Blender 5.2 scripts that generate the high-fidelity meshes |
| `assets/export` | Blender output (OBJ/FBX) for bulk import into Studio (git-ignored) |
| `tools` | `check.sh` (format, lint, typecheck, tests, build), generators |
| `tests` | Lune unit tests for pure modules |
| `build` | Built `.rbxl` (git-ignored) |
| `dist` | The last verified build, committed so it can be opened in Studio without any tooling |

## Daily workflow

```bash
# one-time on your machine: install Rokit, then
cd roblox && rokit install

# format, lint, typecheck, run tests, build the place
./tools/check.sh

# live-sync into Studio while editing (Rojo plugin in Studio -> Connect)
rojo serve default.project.json
```

Open `dist/RaidABase.rbxl` (committed at each milestone) or your fresh `build/RaidABase.rbxl` in Roblox Studio to play-test. In Studio, enable
**Game Settings > Security > Enable Studio Access to API Services** for real DataStores;
without it the game falls back to an in-memory store so play-testing still works.

## Framework contracts

- **Networking**: only through `Shared/Net/Net`. Server handlers declare `Guard`s and are rate
  limited per player. Never trust client values for anything that touches currency.
- **Data**: `DataService.getProfile(player).Data`. Add fields to `Shared/Data/ProfileTemplate`;
  add a migration in `DataService.Migrations` when changing an existing field.
- **Currency**: only through `PlayerService.addCurrency`, which also logs analytics and updates
  the client.
- **Offline effects**: anything that changes another player's saved state goes through
  `InboxService.push(userId, entry)` and a registered handler.
- **Products**: defined once in `Shared/Data/Products`; ids pasted after creation in Creator Hub.
- **UI**: build screens with `UI/Make` + `UI/Components`, register them with
  `HudController.registerScreen`, open with `HudController.open(name)`.

## Publishing checklist

See `docs/roblox/06-publishing.md`.
