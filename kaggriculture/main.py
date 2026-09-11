"""Kaggriculture agent — value-driven farm manager (v2).

Submission entry point: `agent(obs, config)` — the last callable in this file.

Pipeline every turn:
  1. Ctx           – parse observation, census of tiles/units, town demand rates.
  2. Planner       – (hour 0 and every 3 hours) allocate free tiles to the best option
                     (goose/cow/sheep/wheat/carrot/melon/tomato/strawberry) by discounted
                     projected value under cash + labor constraints; sunk assets
                     (animals/seeds already bought) are always placed first; decides land
                     purchases and the number of hands to hire.
  3. Tasks         – value-weighted task list per tile (feed/care/collect/harvest/water/
                     fertilize/plant/build/place/dig).
  4. Scheduler     – greedy unit-to-tile assignment with reservations + shed logistics
                     (wheat pickup for feeding, animal pickup for placement, drops).
  5. Market        – hires, land, purchases, just-in-time feed wheat, price-aware selling.
"""
import math
import os
import json

# ----------------------------------------------------------------------------
# Engine constants (mirrored from kaggle_environments/envs/kaggriculture)
# ----------------------------------------------------------------------------
CROPS = {
    "WHEAT":      {"seed": 10,  "first": 2,  "maxday": 4,  "interval": 0, "max_yield": 6, "ongoing": False, "product": "WHEAT",      "units": 4},
    "CARROT":     {"seed": 20,  "first": 2,  "maxday": 3,  "interval": 0, "max_yield": 4, "ongoing": False, "product": "CARROT",     "units": 3},
    "TOMATO":     {"seed": 50,  "first": 8,  "maxday": 8,  "interval": 1, "max_yield": 4, "ongoing": True,  "product": "TOMATO",     "units": 4},
    "STRAWBERRY": {"seed": 100, "first": 10, "maxday": 10, "interval": 2, "max_yield": 4, "ongoing": True,  "product": "STRAWBERRY", "units": 4},
    "MELON":      {"seed": 80,  "first": 10, "maxday": 12, "interval": 0, "max_yield": 6, "ongoing": False, "product": "MELON",      "units": 6},
}
# cycle length (days from plant to harvest) for one-time crops
CYCLE = {"WHEAT": 4, "CARROT": 3, "MELON": 10}
ANIMALS = {
    "GOOSE": {"cost": 300, "structure": "COOP",    "first": 4, "interval": 1, "max_held": 4, "product": "EGG"},
    "COW":   {"cost": 400, "structure": "PASTURE", "first": 8, "interval": 2, "max_held": 6, "product": "MILK"},
    "SHEEP": {"cost": 500, "structure": "PASTURE", "first": 6, "interval": 3, "max_held": 6, "product": "WOOL"},
}
PRODUCTS = ["WHEAT", "CARROT", "TOMATO", "STRAWBERRY", "MELON", "EGG", "MILK", "WOOL", "FERTILIZER"]
I0 = 10000
MARKET_PARAMS = {
    "WHEAT":      {"base": 25,  "T": 400, "bf": "sqrt",   "bt": 0.80, "af": "log",    "at": 0.20},
    "CARROT":     {"base": 35,  "T": 450, "bf": "hinge",  "bt": 1.00, "af": "sqrt",   "at": 0.70},
    "TOMATO":     {"base": 60,  "T": 200, "bf": "hinge",  "bt": 0.40, "af": "sqrt",   "at": 0.60},
    "STRAWBERRY": {"base": 120, "T": 100, "bf": "sqrt",   "bt": 0.70, "af": "linear", "at": 1.60},
    "MELON":      {"base": 250, "T": 300, "bf": "log",    "bt": 0.20, "af": "sq",     "at": 3.60},
    "EGG":        {"base": 50,  "T": 332, "bf": "hinge",  "bt": 0.40, "af": "log",    "at": 0.20},
    "MILK":       {"base": 160, "T": 122, "bf": "sqrt",   "bt": 0.60, "af": "linear", "at": 1.60},
    "WOOL":       {"base": 200, "T": 105, "bf": "log",    "bt": 0.20, "af": "sq",     "at": 3.20},
    "FERTILIZER": {"base": 100, "T": 200, "bf": "linear", "bt": 0.40, "af": "linear", "at": 0.40},
}
SHOPS = {
    "BAKERY":         ["EGG", "WHEAT"],
    "PIZZA_SHOP":     ["MILK", "TOMATO", "WHEAT"],
    "BRUNCH_SPOT":    ["EGG", "WHEAT", "STRAWBERRY"],
    "YARN_STORE":     ["WOOL"],
    "ICE_CREAM_SHOP": ["STRAWBERRY", "MILK", "WHEAT"],
    "PET_CAFE":       ["CARROT"],
    "SMOOTHIE_SHOP":  ["STRAWBERRY", "MILK"],
    "FARMERS_MARKET": ["WHEAT", "CARROT", "TOMATO", "STRAWBERRY"],
}
LAND_PRICES = [1000, 2000, 4000]
TURNS_PER_DAY = 24
DAYS = 30
LAST_STEP = 718  # last step whose actions/market orders are processed
SHED_CAP = 100


def _shape(func, x, T):
    x = max(0.0, x)
    if func == "linear":
        return x
    if func == "sq":
        return x * x
    if func == "sqrt":
        return math.sqrt(x)
    if func == "log":
        return math.log(1.0 + x)
    if func == "hinge":
        u = x / T
        return u + 8.0 * max(0.0, u - 1.0) ** 2
    return x


def market_price(item, inv):
    p = MARKET_PARAMS[item]
    base, T = p["base"], p["T"]
    if inv < I0:
        amp = p["bt"] * base / _shape(p["bf"], T, T)
        price = base + amp * _shape(p["bf"], I0 - inv, T)
    else:
        amp = p["at"] * base / _shape(p["af"], T, T)
        price = base - amp * _shape(p["af"], inv - I0, T)
    return max(1, int(round(price)))


# Price table + prefix sums for O(1) average price over an inventory range.
_LO, _HI = I0 - 3000, I0 + 6000
_PREFIX = {}
for _item in PRODUCTS:
    _acc = [0]
    for _inv in range(_LO, _HI):
        _acc.append(_acc[-1] + market_price(_item, _inv))
    _PREFIX[_item] = _acc


def avg_price(item, a, b):
    """Average unit price selling with market inventory sweeping from a to b (either order)."""
    lo, hi = (a, b) if a <= b else (b, a)
    lo = int(max(_LO, min(_HI - 1, lo)))
    hi = int(max(lo + 1, min(_HI, hi)))
    pre = _PREFIX[item]
    return (pre[hi - _LO] - pre[lo - _LO]) / (hi - lo)


def fib(n):
    a, b = 1, 1
    for _ in range(n):
        a, b = b, a + b
    return a


# ----------------------------------------------------------------------------
# Tunable parameters (override with env KAGG_PARAMS='{"key": value}' for experiments)
# ----------------------------------------------------------------------------
P = {
    "max_hands": 13,          # cap on hands per day
    "hire_cap_cost": 400,     # never pay more than this for one hire
    "reserve_frac": 0.30,     # crash-prone goods: hold when price < base*frac
    "fert_reserve_frac": 0.12,
    "drop_threshold": 14,     # carried products before a unit drops when at the shed
    "discount_hi": 0.18,      # daily discount rate when capital-constrained (early)
    "discount_lo": 0.02,
    "land_margin": 0.6,       # buy land when 25 * best tile value * margin > price
    "fert_use_price": 40,     # apply fertilizer to crops when its sale price is below this
    "labor_lambda_min": 2.0,
    "feed_price_cap": 60,     # never pay more than this per feed wheat
    "opening": "auto",        # or e.g. "GOOSE:9" / "MELON:12,GOOSE:6" forced day-0 buys
    "replan_hours": 3,
    "feed_days": 2,
    "labor_margin": 1.15,
    "late_animal_day": 24,
}
try:
    P.update(json.loads(os.environ.get("KAGG_PARAMS", "") or "{}"))
except Exception:
    pass


# ----------------------------------------------------------------------------
# Observation helpers
# ----------------------------------------------------------------------------

def G(d, k, default=None):
    if d is None:
        return default
    try:
        v = d[k]
        return default if v is None else v
    except (KeyError, TypeError, IndexError):
        return getattr(d, k, default)


def is_plant(t):
    return isinstance(t, dict) and G(t, "kind") == "PLANT"


def is_animal(t):
    return isinstance(t, dict) and G(t, "animal") is not None


def is_structure(t):
    return isinstance(t, dict) and G(t, "kind") in ("COOP", "PASTURE") and G(t, "animal") is None


def is_weed(t):
    return isinstance(t, dict) and G(t, "kind") == "WEED"


def dist(a, b):
    return abs(a[0] - b[0]) + abs(a[1] - b[1])


MEM = {}


class Ctx:
    def __init__(self, obs):
        self.player = int(G(obs, "player", 0))
        self.step = int(G(obs, "step", 0))
        self.day = int(G(obs, "day", self.step // TURNS_PER_DAY))
        self.hour = int(G(obs, "hour", self.step % TURNS_PER_DAY))
        farms = G(obs, "farms", [])
        self.farm = farms[self.player]
        self.opp = farms[1 - self.player] if len(farms) > 1 else None
        self.tiles = G(self.farm, "tiles")
        self.n = len(self.tiles)
        self.half = self.n // 2
        self.money = float(G(self.farm, "money", 0))
        self.unlocked = list(G(self.farm, "unlocked_quadrants", ["NW"]))
        self.hires_today = int(G(self.farm, "hires_today", 0))
        priv = G(obs, "private", {})
        self.shed = {k: int(v) for k, v in dict(G(priv, "shed", {}) or {}).items()}
        self.seeds = {k: int(v) for k, v in dict(G(priv, "seeds", {}) or {}).items()}
        invs = list(G(priv, "inventories", [{}]) or [{}])
        self.positions = [tuple(G(self.farm, "farmer"))] + [tuple(h) for h in G(self.farm, "hands", [])]
        while len(invs) < len(self.positions):
            invs.append({})
        self.invs = [{k: int(v) for k, v in dict(i or {}).items() if v} for i in invs[:len(self.positions)]]
        market = G(obs, "market", {})
        self.inv = {k: int(v) for k, v in dict(G(market, "inventory", {})).items()}
        self.prices = {k: int(v) for k, v in dict(G(market, "prices", {})).items()}
        self.shops = list(G(G(obs, "town", {}), "unlocked_shops", []) or [])
        self.days_left = DAYS - self.day             # including today
        self.steps_left = LAST_STEP - self.step      # actionable steps after this one
        self.hours_left = min(TURNS_PER_DAY - self.hour, self.steps_left + 1)
        self.last_day = self.day >= DAYS - 1
        self.shed_access = [(self.half - 1, self.half - 1), (self.half, self.half - 1),
                            (self.half - 1, self.half), (self.half, self.half)]
        self.demand = self.town_demand_per_day()
        self.animals, self.plants, self.empties, self.weeds, self.structures = [], [], [], [], []
        for y in range(self.n):
            row = self.tiles[y]
            for x in range(self.n):
                t = row[x]
                if t is None:
                    self.empties.append((x, y))
                elif t == "LOCKED":
                    continue
                elif is_animal(t):
                    self.animals.append((x, y, t))
                elif is_plant(t):
                    self.plants.append((x, y, t))
                elif is_weed(t):
                    self.weeds.append((x, y))
                elif is_structure(t):
                    self.structures.append((x, y, t))
        self.shed_total = sum(self.shed.values())

    def town_demand_per_day(self):
        d = {p: 1.0 for p in PRODUCTS}
        d["FERTILIZER"] = 0.0
        ticks = TURNS_PER_DAY / 4.0
        for s in self.shops:
            prods = SHOPS.get(s, [])
            mult = 2 if len(prods) == 1 else 1
            for p in prods:
                d[p] += ticks * mult
        return d

    def nearest_shed_tile(self, pos):
        return min(self.shed_access, key=lambda t: dist(pos, t))

    def unit_count(self):
        return len(self.positions)

    def carried(self, item):
        return sum(i.get(item, 0) for i in self.invs)


# ----------------------------------------------------------------------------
# Economy model
# ----------------------------------------------------------------------------

def projected_supply(ctx):
    """Units of each product that will reach the market from our farm (and shed) over the season."""
    s = {p: 0.0 for p in PRODUCTS}
    dl = ctx.days_left
    for x, y, t in ctx.animals:
        a = ANIMALS[t["animal"]]
        age = ctx.day - int(G(t, "placed_day", ctx.day))
        prod_days = max(0.0, dl - max(0, a["first"] - age) - 0.5)
        s[a["product"]] += prod_days * (1.0 + a["interval"]) / a["interval"]
        s["FERTILIZER"] += dl - 1
    for x, y, t in ctx.plants:
        c = CROPS[t["crop"]]
        age = ctx.day - int(G(t, "planted_day", ctx.day))
        if c["ongoing"]:
            fired = 0 if age < c["first"] else min(c["max_yield"], (age - c["first"]) // c["interval"] + 1)
            s[c["product"]] += (c["max_yield"] - fired) + int(G(t, "yield_units", 0))
        else:
            s[c["product"]] += c["units"] * max(1, (dl - 1) // CYCLE[t["crop"]])
    # animals waiting in shed/inventories
    for a in ANIMALS:
        n = ctx.shed.get(a, 0) + ctx.carried(a)
        if n:
            s[ANIMALS[a]["product"]] += n * (dl - ANIMALS[a]["first"]) * (1.0 + ANIMALS[a]["interval"]) / ANIMALS[a]["interval"]
            s["FERTILIZER"] += n * (dl - 1)
    for p in PRODUCTS:
        s[p] += ctx.shed.get(p, 0) + ctx.carried(p)
    return s


def opponent_supply(ctx):
    s = {p: 0.0 for p in PRODUCTS}
    if ctx.opp is None:
        return s
    dl = ctx.days_left
    for row in G(ctx.opp, "tiles", []):
        for t in row:
            if is_animal(t):
                a = ANIMALS[t["animal"]]
                s[a["product"]] += 1.3 * dl
                s["FERTILIZER"] += dl * 0.8
            elif is_plant(t):
                c = CROPS[t["crop"]]
                s[c["product"]] += c["units"] * (1.0 if not c["ongoing"] else 0.8)
    return s


class Econ:
    """Marginal price estimates for extra production, given projected supply and town demand."""

    def __init__(self, ctx):
        self.ctx = ctx
        self.dl = ctx.days_left
        self.ours = projected_supply(ctx)
        self.opp = opponent_supply(ctx)

    def marginal(self, item, extra_units, lump=False):
        """Marginal average price for `extra_units` more of `item` given all projected supply/demand.

        lump=True: the units are sold in one batch at the end of the supply path (one-time crops),
        so the marginal price is the average over the last `extra_units` of the path.
        lump=False: production is spread over the horizon; use the average over the later half.
        """
        inv_now = self.ctx.inv.get(item, I0)
        town = self.ctx.demand.get(item, 0.0) * self.dl
        supply = self.ours[item] + self.opp[item] + extra_units
        end_inv = inv_now - town + supply
        if lump:
            return avg_price(item, end_inv - max(1.0, extra_units), end_inv)
        mid = inv_now + (end_inv - inv_now) * 0.5
        return avg_price(item, mid, end_inv)

    def wheat_feed_price(self, extra_animals=0):
        """Marginal price paid for feed wheat (buy side, quoted at post-buy inventory)."""
        deficit_now = I0 - self.ctx.inv.get("WHEAT", I0)
        town = self.ctx.demand.get("WHEAT", 0.0) * self.dl
        n_anim = len(self.ctx.animals) + extra_animals + sum(self.ctx.shed.get(a, 0) + self.ctx.carried(a) for a in ANIMALS)
        need = n_anim * (self.dl - 1)
        grown = self.ours["WHEAT"]
        buy = max(0.0, need - grown)
        end_deficit = deficit_now + town + buy - (self.opp["WHEAT"])
        return min(P["feed_price_cap"], avg_price("WHEAT", I0 - deficit_now, I0 - end_deficit))


def discount_rate(ctx):
    used = len(ctx.animals) + len(ctx.plants)
    frac_free = max(0.0, 1.0 - used / 100.0)
    return P["discount_lo"] + (P["discount_hi"] - P["discount_lo"]) * frac_free


def labor_lambda(ctx):
    h = max(0, ctx.unit_count() - 1)
    return max(P["labor_lambda_min"], fib(min(h, 14)) / 23.0)


def option_value(ctx, econ, name, r, lam, feed_price):
    """Discounted net value (today's dollars) of committing one free tile to `name`, and product units."""
    dl = ctx.days_left
    d0 = ctx.day
    if name in ANIMALS:
        a = ANIMALS[name]
        if dl - a["first"] < 2:
            return None
        events = []  # (day_offset, units)
        first_day = a["first"]
        pend = a["first"]  # care banked from placement day through the day before first production
        total = 0.0
        day = first_day
        first = True
        while day <= dl - 1:
            units = min(a["max_held"], 1 + (pend if first else a["interval"]))
            events.append((day, units))
            total += units
            first = False
            day += a["interval"]
        price = econ.marginal(a["product"], total)
        fert_total = dl - 1
        fert_price = econ.marginal("FERTILIZER", fert_total)
        v = -a["cost"]
        for day, units in events:
            v += units * price / (1 + r) ** day
        for day in range(1, dl):
            v += (max(0.0, fert_price - 2.0) - feed_price - lam * 4.3) / (1 + r) ** day
        return v, total
    c = CROPS[name]
    if c["ongoing"]:
        if dl - 1 < c["first"]:
            return None
        events = []
        total = 0.0
        for k in range(c["max_yield"]):
            day = c["first"] + k * c["interval"]
            if day > dl - 1:
                break
            events.append((day, 1.0))
            total += 1.0
        if total <= 0:
            return None
        price = econ.marginal(c["product"], total)
        v = -c["seed"]
        for day, units in events:
            v += units * price / (1 + r) ** day
        occupancy = min(dl - 1, c["first"] + c["interval"] * (c["max_yield"] - 1))
        v -= lam * 2.0 * occupancy
        return v, total
    L = CYCLE[name]
    if dl - 1 < L:
        return None
    cycles = max(1, (dl - 1) // L)
    total = cycles * c["units"]
    price = econ.marginal(c["product"], total)
    if name == "WHEAT" and len(ctx.animals) > 0:
        price = max(price, feed_price)  # grown wheat replaces bought feed
    v = 0.0
    for k in range(cycles):
        v += (c["units"] * price - c["seed"]) / (1 + r) ** ((k + 1) * L)
    v -= lam * 2.0 * cycles * L
    return v, total


def evaluate_options(ctx, econ):
    r = discount_rate(ctx)
    lam = labor_lambda(ctx)
    feed_price = econ.wheat_feed_price()
    vals = {}
    for name in list(ANIMALS) + list(CROPS):
        res = option_value(ctx, econ, name, r, lam, feed_price)
        if res is not None and res[0] > 0:
            vals[name] = res
    return vals


# ----------------------------------------------------------------------------
# Daily planner
# ----------------------------------------------------------------------------

def feed_unit_price(ctx):
    return min(P["feed_price_cap"], market_price("WHEAT", ctx.inv.get("WHEAT", I0) - 1) + 3)


def cash_reserve(ctx, extra_animals=0):
    """Cash to keep untouched: `feed_days` of feed for every animal (incl. pending) + tomorrow's hires."""
    n_anim = len(ctx.animals) + sum(ctx.shed.get(a, 0) + ctx.carried(a) for a in ANIMALS) + extra_animals
    wheat_have = ctx.shed.get("WHEAT", 0) + ctx.carried("WHEAT")
    days = min(P["feed_days"], max(0, ctx.days_left - 1))
    feed = max(0.0, n_anim * days - wheat_have) * feed_unit_price(ctx)
    hires = sum(fib(i) for i in range(min(P["max_hands"], max(0, ctx.unit_count() - 1))))
    return feed + hires * 0.6 + 15


def plan_day(ctx, mem):
    econ = Econ(ctx)
    old_plan = mem.get("plan", {}) or {}
    plan = {}
    # keep still-valid existing plan entries (stability for units already heading there)
    for pos, name in old_plan.items():
        t = ctx.tiles[pos[1]][pos[0]]
        if t is None or is_weed(t) or (is_structure(t) and name in ANIMALS and G(t, "kind") == ANIMALS[name]["structure"]):
            plan[pos] = name
    free = [p for p in ctx.empties if p not in plan]
    free += [p for p in ctx.weeds if p not in plan]
    # empty structures: reuse for matching animal if planned, else they can be dug (handled in tasks)
    free.sort(key=lambda p: dist(p, ctx.nearest_shed_tile(p)))
    # 1) sunk assets: animals in shed/inventories, seeds already bought
    sunk = {}
    for a in ANIMALS:
        n = ctx.shed.get(a, 0) + ctx.carried(a) - sum(1 for v in plan.values() if v == a)
        if n > 0:
            sunk[a] = n
    for crop in CROPS:
        n = ctx.seeds.get(crop, 0) - sum(1 for v in plan.values() if v == crop)
        if n > 0:
            sunk[crop] = n
    # prefer empty structures for sunk animals
    for x, y, t in ctx.structures:
        for a in ANIMALS:
            if sunk.get(a, 0) > 0 and G(t, "kind") == ANIMALS[a]["structure"] and (x, y) not in plan:
                plan[(x, y)] = a
                sunk[a] -= 1
    for name in sorted(sunk, key=lambda k: -(ANIMALS[k]["cost"] if k in ANIMALS else CROPS[k]["seed"])):
        while sunk[name] > 0 and free:
            pos = free.pop(0)
            plan[pos] = name
            sunk[name] -= 1
    # 2) new allocations
    buy = {}
    budget = ctx.money - cash_reserve(ctx)
    # labor budget for today (rough)
    max_actions = (24 + 22 * P["max_hands"] - 3 * (P["max_hands"] + 1)) / P["labor_margin"]
    labor_left = max_actions - estimate_actions(ctx) - sum(4.5 if n in ANIMALS else 2.3 for n in plan.values())
    vals = evaluate_options(ctx, econ) if ctx.days_left >= 3 else {}
    n_new = 0
    hours_ok = ctx.hours_left >= 4 and not ctx.last_day
    while free and vals and hours_ok:
        best = None
        for name, (v, units) in vals.items():
            cost = ANIMALS[name]["cost"] if name in ANIMALS else CROPS[name]["seed"]
            need_labor = 4.5 if name in ANIMALS else 2.3
            if cost > budget or labor_left < need_labor:
                continue
            if name in ANIMALS and ctx.day > P["late_animal_day"]:
                continue
            if best is None or v > best[1]:
                best = (name, v, units, cost)
        if best is None:
            break
        name, v, units, cost = best
        pos = free.pop(0)
        plan[pos] = name
        buy[name] = buy.get(name, 0) + 1
        budget -= cost
        if name in ANIMALS:
            budget -= P["feed_days"] * feed_unit_price(ctx)  # feed safety for the new animal
        labor_left -= 4.5 if name in ANIMALS else 2.3
        n_new += 1
        # update supply and re-evaluate
        prod = ANIMALS[name]["product"] if name in ANIMALS else CROPS[name]["product"]
        econ.ours[prod] += units
        if name in ANIMALS:
            econ.ours["FERTILIZER"] += ctx.days_left - 1
        vals = evaluate_options(ctx, econ)
    # 3) land: if tiles are exhausted, consider buying the next quadrant
    want_land = False
    if not free and len(ctx.unlocked) < 4 and ctx.days_left >= 7 and vals and not ctx.last_day:
        price = LAND_PRICES[len(ctx.unlocked) - 1]
        best_v = max(v for v, u in vals.values())
        # value of 25 more tiles (diminishing) vs price, must be affordable after reserve
        if best_v * 25 * P["land_margin"] > price and budget >= price + 200:
            want_land = True
    mem["plan"] = plan
    mem["buy"] = buy
    mem["vals"] = vals
    gross = {}
    for name in list(ANIMALS) + list(CROPS):
        cost = ANIMALS[name]["cost"] if name in ANIMALS else CROPS[name]["seed"]
        v = vals.get(name, (0.0, 0.0))[0]
        gross[name] = max(v + cost, 4.0 * cost if name in ANIMALS else 6.0 * cost)
    mem["gross"] = gross
    mem["want_land"] = want_land
    mem["r"] = discount_rate(ctx)
    return plan, buy


def estimate_actions(ctx):
    return len(ctx.animals) * 4.5 + len(ctx.plants) * 2.3 + len(ctx.weeds) * 0.3


# ----------------------------------------------------------------------------
# Task generation
# ----------------------------------------------------------------------------

def gen_tasks(ctx, mem, plan):
    tasks = {}
    fert_price = ctx.prices.get("FERTILIZER", 1)
    last_day = ctx.last_day
    use_fert = fert_price <= P["fert_use_price"]

    def add(pos, op, value, needs=None):
        tasks.setdefault(pos, []).append((op, value, needs))

    for x, y, t in ctx.animals:
        a = ANIMALS[t["animal"]]
        price = ctx.prices.get(a["product"], 1)
        fed = bool(G(t, "fed_today", False))
        unfed_run = int(G(t, "consecutive_unfed", 0))
        held = int(G(t, "yield_units", 0))
        pend = int(G(t, "pending_care_bonus", 0))
        age_next = ctx.day + 1 - int(G(t, "placed_day", ctx.day))
        dsf = age_next - a["first"]
        produces_tonight = dsf >= 0 and dsf % a["interval"] == 0
        if not fed and not last_day:
            v = 100000.0 if unfed_run >= 1 else (2000.0 + price * 2.0)
            add((x, y), ["FEED"], v, "WHEAT")
        if not G(t, "cared_today", False) and not last_day and ctx.days_left > 2:
            add((x, y), ["CARE"], price * (1.0 if fed else 0.9))
        if G(t, "fertilizer_available", False):
            add((x, y), ["COLLECT_FERTILIZER"], max(1.0, fert_price - 2 if not use_fert else 30.0))
        if held > 0:
            nxt = (1 + pend) if produces_tonight else 0
            overflow = held + nxt - a["max_held"]
            if last_day or overflow > 0 or ctx.steps_left < 40:
                v = held * price + max(0, overflow) * price
            else:
                v = held * price * 0.2
            add((x, y), ["HARVEST"], v)

    for x, y, t in ctx.plants:
        c = CROPS[t["crop"]]
        price = ctx.prices.get(c["product"], 1)
        age = ctx.day - int(G(t, "planted_day", ctx.day))
        watered = bool(G(t, "watered_today", False))
        unw = int(G(t, "consecutive_unwatered", 0))
        held = int(G(t, "yield_units", 0))
        mls = int(G(t, "max_lifespan_step", -1))
        fert_until = int(G(t, "fertilized_until_day", -1))
        if not watered and not last_day:
            if c["ongoing"]:
                v = (50000.0 if unw >= 1 else 600.0 + price * 0.6)
            else:
                win_start = (c["maxday"] + 1) // 2
                in_window = win_start <= age <= c["maxday"]
                v = (50000.0 if unw >= 1 else 600.0 + price * 0.6) + (price * (2 if fert_until >= ctx.day else 1) if in_window else 0)
            add((x, y), ["WATER"], v)
        if held > 0 and age >= c["first"]:
            if c["ongoing"]:
                done = mls >= 0
                v = held * price * (1.0 if (held >= 2 or done or last_day) else 0.3)
                add((x, y), ["HARVEST"], v)
            else:
                decaying = mls >= 0 and ctx.step >= mls
                maxed = held >= c["units"] or age >= c["maxday"]
                if decaying or last_day:
                    add((x, y), ["HARVEST"], held * price * 2)
                elif maxed and (watered or age > c["maxday"]):
                    add((x, y), ["HARVEST"], held * price)
        # fertilize when fertilizer is cheap
        if use_fert and fert_until < ctx.day and not last_day:
            if c["ongoing"]:
                if c["first"] - 1 <= age <= c["first"] + c["interval"] * (c["max_yield"] - 1) - 1:
                    add((x, y), ["FERTILIZE"], price * 1.5, "FERT")
            else:
                win_start = (c["maxday"] + 1) // 2
                if age == win_start and t["crop"] != "MELON" and held < c["max_yield"]:
                    add((x, y), ["FERTILIZE"], price * (2 if t["crop"] == "WHEAT" else 1), "FERT")

    for x, y in ctx.weeds:
        if (x, y) not in plan:
            add((x, y), ["DIG"], 12.0 if ctx.days_left > 4 else 0.0)

    gross = mem.get("gross", {}) or {}
    for pos, name in plan.items():
        x, y = pos
        t = ctx.tiles[y][x]
        gv = gross.get(name, 400.0)
        if name in ANIMALS:
            a = ANIMALS[name]
            if t is None:
                add(pos, ["BUILD_COOP" if a["structure"] == "COOP" else "BUILD_PASTURE"], gv, name)
            elif is_structure(t) and G(t, "kind") == a["structure"]:
                add(pos, ["PLACE", name], gv * 1.2, name)
            elif is_structure(t):
                add(pos, ["DIG"], gv * 0.5)
            elif is_weed(t):
                add(pos, ["DIG"], gv * 0.6)
        else:
            if t is None:
                add(pos, ["PLANT", name], gv, "seed:" + name)
            elif is_structure(t) or is_weed(t):
                add(pos, ["DIG"], gv * 0.5)
    return tasks


# ----------------------------------------------------------------------------
# Unit scheduling
# ----------------------------------------------------------------------------

def unit_can(inv, needs, ctx):
    if needs is None:
        return True
    if needs == "WHEAT":
        return inv.get("WHEAT", 0) > 0
    if needs == "FERT":
        return inv.get("FERTILIZER", 0) > 0
    if needs in ANIMALS:
        return inv.get(needs, 0) > 0
    if needs.startswith("seed:"):
        return ctx.seeds.get(needs[5:], 0) > 0
    return False


def move_toward(pos, target):
    dx = target[0] - pos[0]
    dy = target[1] - pos[1]
    if abs(dx) >= abs(dy) and dx != 0:
        return ["EAST"] if dx > 0 else ["WEST"]
    if dy != 0:
        return ["SOUTH"] if dy > 0 else ["NORTH"]
    if dx != 0:
        return ["EAST"] if dx > 0 else ["WEST"]
    return ["PASS"]


def products_carried(inv):
    return sum(v for k, v in inv.items() if k in PRODUCTS and k != "WHEAT")


def serpentine_order(ctx):
    """Tiles of unlocked quadrants in a boustrophedon path starting next to the shed."""
    h = ctx.half
    order = []
    quads = {
        "NW": (range(h - 1, -1, -1), range(h - 1, -1, -1)),
        "NE": (range(h, 2 * h), range(h - 1, -1, -1)),
        "SW": (range(h - 1, -1, -1), range(h, 2 * h)),
        "SE": (range(h, 2 * h), range(h, 2 * h)),
    }
    for q in ("NW", "NE", "SW", "SE"):
        if q not in ctx.unlocked:
            continue
        xs, ys = quads[q]
        xs = list(xs)
        for i, y in enumerate(ys):
            row = xs if i % 2 == 0 else xs[::-1]
            for x in row:
                order.append((x, y))
    return order


def tile_load(ctx, pos, plan):
    t = ctx.tiles[pos[1]][pos[0]]
    if is_animal(t):
        return 4.5
    if is_plant(t):
        return 2.3
    if pos in plan:
        return 3.0
    if is_weed(t):
        return 0.5
    return 0.0


def assign_zones(ctx, mem, plan):
    """Split the serpentine path into contiguous strips of ~equal load, one per unit."""
    n_units = ctx.unit_count()
    order = serpentine_order(ctx)
    loads = [tile_load(ctx, p, plan) for p in order]
    total = sum(loads)
    zones = {}
    if total <= 0:
        mem["zones"] = zones
        return zones
    # farmer has 24 actions, hands ~22 effective; weight shares accordingly
    weights = [1.0] + [0.95] * (n_units - 1)
    wsum = sum(weights)
    target = [total * w / wsum for w in weights]
    u, acc = 0, 0.0
    for p, l in zip(order, loads):
        if l <= 0:
            continue
        zones[p] = u
        acc += l
        if acc >= target[u] and u < n_units - 1:
            u += 1
            acc = 0.0
    mem["zones"] = zones
    return zones


def schedule_units(ctx, mem, tasks):
    n_units = ctx.unit_count()
    ops = [["PASS"] for _ in range(n_units)]
    targets = mem.setdefault("targets", {})
    if mem.get("targets_day") != ctx.day:
        targets.clear()
        mem["targets_day"] = ctx.day
    # persistent reservations: a unit keeps its target while the tile still has tasks
    reserved = {}
    for u in range(n_units):
        tp = targets.get(u)
        if tp is not None and tp in tasks and any(v > 0 for op, v, needs in tasks[tp]):
            reserved[tp] = u
        elif tp is not None:
            targets.pop(u, None)
    unfed = sum(1 for x, y, t in ctx.animals if not G(t, "fed_today", False))
    shed_wheat = ctx.shed.get("WHEAT", 0)
    carried_wheat = ctx.carried("WHEAT")
    animals_in_shed = {a: ctx.shed.get(a, 0) for a in ANIMALS}
    carried_animals = {a: ctx.carried(a) for a in ANIMALS}
    animal_tiles_needed = {a: 0 for a in ANIMALS}
    fert_needed = 0
    for pos, lst in tasks.items():
        for op, v, needs in lst:
            if needs in ANIMALS:
                animal_tiles_needed[needs] += 1
            elif needs == "FERT":
                fert_needed += 1
    fert_in_shed = ctx.shed.get("FERTILIZER", 0)
    hours_left = ctx.hours_left
    last_day = ctx.last_day
    any_tasks = any(any(v > 0 for op, v, needs in lst) for lst in tasks.values())

    zones = mem.get("zones") or {}
    if mem.get("zones_key") != (ctx.day, n_units):
        zones = assign_zones(ctx, mem, mem.get("plan", {}) or {})
        mem["zones_key"] = (ctx.day, n_units)
    for u in range(n_units):
        pos = ctx.positions[u]
        inv = ctx.invs[u]
        at_shed = pos in ctx.shed_access
        n_prod = products_carried(inv)
        shed_tile = ctx.nearest_shed_tile(pos)
        d_shed = dist(pos, shed_tile)
        shed_room = SHED_CAP - ctx.shed_total
        total_carried = sum(products_carried(i) for i in ctx.invs)
        must_return = n_prod > 0 and hours_left <= d_shed + 1 and (last_day or total_carried > shed_room - 5)
        if at_shed:
            end_drop = n_prod > 0 and hours_left <= 2 and (last_day or total_carried > shed_room - 5)
            if n_prod > 0 and (n_prod >= P["drop_threshold"] or end_drop or not any_tasks):
                ops[u] = ["DROP"]
                continue
            if not last_day and inv.get("WHEAT", 0) == 0 and unfed > carried_wheat and shed_wheat > 0:
                share = int(math.ceil((unfed - carried_wheat) * 1.3 / max(1, n_units))) + 2
                share = max(1, min(shed_wheat, share, 14))
                ops[u] = ["PICKUP", "WHEAT", share]
                shed_wheat -= share
                carried_wheat += share
                continue
            picked = False
            for a in ANIMALS:
                need_tiles = animal_tiles_needed[a] - carried_animals[a]
                if animals_in_shed[a] > 0 and need_tiles > 0 and inv.get(a, 0) == 0 and hours_left >= 5:
                    k = min(animals_in_shed[a], need_tiles, 6, max(1, (hours_left - 3) // 4))
                    ops[u] = ["PICKUP", a, k]
                    animals_in_shed[a] -= k
                    carried_animals[a] += k
                    picked = True
                    break
            if picked:
                continue
            if fert_in_shed > 0 and fert_needed > 0 and inv.get("FERTILIZER", 0) == 0 and hours_left >= 4:
                k = min(fert_in_shed, fert_needed, 6)
                ops[u] = ["PICKUP", "FERTILIZER", k]
                fert_in_shed -= k
                fert_needed -= k
                continue
        elif must_return or (n_prod >= P["drop_threshold"] * 2 and total_carried > shed_room - 20):
            ops[u] = move_toward(pos, shed_tile)
            continue
        # act here if possible
        here = tasks.get(pos, [])
        doable = [(op, v, needs) for op, v, needs in here if v > 0 and unit_can(inv, needs, ctx)]
        if doable:
            op, v, needs = max(doable, key=lambda z: z[1])
            ops[u] = list(op)
            here.remove((op, v, needs))
            if needs == "WHEAT":
                inv["WHEAT"] = inv.get("WHEAT", 0) - 1
                unfed -= 1
                carried_wheat -= 1
            elif needs in ANIMALS and op[0] == "PLACE":
                inv[needs] = inv.get(needs, 0) - 1
                carried_animals[needs] -= 1
                animal_tiles_needed[needs] -= 1
            elif needs and needs.startswith("seed:"):
                ctx.seeds[needs[5:]] = ctx.seeds.get(needs[5:], 0) - 1
            elif needs == "FERT":
                inv["FERTILIZER"] = inv.get("FERTILIZER", 0) - 1
                fert_needed -= 1
            reserved[pos] = u
            targets[u] = pos
            continue
        # choose a target tile
        best, best_score = None, 0.0
        for tpos, lst in tasks.items():
            if tpos in reserved and reserved[tpos] != u:
                continue
            val = 0.0
            for op, v, needs in lst:
                if v > 0 and unit_can(inv, needs, ctx):
                    val += v
            if val <= 0:
                continue
            d = dist(pos, tpos)
            if d + 1 > hours_left:
                continue
            score = val / (d + 1.0) ** 1.3
            z = zones.get(tpos)
            if z is not None and z != u and val < 20000:
                score *= 0.25   # someone else's zone: only help if clearly better
            if tpos == targets.get(u):
                score *= 1.25
            if score > best_score:
                best, best_score = tpos, score
        if best is not None:
            reserved[best] = u
            targets[u] = best
            ops[u] = move_toward(pos, best)
            continue
        # nothing doable: fetch wheat if animals are unfed and shed has wheat; else drop products
        if not at_shed and (n_prod > 0 or (unfed > carried_wheat and shed_wheat > 0 and inv.get("WHEAT", 0) == 0)):
            ops[u] = move_toward(pos, shed_tile)
            continue
        ops[u] = ["PASS"]
    return ops


# ----------------------------------------------------------------------------
# Market
# ----------------------------------------------------------------------------

def desired_hands(ctx, mem):
    plan = mem.get("plan", {}) or {}
    sunk_anim = sum(ctx.shed.get(a, 0) + ctx.carried(a) for a in ANIMALS)
    sunk_seed = sum(ctx.seeds.values())
    buy = mem.get("buy", {}) or {}
    cash = max(0.0, ctx.money - cash_reserve(ctx))
    buyable = 0
    for name, n in buy.items():
        cost = ANIMALS[name]["cost"] if name in ANIMALS else CROPS[name]["seed"]
        k = min(n, int(cash // cost))
        buyable += k
        cash -= k * cost
    placements = min(len(plan), sunk_anim + sunk_seed + buyable)
    # per-tile load already includes one move per tile; add per-unit overhead (pickups, trips)
    actions = len(ctx.animals) * 4.5 + len(ctx.plants) * 2.3 + placements * 3.0 + len(ctx.weeds) * 0.3
    if ctx.last_day:
        actions = len(ctx.animals) * 1.5 + len(ctx.plants) * 1.2 + 4
    need = 0
    while need < P["max_hands"]:
        capacity = 24 + 22 * need - 3 * (need + 1)
        if capacity >= actions * P["labor_margin"]:
            break
        need += 1
    cash = ctx.money - cash_reserve(ctx) * 0.5
    h = 0
    while h < min(need, P["max_hands"]):
        c = fib(h)
        if c > P["hire_cap_cost"] or cash < c:
            break
        cash -= c
        h += 1
    return h


def sell_orders(ctx, mem):
    orders = []
    dl = ctx.days_left
    n_anim = len(ctx.animals) + sum(ctx.shed.get(a, 0) + ctx.carried(a) for a in ANIMALS)
    endgame = ctx.steps_left <= 0
    # emergency: if cash cannot cover feed for the unfed animals, sell anything
    unfed = sum(1 for x, y, t in ctx.animals if not G(t, "fed_today", False))
    wheat_have = ctx.shed.get("WHEAT", 0) + ctx.carried("WHEAT")
    feed_gap = max(0, unfed - wheat_have) * feed_unit_price(ctx) - ctx.money
    emergency = feed_gap > 0 and not ctx.last_day
    held_value = []
    for item in PRODUCTS:
        q = ctx.shed.get(item, 0)
        if q <= 0:
            continue
        inv = ctx.inv.get(item, I0)
        if item == "WHEAT":
            reserve = 0 if (endgame or dl <= 1) else min(q, n_anim + 2)
            if emergency:
                reserve = min(reserve, unfed)
            if q - reserve > 0:
                orders.append(["SELL", "WHEAT", q - reserve])
            continue
        if item == "EGG" or endgame or emergency:
            orders.append(["SELL", item, q])
            continue
        base = MARKET_PARAMS[item]["base"]
        frac = P["fert_reserve_frac"] if item == "FERTILIZER" else P["reserve_frac"]
        if dl <= 3:
            frac *= max(0.0, (dl - 1)) / 3.0
        if ctx.shed_total >= 80:
            frac *= 0.4
        reserve = max(1.0, base * frac)
        # units the town will still absorb before the end (price recovery capacity)
        absorb = int(ctx.demand.get(item, 0.0) * max(0, dl - 1) * 0.8)
        must_sell = max(0, q - absorb)
        k = must_sell
        while k < q and market_price(item, inv + k) >= reserve:
            k += 1
        if k > 0:
            orders.append(["SELL", item, k])
    orders.sort(key=lambda o: {"EGG": 0, "WHEAT": 1, "FERTILIZER": 3}.get(o[1], 2))
    return orders


def market_orders(ctx, mem, buy_plan):
    orders = []
    cash = ctx.money
    dl = ctx.days_left
    # opening override (experiments)
    if ctx.step == 0 and P.get("opening", "auto") != "auto":
        for part in P["opening"].split(","):
            name, n = part.split(":")
            n = int(n)
            if name in ANIMALS:
                orders.append(["BUY_ANIMAL", name, n]); cash -= n * ANIMALS[name]["cost"]
            else:
                orders.append(["BUY_SEED", name, n]); cash -= n * CROPS[name]["seed"]
            buy_plan = {}
    # hires
    if ctx.hour in (0, 1) and not (ctx.last_day and ctx.hour == 1):
        want = desired_hands(ctx, mem)
        n_new = max(0, want - ctx.hires_today)
        for i in range(n_new):
            c = fib(ctx.hires_today + i)
            if c > P["hire_cap_cost"] or cash < c + 20:
                break
            orders.append(["HIRE"])
            cash -= c
            if len(orders) >= 7:
                break
    # land
    if mem.get("want_land") and len(ctx.unlocked) < 4 and ctx.hours_left >= 4:
        price = LAND_PRICES[len(ctx.unlocked) - 1]
        if cash - price >= cash_reserve(ctx):
            orders.append(["BUY_LAND"])
            cash -= price
            mem["want_land"] = False
            mem["plan_key"] = None  # force replan next turn
    # purchases for the plan (animals first, then seeds)
    shed_room = SHED_CAP - ctx.shed_total
    if ctx.hours_left >= 5 and dl >= 2:
        reserve = cash_reserve(ctx)
        for name, n in sorted(buy_plan.items(), key=lambda kv: -(ANIMALS[kv[0]]["cost"] if kv[0] in ANIMALS else CROPS[kv[0]]["seed"])):
            if name in ANIMALS:
                have = ctx.shed.get(name, 0) + ctx.carried(name)
                planned = sum(1 for v in (mem.get("plan") or {}).values() if v == name)
                need = planned - have
                cost = ANIMALS[name]["cost"] + P["feed_days"] * feed_unit_price(ctx)
                k = min(need, int((cash - reserve) // cost), shed_room)
                if k > 0:
                    orders.append(["BUY_ANIMAL", name, k])
                    cash -= k * cost
                    shed_room -= k
            else:
                planned = sum(1 for v in (mem.get("plan") or {}).values() if v == name)
                need = planned - ctx.seeds.get(name, 0)
                cost = CROPS[name]["seed"]
                k = min(need, int((cash - reserve) // cost))
                if k > 0:
                    orders.append(["BUY_SEED", name, k])
                    cash -= k * cost
    # feed wheat, just in time
    if not ctx.last_day and ctx.hour <= 21:
        unfed = sum(1 for x, y, t in ctx.animals if not G(t, "fed_today", False))
        pending_animals = sum(ctx.shed.get(a, 0) + ctx.carried(a) for a in ANIMALS) + sum(n for o in orders if o[0] == "BUY_ANIMAL" for n in [o[2]])
        have = ctx.shed.get("WHEAT", 0) + ctx.carried("WHEAT")
        target = unfed + (pending_animals if ctx.hour < 14 else 0) + (2 if ctx.hour < 4 and unfed > 0 else 0)
        need = target - have
        if need > 0:
            unit_price = market_price("WHEAT", ctx.inv.get("WHEAT", I0) - 1)
            if unit_price <= P["feed_price_cap"] or unfed > 0:
                k = min(need, max(0, int((cash - 5) // max(1, unit_price))), max(0, shed_room))
                if k > 0:
                    orders.append(["BUY_PRODUCT", "WHEAT", k])
                    cash -= k * unit_price
    sells = sell_orders(ctx, mem)
    hires = [o for o in orders if o[0] == "HIRE"][:5]
    feed = [o for o in orders if o[0] == "BUY_PRODUCT"]
    buys = [o for o in orders if o[0] in ("BUY_LAND", "BUY_ANIMAL", "BUY_SEED")]
    final = hires + feed + sells[:4] + buys + sells[4:]
    return final[:10]


# ----------------------------------------------------------------------------
# Agent
# ----------------------------------------------------------------------------

def agent(obs, config=None):
    ctx = Ctx(obs)
    mem = MEM.setdefault(ctx.player, {})
    key = (ctx.day, ctx.hour // P["replan_hours"], len(ctx.unlocked))
    if mem.get("plan_key") != key:
        plan_day(ctx, mem)
        mem["plan_key"] = key
    plan = mem.get("plan", {}) or {}
    buy = mem.get("buy", {}) or {}
    # prune plan entries whose tiles are no longer usable
    plan = {pos: name for pos, name in plan.items()
            if (ctx.tiles[pos[1]][pos[0]] is None or is_weed(ctx.tiles[pos[1]][pos[0]]) or is_structure(ctx.tiles[pos[1]][pos[0]]))}
    mem["plan"] = plan
    if ctx.last_day:
        plan, buy = {}, {}
    tasks = gen_tasks(ctx, mem, plan)
    ops = schedule_units(ctx, mem, tasks)
    orders = market_orders(ctx, mem, buy)
    return {"farmer": ops[0], "hands": ops[1:], "market": orders}
