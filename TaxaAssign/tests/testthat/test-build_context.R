# tests/testthat/test-build_context.R

skip_if_not_installed("TaxaHabitat")
skip_if_not_installed("TaxaTools")

# Stub LLM that returns habitat CSV for habitat prompts and a two-line
# synthesis response for the synthesis prompt.
stub_habitat_llm <- function(prompt) {
  # Detect synthesis prompt (contains "Habitat proportions across the assemblage")
  if (grepl("Habitat proportions across the assemblage", prompt, fixed = TRUE)) {
    return("main_habitat: rocky reef / kelp forest\necoregion: Southern California Bight")
  }
  has_eco <- grepl("ecoregion_best_guess", prompt, fixed = TRUE)
  if (has_eco) {
    paste0(
      "taxon_name,Marine,Freshwater,Terrestrial,Other_weight,",
      "habitat_best_guess,ecoregion_best_guess\n",
      "Sebastes mystinus,1.00,0.00,0.00,0.00,,Southern California Bight\n",
      "Gadus morhua,1.00,0.00,0.00,0.00,,Southern California Bight\n",
      "Oncorhynchus mykiss,0.50,0.50,0.00,0.00,,Southern California Bight"
    )
  } else {
    paste0(
      "taxon_name,Marine,Freshwater,Terrestrial,Other_weight,habitat_best_guess\n",
      "Sebastes mystinus,1.00,0.00,0.00,0.00,\n",
      "Gadus morhua,1.00,0.00,0.00,0.00,\n",
      "Oncorhynchus mykiss,0.50,0.50,0.00,0.00,"
    )
  }
}

test_that("build_context returns a valid ctx data frame with synthesis", {
  ctx <- build_context(
    taxon_names     = c("Sebastes mystinus", "Gadus morhua", "Oncorhynchus mykiss"),
    geographic_hint = "Southern California",
    date            = "2025",
    llm_fn          = stub_habitat_llm
  )
  expect_s3_class(ctx, "data.frame")
  expect_equal(nrow(ctx), 1L)
  expect_true("main_habitat" %in% names(ctx))
  expect_true("ecoregion" %in% names(ctx))
  expect_true("date" %in% names(ctx))
  # Synthesis overrides the mechanical argmax
  expect_equal(ctx$main_habitat, "rocky reef / kelp forest")
  expect_equal(ctx$ecoregion, "Southern California Bight")
  expect_equal(ctx$date, "2025")
})

test_that("build_context passes date through", {
  ctx <- build_context(
    taxon_names = c("Sebastes mystinus"),
    date        = "2019",
    llm_fn      = stub_habitat_llm
  )
  expect_equal(ctx$date, "2019")
})

test_that("build_context with NULL date returns NA date", {
  ctx <- build_context(
    taxon_names = c("Sebastes mystinus"),
    llm_fn      = stub_habitat_llm
  )
  expect_true(is.na(ctx$date))
})

test_that("build_context without geographic_hint still synthesises habitat", {
  ctx <- build_context(
    taxon_names = c("Sebastes mystinus", "Gadus morhua"),
    llm_fn      = stub_habitat_llm
  )
  # Synthesis prompt is still sent; ecoregion comes from synthesis
  expect_equal(ctx$main_habitat, "rocky reef / kelp forest")
})

test_that("build_context attaches habitats_df and proportions attributes", {
  ctx <- build_context(
    taxon_names     = c("Sebastes mystinus", "Gadus morhua"),
    geographic_hint = "Southern California",
    llm_fn          = stub_habitat_llm
  )
  hab <- attr(ctx, "habitats_df")
  expect_s3_class(hab, "data.frame")
  expect_true("taxon_name" %in% names(hab))
  expect_true(nrow(hab) >= 2L)

  props <- attr(ctx, "habitat_proportions")
  expect_true(!is.null(props))
  expect_true(is.numeric(props))
})

test_that("build_context falls back to consensus when synthesis fails", {
  bad_synth_llm <- function(prompt) {
    if (grepl("Habitat proportions across the assemblage", prompt, fixed = TRUE)) {
      return("Sorry, I cannot help with that.")
    }
    stub_habitat_llm(prompt)
  }
  ctx <- build_context(
    taxon_names     = c("Sebastes mystinus", "Gadus morhua"),
    geographic_hint = "Southern California",
    llm_fn          = bad_synth_llm
  )
  # Falls back to mechanical consensus
  expect_equal(ctx$main_habitat, "Marine")
  expect_equal(ctx$ecoregion, "Southern California Bight")
})
