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

test_that("resolve_barcode_lengths returns named 2-element integer vector for known marker", {
  out <- resolve_barcode_lengths("COI")
  expect_length(out, 2L)
  expect_named(out, c("min_bp", "max_bp"))
  expect_equal(unname(out), c(300L, 900L))
})

test_that("resolve_barcode_lengths is case-insensitive", {
  expect_equal(resolve_barcode_lengths("coi"), resolve_barcode_lengths("COI"))
})

test_that("resolve_barcode_lengths handles prefix matching (MiFishU -> mifish)", {
  out <- resolve_barcode_lengths("MiFishU")
  expect_named(out, c("min_bp", "max_bp"))
  expect_equal(unname(out), c(130L, 210L))
})

test_that("resolve_barcode_lengths unions multiple markers", {
  out <- resolve_barcode_lengths(c("12S", "16S"))
  expect_equal(out[["min_bp"]], 100L)
  expect_equal(out[["max_bp"]], 700L)
})

test_that("resolve_barcode_lengths allows user overrides", {
  out <- resolve_barcode_lengths("COI", min_len = 500L)
  expect_equal(out[["min_bp"]], 500L)
  expect_equal(out[["max_bp"]], 900L)
})

test_that("resolve_barcode_lengths short-circuits when both overrides given", {
  out <- resolve_barcode_lengths("UNKNOWN_MARKER", min_len = 100, max_len = 500)
  expect_named(out, c("min_bp", "max_bp"))
  expect_equal(unname(out), c(100L, 500L))
})

test_that("resolve_barcode_lengths errors when min_len > max_len", {
  expect_error(
    resolve_barcode_lengths("COI", min_len = 900, max_len = 300),
    "min_len.*greater than max_len"
  )
})

test_that("resolve_barcode_lengths uses fallback for unknown marker", {
  expect_message(
    out <- resolve_barcode_lengths("TOTALLY_UNKNOWN"),
    "No length defaults"
  )
  expect_named(out, c("min_bp", "max_bp"))
  expect_equal(unname(out), c(100L, 2000L))
})

# ---- is_plausible_binomial --------------------------------------------------

test_that("is_plausible_binomial accepts valid binomials", {
  expect_true(is_plausible_binomial("Cottus asper"))
  expect_true(is_plausible_binomial("Fundulus parvipinnis"))
})

test_that("is_plausible_binomial rejects sp. and cf.", {
  expect_false(is_plausible_binomial("Cottus sp."))
  expect_false(is_plausible_binomial("cf. Cottus asper"))
  expect_false(is_plausible_binomial("Cottus cf. asper"))
})

test_that("is_plausible_binomial rejects aff. and uncultured", {
  expect_false(is_plausible_binomial("Cottus aff. asper"))
  expect_false(is_plausible_binomial("uncultured bacterium"))
  expect_false(is_plausible_binomial("environmental sample"))
})

test_that("is_plausible_binomial rejects single-word names", {
  expect_false(is_plausible_binomial("Cottus"))
  expect_false(is_plausible_binomial("cottus"))
})

test_that("is_plausible_binomial is vectorized", {
  out <- is_plausible_binomial(c("Cottus asper", "Cottus sp.", "Enophrys bison"))
  expect_equal(out, c(TRUE, FALSE, TRUE))
})
