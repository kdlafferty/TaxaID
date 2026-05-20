# tests/testthat/test-build_habitat_prompt.R

test_that("build_habitat_prompt with geographic_context includes context in prompt", {
  prompt <- build_habitat_prompt(
    taxon_list         = c("Sebastes mystinus", "Gadus morhua"),
    geographic_context = "Southern California"
  )
  expect_true(grepl("GEOGRAPHIC CONTEXT", prompt$prompts[[1]], fixed = TRUE))
  expect_true(grepl("Southern California", prompt$prompts[[1]], fixed = TRUE))
  expect_true(grepl("ecoregion_best_guess", prompt$prompts[[1]], fixed = TRUE))
})

test_that("build_habitat_prompt without geographic_context omits ecoregion column", {
  prompt <- build_habitat_prompt(
    taxon_list = c("Sebastes mystinus", "Gadus morhua")
  )
  expect_false(grepl("GEOGRAPHIC CONTEXT", prompt$prompts[[1]], fixed = TRUE))
  expect_false(grepl("ecoregion_best_guess", prompt$prompts[[1]], fixed = TRUE))
})

test_that("build_habitat_prompt stores geographic_context in object", {
  prompt <- build_habitat_prompt(
    taxon_list         = c("Sebastes mystinus"),
    geographic_context = "Chesapeake Bay"
  )
  expect_equal(prompt$geographic_context, "Chesapeake Bay")
})

test_that("build_habitat_prompt with NULL geographic_context stores NULL", {
  prompt <- build_habitat_prompt(
    taxon_list = c("Sebastes mystinus")
  )
  expect_null(prompt$geographic_context)
})

test_that("build_habitat_prompt rejects invalid geographic_context", {
  expect_error(
    build_habitat_prompt(c("Sp A"), geographic_context = ""),
    "non-empty string"
  )
  expect_error(
    build_habitat_prompt(c("Sp A"), geographic_context = c("a", "b")),
    "non-empty string"
  )
  expect_error(
    build_habitat_prompt(c("Sp A"), geographic_context = NA_character_),
    "non-empty string"
  )
})
