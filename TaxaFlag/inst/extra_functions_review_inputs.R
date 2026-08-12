# ==============================================================================
# extra_functions_review_inputs.R
# TaxaFlag -- small, ready-to-run inputs for the 17 functions added AFTER this
# package's formal code review (reviewed 2026-08-07)
#
# PURPOSE
# -------
# All 17 functions below belong to the review_spatial_context() feature (a
# leaflet-based Shiny gadget showing GBIF occurrence-density tiles + iNat
# points + a study's own occurrence data, for a reviewer inspecting a flagged
# taxon) -- see TaxaFlag/CLAUDE.md's many 2026-08-07 session notes for the
# full design history. None of them existed at the time of the package's
# review, so none has ever had a reviewer-facing runnable example. This file
# is the companion to inst/... (there is no pre-existing
# review_function_inputs.R in this package -- checked inst/ directly before
# writing this) giving each of the 17 a small, concrete, ready-to-run input,
# following TaxaLikely/inst/review_function_inputs.R's established
# conventions exactly (REQUIRES tags, section banners, per-function
# subheaders with a short WHY comment).
#
# INTERNAL (dot-prefixed) FUNCTIONS -- NOTE ON `:::`
# ---------------------------------------------------
# 14 of the 17 functions are internal (`@noRd`) and called below via
# `TaxaFlag:::.function_name(...)`. This is expected and correct for a dev
# review of a source-installed package -- `:::` is the normal, supported way
# to reach an unexported function from outside its own package's namespace
# (e.g. from a plain Rscript session, as this file is meant to be run). It is
# NOT a bug or a sign these functions should be exported; they stay internal
# because none of them is meant to be part of this package's public API.
#
# THE THREE SHINY-GADGET FUNCTIONS -- NOT GIVEN A HARNESS
# ----------------------------------------------------------
# `review_spatial_context()` (the exported top-level launcher) and its two
# internal implementation functions, `.review_spatial_context_impl()` and
# `.build_spatial_context_server()`, are genuine interactive Shiny gadgets
# (miniUI + leaflet + shiny::paneViewer()) that block waiting for a real
# browser/RStudio viewer session. They cannot be meaningfully exercised as a
# standalone non-interactive R call, and no fake harness is built for them
# here -- see Section 7 below, which states this plainly and points the
# reviewer at calling review_spatial_context() directly in their own
# interactive R session instead. (The gadget's REACTIVE LOGIC does have real
# offline test coverage via shiny::testServer() --
# tests/testthat/test-review_spatial_context.R -- that's the right tool for
# verifying gadget behavior without a browser; this file's job is a
# reviewer-facing runnable EXAMPLE, a different thing.)
#
# Inputs are pulled from three sources, cheapest first:
#   1. This package's own existing testthat fixtures/mocking conventions
#      (test-check_gbif_tile_range.R, test-review_spatial_context.R) --
#      several NETWORK examples below reuse the exact real taxon/coordinate
#      pair (Neogobius melanostomus @ Burns Harbor, taxonKey 2379089) that
#      those test files and check_gbif_tile_range()'s own roxygen @examples
#      already use and that TaxaFlag/CLAUDE.md's session notes confirm was
#      live-verified as "near-occupied" (dist 0.91km) during development.
#   2. This package's own existing roxygen @examples (compute_local_
#      occurrence_distance()'s example is reused verbatim below).
#   3. New small synthetic inputs constructed for this file where neither
#      existed (the pure math/geometry helpers, and .summarise_spatial_
#      context()'s own small hand-built fixture).
#
# REQUIRES tags (read before running a section):
#   OFFLINE        -- pure function or fully self-contained input; no network
#   NETWORK        -- hits a public API (GBIF, iNaturalist), no credentials
#                     needed; kept small/fast by construction -- small taxa,
#                     narrow radii, small per_page/tile counts, matching this
#                     package's own documented "test against real small
#                     taxa/regions" convention (see check_gbif_tile_range.R's
#                     and test-check_gbif_tile_range.R's own real-data
#                     verification notes).
#   INTERACTIVE-ONLY (Section 7 only) -- a genuine blocking Shiny gadget;
#                     cannot be run from this script at all, documented, not
#                     executed.
#
# NON-DETERMINISM NOTE: every NETWORK section below hits real, live GBIF/
# iNaturalist services. Exact occurrence counts/tile pixel content can drift
# over time as those databases grow -- expected, not a bug, matching this
# package's and TaxaLikely's own documented convention for live NETWORK
# review sections. Neogobius melanostomus (round goby, a real, well-
# established Great Lakes invasive) is used throughout the GBIF-tile
# examples specifically because it was already confirmed, during this
# feature's own development, to be a real, stably "near-occupied" species at
# the Burns Harbor coordinates used -- not likely to flip to "beyond_buffer"
# between review sessions.
# ==============================================================================

#devtools::load_all()   # or: library(TaxaFlag)
library(TaxaFlag)


# ==============================================================================
# SECTION 1 -- Pure math/geometry helpers (Web Mercator tile <-> lon/lat,
# ground resolution, great-circle distance)
# .haversine_km() / .lonlat_to_tile_pixel() / .mercator_resolution_km()
# All three are pure functions -- no network, no package state -- extracted
# from R/compute_local_occurrence_distance.R and R/check_gbif_tile_range.R.
# ==============================================================================

## ---- .haversine_km() ---- OFFLINE -------------------------------------------
# Great-circle distance between the Burns Harbor query point used throughout
# this file's NETWORK sections and a second nearby Lake Michigan point --
# real coordinates, not arbitrary numbers, so the ~14km result is a sane
# sanity check against a map.
TaxaFlag:::.haversine_km(lat1 = 41.67, lon1 = -87.15, lat2 = 41.60, lon2 = -87.30)

## ---- .lonlat_to_tile_pixel() ---- OFFLINE ------------------------------------
# zoom = 0: the whole world is one 512x512 tile, and (lon=0, lat=0) is dead
# centre -- the exact hand-computable case test-check_gbif_tile_range.R uses
# to pin this function's correctness (expects xtile=0, ytile=0, px=256,
# py=256).
TaxaFlag:::.lonlat_to_tile_pixel(lat = 0, lon = 0, zoom = 0L, tile_size = 512L)

# A second, more realistic case: the real Burns Harbor query point at
# check_gbif_tile_range()'s own default zoom (6L) -- the tile x/y/pixel-offset
# this file's later GBIF-tile sections build on directly.
loc_burns_harbor <- TaxaFlag:::.lonlat_to_tile_pixel(lat = 41.67, lon = -87.15, zoom = 6L, tile_size = 512L)
loc_burns_harbor

## ---- .mercator_resolution_km() ---- OFFLINE ----------------------------------
# Real-world km-per-pixel at the Burns Harbor latitude/zoom -- confirms the
# documented Mercator distortion pattern (resolution shrinks with both
# increasing zoom and increasing |latitude|), matching this function's own
# existing test-check_gbif_tile_range.R assertions.
TaxaFlag:::.mercator_resolution_km(lat = 41.67, zoom = 6L, tile_size = 512L)
TaxaFlag:::.mercator_resolution_km(lat = 60,    zoom = 6L, tile_size = 512L)  # smaller: higher latitude
TaxaFlag:::.mercator_resolution_km(lat = 41.67, zoom = 8L, tile_size = 512L)  # smaller: finer zoom


# ==============================================================================
# SECTION 2 -- Patch/region-growing helpers
# .dilate8() / .grow_patch_size()
# Pure functions operating on a plain logical/numeric matrix -- no network,
# extracted from R/check_gbif_tile_range.R.
# ==============================================================================

## ---- .dilate8() ---- OFFLINE -------------------------------------------------
# A single TRUE seed cell in the middle of a 5x5 FALSE matrix -- one dilation
# step should grow it to its full 3x3 (8-connected + itself) neighbourhood,
# the exact case test-check_gbif_tile_range.R pins (expects sum == 9).
m <- matrix(FALSE, 5, 5)
m[3, 3] <- TRUE
TaxaFlag:::.dilate8(m)

## ---- .grow_patch_size() ---- OFFLINE -----------------------------------------
# A small isolated 2x2 occupied blob inside an otherwise-empty 10x10 field --
# the "one lone report vs. a small cluster" case this function exists to
# measure. Should converge (not hit max_iter) at size 4, capped = FALSE.
presence <- matrix(FALSE, 10, 10)
presence[5:6, 5:6] <- TRUE
TaxaFlag:::.grow_patch_size(presence, seed_row = 5L, seed_col = 5L)


# ==============================================================================
# SECTION 3 -- GBIF density-tile fetch + range check
# .fetch_gbif_tile_alpha() -> .check_gbif_tile_range_at_zoom() ->
# check_gbif_tile_range() (EXPORTED)
# All three make real, small GBIF map-tile API calls. Neogobius melanostomus
# (round goby, taxonKey 2379089) at Burns Harbor (41.67, -87.15) is the exact
# real species/coordinate pair check_gbif_tile_range()'s own roxygen
# @examples and test-check_gbif_tile_range.R's development notes use --
# confirmed near-occupied (dist ~0.91km) during this feature's own
# development, so it's a stable real positive case, not a fabricated one.
# ==============================================================================

## ---- .fetch_gbif_tile_alpha() ---- NETWORK, one small real GBIF tile --------
# Fetches exactly ONE real GBIF density tile (the tile covering Burns Harbor
# at zoom 6, the same tile check_gbif_tile_range()'s own default call would
# fetch as its centre tile) and reads back its alpha channel. Confirms the
# query pixel itself has non-zero alpha (round goby IS near-occupied here).
alpha <- TaxaFlag:::.fetch_gbif_tile_alpha(
  base_url  = "https://api.gbif.org/v2/map/occurrence/density",
  zoom      = 6L, x = loc_burns_harbor$xtile, y = loc_burns_harbor$ytile,
  taxon_key = 2379089L, tile_size = 512L
)
dim(alpha)
range(alpha)

## ---- .check_gbif_tile_range_at_zoom() ---- NETWORK, real 3x3-tile fetch -----
# One zoom level's worth of tile-fetch + presence/distance/patch computation
# -- the worker check_gbif_tile_range() calls repeatedly across its own
# escalation loop. Called directly here at the same real taxon/point/zoom the
# exported function's own default call resolves at (no escalation needed).
at_zoom <- TaxaFlag:::.check_gbif_tile_range_at_zoom(
  taxon_key = 2379089L, query_lat = 41.67, query_lon = -87.15,
  zoom = 6L, buffer_px = 512L,
  base_url  = "https://api.gbif.org/v2/map/occurrence/density",
  tile_size = 512L
)
at_zoom[c("found", "n_tiles_fetched", "point_occupied", "resolution_km_per_px")]

## ---- check_gbif_tile_range() ---- NETWORK, real small taxon -----------------
# Reused verbatim from this function's own roxygen @examples -- the exact
# real species/point pair used throughout this section.
range_result <- check_gbif_tile_range(
  taxon_key = 2379089L,  # Neogobius melanostomus (round goby)
  query_lat = 41.67, query_lon = -87.15
)
range_result[, c("point_occupied", "dist_nearest_occupied_km", "patch_diameter_km", "beyond_buffer")]


# ==============================================================================
# SECTION 4 -- Local occurrence distance (free -- reuses a workflow's own
# already-fetched occurrence data, no network call at all)
# compute_local_occurrence_distance() (EXPORTED)
# ==============================================================================

## ---- compute_local_occurrence_distance() ---- OFFLINE ------------------------
# Reused verbatim from this function's own roxygen @examples: a small
# synthetic occurrence table (as if already fetched by a workflow's own
# TaxaFetch step) checked against one present and one genuinely absent taxon.
occ <- data.frame(
  taxon_name        = c("Neogobius melanostomus", "Neogobius melanostomus"),
  decimalLatitude   = c(41.60, 42.10),
  decimalLongitude  = c(-87.10, -87.80)
)
compute_local_occurrence_distance(
  taxon_names     = c("Neogobius melanostomus", "Salmo salar"),
  query_lat       = 41.67, query_lon = -87.15,
  occurrence_data = occ
)


# ==============================================================================
# SECTION 5 -- Spatial-context gadget helpers: pure/testable pieces extracted
# from review_spatial_context()'s reactive/render closures specifically so
# they can be unit-tested (and, here, run) independent of the gadget itself
# .gbif_tile_url() / .gbif_legend_swatch() / .summarise_spatial_context()
# ==============================================================================

## ---- .gbif_tile_url() ---- OFFLINE --------------------------------------------
# Reused from tests/testthat/test-review_spatial_context.R's own coverage:
# the .point->.poly auto-upgrade + bin=square/squareSize params fire for a
# bare "classic.point" style once a bin_size is supplied.
TaxaFlag:::.gbif_tile_url(taxon_key = 2379089L, style = "classic.point", bin_size = 256L, year_range = NULL)

# Heat-family styles have no .poly counterpart and are left unbinned even
# when bin_size is supplied -- confirmed live during development (silent
# no-op), reproduced here directly.
TaxaFlag:::.gbif_tile_url(taxon_key = 2379089L, style = "purpleHeat.point", bin_size = 256L, year_range = NULL)

## ---- .gbif_legend_swatch() ---- OFFLINE ---------------------------------------
# Real, sampled colours (see this function's own roxygen for the live-tile
# verification record) -- "classic" and an unverified style both shown, so
# the fallback-to-gray path is visible too, not just the happy path.
TaxaFlag:::.gbif_legend_swatch("classic.point")
TaxaFlag:::.gbif_legend_swatch("outline.poly")  # not in the verified set -> gray fallback

## ---- .summarise_spatial_context() ---- OFFLINE --------------------------------
# Small hand-built fixture (new, no existing test/roxygen source covers this
# exact call shape) mirroring what review_assignments()'s own
# .summarise_spatial_context() call site expects: a data frame carrying
# check_gbif_tile_range()/compute_local_occurrence_distance()-style GBIF
# columns and TaxaFetch::check_inat_range()-style iNat columns, one row per
# taxon (real callers typically get here via a per-taxon join). Two rows
# share a label (Neogobius melanostomus) to exercise the median-aggregation
# path; the third (Barbatula barbatula) is a real beyond_buffer/no-iNat-data
# case.
sc_df <- data.frame(
  taxon                     = c("Neogobius melanostomus", "Neogobius melanostomus", "Barbatula barbatula"),
  dist_nearest_occupied_km  = c(0.9, 0.9, NA_real_),
  patch_diameter_km         = c(6.6, 6.6, NA_real_),
  beyond_buffer              = c(FALSE, FALSE, TRUE),
  in_range                   = c(TRUE, TRUE, NA),
  n_observations             = c(1275, 1275, NA_real_),
  matched_name                = c("Neogobius melanostomus", "Neogobius melanostomus", NA_character_),
  stringsAsFactors = FALSE
)
TaxaFlag:::.summarise_spatial_context(
  label_vec = sc_df$taxon, input_df = sc_df,
  dist_nearest_occupied_km_col = "dist_nearest_occupied_km",
  patch_diameter_km_col        = "patch_diameter_km",
  beyond_buffer_col            = "beyond_buffer",
  inat_in_range_col            = "in_range",
  inat_n_observations_col      = "n_observations",
  inat_matched_name_col        = "matched_name"
)


# ==============================================================================
# SECTION 6 -- Spatial-context gadget network helpers: the two live calls the
# gadget's reactive layer makes when a taxon is selected.
# .resolve_gbif_taxon_key() / .fetch_inat_points()
# ==============================================================================

## ---- .resolve_gbif_taxon_key() ---- NETWORK, real GBIF species-match -------
# Resolves the exact real species name used throughout Section 3 -- should
# recover the same usageKey (2379089) hardcoded there, confirming the two
# real GBIF-side entry points (name resolution here; density tiles in
# Section 3) agree on the same taxon.
TaxaFlag:::.resolve_gbif_taxon_key("Neogobius melanostomus")

## ---- .fetch_inat_points() ---- NETWORK, small real iNat point fetch --------
# American Robin (Turdus migratorius, iNat taxon_id 12727 -- a common,
# fast-responding real iNat taxon already used elsewhere in this ecosystem's
# own acoustic-calibration real-data work, see TaxaLikely/CLAUDE.md's Session
# 133 note) near the same Chicago-area query point, capped small
# (radius_km=25, per_page=5) to keep this a fast, bounded real call.
inat_pts <- TaxaFlag:::.fetch_inat_points(
  taxon_id = 12727L, lat = 41.67, lng = -87.15, radius_km = 25, per_page = 5L
)
inat_pts


# ==============================================================================
# SECTION 7 -- Interactive Shiny gadget: NOT runnable from this script
# .build_spatial_context_server() / .review_spatial_context_impl() /
# review_spatial_context() (EXPORTED)
# ==============================================================================

## ---- review_spatial_context() ---- INTERACTIVE-ONLY, cannot be run here -----
# review_spatial_context() is a genuine, blocking Shiny gadget
# (miniUI::miniPage() + leaflet + shiny::runGadget(..., viewer =
# shiny::paneViewer())) -- it opens a real interactive pane/browser window
# and does not return until the reviewer clicks "Close". Calling it from a
# non-interactive Rscript session immediately errors ("must be run in an
# interactive R session") by design (see its own explicit `if (!interactive())
# stop(...)` guard) -- there is no way to fabricate a harness that exercises
# the real thing here, and this file does not attempt one.
#
# To actually exercise this function, run the following directly in your own
# interactive R/RStudio session (not via Rscript):
#
#   consensus_final <- data.frame(
#     primary_taxon        = c("Neogobius melanostomus", "Barbatula barbatula"),
#     primary_plausibility = c("expected", "unprecedented"),
#     stringsAsFactors = FALSE
#   )
#   review_spatial_context(
#     input_df    = consensus_final,
#     query_lat   = 41.67, query_lon = -87.15,          # Burns Harbor, Lake Michigan
#     taxon_col        = "primary_taxon",
#     plausibility_col = "primary_plausibility"
#     # Optionally also supply: occurrence_data (a real fetched-occurrence
#     # data frame), inat_range, context/target_group/marker (to enable the
#     # "Run AI Review" button -- see review_spatial_context()'s own roxygen
#     # @param docs for every argument's exact shape).
#   )
#
# What this needs, per the function's own roxygen: `input_df` (a data frame
# with at least a taxon column), `query_lat`/`query_lon` (the study site),
# and optionally `occurrence_data`/`inat_range`/`context` to light up the
# gadget's optional panels. See review_spatial_context()'s own @param
# section (R/review_spatial_context.R) for the complete argument list.
#
# The gadget's REACTIVE LOGIC (as opposed to the browser-rendered UI itself)
# IS covered by real, non-interactive tests -- see
# tests/testthat/test-review_spatial_context.R, which drives
# .build_spatial_context_server() directly via shiny::testServer() (Shiny's
# own supported mechanism for exercising server-side reactive code without a
# real browser). That is the right tool for verifying this gadget's behavior
# programmatically; it is a different thing from a reviewer-facing runnable
# example, which is what this file provides for every OTHER function.

## ---- .review_spatial_context_impl() ---- INTERACTIVE-ONLY, cannot be run here
# The actual UI (miniUI::miniPage()) + server construction +
# shiny::runGadget() call, split out of review_spatial_context() purely so it
# can be invoked directly, bypassing the interactive()-only gate, for live
# browser-based verification during development (see its own @noRd comment).
# It is NOT a supported public bypass and is just as blocking/interactive as
# review_spatial_context() itself -- calling it still opens a real gadget
# window and waits for a human to close it. Same guidance as above: run
# review_spatial_context() itself in your own interactive session; don't
# call this internal function directly.

## ---- .build_spatial_context_server() ---- INTERACTIVE-ONLY, cannot be run here
# Builds the gadget's `function(input, output, session)` server closure --
# the piece review_spatial_context() and .review_spatial_context_impl() both
# hand to shiny::runGadget()/shiny::paneViewer() to actually run. On its own
# it is just a function value (constructing it does not open a gadget or
# block), but it is meaningless outside either (a) a real running Shiny
# session (review_spatial_context() itself), or (b) shiny::testServer()
# (test-review_spatial_context.R's approach, for verifying reactive logic
# only, not for a reviewer-facing "run this and look at it" example). Not
# demonstrated here for that reason; see test-review_spatial_context.R's
# `.make_server()` helper if you want to see every argument this function
# takes exercised programmatically, or run review_spatial_context() itself
# per the guidance above to see the real, rendered gadget.
