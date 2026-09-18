"""Autonomous parameter search for the Kaggriculture agent.

Screens random perturbations of the champion's parameters on a small number of
gauntlet games, then re-runs the survivors on more games (successive halving), so
compute goes to promising candidates instead of being spread evenly. A candidate is
promoted only if it beats the champion by `--margin` on the confirmation round.

  python -m kaggriculture.sim.tuner --candidates 12 --screen 8 --confirm 24
  python -m kaggriculture.sim.tuner --apply            # write the winner into main.py
"""
import argparse, json, os, random, re, statistics, subprocess, sys, time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, ROOT)
MAIN = os.path.join(ROOT, "kaggriculture", "main.py")
STATE = os.path.join(ROOT, "kaggriculture", "sim", "tuner_state.json")

# Search space: name -> list of candidate values. Ranges are deliberately bounded to
# regions that did not collapse in earlier measurements (see docs/.../experiments.md).
SPACE = {
    "straw_mult":      [1.8, 2.0, 2.2, 2.5, 2.8],
    "straw_cap":       [40, 44, 48, 52],
    "straw_last_day":  [13, 15, 17],
    "melon_tiles":     [8, 10, 12, 14],
    "melon_repeat":    [0, 6, 10, 14],
    "melon_last_day":  [12, 14, 16],
    "melon_guard":     [60, 90, 120],
    "fill_reserve":    [300, 500, 700],
    "wheat_fill_max":  [8, 12, 18, 999],
    "weed_dig_value":  [12.0, 40.0, 120.0],
    "cow_k":           [2.0, 2.5, 3.2],
    "sheep_k":         [3.5, 4.5, 5.5],
    "size_k":          [0.75, 0.85, 0.95],
    "fair_share":      [0.4, 0.5, 0.6],
    "harvest_hour":    [8, 10, 12],
    "feed_days":       [2, 3],
    "reserve_frac":    [0.2, 0.3, 0.4],
    "max_hands":       [12, 13, 14],
    "cull_margin":     [0.0, 0.6],
}
MUTATIONS = 3          # parameters changed per candidate


def champion_params():
    """Read the P dict defaults out of main.py without importing the whole agent."""
    import importlib.util
    spec = importlib.util.spec_from_file_location("kagg_champion", MAIN)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return dict(m.P)


def make_candidate(base, rng):
    o = {}
    for k in rng.sample(list(SPACE), k=min(MUTATIONS, len(SPACE))):
        choices = [v for v in SPACE[k] if v != base.get(k)]
        if choices:
            o[k] = rng.choice(choices)
    return o


def variant_path(name, overrides):
    d = os.path.join(ROOT, "kaggriculture", "sim", "opponents")
    os.makedirs(d, exist_ok=True)
    p = os.path.join(d, f"tune_{name}.py")
    open(p, "w").write(
        "# Auto-generated tuner candidate.\n"
        "import importlib.util as _ilu\n"
        f"_spec = _ilu.spec_from_file_location('tune_{name}', {MAIN!r})\n"
        "_m = _ilu.module_from_spec(_spec)\n"
        "_spec.loader.exec_module(_m)\n"
        f"_m.P.update({overrides!r})\n\n\n"
        "def agent(obs, config=None):\n"
        "    return _m.agent(obs, config)\n"
    )
    return os.path.relpath(p, ROOT)


def gauntlet(agent_rel, games, seed0, workers):
    out = f"/tmp/tune_{abs(hash(agent_rel))}_{games}.md"
    cmd = [sys.executable, "-m", "kaggriculture.sim.gauntlet", "--agent", agent_rel,
           "--games", str(games), "--seed0", str(seed0), "--workers", str(workers), "--out", out]
    r = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, timeout=14400)
    if r.returncode != 0:
        return None
    m = re.search(r"OVERALL_WINRATE=([0-9.]+)", open(out).read())
    return float(m.group(1)) if m else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--candidates", type=int, default=12)
    ap.add_argument("--screen", type=int, default=8)
    ap.add_argument("--survivors", type=int, default=3)
    ap.add_argument("--confirm", type=int, default=32)
    ap.add_argument("--margin", type=float, default=0.06, help="required win-rate gain to promote")
    ap.add_argument("--seed", type=int, default=None)
    ap.add_argument("--workers", type=int, default=os.cpu_count() or 4)
    ap.add_argument("--budget-min", type=float, default=240.0, help="stop starting new work after this many minutes")
    ap.add_argument("--apply", action="store_true", help="write the winning parameters into main.py")
    a = ap.parse_args()

    t0 = time.time()
    rng = random.Random(a.seed if a.seed is not None else int(time.time()))
    base = champion_params()
    seed0 = rng.randrange(10**6)

    print(f"screening {a.candidates} candidates on {a.screen} games/opponent")
    champ_screen = gauntlet("kaggriculture/main.py", a.screen, seed0, a.workers)
    print(f"champion screen winrate: {champ_screen:.3f}")

    scored = []
    for i in range(a.candidates):
        if (time.time() - t0) / 60 > a.budget_min:
            print("time budget reached, stopping screen")
            break
        ov = make_candidate(base, rng)
        if not ov:
            continue
        rel = variant_path(f"s{i}", ov)
        wr = gauntlet(rel, a.screen, seed0, a.workers)
        if wr is None:
            print(f"  cand {i}: FAILED to run {ov}")
            continue
        scored.append((wr, ov, rel))
        print(f"  cand {i}: {wr:.3f}  {ov}")

    if not scored:
        print("no candidates scored")
        return
    scored.sort(reverse=True, key=lambda x: x[0])
    survivors = scored[: a.survivors]
    print(f"\nconfirming {len(survivors)} survivors on {a.confirm} games/opponent")
    seed1 = rng.randrange(10**6)
    champ_conf = gauntlet("kaggriculture/main.py", a.confirm, seed1, a.workers)
    print(f"champion confirm winrate: {champ_conf:.3f}")

    results = []
    for wr, ov, rel in survivors:
        if (time.time() - t0) / 60 > a.budget_min * 1.5:
            print("hard time budget reached, stopping confirm")
            break
        c = gauntlet(rel, a.confirm, seed1, a.workers)
        if c is None:
            continue
        results.append((c, ov))
        print(f"  {c:.3f} (screen {wr:.3f})  {ov}")

    results.sort(reverse=True, key=lambda x: x[0])
    state = {
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "champion_confirm": champ_conf,
        "confirm_games": a.confirm,
        "results": [{"winrate": c, "overrides": ov} for c, ov in results],
    }
    promoted = None
    if results and results[0][0] >= champ_conf + a.margin:
        promoted = results[0]
        state["promoted"] = {"winrate": promoted[0], "overrides": promoted[1]}
        print(f"\nPROMOTE: {promoted[0]:.3f} vs champion {champ_conf:.3f} (+{promoted[0]-champ_conf:.3f})")
        print(f"  {promoted[1]}")
    else:
        best = results[0][0] if results else 0.0
        print(f"\nno promotion: best {best:.3f} vs champion {champ_conf:.3f}, margin {a.margin}")
    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    json.dump(state, open(STATE, "w"), indent=2)
    print(f"wrote {STATE}")

    if promoted and a.apply:
        apply_overrides(promoted[1])
        print("applied to main.py")


def apply_overrides(overrides):
    src = open(MAIN).read()
    for k, v in overrides.items():
        pat = re.compile(rf'(^\s*"{re.escape(k)}":\s*)([^,\n]+)(,)', re.M)
        if not pat.search(src):
            print(f"  WARNING: parameter {k} not found in main.py, skipped")
            continue
        src = pat.sub(lambda m: f"{m.group(1)}{v!r}{m.group(3)}", src, count=1)
    open(MAIN, "w").write(src)


if __name__ == "__main__":
    main()
