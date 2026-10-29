# Kartverkets terrænmodel (DTM) via åben WCS – ingen login.
# Hentes direkte i den ønskede opløsning, så rasteret kan renderes på en almindelig maskine.

WCS_URL <- "https://wcs.geonorge.no/skwms1/wcs.hoyde-dtm-nhm-25833"

hent_hoejde <- function(fjord, opl = 100, mappe = "data/raw") {
  fil <- file.path(mappe, sprintf("dtm_%s_%dm.tif", fjord, opl))
  if (!file.exists(fil)) {
    bb <- omraade(fjord)
    bb[c("xmin", "ymin")] <- floor(bb[c("xmin", "ymin")] / opl) * opl
    bb[c("xmax", "ymax")] <- ceiling(bb[c("xmax", "ymax")] / opl) * opl
    url <- paste0(
      WCS_URL, "?service=WCS&version=1.0.0&request=GetCoverage",
      "&coverage=nhm_dtm_topo_25833&crs=EPSG:25833&format=GeoTIFF",
      "&bbox=", paste(bb[c("xmin", "ymin", "xmax", "ymax")], collapse = ","),
      "&width=", (bb["xmax"] - bb["xmin"]) / opl,
      "&height=", (bb["ymax"] - bb["ymin"]) / opl
    )
    message("Henter højdedata for ", fjord, " (", opl, " m) ...")
    download.file(url, fil, mode = "wb", quiet = TRUE)
  }
  dtm <- terra::rast(fil)
  # Havet ligger omkring 0 m; små negative værdier sættes til 0, så vandfladen bliver plan
  terra::ifel(is.na(dtm) | dtm < 0, 0, dtm)
}
