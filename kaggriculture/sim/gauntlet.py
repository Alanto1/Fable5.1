"""Evaluate a candidate agent against a panel of diverse opponents.

Tuning against a single mirror of the previous champion overfits: it optimises for
beating one strategy rather than the real ladder's mix. This panel spans the
strategy profiles actually observed in downloaded ladder replays, so a candidate
has to be broadly good rather than narrowly good.

  python -m kaggriculture.sim.gauntlet --agent kaggriculture/main.py --games 24
  python -m kaggriculture.sim.gauntlet --check report.md
"""
import argparse, json, os, statistics, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, ROOT)

# Profiles fitted to composition curves seen in real ladder replays
# (see docs/kaggriculture/ladder-status.md for the observed targets).
PANEL = {
    # heavy strawberry + repeated melon: the dominant winning profile
    "ladder_straw": {"straw_mult": 2.2, "straw_cap": 48, "melon_repeat": 10,
                     "melon_last_day": 14, "wheat_fill_max": 12, "tomato_min_dem": 99},
    # animal-heavy: many cows and sheep, wheat for feed
    "ladder_animal": {"cow_k": 1.8, "sheep_k": 3.0, "max_cows": 16, "max_sheep": 20,
                      "straw_mult": 1.0, "melon_repeat": 0},
    # melon rusher: races the melon pot early and often
    "ladder_melon": {"melon_tiles": 16, "melon_repeat": 14, "melon_last_day": 16,
                     "melon_guard": 45, "straw_mult": 1.2},
    # broad generalist close to the current live submission
    "champion": {},
}
CHECK_MIN_WINRATE = 0.50


def write_variant(name, overrides, base):
    d = os.path.join(ROOT, "kaggriculture", "sim", "opponents")
    os.makedirs(d, exist_ok=True)
    path = os.path.join(d, f"gauntlet_{name}.py")
    tpl = (
        "# Auto-generated gauntlet opponent. Do not edit; regenerate with sim.gauntlet.\n"
        "import importlib.util as _ilu\n"
        f"_spec = _ilu.spec_from_file_location('gauntlet_{name}', {base!r})\n"
        "_m = _ilu.module_from_spec(_spec)\n"
        "_spec.loader.exec_module(_m)\n"
        f"_m.P.update({overrides!r})\n\n\n"
        "def agent(obs, config=None):\n"
        "    return _m.agent(obs, config)\n"
    )
    open(path, "w").write(tpl)
    return path


def run_pair(agent, opp, games, seed0, workers):
    cmd = [sys.executable, "-m", "kaggriculture.sim.run", "--agent", agent, "--opp", opp,
           "--games", str(games), "--seed0", str(seed0), "--quiet",
           "--workers", str(workers), "--json", "/tmp/gauntlet_raw.json"]
    r = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, timeout=7200)
    if r.returncode != 0:
        print(r.stdout[-2000:], r.stderr[-2000:])
        raise SystemExit(f"gauntlet run failed for {opp}")
    res = json.load(open("/tmp/gauntlet_raw.json"))
    wins = sum(1 for x in res if x["me"] > x["opp"])
    ties = sum(1 for x in res if x["me"] == x["opp"])
    errs = sum(1 for x in res if x["status_me"] != "DONE")
    return {
        "games": len(res),
        "wins": wins,
        "ties": ties,
        "errors": errs,
        "winrate": wins / max(1, len(res)),
        "me_mean": statistics.mean(x["me"] for x in res),
        "opp_mean": statistics.mean(x["opp"] for x in res),
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--agent", default="kaggriculture/main.py")
    ap.add_argument("--base", default=None, help="module the opponents are built from")
    ap.add_argument("--games", type=int, default=24)
    ap.add_argument("--seed0", type=int, default=50000)
    ap.add_argument("--workers", type=int, default=os.cpu_count() or 4)
    ap.add_argument("--only", default=None, help="comma-separated subset of panel names")
    ap.add_argument("--out", default="-")
    ap.add_argument("--check", default=None, help="verify a previous report instead of running")
    a = ap.parse_args()

    if a.check:
        txt = open(a.check).read()
        line = [l for l in txt.splitlines() if l.startswith("OVERALL_WINRATE=")]
        if not line:
            raise SystemExit("report has no OVERALL_WINRATE line")
        wr = float(line[0].split("=", 1)[1])
        print(f"overall winrate {wr:.3f} (minimum {CHECK_MIN_WINRATE})")
        if wr < CHECK_MIN_WINRATE:
            raise SystemExit(f"FAIL: candidate below {CHECK_MIN_WINRATE:.0%} against the panel")
        print("PASS")
        return

    base = a.base or os.path.join(ROOT, "kaggriculture", "sim", "opponents", "champ_v6f.py")
    names = a.only.split(",") if a.only else list(PANEL)
    rows = []
    for k, name in enumerate(names):
        opp = write_variant(name, PANEL[name], base)
        rel = os.path.relpath(opp, ROOT)
        r = run_pair(a.agent, rel, a.games, a.seed0 + 1000 * k, a.workers)
        r["name"] = name
        rows.append(r)
        print(f"{name:16s} {r['wins']:2d}/{r['games']:2d} ({r['winrate']:.0%})  "
              f"me={r['me_mean']:,.0f} opp={r['opp_mean']:,.0f} errors={r['errors']}")

    tot_w = sum(r["wins"] for r in rows)
    tot_g = sum(r["games"] for r in rows)
    overall = tot_w / max(1, tot_g)
    L = ["# Gauntlet result", "", f"Agent: `{a.agent}`  games per opponent: {a.games}", "",
         "| Opponent | Record | Win rate | Our mean | Their mean | Errors |",
         "|---|---|---|---|---|---|"]
    for r in rows:
        L.append(f"| {r['name']} | {r['wins']}/{r['games']} | {r['winrate']:.0%} | "
                 f"{r['me_mean']:,.0f} | {r['opp_mean']:,.0f} | {r['errors']} |")
    L += ["", f"**Overall: {tot_w}/{tot_g} = {overall:.1%}**", "", f"OVERALL_WINRATE={overall:.4f}"]
    text = "\n".join(L) + "\n"
    if a.out == "-":
        print(text)
    else:
        open(a.out, "w").write(text)
        print(text)


if __name__ == "__main__":
    main()
