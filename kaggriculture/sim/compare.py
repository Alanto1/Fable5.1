"""Two-sided comparison of one game: money by day, farm census, revenue by product for BOTH players."""
import sys, os, importlib.util, collections
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, ROOT)
from kaggle_environments import make

def load(path):
    spec = importlib.util.spec_from_file_location("agent_mod_" + str(abs(hash(path))), path)
    m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
    return m

def census(tiles):
    c = collections.Counter()
    for row in tiles:
        for t in row:
            if isinstance(t, dict) and t.get("animal"): c[t["animal"]] += 1
            elif isinstance(t, dict) and t.get("kind") == "PLANT": c[t["crop"]] += 1
            elif t is None: c["empty"] += 1
    return dict(c)

def main():
    a_path, b_path, seed = sys.argv[1], sys.argv[2], int(sys.argv[3])
    mods = [load(os.path.join(ROOT, p)) for p in (a_path, b_path)]
    rev = [collections.defaultdict(lambda: [0, 0.0]) for _ in range(2)]
    hires = [0, 0]
    spend = [collections.defaultdict(float) for _ in range(2)]
    ops = [collections.Counter() for _ in range(2)]
    def mk(i):
        def f(obs, cfg):
            a = mods[i].agent(obs, cfg)
            pr = obs["market"]["prices"]
            for o in a["market"]:
                if o[0] == "SELL" and len(o) >= 3:
                    rev[i][o[1]][0] += int(o[2]); rev[i][o[1]][1] += int(o[2]) * pr.get(o[1], 0)
                elif o[0] == "HIRE":
                    hires[i] += 1
                elif o[0] == "BUY_PRODUCT" and len(o) >= 3:
                    spend[i][o[1]] += int(o[2]) * pr.get(o[1], 0)
                elif o[0] == "BUY_ANIMAL" and len(o) >= 3:
                    spend[i]["animals"] += int(o[2]) * {"GOOSE": 300, "COW": 400, "SHEEP": 500}.get(o[1], 0)
                elif o[0] == "BUY_SEED" and len(o) >= 3:
                    spend[i]["seeds"] += int(o[2]) * {"WHEAT": 10, "CARROT": 20, "TOMATO": 50, "STRAWBERRY": 100, "MELON": 80}.get(o[1], 0)
            for o in [a["farmer"]] + a["hands"]:
                ops[i][o[0] if o[0] in ("NORTH","SOUTH","EAST","WEST") and False else ("MOVE" if o[0] in ("NORTH","SOUTH","EAST","WEST") else o[0])] += 1
            return a
        return f
    env = make("kaggriculture", configuration={"episodeSteps": 720, "seed": seed}, debug=True)
    env.run([mk(0), mk(1)])
    names = [os.path.basename(a_path), os.path.basename(b_path)]
    print(f"seed {seed}: {names[0]}=${env.steps[-1][0].reward:,.0f}  {names[1]}=${env.steps[-1][1].reward:,.0f}  shops={env.steps[-1][0].observation['town']['unlocked_shops']}")
    for d in (3, 6, 9, 12, 15, 18, 21, 24, 27):
        ob = env.steps[d * 24 + 12][0].observation
        line = f"day {d:2d} "
        for i in (0, 1):
            f = ob["farms"][i]
            line += f"| P{i} ${f['money']:>7,.0f} h={len(f['hands']):2d} L={len(f['unlocked_quadrants'])} {census(f['tiles'])} "
        print(line)
        pr = ob["market"]["prices"]
        print("        prices: " + " ".join(f"{k[:5]}={v}" for k, v in pr.items()))
    for i in (0, 1):
        print(f"{names[i]} revenue: " + " ".join(f"{k}=({v[0]},{v[1]:,.0f},{v[1]/max(1,v[0]):.0f})" for k, v in sorted(rev[i].items(), key=lambda kv: -kv[1][1])) + f" hires={hires[i]}")
        print(f"{names[i]} spend: " + " ".join(f"{k}={v:,.0f}" for k, v in sorted(spend[i].items(), key=lambda kv: -kv[1])) + " | ops: " + " ".join(f"{k}={v}" for k, v in ops[i].most_common(8)))

if __name__ == "__main__":
    main()
