# =============================================================================
# Analysis grid
# -----------------------------------------------------------------------------
# Every raster in this project is aligned to one grid in EPSG:25833 (ETRS89 /
# UTM 33N, the projection Kartverket publishes Norway in). Using one grid with
# a few resolutions keeps the screening, re-ranking and video comparable cell
# for cell.
# =============================================================================

# Extent ------------------------------------------------------------------------
# Mainland Norway plus a margin into Sweden, Finland and Russia. Lines of sight
# from Norwegian summits cross the border, so the terrain there must exist in
# the model even though only Norwegian land is counted.
GRID_EXTENT <- terra::ext(-100000, 1200000, 6400000, 7960000)
GRID_CRS    <- "EPSG:25833"

# Resolutions -------------------------------------------------------------------
# 500 m: screening every candidate summit (fast, ~2.6 million cells per window)
# 200 m: re-ranking the best candidates
# 100 m: final numbers for the top few, as a convergence check
SCREEN_RES <- 500
RANK_RES   <- 200
FINAL_RES  <- 100

#' Empty template raster for a resolution
grid_template <- function(res_m) {
  terra::rast(GRID_EXTENT, resolution = res_m, crs = GRID_CRS)
}

#' Path helper so every file lands in the same project folders
path_raw  <- function(...) file.path(PROJECT, "data", "raw", ...)
path_proc <- function(...) file.path(PROJECT, "data", "processed", ...)
path_out  <- function(...) file.path(PROJECT, "output", ...)
