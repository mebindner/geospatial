# =============================================================================
# Satellite imagery
# -----------------------------------------------------------------------------
# Source: Sentinel-2 cloudless 2016 by EOX IT Services (https://s2maps.eu),
# a cloud-free mosaic of Copernicus Sentinel-2 data. The 2016 edition is
# licensed CC BY 4.0, which matches this repository's licence for images;
# later editions are CC BY-NC-SA.
#
# Real imagery instead of computed terrain colours is the main visual step up
# from the fjord video: valleys are green, high plateaus grey, glaciers white.
# =============================================================================

EOX_WMS <- "https://tiles.maps.eox.at/wms"
IMAGERY_CREDIT <- "Sentinel-2 cloudless 2016 by EOX (CC BY 4.0), contains modified Copernicus Sentinel data"

#' Satellite image resampled onto a scene grid
#'
#' The WMS serves geographic coordinates (EPSG:4326), so the image is requested
#' a little larger than the scene and then reprojected to UTM 33 cell for cell.
#'
#' @param template SpatRaster defining the scene grid (EPSG:25833).
#' @param px Width of the requested image in pixels (height follows the aspect).
#' @return SpatRaster with three layers (red, green, blue) scaled 0-1.
get_imagery <- function(template, key, px = 4000) {
  out <- path_proc(sprintf("imagery_%s.tif", key))
  if (file.exists(out)) return(terra::rast(out))

  bb <- terra::as.polygons(terra::ext(template), crs = GRID_CRS) |>
    terra::project("EPSG:4326") |>
    terra::ext()
  aspect <- (bb$ymax - bb$ymin) / ((bb$xmax - bb$xmin) * cos(mean(c(bb$ymin, bb$ymax)) * pi / 180))
  url <- paste0(
    EOX_WMS, "?service=WMS&version=1.1.1&request=GetMap&layers=s2cloudless&styles=",
    "&srs=EPSG:4326&format=image/jpeg",
    "&bbox=", paste(sprintf("%.5f", c(bb$xmin, bb$ymin, bb$xmax, bb$ymax)), collapse = ","),
    "&width=", px, "&height=", round(px * aspect)
  )
  jpg <- path_raw(sprintf("imagery_%s.jpg", key))
  download.file(url, jpg, mode = "wb", quiet = TRUE)

  img <- terra::rast(jpg)
  terra::ext(img) <- bb
  terra::crs(img) <- "EPSG:4326"
  terra::project(img, template, method = "bilinear") |>
    (\(r) r / 255)() |>
    terra::writeRaster(out, overwrite = TRUE)
}
