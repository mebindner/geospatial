"""Frost-day series and 50-year trend for Denmark (shared by figure.py)."""
import json, math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
Y0, Y1 = 1976, 2025          # the 50-year window
EARLY, LATE = (1976, 1985), (2016, 2025)
CORE = {106: "Hammer Odde", 107: "Vestervig", 109: "Nordby, Fanø", 113: "Tranebjerg, Samsø", 116: "København"}
# ECA&D lists some series twice (blended copies); keep one of each
DUPLICATES = {117, 118, 303, 304, 25254, 25244}
NAMES = {**CORE, 307: "Thyborøn", 25236: "Aarhus Lufthavn", 677: "Bornholms Lufthavn", 671: "Aalborg",
         672: "Karup", 674: "Skrydstrup", 675: "Odense Lufthavn", 676: "Røsnæs Fyr", 673: "Tirstrup",
         22733: "Tylstrup"}


def load():
    raw = json.loads((ROOT / "data/processed/stations.json").read_text())
    st = {}
    for k, s in raw.items():
        k = int(k)
        if k in DUPLICATES or s["lat"] is None or not (54 < s["lat"] < 58 and 7 < s["lon"] < 16):
            continue
        st[k] = dict(name=NAMES.get(k, s["name"].title()), lat=s["lat"], lon=s["lon"],
                     fd={int(y): v for y, v in s["fd"].items()},
                     fdm={int(y): v for y, v in s.get("fdm", {}).items()})
    return dedupe(st)


def dedupe(st):
    """Drop series that are copies of another (same values in >=10 shared years); keep the longer/named one."""
    keys = sorted(st, key=lambda k: (k not in CORE, k not in NAMES, -len(st[k]["fd"])))
    keep = []
    for k in keys:
        a = st[k]["fd"]
        if not any(len(sh := [y for y in a if y in st[j]["fd"]]) >= 10
                   and sum(abs(a[y] - st[j]["fd"][y]) for y in sh) / len(sh) < 0.5 for j in keep):
            keep.append(k)
    return {k: st[k] for k in keep}


def national(st, y0=1926, y1=2025):
    """Mean of the five long series; a missing station-year is its 1961-90 mean plus the others' anomaly."""
    ref = {}
    for k in CORE:
        v = [st[k]["fd"][y] for y in range(1961, 1991) if y in st[k]["fd"]]
        ref[k] = sum(v) / len(v)
    nat, filled = {}, 0
    for y in range(y0, y1 + 1):
        an = [st[k]["fd"][y] - ref[k] for k in CORE if y in st[k]["fd"]]
        a = sum(an) / len(an)
        nat[y] = sum(st[k]["fd"].get(y, ref[k] + a) for k in CORE) / len(CORE)
        filled += len(CORE) - len(an)
    return nat, filled


def ols(xs, ys):
    n = len(xs); mx = sum(xs) / n; my = sum(ys) / n
    sxx = sum((x - mx) ** 2 for x in xs)
    b = sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / sxx
    a = my - b * mx
    res = sum((y - a - b * x) ** 2 for x, y in zip(xs, ys))
    se = math.sqrt(res / (n - 2) / sxx)
    return a, b, se


def mann_kendall(ys):
    n = len(ys)
    s = sum((ys[j] > ys[i]) - (ys[j] < ys[i]) for i in range(n) for j in range(i + 1, n))
    var = n * (n - 1) * (2 * n + 5) / 18
    z = (s - (1 if s > 0 else -1 if s < 0 else 0)) / math.sqrt(var)
    p = math.erfc(abs(z) / math.sqrt(2))
    return s, z, p


def station_change(st, min_years=8):
    rows = []
    for k, s in st.items():
        e = [s["fd"][y] for y in range(EARLY[0], EARLY[1] + 1) if y in s["fd"]]
        l = [s["fd"][y] for y in range(LATE[0], LATE[1] + 1) if y in s["fd"]]
        if len(e) >= min_years and len(l) >= min_years:
            em, lm = sum(e) / len(e), sum(l) / len(l)
            rows.append(dict(id=k, name=s["name"], lat=s["lat"], lon=s["lon"], early=em, late=lm,
                             diff=lm - em, pct=(lm - em) / em * 100))
    return sorted(rows, key=lambda r: r["pct"])


if __name__ == "__main__":
    st = load(); nat, filled = national(st)
    ys = list(range(Y0, Y1 + 1)); v = [nat[y] for y in ys]
    a, b, se = ols(ys, v)
    print(f"filled station-years 1926-2025: {filled}")
    print(f"OLS {Y0}-{Y1}: {b*10:.1f} days/decade (95% CI {(b-2.01*se)*10:.1f} to {(b+2.01*se)*10:.1f}), "
          f"fitted {a+b*Y0:.0f} -> {a+b*Y1:.0f}")
    print("Mann-Kendall S, z, p:", mann_kendall(v))
    for d in range(1976, 2026, 10):
        print(d, f"{sum(nat[y] for y in range(d, d+10))/10:.1f}")
    rows = station_change(st)
    print(len(rows), "stations with both decades;", sum(r['diff'] < 0 for r in rows), "decreased")
    for r in rows: print(f"{r['name']:<28}{r['early']:6.1f}{r['late']:6.1f}{r['pct']:7.0f}%")


def national_monthly(st, y0=1925, y1=2025):
    """{(year, month): frost days} as the mean of the five long series, gaps filled as in national()."""
    def val(k, y, m):
        row = st[k].get("fdm", {}).get(y)
        return None if row is None else row[m - 1]
    ref = {}
    for k in CORE:
        for m in range(1, 13):
            v = [x for y in range(1961, 1991) if (x := val(k, y, m)) is not None]
            ref[k, m] = sum(v) / len(v)
    out = {}
    for y in range(y0, y1 + 1):
        for m in range(1, 13):
            have = {k: x for k in CORE if (x := val(k, y, m)) is not None}
            if not have:
                continue
            a = sum(x - ref[k, m] for k, x in have.items()) / len(have)
            out[y, m] = sum(have.get(k, max(0.0, ref[k, m] + a)) for k in CORE) / len(CORE)
    return out


SEASON = [10, 11, 12, 1, 2, 3, 4]  # October to April


def seasons(nm, first=1925, last=2024):
    """Frost season starting in autumn of year y: list of monthly values Oct(y)..Apr(y+1)."""
    return {y: [nm.get((y if m >= 10 else y + 1, m)) for m in SEASON] for y in range(first, last + 1)}
