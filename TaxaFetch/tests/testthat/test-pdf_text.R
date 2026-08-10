# test-pdf_text.R
# Minimal, targeted coverage for .match_header()'s Pass 2 (all-caps header
# embedded in a longer two-column-layout line), added 2026-08 alongside a
# real bug fix found in human review: a NUMBERED two-column header
# (e.g. "2.1 RESULTS ... [right-column prose]") never matched Pass 2's
# "^[A-Z]" anchor since the line started with a digit, so Pass 1's leading-
# section-number strip was applied to Pass 2 too. Not a full test file for
# the whole pdf_text.R pipeline (extract_pdf_text() itself needs a real or
# realistic bundled PDF and is not covered here) -- scoped to the specific
# fix.

library(testthat)

test_that(".match_header() Pass 1 matches a plain single-column header", {
  expect_equal(
    TaxaFetch:::.match_header("METHODS", TaxaFetch:::.section_patterns),
    "methods"
  )
  expect_equal(
    TaxaFetch:::.match_header("2. Methods", TaxaFetch:::.section_patterns),
    "methods"
  )
})

test_that(".match_header() Pass 2 matches an unnumbered two-column header", {
  line <- "METHODS Sampling occurred at three sites along the coast during spring"
  expect_equal(
    TaxaFetch:::.match_header(line, TaxaFetch:::.section_patterns),
    "methods"
  )
})

test_that(".match_header() Pass 2 matches a NUMBERED two-column header (real bug)", {
  # Real bug (2026-08 human review): before the fix, this line never matched
  # because Pass 2's regex requires the line to START with an uppercase
  # letter, and a numbered header instead starts with a digit ("2.1 ").
  line <- "2.1 RESULTS Several species were observed near the study transect during"
  expect_equal(
    TaxaFetch:::.match_header(line, TaxaFetch:::.section_patterns),
    "results"
  )
})

test_that(".match_header() Pass 2 handles a roman-numeral-numbered two-column header", {
  line <- "II. DISCUSSION The observed pattern is consistent with prior surveys of"
  expect_equal(
    TaxaFetch:::.match_header(line, TaxaFetch:::.section_patterns),
    "discussion"
  )
})

test_that(".match_header() returns NA for ordinary prose", {
  expect_true(is.na(TaxaFetch:::.match_header(
    "The specimens were collected over three field seasons in the study area.",
    TaxaFetch:::.section_patterns
  )))
})
