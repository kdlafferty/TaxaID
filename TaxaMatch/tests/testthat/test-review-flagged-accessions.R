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
    review_flagged_accessions(dup_df, cache_dir = NULL, llm_fn = stub, verbose = FALSE),
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
  out <- review_flagged_accessions(.base_evaluated_df(), cache_dir = NULL, llm_fn = stub, verbose = FALSE)

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
  out <- review_flagged_accessions(df, cache_dir = NULL, llm_fn = stub, verbose = FALSE)
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
    df, include_non_species_resolved = FALSE, cache_dir = NULL, llm_fn = stub, verbose = FALSE
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
  out <- review_flagged_accessions(.base_evaluated_df(), cache_dir = NULL, llm_fn = stub, verbose = FALSE)
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
    out <- review_flagged_accessions(.base_evaluated_df(), cache_dir = NULL, llm_fn = stub, verbose = FALSE),
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
                                   cache_dir = NULL, llm_fn = stub, verbose = FALSE)
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
                                   cache_dir = NULL, llm_fn = stub, verbose = FALSE)
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
    out <- review_flagged_accessions(.base_evaluated_df(), cache_dir = NULL, llm_fn = stub, verbose = FALSE),
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
  review_flagged_accessions(.base_evaluated_df(), cache_dir = NULL, llm_fn = stub, verbose = FALSE)
  expect_true(grepl("GENUINE MISLABEL", captured_prompt, fixed = TRUE))
  expect_true(grepl("POOR MARKER RESOLVING POWER", captured_prompt, fixed = TRUE))
  expect_true(grepl("SISTER-FAMILY", captured_prompt, fixed = TRUE))
  expect_true(grepl("HYBRID-CROSS", captured_prompt, fixed = TRUE))
  expect_true(grepl("best_disagreeing_taxon=\"Sinipercidae sp.\"", captured_prompt, fixed = TRUE))
  expect_true(grepl("NOT to override hierarchy_flag", captured_prompt, fixed = TRUE))
})

test_that("review_flagged_accessions() adds the local-corroboration line only where the columns are populated (2026-09-03)", {
  df <- .base_evaluated_df()
  df$local_n_independent_conspecific <- c(NA, 1L, NA, NA)
  df$local_best_independent_pident   <- c(NA, 100, NA, NA)
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
  review_flagged_accessions(df, cache_dir = NULL, llm_fn = stub, verbose = FALSE,
                            local_min_overlap = 0.8)
  expect_true(grepl(
    "accession=ACC002:.*local reference set: 1 independent conspecific\\(s\\), best identity 100.0% over >= 80% of the amplicon",
    captured_prompt))
  # ACC003 has no local evidence: no line for it.
  acc3_line <- regmatches(captured_prompt, regexpr("- accession=ACC003:[^\n]*", captured_prompt))
  expect_false(grepl("local reference set", acc3_line, fixed = TRUE))

  # Without a min_overlap the line is worded without a number; with the
  # attribute score_reference_labels() leaves, it is read from there.
  review_flagged_accessions(df, cache_dir = NULL, llm_fn = stub, verbose = FALSE)
  expect_true(grepl("over the required amplicon overlap", captured_prompt, fixed = TRUE))
  attr(df, "local_corroboration_params") <- list(min_overlap = 0.9)
  review_flagged_accessions(df, cache_dir = NULL, llm_fn = stub, verbose = FALSE)
  expect_true(grepl("over >= 90% of the amplicon", captured_prompt, fixed = TRUE))
  expect_error(review_flagged_accessions(df, cache_dir = NULL, llm_fn = stub, verbose = FALSE,
                                         local_min_overlap = 2), "local_min_overlap")
})

test_that("the review fingerprint ignores absent/NA local columns but changes when they are populated", {
  base <- .base_evaluated_df()
  fp0 <- .accession_review_fingerprint(base)
  with_na <- base
  with_na$local_n_independent_conspecific <- NA_integer_
  with_na$local_best_independent_pident   <- NA_real_
  expect_equal(.accession_review_fingerprint(with_na), fp0)
  with_val <- with_na
  with_val$local_n_independent_conspecific[2] <- 1L
  with_val$local_best_independent_pident[2]   <- 100
  fp1 <- .accession_review_fingerprint(with_val)
  expect_equal(fp1[-2], fp0[-2])
  expect_false(fp1[2] == fp0[2])
})

# ------------------------------------------------------------------------------
# Caching (2026-08-14)
# ------------------------------------------------------------------------------

.crfa_stub <- function(prompt, ...) {
  accs <- unique(regmatches(prompt, gregexpr("ACC00[0-9]", prompt))[[1]])
  .canned_json(data.frame(
    accession = accs,
    accession_likely_explanation = "poor_marker_resolution",
    accession_review_confidence = "high",
    accession_review_comment = paste("Fresh review for", accs)
  ))
}

test_that("review_flagged_accessions() writes a fresh review to cache and serves it on a second, unchanged call", {
  cache_dir_path <- withr::local_tempdir()
  call_count <- 0L
  counting_stub <- function(prompt, ...) { call_count <<- call_count + 1L; .crfa_stub(prompt) }

  out1 <- review_flagged_accessions(
    .base_evaluated_df(), cache_dir = cache_dir_path, llm_fn = counting_stub, verbose = FALSE
  )
  expect_true(call_count > 0L)
  expect_true(all(!out1$accession_review_cache_hit[out1$accession %in% c("ACC002","ACC003","ACC004")]))

  first_call_count <- call_count
  out2 <- review_flagged_accessions(
    .base_evaluated_df(), cache_dir = cache_dir_path, llm_fn = counting_stub, verbose = FALSE
  )
  expect_equal(call_count, first_call_count)  # no new LLM calls on the second, identical call
  expect_true(all(out2$accession_review_cache_hit[out2$accession %in% c("ACC002","ACC003","ACC004")]))
  expect_equal(out2$accession_review_comment, out1$accession_review_comment)
})

test_that("review_flagged_accessions() re-reviews an accession whose input changed, but leaves unchanged ones cached", {
  cache_dir_path <- withr::local_tempdir()
  call_log <- list()
  logging_stub <- function(prompt, ...) {
    accs <- unique(regmatches(prompt, gregexpr("ACC00[0-9]", prompt))[[1]])
    call_log[[length(call_log) + 1L]] <<- accs
    .crfa_stub(prompt)
  }

  review_flagged_accessions(
    .base_evaluated_df(), cache_dir = cache_dir_path, llm_fn = logging_stub, verbose = FALSE
  )
  n_calls_first <- length(call_log)

  # ACC002's best_disagreeing_pident changes -- a real evaluate_reference_
  # accessions() re-run finding new evidence -- so it must be re-reviewed;
  # ACC003/ACC004 are untouched and must stay cache hits.
  df2 <- .base_evaluated_df()
  df2$best_disagreeing_pident[df2$accession == "ACC002"] <- 60.0

  out <- review_flagged_accessions(
    df2, cache_dir = cache_dir_path, llm_fn = logging_stub, verbose = FALSE
  )
  reviewed_this_call <- unique(unlist(call_log[(n_calls_first + 1L):length(call_log)]))
  expect_equal(reviewed_this_call, "ACC002")
  expect_false(out$accession_review_cache_hit[out$accession == "ACC002"])
  expect_true(out$accession_review_cache_hit[out$accession == "ACC003"])
  expect_true(out$accession_review_cache_hit[out$accession == "ACC004"])
})

test_that("review_flagged_accessions() writes the cache once per LLM batch, not once for the whole call", {
  cache_dir_path <- withr::local_tempdir()
  save_calls <- 0L
  local_mocked_bindings(
    .save_accession_review_cache = function(cache_dir, cache_df) {
      save_calls <<- save_calls + 1L
      invisible(NULL)
    },
    .package = "TaxaMatch"
  )
  review_flagged_accessions(
    .base_evaluated_df(), taxa_per_call = 1L, cache_dir = cache_dir_path,
    llm_fn = .crfa_stub, verbose = FALSE
  )
  expect_equal(save_calls, 3L)  # ACC002, ACC003, ACC004 -- one batch each
})

test_that("review_flagged_accessions() does not cache a failed/NA review, so it is retried next call", {
  cache_dir_path <- withr::local_tempdir()
  attempt <- 0L
  flaky_stub <- function(prompt, ...) {
    attempt <<- attempt + 1L
    if (attempt == 1L) stop("simulated transient failure")
    .crfa_stub(prompt)
  }

  out1 <- suppressWarnings(review_flagged_accessions(
    .base_evaluated_df(), cache_dir = cache_dir_path, llm_fn = flaky_stub, verbose = FALSE
  ))
  expect_true(all(is.na(out1$accession_review_comment[out1$accession %in% c("ACC002","ACC003","ACC004")])))

  out2 <- review_flagged_accessions(
    .base_evaluated_df(), cache_dir = cache_dir_path, llm_fn = flaky_stub, verbose = FALSE
  )
  expect_true(all(!is.na(out2$accession_review_comment[out2$accession %in% c("ACC002","ACC003","ACC004")])))
})

test_that("review_flagged_accessions() gracefully discards an old-schema review cache instead of erroring", {
  cache_dir_path <- withr::local_tempdir()
  old_schema_cache <- data.frame(
    accession = "ACC002", accession_review_comment = "stale",
    stringsAsFactors = FALSE
  )
  saveRDS(old_schema_cache, file.path(cache_dir_path, "accession_review_cache.rds"))

  expect_warning(
    out <- review_flagged_accessions(
      .base_evaluated_df(), cache_dir = cache_dir_path, llm_fn = .crfa_stub, verbose = FALSE
    ),
    "predates this package version"
  )
  expect_false(out$accession_review_cache_hit[out$accession == "ACC002"])
  expect_equal(out$accession_review_comment[out$accession == "ACC002"], "Fresh review for ACC002")
})

# ---- resolve_review_overrides() ---------------------------------------------

.review_result_fixture <- function() {
  data.frame(
    accession = c("A1", "A2", "A3", "A4", "A5", "A6"),
    accession_likely_explanation = c(
      "genuine_mislabel", "poor_marker_resolution", "sister_family_thin_coverage",
      "hybrid_or_specimen_code_artifact", "uncertain", "poor_marker_resolution"
    ),
    accession_review_confidence = c(
      "high", "high", "moderate", "high", "high", "low"
    ),
    stringsAsFactors = FALSE
  )
}

test_that("resolve_review_overrides() keeps only non-mislabel explanations at sufficient confidence", {
  out <- resolve_review_overrides(.review_result_fixture())
  expect_setequal(out, c("A2", "A3", "A4"))
  expect_false("A1" %in% out)  # genuine_mislabel -- confirms removal, never overrides
})

test_that("resolve_review_overrides() excludes 'uncertain' by default", {
  out <- resolve_review_overrides(.review_result_fixture())
  expect_false("A5" %in% out)
})

test_that("resolve_review_overrides() excludes low-confidence reviews even with a keep-worthy explanation", {
  out <- resolve_review_overrides(.review_result_fixture())
  expect_false("A6" %in% out)  # poor_marker_resolution but confidence = "low"
})

test_that("resolve_review_overrides() can be widened to trust 'uncertain' explicitly", {
  out <- resolve_review_overrides(
    .review_result_fixture(),
    keep_explanations = c("poor_marker_resolution", "sister_family_thin_coverage",
                          "hybrid_or_specimen_code_artifact", "uncertain")
  )
  expect_true("A5" %in% out)
})

test_that("resolve_review_overrides() output feeds directly into remove_incongruent_references()", {
  review <- .review_result_fixture()
  overrides <- resolve_review_overrides(review)
  match_df <- data.frame(
    observation_id = c("O1", "O2", "O3", "O4"),
    accession = c("A1", "A2", "A3", "A4"),
    stringsAsFactors = FALSE
  )
  evaluation <- data.frame(
    accession = c("A1", "A2", "A3", "A4"),
    hierarchy_flag = "incongruent",
    stringsAsFactors = FALSE
  )
  out <- remove_incongruent_references(match_df, evaluation, override_accessions = overrides,
                                      gate = "flag")
  # A1 (genuine_mislabel) removed; A2/A3/A4 (overridden) retained
  expect_equal(out$accession, c("A2", "A3", "A4"))
})

test_that("resolve_review_overrides() rejects 'genuine_mislabel' in keep_explanations", {
  expect_error(
    resolve_review_overrides(.review_result_fixture(),
                             keep_explanations = c("genuine_mislabel", "uncertain")),
    "cannot include"
  )
})

test_that("resolve_review_overrides() validates inputs", {
  expect_error(resolve_review_overrides("not_a_df"), "must be a data frame")
  expect_error(resolve_review_overrides(data.frame(x = 1)), "missing required columns")
  expect_error(resolve_review_overrides(.review_result_fixture(), keep_explanations = character(0)),
              "keep_explanations must be")
  expect_error(resolve_review_overrides(.review_result_fixture(), min_confidence = character(0)),
              "min_confidence must be")
})
