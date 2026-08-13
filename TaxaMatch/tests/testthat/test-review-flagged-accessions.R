# review_flagged_accessions() -- fully offline, llm_fn is always a local stub
# (never calls a real provider). Mirrors TaxaFlag::review_assignments()'s own
# test-review_assignments.R conventions (stub llm_fn returning canned/captured
# JSON), not this package's usual local_mocked_bindings() NCBI-mocking
# convention, since this function makes no network calls of its own at all.

.base_evaluated_df <- function() {
  data.frame(
    accession = c("ACC001", "ACC002", "ACC003", "ACC004"),
    listed_taxon = c("Menidia beryllina", "Stereolepis doederleini",
                     "Serranidae sp. JL-2015", "Cottus asper"),
    hierarchy_flag = c("congruent", "incongruent",
                       "incongruent", "insufficient_independent_evidence"),
    finest_common_rank = c("species", "order", "class", NA_character_),
    best_agreeing_pident = c(99.5, NA_real_, NA_real_, NA_real_),
    best_disagreeing_pident = c(NA_real_, 95.2, 87.3, NA_real_),
    best_disagreeing_taxon = c(NA_character_, "Sinipercidae sp.",
                               "Serranidae sp. JL-2015", NA_character_),
    congruent_evidence_exists_anywhere = c(TRUE, FALSE, FALSE, FALSE),
    congruent_evidence_best_pident = c(99.5, NA_real_, NA_real_, NA_real_),
    taxonomy_resolution_source = c("direct", "direct", "direct", "direct"),
    listed_taxon_is_species = c(TRUE, TRUE, FALSE, TRUE),
    n_independent_top_matches = c(5L, 5L, 1L, 1L),
    n_top_matches_available = c(5L, 5L, 3L, 1L),
    frac_independent_below_min_congruent_rank = c(0.09, 0.9, 0.75, 0.5),
    stringsAsFactors = FALSE
  )
}

.canned_json <- function(rows) {
  jsonlite::toJSON(rows, auto_unbox = TRUE)
}

test_that("review_flagged_accessions() validates required columns", {
  expect_error(review_flagged_accessions(list(a = 1)), "must be a data frame")
  bad_df <- data.frame(accession = "ACC001", stringsAsFactors = FALSE)
  expect_error(review_flagged_accessions(bad_df), "missing required column")
  expect_error(
    review_flagged_accessions(.base_evaluated_df(), hierarchy_flags = character(0)),
    "non-empty character vector"
  )
})

test_that("review_flagged_accessions() warns on duplicate accessions", {
  dup_df <- rbind(.base_evaluated_df(), .base_evaluated_df()[1, ])
  stub <- function(prompt, ...) {
    accs <- unique(regmatches(prompt, gregexpr("ACC00[0-9]", prompt))[[1]])
    .canned_json(data.frame(
      accession = accs, accession_likely_explanation = "uncertain",
      accession_review_confidence = "low", accession_review_comment = "stub"
    ))
  }
  expect_warning(
    review_flagged_accessions(dup_df, llm_fn = stub, verbose = FALSE),
    "duplicate values"
  )
})

test_that("review_flagged_accessions() defaults to the incongruent/insufficient_independent_evidence scope", {
  captured_prompt <- NULL
  stub <- function(prompt, ...) {
    captured_prompt <<- prompt
    .canned_json(data.frame(
      accession = c("ACC002", "ACC003", "ACC004"),
      accession_likely_explanation = c("poor_marker_resolution", "uncertain", "uncertain"),
      accession_review_confidence = c("high", "moderate", "low"),
      accession_review_comment = c("Real diverse disagreement.", "Not species-resolved.", "Thin evidence.")
    ))
  }
  out <- review_flagged_accessions(.base_evaluated_df(), llm_fn = stub, verbose = FALSE)

  # ACC001 is "congruent" and listed_taxon_is_species = TRUE -- out of scope.
  expect_true(is.na(out$accession_review_comment[out$accession == "ACC001"]))
  expect_equal(out$accession_likely_explanation[out$accession == "ACC002"], "poor_marker_resolution")
  expect_equal(out$accession_review_confidence[out$accession == "ACC004"], "low")
  expect_true(grepl("ACC002", captured_prompt, fixed = TRUE))
  expect_false(grepl("ACC001", captured_prompt, fixed = TRUE))
})

test_that("review_flagged_accessions(include_non_species_resolved = TRUE) also reviews a congruent-but-not-species-resolved row", {
  df <- .base_evaluated_df()
  df$hierarchy_flag[3] <- "congruent"  # ACC003 now congruent, but still non-species-resolved
  reviewed_accessions <- NULL
  stub <- function(prompt, ...) {
    reviewed_accessions <<- regmatches(prompt, gregexpr("ACC00[0-9]", prompt))[[1]]
    .canned_json(data.frame(
      accession = unique(reviewed_accessions),
      accession_likely_explanation = "uncertain",
      accession_review_confidence = "low",
      accession_review_comment = "stub"
    ))
  }
  out <- review_flagged_accessions(df, llm_fn = stub, verbose = FALSE)
  expect_true("ACC003" %in% reviewed_accessions)
  expect_false(is.na(out$accession_review_comment[out$accession == "ACC003"]))
})

test_that("review_flagged_accessions(include_non_species_resolved = FALSE) excludes a congruent, non-species-resolved row", {
  df <- .base_evaluated_df()
  df$hierarchy_flag[3] <- "congruent"
  stub <- function(prompt, ...) {
    accs <- unique(regmatches(prompt, gregexpr("ACC00[0-9]", prompt))[[1]])
    .canned_json(data.frame(
      accession = accs, accession_likely_explanation = "uncertain",
      accession_review_confidence = "low", accession_review_comment = "stub"
    ))
  }
  out <- review_flagged_accessions(
    df, include_non_species_resolved = FALSE, llm_fn = stub, verbose = FALSE
  )
  expect_true(is.na(out$accession_review_comment[out$accession == "ACC003"]))
})

test_that("review_flagged_accessions() is a no-op (never calls llm_fn) when nothing is in scope", {
  df <- .base_evaluated_df()
  df$hierarchy_flag <- "congruent"
  df$listed_taxon_is_species <- TRUE
  called <- FALSE
  stub <- function(prompt, ...) { called <<- TRUE; "[]" }
  out <- review_flagged_accessions(df, llm_fn = stub, verbose = FALSE)
  expect_false(called)
  expect_true(all(is.na(out$accession_review_comment)))
  expect_equal(attr(out, "llm_prompts"), list())
})

test_that("review_flagged_accessions() normalises an out-of-enum accession_likely_explanation to 'uncertain'", {
  stub <- function(prompt, ...) .canned_json(data.frame(
    accession = c("ACC002", "ACC003", "ACC004"),
    accession_likely_explanation = c("totally_made_up_category", "uncertain", "uncertain"),
    accession_review_confidence = c("high", "low", "low"),
    accession_review_comment = c("x", "y", "z")
  ))
  out <- review_flagged_accessions(.base_evaluated_df(), llm_fn = stub, verbose = FALSE)
  expect_equal(out$accession_likely_explanation[out$accession == "ACC002"], "uncertain")
})

test_that("review_flagged_accessions() fills a missing accession with NA defaults and warns", {
  stub <- function(prompt, ...) .canned_json(data.frame(
    accession = c("ACC002", "ACC004"),  # ACC003 omitted
    accession_likely_explanation = c("poor_marker_resolution", "uncertain"),
    accession_review_confidence = c("high", "low"),
    accession_review_comment = c("x", "y")
  ))
  expect_warning(
    out <- review_flagged_accessions(.base_evaluated_df(), llm_fn = stub, verbose = FALSE),
    "omitted"
  )
  expect_true(is.na(out$accession_review_comment[out$accession == "ACC003"]))
  expect_equal(out$accession_review_comment[out$accession == "ACC002"], "x")
})

test_that("review_flagged_accessions() batches by taxa_per_call and preserves prompt log", {
  n_calls <- 0L
  stub <- function(prompt, ...) {
    n_calls <<- n_calls + 1L
    accs <- regmatches(prompt, gregexpr("ACC00[0-9]", prompt))[[1]]
    accs <- unique(accs[accs != "ACC001"])  # ACC001 header text sometimes matches nothing, defensive
    .canned_json(data.frame(
      accession = accs,
      accession_likely_explanation = "uncertain",
      accession_review_confidence = "low",
      accession_review_comment = "stub"
    ))
  }
  out <- review_flagged_accessions(.base_evaluated_df(), taxa_per_call = 1L,
                                   llm_fn = stub, verbose = FALSE)
  expect_equal(n_calls, 3L)  # ACC002, ACC003, ACC004 each their own call
  expect_equal(length(attr(out, "llm_prompts")), 3L)
  expect_true(all(!is.na(out$accession_review_comment[out$accession %in% c("ACC002","ACC003","ACC004")])))
})

test_that("review_flagged_accessions() retries a truncated batch as smaller sub-batches", {
  call_log <- character(0)
  stub <- function(prompt, ...) {
    accs <- unique(regmatches(prompt, gregexpr("ACC00[0-9]", prompt))[[1]])
    call_log <<- c(call_log, paste(accs, collapse = ","))
    if (length(accs) > 1L) {
      # Simulate truncation: return valid JSON for only the first accession.
      return(.canned_json(data.frame(
        accession = accs[1],
        accession_likely_explanation = "uncertain",
        accession_review_confidence = "low",
        accession_review_comment = "truncated-stub"
      )))
    }
    .canned_json(data.frame(
      accession = accs,
      accession_likely_explanation = "genuine_mislabel",
      accession_review_confidence = "high",
      accession_review_comment = "sub-batch stub"
    ))
  }
  df <- .base_evaluated_df()  # ACC002, ACC003, ACC004 in scope (3 accessions)
  out <- review_flagged_accessions(df, taxa_per_call = 3L, max_retries = 2L,
                                   llm_fn = stub, verbose = FALSE)
  # Every retry sub-batch above eventually shrinks to a single accession,
  # where the stub always succeeds -- so every in-scope accession ends up
  # reviewed with real (not NA-default) values, and no warning is needed.
  in_scope <- c("ACC002", "ACC003", "ACC004")
  expect_true(all(!is.na(out$accession_review_comment[out$accession %in% in_scope])))
  expect_true(all(out$accession_review_comment[out$accession %in% in_scope] == "sub-batch stub"))
})

test_that("review_flagged_accessions() degrades gracefully (not an error) on a hard llm_fn failure", {
  stub <- function(prompt, ...) stop("simulated network failure")
  expect_warning(
    out <- review_flagged_accessions(.base_evaluated_df(), llm_fn = stub, verbose = FALSE),
    "LLM call failed"
  )
  expect_true(is.na(out$accession_review_comment[out$accession == "ACC002"]))
})

test_that("review_flagged_accessions() prompt includes the guide's 4-category framework", {
  captured_prompt <- NULL
  stub <- function(prompt, ...) {
    captured_prompt <<- prompt
    .canned_json(data.frame(
      accession = c("ACC002", "ACC003", "ACC004"),
      accession_likely_explanation = "uncertain",
      accession_review_confidence = "low",
      accession_review_comment = "stub"
    ))
  }
  review_flagged_accessions(.base_evaluated_df(), llm_fn = stub, verbose = FALSE)
  expect_true(grepl("GENUINE MISLABEL", captured_prompt, fixed = TRUE))
  expect_true(grepl("POOR MARKER RESOLVING POWER", captured_prompt, fixed = TRUE))
  expect_true(grepl("SISTER-FAMILY", captured_prompt, fixed = TRUE))
  expect_true(grepl("HYBRID-CROSS", captured_prompt, fixed = TRUE))
  expect_true(grepl("best_disagreeing_taxon=\"Sinipercidae sp.\"", captured_prompt, fixed = TRUE))
  expect_true(grepl("NOT to override hierarchy_flag", captured_prompt, fixed = TRUE))
})
