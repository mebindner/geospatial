# =============================================================================
# Locator map
# -----------------------------------------------------------------------------
# A small map of Norway with a dot on the summit, so viewers who don't know
# Rendalen see at a glance where in the country the 3D scene is.
#
# The outline comes from the analysis's own land mask (Kartverket > 0 m), not
# from a separate boundary file, so the dot and the coastline are guaranteed to
# share one coordinate system.
# =============================================================================

#' Simplified outline of mainland Norway as polygons
#'
#' The 500 m land mask is aggregated to 4 km before polygonising: at the size the
#' locator is shown (~150 px tall for 1,700 km) finer detail is invisible and
#' would only make the file slow to draw.
norway_outline <- function() {
  out <- path_proc("norway_outline.rds")
  if (file.exists(out)) return(terra::unwrap(readRDS(out)))

  land <- get_elevation(SCREEN_RES)$norway
  outline <- terra::aggregate(land, fact = 8, fun = "max", na.rm = TRUE) |>
    terra::classify(cbind(0, NA)) |>
    terra::as.polygons(dissolve = TRUE) |>
    terra::simplifyGeom(tolerance = 3000)
  saveRDS(terra::wrap(outline), out)   # wrap(): terra objects need it to survive saveRDS()
  outline
}

#' Render the locator as a transparent PNG
#'
#' @param summit_xy Summit position in EPSG:25833.
#' @param height Height in pixels; width follows Norway's shape.
#' @return Path to the PNG.
make_locator <- function(summit_xy, height = 230) {
  file <- path_proc("locator.png")
  outline <- norway_outline()
  e <- terra::ext(outline)
  width <- round(height * (e$xmax - e$xmin) / (e$ymax - e$ymin))

  grDevices::png(file, width = width, height = height, bg = "transparent", type = "cairo")
  graphics::par(mar = c(0, 0, 0, 0))
  terra::plot(outline, col = "#2a343c", border = "#7d8891", lwd = 0.6, axes = FALSE,
              legend = FALSE, mar = c(0, 0, 0, 0), background = NA)
  graphics::points(summit_xy[1], summit_xy[2], pch = 21, cex = 2.6, col = "white", lwd = 1.2)
  graphics::points(summit_xy[1], summit_xy[2], pch = 21, cex = 1.3, bg = GOLD, col = GOLD)
  grDevices::dev.off()
  file
}
