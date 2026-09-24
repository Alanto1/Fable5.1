"""Renders preview images of the game's art with Blender 5.2 (headless, EEVEE).

Two sources of geometry:
  * Rojo model.json files (the part-built "before" look, and map layout) -> parts become primitives
  * assets/export/meshes.json (the Blender "after" look) -> groups become meshes

Shots:
  hub    - the island seen from above the plaza
  base   - a dressed plot with a sample layout
  vault  - close-up of the vault, mine and a few traps

Run from roblox/:
  blender -b --python tools/render_previews.py -- --mode before --out assets/export/previews
  blender -b --python tools/render_previews.py -- --mode after  --out assets/export/previews
"""

from __future__ import annotations

import json
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
MODELS = os.path.join(ROOT, "assets", "models", "Pieces")
MAP = os.path.join(ROOT, "assets", "map")
MESHES = os.path.join(ROOT, "assets", "export", "meshes.json")

THEME = {  # Classic palette (sRGB) for ThemeKey recolouring in renders
    "ground": (116, 176, 86), "border": (96, 82, 64), "wood": (176, 120, 66), "woodDark": (120, 78, 40),
    "stone": (150, 158, 170), "stoneDark": (100, 108, 122), "steel": (176, 196, 214), "steelDark": (90, 110, 130),
    "titanium": (240, 226, 190), "titaniumDark": (190, 160, 100), "laser": (255, 90, 200), "laserDark": (120, 30, 100),
    "vault": (255, 190, 60), "vaultDark": (150, 100, 20), "mine": (120, 90, 70), "mineAccent": (255, 205, 60),
    "trap": (230, 70, 70), "trapDark": (120, 30, 30), "metal": (70, 74, 90), "accent": (80, 200, 255),
    "decor": (90, 170, 90), "decorAlt": (150, 150, 160),
}

SAMPLE_LAYOUT = [
    ("Vault", 7, 5, 0), ("Mine", 5, 6, 0), ("Mine", 10, 6, 0), ("Mine", 5, 4, 0),
    ("WallStone", 5, 8, 0), ("WallStone", 6, 8, 0), ("WallWood", 7, 8, 0), ("WallWood", 8, 8, 0), ("WallStone", 9, 8, 0), ("WallStone", 10, 8, 0),
    ("WallSteel", 4, 5, 0), ("WallSteel", 4, 6, 0), ("WallSteel", 4, 7, 0), ("WallSteel", 11, 5, 0), ("WallSteel", 11, 6, 0), ("WallSteel", 11, 7, 0),
    ("SpikeTrap", 6, 10, 0), ("Flinger", 9, 10, 0), ("FlameJet", 7, 11, 0), ("FreezePad", 8, 11, 0), ("BearTrap", 5, 12, 0),
    ("Cannon", 3, 9, 0), ("Zapper", 12, 9, 0), ("GuardBot", 12, 11, 0), ("GuardDog", 3, 12, 0),
    ("Torch", 4, 2, 0), ("Torch", 11, 2, 0), ("Flag", 2, 2, 0), ("Bush", 13, 3, 0), ("Rock", 1, 10, 0), ("Statue", 13, 13, 0),
    ("SpinningBlade", 10, 12, 0), ("DartLauncher", 6, 13, 2), ("GasVent", 9, 13, 0), ("Sentinel", 2, 6, 0), ("Fountain", 12, 1, 0),
]


def parse_args():
    argv = sys.argv
    if "--" not in argv:
        return {}
    args = argv[argv.index("--") + 1 :]
    out = {}
    i = 0
    while i < len(args):
        if args[i].startswith("--") and i + 1 < len(args) and not args[i + 1].startswith("--"):
            out[args[i][2:]] = args[i + 1]
            i += 2
        else:
            out[args[i][2:]] = True
            i += 1
    return out


# ----------------------------------------------------------------------------- materials

_materials = {}


def material(rgb, kind="SmoothPlastic", transparency=0.0):
    key = (tuple(rgb), kind, round(transparency, 2))
    if key in _materials:
        return _materials[key]
    mat = bpy.data.materials.new(f"m_{len(_materials)}")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")

    def lin(c):
        c = c / 255.0
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

    col = (lin(rgb[0]), lin(rgb[1]), lin(rgb[2]), 1.0)
    bsdf.inputs["Base Color"].default_value = col
    if kind == "Neon":
        bsdf.inputs["Emission Color"].default_value = col
        bsdf.inputs["Emission Strength"].default_value = 3.0
        bsdf.inputs["Roughness"].default_value = 0.4
    elif kind in ("Metal", "DiamondPlate", "Foil"):
        bsdf.inputs["Metallic"].default_value = 0.8
        bsdf.inputs["Roughness"].default_value = 0.35
    elif kind in ("Glass", "Ice"):
        bsdf.inputs["Roughness"].default_value = 0.05
        bsdf.inputs["Transmission Weight"].default_value = 0.6
    elif kind in ("Grass", "Fabric", "Ground", "Sand"):
        bsdf.inputs["Roughness"].default_value = 0.95
    else:
        bsdf.inputs["Roughness"].default_value = 0.7
    if transparency > 0:
        bsdf.inputs["Alpha"].default_value = 1.0 - transparency
        mat.surface_render_method = "BLENDED"
    _materials[key] = mat
    return mat


# ----------------------------------------------------------------------------- roblox -> blender


def rbx_to_blender_matrix(cf: list[float]) -> Matrix:
    """12-number Roblox CFrame -> Blender world matrix. Roblox (x, y, z) -> Blender (x, -z, y)."""
    x, y, z = cf[0], cf[1], cf[2]
    r = cf[3:]
    R = Matrix(((r[0], r[1], r[2]), (r[3], r[4], r[5]), (r[6], r[7], r[8])))
    # Change of basis: B = P * R * P^-1 with P mapping roblox axes to blender axes
    P = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))
    RB = P @ R @ P.transposed()
    M = RB.to_4x4()
    M.translation = Vector((x, -z, y))
    return M


def add_primitive(part: dict, matrix: Matrix, color_override=None):
    props = part.get("properties", {})
    if "Size" not in props or "CFrame" not in props:
        return None
    size = props["Size"]
    shape = props.get("Shape", "Block")
    cls = part.get("className", "Part")
    if cls == "WedgePart":
        w, h, d = size
        verts = [(-w / 2, -h / 2, -d / 2), (w / 2, -h / 2, -d / 2), (w / 2, -h / 2, d / 2), (-w / 2, -h / 2, d / 2), (w / 2, h / 2, d / 2), (-w / 2, h / 2, d / 2)]
        faces = [(0, 1, 2, 3), (2, 4, 5, 3), (0, 3, 5), (1, 4, 2), (0, 5, 4, 1)]
        me = bpy.data.meshes.new("wedge")
        me.from_pydata(verts, [], faces)
        obj = bpy.data.objects.new("wedge", me)
        bpy.context.collection.objects.link(obj)
    elif shape == "Ball":
        bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=10, radius=0.5)
        obj = bpy.context.active_object
        obj.scale = Vector(size)
    elif shape == "Cylinder":
        bpy.ops.mesh.primitive_cylinder_add(vertices=20, radius=0.5, depth=1.0, rotation=(0, math.pi / 2, 0))
        obj = bpy.context.active_object
        bpy.ops.object.transform_apply(rotation=True)
        obj.scale = Vector(size)
    else:
        bpy.ops.mesh.primitive_cube_add(size=1.0)
        obj = bpy.context.active_object
        obj.scale = Vector(size)
    local = rbx_to_blender_matrix(props["CFrame"])
    # Roblox part sizes are in part space; apply size as local scale before the rotation.
    obj.matrix_world = matrix @ local @ Matrix.Diagonal((*obj.scale, 1.0))
    obj.scale = (1, 1, 1)
    rgb = color_override
    theme_key = (part.get("attributes") or {}).get("ThemeKey")
    if theme_key and theme_key in THEME:
        rgb = THEME[theme_key]
    if rgb is None:
        c = props.get("Color", [0.8, 0.8, 0.8])
        rgb = (c[0] * 255, c[1] * 255, c[2] * 255)
    transparency = props.get("Transparency", 0.0)
    if transparency >= 1.0:
        obj.hide_render = True
    obj.data.materials.append(material(rgb, props.get("Material", "SmoothPlastic"), transparency))
    return obj


def instantiate_json_tree(node: dict, matrix: Matrix, mesh_lookup=None):
    """Adds every part in a Rojo model.json tree. Piece/prop markers are replaced by meshes when
    mesh_lookup is given and knows the id."""
    attrs = node.get("attributes") or {}
    marker = attrs.get("Prop") or (attrs.get("PieceId") if node.get("className") == "Model" else None)
    if mesh_lookup and marker and marker in mesh_lookup:
        root = next((c for c in node.get("children", []) if c.get("name") == "Root"), None)
        if root and "CFrame" in root.get("properties", {}):
            m = rbx_to_blender_matrix(root["properties"]["CFrame"])
            m.translation -= m.to_3x3() @ Vector((0, 0, 0.1))
            add_mesh_piece(mesh_lookup[marker], matrix @ m)
            return
    if node.get("className") in ("Part", "WedgePart", "SpawnLocation"):
        add_primitive(node, matrix)
    for child in node.get("children", []):
        instantiate_json_tree(child, matrix, mesh_lookup)


def add_mesh_piece(piece: dict, matrix: Matrix):
    objs = []
    for g in piece["groups"]:
        verts = g["verts"]
        n = len(verts) // 6
        cx, cy, cz = g["center"]
        bverts = []
        for i in range(n):
            x, y, z = verts[i * 6] + cx, verts[i * 6 + 1] + cy, verts[i * 6 + 2] + cz
            bverts.append((x, -z, y))
        tris = g["tris"]
        faces = [(tris[i], tris[i + 2], tris[i + 1]) for i in range(0, len(tris), 3)]
        me = bpy.data.meshes.new(g["name"])
        me.from_pydata(bverts, [], faces)
        me.update()
        obj = bpy.data.objects.new(g["name"], me)
        bpy.context.collection.objects.link(obj)
        obj.matrix_world = matrix
        rgb = THEME.get(g["theme"]) if g.get("theme") else None
        rgb = rgb or tuple(g["color"])
        if g.get("transparency", 0) >= 1.0:
            obj.hide_render = True
        obj.data.materials.append(material(rgb, g["material"], g.get("transparency", 0)))
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        bpy.ops.object.shade_smooth_by_angle(angle=math.radians(38))
        obj.select_set(False)
        objs.append(obj)
    return objs


def load_piece_json(pid: str) -> dict | None:
    path = os.path.join(MODELS, f"{pid}.model.json")
    if not os.path.exists(path):
        return None
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def cell_to_local(x, z, w, d, r):
    if r % 2 == 1:
        w, d = d, w
    return (x + w / 2) * 4 - 32, (z + d / 2) * 4 - 32


def place_layout(root_matrix: Matrix, layout, mode: str, meshes: dict | None):
    sizes = {}
    if meshes:
        for pid, piece in meshes.items():
            sizes[pid] = piece["cells"]
    for (pid, x, z, r) in layout:
        w, d = 1, 1
        if pid in sizes:
            w, d = sizes[pid]
        elif pid in ("Vault", "Pit", "Fountain"):
            w, d = 2, 2
        cx, cz = cell_to_local(x, z, w, d, r)
        # Roblox: root CFrame * CFrame.new(cx, 1.0, cz) * Angles(0, r*90deg, 0)
        rot = Matrix.Rotation(math.radians(r * 90), 4, "Z")
        local = Matrix.Translation(Vector((cx, -cz, 1.0))) @ rot
        m = root_matrix @ local
        if mode == "after" and meshes and pid in meshes:
            add_mesh_piece(meshes[pid], m)
        else:
            tree = load_piece_json(pid)
            if tree:
                # Roblox PivotTo on the Root part at (0, 0.1, 0): shift so the root centre lands on m
                shift = Matrix.Translation(Vector((0, 0, -0.1)))
                instantiate_json_tree({"className": "Model", "children": tree.get("children", [])}, m @ shift, None)


# ----------------------------------------------------------------------------- scenes


def setup_world():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.eevee.taa_render_samples = 24
    scene.render.resolution_x = 1280
    scene.render.resolution_y = 720
    scene.render.film_transparent = False
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "AgX - Punchy"
    world = bpy.data.worlds.new("World")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    bg.inputs[0].default_value = (0.35, 0.55, 0.95, 1.0)
    bg.inputs[1].default_value = 0.9
    bpy.ops.object.light_add(type="SUN", location=(0, 0, 200))
    sun = bpy.context.active_object
    sun.data.energy = 4.5
    sun.data.angle = math.radians(4)
    sun.rotation_euler = (math.radians(50), 0, math.radians(35))
    bpy.ops.object.light_add(type="SUN", location=(0, 0, 200))
    fill = bpy.context.active_object
    fill.data.energy = 1.2
    fill.data.color = (0.8, 0.9, 1.0)
    fill.rotation_euler = (math.radians(60), 0, math.radians(-140))


def camera(location, target, lens=35):
    bpy.ops.object.camera_add(location=location)
    cam = bpy.context.active_object
    direction = Vector(target) - Vector(location)
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    cam.data.lens = lens
    bpy.context.scene.camera = cam
    return cam


def render(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("rendered", path)


def load_map_json(name):
    with open(os.path.join(MAP, name), encoding="utf-8") as f:
        return json.load(f)


def scene_hub(mode, meshes, out):
    setup_world()
    lookup = meshes if mode == "after" else None
    for name in ("Island.model.json", "Plaza.model.json", "Plots.model.json"):
        instantiate_json_tree(load_map_json(name), Matrix.Identity(4), lookup)
    # Populate three plots with the sample base so the ring does not look empty.
    plots = load_map_json("Plots.model.json")
    for i, plot in enumerate(plots.get("children", [])[:3]):
        root = next((c for c in plot.get("children", []) if c.get("name") == "Root"), None)
        if root:
            m = rbx_to_blender_matrix(root["properties"]["CFrame"])
            m.translation -= m.to_3x3() @ Vector((0, 0, 0.1))
            place_layout(m, SAMPLE_LAYOUT[: 12 + i * 8], mode, meshes)
    camera((150, -260, 150), (0, -20, 5), 32)
    render(os.path.join(out, f"hub_{mode}.png"))


def scene_base(mode, meshes, out):
    setup_world()
    ground_size = 70
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.5))
    ground = bpy.context.active_object
    ground.scale = (ground_size, ground_size, 1.0)
    ground.data.materials.append(material(THEME["ground"], "Grass"))
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, -0.5))
    base = bpy.context.active_object
    base.scale = (ground_size + 40, ground_size + 40, 1.0)
    base.data.materials.append(material((92, 150, 70), "Grass"))
    place_layout(Matrix.Identity(4), SAMPLE_LAYOUT, mode, meshes)
    camera((55, -95, 62), (0, 4, 4), 40)
    render(os.path.join(out, f"base_{mode}.png"))


def scene_vault(mode, meshes, out):
    setup_world()
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.5))
    ground = bpy.context.active_object
    ground.scale = (70, 70, 1.0)
    ground.data.materials.append(material(THEME["ground"], "Grass"))
    layout = [("Vault", 7, 5, 0), ("Mine", 5, 6, 0), ("SpikeTrap", 7, 8, 0), ("Flinger", 8, 8, 0), ("WallStone", 6, 8, 0), ("WallSteel", 9, 8, 0), ("Cannon", 10, 6, 0), ("Torch", 5, 8, 0)]
    place_layout(Matrix.Identity(4), layout, mode, meshes)
    camera((22, -46, 20), (0, -4, 4), 45)
    render(os.path.join(out, f"vault_{mode}.png"))


def scene_pieces(mode, meshes, out):
    """Every piece side by side, for a catalogue view."""
    setup_world()
    ids = list(meshes.keys()) if meshes else [os.path.basename(f).split(".")[0] for f in sorted(os.listdir(MODELS)) if f.endswith(".model.json")]
    ids = [i for i in ids if (meshes and meshes[i]["placeable"]) or not meshes]
    cols = 8
    layout = []
    for index, pid in enumerate(ids):
        cx = (index % cols) * 2
        cz = (index // cols) * 2
        layout.append((pid, cx, cz, 0))
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.5))
    ground = bpy.context.active_object
    ground.scale = (90, 90, 1.0)
    ground.data.materials.append(material((225, 215, 195), "Marble"))
    place_layout(Matrix.Identity(4), layout, mode, meshes)
    camera((0, -70, 70), (0, -8, 2), 38)
    render(os.path.join(out, f"pieces_{mode}.png"))


def main():
    args = parse_args()
    mode = args.get("mode", "after")
    out = os.path.abspath(args.get("out", os.path.join(ROOT, "assets", "export", "previews")))
    meshes = None
    if mode == "after" and os.path.exists(MESHES):
        with open(MESHES, encoding="utf-8") as f:
            meshes = json.load(f)["pieces"]
    shots = str(args.get("shots", "vault,base,pieces,hub")).split(",")
    for shot in shots:
        {"hub": scene_hub, "base": scene_base, "vault": scene_vault, "pieces": scene_pieces}[shot](mode, meshes, out)


if __name__ == "__main__":
    main()
