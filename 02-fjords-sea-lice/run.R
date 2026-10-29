# =============================================================================
# Norway's fjords in 3D with sea lice on top
# -----------------------------------------------------------------------------
# Run from Geospatial.Rproj (repository root) or from this folder.
# Steps: 1) visibility check  2) optional test frames  3) full video.
# =============================================================================

PROJECT <- if (dir.exists("02-fjords-sea-lice")) "02-fjords-sea-lice" else "."
for (f in list.files(file.path(PROJECT, "R"), pattern = "[.]R$", full.names = TRUE)) source(f)

# 1. Every farm included in the averages must be visible in every frame
check_visibility("sognefjord", year = 2026, weeks = 18:42)

# 2. Quick look at single frames (intro, mid-season, final still):
# make_video("sognefjord", year = 2026, weeks = 18:42, only_frames = c(1, 400, 775))

# 3. Full video, about 20 minutes.
# Lice data downloaded 28 Oct 2026; week 43 was still missing many counts, so the
# video stops at week 42. The conclusion was checked against the data: the three
# farms above the 0.5 limit in week 42 are all at the mouth of the fjord.
make_video("sognefjord", year = 2026, weeks = 18:42,
           conclusion = c("All three farms above the 0.5 limit", "sit at the mouth of the fjord."))

# Another fjord, same code:
# make_video("hardangerfjord", year = 2026, weeks = 18:42)
