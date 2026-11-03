# =============================================================================
# Which Norwegian summit has the widest view?
# -----------------------------------------------------------------------------
# Run from Geospatial.Rproj (repository root) or from this folder.
# Every stage caches its result in data/processed, so re-running is cheap.
# =============================================================================

# Frame text contains non-ASCII characters (ø, á, ×, ²). R started from a terminal
# can run in the C locale, where "×" stays unmarked bytes and prints as
# "<c3><97>" next to UTF-8 names. RStudio already uses UTF-8; this makes Rscript match.
invisible(Sys.setlocale("LC_CTYPE", "en_US.UTF-8"))

PROJECT <- if (dir.exists("06-widest-view")) "06-widest-view" else "."
for (f in list.files(file.path(PROJECT, "R"), pattern = "[.]R$", full.names = TRUE)) source(f)

# 1. Method check: the viewshed must match the theoretical horizon on a flat plane
check_horizon(1000)
check_horizon(2000)

# 2. Analysis: screen all summits (500 m), re-rank the best 40 (200 m),
#    final numbers for the top 5 (100 m) and for Galdhopiggen (the highest summit) as reference
screen <- run_screening()
ranked <- run_ranking(screen)
check_rank_agreement(screen, ranked)
final  <- run_final(ranked)
refs   <- run_references(screen)

# 3. Video of the winner (about 30 minutes to render)
#    make_video() is called from video_story.R, which builds the hook and the
#    ranking panel from the numbers above, so the text can never drift from the data.
source(file.path(PROJECT, "video_story.R"))
