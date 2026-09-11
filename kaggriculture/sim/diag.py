"""Single-game diagnostic: per-day money, farm census, market prices, agent step time."""
import sys, os, time, importlib.util, collections
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, ROOT)
from kaggle_environments import make

def load(path):
    spec = importlib.util.spec_from_file_location("agent_mod_" + str(abs(hash(path))), path)
    m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
    return m

def main():
    agent_path = sys.argv[1]
    opp = sys.argv[2] if len(sys.argv) > 2 else "starter"
    seed = int(sys.argv[3]) if len(sys.argv) > 3 else 1
    m = load(os.path.join(ROOT, agent_path))
    times = []
    def wrapped(obs, cfg):
        t = time.perf_counter(); a = m.agent(obs, cfg); times.append(time.perf_counter() - t); return a
    opp_fn = opp if opp in ("starter", "random", "pass") else os.path.join(ROOT, opp)
    env = make("kaggriculture", configuration={"episodeSteps": 720, "seed": seed}, debug=True)
    env.run([wrapped, opp_fn])
    lost_total = 0
    for d in range(0, 30):
        st = env.steps[min(d * 24, len(env.steps) - 1)]
        ob = st[0].observation
        f = ob["farms"][0]
        st12 = env.steps[min(d * 24 + 12, len(env.steps) - 1)]
        hands12 = len(st12[0].observation["farms"][0]["hands"])
        # animals lost overnight: animal tiles at day d-1 hour 23 that are empty structures now
        lost = 0
        if d > 0:
            prev = env.steps[d * 24 - 1][0].observation["farms"][0]["tiles"]
            cur = f["tiles"]
            for y in range(len(cur)):
                for x in range(len(cur)):
                    pt, ct = prev[y][x], cur[y][x]
                    if isinstance(pt, dict) and pt.get("animal") and isinstance(ct, dict) and not ct.get("animal") and ct.get("kind") in ("COOP", "PASTURE"):
                        lost += 1
        lost_total += lost
        census = collections.Counter()
        for row in f["tiles"]:
            for t in row:
                if t is None: census["empty"] += 1
                elif t == "LOCKED": pass
                elif isinstance(t, dict) and t.get("animal"): census[t["animal"]] += 1
                elif isinstance(t, dict) and t.get("kind") == "PLANT": census[t["crop"]] += 1
                elif isinstance(t, dict) and t.get("kind") == "WEED": census["weed"] += 1
                elif isinstance(t, dict): census["struct"] += 1
        pr = ob["market"]["prices"]
        shed = {k: v for k, v in st[0].observation["private"]["shed"].items() if v}
        print(f"day {d:2d} ${f['money']:>9,.0f} opp ${ob['farms'][1]['money']:>8,.0f} hands@12={hands12} lost={lost} land={len(f['unlocked_quadrants'])} "
              f"{dict(census)} shed={shed} shops={len(ob['town']['unlocked_shops'])} "
              f"P: W{pr['WHEAT']} E{pr['EGG']} M{pr['MELON']} F{pr['FERTILIZER']} C{pr['CARROT']} S{pr['STRAWBERRY']} Mi{pr['MILK']} Wo{pr['WOOL']} T{pr['TOMATO']}")
    fin = env.steps[-1]
    print("FINAL:", [(i, s.reward, s.status) for i, s in enumerate(fin)], "animals lost total:", lost_total)
    print("shops:", env.steps[-1][0].observation["town"]["unlocked_shops"])
    print(f"agent step time: mean={1000*sum(times)/len(times):.1f}ms max={1000*max(times):.1f}ms n={len(times)}")

if __name__ == "__main__":
    main()
