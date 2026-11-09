"""Render output/frost_days_final.png: 50 years of fewer frost days in Denmark (1080x1350)."""
import json, math
from pathlib import Path
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Polygon
from matplotlib.colors import LinearSegmentedColormap
import analysis as A

ROOT = Path(__file__).resolve().parents[1]
# same dark look as hero.py and map.py: frost in blue, what was lost in amber
BG, INK, INK2, MUTED, GRID = "#08121c", "#f2f7fc", "#a9b8c8", "#6f8296", "#1c2a38"
BAR, EARLY_C, LATE_C, TREND = "#2f6aa8", "#c4e2fb", "#2f73bf", "#f2a65a"
LAND, NEIGH = "#132233", "#0d1926"
W, H = 1080, 1350
plt.rcParams.update({"font.family": "Avenir Next", "font.size": 7.5, "text.color": INK,
                     "axes.edgecolor": GRID, "axes.labelcolor": INK2, "xtick.color": MUTED,
                     "ytick.color": MUTED, "svg.fonttype": "none"})


def dk(x, nd=0):
    s = f"{abs(x):,.{nd}f}".replace(",", "X").replace(".", ",").replace("X", ".")
    return ("−" if x < 0 else "") + s


def outline(ids=("208",)):
    t = json.loads((ROOT / "data/raw/countries-10m.json").read_text())
    sc, tr = t["transform"]["scale"], t["transform"]["translate"]
    arcs = []
    for a in t["arcs"]:
        x = y = 0; pts = []
        for dx, dy in a:
            x += dx; y += dy; pts.append((x * sc[0] + tr[0], y * sc[1] + tr[1]))
        arcs.append(pts)
    def ring(ix):
        out = []
        for i in ix:
            p = arcs[i] if i >= 0 else arcs[~i][::-1]
            out += p if not out else p[1:]
        return out
    res = {}
    for g in t["objects"]["countries"]["geometries"]:
        if g.get("id") in ids:
            polys = g["arcs"] if g["type"] == "MultiPolygon" else [g["arcs"]]
            res[g["id"]] = [ring(r) for poly in polys for r in poly]
    return res


LABEL = {"Tirstrup": "Aarhus (Tirstrup)", "Bornholms Lufthavn": "Bornholm, lufthavn", "Odense Lufthavn": "Odense",
         "Tranebjerg, Samsø": "Samsø", "Nordby, Fanø": "Fanø", "Hammer Odde": "Hammer Odde"}


def main():
    from map import LOSS
    st = A.load(); nat, filled = A.national(st)
    ys = list(range(A.Y0, A.Y1 + 1)); v = [nat[y] for y in ys]
    a, b, se = A.ols(ys, v); _, z, p = A.mann_kendall(v)
    f0, f1 = a + b * A.Y0, a + b * A.Y1
    rows = A.station_change(st)

    fig = plt.figure(figsize=(W / 200, H / 200), dpi=200, facecolor=BG)
    T = lambda x, y, s, **k: fig.text(x / W, 1 - y / H, s, **k)
    box = lambda x0, y0, x1, y1: [x0 / W, 1 - y1 / H, (x1 - x0) / W, (y1 - y0) / H]

    T(64, 62, f"DANMARK  ·  5 DMI-STATIONER  ·  {A.Y0}–{A.Y1}", fontsize=7.5, color=MUTED, va="top", weight="demibold")
    T(62, 100, "Frostdøgnene er\nhalveret på 50 år", fontsize=24, weight="bold", va="top", linespacing=1.02)
    T(64, 278, "Frostdøgn pr. år, gennemsnit af fem stationer med uafbrudte målinger.", fontsize=9, color=INK2, va="top")

    # ---- panel A: yearly bars + linear trend
    ax = fig.add_axes(box(96, 345, 1030, 725), facecolor=BG)
    ax.bar(ys, v, width=0.7, color=BAR, zorder=2)
    ax.plot([A.Y0, A.Y1], [f0, f1], color=TREND, lw=2.4, solid_capstyle="round", zorder=3)
    for yy, ff, ha, dx, dy in [(A.Y0, f0, "center", 0, 26), (A.Y1, f1, "left", 1.2, 0)]:
        ax.scatter([yy], [ff], s=30, color=TREND, zorder=4, edgecolor=BG, linewidth=1.4)
        ax.text(yy + dx, ff + dy, f"{ff:.0f}", color=TREND, fontsize=13, weight="bold", ha=ha, va="center", zorder=5)
    ax.text(1977, 127, f"Trend: {dk(b*10,1)} frostdøgn pr. årti", color=TREND, fontsize=10, weight="bold", va="center")
    ax.text(1977, 118, f"95 %-interval {dk((b-2.01*se)*10,1)} til {dk((b+2.01*se)*10,1)}", color=INK2, fontsize=7.4,
            va="center")
    for y_ in (2010, 2020):
        ax.text(y_, nat[y_] + 2.5, f"{nat[y_]:.0f}", ha="center", fontsize=7.4, color=INK2)
    ax.set_xlim(A.Y0 - 3.5, A.Y1 + 3.5); ax.set_ylim(0, 132)
    ax.set_yticks([0, 25, 50, 75, 100, 125]); ax.set_xticks(range(1980, 2030, 10))
    ax.grid(axis="y", color=GRID, lw=0.7, zorder=0)
    for s_ in ("top", "right", "left"): ax.spines[s_].set_visible(False)
    ax.spines["bottom"].set_color(MUTED)
    ax.tick_params(length=0, labelsize=7.5, colors=MUTED)

    # ---- section B
    n_down = sum(r["diff"] < 0 for r in rows)
    T(64, 775, f"{'Alle' if n_down == len(rows) else n_down} {len(rows)} stationer har fået færre frostdøgn",
      fontsize=12, weight="bold", va="top")
    T(64, 812, "Gennemsnit 1976–1985 mod 2016–2025. Stationer med mindst 8 års data i begge årtier.",
      fontsize=7.6, color=INK2, va="top")

    K = math.cos(math.radians(56))
    mx = fig.add_axes(box(20, 850, 470, 1240), facecolor=BG)
    for r in outline()["208"]:
        if any(7 < x < 16 and 54 < y < 58 for x, y in r):
            mx.add_patch(Polygon(r, closed=True, fc=LAND, ec="#2c4258", lw=0.4))
    off = {"Bornholms Lufthavn": (-0.12, -0.14, "right"), "Hammer Odde": (0.12, 0.09, "left"),
           "Tirstrup": (0.14, 0, "left"), "Aalborg": (0.14, 0, "left"), "København": (0.12, 0.06, "left"),
           "Odense Lufthavn": (0.14, -0.06, "left"), "Nordby, Fanø": (0.14, -0.05, "left"),
           "Vestervig": (0.14, 0, "left"), "Tranebjerg, Samsø": (0.13, 0.07, "left")}
    for r in rows:
        mx.scatter(r["lon"], r["lat"], s=52, color=LOSS(0.35 + 0.65 * min(1, max(0, (-r["pct"] - 20) / 40))), edgecolor=BG, linewidth=1.3, zorder=3)
        dx, dy, ha = off.get(r["name"], (0.12, 0, "left"))
        mx.text(r["lon"] + dx, r["lat"] + dy, f"{dk(r['pct'])} %", fontsize=7.4, ha=ha, va="center",
                weight="bold", color=INK, zorder=4)
    mx.set_xlim(7.7, 15.3); mx.set_ylim(54.45, 57.85); mx.set_aspect(1 / K); mx.axis("off")

    dbx = fig.add_axes(box(680, 870, 1030, 1205), facecolor=BG)
    order = sorted(rows, key=lambda r: r["early"])
    for i, r in enumerate(order):
        dbx.plot([r["late"], r["early"]], [i, i], color="#34506d", lw=2, zorder=1, solid_capstyle="round")
        dbx.scatter([r["early"]], [i], s=30, color=EARLY_C, edgecolor=BG, lw=1, zorder=2)
        dbx.scatter([r["late"]], [i], s=30, color=LATE_C, edgecolor=BG, lw=1, zorder=3)
        dbx.text(-5, i, LABEL.get(r["name"], r["name"]), ha="right", va="center", fontsize=7.4, color=INK)
    top = len(order) - 1
    dbx.text(order[top]["early"], top + 0.8, "1976–85", ha="center", fontsize=7, color=EARLY_C, weight="demibold")
    dbx.text(order[top]["late"], top + 0.8, "2016–25", ha="center", fontsize=7, color="#6fb0ee", weight="demibold")
    dbx.set_xlim(0, 112); dbx.set_ylim(-0.7, top + 1.4)
    dbx.set_yticks([]); dbx.set_xticks([0, 25, 50, 75, 100])
    dbx.grid(axis="x", color=GRID, lw=0.7, zorder=0)
    for s_ in ("top", "right", "left"): dbx.spines[s_].set_visible(False)
    dbx.spines["bottom"].set_color(MUTED)
    dbx.tick_params(length=0, labelsize=7, colors=MUTED)
    T(1030, 1250, "frostdøgn pr. år", fontsize=7, color=MUTED, ha="right", va="top")

    T(64, 1266, "Data: ECA&D frostdøgnsindeks, målinger fra DMI (Klein Tank m.fl. 2002). Frostdøgn: minimum under 0 °C.\n"
      f"Trend: mindste kvadraters metode, Mann-Kendall p = {dk(p,3)}. {filled} manglende stationsår er skønnet.\n"
      "Stationerne ligger mest ved kysten, så indlandet har flere frostdøgn.  Martin Eckberg Bindner", fontsize=5.6, color=MUTED, va="top", linespacing=1.3)

    out = ROOT / "output/frost_days_final.png"
    fig.savefig(out, dpi=200, facecolor=BG)
    print(out, f"trend {b*10:.2f}/decade, fitted {f0:.1f}->{f1:.1f}, p={p:.4f}")


if __name__ == "__main__":
    main()
