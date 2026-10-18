# poor_absolute_fit_col / best_identity_col: one fact line for a poor-fit
# taxon, nothing for a good one, and a changed flag is a cache miss.

.af_json <- function(taxa) {
  rows <- vapply(taxa, function(t) sprintf(
    '{"taxon_name": "%s", "habitat_plausibility": "likely", "geographic_plausibility": "likely", "scope_plausibility": "likely", "contamination_risk": "low", "review_alternatives": null, "review_lower_hypotheses": null, "review_confidence": "high", "review_comment": "ok"}', t
  ), character(1))
  paste0("[", paste(rows, collapse = ","), "]")
}

.af_input <- function(poor = c(TRUE, FALSE), with_cols = TRUE) {
  df <- data.frame(
    observation_id = c("ASV_606", "ASV_1"),
    consensus_taxon = c("Hypsoblennius", "Gobiosoma bosc"),
    consensus_rank = c("genus", "species"),
    consensus_posterior = c(0.998, 0.99),
    stringsAsFactors = FALSE
  )
  if (with_cols) {
    df$best_identity <- c(86.08, 99.4)
    df$poor_absolute_fit <- poor
  }
  df
}

.af_review <- function(df, prompts = NULL, ...) {
  fn <- function(prompt_str, ...) {
    if (!is.null(prompts)) prompts$p <- c(prompts$p, prompt_str)
    .af_json(c("Hypsoblennius", "Gobiosoma bosc"))
  }
  review_assignments(
    data_type = "eDNA", input_df = df, taxon_col = "consensus_taxon",
    context = list(geography = "Mugu Lagoon, California", habitat = "estuary"),
    llm_fn = fn, verbose = FALSE, ...
  )
}

test_that("a poor-fit taxon gets the fact line; a good one does not", {
  pr <- new.env()
  .af_review(.af_input(), pr)
  txt <- paste(pr$p, collapse = "\n")
  expect_equal(lengths(regmatches(txt, gregexpr("is below every rank threshold", txt))), 1L)
  expect_match(txt, "best match identity 86.1% is below every rank threshold for this marker (poor absolute fit)", fixed = TRUE)
  expect_false(grepl("99.4%", txt, fixed = TRUE))
})

test_that("FALSE and NA add nothing", {
  for (v in list(c(FALSE, FALSE), c(NA, NA))) {
    pr <- new.env()
    .af_review(.af_input(poor = v), pr)
    expect_false(grepl("poor absolute fit", paste(pr$p, collapse = "\n"), fixed = TRUE))
  }
})

test_that("the prompt is unchanged when the columns are absent", {
  a <- new.env(); b <- new.env()
  .af_review(.af_input(with_cols = FALSE), a)
  # same input, flags all FALSE: no note either way
  .af_review(.af_input(poor = c(FALSE, FALSE)), b)
  expect_identical(a$p, b$p)
  expect_false(grepl("absolute fit", paste(a$p, collapse = ""), fixed = TRUE))
})

test_that("poor_absolute_fit_col = NULL disables the note", {
  pr <- new.env()
  .af_review(.af_input(), pr, poor_absolute_fit_col = NULL)
  expect_false(grepl("poor absolute fit", paste(pr$p, collapse = "\n"), fixed = TRUE))
})

test_that("the note omits the number when best_identity is absent", {
  pr <- new.env()
  df <- .af_input()
  df$best_identity <- NULL
  .af_review(df, pr)
  expect_match(paste(pr$p, collapse = "\n"), "best match identity is below every rank threshold", fixed = TRUE)
})

test_that("the new column arguments are validated like the others", {
  expect_error(.af_review(.af_input(), poor_absolute_fit_col = c("a", "b")), "single character")
  expect_error(.af_review(.af_input(), best_identity_col = 1), "single character")
})

test_that("a change in poor_absolute_fit is a cache miss", {
  cd <- tempfile("afcache")
  on.exit(unlink(cd, recursive = TRUE), add = TRUE)
  n <- 0L
  fn <- function(prompt_str, ...) {
    n <<- n + 1L
    .af_json(c("Hypsoblennius", "Gobiosoma bosc"))
  }
  run <- function(df) {
    review_assignments(
      data_type = "eDNA", input_df = df, taxon_col = "consensus_taxon",
      context = list(geography = "Mugu Lagoon, California", habitat = "estuary"),
      llm_fn = fn, cache_dir = cd, verbose = FALSE
    )
  }
  run(.af_input())
  expect_equal(n, 1L)
  run(.af_input())
  expect_equal(n, 1L) # identical input: all hits
  run(.af_input(poor = c(FALSE, FALSE))) # Hypsoblennius's note vanished
  expect_equal(n, 2L)
})

test_that("a batch with a poor-fit note gets the name-not-ecology guideline", {
  pr <- new.env()
  .af_review(.af_input(), pr)
  txt <- paste(pr$p, collapse = "\n")
  guide <- sub("TAXA TO REVIEW.*", "", txt)
  expect_match(guide, 'A "(poor absolute fit)" note means the best reference match is weak', fixed = TRUE)
  expect_match(guide, 'must not by itself justify "unlikely" habitat, geography or scope', fixed = TRUE)
})

test_that("a batch without a poor-fit note gets no such guideline", {
  for (v in list(c(FALSE, FALSE), c(NA, NA))) {
    pr <- new.env()
    .af_review(.af_input(poor = v), pr)
    expect_false(grepl("the NAME at the called rank", paste(pr$p, collapse = "\n"), fixed = TRUE))
  }
})

test_that("verdicts cached under the old prompt version are a miss", {
  cd <- tempfile("afv5")
  on.exit(unlink(cd, recursive = TRUE), add = TRUE)
  n <- 0L
  fn <- function(prompt_str, ...) {
    n <<- n + 1L
    .af_json(c("Hypsoblennius", "Gobiosoma bosc"))
  }
  run <- function() {
    review_assignments(
      data_type = "eDNA", input_df = .af_input(), taxon_col = "consensus_taxon",
      context = list(geography = "Mugu Lagoon, California", habitat = "estuary"),
      llm_fn = fn, cache_dir = cd, verbose = FALSE
    )
  }
  run()
  expect_equal(n, 1L)
  # Re-key every cached file as if written under an older version: same verdicts, old key.
  for (f in list.files(cd, full.names = TRUE)) {
    e <- readRDS(f)
    if (is.list(e) && !is.null(e$key)) {
      e$key <- sub("v5", "v4", e$key, fixed = TRUE)
      saveRDS(e, f)
    }
  }
  run()
  expect_equal(n, 2L)
})
