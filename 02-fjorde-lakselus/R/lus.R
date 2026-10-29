# Ugentlige lusetal pr. lokalitet fra BarentsWatch (bulk-eksporten, samme fil som Lakselus-projektet bruger).
# Kolonnenavnene er norske i eksporten; de oversættes her.

hent_lus <- function(fjord, aar = 2025, mappe = "data/raw") {
  fil <- file.path(mappe, sprintf("lusetal_%d.csv", aar))
  if (!file.exists(fil)) {
    stop("Mangler ", fil, ". Kopiér den fra Lakselus/data/raw eller hent den fra BarentsWatch.")
  }
  bb <- fjorde[[fjord]]
  readr::read_csv(fil, show_col_types = FALSE, guess_max = 1e5) |>
    dplyr::transmute(
      uge       = Uke,
      lok       = Lokalitetsnummer,
      navn      = Lokalitetsnavn,
      hunnlus   = `Voksne hunnlus`,
      graense   = `Lusegrense uke`,
      lat       = Lat,
      lon       = Lon
    ) |>
    dplyr::filter(lon >= bb["xmin"], lon <= bb["xmax"], lat >= bb["ymin"], lat <= bb["ymax"]) |>
    sf::st_as_sf(coords = c("lon", "lat"), crs = 4326) |>
    sf::st_transform(25833)
}

# Én række pr. lokalitet med lusetal for en (evt. brøkdels-) uge.
# Mellem to uger interpoleres lineært, så søjlerne vokser jævnt i videoen.
# Lokaliteter uden tælling den uge får NA og vises ikke.
lus_i_uge <- function(lus, uge) {
  u0 <- floor(uge)
  u1 <- min(u0 + 1, max(lus$uge))
  w  <- uge - u0
  a <- lus |> dplyr::filter(uge == u0)
  b <- lus |> sf::st_drop_geometry() |> dplyr::filter(uge == u1) |> dplyr::select(lok, hunnlus_naeste = hunnlus)
  a |>
    dplyr::left_join(b, by = "lok") |>
    dplyr::mutate(
      hunnlus_naeste = dplyr::coalesce(hunnlus_naeste, hunnlus),
      hunnlus = (1 - w) * hunnlus + w * hunnlus_naeste
    ) |>
    dplyr::select(-hunnlus_naeste)
}
