# Prompt: Add iNaturalist Range Check to TaxaFetch

## Context

TaxaFetch is an R package in the TaxaID ecosystem (see CLAUDE.md at the repo root for
conventions). This prompt asks you to implement a new function `check_inat_range()` that,
given a vector of taxon names and a single lat/lng coordinate, returns whether each taxon
falls within its iNaturalist geomodel range polygon at that location.

## Background (read before writing code)

iNaturalist publishes thresholded binary range polygons derived from its geomodel (a
Spatially Implicit Neural Representation trained on iNaturalist observations). These are
available as per-taxon GeoJSON files on S3:

```
https://inaturalist-open-data.s3.us-east-1.amazonaws.com/geomodel/geojsons/latest/{taxon_id}.geojson
```

**Key properties of these polygons:**
- Binary (presence/absence threshold applied) — the continuous probability surface is
  NOT publicly available
- One file per taxon, keyed by iNaturalist taxon ID (integer)
- May not exist for all taxa (especially invertebrates, plants with sparse iNat coverage)
- Represent iNaturalist's implicit prior for whether a species occurs at a location;
  more conservative than eBird because trained on iNat observations (presence probability,
  not encounter rate)
- Reliability scales with iNat observation density for the taxon — well-observed groups
  (birds, butterflies, common mammals) have reliable polygons; poorly-observed groups
  (marine fish, invertebrates, algae, protists) may have no polygon or an unreliable one

**Use case in TaxaID:** corroborates eDNA detections that lack occurrence-database priors.
The primary input is the **dark diversity set** — taxa detected in eDNA (present in the
likelihood object) but absent from `taxaexpect_priors` (not in the regional occurrence
database). These taxa currently receive the global floor or hierarchical group prior.
`check_inat_range()` identifies which dark diversity candidates have independent geographic
support from iNaturalist's geomodel, allowing their priors to be selectively elevated.

**Asymmetric evidence principle (critical — read before implementing):**
Evidence from the range polygon is asymmetric and must NOT be applied symmetrically:

- `in_range = TRUE`: positive evidence — iNat's geomodel independently corroborates the
  eDNA detection at this location. Warrants a prior boost above the dark diversity floor.
- `in_range = FALSE`: weak evidence — absence from the iNat geomodel does NOT confirm
  absence from the site. False negatives are common for eDNA target groups (especially
  marine fish, invertebrates, algae) due to low iNat observer effort in aquatic systems.
  Do NOT suppress or penalize priors for `out_of_range` taxa.
- `in_range = NA` (no polygon): no evidence either way — treat neutrally, no prior change.

The boost should only be applied when the geomodel is reliable (see `n_observations`
below). A range polygon based on 20 observations carries much less weight than one based
on 20,000.

## Step 1 — Name to taxon ID resolution

Use the iNaturalist taxa API to resolve each taxon name to an integer taxon ID:

```
GET https://api.inaturalist.org/v1/taxa?q={taxon_name}&rank=species&per_page=1
```

Parse `$results[[1]]$id` (integer), `$results[[1]]$name` (accepted name),
`$results[[1]]$rank`, `$results[[1]]$observations_count` (integer — total iNat
observations for this taxon), and `$results[[1]]$iconic_taxon_name` (character — broad
taxonomic group, e.g. `"Actinopterygii"`, `"Aves"`, `"Plantae"`, `"Protozoa"`).
If no result is returned, set taxon_id = NA and skip polygon lookup.

Authentication: include `Authorization: Bearer {api_token}` header. Rate-limit: add
`Sys.sleep(0.3)` between taxa API calls. The S3 GeoJSON downloads do not require
rate-limiting (no auth, no rate limit on S3).

## Step 2 — Download range polygon

For each resolved taxon_id, fetch:

```
https://inaturalist-open-data.s3.us-east-1.amazonaws.com/geomodel/geojsons/latest/{taxon_id}.geojson
```

Use `httr::GET()`. If the response is HTTP 404 or 403, the taxon has no geomodel polygon —
set `in_range = NA` with `range_status = "no_polygon"`. No sleep needed between S3 fetches.

Parse the GeoJSON with `sf::st_read(httr::content(resp, as = "text"), quiet = TRUE)`.

## Step 3 — Point-in-polygon test

Create the query point:

```r
query_pt <- sf::st_sfc(sf::st_point(c(lng, lat)), crs = 4326)
```

Test containment:

```r
in_range <- as.logical(sf::st_within(query_pt, sf::st_union(polygon_sf), sparse = FALSE))
```

Note: some GeoJSONs contain MULTIPOLYGON or multiple features — use `sf::st_union()` before
testing to handle both.

## Function specification

```r
check_inat_range(
  taxon_names,                         # character vector of species names
  lat,                                  # numeric: latitude in decimal degrees
  lng,                                  # numeric: longitude in decimal degrees
  api_token  = Sys.getenv("INAT_API_TOKEN"),
  cache_dir  = NULL,                    # optional: path to cache downloaded GeoJSONs
  verbose    = FALSE                    # print progress for long taxon lists
)
```

**Returns:** a tibble with one row per input taxon_name and columns:

| Column | Type | Description |
|---|---|---|
| `taxon_name` | chr | Input name as supplied |
| `taxon_id` | int | iNaturalist taxon ID (NA if not found) |
| `matched_name` | chr | iNaturalist accepted name |
| `rank` | chr | Taxonomic rank from iNat (should be "species") |
| `iconic_taxon_name` | chr | Broad taxonomic group (e.g. `"Actinopterygii"`, `"Aves"`); NA if not found |
| `n_observations` | int | Total iNat observations for this taxon; proxy for geomodel reliability; NA if not found |
| `in_range` | lgl | TRUE/FALSE if point is within range polygon; NA if no polygon |
| `range_status` | chr | One of: `"in_range"`, `"out_of_range"`, `"no_polygon"`, `"taxon_not_found"` |

## Downstream use in TaxaID workflows

`check_inat_range()` is intended to be called on the **dark diversity set** before
`join_priors()` or as a post-hoc prior adjustment:

```r
# Dark diversity set: eDNA detections with no occurrence-database prior
dark_taxa <- setdiff(final_likelihoods$taxon_name, taxaexpect_priors$taxon_name)

inat_range <- check_inat_range(
  taxon_names = dark_taxa,
  lat         = SITE_LAT,
  lng         = SITE_LNG,
  cache_dir   = file.path(OUT_DIR, "inat_cache")
)

# Apply boost only to reliably in-range taxa
# n_observations threshold depends on taxon group — 500 suggested for fish,
# higher for other groups
in_range_boost <- inat_range |>
  filter(in_range == TRUE, n_observations >= 500)
```

The boost elevates these taxa above the dark diversity floor/group prior but below Tier 2
singleton mirrors. The prior adjustment itself is handled in TaxaAssign (see
`adjust_inat_range_priors()` — planned function). The `out_of_range` result should NOT be
used to suppress priors — the eDNA detection already provides positive evidence that the
standard dark diversity prior should handle.

## Caching

If `cache_dir` is supplied and exists, save each downloaded GeoJSON as
`{cache_dir}/{taxon_id}.geojson` on first download and read from cache on subsequent
calls. This avoids repeated S3 downloads for large taxon lists. Use `file.exists()` to
check before downloading. Do not cache 404 responses.

## Implementation notes

- Process taxon_names in a loop (not vectorised — each requires separate API calls)
- Add `Sys.sleep(0.3)` between **taxa API calls only** — S3 GeoJSON fetches need no sleep
- `sf` must be in DESCRIPTION Imports — check before assuming it is present
- `httr` is already in Imports (added for `score_image_inat()`); verify
- Use `package::function()` style throughout (sf::st_read, sf::st_sfc, etc.)
- If `api_token` is empty, stop with message directing user to set `INAT_API_TOKEN`
- Validate that `lat` and `lng` are single numeric values; stop if not

## Helper functions (internal, @noRd)

- `.inat_taxon_id(taxon_name, api_token)`: hits taxa API, returns list(taxon_id, matched_name, rank, iconic_taxon_name, n_observations) or NAs
- `.inat_range_polygon(taxon_id, cache_dir)`: downloads/reads GeoJSON from S3, returns sf object or NULL
- `.point_in_inat_range(polygon_sf, lat, lng)`: runs point-in-polygon test, returns TRUE/FALSE

## Roxygen template

```r
#' Check whether taxa fall within iNaturalist range polygons
#'
#' For each taxon name, resolves the iNaturalist taxon ID, downloads the
#' corresponding geomodel range polygon from iNaturalist's S3 bucket, and
#' tests whether a query point (lat/lng) falls within the polygon. The range
#' polygons are thresholded binary outputs of iNaturalist's SINR geomodel —
#' the continuous probability surface is not publicly available.
#'
#' @details
#' Intended for use on the dark diversity set: taxa detected in eDNA but absent
#' from the regional occurrence database (i.e. lacking a TaxaExpect prior).
#' Evidence is asymmetric: \code{in_range = TRUE} warrants a prior boost;
#' \code{in_range = FALSE} should not suppress priors (false negatives are common
#' for aquatic taxa due to low iNaturalist observer effort in marine systems).
#' Use \code{n_observations} to gate the boost — geomodel reliability scales with
#' observation count. \code{in_range = NA} (no polygon exists) is neutral.
#'
#' @param taxon_names Character vector of species names to check.
#' @param lat Numeric. Latitude of the query point in decimal degrees.
#' @param lng Numeric. Longitude of the query point in decimal degrees.
#' @param api_token Character. iNaturalist API token for taxon name resolution.
#'   Defaults to the \code{INAT_API_TOKEN} environment variable.
#' @param cache_dir Character. Optional path to a directory for caching
#'   downloaded GeoJSON files. Speeds up repeated calls for the same taxa.
#' @param verbose Logical. If TRUE, prints progress for each taxon. Default FALSE.
#' @return A tibble with columns \code{taxon_name}, \code{taxon_id},
#'   \code{matched_name}, \code{rank}, \code{iconic_taxon_name},
#'   \code{n_observations}, \code{in_range}, \code{range_status}.
#' @export
```

## File location

Create `TaxaFetch/R/check_inat_range.R`. Add `sf` to DESCRIPTION Imports if not
already present. Verify `httr` is present.

## Relationship to score_image_inat()

`check_inat_range()` provides a binary location signal derived from iNaturalist's geomodel.
`score_image_inat()` (planned — see TaxaFetch CLAUDE.md TODO) returns `geo_prior_weight`
(combined_score / vision_score) — iNaturalist's continuous geomodel weight for image
classification. The two functions serve analogous roles for different data pathways:

- `check_inat_range()`: eDNA pathway — binary range corroboration for dark diversity taxa
- `score_image_inat()` geo_prior_weight: image pathway — continuous location prior for
  image classification candidates

## Test

```r
devtools::load_all()
result <- check_inat_range(
  taxon_names = c("Calidris mauri", "Calidris pusilla", "Calidris minutilla"),
  lat = 34.1,    # Pt. Mugu, CA
  lng = -119.1,
  cache_dir = tempdir()
)
print(result)
# Expected: mauri in_range = TRUE; pusilla likely FALSE or NA at Pt. Mugu
# n_observations should be high for all three (well-observed shorebirds)
# iconic_taxon_name should be "Aves" for all three

result2 <- check_inat_range(
  taxon_names = c("Calidris mauri", "Calidris pusilla", "Calidris minutilla"),
  lat = 39.07,   # Reed's Beach, NJ
  lng = -74.97,
  cache_dir = tempdir()
)
print(result2)
# Expected: pusilla in_range = TRUE, mauri likely FALSE or NA at Reed's Beach
```

Run `devtools::check()` when done.
