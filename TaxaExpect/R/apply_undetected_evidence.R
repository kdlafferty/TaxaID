#' Elevate the dark-diversity floor prior for species with external occurrence-plausibility evidence
#'
#' \code{\link{generate_undetected_diversity}} treats every species with zero
#' occurrence records identically -- the generic global-floor
#' \code{Beta(1, N_total - 1)}, regardless of whether it has never been
#' recorded within a thousand kilometers, or has real external evidence
#' (a documented invasion-front species, a corroborated nearby record just
#' outside the study bbox) making it a materially more plausible detection.
#' This function is the single, shared mechanism for elevating that floor
#' for named species, given evidence from any number of independent sources
#' -- designed so multiple sources can be combined safely without producing
#' duplicate, ambiguously-joinable rows for the same taxon.
#'
#' @section Why one shared function, not one per evidence source:
#' An earlier design had each evidence source (e.g. an invasive-species
#' watch list, a regional-proximity check) independently construct and
#' append its own finished \code{Beta(alpha, beta)} row to
#' \code{taxaexpect_priors}. That breaks the moment a species qualifies
#' under more than one source at once: \code{TaxaAssign::join_priors()}
#' joins on the composite key \code{(taxon_name, taxon_name_rank, grid_id,
#' main_habitat)}, so two independently-appended rows sharing that key
#' produce an ambiguous join -- silently picking one, fanning out into
#' duplicate hypotheses, or erroring, depending on row order. This function
#' is the single place a new evidence-elevated row is ever created, so that
#' collision is structurally impossible: every source's opinion about a
#' given taxon is combined \emph{before} one row is written.
#'
#' @section Evidence sources are decoupled from prior construction:
#' \code{evidence} is deliberately a thin, source-agnostic table -- a
#' source function (e.g. an invasive-watch-list generator) never touches
#' \code{taxaexpect_priors}, never does Beta-parameter math, and knows
#' nothing about the floor/singleton anchors. It only answers, per taxon:
#' how probable is local presence (\code{weight} = P(present | this source's
#' evidence)) and how much weight that presence claim should carry against
#' future evidence (\code{p_conc}, pseudo-observations; optional, default 1)?
#' This function is the only consumer that turns those into an actual prior.
#'
#' @section How the elevation works:
#' For each taxon in \code{evidence} that is genuinely unobserved (see
#' \verb{Which species are eligible} below), the floor's own
#' \code{(alpha, beta)} is read directly out of \code{taxaexpect_priors}
#' (not recomputed), and the site's own singleton-mirror mean is used as an
#' upper anchor -- the two values \code{\link{generate_undetected_diversity}}
#' already produces. The elevated prior is a PRESENCE MIXTURE (2026-08-26
#' mixture redesign): with probability \code{w_combined} the species is
#' locally present (theta ~ the ceiling-anchor state), with probability
#' \code{1 - w_combined} absent (theta ~ the floor state). The blended mean
#' is that mixture's exact expectation, and the Beta summary's concentration
#' is moment-matched to the mixture's variance -- not caller-chosen:
#' \preformatted{
#'   theta_new = theta_floor + (theta_singleton - theta_floor) * w_combined
#'   v         = w*Var_ceiling + (1-w)*Var_floor + w*(1-w)*(theta_c-theta_f)^2
#'   n_eff_mm  = theta_new*(1-theta_new)/v - 1
#'   alpha_new = theta_new * n_eff_mm;  beta_new = (1-theta_new) * n_eff_mm
#' }
#' The mixture itself is also emitted (\code{prior_mix_w}/
#' \code{prior_mix_theta_present}/\code{prior_mix_theta_absent}) so
#' \code{TaxaAssign::compute_posterior()} can integrate over presence states
#' directly (an explicit Bernoulli presence draw) instead of sampling the
#' J-shaped Beta summary; alpha/beta remain the point-path summary.
#' \code{prior_mix_p_conc} does NOT affect these marginal moments (for a
#' two-point presence mixture, uncertainty about w cancels out of the
#' marginal variance) -- it records how much weight the presence claim
#' carries against future evidence, for the confirmation update.
#' Blending toward \code{theta_singleton} (rather than, say, multiplying the
#' floor's own alpha by a factor) gives this a principled ceiling for free:
#' at \code{w_combined = 1} the elevated prior equals the singleton-mirror
#' mean exactly, so external evidence -- however strong -- can never make an
#' unobserved species look more plausible than one genuinely detected once.
#'
#' \strong{Ceiling anchor ladder (datasets without singletons):} when
#' \code{taxaexpect_priors} carries no \code{singleton_mirror} rows at all,
#' the upper anchor -- "the detection rate of a species present but rare
#' enough to have plausibly escaped local detection" -- is estimated by
#' descending a ladder instead of silently collapsing onto the floor: (1)
#' the minimum theta among genuinely modelled rows (site-scoped rows
#' preferred; a mild, safe-direction overestimate, since a no-singleton
#' dataset detected every species at least twice); (2) one detection per
#' site effort, \code{1 / (median(n_obs) + 1)}; (3) only if neither is
#' computable, the previous floor-equals-ceiling no-op with a warning.
#'
#' @section The printed veto bound:
#' Each call prints the dataset-specific weight above which an unobserved
#' species can block species-level resolution of a singleton-level observed
#' native at likelihood parity (derived from the anchors and the consensus
#' default \code{min_posterior = 0.05}). Choose watch-list weights BELOW this
#' bound unless you deliberately intend elevated species to compete with
#' observed ones.
#'
#' Under \code{pricing = "curve"} the message also names the \code{f1} and
#' \code{f2} counts the price came from, and says so when \code{f2} is in
#' single digits: \code{theta_present = missing_mass / chao_missing} with
#' \code{chao_missing = f1^2/(2 f2)} is hypersensitive to \code{f2} at that
#' scale, and nothing upstream constrains it (the bandwidth is calibrated on
#' composition prediction, which has no stake in singleton/doubleton counts).
#' Quantify it with \code{\link{kernel_budget_sensitivity}()} before acting
#' on a budget figure.
#'
#' @section Per-group curve pricing:
#' A \code{model_obj} fitted with \code{sampling_group_col} carries one
#' Good-Turing budget PER GROUP, and those budgets are not interchangeable. On
#' real PtConception 18S data (\code{diagnostics/kernel_budget_18S_sampling_groups.R})
#' they span \strong{1859x} across the ten groups present -- 441x restricting
#' to groups the assay can actually amplify, or to groups with at least 100
#' effective records -- and the single pooled price sits BELOW all seven priced
#' groups, so it is not even a compromise between them. Under
#' \code{pricing = "curve"} each taxon is therefore priced at its own group's
#' \code{theta_present}, resolved from \code{sampling_group}.
#'
#' \strong{The guards.} Per-group budgets fail in ways a pooled one does not,
#' and every failure below was measured on that real data, not imagined:
#' \itemize{
#'   \item \emph{No anchor.} 3 of 10 groups had \code{f1 = 0} -- no budget at
#'     all. A group can also have real unseen mass and still no price
#'     (\code{f1 = 1, f2 = 0} lands in Chao's \code{f1(f1-1)/2} branch, which
#'     returns 0).
#'   \item \emph{Too thin to trust.} A group with 24 effective records priced a
#'     single unseen species at \code{0.755} -- 75\% of its own community.
#'     \code{min_group_n_eff}/\code{min_group_f1} exclude these.
#'   \item \emph{Chao below one species.} Real 18S zooplankton:
#'     \code{f1 = 3, f2 = 7} gives \code{Chao = 0.64}, so \code{mass/Chao}
#'     INFLATES the price to 4.7x the group's own singleton mean.
#'     \code{cap_at_singleton} bounds this.
#' }
#' A group failing the guards is priced by \code{group_fallback}. The
#' \code{"pooled_qualifying"} price combines the qualifying groups GROUP-WISE
#' and never by re-pooling records (which would reintroduce the very \code{f1}
#' inflation per-group pricing exists to remove): unseen-species counts add
#' across disjoint groups, while missing masses are shares of different
#' denominators and so combine as an \code{n_eff}-weighted average -- together,
#' the budget of the union of qualifying groups.
#'
#' Every row records \code{sampling_group} and \code{pricing_basis}
#' (\code{"own_group"}, \code{"own_group_capped"}, or
#' \code{"pooled_qualifying"}), and the call prints the whole per-group budget
#' with the price adopted for each. A borrowed price is never silent.
#'
#' \strong{Single-group fits are untouched.} The guards police borrowing
#' BETWEEN groups, which only exists once there is more than one group. With
#' one group the caller has asserted the whole stratum is a single detection
#' process; that assertion is not second-guessed here (its \code{f1}/\code{f2}
#' are printed, and \code{\link{kernel_budget_sensitivity}()} is the tool for
#' interrogating it).
#'
#' @section Combining multiple sources for one taxon:
#' When more than one evidence row names the same taxon (e.g. a regional-
#' proximity signal and an invasive-watch-list signal both fire for one
#' species), the weights combine via
#' \code{w_combined = 1 - prod(1 - weight_i)} and the presence-claim
#' confidences combine via \code{p_conc_combined = sum(p_conc_i)}
#' (independent pseudo-observation counts add). \strong{This assumes the evidence sources are independent
#' readers of different underlying facts} -- e.g. a curated invasion-biology
#' database and raw occurrence geography are evidentially unrelated, not two
#' noisy reads of the same signal. This is NOT a safe assumption for every
#' possible pair of sources: this exact codebase already found that a plain
#' maximum or probabilistic-OR combination across CORRELATED confirmations
#' (e.g. several observations independently reviewed by one classifier that
#' structurally cannot separate two similar species) manufactures spurious
#' confidence that renormalization does not undo (see
#' \code{TaxaAssign::update_prior_from_consensus()}'s confirmation-quantile
#' design and its own documented rejection of noisy-OR for exactly this
#' reason). Before combining a new evidence source with an existing one,
#' confirm they are independent in this sense -- two sources both ultimately
#' derived from the same underlying occurrence database would need this
#' revisited, not assumed safe by default.
#'
#' @section Which species are eligible:
#' Only taxa with \strong{no row anywhere} in \code{taxaexpect_priors} are
#' eligible -- checked against both \code{taxon_name} (catches Tier 1/2
#' modelled rows and named rows from other prior sources, e.g.
#' \code{\link{generate_domestic_food_priors}}) and \code{source_taxon_name}
#' (catches singleton mirrors, whose own identity lives in that column, not
#' \code{taxon_name}). A species detected even once is not dark diversity,
#' regardless of what external evidence says about it, and is left
#' untouched.
#'
#' @section Deliberately out of scope: domestic/food priors:
#' \code{\link{generate_domestic_food_priors}} is NOT a valid evidence
#' source for this function and should never be fed into \code{evidence}.
#' A domestic/food-list detection and an occurrence-plausibility detection
#' (invasive-watch, regional-proximity) are opposite claims about the same
#' zero-local-record fact: the former is plausible because the species is
#' transported/food-handled near the site (a contamination-risk signal,
#' unrelated to whether a wild population exists), the latter is plausible
#' because a real wild population might actually be present. OR-combining
#' them would conflate two different questions into one number. A taxon
#' flagged by both mechanisms is a real, interesting case, but belongs
#' surfaced as two distinct reviewer-facing caveats (see
#' \code{TaxaFlag::add_posthoc_assessment()}'s existing
#' \code{domestic_prior_caveat}), not collapsed here.
#'
#' @param taxaexpect_priors Data frame. Must already contain the
#'   \code{undetected_type == "global_floor"} row from
#'   \code{\link{generate_undetected_diversity}} (errors if absent). Used
#'   both as the source of the floor/singleton anchors and to determine
#'   which evidence taxa are already observed.
#' @param model_obj A biofreq_model object, used only for
#'   \code{meta$habitat_col} (to determine whether \code{main_habitat} is
#'   required) so output rows sit on the same schema as every other
#'   prior-generating function in this package.
#' @param evidence Data frame (typically the row-bound output of one or more
#'   evidence-generating functions, e.g.
#'   \code{\link{generate_invasive_watch_evidence}}). Required columns:
#'   \code{taxon_name} (character), \code{weight} (numeric, 0-1 -- the
#'   source's probability of local presence), \code{source} (character, for
#'   audit only). Optional: \code{p_conc} (numeric, > 0; default 1) -- how
#'   much weight the presence claim carries against future evidence, in
#'   pseudo-observations. \code{n_eff} is retired (errors with migration
#'   guidance): the Beta concentration is now moment-matched, not supplied.
#'   Additional source-specific columns are ignored by this function.
#' @param grid_id Character. Single grid cell identifier this call applies
#'   to -- required, no default (mirrors
#'   \code{\link{generate_domestic_food_priors}}'s single-site-per-call
#'   convention; a multi-site study calls this once per site).
#'   \code{TaxaAssign::join_priors()}'s primary join requires an exact
#'   \code{grid_id} match, so the output rows are only usable for
#'   observations at this specific site.
#' @param main_habitat Character. Single habitat category this call applies
#'   to. Required (no default) when \code{model_obj} was trained with a
#'   non-NULL \code{habitat_col}; must be omitted (\code{NULL}, the default)
#'   when \code{model_obj} was trained with \code{habitat_col = NULL}. There
#'   is no habitat-agnostic option here, unlike
#'   \code{generate_domestic_food_priors()}'s \code{main_habitat = NA} rows
#'   (which \code{join_priors()} now has a dedicated fallback tier for) --
#'   occurrence-plausibility evidence is deliberately habitat-AWARE, since a
#'   freshwater species found nearby is only locally plausible in a
#'   freshwater habitat, a real constraint that domestic/food contamination
#'   risk does not share.
#' @param taxonomy Optional data frame with columns \code{taxon_name} and
#'   any subset of \code{genus}, \code{family}, \code{order}, \code{class},
#'   \code{phylum}, joined onto the result the same way
#'   \code{generate_undetected_diversity(taxonomy = ...)} does. Default
#'   \code{NULL}.
#' @param pricing \code{"blend"} (default, the original floor-additive
#'   presence mixture: \code{theta = floor + w*(ceiling - floor)}) or
#'   \code{"curve"} (unobserved-taxa redesign, 2026-08-31: \code{theta = w *
#'   theta_present} with \code{theta_present = missing_mass / chao_missing}
#'   from the kernel fit -- the Good-Turing budget's per-spot value -- and
#'   \code{theta_absent = 0}). Curve pricing makes the branch budget close
#'   exactly in count units (branch evidence total = \code{theta_present *
#'   sum(w)}, coherent iff \code{sum(w) = chao_missing}) and removes the
#'   floor term that dominated every blended row. Requires a
#'   \code{taxaexpect_kernel_priors} \code{model_obj} with a finite
#'   \code{theta_present} (at least one neighborhood singleton), or -- since
#'   2026-09-04 -- a multi-group fit, in which case each taxon is priced by its
#'   OWN sampling group's budget (see \verb{Per-group curve pricing}).
#' @param sampling_group Which sampling group each evidence taxon belongs to.
#'   Required (and only meaningful) when \code{model_obj} was fitted with
#'   \code{sampling_group_col} and \code{pricing = "curve"}. Accepts a single
#'   group name (the whole evidence list shares one detection process -- the
#'   common case, e.g. an all-fish invasive-watch list), a named character
#'   vector (\code{taxon -> group}), or a data frame with \code{taxon_name}
#'   and \code{sampling_group} columns. A \code{sampling_group} column on
#'   \code{evidence} itself takes precedence. Deliberately NEVER inferred from
#'   taxonomy: the classification that produced the occurrence pool's groups
#'   lives in the caller's workflow, and a wrong group mis-prices silently
#'   rather than failing.
#' @param group_fallback What to do with an evidence taxon whose group fails
#'   the pricing guards. \code{"pooled_qualifying"} (default) prices it at the
#'   qualifying groups' combined budget and says so, per row, in
#'   \code{pricing_basis}; \code{"error"} refuses; \code{"skip"} drops those
#'   taxa with a message. Ignored for single-group fits.
#' @param min_group_n_eff,min_group_f1 Support a sampling group must have
#'   before its own budget is trusted: at least this many effective records
#'   (default \code{100}) and this many neighborhood singletons (default
#'   \code{1}). Ignored for single-group fits.
#' @param cap_at_singleton Logical, default \code{TRUE}. Cap a group's price at
#'   its own singleton mean (\code{missing_mass / f1}). This is NOT the
#'   \code{mass/f1} pricing switch (that decision is open and untouched): the
#'   cap binds only in the direction where \code{mass/Chao} EXCEEDS the
#'   singleton mean, which happens exactly when \code{Chao < f1}, i.e. when
#'   \code{f1 < 2*f2} -- contradicting the estimator's own premise that an
#'   unseen species is rarer than a once-seen one. Ignored for single-group
#'   fits.
#'
#' @return A tibble with one row per eligible taxon named in \code{evidence}:
#'   \describe{
#'     \item{taxon_name}{The real taxon name.}
#'     \item{taxon_name_rank}{Always \code{"species"} -- required for the
#'       row to match \code{TaxaAssign::join_priors()}'s composite join key.}
#'     \item{grid_id, main_habitat}{As supplied (\code{main_habitat} omitted
#'       entirely when \code{model_obj} has no habitat concept).}
#'     \item{alpha, beta}{Beta(alpha, beta) prior parameters.}
#'     \item{theta_mean, theta_sd}{Derived from alpha/beta.}
#'     \item{model_tier}{Always \code{"tier_undetected_evidence"}. Deprecated
#'       vocabulary (kernel-priors redesign, 2026-08-31): kernel-path
#'       output replaces \code{model_tier} with \code{prior_branch} +
#'       \code{effective_records}; this column is retained only while
#'       the GLMM path remains in use.}
#'     \item{undetected_type}{Always \code{"evidence_blend"} -- a new value
#'       alongside \code{"singleton_mirror"}/\code{"global_floor"}.}
#'     \item{evidence_weight}{The combined \code{w_combined} for this taxon
#'       (audit column).}
#'     \item{prior_mix_w, prior_mix_theta_present, prior_mix_theta_absent}{
#'       The presence mixture itself, consumed by
#'       \code{TaxaAssign::compute_posterior()}'s presence-draw sampler.}
#'     \item{prior_mix_p_conc}{Combined presence-claim confidence
#'       (pseudo-observations) -- reserved for the confirmation update; does
#'       not affect the static prior's marginal moments.}
#'     \item{evidence_sources}{Semicolon-joined distinct \code{source}
#'       values that contributed to this row (audit column).}
#'     \item{sampling_group, pricing_basis}{Curve pricing only: the detection
#'       process this row was priced by, and whether that price was the group's
#'       own (\code{"own_group"}), capped at its singleton mean
#'       (\code{"own_group_capped"}), or borrowed from the qualifying groups
#'       (\code{"pooled_qualifying"}).}
#'   }
#'   plus taxonomy rank columns when \code{taxonomy} is supplied. Empty
#'   tibble (correct schema, zero rows) when no evidence taxon is eligible.
#'
#' @seealso \code{\link{generate_undetected_diversity}},
#'   \code{\link{generate_invasive_watch_evidence}},
#'   \code{\link{generate_domestic_food_priors}} (a deliberately separate,
#'   NOT-combinable mechanism -- see \verb{Deliberately out of scope}).
#'
#' @examples
#' \dontrun{
#' invasive_evidence <- generate_invasive_watch_evidence(
#'   invasive_taxa = c("Gymnocephalus cernua", "Neogobius melanostomus"),
#'   weight = 0.1
#' )
#' elevated <- apply_undetected_evidence(
#'   taxaexpect_priors, model_fit,
#'   evidence = invasive_evidence,
#'   grid_id = "Grid_41p6_m87p3", main_habitat = "Lentic"
#' )
#' taxaexpect_priors <- dplyr::bind_rows(taxaexpect_priors, elevated)
#' }
#'
#' @importFrom dplyr bind_rows left_join
#' @importFrom tibble tibble
#' @export
apply_undetected_evidence <- function(
    taxaexpect_priors,
    model_obj,
    evidence,
    grid_id,
    main_habitat    = NULL,
    taxonomy        = NULL,
    pricing         = c("blend", "curve"),
    sampling_group  = NULL,
    group_fallback  = c("pooled_qualifying", "error", "skip"),
    min_group_n_eff = 100,
    min_group_f1    = 1L,
    cap_at_singleton = TRUE
) {
  pricing <- match.arg(pricing)
  group_fallback <- match.arg(group_fallback)
  for (.nm in c("min_group_n_eff", "min_group_f1")) {
    .v <- get(.nm)
    if (!is.numeric(.v) || length(.v) != 1L || is.na(.v) || .v < 0)
      stop("apply_undetected_evidence: `", .nm, "` must be a single non-negative number.")
  }
  if (!is.logical(cap_at_singleton) || length(cap_at_singleton) != 1L ||
      is.na(cap_at_singleton))
    stop("apply_undetected_evidence: `cap_at_singleton` must be TRUE or FALSE.")
  # Curve pricing (unobserved-taxa redesign, 2026-08-31): theta = w *
  # theta_present, with theta_present = missing_mass / chao_missing from the
  # kernel fit (the Good-Turing budget's per-spot value) and theta_absent = 0
  # (an absent species contributes nothing -- the honest mixture reading,
  # replacing the floor-additive blend whose floor term dominated every row).
  # Requires a kernel model_obj carrying a finite theta_present.
  kernel_theta_present <- NA_real_
  kernel_theta_singleton <- NA_real_
  # Captured HERE, not at the printout: `model_obj` is replaced by a stub
  # further down (the GLMM-compat branch), so anything read off the kernel fit
  # has to be taken before that point.
  kernel_f1 <- NA_integer_
  kernel_f2 <- NA_integer_
  # Per-group curve pricing state. NULL = single-group (or blend) pricing, i.e.
  # the pre-2026-09-04 path, byte-for-byte. The guards below police BORROWING
  # BETWEEN GROUPS, which only exists once there is more than one group -- a
  # single-group fit is the caller asserting the whole stratum is one detection
  # process, and nothing about that assertion is second-guessed here (its f1/f2
  # are printed, and kernel_budget_sensitivity() is the tool for it).
  curve_groups <- NULL
  model_obj_group_label <- NA_character_
  if (inherits(model_obj, "taxaexpect_kernel_priors")) {
    # A one-group fit still has a group NAME when sampling_group_col was
    # supplied; recorded so the output says which process it priced.
    if (!is.null(model_obj$budget) && nrow(model_obj$budget) == 1L)
      model_obj_group_label <- as.character(model_obj$budget$sampling_group[1L])
    kernel_theta_present <- model_obj$theta_present %||% NA_real_
    f1_k <- model_obj$f1 %||% 0L
    kernel_f1 <- model_obj$f1 %||% NA_integer_
    kernel_f2 <- model_obj$f2 %||% NA_integer_
    # NA-safe: a multi-group fit reports NA pooled scalars by design, and
    # `TRUE && NA` is NA, which `if` rejects outright (this ecosystem's
    # documented is.logical(NA) footgun).
    if (is.numeric(f1_k) && length(f1_k) == 1L && !is.na(f1_k) && f1_k > 0)
      kernel_theta_singleton <- (model_obj$missing_mass %||% NA_real_) / f1_k
    if (pricing == "curve" && (model_obj$params$n_sampling_groups %||% 1L) > 1L) {
      curve_groups <- .resolve_group_prices(
        model_obj, min_group_n_eff, min_group_f1, cap_at_singleton,
        group_fallback)
      if (curve_groups$n_qualifying == 0L)
        stop("apply_undetected_evidence: not one of this fit's ",
             nrow(curve_groups$budget), " sampling groups clears the pricing ",
             "guards (n_eff >= ", min_group_n_eff, ", f1 >= ", min_group_f1,
             ", and a defined theta_present), so there is no trustworthy price ",
             "anywhere in it. Inspect model_fit$budget, lower min_group_n_eff ",
             "if you mean to, or use pricing = \"blend\".")
    }
  }
  if (pricing == "curve" && is.null(curve_groups) &&
      (!is.numeric(kernel_theta_present) || !is.finite(kernel_theta_present) ||
       kernel_theta_present <= 0)) {
    stop("apply_undetected_evidence: pricing = \"curve\" requires a ",
         "taxaexpect_kernel_priors model_obj whose theta_present is a finite ",
         "positive value (missing_mass / chao_missing -- needs at least one ",
         "neighborhood singleton). Re-fit with estimate_kernel_priors() or ",
         "use pricing = \"blend\".")
  }
  if (inherits(model_obj, "taxaexpect_kernel_priors")) {
    # Kernel-priors adapter (Phase 2, 2026-08-31): only the habitat concept is
    # read from model_obj here; kernel estimates are always habitat-stratified.
    model_obj <- list(meta = list(habitat_col = "main_habitat"))
    class(model_obj) <- "biofreq_model_shim"
  } else if (!inherits(model_obj, "biofreq_model")) {
    stop("apply_undetected_evidence: model_obj must be a biofreq_model ",
         "object from train_biodiversity_model() or a taxaexpect_kernel_priors ",
         "object from estimate_kernel_priors().")
  }
  if (!is.data.frame(taxaexpect_priors)) {
    stop("apply_undetected_evidence: taxaexpect_priors must be a data frame.")
  }
  if (!is.character(grid_id) || length(grid_id) != 1L || is.na(grid_id)) {
    stop("apply_undetected_evidence: `grid_id` must be a single non-NA character value.")
  }

  habitat_col <- model_obj$meta$habitat_col
  if (!is.null(habitat_col)) {
    if (is.null(main_habitat) || !is.character(main_habitat) ||
        length(main_habitat) != 1L || is.na(main_habitat)) {
      stop("apply_undetected_evidence: `main_habitat` is required (a single ",
           "non-NA character value) because model_obj was trained with a ",
           "non-NULL habitat_col. There is no habitat-agnostic option here -- ",
           "occurrence-plausibility evidence is deliberately habitat-aware.")
    }
  } else if (!is.null(main_habitat)) {
    stop("apply_undetected_evidence: model_obj was trained with ",
         "habitat_col = NULL, so `main_habitat` must be NULL too.")
  }

  required_evidence_cols <- c("taxon_name", "weight", "source")
  if (!is.data.frame(evidence) || !all(required_evidence_cols %in% names(evidence))) {
    stop("apply_undetected_evidence: `evidence` must be a data frame with columns ",
         paste(required_evidence_cols, collapse = ", "), ".")
  }
  if ("n_eff" %in% names(evidence) && !"p_conc" %in% names(evidence)) {
    stop("apply_undetected_evidence: `evidence$n_eff` is retired (2026-08-26 ",
         "mixture redesign). The elevated prior's Beta concentration is now ",
         "moment-matched from the presence mixture, not caller-chosen; supply ",
         "`p_conc` (confidence in the presence probability itself, in ",
         "pseudo-observations -- used by the confirmation update, not by the ",
         "static prior) or omit both. See ",
         "ecosystem_docs/REENTRY_PROMPT_undetected_evidence_mixture_redesign.md.")
  }
  if (nrow(evidence) == 0L) {
    message("apply_undetected_evidence: `evidence` has zero rows -- nothing to apply.")
    return(.empty_undetected_evidence_result(habitat_col, pricing))
  }
  if (any(evidence$weight < 0 | evidence$weight > 1, na.rm = TRUE) || anyNA(evidence$weight)) {
    stop("apply_undetected_evidence: every `evidence$weight` must be a non-NA value in [0, 1].")
  }
  if (!"p_conc" %in% names(evidence)) evidence$p_conc <- 1
  if (any(evidence$p_conc <= 0, na.rm = TRUE) || anyNA(evidence$p_conc)) {
    stop("apply_undetected_evidence: every `evidence$p_conc` must be a non-NA positive value.")
  }

  # ---- Anchors --------------------------------------------------------------
  # Curve mode needs NO floor/ceiling anchors (theta = w * theta_present,
  # theta_absent = 0); its printer anchor (the observed singleton scale) comes
  # from the kernel object directly, so a table without a global_floor row is
  # fine there. The blend path keeps its original anchor requirements.
  theta_floor <- var_floor <- theta_singleton <- var_singleton <- NA_real_
  if (pricing == "curve") theta_singleton <- kernel_theta_singleton
  if (pricing == "blend") {
  # ---- Floor anchor: read directly from taxaexpect_priors, don't recompute ---
  floor_rows <- taxaexpect_priors[
    !is.na(taxaexpect_priors$undetected_type) &
      taxaexpect_priors$undetected_type == "global_floor",
    , drop = FALSE
  ]
  if (nrow(floor_rows) == 0L) {
    stop("apply_undetected_evidence: taxaexpect_priors has no undetected_type == ",
         "'global_floor' row. Pass generate_undetected_diversity()'s output ",
         "(or a table it was bound into) so the floor anchor is available.")
  }
  floor_alpha <- mean(floor_rows$alpha, na.rm = TRUE)
  floor_beta  <- mean(floor_rows$beta,  na.rm = TRUE)
  theta_floor <- .beta_mean(floor_alpha, floor_beta)
  var_floor   <- .beta_sd(floor_alpha, floor_beta)^2

  # ---- Singleton anchor: prefer this site's own singleton mirrors, fall
  # back to the global singleton mean when this site has none. Mirrors
  # TaxaAssign::join_priors()'s own singleton_by_site/global_singleton
  # fallback design.
  singleton_rows <- taxaexpect_priors[
    !is.na(taxaexpect_priors$undetected_type) &
      taxaexpect_priors$undetected_type == "singleton_mirror",
    , drop = FALSE
  ]
  if (nrow(singleton_rows) == 0L) {
    # ---- Ceiling anchor ladder (2026-08-26 mixture redesign, D2) -----------
    # No singletons does NOT mean no ceiling: the anchor's meaning is "the
    # detection rate of a species present but rare enough to have plausibly
    # escaped local detection." Descend a ladder of estimates rather than
    # silently collapsing the ceiling onto the floor (the previous behavior,
    # which made every elevation a weight-independent no-op):
    #   (2) minimum theta among genuinely modelled rows -- in a dataset with
    #       no singletons every detected species was seen >= 2 times, so the
    #       rarest detected rate mildly OVERestimates the present-but-
    #       undetected rate: conservative in the safe direction.
    #   (3) ~1 detection per site effort (n_obs), i.e. what a singleton's
    #       rate would have been.
    #   (4) only if neither is computable: the old floor-equals-ceiling
    #       no-op, with the original warning.
    theta_singleton <- NA_real_
    var_singleton   <- NA_real_
    modelled <- taxaexpect_priors[
      is.na(taxaexpect_priors$undetected_type) &
        !is.na(taxaexpect_priors$taxon_name) &
        !is.na(taxaexpect_priors$alpha) & !is.na(taxaexpect_priors$beta),
      , drop = FALSE
    ]
    if ("model_tier" %in% names(modelled) && nrow(modelled) > 0L) {
      modelled <- modelled[
        is.na(modelled$model_tier) |
          !modelled$model_tier %in% c("tier_undetected_evidence", "tier_domestic_food"),
        , drop = FALSE
      ]
    }
    if (nrow(modelled) > 0L) {
      site_modelled <- modelled[
        !is.na(modelled$grid_id) & modelled$grid_id == grid_id, , drop = FALSE]
      use_modelled <- if (nrow(site_modelled) > 0L) site_modelled else modelled
      theta_singleton <- min(
        .beta_mean(use_modelled$alpha, use_modelled$beta), na.rm = TRUE)
      message(sprintf(
        "apply_undetected_evidence: no singleton_mirror rows -- ceiling anchor set to the minimum modelled theta (%.3g).",
        theta_singleton
      ))
    } else if ("n_obs" %in% names(taxaexpect_priors) &&
               any(is.finite(taxaexpect_priors$n_obs) & taxaexpect_priors$n_obs > 0)) {
      eff <- stats::median(
        taxaexpect_priors$n_obs[is.finite(taxaexpect_priors$n_obs) &
                                  taxaexpect_priors$n_obs > 0])
      theta_singleton <- 1 / (eff + 1)
      message(sprintf(
        "apply_undetected_evidence: no singleton_mirror or modelled rows -- ceiling anchor set to 1/(site effort + 1) = %.3g.",
        theta_singleton
      ))
    }
    if (is.finite(theta_singleton) && theta_singleton > theta_floor) {
      # Ladder-derived anchors carry no fitted Beta of their own -- hold them at
      # the singleton_ess = 2 convention (generate_undetected_diversity()'s own
      # mirror concentration), the same "observed about once" epistemic state.
      var_singleton <- theta_singleton * (1 - theta_singleton) / 3
    }
    if (!is.finite(theta_singleton) || theta_singleton <= theta_floor) {
      warning(
        "apply_undetected_evidence: taxaexpect_priors has no singleton_mirror ",
        "rows and no usable modelled/effort fallback -- no upper anchor exists ",
        "for the evidence blend. Every elevated row will equal the floor ",
        "exactly (weight has no effect).",
        call. = FALSE
      )
      theta_singleton <- theta_floor
      var_singleton   <- var_floor
    }
  } else {
    site_singletons <- singleton_rows[
      !is.na(singleton_rows$grid_id) & singleton_rows$grid_id == grid_id,
      , drop = FALSE
    ]
    if (!is.null(habitat_col) && nrow(site_singletons) > 0L) {
      site_singletons <- site_singletons[
        !is.na(site_singletons[[habitat_col]]) & site_singletons[[habitat_col]] == main_habitat,
        , drop = FALSE
      ]
    }
    use_singletons <- if (nrow(site_singletons) > 0L) site_singletons else singleton_rows
    theta_singleton <- .beta_mean(mean(use_singletons$alpha, na.rm = TRUE),
                                   mean(use_singletons$beta,  na.rm = TRUE))
    var_singleton   <- .beta_sd(mean(use_singletons$alpha, na.rm = TRUE),
                                 mean(use_singletons$beta,  na.rm = TRUE))^2
  }

  }  # end blend-mode anchor block

  # ---- Dataset-specific veto bound (2026-08-26 mixture redesign, D4) --------
  # At likelihood parity, an elevated species stays in the consensus plausible
  # set against an observed competitor at theta_obs whenever
  #   theta_e >= (m/(1-m)) * theta_obs,   m = the retention floor
  # (TaxaAssign::posterior_consensus() min_posterior, default 0.05). Solved
  # against the WEAKEST observed level -- the singleton ceiling itself -- this
  # gives a weight bound specific to THIS dataset's anchors. Printed so a
  # caller choosing `weight` for a watch list can see where "surfaces for
  # review" ends and "vetoes the resolution of genuinely observed natives"
  # begins. (The GreatLakes2023 case: the bound ~0.05; the pre-calibration
  # w = 0.6 sat far above it and suppressed yellow perch in 78 observations.)
  if (pricing == "curve" && !is.null(curve_groups)) {
    # Multi-group: there is no single price, so print the whole per-group
    # budget with the price actually adopted for each and where it came from.
    b <- curve_groups$budget
    m_ret <- 0.05
    tab <- data.frame(
      sampling_group = b$sampling_group,
      n_eff = round(b$n_eff, 1),
      f1 = b$f1, f2 = b$f2,
      chao = round(b$chao_missing, 1),
      theta_present = signif(b$theta_present, 3),
      price_used = signif(b$price, 3),
      basis = ifelse(is.na(b$pricing_basis), "UNPRICED", b$pricing_basis),
      w_veto = round(((1 - m_ret) / m_ret) * b$singleton_price / b$price, 1),
      stringsAsFactors = FALSE)
    message(sprintf(
      "apply_undetected_evidence: PER-GROUP curve pricing across %d sampling groups ('%s'); %d clear the guards (n_eff >= %g, f1 >= %g).",
      nrow(b), model_obj$params$sampling_group_col %||% "sampling_group",
      curve_groups$n_qualifying, min_group_n_eff, min_group_f1))
    message(paste(utils::capture.output(print(tab, row.names = FALSE)),
                  collapse = "\n"))
    if (any(tab$basis == "own_group_capped"))
      message(sprintf(
        "apply_undetected_evidence: %d group(s) capped at their own singleton mean -- mass/Chao exceeded mass/f1 there (Chao < f1, i.e. f1 < 2*f2), which contradicts an unseen species being rarer than a once-seen one.",
        sum(tab$basis == "own_group_capped")))
    if (any(tab$basis == "pooled_qualifying"))
      message(sprintf(
        "apply_undetected_evidence: %d group(s) failed the guards and are priced at the pooled-qualifying fallback (%.3g) -- a BORROWED price, not their own. Groups: %s.",
        sum(tab$basis == "pooled_qualifying"), curve_groups$fallback_price,
        paste(tab$sampling_group[tab$basis == "pooled_qualifying"], collapse = ", ")))
    .thin <- b$f2[b$f1 > 0 & !is.na(b$f2)]
    if (length(.thin) && min(.thin) < 10)
      message(sprintf(
        "apply_undetected_evidence: the thinnest of these prices rests on %d doubleton(s) -- chao_missing = f1^2/(2 f2) is hypersensitive there. Run kernel_budget_sensitivity() before quoting any of them.",
        min(.thin)))
  } else if (pricing == "curve") {
    # Curve-mode veto bound: an unobserved species VETOES (pushes a
    # singleton-level native below min_posterior at likelihood parity) when
    # theta_e = w * theta_present > ((1-m)/m) * theta_singleton, i.e.
    # w > 19 * theta_singleton / theta_present at the default m = 0.05.
    # theta_present is USUALLY at or below the singleton scale, putting this
    # bound near 19-23 and out of reach for any admissible w <= 1 -- but not
    # "by construction": theta_present = missing_mass/Chao exceeds the
    # singleton mean missing_mass/f1 whenever Chao < f1, i.e. whenever
    # f1 < 2*f2 (real case: PtConception 18S zooplankton, f1 = 3, f2 = 7,
    # Chao = 0.64, price 4.7x the singleton mean). The bound is computed, not
    # assumed, and the "unreachable" clause below is conditional for that
    # reason. f1/f2 are printed with the price so a caller can see how thin
    # the estimate is -- see kernel_budget_sensitivity().
    m_ret <- 0.05
    w_veto_curve <- ((1 - m_ret) / m_ret) * theta_singleton / kernel_theta_present
    .f1_msg <- kernel_f1
    .f2_msg <- kernel_f2
    message(sprintf(
      paste0(
        "apply_undetected_evidence: curve pricing (theta = w * theta_present, ",
        "theta_present = %.3g from f1 = %s singletons / f2 = %s doubletons). ",
        "Veto bound: weight above %.1f would block ",
        "species-level resolution of a singleton-level observed native at ",
        "likelihood parity%s."
      ),
      kernel_theta_present,
      if (is.na(.f1_msg)) "?" else format(.f1_msg),
      if (is.na(.f2_msg)) "?" else format(.f2_msg),
      w_veto_curve,
      if (w_veto_curve > 1) " -- unreachable for any admissible weight <= 1"
      else ""
    ))
    if (!is.na(.f2_msg) && .f2_msg > 0 && .f2_msg < 10)
      message(sprintf(
        paste0("apply_undetected_evidence: that price rests on %d doubleton(s) ",
               "-- chao_missing = f1^2/(2 f2) is hypersensitive there. Run ",
               "kernel_budget_sensitivity() before quoting it."), .f2_msg))
  } else if (theta_singleton > theta_floor) {
    m_ret  <- 0.05
    w_veto <- ((m_ret / (1 - m_ret)) * theta_singleton - theta_floor) /
      (theta_singleton - theta_floor)
    message(sprintf(
      paste0(
        "apply_undetected_evidence: veto bound for these anchors -- weight above %.3f ",
        "lets an unobserved species block species-level resolution of a singleton-level ",
        "observed native at likelihood parity (assumes the consensus default ",
        "min_posterior = 0.05; abundant natives tolerate proportionally more)."
      ),
      max(w_veto, 0)
    ))
  }

  # ---- Exclude already-observed taxa: any row anywhere in taxaexpect_priors
  # naming this taxon, whether via taxon_name (modelled/named-prior rows) or
  # source_taxon_name (singleton mirrors, whose identity lives there instead).
  observed_taxa <- unique(c(
    stats::na.omit(taxaexpect_priors$taxon_name),
    if ("source_taxon_name" %in% names(taxaexpect_priors)) {
      stats::na.omit(taxaexpect_priors$source_taxon_name)
    } else {
      character(0)
    }
  ))

  n_evidence_taxa <- length(unique(evidence$taxon_name))
  evidence <- evidence[!evidence$taxon_name %in% observed_taxa, , drop = FALSE]
  if (nrow(evidence) == 0L) {
    message("apply_undetected_evidence: every taxon in `evidence` is already ",
            "observed (has a row in taxaexpect_priors) -- nothing to elevate.")
    return(.empty_undetected_evidence_result(habitat_col, pricing))
  }

  # ---- Combine multiple evidence rows per taxon ------------------------------
  taxa <- unique(evidence$taxon_name)
  combined <- lapply(taxa, function(nm) {
    sub <- evidence[evidence$taxon_name == nm, , drop = FALSE]
    list(
      w_combined  = 1 - prod(1 - sub$weight),
      p_combined  = sum(sub$p_conc),
      sources     = paste(sort(unique(sub$source)), collapse = ";")
    )
  })
  # USE.NAMES = FALSE throughout: `combined` is a plain positional list aligned
  # with `taxa`, but lapply() above still tags each element's own $w_combined/
  # etc. with a NULL name -- vapply()'s default USE.NAMES = TRUE would instead
  # pull names from `combined` itself if we named it, propagating a spurious
  # `names` attribute onto every downstream numeric/character vector (and, via
  # tibble::tibble(), onto the resulting columns) that has nothing to do with
  # the data itself.
  w_combined_vec <- vapply(combined, function(x) x$w_combined, numeric(1), USE.NAMES = FALSE)
  p_conc_new     <- vapply(combined, function(x) x$p_combined, numeric(1), USE.NAMES = FALSE)
  sources_vec    <- vapply(combined, function(x) x$sources, character(1), USE.NAMES = FALSE)

  # ---- Per-group price assignment -------------------------------------------
  grp_vec <- rep(NA_character_, length(taxa))
  basis_vec <- rep(NA_character_, length(taxa))
  price_vec <- rep(NA_real_, length(taxa))
  if (!is.null(curve_groups)) {
    grp_vec <- unname(.resolve_evidence_groups(
      taxa, evidence, sampling_group, curve_groups$budget$sampling_group))
    price_vec <- unname(curve_groups$price[grp_vec])
    basis_vec <- unname(curve_groups$basis[grp_vec])
    unpriced <- !is.finite(price_vec) | price_vec <= 0
    if (any(unpriced)) {
      if (identical(group_fallback, "error"))
        stop("apply_undetected_evidence: ", sum(unpriced), " evidence taxon/taxa ",
             "belong to sampling group(s) that failed the pricing guards (",
             paste(unique(grp_vec[unpriced]), collapse = ", "), ") and ",
             "group_fallback = \"error\". Use \"pooled_qualifying\" to borrow the ",
             "qualifying groups' combined price, \"skip\" to drop these taxa, or ",
             "lower min_group_n_eff / min_group_f1 if you mean to trust the ",
             "group's own thin budget. See model_fit$budget.")
      # group_fallback = "skip": drop them, loudly. Never silently, and never
      # by pricing them at zero -- an unpriced taxon is one this fit cannot
      # speak to, which is a different statement from "implausible".
      message(sprintf(
        "apply_undetected_evidence: dropping %d taxon/taxa in unpriced sampling group(s) %s (group_fallback = \"skip\") -- this fit has no trustworthy price for them, which is NOT the same as judging them implausible.",
        sum(unpriced), paste(unique(grp_vec[unpriced]), collapse = ", ")))
      keep <- !unpriced
      taxa <- taxa[keep]; w_combined_vec <- w_combined_vec[keep]
      p_conc_new <- p_conc_new[keep]; sources_vec <- sources_vec[keep]
      grp_vec <- grp_vec[keep]; price_vec <- price_vec[keep]
      basis_vec <- basis_vec[keep]
      if (length(taxa) == 0L) {
        message("apply_undetected_evidence: no evidence taxon survives group pricing -- nothing to elevate.")
        return(.empty_undetected_evidence_result(habitat_col, pricing))
      }
    }
  } else if (pricing == "curve") {
    grp_vec <- rep(model_obj_group_label, length(taxa))
    basis_vec <- rep("own_group", length(taxa))
    price_vec <- rep(kernel_theta_present, length(taxa))
  }

  # ---- Presence-mixture prior (2026-08-26 mixture redesign, D3/D8) ----------
  # The elevated prior IS a presence mixture: with probability w the species is
  # locally present (theta ~ the ceiling-anchor state), with probability 1 - w
  # absent (theta ~ the floor state). The blended mean is that mixture's exact
  # expectation; the Beta summary's concentration is now MOMENT-MATCHED to the
  # mixture's variance instead of caller-chosen (the retired free n_eff):
  #   v = w*Var_ceiling + (1-w)*Var_floor + w*(1-w)*(theta_c - theta_f)^2
  #   n_eff_mm = m(1-m)/v - 1
  # Note the marginal moments are independent of p_conc: for a two-point
  # presence mixture, uncertainty ABOUT w cancels out of the marginal variance
  # (E[p(1-p)] + Var(p) = w(1-w)), so record age etc. honestly cannot change
  # today's prior -- p_conc instead records how much weight the presence claim
  # carries against future evidence (the confirmation update; stored as
  # prior_mix_p_conc). The prior_mix_* columns carry the mixture itself for
  # TaxaAssign::compute_posterior()'s presence-draw sampler; alpha/beta remain
  # the point-path/back-compat summary.
  if (pricing == "curve") {
    # Two-point mixture at {0, theta_present}: theta = w * theta_present
    # exactly; marginal variance is pure presence uncertainty. `price_vec` is
    # per-taxon (its own sampling group's price) for a multi-group fit, and a
    # recycled scalar for a single-group one -- identical arithmetic either way.
    mix_present <- price_vec
    mix_absent  <- 0
    theta_new   <- w_combined_vec * mix_present
    v_mix       <- w_combined_vec * (1 - w_combined_vec) * mix_present^2
  } else {
    mix_present <- theta_singleton
    mix_absent  <- theta_floor
    theta_new <- theta_floor + (theta_singleton - theta_floor) * w_combined_vec
    delta_sq  <- (theta_singleton - theta_floor)^2
    v_mix <- w_combined_vec * var_singleton +
      (1 - w_combined_vec) * var_floor +
      w_combined_vec * (1 - w_combined_vec) * delta_sq
  }
  n_eff_mm <- ifelse(
    is.finite(v_mix) & v_mix > 0,
    pmax(theta_new * (1 - theta_new) / v_mix - 1, 1e-3),
    2  # degenerate anchors (ceiling == floor, or w in {0,1}): singleton_ess convention
  )
  alpha_new <- theta_new * n_eff_mm
  beta_new  <- (1 - theta_new) * n_eff_mm

  result <- tibble::tibble(
    taxon_name       = taxa,
    taxon_name_rank  = "species",
    grid_id          = grid_id,
    alpha            = alpha_new,
    beta             = beta_new,
    theta_mean       = .beta_mean(alpha_new, beta_new),
    theta_sd         = .beta_sd(alpha_new, beta_new),
    model_tier       = "tier_undetected_evidence",
    prior_branch     = "resident_undetected",
    undetected_type  = "evidence_blend",
    evidence_weight  = w_combined_vec,
    evidence_sources = sources_vec,
    prior_mix_w             = w_combined_vec,
    prior_mix_theta_present = mix_present,
    prior_mix_theta_absent  = mix_absent,
    prior_mix_p_conc        = p_conc_new
  )
  if (pricing == "curve") {
    # Curve-only provenance: which detection process priced this row, and
    # whether that price was the group's own, capped, or borrowed.
    result$sampling_group <- grp_vec
    result$pricing_basis  <- basis_vec
  }
  if (!is.null(habitat_col)) {
    result[[habitat_col]] <- main_habitat
  }

  tax_rank_cols <- .dark_diversity_rank_cols
  if (!is.null(taxonomy)) {
    if (!is.data.frame(taxonomy) || !"taxon_name" %in% names(taxonomy)) {
      stop("apply_undetected_evidence: taxonomy must be a data frame with a 'taxon_name' column.")
    }
    tax_cols_present <- intersect(tax_rank_cols, names(taxonomy))
    if (length(tax_cols_present) == 0L) {
      warning("apply_undetected_evidence: taxonomy has none of genus/family/order/class/phylum -- ignored.")
    } else {
      tax_lookup <- unique(taxonomy[, c("taxon_name", tax_cols_present), drop = FALSE])
      tax_lookup <- tax_lookup[!duplicated(tax_lookup$taxon_name), ]
      result <- dplyr::left_join(result, tax_lookup, by = "taxon_name")
    }
  }
  for (.col in tax_rank_cols) {
    if (!.col %in% names(result)) result[[.col]] <- NA_character_
  }

  message(sprintf(
    if (pricing == "curve")
      "--- Undetected evidence applied: %d row(s) priced by the presence curve (of %d taxa named in evidence) ---"
    else
      "--- Undetected evidence applied: %d row(s) elevated above the floor (of %d taxa named in evidence) ---",
    nrow(result), n_evidence_taxa
  ))

  result
}

#' Empty-schema result for apply_undetected_evidence(), matching its documented @return
#' @noRd
.empty_undetected_evidence_result <- function(habitat_col, pricing = "blend") {
  result <- tibble::tibble(
    taxon_name       = character(0),
    taxon_name_rank  = character(0),
    grid_id          = character(0),
    alpha            = numeric(0),
    beta             = numeric(0),
    theta_mean       = numeric(0),
    theta_sd         = numeric(0),
    model_tier       = character(0),
    undetected_type  = character(0),
    evidence_weight  = numeric(0),
    evidence_sources = character(0),
    prior_mix_w             = numeric(0),
    prior_mix_theta_present = numeric(0),
    prior_mix_theta_absent  = numeric(0),
    prior_mix_p_conc        = numeric(0)
  )
  if (identical(pricing, "curve")) {
    result$sampling_group <- character(0)
    result$pricing_basis  <- character(0)
  }
  if (!is.null(habitat_col)) result[[habitat_col]] <- character(0)
  result
}

# ==============================================================================
# Per-group curve pricing (2026-09-04). Open decision #2 of
# ecosystem_docs/REENTRY_PROMPT_kernel_budget_pricing_and_scope.md, unblocked by
# the PtConception 18S diagnostic: per-group Good-Turing budgets span 1859x
# (441x among groups the assay can actually amplify), and the single pooled
# price sits BELOW all seven priced groups -- it is not even a compromise
# between them. The guards below are not hypothetical caution; every one of them
# fires on that real data (diagnostics/kernel_budget_18S_sampling_groups.R
# section 5).
# ==============================================================================

#' Resolve a per-group price from a multi-group kernel fit's budget
#'
#' Returns a list with `price`/`basis` (named by sampling group), the annotated
#' `budget` table, and the pooled-qualifying fallback price.
#' @noRd
.resolve_group_prices <- function(kp, min_group_n_eff, min_group_f1,
                                  cap_at_singleton, group_fallback) {
  b <- kp$budget
  # The group's own singleton mean -- missing_mass/f1, exactly the mean theta of
  # the observed singletons (verified on real Mugu data). Used as a CAP, not as
  # the price: see `cap_at_singleton` in the roxygen for why this is not the
  # mass/f1 pricing switch (open decision #1), which remains open.
  b$singleton_price <- ifelse(b$f1 > 0, b$missing_mass / b$f1, NA_real_)
  b$has_price <- is.finite(b$theta_present) & b$theta_present > 0
  b$qualifies <- b$has_price & b$n_eff >= min_group_n_eff & b$f1 >= min_group_f1

  # A group that fails the guards has NO trusted price -- start it at NA rather
  # than at its own untrusted theta_present, or `group_fallback` other than
  # "pooled_qualifying" would silently keep exactly the number the guards just
  # rejected (found by the group_fallback = "error"/"skip" tests, not by review).
  price <- ifelse(b$qualifies, b$theta_present, NA_real_)
  basis <- rep(NA_character_, nrow(b))
  basis[b$qualifies] <- "own_group"
  if (isTRUE(cap_at_singleton)) {
    capped <- b$qualifies & is.finite(b$singleton_price) &
      b$theta_present > b$singleton_price
    price[capped] <- b$singleton_price[capped]
    basis[capped] <- "own_group_capped"
  }

  # Pooled-qualifying fallback. Combined GROUP-WISE, never by re-pooling the
  # records (that would reintroduce exactly the f1 inflation this whole
  # mechanism exists to remove): unseen-species counts ADD across disjoint
  # groups, while missing masses are shares of different denominators and so
  # combine as an n_eff-weighted average -- i.e. the missing mass of the UNION,
  # expressed as a share of a union record.
  q <- which(b$qualifies)
  fallback_price <- NA_real_
  if (length(q) > 0L) {
    n_q <- sum(b$n_eff[q])
    mass_q <- sum((b$n_eff[q] / n_q) * b$missing_mass[q])
    chao_q <- sum(b$chao_missing[q])
    if (is.finite(mass_q) && is.finite(chao_q) && chao_q > 0)
      fallback_price <- mass_q / chao_q
  }
  if (identical(group_fallback, "pooled_qualifying") && is.finite(fallback_price)) {
    price[!b$qualifies] <- fallback_price
    basis[!b$qualifies] <- "pooled_qualifying"
  }
  b$price <- price
  b$pricing_basis <- basis

  list(price = stats::setNames(price, b$sampling_group),
       basis = stats::setNames(basis, b$sampling_group),
       budget = b,
       fallback_price = fallback_price,
       n_qualifying = length(q))
}

#' Resolve each evidence taxon's sampling group
#'
#' Precedence: an explicit `sampling_group` column on `evidence`, then the
#' `sampling_group` argument (scalar = all taxa, or a named vector / two-column
#' lookup). Never guessed from taxonomy -- the classification that produced the
#' occurrence pool's own groups lives in the caller's workflow, not here, and a
#' wrong group silently mis-prices rather than failing.
#' @noRd
.resolve_evidence_groups <- function(taxa, evidence, sampling_group, valid_groups) {
  out <- rep(NA_character_, length(taxa))
  names(out) <- taxa

  if ("sampling_group" %in% names(evidence)) {
    for (i in seq_along(taxa)) {
      v <- unique(stats::na.omit(as.character(
        evidence$sampling_group[evidence$taxon_name == taxa[i]])))
      if (length(v) > 1L)
        stop("apply_undetected_evidence: taxon '", taxa[i], "' is assigned to ",
             "more than one sampling group in `evidence` (",
             paste(v, collapse = ", "), "). One taxon has one detection ",
             "process; reconcile the evidence rows before combining them.")
      if (length(v) == 1L) out[i] <- v
    }
  }

  if (!is.null(sampling_group)) {
    if (is.data.frame(sampling_group)) {
      if (!all(c("taxon_name", "sampling_group") %in% names(sampling_group)))
        stop("apply_undetected_evidence: a data-frame `sampling_group` must have ",
             "columns 'taxon_name' and 'sampling_group'.")
      map <- stats::setNames(as.character(sampling_group$sampling_group),
                             as.character(sampling_group$taxon_name))
    } else if (is.character(sampling_group) && length(sampling_group) == 1L &&
               is.null(names(sampling_group))) {
      map <- stats::setNames(rep(sampling_group, length(taxa)), taxa)
    } else if (is.character(sampling_group) && !is.null(names(sampling_group))) {
      map <- sampling_group
    } else {
      stop("apply_undetected_evidence: `sampling_group` must be a single group ",
           "name, a named character vector (taxon -> group), or a data frame ",
           "with taxon_name/sampling_group columns.")
    }
    fill <- is.na(out) & taxa %in% names(map)
    out[fill] <- unname(map[taxa[fill]])
  }

  bad <- !is.na(out) & !out %in% valid_groups
  if (any(bad))
    stop("apply_undetected_evidence: sampling group(s) ",
         paste(unique(out[bad]), collapse = ", "), " are not present in the ",
         "fit's own budget. Groups available: ",
         paste(valid_groups, collapse = ", "), ".")

  if (anyNA(out))
    stop("apply_undetected_evidence: this model_obj has ", length(valid_groups),
         " sampling groups, so every evidence taxon needs one -- ",
         sum(is.na(out)), " have none (",
         paste(utils::head(taxa[is.na(out)], 5L), collapse = ", "),
         if (sum(is.na(out)) > 5L) ", ..." else "",
         "). Supply `sampling_group` (a single group name if the whole ",
         "evidence list shares one detection process, e.g. an all-fish watch ",
         "list; or a named vector / taxon_name+sampling_group data frame), or ",
         "add a `sampling_group` column to `evidence`. This is deliberately ",
         "never guessed from taxonomy: the classification that built the ",
         "occurrence pool's groups lives in your workflow, and a wrong group ",
         "mis-prices silently.")
  out
}
