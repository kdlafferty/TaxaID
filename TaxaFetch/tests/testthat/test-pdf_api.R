# test-pdf_api.R
# Tests for pdf_api.R's internal page-rendering helper.
#
# .render_pdf_pages() promises a NAMED list of base64 PNG strings, "named by
# page number". A page that fails to render must not disturb the names of the
# pages that succeeded -- see the regression test below for the real failure
# mode this file was added for.

library(testthat)

skip_if_not_installed("pdftools")
skip_if_not_installed("png")
skip_if_not_installed("base64enc")

# The mock must be SELF-CONTAINED (no closure over this file's environment):
# .render_pdf_pages() hands it to callr::r() to run in a fresh R session
# whenever callr is installed.
.fake_render <- function(pdf_path, pg, dpi) {
  if (pg == 20L) stop("simulated poppler failure")
  paste0("b64_page_", pg)
}

test_that(".render_pdf_pages: names track page numbers when every page renders", {
  testthat::local_mocked_bindings(
    .render_one_page_b64 = .fake_render, .package = "TaxaFetch"
  )
  out <- TaxaFetch:::.render_pdf_pages("dummy.pdf", c(10L, 30L), dpi = 72L)
  expect_named(out, c("10", "30"))
  expect_equal(unname(unlist(out)), c("b64_page_10", "b64_page_30"))
})

test_that(".render_pdf_pages: a failed page drops out without shifting the other pages' names", {
  # Regression: `results[[i]] <- b64` DELETES the element when b64 is NULL
  # (the failure path), shrinking the list so every later page was written to
  # -- and returned under -- the wrong page's name, with the last one named "".
  testthat::local_mocked_bindings(
    .render_one_page_b64 = .fake_render, .package = "TaxaFetch"
  )
  expect_warning(
    out <- TaxaFetch:::.render_pdf_pages("dummy.pdf", c(10L, 20L, 30L), dpi = 72L),
    "page 20"
  )
  expect_named(out, c("10", "30"))
  expect_equal(out[["10"]], "b64_page_10")
  expect_equal(out[["30"]], "b64_page_30")
})
