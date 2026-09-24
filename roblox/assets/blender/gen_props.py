"""Blender 5.2 generator for the hero meshes of Raid a Base!

Produces one OBJ per piece in assets/export plus manifest.json. Each mesh is modelled at stud
scale with its origin at the footprint centre on the ground, matching the part-built models, so
a MeshPart can replace the Root of the generated model with no offset. Materials are flat colours
that the renderer recolours per theme.

Run from the roblox/ folder:
    blender -b --python assets/blender/gen_props.py -- --out assets/export
"""

from __future__ import annotations

import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402

from export_lib import (  # noqa: E402
    box,
    cone,
    cylinder,
    export_obj,
    flat_material,
    join,
    parse_args,
    reset_scene,
    set_origin_bottom,
    shade_smooth,
    sphere,
    srgb,
    torus,
    triangle_count,
)

CELL = 4.0

# Palette (linear floats from sRGB)
GOLD = flat_material("Gold", srgb(255, 190, 60), 0.35)
GOLD_DARK = flat_material("GoldDark", srgb(150, 100, 20), 0.5)
METAL = flat_material("Metal", srgb(70, 74, 90), 0.4)
STEEL = flat_material("Steel", srgb(200, 210, 220), 0.3)
WOOD = flat_material("Wood", srgb(176, 120, 66), 0.9)
WOOD_DARK = flat_material("WoodDark", srgb(120, 78, 40), 0.9)
STONE = flat_material("Stone", srgb(150, 158, 170), 0.95)
STONE_DARK = flat_material("StoneDark", srgb(100, 108, 122), 0.95)
RED = flat_material("Trap", srgb(230, 70, 70), 0.6)
RED_DARK = flat_material("TrapDark", srgb(120, 30, 30), 0.6)
NEON = flat_material("Neon", srgb(255, 210, 90), 0.2)
GLASS = flat_material("Glass", srgb(160, 230, 255), 0.1)


def z_up(y: float) -> float:
    """Roblox Y (up) becomes Blender Z; helper for readability."""
    return y


# ----------------------------------------------------------------------------- builders


def build_vault():
    parts = [
        box("Base", (7.6, 7.6, 0.6), (0, 0, 0.3), METAL, bevel=0.1),
        box("Body", (6.4, 6.4, 5.6), (0, 0, 3.4), GOLD, bevel=0.35),
        box("BandLow", (6.8, 6.8, 1.0), (0, 0, 1.1), GOLD_DARK, bevel=0.15),
        box("BandHigh", (6.8, 6.8, 0.8), (0, 0, 5.9), GOLD_DARK, bevel=0.15),
        # Door on the +Y (south) face: cylinder along Y
        cylinder("Door", 1.8, 0.6, (0, 3.25, 3.4), GOLD_DARK, verts=32, rotation=(math.pi / 2, 0, 0)),
        torus("Wheel", 0.75, 0.16, (0, 3.65, 3.4), STEEL, rotation=(math.pi / 2, 0, 0)),
        box("Spoke1", (0.25, 0.25, 1.6), (0, 3.7, 3.4), STEEL),
        box("Spoke2", (1.6, 0.25, 0.25), (0, 3.7, 3.4), STEEL),
        cylinder("Coin", 1.0, 0.3, (0, 0, 6.9), NEON, verts=24, rotation=(math.pi / 2, 0, 0)),
    ]
    obj = join(parts, "Vault")
    shade_smooth(obj, 35)
    return obj


def build_mine():
    parts = [
        box("Base", (3.6, 3.6, 0.5), (0, 0, 0.25), METAL, bevel=0.08),
        box("Body", (2.8, 2.8, 2.2), (0, 0, 1.6), WOOD_DARK, bevel=0.15),
        box("Roof", (3.2, 3.2, 0.4), (0, 0, 2.9), WOOD, bevel=0.1),
        cylinder("Chimney", 0.4, 1.6, (1.0, -1.0, 3.7), METAL, verts=12),
        cylinder("Drill", 0.3, 1.6, (0, 0, 3.9), STEEL, verts=12),
        cone("DrillTip", 0.5, 0.0, 0.9, (0, 0, 5.1), STEEL, verts=12),
        box("Gem", (0.9, 0.9, 0.9), (0, 0, 5.6), NEON, bevel=0.2),
        box("Cart", (1.4, 1.0, 0.8), (1.0, 1.4, 0.9), METAL, bevel=0.1),
        sphere("Ore", 0.4, (1.0, 1.4, 1.5), NEON, 10, 6),
    ]
    obj = join(parts, "Mine")
    shade_smooth(obj, 35)
    return obj


def build_wall(name, body_mat, cap_mat, detail):
    parts = [
        box("Body", (4.0, 3.2, 4.4), (0, 0, 2.2), body_mat, bevel=0.12),
        box("Cap", (4.0, 3.6, 0.6), (0, 0, 4.7), cap_mat, bevel=0.12),
        box("Foot", (4.0, 3.6, 0.6), (0, 0, 0.3), cap_mat, bevel=0.12),
    ]
    parts.extend(detail())
    obj = join(parts, name)
    shade_smooth(obj, 30)
    return obj


def wood_detail():
    out = []
    for i in range(3):
        x = -1.35 + i * 1.35
        out.append(box(f"Plank{i}", (0.9, 0.3, 4.0), (x, 1.7, 2.2), WOOD_DARK, bevel=0.05))
        out.append(box(f"PlankB{i}", (0.9, 0.3, 4.0), (x, -1.7, 2.2), WOOD_DARK, bevel=0.05))
    return out


def stone_detail():
    bricks = [(-0.9, 1.4, 1.6), (1.1, 2.6, 1.2), (-0.6, 3.6, 1.4), (0.8, 1.4, 1.6), (-1.0, 2.8, 1.2)]
    out = []
    for i, (x, z, w) in enumerate(bricks):
        y = 1.7 if i < 3 else -1.7
        out.append(box(f"Brick{i}", (w, 0.3, 0.9), (x, y, z), STONE_DARK, bevel=0.05))
    return out


def steel_detail():
    out = []
    for i, (x, z) in enumerate([(-1.3, 1.0), (1.3, 1.0), (-1.3, 3.4), (1.3, 3.4)]):
        out.append(sphere(f"Rivet{i}", 0.25, (x, 1.7, z), STEEL, 8, 5))
        out.append(sphere(f"RivetB{i}", 0.25, (x, -1.7, z), STEEL, 8, 5))
    return out


def build_spike_trap():
    parts = [
        box("Plate", (3.6, 3.6, 0.4), (0, 0, 0.2), RED, bevel=0.08),
        box("Rim", (3.8, 3.8, 0.2), (0, 0, 0.45), RED_DARK, bevel=0.05),
    ]
    for i, (x, y) in enumerate([(-1.1, -1.1), (1.1, -1.1), (-1.1, 1.1), (1.1, 1.1), (0, 0)]):
        parts.append(cone(f"Spike{i}", 0.4, 0.0, 1.6, (x, y, 1.3), STEEL, verts=10))
    obj = join(parts, "SpikeTrap")
    shade_smooth(obj, 40)
    return obj


def build_flinger():
    parts = [
        box("Base", (3.6, 3.6, 0.5), (0, 0, 0.25), RED_DARK, bevel=0.08),
        cylinder("Spring", 0.6, 0.9, (0, 0, 0.95), STEEL, verts=16),
        box("Paddle", (3.2, 3.2, 0.5), (0, 0, 1.7), RED, bevel=0.15),
        box("Arrow", (0.6, 1.6, 0.2), (0, 0.4, 2.05), NEON),
    ]
    obj = join(parts, "Flinger")
    shade_smooth(obj, 35)
    return obj


def build_cannon():
    parts = [
        box("Base", (3.6, 3.6, 0.6), (0, 0, 0.3), METAL, bevel=0.1),
        cylinder("Pillar", 0.9, 2.4, (0, 0, 1.8), STEEL, verts=16),
        box("Pivot", (1.2, 1.2, 0.6), (0, 0, 3.3), METAL, bevel=0.1),
        box("Head", (2.2, 2.2, 1.6), (0, 0, 4.3), RED, bevel=0.25),
        cylinder("Barrel", 0.45, 2.6, (0, 1.9, 4.3), METAL, verts=16, rotation=(math.pi / 2, 0, 0)),
        torus("Muzzle", 0.45, 0.12, (0, 3.2, 4.3), STEEL, rotation=(math.pi / 2, 0, 0)),
    ]
    obj = join(parts, "Cannon")
    shade_smooth(obj, 35)
    return obj


def build_guard_bot():
    parts = [
        box("Pad", (3.6, 3.6, 0.4), (0, 0, 0.2), METAL, bevel=0.08),
        torus("Ring", 1.3, 0.12, (0, 0, 0.5), NEON),
        cylinder("Post", 0.3, 3.0, (-1.5, -1.5, 1.9), STEEL, verts=10),
        sphere("Lamp", 0.4, (-1.5, -1.5, 3.6), RED, 10, 6),
    ]
    obj = join(parts, "GuardBot")
    shade_smooth(obj, 35)
    return obj


BUILDERS = {
    "Vault": build_vault,
    "Mine": build_mine,
    "WallWood": lambda: build_wall("WallWood", WOOD, WOOD_DARK, wood_detail),
    "WallStone": lambda: build_wall("WallStone", STONE, STONE_DARK, stone_detail),
    "WallSteel": lambda: build_wall("WallSteel", STEEL, METAL, steel_detail),
    "SpikeTrap": build_spike_trap,
    "Flinger": build_flinger,
    "Cannon": build_cannon,
    "GuardBot": build_guard_bot,
}


def main() -> None:
    args = parse_args()
    out_dir = os.path.abspath(args.get("out", "assets/export"))
    only = args.get("only")
    manifest = []
    for name, builder in BUILDERS.items():
        if only and name not in str(only).split(","):
            continue
        reset_scene()
        # Materials are recreated per scene reset; rebind globals.
        globals().update(
            GOLD=flat_material("Gold", srgb(255, 190, 60), 0.35),
            GOLD_DARK=flat_material("GoldDark", srgb(150, 100, 20), 0.5),
            METAL=flat_material("Metal", srgb(70, 74, 90), 0.4),
            STEEL=flat_material("Steel", srgb(200, 210, 220), 0.3),
            WOOD=flat_material("Wood", srgb(176, 120, 66), 0.9),
            WOOD_DARK=flat_material("WoodDark", srgb(120, 78, 40), 0.9),
            STONE=flat_material("Stone", srgb(150, 158, 170), 0.95),
            STONE_DARK=flat_material("StoneDark", srgb(100, 108, 122), 0.95),
            RED=flat_material("Trap", srgb(230, 70, 70), 0.6),
            RED_DARK=flat_material("TrapDark", srgb(120, 30, 30), 0.6),
            NEON=flat_material("Neon", srgb(255, 210, 90), 0.2),
            GLASS=flat_material("Glass", srgb(160, 230, 255), 0.1),
        )
        obj = builder()
        set_origin_bottom(obj)
        path = export_obj(obj, out_dir, name)
        dims = obj.dimensions
        manifest.append({
            "id": name,
            "file": os.path.basename(path),
            "triangles": triangle_count(obj),
            "size_studs": [round(dims.x, 2), round(dims.z, 2), round(dims.y, 2)],
            "meshId": "",
        })
        print(f"exported {name}: {manifest[-1]['triangles']} tris -> {path}")
    with open(os.path.join(out_dir, "manifest.json"), "w", encoding="utf-8") as f:
        json.dump({"pieces": manifest, "note": "Fill meshId after Studio bulk import, then copy into src/shared/Data/AssetIds.luau"}, f, indent=2)
    print(f"wrote manifest with {len(manifest)} meshes to {out_dir}")


if __name__ == "__main__":
    main()
