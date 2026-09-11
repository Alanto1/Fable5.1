"""Step trace: print each unit's op, market orders, money and shed for a step range."""
import sys, os, importlib.util
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, ROOT)
from kaggle_environments import make

def load(path):
    spec = importlib.util.spec_from_file_location("agent_mod_" + str(abs(hash(path))), path)
    m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
    return m

def main():
    agent_path, s0, s1 = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
    seed = int(sys.argv[4]) if len(sys.argv) > 4 else 1
    opp = sys.argv[5] if len(sys.argv) > 5 else "starter"
    m = load(os.path.join(ROOT, agent_path))
    log = []
    def wrapped(obs, cfg):
        a = m.agent(obs, cfg)
        st = obs["step"]
        if s0 <= st <= s1:
            f = obs["farms"][obs["player"]]
            shed = {k: v for k, v in obs["private"]["shed"].items() if v}
            invs = [{k: v for k, v in i.items() if v} for i in obs["private"]["inventories"]]
            log.append(f"step {st:3d} d{obs['day']}h{obs['hour']:2d} ${f['money']:,.0f} farmer@{f['farmer']} hands@{f['hands']} "
                       f"ops={[a['farmer']] + a['hands']} mkt={a['market']} shed={shed} seeds={ {k:v for k,v in obs['private']['seeds'].items() if v} } invs={invs}")
        return a
    opp_fn = opp if opp in ("starter", "random", "pass") else os.path.join(ROOT, opp)
    env = make("kaggriculture", configuration={"episodeSteps": min(720, s1 + 3), "seed": seed}, debug=True)
    env.run([wrapped, opp_fn])
    print("\n".join(log))
    if hasattr(m, "MEM"):
        mem = m.MEM.get(0, {})
        print("vals:", {k: (round(v[0]), round(v[1], 1)) for k, v in (mem.get("vals") or {}).items()})
        print("plan:", mem.get("plan"))

if __name__ == "__main__":
    main()
