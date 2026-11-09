"""Render output/frost_season_final.png: 100 frost seasons, month by month (1080x1350, for social feeds)."""
from pathlib import Path
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.colors import LinearSegmentedColormap
from matplotlib.patches import Rectangle, FancyArrowPatch
import analysis as A

ROOT = Path(__file__).resolve().parents[1]
BG, INK, INK2, MUTED = "#08121c", "#f2f7fc", "#a9b8c8", "#6f8296"
FROST = LinearSegmentedColormap.from_list(
    "frost", ["#11263b", "#1b4673", "#2f73bf", "#6fb0ee", "#c4e2fb", "#ffffff"])
VMAX = 28
MONTHS = ["okt", "nov", "dec", "jan", "feb", "mar", "apr"]
W, H = 1080, 1350
plt.rcParams.update({"font.family": "Avenir Next", "text.color": INK})


def px(fig, x, y):  # pixel coords (top-left origin) -> figure fraction
    return x / W, 1 - y / H


def main():
    st = A.load(); nm = A.national_monthly(st); se = A.seasons(nm)
    years = sorted(se); tot = {y: sum(v) for y, v in se.items()}
    early = sum(tot[y] for y in years[:30]) / 30
    late = sum(tot[y] for y in years[-30:]) / 30
    hi = max(tot, key=tot.get); lo = min(tot, key=tot.get)

    fig = plt.figure(figsize=(W / 200, H / 200), dpi=200, facecolor=BG)
    T = lambda x, y, s, **k: fig.text(*px(fig, x, y), s, **k)

    T(64, 70, "DANMARK  ·  100 VINTRE  ·  1925/26–2024/25", fontsize=7.5, color=MUTED, va="top",
      weight="demibold")
    T(62, 112, "Vintrene har mistet\nen tredjedel af frosten", fontsize=24, weight="bold", va="top",
      linespacing=1.02)
    T(64, 292, "Hver lodret stribe er én vinter, hvert felt en måned.\nJo lysere felt, jo flere frostdøgn.",
      fontsize=9, color=INK2, va="top", linespacing=1.2)

    # ---- the grid: seasons left->right, months top->bottom
    gx0, gx1, gy0, gy1 = 118, 1020, 440, 880
    ax = fig.add_axes([gx0 / W, 1 - gy1 / H, (gx1 - gx0) / W, (gy1 - gy0) / H], facecolor=BG)
    n = len(years); cw = 1.0
    for i, y in enumerate(years):
        for j, v in enumerate(se[y]):
            ax.add_patch(Rectangle((i + 0.08, j + 0.06), cw - 0.16, 0.88, lw=0,
                                   fc=FROST(min(v, VMAX) / VMAX)))
    ax.set_xlim(0, n); ax.set_ylim(7, 0); ax.axis("off")
    for j, m in enumerate(MONTHS):
        T(gx0 - 16, gy0 + (j + 0.5) * (gy1 - gy0) / 7, m, fontsize=8.5, color=INK2, ha="right", va="center")
    BY0, BY1 = gy1 + 22, gy1 + 112
    xpix = lambda y: gx0 + (years.index(y) + 0.5) * (gx1 - gx0) / n
    for y in range(1930, 2030, 10):
        if y in years:
            T(xpix(y), BY1 + 12, str(y), fontsize=7.5, color=MUTED, ha="center", va="top")

    # ---- season totals with an 11-season running mean
    bx = fig.add_axes([gx0 / W, 1 - BY1 / H, (gx1 - gx0) / W, (BY1 - BY0) / H], facecolor=BG)
    tv = [tot[y] for y in years]
    bx.bar([i + 0.5 for i in range(n)], tv, width=0.7, color="#24507f", lw=0)
    rm = [sum(tv[max(0, i - 5):i + 6]) / len(tv[max(0, i - 5):i + 6]) for i in range(n)]
    bx.plot([i + 0.5 for i in range(n)], rm, color=INK, lw=1.6, solid_capstyle="round")
    bx.set_xlim(0, n); bx.set_ylim(0, 125); bx.axis("off")
    T(gx0 - 16, BY0 + 30, "i alt", fontsize=8.5, color=INK2, ha="right", va="center")
    T(gx0 - 16, BY0 + 56, "pr. vinter", fontsize=6.5, color=MUTED, ha="right", va="center")

    # ---- callouts for the coldest and mildest season
    for y, label, ha in [(hi, f"{hi}/{str(hi+1)[2:]}: {tot[hi]:.0f} frostdøgn", "center"),
                         (lo, f"{lo}/{str(lo+1)[2:]}: {tot[lo]:.0f}", "center")]:
        x = xpix(y)
        fig.add_artist(plt.Line2D([x / W, x / W], [1 - (gy0 - 10) / H, 1 - (gy0 - 34) / H],
                                  color=INK2, lw=0.9))
        T(x, gy0 - 40, label, fontsize=8, color=INK, ha=ha, va="bottom", weight="demibold")

    # ---- legend
    lx, ly = 760, 1110
    lax = fig.add_axes([lx / W, 1 - (ly + 12) / H, 260 / W, 12 / H])
    import numpy as np
    lax.imshow(np.linspace(0, 1, 256)[None, :], aspect="auto", cmap=FROST); lax.axis("off")
    T(lx, ly + 22, "0", fontsize=7, color=MUTED, va="top")
    T(lx + 260, ly + 22, f"{VMAX}+ frostdøgn i måneden", fontsize=7, color=MUTED, va="top", ha="right")

    # ---- the two numbers
    for x, val, lab, c in [(64, early, f"{years[0]}–{years[29]+1}", INK2), (390, late, f"{years[-30]}–{years[-1]+1}", INK)]:
        T(x, 1085, lab, fontsize=8, color=MUTED, va="top", weight="demibold")
        T(x - 4, 1112, f"{val:.0f}", fontsize=34, weight="bold", va="top", color=c)
        T(x, 1210, "frostdøgn pr. vinter", fontsize=8, color=INK2, va="top")
    fig.add_artist(FancyArrowPatch(px(fig, 238, 1162), px(fig, 360, 1162), arrowstyle="-|>",
                                   mutation_scale=12, color=INK2, lw=1.2))
    T(299, 1148, f"−{(1 - late / early) * 100:.0f} %", fontsize=9.5, color=INK, ha="center", va="bottom",
      weight="bold")

    T(64, 1272, "Gennemsnit af fem DMI-stationer med uafbrudte målinger: Hammer Odde, Vestervig, Fanø, Samsø og København.\n"
      "Data: ECA&D frostdøgnsindeks (Klein Tank m.fl. 2002). Frostdøgn: minimumstemperatur under 0 °C.  "
      "Martin Eckberg Bindner",
      fontsize=5.8, color=MUTED, va="top", linespacing=1.4)

    out = ROOT / "output/frost_season_final.png"
    fig.savefig(out, dpi=200, facecolor=BG)
    print(out, f"early {early:.1f} late {late:.1f} hi {hi} {tot[hi]:.0f} lo {lo} {tot[lo]:.0f}")


if __name__ == "__main__":
    main()
