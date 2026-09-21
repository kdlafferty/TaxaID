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
