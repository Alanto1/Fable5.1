"""Generates the hub island, eight base plots, the central plaza and eight raid arenas into
assets/map/*.model.json.

Coordinates: the island centre is the origin. Plots sit on a ring and face the centre, so each
plot's local +Z (its entrance edge) points inward. Arenas are far away on the +X axis.

Run: python3 tools/gen_map.py
"""

from __future__ import annotations

import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from rbx import attachment, cframe, folder, instance, model, part, point_light, seeded, write  # noqa: E402

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "map")

PLOT_STUDS = 64.0
PLOT_RING_RADIUS = 150.0
PLOT_COUNT = 8
ISLAND_RADIUS = 250.0
ARENA_COUNT = 8
ARENA_ORIGIN = (2500.0, 0.0, 0.0)
ARENA_SPACING = 400.0

GRASS = (116, 176, 86)
GRASS_DARK = (92, 150, 70)
SAND = (232, 212, 150)
WATER = (70, 160, 230)
STONE = (150, 150, 160)
WOOD = (176, 120, 66)


def cyl(name, radius, height, x, y, z, rgb, material="Grass", **kw):
    """Upright cylinder (Roblox cylinders lie along X, so rotate 90 about Z)."""
    return part(name, (height, radius * 2, radius * 2), cframe(x, y, z, 0, 0, 90), rgb, material, shape="Cylinder", **kw)


def island() -> dict:
    rng = seeded(7)
    children = [
        cyl("Ground", ISLAND_RADIUS, 8, 0, -4, 0, GRASS, "Grass"),
        cyl("Sand", ISLAND_RADIUS + 12, 6, 0, -5.5, 0, SAND, "Sand"),
        cyl("Shelf", ISLAND_RADIUS + 40, 4, 0, -8, 0, (200, 180, 120), "Sand"),
        part("Water", (4000, 2, 4000), cframe(0, -7.5, 0), WATER, "Glass", transparency=0.35, can_collide=False, reflectance=0.1),
        part("Seabed", (4000, 4, 4000), cframe(0, -30, 0), (60, 80, 110), "Sand"),
        part("KillPlane", (6000, 2, 6000), cframe(0, -60, 0), (0, 0, 0), transparency=1.0, can_collide=False, attributes={"KillPlane": True}),
    ]
    # Scatter trees and rocks outside the plot ring and away from the plaza.
    for i in range(70):
        angle = rng.uniform(0, math.tau)
        radius = rng.choice([rng.uniform(60, 95), rng.uniform(205, 240)])
        x, z = math.cos(angle) * radius, math.sin(angle) * radius
        scale = rng.uniform(0.8, 1.5)
        trunk_h = 6 * scale
        children.append(part(f"Trunk{i}", (1.6 * scale, trunk_h, 1.6 * scale), cframe(x, trunk_h / 2, z, 0, 0, 90), (120, 78, 40), "Wood", shape="Cylinder"))
        children[-1]["properties"]["Size"] = [trunk_h, 1.6 * scale, 1.6 * scale]
        for j in range(3):
            r = (5.5 - j * 1.4) * scale
            children.append(part(f"Leaf{i}_{j}", (r, r * 0.8, r), cframe(x + rng.uniform(-1, 1), trunk_h + j * 2.2 * scale, z + rng.uniform(-1, 1)), (rng.randint(70, 110), rng.randint(150, 200), rng.randint(70, 110)), "Grass", shape="Ball", can_collide=False))
    for i in range(30):
        angle = rng.uniform(0, math.tau)
        radius = rng.uniform(210, 245)
        x, z = math.cos(angle) * radius, math.sin(angle) * radius
        s = rng.uniform(2, 6)
        children.append(part(f"Rock{i}", (s, s * 0.7, s * 0.9), cframe(x, s * 0.3, z, rng.uniform(-10, 10), rng.uniform(0, 360), rng.uniform(-10, 10)), STONE, "Slate"))
    return model("Island", children)


def plot(index: int) -> dict:
    angle = (index / PLOT_COUNT) * math.tau
    x, z = math.cos(angle) * PLOT_RING_RADIUS, math.sin(angle) * PLOT_RING_RADIUS
    # Face the centre: local +Z should point toward the origin.
    # Local +Z must point from the plot toward the origin, i.e. along (-x, -z).
    yaw = (math.degrees(math.atan2(x, z)) + 180.0) % 360.0
    half = PLOT_STUDS / 2
    children = [
        part("Root", (PLOT_STUDS, 0.2, PLOT_STUDS), cframe(0, 0.1, 0), (255, 255, 255), transparency=1.0, can_collide=False, can_touch=False),
        part("Ground", (PLOT_STUDS + 2, 1.0, PLOT_STUDS + 2), cframe(0, 0.5, 0), GRASS_DARK, "Grass", theme="ground"),
        # Low borders on three sides; the entrance (south, +Z) is open.
        part("BorderN", (PLOT_STUDS + 4, 2.2, 2), cframe(0, 1.6, -half - 1), (96, 82, 64), "WoodPlanks", theme="border"),
        part("BorderE", (2, 2.2, PLOT_STUDS + 4), cframe(half + 1, 1.6, 0), (96, 82, 64), "WoodPlanks", theme="border"),
        part("BorderW", (2, 2.2, PLOT_STUDS + 4), cframe(-half - 1, 1.6, 0), (96, 82, 64), "WoodPlanks", theme="border"),
        part("BorderSL", (PLOT_STUDS / 2 - 8, 2.2, 2), cframe(-(half / 2 + 4), 1.6, half + 1), (96, 82, 64), "WoodPlanks", theme="border"),
        part("BorderSR", (PLOT_STUDS / 2 - 8, 2.2, 2), cframe(half / 2 + 4, 1.6, half + 1), (96, 82, 64), "WoodPlanks", theme="border"),
        part("Entrance", (16, 0.3, 8), cframe(0, 1.15, half - 4), (255, 240, 180), "SmoothPlastic", can_collide=False, transparency=0.3, attributes={"Entrance": True}),
        part("Sign", (10, 4, 0.6), cframe(-14, 4, half + 3), (60, 40, 30), "Wood", attributes={"Sign": True}),
        part("SignPost", (0.8, 6, 0.8), cframe(-14, 3, half + 3), (120, 78, 40), "Wood"),
        # Grid lines are drawn at runtime in build mode; a subtle checker helps read cells.
        attachment("Camera", cframe(0, 40, half + 30)),
    ]
    node = model(f"Plot{index}", children, "Root", {"PlotIndex": index})
    # Position the whole model by baking the plot transform into every part.
    bake_transform(node, x, 0.0, z, yaw)
    return node


def bake_transform(node: dict, tx: float, ty: float, tz: float, yaw_deg: float) -> None:
    """Applies a translation + yaw to every CFrame in the tree (parts and attachments)."""
    yaw = math.radians(yaw_deg)
    c, s = math.cos(yaw), math.sin(yaw)

    def apply(cf: list[float]) -> list[float]:
        x, y, z = cf[0], cf[1], cf[2]
        rx = c * x + s * z
        rz = -s * x + c * z
        m = cf[3:]
        R = [[c, 0, s], [0, 1, 0], [-s, 0, c]]
        M = [[m[0], m[1], m[2]], [m[3], m[4], m[5]], [m[6], m[7], m[8]]]
        RM = [[sum(R[i][k] * M[k][j] for k in range(3)) for j in range(3)] for i in range(3)]
        return [round(rx + tx, 4), round(y + ty, 4), round(rz + tz, 4)] + [round(v, 5) for row in RM for v in row]

    for child in node.get("children", []):
        props = child.get("properties")
        if props and "CFrame" in props:
            props["CFrame"] = apply(props["CFrame"])
        if child.get("children"):
            for grand in child["children"]:
                gp = grand.get("properties")
                if gp and "CFrame" in gp and grand["className"] != "Attachment":
                    gp["CFrame"] = apply(gp["CFrame"])


def plaza() -> dict:
    children = [
        cyl("Floor", 46, 1.2, 0, 0.6, 0, (200, 190, 170), "Cobblestone"),
        cyl("Inner", 30, 0.6, 0, 1.4, 0, (225, 215, 195), "Marble"),
        cyl("Ring", 12, 0.5, 0, 1.95, 0, (80, 200, 255), "Neon", transparency=0.2, can_collide=False),
        cyl("PortalDisc", 9, 0.4, 0, 2.2, 0, (255, 190, 60), "Neon", transparency=0.1, can_collide=False, attributes={"Interact": "RaidPortal"}),
        part("PortalArchL", (2, 14, 2), cframe(-10, 8, 0), (70, 74, 90), "Metal"),
        part("PortalArchR", (2, 14, 2), cframe(10, 8, 0), (70, 74, 90), "Metal"),
        part("PortalArchT", (22, 2, 2), cframe(0, 15, 0), (70, 74, 90), "Metal"),
        part("PortalSign", (14, 3, 0.6), cframe(0, 12, 0), (255, 190, 60), "Neon", attributes={"Sign": "RAID"}),
        point_light("PortalGlow", (255, 190, 60), 1.5, 30),
        # Spawn ring around the portal
        instance("SpawnLocation", "Spawn", {"Size": [12, 1, 12], "CFrame": cframe(0, 1.9, 26), "Color": [0.8, 0.8, 0.85], "Material": "Marble", "Anchored": True, "CanCollide": True, "Transparency": 0.2, "Neutral": True, "Duration": 0}),
        # Boards
        part("BoardTrophies", (14, 9, 1), cframe(-26, 6.5, -22, 0, 35, 0), (34, 38, 62), "SmoothPlastic", attributes={"Leaderboard": "Trophies"}),
        part("BoardStolen", (14, 9, 1), cframe(26, 6.5, -22, 0, -35, 0), (34, 38, 62), "SmoothPlastic", attributes={"Leaderboard": "Stolen"}),
        part("BoardPostL", (1.2, 12, 1.2), cframe(-26, 6, -22, 0, 35, 0), (70, 74, 90), "Metal"),
        part("BoardPostR", (1.2, 12, 1.2), cframe(26, 6, -22, 0, -35, 0), (70, 74, 90), "Metal"),
        # Shop stall
        part("StallBase", (12, 1, 6), cframe(0, 2.5, -34), WOOD, "WoodPlanks"),
        part("StallRoof", (14, 0.8, 8), cframe(0, 9, -34), (230, 70, 70), "Fabric"),
        part("StallPostL", (0.8, 7, 0.8), cframe(-6, 5.5, -36), WOOD, "Wood"),
        part("StallPostR", (0.8, 7, 0.8), cframe(6, 5.5, -36), WOOD, "Wood"),
        part("StallSign", (10, 2.4, 0.5), cframe(0, 7.2, -31), (255, 190, 60), "Neon", attributes={"Interact": "Shop"}),
        part("GemPile", (3, 3, 3), cframe(0, 4.5, -34, 45, 0, 45), (186, 110, 255), "Neon"),
        # Hero statue
        part("StatueBase", (6, 2, 6), cframe(0, 3, 38), STONE, "Marble"),
        part("StatueBody", (2.4, 4, 1.6), cframe(0, 6, 38), (200, 200, 210), "Marble"),
        part("StatueHead", (1.6, 1.6, 1.6), cframe(0, 8.8, 38), (200, 200, 210), "Marble"),
        part("StatueSack", (2.2, 2.2, 2.2), cframe(1.6, 7.4, 37.5), (255, 190, 60), "Fabric"),
        part("StatueHammer", (0.7, 5, 0.7), cframe(-2, 6.5, 38, 0, 0, 25), (120, 78, 40), "Wood"),
    ]
    return model("Plaza", children)


def arena(index: int) -> dict:
    x = ARENA_ORIGIN[0] + index * ARENA_SPACING
    z = ARENA_ORIGIN[2]
    half = PLOT_STUDS / 2
    children = [
        part("Root", (PLOT_STUDS, 0.2, PLOT_STUDS), cframe(x, 0.1, z), (255, 255, 255), transparency=1.0, can_collide=False, can_touch=False),
        part("Ground", (PLOT_STUDS + 60, 1.0, PLOT_STUDS + 60), cframe(x, -0.5, z), GRASS_DARK, "Grass", theme="ground"),
        part("Base", (PLOT_STUDS + 2, 1.0, PLOT_STUDS + 2), cframe(x, 0.5, z), GRASS, "Grass", theme="ground"),
        part("FenceN", (PLOT_STUDS + 60, 8, 2), cframe(x, 4, z - half - 30), (60, 60, 80), "Metal", transparency=0.4),
        part("FenceS", (PLOT_STUDS + 60, 8, 2), cframe(x, 4, z + half + 30), (60, 60, 80), "Metal", transparency=0.4),
        part("FenceE", (2, 8, PLOT_STUDS + 60), cframe(x + half + 30, 4, z), (60, 60, 80), "Metal", transparency=0.4),
        part("FenceW", (2, 8, PLOT_STUDS + 60), cframe(x - half - 30, 4, z), (60, 60, 80), "Metal", transparency=0.4),
        # Exit pad beyond the entrance edge (south, +Z)
        part("Exit", (16, 0.6, 10), cframe(x, 1.3, z + half + 8), (96, 224, 120), "Neon", transparency=0.2, can_collide=False, attributes={"Exit": True}),
        part("ExitSign", (12, 2.4, 0.5), cframe(x, 8, z + half + 13), (96, 224, 120), "Neon", attributes={"Sign": "EXIT"}),
        part("ExitPostL", (0.8, 9, 0.8), cframe(x - 6, 4.5, z + half + 13), (70, 74, 90), "Metal"),
        part("ExitPostR", (0.8, 9, 0.8), cframe(x + 6, 4.5, z + half + 13), (70, 74, 90), "Metal"),
        attachment("RaiderSpawn", cframe(x, 4, z + half + 20)),
        attachment("Camera", cframe(x, 45, z + half + 40)),
        point_light("ArenaLight", (255, 255, 255), 0.5, 60),
    ]
    return model(f"Arena{index}", children, "Root", {"ArenaIndex": index})


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    write(os.path.join(OUT, "Island.model.json"), island())
    write(os.path.join(OUT, "Plaza.model.json"), plaza())
    write(os.path.join(OUT, "Plots.model.json"), folder("Plots", [plot(i) for i in range(PLOT_COUNT)]))
    write(os.path.join(OUT, "Arenas.model.json"), folder("Arenas", [arena(i) for i in range(ARENA_COUNT)]))
    print(f"wrote map to {os.path.relpath(OUT)}: island, plaza, {PLOT_COUNT} plots, {ARENA_COUNT} arenas")


if __name__ == "__main__":
    main()
