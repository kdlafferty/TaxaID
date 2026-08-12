# ==============================================================================
# extra_functions_review_inputs.R
# TaxaFetch -- small, ready-to-run inputs for the 10 functions written AFTER
# this package's formal code review (reviewed 2026-07-09)
#
# PURPOSE
# -------
# A companion to review_function_inputs.R (which covers every function that
# existed at the time of the 2026-07-09 review). A later audit found 10
# functions written after that review that have never had a reviewer-facing
# runnable example: 7 internal (@noRd) helpers and 3 exported functions. This
# file gives each one its own small section, in the same style/convention as
# review_function_inputs.R.
#
# Inputs are pulled from the same three sources, cheapest first:
#   1. Existing testthat fixtures reused verbatim (already validated, fully
#      offline where the function itself is offline)
#   2. Existing roxygen @examples
#   3. New small synthetic inputs constructed for this file where no fixture
#      or example existed
#
# INTERNAL HELPERS AND `:::` -- EXPECTED, NOT A BUG
# --------------------------------------------------
# The 7 dot-prefixed functions below (.axis_or_default, .detect_attr_col,
# .gbif_default_year_range, .inat_observation_count, .nearest_institution,
# .render_one_page_b64, .track_removed) are internal (@noRd, unexported).
# They are called here via TaxaFetch:::<name>(...). This is the normal,
# expected way to reach an internal function for a source-install dev
# review -- `:::` deliberately bypasses the NAMESPACE export list, which is
# exactly what a reviewer needs to exercise internal logic directly instead
# of only through whatever exported function happens to call it. It is not
# a workaround for anything broken.
#
# REQUIRES tags (read before running a section) -- same convention as
# review_function_inputs.R:
#   OFFLINE       -- pure function, or uses only bundled package data/files;
#                    no network call
#   NETWORK       -- hits a public API, no credentials needed
#   NETWORK+AUTH  -- needs credentials in ~/.Renviron in addition to network
#                    access (here: INAT_API_TOKEN)
#
# Two of the ten functions (check_geographic_outliers(), fetch_inat_
# occurrences()) are documented in this package's CLAUDE.md as making real,
# small NETWORK calls (GBIF/CoordinateCleaner and iNaturalist respectively).
# Both sections below use a small/fast real-taxon query, matching this
# package's established convention (e.g. review_function_inputs.R's
# fetch_gbif_occurrences() section, Section 1 there).
# ==============================================================================

devtools::load_all()   # or: library(TaxaFetch)
library(tibble)


# ==============================================================================
# SECTION 1 -- PDF pipeline internal helpers
# R/pdf_extract.R, R/pdf_api.R
# ==============================================================================

## ---- .axis_or_default() ---- OFFLINE, pure function ------------------------
# Fixture reused verbatim from tests/testthat/test-pdf_extract.R -- covers the
# real bug it exists to fix: screen_pdf_structure() explicitly returns
# NA_character_ (not NULL) on an LLM-characterization failure, and this
# package's shared %||% (NULL-only by design) doesn't catch that case.
axis_default_null <- TaxaFetch:::.axis_or_default(NULL, "fallback")
axis_default_na    <- TaxaFetch:::.axis_or_default(NA_character_, "fallback")
axis_default_real  <- TaxaFetch:::.axis_or_default("real_value", "fallback")
axis_default_null
axis_default_na
axis_default_real

## ---- .render_one_page_b64() ---- OFFLINE, uses bundled real PDF ------------
# Renders one page of a real bundled PDF (inst/extdata/pdfs/, same PDFs
# extract_pdf_text() uses in review_function_inputs.R Section 6) to a base64
# PNG string. dpi = 100L (lower than call_api_pdf()'s own 150L default) to
# keep this section's output small/fast -- the exact resolution doesn't
# matter for exercising the function itself. Shared by both branches of
# .render_pdf_pages() (the callr-subprocess path and the in-process
# fallback), so this is the one place that logic is directly testable.
#
# Called here via callr::r(), NOT directly in-process -- confirmed live
# while preparing this file that a direct in-process call
# (TaxaFetch:::.render_one_page_b64(...)) segfaults this R session
# ("*** caught segfault ***", poppler_render_page), consistent with
# .render_pdf_pages()'s own documented reason for preferring the callr
# subprocess path ("protects against segfaults from corrupt PDFs that
# crash poppler/pdftools at the C level" -- pdf_api.R's own comment). This
# is exactly the real risk that design exists to guard against, not a bug
# in .render_one_page_b64() itself; running it the same way
# .render_pdf_pages() does is the correct way to exercise it safely.
bundled_pdf_for_render <- system.file(
  "extdata", "pdfs", "W2403944014.pdf", package = "TaxaFetch"
)
page1_b64 <- callr::r(
  TaxaFetch:::.render_one_page_b64,
  args = list(pdf_path = bundled_pdf_for_render, pg = 1L, dpi = 100L)
)
nchar(page1_b64)          # length of the base64 string
substr(page1_b64, 1, 40)  # just the start; it's a full PNG, base64-encoded


# ==============================================================================
# SECTION 2 -- DataONE EML column detection internal helper
# R/dataone_eml_screen.R
# ==============================================================================

## ---- .detect_attr_col() ---- OFFLINE, pure function -------------------------
# dataone_eml_screen.R has no dedicated test file, so no fixture exists to
# reuse. Built to exercise .detect_attr_col()'s two real match tiers (exact,
# then partial substring), using the SAME real candidate lists
# .detect_lon_col() passes it (not an arbitrary substitute) -- so this runs
# the identical logic screen_eml_columns() actually relies on to find a
# longitude column in a dataset's EML <attributeName> list.
lon_exact_candidates   <- c("lon", "long", "longitude", "decimallongitude",
                            "x", "xlon", "lon_dd", "longitude_dd",
                            "site_lon", "start_lon", "end_lon", "easting",
                            "x_coord", "xloc", "lon_wgs84",
                            "longitude_wgs84", "point_x")
lon_partial_candidates <- c("lon", "long", "longitude", "easting", "xloc", "x_coord")

# Case 1: an EML attributeName list with an exact match.
attrs_exact_hit <- c("station_id", "sample_date", "decimallongitude", "notes")
lon_col_exact <- TaxaFetch:::.detect_attr_col(
  attrs_exact_hit, exact = lon_exact_candidates, partial = lon_partial_candidates
)
lon_col_exact

# Case 2: no exact match, but a partial (substring) match -- e.g. a
# dataset-specific column name that still contains "longitude".
attrs_partial_hit <- c("site_code", "obs_longitude_deg")
lon_col_partial <- TaxaFetch:::.detect_attr_col(
  attrs_partial_hit, exact = lon_exact_candidates, partial = lon_partial_candidates
)
lon_col_partial

# Case 3: no match at all -- returns NA_character_, not an error.
attrs_no_hit <- c("station_id", "sample_date", "recorder_name")
lon_col_none <- TaxaFetch:::.detect_attr_col(
  attrs_no_hit, exact = lon_exact_candidates, partial = lon_partial_candidates
)
lon_col_none


# ==============================================================================
# SECTION 3 -- GBIF pipeline internal helper
# R/fetch_gbif_occurrences.R
# ==============================================================================

## ---- .gbif_default_year_range() ---- OFFLINE, pure function ----------------
# Fixture reused verbatim from tests/testthat/test-fetch_gbif_occurrences.R.
# Real 2026-08 human-review fix: this replaced a hardcoded "2000,2024"
# literal (duplicated across 5 functions) that was already silently
# excluding all 2025+ GBIF data by the time of the review -- computed fresh
# at call time instead.
gbif_year_range_default <- TaxaFetch:::.gbif_default_year_range()
gbif_year_range_default


# ==============================================================================
# SECTION 4 -- iNaturalist local-observation-count pipeline
# R/fetch_inat_occurrences.R
# ==============================================================================

## ---- .inat_observation_count() ---- NETWORK+AUTH ----------------------------
# Requires INAT_API_TOKEN in ~/.Renviron (also required by fetch_inat_
# occurrences() itself, below). This is the single-taxon count query against
# iNaturalist's real /v1/observations search endpoint -- exercised directly
# here rather than only indirectly through fetch_inat_occurrences(), so a
# reviewer can see its own NA-handling (non-200 status, missing
# total_results, 401) is reachable, not just its happy path.
#
# taxon_id resolved live via .inat_taxon_id() (check_inat_range.R, same
# package -- fetch_inat_occurrences() reuses it too, see its own roxygen)
# for the same real species used in review_function_inputs.R's
# check_inat_range() section (western sandpiper).
inat_token_for_count <- Sys.getenv("INAT_API_TOKEN")
sandpiper_info <- TaxaFetch:::.inat_taxon_id("Calidris mauri", inat_token_for_count)
sandpiper_info$taxon_id

n_local_sandpiper <- TaxaFetch:::.inat_observation_count(
  taxon_id      = sandpiper_info$taxon_id,
  lat           = 34.1,
  lng           = -119.1,
  radius_km     = 50,
  captive       = "any",
  quality_grade = "any",
  api_token     = inat_token_for_count
)
n_local_sandpiper

## ---- fetch_inat_occurrences() ---- NETWORK+AUTH, EXPORTED -------------------
# Requires INAT_API_TOKEN in ~/.Renviron. Real species/point from this
# function's own roxygen @examples (a domestic/commensal species, the
# motivating use case: standard GBIF-style indexing under-counts exactly
# these captive/cultivated organisms, which quality_grade = "any"/
# captive = "any" here deliberately surfaces).
inat_occ_result <- fetch_inat_occurrences(
  taxon_names   = c("Felis catus", "Calidris mauri"),
  lat           = 34.41,
  lng           = -119.86,
  captive       = "any",
  quality_grade = "any"
)
inat_occ_result


# ==============================================================================
# SECTION 5 -- GBIF quality-filter internal helpers
# R/filter_gbif_quality.R
# ==============================================================================

## ---- .nearest_institution() ---- OFFLINE, needs CoordinateCleaner ----------
# Fixture pattern reused from tests/testthat/test-filter_gbif_quality.R's own
# institution tests: pulls a REAL institution coordinate live from
# CoordinateCleaner's own bundled reference data (not a guessed/hand-typed
# value -- this package's own Known Footguns/session notes record that
# hand-replicating CoordinateCleaner's reference values previously produced
# conflicting numbers). Purely offline: CoordinateCleaner::institutions is
# bundled data, no network call.
real_institution_row <- CoordinateCleaner::institutions[
  !is.na(CoordinateCleaner::institutions$decimalLongitude) &
    !is.na(CoordinateCleaner::institutions$decimalLatitude), ][1, ]

nearest_institution_result <- TaxaFetch:::.nearest_institution(
  lon = real_institution_row$decimalLongitude,
  lat = real_institution_row$decimalLatitude
)
nearest_institution_result   # dist_m should be ~0 -- the query point IS that institution

## ---- .track_removed() ---- OFFLINE, pure function ---------------------------
# Small synthetic input mirroring filter_gbif_quality()'s own real usage
# (e.g. its "missing_coordinates" step): accumulates a removed-rows data
# frame, tagged with a single reason string recycled across all rows, into
# the running removed_list later combined via dplyr::bind_rows().
removed_rows_example <- data.frame(
  decimalLatitude  = c(NA_real_, NA_real_),
  decimalLongitude = c(-119.0, NA_real_),
  species          = c("Sp A", "Sp B"),
  stringsAsFactors = FALSE
)
removed_list_example <- TaxaFetch:::.track_removed(
  removed_list = list(),
  removed_rows = removed_rows_example,
  reason       = "missing_coordinates"
)
removed_list_example[[1]]

# A second call demonstrates removed_rows that already carry their own
# per-row filter_reason column (e.g. the CoordinateCleaner removal step,
# where a record can fail more than one check at once) -- reason is ignored
# in that case, used as-is instead.
removed_rows_with_own_reason <- data.frame(
  decimalLatitude  = 0.01,
  decimalLongitude = 0.01,
  species          = "Sp C",
  filter_reason    = "equal_coordinates;near_zero",
  stringsAsFactors = FALSE
)
removed_list_example2 <- TaxaFetch:::.track_removed(
  removed_list = removed_list_example,
  removed_rows = removed_rows_with_own_reason
)
dplyr::bind_rows(removed_list_example2)


# ==============================================================================
# SECTION 6 -- Geographic-outlier flagging
# R/check_geographic_outliers.R
# ==============================================================================

## ---- check_geographic_outliers() ---- NETWORK, EXPORTED --------------------
# Real, small-population GBIF species chosen deliberately for speed: Sebastes
# simulator (pygmy rockfish) has only ~100 GBIF occurrence records worldwide
# (checked live via the GBIF API before choosing it), so the global
# unrestricted fetch this function triggers for species below min_local_n
# stays small and fast, unlike a common species that could return
# thousands of rows. One local record (below the default min_local_n = 5)
# is enough to exercise the real global-fetch + CoordinateCleaner::cc_outl()
# code path end to end. cache_dir = NULL (matches tests/testthat/
# test-check_geographic_outliers.R's own convention) avoids writing a
# checkpoint file during this review run.
local_rare_occurrence <- data.frame(
  gbifID           = "900000001",
  species          = "Sebastes simulator",
  speciesKey       = 2335424L,
  decimalLatitude  = 34.10,
  decimalLongitude = -119.50,
  stringsAsFactors = FALSE
)
outlier_check_result <- check_geographic_outliers(
  local_rare_occurrence,
  cache_dir = NULL
)
outlier_check_result[, c("species", "local_n", "global_n_unique", "outlier_status")]
# Expected outlier_status here: "insufficient_global_data". This section's
# gbifID (900000001) is a synthetic placeholder, not a real GBIF record, so
# it never matches a row in the real global fetch by gbifID -- the join
# that would populate global_n_unique/outlier_status for this specific row
# has nothing to match against. This still exercises the function's real
# global-fetch + per-species cc_outl() code path end to end (confirmed live
# via the "fetch_gbif_occurrences: N records retrieved" message above); a
# real caller's local_occurrences would carry a genuine gbifID and get a
# real "outlier"/"consistent" verdict instead.


# ==============================================================================
# SECTION 7 -- Occurrence deduplication
# R/dedupe_occurrences.R
# ==============================================================================

## ---- dedupe_occurrences() ---- OFFLINE, pure function, EXPORTED ------------
# Fixture reused verbatim from tests/testthat/test-dedupe_occurrences.R:
# a duplicated gbifID (the exact-ID-match half of this function's two dedup
# mechanisms) should be dropped, first occurrence kept.
dedupe_input <- tibble::tibble(
  gbifID           = c("1", "2", "2", "3"),
  decimalLatitude  = c(34.40, 34.41, 34.41, 34.47),
  decimalLongitude = c(-120.41, -120.40, -120.40, -120.36)
)
dedupe_result <- dedupe_occurrences(dedupe_input)
dedupe_result
