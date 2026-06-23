# ---- barcode_length_defaults --------------------------------------------------

test_that("barcode_length_defaults is a named list of 2-element integer vectors", {
  expect_type(barcode_length_defaults, "list")
  expect_true(length(barcode_length_defaults) > 0L)
  for (nm in names(barcode_length_defaults)) {
    v <- barcode_length_defaults[[nm]]
    expect_length(v, 2L)
    expect_true(v[1] < v[2], info = paste0("min < max for '", nm, "'"))
  }
})

test_that("barcode_length_defaults has expected markers", {
  expect_true(all(c("coi", "12s", "its2") %in% names(barcode_length_defaults)))
})

# ---- resolve_barcode_lengths -------------------------------------------------

test_that("resolve_barcode_lengths returns 2-element numeric for known marker", {
  out <- resolve_barcode_lengths("COI")
  expect_length(out, 2L)
  expect_equal(out, c(300L, 900L))
})

test_that("resolve_barcode_lengths is case-insensitive", {
  expect_equal(resolve_barcode_lengths("coi"), resolve_barcode_lengths("COI"))
})

test_that("resolve_barcode_lengths handles prefix matching (MiFishU -> mifish)", {
  out <- resolve_barcode_lengths("MiFishU")
  expect_equal(out, c(130L, 210L))
})

test_that("resolve_barcode_lengths unions multiple markers", {
  out <- resolve_barcode_lengths(c("12S", "16S"))
  expect_equal(out[1], 100L)  # min of both
  expect_equal(out[2], 700L)  # max of both
})

test_that("resolve_barcode_lengths allows user overrides", {
  out <- resolve_barcode_lengths("COI", min_len = 500L)
  expect_equal(out[1], 500L)
  expect_equal(out[2], 900L)
})

test_that("resolve_barcode_lengths short-circuits when both overrides given", {
  out <- resolve_barcode_lengths("UNKNOWN_MARKER", min_len = 100, max_len = 500)
  expect_equal(out, c(100L, 500L))
})

test_that("resolve_barcode_lengths uses fallback for unknown marker", {
  expect_message(
    out <- resolve_barcode_lengths("TOTALLY_UNKNOWN"),
    "No length defaults"
  )
  expect_equal(out, c(100L, 2000L))
})

# ---- is_valid_species_name --------------------------------------------------

test_that("is_valid_species_name accepts valid binomials", {
  expect_true(is_valid_species_name("Cottus asper"))
  expect_true(is_valid_species_name("Fundulus parvipinnis"))
})

test_that("is_valid_species_name rejects sp. and cf.", {
  expect_false(is_valid_species_name("Cottus sp."))
  expect_false(is_valid_species_name("cf. Cottus asper"))
  expect_false(is_valid_species_name("Cottus cf. asper"))
})

test_that("is_valid_species_name rejects aff. and uncultured", {
  expect_false(is_valid_species_name("Cottus aff. asper"))
  expect_false(is_valid_species_name("uncultured bacterium"))
  expect_false(is_valid_species_name("environmental sample"))
})

test_that("is_valid_species_name rejects single-word names", {
  expect_false(is_valid_species_name("Cottus"))
  expect_false(is_valid_species_name("cottus"))
})

test_that("is_valid_species_name is vectorized", {
  out <- is_valid_species_name(c("Cottus asper", "Cottus sp.", "Enophrys bison"))
  expect_equal(out, c(TRUE, FALSE, TRUE))
})
