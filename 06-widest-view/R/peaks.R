# =============================================================================
# Candidate summits
# -----------------------------------------------------------------------------
# Source: OpenStreetMap, every node tagged natural=peak with a name and an
# elevation (ele) inside mainland Norway. OSM is used rather than detecting
# peaks in the DTM because it gives names, and a view is only meaningful from
# a place people can identify and walk to.
#
# Candidates are summits at or above MIN_ELEVATION. Lower summits can have wide
# sea views, but this project counts land, and below ~1000 m the horizon over
# land is short.
# =============================================================================

MIN_ELEVATION <- 1000
NORWAY_BBOX   <- c(4.0, 57.8, 31.5, 71.3)   # lon/lat, mainland Norway only (no Svalbard)

OVERPASS_SERVERS <- c(
  "https://overpass-api.de/api/interpreter",
  "https://overpass.kumi.systems/api/interpreter"
)

#' Download named peaks with an elevation from OpenStreetMap
#'
#' The query asks Overpass to filter on name and ele server-side and to return
#' bare points, which keeps the response small. A plain natural=peak query for
#' all of Norway is large enough that the public servers throttle it.
get_osm_peaks <- function() {
  out <- path_raw("osm_peaks.rds")
  if (file.exists(out)) return(readRDS(out))

  bb <- NORWAY_BBOX
  query <- sprintf('[out:json][timeout:300];node["natural"="peak"]["name"]["ele"](%s,%s,%s,%s);out;',
                   bb[2], bb[1], bb[4], bb[3])

  json <- NULL
  for (server in OVERPASS_SERVERS) {
    message("Querying OpenStreetMap peaks via ", server)
    json <- tryCatch(
      httr2::request(server) |>
        httr2::req_body_form(data = query) |>
        httr2::req_retry(max_tries = 4, backoff = ~ 30) |>
        httr2::req_timeout(400) |>
        httr2::req_perform() |>
        httr2::resp_body_json(simplifyVector = TRUE),
      error = function(e) { message("  failed: ", conditionMessage(e)); NULL }
    )
    if (!is.null(json)) break
  }
  if (is.null(json)) stop("No Overpass server answered. Try again later.")

  pts <- tibble::tibble(
    osm_id = as.character(json$elements$id),
    name   = json$elements$tags$name,
    ele    = json$elements$tags$ele,
    lon    = json$elements$lon,
    lat    = json$elements$lat
  ) |>
    sf::st_as_sf(coords = c("lon", "lat"), crs = 4326)
  saveRDS(pts, out)
  pts
}

#' Clean candidate list on the analysis grid
#'
#' - keeps peaks with a name and a numeric elevation >= MIN_ELEVATION
#' - drops peaks outside Norwegian land (Swedish summits are terrain, not candidates)
#' - records the grid cell's elevation, because the summit itself is higher than
#'   the cell average; the difference is added to the observer height later
#'
#' @param elev Output of get_elevation() for the screening resolution.
candidate_peaks <- function(elev) {
  get_osm_peaks() |>
    dplyr::transmute(
      osm_id = osm_id,
      name   = name,
      # ele is free text in OSM ("2469", "2469 m", "2,469"); keep the number
      ele    = readr::parse_number(ele, locale = readr::locale(decimal_mark = ".", grouping_mark = ","))
    ) |>
    dplyr::filter(!is.na(name), !is.na(ele), ele >= MIN_ELEVATION, ele < 2500) |>
    sf::st_transform(GRID_CRS) |>
    dplyr::mutate(
      cell_ele = terra::extract(elev$dem, terra::vect(geometry))[, 2],
      norway   = terra::extract(elev$norway, terra::vect(geometry))[, 2] == 1
    ) |>
    dplyr::filter(norway %in% TRUE) |>
    dplyr::select(-norway)
}
