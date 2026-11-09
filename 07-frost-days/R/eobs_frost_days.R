# Frost days per year on the E-OBS 0.1° grid over Denmark.
# Input:  data/raw/tn_ens_mean_0.1deg_reg_v31.0e.nc (daily minimum temperature, ECA&D E-OBS)
# Output: data/processed/eobs_fd_dk.csv  (lon, lat, year, fd) for complete years only
# Run from the project folder: Rscript R/eobs_frost_days.R
suppressPackageStartupMessages(library(terra))

nc  <- "data/raw/tn_ens_mean_0.1deg_reg_v31.0e.nc"
out <- "data/processed/eobs_fd_dk.csv"

r <- rast(nc, subds = "tn")
r <- crop(r, ext(7.8, 15.4, 54.4, 57.9))
d <- time(r)
cat("days:", length(d), "from", format(min(d)), "to", format(max(d)), "\n")

yrs  <- as.integer(format(d, "%Y"))
full <- as.integer(names(which(table(yrs) >= 365)))
keep <- yrs %in% full
r <- r[[which(keep)]]; yrs <- yrs[keep]

frost <- r < 0                                  # NA over sea stays NA
fd <- tapp(frost, index = yrs, fun = sum)       # NA if any day is missing in a cell-year
names(fd) <- unique(yrs)

df <- as.data.frame(fd, xy = TRUE, na.rm = FALSE)
long <- do.call(rbind, lapply(names(fd), function(y)
  data.frame(lon = round(df$x, 3), lat = round(df$y, 3), year = as.integer(y), fd = df[[y]])))
long <- long[!is.na(long$fd), ]
dir.create(dirname(out), showWarnings = FALSE, recursive = TRUE)
write.csv(long, out, row.names = FALSE)
cat("cells:", length(unique(paste(long$lon, long$lat))), "years:", min(long$year), "-", max(long$year), "\n")
