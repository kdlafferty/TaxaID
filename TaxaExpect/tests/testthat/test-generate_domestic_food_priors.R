# test-generate_domestic_food_priors.R
# Tests for generate_domestic_food_priors().
#
# Input:  biofreq_model object (only $N_total and $meta$habitat_col are read).
# Output: tibble of named domestic/food/plant priors with columns:
#   taxon_name, grid_id, alpha, beta, theta_mean, theta_sd, model_tier,
#   prior_source_type, cultivar_evidence_source, inat_n_observations_local,
#   inat_kingdom, inat_kingdom_mismatch (+ habitat_col if present,
#   + genus/family/order/class/phylum always).
#
# TaxaFetch::fetch_inat_occurrences() is mocked throughout -- no real HTTP calls.
# IMPORTANT: every call below explicitly zeroes out ALL FOUR fixed/supplied
# channels not under test (domestic_animal_taxa/food_species_taxa/
# known_cultivar_taxa/candidate_plant_taxa) -- the real defaults are large
# (hundreds of species) and a test that forgets to zero one out will iterate
# the whole default list against whatever fetch_inat_occurrences() resolves
# to in that test (a real, live network call if nothing is mocked).

library(testthat)
library(dplyr)

.make_mock_model_obj <- function(N_total = 200L, habitat_col = "main_habitat") {
  structure(
    list(
      N_total = N_total,
      meta    = list(habitat_col = habitat_col)
    ),
    class = "biofreq_model"
  )
}

.mock_inat <- function(n, inat_kingdom = "Animalia") {
  function(taxon_names, ...) {
    tibble::tibble(
      taxon_name           = taxon_names,
      taxon_id             = 1L,
      matched_name         = taxon_names,
      inat_kingdom         = inat_kingdom,
      n_observations_local = n,
      query_status         = "ok",
      radius_km            = 50,
      captive              = "any",
      quality_grade        = "any"
    )
  }
}

# Shorthand: zero out every fixed/supplied channel not being tested.
.no_defaults <- list(
  domestic_animal_taxa = character(0),
  food_species_taxa    = character(0),
  known_cultivar_taxa  = character(0),
  candidate_plant_taxa  = NULL
)

# =============================================================================
# Input validation
# =============================================================================

test_that("stops when model_obj is not a biofreq_model", {
  expect_error(
    generate_domestic_food_priors(list(), lat = 34.1, lng = -119.1),
    regexp = "biofreq_model"
  )
})

test_that("stops when lat is missing/invalid", {
  mod <- .make_mock_model_obj()
  expect_error(
    generate_domestic_food_priors(mod, lat = NA_real_, lng = -119.1),
    regexp = "lat"
  )
})

test_that("stops when N_total is zero", {
  mod <- .make_mock_model_obj(N_total = 0L)
  expect_error(
    generate_domestic_food_priors(mod, lat = 34.1, lng = -119.1),
    regexp = "N_total"
  )
})

# =============================================================================
# Empty-channel behavior
# =============================================================================

test_that("all four fixed/supplied channels empty/NULL returns an empty tibble with correct columns", {
  mod <- .make_mock_model_obj()
  out <- generate_domestic_food_priors(
    mod, lat = 34.1, lng = -119.1,
    domestic_animal_taxa = character(0),
    food_species_taxa    = character(0),
    known_cultivar_taxa   = character(0),
    candidate_plant_taxa  = NULL
  )
  expect_s3_class(out, "tbl_df")
  expect_equal(nrow(out), 0L)
  expect_true(all(c("taxon_name", "prior_source_type", "cultivar_evidence_source",
                    "model_tier", "inat_n_observations_local") %in% names(out)))
})

# =============================================================================
# domestic_animal_taxa / food_species_taxa channels
# =============================================================================

test_that("domestic_animal_taxa gets a row even with zero local iNat evidence", {
  mod <- .make_mock_model_obj(N_total = 200L)
  local_mocked_bindings(
    fetch_inat_occurrences = .mock_inat(0L),
    .package = "TaxaFetch"
  )
  out <- generate_domestic_food_priors(
    mod, lat = 34.1, lng = -119.1,
    domestic_animal_taxa = "Felis catus",
    food_species_taxa    = character(0),
    known_cultivar_taxa   = character(0)
  )
  expect_equal(nrow(out), 1L)
  expect_equal(out$taxon_name, "Felis catus")
  expect_equal(out$prior_source_type, "domestic_animal")
  expect_true(is.na(out$cultivar_evidence_source))
  expect_equal(out$model_tier, "tier_domestic_food")
  expect_gt(out$alpha, 0)
  expect_equal(out$inat_n_observations_local, 0L)
})

test_that("food_species_taxa gets its own category label", {
  mod <- .make_mock_model_obj(N_total = 200L)
  local_mocked_bindings(
    fetch_inat_occurrences = .mock_inat(0L),
    .package = "TaxaFetch"
  )
  out <- generate_domestic_food_priors(
    mod, lat = 34.1, lng = -119.1,
    domestic_animal_taxa = character(0),
    food_species_taxa    = "Solanum lycopersicum",
    known_cultivar_taxa   = character(0)
  )
  expect_equal(out$prior_source_type, "food_species")
  expect_true(is.na(out$cultivar_evidence_source))
})

test_that("local iNat evidence increases alpha (theta_mean) relative to zero evidence", {
  mod <- .make_mock_model_obj(N_total = 200L)

  local_mocked_bindings(fetch_inat_occurrences = .mock_inat(0L), .package = "TaxaFetch")
  out_zero <- generate_domestic_food_priors(
    mod, lat = 34.1, lng = -119.1,
    domestic_animal_taxa = "Felis catus", food_species_taxa = character(0),
    known_cultivar_taxa = character(0)
  )

  local_mocked_bindings(fetch_inat_occurrences = .mock_inat(500L), .package = "TaxaFetch")
  out_evidence <- generate_domestic_food_priors(
    mod, lat = 34.1, lng = -119.1,
    domestic_animal_taxa = "Felis catus", food_species_taxa = character(0),
    known_cultivar_taxa = character(0)
  )

  expect_gt(out_evidence$theta_mean, out_zero$theta_mean)
})

test_that("max_ess caps the evidence boost", {
  mod <- .make_mock_model_obj(N_total = 200L)
  local_mocked_bindings(
    fetch_inat_occurrences = .mock_inat(1e6),
    .package = "TaxaFetch"
  )
  out <- generate_domestic_food_priors(
    mod, lat = 34.1, lng = -119.1,
    domestic_animal_taxa = "Felis catus", food_species_taxa = character(0),
    known_cultivar_taxa = character(0),
    max_ess = 10
  )
  expect_lte(out$alpha, 10)
})

test_that("duplicate taxon name across channels is kept once, first channel wins", {
  mod <- .make_mock_model_obj(N_total = 200L)
  local_mocked_bindings(
    fetch_inat_occurrences = .mock_inat(0L),
    .package = "TaxaFetch"
  )
  out <- generate_domestic_food_priors(
    mod, lat = 34.1, lng = -119.1,
    domestic_animal_taxa = "Ambiguous species",
    food_species_taxa    = "Ambiguous species",
    known_cultivar_taxa   = character(0)
  )
  expect_equal(nrow(out), 1L)
  expect_equal(out$prior_source_type, "domestic_animal")
})

# =============================================================================
# known_cultivar_taxa channel (fixed patch list, no live-evidence requirement)
# =============================================================================

test_that("known_cultivar_taxa gets a row even with zero local iNat evidence", {
  mod <- .make_mock_model_obj(N_total = 200L)
  local_mocked_bindings(fetch_inat_occurrences = .mock_inat(0L, inat_kingdom = "Plantae"), .package = "TaxaFetch")
  out <- generate_domestic_food_priors(
    mod, lat = 34.1, lng = -119.1,
    domestic_animal_taxa = character(0), food_species_taxa = character(0),
    known_cultivar_taxa   = "Iris"
  )
  expect_equal(nrow(out), 1L)
  expect_equal(out$prior_source_type, "domestic_plant")
  expect_equal(out$cultivar_evidence_source, "known_list")
  expect_equal(out$inat_n_observations_local, 0L)
  expect_gt(out$alpha, 0)
})

test_that("known_cultivar_taxa and candidate_plant_taxa share prior_source_type but differ in cultivar_evidence_source", {
  mod <- .make_mock_model_obj(N_total = 200L)
  local_mocked_bindings(fetch_inat_occurrences = .mock_inat(30L, inat_kingdom = "Plantae"), .package = "TaxaFetch")
  out <- generate_domestic_food_priors(
    mod, lat = 34.1, lng = -119.1,
    domestic_animal_taxa = character(0), food_species_taxa = character(0),
    known_cultivar_taxa   = "Iris",
    candidate_plant_taxa  = "Tulipa gesneriana"
  )
  expect_equal(nrow(out), 2L)
  expect_true(all(out$prior_source_type == "domestic_plant"))
  expect_setequal(out$cultivar_evidence_source, c("known_list", "candidate_supplied"))
})

# =============================================================================
# candidate_plant_taxa channel (iNat-casual-grade discovery, no fixed defaults)
# =============================================================================

test_that("candidate_plant_taxa with zero local evidence is skipped entirely", {
  mod <- .make_mock_model_obj(N_total = 200L)
  local_mocked_bindings(
    fetch_inat_occurrences = .mock_inat(0L),
    .package = "TaxaFetch"
  )
  out <- generate_domestic_food_priors(
    mod, lat = 34.1, lng = -119.1,
    domestic_animal_taxa = character(0),
    food_species_taxa    = character(0),
    known_cultivar_taxa   = character(0),
    candidate_plant_taxa  = "Tulipa gesneriana"
  )
  expect_equal(nrow(out), 0L)
})

test_that("candidate_plant_taxa with real casual-grade evidence gets a row", {
  mod <- .make_mock_model_obj(N_total = 200L)
  local_mocked_bindings(
    fetch_inat_occurrences = .mock_inat(30L),
    .package = "TaxaFetch"
  )
  out <- generate_domestic_food_priors(
    mod, lat = 34.1, lng = -119.1,
    domestic_animal_taxa = character(0),
    food_species_taxa    = character(0),
    known_cultivar_taxa   = character(0),
    candidate_plant_taxa  = "Tulipa gesneriana"
  )
  expect_equal(nrow(out), 1L)
  expect_equal(out$prior_source_type, "domestic_plant")
  expect_equal(out$cultivar_evidence_source, "candidate_supplied")
  expect_equal(out$inat_n_observations_local, 30L)
})

test_that("candidate_plant_taxa query uses quality_grade = 'casual'", {
  mod <- .make_mock_model_obj(N_total = 200L)
  captured_quality_grade <- NULL
  local_mocked_bindings(
    fetch_inat_occurrences = function(taxon_names, quality_grade, ...) {
      captured_quality_grade <<- quality_grade
      tibble::tibble(taxon_name = taxon_names, inat_kingdom = "Plantae", n_observations_local = 10L)
    },
    .package = "TaxaFetch"
  )
  generate_domestic_food_priors(
    mod, lat = 34.1, lng = -119.1,
    domestic_animal_taxa = character(0),
    food_species_taxa    = character(0),
    known_cultivar_taxa   = character(0),
    candidate_plant_taxa  = "Tulipa gesneriana"
  )
  expect_equal(captured_quality_grade, "casual")
})

# =============================================================================
# match_list_taxa gating
# =============================================================================

test_that("match_list_taxa = NULL preserves original unrestricted behavior", {
  mod <- .make_mock_model_obj(N_total = 200L)
  local_mocked_bindings(fetch_inat_occurrences = .mock_inat(0L), .package = "TaxaFetch")
  out <- generate_domestic_food_priors(
    mod, lat = 34.1, lng = -119.1,
    domestic_animal_taxa = "Felis catus", food_species_taxa = character(0),
    known_cultivar_taxa = character(0), match_list_taxa = NULL
  )
  expect_equal(nrow(out), 1L)
})

test_that("match_list_taxa restricts fixed-list candidates to the intersection", {
  mod <- .make_mock_model_obj(N_total = 200L)
  local_mocked_bindings(fetch_inat_occurrences = .mock_inat(0L), .package = "TaxaFetch")
  out <- generate_domestic_food_priors(
    mod, lat = 34.1, lng = -119.1,
    domestic_animal_taxa = c("Felis catus", "Canis lupus"),
    food_species_taxa    = character(0),
    known_cultivar_taxa   = character(0),
    match_list_taxa       = "Felis catus"  # Canis lupus never detected this run
  )
  expect_equal(nrow(out), 1L)
  expect_equal(out$taxon_name, "Felis catus")
})

test_that("match_list_taxa with no taxonomy skips the open-discovery step with a message, not a warning", {
  mod <- .make_mock_model_obj(N_total = 200L)
  local_mocked_bindings(fetch_inat_occurrences = .mock_inat(0L), .package = "TaxaFetch")
  expect_no_warning(
    out <- generate_domestic_food_priors(
      mod, lat = 34.1, lng = -119.1,
      domestic_animal_taxa = character(0), food_species_taxa = character(0),
      known_cultivar_taxa = character(0),
      match_list_taxa = "Bidens torta"  # unreferenced, no taxonomy to scope it
    )
  )
  expect_equal(nrow(out), 0L)
})

test_that("open-discovery step checks a match-list taxon in a plausibly-cultivable phylum and adds it on real evidence", {
  mod <- .make_mock_model_obj(N_total = 200L)
  local_mocked_bindings(fetch_inat_occurrences = .mock_inat(40L, inat_kingdom = "Plantae"), .package = "TaxaFetch")
  taxonomy <- tibble::tibble(taxon_name = "Bidens torta", phylum = "Streptophyta")
  out <- generate_domestic_food_priors(
    mod, lat = 34.1, lng = -119.1,
    domestic_animal_taxa = character(0), food_species_taxa = character(0),
    known_cultivar_taxa = character(0),
    match_list_taxa = "Bidens torta",
    taxonomy = taxonomy
  )
  expect_equal(nrow(out), 1L)
  expect_equal(out$taxon_name, "Bidens torta")
  expect_equal(out$prior_source_type, "domestic_plant")
  expect_equal(out$cultivar_evidence_source, "inat_confirmed")
})

test_that("open-discovery step recognizes Tracheophyta as well as Streptophyta", {
  mod <- .make_mock_model_obj(N_total = 200L)
  local_mocked_bindings(fetch_inat_occurrences = .mock_inat(40L, inat_kingdom = "Plantae"), .package = "TaxaFetch")
  taxonomy <- tibble::tibble(taxon_name = "Bidens torta", phylum = "Tracheophyta")
  out <- generate_domestic_food_priors(
    mod, lat = 34.1, lng = -119.1,
    domestic_animal_taxa = character(0), food_species_taxa = character(0),
    known_cultivar_taxa = character(0),
    match_list_taxa = "Bidens torta",
    taxonomy = taxonomy
  )
  expect_equal(nrow(out), 1L)
})

test_that("open-discovery step excludes a match-list taxon outside the plausibly-cultivable phylum scope", {
  mod <- .make_mock_model_obj(N_total = 200L)
  call_count <- 0L
  local_mocked_bindings(
    fetch_inat_occurrences = function(...) { call_count <<- call_count + 1L; .mock_inat(40L)(...) },
    .package = "TaxaFetch"
  )
  taxonomy <- tibble::tibble(taxon_name = "Paracalanus parvus", phylum = "Arthropoda")
  out <- generate_domestic_food_priors(
    mod, lat = 34.1, lng = -119.1,
    domestic_animal_taxa = character(0), food_species_taxa = character(0),
    known_cultivar_taxa = character(0),
    match_list_taxa = "Paracalanus parvus",
    taxonomy = taxonomy
  )
  expect_equal(nrow(out), 0L)
  expect_equal(call_count, 0L)  # never even checked -- excluded before any iNat call
})

test_that("open-discovery step excludes a match-list taxon already covered by taxaexpect_priors", {
  mod <- .make_mock_model_obj(N_total = 200L)
  call_count <- 0L
  local_mocked_bindings(
    fetch_inat_occurrences = function(...) { call_count <<- call_count + 1L; .mock_inat(40L)(...) },
    .package = "TaxaFetch"
  )
  taxonomy <- tibble::tibble(taxon_name = "Bidens torta", phylum = "Streptophyta")
  existing_priors <- tibble::tibble(taxon_name = "Bidens torta", theta_mean = 0.01)
  out <- generate_domestic_food_priors(
    mod, lat = 34.1, lng = -119.1,
    domestic_animal_taxa = character(0), food_species_taxa = character(0),
    known_cultivar_taxa = character(0),
    match_list_taxa = "Bidens torta",
    taxaexpect_priors = existing_priors,
    taxonomy = taxonomy
  )
  expect_equal(nrow(out), 0L)
  expect_equal(call_count, 0L)
})

test_that("open-discovery step accepts a bare taxon_name vector for taxaexpect_priors", {
  mod <- .make_mock_model_obj(N_total = 200L)
  local_mocked_bindings(fetch_inat_occurrences = .mock_inat(40L), .package = "TaxaFetch")
  taxonomy <- tibble::tibble(taxon_name = "Bidens torta", phylum = "Streptophyta")
  out <- generate_domestic_food_priors(
    mod, lat = 34.1, lng = -119.1,
    domestic_animal_taxa = character(0), food_species_taxa = character(0),
    known_cultivar_taxa = character(0),
    match_list_taxa = "Bidens torta",
    taxaexpect_priors = "Bidens torta",  # bare character vector, not a data frame
    taxonomy = taxonomy
  )
  expect_equal(nrow(out), 0L)
})

test_that("open-discovery step is not restricted to known_cultivar_taxa membership", {
  # The whole point of the open-discovery channel is to catch a cultivated
  # species NOT on any fixed list -- confirm a taxon absent from
  # known_cultivar_taxa still gets checked and added.
  mod <- .make_mock_model_obj(N_total = 200L)
  stopifnot(!("Bidens torta" %in% .default_known_cultivar_taxa))
  local_mocked_bindings(fetch_inat_occurrences = .mock_inat(40L, inat_kingdom = "Plantae"), .package = "TaxaFetch")
  taxonomy <- tibble::tibble(taxon_name = "Bidens torta", phylum = "Streptophyta")
  out <- generate_domestic_food_priors(
    mod, lat = 34.1, lng = -119.1,
    domestic_animal_taxa = character(0), food_species_taxa = character(0),
    known_cultivar_taxa = character(0),  # deliberately empty -- not what admits this taxon
    match_list_taxa = "Bidens torta",
    taxonomy = taxonomy
  )
  expect_equal(nrow(out), 1L)
})

# =============================================================================
# habitat_col and taxonomy handling
# =============================================================================

test_that("habitat column is added as NA when model_obj has one", {
  mod <- .make_mock_model_obj(N_total = 200L, habitat_col = "main_habitat")
  local_mocked_bindings(fetch_inat_occurrences = .mock_inat(0L), .package = "TaxaFetch")
  out <- generate_domestic_food_priors(
    mod, lat = 34.1, lng = -119.1,
    domestic_animal_taxa = "Felis catus", food_species_taxa = character(0),
    known_cultivar_taxa = character(0)
  )
  expect_true("main_habitat" %in% names(out))
  expect_true(is.na(out$main_habitat))
})

test_that("no habitat column added when model_obj was trained with habitat_col = NULL", {
  mod <- .make_mock_model_obj(N_total = 200L, habitat_col = NULL)
  local_mocked_bindings(fetch_inat_occurrences = .mock_inat(0L), .package = "TaxaFetch")
  out <- generate_domestic_food_priors(
    mod, lat = 34.1, lng = -119.1,
    domestic_animal_taxa = "Felis catus", food_species_taxa = character(0),
    known_cultivar_taxa = character(0)
  )
  expect_false("main_habitat" %in% names(out))
})

test_that("taxonomy is joined onto result rows by taxon_name", {
  mod <- .make_mock_model_obj(N_total = 200L)
  local_mocked_bindings(fetch_inat_occurrences = .mock_inat(0L), .package = "TaxaFetch")
  taxonomy <- tibble::tibble(
    taxon_name = "Felis catus", genus = "Felis", family = "Felidae"
  )
  out <- generate_domestic_food_priors(
    mod, lat = 34.1, lng = -119.1,
    domestic_animal_taxa = "Felis catus", food_species_taxa = character(0),
    known_cultivar_taxa = character(0),
    taxonomy = taxonomy
  )
  expect_equal(out$genus, "Felis")
  expect_equal(out$family, "Felidae")
  expect_true("order" %in% names(out))
  expect_true(is.na(out$order))
})

test_that("taxonomy rank columns are always present even when taxonomy is NULL", {
  mod <- .make_mock_model_obj(N_total = 200L)
  local_mocked_bindings(fetch_inat_occurrences = .mock_inat(0L), .package = "TaxaFetch")
  out <- generate_domestic_food_priors(
    mod, lat = 34.1, lng = -119.1,
    domestic_animal_taxa = "Felis catus", food_species_taxa = character(0),
    known_cultivar_taxa = character(0)
  )
  expect_true(all(c("genus", "family", "order", "class", "phylum") %in% names(out)))
})

# =============================================================================
# iNaturalist kingdom cross-check
# =============================================================================

test_that("a kingdom mismatch discards the local-evidence boost with a warning", {
  mod <- .make_mock_model_obj(N_total = 200L)
  # Candidate's real kingdom (per taxonomy) is Animalia, but the mocked iNat
  # response resolves to Plantae -- a simulated homonym mismatch.
  local_mocked_bindings(fetch_inat_occurrences = .mock_inat(500L, inat_kingdom = "Plantae"), .package = "TaxaFetch")
  taxonomy <- tibble::tibble(taxon_name = "Felis catus", kingdom = "Animalia", genus = "Felis")
  expect_warning(
    out <- generate_domestic_food_priors(
      mod, lat = 34.1, lng = -119.1,
      domestic_animal_taxa = "Felis catus", food_species_taxa = character(0),
      known_cultivar_taxa = character(0),
      taxonomy = taxonomy
    ),
    regexp = "homonym|kingdom"
  )
  expect_true(out$inat_kingdom_mismatch)
  expect_true(is.na(out$inat_n_observations_local))
  # The fixed-list category itself is unaffected -- still gets the baseline prior.
  expect_equal(out$prior_source_type, "domestic_animal")
  expect_gt(out$alpha, 0)
})

test_that("a kingdom match does not discard evidence and is not flagged", {
  mod <- .make_mock_model_obj(N_total = 200L)
  local_mocked_bindings(fetch_inat_occurrences = .mock_inat(500L, inat_kingdom = "Animalia"), .package = "TaxaFetch")
  taxonomy <- tibble::tibble(taxon_name = "Felis catus", kingdom = "Animalia", genus = "Felis")
  out <- generate_domestic_food_priors(
    mod, lat = 34.1, lng = -119.1,
    domestic_animal_taxa = "Felis catus", food_species_taxa = character(0),
    known_cultivar_taxa = character(0),
    taxonomy = taxonomy
  )
  expect_false(out$inat_kingdom_mismatch)
  expect_equal(out$inat_n_observations_local, 500L)
})

test_that("no kingdom column in taxonomy means the mismatch cannot be checked (no flag, no warning)", {
  mod <- .make_mock_model_obj(N_total = 200L)
  local_mocked_bindings(fetch_inat_occurrences = .mock_inat(500L, inat_kingdom = "Plantae"), .package = "TaxaFetch")
  taxonomy <- tibble::tibble(taxon_name = "Felis catus", genus = "Felis")  # no kingdom column
  out <- expect_no_warning(
    generate_domestic_food_priors(
      mod, lat = 34.1, lng = -119.1,
      domestic_animal_taxa = "Felis catus", food_species_taxa = character(0),
      known_cultivar_taxa = character(0),
      taxonomy = taxonomy
    )
  )
  expect_false(out$inat_kingdom_mismatch)
  expect_equal(out$inat_n_observations_local, 500L)
})

test_that("candidate_plant_taxa with a kingdom mismatch is skipped entirely (no fixed-list fallback)", {
  mod <- .make_mock_model_obj(N_total = 200L)
  local_mocked_bindings(fetch_inat_occurrences = .mock_inat(30L, inat_kingdom = "Animalia"), .package = "TaxaFetch")
  taxonomy <- tibble::tibble(taxon_name = "Tulipa gesneriana", kingdom = "Plantae", genus = "Tulipa")
  expect_warning(
    out <- generate_domestic_food_priors(
      mod, lat = 34.1, lng = -119.1,
      domestic_animal_taxa = character(0), food_species_taxa = character(0),
      known_cultivar_taxa   = character(0),
      candidate_plant_taxa  = "Tulipa gesneriana",
      taxonomy = taxonomy
    ),
    regexp = "homonym|kingdom"
  )
  expect_equal(nrow(out), 0L)
})

test_that("inat_kingdom column is always present in the output", {
  mod <- .make_mock_model_obj(N_total = 200L)
  local_mocked_bindings(fetch_inat_occurrences = .mock_inat(0L), .package = "TaxaFetch")
  out <- generate_domestic_food_priors(
    mod, lat = 34.1, lng = -119.1,
    domestic_animal_taxa = "Felis catus", food_species_taxa = character(0),
    known_cultivar_taxa = character(0)
  )
  expect_true("inat_kingdom" %in% names(out))
  expect_true("inat_kingdom_mismatch" %in% names(out))
})

# =============================================================================
# Default vectors
# =============================================================================

test_that("default domestic_animal_taxa includes Homo sapiens and common livestock/pets", {
  expect_true("Homo sapiens" %in% .default_domestic_animal_taxa)
  expect_true("Felis catus" %in% .default_domestic_animal_taxa)
  expect_true("Bos taurus" %in% .default_domestic_animal_taxa)
})

test_that("default food_species_taxa includes common crop species and is genuinely extensive", {
  expect_true("Solanum lycopersicum" %in% .default_food_species_taxa)
  expect_true("Theobroma cacao" %in% .default_food_species_taxa)
  expect_true(length(.default_food_species_taxa) > 400)
})

test_that("default known_cultivar_taxa is non-empty and distinct from food_species_taxa", {
  expect_true(length(.default_known_cultivar_taxa) > 100)
  expect_true("Iris" %in% .default_known_cultivar_taxa)
  expect_length(intersect(.default_known_cultivar_taxa, .default_food_species_taxa), 0)
})

test_that("cultivated food fungi are in food_species_taxa, not known_cultivar_taxa", {
  fungi <- c("Agaricus bisporus", "Pleurotus ostreatus")
  expect_true(all(fungi %in% .default_food_species_taxa))
  expect_length(intersect(fungi, .default_known_cultivar_taxa), 0)
})

test_that("default vectors do not overlap (domestic animals vs food species vs known cultivars)", {
  expect_length(intersect(.default_domestic_animal_taxa, .default_food_species_taxa), 0)
  expect_length(intersect(.default_domestic_animal_taxa, .default_known_cultivar_taxa), 0)
})

test_that("default vectors contain no non-ASCII characters", {
  all_defaults <- c(.default_domestic_animal_taxa, .default_food_species_taxa, .default_known_cultivar_taxa)
  expect_false(any(grepl("[^\x01-\x7F]", all_defaults, perl = TRUE)))
})

test_that("default animal vector contains no subspecies trinomials or hybrid-formula names", {
  # TaxaAssign::join_priors() joins on an exact taxon_name string match against
  # match_obj$taxon_name, which is always run through TaxaTools::clean_taxon_names()
  # (genus + epithet only) elsewhere in the pipeline. A trinomial default like
  # "Sus scrofa domesticus" would never join, defeating this function's purpose
  # for exactly that taxon. (food_species_taxa/known_cultivar_taxa are excluded
  # from this check -- both legitimately contain hybrid-formula entries like
  # "Citrus x aurantiifolia", which clean_taxon_names() correctly normalizes at
  # call time; the point of this test is the hand-curated animal list only.)
  n_tokens <- lengths(strsplit(.default_domestic_animal_taxa, " ", fixed = TRUE))
  expect_true(all(n_tokens <= 2L))
  expect_false(any(grepl("(^| )x( |$)", .default_domestic_animal_taxa)))
})

# =============================================================================
# Name normalization (clean_taxon_names())
# =============================================================================

test_that("a subspecies trinomial candidate is normalized to a binomial before joining", {
  mod <- .make_mock_model_obj(N_total = 200L)
  local_mocked_bindings(fetch_inat_occurrences = .mock_inat(0L), .package = "TaxaFetch")
  out <- generate_domestic_food_priors(
    mod, lat = 34.1, lng = -119.1,
    domestic_animal_taxa = "Sus scrofa domesticus", food_species_taxa = character(0),
    known_cultivar_taxa = character(0)
  )
  expect_equal(out$taxon_name, "Sus scrofa")
})

test_that("a hybrid-formula candidate name is normalized the same way clean_taxon_names() normalizes it elsewhere", {
  mod <- .make_mock_model_obj(N_total = 200L)
  local_mocked_bindings(fetch_inat_occurrences = .mock_inat(0L), .package = "TaxaFetch")
  out <- generate_domestic_food_priors(
    mod, lat = 34.1, lng = -119.1,
    domestic_animal_taxa = character(0), food_species_taxa = "Fragaria x ananassa",
    known_cultivar_taxa = character(0)
  )
  expect_equal(out$taxon_name, TaxaTools::clean_taxon_names("Fragaria x ananassa"))
})

test_that("a candidate name that cannot be cleaned is dropped with a warning, not passed through raw", {
  mod <- .make_mock_model_obj(N_total = 200L)
  local_mocked_bindings(fetch_inat_occurrences = .mock_inat(0L), .package = "TaxaFetch")
  expect_warning(
    out <- generate_domestic_food_priors(
      mod, lat = 34.1, lng = -119.1,
      domestic_animal_taxa = "lowercase invalid", food_species_taxa = character(0),
      known_cultivar_taxa = character(0)
    ),
    regexp = "could not be cleaned"
  )
  expect_equal(nrow(out), 0L)
})
