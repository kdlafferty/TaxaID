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
  realm = c("marine", "marine", "freshwater"),
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
  required <- c(
    "prompts", "taxa", "chunks", "scheme",
    "habitat_cols", "extra_covariates", "chunk_size", "n_chunks"
  )
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
  prompt <- build_habitat_prompt(simple_taxa,
    habitat_scheme = simple_scheme,
    chunk_size = 60L
  )
  expect_equal(prompt$n_chunks, 1L)
})

test_that("n_chunks is correct when list exceeds chunk_size", {
  many_taxa <- paste0("Species ", seq_len(10))
  prompt <- build_habitat_prompt(many_taxa,
    habitat_scheme = simple_scheme,
    chunk_size = 3L
  )
  expect_equal(prompt$n_chunks, 4L) # ceiling(10/3)
})

test_that("prompts list has one element per chunk", {
  many_taxa <- paste0("Species ", seq_len(7))
  prompt <- build_habitat_prompt(many_taxa,
    habitat_scheme = simple_scheme,
    chunk_size = 3L
  )
  expect_equal(length(prompt$prompts), prompt$n_chunks)
})

test_that("chunks list has one element per chunk", {
  many_taxa <- paste0("Species ", seq_len(7))
  prompt <- build_habitat_prompt(many_taxa,
    habitat_scheme = simple_scheme,
    chunk_size = 3L
  )
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
    extra_covariates   = c("Invasive", "Migratory")
  )
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
  expect_equal(
    prompt$habitat_cols,
    c("Rocky Subtidal", "Pelagic Open Water", "Rivers")
  )
})

test_that("habitat_cols has no duplicates", {
  prompt <- build_habitat_prompt(simple_taxa, habitat_scheme = simple_scheme)
  expect_equal(length(prompt$habitat_cols), length(unique(prompt$habitat_cols)))
})

test_that("NULL habitat_scheme gives 3-category default", {
  prompt <- build_habitat_prompt(simple_taxa) # NULL -> Marine/Freshwater/Terrestrial
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
  prompt <- build_habitat_prompt(simple_taxa,
    habitat_scheme = simple_scheme,
    chunk_size = 60L
  )
  for (taxon in simple_taxa) {
    expect_true(grepl(taxon, prompt$prompts[[1]], fixed = TRUE))
  }
})

test_that("taxon names do NOT spill across chunks", {
  many_taxa <- paste0("Species_", seq_len(6))
  prompt <- build_habitat_prompt(many_taxa,
    habitat_scheme = simple_scheme,
    chunk_size = 3L
  )
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
  expect_equal(
    sort(prompt$scheme$l1_name),
    sort(c("Marine", "Freshwater", "Terrestrial"))
  )
})

test_that("scheme stored has padded optional columns", {
  # simple_scheme has no l2_name/l2_code/realm -- these should be padded with NA
  prompt <- build_habitat_prompt(simple_taxa, habitat_scheme = simple_scheme)
  expect_true("l2_name" %in% names(prompt$scheme))
  expect_true("realm" %in% names(prompt$scheme))
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
  prompt <- build_habitat_prompt(simple_taxa,
    habitat_scheme = simple_scheme,
    extra_covariates = c("Invasive")
  )
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

# ---- compound labels (compound_sep) ----------------------------------------

test_that("compound_sep splits a compound label into the parts the model is asked for", {
  scheme <- data.frame(
    l1_name = c("Deepwater", "Coastal-Marine-Estuary-Stream", "Coastal-Stream", "Lake"),
    stringsAsFactors = FALSE
  )
  p <- suppressMessages(build_habitat_prompt("Pimephales promelas", habitat_scheme = scheme, compound_sep = "-"))
  # asked columns: plain labels plus each distinct part, once, in scheme order
  expect_identical(p$habitat_cols, c("Deepwater", "Coastal", "Marine", "Estuary", "Stream", "Lake"))
  # the scheme's own labels are kept for the output
  expect_identical(p$scheme_cols, scheme$l1_name)
  expect_identical(names(p$compounds), c("Coastal-Marine-Estuary-Stream", "Coastal-Stream"))
  expect_identical(p$compounds[["Coastal-Stream"]], c("Coastal", "Stream"))
  txt <- p$prompts[[1]]
  expect_true(grepl("COMPOUND LABELS", txt, fixed = TRUE))
  expect_true(grepl("'Coastal-Stream' = Coastal + Stream", txt, fixed = TRUE))
  expect_true(grepl("Stream  [part of: Coastal-Marine-Estuary-Stream; Coastal-Stream]", txt, fixed = TRUE))
  # the compound never appears as a REQUIRED column
  lines <- strsplit(txt, "\n", fixed = TRUE)[[1]]
  req <- lines[which(grepl("^REQUIRED COLUMNS", lines)) + 1L]
  expect_false(grepl("Coastal-Stream", req, fixed = TRUE))
  expect_true(grepl("Deepwater, Coastal, Marine, Estuary, Stream, Lake, Other_weight", req, fixed = TRUE))
})

test_that("compound_sep = NULL leaves a hyphenated label as one plain column", {
  scheme <- data.frame(l1_name = c("Coastal-Stream", "Lake"), stringsAsFactors = FALSE)
  p <- suppressMessages(build_habitat_prompt("x", habitat_scheme = scheme))
  expect_identical(p$habitat_cols, c("Coastal-Stream", "Lake"))
  expect_identical(p$scheme_cols, p$habitat_cols)
  expect_length(p$compounds, 0L)
  expect_false(grepl("COMPOUND LABELS", p$prompts[[1]], fixed = TRUE))
})

test_that("a label with the separator but a single part stays plain; a part shared with a plain label is asked once", {
  scheme <- data.frame(l1_name = c("Stream", "Coastal-Stream", "Lake-"), stringsAsFactors = FALSE)
  p <- suppressMessages(build_habitat_prompt("x", habitat_scheme = scheme, compound_sep = "-"))
  expect_identical(p$habitat_cols, c("Stream", "Coastal", "Lake-"))
  expect_identical(names(p$compounds), "Coastal-Stream")
})

test_that("compound_sep is validated and refused on a two-level scheme", {
  scheme <- data.frame(l1_name = c("A-B", "C"), stringsAsFactors = FALSE)
  expect_error(build_habitat_prompt("x", habitat_scheme = scheme, compound_sep = ""), "compound_sep")
  expect_error(build_habitat_prompt("x", habitat_scheme = scheme, compound_sep = c("-", "/")), "compound_sep")
  expect_error(
    suppressMessages(build_habitat_prompt("x", habitat_scheme = example_habitat_scheme, compound_sep = "-")),
    "single-level"
  )
})
