# =============================================================================
# Quality check: is every farm in the numbers also visible in the picture?
# -----------------------------------------------------------------------------
# The average shown on screen is computed over all farms in the bounding box.
# If the camera crops a farm out, the picture and the number disagree. This
# check projects every farm's bar (base and top) to screen coordinates for
# frames across the video and reports any that fall outside the frame or under
# the text areas (title, week counter, legend, source line).
#
# Run it before every full render. It takes seconds; a render takes ~20 minutes.
# =============================================================================

#' Report farms that are cropped or hidden in any checked frame
#'
#' Arguments mirror make_video() and must match it for the result to be valid.
#' @param every Check every n-th frame of the weeks and hold phases.
#' @return Invisibly, a data frame of problems (empty when everything is visible).
check_visibility <- function(fjord = "sognefjord", year = 2026, weeks = 18:42, res_m = 100, zscale = 40,
                             metres_per_louse = 2500, intro_s = 5, weeks_s = 20, hold_s = 6, fps = 25,
                             size = 1080, every = 10, dir = PROJECT) {
  dtm     <- get_elevation(fjord, res_m, file.path(dir, "data/raw"))
  lice    <- read_lice(fjord, year, file.path(dir, "data/raw")) |> dplyr::filter(week %in% weeks, !is.na(lice))
  terrain <- build_terrain(dtm, zscale, fjord, res_m, file.path(dir, "data/processed"))

  # Worst case per farm: its tallest bar over the period
  farms <- lice |> dplyr::group_by(farm, name) |> dplyr::summarise(max_lice = max(lice), .groups = "drop")
  p <- scene_xz(farms, dtm)
  h <- bar_height(farms$max_lice, zscale, metres_per_louse)

  rayshader::plot_3d(terrain$texture, terrain$m, zscale = zscale, windowsize = c(size, size), shadow = FALSE)
  n_intro <- intro_s * fps
  n_weeks <- weeks_s * fps
  n       <- n_intro + n_weeks + hold_s * fps

  # Free area in normalised image coordinates (y = 0 at the top)
  is_free <- function(px, py) px > 0.02 & px < 0.98 & py > 0.17 & py < 0.84

  problems <- list()
  for (i in seq(n_intro + 1, n, by = every)) {
    cam <- camera_at(i, n_intro, n_weeks)
    rayshader::render_camera(theta = cam$theta, phi = cam$phi, zoom = cam$zoom, fov = 30)
    base <- rgl::rgl.user2window(p$x, 0, p$z)
    top  <- rgl::rgl.user2window(p$x, h, p$z)
    ok <- is_free(base[, 1], 1 - base[, 2]) & is_free(top[, 1], 1 - top[, 2])
    if (any(!ok)) problems[[length(problems) + 1]] <- data.frame(frame = i, name = farms$name[!ok], max_lice = farms$max_lice[!ok])
  }
  rgl::close3d()

  res <- dplyr::bind_rows(problems)
  if (nrow(res) == 0) {
    message("All ", nrow(farms), " farms are visible in every checked frame.")
  } else {
    print(res |> dplyr::group_by(name, max_lice) |>
            dplyr::summarise(frames = dplyr::n(), first = min(frame), last = max(frame), .groups = "drop"))
  }
  invisible(res)
}
