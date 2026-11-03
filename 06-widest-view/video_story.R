# =============================================================================
# Story and video
# -----------------------------------------------------------------------------
# Builds the on-screen text from the analysis results and renders the video.
# Nothing in the text is typed by hand: names, heights and areas all come from
# `final` and `refs`, so a re-run with new data can never leave stale numbers
# on screen. Expects `final` and `refs` from run.R.
# =============================================================================

winner <- final[1, ]
galdh  <- refs[1, ]
ratio  <- winner$area_100m / galdh$area_100m

# Three short lines rather than one long one, so nothing is cut at 1080 px.
# Special characters are written as \u escapes: the file then works in any locale.
# paste0() rather than sprintf(): sprintf() converts to the session's native
# encoding, which turns the multiplication sign into "<c3><97>" outside UTF-8.
hook <- c(
  "Norway's widest view isn't from its highest summit.",
  paste0("From ", winner$name, " (", format(winner$ele, big.mark = ","), " m) you see ",
         format(round(ratio, 1), nsmall = 1), "× as much land"),
  paste0("as from ", galdh$name, " (", format(galdh$ele, big.mark = ","), " m), the highest.")
)

# End panel: the 100 m top 5, plus the highest summit for context (no rank,
# since its rank comes from the 500 m screening; see the README)
ranking <- dplyr::bind_rows(
  sf::st_drop_geometry(final) |>
    dplyr::transmute(rank = dplyr::row_number(), name, ele, area_km2 = area_100m, highlight = rank == 1),
  sf::st_drop_geometry(galdh) |>
    dplyr::transmute(rank = NA_integer_, name = paste0(name, " (highest)"), ele, area_km2 = area_100m, highlight = FALSE)
)

# Guard: every visible cell must be inside the frame in every part of the video
coverage <- check_frame_coverage(build_scene(winner, paste0("peak_", winner$osm_id)))
if (coverage >= 0.001) stop("Part of the visible land falls outside the frame; adjust camera_at().")

make_video(winner, ranking, hook)
