# test-generate_regional_proximity_evidence.R
# Tests for generate_regional_proximity_evidence().
#
# Fully offline: mocks the three network-boundary calls
# (rgbif::name_backbone_checklist, TaxaFlag::check_gbif_tile_range,
# TaxaFetch::get_gbif_occurrences) plus TaxaFetch::filter_gbif_quality()
# (pass-through by default, since real CoordinateCleaner behavior is
# TaxaFetch's own concern, not this function's). TaxaFlag::
# compute_local_occurrence_distance() is genuinely REAL and unmocked --
# same "mock only the network boundary, let the real math run underneath"
# convention TaxaFetch::test-check_geographic_outliers.R already uses.
#
# 2026-08-22: name resolution switched from a per-taxon rgbif::name_backbone()
# loop to ONE rgbif::name_backbone_checklist() call (real, verified GBIF-level
# batching win -- see this file's own top session note in TaxaExpect/CLAUDE.md).
# Every mock below targets name_backbone_checklist accordingly; `.mock_key()`
# now builds a one-row-per-name checklist-shaped response including a
# `species` column (GBIF's own accepted name for the resolved key -- defaults
# to echoing the query name itself, the common non-synonym case).
#
# 2026-08-22, continued: a REAL production run (194 real taxa) surfaced a
# second, pre-existing bug (present in the function's original single-call
# form too, just never exercised by the earlier 3-species validation): a
# query name that matches a GBIF SYNONYM's own scientific name resolves to
# that synonym's usageKey, whose real occurrence records report GBIF's
# CURRENTLY ACCEPTED name in their own `species` field -- matching those
# records against the ORIGINAL query name (not the accepted name) silently
# finds nothing, even though real, quality-filtered occurrence data exists.
# Fixed by using the resolved `gbif_species` (not the query name) for the
# internal occurrence-matching step; `taxon_name` in the OUTPUT still reports
# the original query name (the caller's own join key). New tests below cover
# this directly, both at the `.resolve_gbif_taxon_keys_batch()` unit level and
# end to end through `generate_regional_proximity_evidence()` itself.

library(testthat)
library(dplyr)

.mock_key <- function(key = 12345, species = NULL) {
  function(name_data, rank, ...) {
    if (is.na(key)) {
      return(tibble::tibble(
        verbatim_name = name_data$name, usageKey = NA_real_,
        rank = NA_character_, species = NA_character_
      ))
    }
    sp <- if (is.null(species)) name_data$name else rep(species, length(name_data$name))
    tibble::tibble(
      verbatim_name = name_data$name, usageKey = key, rank = "SPECIES", species = sp
    )
  }
}

.mock_tile <- function(beyond_buffer = FALSE, dist_km = 80, zoom_used = 6L) {
  function(taxon_key, query_lat, query_lon, zoom = 6L, ...) {
    data.frame(
      taxon_key = taxon_key, query_lat = query_lat, query_lon = query_lon,
      zoom_requested = zoom, zoom_used = if (beyond_buffer) NA_integer_ else zoom_used,
      escalated = FALSE, tile_size = 512L, n_tiles_fetched = 9L,
      resolution_km_per_px = 10, point_occupied = FALSE,
      dist_nearest_occupied_km = if (beyond_buffer) NA_real_ else dist_km,
      patch_size_px = if (beyond_buffer) NA_integer_ else 5L,
      patch_size_capped = if (beyond_buffer) NA else FALSE,
      patch_area_km2 = if (beyond_buffer) NA_real_ else 500,
      patch_diameter_km = if (beyond_buffer) NA_real_ else 22,
      beyond_buffer = beyond_buffer,
      stringsAsFactors = FALSE
    )
  }
}

.mock_occ <- function(taxon_name, n = 1L, year = 2020, lat = 41.68, lon = -87.14) {
  function(keys, geometry, ...) {
    tibble::tibble(
      species          = rep(taxon_name, n),
      decimalLatitude  = rep(lat, n),
      decimalLongitude = rep(lon, n),
      year             = rep(year, n)
    )
  }
}

.passthrough_filter <- function(data, ...) data

# =============================================================================
# Input validation
# =============================================================================

test_that("stops on empty zero_bbox_taxa", {
  expect_error(
    generate_regional_proximity_evidence(character(0), lat = 41, lng = -87),
    "non-empty"
  )
})

test_that("stops on invalid lat/lng", {
  expect_error(
    generate_regional_proximity_evidence("Gadus morhua", lat = NA_real_, lng = -87),
    "non-NA"
  )
})

test_that("stops on non-positive d_half/age_half", {
  expect_error(
    generate_regional_proximity_evidence("Gadus morhua", lat = 41, lng = -87, d_half = 0),
    "d_half"
  )
  expect_error(
    generate_regional_proximity_evidence("Gadus morhua", lat = 41, lng = -87, age_half = -1),
    "age_half"
  )
})

# =============================================================================
# Happy path -- full Stage 1 -> Stage 2 pipeline
# =============================================================================

test_that("a taxon clearing both stages gets a correctly-computed evidence row", {
  local_mocked_bindings(name_backbone_checklist = .mock_key(), .package = "rgbif")
  local_mocked_bindings(check_gbif_tile_range = .mock_tile(dist_km = 80), .package = "TaxaFlag")
  local_mocked_bindings(
    get_gbif_occurrences = .mock_occ("Etheostoma chlorosomum", year = 2020),
    filter_gbif_quality = .passthrough_filter,
    .package = "TaxaFetch"
  )

  out <- generate_regional_proximity_evidence(
    "Etheostoma chlorosomum",
    lat = 41.67, lng = -87.15,
    d_half = 150, age_half = 15
  )

  expect_equal(nrow(out), 1L)
  expect_equal(out$taxon_name, "Etheostoma chlorosomum")
  expect_equal(out$source, "regional_proximity")
  expect_true(out$weight >= 0 && out$weight <= 1)
  expect_equal(out$weight, exp(-out$distance_km / 150), tolerance = 1e-6)
  current_year <- as.numeric(format(Sys.Date(), "%Y"))
  expect_equal(out$age_years, current_year - 2020)
  expect_equal(out$p_conc, exp(-out$age_years / 15), tolerance = 1e-6)
})

test_that("weight/p_conc scale correctly with d_half/age_half overrides", {
  # Note: weight/p_conc are driven by Stage 2's REAL (haversine) distance --
  # dist_out$dist_nearest_km, computed from the mocked occurrence point's own
  # lat/lon -- not Stage 1's coarse tile-based dist_km (which only sizes the
  # Stage 2 fetch radius). So this asserts self-consistency against whatever
  # real distance the mocked occurrence point produces, not a hardcoded value.
  local_mocked_bindings(name_backbone_checklist = .mock_key(), .package = "rgbif")
  local_mocked_bindings(check_gbif_tile_range = .mock_tile(dist_km = 100), .package = "TaxaFlag")
  local_mocked_bindings(
    get_gbif_occurrences = .mock_occ("Gadus morhua", year = as.numeric(format(Sys.Date(), "%Y"))),
    filter_gbif_quality = .passthrough_filter,
    .package = "TaxaFetch"
  )

  out <- generate_regional_proximity_evidence(
    "Gadus morhua",
    lat = 41.67, lng = -87.15, d_half = 50
  )
  expect_equal(out$weight, exp(-out$distance_km / 50), tolerance = 1e-6)
  expect_equal(out$age_years, 0)
  expect_equal(out$p_conc, 1) # age 0 -> a fresh record = one pseudo-observation
})

test_that("a record with no usable year gets p_conc == 1, not a value in between", {
  local_mocked_bindings(name_backbone_checklist = .mock_key(), .package = "rgbif")
  local_mocked_bindings(check_gbif_tile_range = .mock_tile(dist_km = 80), .package = "TaxaFlag")
  local_mocked_bindings(
    get_gbif_occurrences = .mock_occ("Gadus morhua", year = NA_real_),
    filter_gbif_quality = .passthrough_filter,
    .package = "TaxaFetch"
  )

  out <- generate_regional_proximity_evidence("Gadus morhua", lat = 41.67, lng = -87.15)
  expect_true(is.na(out$age_years))
  expect_equal(out$p_conc, 1)
})

# =============================================================================
# Synonym resolution -- real production bug, 2026-08-22
# =============================================================================

test_that("a query name matching a GBIF SYNONYM still produces evidence, matched via the ACCEPTED species name", {
  # Real motivating case: querying "Erimonax monachus" (a real synonym)
  # resolves to a real usageKey whose occurrence records report GBIF's
  # accepted name, "Cyprinella monacha" -- not the query string itself. The
  # `taxon_name` in the OUTPUT must still be the original query name (the
  # caller's own join key), even though internal matching used the accepted
  # name to actually find the fetched records.
  local_mocked_bindings(
    name_backbone_checklist = .mock_key(species = "Cyprinella monacha"),
    .package = "rgbif"
  )
  local_mocked_bindings(check_gbif_tile_range = .mock_tile(dist_km = 80), .package = "TaxaFlag")
  local_mocked_bindings(
    get_gbif_occurrences = .mock_occ("Cyprinella monacha", year = 2015), # GBIF's ACCEPTED name, not the query
    filter_gbif_quality = .passthrough_filter,
    .package = "TaxaFetch"
  )

  out <- generate_regional_proximity_evidence("Erimonax monachus", lat = 41.67, lng = -87.15)
  expect_equal(nrow(out), 1L)
  expect_equal(out$taxon_name, "Erimonax monachus") # original query, not "Cyprinella monacha"
})

test_that("without the gbif_species fix, a synonym query would find zero matching records (negative control)", {
  # Confirms the bug this fix closes is real: matching against the ORIGINAL
  # query name (what the code did before this fix) genuinely fails to find
  # the fetched records, which are filed under the accepted name.
  dist_out <- TaxaFlag::compute_local_occurrence_distance(
    taxon_names = "Erimonax monachus", # the query/synonym name
    query_lat = 41.67, query_lon = -87.15,
    occurrence_data = tibble::tibble(
      species = "Cyprinella monacha", decimalLatitude = 41.68, decimalLongitude = -87.14
    ),
    taxon_col = "species"
  )
  expect_equal(dist_out$n_local_records, 0L)
})

# =============================================================================
# Skip conditions -- each stage can end the pipeline for one taxon without erroring
# =============================================================================

test_that("a taxon with no GBIF backbone match is skipped, not an error", {
  local_mocked_bindings(name_backbone_checklist = .mock_key(key = NA_real_), .package = "rgbif")

  out <- generate_regional_proximity_evidence("Completely Fictional sp.", lat = 41.67, lng = -87.15)
  expect_equal(nrow(out), 0L)
  expect_true(all(c("taxon_name", "weight", "p_conc", "source") %in% names(out)))
})

test_that("a bare genus name that resolves to a GENUS-rank record is rejected, not silently accepted (real bug found on real GreatLakes2023 data: 'Ictalurus' alone matched via name_backbone(rank='species') despite that argument being a hint, not an enforced constraint)", {
  local_mocked_bindings(
    name_backbone_checklist = function(name_data, rank, ...) {
      tibble::tibble(verbatim_name = name_data$name, usageKey = 44, rank = "GENUS", species = NA_character_)
    },
    .package = "rgbif"
  )
  fetch_called <- FALSE
  local_mocked_bindings(
    get_gbif_occurrences = function(...) {
      fetch_called <<- TRUE
      tibble::tibble()
    },
    .package = "TaxaFetch"
  )

  out <- generate_regional_proximity_evidence("Ictalurus", lat = 41.67, lng = -87.15)
  expect_equal(nrow(out), 0L)
  expect_false(fetch_called) # never even reached Stage 1's tile check
})

test_that("a name_backbone_checklist() response missing a rank field entirely is treated as no match", {
  local_mocked_bindings(
    name_backbone_checklist = function(name_data, rank, ...) {
      tibble::tibble(verbatim_name = name_data$name, usageKey = 44)
    },
    .package = "rgbif"
  )
  out <- generate_regional_proximity_evidence("Some Genus", lat = 41.67, lng = -87.15)
  expect_equal(nrow(out), 0L)
})

test_that("Stage 1 beyond_buffer = TRUE skips the taxon and never triggers a Stage 2 fetch", {
  local_mocked_bindings(name_backbone_checklist = .mock_key(), .package = "rgbif")
  local_mocked_bindings(check_gbif_tile_range = .mock_tile(beyond_buffer = TRUE), .package = "TaxaFlag")

  fetch_called <- FALSE
  local_mocked_bindings(
    get_gbif_occurrences = function(...) {
      fetch_called <<- TRUE
      tibble::tibble()
    },
    .package = "TaxaFetch"
  )

  out <- generate_regional_proximity_evidence("Alburnus alburnus", lat = 41.67, lng = -87.15)
  expect_equal(nrow(out), 0L)
  expect_false(fetch_called)
})

test_that("Stage 2 fetch returning zero rows skips the taxon", {
  local_mocked_bindings(name_backbone_checklist = .mock_key(), .package = "rgbif")
  local_mocked_bindings(check_gbif_tile_range = .mock_tile(dist_km = 80), .package = "TaxaFlag")
  local_mocked_bindings(
    get_gbif_occurrences = function(...) tibble::tibble(),
    .package = "TaxaFetch"
  )

  out <- generate_regional_proximity_evidence("Ictalurus furcatus", lat = 41.67, lng = -87.15)
  expect_equal(nrow(out), 0L)
})

test_that("everything failing quality filtering skips the taxon", {
  local_mocked_bindings(name_backbone_checklist = .mock_key(), .package = "rgbif")
  local_mocked_bindings(check_gbif_tile_range = .mock_tile(dist_km = 80), .package = "TaxaFlag")
  local_mocked_bindings(
    get_gbif_occurrences = .mock_occ("Gadus morhua"),
    filter_gbif_quality = function(data, ...) data[0, , drop = FALSE],
    .package = "TaxaFetch"
  )

  out <- generate_regional_proximity_evidence("Gadus morhua", lat = 41.67, lng = -87.15)
  expect_equal(nrow(out), 0L)
})

# =============================================================================
# Multi-taxon batches
# =============================================================================

test_that("one failing taxon does not block another succeeding in the same call", {
  local_mocked_bindings(
    name_backbone_checklist = function(name_data, rank, ...) {
      tibble::tibble(
        verbatim_name = name_data$name,
        usageKey = ifelse(name_data$name == "Fictional sp.", NA_real_, 999),
        rank = ifelse(name_data$name == "Fictional sp.", NA_character_, "SPECIES"),
        species = ifelse(name_data$name == "Fictional sp.", NA_character_, name_data$name)
      )
    },
    .package = "rgbif"
  )
  local_mocked_bindings(check_gbif_tile_range = .mock_tile(dist_km = 80), .package = "TaxaFlag")
  local_mocked_bindings(
    get_gbif_occurrences = function(keys, geometry, ...) .mock_occ("Gadus morhua")(keys, geometry),
    filter_gbif_quality = .passthrough_filter,
    .package = "TaxaFetch"
  )

  out <- generate_regional_proximity_evidence(
    c("Fictional sp.", "Gadus morhua"),
    lat = 41.67, lng = -87.15
  )
  expect_equal(nrow(out), 1L)
  expect_equal(out$taxon_name, "Gadus morhua")
})

test_that("duplicate taxon names in zero_bbox_taxa are only checked once", {
  local_mocked_bindings(name_backbone_checklist = .mock_key(), .package = "rgbif")
  n_tile_calls <- 0L
  local_mocked_bindings(
    check_gbif_tile_range = function(...) {
      n_tile_calls <<- n_tile_calls + 1L
      .mock_tile(dist_km = 80)(...)
    },
    .package = "TaxaFlag"
  )
  local_mocked_bindings(
    get_gbif_occurrences = .mock_occ("Gadus morhua"),
    filter_gbif_quality = .passthrough_filter,
    .package = "TaxaFetch"
  )

  out <- generate_regional_proximity_evidence(
    c("Gadus morhua", "Gadus morhua"),
    lat = 41.67, lng = -87.15
  )
  expect_equal(nrow(out), 1L)
  expect_equal(n_tile_calls, 1L)
})

test_that("name resolution happens in exactly ONE batched call regardless of taxa count (2026-08-22)", {
  n_checklist_calls <- 0L
  local_mocked_bindings(
    name_backbone_checklist = function(name_data, rank, ...) {
      n_checklist_calls <<- n_checklist_calls + 1L
      .mock_key()(name_data, rank, ...)
    },
    .package = "rgbif"
  )
  local_mocked_bindings(check_gbif_tile_range = .mock_tile(beyond_buffer = TRUE), .package = "TaxaFlag")

  out <- generate_regional_proximity_evidence(
    c("Gadus morhua", "Etheostoma chlorosomum", "Ictalurus furcatus"),
    lat = 41.67, lng = -87.15
  )
  expect_equal(n_checklist_calls, 1L)
  expect_equal(nrow(out), 0L) # beyond_buffer for all -- irrelevant to this test's assertion
})

# =============================================================================
# near_lat_tolerance_deg/near_occurrence_min_n -- isolated-record safeguard
# (ported from build_invasive_candidates.R after a real GLANSIS benchmark
# comparison found the plain nearest-point test alone is precision-poor)
# =============================================================================

.mock_occ_multi <- function(species, lats, lons, years) {
  force(species)
  force(lats)
  force(lons)
  force(years)
  function(keys, geometry, ...) {
    tibble::tibble(
      species = rep(species, length(lats)),
      decimalLatitude = lats, decimalLongitude = lons, year = years
    )
  }
}

test_that("a single isolated record far in latitude from the study site is rejected (proportional fallback correctly requires proximity)", {
  local_mocked_bindings(name_backbone_checklist = .mock_key(), .package = "rgbif")
  local_mocked_bindings(check_gbif_tile_range = .mock_tile(dist_km = 80), .package = "TaxaFlag")
  local_mocked_bindings(
    get_gbif_occurrences = .mock_occ_multi("Astronotus ocellatus", lats = 25.0, lons = -87.15, years = 2019),
    filter_gbif_quality = .passthrough_filter,
    .package = "TaxaFetch"
  )

  out <- generate_regional_proximity_evidence(
    "Astronotus ocellatus",
    lat = 41.67, lng = -87.15
  )
  expect_equal(nrow(out), 0L)
})

test_that("a single isolated record CLOSE in latitude still clears the proportional fallback", {
  local_mocked_bindings(name_backbone_checklist = .mock_key(), .package = "rgbif")
  local_mocked_bindings(check_gbif_tile_range = .mock_tile(dist_km = 80), .package = "TaxaFlag")
  local_mocked_bindings(
    get_gbif_occurrences = .mock_occ_multi("Carassius carassius", lats = 41.68, lons = -87.14, years = 2020),
    filter_gbif_quality = .passthrough_filter,
    .package = "TaxaFetch"
  )

  out <- generate_regional_proximity_evidence(
    "Carassius carassius",
    lat = 41.67, lng = -87.15
  )
  expect_equal(nrow(out), 1L)
})

test_that("several records but too few near the study site's latitude are rejected", {
  local_mocked_bindings(name_backbone_checklist = .mock_key(), .package = "rgbif")
  local_mocked_bindings(check_gbif_tile_range = .mock_tile(dist_km = 80), .package = "TaxaFlag")
  local_mocked_bindings(
    get_gbif_occurrences = .mock_occ_multi(
      "Cichla ocellaris",
      lats = c(41.68, 25.0, 24.5, 26.1, 25.7), lons = rep(-87.15, 5), years = rep(2018, 5)
    ),
    filter_gbif_quality = .passthrough_filter,
    .package = "TaxaFetch"
  )

  out <- generate_regional_proximity_evidence(
    "Cichla ocellaris",
    lat = 41.67, lng = -87.15,
    near_lat_tolerance_deg = 6, near_occurrence_min_n = 3L
  )
  expect_equal(nrow(out), 0L) # only 1 of 5 records within tolerance, need >= 3
})

test_that("enough records genuinely clustered near the study site's latitude clear the test", {
  local_mocked_bindings(name_backbone_checklist = .mock_key(), .package = "rgbif")
  local_mocked_bindings(check_gbif_tile_range = .mock_tile(dist_km = 80), .package = "TaxaFlag")
  local_mocked_bindings(
    get_gbif_occurrences = .mock_occ_multi(
      "Gymnocephalus cernua",
      lats = c(46.5, 46.7, 46.6, 25.0), lons = rep(-87.15, 4), years = rep(2019, 4)
    ),
    filter_gbif_quality = .passthrough_filter,
    .package = "TaxaFetch"
  )

  out <- generate_regional_proximity_evidence(
    "Gymnocephalus cernua",
    lat = 41.67, lng = -87.15,
    near_lat_tolerance_deg = 6, near_occurrence_min_n = 3L
  )
  expect_equal(nrow(out), 1L) # 3 of 4 records within 6 deg latitude
})

test_that("near_occurrence_min_n = 0 disables the safeguard entirely (original nearest-point-only behavior)", {
  local_mocked_bindings(name_backbone_checklist = .mock_key(), .package = "rgbif")
  local_mocked_bindings(check_gbif_tile_range = .mock_tile(dist_km = 80), .package = "TaxaFlag")
  local_mocked_bindings(
    get_gbif_occurrences = .mock_occ_multi("Astronotus ocellatus", lats = 25.0, lons = -87.15, years = 2019),
    filter_gbif_quality = .passthrough_filter,
    .package = "TaxaFetch"
  )

  out <- generate_regional_proximity_evidence(
    "Astronotus ocellatus",
    lat = 41.67, lng = -87.15, near_occurrence_min_n = 0L
  )
  expect_equal(nrow(out), 1L)
})

test_that("stops on invalid near_lat_tolerance_deg/near_occurrence_min_n", {
  expect_error(
    generate_regional_proximity_evidence("Gadus morhua", lat = 41, lng = -87, near_lat_tolerance_deg = 0),
    "near_lat_tolerance_deg"
  )
  expect_error(
    generate_regional_proximity_evidence("Gadus morhua", lat = 41, lng = -87, near_occurrence_min_n = -1),
    "near_occurrence_min_n"
  )
})

# =============================================================================
# .resolve_gbif_taxon_keys_batch() -- direct unit tests
# =============================================================================

test_that(".resolve_gbif_taxon_keys_batch() resolves multiple names correctly, matched by verbatim_name not position", {
  local_mocked_bindings(
    name_backbone_checklist = function(name_data, rank, ...) {
      # Deliberately returns rows in REVERSED order to confirm matching is
      # by verbatim_name, not row position.
      tibble::tibble(
        verbatim_name = rev(name_data$name),
        usageKey      = rev(seq_along(name_data$name)),
        rank          = "SPECIES",
        species       = rev(name_data$name)
      )
    },
    .package = "rgbif"
  )
  out <- .resolve_gbif_taxon_keys_batch(c("Homo sapiens", "Canis lupus", "Felis catus"))
  expect_equal(out$taxon_name, c("Homo sapiens", "Canis lupus", "Felis catus"))
  expect_equal(out$usage_key, c(1, 2, 3))
  expect_equal(out$gbif_species, c("Homo sapiens", "Canis lupus", "Felis catus"))
})

test_that(".resolve_gbif_taxon_keys_batch() gives NA for a fictional name, a genus-only match, and rejects non-species rank", {
  local_mocked_bindings(
    name_backbone_checklist = function(name_data, rank, ...) {
      tibble::tibble(
        verbatim_name = name_data$name,
        usageKey = c(1, NA_real_, 44),
        rank = c("SPECIES", NA_character_, "GENUS"),
        species = c("Homo sapiens", NA_character_, NA_character_)
      )
    },
    .package = "rgbif"
  )
  out <- .resolve_gbif_taxon_keys_batch(c("Homo sapiens", "Fictional sp.", "Ictalurus"))
  expect_equal(out$usage_key, c(1, NA_real_, NA_real_))
  expect_equal(out$gbif_species, c("Homo sapiens", NA_character_, NA_character_))
})

test_that(".resolve_gbif_taxon_keys_batch() gives the ACCEPTED species name for a resolved synonym, not the query name (real production bug)", {
  local_mocked_bindings(
    name_backbone_checklist = function(name_data, rank, ...) {
      tibble::tibble(
        verbatim_name = "Erimonax monachus", usageKey = 2367386,
        rank = "SPECIES", species = "Cyprinella monacha"
      )
    },
    .package = "rgbif"
  )
  out <- .resolve_gbif_taxon_keys_batch("Erimonax monachus")
  expect_equal(out$taxon_name, "Erimonax monachus")
  expect_equal(out$usage_key, 2367386)
  expect_equal(out$gbif_species, "Cyprinella monacha")
})

test_that(".resolve_gbif_taxon_keys_batch() returns all-NA gracefully on an error or empty/missing response", {
  local_mocked_bindings(
    name_backbone_checklist = function(name_data, rank, ...) stop("network error"),
    .package = "rgbif"
  )
  expect_warning(
    out <- .resolve_gbif_taxon_keys_batch(c("Homo sapiens", "Canis lupus")),
    "GBIF name resolution failed"
  )
  expect_true(all(is.na(out$usage_key)))
  expect_true(all(is.na(out$gbif_species)))
  expect_equal(out$taxon_name, c("Homo sapiens", "Canis lupus"))

  local_mocked_bindings(
    name_backbone_checklist = function(name_data, rank, ...) tibble::tibble(),
    .package = "rgbif"
  )
  out2 <- .resolve_gbif_taxon_keys_batch("Homo sapiens")
  expect_true(is.na(out2$usage_key))
})

test_that(".resolve_gbif_taxon_keys_batch() gives NA for a name absent from the response entirely", {
  local_mocked_bindings(
    name_backbone_checklist = function(name_data, rank, ...) {
      tibble::tibble(verbatim_name = "Homo sapiens", usageKey = 1, rank = "SPECIES", species = "Homo sapiens")
    },
    .package = "rgbif"
  )
  out <- .resolve_gbif_taxon_keys_batch(c("Homo sapiens", "Never Queried Back"))
  expect_equal(out$usage_key[out$taxon_name == "Homo sapiens"], 1)
  expect_true(is.na(out$usage_key[out$taxon_name == "Never Queried Back"]))
})

# =============================================================================
# Retry-on-batch-failure -- real production bug, 2026-08-24 (a 333-name real
# batch failed entirely with "Status: 0 - try lower bucket_size or larger
# sleep", silently zeroing every taxon's evidence with no warning at all)
# =============================================================================

test_that(".resolve_gbif_taxon_keys_batch() retries with a smaller bucket_size/larger sleep after a transient failure, and succeeds on a later attempt", {
  call_args <- list()
  local_mocked_bindings(
    name_backbone_checklist = function(name_data, rank, bucket_size, sleep, ...) {
      call_args[[length(call_args) + 1]] <<- list(bucket_size = bucket_size, sleep = sleep)
      if (length(call_args) < 2L) {
        stop("Status: 0 - try lower bucket_size or larger sleep.")
      }
      tibble::tibble(verbatim_name = name_data$name, usageKey = 1, rank = "SPECIES", species = name_data$name)
    },
    .package = "rgbif"
  )
  out <- .resolve_gbif_taxon_keys_batch("Homo sapiens")
  expect_equal(out$usage_key, 1)
  expect_equal(length(call_args), 2L)
  expect_true(call_args[[2]]$bucket_size < call_args[[1]]$bucket_size)
  expect_true(call_args[[2]]$sleep > call_args[[1]]$sleep)
})

test_that(".resolve_gbif_taxon_keys_batch() warns loudly (not silently) and returns all-NA when every retry attempt fails", {
  local_mocked_bindings(
    name_backbone_checklist = function(name_data, rank, bucket_size, sleep, ...) {
      stop("Status: 0 - try lower bucket_size or larger sleep.")
    },
    .package = "rgbif"
  )
  expect_warning(
    out <- .resolve_gbif_taxon_keys_batch(c("Homo sapiens", "Canis lupus")),
    "GBIF name resolution failed for all 2 taxa"
  )
  expect_true(all(is.na(out$usage_key)))
  expect_equal(out$taxon_name, c("Homo sapiens", "Canis lupus"))
})

test_that(".resolve_gbif_taxon_keys_batch() succeeds on the first attempt with no warning when nothing fails (regression guard against the retry loop itself)", {
  n_calls <- 0L
  local_mocked_bindings(
    name_backbone_checklist = function(name_data, rank, bucket_size, sleep, ...) {
      n_calls <<- n_calls + 1L
      tibble::tibble(verbatim_name = name_data$name, usageKey = 1, rank = "SPECIES", species = name_data$name)
    },
    .package = "rgbif"
  )
  expect_no_warning(out <- .resolve_gbif_taxon_keys_batch("Homo sapiens"))
  expect_equal(out$usage_key, 1)
  expect_equal(n_calls, 1L)
})

test_that(".resolve_gbif_taxon_keys_batch() falls back to NA gbif_species (not an error) when the response has no species column", {
  local_mocked_bindings(
    name_backbone_checklist = function(name_data, rank, ...) {
      tibble::tibble(verbatim_name = name_data$name, usageKey = 1, rank = "SPECIES")
    },
    .package = "rgbif"
  )
  out <- .resolve_gbif_taxon_keys_batch("Homo sapiens")
  expect_equal(out$usage_key, 1)
  expect_true(is.na(out$gbif_species))
})

test_that("w_scale scales the distance weight and validates its range", {
  local_mocked_bindings(name_backbone_checklist = .mock_key(), .package = "rgbif")
  local_mocked_bindings(check_gbif_tile_range = .mock_tile(dist_km = 80), .package = "TaxaFlag")
  local_mocked_bindings(
    get_gbif_occurrences = .mock_occ("Gadus morhua", year = 2020),
    filter_gbif_quality = .passthrough_filter,
    .package = "TaxaFetch"
  )
  out <- generate_regional_proximity_evidence("Gadus morhua",
    lat = 41.67, lng = -87.15,
    w_scale = 0.05
  )
  expect_equal(out$weight, 0.05 * exp(-out$distance_km / 150), tolerance = 1e-6)
  expect_error(
    generate_regional_proximity_evidence("Gadus morhua", lat = 41.67, lng = -87.15, w_scale = 0),
    "w_scale"
  )
  expect_error(
    generate_regional_proximity_evidence("Gadus morhua", lat = 41.67, lng = -87.15, w_scale = 1.5),
    "w_scale"
  )
})
