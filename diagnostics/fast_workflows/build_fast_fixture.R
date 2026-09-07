# ==============================================================================
# build_fast_fixture.R
# TaxaID -- Extract a small, curated, real-data fixture from a full production
# checkpoint, for minutes-not-hours debugging iteration.
#
# 2026-09-05: written in response to the user's own experience that testing
# against full real workflows (13k+ observations, live NCBI/GBIF/LLM calls)
# has cost months of development time. This does NOT invent synthetic data --
# it subsets a REAL, already-computed checkpoint, so the fixture still
# contains genuine edge cases (multi-candidate irreducibility stress rows,
# flagged reference-quality verdicts, contaminant-flagged rows), just far
# fewer of them.
#
# Design: read-only against the source checkpoint. Never writes back to the
# directory it reads from -- this script is deliberately safe to run while a
# real production workflow has that same directory open/in progress, AS LONG
# AS the specific source file passed in is not itself being actively written
# by that live run (check its mtime first if in doubt).
#
# Curation strategy -- not a blind "first N rows" or uniform random sample,
# both of which would likely miss the exact rows that matter for regression
# testing:
#   1. "Interesting" observations: any observation_id with >=1 candidate row
#      whose reference_action/hierarchy_flag/validity_flag value is in a
#      caller-supplied "flagged" set (defaults below target the real
#      reference-quality-screening + contaminant-flagging columns), OR whose
#      total candidate count is >= high_candidate_threshold (stress-tests
#      irreducibility/slash-taxon logic, which is exactly what the
#      order-invariance bug -- see TaxaAssign/CLAUDE.md 2026-09-04 -- hid in).
#   2. "Baseline" observations: a reproducible stratified random sample of the
#      remaining, ordinary rows, bucketed by candidate count, so the fixture
#      still exercises the common case at realistic ratios, not just edge
#      cases.
#   3. Total unique observation_ids capped at max_observations (default 150)
#      -- if step 1 alone exceeds this, an "interesting" pool is randomly
#      subsampled down (not truncated positionally) so ANY re-run remains
#      reproducible via the fixed seed, not order-dependent.
#
# Usage:
#   Rscript diagnostics/fast_workflows/build_fast_fixture.R \
#     --input  "~/My Drive/Rscripts/eDNA/PtConception/PtConMifishSchulte_match_obj_restored.rds" \
#     --output "diagnostics/fast_workflows/ptcon12s_fast_match_obj.rds" \
#     --max-observations 150
#
# Or call build_fast_fixture() directly from an R session (see below).
# ==============================================================================

#' Build a small, curated fixture from a real match/reference-quality object
#'
#' @param input_path Path to a real, already-computed match-object-shaped
#'   .rds checkpoint (one row per observation_id x candidate). Read-only.
#' @param output_path Where to save the curated subset (.rds). Not written
#'   until the whole subset is computed, so a failed run never leaves a
#'   partial file.
#' @param id_col Column identifying one detection ("observation"). Default
#'   "observation_id" (this ecosystem's standard name).
#' @param flag_cols Named list: column name -> character vector of "this
#'   value marks an interesting row" values. Any row matching pulls its
#'   WHOLE observation_id into the "interesting" pool (never just that one
#'   candidate row -- consensus/irreducibility logic needs the full
#'   candidate set for an observation to mean anything). Defaults target the
#'   real reference-quality-screening and contaminant-flagging columns this
#'   ecosystem's real checkpoints carry as of 2026-09.
#' @param high_candidate_threshold Observations with at least this many
#'   candidate rows are also pulled into "interesting" (stress-tests
#'   irreducibility/slash-taxon consensus logic on real wide candidate
#'   sets). Default 20L.
#' @param max_observations Hard cap on total unique observation_ids in the
#'   output. Default 150L -- chosen to keep runtime in the "few minutes" range
#'   for the LLM-review/BLAST-rescoring stages, not just the cheap
#'   consensus/posterior math. Tune down further for a true "seconds" smoke
#'   test.
#' @param n_baseline How many additional ordinary (non-"interesting")
#'   observations to include for common-case coverage, stratified by
#'   candidate count. Default 50L. Reduced automatically if max_observations
#'   doesn't leave room after the interesting pool.
#' @param seed Fixed seed for the random components (baseline sample, and
#'   the interesting-pool subsample if it exceeds max_observations), so
#'   re-running this script reproduces byte-identical fixtures.
#' @param always_include_taxa Character vector of taxon names (matched
#'   case-insensitively, as a substring, against every character column --
#'   whichever column actually carries taxon names varies by checkpoint
#'   shape, e.g. `taxon_name` for a match object vs `consensus_taxon` for a
#'   consensus-shaped one) whose observations are ALWAYS pulled into the
#'   fixture, on top of `max_observations`, regardless of whether they trip
#'   any flag column or the candidate-count threshold. Exists specifically so
#'   known problem taxa from past debugging sessions (e.g. Fundulus lima vs
#'   parvipinnis) are guaranteed present rather than left to chance.
#'
#' @return Invisibly, the curated subset data frame (also written to
#'   `output_path`). Prints a summary table so you can see what's in it
#'   before trusting it.
build_fast_fixture <- function(input_path,
                                output_path,
                                id_col = "observation_id",
                                flag_cols = list(
                                  reference_action = c("caution", "inspect", "remove"),
                                  hierarchy_flag = c("incongruent", "insufficient_independent_evidence",
                                                      "not_evaluated_oversized"),
                                  validity_flag = c("invalid_lab_contaminant", "invalid_positive_control",
                                                     "invalid_handling")
                                ),
                                high_candidate_threshold = 20L,
                                max_observations = 150L,
                                n_baseline = 50L,
                                seed = 42L,
                                always_include_taxa = character(0)) {

  if (!file.exists(input_path))
    stop("build_fast_fixture: input_path does not exist: ", input_path, call. = FALSE)

  input_path <- path.expand(input_path)
  cat(sprintf("Reading (read-only): %s\n", input_path))
  full <- readRDS(input_path)

  if (!is.data.frame(full))
    stop("build_fast_fixture: input must be a data frame (one row per ",
         id_col, " x candidate).", call. = FALSE)
  if (!id_col %in% names(full))
    stop("build_fast_fixture: id_col '", id_col, "' not found. Available: ",
         paste(names(full), collapse = ", "), call. = FALSE)

  n_per_obs <- table(full[[id_col]])

  # --- Step 1: interesting observations -----------------------------------
  interesting_ids <- character(0)
  for (col in names(flag_cols)) {
    if (!col %in% names(full)) {
      message(sprintf("  (column '%s' not present in this checkpoint -- skipped)", col))
      next
    }
    hit <- full[[col]] %in% flag_cols[[col]]
    if (any(hit)) {
      new_ids <- unique(full[[id_col]][hit])
      cat(sprintf("  %-16s in %-40s -> %d observation(s)\n",
                  paste(flag_cols[[col]], collapse = "/"), col, length(new_ids)))
      interesting_ids <- union(interesting_ids, new_ids)
    }
  }
  wide_ids <- names(n_per_obs)[n_per_obs >= high_candidate_threshold]
  if (length(wide_ids) > 0) {
    cat(sprintf("  >=%d candidates -> %d observation(s)\n", high_candidate_threshold, length(wide_ids)))
    interesting_ids <- union(interesting_ids, wide_ids)
  }
  cat(sprintf("Total distinct 'interesting' observations: %d\n", length(interesting_ids)))

  # --- Always-include named taxa: guaranteed present, outside the budget ---
  # Scanned against every character column rather than one hardcoded name,
  # since which column carries taxon names varies by checkpoint shape (a
  # match object vs. an already-computed posterior/consensus table).
  always_ids <- character(0)
  if (length(always_include_taxa) > 0) {
    char_cols <- names(full)[vapply(full, is.character, logical(1))]
    pattern <- paste(always_include_taxa, collapse = "|")
    hit <- Reduce(`|`, lapply(char_cols, function(col) {
      grepl(pattern, full[[col]], ignore.case = TRUE)
    }))
    always_ids <- unique(full[[id_col]][hit])
    cat(sprintf("Always-include taxa (%s) -> %d observation(s), guaranteed regardless of max_observations\n",
                paste(always_include_taxa, collapse = ", "), length(always_ids)))
    interesting_ids <- setdiff(interesting_ids, always_ids)
  }

  set.seed(seed)
  # Reserve the caller's full requested baseline count (up to max_observations
  # - 1) REGARDLESS of how large the interesting pool is -- a fixture with
  # only edge cases can't tell you whether a change broke the ORDINARY case,
  # which is just as real a regression. The interesting pool absorbs whatever
  # budget is left, subsampled down if it doesn't fit.
  reserved_baseline <- max(0L, min(n_baseline, max_observations - 1L))
  interesting_budget <- max_observations - reserved_baseline
  if (length(interesting_ids) > interesting_budget) {
    cat(sprintf(
      "  (interesting pool (%d) exceeds its budget (%d of max_observations=%d, reserving %d for baseline) -- randomly subsampling, seed=%d)\n",
      length(interesting_ids), interesting_budget, max_observations, reserved_baseline, seed))
    interesting_ids <- sample(interesting_ids, interesting_budget)
  }
  n_baseline <- min(reserved_baseline, max_observations - length(interesting_ids))

  # --- Step 2: baseline sample, stratified by candidate count --------------
  baseline_ids <- character(0)
  if (n_baseline > 0L) {
    ordinary_ids <- setdiff(names(n_per_obs), interesting_ids)
    ordinary_n <- n_per_obs[ordinary_ids]
    buckets <- cut(ordinary_n, breaks = c(0, 1, 2, 5, 10, Inf),
                    labels = c("1", "2", "3-5", "6-10", "11+"))
    per_bucket <- ceiling(n_baseline / nlevels(buckets))
    for (lvl in levels(buckets)) {
      pool <- ordinary_ids[buckets == lvl]
      take <- min(per_bucket, length(pool))
      if (take > 0) baseline_ids <- c(baseline_ids, sample(pool, take))
    }
    if (length(baseline_ids) > n_baseline) baseline_ids <- sample(baseline_ids, n_baseline)
    cat(sprintf("Baseline (ordinary, stratified by candidate count): %d observation(s)\n",
                length(baseline_ids)))
  }

  keep_ids <- union(union(interesting_ids, baseline_ids), always_ids)
  subset_df <- full[full[[id_col]] %in% keep_ids, , drop = FALSE]

  cat(sprintf("\nFinal fixture: %d observation(s), %d row(s) (from %d / %d in the source)\n",
              length(keep_ids), nrow(subset_df), length(unique(full[[id_col]])), nrow(full)))
  for (col in c("reference_action", "hierarchy_flag", "validity_flag")) {
    if (col %in% names(subset_df)) {
      cat(sprintf("--- %s ---\n", col))
      print(table(subset_df[[col]], useNA = "ifany"))
    }
  }

  attr(subset_df, "fast_fixture_source") <- input_path
  attr(subset_df, "fast_fixture_built") <- Sys.time()
  attr(subset_df, "fast_fixture_interesting_ids") <- interesting_ids
  attr(subset_df, "fast_fixture_baseline_ids") <- baseline_ids
  attr(subset_df, "fast_fixture_always_include_ids") <- always_ids

  dir.create(dirname(output_path), showWarnings = FALSE, recursive = TRUE)
  saveRDS(subset_df, output_path)
  cat(sprintf("\nWritten to: %s (%.1f MB)\n", output_path, file.size(output_path) / 1e6))

  invisible(subset_df)
}

# --- Command-line entry point ------------------------------------------------
# Only fires when --input is actually present on the command line, so
# source()-ing this file (e.g. from an interactive session or another
# script, with no CLI args at all) just defines build_fast_fixture() and
# does nothing further -- it never errors just because it was sourced.
.cli_args <- commandArgs(trailingOnly = TRUE)
if ("--input" %in% .cli_args) {
  get_arg <- function(flag, default = NULL) {
    i <- which(.cli_args == flag)
    if (length(i) == 0) return(default)
    .cli_args[i + 1L]
  }
  input  <- get_arg("--input")
  output <- get_arg("--output")
  max_n  <- as.integer(get_arg("--max-observations", "150"))
  if (is.null(input) || is.null(output)) {
    stop("Usage: Rscript build_fast_fixture.R --input <path.rds> --output <path.rds> ",
         "[--max-observations N]", call. = FALSE)
  }
  build_fast_fixture(input_path = input, output_path = output, max_observations = max_n)
}
rm(.cli_args)
