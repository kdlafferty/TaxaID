# tests/testthat/test-assign_taxa_llm_prompt_example.R
#
# The prompt's "Required output format" example must be placeholders all the
# way down -- names AND values. Naming the batch's own first two candidates
# there handed the model ready-made answers for taxa it was being asked to
# judge, and an answer that merely echoed the example could not be told from a
# judgement. Placeholder names alone would still leave the invented 0.90 / 0.05
# for a model to settle on as a pattern.

# The function's own default, not a copy of it: the prompt interpolates
# prior_weight_guide$transported, so a wrong guide would silently give an
# empty prompt.
pwg <- eval(formals(assign_taxa_llm)$prior_weight_guide)

ctx <- list(main_habitat = "estuarine", ecoregion = "Great Lakes")

batch <- function(n) {
  taxa <- c(
    "Eucyclogobius newberryi", "Quietula y-cauda",
    "Gillichthys mirabilis", "Salmo salar"
  )
  # hypothesis_type is not optional: .build_taxa_prompt() reads it with
  # ifelse(), so a taxa_df without it makes taxa_lines character(0) and the
  # whole taxa list vanishes from the prompt.
  data.frame(
    taxon_name = taxa[seq_len(n)],
    taxon_name_rank = rep("species", n),
    hypothesis_type = rep("specific_candidate", n),
    stringsAsFactors = FALSE
  )
}

# The example block alone: everything between the format heading and the taxa
# list. The surrounding rules legitimately name the vocabulary and the weight
# ranges, so absence has to be asserted here, not over the whole prompt.
example_block <- function(prompt) {
  after <- strsplit(prompt, "is a placeholder; fill it in.", fixed = TRUE)[[1]][[2]]
  strsplit(after, "Taxa to assess:", fixed = TRUE)[[1]][[1]]
}

# Everything before "Taxa to assess:" is instruction, including the example;
# the batch's names belong only after it.
instructions <- function(prompt) {
  strsplit(prompt, "Taxa to assess:", fixed = TRUE)[[1]][[1]]
}

test_that("the format example names no taxon from a multi-taxon batch", {
  taxa_df <- batch(3)
  prompt <- .build_taxa_prompt(taxa_df, ctx, prior_weight_guide = pwg)
  expect_true(nzchar(prompt))

  head_part <- instructions(prompt)
  found <- vapply(
    taxa_df$taxon_name,
    function(nm) grepl(nm, head_part, fixed = TRUE),
    logical(1)
  )
  expect_equal(found, stats::setNames(rep(FALSE, nrow(taxa_df)), taxa_df$taxon_name))

  # The taxa are still asked about, after the instructions.
  for (nm in taxa_df$taxon_name) {
    expect_match(prompt, nm, fixed = TRUE)
  }
})

test_that("the format example names no taxon from a single-taxon batch", {
  taxa_df <- batch(1)
  prompt <- .build_taxa_prompt(taxa_df, ctx, prior_weight_guide = pwg)
  expect_false(grepl(taxa_df$taxon_name[[1]], instructions(prompt), fixed = TRUE))
  expect_match(prompt, taxa_df$taxon_name[[1]], fixed = TRUE)
})

test_that("every value in the example is a placeholder", {
  prompt <- .build_taxa_prompt(batch(3), ctx, prior_weight_guide = pwg)
  ex <- example_block(prompt)
  expect_match(ex, '"taxon_name": "<name exactly as listed>"', fixed = TRUE)
  expect_match(ex, '"prior_weight": <number>', fixed = TRUE)
  for (field in c("range_status", "habitat_fit", "information_quality")) {
    expect_match(ex, paste0('"', field, '": "<'), fixed = TRUE)
  }
  # No invented answer survives in the example: a model can anchor on 0.90 /
  # 0.05 as a pattern with no name echoed at all.
  expect_false(grepl("[0-9]", ex))
  expect_false(grepl("native|expected|unlikely|moderate|high", ex))
})

test_that("the heading says the angle brackets are placeholders", {
  prompt <- .build_taxa_prompt(batch(3), ctx, prior_weight_guide = pwg)
  expect_match(prompt, "placeholder", fixed = TRUE)
  expect_match(prompt, "for no others", fixed = TRUE)
})

test_that("only a multi-taxon batch is shown the ... continuation", {
  one <- example_block(.build_taxa_prompt(batch(1), ctx, prior_weight_guide = pwg))
  many <- example_block(.build_taxa_prompt(batch(3), ctx, prior_weight_guide = pwg))
  expect_false(grepl("...", one, fixed = TRUE))
  expect_match(many, "...", fixed = TRUE)
})
