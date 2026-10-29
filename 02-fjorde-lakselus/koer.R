# Projekt 2: Norges fjorde i 3D med lakselus ovenpå
# Kør fra Geospatial.Rproj (roden) eller fra denne mappe.

PROJEKT <- if (dir.exists("02-fjorde-lakselus")) "02-fjorde-lakselus" else "."
for (f in list.files(file.path(PROJEKT, "R"), full.names = TRUE)) source(f)

# Test først et par frames (intro, midt i ugerne, slutbilledet):
# lav_video("sognefjorden", kun_frames = c(1, 125, 400, 725))

# Hele videoen. Seneste uge er ofte ikke færdigindberettet, så stop en uge før.
# 2026: data hentet 28. okt., uge 43 mangler stadig mange tællinger.
lav_video("sognefjorden", aar = 2026, uger = 18:42)

# Sidste år til sammenligning:
# lav_video("sognefjorden", aar = 2025)

# En anden fjord senere:
# lav_video("hardangerfjorden", aar = 2025)
