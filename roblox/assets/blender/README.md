# Blender asset pipeline

Meshes are generated, not hand-modelled, so the whole art set can be regenerated with a
different palette or silhouette in one run.

```bash
# from the roblox/ folder
blender -b --python assets/blender/gen_props.py -- --out assets/export
```

Each generator writes `assets/export/<Name>.obj` (+ `.mtl`) and a `manifest.json` listing every
mesh with its bounding size and triangle count.

## Getting them into the game

1. In Studio: **Home > Import 3D** (or Asset Manager > Bulk Import). Select every `.obj` in
   `assets/export/`. Keep "Scale Unit: Studs" and untick "Anchor" so pieces follow their models.
2. Studio uploads them and gives each MeshPart a `MeshId`. Copy the ids into
   `src/shared/Data/AssetIds.luau` next to the matching name from `manifest.json`.
3. The game swaps part-built props for MeshParts automatically whenever an id is present.
   Anything without an id keeps using the generated part model, so nothing breaks mid-way.

Studio is the only step that cannot run headless: mesh uploads need an authenticated session.
