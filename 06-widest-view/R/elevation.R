# =============================================================================
# Elevation model
# -----------------------------------------------------------------------------
# Two open sources are combined:
#   1. Kartverket's national terrain model (DTM) for Norway, via the open WCS.
#      It is the authoritative source for Norway. Its coverage does not stop
#      at the border: rectangular blocks reach well into Sweden and Finland,
#      and it is 0 m beyond them.
#   2. Copernicus DEM GLO-90 where Kartverket has no data. Without it, the
#      Swedish mountains would partly be a flat plane at sea level, and summits
#      near the border would "see" through them and score too high.
#
# Norwegian land = Kartverket above 0 m AND inside Norway's national border.
# An earlier version used Kartverket > 0 alone, which counted ~104,000 km² of
# Swedish and Finnish land as Norwegian (17.5% of the first winner's view).
# =============================================================================

KARTVERKET_WCS <- "https://wcs.geonorge.no/skwms1/wcs.hoyde-dtm-nhm-25833"
GLO90_BUCKET   <- "https://copernicus-dem-90m.s3.amazonaws.com"
BOUNDARY_URL   <- "https://github.com/wmgeolab/geoBoundaries/raw/41af8f1/releaseData/gbOpen/NOR/ADM0/geoBoundaries-NOR-ADM0.geojson"

# National border -------------------------------------------------------------------

#' Norway's national border (geoBoundaries ADM0, from OpenStreetMap, ODbL)
#'
#' Downloaded once and stored as a GeoPackage in the grid's projection. The
#' GeoJSON is a single very large feature, so GDAL's object size limit is lifted.
norway_boundary <- function() {
  out <- path_proc("norway_boundary.gpkg")
  if (file.exists(out)) return(terra::vect(out))
  src <- path_raw("geoBoundaries-NOR-ADM0.geojson")
  if (!file.exists(src)) download.file(BOUNDARY_URL, src, mode = "wb", quiet = TRUE)
  terra::setGDALconfig("OGR_GEOJSON_MAX_OBJ_SIZE", "0")
  nor <- terra::vect(src) |> terra::project(GRID_CRS)
  terra::writeVector(nor, out, overwrite = TRUE)
  nor
}

SWEDEN_URL <- "https://github.com/wmgeolab/geoBoundaries/raw/9469f09/releaseData/gbOpen/SWE/ADM0/geoBoundaries-SWE-ADM0.geojson"

#' Sweden's national border (geoBoundaries ADM0, Open Government Licence v3.0)
#'
#' Used only to say how much of a view lies in Sweden. "Outside Norway" is not
#' good enough for that: Norway's border polygon has a generalised coastline, so
#' some Norwegian skerries fall just outside it and would be counted as Swedish.
sweden_boundary <- function() {
  out <- path_proc("sweden_boundary.gpkg")
  if (file.exists(out)) return(terra::vect(out))
  src <- path_raw("geoBoundaries-SWE-ADM0.geojson")
  if (!file.exists(src)) download.file(SWEDEN_URL, src, mode = "wb", quiet = TRUE)
  terra::setGDALconfig("OGR_GEOJSON_MAX_OBJ_SIZE", "0")
  swe <- terra::vect(src) |> terra::project(GRID_CRS)
  terra::writeVector(swe, out, overwrite = TRUE)
  swe
}

# Kartverket ------------------------------------------------------------------

#' Download Kartverket's DTM for the whole grid at one resolution
#'
#' The WCS answers requests up to a few thousand pixels, so the grid is fetched
#' in square tiles and mosaicked. Tiles are cached, so a failed run resumes.
#' @param res_m Resolution in metres.
#' @param area Extent to cover. Defaults to the whole grid; the 100 m stage only
#'   fetches windows around the finalists, since all of Norway at 100 m would be
#'   ~200 million cells.
#' @param key Name used in cache file names for this extent.
get_kartverket <- function(res_m, area = GRID_EXTENT, key = "norway", tile_px = 1000) {
  out <- path_proc(sprintf("kartverket_%s_%dm.tif", key, res_m))
  if (file.exists(out)) return(terra::rast(out))

  tile_dir <- path_raw(sprintf("kartverket_%dm", res_m))
  dir.create(tile_dir, recursive = TRUE, showWarnings = FALSE)
  step <- tile_px * res_m
  # Tiles are aligned to the national grid, so overlapping windows reuse tiles
  x0 <- GRID_EXTENT$xmin + floor((area$xmin - GRID_EXTENT$xmin) / step) * step
  y0 <- GRID_EXTENT$ymin + floor((area$ymin - GRID_EXTENT$ymin) / step) * step
  tiles <- tidyr::expand_grid(
    xmin = seq(x0, area$xmax - 1, by = step),
    ymin = seq(y0, area$ymax - 1, by = step)
  ) |>
    dplyr::mutate(
      xmax = pmin(xmin + step, GRID_EXTENT$xmax),
      ymax = pmin(ymin + step, GRID_EXTENT$ymax),
      file = file.path(tile_dir, sprintf("t_%d_%d.tif", xmin, ymin))
    )

  purrr::pwalk(tiles, function(xmin, ymin, xmax, ymax, file) {
    if (file.exists(file)) return(invisible())
    # sprintf("%.0f") rather than paste(): R would write -100000 as "-1e+05",
    # which the WCS rejects as an invalid bounding box.
    url <- paste0(
      KARTVERKET_WCS, "?service=WCS&version=1.0.0&request=GetCoverage",
      "&coverage=nhm_dtm_topo_25833&crs=EPSG:25833&format=GeoTIFF",
      "&bbox=", paste(sprintf("%.0f", c(xmin, ymin, xmax, ymax)), collapse = ","),
      "&width=", sprintf("%.0f", (xmax - xmin) / res_m),
      "&height=", sprintf("%.0f", (ymax - ymin) / res_m)
    )
    download.file(url, file, mode = "wb", quiet = TRUE)
    # The service answers errors with an XML document and HTTP 200; never keep one
    if (!startsWith(readr::read_file_raw(file)[1:2] |> rawToChar(), "II")) {
      unlink(file)
      stop("Kartverket WCS did not return a GeoTIFF for tile ", basename(file))
    }
  })

  message("Mosaicking ", nrow(tiles), " Kartverket tiles at ", res_m, " m")
  dtm <- terra::vrt(tiles$file) |>
    terra::resample(terra::crop(grid_template(res_m), area), method = "near")
  # Sea and areas outside Norway come back as ~0 with small negative noise
  terra::ifel(is.na(dtm) | dtm < 0, 0, dtm, filename = out, overwrite = TRUE)
}

# Copernicus GLO-90 -------------------------------------------------------------

#' Copernicus DEM resampled to the grid, used only outside Norway
#'
#' Tiles are read straight from the public AWS bucket as cloud-optimised
#' GeoTIFFs. Only tiles that exist (land) are listed, using the bucket's own
#' tile list, so sea tiles never trigger failed requests.
get_copernicus <- function(res_m, area = GRID_EXTENT, key = "norway") {
  out <- path_proc(sprintf("copernicus_%s_%dm.tif", key, res_m))
  if (file.exists(out)) return(terra::rast(out))

  target  <- terra::crop(grid_template(res_m), area)
  # Polygon from the extent only; as.polygons() on the raster itself is too
  # large at 200 m
  bbox_ll <- terra::as.polygons(terra::ext(target), crs = GRID_CRS) |>
    terra::project("EPSG:4326") |>
    terra::ext()
  tile_list <- readr::read_lines(paste0(GLO90_BUCKET, "/tileList.txt"))
  wanted <- tidyr::expand_grid(
    lat = floor(bbox_ll$ymin):floor(bbox_ll$ymax),
    lon = floor(bbox_ll$xmin):floor(bbox_ll$xmax)
  ) |>
    dplyr::mutate(name = sprintf("Copernicus_DSM_COG_30_%s%02d_00_%s%03d_00_DEM",
                                 ifelse(lat >= 0, "N", "S"), abs(lat),
                                 ifelse(lon >= 0, "E", "W"), abs(lon))) |>
    dplyr::filter(name %in% tile_list)

  message("Reading ", nrow(wanted), " Copernicus GLO-90 tiles")
  urls <- sprintf("/vsicurl/%s/%s/%s.tif", GLO90_BUCKET, wanted$name, wanted$name)
  terra::vrt(urls) |>
    terra::project(target, method = "average", filename = out, overwrite = TRUE)
}

# Combined model ----------------------------------------------------------------

#' Terrain for line-of-sight calculations, plus two land masks
#'
#' The ranking counts all land in view, in any country, from summits in Norway.
#' The Norwegian share is kept alongside it, so the video and README can say
#' how much of a view lies across the border.
#'
#' Land outside Kartverket's coverage comes from Copernicus. Its sea surface
#' and large lakes are flattened to values near 0 m, so a 1 m threshold keeps
#' the open sea out of "land" there.
#'
#' @param area,key As in get_kartverket(); default is the whole grid.
#' @return list(dem = terrain for visibility, land = TRUE on land in any country,
#'   norway = TRUE on Norwegian land)
get_elevation <- function(res_m, area = GRID_EXTENT, key = "norway") {
  dem_file  <- path_proc(sprintf("dem_%s_%dm.tif", key, res_m))
  land_file <- path_proc(sprintf("land_%s_%dm.tif", key, res_m))
  all_file  <- path_proc(sprintf("landall_%s_%dm.tif", key, res_m))
  if (!all(file.exists(c(dem_file, land_file, all_file)))) {
    kv  <- get_kartverket(res_m, area, key)
    cop <- get_copernicus(res_m, area, key)
    cop <- terra::ifel(is.na(cop) | cop < 0, 0, cop)
    terra::ifel(kv > 0, kv, cop, filename = dem_file, overwrite = TRUE)
    terra::writeRaster((kv > 0) | (cop > 1), all_file, overwrite = TRUE)
    # A cell is Norwegian land if its centre is inside the border and above sea level
    inside <- terra::rasterize(norway_boundary(), kv, touches = FALSE)
    terra::writeRaster(kv > 0 & !is.na(inside), land_file, overwrite = TRUE)
  }
  list(dem = terra::rast(dem_file), land = terra::rast(all_file), norway = terra::rast(land_file))
}
