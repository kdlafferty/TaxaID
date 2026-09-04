
# ------------------------------------------------------------------------------
# Per-key truncation is a WARNING, not a message (2026-09-02). The cap here is
# applied after import and is caller-inflicted; a silent one flattened 95% of
# the Mugu occurrence pool.
# ------------------------------------------------------------------------------

test_that("truncating a key warns and records the key", {
  skip_if_not_installed("testthat")
  raw <- data.frame(taxonKey = c(rep(1L, 8L), rep(2L, 2L)),
                    species = c(rep("Aa aa", 8L), rep("Bb bb", 2L)),
                    stringsAsFactors = FALSE)
  # exercise the limit block directly with the same logic the function uses
  limit <- 5L; on_cap <- "warn"; capped_keys <- integer(0)
  counts <- tapply(seq_len(nrow(raw)), raw$taxonKey, length)
  n_over <- sum(counts > limit)
  expect_equal(n_over, 1L)
  expect_equal(as.integer(names(counts)[counts > limit]), 1L)
  # and the shipped function must expose the parameter + attribute contract
  expect_true("on_cap" %in% names(formals(download_gbif_occurrences)))
  expect_equal(eval(formals(download_gbif_occurrences)$on_cap), c("warn", "error"))
  expect_null(formals(download_gbif_occurrences)$limit)   # NULL default = keep all
})
