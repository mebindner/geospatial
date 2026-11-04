# =============================================================================
# Frame annotation
# -----------------------------------------------------------------------------
# Text is drawn onto each rendered frame with magick, so it stays sharp and
# fixed while the camera moves. The 4:5 canvas has three zones:
#   top band     hook (on screen from the very first frame)
#   square scene summit label, landmarks, sight line, end panel
#   bottom band  counter, legend, sources
# =============================================================================

BACKGROUND <- "#0b1218"
TEXT_MAIN  <- "white"
TEXT_SOFT  <- "#d3d9de"
TEXT_FAINT <- "#9aa5ae"
GOLD       <- "#ffcc6b"
SWEDEN_BLUE <- "#8fd1ff"
FONT       <- "Helvetica"

#' Source lines for the bottom of every frame; the exaggeration is passed in so
#' the stated value always matches the one used to render.
source_lines <- function(exaggeration) c(
  "Terrain: Kartverket DTM, Copernicus DEM GLO-90. Summits: OpenStreetMap. Borders: geoBoundaries. Imagery: Sentinel-2 cloudless 2016 (EOX).",
  paste0("Line of sight from 1.7 m above each summit, with Earth curvature and refraction, 100 m terrain model. ",
         "Terrain exaggerated ", exaggeration, "\u00d7.")
)

#' Write all text layers onto one rendered frame
#'
#' @param file PNG from render_snapshot() (square); overwritten with the 4:5 frame.
#' @param hook Up to three lines shown from the first frame.
#' @param area_km2 Visible land revealed so far (any country).
#' @param area_swe_km2 The part of it that lies in Sweden.
#' @param radius_km Current reveal distance (NULL hides it).
#' @param summit list(label, pos) with pos = window position c(x, y), 0-1, y up.
#' @param marks List of landmarks: list(label, pos, alpha).
#' @param sight list(from, to, label, sublabel, alpha) for the sight line.
#' @param ranking Tibble (rank, name, ele, area_km2, highlight) for the end panel.
#' @param panel_alpha 0-1, fade of the end panel.
#' @param exaggeration Vertical exaggeration used in the render, for the source line.
#' @param locator Path to the locator map PNG (see make_locator()), or NULL.
annotate_frame <- function(file, hook, area_km2, area_swe_km2, radius_km, summit, marks, sight, ranking,
                           panel_alpha, exaggeration, locator = NULL) {
  shot <- magick::image_read(file)
  sw <- magick::image_info(shot)$width
  sh <- magick::image_info(shot)$height   # can be a few px short of square (screen limit)

  # Place the square scene on the 4:5 canvas
  img <- magick::image_blank(VIDEO_W, VIDEO_H, BACKGROUND) |>
    magick::image_composite(shot, offset = sprintf("+0+%d", SCENE_Y0))
  # Window position (0-1, y up) -> canvas pixels
  to_px <- function(pos) c(pos[1] * sw, SCENE_Y0 + (1 - pos[2]) * sh)

  label <- function(img, text, px, py, pt, colour, ...) {
    magick::image_annotate(img, text, size = pt, color = colour, font = FONT,
                           location = sprintf("+%d+%d", round(px), round(py)), ...)
  }

  # Sight line to the furthest visible land (drawn first, under the labels)
  img <- magick::image_draw(img)
  if (sight$alpha > 0) {
    a <- sight$alpha; f <- to_px(sight$from); t <- to_px(sight$to)
    graphics::segments(f[1], f[2], t[1], t[2], col = grDevices::adjustcolor(GOLD, alpha.f = 0.9 * a), lwd = 2.5)
    graphics::symbols(t[1], t[2], circles = 6, inches = FALSE, add = TRUE,
                      fg = grDevices::adjustcolor("white", alpha.f = a), bg = grDevices::adjustcolor(GOLD, alpha.f = a), lwd = 2)
  }
  # Landmark dots
  for (m in marks) if (m$alpha > 0) {
    p <- to_px(m$pos)
    graphics::symbols(p[1], p[2], circles = 4, inches = FALSE, add = TRUE,
                      fg = grDevices::adjustcolor("white", alpha.f = m$alpha), lwd = 1.5)
  }
  # Summit marker with a short leader line
  s <- to_px(summit$pos)
  graphics::segments(s[1], s[2] - 6, s[1], s[2] - 60, col = TEXT_MAIN, lwd = 1.5)
  graphics::symbols(s[1], s[2], circles = 7, inches = FALSE, add = TRUE, fg = TEXT_MAIN, bg = GOLD, lwd = 2)
  grDevices::dev.off()

  # Labels on dark boxes so they read on top of the gold
  box <- "#0b1218B0"
  img <- magick::image_annotate(img, paste0(" ", summit$label, " "), size = 24, color = TEXT_MAIN, font = FONT,
                                weight = 700, boxcolor = box, location = sprintf("+%d+%d", round(s[1] + 8), round(s[2] - 86)))
  # Labels sit right of their point, or left of it in the right half of the
  # frame, so they never run off the edge
  side_label <- function(img, text, p, dy, ...) {
    if (p[1] < VIDEO_W * 0.55) {
      magick::image_annotate(img, text, font = FONT, ...,
                             location = sprintf("+%d+%d", round(p[1] + 10), round(p[2] + dy)))
    } else {
      magick::image_annotate(img, text, font = FONT, gravity = "northeast", ...,
                             location = sprintf("+%d+%d", round(VIDEO_W - p[1] + 10), round(p[2] + dy)))
    }
  }
  for (m in marks) if (m$alpha > 0) {
    img <- side_label(img, paste0(" ", m$label, " "), to_px(m$pos), -10, size = 17,
                      color = grDevices::adjustcolor(TEXT_SOFT, alpha.f = m$alpha),
                      boxcolor = grDevices::adjustcolor(BACKGROUND, alpha.f = 0.6 * m$alpha))
  }
  if (sight$alpha > 0) {
    t <- to_px(sight$to); a <- sight$alpha
    img <- side_label(img, paste0(" ", sight$label, " "), t, -34, size = 19, weight = 700,
                      color = grDevices::adjustcolor(GOLD, alpha.f = a),
                      boxcolor = grDevices::adjustcolor(BACKGROUND, alpha.f = 0.7 * a))
    img <- side_label(img, paste0(" ", sight$sublabel, " "), t, -10, size = 16,
                      color = grDevices::adjustcolor(TEXT_SOFT, alpha.f = a),
                      boxcolor = grDevices::adjustcolor(BACKGROUND, alpha.f = 0.7 * a))
  }

  # Top band: hook on a dark gradient, so it reads even when the close-up
  # landscape fills the top of the frame in the first seconds
  fade <- magick::image_read(grDevices::as.raster(matrix(
    grDevices::adjustcolor(BACKGROUND, alpha.f = 1)[1] |>
      (\(col) grDevices::colorRampPalette(c(col, grDevices::adjustcolor(col, alpha.f = 0)), alpha = TRUE)(60))(),
    ncol = 1))) |>
    magick::image_scale(sprintf("%dx%d!", VIDEO_W, 240))
  img <- magick::image_composite(img, fade, offset = "+0+0")
  # The same gradient, flipped, under the counter at the bottom
  img <- magick::image_composite(img, magick::image_flip(magick::image_scale(fade, sprintf("%dx%d!", VIDEO_W, 300))),
                                 offset = sprintf("+0+%d", VIDEO_H - 300))
  img <- label(img, hook[1], 48, 34, 38, TEXT_MAIN, weight = 700)
  for (k in seq_along(hook)[-1]) img <- label(img, hook[k], 50, 52 + 30 * k, 24, TEXT_SOFT)

  # Locator map, top right under the headline, on a dark panel so it reads over
  # the close-up landscape in the first seconds
  if (!is.null(locator)) {
    loc <- magick::image_read(locator)
    li  <- magick::image_info(loc)
    pad <- 10
    panel <- magick::image_blank(li$width + 2 * pad, li$height + 2 * pad,
                                 grDevices::adjustcolor(BACKGROUND, alpha.f = 0.7)) |>
      magick::image_composite(loc, offset = sprintf("+%d+%d", pad, pad))
    img <- magick::image_composite(img, panel, offset = sprintf("+%d+%d", VIDEO_W - li$width - 2 * pad - 36, 108))
  }

  # Bottom band: counter (left) and legend (right)
  yb <- 1128   # below the rendered scene, leaving room for three lines above the sources
  img <- label(img, paste0(format(round(area_km2), big.mark = ","), " km\u00b2"), 48, yb, 54, GOLD, weight = 700)
  sub <- if (is.null(radius_km)) "of land in sight" else
    paste0("of land in sight, looking out to ", round(radius_km), " km")
  img <- label(img, sub, 50, yb + 62, 21, TEXT_SOFT)
  if (area_swe_km2 >= 1) {
    img <- label(img, paste0("of which ", format(round(area_swe_km2), big.mark = ","), " km\u00b2 in Sweden"),
                 50, yb + 90, 19, SWEDEN_BLUE)
  }
  legend <- list(c(GOLD, "visible, in Norway"), c(SWEDEN_BLUE, "visible, in Sweden"), c("#3a4148", "hidden by terrain"))
  for (k in seq_along(legend)) {
    img <- magick::image_composite(img, magick::image_blank(16, 16, legend[[k]][1]),
                                   offset = sprintf("+%d+%d", 800, yb + 6 + 28 * (k - 1)))
    img <- label(img, legend[[k]][2], 824, yb + 3 + 28 * (k - 1), 18, TEXT_SOFT)
  }

  # End panel: ranking, lower right of the scene
  if (panel_alpha > 0 && !is.null(ranking)) {
    a <- function(col) grDevices::adjustcolor(col, alpha.f = panel_alpha)
    x0 <- 640; y0 <- SCENE_Y0 + VIDEO_W - 330
    panel_bg <- magick::image_blank(420, 290, grDevices::adjustcolor(BACKGROUND, alpha.f = 0.75 * panel_alpha))
    img <- magick::image_composite(img, panel_bg, offset = sprintf("+%d+%d", x0 - 16, y0 - 14))
    img <- label(img, "Widest views in Norway, km\u00b2 in sight", x0, y0, 21, a(TEXT_MAIN), weight = 700)
    max_area <- max(ranking$area_km2)
    for (i in seq_len(nrow(ranking))) {
      row <- ranking[i, ]
      # Reference rows (rank NA) sit a little apart: they are context, not ranked
      y <- y0 + 36 + (i - 1) * 34 + if (is.na(row$rank)) 12 else 0
      col <- if (row$highlight) a(GOLD) else if (is.na(row$rank)) a(TEXT_FAINT) else a(TEXT_SOFT)
      name <- if (is.na(row$rank)) row$name else paste0(row$rank, ". ", row$name)
      img <- label(img, name, x0, y, 19, col)
      w <- round(150 * row$area_km2 / max_area)
      img <- magick::image_composite(img, magick::image_blank(max(w, 1), 10, col),
                                     offset = sprintf("+%d+%d", x0 + 210, round(y + 7)))
      img <- label(img, format(round(row$area_km2), big.mark = ","), x0 + 216 + w, y, 17, col)
    }
  }

  src <- source_lines(exaggeration)
  img <- label(img, src[1], 50, VIDEO_H - 46, 15, TEXT_FAINT)
  img <- label(img, src[2], 50, VIDEO_H - 26, 15, TEXT_FAINT)
  magick::image_write(img, file)
}
