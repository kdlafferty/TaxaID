# test-escalate_taxonomic_rank.R
# Tests for escalate_taxonomic_rank(). Fully offline -- backbone API calls
# are mocked via local_mocked_bindings(verify_taxon_names = ...).

library(testthat)

.make_verified <- function(name, path, ranks) {
  tibble::tibble(
    user_supplied_name   = name,
    matched_name         = name,
    classification_path  = path,
    classification_ranks = ranks,
    score                = 1.0,
    verified             = TRUE
  )
}

.rhaco_path  <- "Animalia|Chordata|Actinopterygii|Perciformes|Embiotocidae|Rhacochilus"
.rhaco_ranks <- "kingdom|phylum|class|order|family|genus"

# =============================================================================
# Input validation
# =============================================================================

test_that("stops if taxon_name is not a single non-empty string", {
  expect_error(escalate_taxonomic_rank(123, "genus"), regexp = "non-empty")
  expect_error(escalate_taxonomic_rank(c("a", "b"), "genus"), regexp = "non-empty")
  expect_error(escalate_taxonomic_rank(NA_character_, "genus"), regexp = "non-empty")
  expect_error(escalate_taxonomic_rank("", "genus"), regexp = "non-empty")
})

test_that("stops if current_rank is not a single character string", {
  expect_error(escalate_taxonomic_rank("Rhacochilus", 5), regexp = "character string")
  expect_error(escalate_taxonomic_rank("Rhacochilus", NA_character_), regexp = "character string")
})

test_that("stops if current_rank is not found in rank_system", {
  expect_error(
    escalate_taxonomic_rank("Rhacochilus", "not_a_rank"),
    regexp = "not found in rank_system"
  )
})

test_that("stops if max_levels is not a single positive integer", {
  expect_error(escalate_taxonomic_rank("Rhacochilus", "genus", max_levels = 0),
               regexp = "positive integer")
  expect_error(escalate_taxonomic_rank("Rhacochilus", "genus", max_levels = c(1, 2)),
               regexp = "positive integer")
})

test_that("stops if backbone_id is not a single integer or NULL", {
  expect_error(
    escalate_taxonomic_rank("Rhacochilus", "genus", backbone_id = c(4, 11)),
    regexp = "single integer"
  )
})

test_that("stops if verbose is not logical", {
  expect_error(
    escalate_taxonomic_rank("Rhacochilus", "genus", verbose = "yes"),
    regexp = "TRUE or FALSE"
  )
})

# =============================================================================
# Already-coarsest rank: no API call needed
# =============================================================================

test_that("returns NA/NA immediately when current_rank is already the coarsest", {
  called <- FALSE
  local_mocked_bindings(
    verify_taxon_names = function(...) { called <<- TRUE; NULL },
    .package = "TaxaTools"
  )
  out <- escalate_taxonomic_rank("Animalia", "kingdom", verbose = FALSE)
  expect_true(is.na(out$taxon_name))
  expect_true(is.na(out$rank))
  expect_false(called)
})

# =============================================================================
# Immediate-parent escalation (genus -> family)
# =============================================================================

test_that("escalates genus to family when family is present in the classification", {
  local_mocked_bindings(
    verify_taxon_names = function(names, backbone_id, ...) {
      expect_equal(backbone_id, 4L)
      .make_verified(names[1L], .rhaco_path, .rhaco_ranks)
    },
    .package = "TaxaTools"
  )
  out <- escalate_taxonomic_rank("Rhacochilus", current_rank = "genus", verbose = FALSE)
  expect_equal(out$taxon_name, "Embiotocidae")
  expect_equal(out$rank, "family")
})

# =============================================================================
# Skip-level escalation (family missing from path -> order), within max_levels
# =============================================================================

test_that("skips to order when family is absent from the classification path", {
  path  <- "Animalia|Chordata|Actinopterygii|Perciformes|Rhacochilus"
  ranks <- "kingdom|phylum|class|order|genus"
  local_mocked_bindings(
    verify_taxon_names = function(names, backbone_id, ...) {
      .make_verified(names[1L], path, ranks)
    },
    .package = "TaxaTools"
  )
  out <- escalate_taxonomic_rank("Rhacochilus", current_rank = "genus",
                                 max_levels = 2L, verbose = FALSE)
  expect_equal(out$taxon_name, "Perciformes")
  expect_equal(out$rank, "order")
})

test_that("returns NA/NA when max_levels is exhausted before a rank resolves", {
  path  <- "Animalia|Chordata|Actinopterygii|Perciformes|Rhacochilus"
  ranks <- "kingdom|phylum|class|order|genus"
  local_mocked_bindings(
    verify_taxon_names = function(names, backbone_id, ...) {
      .make_verified(names[1L], path, ranks)
    },
    .package = "TaxaTools"
  )
  out <- escalate_taxonomic_rank("Rhacochilus", current_rank = "genus",
                                 max_levels = 1L, verbose = FALSE)
  expect_true(is.na(out$taxon_name))
  expect_true(is.na(out$rank))
})

# =============================================================================
# Fallback backbone
# =============================================================================

test_that("fallback backbone is used when primary backbone doesn't resolve", {
  fb_called <- FALSE
  local_mocked_bindings(
    verify_taxon_names = function(names, backbone_id, ...) {
      if (backbone_id == 4L) {
        return(tibble::tibble(
          user_supplied_name   = names,
          matched_name         = NA_character_,
          classification_path  = NA_character_,
          classification_ranks = NA_character_,
          score                = 0.0,
          verified             = FALSE
        ))
      }
      fb_called <<- TRUE
      .make_verified(names[1L], .rhaco_path, .rhaco_ranks)
    },
    .package = "TaxaTools"
  )
  out <- escalate_taxonomic_rank("Rhacochilus", current_rank = "genus",
                                 backbone_id = 4L, fallback_backbone_id = 11L,
                                 verbose = FALSE)
  expect_true(fb_called)
  expect_equal(out$taxon_name, "Embiotocidae")
})

test_that("fallback is skipped when backbone_id == fallback_backbone_id", {
  call_count <- 0L
  local_mocked_bindings(
    verify_taxon_names = function(names, backbone_id, ...) {
      call_count <<- call_count + 1L
      tibble::tibble(
        user_supplied_name   = names,
        matched_name         = NA_character_,
        classification_path  = NA_character_,
        classification_ranks = NA_character_,
        score                = 0.0, verified = FALSE
      )
    },
    .package = "TaxaTools"
  )
  out <- suppressMessages(escalate_taxonomic_rank(
    "Rhacochilus", current_rank = "genus",
    backbone_id = 4L, fallback_backbone_id = 4L, verbose = FALSE
  ))
  expect_equal(call_count, 1L)
  expect_true(is.na(out$taxon_name))
})

test_that("backbone_id = NULL skips straight to fallback_backbone_id", {
  local_mocked_bindings(
    verify_taxon_names = function(names, backbone_id, ...) {
      expect_equal(backbone_id, 11L)
      .make_verified(names[1L], .rhaco_path, .rhaco_ranks)
    },
    .package = "TaxaTools"
  )
  out <- escalate_taxonomic_rank("Rhacochilus", current_rank = "genus",
                                 backbone_id = NULL, fallback_backbone_id = 11L,
                                 verbose = FALSE)
  expect_equal(out$taxon_name, "Embiotocidae")
})

test_that("returns NA/NA when classification cannot be resolved at all", {
  local_mocked_bindings(
    verify_taxon_names = function(names, backbone_id, ...) {
      tibble::tibble(
        user_supplied_name   = names,
        matched_name         = NA_character_,
        classification_path  = NA_character_,
        classification_ranks = NA_character_,
        score                = 0.0, verified = FALSE
      )
    },
    .package = "TaxaTools"
  )
  out <- escalate_taxonomic_rank("Unknownus genus", current_rank = "genus",
                                 fallback_backbone_id = NULL, verbose = FALSE)
  expect_true(is.na(out$taxon_name))
  expect_true(is.na(out$rank))
})

test_that("a backbone API error is caught and returns NA/NA with a warning", {
  local_mocked_bindings(
    verify_taxon_names = function(...) stop("network unreachable"),
    .package = "TaxaTools"
  )
  expect_warning(
    out <- escalate_taxonomic_rank("Rhacochilus", current_rank = "genus",
                                   fallback_backbone_id = NULL, verbose = FALSE),
    regexp = "backbone 4 query failed"
  )
  expect_true(is.na(out$taxon_name))
})

# =============================================================================
# Second real validation case: Embiotoca caryi (species -> genus)
# =============================================================================

test_that("escalates species-level current_rank to genus", {
  path  <- "Animalia|Chordata|Actinopterygii|Perciformes|Embiotocidae|Embiotoca|Embiotoca caryi"
  ranks <- "kingdom|phylum|class|order|family|genus|species"
  local_mocked_bindings(
    verify_taxon_names = function(names, backbone_id, ...) {
      .make_verified(names[1L], path, ranks)
    },
    .package = "TaxaTools"
  )
  out <- escalate_taxonomic_rank("Embiotoca caryi", current_rank = "species", verbose = FALSE)
  expect_equal(out$taxon_name, "Embiotoca")
  expect_equal(out$rank, "genus")
})

# =============================================================================
# Custom rank_system
# =============================================================================

test_that("respects a custom rank_system", {
  path  <- "Animalia|Chordata|Actinopterygii|Perciformes|Embiotocidae|Rhacochilus"
  ranks <- "kingdom|phylum|class|order|family|genus"
  local_mocked_bindings(
    verify_taxon_names = function(names, backbone_id, ...) {
      .make_verified(names[1L], path, ranks)
    },
    .package = "TaxaTools"
  )
  out <- escalate_taxonomic_rank(
    "Rhacochilus", current_rank = "genus",
    rank_system = c("phylum", "class", "order", "family", "genus"),
    verbose = FALSE
  )
  expect_equal(out$taxon_name, "Embiotocidae")
  expect_equal(out$rank, "family")
})
