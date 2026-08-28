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
#'     \item{model_tier}{Always \code{"tier_undetected_evidence"}.}
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
    main_habitat = NULL,
    taxonomy     = NULL
) {
  if (!inherits(model_obj, "biofreq_model")) {
    stop("apply_undetected_evidence: model_obj must be a biofreq_model ",
         "object from train_biodiversity_model().")
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
    return(.empty_undetected_evidence_result(habitat_col))
  }
  if (any(evidence$weight < 0 | evidence$weight > 1, na.rm = TRUE) || anyNA(evidence$weight)) {
    stop("apply_undetected_evidence: every `evidence$weight` must be a non-NA value in [0, 1].")
  }
  if (!"p_conc" %in% names(evidence)) evidence$p_conc <- 1
  if (any(evidence$p_conc <= 0, na.rm = TRUE) || anyNA(evidence$p_conc)) {
    stop("apply_undetected_evidence: every `evidence$p_conc` must be a non-NA positive value.")
  }

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
  if (theta_singleton > theta_floor) {
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
    return(.empty_undetected_evidence_result(habitat_col))
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
  theta_new <- theta_floor + (theta_singleton - theta_floor) * w_combined_vec
  delta_sq  <- (theta_singleton - theta_floor)^2
  v_mix <- w_combined_vec * var_singleton +
    (1 - w_combined_vec) * var_floor +
    w_combined_vec * (1 - w_combined_vec) * delta_sq
  n_eff_mm <- ifelse(
    is.finite(v_mix) & v_mix > 0,
    pmax(theta_new * (1 - theta_new) / v_mix - 1, 1e-3),
    2  # degenerate anchors (ceiling == floor): singleton_ess convention
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
    undetected_type  = "evidence_blend",
    evidence_weight  = w_combined_vec,
    evidence_sources = sources_vec,
    prior_mix_w             = w_combined_vec,
    prior_mix_theta_present = theta_singleton,
    prior_mix_theta_absent  = theta_floor,
    prior_mix_p_conc        = p_conc_new
  )
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
    "--- Undetected evidence applied: %d row(s) elevated above the floor (of %d taxa named in evidence) ---",
    nrow(result), n_evidence_taxa
  ))

  result
}

#' Empty-schema result for apply_undetected_evidence(), matching its documented @return
#' @noRd
.empty_undetected_evidence_result <- function(habitat_col) {
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
  if (!is.null(habitat_col)) result[[habitat_col]] <- character(0)
  result
}
