test_that(".normalize_scores: 0-100 scale auto-detected", {
  out <- TaxaLikely:::.normalize_scores(c(50, 75, 100))
  expect_true(all(out > 0 & out < 1))
  expect_equal(out[3], 1 - 1e-6)        # 100 → clipped to 1 - epsilon
  expect_true(out[2] > out[1])           # monotone
})

test_that(".normalize_scores: 0-1 scale auto-detected", {
  out <- TaxaLikely:::.normalize_scores(c(0, 0.5, 1))
  expect_true(all(out > 0 & out < 1))
  expect_equal(out[1], 1e-6)            # 0 → clipped to epsilon
  expect_equal(out[3], 1 - 1e-6)        # 1 → clipped to 1 - epsilon
})

test_that(".normalize_scores: explicit bounds override auto-detection", {
  out <- TaxaLikely:::.normalize_scores(c(200, 400, 600), bounds = c(0, 1000))
  expect_equal(out, c(200, 400, 600) / 1000, tolerance = 1e-9)
})

test_that(".normalize_scores: NA values pass through unchanged", {
  out <- TaxaLikely:::.normalize_scores(c(50, NA, 100))
  expect_true(is.na(out[2]))
  expect_false(any(is.na(out[-2])))
})

test_that(".normalize_scores: all-NA input returns input unchanged", {
  x <- c(NA_real_, NA_real_)
  expect_equal(TaxaLikely:::.normalize_scores(x), x)
})

test_that(".normalize_scores: flatline input (all same value) returns consistent output", {
  # c(80, 80, 80) is on 0-100 scale -> normalises to 0.8, not 1-epsilon
  # flatline check only triggers when explicit bounds are c(x, x)
  out <- TaxaLikely:::.normalize_scores(c(80, 80, 80))
  expect_true(all(out > 0 & out < 1))    # still in valid range
  expect_equal(length(unique(out)), 1L)  # all identical
})

test_that(".normalize_scores: explicit identical bounds returns 1 - epsilon", {
  # When theoretical range collapses (e.g. bounds = c(5, 5)), use fallback
  out <- TaxaLikely:::.normalize_scores(c(5, 5, 5), bounds = c(5, 5))
  expect_true(all(out == 1 - 1e-6))
})

test_that(".normalize_scores: output always in (epsilon, 1 - epsilon)", {
  set.seed(42)
  x <- runif(200, 0, 100)
  out <- TaxaLikely:::.normalize_scores(x)
  expect_true(all(out > 1e-6 & out < 1 - 1e-6))
})

test_that(".normalize_scores: non-numeric input errors", {
  expect_error(TaxaLikely:::.normalize_scores(c("a", "b")), "numeric")
})

test_that(".normalize_scores: invalid bounds errors", {
  expect_error(TaxaLikely:::.normalize_scores(c(1, 2), bounds = c(0, 1, 2)), "length-2")
})
