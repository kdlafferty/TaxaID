# update_prior_from_consensus.R
# TaxaAssign package
#
# Uses confident consensus assignments from one pass of posterior_consensus() to
# boost priors for confirmed species in unresolved observations, then re-runs
# compute_posterior() on those observations only.


#' Update Priors from Consensus Assignments and Recompute Posteriors
#'
#' A one-pass empirical Bayes refinement step. Every observation's posterior
#' support for a species is treated as fractional evidence of site-level
#' presence (soft assignment -- no confirmation threshold), aggregated with a
#' leave-one-out, power-prior-discounted mass, and used to move unresolved
#' observations' priors smoothly toward a support-weighted confirmation
#' quantile (never lowering them); [compute_posterior()] is then re-run for
#' those observations only. See the \emph{Soft confirmation} section for the
#' design and its literature grounding.
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
#' @section Soft confirmation (2026-08-28 redesign, replaces the hard gate):
#' The previous design counted an observation as a "donor" only when it
#' resolved a species with `consensus_posterior >=` a threshold (0.8) -- hard
#' assignment in the sense of classification EM (Celeux & Govaert 1992,
#' \emph{Computational Statistics & Data Analysis} 14:315-332). That made the
#' dataset-level output discontinuous in per-observation inputs: one marginal
#' competitor holding every observation of a species just below the bar meant
#' zero donors anywhere (a real case: 78 yellow-perch observations at ~0.69
#' each -- no confirmation, dataset-wide). Now every observation's best
#' posterior for a species contributes fractionally (soft assignment, the
#' one-iteration analog of a multi-scale occupancy update -- Dorazio &
#' Erickson 2018, \emph{Molecular Ecology Resources} 18:368-380):
#' \enumerate{
#'   \item Per species, support mass = the sum over observations of that
#'     observation's best posterior for it; per target row, the target
#'     observation's own support is subtracted (leave-one-out -- no
#'     self-confirmation).
#'   \item The mass is discounted by `confirmation_discount` (a0): same-site
#'     observations share water, DNA pool, and reference biases, so they are
#'     not independent confirmations. Raising auxiliary evidence to a power
#'     a0 in \[0, 1\] is the standard power-prior discount (Ibrahim & Chen
#'     2000, \emph{Statistical Science} 15:46-60); multiplying the
#'     pseudo-observation mass by a0 is its counting equivalent. The default
#'     0.25 treats ~4 correlated observations as worth 1 independent one.
#'   \item The discounted mass enters a smooth saturation `m/(1+m)` that
#'     scales the never-demote move toward the support-weighted
#'     `confirmation_quantile` of per-observation support (occurrence-scale
#'     rescale unchanged, see below). No thresholds anywhere: the update is
#'     continuous in every input.
#'   \item Presence-mixture rows (`prior_mix_w` etc.) are updated in w
#'     itself -- cross-observation support IS evidence about presence -- via
#'     a pseudo-observation update weighted by `prior_mix_p_conc`, with the
#'     Beta summary re-moment-matched. Never demoted.
#' }
#'
#' @section Historical: confirmation-quantile design (Session 149, superseded):
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
#' @section Rescaling onto the occurrence scale (2026-07-30):
#' `consensus_posterior` is P(hypothesis | evidence) *within one
#' observation* -- a probability over competing hypotheses. `prior_mean`,
#' when sourced from `TaxaExpect`, is a **compositional share of the local
#' record pool** (`theta_mean`, confirmed by reading
#' `TaxaExpect::prepare_model_dataframe()`'s binomial response directly:
#' `n_species / n_total_at_site`, one record attributable to exactly one
#' taxon). These are different sample spaces, and substituting one for the
#' other only ever inflates (never-demote guarantees it). Measured on real
#' Mugu data: 220 of 2540 rows were boosted, and all 220 landed in
#' \[0.951, 1.0\] -- every one overshooting the real occurrence-scale
#' ceiling (`max(theta_mean)` across every locally modelled taxon,
#' 0.0865 on that dataset) by 11x to 1000x.
#'
#' When a `theta_mean` column is present on `result`, the substitution is
#' rescaled onto that ceiling instead of being used directly:
#' `prior_new <- max(prior_old, q * max(result$theta_mean, na.rm = TRUE))`,
#' where `q` is the confirmation-quantile value described above. This keeps
#' the confirmation-quantile logic and the never-demote guard unchanged --
#' only the target scale moves -- so a stronger/more numerous confirmation
#' (higher `q`) still produces a stronger boost, bounded by the model's own
#' observed maximum share rather than substituting a foreign-scale
#' constant. When `result` has no `theta_mean` column (e.g. LLM-pathway
#' priors from [assign_taxa_llm()], which are not occurrence-share-based to
#' begin with), the previous direct-substitution behavior is used
#' unchanged -- the units mismatch this section fixes is specific to
#' occurrence-model-sourced priors.
#'
#' @section Confirmed without an occurrence record (2026-07-30):
#' A taxon can be confidently identified elsewhere in the dataset while
#' having no occurrence record at all (`theta_mean` `NA` for every row
#' naming it) -- e.g. a real Mugu case, *Oncorhynchus mykiss*, which has no
#' row in `taxaexpect_priors` at all (see
#' `[[project_urolophus_synonym_join_bug]]` in the project memory system --
#' this is a known, separate upstream join gap, not a sign the species is
#' actually rare). Such a row still gets boosted (the confirmation is real
#' identification evidence, worth keeping) but is flagged via a new
#' `confirmed_without_occurrence_record` column rather than silently
#' presented as occurrence-grounded. Boosting is *not* suppressed for these
#' rows: gating on occurrence-record presence would currently punish
#' exactly the taxa the join gap affects (whole families, in the Mugu
#' salmonid case), which are neither rare nor implausible -- only
#' undercounted by an unrelated bug. Revisit suppression once that join gap
#' is fixed.
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
#' @param confirmation_discount Numeric in \[0, 1\]. Power-prior discount a0
#'   applied to the cross-observation support mass (0.25 default: ~4
#'   correlated observations carry the weight of 1 independent one; 0
#'   disables the update entirely; 1 treats every observation as fully
#'   independent -- almost certainly too strong for same-site eDNA). See the
#'   \emph{Soft confirmation} section.
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
#' @return The full posterior dataframe with the same structure as `result`,
#'   plus one new column, `confirmed_without_occurrence_record` (logical,
#'   `FALSE` unless set `TRUE` -- see @section Confirmed without an
#'   occurrence record). Resolved observations are returned unchanged.
#'   Unresolved observations in a multi-member spatial group (see
#'   `spatial_group_map`) have updated `prior_mean` and freshly computed
#'   posterior columns (`posterior_point_est`, `posterior_mean`,
#'   `posterior_sd`, `confidence_score`). Unresolved observations in a
#'   single-observation spatial group are returned unchanged, same as
#'   resolved ones. Sorted by `observation_id` then descending
#'   `posterior_point_est`.
#'
#' @seealso [posterior_consensus()], [compute_posterior()], [assign_taxa_llm()]
#'
#' @examples
#' \dontrun{
#' result_updated <- update_prior_from_consensus(
#'   result, consensus,
#'   confirmation_quantile  = 0.9,
#'   confirmation_discount  = 0.25
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
                                         confirmation_discount       = 0.25,
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

  if (!is.numeric(confirmation_discount) || length(confirmation_discount) != 1L ||
      is.na(confirmation_discount) ||
      confirmation_discount < 0 || confirmation_discount > 1)
    cli::cli_abort("{.arg confirmation_discount} must be a single number in [0, 1].")

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

  # --- Soft confirmation evidence (2026-08-28 redesign, D7) -------------------
  # Replaces the hard donor gate (a species counted as confirmed only when some
  # observation resolved it with consensus_posterior >= a threshold). Hard
  # assignment is classification EM (Celeux & Govaert 1992, Computational
  # Statistics & Data Analysis 14:315-332) and produced real cliffs: one
  # marginal competitor holding every observation just under the bar meant
  # ZERO donors dataset-wide (the GreatLakes2023 yellow-perch case -- 78
  # observations at ~0.69 each, no confirmation anywhere). The soft version
  # aggregates EVERY observation's posterior support for a species as
  # fractional evidence of site-level presence -- the one-iteration analog of
  # a multi-scale occupancy update (Dorazio & Erickson 2018, Molecular Ecology
  # Resources 18:368-380) -- discounted by `confirmation_discount` (a0):
  # observations from one site share water, DNA pool, and reference biases, so
  # they are not independent confirmations; raising auxiliary evidence to a
  # power a0 in [0,1] is the standard power-prior discount (Ibrahim & Chen
  # 2000, Statistical Science 15:46-60), and multiplying the pseudo-
  # observation mass by a0 is its counting equivalent here. The default
  # a0 = 0.25 treats ~4 correlated observations as worth 1 independent one.
  post_col <- if ("posterior_point_est" %in% names(result)) "posterior_point_est" else "posterior_mean"
  support_pool <- result[!is.na(result$taxon_name) & !is.na(result[[post_col]]), , drop = FALSE]
  if (!is.null(grouped_ids)) {
    support_pool <- support_pool[support_pool$observation_id %in% grouped_ids, , drop = FALSE]
  }
  if (nrow(support_pool) == 0L) {
    cli::cli_inform("No named posterior support anywhere; returning result unchanged.")
    return(result)
  }

  # Per (observation, species) support: the best posterior that observation
  # gives the species (multi-site/duplicate candidate rows collapse to one).
  sup_key     <- paste(support_pool$observation_id, support_pool$taxon_name, sep = "\r")
  obs_support <- tapply(support_pool[[post_col]], sup_key, max)
  key_split   <- strsplit(names(obs_support), "\r", fixed = TRUE)
  sup_taxon   <- vapply(key_split, function(k) k[[2L]], character(1))
  sup_p       <- as.numeric(obs_support)

  species_mass <- tapply(sup_p, sup_taxon, sum)

  # Support-weighted confirmation-quantile of per-observation support: the
  # target level the substitution moves toward. Weighting by the support
  # itself keeps a handful of genuine detections from being drowned by a sea
  # of near-zero candidacies of the same species.
  .weighted_quantile <- function(x, w, prob) {
    o <- order(x); x <- x[o]; w <- w[o]
    cw <- cumsum(w) / sum(w)
    x[which(cw >= prob)[1L]]
  }
  species_target <- vapply(split(seq_along(sup_p), sup_taxon), function(idx) {
    .weighted_quantile(sup_p[idx], sup_p[idx], confirmation_quantile)
  }, numeric(1))

  # --- Identify unresolved observations ----------------------------------------
  unresolved_ids <- consensus$observation_id[
    is.na(consensus$consensus_taxon) | !consensus$is_resolved
  ]
  if (!is.null(grouped_ids)) {
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
    "Soft confirmation: {length(species_mass)} species carry posterior support \\
    across the dataset (power-prior discount a0 = {confirmation_discount}).",
    "Unresolved observations to update: {length(unresolved_ids)}",
    "Confirmation quantile (support-weighted): {confirmation_quantile}"
  ))

  # --- Split result -----------------------------------------------------------
  resolved_rows   <- result[!result$observation_id %in% unresolved_ids, ]
  unresolved_rows <- result[ result$observation_id %in% unresolved_ids, ]

  v1 <- consensus[, c("observation_id", "consensus_taxon", "consensus_rank")]
  names(v1)[2:3] <- c("consensus_taxon_v1", "consensus_rank_v1")
  resolved_rows   <- merge(resolved_rows,   v1, by = "observation_id", all.x = TRUE)
  unresolved_rows <- merge(unresolved_rows, v1, by = "observation_id", all.x = TRUE)
  # rep() guards the all-unresolved case: a scalar assignment onto a 0-row
  # base data frame errors ("replacement has 1 row, data has 0")
  resolved_rows$prior_updated   <- rep(FALSE, nrow(resolved_rows))
  unresolved_rows$prior_updated <- rep(TRUE,  nrow(unresolved_rows))
  resolved_rows$confirmed_without_occurrence_record   <- rep(FALSE, nrow(resolved_rows))
  unresolved_rows$confirmed_without_occurrence_record <- rep(FALSE, nrow(unresolved_rows))

  # --- Leave-one-out, discounted, saturating evidence per row ------------------
  boost_mask <- unresolved_rows$taxon_name %in% names(species_mass)
  row_key    <- paste(unresolved_rows$observation_id, unresolved_rows$taxon_name, sep = "\r")
  own_p      <- as.numeric(obs_support[row_key])
  own_p[is.na(own_p)] <- 0
  mass_row   <- unname(species_mass[unresolved_rows$taxon_name]) - own_p
  mass_row[is.na(mass_row) | mass_row < 0] <- 0
  m_disc     <- confirmation_discount * mass_row
  s_sat      <- m_disc / (1 + m_disc)   # smooth saturation in [0, 1): no cliffs

  if (!any(boost_mask & m_disc > 0)) {
    cli::cli_inform(
      "No unresolved hypothesis has any cross-observation support after the \\
      leave-one-out discount; returning result unchanged."
    )
    return(result)
  }

  # Occurrence-scale rescale (see @section Rescaling onto the occurrence scale)
  has_theta <- "theta_mean" %in% names(result)
  theta_ceiling <- if (has_theta) max(result$theta_mean, na.rm = TRUE) else NA_real_
  if (has_theta && (!is.finite(theta_ceiling) || theta_ceiling <= 0)) {
    has_theta <- FALSE
  }
  q_target <- unname(species_target[unresolved_rows$taxon_name])
  candidate_prior <- if (has_theta) q_target * theta_ceiling else q_target

  mix_cols_all <- c("prior_mix_w", "prior_mix_theta_present", "prior_mix_theta_absent")
  is_mix_row <- if (all(mix_cols_all %in% names(unresolved_rows))) {
    !is.na(unresolved_rows$prior_mix_w) &
      !is.na(unresolved_rows$prior_mix_theta_present) &
      !is.na(unresolved_rows$prior_mix_theta_absent)
  } else {
    rep(FALSE, nrow(unresolved_rows))
  }

  # --- Non-mixture rows: soft, never-demote substitution -----------------------
  old_prior <- unresolved_rows$prior_mean
  soft_gain <- pmax(candidate_prior - old_prior, 0) * s_sat
  soft_gain[!boost_mask | is_mix_row | is.na(soft_gain)] <- 0
  raise_mask <- soft_gain > 0
  new_prior  <- old_prior + soft_gain

  cli::cli_inform(c(
    "{sum(boost_mask)} hypothesis row(s) carry cross-observation support; \\
    {sum(raise_mask)} raised above their existing prior (smoothly, by the \\
    saturating discounted mass -- others already met their support-weighted target).",
    if (has_theta)
      "Substitution rescaled onto the occurrence scale (ceiling = {signif(theta_ceiling, 3)})."
    else
      "No theta_mean column on result -- using the support-weighted quantile directly."
  ))

  if (has_theta && any(raise_mask)) {
    no_record_raised <- raise_mask & is.na(unresolved_rows$theta_mean)
    if (any(no_record_raised)) {
      unresolved_rows$confirmed_without_occurrence_record[no_record_raised] <- TRUE
      cli::cli_inform(
        "{sum(no_record_raised)} raised row(s) have NO occurrence record at all \\
        (theta_mean NA) -- flagged via confirmed_without_occurrence_record, not suppressed."
      )
    }
  }

  if (any(raise_mask)) {
    unresolved_rows$prior_mean[raise_mask] <- new_prior[raise_mask]
    if (all(c("prior_alpha", "prior_beta") %in% names(unresolved_rows))) {
      # keep alpha/beta consistent with the new mean, preserving concentration;
      # clamp away from [0,1] so compute_posterior() never sees beta = 0
      phi     <- unresolved_rows$prior_alpha[raise_mask] + unresolved_rows$prior_beta[raise_mask]
      clamped <- pmin(pmax(new_prior[raise_mask], 1e-9), 1 - 1e-9)
      unresolved_rows$prior_alpha[raise_mask] <- clamped * phi
      unresolved_rows$prior_beta[raise_mask]  <- (1 - clamped) * phi
    }
  }

  # --- Mixture rows: cross-observation support updates prior_mix_w -------------
  # For a presence mixture, confirmation IS evidence about presence: the
  # discounted support mass enters w's own pseudo-observation update
  # (successes at the support mass itself), p_conc grows by the same mass, and
  # the Beta summary is re-moment-matched to the updated two-point mixture.
  # This replaces the interim hard rule that cleared the mixture outright on a
  # thresholded confirmation.
  mixable <- boost_mask & is_mix_row & m_disc > 0
  if (any(mixable)) {
    pc  <- unresolved_rows$prior_mix_p_conc[mixable]
    pc[is.na(pc)] <- 1
    w0  <- unresolved_rows$prior_mix_w[mixable]
    md  <- m_disc[mixable]
    w1  <- (pc * w0 + md) / (pc + md)
    # Cap at the construction-time veto bound (2026-09-05 critical-fix-review
    # finding B2): the update above is level-blind and can be pushed past the
    # bound by a wide, low-grade blocker's correlated cross-observation
    # support alone (worked example in the review: w 0.05 -> 0.33 against a
    # ~0.05 bound, purely from volume, with the genuinely-observed native
    # gaining nothing from the same pass). This is the "at minimum" floor the
    # review names -- NOT the deeper level-aware redesign it also describes
    # (weighting the update by the species' own support-weighted quantile, or
    # scaling trial count by n_observations), which is a real statistical
    # design choice left for a deliberate decision, not made here. NA bound
    # (a prior_mix_* table built before this column existed, or a row with no
    # computable bound) leaves w1 uncapped, unchanged from before this fix.
    n_capped <- 0L
    if ("prior_mix_veto_bound" %in% names(unresolved_rows)) {
      bound <- unresolved_rows$prior_mix_veto_bound[mixable]
      capped <- !is.na(bound) & w1 > bound
      n_capped <- sum(capped)
      if (n_capped > 0L) w1[capped] <- bound[capped]
    }
    thp <- unresolved_rows$prior_mix_theta_present[mixable]
    tha <- unresolved_rows$prior_mix_theta_absent[mixable]
    th1 <- tha + (thp - tha) * w1
    unresolved_rows$prior_mix_w[mixable]      <- w1
    unresolved_rows$prior_mix_p_conc[mixable] <- pc + md
    unresolved_rows$prior_mean[mixable]       <- th1
    if (all(c("prior_alpha", "prior_beta") %in% names(unresolved_rows))) {
      # Reproduce TaxaExpect::apply_undetected_evidence()'s own v_mix formula,
      # not just its (thp-tha) term -- 2026-09-05 critical-fix-review finding
      # A4. Blend-mode rows carry real within-state variance at the present/
      # absent anchors (prior_mix_var_present/_absent); omitting them here
      # silently over-concentrated the refreshed Beta for those rows (curve
      # rows are unaffected -- their states are points, so both are exactly
      # 0 and this reduces to the original formula). Default 0 for a
      # prior_mix_* table built before these two columns existed.
      var_p <- if ("prior_mix_var_present" %in% names(unresolved_rows)) {
        v <- unresolved_rows$prior_mix_var_present[mixable]; v[is.na(v)] <- 0; v
      } else rep(0, sum(mixable))
      var_a <- if ("prior_mix_var_absent" %in% names(unresolved_rows)) {
        v <- unresolved_rows$prior_mix_var_absent[mixable]; v[is.na(v)] <- 0; v
      } else rep(0, sum(mixable))
      v_mix <- w1 * (1 - w1) * (thp - tha)^2 + w1 * var_p + (1 - w1) * var_a
      ok    <- is.finite(v_mix) & v_mix > 0
      if (any(ok)) {
        ne  <- pmax(th1[ok] * (1 - th1[ok]) / v_mix[ok] - 1, 1e-3)
        idx <- which(mixable)[ok]
        unresolved_rows$prior_alpha[idx] <- th1[ok] * ne
        unresolved_rows$prior_beta[idx]  <- (1 - th1[ok]) * ne
      }
    }
    cli::cli_inform(c(
      "{sum(mixable)} presence-mixture row(s) had prior_mix_w updated by the \\
      discounted cross-observation support (presence evidence, never demoted).",
      "i" = "sum(prior_mix_w) over these rows: {signif(sum(w0), 3)} -> \\
      {signif(sum(w1), 3)}. apply_undetected_evidence()'s own budget audit \\
      (sum(w) vs. chao_missing) describes the priors AS BUILT, not as the \\
      posterior actually used -- this is the post-refinement counterpart \\
      (2026-09-05 critical-fix-review finding A3), purely informational.",
      if (n_capped > 0L)
        "!" = "{n_capped} row(s) would have updated PAST their own veto bound \\
        (finding B2) -- capped there instead. This is a floor against runaway \\
        correlated-confirmation accumulation, not a fix to the update rule \\
        itself; see that finding for the deeper level-aware redesign this \\
        stands in for."
    ))
  }


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

  # Merge onto (not overwrite) any report_params already attached to `result`
  # -- e.g. assign_taxa_llm()'s score_sharpness/unknown_lik_weight/
  # score_threshold/top_n. This function's own compute_posterior() call
  # above already set attr(updated_rows, "report_params") <- list(n_sims=...)
  # (compute_posterior()'s own, narrower default), which would otherwise
  # silently discard those upstream values for every real
  # run_llm_pipeline() call (it always calls this function), making
  # generate_report()'s LLM Methods text fall back to hardcoded defaults
  # (e.g. score_sharpness = 0.1) instead of the values actually used --
  # found via code review, not a symptom anyone had reported yet.
  prior_params <- attr(result, "report_params")
  attr(out, "report_params") <- utils::modifyList(
    if (is.null(prior_params)) list() else prior_params,
    list(
      confirmation_quantile       = confirmation_quantile,
      confirmation_discount       = confirmation_discount,
      n_sims                      = n_sims
    )
  )
  out
}
