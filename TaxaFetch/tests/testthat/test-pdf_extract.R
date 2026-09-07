# test-pdf_extract.R
# Minimal, targeted coverage for .axis_or_default() and its use in
# .build_axis_instructions() / build_pdf_extract_prompt() /
# parse_pdf_extract_response(), added 2026-08 alongside a real bug fix
# found in human review: screen_pdf_structure() explicitly returns
# NA_character_ (not NULL) for observation_type/location_structure/
# data_density/contamination_risk when its LLM call fails to classify a
# document (confirmed via that function's own fallback object in
# pdf_characterize.R). This package's shared %||% operator (from
# TaxaTools) only substitutes on NULL by design, so defaulting these axis
# fields via %||% silently left NA unresolved instead of falling back to
# a sensible default -- confirmed live against a real bundled PDF in the
# review (every one of these fields came back NA). Not a full test file
# for the whole pdf_extract.R pipeline (the CSV-parsing/DwC-mapping
# machinery is untested here) -- scoped to the specific fix.

library(testthat)

test_that(".axis_or_default() substitutes for both NULL and NA", {
  expect_equal(TaxaFetch:::.axis_or_default(NULL, "fallback"), "fallback")
  expect_equal(TaxaFetch:::.axis_or_default(NA_character_, "fallback"), "fallback")
  expect_equal(TaxaFetch:::.axis_or_default("real_value", "fallback"), "real_value")
})

test_that(".build_axis_instructions() falls back correctly when every axis is NA (real bug)", {
  # Real case from the human review: a bundled PDF whose LLM
  # characterization produced NA for all four axis fields. Before the fix,
  # `%||%` left these NA, and the instruction-building if/else chains
  # (`if (obs == "field_survey")` etc.) would have compared against NA,
  # silently producing no matching branch and empty/incomplete instructions.
  pdf_structure_all_na <- list(
    observation_type   = NA_character_,
    location_structure = NA_character_,
    data_density       = NA_character_,
    contamination_risk = NA_character_
  )
  txt <- TaxaFetch:::.build_axis_instructions(pdf_structure_all_na)
  expect_true(is.character(txt))
  expect_true(nzchar(txt))
  # Defaults are "field_survey"/"named_localities"/"tabular"/"low" --
  # confirm the field_survey branch text is actually present, not skipped.
  expect_match(txt, "Field survey", fixed = TRUE)
})

test_that(".build_axis_instructions() still respects real (non-NA) axis values", {
  pdf_structure_real <- list(
    observation_type   = "museum_collection",
    location_structure = "named_localities",
    data_density       = "tabular",
    contamination_risk = "low"
  )
  txt <- TaxaFetch:::.build_axis_instructions(pdf_structure_real)
  expect_match(txt, "[Mm]useum")
})

test_that("build_pdf_extract_prompt() does not misroute an NA observation_type as skip-worthy", {
  # observation_type = NA should NOT match the analytical_modelling/
  # experimental_lab skip check -- it should fall back to "field_survey"
  # (the .axis_or_default default) and proceed with extraction, not be
  # silently (and separately, since NA %in% c(...) is NA, not TRUE) treated
  # as unskippable-but-uninstructed.
  pdf_structure <- structure(
    list(
      observation_type = NA_character_,
      location_structure = NA_character_,
      data_density = NA_character_,
      contamination_risk = NA_character_,
      single_site_rule = FALSE,
      page_table = data.frame(page = 1L, send_image = TRUE),
      abbreviation_inventory = character(0L),
      pdf_path = "dummy.pdf"
    ),
    class = "pdf_structure"
  )
  result <- build_pdf_extract_prompt(
    pdf_structure = pdf_structure,
    verbose       = FALSE
  )
  expect_false(is.null(result))
  expect_s3_class(result, "pdf_extract_prompt")
})
