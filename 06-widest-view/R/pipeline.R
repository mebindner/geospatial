# =============================================================================
# Analysis pipeline
# -----------------------------------------------------------------------------
# Three stages, each refining the previous one:
#   1. screen  - every candidate summit at 500 m
#   2. rank    - the best distinct summits again at 200 m
#   3. final   - the top few at 100 m, to see whether the numbers have converged
# Each stage saves its result, so a later stage can be re-run on its own.
#
# Ranking metric: visible land in any country (area_km2). The Norwegian share
# (area_norway_km2) is carried along for the story and the video.
# =============================================================================

#' Stage 1: score every candidate at the screening resolution
run_screening <- function() {
  out <- path_proc("stage1_screen_500m.rds")
  if (file.exists(out)) return(readRDS(out))

  elev  <- get_elevation(SCREEN_RES)
  peaks <- candidate_peaks(elev) |> flag_bad_elevations()
  message(sprintf("Screening %d summits (%d excluded for implausible OSM elevation)",
                  sum(peaks$ele_ok), sum(!peaks$ele_ok)))

  scored <- peaks |>
    dplyr::filter(ele_ok) |>
    score_peaks(SCREEN_RES)
  saveRDS(scored, out)
  scored
}

#' Stage 2: re-rank the best distinct summits at 200 m
#'
#' @param n Number of distinct summits carried over from the screening.
run_ranking <- function(screen, n = 40) {
  out <- path_proc("stage2_rank_200m.rds")
  if (file.exists(out)) return(readRDS(out))

  finalists <- distinct_summits(screen) |> dplyr::slice_max(area_km2, n = n)
  get_elevation(RANK_RES)
  ranked <- finalists |>
    dplyr::select(-area_km2, -area_norway_km2, -max_dist_km) |>
    score_peaks(RANK_RES) |>
    dplyr::arrange(dplyr::desc(area_km2))
  saveRDS(ranked, out)
  ranked
}

#' Stage 3: final numbers at 100 m for the top summits
#'
#' Each summit gets its own 100 m window (700 x 700 km). The terrain is
#' downloaded per window, because the whole country at 100 m is too large to
#' hold in memory on a laptop.
run_final <- function(ranked, n = 5) {
  out <- path_proc("stage3_final_100m.rds")
  if (file.exists(out)) return(readRDS(out))

  top <- dplyr::slice_max(ranked, area_km2, n = n)
  xy  <- sf::st_coordinates(top)
  final <- purrr::map(seq_len(nrow(top)), function(i) {
    key  <- paste0("peak_", top$osm_id[i])
    area <- terra::ext(xy[i, 1] - MAX_RANGE_M, xy[i, 1] + MAX_RANGE_M,
                       xy[i, 2] - MAX_RANGE_M, xy[i, 2] + MAX_RANGE_M) |>
      terra::intersect(GRID_EXTENT)
    elev <- get_elevation(FINAL_RES, area, key)
    r <- visible_land(xy[i, 1], xy[i, 2], top$ele[i], elev$dem, elev$land, elev$norway, keep_raster = TRUE)
    # Visible land (any country) drives the video; the raw viewshed is kept to
    # check landmarks, which may be summits outside Norway
    terra::writeRaster(r$seen, path_proc(sprintf("visible_%s_100m.tif", key)), overwrite = TRUE)
    terra::writeRaster(r$viewshed, path_proc(sprintf("viewshed_%s_100m.tif", key)), overwrite = TRUE)
    message(sprintf("  %s: %.0f km2 at 100 m (%.0f km2 in Norway)", top$name[i], r$area_km2, r$area_norway_km2))
    tibble::tibble(osm_id = top$osm_id[i], area_100m = r$area_km2, area_norway_100m = r$area_norway_km2,
                   max_dist_100m = r$max_dist_km)
  }) |>
    purrr::list_rbind()

  result <- top |>
    dplyr::rename(area_200m = area_km2, area_norway_200m = area_norway_km2, max_dist_200m = max_dist_km) |>
    dplyr::left_join(final, by = "osm_id") |>
    dplyr::arrange(dplyr::desc(area_100m))
  saveRDS(result, out)
  result
}

#' Reference summits at 100 m, for fair comparisons in the story
#'
#' Comparing the winner's 100 m number with another summit's 500 m number would
#' mix resolutions. Reference summits are therefore computed with exactly the
#' same model as the winner. Their screening rank is kept for context.
#'
#' @param screen Stage 1 result (for the screening rank).
#' @param osm_ids Reference summits, e.g. Norway's highest (Galdhopiggen).
run_references <- function(screen, osm_ids = c(galdhopiggen = "26862903")) {
  out <- path_proc("references_100m.rds")
  if (file.exists(out)) return(readRDS(out))

  ranked_screen <- distinct_summits(screen) |>
    dplyr::mutate(screen_rank = dplyr::row_number())
  refs <- ranked_screen |> dplyr::filter(osm_id %in% osm_ids)
  xy <- sf::st_coordinates(refs)

  areas <- purrr::map(seq_len(nrow(refs)), function(i) {
    key  <- paste0("peak_", refs$osm_id[i])
    area <- terra::ext(xy[i, 1] - MAX_RANGE_M, xy[i, 1] + MAX_RANGE_M,
                       xy[i, 2] - MAX_RANGE_M, xy[i, 2] + MAX_RANGE_M) |>
      terra::intersect(GRID_EXTENT)
    elev <- get_elevation(FINAL_RES, area, key)
    r <- visible_land(xy[i, 1], xy[i, 2], refs$ele[i], elev$dem, elev$land, elev$norway)
    tibble::tibble(area_100m = r$area_km2, area_norway_100m = r$area_norway_km2)
  }) |>
    purrr::list_rbind()
  result <- dplyr::bind_cols(refs, areas) |> dplyr::mutate(n_screened = nrow(ranked_screen))
  saveRDS(result, out)
  result
}
