# Prompt: Add iNaturalist Computer Vision API to TaxaFetch

## Context

TaxaFetch is an R package in the TaxaID ecosystem (see CLAUDE.md at the repo root for
conventions). This prompt asks you to implement a new function `score_image_inat()` that
wraps the iNaturalist Computer Vision API.

## Background (read before writing code)

The iNaturalist CV API (`POST https://api.inaturalist.org/v1/computervision/score_image`)
accepts an image file plus optional location and date, and returns ranked taxon suggestions
with three score fields per taxon:

- `vision_score`: raw image classifier output (discriminative CNN, no location)
- `combined_score`: `vision_score × geomodel_weight` — approximates a Bayesian posterior
- `frequency_score`: presence indicator from the iNaturalist geomodel (not a raw frequency)

**Key mathematical property:** `combined_score_i / vision_score_i` is constant across all
images for a given (species, location, date) triplet. This ratio is iNaturalist's implicit
geographic prior weight for that species at that location. Dividing across species gives the
relative prior ratio (e.g., SP/W at Reed's Beach in May ≈ 2.63).

**Practical implication:** `combined_score` ≈ posterior; `vision_score` ≈ semi-posterior
(still embeds training-data composition as an implicit prior). Neither is a true likelihood
in the Bayesian sense.

## Authentication

Users must provide an iNaturalist API token. The token is obtained by a logged-in user via:

```
GET https://www.inaturalist.org/users/api_token
```

It should be accepted as a function argument `api_token` with a default of
`Sys.getenv("INAT_API_TOKEN")`. Do not store or print the token.

## Function specification

```r
score_image_inat(
  image_path,          # character: path to image file (JPEG or PNG)
  lat        = NULL,   # numeric: latitude  (optional; enables geomodel)
  lng        = NULL,   # numeric: longitude (optional; enables geomodel)
  observed_on = NULL,  # character: date "YYYY-MM-DD" (optional)
  top_n      = 10L,    # integer: number of top results to return
  api_token  = Sys.getenv("INAT_API_TOKEN")
)
```

**Returns:** a tibble with columns:
`rank`, `taxon_id`, `taxon_name`, `common_name`, `iconic_taxon_name`,
`vision_score`, `combined_score`, `freq_score`, `geo_prior_weight`

where `geo_prior_weight = combined_score / vision_score` (NA when vision_score == 0).

## Implementation notes

- Use `httr::POST()` with `httr::add_headers(Authorization = paste("Bearer", api_token))`
  and `httr::upload_file(image_path)` in the multipart body.
- Pass `lat`, `lng`, `observed_on` as additional form fields in the body (not query params —
  query params are silently ignored by this endpoint).
- Parse the JSON response with `jsonlite::fromJSON()` or `httr::content(..., as = "parsed")`.
- The response structure is `$results[[i]]$taxon` (taxon metadata) and
  `$results[[i]]$vision_score`, `$results[[i]]$combined_score`,
  `$results[[i]]$frequency_score`.
- Validate that `image_path` exists and is JPEG or PNG before sending.
- If `api_token` is empty, stop with a clear message directing the user to set
  `INAT_API_TOKEN` in `~/.Renviron`.
- If `lat` is supplied, `lng` must also be supplied (and vice versa); stop with an error
  if only one is given.
- Follow all TaxaID coding conventions (native pipe `|>`, `package::function()` style,
  roxygen with no blank lines inside `@param` blocks, `@noRd` for helpers).

## Helper function (internal)

Add a `.parse_inat_cv_response()` helper (`@noRd`) that takes the parsed JSON list and
`top_n`, and returns the tibble. This keeps `score_image_inat()` clean.

## Roxygen template

```r
#' Score an image using the iNaturalist Computer Vision API
#'
#' Submits an image to the iNaturalist CV API and returns ranked taxon
#' suggestions with vision, combined, and frequency scores. When a location
#' is supplied, \code{combined_score} reflects iNaturalist's geomodel prior;
#' the ratio \code{combined_score / vision_score} recovers the implicit
#' geographic prior weight for each taxon at that location.
#'
#' @param image_path Character. Path to a JPEG or PNG image file.
#' @param lat Numeric. Latitude in decimal degrees (optional). Must be
#'   supplied together with \code{lng}.
#' @param lng Numeric. Longitude in decimal degrees (optional). Must be
#'   supplied together with \code{lat}.
#' @param observed_on Character. Observation date in \code{"YYYY-MM-DD"}
#'   format (optional).
#' @param top_n Integer. Number of top suggestions to return. Default 10.
#' @param api_token Character. iNaturalist API token. Defaults to the
#'   \code{INAT_API_TOKEN} environment variable.
#' @return A tibble with columns \code{rank}, \code{taxon_id},
#'   \code{taxon_name}, \code{common_name}, \code{iconic_taxon_name},
#'   \code{vision_score}, \code{combined_score}, \code{freq_score},
#'   \code{geo_prior_weight}.
#' @export
```

## File location

Create `TaxaFetch/R/score_image_inat.R`. Add `httr` to `DESCRIPTION` Imports if not
already present (check first). `jsonlite` and `tibble` are likely already imported;
verify in `zzz_imports.R`.

## Test

After implementing, verify with a quick manual test:

```r
devtools::load_all()
result <- score_image_inat(
  image_path  = "path/to/any_bird_photo.jpg",
  lat         = 34.1,
  lng         = -119.1,
  observed_on = "2024-09-15",
  api_token   = Sys.getenv("INAT_API_TOKEN")
)
print(result)
# geo_prior_weight should be constant-ish across images for the same location
```

Run `devtools::check()` when done.
