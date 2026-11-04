# =============================================================================
# Quality checks
# -----------------------------------------------------------------------------
# Three checks guard the result:
#   1. Method: on a perfectly flat plane the viewshed must reach the textbook
#      horizon distance, given curvature and refraction.
#   2. Input: OSM elevations that disagree wildly with the terrain model are
#      flagged and excluded (wrong tag or misplaced node).
#   3. Robustness: the ranking at 200 m must agree with the 500 m screening,
#      and the winner's area must converge from 200 m to 100 m.
# =============================================================================

EARTH_RADIUS_M <- 6371000

#' Check 1: viewshed on a flat plane matches the theoretical horizon
#'
#' With GDAL's correction, a target at distance d is lowered by
#' curvcoef * d^2 / (2R). The horizon is where that equals the eye height:
#' d = sqrt(2 * R * h / curvcoef).
check_horizon <- function(h = 1000, res_m = 500, tolerance_cells = 2) {
  half <- 200000
  flat <- terra::rast(terra::ext(-half, half, -half, half), resolution = res_m, crs = GRID_CRS, vals = 0)
  vis  <- terra::viewshed(flat, loc = c(0, 0), observer = h, target = 0, curvcoef = CURV_COEF, output = "yes/no")
  dist <- terra::distance(flat, terra::vect(cbind(0, 0), crs = GRID_CRS))
  seen_max <- terra::global(terra::ifel(vis, dist, NA), "max", na.rm = TRUE)[[1]]
  theory   <- sqrt(2 * EARTH_RADIUS_M * h / CURV_COEF)

  ok <- abs(seen_max - theory) <= tolerance_cells * res_m * sqrt(2)
  message(sprintf("Horizon check: viewshed %.1f km, theory %.1f km -> %s",
                  seen_max / 1000, theory / 1000, if (ok) "OK" else "FAIL"))
  invisible(ok)
}

#' Check 2: flag summits whose OSM elevation disagrees with the terrain model
#'
#' A summit is always at least as high as the average of its grid cell, and at
#' 500 m cells rarely more than ~600 m higher, even for needle peaks like Storen.
#' Outside that band, the OSM tag or node position is wrong.
flag_bad_elevations <- function(peaks, max_above = 700, max_below = 50) {
  peaks |>
    dplyr::mutate(ele_ok = (ele - cell_ele) <= max_above & (ele - cell_ele) >= -max_below)
}

#' Check 4: is all the visible land actually inside the video frame?
#'
#' The counter on screen adds up every visible cell. If the camera crops some of
#' them out, the picture shows less than the number claims (the lesson from the
#' fjord project). For each checked frame, only the land revealed so far (inside
#' the current ring) is tested, since the camera deliberately starts close and
#' pulls back as the ring grows. Cells are weighted by their visible area.
#'
#' Timeline arguments must match make_video().
#' @return Invisibly, the largest share of revealed visible area outside the frame.
check_frame_coverage <- function(scene, exaggeration = 4, intro_s = 2, reveal_s = 9, hold_s = 7,
                                 fps = 25, every = 10, size = 1080) {
  zscale <- scene$res_m / exaggeration
  idx <- which(scene$frac > 0, arr.ind = TRUE)            # row = north-south, col = west-east
  w   <- scene$frac[idx]
  d   <- scene$dist[idx]
  x   <- idx[, "col"] - 0.5 - ncol(scene$frac) / 2        # scene x runs west-east
  z   <- idx[, "row"] - 0.5 - nrow(scene$frac) / 2        # scene z runs north-south
  y   <- scene$m[cbind(idx[, "col"], idx[, "row"])] / zscale

  n_intro <- intro_s * fps; n_reveal <- reveal_s * fps
  n <- n_intro + n_reveal + hold_s * fps
  max_radius <- max(d)

  base <- scene$rgb; base[is.na(base)] <- 0
  rayshader::plot_3d(base, scene$m, zscale = zscale, windowsize = c(size, size), shadow = FALSE)
  worst <- 0
  for (i in seq(n_intro + 1, n, by = every)) {
    cam <- camera_at(i, n_intro, n_reveal, n)
    rayshader::render_camera(theta = cam$theta, phi = cam$phi, zoom = cam$zoom, fov = cam$fov)
    shown <- d <= max_radius * reveal_progress(i, n_intro, n_reveal)
    if (!any(shown)) next
    win <- rgl::rgl.user2window(x[shown], y[shown], z[shown])
    outside <- win[, 1] < 0 | win[, 1] > 1 | win[, 2] < 0 | win[, 2] > 1
    worst <- max(worst, sum(w[shown][outside]) / sum(w[shown]))
  }
  rgl::close3d()
  message(sprintf("Frame coverage: at most %.2f%% of the visible area falls outside the frame -> %s",
                  100 * worst, if (worst < 0.001) "OK" else "CHECK"))
  invisible(worst)
}

#' Check 5: labelled points need room for their labels
#'
#' The coverage check only asks whether land is inside the frame. A labelled
#' point at the very edge passes it, but its label is cut off. This checks the
#' summit, the landmarks and the furthest visible point in the final (hold) view,
#' where they are labelled, against a margin from every edge.
#'
#' @param points Tibble with x, y (EPSG:25833) and ele.
check_points_in_frame <- function(scene, points, exaggeration = 4, intro_s = 2, reveal_s = 9, hold_s = 7,
                                  fps = 25, margin = 0.06, size = 1080) {
  zscale <- scene$res_m / exaggeration
  n_intro <- intro_s * fps; n_reveal <- reveal_s * fps; n <- n_intro + n_reveal + hold_s * fps
  base <- scene$rgb; base[is.na(base)] <- 0
  rayshader::plot_3d(base, scene$m, zscale = zscale, windowsize = c(size, size), shadow = FALSE)
  worst <- 1
  for (i in c(n_intro + n_reveal + 1, n)) {            # start and end of the hold
    cam <- camera_at(i, n_intro, n_reveal, n)
    rayshader::render_camera(theta = cam$theta, phi = cam$phi, zoom = cam$zoom, fov = cam$fov)
    xz  <- purrr::map2(points$x, points$y, \(x, y) scene_point(scene, x, y))
    win <- rgl::rgl.user2window(purrr::map_dbl(xz, "x"), points$ele / zscale, purrr::map_dbl(xz, "z"))
    worst <- min(worst, win[, 1], 1 - win[, 1], win[, 2], 1 - win[, 2])
  }
  rgl::close3d()
  message(sprintf("Labelled points: closest is %.1f%% from an edge (need %.0f%%) -> %s",
                  100 * worst, 100 * margin, if (worst >= margin) "OK" else "CHECK"))
  invisible(worst >= margin)
}

#' Check 6: the country shares add up
#'
#' Visible land is split into Norway, Sweden and "other" (land outside both,
#' e.g. a skerry just outside Norway's generalised coastline). Each visible cell
#' must be in exactly one group, so the parts sum to the total, and nothing may
#' be counted as both Norwegian and Swedish. "Other" is reported, and must be
#' small, because the video only names Norway and Sweden.
#'
#' @param visible,vis_nor,vis_swe Logical rasters on the same grid.
#' @param max_other Largest acceptable share of visible land in "other".
check_country_split <- function(visible, vis_nor, vis_swe, max_other = 0.005) {
  km2 <- function(r) terra::global(r, "sum", na.rm = TRUE)[[1]] * prod(terra::res(visible)) / 1e6
  total <- km2(visible); nor <- km2(vis_nor); swe <- km2(vis_swe); both <- km2(vis_nor & vis_swe)
  other <- total - nor - swe
  other <- max(other, 0)   # floating-point remainder of a sum that is exactly zero
  ok <- both == 0 && other / total <= max_other
  message(sprintf("Country split: total %.0f = Norway %.0f + Sweden %.0f + other %.0f km2 (both: %.0f) -> %s",
                  total, nor, swe, other, both, if (ok) "OK" else "CHECK"))
  invisible(ok)
}

#' Check 7: the map reads north-up
#'
#' People read maps with north up and east to the right. Known points are
#' projected to the screen in the final view: a point east of the summit must
#' appear to its right, a point north of it must appear above it.
#'
#' @param points Tibble with x, y (EPSG:25833) and ele, plus the summit's x, y, ele.
check_orientation <- function(scene, points, summit, exaggeration = 4, intro_s = 2, reveal_s = 9, hold_s = 7,
                              fps = 25, size = 1080) {
  zscale <- scene$res_m / exaggeration
  n_intro <- intro_s * fps; n_reveal <- reveal_s * fps; n <- n_intro + n_reveal + hold_s * fps
  base <- scene$rgb; base[is.na(base)] <- 0
  rayshader::plot_3d(base, scene$m, zscale = zscale, windowsize = c(size, size), shadow = FALSE)
  cam <- camera_at(n, n_intro, n_reveal, n)
  rayshader::render_camera(theta = cam$theta, phi = cam$phi, zoom = cam$zoom, fov = cam$fov)
  proj <- function(x, y, ele) { p <- scene_point(scene, x, y); rgl::rgl.user2window(p[["x"]], ele / zscale, p[["z"]])[1, 1:2] }
  s <- proj(summit$x, summit$y, summit$ele)
  ok <- TRUE
  for (k in seq_len(nrow(points))) {
    w <- proj(points$x[k], points$y[k], points$ele[k])
    dx <- points$x[k] - summit$x; dy <- points$y[k] - summit$y
    # Only test the dominant direction, so a point due north is not judged on x
    if (abs(dx) > abs(dy) * 0.5 && sign(w[1] - s[1]) != sign(dx)) ok <- FALSE
    if (abs(dy) > abs(dx) * 0.5 && sign(w[2] - s[2]) != sign(dy)) ok <- FALSE
  }
  rgl::close3d()
  message("Orientation (north up, east right): ", if (ok) "OK" else "CHECK")
  invisible(ok)
}

#' Check 3a: rank agreement between two resolutions (Spearman's rho, top-n overlap)
check_rank_agreement <- function(screen, rank, n = 10) {
  both <- dplyr::inner_join(
    sf::st_drop_geometry(screen) |> dplyr::select(osm_id, area_screen = area_km2),
    sf::st_drop_geometry(rank)   |> dplyr::select(osm_id, area_rank = area_km2),
    by = "osm_id"
  )
  rho <- stats::cor(both$area_screen, both$area_rank, method = "spearman")
  top_screen <- both |> dplyr::slice_max(area_screen, n = n) |> dplyr::pull(osm_id)
  top_rank   <- both |> dplyr::slice_max(area_rank, n = n) |> dplyr::pull(osm_id)
  overlap <- length(intersect(top_screen, top_rank))
  same_winner <- top_screen[1] == top_rank[1]
  message(sprintf("Rank agreement 500 m vs 200 m: Spearman %.2f, top-%d overlap %d/%d, same winner: %s",
                  rho, n, overlap, n, same_winner))
  invisible(list(rho = rho, overlap = overlap, same_winner = same_winner))
}
