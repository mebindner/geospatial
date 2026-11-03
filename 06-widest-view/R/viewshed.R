# =============================================================================
# Visibility analysis
# -----------------------------------------------------------------------------
# For each summit: which cells of Norwegian land can a person standing on top
# see? The answer depends on terrain in between, on the curvature of the Earth
# and on atmospheric refraction, which bends light slightly downwards and lets
# you see a little further than pure geometry allows.
#
# terra::viewshed() wraps GDAL's viewshed algorithm. Its curvcoef argument
# combines curvature and refraction; 6/7 (0.857) is the standard value for
# visible light (refraction coefficient 0.13).
# =============================================================================

EYE_HEIGHT  <- 1.7      # metres, a person standing on the summit
CURV_COEF   <- 6 / 7    # curvature + standard refraction for visible light
MAX_RANGE_M <- 350000   # search radius. From 2,500 m to a 2,500 m target the
                        # horizon is ~380 km in theory; beyond 350 km nothing on
                        # Norwegian land is high enough to be seen in practice.

#' Visible Norwegian land from one summit
#'
#' The terrain is cropped to a square window around the summit, which makes each
#' call ~50 times faster than running on the whole country and does not change
#' the result, since nothing outside MAX_RANGE_M can be seen.
#'
#' @param x,y Summit position in EPSG:25833.
#' @param ele Summit elevation from OSM (metres).
#' @param dem,norway SpatRasters from get_elevation().
#' @param keep_raster Return the visibility raster as well (used for the video).
#' @return list(area_km2, max_dist_km, raster or NULL)
visible_land <- function(x, y, ele, dem, norway, keep_raster = FALSE) {
  win  <- terra::ext(x - MAX_RANGE_M, x + MAX_RANGE_M, y - MAX_RANGE_M, y + MAX_RANGE_M)
  d    <- terra::crop(dem, win)
  land <- terra::crop(norway, win)

  # A grid cell holds the average height of its area, which is lower than the
  # summit point. Lift the observer by the difference so the eye is at the true
  # summit height (never below the cell surface).
  cell_ele <- terra::extract(d, cbind(x, y))[1, 1]
  observer <- max(ele - cell_ele, 0) + EYE_HEIGHT

  vis <- terra::viewshed(d, loc = c(x, y), observer = observer, target = 0,
                         curvcoef = CURV_COEF, output = "yes/no")
  seen <- vis & (land == 1)

  # Cell area in km2, and the furthest visible land cell. The distance raster is
  # computed once per window; masking it keeps memory flat even at 100 m.
  cell_km2 <- prod(terra::res(d)) / 1e6
  n_seen   <- terra::global(seen, "sum", na.rm = TRUE)[[1]]
  dist     <- terra::distance(terra::rast(d), terra::vect(cbind(x, y), crs = GRID_CRS))
  max_dist <- terra::global(terra::ifel(seen, dist, NA), "max", na.rm = TRUE)[[1]] / 1000
  if (is.na(max_dist)) max_dist <- 0

  list(area_km2 = n_seen * cell_km2, max_dist_km = max_dist, raster = if (keep_raster) seen else NULL)
}

#' Run visible_land() for many summits in parallel
#'
#' Uses forked workers (macOS/Linux). Each worker re-opens the rasters from
#' disk, because terra objects cannot be shared across processes.
#'
#' @param peaks sf points with name, ele.
#' @param res_m Resolution to compute at.
#' @param cores Number of worker processes.
#' @return peaks with area_km2 and max_dist_km added.
#' Workers are limited by memory, not CPU: a 200 m window is ~12 million cells,
#' and each worker holds several layers of it. On an 8 GB laptop more than three
#' workers at 200 m pushes the machine into swap and makes the run slower.
score_peaks <- function(peaks, res_m, key = "norway",
                        cores = if (res_m >= 500) 6 else 3) {
  dem_file  <- path_proc(sprintf("dem_%s_%dm.tif", key, res_m))
  land_file <- path_proc(sprintf("land_%s_%dm.tif", key, res_m))
  xy <- sf::st_coordinates(peaks)

  results <- parallel::mclapply(seq_len(nrow(peaks)), function(i) {
    # By default terra lets every process plan for 60% of RAM; split it instead
    terra::terraOptions(memfrac = 0.5 / cores, progress = 0)
    dem <- terra::rast(dem_file); norway <- terra::rast(land_file)
    r <- visible_land(xy[i, 1], xy[i, 2], peaks$ele[i], dem, norway)
    c(area_km2 = r$area_km2, max_dist_km = r$max_dist_km)
  }, mc.cores = cores)

  dplyr::bind_cols(peaks, dplyr::bind_rows(results))
}

#' One summit per massif
#'
#' OSM often has several named tops on the same mountain within a few hundred
#' metres, with nearly identical views. For a ranking of places, keep the best
#' top within each `radius_km` cluster.
distinct_summits <- function(scored, radius_km = 3) {
  scored <- dplyr::arrange(scored, dplyr::desc(area_km2))
  keep <- rep(TRUE, nrow(scored))
  d <- sf::st_distance(scored) |> units::drop_units()
  for (i in seq_len(nrow(scored))) {
    if (!keep[i]) next
    near <- which(d[i, ] < radius_km * 1000 & seq_len(nrow(scored)) > i)
    keep[near] <- FALSE
  }
  scored[keep, ]
}
