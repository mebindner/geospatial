# =============================================================================
# 3D scene for the winning summit
# -----------------------------------------------------------------------------
# The scene is everything the summit can see, plus a margin: terrain from the
# 200 m model, satellite imagery as texture, and a visibility layer from the
# 100 m analysis. Each video frame blends these into one texture, so the
# visible land can "light up" outwards from the summit.
#
# Orientation: rayshader wants the elevation as a matrix with x in rows
# (raster_to_matrix), but textures as image arrays with north in the first row.
# Both are produced from the same SpatRaster grid, so cells line up exactly.
# =============================================================================

SCENE_CELLS <- 1200      # longest side of the scene grid; enough detail at 1080 px video
GLOW        <- c(1.00, 0.80, 0.42)   # warm gold for visible land
RING        <- c(1.00, 0.95, 0.85)   # thin light ring at the current reveal distance

#' Scene grid around everything the summit can see
#'
#' The cell size is a whole multiple of 100 m, so aggregating the 100 m
#' visibility raster gives exact visible fractions and the area counter adds up
#' to the 100 m result.
scene_template <- function(visible, summit_xy, margin = 0.12) {
  seen <- terra::trim(terra::ifel(visible, 1, NA))
  e <- terra::ext(seen)
  # Square around the summit, large enough for the furthest visible cell
  half <- max(abs(c(e$xmin, e$xmax) - summit_xy[1]), abs(c(e$ymin, e$ymax) - summit_xy[2])) * (1 + margin)
  res_m <- ceiling(2 * half / SCENE_CELLS / 100) * 100
  half <- ceiling(half / res_m) * res_m
  terra::rast(terra::ext(summit_xy[1] - half, summit_xy[1] + half, summit_xy[2] - half, summit_xy[2] + half),
              resolution = res_m, crs = GRID_CRS)
}

#' All layers the video needs, on the scene grid
build_scene <- function(winner, key) {
  out <- path_proc(sprintf("scene_%s.rds", key))
  if (file.exists(out)) return(readRDS(out))

  xy <- sf::st_coordinates(winner)[1, ]
  visible100 <- terra::rast(path_proc(sprintf("visible_%s_100m.tif", key)))
  tmpl <- scene_template(visible100, xy)
  res_m <- terra::res(tmpl)[1]

  # Visible fraction per scene cell (0-1), exact aggregation from 100 m
  frac <- terra::extend(visible100, tmpl, fill = 0) |>
    terra::crop(tmpl) |>
    (\(r) terra::ifel(is.na(r), 0, r))() |>
    terra::aggregate(fact = res_m / 100, fun = "mean") |>
    terra::resample(tmpl, method = "near")

  dem  <- terra::resample(get_elevation(RANK_RES)$dem, tmpl, method = "average")
  dem  <- terra::ifel(is.na(dem), 0, dem)
  dist <- terra::distance(tmpl, terra::vect(rbind(xy), crs = GRID_CRS)) / 1000   # km
  img  <- get_imagery(tmpl, key)

  as_img <- function(r) terra::as.matrix(r, wide = TRUE)   # north in row 1
  scene <- list(
    # Plain numbers, not a SpatExtent: terra objects do not survive saveRDS()
    xy = xy, res_m = res_m, ext = as.vector(terra::ext(tmpl)),
    m = rayshader::raster_to_matrix(dem),
    frac = as_img(frac), dist = as_img(dist),
    rgb = terra::as.array(img)[, , 1:3],
    cell_km2 = (res_m / 1000)^2
  )
  # Area revealed within each distance, for the on-screen counter
  scene$area_by_dist <- tibble::tibble(dist = as.vector(scene$dist), area = as.vector(scene$frac) * scene$cell_km2) |>
    dplyr::arrange(dist) |>
    dplyr::mutate(cum_area = cumsum(area))

  saveRDS(scene, out)
  scene
}

#' Shaded base texture: satellite colours with relief shading
#'
#' A low sun from the north-west (the conventional cartographic light) plus
#' ambient occlusion gives the mountains depth without hiding the imagery.
base_texture <- function(scene, zscale) {
  tex <- scene$rgb
  tex[is.na(tex)] <- 0
  tex |>
    rayshader::add_shadow(rayshader::lamb_shade(scene$m, zscale = zscale, sunaltitude = 30, sunangle = 315), 0.45) |>
    rayshader::add_shadow(rayshader::ray_shade(scene$m, zscale = zscale, sunaltitude = 25, sunangle = 315, multicore = TRUE), 0.55) |>
    rayshader::add_shadow(rayshader::ambient_shade(scene$m, zscale = zscale, multicore = TRUE), 0.2)
}

#' Texture for one frame, with visible land revealed out to `radius_km`
#'
#' Inside the radius, visible land glows gold (by its visible fraction) and land
#' that cannot be seen is dimmed, so the contrast reads at a glance. Outside the
#' radius the landscape is untouched.
reveal_texture <- function(base, scene, radius_km, ring = TRUE, glow = 0.72, dim = 0.55) {
  inside <- scene$dist <= radius_km
  a <- glow * scene$frac * inside
  shade <- ifelse(inside & scene$frac < 0.5, dim, 1)
  tex <- base
  for (k in 1:3) tex[, , k] <- (base[, , k] * shade) * (1 - a) + GLOW[k] * a
  if (ring && radius_km > 0) {
    on_ring <- abs(scene$dist - radius_km) < scene$res_m / 1000 * 0.9
    for (k in 1:3) tex[, , k][on_ring] <- 0.4 * tex[, , k][on_ring] + 0.6 * RING[k]
  }
  pmin(pmax(tex, 0), 1)
}

#' Scene coordinates of a projected point (see the fjord project for the convention)
scene_point <- function(scene, x, y) {
  # unname(): coordinates from st_coordinates() carry names (X, Y) that would
  # otherwise turn into x.X / z.Y and break lookups by name
  c(x = unname((x - scene$ext[["xmin"]]) / scene$res_m - nrow(scene$m) / 2),
    z = unname((scene$ext[["ymax"]] - y) / scene$res_m - ncol(scene$m) / 2))
}
