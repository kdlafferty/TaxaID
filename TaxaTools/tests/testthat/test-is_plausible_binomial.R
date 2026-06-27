# ==============================================================================
# test-is_plausible_binomial.R
# Tests for is_plausible_binomial()
# All tests are fully offline.
# ==============================================================================

# --- Valid binomials -----------------------------------------------------------

test_that("returns TRUE for well-formed binomials", {
  expect_true(is_plausible_binomial("Cottus asper"))
  expect_true(is_plausible_binomial("Homo sapiens"))
  expect_true(is_plausible_binomial("Oncorhynchus mykiss"))
})

test_that("returns FALSE for lowercase genus", {
  expect_false(is_plausible_binomial("cottus asper"))
  expect_false(is_plausible_binomial("homo sapiens"))
})

test_that("returns FALSE for genus-only string", {
  expect_false(is_plausible_binomial("Cottus"))
})

# --- Placeholder patterns -----------------------------------------------------

test_that("returns FALSE for sp. suffix", {
  expect_false(is_plausible_binomial("Cottus sp."))
  expect_false(is_plausible_binomial("Cottus sp"))
})

test_that("returns FALSE for cf. prefix on epithet", {
  expect_false(is_plausible_binomial("Cottus cf. asper"))
})

test_that("returns FALSE for aff. prefix on epithet", {
  expect_false(is_plausible_binomial("Cottus aff. asper"))
})

test_that("returns FALSE for uncultured names", {
  expect_false(is_plausible_binomial("uncultured bacterium"))
  expect_false(is_plausible_binomial("Uncultured Bacteroidetes"))
})

test_that("returns FALSE for environmental names", {
  expect_false(is_plausible_binomial("environmental sample"))
  expect_false(is_plausible_binomial("Environmental sequence"))
})

test_that("returns FALSE for metagenome names", {
  expect_false(is_plausible_binomial("metagenome"))
  expect_false(is_plausible_binomial("metagenomics sample"))
})

# --- Vectorized behavior ------------------------------------------------------

test_that("vectorizes correctly over a mixed input", {
  x <- c("Cottus asper", "Cottus sp.", "uncultured bacterium",
         "Homo sapiens", "mus musculus")
  result <- is_plausible_binomial(x)
  expect_equal(result, c(TRUE, FALSE, FALSE, TRUE, FALSE))
})

test_that("returns logical vector same length as input", {
  x <- c("Salmo salar", "sp.", "Gadus morhua")
  expect_equal(length(is_plausible_binomial(x)), 3L)
  expect_type(is_plausible_binomial(x), "logical")
})

# --- Edge cases ---------------------------------------------------------------

test_that("returns FALSE for empty string", {
  expect_false(is_plausible_binomial(""))
})

test_that("handles length-1 input correctly", {
  expect_true(is_plausible_binomial("Gadus morhua"))
  expect_false(is_plausible_binomial("Gadus sp."))
})

test_that("NA input returns FALSE (grepl short-circuits on non-matching NA)", {
  expect_false(is_plausible_binomial(NA_character_))
})
