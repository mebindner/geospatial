# =============================================================================
# Video: the visible land lights up outwards from the winning summit
# -----------------------------------------------------------------------------
# Timeline (about 18 s, built for LinkedIn where most viewers leave early):
#   0-2 s   hook and winner on screen over the 3D landscape
#   2-11 s  reveal: a ring moves outwards and visible land glows gold;
#           the counter adds up the visible area
#   11-18 s hold on the full result; the ranking panel fades in
# =============================================================================

#' Camera for frame i: a slow orbit around the summit, the same in every phase
#' so the eye can follow the reveal without the view jumping.
camera_at <- function(i, n) {
  t <- (i - 1) / max(n - 1, 1)
  list(theta = 20 + 25 * t, phi = 38 - 4 * t, zoom = 0.62 - 0.04 * t)
}

#' Render the video for the winning summit
#'
#' @param winner One row of the stage 3 result.
#' @param ranking Tibble for the end panel (see annotate_frame()).
#' @param hook Two text lines shown from the first frame.
#' @param exaggeration Vertical exaggeration of the terrain (stated on screen).
#' @param only_frames Frame numbers to render for a quick check.
make_video <- function(winner, ranking, hook, exaggeration = 4,
                       intro_s = 2, reveal_s = 9, hold_s = 7, fps = 25, size = 1080,
                       only_frames = NULL) {
  key   <- paste0("peak_", winner$osm_id)
  scene <- build_scene(winner, key)
  zscale <- scene$res_m / exaggeration
  base  <- base_texture(scene, zscale)

  frames <- path_out("frames"); dir.create(frames, recursive = TRUE, showWarnings = FALSE)
  if (is.null(only_frames)) unlink(file.path(frames, "*.png"))

  n_intro <- intro_s * fps; n_reveal <- reveal_s * fps; n_hold <- hold_s * fps
  n <- n_intro + n_reveal + n_hold
  max_radius <- max(scene$dist[scene$frac > 0])
  final_area <- winner$area_100m

  # Summit marker in scene coordinates; the eye height is exaggerated with the terrain
  p  <- scene_point(scene, scene$xy[1], scene$xy[2])
  sy <- winner$ele / zscale

  frame_list <- if (is.null(only_frames)) seq_len(n) else only_frames
  for (i in frame_list) {
    # Reveal radius eases in and out so the ring starts and lands gently
    t <- min(max((i - n_intro) / n_reveal, 0), 1)
    radius <- max_radius * (1 - cos(pi * t)) / 2
    in_hold <- i > n_intro + n_reveal

    tex <- reveal_texture(base, scene, radius, ring = !in_hold && radius > 0)
    rayshader::plot_3d(tex, scene$m, zscale = zscale, windowsize = c(size, size),
                       solid = TRUE, soliddepth = -40, solidcolor = BACKGROUND, solidlinecolor = BACKGROUND,
                       shadow = FALSE, background = BACKGROUND)
    cam <- camera_at(i, n)
    rayshader::render_camera(theta = cam$theta, phi = cam$phi, zoom = cam$zoom, fov = 35)

    # Area revealed so far; at the end exactly the 100 m result
    area <- if (in_hold) final_area else {
      ab <- scene$area_by_dist
      idx <- findInterval(radius, ab$dist)
      if (idx == 0) 0 else ab$cum_area[idx] * final_area / max(ab$cum_area)
    }
    win <- rgl::rgl.user2window(p["x"], sy, p["z"])
    summit <- list(label = sprintf("%s  %s m", winner$name, format(winner$ele, big.mark = ",")),
                   px = win[1, 1], py = win[1, 2])

    file <- file.path(frames, sprintf("f%04d.png", i))
    rayshader::render_snapshot(file)
    annotate_frame(file, hook, area, if (in_hold || radius == 0) NULL else radius, summit, ranking,
                   panel_alpha = if (in_hold) min((i - n_intro - n_reveal) / fps, 1) else 0,
                   exaggeration = exaggeration, size = size)
    message(sprintf("frame %d/%d", i, n))
  }
  rgl::close3d()

  if (is.null(only_frames)) {
    video <- path_out("widest_view.mp4")
    system2("ffmpeg", c("-y", "-loglevel", "error", "-framerate", fps, "-i", shQuote(file.path(frames, "f%04d.png")),
                        "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18", shQuote(video)))
    file.copy(file.path(frames, sprintf("f%04d.png", n)), path_out("widest_view_final.png"), overwrite = TRUE)
    message("Video: ", video)
  }
}
