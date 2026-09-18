"""Summarise harvested ladder episodes: win rate, score gaps, and composition deltas.

Reads kaggriculture/ladder/features/*.json (written by harvest.py) and writes a
markdown report. The composition table is the important part: it shows, per game
day, how our farm differs from the farms of the opponents who beat us.
"""
import argparse, collections, glob, json, os, statistics

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
FEAT = os.path.join(ROOT, "kaggriculture", "ladder", "features")
KINDS = ["STRAWBERRY", "MELON", "WHEAT", "CARROT", "TOMATO", "COW", "SHEEP", "GOOSE", "weed", "empty"]
DAYS = [9, 15, 21, 27]


def load():
    out = []
    for f in sorted(glob.glob(os.path.join(FEAT, "*.json"))):
        try:
            d = json.load(open(f))
        except Exception:
            continue
        if d.get("my_seat") is None or not d.get("rewards"):
            continue
        out.append(d)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--rating", default="?")
    ap.add_argument("--out", default="-")
    a = ap.parse_args()
    eps = load()
    L = []
    if not eps:
        L.append("# Ladder status\n\nNo episodes harvested yet.\n")
        emit(L, a.out)
        return

    wins = losses = 0
    my_scores, opp_scores, margins = [], [], []
    comp = {"me": collections.defaultdict(list), "opp": collections.defaultdict(list)}
    comp_lost = {"me": collections.defaultdict(list), "opp": collections.defaultdict(list)}
    opponents = collections.Counter()
    opp_beat_us = collections.Counter()
    hires = {"me": [], "opp": []}
    errors = []

    for d in eps:
        i = d["my_seat"]
        j = 1 - i
        mine, theirs = d["rewards"][i], d["rewards"][j]
        won = mine > theirs
        wins += won
        losses += (not won)
        my_scores.append(mine)
        opp_scores.append(theirs)
        margins.append(mine - theirs)
        opponents[d["teams"][j]] += 1
        if not won:
            opp_beat_us[d["teams"][j]] += 1
        st = d.get("statuses") or []
        if any(s not in ("DONE", "ACTIVE") for s in st):
            errors.append((d["episode_id"], st))
        for tag, seat in (("me", i), ("opp", j)):
            s = d["seats"][seat]
            hires[tag].append(s.get("hires_total", 0))
            for day in DAYS:
                c = s["census_by_day"].get(str(day), {})
                for k in KINDS:
                    comp[tag][(day, k)].append(c.get(k, 0))
                    if not won:
                        comp_lost[tag][(day, k)].append(c.get(k, 0))

    n = len(eps)
    L.append("# Kaggriculture ladder status\n")
    L.append(f"- Episodes analysed: **{n}**")
    L.append(f"- Record: **{wins}W / {losses}L** ({100.0*wins/n:.0f}% win rate)")
    L.append(f"- Current rating: **{a.rating}**")
    L.append(f"- Mean score: **{statistics.mean(my_scores):,.0f}** vs opponents **{statistics.mean(opp_scores):,.0f}**")
    L.append(f"- Mean margin: **{statistics.mean(margins):+,.0f}**")
    L.append(f"- Hires per game: ours {statistics.mean(hires['me']):.0f}, opponents {statistics.mean(hires['opp']):.0f}")
    if errors:
        L.append(f"- **Non-DONE statuses in {len(errors)} episodes**: {errors[:5]}")
    else:
        L.append("- No crashes or timeouts detected")

    L.append("\n## Farm composition vs opponents (mean tiles)\n")
    L.append("| Day | Kind | Us | Them | Gap |")
    L.append("|---|---|---|---|---|")
    rows = []
    for day in DAYS:
        for k in KINDS:
            m = comp["me"][(day, k)]
            o = comp["opp"][(day, k)]
            if not m and not o:
                continue
            mm = statistics.mean(m) if m else 0.0
            om = statistics.mean(o) if o else 0.0
            if abs(mm - om) < 1.0:
                continue
            rows.append((abs(mm - om), day, k, mm, om))
    for _, day, k, mm, om in sorted(rows, reverse=True)[:18]:
        L.append(f"| {day} | {k} | {mm:.1f} | {om:.1f} | {mm-om:+.1f} |")

    L.append("\n## Same table, losses only\n")
    L.append("| Day | Kind | Us | Them | Gap |")
    L.append("|---|---|---|---|---|")
    rows = []
    for day in DAYS:
        for k in KINDS:
            m = comp_lost["me"][(day, k)]
            o = comp_lost["opp"][(day, k)]
            if not m or not o:
                continue
            mm, om = statistics.mean(m), statistics.mean(o)
            if abs(mm - om) < 1.0:
                continue
            rows.append((abs(mm - om), day, k, mm, om))
    for _, day, k, mm, om in sorted(rows, reverse=True)[:18]:
        L.append(f"| {day} | {k} | {mm:.1f} | {om:.1f} | {mm-om:+.1f} |")

    L.append("\n## Opponents faced most\n")
    L.append("| Opponent | Games | Beat us |")
    L.append("|---|---|---|")
    for name, c in opponents.most_common(12):
        L.append(f"| {name} | {c} | {opp_beat_us[name]} |")
    emit(L, a.out)


def emit(lines, out):
    text = "\n".join(lines) + "\n"
    if out == "-":
        print(text)
    else:
        os.makedirs(os.path.dirname(out), exist_ok=True)
        with open(out, "w") as f:
            f.write(text)
        print(f"wrote {out}")
        print(text)


if __name__ == "__main__":
    main()
