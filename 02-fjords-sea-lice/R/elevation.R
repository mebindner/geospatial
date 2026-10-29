# =============================================================================
# Elevation: Kartverket's national terrain model (DTM)
# -----------------------------------------------------------------------------
# Source: the open WCS service for the national height model, EPSG:25833.
# No login is needed. The service resamples on request, so we ask for exactly
# the resolution we want to render instead of downloading 1 m tiles and
# aggregating them locally.
# =============================================================================

WCS_URL <- "https://wcs.geonorge.no/skwms1/wcs.hoyde-dtm-nhm-25833"

#' Download (or reuse) the terrain model for a fjord
#'
#' @param fjord Name of an entry in `fjords`.
#' @param res_m Cell size in metres. 100 m keeps the mesh small enough to render
#'   hundreds of frames on a laptop while still showing the fjord walls clearly.
#' @param dir Folder for the cached GeoTIFF.
#' @return A `SpatRaster` with sea and no-data cells set to 0 m.
get_elevation <- function(fjord, res_m = 100, dir = "data/raw") {
  bb <- area_bbox(fjord)
  file <- file.path(dir, sprintf("dtm_%s_%dm_%s.tif", fjord, res_m, area_key(fjord)))

  if (!file.exists(file)) {
    # Snap the box to whole cells so width and height are exact integers
    bb[c("xmin", "ymin")] <- floor(bb[c("xmin", "ymin")] / res_m) * res_m
    bb[c("xmax", "ymax")] <- ceiling(bb[c("xmax", "ymax")] / res_m) * res_m
    url <- paste0(
      WCS_URL, "?service=WCS&version=1.0.0&request=GetCoverage",
      "&coverage=nhm_dtm_topo_25833&crs=EPSG:25833&format=GeoTIFF",
      "&bbox=", paste(bb[c("xmin", "ymin", "xmax", "ymax")], collapse = ","),
      "&width=", (bb["xmax"] - bb["xmin"]) / res_m,
      "&height=", (bb["ymax"] - bb["ymin"]) / res_m
    )
    message("Downloading elevation for ", fjord, " (", res_m, " m) ...")
    download.file(url, file, mode = "wb", quiet = TRUE)
  }

  dtm <- terra::rast(file)
  # The sea surface comes back as values around 0 with small negative noise.
  # Flattening it to exactly 0 gives a clean water mask and a flat fjord surface.
  terra::ifel(is.na(dtm) | dtm < 0, 0, dtm)
}
