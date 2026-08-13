# ==============================================================================
# review_flagged_accessions() -- LLM second-look reviewer for
# evaluate_reference_accessions()'s flagged/borderline output.
#
# Implements Question 2 of
# ecosystem_docs/REENTRY_PROMPT_flagged_accession_second_look.md. See that
# doc's own "Real design questions to resolve before writing code" for the
# design answers this implementation follows (what the LLM sees, what it
# outputs, cost/scale scoping, package placement) -- summarized in this
# function's own roxygen below rather than re-derived here.
# ==============================================================================

#' LLM Second-Look Review of Flagged Reference Accessions
#'
#' Sends `evaluate_reference_accessions()`'s flagged/borderline rows to an LLM
#' for a free-text second look -- the same "narrative-judgment layer added ON
#' TOP of statistical flags, never replacing them, never auto-acting" pattern
#' `TaxaFlag::review_assignments()` already established for posterior
#' taxonomic assignments (implements Question 2 of
#' `ecosystem_docs/REENTRY_PROMPT_flagged_accession_second_look.md`). The LLM
#' never re-decides `hierarchy_flag` -- it adds what the statistical check
#' structurally cannot: recognizing a known hybrid-cross name (e.g.
#' `"Ctenopharyngodon idella x Megalobrama amblycephala"`, a known Chinese
#' aquaculture hybrid), an informal specimen code (e.g. `"Serranidae sp.
#' JL-2015"`), or a taxonomic-literature fact (a recent species split or
#' synonymy) that would explain an apparent disagreement.
#'
#' @section Prompt content, lifted from the evaluation guide, not re-derived:
#' The prompt teaches the LLM `inst/reference_accession_evaluation_guide.md`'s
#' own 5-category decision framework (genuine mislabel / poor marker
#' resolving power / sister-family-thin-coverage artifact / hybrid-cross or
#' specimen-code artifact / non-species-resolved partner) using that guide's
#' own worked real examples (`Stereolepis doederleini`, `Abylopsis
#' eschscholtzii`, `NC_028197`/`"Serranidae sp. JL-2015"`) -- the same
#' reasoning a careful human reviewer already applies by hand. Keep the guide
#' updated (and this function's prompt in sync with it) if real usage
#' surfaces a case class the guide doesn't yet cover.
#'
#' @section What the LLM outputs -- and does NOT output:
#' A free-text `accession_review_comment` plus two small structured fields
#' (`accession_likely_explanation`, `accession_review_confidence`) -- never a
#' re-decided `hierarchy_flag`, and this function never calls
#' [remove_incongruent_references()] or otherwise mutates the evaluation
#' itself. This mirrors this ecosystem's own `trusted_rank` cautionary
#' history (`TaxaLikely::evaluate_likelihoods()`, built 2026-07-19, removed
#' 2026-07-20 after a real ~30% mismatch between the hypothesis it was
#' computed for and the one that actually won downstream -- see
#' `[[project_rank_trust_mechanism_removed]]` in the project memory system):
#' a mechanism that recomputes/overrides an existing categorical verdict is
#' exactly the shape that broke there. A human reads
#' `accession_review_comment` before acting on it.
#'
#' @section Package placement:
#' Lives in TaxaMatch, not TaxaFlag, deliberately. Every other reference-
#' accession-quality function ([evaluate_reference_accessions()],
#' [investigate_flagged_accession()], `check_marker_mismatch()`,
#' [flag_incongruent_references()], [remove_incongruent_references()])
#' already lives here and operates on this same output shape.
#' TaxaMatch -> TaxaFlag is not currently a dependency edge in this
#' ecosystem -- `TaxaFlag::review_assignments()` reviews post-assignment
#' DETECTIONS (a structurally later pipeline stage, downstream of
#' TaxaAssign); this reviews pre-assignment REFERENCE DATABASE quality,
#' upstream of TaxaExpect/TaxaAssign entirely. No new dependency is needed
#' to place it here either way: this function calls `TaxaTools::call_api()`
#' the exact same way `review_assignments()` does, and TaxaMatch already
#' depends on TaxaTools for several other reasons (`is_plausible_binomial()`,
#' `clean_taxon_names()`, `verify_taxon_names()`, `standard_ranks`).
#'
#' @section Scope (cost control):
#' Only reviews rows matching `hierarchy_flags`/`include_non_species_resolved`
#' -- not the whole evaluated population. On the real GreatLakes Goal-2
#' population this reentry prompt was written against, the default scope
#' selects 8 + 17 + 57 = 82 of 1,183 accessions (~7%), a tractable LLM batch
#' size -- see the reentry prompt's own "Cost/scale" discussion.
#'
#' @param evaluated_df Data frame -- [evaluate_reference_accessions()]'s own
#'   output. Must contain `accession`, `listed_taxon`, `hierarchy_flag`, one
#'   row per accession. Every other column used in the prompt
#'   (`finest_common_rank`, `best_agreeing_pident`, `best_disagreeing_pident`,
#'   `best_disagreeing_taxon`, `congruent_evidence_exists_anywhere`,
#'   `congruent_evidence_best_pident`, `taxonomy_resolution_source`,
#'   `listed_taxon_is_species`, `n_independent_top_matches`,
#'   `n_top_matches_available`, `frac_independent_below_min_congruent_rank`)
#'   is optional -- silently omitted from the prompt when absent, matching
#'   `TaxaFlag::review_assignments()`'s established convention for optional
#'   upstream columns. A duplicated `accession` value triggers a `warning()`
#'   (see Details) rather than an error, since a caller may have joined this
#'   onto a match object by mistake.
#' @param hierarchy_flags Character vector of `hierarchy_flag` values to
#'   review. Default `c("incongruent", "insufficient_independent_evidence")`.
#' @param include_non_species_resolved Logical (default `TRUE`). Also review
#'   any row with `listed_taxon_is_species == FALSE`, regardless of
#'   `hierarchy_flag` -- a structurally different, orthogonal problem the
#'   evaluation guide documents separately (see its own "listed_taxon_is_
#'   species = FALSE" section). Silently ignored if `listed_taxon_is_species`
#'   is absent from `evaluated_df`.
#' @param llm_fn Function. LLM provider function with signature
#'   `function(prompt_str, ...)`. Default `TaxaTools::call_api`.
#'   \strong{Known footgun:} `call_api()`'s provider auto-detection is set up
#'   by TaxaTools's own `.onAttach()`, which only runs via
#'   `library(TaxaTools)` -- a fully-namespaced call (`TaxaTools::`
#'   everywhere, no `library()`) never triggers it, and `call_api()` silently
#'   falls back to degraded/uniform output rather than erroring. Pass
#'   `llm_fn` explicitly if every review comes back suspiciously uniform,
#'   e.g. `function(p) TaxaTools::call_api(p, provider = "anthropic")`. See
#'   `TaxaID/CLAUDE.md`'s "Known R Footguns" for the full record.
#' @param taxa_per_call Integer. Maximum accessions per LLM call. Default
#'   `10L`.
#' @param max_tokens Integer or `NULL`. Forwarded as
#'   `llm_fn(prompt, max_tokens = max_tokens)` whenever supplied. Default
#'   `NULL` -- `llm_fn`'s own default applies.
#' @param max_retries Integer (default `2L`). A truncated, empty, or
#'   unparseable batch response is automatically split in half and retried
#'   (a smaller batch requests a proportionally shorter response) up to this
#'   many times, matching `review_assignments()`'s own retry mechanism.
#' @param pause_seconds Numeric (default `1`). Seconds to pause between LLM
#'   calls.
#' @param verbose Logical (default `TRUE`). Print progress messages.
#'
#' @return `evaluated_df` with 3 columns appended (`NA` for out-of-scope
#'   rows):
#' \describe{
#'   \item{`accession_likely_explanation`}{One of `"genuine_mislabel"`,
#'     `"poor_marker_resolution"`, `"sister_family_thin_coverage"`,
#'     `"hybrid_or_specimen_code_artifact"`, `"uncertain"` -- the LLM's own
#'     categorization of WHY the accession was flagged, never a re-decided
#'     `hierarchy_flag`.}
#'   \item{`accession_review_confidence`}{`"high"` / `"moderate"` / `"low"`.}
#'   \item{`accession_review_comment`}{Free-text note, or `NA`.}
#' }
#' Also carries `attr(result, "llm_prompts")` -- a named list of the exact
#' prompt string sent for each LLM call (named by batch number, with an
#' `"a"`/`"b"` suffix per retry sub-batch split), matching
#' `review_assignments()`'s own convention.
#'
#' @seealso [evaluate_reference_accessions()] for the columns this function
#'   reads, `TaxaFlag::review_assignments()` for the precedent this follows,
#'   `inst/reference_accession_evaluation_guide.md` for the full guide this
#'   function's prompt is built from.
#'
#' @export
review_flagged_accessions <- function(evaluated_df,
                                      hierarchy_flags = c("incongruent", "insufficient_independent_evidence"),
                                      include_non_species_resolved = TRUE,
                                      llm_fn = getOption("TaxaID.llm_fn", TaxaTools::call_api),
                                      taxa_per_call = 10L,
                                      max_tokens = NULL,
                                      max_retries = 2L,
                                      pause_seconds = 1,
                                      verbose = TRUE) {

  if (!is.data.frame(evaluated_df))
    stop("'evaluated_df' must be a data frame.", call. = FALSE)

  required_cols <- c("accession", "listed_taxon", "hierarchy_flag")
  missing_req <- setdiff(required_cols, names(evaluated_df))
  if (length(missing_req) > 0L)
    stop(sprintf("'evaluated_df' is missing required column(s): %s",
                paste(missing_req, collapse = ", ")), call. = FALSE)

  if (!is.character(hierarchy_flags) || length(hierarchy_flags) == 0L)
    stop("'hierarchy_flags' must be a non-empty character vector.", call. = FALSE)

  if (anyDuplicated(evaluated_df$accession) != 0L)
    warning(paste0(
      "review_flagged_accessions(): 'accession' has duplicate values in ",
      "'evaluated_df' -- expected one row per accession (evaluate_reference_",
      "accessions()'s own output shape). If this is a match object joined via ",
      "flag_incongruent_references(), reduce to unique accessions first (e.g. ",
      "evaluated_df[!duplicated(evaluated_df$accession), ]) before calling this ",
      "function -- review output is only written to the FIRST row per accession ",
      "otherwise."
    ), call. = FALSE)

  in_scope <- evaluated_df$hierarchy_flag %in% hierarchy_flags
  if (isTRUE(include_non_species_resolved) && "listed_taxon_is_species" %in% names(evaluated_df))
    in_scope <- in_scope | evaluated_df$listed_taxon_is_species %in% FALSE

  n_scope <- sum(in_scope)
  if (verbose)
    message(sprintf(
      "review_flagged_accessions(): %d of %d row(s) in scope for LLM review.",
      n_scope, nrow(evaluated_df)
    ))

  evaluated_df$accession_likely_explanation <- NA_character_
  evaluated_df$accession_review_confidence  <- NA_character_
  evaluated_df$accession_review_comment     <- NA_character_

  if (n_scope == 0L) {
    attr(evaluated_df, "llm_prompts") <- list()
    return(evaluated_df)
  }

  review_batch <- evaluated_df[in_scope, , drop = FALSE]
  review_batch <- review_batch[!duplicated(review_batch$accession), , drop = FALSE]

  n_acc     <- nrow(review_batch)
  tpc       <- min(taxa_per_call, n_acc)
  batch_idx <- split(seq_len(n_acc), ceiling(seq_len(n_acc) / tpc))
  n_batches <- length(batch_idx)

  if (verbose)
    message(sprintf("  %d LLM call(s) needed (taxa_per_call = %d).", n_batches, taxa_per_call))

  batch_results <- vector("list", n_batches)
  prompt_log    <- new.env(parent = emptyenv())

  for (b in seq_along(batch_idx)) {
    acc_batch <- review_batch[batch_idx[[b]], , drop = FALSE]

    if (verbose)
      message(sprintf("  Calling LLM (batch %d/%d, %d accession(s))...",
                      b, n_batches, nrow(acc_batch)))

    batch_results[[b]] <- .review_accession_batch_with_retry(
      acc_batch, llm_fn, max_tokens, verbose, pause_seconds,
      batch_label = as.character(b), max_retries = max_retries, prompt_log = prompt_log
    )

    if (b < n_batches) Sys.sleep(pause_seconds)
  }

  review_out <- do.call(rbind, batch_results)
  rownames(review_out) <- NULL

  if (verbose)
    message(sprintf("  Review complete. %d accession(s) reviewed.", nrow(review_out)))

  # A plain match()-based single-row update -- safe because 'accession' in
  # evaluated_df is required to be unique (checked above, warned otherwise).
  idx <- match(review_out$accession, evaluated_df$accession)
  evaluated_df$accession_likely_explanation[idx] <- review_out$accession_likely_explanation
  evaluated_df$accession_review_confidence[idx]  <- review_out$accession_review_confidence
  evaluated_df$accession_review_comment[idx]     <- review_out$accession_review_comment

  attr(evaluated_df, "llm_prompts") <- as.list(prompt_log)
  evaluated_df
}


# ==============================================================================
# Internal helpers
# ==============================================================================

#' Build LLM Prompt for a Batch of Flagged-Accession Second-Look Reviews
#'
#' Lifts its explanatory content directly from
#' `inst/reference_accession_evaluation_guide.md` -- the same 5-category
#' decision framework and worked real examples a human reviewer already
#' uses, not re-derived from scratch. Keep in sync with that guide if it's
#' updated.
#' @noRd
.build_accession_review_prompt <- function(acc_batch) {

  guide_block <- paste0(
    "You are an expert molecular systematist doing a second-look review of ",
    "flagged NCBI reference accessions for a DNA barcode reference-database ",
    "quality-control pipeline (TaxaMatch::evaluate_reference_accessions()).\n\n",
    "BACKGROUND: for each accession, the pipeline BLASTs its own deposited ",
    "sequence against a broad NCBI database, keeps independent hits (not from ",
    "the same submission batch), and asks whether the closest independent hits ",
    "agree with the accession's own listed taxon at family rank or finer. ",
    "hierarchy_flag = \"incongruent\" means most of the closest independent ",
    "evidence DISAGREES -- but this can mean several structurally different ",
    "things, which is exactly what you are being asked to help distinguish:\n\n",
    "1. GENUINE MISLABEL (real problem): best_disagreeing_pident is very high ",
    "(~98-100%) and congruent_evidence_exists_anywhere is false (or true but at ",
    "much lower identity than the disagreeing hit) -- the deposited sequence is ",
    "nearly identical to something in a completely different family/order.\n",
    "2. POOR MARKER RESOLVING POWER (not a mislabel -- correctly flagged, just ",
    "for a different reason): best_disagreeing_pident is high AND several real, ",
    "taxonomically diverse independent hits disagree (not just one), often at ",
    "moderate-to-high identity (~93-96%) -- the marker/amplicon genuinely ",
    "doesn't discriminate this lineage well from several unrelated families. ",
    "Real example: Stereolepis doederleini's amplicon-trimmed 12S region ",
    "doesn't discriminate it from 4 unrelated families at 94.9-95.9% identity -- ",
    "a correctly-earned flag, not a mislabel.\n",
    "3. SISTER-FAMILY OR THIN-COVERAGE ARTIFACT (weak signal, likely not a ",
    "mislabel): finest_common_rank reports a real coarser agreement (e.g. ",
    "\"order\") rather than being entirely absent, and best_disagreeing_pident ",
    "is only moderate (~85-92%) -- the closest independent hits are a sister ",
    "clade within the same order, at an identity level unremarkable for a ",
    "conserved/poorly-resolving marker with thin database coverage at the ",
    "listed rank.\n",
    "4. HYBRID-CROSS OR INFORMAL-SPECIMEN-CODE ARTIFACT: listed_taxon may be a ",
    "nomenclatural hybrid formula (e.g. \"Ctenopharyngodon idella x ",
    "Megalobrama amblycephala\", a known Chinese aquaculture hybrid) or an ",
    "informal specimen code standing in for a real species name (e.g. ",
    "\"Serranidae sp. JL-2015\", a family name plus a specimen code, not a real ",
    "binomial) -- best_disagreeing_taxon may itself be one of these. ",
    "Recognizing either from taxonomic knowledge is exactly the kind of thing ",
    "you can add that the statistical check alone cannot.\n\n",
    "Your job is NOT to override hierarchy_flag or decide whether to remove the ",
    "accession -- a human reads your comment before acting on it. Bring any real ",
    "taxonomic-literature knowledge you have (known hybrid crosses, recent ",
    "species splits/synonymies, informal specimen-code conventions) that the ",
    "numeric columns alone can't capture.\n"
  )

  acc_lines <- vapply(seq_len(nrow(acc_batch)), function(i) {
    row <- acc_batch[i, ]
    add_if <- function(col, fmt) {
      if (col %in% names(row) && !is.na(row[[col]])) sprintf(fmt, row[[col]]) else NULL
    }
    parts <- c(
      sprintf("listed_taxon=\"%s\"", row$listed_taxon),
      sprintf("hierarchy_flag=%s", row$hierarchy_flag),
      add_if("finest_common_rank", "finest_common_rank=%s"),
      add_if("best_agreeing_pident", "best_agreeing_pident=%.1f"),
      add_if("best_disagreeing_pident", "best_disagreeing_pident=%.1f"),
      add_if("best_disagreeing_taxon", "best_disagreeing_taxon=\"%s\""),
      add_if("congruent_evidence_exists_anywhere", "congruent_evidence_exists_anywhere=%s"),
      add_if("congruent_evidence_best_pident", "congruent_evidence_best_pident=%.1f"),
      add_if("taxonomy_resolution_source", "taxonomy_resolution_source=%s"),
      add_if("listed_taxon_is_species", "listed_taxon_is_species=%s"),
      add_if("n_independent_top_matches", "n_independent_top_matches=%d"),
      add_if("n_top_matches_available", "n_top_matches_available=%d"),
      add_if("frac_independent_below_min_congruent_rank",
             "frac_independent_below_min_congruent_rank=%.2f")
    )
    sprintf("- accession=%s: %s", row$accession, paste(unlist(parts), collapse = ", "))
  }, character(1))

  paste0(
    guide_block, "\n",
    "TASK: review each flagged accession below and return a JSON array with one ",
    "object per accession. Return ONLY the JSON array -- no markdown fences, no ",
    "explanation before or after.\n\n",
    "Each object must have these fields:\n",
    "  \"accession\": the exact accession as provided,\n",
    "  \"accession_likely_explanation\": one of \"genuine_mislabel\", ",
    "\"poor_marker_resolution\", \"sister_family_thin_coverage\", ",
    "\"hybrid_or_specimen_code_artifact\", \"uncertain\",\n",
    "  \"accession_review_confidence\": one of \"high\", \"moderate\", \"low\",\n",
    "  \"accession_review_comment\": a brief free-text note (1-3 sentences), or null\n\n",
    "GUIDELINES:\n",
    "- If listed_taxon_is_species is false, that's a separate, orthogonal problem ",
    "(the reference can't discriminate at species level regardless of ",
    "hierarchy_flag) -- say so plainly in the comment rather than forcing it into ",
    "one of the 4 disagreement categories above.\n",
    "- Be conservative with \"genuine_mislabel\" -- only use it when the identity ",
    "and pattern genuinely point that way, not just because hierarchy_flag is ",
    "\"incongruent\".\n",
    "- If uncertain, use \"uncertain\" with \"low\" or \"moderate\" confidence ",
    "rather than forcing a specific category.\n\n",
    "ACCESSIONS TO REVIEW:\n",
    paste(acc_lines, collapse = "\n")
  )
}


#' Call LLM for One Accession-Review Batch, Retrying Smaller Sub-batches on
#' Truncation/Failure
#'
#' Mirrors `TaxaFlag::review_assignments()`'s
#' `.review_batch_with_retry()`/`.parse_review_response()` design exactly
#' (same retry-by-halving strategy, same reasoning for why a hard `llm_fn`
#' error is never retried this way) -- see that function's own roxygen for
#' the full rationale. Not shared code (TaxaMatch must not depend on
#' TaxaFlag, matching this ecosystem's documented dependency direction), but
#' deliberately the same shape.
#' @noRd
.review_accession_batch_with_retry <- function(acc_batch, llm_fn, max_tokens, verbose,
                                               pause_seconds, batch_label, max_retries,
                                               depth = 0L, prompt_log = NULL) {

  prompt <- .build_accession_review_prompt(acc_batch)
  if (!is.null(prompt_log)) assign(batch_label, prompt, envir = prompt_log)

  call_error <- NULL
  raw <- tryCatch(
    if (is.null(max_tokens)) llm_fn(prompt) else llm_fn(prompt, max_tokens = max_tokens),
    error = function(e) { call_error <<- conditionMessage(e); NULL }
  )

  if (!is.null(call_error)) {
    warning(sprintf("LLM call failed for accession-review batch %s: %s. Using NA defaults.",
                    batch_label, call_error), call. = FALSE)
    result <- .parse_accession_review_response(NULL, acc_batch)
    attr(result, "status")           <- NULL
    attr(result, "pending_warnings") <- NULL
    return(result)
  }

  parsed  <- .parse_accession_review_response(raw, acc_batch)
  status  <- attr(parsed, "status")
  pending <- attr(parsed, "pending_warnings")

  can_retry <- status %in% c("truncated", "failed") &&
    depth < max_retries && nrow(acc_batch) > 1L

  if (can_retry) {
    if (verbose)
      message(sprintf(
        "  Accession-review batch %s %s (%d accession(s)) -- retrying as smaller sub-batches...",
        batch_label, if (status == "failed") "returned no usable content" else "was truncated",
        nrow(acc_batch)
      ))
    mid   <- ceiling(nrow(acc_batch) / 2)
    left  <- acc_batch[seq_len(mid), , drop = FALSE]
    right <- acc_batch[(mid + 1L):nrow(acc_batch), , drop = FALSE]

    left_result <- .review_accession_batch_with_retry(
      left, llm_fn, max_tokens, verbose, pause_seconds,
      paste0(batch_label, "a"), max_retries, depth + 1L, prompt_log
    )
    Sys.sleep(pause_seconds)
    right_result <- .review_accession_batch_with_retry(
      right, llm_fn, max_tokens, verbose, pause_seconds,
      paste0(batch_label, "b"), max_retries, depth + 1L, prompt_log
    )
    return(rbind(left_result, right_result))
  }

  for (w in pending) warning(w, call. = FALSE)
  attr(parsed, "status")           <- NULL
  attr(parsed, "pending_warnings") <- NULL
  parsed
}


#' Parse LLM Accession-Review Response
#'
#' Never calls `warning()` directly -- returns the parsed result with two
#' attributes (`status`, `pending_warnings`) so
#' `.review_accession_batch_with_retry()` can decide whether to retry with a
#' smaller batch before emitting anything. Mirrors
#' `TaxaFlag::review_assignments()`'s `.parse_review_response()`.
#' @noRd
.parse_accession_review_response <- function(response, acc_batch) {

  expected_acc <- acc_batch$accession

  make_default <- function(accessions = expected_acc) {
    data.frame(
      accession                    = accessions,
      accession_likely_explanation = NA_character_,
      accession_review_confidence  = NA_character_,
      accession_review_comment     = NA_character_,
      stringsAsFactors = FALSE
    )
  }

  .with_status <- function(result, status, pending_warnings = character(0)) {
    attr(result, "status")           <- status
    attr(result, "pending_warnings") <- pending_warnings
    result
  }

  if (is.null(response) || !nzchar(trimws(response))) {
    return(.with_status(make_default(), "failed",
                        "Empty LLM response. Returning NA defaults."))
  }

  cleaned <- trimws(response)

  if (grepl("```", cleaned)) {
    fenced <- sub("(?s).*?```(?:json)?\\s*", "", cleaned, perl = TRUE)
    fenced <- sub("(?s)\\s*```.*", "", fenced, perl = TRUE)
    fenced <- trimws(fenced)
  } else {
    fenced <- cleaned
  }

  parsed <- tryCatch(
    jsonlite::fromJSON(fenced, simplifyDataFrame = TRUE),
    error = function(e) NULL
  )

  if (is.null(parsed) || !is.data.frame(parsed)) {
    arr_str <- sub("(?s).*?(\\[\\s*\\{[\\s\\S]*\\}\\s*\\]).*", "\\1", cleaned, perl = TRUE)
    parsed <- tryCatch(
      jsonlite::fromJSON(arr_str, simplifyDataFrame = TRUE),
      error = function(e) NULL
    )
  }

  if (is.null(parsed) || !is.data.frame(parsed))
    parsed <- .recover_truncated_accession_json(fenced)

  if (is.null(parsed) || !is.data.frame(parsed) || nrow(parsed) == 0L) {
    n <- nchar(trimws(response))
    tail_str <- if (n > 200L) substr(trimws(response), max(1L, n - 200L), n) else trimws(response)
    return(.with_status(make_default(), "failed", sprintf(
      "Could not parse LLM accession-review response as JSON. Returning NA defaults.\n  Response length: %d chars; ends with: ...%s",
      n, tail_str
    )))
  }

  pending <- character(0)
  status  <- "complete"

  n_recovered <- nrow(parsed)
  n_expected  <- length(expected_acc)
  if (n_recovered < n_expected) {
    status  <- "truncated"
    pending <- c(pending, sprintf(
      "LLM accession-review response was truncated. Recovered %d of %d accessions from partial JSON.",
      n_recovered, n_expected
    ))
  }

  if (!"accession" %in% names(parsed)) {
    return(.with_status(make_default(), "failed",
                        "LLM accession-review response missing 'accession' field. Returning NA defaults."))
  }

  .safe_col <- function(df, col_name) {
    if (col_name %in% names(df)) {
      vals <- as.character(df[[col_name]])
      vals[vals %in% c("null", "NULL", "NA")] <- NA_character_
      vals
    } else {
      rep(NA_character_, nrow(df))
    }
  }

  valid_explanations <- c("genuine_mislabel", "poor_marker_resolution",
                          "sister_family_thin_coverage",
                          "hybrid_or_specimen_code_artifact", "uncertain")

  result <- data.frame(
    accession                    = as.character(parsed$accession),
    accession_likely_explanation = .safe_col(parsed, "accession_likely_explanation"),
    accession_review_confidence  = .safe_col(parsed, "accession_review_confidence"),
    accession_review_comment     = .safe_col(parsed, "accession_review_comment"),
    stringsAsFactors = FALSE
  )

  # An LLM occasionally invents a category outside the requested enum --
  # normalised to "uncertain" rather than left as free-form text a caller
  # would have to defensively re-validate before using this column in a
  # table/filter.
  bad_explanation <- !is.na(result$accession_likely_explanation) &
    !result$accession_likely_explanation %in% valid_explanations
  if (any(bad_explanation))
    result$accession_likely_explanation[bad_explanation] <- "uncertain"

  # Normalise trailing punctuation/whitespace before exact-matching back to
  # the requested accessions -- mirrors review_assignments()'s own
  # taxon-name normalisation, applied to accession strings instead.
  .norm <- function(x) toupper(trimws(gsub("[.,;:]+$", "", trimws(x))))
  expected_norm <- .norm(expected_acc)

  unmatched_idx <- which(!result$accession %in% expected_acc)
  if (length(unmatched_idx) > 0L) {
    result_norm <- .norm(result$accession)
    remapped <- character(0)
    for (i in unmatched_idx) {
      hit <- which(expected_norm == result_norm[i])
      if (length(hit) == 1L) {
        remapped <- c(remapped, sprintf("'%s' -> '%s'", result$accession[i], expected_acc[hit]))
        result$accession[i] <- expected_acc[hit]
      }
    }
    if (length(remapped) > 0L)
      pending <- c(pending, sprintf(
        "LLM returned %d accession(s) that required normalised matching: %s",
        length(remapped), paste(remapped, collapse = "; ")
      ))
  }

  missing_acc <- setdiff(expected_acc, result$accession)
  if (length(missing_acc) > 0L) {
    pending <- c(pending, sprintf("LLM omitted %d accession(s). Filling with NA defaults: %s",
                    length(missing_acc), paste(missing_acc, collapse = ", ")))
    result <- rbind(result, make_default(missing_acc))
  }

  result <- result[result$accession %in% expected_acc, , drop = FALSE]
  result <- result[!duplicated(result$accession), , drop = FALSE]

  .with_status(result, status, pending)
}


#' Recover Parseable Objects from Truncated Accession-Review JSON Array
#' @noRd
.recover_truncated_accession_json <- function(text) {
  if (is.null(text) || !nzchar(trimws(text))) return(NULL)

  arr_start <- regexpr("\\[", text)
  if (arr_start < 0L) return(NULL)

  text_from_arr   <- substring(text, arr_start)
  brace_positions <- gregexpr("\\}", text_from_arr)[[1]]
  if (brace_positions[1] < 0L) return(NULL)

  for (i in rev(seq_along(brace_positions))) {
    candidate <- paste0(substring(text_from_arr, 1L, brace_positions[i]), "\n]")
    parsed <- tryCatch(
      jsonlite::fromJSON(candidate, simplifyDataFrame = TRUE),
      error = function(e) NULL
    )
    if (is.data.frame(parsed) && nrow(parsed) > 0L) return(parsed)
  }

  NULL
}
