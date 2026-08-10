# Internal helper: shared consensus -> empirical Bayes -> report logic
# Used by run_bayesian_pipeline() and run_llm_pipeline(), which are otherwise
# structurally identical from this point on -- everything upstream (how
# `result` was produced: TaxaLikely scores + TaxaExpect priors vs. an LLM
# call) differs between the two pipelines, but the three-step sequence below
# does not. Runs three steps in order: (1) an initial posterior_consensus()
# on the raw `result`; (2) update_prior_from_consensus() (empirical-Bayes
# refinement using observations resolved in step 1 as confirmation evidence
# for OTHER unresolved observations sharing a species), followed by a second
# posterior_consensus() on the refined result; (3) an optional
# generate_report() call. Every argument here is forwarded verbatim from the
# calling pipeline wrapper's own like-named parameter -- see
# run_bayesian_pipeline()'s and run_llm_pipeline()'s roxygen for what each
# one means; not documented a second time here to avoid the two copies
# drifting out of sync. `.msg`/`stage_prefix` let the two callers customize
# progress-message wording (e.g. "Bayesian pipeline" vs "LLM pipeline")
# without duplicating this function's body. `workflow` ("bayesian"/"llm") is
# passed straight through to generate_report()'s own `workflow` argument --
# each pipeline wrapper knows definitively which one it is, so there is no
# reason to let generate_report() guess from column presence here.
#' @noRd
.run_consensus_and_report <- function(result,
                                       species_reference,
                                       cumulative_threshold,
                                       min_posterior,
                                       posterior_col,
                                       lookup_missing_taxonomy,
                                       backbone_id,
                                       rank_system,
                                       confirmation_quantile,
                                       min_confirmation_confidence,
                                       n_sims,
                                       generate_report_flag,
                                       report_params,
                                       unreferenced_result,
                                       llm_fn,
                                       verbose,
                                       .msg,
                                       stage_prefix,
                                       workflow) {

  # --- First consensus ---
  .msg(sprintf("%s: Deriving consensus taxonomy...", stage_prefix))

  consensus <- posterior_consensus(
    result,
    cumulative_threshold    = cumulative_threshold,
    min_posterior           = min_posterior,
    posterior_col           = posterior_col,
    lookup_missing_taxonomy = lookup_missing_taxonomy,
    backbone_id             = backbone_id,
    rank_system             = rank_system,
    species_reference       = species_reference
  )

  # --- Empirical Bayes refinement + final consensus ---
  .msg(sprintf("%s: Empirical Bayes refinement + final consensus...", stage_prefix))

  result_updated <- update_prior_from_consensus(
    result, consensus,
    confirmation_quantile       = confirmation_quantile,
    min_confirmation_confidence = min_confirmation_confidence,
    n_sims                      = n_sims
  )

  consensus_final <- posterior_consensus(
    result_updated,
    cumulative_threshold    = cumulative_threshold,
    min_posterior           = min_posterior,
    posterior_col           = posterior_col,
    lookup_missing_taxonomy = lookup_missing_taxonomy,
    backbone_id             = backbone_id,
    rank_system             = rank_system,
    species_reference       = species_reference
  )

  n_resolved <- sum(consensus_final$is_resolved, na.rm = TRUE)
  .msg(sprintf("  %d / %d samples resolved to species level.",
               n_resolved, nrow(consensus_final)))

  # --- Optional report ---
  report <- NULL

  if (generate_report_flag) {
    .msg(sprintf("%s: Generating report...", stage_prefix))

    # generate_report() expects an unreferenced_species_result S3 object or NULL
    safe_unreferenced <- if (inherits(unreferenced_result, "unreferenced_species_result")) {
      unreferenced_result
    } else {
      NULL
    }

    report_args <- c(
      list(
        result              = result_updated,
        consensus           = consensus_final,
        unreferenced_result = safe_unreferenced,
        workflow            = workflow,
        llm_fn              = llm_fn,
        verbose             = verbose
      ),
      report_params
    )
    report <- do.call(generate_report, report_args)
  } else {
    .msg(sprintf("%s: Skipping report generation.", stage_prefix))
  }

  list(
    consensus = consensus_final,
    result    = result_updated,
    report    = report
  )
}
