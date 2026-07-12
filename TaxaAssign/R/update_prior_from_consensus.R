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
#' For each confirmed species, the `confirmation_quantile`-th quantile of
#' `consensus_posterior` across all confirming ("donor") observations is
#' computed; if that value clears `min_confirmation_confidence`, it
#' *substitutes* for `prior_mean` (never lowering it) in all *unresolved*
#' observations, and [compute_posterior()] is re-run for those observations
#' only.
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
#' @section Confirmation-quantile design (Session 149):
#' The previous design (a fixed `presence_multiplier`, e.g. x5) applied the
#' same boost regardless of how many observations confirmed a species or how
#' confident those confirmations were -- flagged as High priority in
#' `ecosystem_docs/STATISTICAL_COMPONENT_SOUNDNESS_REVIEW.md`. This design
#' instead ties the boost directly to the strength of the confirming
#' evidence:
#' \enumerate{
#'   \item For each confirmed species, take the `confirmation_quantile`-th
#'     quantile (default 0.9) of `consensus_posterior` across all resolved
#'     "donor" observations naming it. A high quantile behaves like a
#'     near-maximum for a small donor pool (rewarding one strong,
#'     high-quality confirmation the way a single excellent frame in an
#'     otherwise-poor camera-trap burst should), but -- unlike a plain
#'     maximum -- it converges to a *stable* population value as the donor
#'     pool grows, rather than drifting toward the degenerate ceiling of 1.0
#'     regardless of whether the evidence is real. This matters specifically
#'     for a pair of species a classifier cannot reliably separate: many
#'     weak, correlated (not independent) confirmations split between them
#'     would otherwise let a plain maximum -- or a probabilistic-OR
#'     combination across all of them -- manufacture unwarranted confidence
#'     for one or both, an effect that does not simply cancel out under
#'     renormalization once a third, unrelated candidate is also present.
#'   \item That quantile value is only used at all if it clears
#'     `min_confirmation_confidence` (default 0.8) -- a barely-resolved
#'     confirmation (e.g. just above whatever `posterior_consensus()`
#'     threshold marked it "resolved") should not be trusted to inject a
#'     large jump into an unrelated observation's prior.
#'   \item Even then, it only *replaces* `prior_mean` where it exceeds the
#'     existing value (never-demote) -- a species already well-supported by
#'     occurrence data is left alone.
#' }
#' This is still a threshold-based design (the quantile level and the
#' confidence floor are both free parameters), and it does not by itself
#' distinguish "confidence earned by genuinely strong evidence" from
#' "confidence attained despite thin/low-quality input" (e.g. a short,
#' low-coverage sequence read producing a spurious high-identity match) --
#' that would need a quality covariate on the underlying scores, a separate,
#' larger design question flagged for later rather than solved here.
#' A formally correct alternative would still be a Beta-Binomial
#' hierarchical model over species x observation within a site; this
#' quantile-based design is a more evidence-sensitive interim step than the
#' old fixed multiplier, not a replacement for that.
#'
#' @param result Dataframe. Output of [assign_taxa_llm()] or [compute_posterior()].
#'   Must contain: `observation_id`, `taxon_name`, `score_likelihood`,
#'   `score_likelihood_mean`, `score_likelihood_sd`, `prior_mean`. When
#'   `prior_alpha`/`prior_beta` (Beta shape parameters) are present, they are
#'   recomputed alongside `prior_mean` for boosted rows, preserving the
#'   original concentration (`alpha + beta`) so [compute_posterior()]'s Monte
#'   Carlo path stays consistent with the boosted point estimate -- fixes a
#'   latent inconsistency in the previous design, where only `prior_mean` was
#'   rescaled and a stale Beta shape could be sampled from if `n_sims > 0`.
#' @param consensus Dataframe. Output of [posterior_consensus()] run on `result`.
#'   Must contain: `observation_id`, `consensus_taxon`, `is_resolved`,
#'   `consensus_posterior`.
#' @param confirmation_quantile Numeric in (0, 1]. Quantile of confirming
#'   observations' `consensus_posterior` used as the candidate new
#'   `prior_mean` for a confirmed species. Default 0.9. `1` is equivalent to
#'   taking the maximum.
#' @param min_confirmation_confidence Numeric in \[0, 1\]. Minimum value the
#'   `confirmation_quantile` must clear for a species to be treated as
#'   confirmed at all. Default 0.8. Set to `0` to disable this gate entirely
#'   (every confirmed species is used, however weakly confirmed -- restores
#'   the previous design's lack of a confidence floor).
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
#'   confirmation_quantile        = 0.9,
#'   min_confirmation_confidence  = 0.8
#' )
#' }
#'
#' @importFrom cli cli_abort cli_inform
#' @importFrom dplyr bind_rows arrange desc n_distinct
#' @importFrom rlang .data
#' @importFrom stats quantile
#'
#' @export
update_prior_from_consensus <- function(result,
                                         consensus,
                                         confirmation_quantile       = 0.9,
                                         min_confirmation_confidence = 0.8,
                                         n_sims              = 0,
                                         spatial_group_map    = NULL) {

  # --- Input validation -------------------------------------------------------
  required_result <- c("observation_id", "taxon_name", "score_likelihood",
                        "score_likelihood_mean", "score_likelihood_sd", "prior_mean")
  missing_result <- setdiff(required_result, names(result))
  if (length(missing_result) > 0)
    cli::cli_abort("result missing required column(s): {.field {missing_result}}")

  required_consensus <- c("observation_id", "consensus_taxon", "is_resolved",
                           "consensus_posterior")
  missing_consensus <- setdiff(required_consensus, names(consensus))
  if (length(missing_consensus) > 0)
    cli::cli_abort("consensus missing required column(s): {.field {missing_consensus}}")

  if (!is.numeric(confirmation_quantile) || length(confirmation_quantile) != 1L ||
      is.na(confirmation_quantile) || confirmation_quantile <= 0 || confirmation_quantile > 1)
    cli::cli_abort("{.arg confirmation_quantile} must be a single number in (0, 1].")

  if (!is.numeric(min_confirmation_confidence) || length(min_confirmation_confidence) != 1L ||
      is.na(min_confirmation_confidence) ||
      min_confirmation_confidence < 0 || min_confirmation_confidence > 1)
    cli::cli_abort("{.arg min_confirmation_confidence} must be a single number in [0, 1].")

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
  # For each species named by >= 1 resolved ("donor") observation, take the
  # confirmation_quantile-th quantile of those donors' consensus_posterior --
  # not just the raw set of names -- so the eventual boost reflects how
  # strong (and how numerous) the confirming evidence actually was, not a
  # flat constant regardless of confirmation count/confidence (see @section
  # Confirmation-quantile design above).
  confirmation_pool <- consensus
  if (!is.null(grouped_ids)) {
    confirmation_pool <- consensus[consensus$observation_id %in% grouped_ids, , drop = FALSE]
  }
  donor_rows <- confirmation_pool[
    !is.na(confirmation_pool$consensus_taxon) &
      confirmation_pool$is_resolved &
      !is.na(confirmation_pool$consensus_posterior),
    ,
    drop = FALSE
  ]

  if (nrow(donor_rows) == 0L) {
    cli::cli_inform("No resolved species found in consensus; returning result unchanged.")
    return(result)
  }

  species_quantile <- tapply(
    donor_rows$consensus_posterior, donor_rows$consensus_taxon,
    function(x) stats::quantile(x, probs = confirmation_quantile, na.rm = TRUE, names = FALSE)
  )
  n_species_seen <- length(species_quantile)

  if (min_confirmation_confidence > 0) {
    species_quantile <- species_quantile[species_quantile >= min_confirmation_confidence]
  }

  confirmed_species <- names(species_quantile)

  if (length(confirmed_species) == 0L) {
    cli::cli_inform(
      "{n_species_seen} confirmed species found, but none reached the \\
      confirmation_quantile = {confirmation_quantile} threshold of \\
      min_confirmation_confidence = {min_confirmation_confidence}; \\
      returning result unchanged."
    )
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
    "Confirmed species from resolved observations: {length(confirmed_species)} \\
    (of {n_species_seen} seen, gated at min_confirmation_confidence = {min_confirmation_confidence})",
    "Unresolved observations to update: {length(unresolved_ids)}",
    "Confirmation quantile: {confirmation_quantile}"
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

  # --- Apply confirmation-quantile substitution (never-demote) ----------------
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

  candidate_prior <- unname(species_quantile[unresolved_rows$taxon_name[boost_mask]])
  old_prior        <- unresolved_rows$prior_mean[boost_mask]
  raise_mask       <- candidate_prior > old_prior   # never-demote: only raise
  n_raised         <- sum(raise_mask)

  cli::cli_inform(
    "{n_boosted} hypothesis row(s) across \\
    {dplyr::n_distinct(unresolved_rows$observation_id[boost_mask])} observation(s) \\
    matched a confirmed species; {n_raised} actually raised above their existing prior \\
    (others already met or exceeded the confirmation quantile)."
  )

  new_prior <- old_prior
  new_prior[raise_mask] <- candidate_prior[raise_mask]

  # Keep prior_alpha/prior_beta consistent with the boosted prior_mean, when
  # present, by preserving the original concentration (alpha + beta) and
  # recentering it at the new mean -- otherwise compute_posterior()'s Monte
  # Carlo path (if n_sims > 0) would sample from a stale Beta shape while the
  # point estimate uses the new mean (a latent inconsistency in the previous
  # design, flagged during the Session 149 soundness-review walk-through).
  has_beta_cols <- all(c("prior_alpha", "prior_beta") %in% names(unresolved_rows))
  if (has_beta_cols) {
    old_alpha <- unresolved_rows$prior_alpha[boost_mask]
    old_beta  <- unresolved_rows$prior_beta[boost_mask]
    phi       <- old_alpha + old_beta
    new_alpha <- old_alpha
    new_beta  <- old_beta
    new_alpha[raise_mask] <- new_prior[raise_mask] * phi[raise_mask]
    new_beta[raise_mask]  <- (1 - new_prior[raise_mask]) * phi[raise_mask]
    unresolved_rows$prior_alpha[boost_mask] <- new_alpha
    unresolved_rows$prior_beta[boost_mask]  <- new_beta
  }

  unresolved_rows$prior_mean[boost_mask] <- new_prior

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
    confirmation_quantile       = confirmation_quantile,
    min_confirmation_confidence = min_confirmation_confidence,
    n_sims                      = n_sims
  )
  out
}
