"""Generates part-built piece models into assets/models/Pieces/<Id>.model.json.

Every piece is a Model whose PrimaryPart `Root` sits at the footprint centre on the ground
(y = 0), so `Model:PivotTo(groundCFrame)` places it. Parts carry a `ThemeKey` attribute the
renderer recolours per theme. Behaviour hooks:
  - `Trigger` part on traps (server listens to Touched)
  - `Muzzle` attachment on turrets
  - `Spawn` attachment on guard docks
  - `Body` parts are what the hammer hits (any BasePart in the model counts; HP is on the model)

Run: python3 tools/gen_props.py
"""

from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from rbx import attachment, cframe, model, part, point_light, wedge, write  # noqa: E402

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "models", "Pieces")
CELL = 4.0


def root(w_cells: int, d_cells: int) -> dict:
    return part(
        "Root",
        (w_cells * CELL, 0.2, d_cells * CELL),
        cframe(0, 0.1, 0),
        (255, 255, 255),
        transparency=1.0,
        can_collide=False,
        can_touch=False,
        cast_shadow=False,
    )


# ----------------------------------------------------------------------------- structures


def vault() -> dict:
    children = [
        root(2, 2),
        part("Base", (7.6, 0.6, 7.6), cframe(0, 0.3, 0), (90, 90, 100), "Concrete", theme="metal"),
        part("Body", (6.4, 5.6, 6.4), cframe(0, 3.4, 0), (255, 190, 60), theme="vault"),
        part("Band", (6.8, 1.0, 6.8), cframe(0, 1.1, 0), (150, 100, 20), theme="vaultDark"),
        part("BandTop", (6.8, 0.8, 6.8), cframe(0, 5.9, 0), (150, 100, 20), theme="vaultDark"),
        # Door on the south face (+Z): a cylinder lying along Z
        part("Door", (0.6, 3.6, 3.6), cframe(0, 3.4, 3.25, 0, 0, 90), (150, 100, 20), "Metal", shape="Cylinder", theme="vaultDark"),
        part("Wheel", (0.4, 1.8, 1.8), cframe(0, 3.4, 3.6, 0, 0, 90), (240, 240, 240), "Metal", shape="Cylinder", theme="steel"),
        part("Spoke1", (0.3, 0.3, 1.9), cframe(0, 3.4, 3.7), (240, 240, 240), "Metal", theme="steel"),
        part("Spoke2", (1.9, 0.3, 0.3), cframe(0, 3.4, 3.7), (240, 240, 240), "Metal", theme="steel"),
        part("Coin", (0.3, 2.0, 2.0), cframe(0, 6.9, 0, 0, 0, 90), (255, 220, 90), "Neon", shape="Cylinder"),
        attachment("Top", cframe(0, 7.5, 0)),
    ]
    return model("Vault", children, "Root", {"PieceId": "Vault"})


def mine() -> dict:
    children = [
        root(1, 1),
        part("Base", (3.6, 0.5, 3.6), cframe(0, 0.25, 0), (90, 80, 70), "Concrete", theme="metal"),
        part("Body", (2.8, 2.2, 2.8), cframe(0, 1.6, 0), (120, 90, 70), "WoodPlanks", theme="mine"),
        part("Roof", (3.2, 0.4, 3.2), cframe(0, 2.9, 0), (80, 60, 50), "Wood", theme="mineAccent"),
        part("Chimney", (0.8, 1.6, 0.8), cframe(1.0, 3.7, -1.0), (70, 70, 80), "Metal", shape="Cylinder", theme="metal"),
        part("Drill", (0.6, 1.6, 0.6), cframe(0, 3.9, 0), (200, 200, 210), "Metal", shape="Cylinder", theme="steel"),
        part("Gem", (0.9, 0.9, 0.9), cframe(0, 4.9, 0, 45, 0, 45), (255, 205, 60), "Neon"),
        part("Cart", (1.4, 0.8, 1.0), cframe(1.0, 0.9, 1.4), (90, 90, 100), "Metal", theme="metal"),
        part("Ore", (0.8, 0.5, 0.6), cframe(1.0, 1.5, 1.4), (255, 205, 60), "Neon"),
        attachment("Top", cframe(0, 5.5, 0)),
    ]
    return model("Mine", children, "Root", {"PieceId": "Mine"})


# ----------------------------------------------------------------------------- walls


def wall(piece_id: str, theme: str, theme_dark: str, material: str, rgb, rgb_dark, extra) -> dict:
    children = [
        root(1, 1),
        part("Body", (4.0, 4.4, 3.2), cframe(0, 2.2, 0), rgb, material, theme=theme),
        part("Cap", (4.0, 0.6, 3.6), cframe(0, 4.7, 0), rgb_dark, material, theme=theme_dark),
        part("Foot", (4.0, 0.6, 3.6), cframe(0, 0.3, 0), rgb_dark, material, theme=theme_dark),
    ]
    children.extend(extra)
    return model(piece_id, children, "Root", {"PieceId": piece_id})


def wall_wood() -> dict:
    planks = [
        part(f"Plank{i}", (0.9, 4.0, 0.3), cframe(-1.35 + i * 1.35, 2.2, 1.7), (120, 78, 40), "Wood", theme="woodDark")
        for i in range(3)
    ]
    planks += [part(f"PlankB{i}", (0.9, 4.0, 0.3), cframe(-1.35 + i * 1.35, 2.2, -1.7), (120, 78, 40), "Wood", theme="woodDark") for i in range(3)]
    return wall("WallWood", "wood", "woodDark", "WoodPlanks", (176, 120, 66), (120, 78, 40), planks)


def wall_stone() -> dict:
    bricks = [
        part("Brick1", (1.6, 0.9, 0.3), cframe(-0.9, 1.4, 1.7), (100, 108, 122), "Slate", theme="stoneDark"),
        part("Brick2", (1.2, 0.9, 0.3), cframe(1.1, 2.6, 1.7), (100, 108, 122), "Slate", theme="stoneDark"),
        part("Brick3", (1.4, 0.9, 0.3), cframe(-0.6, 3.6, 1.7), (100, 108, 122), "Slate", theme="stoneDark"),
        part("Brick4", (1.6, 0.9, 0.3), cframe(0.8, 1.4, -1.7), (100, 108, 122), "Slate", theme="stoneDark"),
        part("Brick5", (1.2, 0.9, 0.3), cframe(-1.0, 2.8, -1.7), (100, 108, 122), "Slate", theme="stoneDark"),
    ]
    return wall("WallStone", "stone", "stoneDark", "Slate", (150, 158, 170), (100, 108, 122), bricks)


def wall_steel() -> dict:
    rivets = []
    for i, (x, y) in enumerate([(-1.3, 1.0), (1.3, 1.0), (-1.3, 3.4), (1.3, 3.4)]):
        rivets.append(part(f"Rivet{i}", (0.5, 0.5, 0.5), cframe(x, y, 1.7), (90, 110, 130), "Metal", shape="Ball", theme="steelDark"))
        rivets.append(part(f"RivetB{i}", (0.5, 0.5, 0.5), cframe(x, y, -1.7), (90, 110, 130), "Metal", shape="Ball", theme="steelDark"))
    return wall("WallSteel", "steel", "steelDark", "Metal", (176, 196, 214), (90, 110, 130), rivets)


def wall_titanium() -> dict:
    trim = [
        part("TrimF", (3.4, 0.3, 0.3), cframe(0, 2.2, 1.7), (190, 160, 100), "Metal", theme="titaniumDark"),
        part("TrimB", (3.4, 0.3, 0.3), cframe(0, 2.2, -1.7), (190, 160, 100), "Metal", theme="titaniumDark"),
        part("Crest", (1.2, 1.2, 0.3), cframe(0, 3.2, 1.75, 0, 0, 45), (255, 205, 60), "Neon"),
    ]
    return wall("WallTitanium", "titanium", "titaniumDark", "Metal", (240, 226, 190), (190, 160, 100), trim)


def wall_laser() -> dict:
    children = [
        root(1, 1),
        part("Foot", (4.0, 0.6, 3.6), cframe(0, 0.3, 0), (120, 30, 100), "Metal", theme="laserDark"),
        part("PostL", (0.7, 4.6, 0.7), cframe(-1.65, 2.6, 0), (120, 30, 100), "Metal", theme="laserDark"),
        part("PostR", (0.7, 4.6, 0.7), cframe(1.65, 2.6, 0), (120, 30, 100), "Metal", theme="laserDark"),
        part("Body", (2.6, 4.0, 0.5), cframe(0, 2.6, 0), (255, 90, 200), "Neon", transparency=0.25, theme="laser"),
        part("Cap", (4.0, 0.4, 1.0), cframe(0, 5.1, 0), (120, 30, 100), "Metal", theme="laserDark"),
        point_light("Glow", (255, 90, 200), 0.8, 10),
    ]
    return model("WallLaser", children, "Root", {"PieceId": "WallLaser"})


# ----------------------------------------------------------------------------- traps


def trigger(w_cells=1, d_cells=1, height=3.0, y=None) -> dict:
    y = height / 2 if y is None else y
    return part("Trigger", (w_cells * CELL - 0.4, height, d_cells * CELL - 0.4), cframe(0, y, 0), (255, 0, 0), transparency=1.0, can_collide=False, cast_shadow=False)


def spike_trap() -> dict:
    spikes = []
    for i, (x, z) in enumerate([(-1.1, -1.1), (1.1, -1.1), (-1.1, 1.1), (1.1, 1.1), (0, 0)]):
        # Spikes start retracted (below the plate); the server raises them on trigger.
        spikes.append(wedge(f"Spike{i}", (0.8, 1.6, 0.8), cframe(x, -0.6, z), (220, 220, 230), "Metal", theme="steel", can_collide=False, attributes={"Spike": True}))
    children = [
        root(1, 1),
        part("Plate", (3.6, 0.4, 3.6), cframe(0, 0.2, 0), (230, 70, 70), "Metal", theme="trap"),
        part("Rim", (3.8, 0.2, 3.8), cframe(0, 0.45, 0), (120, 30, 30), "Metal", theme="trapDark"),
        trigger(height=2.5),
    ] + spikes
    return model("SpikeTrap", children, "Root", {"PieceId": "SpikeTrap"})


def flinger() -> dict:
    children = [
        root(1, 1),
        part("Base", (3.6, 0.5, 3.6), cframe(0, 0.25, 0), (120, 30, 30), "Metal", theme="trapDark"),
        part("Spring", (1.2, 0.9, 1.2), cframe(0, 0.95, 0), (200, 200, 210), "Metal", shape="Cylinder", theme="steel"),
        wedge("Paddle", (3.2, 1.2, 3.2), cframe(0, 1.9, 0), (230, 70, 70), "SmoothPlastic", theme="trap", attributes={"Paddle": True}),
        part("Arrow", (0.6, 0.2, 1.6), cframe(0, 2.6, 0.4), (255, 240, 120), "Neon", can_collide=False),
        trigger(height=3.0),
    ]
    return model("Flinger", children, "Root", {"PieceId": "Flinger"})


def flame_jet() -> dict:
    children = [
        root(1, 1),
        part("Grate", (3.6, 0.5, 3.6), cframe(0, 0.25, 0), (70, 74, 90), "DiamondPlate", theme="metal"),
        part("Nozzle", (1.4, 0.6, 1.4), cframe(0, 0.8, 0), (120, 30, 30), "Metal", shape="Cylinder", theme="trapDark"),
        part("Flame", (2.6, 6.0, 2.6), cframe(0, 3.5, 0), (255, 140, 30), "Neon", transparency=1.0, can_collide=False, attributes={"Flame": True}),
        point_light("Glow", (255, 140, 30), 0.0, 14),
        trigger(height=6.0, y=3.5),
    ]
    return model("FlameJet", children, "Root", {"PieceId": "FlameJet"})


def freeze_pad() -> dict:
    crystals = [
        wedge(f"Crystal{i}", (0.7, 1.4 + i * 0.3, 0.7), cframe(x, 0.9 + i * 0.15, z, 0, i * 40, 0), (200, 240, 255), "Glass", can_collide=False)
        for i, (x, z) in enumerate([(-1.2, 1.0), (1.1, -0.8), (0.2, 1.3)])
    ]
    children = [
        root(1, 1),
        part("Plate", (3.6, 0.4, 3.6), cframe(0, 0.2, 0), (160, 230, 255), "Ice", transparency=0.2, theme="accent"),
        trigger(height=2.5),
    ] + crystals
    return model("FreezePad", children, "Root", {"PieceId": "FreezePad"})


def pit() -> dict:
    children = [
        root(2, 2),
        part("Rim", (8.0, 0.4, 8.0), cframe(0, 0.2, 0), (70, 74, 90), "Metal", theme="metal"),
        part("Hole", (6.8, 0.3, 6.8), cframe(0, 0.35, 0), (15, 15, 22), "SmoothPlastic", attributes={"Hole": True}),
        part("Door", (6.6, 0.25, 6.6), cframe(0, 0.55, 0), (120, 78, 40), "WoodPlanks", theme="woodDark", attributes={"Door": True}),
        part("Handle", (1.2, 0.3, 0.4), cframe(0, 0.8, 2.4), (200, 200, 210), "Metal", theme="steel", can_collide=False),
        trigger(2, 2, 2.5),
    ]
    return model("Pit", children, "Root", {"PieceId": "Pit"})


def bear_trap() -> dict:
    children = [
        root(1, 1),
        part("Plate", (3.0, 0.3, 3.0), cframe(0, 0.15, 0), (70, 74, 90), "Metal", theme="metal"),
        wedge("JawL", (2.6, 1.4, 1.2), cframe(0, 0.5, -1.2, -70, 0, 0), (220, 220, 230), "Metal", theme="steel", can_collide=False, attributes={"Jaw": "L"}),
        wedge("JawR", (2.6, 1.4, 1.2), cframe(0, 0.5, 1.2, 70, 180, 0), (220, 220, 230), "Metal", theme="steel", can_collide=False, attributes={"Jaw": "R"}),
        part("Bait", (0.8, 0.5, 0.8), cframe(0, 0.55, 0), (255, 205, 60), "Neon", can_collide=False),
        trigger(height=2.5),
    ]
    return model("BearTrap", children, "Root", {"PieceId": "BearTrap"})


# ----------------------------------------------------------------------------- turrets


def turret_base(name: str, head_children: list, theme_accent="trap") -> dict:
    children = [
        root(1, 1),
        part("Base", (3.6, 0.6, 3.6), cframe(0, 0.3, 0), (70, 74, 90), "Metal", theme="metal"),
        part("Pillar", (1.8, 2.4, 1.8), cframe(0, 1.8, 0), (90, 110, 130), "Metal", shape="Cylinder", theme="steelDark"),
        part("Pivot", (1.2, 0.6, 1.2), cframe(0, 3.3, 0), (70, 74, 90), "Metal", theme="metal"),
    ]
    children.extend(head_children)
    return model(name, children, "Root", {"PieceId": name})


def cannon() -> dict:
    head = [
        part("Head", (2.2, 1.6, 2.2), cframe(0, 4.3, 0), (230, 70, 70), "Metal", theme="trap", attributes={"Head": True}),
        part("Barrel", (0.9, 0.9, 2.6), cframe(0, 4.3, 1.9), (70, 74, 90), "Metal", theme="metal", attributes={"Head": True}),
        attachment("Muzzle", cframe(0, 4.3, 3.3)),
    ]
    return turret_base("Cannon", head)


def zapper() -> dict:
    head = [
        part("Coil", (1.2, 1.4, 1.2), cframe(0, 4.3, 0), (90, 110, 130), "Metal", shape="Cylinder", theme="steelDark", attributes={"Head": True}),
        part("Orb", (2.0, 2.0, 2.0), cframe(0, 5.7, 0), (120, 200, 255), "Neon", shape="Ball", theme="accent", attributes={"Head": True}),
        point_light("Glow", (120, 200, 255), 1.0, 12),
        attachment("Muzzle", cframe(0, 5.7, 0)),
    ]
    return turret_base("Zapper", head)


def goo_gun() -> dict:
    head = [
        part("Tank", (1.8, 2.2, 1.8), cframe(0, 4.6, 0), (120, 220, 90), "Glass", shape="Cylinder", transparency=0.2, attributes={"Head": True}),
        part("Nozzle", (0.7, 0.7, 2.2), cframe(0, 4.0, 1.7), (70, 74, 90), "Metal", theme="metal", attributes={"Head": True}),
        attachment("Muzzle", cframe(0, 4.0, 2.9)),
    ]
    return turret_base("GooGun", head)


# ----------------------------------------------------------------------------- guards (docks)


def guard_dock(name: str, accent, extra: list) -> dict:
    children = [
        root(1, 1),
        part("Pad", (3.6, 0.4, 3.6), cframe(0, 0.2, 0), (70, 74, 90), "DiamondPlate", theme="metal"),
        part("Ring", (3.0, 0.2, 3.0), cframe(0, 0.45, 0), accent, "Neon", shape="Cylinder", transparency=0.3, can_collide=False),
        part("Post", (0.6, 3.0, 0.6), cframe(-1.5, 1.9, -1.5), (90, 110, 130), "Metal", theme="steelDark"),
        part("Lamp", (0.8, 0.8, 0.8), cframe(-1.5, 3.6, -1.5), accent, "Neon", shape="Ball"),
        attachment("Spawn", cframe(0, 3.0, 0)),
    ]
    children.extend(extra)
    return model(name, children, "Root", {"PieceId": name})


def guard_bot() -> dict:
    return guard_dock("GuardBot", (230, 70, 70), [])


def guard_dog() -> dict:
    return guard_dock("GuardDog", (255, 160, 60), [part("Bowl", (1.2, 0.4, 1.2), cframe(1.2, 0.6, 1.2), (200, 200, 210), "Metal", shape="Cylinder", theme="steel")])


# ----------------------------------------------------------------------------- decor


def flag() -> dict:
    children = [
        root(1, 1),
        part("Base", (1.4, 0.4, 1.4), cframe(0, 0.2, 0), (90, 90, 100), "Concrete", theme="metal"),
        part("Pole", (0.4, 8.0, 0.4), cframe(0, 4.2, 0), (200, 200, 210), "Metal", shape="Cylinder", theme="steel", attributes={"Upright": True}),
        part("Cloth", (0.15, 2.2, 3.2), cframe(0.0, 7.0, 1.7), (80, 200, 255), "Fabric", theme="accent", can_collide=False),
        part("Knob", (0.8, 0.8, 0.8), cframe(0, 8.4, 0), (255, 205, 60), "Neon", shape="Ball"),
    ]
    # Upright cylinders: Roblox cylinders lie along X, so rotate 90 about Z.
    children[2]["properties"]["CFrame"] = cframe(0, 4.2, 0, 0, 0, 90)
    return model("Flag", children, "Root", {"PieceId": "Flag"})


def torch() -> dict:
    children = [
        root(1, 1),
        part("Base", (1.2, 0.4, 1.2), cframe(0, 0.2, 0), (90, 90, 100), "Concrete", theme="metal"),
        part("Pole", (0.5, 4.0, 0.5), cframe(0, 2.2, 0, 0, 0, 90), (120, 78, 40), "Wood", shape="Cylinder", theme="woodDark"),
        part("Bowl", (1.4, 0.8, 1.4), cframe(0, 4.4, 0), (70, 74, 90), "Metal", theme="metal"),
        part("Fire", (1.2, 1.4, 1.2), cframe(0, 5.3, 0), (255, 140, 30), "Neon", shape="Ball", can_collide=False),
        point_light("Light", (255, 160, 60), 1.2, 16),
    ]
    return model("Torch", children, "Root", {"PieceId": "Torch"})


def bush() -> dict:
    children = [
        root(1, 1),
        part("Ball1", (3.0, 2.6, 3.0), cframe(0, 1.3, 0), (90, 170, 90), "Grass", shape="Ball", theme="decor"),
        part("Ball2", (2.0, 1.8, 2.0), cframe(1.0, 1.9, 0.8), (90, 170, 90), "Grass", shape="Ball", theme="decor"),
        part("Ball3", (1.8, 1.6, 1.8), cframe(-1.0, 1.7, -0.6), (90, 170, 90), "Grass", shape="Ball", theme="decor"),
    ]
    return model("Bush", children, "Root", {"PieceId": "Bush"})


def rock() -> dict:
    children = [
        root(1, 1),
        part("Rock1", (3.0, 2.2, 2.6), cframe(0, 1.0, 0, 10, 20, 0), (150, 150, 160), "Slate", theme="decorAlt"),
        part("Rock2", (1.8, 1.4, 1.6), cframe(1.1, 0.8, 0.9, 0, 40, 15), (150, 150, 160), "Slate", theme="decorAlt"),
    ]
    return model("Rock", children, "Root", {"PieceId": "Rock"})


def statue() -> dict:
    children = [
        root(1, 1),
        part("Pedestal", (2.6, 1.4, 2.6), cframe(0, 0.7, 0), (150, 150, 160), "Marble", theme="decorAlt"),
        part("Legs", (1.2, 1.6, 0.8), cframe(0, 2.2, 0), (200, 200, 210), "Marble", theme="decorAlt"),
        part("TorsoP", (1.6, 1.8, 0.9), cframe(0, 3.9, 0), (200, 200, 210), "Marble", theme="decorAlt"),
        part("HeadP", (1.0, 1.0, 1.0), cframe(0, 5.3, 0), (200, 200, 210), "Marble", theme="decorAlt"),
        part("Sack", (1.2, 1.2, 1.2), cframe(0.9, 4.6, -0.3), (255, 205, 60), "Fabric"),
        part("Hammer", (0.4, 2.4, 0.4), cframe(-1.2, 3.6, 0, 0, 0, 20), (120, 78, 40), "Wood"),
    ]
    return model("Statue", children, "Root", {"PieceId": "Statue"})


def fountain() -> dict:
    children = [
        root(2, 2),
        part("Basin", (7.2, 1.2, 7.2), cframe(0, 0.6, 0), (150, 150, 160), "Marble", shape="Cylinder", theme="decorAlt"),
        part("Water", (6.4, 0.3, 6.4), cframe(0, 1.1, 0), (80, 200, 255), "Glass", shape="Cylinder", transparency=0.4, can_collide=False),
        part("Column", (1.4, 3.0, 1.4), cframe(0, 2.5, 0), (150, 150, 160), "Marble", shape="Cylinder", theme="decorAlt"),
        part("Top", (3.0, 0.6, 3.0), cframe(0, 4.1, 0), (150, 150, 160), "Marble", shape="Cylinder", theme="decorAlt"),
        part("Spout", (0.8, 0.8, 0.8), cframe(0, 4.7, 0), (80, 200, 255), "Neon", shape="Ball", can_collide=False),
        attachment("Spray", cframe(0, 4.9, 0)),
    ]
    # Cylinders lie along X; stand them up.
    for name in ("Basin", "Water", "Column", "Top"):
        for child in children:
            if child["name"] == name:
                x, y, z = child["properties"]["CFrame"][:3]
                child["properties"]["CFrame"] = cframe(x, y, z, 0, 0, 90)
                s = child["properties"]["Size"]
                child["properties"]["Size"] = [s[1], s[0], s[2]]
    return model("Fountain", children, "Root", {"PieceId": "Fountain"})


BUILDERS = [
    vault, mine,
    wall_wood, wall_stone, wall_steel, wall_titanium, wall_laser,
    spike_trap, flinger, flame_jet, freeze_pad, pit, bear_trap,
    cannon, zapper, goo_gun,
    guard_bot, guard_dog,
    flag, torch, bush, rock, statue, fountain,
]


def fix_upright_cylinders(node: dict) -> None:
    """Cylinders in Roblox lie along X. Any cylinder whose Size has Y as the long axis (we wrote
    them 'as if upright') gets rotated 90 degrees about Z with X/Y sizes swapped."""
    for child in node.get("children", []):
        props = child.get("properties")
        if props and props.get("Shape") == "Cylinder" and child["name"] not in ("Door", "Wheel", "Coin", "Basin", "Water", "Column", "Top", "Pole"):
            sx, sy, sz = props["Size"]
            if sy > sx:
                cf = props["CFrame"]
                props["CFrame"] = cframe(cf[0], cf[1], cf[2], 0, 0, 90)
                props["Size"] = [sy, sx, sz]
        fix_upright_cylinders(child)


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    count = 0
    for builder in BUILDERS:
        node = builder()
        fix_upright_cylinders(node)
        write(os.path.join(OUT, f"{node['name']}.model.json"), node)
        count += 1
    print(f"wrote {count} piece models to {os.path.relpath(OUT)}")


if __name__ == "__main__":
    main()
