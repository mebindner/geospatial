# =============================================================================
# Frame annotation
# -----------------------------------------------------------------------------
# Titles, week counter, legend, source line and the closing conclusion are
# drawn onto each rendered frame with magick. Keeping text out of the 3D scene
# means it stays sharp and in the same place while the camera moves.
# All text is in English for an international audience.
# =============================================================================

BACKGROUND <- "#0e1a22"
TEXT_MAIN  <- "white"
TEXT_SOFT  <- "#d0d6dc"
TEXT_FAINT <- "#9aa5ae"
FONT       <- "Helvetica"

SOURCE_LINE <- paste(
  "Data: BarentsWatch/Norwegian Food Safety Authority (NLOD), Kartverket.",
  "Terrain exaggerated 2.5×, bars capped at 2."
)

#' Write titles, legend and (optionally) the conclusion onto a rendered frame
#'
#' @param file PNG written by rayshader::render_snapshot(); overwritten in place.
#' @param title Fjord name shown top left.
#' @param year,week,avg_lice Values for the subtitle and week counter.
#' @param show_week FALSE during the intro, where no data is shown yet.
#' @param size Output width and height in pixels (frames are square).
#' @param conclusion NULL, or list(text = c(line1, line2), points = matrix of
#'   window positions (0-1, y from bottom) of the bar tops to circle,
#'   alpha = 0-1 for the fade-in).
annotate_frame <- function(file, title, year, week, avg_lice, show_week, size, conclusion = NULL) {
  img <- magick::image_read(file)
  # The rgl window can come out a few pixels shorter than requested (the macOS
  # menu bar limits it), so pad to an exact square for the video encoder.
  h0 <- magick::image_info(img)$height
  img <- img |>
    magick::image_background(BACKGROUND) |>
    magick::image_extent(sprintf("%dx%d", size, size), gravity = "center", color = BACKGROUND)
  s <- size / 1080   # all positions below are designed at 1080 px and scaled

  label <- function(img, text, px, py, pt, colour, ...) {
    magick::image_annotate(img, text, size = pt * s, color = colour, font = FONT,
                           location = sprintf("+%d+%d", round(px * s), round(py * s)), ...)
  }

  # Conclusion: circles on the farms it refers to, a leader line and two lines of text
  if (!is.null(conclusion) && conclusion$alpha > 0) {
    main <- grDevices::adjustcolor(TEXT_MAIN, alpha.f = conclusion$alpha)
    soft <- grDevices::adjustcolor(TEXT_SOFT, alpha.f = conclusion$alpha)
    px <- conclusion$points[, 1] * size
    py <- (1 - conclusion$points[, 2]) * h0 + (size - h0) / 2
    top <- which.min(py)
    img <- magick::image_draw(img)
    graphics::segments(60 * s, 300 * s, px[top], py[top] - 16 * s, col = main, lwd = 1.5 * s)
    graphics::symbols(px, py, circles = rep(14 * s, length(px)), inches = FALSE, add = TRUE, fg = main, lwd = 2 * s)
    grDevices::dev.off()
    img <- label(img, conclusion$text[1], 50, 200, 32, main, weight = 700)
    img <- label(img, conclusion$text[2], 50, 244, 26, soft)
  }

  # Title block
  img <- label(img, title, 48, 44, 46, TEXT_MAIN, weight = 700)
  img <- label(img, sprintf("Sea lice on salmon farms, %d", year), 50, 104, 28, TEXT_SOFT)

  if (show_week) {
    # Week counter, top right
    img <- label(img, sprintf("Week %d", week), 48, 40, 64, TEXT_MAIN, weight = 700, gravity = "northeast")
    img <- label(img, sprintf("Average: %.2f lice per fish", avg_lice), 50, 118, 26, TEXT_SOFT, gravity = "northeast")

    # Legend, bottom left
    img <- label(img, "Adult female lice per fish", 50, 1080 - 152, 22, TEXT_SOFT)
    bar <- magick::image_read(grDevices::as.raster(matrix(lice_palette, nrow = 1))) |>
      magick::image_scale(sprintf("%dx%d!", round(300 * s), round(14 * s)))
    img <- magick::image_composite(img, bar, offset = sprintf("+%d+%d", round(50 * s), round(size - 120 * s)))
    img <- label(img, "0", 50, 1080 - 100, 22, TEXT_SOFT)
    img <- label(img, "1+", 328, 1080 - 100, 22, TEXT_SOFT)
  }

  img <- label(img, SOURCE_LINE, 50, 30, 18, TEXT_FAINT, gravity = "southwest")
  magick::image_write(img, file)
}
