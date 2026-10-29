# =============================================================================
# 3D scene: terrain, bars and camera
# -----------------------------------------------------------------------------
# rayshader builds the terrain; the bars are drawn directly with rgl on top of
# it. Everything in this file works in rayshader's scene coordinates:
#   x = column offset from the centre of the elevation grid
#   z = row offset from the centre (north is negative)
#   y = elevation in metres / zscale
# =============================================================================

# Colour scale --------------------------------------------------------------------
# Teal to dark red, saturating at 1 adult female louse per fish. The scale is
# deliberately not centred on the legal limit (0.5, or 0.2 in spring): the limit
# changes during the year, and a fixed scale keeps colours comparable across weeks.
lice_palette <- grDevices::colorRampPalette(c("#2a9d8f", "#e9c46a", "#e76f51", "#9b2226"))(101)

lice_colour <- function(lice, max_lice = 1) {
  lice_palette[round(pmin(lice / max_lice, 1) * 100) + 1]
}

# Terrain -------------------------------------------------------------------------

#' Build (or reuse) the shaded terrain texture
#'
#' Shadows are the slow part (ray tracing over the whole grid), so the finished
#' texture is cached. The cache name includes zscale and the area fingerprint,
#' because both change how the shadows fall.
#'
#' @return list(m = elevation matrix, texture = RGB array)
build_terrain <- function(dtm, zscale, fjord, res_m, dir) {
  file <- file.path(dir, sprintf("texture_%s_%dm_z%d_%s.rds", fjord, res_m, zscale, area_key(fjord)))
  m <- rayshader::raster_to_matrix(dtm)
  if (file.exists(file)) return(list(m = m, texture = readRDS(file)))

  land <- grDevices::colorRampPalette(c("#5b7553", "#8c9a73", "#b8b39b", "#e8e4dc", "#ffffff"))(256)
  texture <- rayshader::height_shade(m, texture = land)

  # Water is painted onto the texture by hand. height_shade() returns the image
  # transposed relative to the elevation matrix, and add_water() misplaces a
  # logical mask in rayshader 0.41, so using t(m == 0) directly is the reliable route.
  water <- t(m == 0)
  water_rgb <- grDevices::col2rgb("#1d3d52") / 255
  for (k in 1:3) texture[, , k][water] <- water_rgb[k]

  # Light from the south-west, low sun: long shadows make the fjord walls read
  # as steep even at 100 m resolution.
  texture <- texture |>
    rayshader::add_shadow(rayshader::lamb_shade(m, zscale = zscale, sunaltitude = 35, sunangle = 225), 0.3) |>
    rayshader::add_shadow(rayshader::ray_shade(m, zscale = zscale, sunaltitude = 25, sunangle = 225, multicore = TRUE), 0.4) |>
    rayshader::add_shadow(rayshader::ambient_shade(m, zscale = zscale, multicore = TRUE), 0)

  saveRDS(texture, file)
  list(m = m, texture = texture)
}

# Bars ----------------------------------------------------------------------------

#' Convert projected point coordinates to rayshader scene coordinates
scene_xz <- function(points, dtm) {
  e <- terra::ext(dtm)
  res_m <- terra::res(dtm)[1]
  xy <- sf::st_coordinates(points)
  list(x = (xy[, 1] - e$xmin) / res_m - terra::ncol(dtm) / 2,
       z = (e$ymax - xy[, 2]) / res_m - terra::nrow(dtm) / 2)
}

#' Bar height in scene units
#'
#' Capped at `max_lice` so a single extreme farm cannot dwarf the landscape.
#' A small minimum keeps farms with zero lice visible as a stub on the water.
bar_height <- function(lice, zscale, metres_per_louse, max_lice = 2) {
  pmax(pmin(lice, max_lice), 0.02) * metres_per_louse / zscale
}

#' Draw one bar per farm and return the rgl ids, so they can be removed next frame
#'
#' Drawn with rgl rather than rayshader::render_polygons(), because
#' render_polygons() ignores data_column_top in rayshader 0.41 and draws flat tiles.
draw_bars <- function(farms, dtm, zscale, metres_per_louse, half_width_m = 350) {
  p <- scene_xz(farms, dtm)
  h <- bar_height(farms$lice, zscale, metres_per_louse)
  b <- half_width_m / terra::res(dtm)[1]
  ids <- integer(0)
  for (j in seq_len(nrow(farms))) {
    box <- rgl::cube3d(color = lice_colour(farms$lice[j]), lit = TRUE, specular = "black") |>
      rgl::scale3d(b, h[j] / 2, b) |>
      rgl::translate3d(p$x[j], h[j] / 2, p$z[j])
    ids <- c(ids, rgl::shade3d(box))
  }
  ids
}

# Camera --------------------------------------------------------------------------

#' Camera position for frame i
#'
#' Three phases:
#'   intro  - eases from a high, top-down view to a low oblique view (no bars yet)
#'   weeks  - slow rotation while the weeks run
#'   hold   - camera stops so the final week can be read
#' The final zoom (0.78) keeps the whole terrain block, and therefore every farm
#' included in the averages, inside the frame. check_visibility() tests this.
camera_at <- function(i, n_intro, n_weeks) {
  t_intro <- min(i / n_intro, 1)
  ease    <- (1 - cos(pi * t_intro)) / 2
  t_turn  <- max(0, min((i - n_intro) / n_weeks, 1))
  list(
    theta = -30 + 25 * ease + 20 * t_turn,
    phi   = 70 - 38 * ease,
    zoom  = 0.95 - 0.14 * ease - 0.03 * t_turn
  )
}
