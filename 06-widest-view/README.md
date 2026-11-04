# Norway's widest view

Which Norwegian summit lets you see the most land? Not the highest one.

![Midtre Sølen, the visible land lit up](output/widest_view_final.png)

From **Midtre Sølen** (1,755 m) in Rendalen you can see **6,685 km²** of land, 2.8 times as much as from **Galdhøpiggen** (2,469 m), Norway's highest summit, which is hemmed in by the other peaks of Jotunheimen. Midtre Sølen is 35–40 km from the Swedish border, and 1,632 km² of its view lies in Sweden.

The summit must be in Norway; the land it sees can be in any country.

| Rank | Summit | Height | Visible land (100 m model) | of which in Norway | Furthest visible land |
|---|---|---|---|---|---|
| 1 | Midtre Sølen | 1,755 m | 6,685 km² | 5,053 km² | 187 km |
| 2 | Rondslottet | 2,178 m | 5,089 km² | 5,051 km² | 195 km |
| 3 | Høgronden | 2,115 m | 4,612 km² | 4,569 km² | 190 km |
| 4 | Sålekinntoppen | 1,591 m | 4,567 km² | 3,444 km² | 154 km |
| 5 | Rásttigáisá | 1,067 m | 4,418 km² | 2,890 km² | 172 km |
| – | Galdhøpiggen (highest) | 2,469 m | 2,392 km² | 2,392 km² | |

## Run

Open `Geospatial.Rproj` and run [run.R](run.R). Each stage caches its result in `data/processed`, so re-running is cheap. The first full run downloads about 1.5 GB of elevation data and takes roughly an hour, most of it rendering.

## Method

1. **Terrain.** Kartverket's national terrain model (DTM), filled with Copernicus DEM GLO-90 where Kartverket has no data, so mountains across the border block lines of sight as they should.
2. **Land and countries.** Land is any cell above sea level in either model. Norwegian land is Kartverket above 0 m *and* inside Norway's national border (geoBoundaries). Land in Sweden is land outside that mask and inside Sweden's border. Each visible cell belongs to exactly one country, and the shares add up to the total (checked).
3. **Summits.** Every named OpenStreetMap summit of at least 1,000 m inside Norway: 4,522 candidates, of which 6 were excluded because their OSM elevation disagrees with the terrain by more than plausible.
4. **Visibility.** For each summit, a viewshed from 1.7 m above the summit (eye height), with Earth curvature and standard atmospheric refraction (GDAL, `curvcoef = 6/7`), out to 350 km. Because a grid cell holds the average height of its area, the observer is lifted from the cell to the true summit height.
5. **Three resolutions.** All summits are screened at 500 m. The best 40 distinct summits (one per 3 km) are re-ranked at 200 m. The top 5, and Galdhøpiggen for comparison, are computed at 100 m.
6. **Video.** The 100 m visibility layer, aggregated exactly to a 400 m scene grid, on Sentinel-2 cloudless imagery and the terrain in 3D (rayshader), in 4:5 format. The map reads north-up. Visible land is gold in Norway and light blue in Sweden, with the border drawn in. The counter adds up visible area by distance and ends exactly on the 100 m result. Landmarks are labelled only if the 100 m viewshed confirms they are visible (Rondslottet 88 km, Snøhetta 127 km, Storsylen 131 km, which sits on the border), and a sight line marks the furthest visible land (187 km, near Rankonøse).

## Checks

| Check | Result |
|---|---|
| Viewshed on a flat plane vs. the theoretical horizon (with refraction) | 1,000 m eye: 122.7 km vs 121.9 km. 2,000 m: 173.2 km vs 172.4 km. Both within one cell |
| Same winner at 500 m, 200 m and 100 m | Yes |
| Rank agreement 500 m vs 200 m (top 40) | Spearman 0.87, top 10 overlap 9/10 |
| Country shares add up (winner) | 6,685 = 5,053 Norway + 1,632 Sweden + 0 other, no cell in both |
| Revealed visible land inside the video frame, every frame | 100% (verified to fail on a deliberately cropped camera) |
| Labelled points away from the frame edge | Closest is 7.6% from an edge (minimum 6%) |
| Map orientation in the final view | North up, east right |

## Results depend on resolution, the ranking does not

Visible areas shrink as the terrain gets more detailed, because finer terrain hides more of the small valleys:

| | 500 m | 200 m | 100 m |
|---|---|---|---|
| Midtre Sølen | 9,047 km² | 7,425 km² | 6,685 km² |
| Galdhøpiggen | 4,106 km² | – | 2,392 km² |

The steps get smaller (−18%, then −10%), so the numbers are converging but not final; at 10 m they would be lower still. The **ranking** is what the analysis supports: the same winner at every resolution, and Galdhøpiggen falls faster than the winner as detail increases. Galdhøpiggen ranked 70th of 2,576 distinct summits in the 500 m screening; that rank is not recomputed at 100 m.

## Corrections

This project was published in an earlier form with errors. They are listed here rather than quietly fixed.

1. **Land outside Norway counted as Norwegian.** The first version defined Norwegian land as "Kartverket above 0 m". Kartverket's coverage reaches well into Sweden and Finland in rectangular blocks, so about 104,000 km² of foreign land was treated as Norwegian, and 345 Swedish and Finnish summits were candidates. The first published result (6,124 km² of "Norwegian land", 2.6× Galdhøpiggen) was therefore wrong. It was caught when a locator map showed a stepped eastern border. The analysis now uses the national borders and counts all land, with the Swedish share reported separately.
2. **Map shown upside down.** Version 2 of the video looked at the scene from about 200 degrees, which put south at the top. Positions were right relative to each other but read as wrong. The video is now north-up, and a check enforces it.
3. **Distant visible land drawn too faintly.** An earlier video dimmed scene cells less than half visible, which drew 8.8% of the visible land as if it were hidden. Every cell with any visible land now glows.

## Limitations

- "Visible" means a clear line of sight. Haze and weather limit real views long before 150–190 km.
- Sea is not counted as land in view.
- Kartverket's terrain is bare earth. Copernicus, used outside Kartverket's coverage, is a surface model that includes forest, so Swedish terrain can be a little higher than the ground.
- National borders come from generalised datasets. Summits within 300 m of the border are labelled "on the border" rather than assigned to a country.
- Candidates are named OSM summits of at least 1,000 m. An unnamed or lower top with a wide view would be missed.
- The video exaggerates the terrain 4× for legibility; this is stated on every frame.

## Data

| Data | Source | Licence |
|---|---|---|
| Terrain, Norway | Kartverket, WCS `wcs.hoyde-dtm-nhm-25833` | CC BY 4.0 |
| Terrain, elsewhere | Copernicus DEM GLO-90 (© DLR e.V. 2010–2014 and © Airbus Defence and Space GmbH 2014–2018, provided under COPERNICUS by the European Union and ESA) | Copernicus DEM licence |
| Summits | OpenStreetMap contributors, via Overpass | ODbL |
| Border, Norway | geoBoundaries ADM0 (from OpenStreetMap) | ODbL |
| Border, Sweden | geoBoundaries ADM0 | Open Government Licence v3.0 |
| Imagery | Sentinel-2 cloudless 2016 by EOX IT Services (s2maps.eu), contains modified Copernicus Sentinel data 2016 | CC BY 4.0 |

## Code

| File | Responsibility |
|---|---|
| [R/grid.R](R/grid.R) | Analysis grid and resolutions |
| [R/elevation.R](R/elevation.R) | Terrain, land masks, national borders |
| [R/peaks.R](R/peaks.R) | Named summits from OpenStreetMap |
| [R/viewshed.R](R/viewshed.R) | Visible land from one summit, parallel scoring |
| [R/pipeline.R](R/pipeline.R) | Screening, re-ranking, final 100 m numbers, reference summits |
| [R/checks.R](R/checks.R) | Horizon, OSM elevations, rank agreement, country split, frame coverage, label margins, orientation |
| [R/imagery.R](R/imagery.R) | Sentinel-2 cloudless imagery on the scene grid |
| [R/scene.R](R/scene.R) | 3D scene, country colours, border line, reveal texture |
| [R/locator.R](R/locator.R) | Locator map of Norway with the summit |
| [R/annotate.R](R/annotate.R) | On-screen text, counter, legend and ranking panel |
| [R/video.R](R/video.R) | Camera, frame rendering and video encoding |
| [video_story.R](video_story.R) | Builds the on-screen story from the results |
