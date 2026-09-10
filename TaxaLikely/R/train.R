utils::globalVariables(c(
  "p_norm", "p_b", "score_logit", "id_x", "id_y",
  "max_foreign_score", "raw_gap", "gap_logit", "rank_category", "N_Obs",
  "rank_code_a.x", "rank_code_a", "rank_code_b",
  "median_self_match", "max_foreign_match", "n_self_neighbors",
  "integrity_gap", "error_type", "identifier",
  "species.x", "species.y", "p_match",
  "mu_score", "mu_gap", "sigma_score", "lookup_key", "rank",
  "score_logit_mean", "gap_logit_mean", "score_logit_var",
  "n_obs_species", "shrunk_mu_score", "shrunk_mu_gap", "shrunk_sigma",
  "w", "species", "max_congener_score", "delta_emp", "n_pairs", "delta_shrunk",
  "mean_cong", "var_cong", "var_shrunk",
  "median_foreign_match", "n_foreign_pairs", "n_foreign_taxa", "species_x",
  "coverage", "foreign_match_coverage", "median_self_coverage"
))

# ==============================================================================
# MODULE C: TRAINING ENGINE (Empirical Bayes Shrinkage)
# ==============================================================================

#' Prepare within-species training pairs from a pairwise distance matrix
#'
#' Takes the output of `build_sequence_matrix()` and produces the H1 training
#' data set used by `train_likelihood_model()`.  For each reference sequence the
#' function:
#' \enumerate{
#'   \item Normalises raw scores to (0, 1) then logit-transforms them.
#'   \item Computes the \emph{gap}: best within-species logit score minus the
#'     best cross-species logit score for the same query sequence.
#'   \item Retains the single best within-species match per query (reduces bias
#'     from variable per-species sequence counts).
#'   \item Adds \emph{singleton} rows (sequences with no within-species
#'     neighbours) with a fixed high gap.
#' }
#'
#' Taxonomy columns are renamed to `rank_code_a` ... `rank_code_z` so
#' that downstream training code does not depend on rank-name strings.
#' `rank_code_a` always corresponds to the finest rank (the last element of
#' `rank_system`).
#'
#' @param raw_df Data frame of pairwise match scores from
#'   `build_sequence_matrix()`.  Must contain `id_x`, `id_y`, and either
#'   `p_match` or `raw_score`, plus taxonomy columns for each rank in
#'   `rank_system` with `.x` and `.y` suffixes (e.g., `species.x`, `genus.x`).
#' @param rank_system Character vector of rank names ordered **coarse to fine**
#'   (e.g., `c("family", "genus", "species")`).  The finest rank (last element)
#'   is used as the primary grouping unit for H1 pairs.
#' @param score_bounds Optional length-2 numeric vector `c(min, max)`.  Passed
#'   to `.normalize_scores()`.  If `NULL` (default) the scale is auto-detected.
#' @param logit_epsilon Numeric scalar.  Clipping applied before logit to
#'   prevent infinite values (default `1e-4`).
#' @param max_gap_ceiling Numeric scalar.  Cap on `gap_logit` to prevent extreme
#'   outliers from dominating training (default `5.0`).  In logit space, 5.0
#'   corresponds roughly to the gap between 99.3% and 50% identity --
#'   differences larger than this are capped to prevent extreme outliers from
#'   dominating model estimates.  `NULL` resolves per `score_transform` via
#'   `.resolve_gap_ceiling()`.
#' @param score_transform Character, `"logit"` (default) or `"sqrt_mismatch"`.
#'   Which scale scores/gaps are transformed onto before training -- see
#'   `train_likelihood_model()`'s own `@param score_transform` for the full
#'   explanation (this internal function is always called with the same value
#'   the caller passed there).
#' @return A data frame with one row per query sequence containing:
#'   \describe{
#'     \item{`id_x`}{Query sequence identifier.}
#'     \item{`rank_code_a`, ...}{Generalized rank columns (finest = `a`).}
#'     \item{`score_logit`}{Logit-transformed normalized best within-species
#'       match score.}
#'     \item{`gap_logit`}{Score gap (capped at `max_gap_ceiling`).}
#'     \item{`rank_category`}{`"1_Known_Species"` or `"Singleton"`.}
#'     \item{`N_Obs`}{Number of within-species PAIRS for this taxon (O(k^2)
#'       for k reference sequences, since every ordered pair within
#'       `max_dist` survives `build_sequence_matrix()`). Diagnostic only --
#'       NOT the N used for Empirical Bayes shrinkage in
#'       `train_likelihood_model()`, which instead counts rows of this data
#'       frame per species (one row per SEQUENCE, since the `group_by(id_x)
#'       |> slice_max()` step above already collapses each sequence's many
#'       pairs down to its single best within-species match before this
#'       column is even computed). Kept for possible future use as a
#'       pair-density diagnostic; not currently read by any downstream
#'       function.}
#'     \item{`max_congener_score`}{Best cross-species match restricted to a
#'       true congener (same genus, different species). `NA` when the query's
#'       genus has no other referenced species. Used by
#'       `train_likelihood_model()` to estimate a genus-specific H2 delta.}
#'   }
#'
#' @noRd
.prep_training_data <- function(raw_df,
                                rank_system,
                                score_bounds = NULL,
                                logit_epsilon = 1e-4,
                                max_gap_ceiling = NULL,
                                score_transform = "logit") {
  max_gap_ceiling <- .resolve_gap_ceiling(max_gap_ceiling, score_transform)
  if (!is.data.frame(raw_df)) {
    stop("raw_df must be a data frame")
  }
  if (!is.character(rank_system) || length(rank_system) == 0L) {
    stop("rank_system must be a non-empty character vector")
  }

  names(raw_df) <- tolower(names(raw_df))
  rank_system <- tolower(rank_system)

  # Validate rank columns exist (with .x/.y suffixes from build_sequence_matrix)
  x_cols <- paste0(rank_system, ".x")
  missing_x <- setdiff(x_cols, names(raw_df))
  if (length(missing_x) > 0L) {
    stop(sprintf(
      paste0(
        "rank_system columns not found in raw_df: %s. Expected columns with '.x'/'.y' ",
        "suffixes (e.g., '%s'). Check that rank_system matches the taxonomy columns in ",
        "your reference matrix."
      ),
      paste(missing_x, collapse = ", "), x_cols[1]
    ))
  }

  score_col <- if ("p_match" %in% names(raw_df)) "p_match" else "raw_score"
  raw_df$p_norm <- .normalize_scores(raw_df[[score_col]], bounds = score_bounds)

  # ---- STEP 1: GENERALISE TAXONOMY COLUMNS ----------------------------------
  # Rename rank columns to rank_code_a/b/c... (finest rank -> code_a).
  # Applied separately to .x and .y suffix sets, then recombined.
  .generalize_ranks <- function(df_sub, ranks) {
    present <- intersect(ranks, names(df_sub))
    if (length(present) == 0L) {
      return(df_sub)
    }
    # rev(present): last element of ranks (finest) -> code_a
    codes <- paste0("rank_code_", letters[seq_along(present)])
    rename_map <- stats::setNames(rev(present), codes)
    dplyr::rename(df_sub, !!rename_map)
  }

  df_x <- raw_df |>
    dplyr::select(dplyr::ends_with(".x")) |>
    dplyr::rename_with(~ sub("\\.x$", "", .x)) |>
    .generalize_ranks(rank_system) |>
    dplyr::rename_with(~ paste0(., ".x"))

  df_y <- raw_df |>
    dplyr::select(dplyr::ends_with(".y")) |>
    dplyr::rename_with(~ sub("\\.y$", "", .x)) |>
    .generalize_ranks(rank_system) |>
    dplyr::rename_with(~ paste0(., ".y"))

  if (!"rank_code_a.x" %in% names(df_x)) {
    stop("Taxonomy generalisation failed -- ensure input columns match rank_system")
  }

  df_combined <- dplyr::bind_cols(
    dplyr::select(raw_df, id_x, id_y, p_norm),
    df_x, df_y
  )

  # ---- STEP 2: SCORE TRANSFORM -----------------------------------------------
  # noise floor: scores below 1% identity are treated as random noise and
  # replaced with this floor value, on whichever scale score_transform picks.
  # Named "_transformed", not "_logit", because this value is computed via
  # .transform_p() and so lives on score_transform's own scale -- calling it
  # "_logit" would be a wrong/misleading name whenever score_transform =
  # "sqrt_mismatch".
  noise_floor_transformed <- .transform_p(0.01, score_transform, logit_epsilon)

  df_logit <- df_combined |>
    dplyr::mutate(
      score_logit = .transform_p(p_norm, score_transform, logit_epsilon)
    )

  # ---- STEP 3: FOREIGN STATS (max cross-species logit score per id_x) -------
  foreign_stats <- df_logit |>
    dplyr::filter(
      !is.na(.data[["rank_code_a.x"]]),
      !is.na(.data[["rank_code_a.y"]])
    ) |>
    dplyr::group_by(id_x) |>
    dplyr::summarise(
      max_foreign_score = suppressWarnings(
        max(
          score_logit[.data[["rank_code_a.x"]] != .data[["rank_code_a.y"]]],
          -Inf
        )
      ),
      .groups = "drop"
    ) |>
    dplyr::mutate(
      max_foreign_score = ifelse(
        is.infinite(max_foreign_score), noise_floor_transformed, max_foreign_score
      )
    )

  # ---- STEP 3B: CONGENER STATS (best same-genus, different-species match) ---
  # max_foreign_score above is the best match to ANY other species, in any
  # genus. That mixes true congeners in with distant, unrelated matches, so it
  # cannot tell "this genus has tight congeneric divergence" apart from "this
  # sequence's closest relative in the whole database happens to be distant."
  # max_congener_score restricts to real congeners (same genus, different
  # species) and is left NA -- not floored -- when the query's genus has no
  # other referenced species at all, so train_likelihood_model() can tell
  # "no local congener data exists for this genus" apart from "a real
  # congener match was observed and it was distant." Used to estimate a
  # genus-specific H2 delta (see H2_Lookup below); requires rank_code_b to be
  # present.
  #
  # rank_code_b is PURELY POSITIONAL, not semantic: rank_code_a is always
  # rank_system's LAST (finest) element, rank_code_b its second-to-last, and
  # so on (.generalize_ranks() above renames by position via rev(present)).
  # "Genus" here is a documented CONVENTION, not an enforced guarantee --
  # true whenever rank_system's finest two elements are ("...", "genus",
  # "species"), which is this ecosystem's own standard rank_system (see
  # Statistical Design Notes, "rank_system convention", in this package's
  # CLAUDE.md) and how every real production workflow calls this package. A
  # caller supplying a non-standard rank_system whose second-finest rank
  # ISN'T genus (e.g. one ending "...genus, species, subspecies", finest =
  # subspecies) would silently get max_congener_score/H2_Lookup keyed on
  # THAT rank instead (e.g. same-species-different-subspecies) with no
  # error or warning -- there is no runtime check enforcing "genus"
  # specifically, by design (this package's rank_system is deliberately
  # flexible, not hardcoded to a fixed taxonomic ladder).
  has_genus_code <- all(c("rank_code_b.x", "rank_code_b.y") %in% names(df_logit))
  congener_stats <- if (has_genus_code) {
    df_logit |>
      dplyr::filter(
        !is.na(.data[["rank_code_a.x"]]), !is.na(.data[["rank_code_a.y"]]),
        !is.na(.data[["rank_code_b.x"]]), !is.na(.data[["rank_code_b.y"]])
      ) |>
      dplyr::group_by(id_x) |>
      dplyr::summarise(
        max_congener_score = suppressWarnings(
          max(score_logit[
            .data[["rank_code_b.x"]] == .data[["rank_code_b.y"]] &
              .data[["rank_code_a.x"]] != .data[["rank_code_a.y"]]
          ], -Inf)
        ),
        .groups = "drop"
      ) |>
      dplyr::mutate(
        max_congener_score = ifelse(is.infinite(max_congener_score),
          NA_real_, max_congener_score
        )
      )
  } else {
    NULL
  }

  # ---- STEP 4: H1 PAIRS (same taxon, different sequence IDs) ----------------
  h1_pairs <- df_logit |>
    dplyr::filter(
      !is.na(.data[["rank_code_a.x"]]),
      !is.na(.data[["rank_code_a.y"]]),
      .data[["rank_code_a.x"]] == .data[["rank_code_a.y"]],
      id_x != id_y
    ) |>
    dplyr::left_join(foreign_stats, by = "id_x")

  h1_pairs <- if (!is.null(congener_stats)) {
    dplyr::left_join(h1_pairs, congener_stats, by = "id_x")
  } else {
    dplyr::mutate(h1_pairs, max_congener_score = NA_real_)
  }

  h1_pairs <- h1_pairs |>
    dplyr::mutate(
      raw_gap       = score_logit - max_foreign_score,
      gap_logit     = pmin(raw_gap, max_gap_ceiling),
      rank_category = "1_Known_Species"
    )

  species_counts <- h1_pairs |>
    dplyr::group_by(rank_code_a.x) |>
    dplyr::summarise(N_Obs = dplyr::n(), .groups = "drop")

  df_h1 <- h1_pairs |>
    dplyr::group_by(id_x) |>
    dplyr::slice_max(score_logit, n = 1L, with_ties = FALSE) |>
    dplyr::ungroup() |>
    dplyr::left_join(species_counts, by = "rank_code_a.x")

  # ---- STEP 5: SINGLETONS ---------------------------------------------------
  trained_ids <- unique(h1_pairs$id_x)
  all_ids <- unique(df_logit$id_x)
  missing_ids <- setdiff(all_ids, trained_ids)

  # Singletons are identified as sequences absent from h1_pairs (no within-species
  # neighbours). They require self-match rows (id_x == id_y) in the distance matrix.
  # If the matrix lacks self-matches, singletons are identified by missing_ids alone.
  has_self_match <- any(df_logit$id_x == df_logit$id_y)
  if (length(missing_ids) > 0L && !has_self_match) {
    warning(sprintf(
      paste0(
        "%d singleton reference(s) found but distance matrix lacks self-matches. ",
        "Singleton score estimates will use global mean instead of self-match scores."
      ),
      length(missing_ids)
    ))
  }

  df_singletons <- if (has_self_match) {
    df_logit |>
      dplyr::filter(id_x %in% missing_ids, id_x == id_y) |>
      dplyr::distinct(id_x, .keep_all = TRUE)
  } else {
    # Fallback: take one row per missing_id with best score
    df_logit |>
      dplyr::filter(id_x %in% missing_ids) |>
      dplyr::group_by(id_x) |>
      dplyr::slice_max(score_logit, n = 1L, with_ties = FALSE) |>
      dplyr::ungroup()
  }

  df_singletons <- df_singletons |>
    dplyr::mutate(
      max_foreign_score  = noise_floor_transformed,
      max_congener_score = NA_real_,
      gap_logit          = max_gap_ceiling,
      rank_category      = "Singleton",
      N_Obs              = 1L
    )

  # ---- COMBINE + STRIP .x SUFFIXES ------------------------------------------
  dplyr::bind_rows(df_h1, df_singletons) |>
    dplyr::rename_with(~ sub("\\.x$", "", .x), dplyr::ends_with(".x"))
}


#' Train the hierarchical likelihood model on reference-vs-reference scores
#'
#' Fits an Empirical Bayes model using pairwise within-species match scores
#' (from `build_sequence_matrix()`) to learn species-specific score
#' distributions.  Per-species parameters are shrunk toward a global mean,
#' with shrinkage strength inversely proportional to the number of observations
#' for that species.  Optionally uses `lme4` random intercepts per taxonomic
#' rank for more robust estimation.
#'
#' @section Model structure:
#' For each candidate hypothesis the model uses a 2-dimensional multivariate
#' normal distribution over `(score_logit, gap_logit)`:
#' * **H1 (known species):** species-specific mean with shrinkage; global
#'   covariance matrix.
#' * **H2 (missing species):** H1 mean shifted left by `H2$delta` --
#'   approximately what a sister species looks like. `H2$delta` is a single
#'   value pooled across every genus in the training set; where a genus has
#'   real congener pairs in the reference, `H2_Lookup` provides a
#'   genus-specific delta (Empirical Bayes shrinkage toward `H2$delta`,
#'   identical in form to the per-species shrinkage below) that
#'   `evaluate_likelihoods()` prefers when available. See the "Per-genus
#'   delta shrinkage" section below.
#' * **H3 (missing genus):** H1 mean shifted further left by `H3$delta`.
#'
#' @section Marker validation scope:
#' The continuous bivariate-normal form above (as opposed to a discrete
#' "100\% match or nothing" rule) was empirically validated against real
#' PtConception data for the 12S and 18S markers only (see the "Framing B
#' verdict" project notes) -- 100\% rules were shown unreliable at the
#' congeneric level, and the bivariate-normal form captured the real score
#' distribution well for those two markers specifically. Nothing in this
#' function checks that the same form fits a different marker (e.g. COI,
#' 16S, cytb, rbcL, matK, trnL -- all now trainable here via
#' `trim_to_amplicon()`) before fitting it. Run
#' `diagnostics/seq_matrix_score_distribution.R` on `build_sequence_matrix()`
#' output for a new marker before trusting this model there -- it checks
#' logit-normality and the H1/H2 spike ratio, the two properties this
#' function's Gaussian form assumes hold.
#'
#' @section Per-genus delta shrinkage:
#' The pooled, global `H2$delta` treats every genus identically, which is a
#' poor approximation for genera whose real congeneric divergence is far from
#' the training-set average -- most consequentially for cryptic species
#' complexes, where true divergence is much smaller than the pooled estimate
#' and the pooled delta will overstate confidence in the known-species
#' hypothesis. Where a genus has at least one real congener pair in the
#' reference database, `H2_Lookup` stores a genus-specific delta shrunk
#' toward the pooled value by `n_pairs / (n_pairs + prior_weight)` (the same
#' Empirical Bayes form used for per-species means). A genus with only one
#' referenced species (no congener pairs at all) gets no `H2_Lookup` row and
#' falls back to the pooled `H2$delta` unchanged -- there is no way to
#' estimate local divergence from a single species, and none is invented.
#' This says nothing about whether an unreferenced congener is plausible in
#' the first place (that is a prior-side question, answered by
#' \code{TaxaExpect} from occurrence/richness data, not by this function) --
#' only about how far its likelihood should be shifted from a known match
#' \emph{if} one exists. Nor does it address the case where a query's true
#' relatives are absent from the reference for reasons unrelated to sequence
#' divergence (e.g. an unreferenced acoustic or visual mimic in the acoustic
#' and image pathways, where evidence similarity need not track phylogeny at
#' all) -- see `inst/TaxaLikely_supplemental_methods.md` for a fuller
#' discussion of that limitation.
#'
#' @section Pseudo-data anchoring:
#' When `anchor_perfect = TRUE`, synthetic "perfect match" observations are
#' injected into the H1 training data before fitting the global mean.  This
#' softens the **perfection penalty** -- a pathology where a 100% match
#' receives a *lower* likelihood than the training mean (e.g., 98.5%) because
#' the Gaussian density peaks at the mean -- by nudging the *global* (pooled)
#' mean upward, diluted by however much real training data exists. It does
#' **not** force any individual species' own `H1_Lookup$mu_score` to the
#' ceiling (the anchor pseudo-rows are excluded from per-species estimation
#' before shrinkage happens) and does **not**, on its own, guarantee a
#' monotonically increasing density as match quality approaches 100% for any
#' given species -- see the "Non-monotonic score->likelihood shape" section
#' below for what property this model actually needs (and checks
#' automatically), and why a peaked-below-100%-density is not itself a
#' problem. The number of anchor points is 10% of the H1 training rows
#' (minimum 5), weighted enough to nudge the pooled mean without overwhelming
#' real data.
#'
#' This is not a workaround standing in for "a real Bayesian model" -- it IS
#' one, via the standard prior-as-pseudo-observations construction for
#' conjugate Normal estimation: adding `n0` synthetic rows at a target value
#' is mathematically equivalent to placing a `Normal(target, sigma^2/n0)`
#' prior on the mean and computing the closed-form posterior mean, the exact
#' same `w = N/(N+prior_weight)` Empirical Bayes shrinkage form already used
#' throughout this model for per-species/per-genus estimates (see
#' `prior_weight` above). Implementing it as injected rows, rather than a
#' second, separately-coded prior-density formula, keeps this correction on
#' the same estimation machinery as everything else in the model instead of
#' adding a parallel mechanism to keep in sync. It is also deliberately NOT a
#' tight/strong prior: capped at 10% of real H1 rows (min 5) specifically so
#' it nudges the pooled global mean rather than dominating it, and it is
#' never applied to any individual species' own shrunk estimate -- only the
#' pooled global mean is nudged, and only diluted by however much real
#' training data exists (a species with abundant real data is essentially
#' unaffected).
#'
#' @section Non-monotonic score->likelihood shape:
#' A trained species' H1 density is a Gaussian (or bivariate normal, jointly
#' with gap) on the transformed score, and a Gaussian is unimodal by
#' construction -- it peaks at that species' own fitted `mu_score`, not
#' necessarily at the transformed value of a perfect (100%) match. Since
#' `mu_score` is estimated from real reference-pair comparisons (which are
#' essentially never *exactly* 100% identical even for the correct species,
#' due to real intraspecific variation and sequencing/assembly noise) and
#' real query-time scores run measurably below the training-only mean on top
#' of that (`calibrate_query_noise()`'s own real-data finding: trained means
#' commonly sit 0.6-1.2 percentage points above real production query
#' medians), it is normal and expected for a species' H1 density to peak at
#' an intermediate score and decline, rather than increase, as score
#' approaches 100%. **This is not itself a sign of overfitting or a
#' bug** -- it is the correct behavior of a well-specified Gaussian estimating
#' a quantity whose true mean is genuinely below the ceiling.
#'
#' What actually matters for a Bayesian classifier is not where the H1
#' density's own peak sits, but whether the **H1-vs-H2 likelihood
#' ratio** stays monotone at the ceiling -- i.e. whether a better score is
#' ever *weaker*, rather than stronger or equal, evidence for the
#' known-species hypothesis relative to the missing-species alternative. Two
#' Gaussians with different means and different variances can, in principle,
#' cross twice, so this is checked directly (not assumed) at the end of
#' training via an internal `.check_score_ratio_monotonicity()`, using the
#' same inference-time sigma floor `evaluate_likelihoods()` applies. A
#' `warning()` is raised if any species' ratio turns over before the ceiling,
#' or if any species' perfect-match point sits implausibly far (more than 2
#' floored standard deviations) from its own fitted mean -- both symptoms are
#' recorded in the returned object's `Stats` list (`mlr_violations` and
#' `max_ceiling_z` respectively) for inspection.
#'
#' On real production models (Great Lakes, Mugu; all trained with
#' `score_transform = "sqrt_mismatch"`), this was checked empirically across
#' ~2,000 real species and found negligible: the likelihood ratio was
#' strictly increasing all the way to a perfect match in every case, and the
#' worst observed distance from a species' fitted mean to the ceiling was
#' 0.85 floored standard deviations (0% exceeded 1 SD). The one severe case
#' found (median ~2.5 floored SDs, some species effectively at the boundary)
#' was a stale, orphaned model object still trained with
#' `score_transform = "logit"` -- under `logit`, the transformed value of a
#' perfect match is not a fixed point determined by real data but is set by
#' `logit_epsilon` (a numerical-hygiene constant), and the default sits only
#' about one order of magnitude away from a value that would make every
#' perfect match implausible under every species' own fitted distribution.
#' `score_transform = "sqrt_mismatch"` does not have this fragility (a
#' perfect match maps to exactly `0`, the finite edge of that transform's own
#' range, with no free parameter) and is the more robust choice for any new
#' training run near this boundary.
#'
#' @param raw_df Data frame of pairwise match scores, as returned by
#'   `build_sequence_matrix()`.  Passed through `.prep_training_data()`.
#' @param rank_system Character vector of rank names, **coarse to fine**
#'   (e.g., `c("family", "genus", "species")`). Default `NULL` auto-detects
#'   from the `.x`-suffixed columns in `raw_df`.
#' @param score_bounds Optional `c(min, max)` for score normalization.
#' @param min_observed_sigma Numeric or `NULL` (default).  Floor on observed
#'   within-species score variance.  Prevents overfitting on species with very
#'   low variance (e.g., a species with two nearly identical reference
#'   sequences).  `NULL` resolves to `1.0` for `score_transform = "logit"`
#'   (in logit space, 1.0 corresponds to meaningful within-species variation)
#'   or the equivalent rescaled value for `"sqrt_mismatch"` -- see
#'   `score_transform` below.
#' @param prior_weight Numeric.  Equivalent pseudo-sample size for Empirical
#'   Bayes shrinkage toward the global mean.  Controls how strongly
#'   species-specific estimates are regularized.  A value of 10 means each
#'   species estimate is pulled toward the global mean as if 10 additional
#'   observations at the global mean had been added.  Higher values produce
#'   more conservative (less species-specific) estimates; lower values trust
#'   per-species data more but risk overfitting for species with few
#'   references.  Default `10.0`.
#' @param use_hierarchy Logical (default `TRUE`).  If `TRUE` and `lme4` is
#'   available, fits random intercepts per rank level to stabilize estimates
#'   across the taxonomic hierarchy.
#' @param anchor_perfect Logical (default `TRUE`).  If `TRUE`, injects
#'   synthetic perfect-match observations into the H1 training data to
#'   prevent the perfection penalty (see section below).
#' @param logit_epsilon Numeric.  Logit-clipping value (default `1e-4`).
#'   Used only when `score_transform = "logit"`.
#' @param max_gap_ceiling Numeric or `NULL` (default).  Gap cap.  `NULL`
#'   resolves to `5.0` for `score_transform = "logit"` (roughly the gap
#'   between 99.3% and 50% identity, in logit units) or `0.6234` for
#'   `"sqrt_mismatch"` (the same 99.3%-vs-50% reference gap on that scale) --
#'   prevents extreme outliers from dominating model estimates either way.
#' @param score_transform Character, `"logit"` (default) or `"sqrt_mismatch"`.
#'   The scale H1/H2/H3 are all modeled on -- must be shared across all three
#'   hypotheses, since they are compared via density ratios at the same
#'   observed point (a valid likelihood ratio requires one consistent scale;
#'   mixing transforms across hypotheses would need an explicit
#'   change-of-variables correction that this package does not implement).
#'   `"logit"` (`log(p/(1-p))`) is the package's original scale. `"sqrt_mismatch"`
#'   (`-sqrt(1-p)`) was added in Session 158 after real 12S congener data
#'   showed `"logit"` gives a genuinely backwards answer for one of the
#'   package's more novel claims: whether a genus's species are hard to tell
#'   apart (small, consistent divergence) or easy to tell apart (larger,
#'   more variable divergence). On the raw match-proportion scale, tight
#'   genera show lower congener-score variance, as expected -- but under
#'   `"logit"`, this can reverse sign, because nearly all real barcode
#'   matches sit close to 100% identity, exactly where logit's derivative
#'   diverges fastest. `"sqrt_mismatch"` treats divergence as a rare-event
#'   count (few mismatches out of many aligned bases -- the regime real data
#'   is actually in), for which square-root is the classical
#'   variance-stabilizing transform; it recovers the correct qualitative
#'   ordering where `"logit"` does not. See `evaluate_likelihoods()`'s own
#'   documentation and `[[project_job2_unreferenced_relatives]]` in the
#'   TaxaID memory system for the full empirical derivation, including why
#'   several other standard transforms (probit, complementary log-log) were
#'   checked and rejected. `"sqrt_mismatch"` is bounded to `[-1, 0]` rather
#'   than unbounded like `"logit"` -- a Gaussian fit to it is technically an
#'   approximation for that reason, but a mild one in practice, since real
#'   observations concentrate near 0 (good matches), far from the -1
#'   boundary. **Not yet ported to this scale**: `calibrate_query_noise()`
#'   and `evaluate_likelihoods()`'s `evidence_col`/`min_coverage` mechanisms
#'   all assume `"logit"` internally and will error rather than silently
#'   produce wrong numbers if combined with a `"sqrt_mismatch"`-trained model.
#'
#' @section No built-in reference-quality screening (2026-09-08):
#' This function does NOT screen `raw_df` for mislabeled/contaminated
#' reference accessions before fitting -- it trains on exactly what it's
#' given. Earlier versions called an internal, free, within-reference-set
#' heuristic (`flag_reference_errors()`, retired this date) unconditionally
#' on every run; a 2026-08-08 audit found it roughly 6.7% precise against
#' `TaxaMatch::evaluate_reference_accessions()`'s BLAST-based screen (0 of 40
#' randomly-sampled real flags confirmed as genuine mislabels on one real
#' dataset), and a newer TaxaMatch mechanism
#' (`TaxaMatch::corroborate_references_locally()` +
#' `TaxaMatch::evaluate_reference_accessions()`) already does the same job
#' more precisely, for the same zero/low NCBI cost, directly on `reference_df`
#' before it ever reaches `build_sequence_matrix()`. Screen there, exclude
#' any accession `evaluate_reference_accessions()`/`score_reference_labels()`
#' resolves to `reference_action == "remove"` from `reference_df` (or from
#' `raw_df` by `id_x`/`id_y`) before calling this function -- there is no
#' longer a parameter here to pass a bad-accession list through.
#'
#' @return A named list (class `"taxa_model_params"`) with slots:
#'   \describe{
#'     \item{`H1_Lookup`}{Data frame with per-species parameters: `lookup_key`,
#'       `rank`, `mu_score`, `mu_gap`, `sigma_score`, `n_obs_species` (number of
#'       within-species reference sequences trained on -- used by
#'       `evaluate_likelihoods()` to weight the Monte Carlo uncertainty of the
#'       trained mean; see that function's own documentation).}
#'     \item{`H1_Global_Mu`}{Named numeric vector: `score_logit`, `gap_logit`.}
#'     \item{`H1_Sigma`}{2x2 covariance matrix for the global H1 distribution.}
#'     \item{`Score_Transform`}{Character, `"logit"` or `"sqrt_mismatch"` --
#'       the scale this model's H1/H2/H3 parameters were fit on. Read
#'       automatically by `evaluate_likelihoods()`; callers should not need
#'       to track or re-supply it.}
#'     \item{`H2`}{List with `delta` and `sigma` for the missing-species
#'       hypothesis (pooled across all genera).}
#'     \item{`H3`}{List with `delta` and `sigma` for the missing-genus
#'       hypothesis.}
#'     \item{`H2_Lookup`}{Data frame (or `NULL`) with per-genus `H2` delta and
#'       variance estimates: `genus`, `n_pairs`, `delta_shrunk`, `var_shrunk`
#'       (Session 158). See "Per-genus delta shrinkage" section below.}
#'     \item{`Confusion_Risk_Curves`}{List (or `NULL`) of genus-/family-equal-
#'       weighted, Empirical-Bayes-shrunk per-rank score curves, read by
#'       `evaluate_likelihoods()` to compute its `species_confusion_risk`/
#'       `genus_confusion_risk`/`family_confusion_risk` output columns -- a
#'       model-independent, score-only diagnostic of the risk that the raw
#'       match score is equally well explained by a confusable congener/
#'       confamilial/cross-family relative at the rank a hypothesis resolved
#'       to, distinct from this model's own trained bivariate-normal
#'       likelihood. `NULL` when `rank_system` has fewer than 2 levels or the
#'       required taxonomy columns aren't usable (`species_confusion_risk`/
#'       `genus_confusion_risk`/`family_confusion_risk` are then simply `NA`,
#'       never an error). See
#'       `.compute_rank_score_curves()`'s own documentation for the exact
#'       structure, and `compute_rank_thresholds()` for the sibling function
#'       that derives `TaxaAssign::score_consensus()`'s `rank_thresholds`
#'       from the same underlying curves.}
#'     \item{`Stats`}{List of diagnostics (e.g., `AIC_Score` if lmer succeeded,
#'       `n_species`, `n_singletons`, `n_h1_pooled` -- total sequences behind
#'       the global H1 mean (informational only; NOT used as the Monte Carlo
#'       uncertainty fallback -- see `prior_weight` below) -- and
#'       `n_h2_pooled` -- foreign-match count behind the pooled global `H2`
#'       delta, `NA` when too few foreign matches existed to estimate one
#'       (also informational only). `prior_weight` -- the same value passed to
#'       this call -- is what `evaluate_likelihoods()` actually uses as the
#'       equivalent sample size for candidates with no species/genus-specific
#'       reference data at all: the true pooled sample size (`n_h1_pooled`/
#'       `n_h2_pooled`) reflects how well the GLOBAL average is known, not how
#'       confidently that average applies to a candidate we have zero direct
#'       data for, so using it directly would understate uncertainty exactly
#'       where it should be largest.}
#'   }
#'
#' @references
#' Efron, B. and Morris, C. (1973). Stein's estimation rule and its
#' competitors -- an empirical Bayes approach. \emph{Journal of the American
#' Statistical Association}, 68(341), 117--130.
#' \doi{10.1080/01621459.1973.10481350}
#'
#' Somervuo, P., Koskela, S., Pennanen, J., Nilsson, R.H. and Ovaskainen, O.
#' (2017). Unbiased probabilistic taxonomic classification for DNA barcoding.
#' \emph{Bioinformatics}, 33(19), 2997--3005.
#' \doi{10.1093/bioinformatics/btx369}
#'
#' Genz, A., Bretz, F., Miwa, T., Mi, X., Leisch, F., Scheipl, F. and
#' Hothorn, T. (2023). \emph{mvtnorm: Multivariate Normal and t
#' Distributions}. R package. \doi{10.5281/zenodo.10021696}
#'
#' Hebert, P.D.N., Cywinska, A., Ball, S.L. and deWaard, J.R. (2003).
#' Biological identifications through DNA barcodes. \emph{Proceedings of
#' the Royal Society of London B}, 270(1512), 313--321.
#' \doi{10.1098/rspb.2002.2218}
#'
#' @seealso [evaluate_likelihoods()], [interpret_model()]
#'
#' @note For a fully runnable, non-`\dontrun{}` demonstration (including how
#'   `reference_df` is derived), see `inst/review_function_inputs.R`
#'   Section 2 in the package source.
#'
#' @examples
#' \dontrun{
#' ref_matrix <- build_sequence_matrix(reference_df,
#'   rank_system = c("family", "genus", "species")
#' )
#' model <- train_likelihood_model(ref_matrix,
#'   rank_system = c("family", "genus", "species")
#' )
#' interpret_model(model)
#' }
#'
#' @importFrom dplyr bind_rows distinct ends_with filter group_by left_join mutate n
#' @importFrom dplyr rename_with select slice_max summarise ungroup case_when
#' @importFrom stats median setNames var lm coef
#' @export
train_likelihood_model <- function(raw_df,
                                   rank_system = NULL,
                                   score_bounds = NULL,
                                   min_observed_sigma = NULL,
                                   prior_weight = 10.0,
                                   use_hierarchy = TRUE,
                                   anchor_perfect = TRUE,
                                   logit_epsilon = 1e-4,
                                   max_gap_ceiling = NULL,
                                   score_transform = "logit") {
  score_transform <- match.arg(score_transform, c("logit", "sqrt_mismatch"))
  max_gap_ceiling <- .resolve_gap_ceiling(max_gap_ceiling, score_transform)
  if (is.null(min_observed_sigma)) {
    min_observed_sigma <- 1.0 * .transform_unit_ratio(score_transform)^2
  }
  if (!is.data.frame(raw_df)) {
    stop("raw_df must be a data frame")
  }

  # Auto-detect rank_system from .x-suffixed columns in raw_df
  if (is.null(rank_system)) {
    x_cols <- grep("\\.x$", tolower(names(raw_df)), value = TRUE)
    x_cols <- sub("\\.x$", "", x_cols)
    # Keep only recognised taxonomy ranks, in canonical coarse-to-fine order
    canonical <- c(
      "kingdom", "phylum", "subphylum", "superclass", "class",
      "subclass", "infraclass", "cohort", "order", "suborder",
      "infraorder", "family", "genus", "species"
    )
    rank_system <- canonical[canonical %in% x_cols]
    if (length(rank_system) < 2L) {
      stop(
        "Could not auto-detect rank_system from raw_df columns. ",
        "Found .x columns: ", paste(x_cols, collapse = ", "),
        ". Supply rank_system explicitly.",
        call. = FALSE
      )
    }
    message(sprintf(
      "Auto-detected rank_system: %s",
      paste(rank_system, collapse = ", ")
    ))
  }

  if (!is.character(rank_system) || length(rank_system) == 0L) {
    stop("rank_system must be a non-empty character vector (coarse to fine)")
  }
  if (!is.numeric(prior_weight) || length(prior_weight) != 1L || prior_weight <= 0) {
    stop("prior_weight must be a positive numeric scalar")
  }
  if (!is.logical(use_hierarchy) || length(use_hierarchy) != 1L || is.na(use_hierarchy)) {
    stop("use_hierarchy must be TRUE or FALSE")
  }
  if (!is.logical(anchor_perfect) || length(anchor_perfect) != 1L || is.na(anchor_perfect)) {
    stop("anchor_perfect must be TRUE or FALSE")
  }

  # No built-in reference-quality screening -- see @section "No built-in
  # reference-quality screening" above. raw_df is trained on as-is; a caller
  # wanting to exclude flagged accessions does so upstream, before calling
  # this function.
  raw_clean <- raw_df

  # ---- CONFUSION-RISK CURVES (2026-07-23) ------------------------------------
  # Genus-/family-equal-weighted, Empirical-Bayes-shrunk per-rank score curves
  # (diagnostics/score_floor_roc_sweep.R's reference implementation, made
  # real via .compute_rank_score_curves()) -- computed once at training time
  # and stored below, not recomputed from a raw seq_matrix on every inference
  # call. Feeds evaluate_likelihoods()'s species_confusion_risk/
  # genus_confusion_risk/family_confusion_risk columns. NULL when rank_system
  # is too short (< 2 levels) or the required taxonomy columns aren't usable
  # -- those three output columns are then simply NA, never an error.
  confusion_risk_curves <- tryCatch(
    .compute_rank_score_curves(raw_clean, rank_system, prior_weight = prior_weight),
    error = function(e) {
      warning(sprintf(
        paste0(
          "Failed to compute confusion-risk curves (%s); species_confusion_risk/",
          "genus_confusion_risk/family_confusion_risk will be unavailable."
        ),
        conditionMessage(e)
      ))
      NULL
    }
  )

  message("Preparing training data...")
  train_df <- .prep_training_data(
    raw_df          = raw_clean,
    rank_system     = rank_system,
    score_bounds    = score_bounds,
    logit_epsilon   = logit_epsilon,
    max_gap_ceiling = max_gap_ceiling,
    score_transform = score_transform
  )

  if (nrow(train_df) == 0L) {
    stop(paste0(
      "Training data is empty after preprocessing. Check that raw_df contains valid ",
      "pairwise match scores and that rank_system columns are present."
    ))
  }

  h1_data <- dplyr::filter(train_df, rank_category == "1_Known_Species")
  n_species <- dplyr::n_distinct(h1_data$rank_code_a)
  n_singletons <- sum(train_df$rank_category == "Singleton")

  if (nrow(h1_data) == 0L) {
    stop(paste0(
      "No H1 (within-species) pairs found -- cannot train model. All sequences may ",
      "be singletons (only one per species in the reference database)."
    ))
  }

  # ---- PSEUDO-DATA ANCHORING ------------------------------------------------
  # Anchoring is a form of informative pseudo-data, analogous to Bayesian
  # prior pseudo-counts. The 10% fraction nudges the global mean by ~0.5
  # logit units without overwhelming real data. For markers with very few
  # reference sequences (<50 total), anchoring has a larger relative effect;
  # inspect interpret_model() output to verify anchors did not distort the
  # H1 landscape.
  # Without anchoring, the H1 mean sits at the training average
  # (e.g., logit(0.985)) and a perfect 100% match falls in the tail.
  n_anchors <- 0L
  if (anchor_perfect) {
    perfect_logit <- .transform_p(1, score_transform, logit_epsilon)
    real_pos_gaps <- h1_data$gap_logit[h1_data$gap_logit > 0]
    if (length(real_pos_gaps) == 0L || all(is.na(real_pos_gaps))) {
      anchor_gap <- max_gap_ceiling
      if (all(is.na(real_pos_gaps))) {
        warning("All positive gaps are NA; using max_gap_ceiling for anchor gap.")
      }
    } else {
      # 95th percentile of positive within-species gaps: represents "typical
      # good separation" for anchor pseudo-data.
      anchor_gap <- stats::quantile(real_pos_gaps, 0.95, na.rm = TRUE)
    }
    # Anchor count: max(5, 10% of training rows). 5 ensures anchoring even
    # for tiny datasets; 10% prevents dilution of real data.
    n_anchors <- max(5L, ceiling(nrow(h1_data) * 0.10))

    anchor_rows <- data.frame(
      score_logit   = rep(perfect_logit, n_anchors),
      gap_logit     = rep(as.numeric(anchor_gap), n_anchors),
      rank_category = "1_Known_Species",
      N_Obs         = 1L
    )
    # Fill taxonomy_code columns with placeholder so lme4 doesn't error
    code_cols_pre <- names(h1_data)[grepl("^rank_code_", names(h1_data))]
    for (cc in code_cols_pre) anchor_rows[[cc]] <- "ANCHOR_PERFECT"

    h1_data <- dplyr::bind_rows(h1_data, anchor_rows)
    message(sprintf(
      "Anchoring: injected %d perfect-match pseudo-observations",
      n_anchors
    ))
  }

  # ---- GLOBAL PRIOR ---------------------------------------------------------
  global_mu_score <- mean(h1_data$score_logit, na.rm = TRUE)
  global_mu_gap <- mean(h1_data$gap_logit, na.rm = TRUE)
  global_var_score <- max(
    stats::var(h1_data$score_logit, na.rm = TRUE),
    min_observed_sigma
  )
  global_var_gap <- max(
    stats::var(h1_data$gap_logit, na.rm = TRUE),
    min_observed_sigma
  )
  global_cov <- tryCatch(
    stats::cov(cbind(score_logit = h1_data$score_logit, gap_logit = h1_data$gap_logit)),
    error = function(e) {
      warning("Covariance estimation failed (likely too few observations). Using diagonal fallback.")
      matrix(c(global_var_score, 0, 0, global_var_gap), 2, 2,
        dimnames = list(c("score_logit", "gap_logit"), c("score_logit", "gap_logit"))
      )
    }
  )
  if (any(!is.finite(global_cov))) {
    warning("Non-finite values in covariance matrix. Using diagonal fallback.")
    global_cov <- matrix(c(global_var_score, 0, 0, global_var_gap), 2, 2,
      dimnames = list(c("score_logit", "gap_logit"), c("score_logit", "gap_logit"))
    )
  }
  diag(global_cov) <- pmax(diag(global_cov), min_observed_sigma)

  # ---- OPTIONAL lme4 HIERARCHY ----------------------------------------------
  lmer_mu_score <- NULL
  lmer_mu_gap <- NULL
  aic_score <- NA_real_

  # sort(): .generalize_ranks() renames rank columns IN PLACE, so `train_df`'s
  # own column order is rank_system's own coarse-to-fine order -- i.e.
  # rank_code_c, rank_code_b, rank_code_a for c("family", "genus", "species").
  # Every use of `code_cols` below assumes the OPPOSITE (finest first), so that
  # `code_cols[-1L]` means "every rank above the finest" and `code_cols[-1L][1]`
  # means the second-finest rank (genus). Without the sort, `code_cols[-1L]`
  # dropped the COARSEST rank and wrongly included the finest one -- fitting
  # `(1 | genus) + (1 | species)` instead of the intended
  # `(1 | genus) + (1 | family)`, and (for any rank_system that is not exactly
  # three levels) reading the wrong column as "genus" when counting genera with
  # congener data. Sorting is safe because the codes are assigned by position
  # (a = finest, b = second-finest, ...), so alphabetical order IS fine-to-coarse
  # order.
  code_cols <- sort(names(train_df)[grepl("^rank_code_[a-z]$", names(train_df))])

  # Early exit: lme4 hierarchy is uninformative with too few species
  if (use_hierarchy && n_species < 10L) {
    message(sprintf(
      "Skipping lme4 hierarchy: only %d species (need >= 10).",
      n_species
    ))
    use_hierarchy <- FALSE
  }

  if (use_hierarchy && length(code_cols) >= 2L &&
    requireNamespace("lme4", quietly = TRUE)) {
    # Random intercepts for each rank level above species (code_b, code_c, ...)
    random_terms <- paste0("(1 | ", code_cols[-1L], ")", collapse = " + ")
    formula_score <- stats::as.formula(
      sprintf("score_logit ~ 1 + %s", random_terms)
    )
    formula_gap <- stats::as.formula(
      sprintf("gap_logit ~ 1 + %s", random_terms)
    )
    tryCatch(
      {
        fit_score <- lme4::lmer(formula_score,
          data = h1_data,
          control = lme4::lmerControl(optimizer = "bobyqa")
        )
        fit_gap <- lme4::lmer(formula_gap,
          data = h1_data,
          control = lme4::lmerControl(optimizer = "bobyqa")
        )
        lmer_mu_score <- lme4::fixef(fit_score)[["(Intercept)"]]
        lmer_mu_gap <- lme4::fixef(fit_gap)[["(Intercept)"]]
        aic_score <- stats::AIC(fit_score)
      },
      error = function(e) {
        message(sprintf(
          "lme4 fit failed (%s) -- falling back to global mean",
          conditionMessage(e)
        ))
      }
    )
  }

  mu_score_global <- if (!is.null(lmer_mu_score)) lmer_mu_score else global_mu_score
  mu_gap_global <- if (!is.null(lmer_mu_gap)) lmer_mu_gap else global_mu_gap

  # ---- PER-SPECIES LOOKUP WITH SHRINKAGE ------------------------------------
  message("Fitting per-species parameters with Empirical Bayes shrinkage...")
  species_params <- h1_data |>
    dplyr::group_by(rank_code_a) |>
    dplyr::summarise(
      n_obs_species = dplyr::n(),
      score_logit_mean = mean(score_logit, na.rm = TRUE),
      gap_logit_mean = mean(gap_logit, na.rm = TRUE),
      score_logit_var = max(stats::var(score_logit, na.rm = TRUE),
        min_observed_sigma,
        na.rm = TRUE
      ),
      .groups = "drop"
    ) |>
    dplyr::mutate(
      # Empirical Bayes shrinkage: w = N / (N + prior_weight).
      # James-Stein / Efron-Morris (1973) shrinkage estimator for Normal means.
      # prior_weight is the "equivalent sample size" of the prior: with
      # N = prior_weight observations, species and global means get equal weight.
      w = n_obs_species / (n_obs_species + prior_weight),
      shrunk_mu_score = w * score_logit_mean + (1 - w) * mu_score_global,
      shrunk_mu_gap = w * gap_logit_mean + (1 - w) * mu_gap_global,
      # Variance shrinkage via linear combination is an approximation to the
      # inverse-chi-squared posterior. Adequate for typical barcode reference
      # sizes (3-20 sequences per species).
      #
      # Session 158 fix: this used to take sqrt() of the shrunk variance
      # before storing it, producing an SD-shaped number in a slot
      # (`H1_Lookup$sigma_score`) that every downstream consumer -- the
      # species floor comparison against `H1_Sigma` (a true covariance
      # matrix, unaffected), the outlier chi-squared test, `dnorm(sd =
      # sqrt(...))`, `dmvnorm(sigma = ...)` -- treats as a VARIANCE, applying
      # its own sqrt() (or using it directly as a covariance diagonal entry)
      # on top. Net effect: species-specific H1 candidates were evaluated
      # against a variance equal to the FOURTH root of the intended shrunk
      # variance, not its square root -- systematically tighter
      # (overconfident) than the training data actually supports. This was
      # invisible on the logit scale (shrunk variances ~1.5-2.5, where the
      # extra sqrt is a ~15-25% correction, not obviously wrong-looking) and
      # only became impossible to miss once Session 158's score_transform
      # work put real variances on a much smaller natural scale (~0.01-0.1),
      # where the same bug produces a 3-6x distortion. Confirmed directly:
      # hand-reproduced this formula against real 12S training data and
      # matched the shipped code's literal (buggy) output before concluding
      # this was real, not a misreading. Fixed by storing the shrunk
      # variance itself, with no extra sqrt -- consistent with
      # `global_var_score`/`H1_Sigma` (always true variances) and with every
      # downstream consumer's own expectation.
      shrunk_sigma = w * score_logit_var + (1 - w) * global_var_score
    )

  # Remove anchor pseudo-species from lookup
  species_params <- dplyr::filter(
    species_params,
    rank_code_a != "ANCHOR_PERFECT"
  )

  H1_Lookup <- tibble::tibble(
    lookup_key     = species_params$rank_code_a,
    rank           = rank_system[length(rank_system)],
    mu_score       = species_params$shrunk_mu_score,
    mu_gap         = species_params$shrunk_mu_gap,
    sigma_score    = species_params$shrunk_sigma,
    n_obs_species  = species_params$n_obs_species
  )

  # ---- H2 / H3 PARAMETERS ---------------------------------------------------
  # H2 delta AND variance are estimated from real CONGENER comparisons
  # (max_congener_score: same-genus, different-species matches) wherever
  # possible -- both the pooled default and the per-genus shrinkage below use
  # this same, more specific population. (Session 158 fix: previously the
  # pooled default alone used max_foreign_score -- matches to ANY other
  # species in ANY genus -- a broader, noisier population than what the
  # per-genus shrinkage was already comparing against, so a genus with NO
  # congener data of its own fell back to a variance estimated from a subtly
  # different, less relevant reference population than genera that DID have
  # local data. Confirmed empirically to matter: the old pooled variance from
  # max_foreign_score was 9.58 on real 12S data; the correctly-sourced
  # congener-only pooled variance is 5.91.)
  # H3 delta = H2 delta + 2.0 (one additional rank step away, unscaled here --
  # see note at H3's own definition below for why this offset itself still
  # needs a transform-aware equivalent).
  # Both sigma slots are 2x2 matrices for compatibility with dmvnorm.
  unit_ratio <- .transform_unit_ratio(score_transform)

  # Default H2 delta: 3 logit units ~ 95% vs 50% on the probability scale (or
  # the transform_unit_ratio-rescaled equivalent) -- a reasonable default for
  # typical barcode markers (COI, 12S) before any real congener data is seen.
  # Marker-specific tuning is handled automatically when sufficient congener
  # data exists (see empirical override below).
  h2_delta_val <- 3.0 * unit_ratio
  h2_var <- 1.0 * unit_ratio^2 # default before empirical override
  H2_Lookup <- NULL
  n_h2_pooled <- NA_integer_ # sample size behind h2_delta_val, for SE-of-delta use at inference
  noise_floor_congener <- .transform_p(0.007, score_transform, logit_epsilon)

  if (nrow(h1_data) > 5L && "max_congener_score" %in% names(train_df)) {
    h2_source_all <- train_df[train_df$rank_category == "1_Known_Species", ]

    # Pooled default population: real congener comparisons only, filtered the
    # same way the old max_foreign_score pool was (drop extreme low-identity
    # outliers below the ~0.7% noise floor) so this remains comparable in
    # spirit to the previous default.
    congener_keep <- !is.na(h2_source_all$max_congener_score) &
      h2_source_all$max_congener_score > noise_floor_congener
    congener_df <- h2_source_all[congener_keep, , drop = FALSE]
    congener_pool <- congener_df$max_congener_score

    if (length(congener_pool) > 2L) {
      n_h2_pooled <- length(congener_pool)

      # ---- OPTIONAL lme4 HIERARCHY FOR THE POOLED CONGENER MEAN -------------
      # Mirrors the H1_Global_Mu hierarchy fit above, for the identical reason:
      # a naive row-weighted mean(congener_pool) is dominated by whichever
      # genus contributes the most reference sequences to this pool. Confirmed
      # as a real, measurable (not hypothetical) bias on real 12S data:
      # Sebastes is only 7% of congener_pool rows (the per-sequence "best
      # congener match" collapse above already dilutes its much larger ~31%
      # share of raw pairwise comparisons), but its congeners are so close to
      # indistinguishable (its own genus-specific delta hits the 0.5-unit
      # floor) that including it row-weighted still pulls the pooled mean
      # toward "congeners are more competitive than a typical genus" by
      # ~8-9% relative to a genus-equal-weighted estimate. A random-intercept
      # model absorbs this the same way it already does for H1_Global_Mu --
      # the fixed intercept estimates the population-average GENUS mean, not
      # the row-weighted pooled mean. Falls back to the naive pooled mean
      # under the same conditions H1's own hierarchy fit already falls back
      # under (use_hierarchy = FALSE, too few rank levels, lme4 unavailable,
      # too few genera, or non-convergence) -- same graceful-degradation
      # contract as H1, never a hard requirement.
      lmer_h2_mean <- NULL
      if (use_hierarchy && length(code_cols) >= 2L &&
        requireNamespace("lme4", quietly = TRUE)) {
        genus_col_h2 <- code_cols[-1L][1]
        n_genera_h2 <- length(unique(congener_df[[genus_col_h2]]))
        if (n_genera_h2 >= 10L) {
          random_terms_h2 <- paste0("(1 | ", code_cols[-1L], ")", collapse = " + ")
          formula_h2 <- stats::as.formula(
            sprintf("max_congener_score ~ 1 + %s", random_terms_h2)
          )
          tryCatch(
            {
              fit_h2 <- lme4::lmer(formula_h2,
                data = congener_df,
                control = lme4::lmerControl(optimizer = "bobyqa")
              )
              lmer_h2_mean <- lme4::fixef(fit_h2)[["(Intercept)"]]
            },
            error = function(e) {
              message(sprintf(
                "lme4 fit failed for pooled H2 delta (%s) -- falling back to row-weighted mean",
                conditionMessage(e)
              ))
            }
          )
        } else {
          message(sprintf(
            "Skipping lme4 hierarchy for pooled H2 delta: only %d genera with congener data (need >= 10).",
            n_genera_h2
          ))
        }
      }
      congener_pool_mean <- if (!is.null(lmer_h2_mean)) {
        lmer_h2_mean
      } else {
        mean(congener_pool, na.rm = TRUE)
      }

      # Minimum H1-H2 separation ensures unreferenced-species hypothesis is
      # always distinguishable from known-species hypothesis (rescaled from
      # the original 0.5-logit-unit floor -- an ad hoc choice to begin with,
      # kept proportionally consistent across transforms via unit_ratio
      # rather than invented fresh per scale).
      h2_delta_val <- max(0.5 * unit_ratio, mu_score_global - congener_pool_mean)
      # Minimum H2 variance (rescaled from the original 0.1-logit-unit^2
      # floor) prevents degenerate zero-variance estimates when few congener
      # matches exist. Left row-weighted/naive, matching H1's own
      # global_var_score above -- the hierarchy fit only ever corrects the
      # MEAN (both here and for H1), not the variance.
      h2_var <- max(stats::var(congener_pool, na.rm = TRUE), 0.1 * unit_ratio^2)

      # ---- PER-GENUS DELTA + VARIANCE SHRINKAGE (Empirical Bayes, same form
      # as H1) ----------------------------------------------------------
      # h2_delta_val/h2_var above pool cross-species divergence across every
      # genus in the training set, so a genus with unusually tight
      # (cryptic-like) or unusually loose congeneric divergence gets the
      # exact same constants as every other genus -- the model has no way to
      # tell them apart. Where a genus has real congener pairs in the
      # reference (max_congener_score -- NA when the genus has no second
      # referenced species at all), shrink a genus-specific delta AND
      # variance toward the pooled values with the identical
      # w = n / (n + prior_weight) form used for H1 species means above.
      # Genera with no congener data (monotypic in the reference database,
      # regardless of how many species the genus has in nature) simply get
      # no lookup row and fall back to the pooled defaults unchanged -- there
      # is no local information to borrow, and none is invented.
      #
      # Session 158: the genus-specific VARIANCE is new. Previously only the
      # delta (mean shift) was genus-specific; the variance was always the
      # single pooled value regardless of genus. Real data shows this
      # matters directionally, not just in magnitude: on the raw match-
      # proportion scale, a tight genus (species hard to tell apart, e.g.
      # Sardinops: mean congener similarity 99.9%) has ~0 congener variance,
      # while a loose genus (e.g. Symphurus: mean 90.5%) has real, much
      # larger variance -- confirmed on real 12S congener data
      # (Pearson r = -0.55 between per-genus mean similarity and variance).
      # This is exactly why H2/H3 needed the score_transform fix above too:
      # under plain logit, this relationship reverses sign (genuinely tight
      # genera can appear MORE variable), an artifact of logit's diverging
      # derivative near p=1 where nearly all real barcode matches sit -- see
      # [[project_job2_unreferenced_relatives]] in the TaxaID memory system
      # for the full empirical derivation.
      if ("rank_code_b" %in% names(h2_source_all)) {
        genus_h2 <- h2_source_all |>
          dplyr::filter(!is.na(rank_code_b), !is.na(max_congener_score)) |>
          dplyr::group_by(rank_code_b) |>
          dplyr::summarise(
            n_pairs    = dplyr::n(),
            mean_cong  = mean(max_congener_score, na.rm = TRUE),
            var_cong   = stats::var(max_congener_score, na.rm = TRUE),
            .groups    = "drop"
          ) |>
          dplyr::mutate(
            delta_emp = mu_score_global - mean_cong,
            w = n_pairs / (n_pairs + prior_weight),
            delta_shrunk = pmax(0.5 * unit_ratio, w * delta_emp + (1 - w) * h2_delta_val),
            # var_cong is NA for genera with exactly 1 congener pair (no
            # within-genus variance to estimate) -- shrinkage then reduces to
            # the pooled value entirely (w * NA would propagate NA, so treat
            # the local term as absent rather than undefined).
            var_shrunk = ifelse(
              is.na(var_cong),
              h2_var,
              w * var_cong + (1 - w) * h2_var
            )
          )
        if (nrow(genus_h2) > 0L) {
          H2_Lookup <- tibble::tibble(
            genus        = genus_h2$rank_code_b,
            n_pairs      = genus_h2$n_pairs,
            delta_shrunk = genus_h2$delta_shrunk,
            var_shrunk   = genus_h2$var_shrunk
          )
        }
      }
    }
  }

  h2_sigma_mat <- matrix(c(h2_var, 0, 0, 1.0 * unit_ratio^2), ncol = 2L)
  rownames(h2_sigma_mat) <- colnames(h2_sigma_mat) <- c("score_logit", "gap_logit")
  h3_sigma_mat <- diag(2) * unit_ratio^2
  rownames(h3_sigma_mat) <- colnames(h3_sigma_mat) <- c("score_logit", "gap_logit")

  H2 <- list(delta = h2_delta_val, sigma = h2_sigma_mat)
  # H3 delta = H2 delta + 2.0 (logit units) / rescaled equivalent: heuristic
  # representing one additional taxonomic rank step (genus-level mismatch vs
  # species-level mismatch). Applied on top of whichever H2 delta -- pooled
  # global or genus-specific via H2_Lookup -- is selected at inference time;
  # see .evaluate_one_query(). H3 itself has no genus-specific estimate
  # (would need family-level congener data); low priority, noted as a
  # possible future extension.
  H3 <- list(delta = h2_delta_val + 2.0 * unit_ratio, sigma = h3_sigma_mat)

  # ---- NON-MONOTONICITY / MONOTONE-LIKELIHOOD-RATIO DIAGNOSTIC --------------
  # Added following a statistical-critique session prompted by a user
  # observation that the fitted score->likelihood relationship can peak at an
  # intermediate score rather than at a perfect (100%) match -- see this
  # function's own "Non-monotonic score->likelihood shape" @section below for
  # the full analysis and why a peaked-below-the-ceiling H1 DENSITY is
  # expected and not itself a problem. What DOES matter for a Bayesian
  # classifier is whether the H1-vs-H2 LIKELIHOOD RATIO stays monotone (a
  # better score is never weaker evidence for the known-species hypothesis
  # than a worse one) -- checked here directly rather than assumed, per-
  # species, at the transformed value of a perfect match. Uses the SAME
  # inference-time sigma floor evaluate_likelihoods() applies
  # (max(sigma_species, global_sigma), Session 121) -- checking the raw,
  # unfloored sigma_score overstates how severe any violation would actually
  # be at inference time (this exact mistake was caught and corrected during
  # the critique session that motivated this check).
  species_genus <- if ("rank_code_b" %in% names(h1_data)) {
    stats::setNames(h1_data$rank_code_b, h1_data$rank_code_a)
  } else {
    NULL
  }
  mlr_check <- .check_score_ratio_monotonicity(
    H1_Lookup       = H1_Lookup,
    global_sigma1   = global_cov[1L, 1L],
    H2              = H2,
    H2_Lookup       = H2_Lookup,
    species_genus   = species_genus,
    score_transform = score_transform,
    logit_epsilon   = logit_epsilon
  )
  if (length(mlr_check$violations) > 0L) {
    warning(sprintf(paste0(
      "%d of %d species have a non-monotone H1-vs-H2 likelihood ratio at a perfect ",
      "match: this species' own fitted score distribution is wide enough, relative to ",
      "its genus's H2 (missing-species) distribution, that a literal 100%% identity ",
      "match would be RELATIVELY WEAKER evidence for the known-species hypothesis than ",
      "a slightly lower score would be. Affected species are in model_params$Stats$",
      "mlr_violations. This does not necessarily make any single likelihood value ",
      "wrong, but the 'more identity is always at least as much evidence' property does ",
      "not hold for these species and is worth inspecting directly (e.g. via ",
      "interpret_model())."
    ), length(mlr_check$violations), nrow(H1_Lookup)), call. = FALSE)
  }
  if (isTRUE(mlr_check$max_z > 2)) {
    warning(sprintf(paste0(
      "Species '%s' has its fitted score mean %.2f SD (floored sigma) away from a ",
      "perfect match -- the H1 density has already substantially decayed by the time a ",
      "query reaches 100%% identity for this species. A small gap here is expected and ",
      "harmless (real production models typically run well under 1 SD); a value this ",
      "large is worth checking against score_transform (\"logit\" is the more fragile ",
      "of the two -- see this function's \"Non-monotonic score->likelihood shape\" ",
      "@section) and against how many reference sequences this species has."
    ), mlr_check$max_z_species, mlr_check$max_z), call. = FALSE)
  }

  message(sprintf(
    "Model trained: %d species, %d singletons. Global mu_score=%.2f, mu_gap=%.2f",
    n_species, n_singletons, mu_score_global, mu_gap_global
  ))

  structure(
    list(
      H1_Lookup = H1_Lookup,
      H1_Global_Mu = c(score_logit = mu_score_global, gap_logit = mu_gap_global),
      H1_Sigma = global_cov,
      H2 = H2,
      H3 = H3,
      H2_Lookup = H2_Lookup,
      Confusion_Risk_Curves = confusion_risk_curves,
      Score_Transform = score_transform,
      Stats = list(
        AIC_Score = aic_score,
        n_species = n_species,
        n_singletons = n_singletons,
        n_anchors = n_anchors,
        n_h1_pooled = sum(species_params$n_obs_species),
        n_h2_pooled = n_h2_pooled,
        prior_weight = prior_weight,
        mlr_violations = mlr_check$violations,
        max_ceiling_z = mlr_check$max_z,
        max_ceiling_z_species = mlr_check$max_z_species
      )
    ),
    class = "taxa_model_params"
  )
}

#' Check H1-vs-H2 log-likelihood-ratio monotonicity at a perfect match
#'
#' For each species, checks whether the H1 (known-species) density remains at
#' least as strong, relative to its genus's H2 (missing-species) alternative,
#' as the score improves all the way to a perfect match -- the
#' monotone-likelihood-ratio (MLR) property that actually matters for a
#' Bayesian classifier, as distinct from whether the H1 density's own PEAK
#' sits at the ceiling (it need not -- see train_likelihood_model()'s
#' "Non-monotonic score->likelihood shape" @section). For two univariate
#' normals sharing an evaluation point x, `log(f1(x)/f2(x))` has derivative
#' `(mu1 - x)/sigma1 + (x - mu2)/sigma2`; evaluated at the transformed value
#' of a perfect match, a positive value means the ratio is still increasing
#' there (a better score at the ceiling is still relatively stronger evidence
#' for H1), a negative value means it has already turned over.
#'
#' @param H1_Lookup Data frame with `lookup_key`, `mu_score`, `sigma_score`.
#' @param global_sigma1 Numeric. Global H1 score variance, used as the same
#'   inference-time floor `evaluate_likelihoods()` applies to `sigma_score`.
#' @param H2 List with `delta` (pooled) and `sigma` (2x2, `[1,1]` used).
#' @param H2_Lookup Data frame with `genus`, `delta_shrunk`, `var_shrunk`, or
#'   `NULL` if no genus had a real congener pair.
#' @param species_genus Named character vector (species -> genus), or `NULL`
#'   if the training data had no genus-level rank column.
#' @param score_transform,logit_epsilon Passed to `.transform_p()` to compute
#'   the transformed value of a perfect (100%) match.
#'
#' @return List with `violations` (character vector of species names whose
#'   ratio turns over before the ceiling), `max_z` (largest per-species
#'   distance, in floored SDs, from `mu_score` to the perfect-match point),
#'   and `max_z_species` (the species attaining it).
#' @noRd
.check_score_ratio_monotonicity <- function(H1_Lookup, global_sigma1, H2, H2_Lookup,
                                            species_genus, score_transform,
                                            logit_epsilon) {
  if (nrow(H1_Lookup) == 0L) {
    return(list(violations = character(0), max_z = NA_real_, max_z_species = NA_character_))
  }

  perfect_x <- .transform_p(1, score_transform, logit_epsilon)

  mu1 <- H1_Lookup$mu_score
  sigma1 <- pmax(H1_Lookup$sigma_score, global_sigma1)
  genus <- if (!is.null(species_genus)) {
    unname(species_genus[H1_Lookup$lookup_key])
  } else {
    rep(NA_character_, nrow(H1_Lookup))
  }

  h2_delta <- rep(H2$delta, nrow(H1_Lookup))
  h2_var <- rep(H2$sigma[1L, 1L], nrow(H1_Lookup))
  if (!is.null(H2_Lookup) && nrow(H2_Lookup) > 0L) {
    m <- match(genus, H2_Lookup$genus)
    has_local <- !is.na(m)
    h2_delta[has_local] <- H2_Lookup$delta_shrunk[m[has_local]]
    h2_var[has_local] <- H2_Lookup$var_shrunk[m[has_local]]
  }
  mu2 <- mu1 - h2_delta

  slope_at_ceiling <- (mu1 - perfect_x) / sigma1 + (perfect_x - mu2) / h2_var
  z_at_ceiling <- (perfect_x - mu1) / sqrt(sigma1)

  violated <- !is.na(slope_at_ceiling) & slope_at_ceiling < 0
  best_i <- if (all(is.na(z_at_ceiling))) NA_integer_ else which.max(z_at_ceiling)

  list(
    violations    = H1_Lookup$lookup_key[violated],
    max_z         = if (is.na(best_i)) NA_real_ else z_at_ceiling[best_i],
    max_z_species = if (is.na(best_i)) NA_character_ else H1_Lookup$lookup_key[best_i]
  )
}
