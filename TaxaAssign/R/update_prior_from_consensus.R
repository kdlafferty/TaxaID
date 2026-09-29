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
#' **Evidence is group-local.** Priors are spatially local, so the update is
#' too: a hypothesis is confirmed only by observations that share one of its
#' observation's evidence groups. The grouping is the caller's choice, given as
#' a `detections` table and the `group_cols` that define a group. The default
#' is the sample (tube), the most conservative choice: only the same tube's
#' other detections, including its other markers' libraries, count as
#' confirmation. A study that treats every tube at a site as one species pool
#' passes `group_cols = "site"`; one that also separates seasons passes
#' `group_cols = c("site", "season")`. The function attaches no meaning to the
#' column names; it groups by whatever it is given. An observation whose every
#' group is a singleton has nobody to borrow from and is returned unchanged,
#' exactly like an already-resolved observation. See the \emph{Group-local
#' evidence} section for how an observation in several groups is handled.
#'
#' @section Group-local evidence:
#' The posterior grain is observation x taxon, and one observation (for
#' example an ESV) is usually detected in several groups: many tubes, or
#' several sites. For each hypothesis row the update is computed separately in
#' every group its observation belongs to, using only that group's members:
#' the support mass, the leave-one-out subtraction of the row's own support,
#' the saturating discounted mass, the support-weighted confirmation target and
#' the occurrence-scale ceiling are all per group. The row then receives the
#' MEAN of its per-group gains over all k of its groups, singleton groups
#' included (they contribute zero). Averaging, rather than summing, means no
#' row is raised by more than its single best-supported group could raise it,
#' and evidence from one group of k is diluted to 1/k: an ESV found at 23
#' sites whose species is supported at only one of them receives 1/23 of that
#' site's gain. This matches the combined prior, which already averages the
#' sites' priors. It is an equal-weight average: the per-site prior precisions
#' that [combine_multisite_priors()] weights by are not carried on the combined
#' row. Presence-mixture rows average their per-group `prior_mix_w` updates in
#' the same way.
#'
#' Cross-marker confirmation needs the grouping values to be the SAME strings
#' across markers: a tube's 12S, COI and 18S libraries must share its sample
#' id, even though `observation_id` is namespaced per marker. When `detections`
#' has a `marker_col` column spanning several markers and no group contains
#' more than one marker, the function says so.
#'
#' With `detections = NULL` every observation in `result` forms one group
#' (study-wide pooling), announced with a message. That is correct for a single
#' site or sampling event. It is refused when `result` carries priors that
#' [combine_multisite_priors()] combined across sites (`n_sites_combined` > 1),
#' because that data is multi-site by construction.
#'
#' Per-group counts of observations, eligible unresolved observations,
#' observations updated and rows raised are printed and returned as
#' `attr(<result>, "prior_update_groups")`.
#'
#' @section Soft confirmation:
#' A hard-gate donor definition -- counting an observation as a "donor" only
#' when it resolves a species with `consensus_posterior >=` a threshold
#' (e.g. 0.8) -- is hard assignment in the sense of classification EM
#' (Celeux & Govaert 1992, \emph{Computational Statistics & Data Analysis}
#' 14:315-332). That would make the
#' dataset-level output discontinuous in per-observation inputs: one marginal
#' competitor holding every observation of a species just below the bar means
#' zero donors anywhere (a real case: 78 yellow-perch observations at ~0.69
#' each -- no confirmation, dataset-wide). Instead, every observation's best
#' posterior for a species contributes fractionally (soft assignment, the
#' one-iteration analog of a multi-scale occupancy update -- Dorazio &
#' Erickson 2018, \emph{Molecular Ecology Resources} 18:368-380):
#' \enumerate{
#'   \item Per species, support mass = the sum over observations of that
#'     observation's best posterior for it; per target row, the target
#'     observation's own support is subtracted (leave-one-out -- no
#'     self-confirmation).
#'   \item The mass is discounted by `confirmation_discount` (a0): same-site
#'     observations share the same sampling event (water body, sound field,
#'     or image set) and reference biases, so they are
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
#' A formally correct alternative to this quantile-based design would be a
#' Beta-Binomial hierarchical model over species x observation within a
#' site; the current design does not by itself distinguish "confidence
#' earned by genuinely strong evidence" from "confidence attained despite
#' thin/low-quality input" (e.g. a short, low-coverage sequence read
#' producing a spurious high-identity match) -- that would need a quality
#' covariate on the underlying scores, a separate, larger design question
#' flagged for later rather than solved here.
#'
#' @section Rescaling onto the occurrence scale:
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
#' `prior_new <- max(prior_old, q * max(theta_mean, na.rm = TRUE))`,
#' where `q` is the confirmation-quantile value described above and the
#' maximum is taken over the rows of the group's own observations (the
#' study-wide maximum when the group has none). This keeps
#' the confirmation-quantile logic and the never-demote guard unchanged --
#' only the target scale moves -- so a stronger/more numerous confirmation
#' (higher `q`) still produces a stronger boost, bounded by the model's own
#' observed maximum share rather than substituting a foreign-scale
#' constant. When `result` has no `theta_mean` column (e.g. LLM-pathway
#' priors from [assign_taxa_llm()], which are not occurrence-share-based to
#' begin with), direct substitution (without rescaling) is used
#' instead -- the units mismatch this section fixes is specific to
#' occurrence-model-sourced priors.
#'
#' @section Confirmed without an occurrence record:
#' A taxon can be confidently identified elsewhere in the dataset while
#' having no occurrence record at all (`theta_mean` `NA` for every row
#' naming it) -- e.g. a real Mugu case, *Oncorhynchus mykiss*, which has no
#' row in `taxaexpect_priors` at all (a known, separate upstream join gap,
#' not a sign the species is
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
#'   Carlo path stays consistent with the boosted point estimate -- rescaling
#'   only `prior_mean` would leave a stale Beta shape that could be sampled
#'   from if `n_sims > 0`.
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
#'   independent -- almost certainly too strong for same-site detections of
#'   any kind). See the
#'   \emph{Soft confirmation} section.
#' @param n_sims Integer. Passed to [compute_posterior()] for the re-run.
#'   Default 0 (point estimates only, fast). Set to 1000 to propagate
#'   uncertainty -- match the value used in the original run.
#' @param detections Data frame, optional. One row per observation x group
#'   membership: an `observation_id` column plus the `group_cols` column(s), and
#'   optionally `marker_col`. An observation may appear in many rows (an ESV
#'   detected in several tubes or at several sites). Observations of `result`
#'   missing from it belong to no group and are returned unchanged. Default
#'   `NULL`: every observation shares one group (study-wide pooling; refused
#'   for multi-site combined priors).
#' @param group_cols Character vector. Column(s) of `detections` whose
#'   combination defines an evidence group. Default `"sample_id"`, the sample
#'   (tube). Pass e.g. `"site"` to pool every tube at a site, or
#'   `c("site", "season")` to pool within site and season.
#' @param marker_col Character. Optional column of `detections` naming the
#'   marker or assay, used only to warn when no group spans more than one
#'   marker. Ignored when absent. Default `"marker"`.
#' @param spatial_group_map Data frame with `observation_id` and
#'   `spatial_group_id` columns (e.g. from
#'   `TaxaMatch::group_observations_by_bbox()`), optional. Equivalent to
#'   `detections = spatial_group_map, group_cols = "spatial_group_id"`:
#'   evidence is pooled within each spatial group only, so two sites in
#'   different spatial groups donate nothing to each other. Membership is
#'   binary (same group or not), with no distance decay within a group. Supply
#'   this or `detections`, not both.
#'
#' @return The full posterior dataframe with the same structure as `result`,
#'   plus one new column, `confirmed_without_occurrence_record` (logical,
#'   `FALSE` unless set `TRUE` -- see @section Confirmed without an
#'   occurrence record). Resolved observations are returned unchanged.
#'   Unresolved observations that share at least one group with another
#'   observation have updated `prior_mean` and freshly computed posterior
#'   columns (`posterior_point_est`, `posterior_mean`, `posterior_sd`,
#'   `confidence_score`). Unresolved observations whose every group is a
#'   singleton are returned unchanged, same as resolved ones. Sorted by
#'   `observation_id` then descending `posterior_point_est`. Attribute
#'   `prior_update_groups` holds the per-group counts (`group`,
#'   `n_observations`, `n_eligible_unresolved`, `n_observations_updated`,
#'   `n_rows_raised`).
#'
#' @seealso [posterior_consensus()], [compute_posterior()], [assign_taxa_llm()],
#'   [combine_multisite_priors()]
#'
#' @examples
#' \dontrun{
#' # detections: one row per observation x sample, plus a site column
#' result_updated <- update_prior_from_consensus(
#'   result, consensus,
#'   confirmation_quantile = 0.9,
#'   confirmation_discount = 0.25,
#'   detections = detections,
#'   group_cols = "site"
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
                                        confirmation_quantile = 0.9,
                                        confirmation_discount = 0.25,
                                        n_sims = 0,
                                        detections = NULL,
                                        group_cols = "sample_id",
                                        marker_col = "marker",
                                        spatial_group_map = NULL) {
  # --- Input validation -------------------------------------------------------
  required_result <- c(
    "observation_id", "taxon_name", "score_likelihood",
    "score_likelihood_mean", "score_likelihood_sd", "prior_mean"
  )
  missing_result <- setdiff(required_result, names(result))
  if (length(missing_result) > 0) {
    cli::cli_abort("result missing required column(s): {.field {missing_result}}")
  }

  required_consensus <- c(
    "observation_id", "consensus_taxon", "is_resolved",
    "consensus_posterior"
  )
  missing_consensus <- setdiff(required_consensus, names(consensus))
  if (length(missing_consensus) > 0) {
    cli::cli_abort("consensus missing required column(s): {.field {missing_consensus}}")
  }

  if (!is.numeric(confirmation_quantile) || length(confirmation_quantile) != 1L ||
    is.na(confirmation_quantile) || confirmation_quantile <= 0 || confirmation_quantile > 1) {
    cli::cli_abort("{.arg confirmation_quantile} must be a single number in (0, 1].")
  }

  if (!is.numeric(confirmation_discount) || length(confirmation_discount) != 1L ||
    is.na(confirmation_discount) ||
    confirmation_discount < 0 || confirmation_discount > 1) {
    cli::cli_abort("{.arg confirmation_discount} must be a single number in [0, 1].")
  }

  # --- Resolve the evidence groups ----------------------------------------------
  # One row per (observation_id, group_key). An observation may sit in several
  # groups (an ESV detected in many tubes, or at several sites); evidence is
  # pooled WITHIN a group only, and a row's per-group gains are averaged over
  # every group its observation belongs to (see @section Group-local evidence).
  membership <- .resolve_update_groups(
    result, detections, group_cols, marker_col, spatial_group_map
  )
  group_size <- table(membership$group_key)
  multi_groups <- names(group_size)[group_size >= 2L]
  eligible_ids <- unique(membership$observation_id[membership$group_key %in% multi_groups])
  .report_group_structure(membership, group_size, attr(membership, "study_wide"))

  # --- Soft confirmation evidence ---------------------------------------------
  # A hard donor gate (a species counted as confirmed only when some
  # observation resolved it with consensus_posterior >= a threshold) is
  # classification EM (Celeux & Govaert 1992, Computational
  # Statistics & Data Analysis 14:315-332) and would produce real cliffs: one
  # marginal competitor holding every observation just under the bar means
  # ZERO donors dataset-wide (the GreatLakes2023 yellow-perch case -- 78
  # observations at ~0.69 each, no confirmation anywhere). The soft version
  # instead aggregates EVERY observation's posterior support for a species as
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
  if (nrow(support_pool) == 0L) {
    cli::cli_inform("No named posterior support anywhere; returning result unchanged.")
    return(result)
  }

  # Per (observation, species) support: the best posterior that observation
  # gives the species (multi-site/duplicate candidate rows collapse to one).
  sup_key <- paste(support_pool$observation_id, support_pool$taxon_name, sep = "\r")
  obs_support <- tapply(support_pool[[post_col]], sup_key, max)
  key_split <- strsplit(names(obs_support), "\r", fixed = TRUE)
  sup_obs <- vapply(key_split, function(k) k[[1L]], character(1))
  sup_taxon <- vapply(key_split, function(k) k[[2L]], character(1))
  sup_p <- as.numeric(obs_support)

  # Per (group, species) evidence, from the members of that group only.
  # Singleton groups carry no cross-observation evidence by construction, so
  # only multi-member groups are expanded here.
  mem_multi <- membership[membership$group_key %in% multi_groups, , drop = FALSE]
  ev <- merge(
    data.frame(observation_id = sup_obs, taxon = sup_taxon, p = sup_p, stringsAsFactors = FALSE),
    mem_multi,
    by = "observation_id"
  )
  gs_key <- paste(ev$group_key, ev$taxon, sep = "\n")
  gs_mass <- tapply(ev$p, gs_key, sum)
  # Support-weighted confirmation-quantile of per-observation support within
  # each group: the target level the substitution moves toward. Weighting by
  # the support itself keeps a handful of genuine detections from being
  # drowned by a sea of near-zero candidacies of the same species.
  gs_target <- .grouped_weighted_quantile(ev$p, gs_key, confirmation_quantile)

  # --- Identify unresolved observations ----------------------------------------
  unresolved_ids <- consensus$observation_id[
    is.na(consensus$consensus_taxon) | !consensus$is_resolved
  ]
  if (length(unresolved_ids) == 0L) {
    cli::cli_inform("All observations already resolved; returning result unchanged.")
    return(result)
  }
  unresolved_ids <- unresolved_ids[as.character(unresolved_ids) %in% eligible_ids]
  if (length(unresolved_ids) == 0L) {
    cli::cli_inform(
      "No unresolved observation shares a group with any other observation; \\
      returning result unchanged."
    )
    return(result)
  }

  cli::cli_inform(c(
    "Soft confirmation: {length(unique(ev$taxon))} species carry posterior support \\
    inside {length(multi_groups)} multi-member group(s) (power-prior discount \\
    a0 = {confirmation_discount}).",
    "Unresolved observations to update: {length(unresolved_ids)}",
    "Confirmation quantile (support-weighted, per group): {confirmation_quantile}"
  ))

  # --- Split result -----------------------------------------------------------
  resolved_rows <- result[!result$observation_id %in% unresolved_ids, ]
  unresolved_rows <- result[result$observation_id %in% unresolved_ids, ]

  v1 <- consensus[, c("observation_id", "consensus_taxon", "consensus_rank")]
  names(v1)[2:3] <- c("consensus_taxon_v1", "consensus_rank_v1")
  resolved_rows <- merge(resolved_rows, v1, by = "observation_id", all.x = TRUE)
  unresolved_rows <- merge(unresolved_rows, v1, by = "observation_id", all.x = TRUE)
  # rep() guards the all-unresolved case: a scalar assignment onto a 0-row
  # base data frame errors ("replacement has 1 row, data has 0")
  resolved_rows$prior_updated <- rep(FALSE, nrow(resolved_rows))
  unresolved_rows$prior_updated <- rep(TRUE, nrow(unresolved_rows))
  resolved_rows$confirmed_without_occurrence_record <- rep(FALSE, nrow(resolved_rows))
  unresolved_rows$confirmed_without_occurrence_record <- rep(FALSE, nrow(unresolved_rows))

  # --- Expand every unresolved row over its observation's groups ---------------
  # rg: one row per (unresolved hypothesis row, group of its observation),
  # singleton groups included -- they contribute zero gain but still count in
  # the denominator of the per-row mean, so evidence from one group of k is
  # diluted to 1/k (see @section Group-local evidence).
  n_ur <- nrow(unresolved_rows)
  rg <- merge(
    data.frame(
      row = seq_len(n_ur),
      observation_id = as.character(unresolved_rows$observation_id),
      stringsAsFactors = FALSE
    ),
    membership,
    by = "observation_id"
  )
  rg <- rg[order(rg$row), , drop = FALSE]
  k_row <- tabulate(rg$row, nbins = n_ur)
  .row_mean <- function(v) {
    s <- numeric(n_ur)
    agg <- rowsum(v, rg$row, reorder = TRUE)
    s[as.integer(rownames(agg))] <- agg[, 1L]
    ifelse(k_row > 0L, s / pmax(k_row, 1L), 0)
  }

  rg_taxon <- unresolved_rows$taxon_name[rg$row]
  rg_gs <- paste(rg$group_key, rg_taxon, sep = "\n")
  row_key <- paste(unresolved_rows$observation_id, unresolved_rows$taxon_name, sep = "\r")
  own_p <- as.numeric(obs_support[row_key])
  own_p[is.na(own_p)] <- 0

  # Leave-one-out, discounted, saturating evidence per (row, group): the row's
  # own support is removed from each of its groups separately, so an
  # observation can never confirm itself, even as the sole supporter of a group.
  mass_rg <- as.numeric(gs_mass[rg_gs])
  mass_rg[is.na(mass_rg)] <- 0
  mass_rg <- pmax(mass_rg - own_p[rg$row], 0)
  md_rg <- confirmation_discount * mass_rg
  s_rg <- md_rg / (1 + md_rg) # smooth saturation in [0, 1): no cliffs
  md_row <- .row_mean(md_rg)
  boost_mask <- !is.na(unresolved_rows$taxon_name) & md_row > 0

  if (!any(boost_mask)) {
    cli::cli_inform(
      "No unresolved hypothesis has any cross-observation support within its own \\
      group(s) after the leave-one-out discount; returning result unchanged."
    )
    return(result)
  }

  # Occurrence-scale rescale (see @section Rescaling onto the occurrence scale),
  # with the ceiling taken PER GROUP: the largest theta_mean among the rows of
  # that group's own observations. A group with no finite positive theta falls
  # back to the study-wide ceiling (a scale bound, not evidence).
  has_theta <- "theta_mean" %in% names(result)
  theta_ceiling <- if (has_theta) suppressWarnings(max(result$theta_mean, na.rm = TRUE)) else NA_real_
  if (has_theta && (!is.finite(theta_ceiling) || theta_ceiling <= 0)) {
    has_theta <- FALSE
  }
  n_ceiling_fallback <- 0L
  if (has_theta) {
    th_obs <- tapply(result$theta_mean, as.character(result$observation_id), function(v) {
      suppressWarnings(max(v, na.rm = TRUE))
    })
    g_ceiling <- tapply(as.numeric(th_obs[membership$observation_id]), membership$group_key, max)
    bad <- !is.finite(g_ceiling) | g_ceiling <= 0
    n_ceiling_fallback <- sum(bad & names(g_ceiling) %in% multi_groups)
    g_ceiling[bad] <- theta_ceiling
    ceil_rg <- as.numeric(g_ceiling[rg$group_key])
  }
  q_rg <- as.numeric(gs_target[rg_gs])
  cand_rg <- if (has_theta) q_rg * ceil_rg else q_rg

  mix_cols_all <- c("prior_mix_w", "prior_mix_theta_present", "prior_mix_theta_absent")
  is_mix_row <- if (all(mix_cols_all %in% names(unresolved_rows))) {
    !is.na(unresolved_rows$prior_mix_w) &
      !is.na(unresolved_rows$prior_mix_theta_present) &
      !is.na(unresolved_rows$prior_mix_theta_absent)
  } else {
    rep(FALSE, n_ur)
  }

  # --- Non-mixture rows: soft, never-demote substitution -----------------------
  old_prior <- unresolved_rows$prior_mean
  gain_rg <- pmax(cand_rg - old_prior[rg$row], 0) * s_rg
  gain_rg[is.na(gain_rg) | is_mix_row[rg$row] | is.na(rg_taxon)] <- 0
  soft_gain <- .row_mean(gain_rg)
  raise_mask <- soft_gain > 0
  new_prior <- old_prior + soft_gain

  cli::cli_inform(c(
    "{sum(boost_mask)} hypothesis row(s) carry cross-observation support within \\
    their own group(s); {sum(raise_mask)} raised above their existing prior \\
    (smoothly, by the saturating discounted mass, averaged over each row's groups \\
    -- others already met their support-weighted target).",
    if (has_theta) {
      "Substitution rescaled onto each group's occurrence ceiling (study-wide \\
      fallback used for {n_ceiling_fallback} multi-member group(s) with no theta_mean)."
    } else {
      "No theta_mean column on result -- using the support-weighted quantile directly."
    }
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
      phi <- unresolved_rows$prior_alpha[raise_mask] + unresolved_rows$prior_beta[raise_mask]
      clamped <- pmin(pmax(new_prior[raise_mask], 1e-9), 1 - 1e-9)
      unresolved_rows$prior_alpha[raise_mask] <- clamped * phi
      unresolved_rows$prior_beta[raise_mask] <- (1 - clamped) * phi
    }
  }

  # --- Mixture rows: cross-observation support updates prior_mix_w -------------
  # For a presence mixture, confirmation IS evidence about presence: each
  # group's discounted support mass enters w's own pseudo-observation update
  # (successes at the support mass itself), the per-group updates are averaged
  # over the row's groups exactly like the non-mixture gains, p_conc grows by
  # the averaged mass, and the Beta summary is re-moment-matched to the updated
  # two-point mixture, rather than a hard rule that would clear the mixture
  # outright on a thresholded confirmation.
  mixable <- boost_mask & is_mix_row
  w_raised_rg <- rep(FALSE, nrow(rg))
  if (any(mixable)) {
    pc_all <- if ("prior_mix_p_conc" %in% names(unresolved_rows)) {
      unresolved_rows$prior_mix_p_conc
    } else {
      rep(NA_real_, n_ur)
    }
    pc_all[is.na(pc_all)] <- 1
    w0_all <- unresolved_rows$prior_mix_w
    pc_rg <- pc_all[rg$row]
    w0_rg <- w0_all[rg$row]
    w1_rg <- (pc_rg * w0_rg + md_rg) / (pc_rg + md_rg)
    w1_rg[!is_mix_row[rg$row] | is.na(w1_rg)] <- 0
    w_raised_rg <- is_mix_row[rg$row] & md_rg > 0
    w1_all <- .row_mean(w1_rg)

    pc <- pc_all[mixable]
    w0 <- w0_all[mixable]
    md <- md_row[mixable]
    w1 <- w1_all[mixable]
    # Cap at the construction-time veto bound: the update above is
    # level-blind and can be pushed past the
    # bound by a wide, low-grade blocker's correlated cross-observation
    # support alone (worked example: w 0.05 -> 0.33 against a
    # ~0.05 bound, purely from volume, with the genuinely-observed native
    # gaining nothing from the same pass). This is an "at minimum" floor --
    # NOT a deeper level-aware redesign
    # (weighting the update by the species' own support-weighted quantile, or
    # scaling trial count by n_observations), which is a real statistical
    # design choice left for a deliberate decision, not made here. NA bound
    # (a prior_mix_* table built before this column existed, or a row with no
    # computable bound) leaves w1 uncapped.
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
    unresolved_rows$prior_mix_w[mixable] <- w1
    unresolved_rows$prior_mix_p_conc[mixable] <- pc + md
    unresolved_rows$prior_mean[mixable] <- th1
    if (all(c("prior_alpha", "prior_beta") %in% names(unresolved_rows))) {
      # Reproduce TaxaExpect::apply_undetected_evidence()'s own v_mix formula,
      # not just its (thp-tha) term. Blend-mode rows carry real
      # within-state variance at the present/
      # absent anchors (prior_mix_var_present/_absent); omitting them here
      # silently over-concentrated the refreshed Beta for those rows (curve
      # rows are unaffected -- their states are points, so both are exactly
      # 0 and this reduces to the original formula). Default 0 for a
      # prior_mix_* table built before these two columns existed.
      var_p <- if ("prior_mix_var_present" %in% names(unresolved_rows)) {
        v <- unresolved_rows$prior_mix_var_present[mixable]
        v[is.na(v)] <- 0
        v
      } else {
        rep(0, sum(mixable))
      }
      var_a <- if ("prior_mix_var_absent" %in% names(unresolved_rows)) {
        v <- unresolved_rows$prior_mix_var_absent[mixable]
        v[is.na(v)] <- 0
        v
      } else {
        rep(0, sum(mixable))
      }
      v_mix <- w1 * (1 - w1) * (thp - tha)^2 + w1 * var_p + (1 - w1) * var_a
      ok <- is.finite(v_mix) & v_mix > 0
      if (any(ok)) {
        ne <- pmax(th1[ok] * (1 - th1[ok]) / v_mix[ok] - 1, 1e-3)
        idx <- which(mixable)[ok]
        unresolved_rows$prior_alpha[idx] <- th1[ok] * ne
        unresolved_rows$prior_beta[idx] <- (1 - th1[ok]) * ne
      }
    }
    cli::cli_inform(c(
      "{sum(mixable)} presence-mixture row(s) had prior_mix_w updated by the \\
      discounted cross-observation support within their own group(s) (presence \\
      evidence, never demoted).",
      "i" = "sum(prior_mix_w) over these rows: {signif(sum(w0), 3)} -> \\
      {signif(sum(w1), 3)}. apply_undetected_evidence()'s own budget audit \\
      (sum(w) vs. chao_missing) describes the priors AS BUILT, not as the \\
      posterior actually used -- this is the post-refinement counterpart, \\
      purely informational.",
      if (n_capped > 0L) {
        c("!" = "{n_capped} row(s) would have updated PAST their own veto bound \\
        -- capped there instead. This is a floor against runaway \\
        correlated-confirmation accumulation, not a fix to the update rule \\
        itself; a deeper level-aware redesign (weighting the update by the \\
        species' own support-weighted quantile, or scaling trial count by \\
        n_observations) is a real statistical design choice left for a \\
        deliberate decision, not made here.")
      }
    ))
  }

  # --- Per-group report ----------------------------------------------------------
  raised_rg <- (gain_rg > 0) | w_raised_rg
  group_report <- .summarise_group_update(
    membership, group_size, unresolved_ids, rg, raised_rg
  )
  .report_group_update(group_report)

  # --- Recompute posteriors for unresolved observations ------------------------
  # Drop existing posterior columns so compute_posterior() produces fresh values
  post_cols <- intersect(
    c("posterior_point_est", "posterior_mean", "posterior_sd", "confidence_score"),
    names(unresolved_rows)
  )
  unresolved_rows <- unresolved_rows[,
    setdiff(names(unresolved_rows), post_cols),
    drop = FALSE
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
      n_sims                      = n_sims,
      group_cols                  = attr(membership, "group_cols")
    )
  )
  attr(out, "prior_update_groups") <- group_report
  out
}


# --- Internal helpers ---------------------------------------------------------

#' Resolve observation -> evidence-group membership
#'
#' Returns one row per distinct (observation_id, group_key) pair, restricted to
#' observations present in `result`. `group_key` is the combination of the
#' caller's `group_cols` (joined with "\r"); attribute `study_wide` is TRUE when
#' no grouping was supplied and every observation shares one group.
#' @noRd
.resolve_update_groups <- function(result, detections, group_cols, marker_col,
                                   spatial_group_map) {
  if (!is.null(spatial_group_map)) {
    if (!is.null(detections)) {
      cli::cli_abort(
        "Supply {.arg detections} or the superseded {.arg spatial_group_map}, not both."
      )
    }
    missing_group <- setdiff(c("observation_id", "spatial_group_id"), names(spatial_group_map))
    if (length(missing_group) > 0) {
      cli::cli_abort("spatial_group_map missing required column(s): {.field {missing_group}}")
    }
    cli::cli_inform(c(
      "i" = "{.arg spatial_group_map} supplied; treating it as {.code detections = spatial_group_map, \\
      group_cols = \"spatial_group_id\"}. Evidence is pooled within each spatial \\
      group only."
    ))
    detections <- spatial_group_map
    group_cols <- "spatial_group_id"
    marker_col <- NULL
  }

  res_ids <- unique(as.character(result$observation_id))

  if (is.null(detections)) {
    if ("n_sites_combined" %in% names(result) &&
      any(result$n_sites_combined > 1L, na.rm = TRUE)) {
      cli::cli_abort(c(
        "{.arg detections} is NULL, but {.arg result} carries priors combined across \\
        several sites ({.field n_sites_combined} > 1).",
        "i" = "Without a grouping the update would pool evidence across every site in \\
        the study, so a detection at one site would raise priors at all the others.",
        "i" = "Pass {.arg detections} (a table with {.field observation_id} plus the \\
        grouping column(s)) and {.arg group_cols}, e.g. {.code group_cols = \"site\"}."
      ))
    }
    cli::cli_inform(c(
      "!" = "No {.arg detections} supplied: evidence is pooled across ALL of \\
      {.arg result} as a single group. That is correct only when every observation \\
      shares one local species pool (one site / sampling event). For several sites \\
      or samples, pass {.arg detections} and {.arg group_cols}."
    ))
    out <- data.frame(
      observation_id = res_ids,
      group_key = rep("(all observations)", length(res_ids)),
      stringsAsFactors = FALSE
    )
    attr(out, "study_wide") <- TRUE
    attr(out, "group_cols") <- NA_character_
    return(out)
  }

  if (!is.data.frame(detections)) {
    cli::cli_abort("{.arg detections} must be a data frame.")
  }
  if (!is.character(group_cols) || length(group_cols) < 1L || anyNA(group_cols) ||
    any(!nzchar(group_cols))) {
    cli::cli_abort("{.arg group_cols} must be a non-empty character vector of column names.")
  }
  missing_cols <- setdiff(c("observation_id", group_cols), names(detections))
  if (length(missing_cols) > 0) {
    cli::cli_abort(c(
      "detections missing required column(s): {.field {missing_cols}}",
      "i" = "{.arg group_cols} = {.val {group_cols}}; the default is the sample (tube) \\
      column {.val sample_id}."
    ))
  }

  det <- as.data.frame(detections)
  key_df <- det[, group_cols, drop = FALSE]
  bad <- is.na(det$observation_id) | !stats::complete.cases(key_df)
  if (any(bad)) {
    cli::cli_inform(c(
      "!" = "{sum(bad)} detections row(s) have NA {.field observation_id} or NA in \\
      {.field {group_cols}}; dropped from the grouping."
    ))
  }
  det <- det[!bad, , drop = FALSE]
  key <- do.call(paste, c(lapply(det[, group_cols, drop = FALSE], as.character), sep = "\r"))
  det_ids <- as.character(det$observation_id)

  in_map <- res_ids %in% det_ids
  if (!any(in_map)) {
    cli::cli_abort(c(
      "None of {.arg result}'s observation_ids appear in {.arg detections}.",
      "i" = "Check that both tables use the same observation_id strings (e.g. the \\
      same per-marker namespacing)."
    ))
  }
  if (!all(in_map)) {
    cli::cli_inform(c(
      "!" = "{sum(!in_map)} of {length(res_ids)} observation(s) in {.arg result} have \\
      no row in {.arg detections}: they belong to no group, so they neither donate \\
      nor receive, and are returned unchanged."
    ))
  }

  if (!is.null(marker_col) && marker_col %in% names(det)) {
    keep <- det_ids %in% res_ids
    mk <- as.character(det[[marker_col]][keep])
    gk <- key[keep]
    ok <- !is.na(mk)
    if (length(unique(mk[ok])) > 1L) {
      n_mk <- tapply(mk[ok], gk[ok], function(x) length(unique(x)))
      if (all(n_mk <= 1L)) {
        cli::cli_inform(c(
          "!" = "{.arg detections} spans {length(unique(mk[ok]))} markers \\
          ({.field {marker_col}}), but every group holds a single marker, so no \\
          cross-marker confirmation can happen.",
          "i" = "Grouping values must be the SAME strings across markers (a tube's \\
          12S, COI and 18S libraries must share its sample id), even though \\
          observation_ids are namespaced per marker."
        ))
      }
    }
  }

  out <- unique(data.frame(observation_id = det_ids, group_key = key, stringsAsFactors = FALSE))
  out <- out[out$observation_id %in% res_ids, , drop = FALSE]
  rownames(out) <- NULL
  attr(out, "study_wide") <- FALSE
  attr(out, "group_cols") <- group_cols
  out
}

#' Report how observations are spread over evidence groups
#' @noRd
.report_group_structure <- function(membership, group_size, study_wide) {
  n_obs <- length(unique(membership$observation_id))
  n_groups <- length(group_size)
  n_multi <- sum(group_size >= 2L)
  n_per_obs <- table(membership$observation_id)
  largest <- if (n_groups > 0L) max(group_size) else 0L
  cli::cli_inform(c(
    "Evidence groups: {n_groups} group(s) ({n_multi} multi-member, \\
    {n_groups - n_multi} singleton) over {n_obs} observation(s); groups per \\
    observation {min(n_per_obs)}-{max(n_per_obs)}; largest group \\
    {largest} observation(s)."
  ))
  if (n_groups > 0L && n_multi == 0L) {
    cli::cli_inform(c(
      "!" = "Every group is a singleton: no observation shares a group with another, \\
      so no prior can be updated."
    ))
  }
  if (!isTRUE(study_wide) && n_groups == 1L && n_obs > 1L) {
    cli::cli_inform(c(
      "!" = "One group holds every observation: this is study-wide pooling. Check \\
      {.arg group_cols} if the study has more than one site or sample."
    ))
  }
  invisible(NULL)
}

#' Support-weighted quantile of `x` within each level of `key`
#'
#' Returns a vector named by key. The weights are `x` itself, matching the
#' support-weighted confirmation target.
#' @noRd
.grouped_weighted_quantile <- function(x, key, prob) {
  if (length(x) == 0L) {
    return(stats::setNames(numeric(0), character(0)))
  }
  o <- order(key, x)
  k <- key[o]
  xs <- x[o]
  tot <- tapply(xs, k, sum)
  cw <- stats::ave(xs, k, FUN = cumsum) / as.numeric(tot[k])
  cw[!duplicated(k, fromLast = TRUE)] <- 1
  hit <- !is.na(cw) & cw >= prob
  hk <- k[hit]
  hx <- xs[hit]
  first <- !duplicated(hk)
  stats::setNames(hx[first], hk[first])
}

#' Per-group counts of eligible, updated and raised
#' @noRd
.summarise_group_update <- function(membership, group_size, unresolved_ids, rg, raised_rg) {
  keys <- names(group_size)
  unres <- membership$observation_id %in% as.character(unresolved_ids) &
    membership$group_key %in% keys[group_size >= 2L]
  n_elig <- table(factor(membership$group_key[unres], levels = keys))
  n_rows <- table(factor(rg$group_key[raised_rg], levels = keys))
  upd <- unique(rg[raised_rg, c("observation_id", "group_key"), drop = FALSE])
  n_upd <- table(factor(upd$group_key, levels = keys))
  data.frame(
    group = gsub("\r", " / ", keys, fixed = TRUE),
    n_observations = as.integer(group_size),
    n_eligible_unresolved = as.integer(n_elig),
    n_observations_updated = as.integer(n_upd),
    n_rows_raised = as.integer(n_rows),
    stringsAsFactors = FALSE
  )
}

#' Print the per-group update table (all groups when few, a summary otherwise)
#' @noRd
.report_group_update <- function(tab, max_lines = 30L) {
  if (nrow(tab) == 0L) {
    return(invisible(NULL))
  }
  fmt <- function(t) {
    sprintf(
      "  %s: %d obs, %d eligible unresolved, %d updated, %d row(s) raised",
      t$group, t$n_observations, t$n_eligible_unresolved,
      t$n_observations_updated, t$n_rows_raised
    )
  }
  if (nrow(tab) <= max_lines) {
    message(paste(c("Per-group prior update:", fmt(tab)), collapse = "\n"))
  } else {
    top <- tab[order(-tab$n_rows_raised), , drop = FALSE][seq_len(10L), , drop = FALSE]
    message(paste(c(
      sprintf(
        "Per-group prior update: %d group(s); %d with at least one raised row. Top 10 by rows raised:",
        nrow(tab), sum(tab$n_rows_raised > 0L)
      ),
      fmt(top),
      "  (full table: attr(<result>, \"prior_update_groups\"))"
    ), collapse = "\n"))
  }
  invisible(NULL)
}
