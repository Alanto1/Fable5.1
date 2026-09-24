"""Shared helpers for generating Roblox-ready meshes in Blender 5.2 (headless).

Conventions
- 1 Blender unit = 1 Roblox stud. Model at stud scale and export OBJ; Roblox imports OBJ 1:1.
- Y is up in Roblox; Blender is Z-up. The OBJ exporter is called with forward=-Z, up=Y so the
  mesh lands upright in Studio.
- Every object gets flat-colour materials. Roblox imports OBJ material colours as the MeshPart's
  vertex/material colour; game code recolours by theme at runtime, so keep materials few.
- Keep tri counts low (props < 1.5K tris) so phones stream them instantly.

Run a generator:
    blender -b --python assets/blender/gen_props.py -- --out assets/export
"""

from __future__ import annotations

import math
import os
import sys
from typing import Iterable

import bpy
import bmesh
from mathutils import Vector


def parse_args() -> dict:
    """Arguments after `--` on the blender command line, as key=value pairs or --key value."""
    argv = sys.argv
    if "--" not in argv:
        return {}
    args = argv[argv.index("--") + 1 :]
    out = {}
    i = 0
    while i < len(args):
        token = args[i]
        if token.startswith("--"):
            key = token[2:]
            if i + 1 < len(args) and not args[i + 1].startswith("--"):
                out[key] = args[i + 1]
                i += 2
            else:
                out[key] = True
                i += 1
        else:
            i += 1
    return out


def reset_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "NONE"
    scene.unit_settings.scale_length = 1.0


def flat_material(name: str, rgb: tuple[float, float, float], roughness: float = 0.8) -> bpy.types.Material:
    mat = bpy.data.materials.get(name)
    if mat:
        return mat
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
        bsdf.inputs["Roughness"].default_value = roughness
    mat.diffuse_color = (*rgb, 1.0)
    return mat


def srgb(r: int, g: int, b: int) -> tuple[float, float, float]:
    """0-255 sRGB to linear floats for material colours."""

    def lin(c: int) -> float:
        c = c / 255.0
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

    return (lin(r), lin(g), lin(b))


def _finish(obj: bpy.types.Object, material: bpy.types.Material | None, name: str) -> bpy.types.Object:
    obj.name = name
    if material:
        if obj.data.materials:
            obj.data.materials[0] = material
        else:
            obj.data.materials.append(material)
    return obj


def box(name: str, size: tuple[float, float, float], location=(0, 0, 0), material=None, bevel: float = 0.0):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location)
    obj = bpy.context.active_object
    obj.scale = Vector(size)
    bpy.ops.object.transform_apply(scale=True)
    if bevel > 0:
        mod = obj.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 2
        mod.limit_method = "ANGLE"
        bpy.ops.object.modifier_apply(modifier=mod.name)
    return _finish(obj, material, name)


def cylinder(name: str, radius: float, depth: float, location=(0, 0, 0), material=None, verts: int = 16, rotation=(0, 0, 0)):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=depth, location=location, rotation=rotation)
    obj = bpy.context.active_object
    return _finish(obj, material, name)


def cone(name: str, radius1: float, radius2: float, depth: float, location=(0, 0, 0), material=None, verts: int = 16, rotation=(0, 0, 0)):
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=radius1, radius2=radius2, depth=depth, location=location, rotation=rotation)
    obj = bpy.context.active_object
    return _finish(obj, material, name)


def sphere(name: str, radius: float, location=(0, 0, 0), material=None, segments: int = 16, rings: int = 10):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, radius=radius, location=location)
    obj = bpy.context.active_object
    return _finish(obj, material, name)


def torus(name: str, major: float, minor: float, location=(0, 0, 0), material=None, rotation=(0, 0, 0)):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, location=location, rotation=rotation, major_segments=20, minor_segments=10)
    obj = bpy.context.active_object
    return _finish(obj, material, name)


def join(objects: Iterable[bpy.types.Object], name: str) -> bpy.types.Object:
    objects = list(objects)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    joined = bpy.context.active_object
    joined.name = name
    return joined


def shade_smooth(obj: bpy.types.Object, angle_deg: float = 40.0) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.shade_smooth_by_angle(angle=math.radians(angle_deg))


def set_origin_bottom(obj: bpy.types.Object) -> None:
    """Origin at the bottom centre so Roblox places it on the ground when positioned."""
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.origin_set(type="ORIGIN_GEOMETRY", center="BOUNDS")
    min_z = min((obj.matrix_world @ v.co).z for v in obj.data.vertices)
    bpy.context.scene.cursor.location = Vector((obj.location.x, obj.location.y, min_z))
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    obj.location = Vector((0, 0, 0))


def triangle_count(obj: bpy.types.Object) -> int:
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    count = len(bm.faces)
    bm.free()
    return count


def export_obj(obj: bpy.types.Object, out_dir: str, filename: str | None = None) -> str:
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, (filename or obj.name) + ".obj")
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.wm.obj_export(
        filepath=path,
        export_selected_objects=True,
        forward_axis="NEGATIVE_Z",
        up_axis="Y",
        export_materials=True,
        export_triangulated_mesh=True,
        apply_modifiers=True,
        export_uv=True,
        export_normals=True,
        global_scale=1.0,
    )
    return path


def export_fbx(obj: bpy.types.Object, out_dir: str, filename: str | None = None) -> str:
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, (filename or obj.name) + ".fbx")
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.fbx(
        filepath=path,
        use_selection=True,
        apply_unit_scale=True,
        global_scale=1.0,
        axis_forward="-Z",
        axis_up="Y",
        mesh_smooth_type="FACE",
        add_leaf_bones=False,
        bake_anim=False,
    )
    return path
