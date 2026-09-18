# The autonomous loop

Three GitHub Actions workflows plus a local toolchain. The design principle is to
separate cheap deterministic work (simulating games, downloading replays) from
expensive judgment (deciding what to change), and to keep a benchmark that is hard
to fool.

## Why this exists

Two submissions were tuned entirely against self-play and reported 92-94% win rates
locally while scoring 596 and 731 on the ladder. Self-play against a near-copy of
yourself returns roughly 50% no matter how good or bad you are, so it carries almost
no information. The loop below replaces that signal with two real ones: replays of
games the agent actually played, and a panel of opponents that are deliberately
different from the agent.

## Workflows

| Workflow | Trigger | What it does |
|---|---|---|
| `kaggriculture-loop.yml` | every 3 hours | Downloads new episodes of the live submission, extracts features, deletes the 30 MB raw replays, regenerates `ladder-status.md`, commits |
| `kaggriculture-benchmark.yml` | push to the agent | Runs the gauntlet and fails the build if the candidate falls below 50% against the panel |
| `kaggriculture-tuner.yml` | 02:00 UTC nightly | Screens random parameter perturbations, confirms survivors on more games, opens a pull request if one beats the champion by 6 points |

The tuner never submits to Kaggle. It opens a pull request, the benchmark gate runs
on it, and a human or a Claude session decides.

## One-time setup

The workflows need the Kaggle token as an encrypted repository secret. This cannot
be done through the API from here, so add it once by hand:

1. Open `https://github.com/Alanto1/Fable5.1/settings/secrets/actions`
2. New repository secret
3. Name `KAGGLE_API_TOKEN`, value is the token string
4. Save

Until that exists, the harvest workflow fails at the "Resolve active submission"
step and the other two still work (they do not touch Kaggle).

## Local commands

```bash
# pull new episodes of the live submission and refresh the report
python -m kaggriculture.ladder.harvest --submission <id> --limit 30
python -m kaggriculture.ladder.report --rating <score> --out docs/kaggriculture/ladder-status.md

# measure a candidate against the panel
python -m kaggriculture.sim.gauntlet --agent kaggriculture/main.py --games 24

# search the parameter space
python -m kaggriculture.sim.tuner --candidates 14 --screen 8 --confirm 32
```

## The benchmark, and how it can still lie

`gauntlet.py` runs the candidate against four opponents: a strawberry profile, an
animal-heavy profile, a melon rusher, and the previous strategy generation. Three are
built from the current champion with parameter overrides, one from the older champion
so the panel keeps a fixed reference point.

Known limits, stated plainly:

- The opponents are all built from **our** agent's execution machinery. If that
  machinery has a systematic weakness, every opponent shares it and the panel cannot
  see it. Only real ladder replays can.
- Win rates carry roughly five points of noise at 96 games. Differences smaller than
  that are not real, which is why the tuner demands six.
- The panel saturates as the agent improves. When the agent exceeds about 65% against
  it, replace an opponent with a fresh profile taken from `ladder-status.md`.

## Submission limits

Kaggle allows five submissions per day for this competition. The loop deliberately
leaves submission as a manual decision so a bad candidate cannot burn the budget.
