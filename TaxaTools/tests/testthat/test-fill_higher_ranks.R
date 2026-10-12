# test-fill_higher_ranks.R
# Tests for fill_higher_ranks(), .build_genus_rank_lookup(),
# .lookup_rank_from_backbone(), and .extract_classified_rank().
# Fully offline -- backbone API calls are mocked.

library(testthat)

# =============================================================================
# Fixtures
# =============================================================================

.local_src <- data.frame(
  genus = c("Sebastes", "Paralabrax", "Cottus", "Homo"),
  family = c("Scorpaenidae", "Serranidae", "Cottidae", "Hominidae"),
  stringsAsFactors = FALSE
)

.species_vec <- c(
  "Sebastes mystinus",
  "Paralabrax clathratus",
  "Corvus corax", # not in local source
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
      backbone_id = NULL, fallback_backbone_id = NULL, verbose = FALSE
    )
  )
  expect_equal(out$family, "Scorpaenidae")
})

test_that("genus extracted as first word of binomial", {
  out <- suppressWarnings(
    fill_higher_ranks("Paralabrax clathratus",
      local_sources = list(.local_src),
      backbone_id = NULL, fallback_backbone_id = NULL, verbose = FALSE
    )
  )
  expect_equal(out$genus, "Paralabrax")
})

test_that("handles single-word (genus-only) input", {
  out <- suppressWarnings(
    fill_higher_ranks("Sebastes",
      local_sources = list(.local_src),
      backbone_id = NULL, fallback_backbone_id = NULL, verbose = FALSE
    )
  )
  expect_equal(out$genus, "Sebastes")
  expect_equal(out$family, "Scorpaenidae")
})

test_that("multiple local sources combined; first-source-wins on conflict", {
  src1 <- data.frame(
    genus = "Corvus", family = "Corvidae",
    stringsAsFactors = FALSE
  )
  src2 <- data.frame(
    genus = "Corvus", family = "WrongFamily",
    stringsAsFactors = FALSE
  )
  out <- suppressWarnings(
    fill_higher_ranks("Corvus corax",
      local_sources = list(src1, src2),
      backbone_id = NULL, fallback_backbone_id = NULL, verbose = FALSE
    )
  )
  expect_equal(out$family, "Corvidae")
})

test_that("sources with missing genus/family columns are silently skipped", {
  bad_src <- data.frame(
    taxon = "Corvus", family = "Corvidae",
    stringsAsFactors = FALSE
  )
  good_src <- data.frame(
    genus = "Corvus", family = "Corvidae",
    stringsAsFactors = FALSE
  )
  out <- suppressWarnings(
    fill_higher_ranks("Corvus corax",
      local_sources = list(bad_src, good_src),
      backbone_id = NULL, fallback_backbone_id = NULL, verbose = FALSE
    )
  )
  expect_equal(out$family, "Corvidae")
})

test_that("case-insensitive column names in local source work", {
  mixed_case <- data.frame(
    Genus = "Sebastes", Family = "Scorpaenidae",
    stringsAsFactors = FALSE
  )
  out <- suppressWarnings(
    fill_higher_ranks("Sebastes mystinus",
      local_sources = list(mixed_case),
      backbone_id = NULL, fallback_backbone_id = NULL, verbose = FALSE
    )
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
      backbone_id = NULL, fallback_backbone_id = NULL, verbose = FALSE
    )
  )
  expect_s3_class(out, "tbl_df")
  expect_true(all(c("taxon_name", "genus", "family") %in% names(out)))
})

test_that("output length matches input length (preserves duplicates)", {
  names_with_dup <- c("Sebastes mystinus", "Sebastes mystinus", "Homo sapiens")
  out <- suppressWarnings(
    fill_higher_ranks(names_with_dup,
      local_sources = list(.local_src),
      backbone_id = NULL, fallback_backbone_id = NULL, verbose = FALSE
    )
  )
  expect_equal(nrow(out), 3L)
  expect_equal(out$family, c("Scorpaenidae", "Scorpaenidae", "Hominidae"))
})

test_that("output order matches input order", {
  input <- c("Homo sapiens", "Sebastes mystinus", "Paralabrax clathratus")
  out <- suppressWarnings(
    fill_higher_ranks(input,
      local_sources = list(.local_src),
      backbone_id = NULL, fallback_backbone_id = NULL, verbose = FALSE
    )
  )
  expect_equal(out$taxon_name, input)
})

test_that("NA and blank inputs produce NA genus and family", {
  out <- suppressWarnings(
    fill_higher_ranks(c("Sebastes mystinus", NA, ""),
      local_sources = list(.local_src),
      backbone_id = NULL, fallback_backbone_id = NULL, verbose = FALSE
    )
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
      backbone_id = NULL, fallback_backbone_id = NULL, verbose = FALSE
    ),
    regexp = "no family"
  )
})

test_that("no warning when all families resolved locally", {
  expect_no_warning(
    fill_higher_ranks("Sebastes mystinus",
      local_sources = list(.local_src),
      backbone_id = NULL, fallback_backbone_id = NULL, verbose = FALSE
    )
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
    backbone_id = 4L, fallback_backbone_id = NULL,
    verbose = FALSE
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
        user_supplied_name = names,
        matched_name = NA_character_,
        classification_path = NA_character_,
        classification_ranks = NA_character_,
        score = 0.0, verified = FALSE
      )
    },
    .package = "TaxaTools"
  )
  suppressWarnings(
    fill_higher_ranks("Corvus corax",
      local_sources        = list(),
      backbone_id          = 4L,
      fallback_backbone_id = 4L,
      verbose              = FALSE
    )
  )
  expect_equal(call_count, 1L) # only one API call
})

test_that("both backbone_id and fallback_backbone_id = NULL skips all API calls", {
  called <- FALSE
  local_mocked_bindings(
    verify_taxon_names = function(...) {
      called <<- TRUE
      NULL
    },
    .package = "TaxaTools"
  )
  suppressWarnings(
    fill_higher_ranks("Corvus corax",
      local_sources        = list(),
      backbone_id          = NULL,
      fallback_backbone_id = NULL,
      verbose              = FALSE
    )
  )
  expect_false(called)
})

# =============================================================================
# Genus correction (2026-07-25) -- keeps this function consistent with
# TaxaMatch::convert_taxonomy_backbone()'s current-name preference, closing a
# real gap where the two functions could report DIFFERENT genus labels for
# the same taxon, silently breaking TaxaAssign::join_priors()'s exact-string
# genus/family match between the likelihood side and the priors side.
# =============================================================================

.make_verified_synonym <- function(query_genus, resolved_genus, family) {
  tibble::tibble(
    user_supplied_name = query_genus,
    matched_name = resolved_genus,
    matched_rank = "genus",
    is_synonym = TRUE,
    classification_path = paste0("Animalia|Chordata|", family, "|", resolved_genus),
    classification_ranks = "kingdom|phylum|family|genus",
    score = 1.0,
    verified = TRUE
  )
}

test_that("genus is corrected to the backbone's resolved name for a genus-level synonym", {
  # Real motivating case: "Inu sp. 1 sensu Shibukawa et al., 2020." extracts
  # genus = "Inu" locally; GBIF resolves "Inu" as a synonym of "Luciogobius".
  local_mocked_bindings(
    verify_taxon_names = function(names, backbone_id, ...) {
      .make_verified_synonym("Inu", "Luciogobius", "Gobiidae")
    },
    .package = "TaxaTools"
  )
  out <- fill_higher_ranks(
    "Inu sp. 1 sensu Shibukawa et al., 2020.",
    local_sources        = list(),
    backbone_id          = 11L,
    fallback_backbone_id = NULL,
    verbose              = FALSE
  )
  expect_equal(out$genus, "Luciogobius")
  expect_equal(out$family, "Gobiidae")
})

test_that("genus is left unchanged when the API response has no matched_rank column (backward compat)", {
  # Same synonym scenario, but with a verify_fn shaped like every
  # pre-2026-07-25 mock in this file (no matched_rank/is_synonym) --
  # confirms old behavior (genus stays the locally-extracted string) is
  # fully preserved for any verify_taxon_names() implementation that
  # predates the fix.
  local_mocked_bindings(
    verify_taxon_names = function(names, backbone_id, ...) {
      .make_verified("Inu", "Gobiidae") # matched_name = "Inu" too, no matched_rank
    },
    .package = "TaxaTools"
  )
  out <- fill_higher_ranks(
    "Inu sp. 1 sensu Shibukawa et al., 2020.",
    local_sources        = list(),
    backbone_id          = 11L,
    fallback_backbone_id = NULL,
    verbose              = FALSE
  )
  expect_equal(out$genus, "Inu") # unchanged, as before this fix
  expect_equal(out$family, "Gobiidae")
})

test_that("genus is unchanged when matched_rank is present but not \"genus\"", {
  # Defensive case: a lookup that resolved to a coarser rank than genus
  # should not be trusted as a genus substitution.
  local_mocked_bindings(
    verify_taxon_names = function(names, backbone_id, ...) {
      row <- .make_verified("Inu", "Gobiidae")
      row$matched_rank <- "family"
      row$is_synonym <- NA
      row
    },
    .package = "TaxaTools"
  )
  out <- fill_higher_ranks(
    "Inu sp. 1 sensu Shibukawa et al., 2020.",
    local_sources        = list(),
    backbone_id          = 11L,
    fallback_backbone_id = NULL,
    verbose              = FALSE
  )
  expect_equal(out$genus, "Inu")
})

# =============================================================================
# Internal helpers
# =============================================================================

test_that(".extract_classified_rank returns NA for NA inputs", {
  expect_identical(
    TaxaTools:::.extract_classified_rank(NA, NA, "family"),
    NA_character_
  )
})

test_that(".extract_classified_rank extracts correct rank", {
  path <- "Animalia|Chordata|Cottidae|Cottus|Cottus asper"
  ranks <- "kingdom|phylum|family|genus|species"
  expect_equal(
    TaxaTools:::.extract_classified_rank(path, ranks, "family"),
    "Cottidae"
  )
  expect_equal(
    TaxaTools:::.extract_classified_rank(path, ranks, "genus"),
    "Cottus"
  )
  expect_identical(
    TaxaTools:::.extract_classified_rank(path, ranks, "order"),
    NA_character_
  )
})

test_that(".build_genus_rank_lookup returns an empty, correctly-named tibble for an empty list", {
  result <- TaxaTools:::.build_genus_rank_lookup(list(), "family")
  expect_s3_class(result, "tbl_df")
  expect_equal(nrow(result), 0L)
  expect_identical(names(result), c("genus", "family"))
  # the same for a rank other than family
  r2 <- TaxaTools:::.build_genus_rank_lookup(list(), "class")
  expect_equal(nrow(r2), 0L)
  expect_identical(names(r2), c("genus", "class"))
})

test_that(".build_genus_rank_lookup reads the requested rank and skips sources lacking it", {
  src_ok <- data.frame(genus = c("Cottus", "Girella"), class = c("Actinopteri", "Actinopteri"),
                       stringsAsFactors = FALSE)
  src_no_rank <- data.frame(genus = "Scomber", family = "Scombridae", stringsAsFactors = FALSE)
  got <- TaxaTools:::.build_genus_rank_lookup(list(src_no_rank, src_ok), "class")
  expect_identical(names(got), c("genus", "class"))
  expect_setequal(got$genus, c("Cottus", "Girella"))
  expect_true(all(got$class == "Actinopteri"))
  # a source lacking the rank column contributes nothing rather than erroring
  expect_equal(nrow(TaxaTools:::.build_genus_rank_lookup(list(src_no_rank), "class")), 0L)
})

# =============================================================================
# parse_classification_path() -- exported wrapper
# =============================================================================

test_that("parse_classification_path extracts family correctly", {
  expect_equal(
    parse_classification_path(
      "Animalia|Chordata|Cottidae|Cottus",
      "kingdom|phylum|family|genus",
      "family"
    ),
    "Cottidae"
  )
})

test_that("parse_classification_path extracts genus correctly", {
  expect_equal(
    parse_classification_path(
      "Animalia|Chordata|Cottidae|Cottus",
      "kingdom|phylum|family|genus",
      "genus"
    ),
    "Cottus"
  )
})

test_that("parse_classification_path returns NA for absent rank", {
  expect_identical(
    parse_classification_path(
      "Animalia|Chordata|Cottidae|Cottus",
      "kingdom|phylum|family|genus",
      "order"
    ),
    NA_character_
  )
})

test_that("parse_classification_path returns NA for NA inputs", {
  expect_identical(
    parse_classification_path(NA, NA, "family"),
    NA_character_
  )
})

# =============================================================================
# ranks= / record_source= (added 2026-10-08)
# =============================================================================

test_that("ranks must be a usable set of higher ranks", {
  expect_error(fill_higher_ranks("Aa aa", ranks = character(0)), "non-empty character vector")
  expect_error(fill_higher_ranks("Aa aa", ranks = c("family", NA)), "non-empty character vector")
  expect_error(fill_higher_ranks("Aa aa", ranks = 1), "non-empty character vector")
  # genus is derived from the input, not looked up; species IS the input
  expect_error(fill_higher_ranks("Aa aa", ranks = c("family", "genus")), "must not include 'genus'")
  expect_error(fill_higher_ranks("Aa aa", ranks = "species"), "must not include 'species'")
  expect_error(fill_higher_ranks("Aa aa", record_source = NA), "record_source must be TRUE or FALSE")
  expect_error(fill_higher_ranks("Aa aa", record_source = "yes"), "record_source must be TRUE or FALSE")
})

test_that("record_source controls the source columns, and local sources win", {
  # Entirely offline: local_sources supply both ranks, so no API is reached and
  # both backbones are switched off.
  loc <- data.frame(
    genus = c("Girella", "Corallina"),
    family = c("LocalFam", "LocalFam2"),
    class = c("LocalClass", "LocalClass2"),
    stringsAsFactors = FALSE
  )
  off <- fill_higher_ranks(
    c("Girella nigricans", "Corallina caespitosa"),
    local_sources = list(loc), ranks = c("family", "class"),
    backbone_id = NULL, fallback_backbone_id = NULL, verbose = FALSE
  )
  expect_identical(names(off), c("taxon_name", "genus", "family", "class"))
  expect_identical(off$class, c("LocalClass", "LocalClass2"))

  on <- fill_higher_ranks(
    c("Girella nigricans", "Corallina caespitosa"),
    local_sources = list(loc), ranks = c("family", "class"), record_source = TRUE,
    backbone_id = NULL, fallback_backbone_id = NULL, verbose = FALSE
  )
  expect_identical(
    names(on),
    c("taxon_name", "genus", "family", "class", "family_source", "class_source")
  )
  expect_true(all(on$class_source == "local"))
  # the rank columns themselves are unaffected by record_source
  expect_identical(on$class, off$class)
  expect_identical(on$family, off$family)
})

test_that("an unresolved rank is NA, warns, and carries no source", {
  expect_warning(
    res <- fill_higher_ranks("Zzzz qqqq", ranks = "class", record_source = TRUE,
                             backbone_id = NULL, fallback_backbone_id = NULL, verbose = FALSE),
    "no class after all lookups"
  )
  expect_true(is.na(res$class))
  expect_true(is.na(res$class_source))
})

test_that("NA and blank inputs stay NA across every added column", {
  loc <- data.frame(genus = "Girella", family = "F", class = "C", stringsAsFactors = FALSE)
  res <- suppressWarnings(fill_higher_ranks(
    c("Girella nigricans", NA, ""), local_sources = list(loc),
    ranks = c("family", "class"), record_source = TRUE,
    backbone_id = NULL, fallback_backbone_id = NULL, verbose = FALSE
  ))
  expect_equal(nrow(res), 3L)
  for (cc in c("genus", "family", "class", "family_source", "class_source")) {
    expect_true(all(is.na(res[[cc]][2:3])), info = cc)
  }
  expect_identical(res$class[1], "C")
})

test_that(".rank_from_lineage reads a rank off a lineage and is NA when silent", {
  lin <- tibble::tibble(
    genus = c("Girella", "Scomber"),
    resolved_genus = c(NA_character_, NA_character_),
    # GBIF's shape for a ray-finned fish: no class entry at all
    path  = c("Animalia|Chordata|Perciformes|Girellidae|Girella",
              "Animalia|Chordata|Actinopteri|Perciformes|Scombridae|Scomber"),
    ranks = c("kingdom|phylum|order|family|genus",
              "kingdom|phylum|class|order|family|genus")
  )
  expect_identical(TaxaTools:::.rank_from_lineage(lin, c("Girella", "Scomber"), "class"),
                   c(NA_character_, "Actinopteri"))
  expect_identical(TaxaTools:::.rank_from_lineage(lin, c("Girella", "Scomber"), "phylum"),
                   c("Chordata", "Chordata"))
  # a genus the lineage table does not contain
  expect_identical(TaxaTools:::.rank_from_lineage(lin, "Nope", "class"), NA_character_)
})

test_that(".lineages_agree rejects a phylum contradiction and tolerates the rest", {
  prim <- tibble::tibble(
    genus = c("Corallina", "Girella", "Onlyhere"),
    resolved_genus = NA_character_,
    path  = c("Rhodophyta|Florideophyceae|Corallinales|Corallina",
              "Metazoa|Chordata|Centrarchiformes|Girellidae|Girella",
              "Rhodophyta|Florideophyceae|Onlyhere"),
    ranks = c("phylum|class|order|genus",
              "kingdom|phylum|order|family|genus",
              "phylum|class|genus")
  )
  fb <- tibble::tibble(
    genus = c("Corallina", "Girella", "Unseen"),
    resolved_genus = NA_character_,
    # Corallina: a DIFFERENT phylum -- the worm homonym. Girella: same phylum,
    # different kingdom vocabulary (Animalia vs Metazoa) and a different order,
    # both of which must be tolerated. Unseen: absent from the primary.
    path  = c("Animalia|Annelida|Polychaeta|Sabellida|Corallina",
              "Animalia|Chordata|Perciformes|Kyphosidae|Girella",
              "Animalia|Chordata|Perciformes|Xx|Unseen"),
    ranks = c("kingdom|phylum|class|order|genus",
              "kingdom|phylum|order|family|genus",
              "kingdom|phylum|order|family|genus")
  )
  got <- TaxaTools:::.lineages_agree(prim, fb)
  expect_false("Corallina" %in% got)
  expect_true("Girella" %in% got)
  # A genus the primary could not place at all is REFUSED, not trusted. This
  # is not the same as the primary being silent about one rank: NCBI refuses
  # "Liparis" as ambiguous and GBIF resolves the same string to an insect
  # genus, so a "nothing to contradict" allowance filled class = "Insecta" on
  # a fish (measured 2026-10-08, caught in the fill map).
  expect_false("Unseen" %in% got)
  # no primary at all means nothing to check against
  expect_setequal(TaxaTools:::.lineages_agree(NULL, fb), fb$genus)
  expect_identical(TaxaTools:::.lineages_agree(prim, NULL), character(0))
})

# ---- a genus that maps to two values is REPORTED, not silently chosen ------
# `local_sources` is a priority-ordered chain and first-source-wins is its
# documented contract -- the right policy when the caller ranked its sources by
# authority. The same shape also arises when two PEER sources disagree because
# the genus is a homonym (Dilophus is a fly and a brown alga; Porella a
# bryozoan and a liverwort), and there the winner is an artefact of binding
# order. The function cannot tell those apart, so the choice stands and is
# reported. Both backbones are NULL here so nothing reaches a network.

.amb_src_a <- data.frame(
  genus = c("Gobius", "Dilophus"), family = c("Gobiidae", "Bibionidae"),
  class = c("Actinopteri", "Insecta"), stringsAsFactors = FALSE
)
.amb_src_b <- data.frame(
  genus = c("Dilophus", "Porella"), family = c("Dictyotaceae", "Porellaceae"),
  class = c("Phaeophyceae", "Jungermanniopsida"), stringsAsFactors = FALSE
)

test_that("a genus mapping to two families is named in a message", {
  expect_message(
    out <- fill_higher_ranks(
      c("Gobius niger", "Dilophus sp", "Porella sp"),
      ranks = "family", local_sources = list(.amb_src_a, .amb_src_b),
      backbone_id = NULL, fallback_backbone_id = NULL, verbose = FALSE
    ),
    "Dilophus"
  )
  # Behaviour is UNCHANGED: first source still wins, and the unambiguous
  # genera are unaffected.
  expect_equal(out$family[out$genus == "Gobius"], "Gobiidae")
  expect_equal(out$family[out$genus == "Dilophus"], "Bibionidae")
  expect_equal(out$family[out$genus == "Porella"], "Porellaceae")
})

test_that("the report is rank-general, not a family rule", {
  # The same two sources also disagree about Dilophus's CLASS. Nothing in the
  # rule names a rank or a taxon.
  expect_message(
    fill_higher_ranks(
      c("Gobius niger", "Dilophus sp"),
      ranks = "class", local_sources = list(.amb_src_a, .amb_src_b),
      backbone_id = NULL, fallback_backbone_id = NULL, verbose = FALSE
    ),
    "more than one class"
  )
})

test_that("sources that AGREE about a genus are not reported", {
  # Ambiguity means conflicting values, not merely appearing twice.
  a <- data.frame(genus = "Gobius", family = "Gobiidae", stringsAsFactors = FALSE)
  b <- data.frame(genus = "Gobius", family = "Gobiidae", stringsAsFactors = FALSE)
  out <- expect_silent(fill_higher_ranks(
    "Gobius niger", ranks = "family", local_sources = list(a, b),
    backbone_id = NULL, fallback_backbone_id = NULL, verbose = FALSE
  ))
  expect_equal(out$family, "Gobiidae")
})

# ---- an ambiguous genus is resolved from the taxon's own row ---------------
# The shape that matters: the FIRST source answers at genus level with a
# homonym's family, and the taxon's own row sits in a LATER source. Precedence
# alone returns the fly's family for an alga.

test_that("an ambiguous genus is filled from the taxon's own row, not precedence", {
  fly <- data.frame(
    genus = "Dilophus", family = "Bibionidae",
    stringsAsFactors = FALSE
  )
  alga <- data.frame(
    taxon_name = "Dilophus okamurae", genus = "Dilophus",
    family = "Dictyotaceae", stringsAsFactors = FALSE
  )
  out <- suppressWarnings(suppressMessages(
    fill_higher_ranks("Dilophus okamurae",
      local_sources = list(fly, alga),
      backbone_id = NULL, fallback_backbone_id = NULL, verbose = FALSE
    )
  ))
  expect_equal(out$family, "Dictyotaceae")
})

test_that("own-row preference is rank-general, not family-specific", {
  fly <- data.frame(
    genus = "Dilophus", class = "Insecta",
    stringsAsFactors = FALSE
  )
  alga <- data.frame(
    taxon_name = "Dilophus okamurae", genus = "Dilophus",
    class = "Phaeophyceae", stringsAsFactors = FALSE
  )
  out <- suppressWarnings(suppressMessages(
    fill_higher_ranks("Dilophus okamurae",
      ranks = "class", local_sources = list(fly, alga),
      backbone_id = NULL, fallback_backbone_id = NULL, verbose = FALSE
    )
  ))
  expect_equal(out$class, "Phaeophyceae")
})

test_that("a `species` column serves as the taxon's own name when taxon_name is absent", {
  fly <- data.frame(
    genus = "Dilophus", family = "Bibionidae",
    stringsAsFactors = FALSE
  )
  alga <- data.frame(
    species = "Dilophus okamurae", genus = "Dilophus",
    family = "Dictyotaceae", stringsAsFactors = FALSE
  )
  out <- suppressWarnings(suppressMessages(
    fill_higher_ranks("Dilophus okamurae",
      local_sources = list(fly, alga),
      backbone_id = NULL, fallback_backbone_id = NULL, verbose = FALSE
    )
  ))
  expect_equal(out$family, "Dictyotaceae")
})

test_that("an UNambiguous genus keeps the precedence even when a row disagrees", {
  # Measured guard: where the genus is unanimous, preferring one row's value
  # only imports that row's errors. `Grateloupia` is unanimous at genus here,
  # so the stray own-row value must NOT win.
  authority <- data.frame(
    genus = "Grateloupia", family = "Halymeniaceae",
    stringsAsFactors = FALSE
  )
  stray <- data.frame(
    taxon_name = "Grateloupia prolongata", genus = NA_character_,
    family = "Callithamniaceae", stringsAsFactors = FALSE
  )
  out <- suppressWarnings(suppressMessages(
    fill_higher_ranks("Grateloupia prolongata",
      local_sources = list(authority, stray),
      backbone_id = NULL, fallback_backbone_id = NULL, verbose = FALSE
    )
  ))
  expect_equal(out$family, "Halymeniaceae")
})

test_that("an ambiguous genus with no row of its own keeps the precedence", {
  src1 <- data.frame(genus = "Dilophus", family = "Bibionidae",
                     stringsAsFactors = FALSE)
  src2 <- data.frame(genus = "Dilophus", family = "Dictyotaceae",
                     stringsAsFactors = FALSE)
  out <- suppressWarnings(suppressMessages(
    fill_higher_ranks("Dilophus sp1",
      local_sources = list(src1, src2),
      backbone_id = NULL, fallback_backbone_id = NULL, verbose = FALSE
    )
  ))
  expect_equal(out$family, "Bibionidae")
})

test_that("the ambiguity report says how many names the own row resolved", {
  fly <- data.frame(genus = "Dilophus", family = "Bibionidae",
                    stringsAsFactors = FALSE)
  alga <- data.frame(taxon_name = "Dilophus okamurae", genus = "Dilophus",
                     family = "Dictyotaceae", stringsAsFactors = FALSE)
  expect_message(
    suppressWarnings(fill_higher_ranks("Dilophus okamurae",
      local_sources = list(fly, alga),
      backbone_id = NULL, fallback_backbone_id = NULL, verbose = FALSE
    )),
    "1 name\\(s\\) resolved that way"
  )
})

test_that("a name carrying two values itself is settled by precedence and named", {
  # Competing circumscription of ONE organism, not a homonym: both candidates
  # describe this taxon, so the precedence still decides -- but it must say so.
  a <- data.frame(
    taxon_name = "Citharichthys stigmaeus", genus = "Citharichthys",
    family = "Cyclopsettidae", stringsAsFactors = FALSE
  )
  b <- data.frame(
    taxon_name = "Citharichthys stigmaeus", genus = "Citharichthys",
    family = "Paralichthyidae", stringsAsFactors = FALSE
  )
  expect_message(
    suppressWarnings(fill_higher_ranks("Citharichthys stigmaeus",
      local_sources = list(a, b),
      backbone_id = NULL, fallback_backbone_id = NULL, verbose = FALSE
    )),
    "competing circumscription"
  )
  out <- suppressWarnings(suppressMessages(
    fill_higher_ranks("Citharichthys stigmaeus",
      local_sources = list(a, b),
      backbone_id = NULL, fallback_backbone_id = NULL, verbose = FALSE
    )
  ))
  expect_equal(out$family, "Cyclopsettidae")
})

test_that(".build_name_rank_lookup dedups first-source-wins and flags conflicts", {
  a <- data.frame(taxon_name = "Aa bb", family = "F1", stringsAsFactors = FALSE)
  b <- data.frame(taxon_name = "Aa bb", family = "F2", stringsAsFactors = FALSE)
  no_rank <- data.frame(taxon_name = "Aa bb", stringsAsFactors = FALSE)
  no_name <- data.frame(genus = "Aa", family = "F3", stringsAsFactors = FALSE)
  lu <- .build_name_rank_lookup(list(no_rank, no_name, a, b), "family")
  expect_equal(nrow(lu), 1L)
  expect_equal(lu$family, "F1")
  expect_equal(attr(lu, "ambiguous_names"), "Aa bb")
})

test_that(".build_name_rank_lookup returns a shaped empty table with no usable source", {
  lu <- .build_name_rank_lookup(list(data.frame(x = 1), "not a df"), "family")
  expect_equal(nrow(lu), 0L)
  expect_true(all(c("taxon_name", "family") %in% names(lu)))
  expect_equal(attr(lu, "ambiguous_names"), character(0))
})
