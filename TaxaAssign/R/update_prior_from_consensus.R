# update_prior_from_consensus.R
# TaxaAssign package
#
# Uses confident consensus assignments from one pass of posterior_consensus() to
# boost priors for confirmed species in unresolved observations, then re-runs
# compute_posterior() on those observations only.


#' Update Priors from Consensus Assignments and Recompute Posteriors
#'
#' A one-pass empirical Bayes refinement step. Takes the output of
#' [posterior_consensus()] and uses species-level consensus assignments
#' (where `is_resolved = TRUE`) as evidence of true presence at the site.
#' The `prior_mean` for each confirmed species is multiplied by
#' `presence_multiplier` in all *unresolved* observations, then
#' [compute_posterior()] is re-run for those observations only.
#'
#' **Why only unresolved observations?** Resolved observations already have a clear
#' winner; updating their priors and re-running would not change the conclusion
#' and risks overconfidence. Unresolved observations are the ones that may benefit
#' from the additional site-level presence information.
#'
#' **Avoiding circularity:** Priors for observation B are updated using confirmations
#' from *other* observations. An observation's own posterior never feeds back into its own
#' prior.
#'
#' **Multi-member vs. single-observation spatial groups:** this refinement is
#' only valid when other observations genuinely share a local species pool
#' with the one being updated -- i.e. they share a spatial group (a drawn
#' bounding box; see `TaxaMatch::group_observations_by_bbox()`). For a
#' single-observation spatial group (whether because it was submitted alone,
#' or because it fell outside every user-drawn box and was placed in its own
#' group rather than dropped), no other observation shares its local species
#' pool, so another observation's confirmed presence says nothing about it and
#' must not be used. Supply `spatial_group_map` to enforce this: only
#' observations whose `spatial_group_id` is shared with at least one other
#' observation are used as evidence sources or receive a prior update;
#' observations in a single-observation spatial group are always returned
#' unchanged, exactly like already-resolved observations.
#'
#' **Multiplier choice:** A multiplier raises the prior proportionally, preserving
#' the relative ranking of other hypotheses before renormalization. The default
#' of 5 is a moderate nudge: a confirmed species starting at 10\% prior moves
#' to roughly 33\% after normalization. Increase to 10--20 for datasets where
#' species identity is highly consistent within a site (e.g. eDNA from a single
#' water body). Decrease to 2 for datasets with high spatial heterogeneity.
#' A formally correct alternative would be a Beta-Binomial hierarchical model
#' over species x observation within a site, but the multiplier approximation is
#' adequate in practice.
#'
#' @param result Dataframe. Output of [assign_taxa_llm()] or [compute_posterior()].
#'   Must contain: `observation_id`, `taxon_name`, `score_likelihood`,
#'   `score_likelihood_mean`, `score_likelihood_sd`, `prior_mean`.
#' @param consensus Dataframe. Output of [posterior_consensus()] run on `result`.
#'   Must contain: `observation_id`, `consensus_taxon`, `is_resolved`.
#' @param presence_multiplier Numeric > 1. Factor by which `prior_mean` is
#'   multiplied for confirmed species in unresolved observations. Default 5.
#' @param n_sims Integer. Passed to [compute_posterior()] for the re-run.
#'   Default 0 (point estimates only, fast). Set to 1000 to propagate
#'   uncertainty — match the value used in the original run.
#' @param spatial_group_map Dataframe with `observation_id` and
#'   `spatial_group_id` columns (e.g. from
#'   `TaxaMatch::group_observations_by_bbox()`), optional. When supplied, only
#'   observations whose `spatial_group_id` is shared with at least one other
#'   observation can contribute confirmed species or receive a prior update;
#'   observations in a single-observation spatial group (a singleton
#'   `spatial_group_id` -- there is no separate naming convention for these,
#'   see `group_observations_by_bbox()`) are always returned unchanged.
#'   Default `NULL` (no group-based restriction — all observations
#'   participate, matching this function's original behaviour).
#'
#' @return The full posterior dataframe with the same structure as `result`.
#'   Resolved observations are returned unchanged. Unresolved observations in
#'   a multi-member spatial group (see `spatial_group_map`) have updated
#'   `prior_mean` and freshly computed posterior columns
#'   (`posterior_point_est`, `posterior_mean`, `posterior_sd`,
#'   `confidence_score`). Unresolved observations in a single-observation
#'   spatial group are returned unchanged, same as resolved ones. Sorted by
#'   `observation_id` then descending `posterior_point_est`.
#'
#' @seealso [posterior_consensus()], [compute_posterior()], [assign_taxa_llm()]
#'
#' @examples
#' \dontrun{
#' result_updated <- update_prior_from_consensus(
#'   result, consensus,
#'   presence_multiplier = 5
#' )
#' }
#'
#' @importFrom cli cli_abort cli_inform
#' @importFrom dplyr bind_rows arrange desc n_distinct
#' @importFrom rlang .data
#'
#' @export
update_prior_from_consensus <- function(result,
                                         consensus,
                                         presence_multiplier = 5,
                                         n_sims              = 0,
                                         spatial_group_map    = NULL) {

  # --- Input validation -------------------------------------------------------
  required_result <- c("observation_id", "taxon_name", "score_likelihood",
                        "score_likelihood_mean", "score_likelihood_sd", "prior_mean")
  missing_result <- setdiff(required_result, names(result))
  if (length(missing_result) > 0)
    cli::cli_abort("result missing required column(s): {.field {missing_result}}")

  required_consensus <- c("observation_id", "consensus_taxon", "is_resolved")
  missing_consensus <- setdiff(required_consensus, names(consensus))
  if (length(missing_consensus) > 0)
    cli::cli_abort("consensus missing required column(s): {.field {missing_consensus}}")

  if (!is.numeric(presence_multiplier) || length(presence_multiplier) != 1L ||
      presence_multiplier <= 1)
    cli::cli_abort("{.arg presence_multiplier} must be a single number > 1.")

  # --- Resolve multi-member spatial groups from spatial_group_map, if supplied ----
  # Only observations that share a spatial_group_id with >=1 other observation
  # may act as evidence sources or receive an update -- an observation in a
  # single-observation spatial group's own posterior never says anything
  # about an unrelated one.
  grouped_ids <- NULL
  if (!is.null(spatial_group_map)) {
    required_group <- c("observation_id", "spatial_group_id")
    missing_group  <- setdiff(required_group, names(spatial_group_map))
    if (length(missing_group) > 0)
      cli::cli_abort("spatial_group_map missing required column(s): {.field {missing_group}}")

    group_sizes    <- table(spatial_group_map$spatial_group_id)
    shared_groups  <- names(group_sizes)[group_sizes >= 2L]
    grouped_ids    <- unique(spatial_group_map$observation_id[spatial_group_map$spatial_group_id %in% shared_groups])

    n_singleton <- dplyr::n_distinct(spatial_group_map$observation_id) - length(grouped_ids)
    cli::cli_inform(
      "spatial_group_map supplied: {length(grouped_ids)} observation(s) in a multi-member \\
      spatial group are eligible for the consensus prior update; {n_singleton} observation(s) \\
      in a single-observation spatial group will be skipped (returned unchanged)."
    )
  }

  # --- Extract confirmed species (resolved across any OTHER observation sharing a spatial group) ---
  confirmation_pool <- consensus
  if (!is.null(grouped_ids)) {
    confirmation_pool <- consensus[consensus$observation_id %in% grouped_ids, , drop = FALSE]
  }
  confirmed_species <- unique(confirmation_pool$consensus_taxon[
    !is.na(confirmation_pool$consensus_taxon) & confirmation_pool$is_resolved
  ])

  if (length(confirmed_species) == 0L) {
    cli::cli_inform("No resolved species found in consensus; returning result unchanged.")
    return(result)
  }

  # --- Identify unresolved observations ----------------------------------------
  unresolved_ids <- consensus$observation_id[
    is.na(consensus$consensus_taxon) | !consensus$is_resolved
  ]

  if (!is.null(grouped_ids)) {
    # Unresolved observations in a single-observation spatial group are left
    # unchanged, same as resolved ones -- they are not eligible for this
    # refinement (see @details).
    unresolved_ids <- intersect(unresolved_ids, grouped_ids)
  }

  if (length(unresolved_ids) == 0L) {
    cli::cli_inform(
      if (!is.null(grouped_ids))
        "No unresolved observations in a multi-member spatial group; returning result unchanged."
      else
        "All observations already resolved; returning result unchanged."
    )
    return(result)
  }

  cli::cli_inform(c(
    "Confirmed species from resolved observations: {length(confirmed_species)}",
    "Unresolved observations to update: {length(unresolved_ids)}",
    "Prior multiplier: {presence_multiplier}x"
  ))

  # --- Split result -----------------------------------------------------------
  resolved_rows   <- result[!result$observation_id %in% unresolved_ids, ]
  unresolved_rows <- result[ result$observation_id %in% unresolved_ids, ]

  # Tag rows so posterior_consensus() can propagate these to its output.
  # v1 columns carry the pass-1 assignment for every row; posterior_consensus()
  # uses them to populate consensus_taxon_v1, consensus_rank_v1, and taxon_changed.
  v1 <- consensus[, c("observation_id", "consensus_taxon", "consensus_rank")]
  names(v1)[2:3] <- c("consensus_taxon_v1", "consensus_rank_v1")

  resolved_rows   <- merge(resolved_rows,   v1, by = "observation_id", all.x = TRUE)
  unresolved_rows <- merge(unresolved_rows, v1, by = "observation_id", all.x = TRUE)

  resolved_rows$prior_updated   <- FALSE
  unresolved_rows$prior_updated <- TRUE

  # --- Apply multiplier -------------------------------------------------------
  boost_mask <- unresolved_rows$taxon_name %in% confirmed_species
  n_boosted  <- sum(boost_mask)

  if (n_boosted == 0L) {
    cli::cli_inform(
      "None of the {length(confirmed_species)} confirmed species appear as \\
      hypotheses in the {length(unresolved_ids)} unresolved observation(s); \\
      returning result unchanged."
    )
    return(result)
  }

  cli::cli_inform(
    "Boosting {n_boosted} hypothesis row(s) across \\
    {dplyr::n_distinct(unresolved_rows$observation_id[boost_mask])} observation(s)."
  )

  unresolved_rows$prior_mean[boost_mask] <-
    unresolved_rows$prior_mean[boost_mask] * presence_multiplier

  # --- Recompute posteriors for unresolved observations ------------------------
  # Drop existing posterior columns so compute_posterior() produces fresh values
  post_cols       <- intersect(
    c("posterior_point_est", "posterior_mean", "posterior_sd", "confidence_score"),
    names(unresolved_rows)
  )
  unresolved_rows <- unresolved_rows[,
    setdiff(names(unresolved_rows), post_cols), drop = FALSE
  ]

  updated_rows <- compute_posterior(unresolved_rows, n_sims = n_sims)

  # --- Recombine and sort -----------------------------------------------------
  out <- dplyr::bind_rows(resolved_rows, updated_rows) |>
    dplyr::arrange(.data$observation_id, dplyr::desc(.data$posterior_point_est))

  attr(out, "report_params") <- list(
    presence_multiplier = presence_multiplier,
    n_sims              = n_sims
  )
  out
}
