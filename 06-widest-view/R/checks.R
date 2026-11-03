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
#' fjord project). Every visible cell is projected to window coordinates for
#' frames across the video, weighted by its visible area.
#'
#' @return Invisibly, the largest share of visible area outside the frame.
check_frame_coverage <- function(scene, exaggeration = 4, n = 450, every = 25, size = 1080) {
  zscale <- scene$res_m / exaggeration
  idx <- which(scene$frac > 0, arr.ind = TRUE)            # row = north-south, col = west-east
  w   <- scene$frac[idx]
  x   <- idx[, "col"] - 0.5 - ncol(scene$frac) / 2        # scene x runs west-east
  z   <- idx[, "row"] - 0.5 - nrow(scene$frac) / 2        # scene z runs north-south
  y   <- scene$m[cbind(idx[, "col"], idx[, "row"])] / zscale

  base <- scene$rgb; base[is.na(base)] <- 0
  rayshader::plot_3d(base, scene$m, zscale = zscale, windowsize = c(size, size), shadow = FALSE)
  worst <- 0
  for (i in seq(1, n, by = every)) {
    cam <- camera_at(i, n)
    rayshader::render_camera(theta = cam$theta, phi = cam$phi, zoom = cam$zoom, fov = 35)
    win <- rgl::rgl.user2window(x, y, z)
    outside <- win[, 1] < 0 | win[, 1] > 1 | win[, 2] < 0 | win[, 2] > 1
    worst <- max(worst, sum(w[outside]) / sum(w))
  }
  rgl::close3d()
  message(sprintf("Frame coverage: at most %.2f%% of the visible area falls outside the frame -> %s",
                  100 * worst, if (worst < 0.001) "OK" else "CHECK"))
  invisible(worst)
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
