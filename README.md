# Geospatial

Maps and spatial analysis built from open data, one project at a time. Each project ends in a single visual (image, short video or GIF) with a short note on method and limitations.

Code is in R or Python, chosen per task.

| # | Project | Folder | Status |
|---|---------|--------|--------|
| 2 | Norway's fjords in 3D with sea lice on top | [`02-fjords-sea-lice/`](02-fjords-sea-lice/) | Done: Sognefjord 2026, weeks 18–42 |
| 1 | Denmark at +1 and +2 metres of sea level rise | – | Planned |
| 3 | How far does public money travel? | – | Planned |
| 4 | Denmark from space: greener or greyer? | – | Planned |
| 5 | 15-minute Denmark | – | Planned |

## Structure

Each project folder follows the same layout:

```
data/raw/        downloaded source data (not committed)
data/processed/  derived data and caches (not committed)
R/ or py/        code
output/          renders (only the final still is committed)
README.md        data, method and limitations
```

## Related

- [lakselus](https://github.com/mebindner/lakselus): weekly sea lice brief and 1–4 week forecast for Norwegian salmon farming ([live app](https://lakselus.streamlit.app))

## License

Code: MIT. Data belongs to the sources named in each project and keeps their licences.
