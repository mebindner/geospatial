# Fjordområder som bounding box i WGS84 (lon/lat).
# Tilføj en ny fjord her, så kan hele pipelinen køres for den med ét navn.

fjorde <- list(
  sognefjorden     = c(xmin = 4.85, ymin = 60.95, xmax = 6.30, ymax = 61.32),
  hardangerfjorden = c(xmin = 5.45, ymin = 59.75, xmax = 6.75, ymax = 60.50)
)

# Engelske navne til tekst i video og billeder
fjord_navne <- c(
  sognefjorden     = "Sognefjord",
  hardangerfjorden = "Hardangerfjord"
)

# Bounding box i EPSG:25833 (det koordinatsystem Kartverket leverer højdedata i)
omraade <- function(fjord) {
  if (!fjord %in% names(fjorde)) stop("Ukendt fjord: ", fjord, ". Vælg en af: ", paste(names(fjorde), collapse = ", "))
  sf::st_bbox(fjorde[[fjord]], crs = 4326) |>
    sf::st_as_sfc() |>
    sf::st_transform(25833) |>
    sf::st_bbox()
}
