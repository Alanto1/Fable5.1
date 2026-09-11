# Competition research and ranking (2026-09-11)

Three live Kaggle competitions were evaluated for feasibility given this session's
compute: **4 CPU cores, 15 GB RAM, ~30 GB disk, no GPU, no Kaggle API credentials**.

## Summary table

| | Kaggriculture | Biohub Cell Tracking | RSNA Knee Abnormality |
|---|---|---|---|
| Type | Simulation / agent (2-player) | 3D+time microscopy tracking | Multimodal medical imaging + text |
| Data needed | **None** (engine ships in `kaggle-environments`) | 4D OME-Zarr light-sheet volumes (tens of GB) | >5,000 knee MRI exams + reports (hundreds of GB) |
| Compute needed | CPU only, seconds per game | GPU (3D U-Net + transformer linking) | GPU (3D CNN / ViT over MRI volumes) |
| Metric | Win/loss head-to-head on final bank balance | Micro-averaged Jaccard on edges and divisions | Macro ROC-AUC over 12 labels |
| Submission | `main.py` with `agent(obs)` (single file or tar.gz) | CSV of tracked graph, code notebook | Code competition (notebook, offline inference) |
| Deadline | Entry Sep 23, 2026 | Entry Sep 22, 2026 | Entry Oct 15, final Oct 22, 2026 |
| Prize | $50,000 ($5k x top 10) | $60,000 | $77,000 (incl. efficiency awards) |
| Feasible here? | **Yes, end to end** | Only planning and pipeline scaffolding | Only planning and pipeline scaffolding |

## Ranking (easiest / highest confidence first)

1. **Kaggriculture** – the entire game engine (`kaggriculture.py`, 1086 lines) is bundled in the
   `kaggle-environments` PyPI wheel, so the exact rules, price curves and turn order are known and
   the game can be simulated locally at ~2 s/game. An agent can be developed, benchmarked over
   hundreds of seeds and opponents, and tuned entirely on CPU. Submission is one Python file.
   This is the only competition where this environment can produce a competitive, verified result.
2. **Biohub Cell Tracking** – the organizers publish a baseline repo (`royerlab/kaggle-cell-tracking-competition`,
   3D temporal U-Net + node transformer). Data are multi-GB zarr volumes and training needs a GPU.
   Without Kaggle credentials the data cannot be downloaded here. Deliverable: a detailed plan and
   a pipeline skeleton the user can run in a Kaggle GPU notebook.
3. **RSNA Knee Abnormality Detection** – >5,000 MRI exams from 16-19 sites with reports in 9+ languages,
   12 multilabel targets, macro AUC. Largest data, heaviest compute, longest deadline. Deliverable:
   plan and pipeline skeleton.

## Sources

- RSNA challenge page: https://www.rsna.org/artificial-intelligence/ai-image-challenge/knee-mri-ai-challenge
- RSNA news: https://www.rsna.org/news/2026/august/ai-challenge-knee-mri
- RuntimeWire summary of RSNA challenge: https://runtimewire.com/article/rsna-knee-mri-ai-challenge-2026
- Kaggriculture competition: https://www.kaggle.com/competitions/kaggriculture
- Kaggriculture episodes dataset: https://www.kaggle.com/datasets/kaggle/kaggriculture-episodes-index
- Biohub competition: https://www.kaggle.com/competitions/biohub-cell-tracking-during-development
- Biohub baseline repo: https://github.com/royerlab/kaggle-cell-tracking-competition
- FEBS Network article: https://network.febs.org/posts/biohub-calls-on-ai-community-to-transform-3d-cell-tracking
