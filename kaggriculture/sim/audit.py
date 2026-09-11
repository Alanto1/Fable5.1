"""End-of-game audit: action-type counts, unsold shed value, hire cost, animals lost, day-29 behavior."""
import sys, os, importlib.util, collections
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, ROOT)
from kaggle_environments import make

def load(path):
    spec = importlib.util.spec_from_file_location("agent_mod_" + str(abs(hash(path))), path)
    m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
    return m

def main():
    agent_path = sys.argv[1]; opp = sys.argv[2] if len(sys.argv) > 2 else "starter"
    seeds = [int(s) for s in (sys.argv[3] if len(sys.argv) > 3 else "1").split(",")]
    m = load(os.path.join(ROOT, agent_path))
    for seed in seeds:
        m.MEM.clear()
        ops = collections.Counter(); mk = collections.Counter(); unit_turns = 0
        def wrapped(obs, cfg):
            nonlocal unit_turns
            a = m.agent(obs, cfg)
            for o in [a["farmer"]] + a["hands"]:
                ops[o[0]] += 1; unit_turns += 1
            for o in a["market"]:
                mk[o[0]] += 1
            return a
        opp_fn = opp if opp in ("starter", "random", "pass") else os.path.join(ROOT, opp)
        env = make("kaggriculture", configuration={"episodeSteps": 720, "seed": seed}, debug=True)
        env.run([wrapped, opp_fn])
        fin = env.steps[-1]
        ob = fin[0].observation
        shed = {k: v for k, v in ob["private"]["shed"].items() if v}
        prices = ob["market"]["prices"]
        unsold = sum(prices.get(k, 0) * v for k, v in shed.items() if k in prices)
        invs = [{k: v for k, v in i.items() if v} for i in ob["private"]["inventories"]]
        carried = sum(prices.get(k, 0) * v for i in invs for k, v in i.items() if k in prices)
        tiles = ob["farms"][0]["tiles"]
        on_tiles = 0
        for row in tiles:
            for t in row:
                if isinstance(t, dict) and t.get("yield_units"):
                    if t.get("animal"):
                        on_tiles += t["yield_units"] * prices.get({"GOOSE": "EGG", "COW": "MILK", "SHEEP": "WOOL"}[t["animal"]], 0)
                    elif t.get("crop"):
                        on_tiles += t["yield_units"] * prices.get(t["crop"], 0)
        print(f"seed {seed}: reward={fin[0].reward:,.0f} opp={fin[1].reward:,.0f}")
        print(f"   unit-actions={unit_turns} " + " ".join(f"{k}={v}" for k, v in ops.most_common()))
        print(f"   market: " + " ".join(f"{k}={v}" for k, v in mk.most_common()))
        print(f"   end shed={shed} unsold≈${unsold:,.0f}  carried≈${carried:,.0f}  on-tiles≈${on_tiles:,.0f}")
        print(f"   end prices={ {k: prices[k] for k in prices} }")

if __name__ == "__main__":
    main()
