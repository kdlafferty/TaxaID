utils::globalVariables(c("group", "threshold", "rate", "pooled_rate"))

# support_curves.R
# TaxaLikely package
#
# Shared machinery behind two consumers, both growing out of the same
# 2026-07-23 design conversation and its reference implementation,
# diagnostics/score_floor_roc_sweep.R:
#   1. evaluate_likelihoods()'s species_confusion_risk/genus_confusion_risk/
#      family_confusion_risk columns (R/evaluate.R) -- a model-independent,
#      score-only diagnostic of the risk that the raw match score is
#      equally explained by a confusable congener/confamilial/cross-family
#      relative, evaluated against the FALSE-POSITIVE side of these curves
#      (a genuine congener/confamilial/cross-family pair's own score
#      distribution). Renamed 2026-07-23 (same day) from "*_support" after
#      noticing the original name inverted the ecosystem's own convention:
#      every other "_score"/"_risk" metric here (e.g. TaxaFlag::
#      flag_contaminant()'s contaminant_score) already uses HIGH = MORE of
#      the named concern; "_support" implied the opposite (high = backs up
#      the claim) while the values themselves are P(a confusable relative
#      would score this high or higher) -- i.e. HIGH = MORE confusable =
#      WEAKER evidence. "_confusion_risk" matches the established
#      high=concern convention with no math change.
#   2. compute_rank_thresholds() (this file) -- a marker-agnostic Youden's-J
#      threshold deriver for TaxaAssign::score_consensus()'s rank_thresholds,
#      needing BOTH the true-positive and false-positive sides.
#
# Genus-/family-EQUAL-WEIGHTED pooling (one vote per taxon, not per raw pair)
# plus Empirical-Bayes shrinkage (w = n/(n+prior_weight), the same form
# train_likelihood_model() already uses for H1/H2) corrects the same
# Sebastes-style dominance problem documented in that function's own H2
# pooled-delta fix -- see train_likelihood_model()'s "Per-genus delta
# shrinkage" section for the real, measured version of this bias. A
# per-sequence best-match collapse (one row per id_x per pair_type) mirrors
# .prep_training_data()'s own h1_data/max_congener_score convention, for the
# same two reasons: avoiding O(k^2) combinatorial pair-count domination by a
# heavily-resequenced taxon, and better matching what a real query sees at
# inference (one best hit per competing category, not an average over every
# reference pair).
#
# Internal only -- no exported entry point of its own. train_likelihood_model()
# calls this once at training time and stores the result in
# model_params$Confusion_Risk_Curves; compute_rank_thresholds() calls it
# directly on a user-supplied seq_matrix.

#' Per-rank, genus-/family-equal-weighted EB-shrunk score curves
#'
#' Computes true-positive (TPR) and false-positive (FPR) rate-at-threshold
#' curves for each taxonomic rank (species/genus/family), directly from a
#' `build_sequence_matrix()`-style pairwise distance matrix (`.x`/`.y`-suffixed
#' taxonomy columns + `p_match` or `raw_score`). Requires at least a
#' genus-level rank pair to compute anything (the species tier's FP
#' population, congeneric pairs, needs genus); the genus and family tiers
#' additionally require a family-level rank pair. Returns `NULL` (not an
#' error) when neither is available, since this is meant to degrade
#' gracefully as one input among several to `train_likelihood_model()`.
#'
#' `pair_type` mirrors `diagnostics/score_floor_roc_sweep.R` exactly:
#' `"within-species"` (TP for the species tier), `"congeneric"` (same genus,
#' different species -- FP for the species tier), `"confamilial"` (same
#' family, different genus -- FP for the genus tier), `"cross-family"` (FP
#' for the family tier -- a structural ceiling when `rank_system` carries no
#' rank coarser than family, exactly as in that diagnostic script).
#'
#' @param raw_df Data frame of pairwise match scores (as returned by
#'   `build_sequence_matrix()`), with `.x`/`.y`-suffixed taxonomy columns and
#'   a `p_match` or `raw_score` column.
#' @param rank_system Character vector of rank names, coarse to fine, e.g.
#'   `c("family", "genus", "species")`.
#' @param prior_weight Numeric. Empirical Bayes shrinkage weight, same
#'   meaning and default as `train_likelihood_model()`'s own parameter of the
#'   same name (reused for consistency, not independently validated for this
#'   rate-estimate use -- see the diagnostic script's own caveat).
#' @param threshold_grid Numeric vector of percent-identity thresholds to
#'   evaluate rates at. Default `seq(0, 100, by = 1)`.
#'
#' @return `NULL` if no tier is computable (fewer than 2 usable rank levels,
#'   or missing/all-NA identifying columns). Otherwise a list with up to
#'   three slots (`species`, `genus`, `family` -- each `NULL` if that tier's
#'   own required rank isn't present), plus `threshold_grid`/`prior_weight`.
#'   Every rate curve carries the raw empirical proportion (`rate`/
#'   `pooled_rate`) and a Jeffreys-smoothed companion (`rate_smooth`/
#'   `pooled_rate_smooth`, `(k + 1/2)/(n + 1)`); `shrunk_rate` is built from
#'   the smoothed pair. `compute_rank_thresholds()` reads the raw columns,
#'   `.lookup_confusion_risk_value()` reads the smoothed ones -- see the
#'   `.jeffreys_rate()` comment in the function body for why:
#'   \describe{
#'     \item{`species`}{`tpr_pooled` (equal-weighted across species),
#'       `fpr_by_genus_shrunk` (EB-shrunk per genus), `fpr_pooled`
#'       (equal-weighted across genera) -- all data frames with a
#'       `threshold` column plus `pooled_rate`/`shrunk_rate` as applicable.}
#'     \item{`genus`}{Same shape, one rank coarser: `tpr_pooled` equal-
#'       weighted across genera (TP = same-genus), `fpr_by_family_shrunk`/
#'       `fpr_pooled` from confamilial pairs, equal-weighted across
#'       families.}
#'     \item{`family`}{`tpr_pooled` equal-weighted across families (TP =
#'       same-family); `fpr_pooled` from cross-family pairs -- a single
#'       ungrouped rate (no rank above family to equal-weight by), matching
#'       the structural ceiling documented in
#'       `diagnostics/score_floor_roc_sweep.R`.}
#'   }
#'
#' @noRd
.compute_rank_score_curves <- function(raw_df,
                                       rank_system,
                                       prior_weight = 10.0,
                                       threshold_grid = seq(0, 100, by = 1)) {
  names(raw_df) <- tolower(names(raw_df))
  rank_system <- tolower(rank_system)
  n_ranks <- length(rank_system)
  if (n_ranks < 2L) {
    return(NULL)
  }

  species_col <- rank_system[n_ranks]
  genus_col <- rank_system[n_ranks - 1L]
  family_col <- if (n_ranks >= 3L) rank_system[n_ranks - 2L] else NA_character_

  need_cols <- c(
    paste0(species_col, ".x"), paste0(species_col, ".y"),
    paste0(genus_col, ".x"), paste0(genus_col, ".y")
  )
  if (!all(need_cols %in% names(raw_df))) {
    return(NULL)
  }

  score_col <- if ("p_match" %in% names(raw_df)) {
    "p_match"
  } else if ("raw_score" %in% names(raw_df)) {
    "raw_score"
  } else {
    return(NULL)
  }

  sp_x <- as.character(raw_df[[paste0(species_col, ".x")]])
  sp_y <- as.character(raw_df[[paste0(species_col, ".y")]])
  gn_x <- as.character(raw_df[[paste0(genus_col, ".x")]])
  gn_y <- as.character(raw_df[[paste0(genus_col, ".y")]])

  has_family <- !is.na(family_col) &&
    all(c(paste0(family_col, ".x"), paste0(family_col, ".y")) %in% names(raw_df))
  fam_x <- if (has_family) {
    as.character(raw_df[[paste0(family_col, ".x")]])
  } else {
    rep(NA_character_, nrow(raw_df))
  }
  fam_y <- if (has_family) {
    as.character(raw_df[[paste0(family_col, ".y")]])
  } else {
    rep(NA_character_, nrow(raw_df))
  }

  pct_identity <- .normalize_scores(raw_df[[score_col]]) * 100

  same_species <- !is.na(sp_x) & !is.na(sp_y) & sp_x == sp_y
  same_genus <- !is.na(gn_x) & !is.na(gn_y) & gn_x == gn_y
  same_family <- if (has_family) {
    (!is.na(fam_x) & !is.na(fam_y) & fam_x == fam_y)
  } else {
    rep(FALSE, length(sp_x))
  }

  pair_type <- rep("cross-family", length(sp_x))
  pair_type[!same_species & same_genus] <- "congeneric"
  pair_type[!same_genus & has_family & same_family] <- "confamilial"
  pair_type[same_species] <- "within-species"

  keep <- !is.na(sp_x) & nzchar(sp_x) & !is.na(raw_df$id_x)
  if (!any(keep)) {
    return(NULL)
  }

  df <- data.frame(
    id_x = raw_df$id_x[keep],
    species = sp_x[keep],
    genus = gn_x[keep],
    family = fam_x[keep],
    pair_type = pair_type[keep],
    pct_identity = pct_identity[keep],
    stringsAsFactors = FALSE
  )

  # Per-sequence best-match collapse within each pair_type -- mirrors
  # .prep_training_data()'s own h1_data/max_congener_score convention (see
  # this file's header for the rationale).
  collapsed <- dplyr::ungroup(dplyr::slice_max(
    dplyr::group_by(df, id_x, pair_type), pct_identity,
    n = 1L, with_ties = FALSE
  ))

  # Jeffreys posterior mean, (k + 1/2) / (n + 1), alongside the raw proportion
  # k/n -- the standard non-informative Beta(1/2, 1/2) reference prior for a
  # Bernoulli parameter (Jeffreys, 1946), already this ecosystem's own
  # convention for the same problem (see TaxaExpect::generate_full_priors()'s
  # jeffreys_fallback). Needed because a raw k = 0 reports an EXACT zero --
  # "no congener could ever score this well" -- which finite reference data
  # cannot support, and which is not a rare small-sample edge case here: on
  # real 12S data every observed score at or above ~99.5% identity landed on
  # a zero-valued grid point. Derived rather than chosen (the Jeffreys prior
  # follows from the Fisher information), so it adds no tunable constant, and
  # it is plain arithmetic on values already being computed. Monotonicity in
  # `threshold` is preserved (k is non-increasing in t).
  #
  # Deliberately kept as a SEPARATE column rather than replacing `rate`,
  # because this file's two consumers want different things. The reported
  # confusion risk is a probability estimate and wants the smoothed value;
  # `compute_rank_thresholds()`'s Youden's J wants the argmax of the raw
  # empirical ROC, and smoothing perturbs it -- the (k+1/2)/(n+1) form
  # reweights groups by n/(n+1), which partly undoes the deliberate
  # genus-/family-equal weighting this file exists to apply. Verified on real
  # Mugu data: replacing `rate` outright moved real production thresholds
  # (12S genus 97->98, 16S genus 96->98, COI species 98->99). Keeping both
  # columns leaves `compute_rank_thresholds()` bit-identical while giving the
  # confusion-risk lookup the estimator it needs.
  .jeffreys_rate <- function(k, n) (k + 0.5) / (n + 1)

  .rate_curve_by_group <- function(sub_df, group_col, thresholds) {
    sub_df <- sub_df[!is.na(sub_df[[group_col]]), , drop = FALSE]
    if (nrow(sub_df) == 0L) {
      return(NULL)
    }
    groups <- split(sub_df$pct_identity, sub_df[[group_col]])
    out <- lapply(names(groups), function(g) {
      vals <- groups[[g]]
      k <- vapply(thresholds, function(t) sum(vals >= t), numeric(1))
      data.frame(
        group = g,
        threshold = thresholds,
        n = length(vals),
        rate = k / length(vals),
        rate_smooth = .jeffreys_rate(k, length(vals)),
        stringsAsFactors = FALSE
      )
    })
    do.call(rbind, out)
  }

  .pooled_rate_ungrouped <- function(vals, thresholds) {
    k <- vapply(thresholds, function(t) sum(vals >= t), numeric(1))
    data.frame(
      threshold = thresholds,
      pooled_rate = k / length(vals),
      pooled_rate_smooth = .jeffreys_rate(k, length(vals))
    )
  }

  # Pools both the raw and the smoothed rate, equal-weighted across groups.
  # `pooled_rate` feeds compute_rank_thresholds()'s Youden's J (raw empirical
  # ROC); `pooled_rate_smooth` feeds the confusion-risk lookup and the EB
  # shrinkage target -- see the .jeffreys_rate() comment above for why the two
  # are kept apart.
  .equal_weighted_pooled <- function(curve_by_group) {
    if (is.null(curve_by_group)) {
      return(NULL)
    }
    agg <- stats::aggregate(cbind(rate, rate_smooth) ~ threshold,
      data = curve_by_group, FUN = mean
    )
    names(agg)[names(agg) == "rate"] <- "pooled_rate"
    names(agg)[names(agg) == "rate_smooth"] <- "pooled_rate_smooth"
    agg[order(agg$threshold), , drop = FALSE]
  }

  .eb_shrink <- function(curve_by_group, pooled, pw) {
    if (is.null(curve_by_group) || is.null(pooled)) {
      return(NULL)
    }
    merged <- merge(curve_by_group, pooled, by = "threshold", all.x = TRUE)
    merged$w <- merged$n / (merged$n + pw)
    # Shrink the SMOOTHED rate toward the SMOOTHED pooled target, so the
    # reported value never claims more certainty than the data supports at
    # either level.
    merged$shrunk_rate <- merged$w * merged$rate_smooth +
      (1 - merged$w) * merged$pooled_rate_smooth
    merged
  }

  # ---- Species tier: TP = within-species, FP = congeneric -------------------
  within_sp <- collapsed[collapsed$pair_type == "within-species", , drop = FALSE]
  tpr_species_by_sp <- .rate_curve_by_group(within_sp, "species", threshold_grid)
  tpr_species_pooled <- .equal_weighted_pooled(tpr_species_by_sp)

  congeneric <- collapsed[collapsed$pair_type == "congeneric", , drop = FALSE]
  fpr_congeneric_by_genus <- .rate_curve_by_group(congeneric, "genus", threshold_grid)
  fpr_congeneric_pooled <- .equal_weighted_pooled(fpr_congeneric_by_genus)
  fpr_congeneric_shrunk <- .eb_shrink(fpr_congeneric_by_genus, fpr_congeneric_pooled, prior_weight)

  species_slot <- if (!is.null(tpr_species_pooled) && !is.null(fpr_congeneric_pooled)) {
    list(
      tpr_pooled = tpr_species_pooled,
      fpr_by_genus_shrunk = fpr_congeneric_shrunk,
      fpr_pooled = fpr_congeneric_pooled
    )
  } else {
    NULL
  }

  genus_slot <- NULL
  family_slot <- NULL

  if (has_family) {
    # ---- Genus tier: TP = same-genus (within-species OR congeneric), FP = confamilial
    same_genus_pop <- collapsed[collapsed$pair_type %in% c("within-species", "congeneric"), , drop = FALSE]
    tpr_genus_by_gn <- .rate_curve_by_group(same_genus_pop, "genus", threshold_grid)
    tpr_genus_pooled <- .equal_weighted_pooled(tpr_genus_by_gn)

    confamilial <- collapsed[collapsed$pair_type == "confamilial", , drop = FALSE]
    fpr_confamilial_by_family <- .rate_curve_by_group(confamilial, "family", threshold_grid)
    fpr_confamilial_pooled <- .equal_weighted_pooled(fpr_confamilial_by_family)
    fpr_confamilial_shrunk <- .eb_shrink(fpr_confamilial_by_family, fpr_confamilial_pooled, prior_weight)

    if (!is.null(tpr_genus_pooled) && !is.null(fpr_confamilial_pooled)) {
      genus_slot <- list(
        tpr_pooled = tpr_genus_pooled,
        fpr_by_family_shrunk = fpr_confamilial_shrunk,
        fpr_pooled = fpr_confamilial_pooled
      )
    }

    # ---- Family tier: TP = same-family (...OR confamilial), FP = cross-family
    # (a single, ungrouped rate -- the structural ceiling documented in this
    # file's header; no rank coarser than family exists to equal-weight by).
    same_family_pop <- collapsed[collapsed$pair_type %in%
      c("within-species", "congeneric", "confamilial"), , drop = FALSE]
    tpr_family_by_fam <- .rate_curve_by_group(same_family_pop, "family", threshold_grid)
    tpr_family_pooled <- .equal_weighted_pooled(tpr_family_by_fam)

    crossfamily <- collapsed[collapsed$pair_type == "cross-family", , drop = FALSE]
    if (!is.null(tpr_family_pooled) && nrow(crossfamily) > 0L) {
      fpr_crossfamily_pooled <- .pooled_rate_ungrouped(crossfamily$pct_identity, threshold_grid)
      family_slot <- list(
        tpr_pooled = tpr_family_pooled,
        fpr_pooled = fpr_crossfamily_pooled
      )
    }
  }

  if (is.null(species_slot) && is.null(genus_slot) && is.null(family_slot)) {
    return(NULL)
  }

  list(
    species = species_slot, genus = genus_slot, family = family_slot,
    threshold_grid = threshold_grid, prior_weight = prior_weight
  )
}

#' Look up a confusion-risk value from one Confusion_Risk_Curves rank slot
#'
#' `observed_pct` is read off the rate curve by LINEAR INTERPOLATION between
#' the two bracketing grid thresholds; when `shrunk_df`/`group_key` resolve to
#' a real EB-shrunk group row, that curve is preferred, falling back to the
#' equal-weighted pooled curve when the group was never seen in training (a
#' permanent structural zero for a monotypic genus/family, not a small-sample
#' problem -- shrinkage weight -> 0 handles this gracefully with no separate
#' NA-emitting floor needed, same as `H2_Lookup`'s own convention).
#'
#' Interpolation replaces an earlier nearest-grid-threshold snap, which put a
#' real discontinuity exactly where this data lives. The curves are built on a
#' 1-percentage-point grid, but a congeneric false-positive rate falls very
#' steeply across the top point or two (on real 12S: 0.279 at 99% to ~0 at
#' 100%), and 45% of real observed scores sit at or above 99%. Snapping
#' therefore reported the same confusion risk for a 99.5% match as for a
#' literal 100% one, while separating 99.4% from 99.6% by the full height of
#' that final step -- an artifact of grid spacing, not a property of the
#' evidence. Interpolating turns that cliff into the gradient the underlying
#' empirical curve actually describes, and needs no retraining: it reads the
#' same stored grid more faithfully.
#'
#' `rule = 2` clamps outside the grid range, so a score above the grid's top
#' (or below its bottom) returns the nearest endpoint rather than `NA`.
#'
#' @noRd
.lookup_confusion_risk_value <- function(observed_pct, group_key, shrunk_df, pooled_df) {
  if (is.null(pooled_df) || is.na(observed_pct)) {
    return(NA_real_)
  }

  .interp <- function(x, y, xout) {
    ok <- !is.na(x) & !is.na(y)
    x <- x[ok]
    y <- y[ok]
    if (length(x) == 0L) {
      return(NA_real_)
    }
    if (length(x) == 1L) {
      return(y[[1L]])
    }
    o <- order(x)
    stats::approx(x[o], y[o], xout = xout, rule = 2)$y[[1L]]
  }

  if (!is.null(shrunk_df) && !is.null(group_key) && !is.na(group_key)) {
    rows <- shrunk_df[shrunk_df$group == group_key, , drop = FALSE]
    if (nrow(rows) > 0L) {
      return(.interp(rows$threshold, rows$shrunk_rate, observed_pct))
    }
  }
  # Prefer the Jeffreys-smoothed pooled column; fall back to the raw one for a
  # Confusion_Risk_Curves object built before that column existed.
  pooled_col <- if ("pooled_rate_smooth" %in% names(pooled_df)) {
    pooled_df$pooled_rate_smooth
  } else {
    pooled_df$pooled_rate
  }
  .interp(pooled_df$threshold, pooled_col, observed_pct)
}

#' Derive marker-specific rank_thresholds via per-rank Youden's J
#'
#' A real, exported, marker-agnostic version of
#' `diagnostics/score_floor_roc_sweep.R`'s per-rank Youden's J logic: given a
#' `build_sequence_matrix()`-style pairwise distance matrix for YOUR marker
#' and reference database, returns the percent-identity threshold at each
#' taxonomic rank (species/genus/family) that maximizes true-positive minus
#' false-positive rate for that rank's own, correctly-matched positive/
#' negative classes -- species tier: TP = within-species, FP = congeneric;
#' genus tier: TP = same-genus, FP = confamilial; family tier: TP =
#' same-family, FP = cross-family. Reuses the identical genus-/family-
#' equal-weighted, Empirical-Bayes-shrunk pooling machinery
#' `train_likelihood_model()` stores in `model_params$Confusion_Risk_Curves` (see
#' `.compute_rank_score_curves()`), so the two stay consistent with each
#' other rather than duplicating the correction independently.
#'
#' Exists specifically because `TaxaAssign::score_consensus()`'s
#' `rank_thresholds` has no safe universal default (see that function's own
#' documentation) -- this is the "derive your own from real reference data"
#' option that error message points at.
#'
#' @param seq_matrix Data frame of pairwise match scores, as returned by
#'   `build_sequence_matrix()`, for the SAME marker/reference database
#'   `score_consensus()` will be scoring against. Every pair must have known
#'   taxonomy on both sides (species/genus/family), which is exactly what
#'   `build_sequence_matrix()` already produces.
#' @param rank_system Character vector of rank names, coarse to fine, e.g.
#'   `c("family", "genus", "species")`. Default `NULL` auto-detects from
#'   `.x`-suffixed columns in `seq_matrix` (same convention as
#'   `train_likelihood_model()`).
#' @param prior_weight Numeric. Empirical Bayes shrinkage weight for the
#'   per-genus/per-family curves (default `10.0`, matching
#'   `train_likelihood_model()`'s own default).
#' @param threshold_grid Numeric vector of percent-identity thresholds to
#'   search over. Default `seq(0, 100, by = 1)`.
#'
#' @return A named numeric vector, a subset of `c(species=, genus=, family=)`
#'   depending on what `rank_system`/`seq_matrix` make computable -- directly
#'   usable as `TaxaAssign::score_consensus(rank_thresholds = ...)`. Errors
#'   if nothing is computable at all (fewer than 2 usable rank levels).
#'
#' @examples
#' \dontrun{
#' ref_matrix <- build_sequence_matrix(reference_df,
#'   rank_system = c("family", "genus", "species")
#' )
#' rt <- compute_rank_thresholds(ref_matrix,
#'   rank_system = c("family", "genus", "species")
#' )
#' TaxaAssign::score_consensus(match_df, rank_thresholds = rt)
#' }
#'
#' @seealso [train_likelihood_model()], [build_sequence_matrix()]
#' @export
compute_rank_thresholds <- function(seq_matrix,
                                    rank_system = NULL,
                                    prior_weight = 10.0,
                                    threshold_grid = seq(0, 100, by = 1)) {
  if (!is.data.frame(seq_matrix)) {
    stop("compute_rank_thresholds: 'seq_matrix' must be a data frame (build_sequence_matrix() output).",
      call. = FALSE
    )
  }
  if (!is.numeric(prior_weight) || length(prior_weight) != 1L || prior_weight <= 0) {
    stop("compute_rank_thresholds: 'prior_weight' must be a positive numeric scalar.", call. = FALSE)
  }

  if (is.null(rank_system)) {
    x_cols <- grep("\\.x$", tolower(names(seq_matrix)), value = TRUE)
    x_cols <- sub("\\.x$", "", x_cols)
    canonical <- c(
      "kingdom", "phylum", "subphylum", "superclass", "class",
      "subclass", "infraclass", "cohort", "order", "suborder",
      "infraorder", "family", "genus", "species"
    )
    rank_system <- canonical[canonical %in% x_cols]
    if (length(rank_system) < 2L) {
      stop(
        "compute_rank_thresholds: could not auto-detect rank_system from seq_matrix columns. ",
        "Found .x columns: ", paste(x_cols, collapse = ", "), ". Supply rank_system explicitly.",
        call. = FALSE
      )
    }
  }

  curves <- .compute_rank_score_curves(seq_matrix, rank_system, prior_weight, threshold_grid)
  if (is.null(curves)) {
    stop(paste0(
      "compute_rank_thresholds: could not compute rank-score curves from this seq_matrix -- ",
      "needs at least a genus-level rank pair (species.x/.y + genus.x/.y) present and non-NA. ",
      "Check rank_system and seq_matrix's own column names."
    ), call. = FALSE)
  }

  .youden_best <- function(tier) {
    if (is.null(tier)) {
      return(NA_real_)
    }
    merged <- merge(tier$tpr_pooled, tier$fpr_pooled,
      by = "threshold",
      suffixes = c("_tpr", "_fpr")
    )
    if (nrow(merged) == 0L) {
      return(NA_real_)
    }
    j <- merged$pooled_rate_tpr - merged$pooled_rate_fpr
    merged$threshold[[which.max(j)]]
  }

  out <- numeric(0)
  if (!is.null(curves$species)) out["species"] <- .youden_best(curves$species)
  if (!is.null(curves$genus)) out["genus"] <- .youden_best(curves$genus)
  if (!is.null(curves$family)) out["family"] <- .youden_best(curves$family)

  if (length(out) == 0L) {
    stop("compute_rank_thresholds: no rank tier was computable from this seq_matrix.", call. = FALSE)
  }

  out
}
