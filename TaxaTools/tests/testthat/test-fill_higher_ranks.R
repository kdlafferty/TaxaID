# test-fill_higher_ranks.R
# Tests for fill_higher_ranks(), .build_genus_family_lookup(),
# .lookup_family_from_backbone(), and .extract_rank_from_classification().
# Fully offline — backbone API calls are mocked.

library(testthat)

# =============================================================================
# Fixtures
# =============================================================================

.local_src <- data.frame(
  genus  = c("Sebastes", "Paralabrax", "Cottus", "Homo"),
  family = c("Scorpaenidae", "Serranidae", "Cottidae", "Hominidae"),
  stringsAsFactors = FALSE
)

.species_vec <- c(
  "Sebastes mystinus",
  "Paralabrax clathratus",
  "Corvus corax",         # not in local source
  "Homo sapiens"
)

# =============================================================================
# Input validation
# =============================================================================

test_that("stops if taxon_names is not character", {
  expect_error(fill_higher_ranks(123), regexp = "character")
})

test_that("stops if taxon_names is empty", {
  expect_error(fill_higher_ranks(character(0)), regexp = "non-empty")
})

test_that("stops if local_sources is not a list", {
  expect_error(fill_higher_ranks("Sp a", local_sources = "df"), regexp = "list")
})

test_that("stops if backbone_id is not a single numeric or NULL", {
  expect_error(
    fill_higher_ranks("Sp a", backbone_id = c(4L, 11L)),
    regexp = "single integer"
  )
})

test_that("stops if verbose is not logical", {
  expect_error(fill_higher_ranks("Sp a", verbose = "yes"), regexp = "TRUE or FALSE")
})

# =============================================================================
# Local source lookup
# =============================================================================

test_that("resolves family from a single local source", {
  out <- suppressWarnings(
    fill_higher_ranks("Sebastes mystinus",
                      local_sources = list(.local_src),
                      backbone_id   = NULL, fallback_backbone_id = NULL, verbose = FALSE)
  )
  expect_equal(out$family, "Scorpaenidae")
})

test_that("genus extracted as first word of binomial", {
  out <- suppressWarnings(
    fill_higher_ranks("Paralabrax clathratus",
                      local_sources = list(.local_src),
                      backbone_id   = NULL, fallback_backbone_id = NULL, verbose = FALSE)
  )
  expect_equal(out$genus, "Paralabrax")
})

test_that("handles single-word (genus-only) input", {
  out <- suppressWarnings(
    fill_higher_ranks("Sebastes",
                      local_sources = list(.local_src),
                      backbone_id   = NULL, fallback_backbone_id = NULL, verbose = FALSE)
  )
  expect_equal(out$genus,  "Sebastes")
  expect_equal(out$family, "Scorpaenidae")
})

test_that("multiple local sources combined; first-source-wins on conflict", {
  src1 <- data.frame(genus = "Corvus", family = "Corvidae",
                     stringsAsFactors = FALSE)
  src2 <- data.frame(genus = "Corvus", family = "WrongFamily",
                     stringsAsFactors = FALSE)
  out <- suppressWarnings(
    fill_higher_ranks("Corvus corax",
                      local_sources = list(src1, src2),
                      backbone_id   = NULL, fallback_backbone_id = NULL, verbose = FALSE)
  )
  expect_equal(out$family, "Corvidae")
})

test_that("sources with missing genus/family columns are silently skipped", {
  bad_src  <- data.frame(taxon = "Corvus", family = "Corvidae",
                          stringsAsFactors = FALSE)
  good_src <- data.frame(genus = "Corvus", family = "Corvidae",
                          stringsAsFactors = FALSE)
  out <- suppressWarnings(
    fill_higher_ranks("Corvus corax",
                      local_sources = list(bad_src, good_src),
                      backbone_id   = NULL, fallback_backbone_id = NULL, verbose = FALSE)
  )
  expect_equal(out$family, "Corvidae")
})

test_that("case-insensitive column names in local source work", {
  mixed_case <- data.frame(Genus = "Sebastes", Family = "Scorpaenidae",
                            stringsAsFactors = FALSE)
  out <- suppressWarnings(
    fill_higher_ranks("Sebastes mystinus",
                      local_sources = list(mixed_case),
                      backbone_id   = NULL, fallback_backbone_id = NULL, verbose = FALSE)
  )
  expect_equal(out$family, "Scorpaenidae")
})

# =============================================================================
# Output structure
# =============================================================================

test_that("output is a tibble with taxon_name, genus, family columns", {
  out <- suppressWarnings(
    fill_higher_ranks(.species_vec,
                      local_sources = list(.local_src),
                      backbone_id   = NULL, fallback_backbone_id = NULL, verbose = FALSE)
  )
  expect_s3_class(out, "tbl_df")
  expect_true(all(c("taxon_name", "genus", "family") %in% names(out)))
})

test_that("output length matches input length (preserves duplicates)", {
  names_with_dup <- c("Sebastes mystinus", "Sebastes mystinus", "Homo sapiens")
  out <- suppressWarnings(
    fill_higher_ranks(names_with_dup,
                      local_sources = list(.local_src),
                      backbone_id   = NULL, fallback_backbone_id = NULL, verbose = FALSE)
  )
  expect_equal(nrow(out), 3L)
  expect_equal(out$family, c("Scorpaenidae", "Scorpaenidae", "Hominidae"))
})

test_that("output order matches input order", {
  input <- c("Homo sapiens", "Sebastes mystinus", "Paralabrax clathratus")
  out   <- suppressWarnings(
    fill_higher_ranks(input,
                      local_sources = list(.local_src),
                      backbone_id   = NULL, fallback_backbone_id = NULL, verbose = FALSE)
  )
  expect_equal(out$taxon_name, input)
})

test_that("NA and blank inputs produce NA genus and family", {
  out <- suppressWarnings(
    fill_higher_ranks(c("Sebastes mystinus", NA, ""),
                      local_sources = list(.local_src),
                      backbone_id   = NULL, fallback_backbone_id = NULL, verbose = FALSE)
  )
  expect_equal(nrow(out), 3L)
  expect_true(is.na(out$genus[2L]))
  expect_true(is.na(out$genus[3L]))
})

# =============================================================================
# NA warning
# =============================================================================

test_that("warns when family cannot be resolved", {
  expect_warning(
    fill_higher_ranks("Unknown species",
                      local_sources = list(),
                      backbone_id   = NULL, fallback_backbone_id = NULL, verbose = FALSE),
    regexp = "no family"
  )
})

test_that("no warning when all families resolved locally", {
  expect_no_warning(
    fill_higher_ranks("Sebastes mystinus",
                      local_sources = list(.local_src),
                      backbone_id   = NULL, fallback_backbone_id = NULL, verbose = FALSE)
  )
})

# =============================================================================
# API fallback (mocked via local_mocked_bindings)
# =============================================================================

.make_verified <- function(genus, family) {
  tibble::tibble(
    user_supplied_name   = genus,
    matched_name         = genus,
    classification_path  = paste0("Animalia|Chordata|", family, "|", genus),
    classification_ranks = "kingdom|phylum|family|genus",
    score                = 1.0,
    verified             = TRUE
  )
}

test_that("primary backbone API is called for genera not in local sources", {
  api_called <- FALSE
  local_mocked_bindings(
    verify_taxon_names = function(names, backbone_id, ...) {
      api_called <<- TRUE
      expect_equal(backbone_id, 4L)
      .make_verified(names[1L], "Corvidae")
    },
    .package = "TaxaTools"
  )
  out <- fill_higher_ranks(
    "Corvus corax",
    local_sources = list(.local_src),
    backbone_id   = 4L, fallback_backbone_id = NULL,
    verbose       = FALSE
  )
  expect_true(api_called)
  expect_equal(out$family, "Corvidae")
})

test_that("fallback backbone is called when primary returns no match", {
  fb_called <- FALSE
  local_mocked_bindings(
    verify_taxon_names = function(names, backbone_id, ...) {
      if (backbone_id == 4L) {
        # Primary returns no result
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
      .make_verified(names[1L], "Corvidae")
    },
    .package = "TaxaTools"
  )
  out <- fill_higher_ranks(
    "Corvus corax",
    local_sources        = list(),
    backbone_id          = 4L,
    fallback_backbone_id = 11L,
    verbose              = FALSE
  )
  expect_true(fb_called)
  expect_equal(out$family, "Corvidae")
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
  suppressWarnings(
    fill_higher_ranks("Corvus corax",
                      local_sources        = list(),
                      backbone_id          = 4L,
                      fallback_backbone_id = 4L,
                      verbose              = FALSE)
  )
  expect_equal(call_count, 1L)   # only one API call
})

test_that("both backbone_id and fallback_backbone_id = NULL skips all API calls", {
  called <- FALSE
  local_mocked_bindings(
    verify_taxon_names = function(...) { called <<- TRUE; NULL },
    .package = "TaxaTools"
  )
  suppressWarnings(
    fill_higher_ranks("Corvus corax",
                      local_sources        = list(),
                      backbone_id          = NULL,
                      fallback_backbone_id = NULL,
                      verbose              = FALSE)
  )
  expect_false(called)
})

# =============================================================================
# Internal helpers
# =============================================================================

test_that(".extract_rank_from_classification returns NA for NA inputs", {
  expect_identical(
    TaxaTools:::.extract_rank_from_classification(NA, NA, "family"),
    NA_character_
  )
})

test_that(".extract_rank_from_classification extracts correct rank", {
  path  <- "Animalia|Chordata|Cottidae|Cottus|Cottus asper"
  ranks <- "kingdom|phylum|family|genus|species"
  expect_equal(
    TaxaTools:::.extract_rank_from_classification(path, ranks, "family"),
    "Cottidae"
  )
  expect_equal(
    TaxaTools:::.extract_rank_from_classification(path, ranks, "genus"),
    "Cottus"
  )
  expect_identical(
    TaxaTools:::.extract_rank_from_classification(path, ranks, "order"),
    NA_character_
  )
})

test_that(".build_genus_family_lookup returns empty tibble for empty list", {
  result <- TaxaTools:::.build_genus_family_lookup(list())
  expect_s3_class(result, "tbl_df")
  expect_equal(nrow(result), 0L)
})
