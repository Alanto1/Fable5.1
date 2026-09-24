"""Tiny builder for Rojo `.model.json` files.

Verified against Rojo 7.7: CFrame as 12 numbers (x, y, z, then the rotation matrix rows),
enums by name, Color3 as 0-1 floats, PrimaryPart through `Rojo_Id` / `Rojo_Target_PrimaryPart`
attributes.
"""

from __future__ import annotations

import json
import math
import os
import random
from typing import Any

# ----------------------------------------------------------------------------- maths


def rot(rx: float = 0.0, ry: float = 0.0, rz: float = 0.0) -> list[list[float]]:
    """Rotation matrix equal to Roblox CFrame.Angles(rx, ry, rz) (radians)."""
    cx, sx = math.cos(rx), math.sin(rx)
    cy, sy = math.cos(ry), math.sin(ry)
    cz, sz = math.cos(rz), math.sin(rz)
    Rx = [[1, 0, 0], [0, cx, -sx], [0, sx, cx]]
    Ry = [[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]]
    Rz = [[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]]

    def mul(a, b):
        return [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]

    return mul(mul(Rx, Ry), Rz)


def cframe(x: float, y: float, z: float, rx: float = 0.0, ry: float = 0.0, rz: float = 0.0) -> list[float]:
    """12-number CFrame with Euler angles in degrees."""
    m = rot(math.radians(rx), math.radians(ry), math.radians(rz))
    flat = [round(float(v), 5) for row in m for v in row]
    return [round(x, 4), round(y, 4), round(z, 4), *flat]


def color(r: int, g: int, b: int) -> list[float]:
    return [round(r / 255, 4), round(g / 255, 4), round(b / 255, 4)]


# ----------------------------------------------------------------------------- instances


def instance(class_name: str, name: str, properties: dict | None = None, children: list | None = None, attributes: dict | None = None) -> dict:
    node: dict[str, Any] = {"name": name, "className": class_name}
    if properties:
        node["properties"] = properties
    if attributes:
        node["attributes"] = attributes
    if children:
        node["children"] = children
    return node


def part(
    name: str,
    size: tuple[float, float, float],
    cf: list[float],
    rgb: tuple[int, int, int] = (200, 200, 200),
    material: str = "SmoothPlastic",
    shape: str | None = None,
    transparency: float = 0.0,
    can_collide: bool = True,
    anchored: bool = True,
    theme: str | None = None,
    class_name: str = "Part",
    attributes: dict | None = None,
    children: list | None = None,
    reflectance: float = 0.0,
    cast_shadow: bool = True,
    can_touch: bool = True,
) -> dict:
    props: dict[str, Any] = {
        "Size": [round(size[0], 4), round(size[1], 4), round(size[2], 4)],
        "CFrame": cf,
        "Color": color(*rgb),
        "Material": material,
        "Anchored": anchored,
        "CanCollide": can_collide,
        "CanTouch": can_touch,
        "CanQuery": True,
        "TopSurface": "Smooth",
        "BottomSurface": "Smooth",
        "CastShadow": cast_shadow,
    }
    if shape and class_name == "Part":
        props["Shape"] = shape
    if transparency:
        props["Transparency"] = transparency
    if reflectance:
        props["Reflectance"] = reflectance
    attrs = dict(attributes or {})
    if theme:
        attrs["ThemeKey"] = theme
    return instance(class_name, name, props, children, attrs or None)


def wedge(name: str, size, cf, rgb=(200, 200, 200), material="SmoothPlastic", theme=None, can_collide=True, attributes=None, transparency=0.0) -> dict:
    return part(name, size, cf, rgb, material, None, transparency, can_collide, True, theme, "WedgePart", attributes)


def attachment(name: str, cf: list[float], attributes: dict | None = None) -> dict:
    return instance("Attachment", name, {"CFrame": cf}, None, attributes)


def point_light(name: str, rgb, brightness: float = 1.0, range_: float = 12.0) -> dict:
    return instance("PointLight", name, {"Color": color(*rgb), "Brightness": brightness, "Range": range_, "Shadows": False})


def model(name: str, children: list, primary: str | None = None, attributes: dict | None = None) -> dict:
    """Model with an optional PrimaryPart (the child part with that name)."""
    attrs = dict(attributes or {})
    if primary:
        ref_id = f"{name}-{primary}-pp"
        for child in children:
            if child.get("name") == primary:
                child.setdefault("attributes", {})["Rojo_Id"] = ref_id
                break
        else:
            raise ValueError(f"model {name}: primary part {primary} not among children")
        attrs["Rojo_Target_PrimaryPart"] = ref_id
    return instance("Model", name, None, children, attrs or None)


def folder(name: str, children: list) -> dict:
    return instance("Folder", name, None, children)


def write(path: str, node: dict) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    top = dict(node)
    top.pop("name", None)  # the file name supplies the instance name
    with open(path, "w", encoding="utf-8") as f:
        json.dump(top, f, separators=(",", ":"))


def seeded(seed: int) -> random.Random:
    return random.Random(seed)
