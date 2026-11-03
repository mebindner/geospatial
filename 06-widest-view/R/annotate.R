# =============================================================================
# Frame annotation
# -----------------------------------------------------------------------------
# Text is drawn onto each rendered frame with magick, so it stays sharp and
# fixed while the camera moves. Layout follows the lessons from the first
# video: the hook is on screen from the very first frame, and the number the
# story is about is large and always visible.
# =============================================================================

BACKGROUND <- "#0b1218"
TEXT_MAIN  <- "white"
TEXT_SOFT  <- "#d3d9de"
TEXT_FAINT <- "#9aa5ae"
GOLD       <- "#ffcc6b"
FONT       <- "Helvetica"

#' Source lines for the bottom of every frame; the exaggeration is passed in so
#' the stated value always matches the one used to render.
source_lines <- function(exaggeration) c(
  "Terrain: Kartverket DTM (CC BY 4.0), Copernicus DEM GLO-90 outside Norway. Summits: OpenStreetMap (ODbL).",
  paste0("Imagery: Sentinel-2 cloudless 2016 by EOX (CC BY 4.0). Earth curvature and refraction included. ",
         "Terrain exaggerated ", exaggeration, "\u00d7.")
)

#' Write all text layers onto one rendered frame
#'
#' @param file PNG from render_snapshot(); overwritten.
#' @param hook Two lines shown from the first frame.
#' @param area_km2 Visible land revealed so far.
#' @param radius_km Current reveal distance (NULL hides it).
#' @param summit list(label, px, py) with the summit's window position (0-1, y up).
#' @param ranking Tibble (rank, name, ele, area_km2, highlight) for the end panel.
#' @param panel_alpha 0-1, fade of the end panel.
#' @param exaggeration Vertical exaggeration used in the render, for the source line.
annotate_frame <- function(file, hook, area_km2, radius_km, summit, ranking, panel_alpha,
                           exaggeration, size = 1080) {
  img <- magick::image_read(file)
  h0  <- magick::image_info(img)$height
  img <- img |>
    magick::image_background(BACKGROUND) |>
    magick::image_extent(sprintf("%dx%d", size, size), gravity = "center", color = BACKGROUND)
  s <- size / 1080
  label <- function(img, text, px, py, pt, colour, ...) {
    magick::image_annotate(img, text, size = pt * s, color = colour, font = FONT,
                           location = sprintf("+%d+%d", round(px * s), round(py * s)), ...)
  }

  # Summit marker label with a short leader line
  if (!is.null(summit)) {
    sx <- summit$px * size
    sy <- (1 - summit$py) * h0 + (size - h0) / 2
    img <- magick::image_draw(img)
    graphics::segments(sx, sy - 6 * s, sx, sy - 70 * s, col = TEXT_MAIN, lwd = 1.5 * s)
    graphics::symbols(sx, sy, circles = 7 * s, inches = FALSE, add = TRUE, fg = TEXT_MAIN, bg = GOLD, lwd = 2 * s)
    grDevices::dev.off()
    # A dark box behind the name keeps it legible on top of the gold
    img <- magick::image_annotate(img, paste0(" ", summit$label, " "), size = 24 * s, color = TEXT_MAIN, font = FONT,
                                  weight = 700, boxcolor = "#0b1218B0",
                                  location = sprintf("+%d+%d", round(sx + 8 * s), round(sy - 96 * s)))
  }

  # Hook, full width at the top (from frame 1): one headline and up to two lines
  img <- label(img, hook[1], 48, 36, 38, TEXT_MAIN, weight = 700)
  for (k in seq_along(hook)[-1]) img <- label(img, hook[k], 50, 58 + 30 * k, 24, TEXT_SOFT)

  # Counter, right, below the hook
  img <- label(img, sprintf("%s km\u00b2", format(round(area_km2), big.mark = ",")), 48, 168, 54, GOLD,
               weight = 700, gravity = "northeast")
  img <- label(img, "of Norwegian land in sight", 50, 232, 22, TEXT_SOFT, gravity = "northeast")
  if (!is.null(radius_km)) {
    img <- label(img, sprintf("looking out to %d km", round(radius_km)), 50, 260, 20, TEXT_FAINT, gravity = "northeast")
  }

  # Legend, bottom left
  img <- magick::image_composite(img, magick::image_blank(round(18 * s), round(18 * s), GOLD),
                                 offset = sprintf("+%d+%d", round(50 * s), round(size - 150 * s)))
  img <- label(img, "visible from the summit", 76, 1080 - 152, 20, TEXT_SOFT)
  img <- magick::image_composite(img, magick::image_blank(round(18 * s), round(18 * s), "#3a4148"),
                                 offset = sprintf("+%d+%d", round(50 * s), round(size - 122 * s)))
  img <- label(img, "hidden by terrain", 76, 1080 - 124, 20, TEXT_SOFT)

  # End panel: ranking, bottom right
  if (panel_alpha > 0 && !is.null(ranking)) {
    a <- function(col) grDevices::adjustcolor(col, alpha.f = panel_alpha)
    x0 <- 640; y0 <- 1080 - 330
    img <- label(img, "Widest views in Norway", x0, y0, 22, a(TEXT_MAIN), weight = 700)
    max_area <- max(ranking$area_km2)
    for (i in seq_len(nrow(ranking))) {
      row <- ranking[i, ]
      # Reference rows (rank NA) sit a little apart: they are context, not ranked
      y <- y0 + 36 + (i - 1) * 34 + if (is.na(row$rank)) 12 else 0
      col <- if (row$highlight) a(GOLD) else if (is.na(row$rank)) a(TEXT_FAINT) else a(TEXT_SOFT)
      name <- if (is.na(row$rank)) row$name else sprintf("%d. %s", row$rank, row$name)
      img <- label(img, name, x0, y, 19, col)
      w <- round(150 * row$area_km2 / max_area * s)
      img <- magick::image_composite(img, magick::image_blank(max(w, 1), round(10 * s), col),
                                     offset = sprintf("+%d+%d", round((x0 + 230) * s), round((y + 7) * s)))
      img <- label(img, format(round(row$area_km2), big.mark = ","), x0 + 236 + 150 * row$area_km2 / max_area, y, 17, col)
    }
  }

  src <- source_lines(exaggeration)
  img <- label(img, src[1], 50, 46, 15, TEXT_FAINT, gravity = "southwest")
  img <- label(img, src[2], 50, 26, 15, TEXT_FAINT, gravity = "southwest")
  magick::image_write(img, file)
}
