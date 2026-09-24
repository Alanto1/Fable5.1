"""Blender 5.2 piece library for Raid a Base!

Every piece is built from named material GROUPS so the game can recolour by theme and animate
the parts its behaviours expect (Spikes, Paddle, Jaw, Head, Door, Flame, Blade, Vent).
Two outputs:
  * assets/export/meshes.json  - packed geometry per group (Roblox coordinates, Y up) consumed by
                                 tools/gen_meshdata.py -> runtime EditableMesh templates
  * assets/export/<Id>.obj     - optional, for manual Studio import (--obj)

Coordinates: modelled in Blender at stud scale, Z up, +Y = Roblox +Z (south, the entrance
side). The exporter maps (x, y, z) -> (x, z, y) and reverses triangle winding.

Run from roblox/:  blender -b --python assets/blender/gen_props.py -- --out assets/export [--obj]
"""

from __future__ import annotations

import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bmesh  # noqa: E402
import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

from export_lib import export_obj, parse_args, reset_scene  # noqa: E402

CELL = 4.0

# ----------------------------------------------------------------------------- palette
# Colours are sRGB 0-255. `theme` keys match Themes.luau; groups without a theme keep their colour.

PAL = {
    "gold": (255, 190, 60), "goldDark": (150, 100, 20), "metal": (70, 74, 90), "steel": (200, 210, 220),
    "steelDark": (90, 110, 130), "wood": (176, 120, 66), "woodDark": (120, 78, 40), "stone": (150, 158, 170),
    "stoneDark": (100, 108, 122), "titanium": (240, 226, 190), "titaniumDark": (190, 160, 100),
    "laser": (255, 90, 200), "laserDark": (120, 30, 100), "trap": (230, 70, 70), "trapDark": (120, 30, 30),
    "neon": (255, 210, 90), "fire": (255, 140, 30), "ice": (160, 230, 255), "glass": (200, 240, 255),
    "green": (96, 224, 120), "gas": (150, 240, 90), "purple": (186, 110, 255), "black": (20, 20, 28),
    "mine": (120, 90, 70), "mineAccent": (255, 205, 60), "accent": (80, 200, 255), "decor": (90, 170, 90),
    "decorAlt": (150, 150, 160), "white": (245, 245, 250), "ground": (116, 176, 86), "sky": (120, 190, 255),
}


# ----------------------------------------------------------------------------- primitives


def _apply(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    return obj


def box(size, loc=(0, 0, 0), rot=(0, 0, 0), bevel=0.12, segs=2):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc, rotation=[math.radians(r) for r in rot])
    o = bpy.context.active_object
    o.scale = Vector(size)
    _apply(o)
    if bevel > 0:
        m = o.modifiers.new("Bevel", "BEVEL")
        m.width = min(bevel, min(size) * 0.45)
        m.segments = segs
        m.limit_method = "ANGLE"
        bpy.ops.object.modifier_apply(modifier=m.name)
    return o


def cyl(radius, depth, loc=(0, 0, 0), rot=(0, 0, 0), verts=16, bevel=0.06):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=depth, location=loc, rotation=[math.radians(r) for r in rot])
    o = bpy.context.active_object
    _apply(o)
    if bevel > 0:
        m = o.modifiers.new("Bevel", "BEVEL")
        m.width = min(bevel, radius * 0.4, depth * 0.4)
        m.segments = 2
        m.limit_method = "ANGLE"
        bpy.ops.object.modifier_apply(modifier=m.name)
    return o


def cone(r1, r2, depth, loc=(0, 0, 0), rot=(0, 0, 0), verts=12):
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r1, radius2=r2, depth=depth, location=loc, rotation=[math.radians(r) for r in rot])
    return _apply(bpy.context.active_object)


def sphere(radius, loc=(0, 0, 0), segs=16, rings=10, scale=(1, 1, 1)):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segs, ring_count=rings, radius=radius, location=loc)
    o = bpy.context.active_object
    o.scale = Vector(scale)
    return _apply(o)


def torus(major, minor, loc=(0, 0, 0), rot=(0, 0, 0), segs=24, rings=10):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, location=loc, rotation=[math.radians(r) for r in rot], major_segments=segs, minor_segments=rings)
    return _apply(bpy.context.active_object)


def wedge(size, loc=(0, 0, 0), rot=(0, 0, 0)):
    """Triangular prism: flat bottom, vertical back (+Y), slope down toward -Y."""
    w, d, h = size
    verts = [(-w / 2, -d / 2, 0), (w / 2, -d / 2, 0), (w / 2, d / 2, 0), (-w / 2, d / 2, 0), (w / 2, d / 2, h), (-w / 2, d / 2, h)]
    faces = [(0, 1, 2, 3), (2, 4, 5, 3), (0, 3, 5), (1, 4, 2), (0, 5, 4, 1)]
    return mesh_from(verts, faces, "Wedge", loc, rot)


def mesh_from(verts, faces, name="Mesh", loc=(0, 0, 0), rot=(0, 0, 0)):
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.update()
    o = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(o)
    o.location = Vector(loc)
    o.rotation_euler = [math.radians(r) for r in rot]
    return _apply(o)


def spike(r, h, loc, rot=(0, 0, 0)):
    return cone(r, 0.0, h, loc, rot, 8)


# ----------------------------------------------------------------------------- piece builder


class Piece:
    def __init__(self, pid: str, w: int, d: int):
        self.id, self.w, self.d = pid, w, d
        self.groups = []  # dict(name, objects, color, theme, material, attrs, collide, transparency)
        self.attachments = {}
        self.lights = []

    def group(self, name, objects, color, theme=None, material="SmoothPlastic", attrs=None, collide=True, transparency=0.0, smooth=True):
        if isinstance(objects, bpy.types.Object):
            objects = [objects]
        self.groups.append(dict(name=name, objects=objects, color=PAL[color] if isinstance(color, str) else color, theme=theme, material=material, attrs=attrs or {}, collide=collide, transparency=transparency, smooth=smooth))
        return self

    def attach(self, name, pos):
        self.attachments[name] = pos
        return self

    def light(self, pos, color, brightness=1.0, range_=12.0):
        self.lights.append(dict(position=pos, color=PAL[color] if isinstance(color, str) else color, brightness=brightness, range=range_))
        return self


PIECES: dict[str, callable] = {}


def piece(pid, w=1, d=1):
    def deco(fn):
        PIECES[pid] = (fn, w, d)
        return fn
    return deco


# ----------------------------------------------------------------------------- structures


@piece("Vault", 2, 2)
def vault(p: Piece):
    p.group("Base", box((7.6, 7.6, 0.6), (0, 0, 0.3), bevel=0.1), "metal", "metal", "Concrete")
    p.group("Body", box((6.4, 6.4, 5.6), (0, 0, 3.4), bevel=0.45, segs=3), "gold", "vault")
    p.group("Bands", [box((6.9, 6.9, 0.9), (0, 0, 1.1), bevel=0.15), box((6.9, 6.9, 0.7), (0, 0, 5.95), bevel=0.15),
                      box((0.7, 6.9, 5.6), (-3.1, 0, 3.4), bevel=0.1), box((0.7, 6.9, 5.6), (3.1, 0, 3.4), bevel=0.1)], "goldDark", "vaultDark", "Metal")
    p.group("Door", [cyl(1.9, 0.5, (0, 3.35, 3.4), (90, 0, 0), 32, 0.08), torus(1.55, 0.14, (0, 3.6, 3.4), (90, 0, 0))], "goldDark", "vaultDark", "Metal")
    p.group("Wheel", [torus(0.8, 0.14, (0, 3.75, 3.4), (90, 0, 0), 24, 8), box((0.22, 0.22, 1.7), (0, 3.78, 3.4), bevel=0.03), box((1.7, 0.22, 0.22), (0, 3.78, 3.4), bevel=0.03), sphere(0.24, (0, 3.9, 3.4), 10, 6)], "steel", "steel", "Metal")
    p.group("Coin", [cyl(1.0, 0.28, (0, 0, 6.9), (90, 0, 0), 24, 0.05), box((0.35, 0.3, 1.1), (0, 0, 6.9), bevel=0.05)], "neon", None, "Neon", collide=False)
    p.attach("Top", (0, 7.6, 0))


@piece("Mine")
def mine(p: Piece):
    p.group("Base", box((3.6, 3.6, 0.5), (0, 0, 0.25), bevel=0.08), "metal", "metal", "Concrete")
    p.group("Body", box((2.8, 2.8, 2.2), (0, 0, 1.6), bevel=0.15), "mine", "mine", "WoodPlanks")
    p.group("Roof", [box((3.3, 3.3, 0.35), (0, 0, 2.9), bevel=0.1), box((3.0, 0.4, 0.4), (0, 1.5, 3.2), bevel=0.08)], "mineAccent", "mineAccent", "Wood")
    p.group("Machinery", [cyl(0.4, 1.6, (1.0, -1.0, 3.7), verts=12), cyl(0.3, 1.5, (0, 0, 3.85), verts=12), cone(0.5, 0.0, 0.9, (0, 0, 5.05)), cyl(0.9, 0.3, (0.9, 0.9, 3.2), verts=16)], "steel", "steel", "Metal")
    p.group("Gem", [box((0.8, 0.8, 0.8), (0, 0, 5.6), (45, 0, 45), bevel=0.15), sphere(0.42, (1.0, 1.4, 1.5), 10, 6)], "neon", None, "Neon", collide=False)
    p.group("Cart", box((1.4, 1.0, 0.8), (1.0, 1.4, 0.9), bevel=0.1), "metal", "metal", "Metal")
    p.attach("Top", (0, 5.6, 0))


# ----------------------------------------------------------------------------- walls


def wall_common(p: Piece, body, dark, material="SmoothPlastic"):
    p.group("Body", box((4.0, 3.2, 4.4), (0, 0, 2.2), bevel=0.18, segs=3), body, body, material)
    p.group("Trim", [box((4.0, 3.6, 0.6), (0, 0, 4.7), bevel=0.14), box((4.0, 3.6, 0.6), (0, 0, 0.3), bevel=0.14)], dark, dark, material)


@piece("WallWood")
def wall_wood(p: Piece):
    wall_common(p, "wood", "woodDark", "WoodPlanks")
    planks = []
    for i in range(3):
        x = -1.35 + i * 1.35
        planks += [box((0.9, 0.28, 3.9), (x, 1.66, 2.2), bevel=0.06), box((0.9, 0.28, 3.9), (x, -1.66, 2.2), bevel=0.06)]
    planks += [box((3.8, 0.3, 0.5), (0, 1.75, 2.2), (0, 0, 0), bevel=0.05)]
    p.group("Planks", planks, "woodDark", "woodDark", "Wood")


@piece("WallStone")
def wall_stone(p: Piece):
    wall_common(p, "stone", "stoneDark", "Slate")
    bricks = []
    for (x, z, w, y) in [(-0.9, 1.4, 1.6, 1.68), (1.1, 2.6, 1.2, 1.68), (-0.6, 3.6, 1.4, 1.68), (0.8, 1.4, 1.6, -1.68), (-1.0, 2.8, 1.2, -1.68), (0.9, 3.7, 1.0, -1.68)]:
        bricks.append(box((w, 0.28, 0.85), (x, y, z), bevel=0.06))
    p.group("Bricks", bricks, "stoneDark", "stoneDark", "Slate")


@piece("WallSteel")
def wall_steel(p: Piece):
    wall_common(p, "steel", "steelDark", "Metal")
    rivets = []
    for (x, z) in [(-1.3, 1.0), (1.3, 1.0), (-1.3, 3.4), (1.3, 3.4)]:
        rivets += [sphere(0.26, (x, 1.68, z), 8, 5), sphere(0.26, (x, -1.68, z), 8, 5)]
    rivets += [box((3.2, 0.25, 0.4), (0, 1.7, 2.2), bevel=0.05), box((3.2, 0.25, 0.4), (0, -1.7, 2.2), bevel=0.05)]
    p.group("Rivets", rivets, "steelDark", "steelDark", "Metal")


@piece("WallTitanium")
def wall_titanium(p: Piece):
    wall_common(p, "titanium", "titaniumDark", "Metal")
    p.group("Trim2", [box((3.4, 0.3, 0.3), (0, 1.7, 2.2), bevel=0.05), box((3.4, 0.3, 0.3), (0, -1.7, 2.2), bevel=0.05)], "titaniumDark", "titaniumDark", "Metal")
    p.group("Crest", [box((1.1, 0.3, 1.1), (0, 1.8, 3.1), (45, 0, 0), bevel=0.08), box((1.1, 0.3, 1.1), (0, -1.8, 3.1), (45, 0, 0), bevel=0.08)], "neon", None, "Neon", collide=False)


@piece("WallLaser")
def wall_laser(p: Piece):
    p.group("Frame", [box((4.0, 3.6, 0.6), (0, 0, 0.3), bevel=0.12), box((0.7, 0.9, 4.8), (-1.65, 0, 2.6), bevel=0.1), box((0.7, 0.9, 4.8), (1.65, 0, 2.6), bevel=0.1), box((4.0, 1.0, 0.4), (0, 0, 5.15), bevel=0.1)], "laserDark", "laserDark", "Metal")
    p.group("Emitters", [sphere(0.28, (-1.65, 0, 4.4), 8, 5), sphere(0.28, (1.65, 0, 4.4), 8, 5), sphere(0.28, (-1.65, 0, 1.0), 8, 5), sphere(0.28, (1.65, 0, 1.0), 8, 5)], "laser", "laser", "Neon", collide=False)
    p.group("Body", box((2.6, 0.35, 4.0), (0, 0, 2.6), bevel=0.05), "laser", "laser", "Neon", transparency=0.25)
    p.light((0, 2.6, 0), "laser", 0.8, 10)


# ----------------------------------------------------------------------------- traps


def plate(p: Piece, color="trap", theme="trap", rim="trapDark", rim_theme="trapDark"):
    p.group("Plate", box((3.6, 3.6, 0.4), (0, 0, 0.2), bevel=0.1), color, theme, "Metal")
    p.group("Rim", box((3.9, 3.9, 0.18), (0, 0, 0.45), bevel=0.05), rim, rim_theme, "Metal")


@piece("SpikeTrap")
def spike_trap(p: Piece):
    plate(p)
    spikes = [spike(0.42, 1.7, (x, y, -0.65)) for (x, y) in [(-1.1, -1.1), (1.1, -1.1), (-1.1, 1.1), (1.1, 1.1), (0, 0)]]
    p.group("Spikes", spikes, "steel", "steel", "Metal", attrs={"Spike": True}, collide=False)
    p.group("Holes", [cyl(0.5, 0.1, (x, y, 0.5), verts=10, bevel=0) for (x, y) in [(-1.1, -1.1), (1.1, -1.1), (-1.1, 1.1), (1.1, 1.1), (0, 0)]], "black", None, "SmoothPlastic", collide=False)


@piece("Flinger")
def flinger(p: Piece):
    p.group("Base", box((3.6, 3.6, 0.5), (0, 0, 0.25), bevel=0.1), "trapDark", "trapDark", "Metal")
    p.group("Spring", [torus(0.55, 0.12, (0, 0, 0.6 + i * 0.22), (0, 0, 0), 14, 6) for i in range(4)], "steel", "steel", "Metal", collide=False)
    p.group("Paddle", [box((3.2, 3.2, 0.45), (0, 0, 1.7), bevel=0.14), box((0.7, 1.7, 0.16), (0, 0.5, 2.02), bevel=0.03), cone(0.55, 0.0, 0.6, (0, 1.5, 2.02), (-90, 0, 0), 4)], "trap", "trap", "SmoothPlastic", attrs={"Paddle": True})


@piece("FlameJet")
def flame_jet(p: Piece):
    p.group("Grate", [box((3.6, 3.6, 0.5), (0, 0, 0.25), bevel=0.1)] + [box((3.2, 0.25, 0.12), (0, -1.2 + i * 0.6, 0.55), bevel=0.02) for i in range(5)], "metal", "metal", "DiamondPlate")
    p.group("Nozzle", [cyl(0.75, 0.7, (0, 0, 0.85), verts=16), cone(0.75, 0.5, 0.35, (0, 0, 1.35), verts=16)], "trapDark", "trapDark", "Metal")
    p.group("Flame", [cone(1.3, 0.2, 5.5, (0, 0, 4.2), verts=12)], "fire", None, "Neon", attrs={"Flame": True}, collide=False, transparency=1.0)
    p.light((0, 2.0, 0), "fire", 0.0, 14)


@piece("FreezePad")
def freeze_pad(p: Piece):
    p.group("Plate", box((3.6, 3.6, 0.4), (0, 0, 0.2), bevel=0.1), "ice", "accent", "Ice", transparency=0.15)
    p.group("Rim", box((3.9, 3.9, 0.18), (0, 0, 0.45), bevel=0.05), "steel", "steel", "Metal")
    crystals = []
    for i, (x, y) in enumerate([(-1.1, 0.9), (1.0, -0.7), (0.2, 1.2), (-0.4, -1.2)]):
        crystals.append(cone(0.45, 0.0, 1.3 + i * 0.3, (x, y, 1.0 + i * 0.15), (0, i * 25 - 20, i * 40), 6))
    p.group("Crystals", crystals, "glass", None, "Glass", collide=False, transparency=0.15)


@piece("Pit", 2, 2)
def pit(p: Piece):
    p.group("Rim", box((8.0, 8.0, 0.4), (0, 0, 0.2), bevel=0.1), "metal", "metal", "Metal")
    p.group("Hole", box((6.9, 6.9, 0.25), (0, 0, 0.36), bevel=0.02), "black", None, "SmoothPlastic", collide=True)
    p.group("Door", [box((3.2, 6.6, 0.25), (-1.7, 0, 0.58), bevel=0.05), box((3.2, 6.6, 0.25), (1.7, 0, 0.58), bevel=0.05), box((0.4, 6.4, 0.3), (-1.7, 0, 0.72), bevel=0.03), box((0.4, 6.4, 0.3), (1.7, 0, 0.72), bevel=0.03)], "woodDark", "woodDark", "WoodPlanks", attrs={"Door": True})
    p.group("Handle", [torus(0.4, 0.08, (-1.7, 2.4, 0.8), (90, 0, 0), 12, 6), torus(0.4, 0.08, (1.7, 2.4, 0.8), (90, 0, 0), 12, 6)], "steel", "steel", "Metal", collide=False)


@piece("BearTrap")
def bear_trap(p: Piece):
    p.group("Plate", [box((3.0, 3.0, 0.3), (0, 0, 0.15), bevel=0.08), box((0.4, 3.4, 0.2), (0, 0, 0.35), bevel=0.03)], "metal", "metal", "Metal")
    teeth_l = [box((2.7, 0.35, 0.7), (0, -1.35, 0.55), bevel=0.05)] + [spike(0.16, 0.6, (-1.0 + i * 0.5, -1.35, 1.1)) for i in range(5)]
    teeth_r = [box((2.7, 0.35, 0.7), (0, 1.35, 0.55), bevel=0.05)] + [spike(0.16, 0.6, (-1.0 + i * 0.5, 1.35, 1.1)) for i in range(5)]
    p.group("JawL", teeth_l, "steel", "steel", "Metal", attrs={"Jaw": "L"}, collide=False)
    p.group("JawR", teeth_r, "steel", "steel", "Metal", attrs={"Jaw": "R"}, collide=False)
    p.group("Bait", cyl(0.45, 0.35, (0, 0, 0.55), verts=12), "neon", None, "Neon", collide=False)


@piece("SpinningBlade")
def spinning_blade(p: Piece):
    p.group("Base", box((3.6, 3.6, 0.5), (0, 0, 0.25), bevel=0.1), "metal", "metal", "DiamondPlate")
    p.group("Hub", [cyl(0.7, 1.4, (0, 0, 1.2), verts=16), cyl(0.9, 0.3, (0, 0, 0.6), verts=16)], "trapDark", "trapDark", "Metal")
    blades = []
    for angle in (0, 120, 240):
        blades.append(box((3.4, 0.5, 0.14), (math.cos(math.radians(angle)) * 1.7, math.sin(math.radians(angle)) * 1.7, 1.5), (0, 0, angle), bevel=0.04))
        blades.append(wedge((0.5, 1.2, 0.5), (math.cos(math.radians(angle)) * 3.3, math.sin(math.radians(angle)) * 3.3, 1.43), (0, 0, angle + 90)))
    p.group("Blades", blades, "steel", "steel", "Metal", attrs={"Blade": True}, collide=False)
    p.group("Warning", [cyl(1.9, 0.06, (0, 0, 0.53), verts=24, bevel=0)], "trap", "trap", "Neon", collide=False, transparency=0.5)


@piece("DartLauncher")
def dart_launcher(p: Piece):
    p.group("Base", box((3.6, 3.6, 0.5), (0, 0, 0.25), bevel=0.1), "metal", "metal", "Metal")
    p.group("Housing", [box((3.0, 1.6, 3.6), (0, -0.9, 2.3), bevel=0.2), box((3.2, 0.6, 0.6), (0, -1.7, 4.0), bevel=0.1)], "trapDark", "trapDark", "Metal")
    barrels = [cyl(0.32, 1.2, (x, 0.2, z), (90, 0, 0), 12, 0.03) for x in (-0.9, 0, 0.9) for z in (1.6, 2.7)]
    p.group("Barrels", barrels, "steel", "steel", "Metal", attrs={"Barrel": True}, collide=False)
    p.group("Eye", [sphere(0.35, (0, -0.2, 3.5), 10, 6)], "trap", "trap", "Neon", collide=False)
    p.attach("Muzzle", (0, 2.2, 0.9))


@piece("GasVent")
def gas_vent(p: Piece):
    p.group("Grate", [box((3.6, 3.6, 0.4), (0, 0, 0.2), bevel=0.1)] + [box((0.22, 3.0, 0.12), (-1.2 + i * 0.6, 0, 0.45), bevel=0.02) for i in range(5)], "metal", "metal", "DiamondPlate")
    p.group("Vent", [cyl(1.0, 0.5, (0, 0, 0.6), verts=16), cone(1.0, 0.6, 0.4, (0, 0, 1.05), verts=16)], "gas", None, "Neon", attrs={"Vent": True}, collide=False, transparency=0.3)
    p.group("Tanks", [cyl(0.45, 1.6, (-1.3, 1.2, 0.9), (90, 0, 0), 12), cyl(0.45, 1.6, (1.3, 1.2, 0.9), (90, 0, 0), 12)], "green", None, "Metal")
    p.attach("Vent", (0, 1.4, 0))


# ----------------------------------------------------------------------------- turrets


def turret_base(p: Piece):
    p.group("Base", box((3.6, 3.6, 0.6), (0, 0, 0.3), bevel=0.12), "metal", "metal", "Metal")
    p.group("Pillar", [cyl(0.95, 2.4, (0, 0, 1.8), verts=16), torus(0.95, 0.12, (0, 0, 0.7), (0, 0, 0), 16, 6)], "steelDark", "steelDark", "Metal")
    p.group("Pivot", cyl(0.75, 0.6, (0, 0, 3.3), verts=16), "metal", "metal", "Metal")


@piece("Cannon")
def cannon(p: Piece):
    turret_base(p)
    p.group("Head", [box((2.3, 2.3, 1.6), (0, 0, 4.3), bevel=0.3, segs=3), box((0.5, 0.5, 0.8), (0, -0.9, 5.3), bevel=0.08)], "trap", "trap", "Metal", attrs={"Head": True})
    p.group("Barrel", [cyl(0.5, 2.6, (0, 1.9, 4.3), (90, 0, 0), 16), torus(0.55, 0.13, (0, 3.15, 4.3), (90, 0, 0), 16, 6)], "metal", "metal", "Metal", attrs={"Head": True})
    p.attach("Muzzle", (0, 4.3, 3.3))


@piece("Zapper")
def zapper(p: Piece):
    turret_base(p)
    p.group("Coil", [torus(0.7, 0.12, (0, 0, 3.9 + i * 0.3), (0, 0, 0), 16, 6) for i in range(4)] + [cyl(0.4, 1.6, (0, 0, 4.4), verts=12)], "steelDark", "steelDark", "Metal", attrs={"Head": True})
    p.group("Orb", sphere(1.05, (0, 0, 5.8), 16, 10), "accent", "accent", "Neon", attrs={"Head": True}, collide=False)
    p.light((0, 5.8, 0), "accent", 1.0, 12)
    p.attach("Muzzle", (0, 5.8, 0))


@piece("GooGun")
def goo_gun(p: Piece):
    turret_base(p)
    p.group("Tank", [cyl(0.95, 2.2, (0, 0, 4.6), verts=16), torus(0.95, 0.1, (0, 0, 5.5), (0, 0, 0), 16, 6)], "gas", None, "Glass", attrs={"Head": True}, transparency=0.2)
    p.group("Nozzle", [cyl(0.36, 2.2, (0, 1.7, 4.0), (90, 0, 0), 12), cone(0.5, 0.36, 0.5, (0, 2.9, 4.0), (-90, 0, 0), 12)], "metal", "metal", "Metal", attrs={"Head": True})
    p.attach("Muzzle", (0, 4.0, 2.9))


# ----------------------------------------------------------------------------- guard docks


def dock(p: Piece, accent, extra=None):
    p.group("Pad", box((3.6, 3.6, 0.4), (0, 0, 0.2), bevel=0.1), "metal", "metal", "DiamondPlate")
    p.group("Ring", torus(1.35, 0.12, (0, 0, 0.45), (0, 0, 0), 24, 6), accent, None, "Neon", collide=False)
    p.group("Post", [cyl(0.32, 3.0, (-1.5, -1.5, 1.9), verts=10), box((0.7, 0.7, 0.2), (-1.5, -1.5, 3.45), bevel=0.04)], "steelDark", "steelDark", "Metal")
    p.group("Lamp", sphere(0.4, (-1.5, -1.5, 3.75), 10, 6), accent, None, "Neon", collide=False)
    for g in extra or []:
        p.group(*g)
    p.attach("Spawn", (0, 3.0, 0))


@piece("GuardBot")
def guard_bot(p: Piece):
    dock(p, "trap")


@piece("GuardDog")
def guard_dog(p: Piece):
    dock(p, "fire", [("Bowl", cyl(0.6, 0.35, (1.2, 1.2, 0.6), verts=12), "steel", "steel", "Metal")])


@piece("Sentinel")
def sentinel(p: Piece):
    dock(p, "purple", [("Plates", [box((0.9, 0.5, 2.6), (1.4, -1.4, 1.5), (0, 0, 45), bevel=0.06), box((0.9, 0.5, 2.6), (1.4, 1.4, 1.5), (0, 0, -45), bevel=0.06)], "purple", None, "Metal")])


# ----------------------------------------------------------------------------- decor


@piece("Flag")
def flag(p: Piece):
    p.group("Base", cyl(0.8, 0.4, (0, 0, 0.2), verts=12), "metal", "metal", "Concrete")
    p.group("Pole", cyl(0.18, 8.2, (0, 0, 4.3), verts=10), "steel", "steel", "Metal")
    p.group("Cloth", wedge((0.14, 3.2, 2.2), (0, 1.7, 5.9), (0, 0, 0)), "accent", "accent", "Fabric", collide=False)
    p.group("Knob", sphere(0.36, (0, 0, 8.6), 10, 6), "neon", None, "Neon", collide=False)


@piece("Torch")
def torch(p: Piece):
    p.group("Base", cyl(0.7, 0.4, (0, 0, 0.2), verts=12), "metal", "metal", "Concrete")
    p.group("Pole", cyl(0.24, 4.0, (0, 0, 2.2), verts=10), "woodDark", "woodDark", "Wood")
    p.group("Bowl", cone(0.75, 0.45, 0.9, (0, 0, 4.45), verts=12), "metal", "metal", "Metal")
    p.group("Fire", [cone(0.55, 0.0, 1.5, (0, 0, 5.5), verts=8), cone(0.35, 0.0, 1.0, (0.2, 0.15, 5.3), (0, 20, 0), 6)], "fire", None, "Neon", collide=False)
    p.light((0, 5.4, 0), "fire", 1.2, 16)


@piece("Bush")
def bush(p: Piece):
    p.group("Leaves", [sphere(1.5, (0, 0, 1.3), 12, 8, (1, 1, 0.85)), sphere(1.0, (1.0, 0.8, 1.9), 10, 6), sphere(0.9, (-1.0, -0.6, 1.7), 10, 6), sphere(0.8, (-0.4, 1.1, 2.2), 10, 6)], "decor", "decor", "Grass")
    p.group("Berries", [sphere(0.18, (0.9, -0.9, 2.1), 6, 4), sphere(0.18, (-1.3, 0.4, 1.5), 6, 4), sphere(0.18, (0.3, 1.5, 1.4), 6, 4)], "trap", None, "SmoothPlastic", collide=False)


@piece("Rock")
def rock(p: Piece):
    p.group("Rocks", [box((3.0, 2.6, 2.2), (0, 0, 1.0), (10, 20, 15), bevel=0.4, segs=3), box((1.8, 1.6, 1.4), (1.1, 0.9, 0.7), (0, 40, 15), bevel=0.3, segs=3), box((1.2, 1.0, 0.9), (-1.2, -0.8, 0.45), (20, 0, 30), bevel=0.25, segs=3)], "decorAlt", "decorAlt", "Slate")


@piece("Statue")
def statue(p: Piece):
    p.group("Pedestal", [box((2.6, 2.6, 1.4), (0, 0, 0.7), bevel=0.12), box((2.2, 2.2, 0.3), (0, 0, 1.55), bevel=0.05)], "decorAlt", "decorAlt", "Marble")
    figure = [box((1.2, 0.8, 1.6), (0, 0, 2.5), bevel=0.15), box((1.6, 0.9, 1.8), (0, 0, 4.2), bevel=0.2), sphere(0.6, (0, 0, 5.6), 12, 8), box((0.5, 0.5, 1.6), (-1.15, 0, 4.1), (0, 0, 20), bevel=0.1), box((0.5, 0.5, 1.6), (1.15, -0.2, 4.1), (25, 0, -20), bevel=0.1)]
    p.group("Figure", figure, "decorAlt", "decorAlt", "Marble")
    p.group("Sack", sphere(0.7, (0.9, -0.5, 4.8), 10, 6), "gold", None, "Fabric", collide=False)
    p.group("Hammer", [cyl(0.14, 2.4, (-1.4, 0.4, 4.4), (0, 20, 0), 8), box((1.1, 0.6, 0.6), (-1.0, 0.4, 5.5), bevel=0.1)], "wood", None, "Wood", collide=False)


@piece("Fountain", 2, 2)
def fountain(p: Piece):
    p.group("Basin", [cyl(3.6, 1.2, (0, 0, 0.6), verts=24), torus(3.4, 0.25, (0, 0, 1.2), (0, 0, 0), 24, 8)], "decorAlt", "decorAlt", "Marble")
    p.group("Water", cyl(3.2, 0.25, (0, 0, 1.1), verts=24, bevel=0), "accent", None, "Glass", collide=False, transparency=0.35)
    p.group("Column", [cyl(0.7, 3.0, (0, 0, 2.6), verts=16), cyl(1.6, 0.5, (0, 0, 4.2), verts=20), cyl(0.9, 0.3, (0, 0, 4.55), verts=16)], "decorAlt", "decorAlt", "Marble")
    p.group("Spout", sphere(0.42, (0, 0, 4.9), 10, 6), "accent", None, "Neon", collide=False)
    p.attach("Spray", (0, 4.9, 0))


# ----------------------------------------------------------------------------- hub props (not placeable)

HUB: dict[str, callable] = {}


def hubprop(pid):
    def deco(fn):
        HUB[pid] = fn
        return fn
    return deco


@hubprop("Tree")
def tree(p: Piece):
    p.group("Trunk", [cyl(0.8, 6.0, (0, 0, 3.0), verts=10), cyl(1.1, 0.8, (0, 0, 0.4), verts=10)], "woodDark", None, "Wood")
    p.group("Leaves", [sphere(3.4, (0, 0, 7.5), 14, 9, (1, 1, 0.8)), sphere(2.4, (1.6, 1.0, 9.4), 12, 8), sphere(2.2, (-1.8, -0.6, 9.0), 12, 8), sphere(2.0, (0.2, -1.8, 10.2), 12, 8)], "decor", None, "Grass")


@hubprop("PalmTree")
def palm(p: Piece):
    p.group("Trunk", [cyl(0.55, 9.0, (0.3, 0, 4.5), (0, 8, 0), 10)], "wood", None, "Wood")
    fronds = []
    for i in range(6):
        a = i * 60
        fronds.append(wedge((1.6, 5.0, 0.5), (math.cos(math.radians(a)) * 2.4 + 0.9, math.sin(math.radians(a)) * 2.4, 8.6), (25, 0, a + 90)))
    p.group("Fronds", fronds, "decor", None, "Grass", collide=False)
    p.group("Coconuts", [sphere(0.4, (0.9, 0.4, 8.3), 8, 5), sphere(0.4, (1.4, -0.5, 8.2), 8, 5)], "woodDark", None, "SmoothPlastic", collide=False)


@hubprop("LampPost")
def lamp_post(p: Piece):
    p.group("Post", [cyl(0.6, 0.5, (0, 0, 0.25), verts=12), cyl(0.22, 8.0, (0, 0, 4.2), verts=10), box((2.0, 0.3, 0.3), (0.9, 0, 8.2), bevel=0.04)], "metal", None, "Metal")
    p.group("Lamp", [sphere(0.6, (1.8, 0, 7.8), 12, 8)], "neon", None, "Neon", collide=False)
    p.light((1.8, 7.8, 0), "neon", 1.2, 24)


@hubprop("Signpost")
def signpost(p: Piece):
    p.group("Post", cyl(0.25, 6.0, (0, 0, 3.0), verts=10), "woodDark", None, "Wood")
    p.group("Board", [box((6.0, 0.4, 1.6), (0, 0, 5.2), bevel=0.1), wedge((0.9, 0.4, 1.6), (3.45, 0, 4.4), (0, 0, 0))], "wood", None, "WoodPlanks", attrs={"Sign": True})


@hubprop("PortalArch")
def portal_arch(p: Piece):
    p.group("Arch", [torus(10.0, 1.2, (0, 0, 10.0), (90, 0, 0), 32, 10), box((3.0, 3.0, 2.0), (-10, 0, 1.0), bevel=0.2), box((3.0, 3.0, 2.0), (10, 0, 1.0), bevel=0.2)], "metal", None, "Metal")
    p.group("Ring", torus(10.0, 0.4, (0, 0.9, 10.0), (90, 0, 0), 32, 8), "gold", None, "Neon", collide=False)
    p.group("Disc", cyl(9.0, 0.3, (0, 0, 0.35), verts=32, bevel=0), "gold", None, "Neon", collide=False, transparency=0.15)
    p.light((0, 10, 0), "gold", 1.5, 40)


@hubprop("ShopStall")
def shop_stall(p: Piece):
    p.group("Counter", [box((12, 5, 3.0), (0, 0, 1.5), bevel=0.15), box((12.6, 5.6, 0.4), (0, 0, 3.2), bevel=0.08)], "wood", None, "WoodPlanks")
    p.group("Posts", [box((0.8, 0.8, 8.0), (-5.5, -2.0, 4.0), bevel=0.08), box((0.8, 0.8, 8.0), (5.5, -2.0, 4.0), bevel=0.08), box((0.8, 0.8, 8.0), (-5.5, 2.0, 4.0), bevel=0.08), box((0.8, 0.8, 8.0), (5.5, 2.0, 4.0), bevel=0.08)], "woodDark", None, "Wood")
    stripes = []
    for i in range(6):
        stripes.append(box((2.3, 7.5, 0.5), (-5.75 + i * 2.3, 0, 8.4), (0, 0, 0), bevel=0.05))
    p.group("Roof", stripes[0::2], "trap", None, "Fabric")
    p.group("RoofAlt", stripes[1::2], "white", None, "Fabric")
    p.group("Gems", [box((1.3, 1.3, 1.3), (-2.5, 0, 4.0), (45, 0, 45), bevel=0.15), box((1.0, 1.0, 1.0), (0, 0.4, 3.9), (45, 0, 45), bevel=0.12), box((1.5, 1.5, 1.5), (2.6, -0.2, 4.1), (45, 0, 45), bevel=0.15)], "purple", None, "Neon", collide=False)


@hubprop("Bench")
def bench(p: Piece):
    p.group("Seat", [box((5.0, 1.6, 0.35), (0, 0, 1.6), bevel=0.06), box((5.0, 0.35, 1.6), (0, -0.9, 2.5), (15, 0, 0), bevel=0.06)], "wood", None, "WoodPlanks")
    p.group("Legs", [box((0.4, 1.4, 1.6), (-2.1, 0, 0.8), bevel=0.04), box((0.4, 1.4, 1.6), (2.1, 0, 0.8), bevel=0.04)], "metal", None, "Metal")


@hubprop("FlowerBed")
def flower_bed(p: Piece):
    p.group("Bed", [cyl(2.6, 0.7, (0, 0, 0.35), verts=20)], "woodDark", None, "Ground")
    p.group("Soil", cyl(2.3, 0.2, (0, 0, 0.75), verts=20, bevel=0), "mine", None, "Ground", collide=False)
    flowers = []
    for i in range(9):
        a = i * 40
        r = 0.6 + (i % 3) * 0.55
        flowers.append(sphere(0.35, (math.cos(math.radians(a)) * r, math.sin(math.radians(a)) * r, 1.2 + (i % 2) * 0.2), 8, 5))
    p.group("Flowers", flowers[0::2], "trap", None, "SmoothPlastic", collide=False)
    p.group("Flowers2", flowers[1::2], "neon", None, "SmoothPlastic", collide=False)
    p.group("Stems", [cyl(0.05, 0.6, (math.cos(math.radians(i * 40)) * (0.6 + (i % 3) * 0.55), math.sin(math.radians(i * 40)) * (0.6 + (i % 3) * 0.55), 1.0), verts=5, bevel=0) for i in range(9)], "decor", None, "SmoothPlastic", collide=False)


@hubprop("Board")
def board(p: Piece):
    p.group("Frame", [box((14.6, 1.2, 9.6), (0, 0, 6.8), bevel=0.2), box((1.4, 1.4, 12), (-6.4, 0, 6), bevel=0.1), box((1.4, 1.4, 12), (6.4, 0, 6), bevel=0.1)], "metal", None, "Metal")
    p.group("Screen", box((13.6, 0.6, 8.6), (0, 0.4, 6.8), bevel=0.05), (34, 38, 62), None, "SmoothPlastic", attrs={"Screen": True})
    p.group("Trim", box((14.0, 0.4, 0.9), (0, 0.55, 11.6), bevel=0.05), "gold", None, "Neon", collide=False)


@hubprop("Crate")
def crate(p: Piece):
    p.group("Box", box((3, 3, 3), (0, 0, 1.5), bevel=0.15), "wood", None, "WoodPlanks")
    p.group("Bands", [box((3.15, 3.15, 0.4), (0, 0, 0.8), bevel=0.03), box((3.15, 3.15, 0.4), (0, 0, 2.2), bevel=0.03)], "metal", None, "Metal")


@hubprop("Fence")
def fence(p: Piece):
    posts = [box((0.5, 0.5, 2.6), (x, 0, 1.3), bevel=0.05) for x in (-3.75, -1.25, 1.25, 3.75)]
    p.group("Posts", posts, "woodDark", None, "Wood")
    p.group("Rails", [box((8.4, 0.3, 0.5), (0, 0, 1.0), bevel=0.05), box((8.4, 0.3, 0.5), (0, 0, 2.0), bevel=0.05)], "wood", None, "WoodPlanks")


# ----------------------------------------------------------------------------- export


def group_geometry(objects, smooth):
    """Join objects, triangulate, and return split vertices (pos+normal) and triangle indices in
    ROBLOX coordinates: (x, y, z)_roblox = (x, z, y)_blender, winding reversed for the reflection."""
    bpy.ops.object.select_all(action="DESELECT")
    for o in objects:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    if len(objects) > 1:
        bpy.ops.object.join()
    obj = bpy.context.active_object
    if smooth:
        bpy.ops.object.shade_smooth_by_angle(angle=math.radians(38))
    else:
        bpy.ops.object.shade_flat()
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bm.to_mesh(me)
    bm.free()
    me.update()
    # Corner normals (respect smooth-by-angle)
    corner_normals = [ln.vector.copy() for ln in me.corner_normals] if hasattr(me, "corner_normals") else None
    verts_out, index_of = [], {}
    tris = []
    bounds_min = [1e9, 1e9, 1e9]
    bounds_max = [-1e9, -1e9, -1e9]
    for poly in me.polygons:
        ids = []
        for li in poly.loop_indices:
            vi = me.loops[li].vertex_index
            co = obj.matrix_world @ me.vertices[vi].co
            n = corner_normals[li] if corner_normals is not None else poly.normal
            n = (obj.matrix_world.to_3x3() @ n).normalized()
            rx, ry, rz = co.x, co.z, co.y  # Blender -> Roblox
            nx, ny, nz = n.x, n.z, n.y
            key = (round(rx, 3), round(ry, 3), round(rz, 3), round(nx, 2), round(ny, 2), round(nz, 2))
            idx = index_of.get(key)
            if idx is None:
                idx = len(verts_out)
                index_of[key] = idx
                verts_out.append((rx, ry, rz, nx, ny, nz))
                for k, v in enumerate((rx, ry, rz)):
                    bounds_min[k] = min(bounds_min[k], v)
                    bounds_max[k] = max(bounds_max[k], v)
            ids.append(idx)
        # reflection flips handedness: reverse winding
        tris.append((ids[0], ids[2], ids[1]))
    center = [(bounds_min[i] + bounds_max[i]) / 2 for i in range(3)]
    size = [bounds_max[i] - bounds_min[i] for i in range(3)]
    return verts_out, tris, center, size, obj


def export_piece(pid, builder, w, d, out_dir, want_obj, placeable=True):
    reset_scene()
    p = Piece(pid, w, d)
    builder(p)
    groups_out = []
    total_tris = 0
    joined = []
    for g in p.groups:
        verts, tris, center, size, obj = group_geometry(g["objects"], g["smooth"])
        obj.name = g["name"]
        joined.append(obj)
        total_tris += len(tris)
        # store verts relative to the group centre so the MeshPart origin is its bounding centre
        packed_verts = []
        for (x, y, z, nx, ny, nz) in verts:
            packed_verts.extend([round(x - center[0], 4), round(y - center[1], 4), round(z - center[2], 4), round(nx, 3), round(ny, 3), round(nz, 3)])
        groups_out.append({
            "name": g["name"], "color": list(g["color"]), "theme": g["theme"], "material": g["material"],
            "attrs": g["attrs"], "collide": g["collide"], "transparency": g["transparency"],
            "center": [round(c, 4) for c in center], "size": [round(s, 4) for s in size],
            "verts": packed_verts, "tris": [i for t in tris for i in t],
        })
    entry = {
        "id": pid, "cells": [w, d], "placeable": placeable, "triangles": total_tris,
        "attachments": {k: list(v) for k, v in p.attachments.items()},
        "lights": p.lights, "groups": groups_out,
    }
    if want_obj:
        bpy.ops.object.select_all(action="DESELECT")
        for o in joined:
            o.select_set(True)
        bpy.context.view_layer.objects.active = joined[0]
        if len(joined) > 1:
            bpy.ops.object.join()
        export_obj(bpy.context.active_object, out_dir, pid)
    return entry


def main():
    args = parse_args()
    out_dir = os.path.abspath(args.get("out", "assets/export"))
    want_obj = bool(args.get("obj", False))
    only = args.get("only")
    os.makedirs(out_dir, exist_ok=True)
    pieces = {}
    for pid, (fn, w, d) in PIECES.items():
        if only and pid not in str(only).split(","):
            continue
        pieces[pid] = export_piece(pid, fn, w, d, out_dir, want_obj, True)
        print(f"piece {pid}: {pieces[pid]['triangles']} tris, {len(pieces[pid]['groups'])} groups")
    for pid, fn in HUB.items():
        if only and pid not in str(only).split(","):
            continue
        pieces[pid] = export_piece(pid, fn, 1, 1, out_dir, want_obj, False)
        print(f"prop {pid}: {pieces[pid]['triangles']} tris, {len(pieces[pid]['groups'])} groups")
    bundle = {"version": 2, "units": "studs", "up": "Y", "pieces": pieces}
    path = os.path.join(out_dir, "meshes.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(bundle, f, separators=(",", ":"))
    total = sum(p["triangles"] for p in pieces.values())
    print(f"wrote {len(pieces)} meshes ({total} tris) to {path}")


if __name__ == "__main__":
    main()
