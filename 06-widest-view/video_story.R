# =============================================================================
# Story and video
# -----------------------------------------------------------------------------
# Builds the on-screen text from the analysis results and renders the video.
# Nothing in the text is typed by hand: names, heights, areas and distances
# all come from the data, so a re-run can never leave stale numbers on screen.
# Expects `final`, `refs` and `screen` from run.R.
# =============================================================================

winner <- final[1, ]
galdh  <- refs[1, ]
ratio  <- winner$area_100m / galdh$area_100m
key    <- paste0("peak_", winner$osm_id)
xy     <- sf::st_coordinates(winner)[1, ]

# Hook ----------------------------------------------------------------------------
# paste0() rather than sprintf(): sprintf() converts to the session's native
# encoding, which can mangle the multiplication sign outside UTF-8.
hook <- c(
  "Norway's widest view isn't from its highest summit.",
  paste0("From ", winner$name, " (", format(winner$ele, big.mark = ","), " m) you see ",
         format(round(ratio, 1), nsmall = 1), "\u00d7 as much land"),
  paste0("as from ", galdh$name, " (", format(galdh$ele, big.mark = ","), " m), the highest.")
)

# Furthest visible land and the nearest named summit to it -------------------------
visible100 <- terra::rast(path_proc(sprintf("visible_%s_100m.tif", key)))
dist100    <- terra::distance(terra::rast(visible100), terra::vect(rbind(xy), crs = GRID_CRS))
far_cell   <- terra::where.max(terra::ifel(visible100, dist100, NA))[1, 2]
far_xy     <- terra::xyFromCell(visible100, far_cell)
far_pt     <- sf::st_sfc(sf::st_point(far_xy[1, ]), crs = GRID_CRS)
far_ele    <- terra::extract(get_elevation(RANK_RES)$dem, far_xy)[1, 1]

# All named OSM summits, in any country, with the country they lie in. The
# furthest point and the landmarks may be across the border, and the label says so.
all_peaks <- get_osm_peaks() |>
  dplyr::mutate(ele = readr::parse_number(ele, locale = readr::locale(decimal_mark = ".", grouping_mark = ","))) |>
  dplyr::filter(!is.na(ele)) |>
  sf::st_transform(GRID_CRS)
# Summits within 300 m of the border are labelled "on the border": the border
# datasets are generalised, and both countries' polygons can contain such a
# summit (Storsylen is 69 m from the line and inside both).
in_country <- function(pts, boundary) !is.na(terra::extract(boundary, terra::vect(pts))[, 2])
border_line <- terra::as.lines(norway_boundary()) |>
  terra::intersect(terra::buffer(terra::simplifyGeom(sweden_boundary(), 500), 3000))
near_border <- function(pts) {
  near <- terra::nearby(terra::vect(pts), border_line, distance = 300)
  seq_len(nrow(pts)) %in% near[, 1]
}
all_peaks <- all_peaks |>
  dplyr::filter(name %in% c("Sn\u00f8hetta", "Rondslottet", "Storsylen") |
                  as.numeric(sf::st_distance(geometry, far_pt)) < 20000)
all_peaks$country <- dplyr::case_when(
  near_border(all_peaks) ~ "border",
  in_country(all_peaks, norway_boundary()) ~ "Norway",
  in_country(all_peaks, sweden_boundary()) ~ "Sweden",
  TRUE ~ "other"
)
country_tag <- function(country) dplyr::case_when(country == "Norway" ~ "", country == "border" ~ ", on the border",
                                                   TRUE ~ paste0(", ", country))

nearest  <- all_peaks[which.min(sf::st_distance(all_peaks, far_pt)), ]
furthest <- list(
  x = far_xy[1, 1], y = far_xy[1, 2], ele = far_ele,
  dist_km = terra::values(dist100)[far_cell] / 1000,
  near = paste0(nearest$name, " (", format(nearest$ele, big.mark = ","), " m", country_tag(nearest$country), ")")
)

# Landmarks: well-known summits that are actually visible from the winner ---------
# Checked against the 100 m viewshed (terrain of any kind, any country), so a
# label never claims a view that the analysis does not support.
viewshed100 <- terra::rast(path_proc(sprintf("viewshed_%s_100m.tif", key)))
landmark_names <- c("Sn\u00f8hetta", "Rondslottet", "Storsylen")
landmarks <- all_peaks |>
  dplyr::filter(name %in% landmark_names) |>
  dplyr::group_by(name) |> dplyr::slice_max(ele, n = 1, with_ties = FALSE) |> dplyr::ungroup() |>
  dplyr::mutate(
    visible = terra::extract(viewshed100, terra::vect(geometry))[, 2] == 1,
    dist_km = as.numeric(sf::st_distance(geometry, sf::st_geometry(winner))) / 1000
  ) |>
  dplyr::filter(visible %in% TRUE)
landmarks <- dplyr::bind_cols(sf::st_drop_geometry(landmarks), tibble::as_tibble(sf::st_coordinates(landmarks))) |>
  dplyr::rename(x = X, y = Y)
message("Landmarks in view: ", paste0(landmarks$name, " (", landmarks$country, ") ", round(landmarks$dist_km), " km", collapse = ", "))

# End panel -----------------------------------------------------------------------
# The 100 m top 5, plus the highest summit for context (no rank, since its rank
# comes from the 500 m screening; see the README)
ranking <- dplyr::bind_rows(
  sf::st_drop_geometry(final) |>
    dplyr::transmute(rank = dplyr::row_number(), name, ele, area_km2 = area_100m, highlight = rank == 1),
  sf::st_drop_geometry(galdh) |>
    dplyr::transmute(rank = NA_integer_, name = paste0(name, " (highest)"), ele, area_km2 = area_100m, highlight = FALSE)
)

# Guard and render ----------------------------------------------------------------
# Every revealed visible cell must be inside the frame in every part of the video
scene <- build_scene(winner, key)
coverage <- check_frame_coverage(scene)
if (coverage >= 0.001) stop("Part of the revealed land falls outside the frame; adjust camera_at().")
labelled <- dplyr::bind_rows(
  tibble::tibble(x = xy[1], y = xy[2], ele = winner$ele),
  tibble::tibble(x = furthest$x, y = furthest$y, ele = furthest$ele),
  dplyr::select(landmarks, x, y, ele)
)
if (!check_points_in_frame(scene, labelled)) stop("A labelled point is too close to the frame edge; adjust camera_at().")
if (!check_orientation(scene, labelled[-1, ], summit = labelled[1, ])) stop("The final view is not north-up; adjust camera_at().")

make_video(winner, ranking, hook, landmarks, furthest)
