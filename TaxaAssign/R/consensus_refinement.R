# Internal helper: shared consensus → empirical Bayes → report logic
# Used by run_bayesian_pipeline() and run_llm_pipeline()

#' @noRd
.run_consensus_and_report <- function(result,
                                       species_reference,
                                       cumulative_threshold,
                                       min_posterior,
                                       posterior_col,
                                       lookup_missing_taxonomy,
                                       backbone_id,
                                       rank_system,
                                       presence_multiplier,
                                       n_sims,
                                       generate_report_flag,
                                       report_params,
                                       unreferenced_result,
                                       llm_fn,
                                       verbose,
                                       .msg,
                                       stage_prefix) {

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
    presence_multiplier = presence_multiplier,
    n_sims              = n_sims
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
