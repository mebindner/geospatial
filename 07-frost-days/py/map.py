"""Render output/frost_map_final.png: where in Denmark frost days have disappeared (E-OBS 0.1° grid)."""
import csv, json
from collections import defaultdict
from pathlib import Path
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.colors import LinearSegmentedColormap
from matplotlib.patches import Rectangle, Polygon
from hero import FROST, BG, INK, INK2, MUTED
from figure import dk

ROOT = Path(__file__).resolve().parents[1]
W, H = 1080, 1350
P0, P1 = (1951, 1980), (1995, 2024)          # two 30-year periods
K = np.cos(np.radians(56.0))                 # lon scale at Denmark's latitude
LOSS = LinearSegmentedColormap.from_list("loss", ["#2a1d17", "#6b3a1f", "#c4652b", "#f2a65a", "#ffe2b8"])
CITIES = {"Aalborg": (9.92, 57.05), "Aarhus": (10.21, 56.16), "Odense": (10.39, 55.40),
          "København": (12.57, 55.68), "Esbjerg": (8.45, 55.47), "Herning": (8.98, 56.14)}
plt.rcParams.update({"font.family": "Avenir Next", "text.color": INK})


def load_grid():
    cells = defaultdict(dict)
    with open(ROOT / "data/processed/eobs_fd_dk.csv") as f:
        for r in csv.DictReader(f):
            cells[float(r["lon"]), float(r["lat"])][int(r["year"])] = float(r["fd"])
    return cells


def period_mean(fd, p):
    v = [fd[y] for y in range(p[0], p[1] + 1) if y in fd]
    return sum(v) / len(v) if len(v) == p[1] - p[0] + 1 else None


def dk_outline():
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
    g = next(g for g in t["objects"]["countries"]["geometries"] if g.get("id") == "208")
    return [ring(r) for poly in g["arcs"] for r in poly]


BORNHOLM_SHIFT = (-2.6, 2.4)   # Bornholm drawn as an inset in the empty Kattegat corner


def shift(lon, lat):
    return (lon + BORNHOLM_SHIFT[0], lat + BORNHOLM_SHIFT[1]) if lon > 14 else (lon, lat)


def draw(ax, vals, cmap, vmin, vmax, outline, ext, cell=0.1, gap=0.011):
    """vals: {(lon, lat): value}. Squares with a hairline gap, then the coastline on top."""
    # one raster, PX pixels per cell with a 1-pixel gap, so every gap is identical
    PX = 9
    lon0, lat1 = ext[0], ext[3]
    nx, ny = round((ext[1] - ext[0]) / cell), round((ext[3] - ext[2]) / cell)
    img = np.zeros((ny * PX, nx * PX, 4))
    for (lon, lat), v in vals.items():
        if v is None:
            continue
        x, y = shift(lon, lat)
        i, j = round((x - cell / 2 - lon0) / cell), round((lat1 - (y + cell / 2)) / cell)
        if 0 <= i < nx and 0 <= j < ny:
            img[j * PX:(j + 1) * PX - 1, i * PX:(i + 1) * PX - 1] = cmap(min(1, max(0, (v - vmin) / (vmax - vmin))))
    ax.imshow(img, extent=(lon0, lon0 + nx * cell, lat1 - ny * cell, lat1), interpolation="nearest", zorder=1)
    for r in outline:
        ax.add_patch(Polygon([shift(*p) for p in r], closed=True, fc="none", ec="#ffffff", lw=0.35, alpha=0.3, zorder=2))
    bx, by = shift(14.65, 54.97)
    ax.add_patch(Rectangle((bx, by), 0.62, 0.38, fc="none", ec=MUTED, lw=0.5, ls=(0, (2, 2))))
    ax.set_xlim(ext[0], ext[1]); ax.set_ylim(ext[2], ext[3]); ax.set_aspect(1 / K); ax.axis("off")


def dk_cells(cells, outline):
    """Keep grid cells whose centre, or a point 0.04° from it, lies on Danish land."""
    from matplotlib.path import Path as MPath
    paths = [MPath(r) for r in outline if len(r) > 2]
    offs = [(0, 0), (0.04, 0), (-0.04, 0), (0, 0.04), (0, -0.04)]
    keep = {}
    for (lon, lat), fd in cells.items():
        if any(p.contains_point((lon + dx, lat + dy)) for dx, dy in offs for p in paths):
            keep[lon, lat] = fd
    return keep


def main():
    import analysis as A
    outline = dk_outline(); cells = dk_cells(load_grid(), outline)
    a = {k: period_mean(v, P0) for k, v in cells.items()}
    b = {k: period_mean(v, P1) for k, v in cells.items()}
    lost = {k: a[k] - b[k] for k in cells}
    pct = {k: lost[k] / a[k] * 100 for k in cells}
    ma, mb = np.mean(list(a.values())), np.mean(list(b.values()))
    ys = list(range(1951, 2025)); nat = [np.mean([v[y] for v in cells.values()]) for y in ys]
    _, slope, se = A.ols(ys, nat)
    n_down = sum(v > 0 for v in lost.values())

    fig = plt.figure(figsize=(W / 200, H / 200), dpi=200, facecolor=BG)
    T = lambda x, y, s, **k: fig.text(x / W, 1 - y / H, s, **k)
    T(64, 62, "DANMARK  ·  11 × 11 KM-GITTER  ·  1951–2024", fontsize=7.5, color=MUTED, va="top", weight="demibold")
    T(62, 100, "Hele Danmark har\nfået færre frostdøgn", fontsize=24, weight="bold", va="top", linespacing=1.02)
    T(64, 270, "Gennemsnitligt antal frostdøgn pr. år i hver gittercelle.", fontsize=9, color=INK2, va="top")

    ext = (7.9, 12.8, 54.5, 57.8)   # edges on the 0.1° grid
    for x0, p, m, vals in [(30, P0, ma, a), (550, P1, mb, b)]:
        ax = fig.add_axes([x0 / W, 1 - 950 / H, 500 / W, 570 / H], facecolor=BG)
        draw(ax, vals, FROST, 30, 100, outline, ext)
        T(x0 + 34, 330, f"{p[0]}–{p[1]}", fontsize=10, weight="bold", va="top")
        T(x0 + 34, 362, f"{m:.0f} frostdøgn pr. år", fontsize=8, color=INK2, va="top")

    # frost legend
    lx, ly = 64, 962
    lax = fig.add_axes([lx / W, 1 - (ly + 10) / H, 300 / W, 10 / H])
    lax.imshow(np.linspace(0, 1, 256)[None, :], aspect="auto", cmap=FROST); lax.axis("off")
    for v in (30, 50, 70, 90):
        T(lx + (v - 30) / 70 * 300, ly + 18, str(v), fontsize=6.8, color=MUTED, va="top", ha="center")
    T(lx + 310, ly + 5, "frostdøgn pr. år", fontsize=6.8, color=MUTED, va="center")

    # ---- change: small map + histogram
    T(64, 1022, "Tabt frostdøgn pr. år", fontsize=11, weight="bold", va="top")
    T(64, 1052, f"{n_down} af {len(cells)} celler har færre frostdøgn. Faldet er {min(lost.values()):.0f}–{max(lost.values()):.0f} døgn\n"
      f"({min(pct.values()):.0f}–{max(pct.values()):.0f} %). Landstrend 1951–2024: {dk(slope*10, 1)} døgn pr. årti.",
      fontsize=7.6, color=INK2, va="top", linespacing=1.2)
    T(710, 1132, "antal gitterceller", fontsize=6.5, color=MUTED, va="top", ha="right")
    cx = fig.add_axes([800 / W, 1 - 1250 / H, 240 / W, 260 / H], facecolor=BG)
    draw(cx, lost, LOSS, 0, 32, outline, ext, gap=0.006)
    hx = fig.add_axes([70 / W, 1 - 1228 / H, 640 / W, 100 / H], facecolor=BG)
    bins = np.arange(0, 34, 2)
    cnt, _ = np.histogram(list(lost.values()), bins)
    hx.bar(bins[:-1] + 1, cnt, width=1.7, color=[LOSS((c + 1) / 32) for c in bins[:-1]], lw=0)
    hx.set_xlim(0, 34); hx.set_yticks([])
    for s_ in ("top", "right", "left"): hx.spines[s_].set_visible(False)
    hx.spines["bottom"].set_color(MUTED); hx.tick_params(colors=MUTED, labelsize=6.8, length=0)
    hx.set_xticks([0, 10, 20, 30]); hx.set_facecolor(BG)
    T(712, 1240, "døgn", fontsize=6.8, color=MUTED, va="top", ha="right")

    T(64, 1278, "Data: E-OBS v31.0e, daglig minimumstemperatur på 0,1°-gitter (Cornes m.fl. 2018, ECA&D). Frostdøgn: minimum under 0 °C.\n"
      "Gitteret er interpoleret fra målestationer; detaljer mellem stationerne er usikre. Bornholm vist i boks.  Martin Eckberg Bindner",
      fontsize=5.6, color=MUTED, va="top", linespacing=1.4)
    out = ROOT / "output/frost_map_final.png"
    fig.savefig(out, dpi=200, facecolor=BG)
    print(out, f"P0 {ma:.1f} P1 {mb:.1f} trend {slope*10:.2f}/decade +-{2*se*10:.2f}")


if __name__ == "__main__":
    main()
