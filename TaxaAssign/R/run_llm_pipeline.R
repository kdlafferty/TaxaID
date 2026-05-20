#' Run the Full LLM-Shortcut Assignment Pipeline
#'
#' High-level wrapper that chains the LLM-shortcut workflow into a single call:
#' optionally build context, optionally detect unreferenced species, run
#' \code{assign_taxa_llm()}, derive consensus, refine via empirical Bayes, and
#' optionally generate a report.
#'
#' This encapsulates ~7 function calls (Sections 2-5 of
#' \code{inst/TaxaAssign_llm_workflow.R}) into a single step. For fine-grained
#' control, use the individual functions directly.
#'
#' @param match_df Data frame. Standardized match object from
#'   \code{\link[TaxaMatch]{standardize_match_data}}, with columns
#'   \code{observation_id}, \code{score}, \code{taxon_name}, \code{taxon_name_rank},
#'   and taxonomy columns.
#' @param context Optional data frame or list with location/habitat context.
#'   When \code{NULL} (default) and \code{auto_context = TRUE}, context is
#'   auto-populated via \code{\link{build_context}}. When supplied, passed
#'   directly to \code{\link{assign_taxa_llm}}.
#' @param auto_context Logical. When \code{TRUE} (default) and \code{context}
#'   is \code{NULL}, automatically build context via \code{\link{build_context}}.
#'   Requires the TaxaHabitat package.
#' @param geographic_hint Optional character string for
#'   \code{\link{build_context}} (e.g. \code{"Southern California"}).
#'   Ignored when \code{context} is supplied.
#' @param date Optional character string for \code{\link{build_context}}
#'   (e.g. \code{"2025"}). Ignored when \code{context} is supplied.
#' @param habitat_scheme Passed to \code{\link{build_context}} for habitat
#'   assignment. Default \code{NULL} (3-category).
#' @param llm_fn Function or NULL. LLM provider following the TaxaTools
#'   \code{llm_fn} pattern. Default NULL resolves to
#'   \code{TaxaTools::call_anthropic_api} (requires TaxaTools).
#' @param detect_unreferenced Logical. When \code{TRUE} (default), run
#'   \code{\link{suggest_unreferenced_species}} to detect taxa absent from the
#'   reference database. Set to \code{FALSE} to skip.
#' @param barcode_term Character. Barcode marker for unreferenced species
#'   detection. Default \code{"12S"}.
#' @param expand_to_family Logical. Expand unreferenced search to family level.
#'   Default \code{TRUE}. Passed to \code{\link{suggest_unreferenced_species}}.
#' @param max_date Optional character. NCBI date filter for unreferenced species
#'   detection (e.g. \code{"2024/12/31"}).
#' @param unreferenced_taxa Optional character vector of known unreferenced
#'   species. When supplied, \code{detect_unreferenced} is ignored and these
#'   are passed directly to \code{\link{assign_taxa_llm}}.
#' @param score_threshold Numeric. Minimum score to include a candidate (0-100).
#'   Default 80.
#' @param top_n Integer. Maximum candidates per observation sent to LLM. Default 10.
#' @param score_sharpness Numeric. Exponential weight sharpness for likelihood
#'   proxy. Default 0.1.
#' @param unknown_lik_weight Numeric. Baseline likelihood for the unknown
#'   species hypothesis. Default 0.05.
#' @param known_present Optional character vector of confirmed present species.
#' @param known_absent Optional character vector or data frame of confirmed
#'   absent species. See \code{\link{assign_taxa_llm}} for details.
#' @param absent_detection_prob Numeric. Detection probability for known-absent
#'   species. Default 0.80.
#' @param taxa_per_call Integer. Maximum taxa per LLM call. Default 30.
#' @param pause_seconds Numeric. Pause between LLM calls. Default 1.
#' @param prior_phi Named numeric vector mapping \code{information_quality}
#'   to Beta concentration. Default \code{c(high = 50, moderate = 10, low = 3)}.
#' @param n_sims Integer. Monte Carlo simulations. Default \code{1000L}.
#' @param context_group Optional character vector of column names in
#'   \code{context} for grouping observations. Default \code{NULL}.
#' @param rank_system Character vector of taxonomy ranks, coarse to fine.
#'   Default \code{c("family", "genus", "species")}.
#' @param cumulative_threshold Numeric. Posterior probability threshold for
#'   consensus. Default 0.90.
#' @param min_posterior Numeric. Minimum posterior to be considered plausible.
#'   Default 0.05.
#' @param posterior_col Character. Column name for posterior values. Default
#'   \code{"posterior_point_est"}.
#' @param backbone_id Integer. Backbone for taxonomy lookup. Default \code{4L}
#'   (NCBI).
#' @param lookup_missing_taxonomy Logical. Look up missing taxonomy in
#'   consensus. Default \code{TRUE}.
#' @param presence_multiplier Numeric. Multiplier for empirical Bayes
#'   refinement. Default 5.
#' @param generate_report Logical. Generate a Methods + Results report.
#'   Default \code{FALSE}.
#' @param report_params Named list of additional arguments passed to
#'   \code{\link{generate_report}} (e.g. \code{data_type}, \code{marker},
#'   \code{study_description}).
#' @param reference_errors Optional data frame. Output of
#'   \code{\link[TaxaLikely]{flag_reference_errors}} (or
#'   \code{model_params$reference_errors} from a trained model). When
#'   supplied, mislabeled accessions are removed from \code{match_df}
#'   before assignment. Default \code{NULL} (no filtering).
#' @param verbose Logical. Print progress messages. Default \code{TRUE}.
#'
#' @return A named list with components:
#' \describe{
#'   \item{\code{$consensus}}{Final consensus data frame (one row per
#'     \code{observation_id}), after empirical Bayes refinement.}
#'   \item{\code{$result}}{Full posterior data frame (after refinement),
#'     with all hypotheses per observation.}
#'   \item{\code{$context}}{The context data frame used (auto-built or
#'     user-supplied).}
#'   \item{\code{$unreferenced}}{The unreferenced species result, or
#'     \code{NULL} if skipped.}
#'   \item{\code{$report}}{Report text from \code{generate_report()}, or
#'     \code{NULL} if \code{generate_report = FALSE}.}
#' }
#'
#' @seealso \code{\link{run_bayesian_pipeline}} for the model-based alternative,
#'   \code{\link{assign_taxa_llm}}, \code{\link{build_context}}
#'
#' @examples
#' \dontrun{
#' out <- run_llm_pipeline(
#'   match_df        = match_obj,
#'   geographic_hint = "Southern California",
#'   barcode_term    = "12S"
#' )
#' head(out$consensus)
#' }
#'
#' @export
run_llm_pipeline <- function(
    match_df,
    context              = NULL,
    auto_context         = TRUE,
    geographic_hint      = NULL,
    date                 = NULL,
    habitat_scheme       = NULL,
    llm_fn               = NULL,
    detect_unreferenced  = TRUE,
    barcode_term         = "12S",
    expand_to_family     = TRUE,
    max_date             = NULL,
    unreferenced_taxa    = NULL,
    score_threshold      = 80,
    top_n                = 10L,
    score_sharpness      = 0.1,
    unknown_lik_weight   = 0.05,
    known_present        = NULL,
    known_absent         = NULL,
    absent_detection_prob = 0.80,
    taxa_per_call        = 30L,
    pause_seconds        = 1,
    prior_phi            = c(high = 50, moderate = 10, low = 3),
    n_sims               = 1000L,
    context_group        = NULL,
    rank_system          = c("family", "genus", "species"),
    cumulative_threshold = 0.90,
    min_posterior        = 0.05,
    posterior_col        = "posterior_point_est",
    backbone_id          = 4L,
    lookup_missing_taxonomy = TRUE,
    presence_multiplier  = 5,
    generate_report      = FALSE,
    report_params        = list(),
    reference_errors     = NULL,
    verbose              = TRUE
) {

  .msg <- function(...) if (verbose) message(...)
  llm_fn <- .resolve_llm_fn(llm_fn, "run_llm_pipeline")

  # =========================================================================
  # Stage 0: Remove flagged reference errors from match_df
  # =========================================================================
  if (!is.null(reference_errors) && is.data.frame(reference_errors) &&
      nrow(reference_errors) > 0L && "accession" %in% names(match_df)) {
    match_df <- TaxaLikely::remove_flagged_references(match_df, reference_errors)
  }

  # =========================================================================
  # Stage 1: Build context (if needed)
  # =========================================================================
  if (is.null(context) && auto_context) {
    .msg("run_llm_pipeline [1/4]: Auto-building context via build_context()...")

    context <- build_context(
      taxon_names     = unique(match_df$taxon_name[match_df$score >= score_threshold]),
      geographic_hint = geographic_hint,
      date            = date,
      habitat_scheme  = habitat_scheme,
      llm_fn          = llm_fn
    )
    .msg(sprintf("  Context: ecoregion = %s, main_habitat = %s",
                 context$ecoregion %||% "NA", context$main_habitat %||% "NA"))
  } else if (is.null(context)) {
    .msg("run_llm_pipeline [1/4]: No context provided (auto_context = FALSE). Proceeding without.")
  } else {
    .msg("run_llm_pipeline [1/4]: Using user-supplied context.")
  }

  # =========================================================================
  # Stage 2: Detect unreferenced species
  # =========================================================================
  unreferenced_result <- NULL

  if (!is.null(unreferenced_taxa)) {
    .msg("run_llm_pipeline [2/4]: Using user-supplied unreferenced taxa.")
    unreferenced_result <- unreferenced_taxa
  } else if (detect_unreferenced) {
    .msg("run_llm_pipeline [2/4]: Detecting unreferenced species via LLM + NCBI...")

    unreferenced_result <- suggest_unreferenced_species(
      match_df         = match_df,
      context          = context,
      barcode_term     = barcode_term,
      llm_fn           = llm_fn,
      expand_to_family = expand_to_family,
      max_date         = max_date,
      taxa_per_call    = taxa_per_call,
      pause_seconds    = pause_seconds,
      verbose          = verbose
    )
    .msg(sprintf("  %d unreferenced species detected.", length(unreferenced_result)))
  } else {
    .msg("run_llm_pipeline [2/4]: Skipping unreferenced species detection.")
  }

  # =========================================================================
  # Stage 3: Assign taxa via LLM
  # =========================================================================
  .msg("run_llm_pipeline [3/4]: Running assign_taxa_llm()...")

  result <- assign_taxa_llm(
    match_df              = match_df,
    context               = context,
    context_group         = context_group,
    llm_fn                = llm_fn,
    score_threshold       = score_threshold,
    top_n                 = top_n,
    rank_system           = rank_system,
    score_sharpness       = score_sharpness,
    unknown_lik_weight    = unknown_lik_weight,
    unreferenced_taxa     = unreferenced_result,
    known_present         = known_present,
    known_absent          = known_absent,
    absent_detection_prob = absent_detection_prob,
    taxa_per_call         = taxa_per_call,
    pause_seconds         = pause_seconds,
    prior_phi             = prior_phi,
    n_sims                = n_sims,
    verbose               = verbose
  )

  .msg(sprintf("  %d posterior rows, %d observations.",
               nrow(result), dplyr::n_distinct(result$observation_id)))

  # =========================================================================
  # Stages 4-6: Consensus + Empirical Bayes + Report (shared helper)
  # =========================================================================

  # Build species_reference for downranking
  species_reference <- if (inherits(unreferenced_result, "unreferenced_species_result")) {
    unreferenced_result
  } else {
    NULL
  }

  refined <- .run_consensus_and_report(
    result                = result,
    species_reference     = species_reference,
    cumulative_threshold  = cumulative_threshold,
    min_posterior         = min_posterior,
    posterior_col         = posterior_col,
    lookup_missing_taxonomy = lookup_missing_taxonomy,
    backbone_id           = backbone_id,
    rank_system           = rank_system,
    presence_multiplier   = presence_multiplier,
    n_sims                = n_sims,
    generate_report_flag  = generate_report,
    report_params         = report_params,
    unreferenced_result   = unreferenced_result,
    llm_fn                = llm_fn,
    verbose               = verbose,
    .msg                  = .msg,
    stage_prefix          = "run_llm_pipeline [4/4]"
  )

  .msg("run_llm_pipeline: done.")

  list(
    consensus    = refined$consensus,
    result       = refined$result,
    context      = context,
    unreferenced = unreferenced_result,
    report       = refined$report
  )
}
