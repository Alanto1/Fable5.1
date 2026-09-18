"""Download Kaggriculture episode replays, extract compact features, delete the raw JSON.

Raw replays are ~30 MB each; only the extracted features are kept (a few KB per seat).
Features land in kaggriculture/ladder/features/<episode_id>.json and are safe to commit.

Usage:
  python -m kaggriculture.ladder.harvest --submission 56185165 --limit 40
  python -m kaggriculture.ladder.harvest --me "JOP OK" --limit 20
"""
import argparse, collections, json, os, subprocess, sys, tempfile, shutil

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
FEAT = os.path.join(ROOT, "kaggriculture", "ladder", "features")
ANIMAL_COST = {"GOOSE": 300, "COW": 400, "SHEEP": 500}
SEED_COST = {"WHEAT": 10, "CARROT": 20, "TOMATO": 50, "STRAWBERRY": 100, "MELON": 80}
PRODUCTS = ["WHEAT", "CARROT", "TOMATO", "STRAWBERRY", "MELON", "EGG", "MILK", "WOOL", "FERTILIZER"]


def census(tiles):
    c = collections.Counter()
    for row in tiles:
        for t in row:
            if isinstance(t, dict) and t.get("animal"):
                c[t["animal"]] += 1
            elif isinstance(t, dict) and t.get("kind") == "PLANT":
                c[t["crop"]] += 1
            elif isinstance(t, dict) and t.get("kind") == "WEED":
                c["weed"] += 1
            elif t is None:
                c["empty"] += 1
    return dict(c)


def seat_features(d, i):
    """Realized (not requested) economics for one seat, plus daily farm composition."""
    steps = d["steps"]
    n = len(steps)
    ops = collections.Counter()
    hires_by_day = collections.Counter()
    land_days = []
    money = {}
    cen = {}
    realized_sales = collections.defaultdict(lambda: [0, 0.0])
    realized_buys = collections.defaultdict(lambda: [0, 0.0])
    spend_seeds = 0.0
    spend_animals = 0.0
    prev_land = 1
    prev_shed = None
    for k in range(n):
        st = steps[k]
        ob0 = steps[k][0]["observation"]
        farm = ob0["farms"][i]
        pr = ob0["market"]["prices"]
        day, hour = k // 24, k % 24
        if hour == 12 or day not in cen:
            cen[day] = census(farm["tiles"])
            money[day] = farm["money"]
        if len(farm["unlocked_quadrants"]) > prev_land:
            land_days.append(day)
            prev_land = len(farm["unlocked_quadrants"])
        a = st[i].get("action") or {}
        if not isinstance(a, dict):
            continue
        for o in [a.get("farmer", ["PASS"])] + (a.get("hands") or []):
            if isinstance(o, list) and o:
                ops[o[0]] += 1
        # realized sales: cap the requested quantity by what the shed actually held
        priv = st[i].get("observation", {}).get("private") or {}
        shed = priv.get("shed") or {}
        for o in (a.get("market") or []):
            if not isinstance(o, list) or not o:
                continue
            if o[0] == "HIRE":
                hires_by_day[day] += 1
                continue
            if len(o) < 3:
                continue
            try:
                q = int(o[2])
            except (TypeError, ValueError):
                continue
            item = o[1]
            if o[0] == "SELL":
                got = min(q, int(shed.get(item, 0)))
                if got > 0:
                    realized_sales[item][0] += got
                    realized_sales[item][1] += got * pr.get(item, 0)
            elif o[0] == "BUY_PRODUCT":
                realized_buys[item][0] += q
                realized_buys[item][1] += q * pr.get(item, 0)
            elif o[0] == "BUY_SEED":
                spend_seeds += q * SEED_COST.get(item, 0)
            elif o[0] == "BUY_ANIMAL":
                spend_animals += q * ANIMAL_COST.get(item, 0)
    return {
        "ops": dict(ops),
        "hires_total": sum(hires_by_day.values()),
        "hires_by_day": {str(k): v for k, v in sorted(hires_by_day.items())},
        "land_days": land_days,
        "money_by_day": {str(k): v for k, v in sorted(money.items())},
        "census_by_day": {str(k): v for k, v in sorted(cen.items())},
        "sales": {k: {"units": v[0], "value": round(v[1])} for k, v in realized_sales.items()},
        "buys": {k: {"units": v[0], "value": round(v[1])} for k, v in realized_buys.items()},
        "spend_seeds": spend_seeds,
        "spend_animals": spend_animals,
    }


def extract(path, me_name):
    d = json.load(open(path))
    info = d.get("info", {})
    names = info.get("TeamNames") or ["?", "?"]
    out = {
        "episode_id": info.get("EpisodeId"),
        "module_version": d.get("module_version"),
        "seed": info.get("seed"),
        "teams": names,
        "rewards": d.get("rewards"),
        "statuses": d.get("statuses"),
        "configuration": d.get("configuration"),
        "shops": d["steps"][-1][0]["observation"]["town"]["unlocked_shops"],
        "final_prices": d["steps"][-1][0]["observation"]["market"]["prices"],
        "seats": [seat_features(d, 0), seat_features(d, 1)],
    }
    out["my_seat"] = names.index(me_name) if me_name in names else None
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--submission", help="submission id to pull episodes from")
    ap.add_argument("--episodes", help="comma-separated episode ids instead")
    ap.add_argument("--limit", type=int, default=20)
    ap.add_argument("--me", default="JOP OK")
    a = ap.parse_args()
    os.makedirs(FEAT, exist_ok=True)
    env = dict(os.environ)
    tok = os.path.expanduser("~/.kaggle/access_token")
    if os.path.exists(tok) and "KAGGLE_API_TOKEN" not in env:
        env["KAGGLE_API_TOKEN"] = open(tok).read().strip()

    if a.episodes:
        ids = [x.strip() for x in a.episodes.split(",") if x.strip()]
    else:
        r = subprocess.run(["kaggle", "competitions", "episodes", str(a.submission), "-v"],
                           capture_output=True, text=True, env=env, timeout=600)
        ids = []
        for line in r.stdout.splitlines()[1:]:
            parts = line.split(",")
            if parts and parts[0].strip().isdigit():
                ids.append(parts[0].strip())
    have = {f.split(".")[0] for f in os.listdir(FEAT)}
    todo = [i for i in ids if i not in have][: a.limit]
    print(f"{len(ids)} episodes listed, {len(have)} already extracted, downloading {len(todo)}")
    tmp = tempfile.mkdtemp(prefix="kagg_replay_")
    ok = 0
    try:
        for eid in todo:
            try:
                subprocess.run(["kaggle", "competitions", "replay", eid, "-p", tmp],
                               capture_output=True, text=True, env=env, timeout=600, check=True)
            except Exception as e:
                print(f"  {eid}: download failed ({type(e).__name__})")
                continue
            path = os.path.join(tmp, f"episode-{eid}-replay.json")
            if not os.path.exists(path):
                cands = [p for p in os.listdir(tmp) if eid in p]
                if not cands:
                    print(f"  {eid}: no file produced")
                    continue
                path = os.path.join(tmp, cands[0])
            try:
                feat = extract(path, a.me)
                with open(os.path.join(FEAT, f"{eid}.json"), "w") as fh:
                    json.dump(feat, fh, separators=(",", ":"))
                rw = feat["rewards"]
                ms = feat["my_seat"]
                tag = "?" if ms is None else ("WIN" if rw[ms] > rw[1 - ms] else "LOSS")
                print(f"  {eid}: {feat['teams']} {rw} {tag}")
                ok += 1
            except Exception as e:
                print(f"  {eid}: extract failed {type(e).__name__}: {e}")
            finally:
                if os.path.exists(path):
                    os.remove(path)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print(f"extracted {ok} episodes into {FEAT}")


if __name__ == "__main__":
    main()
