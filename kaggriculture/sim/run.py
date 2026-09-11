"""Parallel local evaluation harness for Kaggriculture agents.

Usage:
  python -m kaggriculture.sim.run --agent kaggriculture/main.py --opp starter --games 20
  python -m kaggriculture.sim.run --agent kaggriculture/main.py --opp kaggriculture/sim/opponents/goose_rush.py --games 40 --seed0 100

Plays the agent as player 0 and player 1 alternately (seat swap), reports mean income,
win rate, per-seat stats, and the slowest agent step time.
"""
import argparse
import json
import os
import statistics
import sys
import time
from concurrent.futures import ProcessPoolExecutor

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)


def _resolve(spec):
    if spec in ("starter", "random", "pass"):
        return spec
    p = spec if os.path.isabs(spec) else os.path.join(ROOT, spec)
    if not os.path.exists(p):
        raise FileNotFoundError(spec)
    return p


def play_one(args):
    agent_spec, opp_spec, seed, swap, steps, debug, save_replay = args
    from kaggle_environments import make
    env = make("kaggriculture", configuration={"episodeSteps": steps, "seed": seed}, debug=debug)
    agents = [_resolve(agent_spec), _resolve(opp_spec)]
    if swap:
        agents = agents[::-1]
    t = time.time()
    env.run(agents)
    dt = time.time() - t
    final = env.steps[-1]
    me = 1 if swap else 0
    r_me = final[me].reward or 0.0
    r_op = final[1 - me].reward or 0.0
    st_me = final[me].status
    st_op = final[1 - me].status
    # per-day money trace for the agent (for diagnostics)
    trace = []
    for i in range(0, len(env.steps), 24):
        trace.append(round(env.steps[i][0].observation["farms"][me]["money"]))
    town = env.steps[-1][0].observation["town"]["unlocked_shops"]
    if save_replay:
        os.makedirs(os.path.join(ROOT, "kaggriculture", "sim", "replays"), exist_ok=True)
        with open(os.path.join(ROOT, "kaggriculture", "sim", "replays", f"replay_{seed}_{int(swap)}.json"), "w") as f:
            json.dump(env.toJSON(), f)
    return {"seed": seed, "swap": swap, "me": r_me, "opp": r_op, "status_me": st_me, "status_opp": st_op,
            "secs": dt, "trace": trace, "town": town}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--agent", required=True)
    ap.add_argument("--opp", default="starter")
    ap.add_argument("--games", type=int, default=10)
    ap.add_argument("--seed0", type=int, default=1)
    ap.add_argument("--steps", type=int, default=720)
    ap.add_argument("--workers", type=int, default=os.cpu_count() or 2)
    ap.add_argument("--debug", action="store_true")
    ap.add_argument("--replay", action="store_true")
    ap.add_argument("--json", default=None, help="write raw results to this path")
    ap.add_argument("--quiet", action="store_true")
    a = ap.parse_args()

    jobs = []
    for g in range(a.games):
        seed = a.seed0 + g
        jobs.append((a.agent, a.opp, seed, bool(g % 2), a.steps, a.debug, a.replay))
    t0 = time.time()
    with ProcessPoolExecutor(max_workers=a.workers) as ex:
        results = list(ex.map(play_one, jobs))
    wall = time.time() - t0

    me = [r["me"] for r in results]
    opp = [r["opp"] for r in results]
    wins = sum(1 for r in results if r["me"] > r["opp"])
    ties = sum(1 for r in results if r["me"] == r["opp"])
    errs = sum(1 for r in results if r["status_me"] not in ("DONE",))
    print(f"agent={a.agent} opp={a.opp} games={a.games} wall={wall:.1f}s")
    print(f"  income  mean={statistics.mean(me):,.0f} median={statistics.median(me):,.0f} "
          f"min={min(me):,.0f} max={max(me):,.0f}")
    print(f"  opp     mean={statistics.mean(opp):,.0f}")
    print(f"  winrate {wins}/{a.games} ({100*wins/a.games:.0f}%) ties={ties} errors={errs}")
    p0 = [r["me"] for r in results if not r["swap"]]
    p1 = [r["me"] for r in results if r["swap"]]
    if p0 and p1:
        print(f"  seat0 mean={statistics.mean(p0):,.0f}  seat1 mean={statistics.mean(p1):,.0f}")
    if not a.quiet:
        for r in results:
            print(f"   seed={r['seed']:4d} swap={int(r['swap'])} me={r['me']:>9,.0f} opp={r['opp']:>9,.0f} "
                  f"{'W' if r['me']>r['opp'] else ('T' if r['me']==r['opp'] else 'L')} "
                  f"{r['status_me']}/{r['status_opp']} {r['secs']:.1f}s town={r['town']}")
    if a.json:
        with open(a.json, "w") as f:
            json.dump(results, f)


if __name__ == "__main__":
    main()
