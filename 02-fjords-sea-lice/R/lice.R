# =============================================================================
# Sea lice counts
# -----------------------------------------------------------------------------
# Source: BarentsWatch fish health bulk export (reporttype = lice), published
# by the Norwegian Food Safety Authority under NLOD. Farms report adult female
# lice per fish every week. These are reported counts, not model estimates.
#
# The CSV is the same file the lakselus project downloads
# (https://github.com/mebindner/lakselus). Column names in the export are
# Norwegian and are translated here, once.
# =============================================================================

#' Read weekly lice counts for the farms inside a fjord's bounding box
#'
#' @param fjord Name of an entry in `fjords`.
#' @param year Year of the export file `lusetal_<year>.csv`.
#' @param dir Folder with the raw export.
#' @return An `sf` point layer in EPSG:25833, one row per farm and week.
read_lice <- function(fjord, year = 2026, dir = "data/raw") {
  file <- file.path(dir, sprintf("lusetal_%d.csv", year))
  if (!file.exists(file)) {
    stop("Missing ", file, ". Copy it from lakselus/data/raw or download it from BarentsWatch.")
  }
  bb <- fjords[[fjord]]

  # guess_max is raised because municipality columns are empty for many rows
  # at the top of the file, which otherwise makes readr guess the wrong type.
  readr::read_csv(file, show_col_types = FALSE, guess_max = 1e5) |>
    dplyr::transmute(
      week   = Uke,
      farm   = Lokalitetsnummer,
      name   = Lokalitetsnavn,
      lice   = `Voksne hunnlus`,            # adult female lice per fish
      # 0.5, or 0.2 in spring weeks. A handful of rows say "Ukjent" (unknown); they become NA.
      limit  = as.numeric(dplyr::na_if(as.character(`Lusegrense uke`), "Ukjent")),
      lat    = Lat,
      lon    = Lon
    ) |>
    dplyr::filter(lon >= bb["xmin"], lon <= bb["xmax"], lat >= bb["ymin"], lat <= bb["ymax"]) |>
    sf::st_as_sf(coords = c("lon", "lat"), crs = 4326) |>
    sf::st_transform(25833)
}

#' Lice counts for a (possibly fractional) week
#'
#' The video shows many frames per week. Between two weekly counts the value is
#' interpolated linearly, so bars grow smoothly instead of jumping once a second.
#' Only farms with a count in the earlier week are returned; a farm that has no
#' count that week is left out rather than shown with an invented value.
#'
#' @param lice Output of `read_lice()`.
#' @param week Week number, e.g. 33.4.
lice_in_week <- function(lice, week) {
  w0 <- floor(week)
  w1 <- min(w0 + 1, max(lice$week))
  t  <- week - w0

  # .data$ makes it explicit that `week` is the column, not this function's argument
  this_week <- lice |> dplyr::filter(.data$week == w0)
  next_week <- lice |>
    sf::st_drop_geometry() |>
    dplyr::filter(.data$week == w1) |>
    dplyr::select(farm, lice_next = lice)

  this_week |>
    dplyr::left_join(next_week, by = "farm") |>
    dplyr::mutate(
      # If the farm has no count next week, hold its current value
      lice_next = dplyr::coalesce(lice_next, lice),
      lice      = (1 - t) * lice + t * lice_next
    ) |>
    dplyr::select(-lice_next)
}
