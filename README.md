# Kaggle competition work – Fable 5.1 session

This repository holds the research, code and documentation produced for three live Kaggle
competitions, prioritised by what could be completed end to end on a CPU-only machine
without Kaggle credentials (see `docs/research.md`):

1. **Kaggriculture** (simulation / agent competition) – **complete, tuned agent** in
   `kaggriculture/main.py`, with a local evaluation harness.
2. **Biohub – Cell Tracking During Development** – plan and pipeline design in `docs/biohub/plan.md`.
3. **RSNA Knee Abnormality Detection** – plan and pipeline design in `docs/rsna/plan.md`.

## Kaggriculture

| Path | Purpose |
|---|---|
| `kaggriculture/main.py` | The submission. Single file, `agent(obs, config)` is the last callable. |
| `kaggriculture/sim/run.py` | Parallel evaluation: `python -m kaggriculture.sim.run --agent kaggriculture/main.py --opp starter --games 24` |
| `kaggriculture/sim/diag.py` | Per-day trace of one game (money, farm census, prices, animals lost, hire cost) |
| `kaggriculture/sim/trace.py` | Per-step trace of unit ops and market orders for a step range |
| `kaggriculture/sim/audit.py` | Action mix, unsold value at the end, purchase counts |
| `kaggriculture/tools/make_variant.py` | Build an opponent file with parameter overrides for A/B tests |
| `kaggriculture/sim/opponents/` | Frozen champions (`champ_v2..v4`) and ablation variants |
| `docs/kaggriculture/economics.md` | Engine-derived economics: yields, price curves, pots, town demand, labor |
| `docs/kaggriculture/strategy.md` | How the agent decides (planner, scheduler, market) |
| `docs/kaggriculture/experiments.md` | Results log of every iteration |
| `docs/kaggriculture/top-bots.md` | What the ~3,000-Elo bots do, mined from 60 leaderboard replays |
| `kaggriculture/sim/compare.py` | Two-sided game comparison: money by day, census, revenue by product for both players |

### Setup

```bash
uv venv .venv --python 3.11 && source .venv/bin/activate
uv pip install kaggle-environments==1.32.7 numpy
python -m kaggriculture.sim.run --agent kaggriculture/main.py --opp starter --games 8
```

### Submitting to Kaggle

The competition accepts a single `main.py` whose last callable is the agent. Credentials are
not available in this environment, so submission is a manual step:

```bash
pip install kaggle
# put your API token in ~/.kaggle/access_token (Kaggle → Settings → API → Generate New Token)
kaggle competitions submit kaggriculture -f kaggriculture/main.py -m "recipe farm manager v6"
kaggle competitions submissions kaggriculture
```

Accept the competition rules on the website first (Join Competition). Entry deadline:
September 23, 2026.
