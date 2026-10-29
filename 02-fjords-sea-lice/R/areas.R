# =============================================================================
# Study areas
# -----------------------------------------------------------------------------
# Each fjord is defined once, as a bounding box in WGS84. Every other step
# (elevation download, lice filtering, rendering) takes the fjord name as its
# only spatial input, so a new fjord is one entry here and one function call.
# =============================================================================

# Bounding boxes ----------------------------------------------------------------
# Boxes are drawn generously around the farms. The Sognefjord box reaches out into
# open sea on the west side so that farms at the fjord mouth do not sit on the edge
# of the rendered terrain block. check_visibility() verifies this for every frame.
fjords <- list(
  sognefjord     = c(xmin = 4.65, ymin = 60.88, xmax = 6.25, ymax = 61.30),
  hardangerfjord = c(xmin = 5.45, ymin = 59.75, xmax = 6.75, ymax = 60.50)
)

# Display names used in titles on the rendered frames
fjord_labels <- c(
  sognefjord     = "Sognefjord",
  hardangerfjord = "Hardangerfjord"
)

#' Bounding box of a fjord in the projection Kartverket delivers elevation data in
#'
#' @param fjord Name of an entry in `fjords`.
#' @return An `sf` bbox in EPSG:25833 (ETRS89 / UTM 33N).
area_bbox <- function(fjord) {
  if (!fjord %in% names(fjords)) {
    stop("Unknown fjord: ", fjord, ". Choose one of: ", paste(names(fjords), collapse = ", "))
  }
  sf::st_bbox(fjords[[fjord]], crs = 4326) |>
    sf::st_as_sfc() |>
    sf::st_transform(25833) |>
    sf::st_bbox()
}

#' Short fingerprint of a fjord's bounding box
#'
#' Used in cache file names, so that changing a box always triggers a fresh
#' download instead of silently reusing data for the old extent.
area_key <- function(fjord) {
  substr(rlang::hash(fjords[[fjord]]), 1, 8)
}
