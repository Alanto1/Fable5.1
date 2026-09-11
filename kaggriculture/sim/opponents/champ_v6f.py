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
    "discount_hi": 0.10,      # daily discount rate when capital-constrained (early)
    "discount_lo": 0.02,
    "land_margin": 0.6,       # buy land when 25 * best tile value * margin > price
    "fert_use_price": 40,     # apply fertilizer to crops when its sale price is below this
    "labor_lambda_min": 2.0,
    "feed_price_cap": 60,     # never pay more than this per feed wheat
    "opening": "auto",        # or e.g. "GOOSE:9" / "MELON:12,GOOSE:6" forced day-0 buys
    "replan_hours": 3,
    "placement_labor": 0.0,   # one-off actions to build/place/plant a new tile (today); >0 hurt in tests
    "max_unplaced_animals": 4,
    "placement_priority": False,
    "recipe": True,               # recipe-driven planner (top-bot composition) instead of pure value planner
    "melon_tiles": 10,            # day-0/1 melon tiles
    "max_cows": 12,
    "max_sheep": 18,
    "cow_last_day": 16,
    "sheep_last_day": 19,
    "straw_last_day": 15,
    "tomato_last_day": 18,
    "straw_base": 10,             # strawberry tiles = straw_base + straw_k * expected demand
    "straw_k": 0.9,
    "straw_cap": 44,
    "cow_k": 2.5,                 # cows = cow_base + expected milk demand / cow_k
    "cow_base": 3,
    "cow_min": 2,
    "sheep_min": 2,
    "size_k": 0.85,               # fraction of demand to supply
    "fair_share": 0.5,            # floor (fraction of full-demand target) when the opponent already saturates a pool
    "straw_mult": 1.5,
    "feed_tiles_per_animal": 1.0,
    "wheat_buffer": 1,
    "harvest_hour": 10,
    "zone_hour": 2,               # zones are assigned once all hands of the day exist           # ongoing-crop harvests get full priority from this hour
    "carrot_min_dem": 10,
    "egg_min_dem": 8,
    "max_geese": 14,
    "goose_last_day": 20,
    "opp_weight": 0.8,            # how much of the opponent's visible production to subtract from demand
    "sheep_k": 4.5,
    "tomato_min_dem": 18,
    "future_shop_weight": 0.6,    # weight of not-yet-unlocked shops in expected demand
    "hands_schedule": [4, 4, 4, 5, 5, 5, 8, 8, 8, 11, 11, 12],
    "buy_se": False,              # never buy the $4000 quadrant
    "land_ne_day": 4,
    "land_sw_day": 7,
    "guard_price": {"MILK": 70, "WOOL": 70, "STRAWBERRY": 60, "TOMATO": 40, "MELON": 60, "CARROT": 30, "EGG": 42},
    "fert_cheap": 30,
    "fill_min_value": 4.0,
    "wheat_floor": 0,
    "fill_crops": ["WHEAT"],        # min value per tile-day for filler crops (below: leave tile empty)             # fertilize wheat/carrot only below this fertilizer price
    "rush_hours": 6,          # value-first targeting when this few hours remain in the day
    "sweep_dist_pow": 2.0,    # distance exponent for nearest-first sweeping
    "feed_days": 2,
    "cull_per_replan": 3,
    "task_price_mode": "marginal",   # or "spot"
    "cull_margin": 0.0,       # stop feeding an animal whose daily value < feed price * margin (0 = never cull)
    "labor_margin": 1.12,
    "hand_capacity": 20,      # useful actions per hired hand per day
    "farmer_capacity": 22,
    "load_animal": 4.3,
    "load_plant": 2.2,
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
DEBUG = bool(os.environ.get("KAGG_DEBUG"))


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
    for crop, n in ctx.seeds.items():
        if n > 0 and crop in CROPS:
            s[CROPS[crop]["product"]] += n * CROPS[crop]["units"]
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
        if P.get("recipe"):
            exp = expected_demand(ctx)
            self.dem = {p: max(ctx.demand.get(p, 0.0), exp.get(p, 0.0) + 1.0) for p in PRODUCTS}
            self.dem["FERTILIZER"] = 0.0
        else:
            self.dem = dict(ctx.demand)

    def marginal(self, item, extra_units, lump=False):
        """Marginal average price for `extra_units` more of `item` given all projected supply/demand.

        lump=True: the units are sold in one batch at the end of the supply path (one-time crops),
        so the marginal price is the average over the last `extra_units` of the path.
        lump=False: production is spread over the horizon; use the average over the later half.
        """
        inv_now = self.ctx.inv.get(item, I0)
        town = self.dem.get(item, 0.0) * self.dl
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
    """Daily discount rate: high when cash is the bottleneck (early), low when cash is plentiful."""
    scarcity = max(0.0, min(1.0, 1.0 - ctx.money / 4000.0))
    return P["discount_lo"] + (P["discount_hi"] - P["discount_lo"]) * scarcity


def labor_lambda(ctx, hands=None):
    """Marginal price of one unit-action given `hands` hired (cost of the next hand / its capacity)."""
    h = max(0, ctx.unit_count() - 1) if hands is None else hands
    return max(P["labor_lambda_min"], fib(min(h, 25)) / P["hand_capacity"])


def labor_capacity(hands):
    return P["farmer_capacity"] + P["hand_capacity"] * hands


def hands_for_load(load):
    h = 0
    while h < P["max_hands"] and labor_capacity(h) < load * P["labor_margin"]:
        if fib(h) > P["hire_cap_cost"]:
            break
        h += 1
    return h


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
            v += (max(0.0, fert_price - 2.0) - feed_price - lam * P["load_animal"]) / (1 + r) ** day
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
        for day in range(occupancy):
            v -= lam * P["load_plant"] / (1 + r) ** day
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
    for day in range(cycles * L):
        v -= lam * P["load_plant"] / (1 + r) ** day
    return v, total


def evaluate_options(ctx, econ, hands=None):
    r = discount_rate(ctx)
    lam = labor_lambda(ctx, hands)
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


def plan_day_value(ctx, mem):
    econ = Econ(ctx)
    old_plan = mem.get("plan", {}) or {}
    plan = {}
    # keep old entries only while they are funded (seed/animal already in stock); others are re-planned
    funded = {a: ctx.shed.get(a, 0) + ctx.carried(a) for a in ANIMALS}
    funded.update({c: ctx.seeds.get(c, 0) for c in CROPS})
    for pos, name in sorted(old_plan.items(), key=lambda kv: dist(kv[0], ctx.nearest_shed_tile(kv[0]))):
        t = ctx.tiles[pos[1]][pos[0]]
        ok_tile = t is None or is_weed(t) or (is_structure(t) and name in ANIMALS and G(t, "kind") == ANIMALS[name]["structure"])
        if ok_tile and funded.get(name, 0) > 0:
            plan[pos] = name
            funded[name] -= 1
    free = [p for p in ctx.empties if p not in plan]
    free += [p for p in ctx.weeds if p not in plan]
    free += [(x, y) for x, y, t in ctx.structures if (x, y) not in plan]
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
    # 2) new allocations; the hand count H grows while the marginal hand pays for itself
    buy = {}
    budget = ctx.money - cash_reserve(ctx)
    load = estimate_actions(ctx) + sum(P["load_animal"] if n in ANIMALS else P["load_plant"] for n in plan.values())
    H = hands_for_load(load)
    labor_left = labor_capacity(H) / P["labor_margin"] - load
    vals = evaluate_options(ctx, econ, H) if ctx.days_left >= 3 else {}
    n_new = 0
    hours_ok = ctx.hours_left >= 4 and not ctx.last_day
    while free and vals and hours_ok:
        best = None
        for name, (v, units) in vals.items():
            cost = ANIMALS[name]["cost"] if name in ANIMALS else CROPS[name]["seed"]
            if cost > budget:
                continue
            if name in ANIMALS and ctx.day > P["late_animal_day"]:
                continue
            if best is None or v > best[1]:
                best = (name, v, units, cost)
        if best is None:
            break
        name, v, units, cost = best
        need_labor = P["load_animal"] if name in ANIMALS else P["load_plant"]
        if labor_left < need_labor:
            # hire one more hand if allowed and re-price labor; stop if nothing stays profitable
            if H >= P["max_hands"] or fib(H) > P["hire_cap_cost"] or budget < fib(H) * 2:
                break
            H += 1
            labor_left += P["hand_capacity"] / P["labor_margin"]
            vals = evaluate_options(ctx, econ, H)
            if not vals:
                H -= 1
                labor_left -= P["hand_capacity"] / P["labor_margin"]
                break
            continue
        pos = free.pop(0)
        plan[pos] = name
        buy[name] = buy.get(name, 0) + 1
        budget -= cost
        if name in ANIMALS:
            budget -= P["feed_days"] * feed_unit_price(ctx)  # feed safety for the new animal
        labor_left -= need_labor + P["placement_labor"]
        n_new += 1
        prod = ANIMALS[name]["product"] if name in ANIMALS else CROPS[name]["product"]
        econ.ours[prod] += units
        if name in ANIMALS:
            econ.ours["FERTILIZER"] += ctx.days_left - 1
        vals = evaluate_options(ctx, econ, H)
    mem["H"] = H
    # 3) land: when funded tiles are exhausted and cash remains, consider the next quadrant
    want_land = False
    if len(ctx.unlocked) < 4 and ctx.days_left >= 7 and vals and not ctx.last_day:
        price = LAND_PRICES[len(ctx.unlocked) - 1]
        best_name, (best_v, _u) = max(vals.items(), key=lambda kv: kv[1][0])
        best_cost = ANIMALS[best_name]["cost"] if best_name in ANIMALS else CROPS[best_name]["seed"]
        # tiles still free after allocation (money or labor ran out) mean land is not the bottleneck
        if not free and best_v * 25 * P["land_margin"] > price and budget >= price + 3 * best_cost:
            want_land = True
    if DEBUG:
        stop = "free" if not free else ("hours" if not hours_ok else ("vals" if not vals else "budget/labor"))
        print(f"[plan] d{ctx.day}h{ctx.hour} money={ctx.money:.0f} budget={budget:.0f} H={H} labor_left={labor_left:.0f} "
              f"free={len(free)} new={n_new} stop={stop} land={want_land} r={discount_rate(ctx):.2f} "
              f"vals={ {k: round(v[0]) for k, v in vals.items()} } buy={buy}")
    mem["plan"] = plan
    mem["buy"] = buy
    mem["vals"] = vals
    # marginal prices of each product given projected supply (for task priorities)
    econ2 = Econ(ctx)
    mprice = {}
    for p in PRODUCTS:
        mprice[p] = max(1.0, min(ctx.prices.get(p, 1), econ2.marginal(p, 5.0)))
    mem["mprice"] = mprice
    feed_price = feed_unit_price(ctx)
    mem["feed_price"] = feed_price
    # culling: stop feeding animals whose marginal production no longer covers feed, one at a time
    cull = set()
    if ctx.days_left > 3:
        dl = ctx.days_left
        for _ in range(P["cull_per_replan"]):
            worst = None
            for x, y, t in ctx.animals:
                if (x, y) in cull:
                    continue
                a = ANIMALS[t["animal"]]
                per_day = (1.0 + a["interval"]) / a["interval"]
                units = per_day * (dl - 1)
                mp = econ2.marginal(a["product"], units)
                fm = max(0.0, econ2.marginal("FERTILIZER", dl - 1) - 2.0)
                daily = mp * per_day + fm
                if daily < feed_price * P["cull_margin"] and (worst is None or daily < worst[0]):
                    worst = (daily, (x, y), a["product"], units)
            if worst is None:
                break
            cull.add(worst[1])
            econ2.ours[worst[2]] -= worst[3]
            econ2.ours["FERTILIZER"] -= dl - 1
    mem["cull"] = cull
    gross = {}
    for name in list(ANIMALS) + list(CROPS):
        cost = ANIMALS[name]["cost"] if name in ANIMALS else CROPS[name]["seed"]
        v = vals.get(name, (0.0, 0.0))[0]
        gross[name] = max(v + cost, 4.0 * cost if name in ANIMALS else 6.0 * cost)
    mem["gross"] = gross
    mem["want_land"] = want_land
    mem["r"] = discount_rate(ctx)
    return plan, buy

# Expected daily demand added by one future (unknown) shop unlock, per product.
_SHOP_UNIT = {}
for _s, _prods in SHOPS.items():
    for _p in _prods:
        _SHOP_UNIT[_p] = _SHOP_UNIT.get(_p, 0.0) + (12.0 if len(_prods) == 1 else 6.0) / len(SHOPS)


def expected_demand(ctx):
    """Current town demand plus a discounted expectation for shops not yet unlocked."""
    unlocks_left = sum(1 for u in (3, 6, 9, 12, 15, 18, 21, 24) if u > ctx.day) if len(ctx.shops) < 8 else 0
    unlocks_left = min(unlocks_left, 8 - len(ctx.shops))
    exp = {}
    for p in PRODUCTS:
        exp[p] = ctx.demand.get(p, 0.0) - 1.0 + unlocks_left * _SHOP_UNIT.get(p, 0.0) * P["future_shop_weight"]
    return exp


def opponent_rates(ctx):
    """Opponent's visible production rate per product (units/day)."""
    r = {p: 0.0 for p in PRODUCTS}
    if ctx.opp is None:
        return r
    for row in G(ctx.opp, "tiles", []):
        for t in row:
            if is_animal(t):
                a = ANIMALS[t["animal"]]
                r[a["product"]] += (1.0 + a["interval"]) / a["interval"]
            elif is_plant(t):
                c = CROPS[t["crop"]]
                if c["ongoing"]:
                    r[c["product"]] += (2.0 if t["crop"] == "STRAWBERRY" else 1.0) * c["max_yield"] / (c["first"] + c["interval"] * (c["max_yield"] - 1) + 1)
                else:
                    r[c["product"]] += c["units"] / CYCLE[t["crop"]]
    return r


def recipe_targets(ctx, counts):
    """Target tile counts per kind: each product sized to demand, with a fair-share floor so the
    agent never yields a pool to the opponent, and a residual cap so it does not flood one the
    opponent already saturates."""
    d = ctx.day
    full = expected_demand(ctx)          # demand ignoring the opponent
    opp = opponent_rates(ctx)
    k = P["size_k"]
    fs = P["fair_share"]

    def size(product, per_tile, mult=1.0):
        f = full[product] / per_tile * k * mult            # my target if I supplied the whole demand
        opp_tiles = opp.get(product, 0.0) / per_tile
        excess = max(0.0, opp_tiles - f)                     # opponent already beyond the demand alone
        return int(round(max(fs * f, f - P["opp_weight"] * excess)))

    T = {}
    cow_cap = max(P["cow_min"], min(P["max_cows"], size("MILK", 1.5)))
    T["COW"] = min(cow_cap, 2 + d) if d <= P["cow_last_day"] else 0
    sheep_cap = max(P["sheep_min"], min(P["max_sheep"], size("WOOL", 1.33)))
    T["SHEEP"] = min(sheep_cap, 2 + d // 2) if d <= P["sheep_last_day"] else 0
    # strawberries: ~8 units per tile concentrated over ~12 days -> tiles ~ 1.5 x daily demand
    T["STRAWBERRY"] = max(8, min(P["straw_cap"], size("STRAWBERRY", 1.0, P["straw_mult"]))) if d <= P["straw_last_day"] else 0
    T["TOMATO"] = size("TOMATO", 0.6) if (full["TOMATO"] >= P["tomato_min_dem"] and d <= P["tomato_last_day"]) else 0
    T["CARROT"] = size("CARROT", 1.0) if (full["CARROT"] >= P["carrot_min_dem"] and d <= 26) else 0
    T["GOOSE"] = min(P["max_geese"], size("EGG", 2.0)) if (full["EGG"] >= P["egg_min_dem"] and d <= P["goose_last_day"]) else 0
    T["MELON"] = P["melon_tiles"] if d <= 1 else 0
    T["WHEAT"] = 999  # fill
    if ctx.days_left <= 6:
        T["CARROT"] = 999 if ctx.days_left >= 4 else 0
    return T, full


def fill_value(ctx, econ, name, feed_price):
    """Marginal value per tile-day of a filler crop given projected supply; None if not plantable now."""
    dl = ctx.days_left
    if name == "WHEAT":
        if dl < 5:
            return None
        cycles = (dl - 1) // 4
        mp = econ.marginal("WHEAT", 4.0 * cycles, lump=True)
        n_anim = len(ctx.animals) + sum(ctx.shed.get(a, 0) + ctx.carried(a) for a in ANIMALS)
        feed_gap = n_anim * (dl - 1) - econ.ours["WHEAT"]
        price = max(mp, feed_price if feed_gap > 0 else 0.0)
        return (4.0 * price - 10.0) / 4.0 - P["load_plant"] * 1.0
    if name == "CARROT":
        if dl < 4:
            return None
        cycles = (dl - 1) // 3
        mp = econ.marginal("CARROT", 3.0 * cycles, lump=True)
        return (3.0 * mp - 20.0) / 3.0 - P["load_plant"] * 1.0
    if name == "TOMATO":
        if ctx.day > P["tomato_last_day"]:
            return None
        n_prod = min(4, (dl - 1 - 8) + 1)
        if n_prod <= 0:
            return None
        units = n_prod * 1.75  # fertilized
        mp = econ.marginal("TOMATO", units)
        occ = min(dl - 1, 12)
        return (units * mp - 50.0) / occ - P["load_plant"] * 1.0
    if name == "STRAWBERRY":
        if ctx.day > P["straw_last_day"]:
            return None
        n_prod = min(4, (dl - 1 - 10) // 2 + 1)
        if n_prod <= 0:
            return None
        units = n_prod * 2.0
        mp = econ.marginal("STRAWBERRY", units)
        if mp < P["guard_price"]["STRAWBERRY"]:
            return None
        occ = min(dl - 1, 17)
        return (units * mp - 100.0) / occ - P["load_plant"] * 1.0
    return None


def fill_tiles(ctx, mem, econ, plan, free, counts, buy, budget, labor_left, T):
    """Fill remaining free tiles with the best filler crop by marginal value; re-priced after every tile."""
    feed_price = feed_unit_price(ctx)
    n = 0
    while free and labor_left >= P["load_plant"]:
        best = None
        for name in P["fill_crops"]:
            v = fill_value(ctx, econ, name, feed_price)
            if v is None or v <= P["fill_min_value"]:
                continue
            if CROPS[name]["seed"] > budget:
                continue
            if best is None or v > best[0]:
                best = (v, name)
        if best is None:
            break
        v, name = best
        pos = free.pop(-1)
        plan[pos] = name
        counts[name] += 1
        buy[name] = buy.get(name, 0) + 1
        budget -= CROPS[name]["seed"]
        labor_left -= P["load_plant"]
        units = {"WHEAT": 4.0 * max(1, (ctx.days_left - 1) // 4), "CARROT": 3.0 * max(1, (ctx.days_left - 1) // 3), "TOMATO": 7.0, "STRAWBERRY": 8.0}[name]
        econ.ours[CROPS[name]["product"]] += units
        n += 1
    return n


def plan_day(ctx, mem):
    if not P["recipe"]:
        return plan_day_value(ctx, mem)
    econ = Econ(ctx)
    old_plan = mem.get("plan", {}) or {}
    plan = {}
    funded = {a: ctx.shed.get(a, 0) + ctx.carried(a) for a in ANIMALS}
    funded.update({c: ctx.seeds.get(c, 0) for c in CROPS})
    for pos, name in sorted(old_plan.items(), key=lambda kv: dist(kv[0], ctx.nearest_shed_tile(kv[0]))):
        t = ctx.tiles[pos[1]][pos[0]]
        ok_tile = t is None or is_weed(t) or (is_structure(t) and name in ANIMALS and G(t, "kind") == ANIMALS[name]["structure"])
        if ok_tile and funded.get(name, 0) > 0:
            plan[pos] = name
            funded[name] -= 1
    free = [p for p in ctx.empties if p not in plan]
    free += [p for p in ctx.weeds if p not in plan]
    free += [(x, y) for x, y, t in ctx.structures if (x, y) not in plan]
    free.sort(key=lambda p: dist(p, ctx.nearest_shed_tile(p)))
    # sunk assets first
    sunk = {}
    for a in ANIMALS:
        n = ctx.shed.get(a, 0) + ctx.carried(a) - sum(1 for v in plan.values() if v == a)
        if n > 0:
            sunk[a] = n
    for crop in CROPS:
        n = ctx.seeds.get(crop, 0) - sum(1 for v in plan.values() if v == crop)
        if n > 0:
            sunk[crop] = n
    for x, y, t in ctx.structures:
        for a in ANIMALS:
            if sunk.get(a, 0) > 0 and G(t, "kind") == ANIMALS[a]["structure"] and (x, y) not in plan:
                plan[(x, y)] = a
                sunk[a] -= 1
                if (x, y) in free:
                    free.remove((x, y))
    for name in sorted(sunk, key=lambda k: -(ANIMALS[k]["cost"] if k in ANIMALS else CROPS[k]["seed"])):
        while sunk[name] > 0 and free:
            pos = free.pop(0)
            plan[pos] = name
            sunk[name] -= 1
    # current composition (tiles + planned)
    counts = {k: 0 for k in list(ANIMALS) + list(CROPS)}
    for x, y, t in ctx.animals:
        counts[t["animal"]] += 1
    for x, y, t in ctx.plants:
        counts[t["crop"]] += 1
    for name in plan.values():
        counts[name] += 1
    T, exp = recipe_targets(ctx, counts)
    # labor
    load = estimate_actions(ctx) + sum(P["load_animal"] if n in ANIMALS else P["load_plant"] for n in plan.values())
    sched = P["hands_schedule"][min(ctx.day, len(P["hands_schedule"]) - 1)]
    H = max(hands_for_load(load), min(sched, P["max_hands"]))
    labor_left = labor_capacity(min(P["max_hands"], H)) / P["labor_margin"] - load
    budget = ctx.money - cash_reserve(ctx)
    buy = {}
    n_new = 0
    hours_ok = ctx.hours_left >= 4 and not ctx.last_day and ctx.days_left >= 3
    guard = P["guard_price"]
    order = ["COW", "SHEEP", "MELON", "WHEAT_FEED", "STRAWBERRY", "GOOSE", "TOMATO", "CARROT", "FILL"]
    if ctx.days_left <= 6:
        order = ["CARROT", "FILL"]
    for name in order:
        if not hours_ok or not free:
            break
        if name == "FILL":
            n_new += fill_tiles(ctx, mem, econ, plan, free, counts, buy, budget, labor_left, T)
            break
        if name == "WHEAT_FEED":
            # wheat tiles sized to feed all animals (placed + planned) from the farm
            n_anim = sum(counts[a] for a in ANIMALS)
            target = int(n_anim * P["feed_tiles_per_animal"]) + 2 if ctx.days_left >= 6 else 0
            name = "WHEAT"
        else:
            target = T.get(name, 0)
        cost = ANIMALS[name]["cost"] if name in ANIMALS else CROPS[name]["seed"]
        need_labor = P["load_animal"] if name in ANIMALS else P["load_plant"]
        product = ANIMALS[name]["product"] if name in ANIMALS else CROPS[name]["product"]
        while counts[name] < target and free:
            if cost > budget:
                break
            if name == "WHEAT" and labor_left < need_labor:
                break
            if name != "WHEAT" and labor_left < need_labor:
                if H >= P["max_hands"]:
                    break
                H += 1
                labor_left += P["hand_capacity"] / P["labor_margin"]
            # value guard on the marginal product price
            units = {"COW": 25.0, "SHEEP": 20.0, "STRAWBERRY": 8.0, "TOMATO": 7.0, "MELON": 6.0, "CARROT": 3.0 * max(1, (ctx.days_left - 1) // 3), "GOOSE": 2.0 * max(1, ctx.days_left - 4)}.get(name, 0.0)
            if product in guard and units > 0:
                mp = econ.marginal(product, units, lump=(name in ("MELON", "CARROT")))
                if mp < guard[product]:
                    break
            # animals near the shed, crops farther out
            pos = free.pop(0) if name in ANIMALS else free.pop(-1)
            plan[pos] = name
            counts[name] += 1
            buy[name] = buy.get(name, 0) + 1
            budget -= cost
            if name in ANIMALS:
                budget -= P["feed_days"] * feed_unit_price(ctx)
                econ.ours["FERTILIZER"] += ctx.days_left - 1
            econ.ours[product] += units
            labor_left -= need_labor
            n_new += 1
    mem["H"] = min(H, P["max_hands"])
    # land: NE then SW when tiles run short and cash allows; SE only if enabled
    want_land = False
    n_unl = len(ctx.unlocked)
    if not ctx.last_day and ctx.days_left >= 8 and hours_ok:
        if n_unl == 1 and ctx.day >= P["land_ne_day"] and len(free) <= 2 and budget >= LAND_PRICES[0] + 300:
            want_land = True
        elif n_unl == 2 and ctx.day >= P["land_sw_day"] and len(free) <= 2 and budget >= LAND_PRICES[1] + 300:
            want_land = True
        elif n_unl == 3 and P["buy_se"] and len(free) <= 2 and budget >= LAND_PRICES[2] + 2000 and ctx.day <= 12:
            want_land = True
    if DEBUG:
        print(f"[plan] d{ctx.day}h{ctx.hour} money={ctx.money:.0f} budget={budget:.0f} H={H} labor_left={labor_left:.0f} "
              f"free={len(free)} new={n_new} land={want_land} T={ {k: v for k, v in T.items() if v} } "
              f"counts={ {k: v for k, v in counts.items() if v} } exp={ {k: round(v) for k, v in exp.items() if v > 0} } buy={buy}")
    mem["plan"] = plan
    mem["buy"] = buy
    mem["vals"] = {}
    mem["targets"] = T
    econ2 = Econ(ctx)
    mprice = {}
    for p in PRODUCTS:
        mprice[p] = max(1.0, min(ctx.prices.get(p, 1), econ2.marginal(p, 5.0)))
    mem["mprice"] = mprice
    mem["feed_price"] = feed_unit_price(ctx)
    mem["cull"] = set()
    gross = {"COW": 2500.0, "SHEEP": 2500.0, "GOOSE": 1200.0, "STRAWBERRY": 900.0, "TOMATO": 450.0,
             "MELON": 600.0, "WHEAT": 80.0, "CARROT": 80.0}
    mem["gross"] = gross
    mem["want_land"] = want_land
    mem["r"] = discount_rate(ctx)
    return plan, buy


def estimate_actions(ctx):
    return len(ctx.animals) * P["load_animal"] + len(ctx.plants) * P["load_plant"] + len(ctx.weeds) * 0.3


# ----------------------------------------------------------------------------
# Task generation
# ----------------------------------------------------------------------------

def gen_tasks(ctx, mem, plan):
    tasks = {}
    mprice = mem.get("mprice") or {}
    fert_price = ctx.prices.get("FERTILIZER", 1)
    fert_mval = mprice.get("FERTILIZER", fert_price)
    feed_price = mem.get("feed_price", feed_unit_price(ctx))
    last_day = ctx.last_day
    use_fert = fert_price <= P["fert_use_price"]
    cull = mem.get("cull") or set()

    def add(pos, op, value, needs=None):
        tasks.setdefault(pos, []).append((op, value, needs))

    for x, y, t in ctx.animals:
        a = ANIMALS[t["animal"]]
        spot = ctx.prices.get(a["product"], 1)
        price = max(1.0, min(spot, mprice.get(a["product"], spot))) if P["task_price_mode"] == "marginal" else spot
        fed = bool(G(t, "fed_today", False))
        unfed_run = int(G(t, "consecutive_unfed", 0))
        held = int(G(t, "yield_units", 0))
        pend = int(G(t, "pending_care_bonus", 0))
        age_next = ctx.day + 1 - int(G(t, "placed_day", ctx.day))
        dsf = age_next - a["first"]
        produces_tonight = dsf >= 0 and dsf % a["interval"] == 0
        keep = (x, y) not in cull
        if not fed and not last_day and ctx.days_left > 1 and keep:
            v = 100000.0 if unfed_run >= 1 else (2000.0 + price * 2.0)
            add((x, y), ["FEED"], v, "WHEAT")
        if not G(t, "cared_today", False) and not last_day and ctx.days_left > 2 and keep:
            add((x, y), ["CARE"], price * (1.0 if fed else 0.9))
        if G(t, "fertilizer_available", False):
            straw_need = sum(1 for xx, yy, tt in ctx.plants if tt["crop"] in ("STRAWBERRY", "TOMATO"))
            add((x, y), ["COLLECT_FERTILIZER"], max(1.0, fert_mval - 2, 60.0 if straw_need > 0 else 0.0))
        if held > 0:
            nxt = (1 + pend) if produces_tonight else 0
            overflow = held + nxt - a["max_held"]
            if last_day or overflow > 0 or ctx.days_left <= 2:
                v = held * price + max(0, overflow) * price
            else:
                v = held * price * 0.2
            add((x, y), ["HARVEST"], v)

    for x, y, t in ctx.plants:
        c = CROPS[t["crop"]]
        spot = ctx.prices.get(c["product"], 1)
        price = max(1.0, min(spot, mprice.get(c["product"], spot))) if P["task_price_mode"] == "marginal" else spot
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
                # next production adds 2 when fertilized: harvest when it would overflow max_yield,
                # when the plant is finished, on the last day, or late in the day; otherwise defer
                fert_active = fert_until >= ctx.day
                nxt = 2 if fert_active else 1
                overflow = held + nxt > c["max_yield"]
                urgent = overflow or done or last_day or ctx.days_left <= 2
                v = held * price * (1.0 if (urgent or ctx.hour >= P["harvest_hour"]) else 0.15)
                add((x, y), ["HARVEST"], v)
            else:
                decaying = mls >= 0 and ctx.step >= mls
                maxed = held >= c["units"] or age >= c["maxday"]
                if decaying or last_day:
                    add((x, y), ["HARVEST"], held * price * 2)
                elif maxed and (watered or age > c["maxday"]):
                    add((x, y), ["HARVEST"], held * price)
        # fertilizer: strawberries at ages 9/13 (each covers two productions), tomatoes at 7/10;
        # wheat/carrot only when fertilizer is cheap
        if fert_until < ctx.day and not last_day and ctx.days_left >= 2:
            if t["crop"] == "STRAWBERRY" and age in (9, 11, 13, 15) and age <= ctx.day - int(G(t, "planted_day", ctx.day)):
                add((x, y), ["FERTILIZE"], price * 2.0, "FERT")
            elif t["crop"] == "TOMATO" and age in (7, 8, 10):
                add((x, y), ["FERTILIZE"], price * 2.0, "FERT")
            elif fert_price <= P["fert_cheap"] and not c["ongoing"]:
                win_start = (c["maxday"] + 1) // 2
                if age == win_start and t["crop"] != "MELON" and held < c["max_yield"]:
                    add((x, y), ["FERTILIZE"], price * (2 if t["crop"] == "WHEAT" else 1), "FERT")

    for x, y in ctx.weeds:
        if (x, y) not in plan:
            add((x, y), ["DIG"], 12.0 if ctx.days_left > 4 else 0.0)
    for x, y, t in ctx.structures:
        if (x, y) not in plan and ctx.days_left > 6:
            add((x, y), ["DIG"], 6.0)

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
    planned = 1 + min(P["max_hands"], max(int(mem.get("H", 0)), ctx.hires_today))
    n_units = max(ctx.unit_count(), planned)
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

    dropping = {}
    mem["dropping"] = dropping
    zones = mem.get("zones") or {}
    if ctx.hour < 1 and not ctx.last_day:
        zones = {}
    elif mem.get("zones_key") != ctx.day:
        zones = assign_zones(ctx, mem, mem.get("plan", {}) or {})
        mem["zones_key"] = ctx.day
    for u in range(n_units):
        pos = ctx.positions[u]
        inv = ctx.invs[u]
        at_shed = pos in ctx.shed_access
        n_prod = products_carried(inv)
        shed_tile = ctx.nearest_shed_tile(pos)
        d_shed = dist(pos, shed_tile)
        shed_room = SHED_CAP - ctx.shed_total
        total_carried = sum(products_carried(i) + i.get("WHEAT", 0) for i in ctx.invs)
        must_return = n_prod > 0 and hours_left <= d_shed + 2 and (last_day or total_carried > shed_room - 5)
        if at_shed:
            end_drop = n_prod > 0 and hours_left <= 3 and (last_day or total_carried > shed_room - 5)
            if n_prod > 0 and (n_prod >= P["drop_threshold"] or end_drop or not any_tasks):
                ops[u] = ["DROP"]
                for k, v in inv.items():
                    dropping[k] = dropping.get(k, 0) + v
                continue
            my_wheat = inv.get("WHEAT", 0)
            must_feed = sum(1 for x, y, t in ctx.animals if not G(t, "fed_today", False) and int(G(t, "consecutive_unfed", 0)) >= 1)
            if zones:
                zone_unfed = sum(1 for x, y, t in ctx.animals if zones.get((x, y)) == u and not G(t, "fed_today", False))
                need_w = zone_unfed + P["wheat_buffer"] - my_wheat if zone_unfed > 0 else 0
                if my_wheat == 0 and must_feed > 0:
                    need_w = max(need_w, min(must_feed, 4))
            else:
                exp_units = max(n_units, 1 + int(mem.get("H", 0)))
                need_w = min(unfed - carried_wheat, int(math.ceil(unfed / exp_units)) + 2) if my_wheat == 0 else 0
            if not last_day and need_w > 0 and shed_wheat > 0:
                share = max(1, min(shed_wheat, need_w, 14 if zones else 8))
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
                k = min(fert_in_shed, fert_needed, 8)
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
        rush = hours_left <= P["rush_hours"]
        for tpos, lst in tasks.items():
            if tpos in reserved and reserved[tpos] != u:
                continue
            val = 0.0
            carried_need = False
            placement = False
            for op, v, needs in lst:
                if v > 0 and unit_can(inv, needs, ctx):
                    val += v
                    if needs in ANIMALS or needs == "FERT":
                        carried_need = True
                    if op[0] in ("PLANT", "PLACE", "BUILD_COOP", "BUILD_PASTURE"):
                        placement = True
            if val <= 0:
                continue
            d = dist(pos, tpos)
            if d + 1 > hours_left:
                continue
            if last_day and d + 2 + dist(tpos, ctx.nearest_shed_tile(tpos)) > hours_left:
                continue
            if rush or (placement and P["placement_priority"]):
                score = val / (d + 1.0) ** 1.3
            else:
                score = (1.0 + math.log1p(val)) / (d + 1.0) ** P["sweep_dist_pow"]
            z = zones.get(tpos)
            if z is not None and z != u and val < 20000 and not carried_need:
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
    actions = len(ctx.animals) * P["load_animal"] + len(ctx.plants) * P["load_plant"] + placements * 3.0 + len(ctx.weeds) * 0.3
    if ctx.last_day:
        actions = len(ctx.animals) * 2.5 + len(ctx.plants) * 2.0 + 12
    need = hands_for_load(actions)
    if not ctx.last_day:
        need = max(need, int(mem.get("H", 0)))
        if P["recipe"]:
            need = max(need, P["hands_schedule"][min(ctx.day, len(P["hands_schedule"]) - 1)])
    else:
        need = P["max_hands"]
    need = min(need, P["max_hands"])
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
    dropping = mem.get("dropping") or {}
    shed_now = dict(ctx.shed)
    for k, v in dropping.items():
        if k in PRODUCTS:
            shed_now[k] = shed_now.get(k, 0) + v
    n_anim = len(ctx.animals) + sum(ctx.shed.get(a, 0) + ctx.carried(a) for a in ANIMALS)
    endgame = ctx.steps_left <= 0
    # emergency: if cash cannot cover feed for the unfed animals, sell anything
    unfed = sum(1 for x, y, t in ctx.animals if not G(t, "fed_today", False))
    wheat_have = ctx.shed.get("WHEAT", 0) + ctx.carried("WHEAT")
    feed_gap = max(0, unfed - wheat_have) * feed_unit_price(ctx) - ctx.money
    emergency = feed_gap > 0 and not ctx.last_day
    held_value = []
    for item in PRODUCTS:
        q = shed_now.get(item, 0)
        if q <= 0:
            continue
        inv = ctx.inv.get(item, I0)
        if item == "WHEAT":
            reserve = 0 if (endgame or dl <= 1) else min(q, n_anim + 2)
            if emergency:
                reserve = min(reserve, unfed)
            if not endgame and dl > 2 and market_price("WHEAT", inv) < P["wheat_floor"] and ctx.shed_total < 70:
                reserve = max(reserve, min(q, n_anim * 4))  # glut: keep feed stock instead of dumping
            if q - reserve > 0:
                orders.append(["SELL", "WHEAT", q - reserve])
            continue
        if item == "EGG" or endgame or emergency:
            orders.append(["SELL", item, q])
            continue
        base = MARKET_PARAMS[item]["base"]
        if item == "FERTILIZER":
            # keep enough for upcoming strawberry/tomato fertilizing
            need = 0
            for x, y, t in ctx.plants:
                age = ctx.day - int(G(t, "planted_day", ctx.day))
                if t["crop"] == "STRAWBERRY" and 4 <= age <= 13:
                    need += 1
                elif t["crop"] == "TOMATO" and 3 <= age <= 9:
                    need += 1
            need = min(need, 60)
            q = q - need
            if q <= 0:
                continue
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
    orders.sort(key=lambda o: {"MELON": 0, "MILK": 0, "WOOL": 0, "STRAWBERRY": 0, "EGG": 2, "WHEAT": 2, "FERTILIZER": 3}.get(o[1], 1))
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
    if ctx.hour in (0, 1):
        want = desired_hands(ctx, mem)
        n_new = max(0, want - ctx.hires_today)
        for i in range(n_new):
            c = fib(ctx.hires_today + i)
            if c > P["hire_cap_cost"] or cash < c + 20:
                break
            orders.append(["HIRE"])
            cash -= c
            if len(orders) >= 8:
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
        plan_names = {}
        for v in (mem.get("plan") or {}).values():
            plan_names[v] = plan_names.get(v, 0) + 1
        for name, n in sorted(plan_names.items(), key=lambda kv: -(ANIMALS[kv[0]]["cost"] if kv[0] in ANIMALS else CROPS[kv[0]]["seed"])):
            if name in ANIMALS:
                if name not in buy_plan or ctx.day > P["late_animal_day"] or dl - ANIMALS[name]["first"] < 2:
                    continue
                unplaced = sum(ctx.shed.get(a, 0) + ctx.carried(a) for a in ANIMALS)
                if unplaced >= P["max_unplaced_animals"]:
                    continue
                have = ctx.shed.get(name, 0) + ctx.carried(name)
                planned = sum(1 for v in (mem.get("plan") or {}).values() if v == name)
                need = min(planned - have, buy_plan.get(name, 0))
                cost = ANIMALS[name]["cost"] + P["feed_days"] * feed_unit_price(ctx)
                k = min(need, int((cash - reserve) // cost), shed_room)
                if k > 0:
                    orders.append(["BUY_ANIMAL", name, k])
                    cash -= k * ANIMALS[name]["cost"]
                    reserve += k * P["feed_days"] * feed_unit_price(ctx)
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
        if ctx.hour <= P["zone_hour"] and (mem.get("zones") or {}):
            # morning: the shed must cover every unit's own zone (incl. hands not hired yet)
            zones = mem.get("zones") or {}
            per_unit = {}
            for x, y, t in ctx.animals:
                if not G(t, "fed_today", False):
                    u = zones.get((x, y))
                    if u is not None:
                        per_unit[u] = per_unit.get(u, 0) + 1
            short = 0
            for u, n in per_unit.items():
                w = ctx.invs[u].get("WHEAT", 0) if u < len(ctx.invs) else 0
                short += max(0, n - w)
            need = short + (pending_animals if ctx.hour < 14 else 0) - ctx.shed.get("WHEAT", 0)
        else:
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
    hires = [o for o in orders if o[0] == "HIRE"][:6]
    feed = [o for o in orders if o[0] == "BUY_PRODUCT"]
    buys = [o for o in orders if o[0] in ("BUY_LAND", "BUY_ANIMAL", "BUY_SEED")]
    final = hires + feed + sells[:4] + buys + sells[4:]
    return final[:10]


# ----------------------------------------------------------------------------
# Agent
# ----------------------------------------------------------------------------

def _agent_impl(obs):
    ctx = Ctx(obs)
    if ctx.step == 0:
        MEM.pop(ctx.player, None)
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


def _safe_action(obs):
    """Fallback if the main logic raises: pass, but still sell whatever is in the shed."""
    try:
        player = int(G(obs, "player", 0))
        farm = G(obs, "farms", [])[player]
        n_hands = len(G(farm, "hands", []) or [])
        shed = G(G(obs, "private", {}), "shed", {}) or {}
        market = [["SELL", k, int(v)] for k, v in dict(shed).items() if k in PRODUCTS and int(v) > 0][:10]
        return {"farmer": ["PASS"], "hands": [["PASS"]] * n_hands, "market": market}
    except Exception:
        return {"farmer": ["PASS"], "hands": [], "market": []}


def agent(obs, config=None):
    try:
        return _agent_impl(obs)
    except Exception as e:  # never forfeit the episode on an internal error
        try:
            import traceback
            print("kaggriculture agent error:", repr(e))
            traceback.print_exc()
        except Exception:
            pass
        return _safe_action(obs)
