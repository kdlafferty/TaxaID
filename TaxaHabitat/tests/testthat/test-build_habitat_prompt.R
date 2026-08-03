# tests/testthat/test-build_habitat_prompt.R
#
# Tests for build_habitat_prompt() -- new weighted prompt format.
# All tests are pure (no API calls, no files, no network).
#
# Key changes from old version:
#   - extra_covariates defaults to character(0)
#   - prompt$habitat_cols element now present
#   - Prompt text requests weighted output (not single-best-fit)
#   - Other_weight and habitat_best_guess columns requested in prompt
#   - BINARY COVARIATES section omitted from prompt when extra_covariates empty

# ==============================================================================
# Helpers
# ==============================================================================

simple_taxa <- c("Gadus morhua", "Sebastes mystinus", "Engraulis mordax")

simple_scheme <- data.frame(
  l1_name = c("Rocky Subtidal", "Kelp Forest", "Pelagic"),
  stringsAsFactors = FALSE
)

two_level_scheme <- data.frame(
  l1_name = c("Marine", "Marine", "Freshwater"),
  l2_name = c("Rocky Subtidal", "Pelagic Open Water", "Rivers"),
  l2_code = c("M1", "M2", "F1"),
  realm   = c("marine", "marine", "freshwater"),
  stringsAsFactors = FALSE
)

# ==============================================================================
# Part A: Input validation
# ==============================================================================

test_that("stops when taxon_list is empty", {
  expect_error(
    build_habitat_prompt(character(0)),
    "non-empty character vector"
  )
})

test_that("stops when taxon_list is not character", {
  expect_error(
    build_habitat_prompt(123),
    "non-empty character vector"
  )
})

test_that("stops when extra_covariates is not character", {
  expect_error(
    build_habitat_prompt(simple_taxa, extra_covariates = 1:3),
    "must be a character vector"
  )
})

test_that("stops when chunk_size < 1", {
  expect_error(
    build_habitat_prompt(simple_taxa, chunk_size = 0),
    "must be a positive integer"
  )
})

# ==============================================================================
# Part B: S3 class and object structure
# ==============================================================================

test_that("returns an object with class c('habitat_prompt', 'llm_prompt')", {
  prompt <- build_habitat_prompt(simple_taxa, habitat_scheme = simple_scheme)
  expect_true(inherits(prompt, "habitat_prompt"))
  expect_true(inherits(prompt, "llm_prompt"))
})

test_that("object has all required list elements", {
  prompt <- build_habitat_prompt(simple_taxa, habitat_scheme = simple_scheme)
  required <- c("prompts", "taxa", "chunks", "scheme",
                "habitat_cols", "extra_covariates", "chunk_size", "n_chunks")
  expect_true(all(required %in% names(prompt)))
})

test_that("taxa element is deduplicated", {
  duped <- c("Gadus morhua", "Gadus morhua", "Sebastes mystinus")
  prompt <- build_habitat_prompt(duped, habitat_scheme = simple_scheme)
  expect_equal(length(prompt$taxa), 2L)
})

test_that("taxa element has whitespace trimmed", {
  messy <- c("  Gadus morhua  ", "Sebastes mystinus")
  prompt <- build_habitat_prompt(messy, habitat_scheme = simple_scheme)
  expect_equal(prompt$taxa[1], "Gadus morhua")
})

test_that("n_chunks is correct for small list", {
  prompt <- build_habitat_prompt(simple_taxa, habitat_scheme = simple_scheme,
                                 chunk_size = 60L)
  expect_equal(prompt$n_chunks, 1L)
})

test_that("n_chunks is correct when list exceeds chunk_size", {
  many_taxa <- paste0("Species ", seq_len(10))
  prompt <- build_habitat_prompt(many_taxa, habitat_scheme = simple_scheme,
                                 chunk_size = 3L)
  expect_equal(prompt$n_chunks, 4L)   # ceiling(10/3)
})

test_that("prompts list has one element per chunk", {
  many_taxa <- paste0("Species ", seq_len(7))
  prompt <- build_habitat_prompt(many_taxa, habitat_scheme = simple_scheme,
                                 chunk_size = 3L)
  expect_equal(length(prompt$prompts), prompt$n_chunks)
})

test_that("chunks list has one element per chunk", {
  many_taxa <- paste0("Species ", seq_len(7))
  prompt <- build_habitat_prompt(many_taxa, habitat_scheme = simple_scheme,
                                 chunk_size = 3L)
  expect_equal(length(prompt$chunks), prompt$n_chunks)
})

# ==============================================================================
# Part C: extra_covariates default is empty
# ==============================================================================

test_that("extra_covariates defaults to character(0)", {
  prompt <- build_habitat_prompt(simple_taxa, habitat_scheme = simple_scheme)
  expect_equal(prompt$extra_covariates, character(0))
})

test_that("prompt text does NOT contain binary covariates section by default", {
  prompt <- build_habitat_prompt(simple_taxa, habitat_scheme = simple_scheme)
  expect_false(grepl("BINARY COVARIATES", prompt$prompts[[1]], ignore.case = TRUE))
})

test_that("prompt text DOES contain binary covariates section when supplied", {
  prompt <- build_habitat_prompt(simple_taxa,
                                 habitat_scheme     = simple_scheme,
                                 extra_covariates   = c("Invasive", "Migratory"))
  expect_true(grepl("Invasive", prompt$prompts[[1]]))
  expect_true(grepl("Migratory", prompt$prompts[[1]]))
})

# ==============================================================================
# Part D: habitat_cols element
# ==============================================================================

test_that("habitat_cols matches single-level scheme l1_name values", {
  prompt <- build_habitat_prompt(simple_taxa, habitat_scheme = simple_scheme)
  expect_equal(prompt$habitat_cols, c("Rocky Subtidal", "Kelp Forest", "Pelagic"))
})

test_that("habitat_cols matches two-level scheme l2_name values", {
  prompt <- build_habitat_prompt(simple_taxa, habitat_scheme = two_level_scheme)
  expect_equal(prompt$habitat_cols,
               c("Rocky Subtidal", "Pelagic Open Water", "Rivers"))
})

test_that("habitat_cols has no duplicates", {
  prompt <- build_habitat_prompt(simple_taxa, habitat_scheme = simple_scheme)
  expect_equal(length(prompt$habitat_cols), length(unique(prompt$habitat_cols)))
})

test_that("NULL habitat_scheme gives 3-category default", {
  prompt <- build_habitat_prompt(simple_taxa)   # NULL -> Marine/Freshwater/Terrestrial
  expect_equal(length(prompt$habitat_cols), 3L)
  expect_true("Marine" %in% prompt$habitat_cols)
  expect_true("Freshwater" %in% prompt$habitat_cols)
  expect_true("Terrestrial" %in% prompt$habitat_cols)
})

# ==============================================================================
# Part E: Prompt text content
# ==============================================================================

test_that("prompt text contains 'weight' instruction", {
  prompt <- build_habitat_prompt(simple_taxa, habitat_scheme = simple_scheme)
  expect_true(grepl("weight", prompt$prompts[[1]], ignore.case = TRUE))
})

test_that("prompt text mentions Other_weight column", {
  prompt <- build_habitat_prompt(simple_taxa, habitat_scheme = simple_scheme)
  expect_true(grepl("Other_weight", prompt$prompts[[1]]))
})

test_that("prompt text mentions habitat_best_guess column", {
  prompt <- build_habitat_prompt(simple_taxa, habitat_scheme = simple_scheme)
  expect_true(grepl("habitat_best_guess", prompt$prompts[[1]]))
})

test_that("prompt text mentions summing to 1.0", {
  prompt <- build_habitat_prompt(simple_taxa, habitat_scheme = simple_scheme)
  expect_true(grepl("1\\.0|sum to", prompt$prompts[[1]], ignore.case = TRUE))
})

test_that("each taxon name appears in its chunk's prompt", {
  prompt <- build_habitat_prompt(simple_taxa, habitat_scheme = simple_scheme,
                                 chunk_size = 60L)
  for (taxon in simple_taxa) {
    expect_true(grepl(taxon, prompt$prompts[[1]], fixed = TRUE))
  }
})

test_that("taxon names do NOT spill across chunks", {
  many_taxa <- paste0("Species_", seq_len(6))
  prompt <- build_habitat_prompt(many_taxa, habitat_scheme = simple_scheme,
                                 chunk_size = 3L)
  # chunk 1 should only contain first 3, not last 3
  expect_true(grepl("Species_1", prompt$prompts[[1]], fixed = TRUE))
  expect_false(grepl("Species_4", prompt$prompts[[1]], fixed = TRUE))
  expect_true(grepl("Species_4", prompt$prompts[[2]], fixed = TRUE))
})

test_that("custom single-level scheme: habitat names appear in prompt", {
  prompt <- build_habitat_prompt(simple_taxa, habitat_scheme = simple_scheme)
  for (h in simple_scheme$l1_name) {
    expect_true(grepl(h, prompt$prompts[[1]], fixed = TRUE))
  }
})

test_that("custom two-level scheme: l2 names appear in prompt", {
  prompt <- build_habitat_prompt(simple_taxa, habitat_scheme = two_level_scheme)
  for (h in two_level_scheme$l2_name) {
    expect_true(grepl(h, prompt$prompts[[1]], fixed = TRUE))
  }
})

# ==============================================================================
# Part F: scheme element stored correctly
# ==============================================================================

test_that("scheme element is a dataframe", {
  prompt <- build_habitat_prompt(simple_taxa, habitat_scheme = simple_scheme)
  expect_true(is.data.frame(prompt$scheme))
})

test_that("NULL habitat_scheme stores 3-category scheme", {
  prompt <- build_habitat_prompt(simple_taxa)
  expect_true(is.data.frame(prompt$scheme))
  expect_equal(nrow(prompt$scheme), 3L)
  expect_equal(sort(prompt$scheme$l1_name),
               sort(c("Marine", "Freshwater", "Terrestrial")))
})

test_that("scheme stored has padded optional columns", {
  # simple_scheme has no l2_name/l2_code/realm -- these should be padded with NA
  prompt <- build_habitat_prompt(simple_taxa, habitat_scheme = simple_scheme)
  expect_true("l2_name" %in% names(prompt$scheme))
  expect_true("realm"   %in% names(prompt$scheme))
  expect_true(all(is.na(prompt$scheme$l2_name)))
})

# ==============================================================================
# Part G: print method
# ==============================================================================

test_that("print.habitat_prompt runs without error", {
  prompt <- build_habitat_prompt(simple_taxa, habitat_scheme = simple_scheme)
  expect_output(print(prompt), "<habitat_prompt>")
})

test_that("print shows '(none)' when extra_covariates is empty", {
  prompt <- build_habitat_prompt(simple_taxa, habitat_scheme = simple_scheme)
  expect_output(print(prompt), "\\(none\\)")
})

test_that("print shows covariate names when extra_covariates supplied", {
  prompt <- build_habitat_prompt(simple_taxa, habitat_scheme = simple_scheme,
                                 extra_covariates = c("Invasive"))
  expect_output(print(prompt), "Invasive")
})

test_that("print shows habitat count", {
  prompt <- build_habitat_prompt(simple_taxa, habitat_scheme = simple_scheme)
  expect_output(print(prompt), "3 columns")
})

# ==============================================================================
# Part H: geographic_context parameter
# ==============================================================================

test_that("build_habitat_prompt with geographic_context includes context in prompt", {
  prompt <- build_habitat_prompt(
    taxon_list         = c("Sebastes mystinus", "Gadus morhua"),
    geographic_context = "Southern California"
  )
  expect_true(grepl("GEOGRAPHIC CONTEXT", prompt$prompts[[1]], fixed = TRUE))
  expect_true(grepl("Southern California", prompt$prompts[[1]], fixed = TRUE))
  expect_true(grepl("ecoregion_best_guess", prompt$prompts[[1]], fixed = TRUE))
})

test_that("build_habitat_prompt without geographic_context omits ecoregion column", {
  prompt <- build_habitat_prompt(
    taxon_list = c("Sebastes mystinus", "Gadus morhua")
  )
  expect_false(grepl("GEOGRAPHIC CONTEXT", prompt$prompts[[1]], fixed = TRUE))
  expect_false(grepl("ecoregion_best_guess", prompt$prompts[[1]], fixed = TRUE))
})

test_that("build_habitat_prompt stores geographic_context in object", {
  prompt <- build_habitat_prompt(
    taxon_list         = c("Sebastes mystinus"),
    geographic_context = "Chesapeake Bay"
  )
  expect_equal(prompt$geographic_context, "Chesapeake Bay")
})

test_that("build_habitat_prompt with NULL geographic_context stores NULL", {
  prompt <- build_habitat_prompt(
    taxon_list = c("Sebastes mystinus")
  )
  expect_null(prompt$geographic_context)
})

test_that("build_habitat_prompt rejects invalid geographic_context", {
  expect_error(
    build_habitat_prompt(c("Sp A"), geographic_context = ""),
    "non-empty string"
  )
  expect_error(
    build_habitat_prompt(c("Sp A"), geographic_context = c("a", "b")),
    "non-empty string"
  )
  expect_error(
    build_habitat_prompt(c("Sp A"), geographic_context = NA_character_),
    "non-empty string"
  )
})

test_that("prompt quoting instruction only mentions ecoregion_best_guess when geographic_context is set", {
  no_geo <- build_habitat_prompt(c("Sp A"))
  expect_true(grepl("If habitat_best_guess contains a comma", no_geo$prompts[[1]], fixed = TRUE))
  expect_false(grepl("ecoregion_best_guess contains a comma", no_geo$prompts[[1]], fixed = TRUE))

  with_geo <- build_habitat_prompt(c("Sp A"), geographic_context = "Gulf of Maine")
  expect_true(grepl("ecoregion_best_guess contains a comma", with_geo$prompts[[1]], fixed = TRUE))
})

# ==============================================================================
# build_iucn_scheme() -- realm column and IUCN Habitats Classification
# Scheme v3.1 audit (2026-08-01 code review)
# ==============================================================================

test_that("build_iucn_scheme(realm=) sets a non-NA realm matching the request", {
  # Real bug: .l1_to_realm() only recognises marine/freshwater L1 group
  # names and returned NA for everything else, so a realm = "terrestrial"
  # (or "artificial") scheme previously had realm = NA on every row despite
  # the caller explicitly requesting that realm.
  scheme <- suppressWarnings(build_iucn_scheme(realm = "terrestrial"))
  expect_true(all(scheme$realm == "terrestrial"))

  scheme_art <- suppressWarnings(build_iucn_scheme(realm = "artificial"))
  expect_true(all(scheme_art$realm == "artificial"))

  scheme_mar <- suppressWarnings(build_iucn_scheme(realm = "marine"))
  expect_true(all(scheme_mar$realm == "marine"))
})

test_that("build_iucn_scheme(realm = NULL) still varies realm per L1 group", {
  scheme <- suppressWarnings(build_iucn_scheme(l1 = "all", l2 = "none"))
  expect_true("marine" %in% scheme$realm)
  expect_true(any(is.na(scheme$realm)))  # terrestrial/artificial groups
})

test_that("Shrubland has real Subarctic/Subantarctic/Boreal L2 subcategories, not Forest's order", {
  # Real bug: the table previously used Forest's Boreal/Subarctic/Subantarctic
  # order for Shrubland too, when the real scheme's own order for Shrubland's
  # first three subcategories is Subarctic/Subantarctic/Boreal. Some names
  # also appear under other L1 groups and get disambiguated with "(L1 parent)"
  # -- match by substring rather than exact equality.
  scheme <- suppressWarnings(build_iucn_scheme(l1 = "none", l2 = "all"))
  shrub_l2 <- scheme$l2_name[scheme$l1_name == "Shrubland"]
  expect_true(any(grepl("^Subarctic", shrub_l2)))
  expect_true(any(grepl("^Subantarctic", shrub_l2)))
  expect_true(any(grepl("^Boreal", shrub_l2)))
})

test_that("Marine Neritic contains real IUCN 9.x categories, not fabricated ones", {
  scheme <- suppressWarnings(build_iucn_scheme(realm = "marine", l1 = "none", l2 = "all"))
  neritic <- scheme[scheme$l1_name == "Marine Neritic", ]
  # Real categories that were previously missing/scrambled
  expect_true("Pelagic" %in% neritic$l2_name)
  expect_true("Seagrass (submerged)" %in% neritic$l2_name)
  # Fabricated categories that must no longer appear
  expect_false("Subtidal Cave and Overhangs" %in% neritic$l2_name)
  expect_false("Pelagic (Supercolumnar)" %in% neritic$l2_name)
  expect_false(any(grepl("Seamounts and Knolls", neritic$l2_name)))
})

test_that("Seamount is its own real category under Marine Deep Ocean Floor", {
  scheme <- suppressWarnings(build_iucn_scheme(realm = "marine", l1 = "none", l2 = "all"))
  deep <- scheme[scheme$l1_name == "Marine Deep Ocean Floor", ]
  expect_true("Seamount" %in% deep$l2_name)
  expect_true("Abyssal Mountain/Hills" %in% deep$l2_name)
})

test_that("Rocky Areas (inland) and Introduced Vegetation have no fabricated L2 subcategories", {
  # Real bug: both are L1-only in the real IUCN scheme (no L2 subcategories
  # at all), but the table previously fabricated two L2 rows for each.
  scheme <- suppressWarnings(build_iucn_scheme(realm = "terrestrial", l1 = "all", l2 = "none"))
  rocky <- scheme[scheme$l1_name == "Rocky Areas (inland)", ]
  expect_equal(nrow(rocky), 1L)
  expect_true(is.na(rocky$l2_name))

  veg <- scheme[scheme$l1_name == "Introduced Vegetation", ]
  expect_equal(nrow(veg), 1L)
  expect_true(is.na(veg$l2_name))
})

test_that("a mixed-scale scheme's L1-only rows display the L1 name, not literal NA", {
  # Real, reproducible bug: build_iucn_scheme(realm = "terrestrial",
  # l2 = "Temperate") returns a scheme with both L1-only rows (l2_name = NA)
  # and L2 rows in the same object; build_habitat_prompt() previously
  # printed literal "NA" for every L1-only row's habitat name in the
  # HABITAT CLASSES prompt block instead of falling back to l1_name.
  scheme <- suppressWarnings(suppressMessages(
    build_iucn_scheme(realm = "terrestrial", l2 = "Temperate")
  ))
  prompt <- build_habitat_prompt(c("Pinus contorta"), habitat_scheme = scheme)
  prompt_text <- prompt$prompts[[1]]

  expect_false(grepl("\\bNA\\b\\s*\\[", prompt_text))
  expect_true(grepl("Forest\\s*\\[Forest\\]", prompt_text))
  expect_true(grepl("Temperate \\(Forest\\)\\s*\\[Forest\\]", prompt_text))
})
