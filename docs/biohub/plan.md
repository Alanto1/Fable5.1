# Biohub – Cell Tracking During Development – plan (not executable in this session)

**Status:** planning only. Data are multi-GB OME-Zarr light-sheet volumes and the baseline is a
3D U-Net + transformer trained on GPU. No Kaggle credentials or GPU here.

## Facts gathered

| Item | Value | Source |
|---|---|---|
| Data | Zebrafish embryo light-sheet videos, OME-Zarr `(T, Z, Y, X)`; voxel 1.625 × 0.406 × 0.406 µm | organizer repo README |
| Labels | GEFF track graphs: nodes `(t, z, y, x)`, edges across time, divisions = 1 parent → 2 children; **sparse** (subset of cells annotated) | organizer repo README |
| Metric | `score = adjusted_edge_jaccard + 0.1 * division_jaccard`, micro-averaged over videos | organizer repo metrics.md |
| Matching | nodes matched by centroid distance ≤ 7 µm with optimal bipartite assignment; edges TP if both endpoints match a GT edge | metrics.md |
| Adjustment | `max(0, J * (1 - 0.1 * (T_pred - T_true) / T_true))` – over-predicting node count is penalized | metrics.md |
| Baseline | `TemporalUNet3D` detection (local-max suppression) + `SimpleNodeTransformer` linking; trained 3 epochs only | organizer repo README |
| Timeline | Entry deadline Sep 22 2026 | Kaggle |
| Prize | $60,000 | Kaggle |

Sources: https://github.com/royerlab/kaggle-cell-tracking-competition (README.md, metrics.md),
https://www.kaggle.com/competitions/biohub-cell-tracking-during-development

## What the metric rewards

- Edge Jaccard dominates (division term is only 0.1 weight). Get **linking right** on the
  annotated cells; unmatched predicted nodes are ignored, but the node-count adjustment
  penalizes predicting far more nodes than the estimated true count, so do not flood with
  detections.
- 7 µm matching radius is ~17 voxels in XY but only ~4 voxels in Z; detection precision in Z
  matters.

## Proposed approach (ordered by expected gain per hour)

1. **Reproduce the baseline** exactly (`uv sync`, `train_unet_transformer.py --epochs 3`,
   predict, `evaluate.py`) to get a local score and a working CSV pipeline.
2. **Train longer** (organizers state it was not trained to convergence): 20-40 epochs with
   cosine LR, random 3D crops, flips, intensity jitter; monitor the edge Jaccard on a held-out
   video rather than loss.
3. **Better detection**: predict Gaussian heatmaps of nuclei centers (sigma ~ 2 voxels in Z,
   5 in XY), use NMS with a radius matched to nucleus size, and tune the detection threshold
   against the node-count adjustment term.
4. **Better linking**: replace greedy pair scoring with global assignment (Hungarian per frame
   pair on transformer scores + distance prior), allow division candidates (one parent to two
   children) with a learned division score, and forbid unrealistic displacements (> 15 µm).
5. **Classical fallback / ensemble**: LoG blob detection + nearest-neighbour linking with
   motion prediction; useful for sanity checks and for videos where the learned model fails.
6. **Post-processing**: drop tracks shorter than 2 frames, fill 1-frame gaps.

## Skeleton to create in a Kaggle GPU notebook

```
biohub/
  data/loaders.py       # zarr chunked reading, crop sampling around annotated nodes
  models/detector.py    # heatmap 3D U-Net
  models/linker.py      # pairwise scoring + assignment
  eval/score_local.py   # wraps organizer metrics
  infer/to_csv.py       # GEFF -> Kaggle CSV
```
