# =============================================================================
# Video: the visible land lights up outwards from the winning summit
# -----------------------------------------------------------------------------
# Timeline (about 18 s, built for LinkedIn where most viewers leave early):
#   0-2 s   close and low over the summit, hook already on screen
#   2-11 s  reveal: a ring moves outwards, visible land glows gold, the camera
#           pulls up and back at the same pace, landmarks appear as the ring
#           reaches them, and a sight line marks the furthest land in view
#   11-18 s hold on the full result; the ranking panel fades in
#
# Format 4:5 (1080 x 1350): the 3D scene is square and the text lives in bands
# above and below it, so nothing covers the landscape.
# =============================================================================

VIDEO_W  <- 1080
VIDEO_H  <- 1350
SCENE_Y0 <- 70      # top of the square scene on the 4:5 canvas; the hook sits on a
                    # gradient over the scene's empty sky

#' Reveal progress (0-1) for frame i: eases in and out so the ring starts and lands gently
reveal_progress <- function(i, n_intro, n_reveal) {
  t <- min(max((i - n_intro) / n_reveal, 0), 1)
  (1 - cos(pi * t)) / 2
}

#' Camera for frame i
#'
#' Starts low and close over the summit (the scene is centred on it, so the
#' orbit centre is the summit) and pulls up and out in step with the reveal, so
#' the revealed land always fits the frame. check_frame_coverage() verifies this.
#'
#' The camera looks from the south, so the map reads north-up with east to the
#' right, as on any ordinary map and on the locator. It turns gently into that
#' position during the reveal and stays there for the hold, where the labels
#' are read. (An earlier version looked from ~200 degrees, which put south at
#' the top; positions were right relative to each other but read as wrong.)
camera_at <- function(i, n_intro, n_reveal, n) {
  p <- reveal_progress(i, n_intro, n_reveal)
  list(theta = -12 * (1 - p),
       phi   = 16 + 20 * p,
       zoom  = 0.18 + 0.56 * p,
       fov   = 45 - 10 * p)
}

#' Render the video for the winning summit
#'
#' @param winner One row of the stage 3 result.
#' @param ranking Tibble for the end panel (see annotate_frame()).
#' @param hook Up to three text lines shown from the first frame.
#' @param landmarks Tibble (name, x, y, ele, dist_km) of named summits in view,
#'   labelled when the ring reaches them.
#' @param furthest list(x, y, ele, dist_km, near) for the sight line.
#' @param exaggeration Vertical exaggeration of the terrain (stated on screen).
#' @param only_frames Frame numbers to render for a quick check.
#' @param resume Keep frames already on disk and render only the missing ones,
#'   so an interrupted render can continue instead of starting over.
make_video <- function(winner, ranking, hook, landmarks, furthest, exaggeration = 4,
                       intro_s = 2, reveal_s = 9, hold_s = 7, fps = 25,
                       only_frames = NULL, resume = FALSE) {
  key   <- paste0("peak_", winner$osm_id)
  scene <- build_scene(winner, key)
  zscale <- scene$res_m / exaggeration
  base  <- base_texture(scene, zscale)
  locator <- make_locator(scene$xy)

  frames <- path_out("frames"); dir.create(frames, recursive = TRUE, showWarnings = FALSE)
  if (is.null(only_frames) && !resume) unlink(file.path(frames, "*.png"))

  n_intro <- intro_s * fps; n_reveal <- reveal_s * fps; n_hold <- hold_s * fps
  n <- n_intro + n_reveal + n_hold
  max_radius <- max(scene$dist[scene$frac > 0])
  final_area <- winner$area_100m

  # Points of interest in scene coordinates (y = height in scene units)
  to_scene <- function(x, y, ele) { p <- scene_point(scene, x, y); c(p[["x"]], ele / zscale, p[["z"]]) }
  summit3d   <- to_scene(scene$xy[1], scene$xy[2], winner$ele)
  furthest3d <- to_scene(furthest$x, furthest$y, furthest$ele)
  marks3d    <- purrr::pmap(landmarks[, c("x", "y", "ele")], to_scene)

  frame_list <- if (is.null(only_frames)) seq_len(n) else only_frames
  if (resume) frame_list <- frame_list[!file.exists(file.path(frames, sprintf("f%04d.png", frame_list)))]
  for (i in frame_list) {
    p <- reveal_progress(i, n_intro, n_reveal)
    radius  <- max_radius * p
    in_hold <- i > n_intro + n_reveal

    tex <- reveal_texture(base, scene, radius, ring = !in_hold && radius > 0)
    rayshader::plot_3d(tex, scene$m, zscale = zscale, windowsize = c(VIDEO_W, VIDEO_W),
                       solid = TRUE, soliddepth = -40, solidcolor = BACKGROUND, solidlinecolor = BACKGROUND,
                       shadow = FALSE, background = BACKGROUND)
    cam <- camera_at(i, n_intro, n_reveal, n)
    rayshader::render_camera(theta = cam$theta, phi = cam$phi, zoom = cam$zoom, fov = cam$fov)

    # Window positions (0-1, y up) of everything labelled in 2D
    win <- function(v) rgl::rgl.user2window(v[1], v[2], v[3])[1, 1:2]
    summit <- list(label = paste0(winner$name, "  ", format(winner$ele, big.mark = ","), " m"), pos = win(summit3d))
    marks <- purrr::map2(marks3d, seq_len(nrow(landmarks)), function(v, k) {
      country <- switch(landmarks$country[k], Norway = "", border = " (on the border)",
                        paste0(" (", landmarks$country[k], ")"))
      list(label = paste0(landmarks$name[k], country, "  ", round(landmarks$dist_km[k]), " km"),
           pos = win(v), alpha = min(max((radius - landmarks$dist_km[k]) / 15, 0), 1))
    })
    # Sight line appears once the ring has reached the furthest land, fades in over 1 s
    sight <- list(from = summit$pos, to = win(furthest3d),
                  label = paste0("Furthest land in sight: ", round(furthest$dist_km), " km"),
                  sublabel = paste0("near ", furthest$near),
                  alpha = if (in_hold) min((i - n_intro - n_reveal) / fps, 1) else 0)

    # Area revealed so far, in total and in Sweden; at the end exactly the 100 m result
    ab  <- scene$area_by_dist
    idx <- if (in_hold) nrow(ab) else findInterval(radius, ab$dist)
    area     <- if (idx == 0) 0 else ab$cum_area[idx] * final_area / max(ab$cum_area)
    area_swe <- if (idx == 0) 0 else ab$cum_area_swe[idx] * final_area / max(ab$cum_area)

    file <- file.path(frames, sprintf("f%04d.png", i))
    rayshader::render_snapshot(file)
    annotate_frame(file, hook, area, area_swe, if (in_hold || radius == 0) NULL else radius,
                   summit, marks, sight, ranking,
                   panel_alpha = if (in_hold) min((i - n_intro - n_reveal - fps) / fps, 1) else 0,
                   exaggeration = exaggeration, locator = locator)
    message(sprintf("frame %d/%d", i, n))
    # Each frame builds a new scene; closing it frees the memory. Without this
    # the session grew to ~10 GB and the render slowed to a crawl in swap.
    rgl::close3d()
    gc(verbose = FALSE)
  }

  if (is.null(only_frames)) {
    video <- path_out("widest_view.mp4")
    system2("ffmpeg", c("-y", "-loglevel", "error", "-framerate", fps, "-i", shQuote(file.path(frames, "f%04d.png")),
                        "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18", shQuote(video)))
    file.copy(file.path(frames, sprintf("f%04d.png", n)), path_out("widest_view_final.png"), overwrite = TRUE)
    message("Video: ", video)
  }
}
