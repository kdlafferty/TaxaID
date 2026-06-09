# ==============================================================================
# test-is_valid_species_name.R
# Tests for is_valid_species_name()
# All tests are fully offline.
# ==============================================================================

# --- Valid binomials -----------------------------------------------------------

test_that("returns TRUE for well-formed binomials", {
  expect_true(is_valid_species_name("Cottus asper"))
  expect_true(is_valid_species_name("Homo sapiens"))
  expect_true(is_valid_species_name("Oncorhynchus mykiss"))
})

test_that("returns FALSE for lowercase genus", {
  expect_false(is_valid_species_name("cottus asper"))
  expect_false(is_valid_species_name("homo sapiens"))
})

test_that("returns FALSE for genus-only string", {
  expect_false(is_valid_species_name("Cottus"))
})

# --- Placeholder patterns -----------------------------------------------------

test_that("returns FALSE for sp. suffix", {
  expect_false(is_valid_species_name("Cottus sp."))
  expect_false(is_valid_species_name("Cottus sp"))
})

test_that("returns FALSE for cf. prefix on epithet", {
  expect_false(is_valid_species_name("Cottus cf. asper"))
})

test_that("returns FALSE for aff. prefix on epithet", {
  expect_false(is_valid_species_name("Cottus aff. asper"))
})

test_that("returns FALSE for uncultured names", {
  expect_false(is_valid_species_name("uncultured bacterium"))
  expect_false(is_valid_species_name("Uncultured Bacteroidetes"))
})

test_that("returns FALSE for environmental names", {
  expect_false(is_valid_species_name("environmental sample"))
  expect_false(is_valid_species_name("Environmental sequence"))
})

test_that("returns FALSE for metagenome names", {
  expect_false(is_valid_species_name("metagenome"))
  expect_false(is_valid_species_name("metagenomics sample"))
})

# --- Vectorized behavior ------------------------------------------------------

test_that("vectorizes correctly over a mixed input", {
  x <- c("Cottus asper", "Cottus sp.", "uncultured bacterium",
         "Homo sapiens", "mus musculus")
  result <- is_valid_species_name(x)
  expect_equal(result, c(TRUE, FALSE, FALSE, TRUE, FALSE))
})

test_that("returns logical vector same length as input", {
  x <- c("Salmo salar", "sp.", "Gadus morhua")
  expect_equal(length(is_valid_species_name(x)), 3L)
  expect_type(is_valid_species_name(x), "logical")
})

# --- Edge cases ---------------------------------------------------------------

test_that("returns FALSE for empty string", {
  expect_false(is_valid_species_name(""))
})

test_that("handles length-1 input correctly", {
  expect_true(is_valid_species_name("Gadus morhua"))
  expect_false(is_valid_species_name("Gadus sp."))
})

test_that("NA input returns FALSE (grepl short-circuits on non-matching NA)", {
  expect_false(is_valid_species_name(NA_character_))
})
