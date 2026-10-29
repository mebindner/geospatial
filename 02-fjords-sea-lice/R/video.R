# =============================================================================
# Video pipeline
# -----------------------------------------------------------------------------
# One function runs the whole project for one fjord and one year:
#   elevation -> lice counts -> terrain -> one rendered frame per video frame
#   -> annotation -> mp4 with ffmpeg
# =============================================================================

#' Render the sea lice video for one fjord
#'
#' @param fjord Name of an entry in `fjords`.
#' @param year Year of the lice export.
#' @param weeks Weeks to show. Stop one week before the latest data: the most
#'   recent week is usually still missing many farms' counts.
#' @param res_m Elevation cell size in metres.
#' @param zscale Vertical scale. At 100 m cells, zscale = 40 exaggerates the
#'   terrain 2.5×, which makes the fjord read clearly at video size. The source
#'   line on every frame states the exaggeration.
#' @param metres_per_louse Bar height per adult female louse, in terrain metres.
#' @param intro_s,weeks_s,hold_s Length of the three phases in seconds.
#' @param conclusion Two lines of text that fade in during the hold, with circles
#'   on the farms above the limit in the final week. Check the wording against
#'   the data before using it; the function prints which farms it circles.
#' @param fps,size Frame rate and square frame size in pixels.
#' @param only_frames Render just these frame numbers, for quick checks.
#' @param dir Project folder.
make_video <- function(fjord            = "sognefjord",
                       year             = 2026,
                       weeks            = 18:42,
                       res_m            = 100,
                       zscale           = 40,
                       metres_per_louse = 2500,
                       intro_s          = 5,
                       weeks_s          = 20,
                       hold_s           = 6,
                       conclusion       = NULL,
                       fps              = 25,
                       size             = 1080,
                       only_frames      = NULL,
                       dir              = PROJECT) {

  # Paths ---------------------------------------------------------------------------
  raw    <- file.path(dir, "data/raw")
  cache  <- file.path(dir, "data/processed")
  out    <- file.path(dir, "output")
  frames <- file.path(out, "frames", paste(fjord, year, sep = "_"))
  unlink(file.path(frames, "*.png"))
  dir.create(frames, recursive = TRUE, showWarnings = FALSE)

  # Data ----------------------------------------------------------------------------
  dtm     <- get_elevation(fjord, res_m, raw)
  lice    <- read_lice(fjord, year, raw) |> dplyr::filter(week %in% weeks)
  terrain <- build_terrain(dtm, zscale, fjord, res_m, cache)

  # Timeline ------------------------------------------------------------------------
  # The weeks run from the first to the last week in `weeks`, and the video ends
  # on the most recent week rather than the worst one: the point is "where things
  # stand now", and ending on a cherry-picked peak would overstate it.
  first_week <- min(weeks)
  last_week  <- max(weeks)
  n_intro <- intro_s * fps
  n_weeks <- weeks_s * fps
  n_hold  <- hold_s * fps
  n       <- n_intro + n_weeks + n_hold

  # Scene ---------------------------------------------------------------------------
  rayshader::plot_3d(terrain$texture, terrain$m, zscale = zscale, windowsize = c(size, size),
                     solid = TRUE, soliddepth = -60, solidcolor = BACKGROUND, solidlinecolor = BACKGROUND,
                     shadow = FALSE, background = BACKGROUND)

  # Frames --------------------------------------------------------------------------
  bar_ids <- integer(0)
  for (i in if (is.null(only_frames)) seq_len(n) else only_frames) {
    cam <- camera_at(i, n_intro, n_weeks)
    rayshader::render_camera(theta = cam$theta, phi = cam$phi, zoom = cam$zoom, fov = 30)

    # Bars are rebuilt every frame: remove last frame's, draw this frame's
    if (length(bar_ids)) rgl::pop3d(id = bar_ids)
    bar_ids <- integer(0)
    in_intro <- i <= n_intro
    in_hold  <- i > n_intro + n_weeks

    if (in_intro) {
      week <- first_week
    } else {
      week <- if (in_hold) last_week else first_week + (i - n_intro) / n_weeks * (last_week - first_week)
      farms <- lice_in_week(lice, week) |> dplyr::filter(!is.na(lice))
      if (nrow(farms) > 0) bar_ids <- draw_bars(farms, dtm, zscale, metres_per_louse)
    }

    # Conclusion: locate the bar tops of farms above the limit on screen, fade in over 1 s
    concl <- NULL
    if (!is.null(conclusion) && in_hold) {
      over <- farms[farms$lice > farms$limit, ]
      p <- scene_xz(over, dtm)
      concl <- list(text   = conclusion,
                    points = rgl::rgl.user2window(p$x, bar_height(over$lice, zscale, metres_per_louse), p$z),
                    alpha  = min((i - n_intro - n_weeks) / fps, 1))
      if (i == n_intro + n_weeks + 1) {
        message("Above the limit in week ", last_week, ": ", paste(over$name, collapse = ", "))
      }
    }

    file <- file.path(frames, sprintf("f%04d.png", i))
    rayshader::render_snapshot(file)
    # The bars glide between weeks, but the number on screen is always the exact
    # reported average for the week shown in the counter, never an interpolated value.
    shown_week <- round(week)
    avg <- if (in_intro) NA else mean(lice$lice[lice$week == shown_week], na.rm = TRUE)
    annotate_frame(file, fjord_labels[[fjord]], year, shown_week, avg, !in_intro, size, concl)
    message(sprintf("frame %d/%d", i, n))
  }
  rgl::close3d()

  # Encode --------------------------------------------------------------------------
  # yuv420p and H.264 are what LinkedIn and most players expect; crf 18 is
  # visually lossless at this size.
  if (is.null(only_frames)) {
    video <- file.path(out, sprintf("%s_%d.mp4", fjord, year))
    system2("ffmpeg", c("-y", "-framerate", fps, "-i", shQuote(file.path(frames, "f%04d.png")),
                        "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18", shQuote(video)))
    file.copy(file.path(frames, sprintf("f%04d.png", n)),
              file.path(out, sprintf("%s_%d_final.png", fjord, year)), overwrite = TRUE)
    message("Video: ", video)
  }
}
