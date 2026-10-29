# 3D-scene og video: terræn fra Kartverket, ét søjle pr. anlæg med højde og farve efter lusetal.

lus_farve <- grDevices::colorRampPalette(c("#2a9d8f", "#e9c46a", "#e76f51", "#9b2226"))(101)

farve_for <- function(hunnlus, maks = 1) {
  lus_farve[round(pmin(hunnlus / maks, 1) * 100) + 1]
}

# Terræntekstur beregnes én gang (skygge tager tid) og gemmes
byg_terraen <- function(dtm, zscale, fjord, opl, mappe) {
  fil <- file.path(mappe, sprintf("tekstur_%s_%dm.rds", fjord, opl))
  m <- rayshader::raster_to_matrix(dtm)
  if (file.exists(fil)) return(list(m = m, tekstur = readRDS(fil)))
  tekstur <- rayshader::height_shade(m, texture = grDevices::colorRampPalette(c("#5b7553", "#8c9a73", "#b8b39b", "#e8e4dc", "#ffffff"))(256))
  # Vandet males direkte på teksturen. height_shade() giver billedet transponeret i forhold til m,
  # og add_water() rammer forkert med en logisk maske, så vi gør det selv.
  vand <- t(m == 0)
  vandfarve <- grDevices::col2rgb("#1d3d52") / 255
  for (k in 1:3) tekstur[, , k][vand] <- vandfarve[k]
  tekstur <- tekstur |>
    rayshader::add_shadow(rayshader::lamb_shade(m, zscale = zscale, sunaltitude = 35, sunangle = 225), 0.3) |>
    rayshader::add_shadow(rayshader::ray_shade(m, zscale = zscale, sunaltitude = 25, sunangle = 225, multicore = TRUE), 0.4) |>
    rayshader::add_shadow(rayshader::ambient_shade(m, zscale = zscale, multicore = TRUE), 0)
  saveRDS(tekstur, fil)
  list(m = m, tekstur = tekstur)
}

# Kamerabane: glid ind over fjorden i intro, drej langsomt under ugerne, stå stille til sidst
kamera <- function(i, n_intro, n_uger, n_hold) {
  t_intro <- min(i / n_intro, 1)
  ease <- (1 - cos(pi * t_intro)) / 2
  t_drej <- max(0, min((i - n_intro) / n_uger, 1))
  list(
    theta = -30 + 25 * ease + 20 * t_drej,
    phi   = 70 - 38 * ease,
    zoom  = 0.95 - 0.25 * ease - 0.04 * t_drej
  )
}

# Søjler tegnes direkte med rgl (render_polygons ignorerer data_column_top i rayshader 0.41).
# Scenens koordinater: x = kolonne fra midten, z = række fra midten (nord = negativ), y = højde / zscale.
tegn_soejler <- function(d, dtm, zscale, meter_pr_lus, halvbredde_m = 350, max_lus = 2) {
  e <- terra::ext(dtm)
  opl <- terra::res(dtm)[1]
  xy <- sf::st_coordinates(d)
  x <- (xy[, 1] - e$xmin) / opl - terra::ncol(dtm) / 2
  z <- (e$ymax - xy[, 2]) / opl - terra::nrow(dtm) / 2
  h <- pmax(pmin(d$hunnlus, max_lus), 0.02) * meter_pr_lus / zscale
  b <- halvbredde_m / opl
  ids <- integer(0)
  for (j in seq_len(nrow(d))) {
    kasse <- rgl::cube3d(color = farve_for(d$hunnlus[j]), lit = TRUE, specular = "black") |>
      rgl::scale3d(b, h[j] / 2, b) |>
      rgl::translate3d(x[j], h[j] / 2, z[j])
    ids <- c(ids, rgl::shade3d(kasse))
  }
  ids
}

# Tekst og signaturforklaring lægges ovenpå med magick
paaskrift <- function(fil, fjord_navn, aar, uge, lus_snit, vis_uge, bredde) {
  # rgl-vinduet kan blive et par pixels lavere end bestilt (skærmens menulinje); fyld op til kvadrat
  img <- magick::image_read(fil) |>
    magick::image_background("#0e1a22") |>
    magick::image_extent(sprintf("%dx%d", bredde, bredde), gravity = "center", color = "#0e1a22")
  s <- bredde / 1080
  img <- magick::image_annotate(img, fjord_navn, size = 46 * s, color = "white", weight = 700,
                                location = sprintf("+%d+%d", round(48 * s), round(44 * s)), font = "Helvetica")
  # Al tekst i billedet er på engelsk (internationalt publikum)
  img <- magick::image_annotate(img, sprintf("Sea lice on salmon farms, %d", aar), size = 28 * s, color = "#d0d6dc",
                                location = sprintf("+%d+%d", round(50 * s), round(104 * s)), font = "Helvetica")
  if (vis_uge) {
    img <- magick::image_annotate(img, sprintf("Week %d", uge), size = 64 * s, color = "white", weight = 700,
                                  gravity = "northeast", location = sprintf("+%d+%d", round(48 * s), round(40 * s)), font = "Helvetica")
    img <- magick::image_annotate(img, sprintf("Average: %.2f lice per fish", lus_snit), size = 26 * s, color = "#d0d6dc",
                                  gravity = "northeast", location = sprintf("+%d+%d", round(50 * s), round(118 * s)), font = "Helvetica")
    # Farveskala
    img <- magick::image_annotate(img, "Adult female lice per fish", size = 22 * s, color = "#d0d6dc",
                                  location = sprintf("+%d+%d", round(50 * s), round(bredde - 152 * s)), font = "Helvetica")
    skala <- magick::image_read(grDevices::as.raster(matrix(lus_farve, nrow = 1)))
    skala <- magick::image_scale(skala, sprintf("%dx%d!", round(300 * s), round(14 * s)))
    img <- magick::image_composite(img, skala, offset = sprintf("+%d+%d", round(50 * s), round(bredde - 120 * s)))
    img <- magick::image_annotate(img, "0", size = 22 * s, color = "#d0d6dc",
                                  location = sprintf("+%d+%d", round(50 * s), round(bredde - 100 * s)), font = "Helvetica")
    img <- magick::image_annotate(img, "1+", size = 22 * s, color = "#d0d6dc",
                                  location = sprintf("+%d+%d", round(328 * s), round(bredde - 100 * s)), font = "Helvetica")
  }
  img <- magick::image_annotate(img, "Data: BarentsWatch/Norwegian Food Safety Authority (NLOD), Kartverket. Terrain exaggerated 2.5×, bars capped at 2.", size = 18 * s,
                                color = "#9aa5ae", gravity = "southwest",
                                location = sprintf("+%d+%d", round(50 * s), round(30 * s)), font = "Helvetica")
  magick::image_write(img, fil)
}

# Hele pipelinen for én fjord. Skift fjord med ét argument.
lav_video <- function(fjord        = "sognefjorden",
                      aar          = 2025,
                      uger         = 18:44,
                      opl          = 100,      # meter pr. pixel i højdemodellen
                      zscale       = 40,       # lavere = mere overdrevet terræn
                      meter_pr_lus = 2500,     # søjlehøjde i meter pr. hunlus
                      sek_intro    = 5,
                      sek_uger     = 20,
                      sek_hold     = 4,
                      fps          = 25,
                      bredde       = 1080,
                      kun_frames   = NULL,     # fx c(1, 150, 500) for at teste enkelte frames
                      mappe        = PROJEKT) {
  raw  <- file.path(mappe, "data/raw")
  proc <- file.path(mappe, "data/processed")
  ud   <- file.path(mappe, "output")
  frames <- file.path(ud, "frames", paste(fjord, aar, sep = "_"))
  unlink(file.path(frames, "*.png"))
  dir.create(frames, recursive = TRUE, showWarnings = FALSE)

  dtm <- hent_hoejde(fjord, opl, raw)
  lus <- hent_lus(fjord, aar, raw) |> dplyr::filter(uge %in% uger)
  terr <- byg_terraen(dtm, zscale, fjord, opl, proc)

  # Værste uge (højeste snit) bruges til slutbilledet
  snit <- lus |> sf::st_drop_geometry() |> dplyr::group_by(uge) |>
    dplyr::summarise(m = mean(hunnlus, na.rm = TRUE))
  vaerste <- snit$uge[which.max(snit$m)]

  n_intro <- sek_intro * fps
  n_uger  <- sek_uger * fps
  n_hold  <- sek_hold * fps
  n <- n_intro + n_uger + n_hold
  fjord_navn <- fjord_navne[[fjord]]

  rayshader::plot_3d(terr$tekstur, terr$m, zscale = zscale, windowsize = c(bredde, bredde),
                     solid = TRUE, soliddepth = -60, solidcolor = "#0e1a22", solidlinecolor = "#0e1a22",
                     shadow = FALSE, background = "#0e1a22")

  soejle_ids <- integer(0)
  for (i in if (is.null(kun_frames)) seq_len(n) else kun_frames) {
    k <- kamera(i, n_intro, n_uger, n_hold)
    rayshader::render_camera(theta = k$theta, phi = k$phi, zoom = k$zoom, fov = 30)

    if (length(soejle_ids)) rgl::pop3d(id = soejle_ids)
    soejle_ids <- integer(0)
    if (i <= n_intro) {
      uge <- min(uger); vis <- FALSE
    } else {
      # Ugerne løber fra første uge frem til den værste uge, så videoen ender på toppen
      uge <- if (i > n_intro + n_uger) vaerste else min(uger) + (i - n_intro) / n_uger * (vaerste - min(uger))
      vis <- TRUE
      d <- lus_i_uge(lus, uge) |> dplyr::filter(!is.na(hunnlus))
      if (nrow(d) > 0) soejle_ids <- tegn_soejler(d, dtm, zscale, meter_pr_lus)
    }

    fil <- file.path(frames, sprintf("f%04d.png", i))
    rayshader::render_snapshot(fil)
    snit_nu <- if (vis) mean(lus_i_uge(lus, uge)$hunnlus, na.rm = TRUE) else NA
    paaskrift(fil, fjord_navn, aar, round(uge), snit_nu, vis, bredde)
    message(sprintf("frame %d/%d", i, n))
  }
  rgl::close3d()

  if (is.null(kun_frames)) {
    video <- file.path(ud, sprintf("%s_%d.mp4", fjord, aar))
    system2("ffmpeg", c("-y", "-framerate", fps, "-i", shQuote(file.path(frames, "f%04d.png")),
                        "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18", shQuote(video)))
    file.copy(file.path(frames, sprintf("f%04d.png", n)), file.path(ud, sprintf("%s_%d_slut.png", fjord, aar)), overwrite = TRUE)
    message("Video: ", video)
  }
}
