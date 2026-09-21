# Invariants of the registry's Rd parsing. Offline: reads the installed TaxaID
# packages, exactly as workflow_registry() does. An argument doc must never
# bleed into its neighbour, a multi-name \item must give every name the same
# doc, and no description or value may be cut mid-word: a truncated field ends
# in " ...".

testthat::test_that("apply_undetected_evidence: no argument doc is empty or bled into its neighbor", {
  testthat::skip_if_not_installed("TaxaExpect")
  reg <- workflow_registry(packages = "TaxaExpect", refresh = TRUE)
  fn <- Filter(function(f) f$name == "apply_undetected_evidence", reg$TaxaExpect$functions)[[1]]
  doc_by_name <- stats::setNames(
    vapply(fn$params, function(p) p$doc %||% "", ""),
    vapply(fn$params, `[[`, "", "name")
  )

  # Every formal apply_undetected_evidence's Rd page documents has real text.
  documented <- c(
    "taxaexpect_priors", "model_obj", "evidence", "grid_id", "main_habitat",
    "taxonomy", "pricing", "sampling_group", "group_fallback",
    "min_group_n_eff", "min_group_f1"
  )
  testthat::expect_true(all(documented %in% names(doc_by_name)))
  for (nm in documented) {
    testthat::expect_true(nzchar(doc_by_name[[nm]]), info = nm)
  }

  # The old text-parser bug: `grid_id`'s and `pricing`'s docs went missing
  # and their text was appended onto `evidence`'s and `taxonomy`'s docs
  # instead (each item's boundary was guessed from blank-line layout).
  testthat::expect_false(grepl("grid_id:", doc_by_name[["evidence"]], fixed = TRUE))
  testthat::expect_false(grepl("pricing:", doc_by_name[["taxonomy"]], fixed = TRUE))
})

testthat::test_that("calibrate_kernel_bandwidth: m_grid/occurrence_data/site_habitat are non-empty", {
  testthat::skip_if_not_installed("TaxaExpect")
  reg <- workflow_registry(packages = "TaxaExpect", refresh = TRUE)
  fn <- Filter(function(f) f$name == "calibrate_kernel_bandwidth", reg$TaxaExpect$functions)[[1]]
  doc_by_name <- stats::setNames(
    vapply(fn$params, function(p) p$doc %||% "", ""),
    vapply(fn$params, `[[`, "", "name")
  )
  for (nm in c("m_grid", "occurrence_data", "site_habitat")) {
    testthat::expect_true(nzchar(doc_by_name[[nm]]), info = nm)
  }
  # The old parser's bug for this function: m_grid's text sat inside
  # lambda_grid's doc instead of its own.
  testthat::expect_false(grepl("m_grid:", doc_by_name[["lambda_grid"]], fixed = TRUE))
})

testthat::test_that("a multi-name \\item (e.g. \\item{a, b}{...}) gives every name the SAME doc", {
  # calibrate_kernel_bandwidth.Rd has
  # \item{occurrence_data, site_habitat, taxon_col, lat_col, lon_col, habitat_col}{...}
  # (found via grep '\\item\\{[^}]*,' over Taxa*/man/*.Rd) -- a real,
  # committed multi-name item, not a synthetic fixture.
  testthat::skip_if_not_installed("TaxaExpect")
  reg <- workflow_registry(packages = "TaxaExpect", refresh = TRUE)
  fn <- Filter(function(f) f$name == "calibrate_kernel_bandwidth", reg$TaxaExpect$functions)[[1]]
  doc_by_name <- stats::setNames(
    vapply(fn$params, function(p) p$doc %||% "", ""),
    vapply(fn$params, `[[`, "", "name")
  )
  testthat::expect_true(nzchar(doc_by_name[["occurrence_data"]]))
  testthat::expect_identical(doc_by_name[["occurrence_data"]], doc_by_name[["site_habitat"]])
  testthat::expect_identical(doc_by_name[["occurrence_data"]], doc_by_name[["taxon_col"]])
})

testthat::test_that("no registry description/value is truncated mid-word (word-boundary + ' ...' contract)", {
  for (p in TAXAID_PACKAGES) testthat::skip_if_not_installed(p)
  reg <- workflow_registry(refresh = TRUE)
  offenders <- character()
  for (pkg in reg) {
    for (fn in pkg$functions) {
      for (field in c("description", "value")) {
        txt <- fn[[field]]
        if (is.null(txt) || !nzchar(txt)) next
        max_chars <- if (field == "description") 600L else 400L
        # Anything at/over the cap must have been truncated, and every
        # truncation appends " ..." -- so a long field with no trailing
        # " ..." means it was hard-cut (possibly mid-word) without the
        # marker: the mid-word cut this guards against ("...can be combined safely wit").
        if (nchar(txt) >= max_chars && !grepl(" \\.\\.\\.$", txt)) {
          offenders <- c(offenders, paste0(pkg$package, "::", fn$name, "$", field))
        }
      }
    }
  }
  testthat::expect_length(offenders, 0)
})

testthat::test_that(".truncate_at_word(): word-boundary cut, n-char cap, and the documented mid-word fallback", {
  # The registry-level test above only asserts the trailing " ..." marker,
  # which a hard cut at n - 4 with the marker appended would also satisfy --
  # it does not by itself prove the cut landed on a word boundary. These
  # cases exercise .truncate_at_word() directly against synthetic strings.

  x <- "The quick brown fox jumps over the lazy dog"

  # Cut lands exactly on a space in the source (head ends in whitespace).
  r1 <- TaxaWizard:::.truncate_at_word(x, 20L)
  testthat::expect_true(endsWith(r1, " ..."))
  body1 <- sub(" \\.\\.\\.$", "", r1)
  testthat::expect_identical(substr(x, 1L, nchar(body1)), body1)
  testthat::expect_identical(substr(x, nchar(body1) + 1L, nchar(body1) + 1L), " ")
  testthat::expect_true(nchar(r1) <= 20L)

  # Cut lands mid-word (n - 4 falls inside "brown") and must walk back to
  # the previous space -- the case a bare " ..." check cannot distinguish
  # from a hard cut.
  r2 <- TaxaWizard:::.truncate_at_word(x, 18L)
  testthat::expect_true(endsWith(r2, " ..."))
  body2 <- sub(" \\.\\.\\.$", "", r2)
  testthat::expect_identical(substr(x, 1L, nchar(body2)), body2)
  testthat::expect_identical(substr(x, nchar(body2) + 1L, nchar(body2) + 1L), " ")
  testthat::expect_true(nchar(r2) <= 18L)

  # An input shorter than n comes back unchanged.
  short_x <- "short text"
  testthat::expect_identical(TaxaWizard:::.truncate_at_word(short_x, 50L), short_x)

  # An input of exactly n characters is still "at the cap" per the function's
  # own contract comment ("length >= n always carries the marker") and gets
  # truncated, not returned as-is.
  exact_x <- strrep("a", 10L)
  r_exact <- TaxaWizard:::.truncate_at_word(exact_x, 10L)
  testthat::expect_true(endsWith(r_exact, " ..."))
  testthat::expect_true(nchar(r_exact) <= 10L)

  # First token longer than n - 4: no whitespace anywhere in the truncated
  # head, so no word-boundary cut is possible. Documented behaviour is a
  # hard cut at n - 4 with the marker still appended -- assert that exact
  # fallback rather than a word-boundary property it cannot have.
  long_word_x <- "Supercalifragilisticexpialidocious is a word"
  head6 <- substr(long_word_x, 1L, 6L)
  testthat::expect_false(grepl("\\s", head6)) # confirms the fixture actually hits this branch
  r_word <- TaxaWizard:::.truncate_at_word(long_word_x, 10L)
  testthat::expect_identical(r_word, paste0(head6, " ..."))
  testthat::expect_true(nchar(r_word) <= 10L)
})
