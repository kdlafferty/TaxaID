# ==============================================================================
# detect_suppressed_candidates()  /  restore_suppressed_candidates()
# ==============================================================================
# Motivation: many pipelines suppress lower-scoring candidates from the match
# object, making referenced alternatives invisible to evaluate_likelihoods().
# Three pipeline rules are recognised and corrected:
#
#   Rule 1 -"perfect_only":  when >=1 candidate scores at or above
#     perfect_threshold, all sub-threshold candidates are dropped.  The
#     observation may have multiple rows (ties at the threshold) but never a
#     row below it.  (Example: Jonah Ventures 100% rule.)
#
#   Rule 2 -"max_score_ties": only tied-top candidates are returned; nothing
#     below the per-observation maximum is retained.  Multi-row observations
#     therefore show zero within-observation score variance.
#
#   Rule 3 -"best_only": each observation has exactly one row regardless of
#     score value.  Arises from top-1 classifiers, pre-computed consensus
#     assignments, or pipelines that report a single best match.
#
# detect_suppressed_candidates() diagnoses which (if any) rule is active.
# restore_suppressed_candidates() appends same-genus congeners from the
# reference database so that evaluate_likelihoods() (or assign_scores) can
# evaluate them as real alternatives.


#' Detect pipeline rules that suppress candidate rows in a match object
#'
#' Inspects a match object for evidence that an upstream tool suppressed
#' lower-scoring candidates.  Three patterns are recognised:
#'
#' \describe{
#'   \item{`"perfect_only"`}{Among observations where at least one candidate
#'     scores at or above \code{perfect_threshold}, none also contains a row
#'     below that threshold.  Typical cause: a 100-percent rule that drops all
#'     sub-perfect hits when a perfect match exists.}
#'   \item{`"max_score_ties"`}{Multi-row observations show zero within-
#'     observation score variance -only tied-top candidates were returned.}
#'   \item{`"best_only"`}{Essentially all observations have exactly one
#'     candidate row, indicating a top-1 pipeline, pre-computed consensus, or
#'     absence of a score column.}
#' }
#'
#' Detection is conservative: a rule is flagged only when the observed pattern
#' is present in at least \code{purity_threshold} of qualifying observations.
#'
#' @param match_obj Data frame. Standardised match object containing at least
#'   \code{observation_id_col}.  \code{score_col} is optional; Rules 1 and 2
#'   are skipped when it is absent.
#' @param score_col Character. Name of the score column (default
#'   \code{"score_original"}).
#' @param observation_id_col Character. Name of the observation ID column
#'   (default \code{"observation_id"}).
#' @param perfect_threshold Numeric. Score at or above which a candidate is
#'   considered a "perfect" match for Rule 1 detection (default \code{100}).
#'   Set to 95 for pipelines that enforce a 95-percent identity floor, for example.
#' @param purity_threshold Numeric in (0, 1]. Fraction of qualifying
#'   observations that must exhibit the pattern for the rule to be flagged
#'   (default \code{0.99}).  A high value reduces false positives from
#'   rounding artefacts.
#' @param singleton_threshold Numeric in (0, 1]. Fraction of all observations
#'   that must be singletons (1 row) for Rule 3 to be flagged (default
#'   \code{0.98}).
#'
#' @return A named list:
#' \describe{
#'   \item{`rule_detected`}{Logical. \code{TRUE} if any rule is flagged.}
#'   \item{`rules`}{Character vector of flagged rule names (may be empty).}
#'   \item{`perfect_only`}{Logical.}
#'   \item{`max_score_ties`}{Logical.}
#'   \item{`best_only`}{Logical.}
#'   \item{`has_score_col`}{Logical. Whether \code{score_col} was found.}
#'   \item{`n_total`}{Integer. Unique observations.}
#'   \item{`n_perfect_obs`}{Integer. Observations with >=1 score >=
#'     \code{perfect_threshold}.}
#'   \item{`purity_perfect`}{Numeric. Fraction of perfect-obs that are pure
#'     (no sub-threshold rows).}
#'   \item{`n_multi_obs`}{Integer. Observations with >1 row.}
#'   \item{`purity_ties`}{Numeric. Fraction of multi-row obs with uniform
#'     scores.}
#'   \item{`frac_singleton`}{Numeric. Fraction of obs that are singletons.}
#'   \item{`example_observations`}{Character. Up to 5 affected observation IDs.}
#' }
#'
#' @examples
#' m <- data.frame(
#'   observation_id = c("obs1", "obs1", "obs2"),
#'   score_original = c(100, 100, 99),
#'   taxon_name     = c("Sp_A", "Sp_B", "Sp_C")
#' )
#' detect_suppressed_candidates(m)
#'
#' @seealso [restore_suppressed_candidates()]
#' @importFrom utils head
#' @export
detect_suppressed_candidates <- function(match_obj,
                                          score_col           = "score_original",
                                          observation_id_col  = "observation_id",
                                          perfect_threshold   = 100,
                                          purity_threshold    = 0.99,
                                          singleton_threshold = 0.98) {

  if (!is.data.frame(match_obj))
    stop("detect_suppressed_candidates: 'match_obj' must be a data frame.",
         call. = FALSE)
  if (!observation_id_col %in% names(match_obj))
    stop(sprintf("detect_suppressed_candidates: column '%s' not found.",
                 observation_id_col), call. = FALSE)

  has_score <- score_col %in% names(match_obj)
  obs_ids   <- match_obj[[observation_id_col]]

  per_obs <- tapply(seq_len(nrow(match_obj)), obs_ids, function(idx) {
    n  <- length(idx)
    if (has_score) {
      s  <- match_obj[[score_col]][idx]
      s  <- s[!is.na(s)]
      mx <- if (length(s) > 0L) max(s) else NA_real_
      list(
        n             = n,
        max_score     = mx,
        has_perfect   = !is.na(mx) && mx >= perfect_threshold,
        is_pure_perfect = !is.na(mx) && mx >= perfect_threshold &&
                          (length(s) == 0L || min(s) >= perfect_threshold),
        all_same      = (n > 1L) && length(s) > 1L &&
                        length(unique(round(s, 8))) == 1L
      )
    } else {
      list(n = n, max_score = NA_real_, has_perfect = FALSE,
           is_pure_perfect = FALSE, all_same = FALSE)
    }
  }, simplify = FALSE)

  n_total <- length(per_obs)

  # ---- Rule 1: perfect_only ---------------------------------------------------
  n_perfect_obs  <- sum(vapply(per_obs, function(x) x$has_perfect, logical(1L)))
  n_pure_perfect <- sum(vapply(per_obs, function(x) x$is_pure_perfect, logical(1L)))
  purity_perfect <- if (n_perfect_obs > 0L) n_pure_perfect / n_perfect_obs else 0
  perfect_only   <- has_score && n_perfect_obs > 0L &&
                    purity_perfect >= purity_threshold

  # ---- Rule 2: max_score_ties -------------------------------------------------
  n_multi    <- sum(vapply(per_obs, function(x) x$n > 1L, logical(1L)))
  n_ties     <- sum(vapply(per_obs, function(x) x$all_same, logical(1L)))
  purity_ties <- if (n_multi > 0L) n_ties / n_multi else 0
  max_score_ties <- has_score && n_multi > 0L && purity_ties >= purity_threshold

  # ---- Rule 3: best_only ------------------------------------------------------
  n_singletons   <- sum(vapply(per_obs, function(x) x$n == 1L, logical(1L)))
  frac_singleton <- n_singletons / n_total
  best_only      <- frac_singleton >= singleton_threshold

  # ---- collect examples -------------------------------------------------------
  affected_ids <- character(0L)
  if (perfect_only)
    affected_ids <- c(affected_ids,
                      names(which(vapply(per_obs,
                                         function(x) x$is_pure_perfect, logical(1L)))))
  if (max_score_ties)
    affected_ids <- c(affected_ids,
                      names(which(vapply(per_obs,
                                         function(x) x$all_same, logical(1L)))))
  if (best_only)
    affected_ids <- c(affected_ids, names(per_obs))
  affected_ids <- unique(affected_ids)

  rules <- character(0L)
  if (perfect_only)    rules <- c(rules, "perfect_only")
  if (max_score_ties)  rules <- c(rules, "max_score_ties")
  if (best_only)       rules <- c(rules, "best_only")

  list(
    rule_detected   = length(rules) > 0L,
    rules           = rules,
    perfect_only    = perfect_only,
    max_score_ties  = max_score_ties,
    best_only       = best_only,
    has_score_col   = has_score,
    n_total         = n_total,
    n_perfect_obs   = n_perfect_obs,
    purity_perfect  = round(purity_perfect,  4),
    n_multi_obs     = n_multi,
    purity_ties     = round(purity_ties, 4),
    frac_singleton  = round(frac_singleton, 4),
    example_observations = head(affected_ids, 5L)
  )
}


#' Restore candidates suppressed by upstream pipeline rules
#'
#' Reframed design (see
#' \code{ecosystem_docs/SPEC_restore_suppressed_candidates_redesign.md}): the
#' function's job is not "restore candidates so more of them can individually
#' win" but to detect whether the anchor's apparent win is real or an
#' artifact of upstream suppression, so that downstream consensus logic can
#' back off from a false-precision specific-species call when it isn't. Every
#' same-genus congener in \code{reference_df} not already present for an
#' observation is checked, for \emph{every} observation, regardless of
#' whether [detect_suppressed_candidates()] finds a global pipeline pattern
#' -- unlike the pre-redesign version, admission no longer depends on a
#' globally detected rule.  A congener is admitted as an ordinary
#' \code{hypothesis_type = "suppressed_candidate"} row (so it flows through
#' [evaluate_likelihoods()] -> prior join -> \code{compute_posterior()}
#' exactly like anything else) under either or both of two purposes, recorded
#' in the new \code{restoration_basis} column:
#'
#' \itemize{
#'   \item \strong{\code{"competitive_score"}} (Purpose A -- competitiveness
#'     detection): the candidate's hierarchy-resolved score
#'     (\code{@section Score-sourcing hierarchy}) is statistically
#'     indistinguishable from the anchor's own observed score, via the same
#'     score-only chi-squared outlier test [evaluate_likelihoods()] already
#'     uses (\code{alpha}, default \code{0.001}). Prior-agnostic --
#'     \code{candidate_species_filter} never gates this purpose. Requires
#'     \code{model_params} (for the per-species/global sigma the test needs);
#'     without it, no candidate is ever admitted under this purpose.
#'   \item \strong{\code{"plausible_prior"}} (Purpose B -- plausible
#'     candidate admission): the candidate is on \code{candidate_species_filter}
#'     (or no filter was supplied at all) and its hierarchy-resolved score
#'     clears \code{build_sequence_matrix()}'s own \code{max_dist} sanity
#'     floor (default \code{0.25}, ~75\% identity) -- a much wider bar than
#'     Purpose A's, since local occurrence plausibility substitutes for some
#'     of the score-closeness Purpose A needs on its own.
#'   \item \strong{\code{"both"}} when a candidate clears both gates (the wide
#'     gap is a superset of the tight one, so this never duplicates work --
#'     the hierarchy score is resolved once and compared against both
#'     thresholds).
#' }
#'
#' A candidate resolved via neither purpose (or with no evidence at all --
#' see \code{@section Score-sourcing hierarchy}'s Level 0) is not restored as
#' a hypothesis row, but --  when \code{check_regional_overlap = TRUE} -- may
#' still be recorded via \code{attr(result, "regional_unreferenced")} (see
#' \code{@return}) so it can compete through
#' [expand_unreferenced_hypotheses()]'s generic borrowed-likelihood path
#' instead.
#'
#' \strong{No-score pathway (Rule 3 / \code{best_only}, unchanged):} when
#' \code{match_obj} carries no usable \code{score_col} at all, there is no
#' real evidence to source Purpose A/B from -- every same-genus congener
#' (filtered by \code{candidate_species_filter} if supplied) is restored with
#' a synthetic score exactly as before this redesign: original rows get
#' \code{1.0}, restored rows get \code{1.0 - delta / 100}. Pass the result to
#' \code{assign_scores(score_type = "direct")} rather than the bivariate-
#' normal pipeline. \code{restoration_basis} is \code{NA} for rows added this
#' way (no purpose distinction applies without real score evidence).
#'
#' @param match_obj Data frame. Standardised match object.
#' @param reference_df Data frame. Reference database (output of
#'   [fetch_ncbi_reference_sequences()], [read_reference_fasta()], or
#'   [read_crabs_output()]).  Must contain the same genus/species columns as
#'   \code{match_obj}.
#' @param rank_system Character vector or \code{NULL}. Rank columns
#'   coarse-to-fine (e.g. \code{c("family","genus","species")}).
#'   Auto-detected when \code{NULL}.
#' @param score_col Character. Score column name (default
#'   \code{"score_original"}).
#' @param observation_id_col Character. Observation ID column name (default
#'   \code{"observation_id"}).
#' @param delta Numeric. Only used by the no-score pathway (see
#'   \code{@details}) -- score gap between H1's synthetic \code{1.0} and a
#'   restored row's synthetic score (default \code{0.5}, on the 0-100 scale;
#'   used as \code{delta / 100} against the \code{1.0} baseline). Has no
#'   effect when \code{match_obj} carries real scores -- restored rows there
#'   get a real, hierarchy-resolved score instead (\code{@section
#'   Score-sourcing hierarchy}).
#' @param max_per_obs Integer. Maximum restored candidates per observation
#'   (default \code{10L}), applied to the final admitted set (after Purpose
#'   A/B gating), not to the raw congener list.
#' @param model_params A \code{taxa_model_params} object (output of
#'   [train_likelihood_model()]) or \code{NULL} (default). Used two ways:
#'   (1) Purpose A's outlier test needs the anchor species' own sigma
#'   (\code{H1_Lookup}, floored at \code{H1_Sigma[1,1]}, matching
#'   [evaluate_likelihoods()]'s own convention) -- Purpose A never admits
#'   any candidate when this is \code{NULL}; (2) Level 3 of the score-sourcing
#'   hierarchy prefers \code{H2_Lookup$delta_shrunk} (the model's own
#'   genus-specific congener-divergence estimate) over a raw seq_matrix
#'   median when available, keeping a restored row's imputed score
#'   consistent with the same estimate [evaluate_likelihoods()] already uses
#'   for that genus's H2 rows.
#' @param alpha Numeric (default \code{0.001}). Purpose A's outlier-test
#'   p-value cutoff -- identical parameter and identical test to
#'   [evaluate_likelihoods()]'s own \code{alpha}, reused rather than
#'   inventing a second calibrated constant for the same question.
#' @param max_dist Numeric (default \code{0.25}). Purpose B's admission
#'   floor, on the same distance (\code{1 - p_match}) scale as
#'   [build_sequence_matrix()]'s own \code{max_dist} -- reuse the same value
#'   passed there for consistency.
#' @param check_regional_overlap Logical (default \code{FALSE}). When
#'   \code{TRUE}, enables the score-sourcing hierarchy's Level 4 (live Tier 2
#'   pairwise alignment, \code{@section Score-sourcing hierarchy}) for
#'   candidates that Levels 1-3 can't resolve for free -- without it, such
#'   candidates simply get no score and are never restored. Requires
#'   \code{accession_col} in \code{match_obj} and \code{composite_id}/
#'   \code{sequence} in \code{reference_df} (errors if absent). This also
#'   doubles as Purpose A's regional-overlap guarantee for real, without a
#'   second position check: any candidate resolved via Levels 1-3 is
#'   position-safe by construction (\code{seq_matrix} only ever contains
#'   properly-sized, in-window sequences), so the regional-overlap concern
#'   only ever bites exactly where Level 4 already lives.
#' @param seq_matrix Data frame or \code{NULL}. Output of
#'   [build_sequence_matrix()] (needs \code{id_x}/\code{id_y}/\code{p_match}/
#'   \code{coverage}), the source for Levels 1-3 of the score-sourcing
#'   hierarchy and Level 4's Tier 1 lookup. Restoration is a no-op for the
#'   scored pathway when this is \code{NULL} and \code{check_regional_overlap
#'   = FALSE} -- there is no free evidence to source a score from and no live
#'   alignment enabled either.
#' @param min_regional_coverage Numeric in (0, 1]. Minimum alignment coverage
#'   required for Level 4's live Tier 2 alignment to accept a congener as
#'   overlapping (default \code{0.5}). Only used when
#'   \code{check_regional_overlap = TRUE}.
#' @param accession_col Character. Column in \code{match_obj} naming each
#'   row's own reference accession (default \code{"accession"}).
#' @param sequence_col Character or \code{NULL} (default \code{NULL}). Column
#'   in \code{match_obj} carrying each observation's own raw query DNA
#'   sequence, enabling Level 4's Tier 2b fallback (see \code{@section
#'   Score-sourcing hierarchy}) for match objects with no live BLAST
#'   alignment coordinates at all. \code{NULL} means only Tier 1/2a run.
#' @param candidate_species_filter Character vector or \code{NULL} (default
#'   \code{NULL}). Two roles, both cost- or plausibility-related, never a
#'   correctness gate on the free hierarchy levels: (1) defines Purpose B's
#'   plausible-candidate set; (2) \strong{is Level 4's own default cost gate}
#'   (\code{@section Level 4 cost control}, revised 2026-07-18) -- a
#'   candidate not on this list only reaches the expensive live-alignment
#'   step if \code{taxaexpect_priors}' ratio test says it's specifically
#'   worth it. Never gates Levels 1-3 -- Purpose A's free-tier genus-wide
#'   sweep sees every congener regardless of this filter (the design spec's
#'   red flag 1 stays closed: a plausibility filter can no longer make an
#'   observation get zero signal, it can only skip the expensive step for an
#'   implausible congener). Intended to hold whatever locally-plausible-
#'   species list a caller would apply downstream anyway (e.g. TaxaExpect
#'   occurrence priors' \code{taxon_name} column). Species names must match
#'   \code{reference_df}'s own \code{species_col} values exactly (full
#'   binomial, e.g. \code{"Fundulus parvipinnis"}). \code{NULL} (default)
#'   means every same-genus congener is both Purpose-B-eligible AND
#'   Level-4-eligible -- no narrowing at all, matching the original
#'   pre-redesign behavior at some real cost (see \code{@section Level 4 cost
#'   control} for two real, measured cases).
#' @param taxaexpect_priors Data frame or \code{NULL} (default \code{NULL}).
#'   Powers the floor-vs-documented ratio fallback in \code{@section Level 4
#'   cost control} for a candidate NOT on \code{candidate_species_filter}.
#'   \code{NULL} (default) means that fallback is unavailable -- a candidate
#'   missing the filter is never worth Level 4 regardless of its real
#'   occurrence support. When supplied, needs \code{taxon_col}/
#'   \code{grid_col}/\code{theta_col} (defaults match TaxaExpect's own
#'   \code{generate_full_priors()} output column names).
#' @param grid_id_col Character. Column in \code{match_obj} naming each
#'   observation's own grid cell (default \code{"grid_id"}), looked up
#'   against \code{taxaexpect_priors}' grid column. Only used when
#'   \code{taxaexpect_priors} is supplied.
#' @param taxon_col,grid_col,theta_col Character. Column names within
#'   \code{taxaexpect_priors} for the species/grid/prior-mean columns
#'   (defaults \code{"taxon_name"}, \code{"grid_id"}, \code{"theta_mean"}).
#' @param budget_ratio_cap Numeric (default \code{19}). Derived, not an
#'   arbitrary tuning knob: from \code{posterior_consensus()}'s
#'   \code{min_posterior} default of \code{0.05} and a same-or-worse-than-
#'   anchor likelihood bound (\code{@section Level 4 cost control}).
#' @param max_level4_per_anchor Numeric (default \code{10L}, use \code{Inf}
#'   to disable). Hard backstop cap on how many distinct candidates get a
#'   live Level 4 alignment attempt per anchor accession, independent of
#'   \code{candidate_species_filter}/\code{taxaexpect_priors} -- insurance
#'   against a large or absent filter (or a permissive ratio) still forcing
#'   an unbounded number of expensive alignments for one anchor. See
#'   \code{@section Level 4 cost control}.
#' @param verbose Logical. Emit summary messages (default \code{TRUE}).
#'
#' @section Score-sourcing hierarchy:
#' Replaces the pre-redesign flat \code{anchor_score - delta} imputation.
#' Cheapest/most-certain first, stopping at the first level that resolves a
#' candidate; aggregated by \strong{median}, never max or a random pick, when
#' more than one qualifying value exists at a level (max is an upward-biased
#' order statistic -- a well-referenced species draws more pairs from the
#' same underlying similarity distribution, inflating its expected max for
#' reasons unrelated to true similarity).
#' \enumerate{
#'   \item \strong{Level 0 precheck:} does the anchor's own species have ANY
#'     \code{seq_matrix} representation at all (as \code{id_x} or
#'     \code{id_y}, against anything, not just this genus)? When it doesn't
#'     (e.g. its only references are out-of-range mitogenomes that never
#'     entered [build_sequence_matrix()]'s alignment), Levels 1-3 are all
#'     provably futile, not just unlucky -- route straight to Level 4.
#'   \item \strong{Level 1 (free):} direct accession-pair \code{p_match}
#'     lookup in \code{seq_matrix} -- the specific anchor accession vs. the
#'     specific candidate accession(s).
#'   \item \strong{Level 2 (free):} any-accession species-pair lookup -- any
#'     reference accession of the anchor's species vs. any reference
#'     accession of the candidate species. Rescues a case where Level 1's
#'     specific accession happens to be an unrepresentative outlier; not a
#'     universal rescue (several real anchors show zero improvement, when the
#'     missing pairs are genuinely outside \code{max_dist} rather than an
#'     accession-pick artifact).
#'   \item \strong{Level 3 (free), one level with an internal preference:} a
#'     raw genus-wide median and the trained model's own genus-specific
#'     estimate both answer "typical congener divergence for this genus," at
#'     different levels of rigor, so they're tried as alternatives rather
#'     than strictly in sequence. \strong{Preferred:}
#'     \code{model_params$H2_Lookup$delta_shrunk} (used when
#'     \code{model_params} has an entry for the anchor's genus) --
#'     Empirical-Bayes-shrunk, matters most for thin-data genera, and keeps a
#'     restored row's imputed score consistent with the same estimate
#'     [evaluate_likelihoods()] already uses for that genus's H2 rows.
#'     \strong{Fallback:} median \code{p_match} across all within-genus,
#'     cross-species pairs already present in \code{seq_matrix}, ignoring
#'     which two specific species are involved. Both require the Level 0
#'     precheck to have passed.
#'   \item \strong{Level 4 (expensive, only when \code{check_regional_overlap
#'     = TRUE}):} live pairwise alignment via the same Tier 1/2a/2b mechanism
#'     \code{.check_regional_overlap()} uses for the regional-overlap check,
#'     called with \code{return_detail = TRUE} to also read back a percent-
#'     identity score (\code{pwalign::pid()}, default \code{PID1}) from the
#'     same alignment object the position check already builds -- free, no
#'     extra alignment work. A candidate whose position genuinely does not
#'     overlap the anchor's hit region is recorded via
#'     \code{attr(result, "regional_unreferenced")} rather than restored (see
#'     \code{@return}); one with literally no evidence either way (e.g. no
#'     usable sequence data, or skipped by the compute-budget mechanism) is
#'     recorded there too, distinguishable via its \code{basis} column
#'     (\code{"regional_reject"} vs. \code{"no_reference_data"}).
#' }
#'
#' @section Level 4 cost control (revised 2026-07-18):
#' Live-testing the original ratio-only compute-budget design against two
#' real motivating cases -- Mugu \code{Fundulus lima}/\code{parvipinnis},
#' PtConception \code{Girella simplicidens}/\code{nigricans} -- found a real
#' hole: BOTH real anchors are themselves occurrence-implausible (absent
#' from \code{taxaexpect_priors} entirely), which is exactly the case this
#' whole function exists to handle, but made the floor-vs-documented ratio
#' uncomputable and the original design skip Level 4 for every candidate --
#' including the one that actually matters. Measured real cost of leaving
#' Level 4 fully unrestricted (the \code{candidate_species_filter = NULL}
#' default): restoring one marker's real 12S Mugu data went from a
#' documented ~38s (pre-redesign, filter-gated) to ~276s, because Purpose
#' A's genus-wide sweep sent every one of \code{Fundulus}'s 20 species to a
#' live alignment against \code{F. lima}'s 16kb mitogenome.
#'
#' Two independent controls now gate Level 4, cheapest-decision first (see
#' \code{.worth_level4_check()}/\code{.level4_attempt_allowed()}'s own
#' headers for the full derivation):
#' \enumerate{
#'   \item \strong{\code{candidate_species_filter} (default gate, restored
#'     from the pre-redesign design specifically for this one expensive
#'     step):} a candidate on the filter -- or any candidate, when no filter
#'     was supplied at all -- is always worth checking. Levels 1-3 remain
#'     completely unaffected by this filter; only Level 4 is gated.
#'   \item \strong{Floor-vs-documented ratio (fallback, only consulted for a
#'     candidate NOT on the filter):} \code{posterior_consensus()}'s
#'     \code{min_posterior} filter (default \code{0.05}) drops any
#'     hypothesis below ~1/19th of total posterior mass, and posterior is
#'     proportional to likelihood times prior, so a candidate's prior
#'     disadvantage alone can make it mathematically impossible to ever
#'     surface. Bounding a restored congener's likelihood at, at best, the
#'     anchor's own (\code{L_candidate/L_anchor <= 1}, a safe working
#'     assumption for a budget heuristic, not a correctness gate) gives:
#'     worth spending Level 4 budget only when \code{R = P_anchor /
#'     P_candidate <= 19}, where \code{P_anchor}/\code{P_candidate} are the
#'     two species' own occurrence-prior means at the observation's grid
#'     cell. \code{R} not being computable at all (either species absent
#'     from \code{taxaexpect_priors} at that grid cell) is treated the same
#'     as \code{R > 19} -- skip.
#' }
#' Verified against both real cases: Fundulus goes from ~19 live alignments
#' per anchor down to 1 (\code{F. parvipinnis}, still correctly rejected on
#' position grounds); Girella goes from 8 wasted alignments down to 0,
#' keeping the 1 that matters (\code{G. nigricans}, still correctly admitted
#' at its real ~98\% score). \code{max_level4_per_anchor} (default
#' \code{10L}) is a separate, independent hard cap on top of both -- insurance
#' against a large/absent filter or a permissive ratio still admitting an
#' unbounded number of candidates for one anchor.
#'
#' @return \code{match_obj} with restored \code{"suppressed_candidate"} rows
#'   appended (or unchanged if nothing qualified), plus new \code{is_restored}
#'   and \code{restoration_basis} columns. When \code{check_regional_overlap
#'   = TRUE}, the result also carries \code{attr(result,
#'   "regional_unreferenced")}: \code{NULL} if nothing was ever rejected/
#'   unresolved, otherwise a data frame with columns \code{observation_id}/
#'   \code{species}/\code{genus}/\code{family}/\code{basis} -- one row per
#'   such species per observation, \code{basis} either \code{"regional_reject"}
#'   (Level 4 ran and found no position overlap) or \code{"no_reference_data"}
#'   (no evidence could be gathered either way -- Level 0 failed and Level 4
#'   also came back empty, or was skipped by the compute-budget mechanism).
#'   Ready to \code{dplyr::bind_rows()} onto an \code{unreferenced_df} before
#'   calling [expand_unreferenced_hypotheses()], whose \code{observation_id}-
#'   scoped rows accept this shape directly (an extra \code{basis} column is
#'   additive and does not disturb that consumer).
#'
#' @examples
#' \dontrun{
#' match_obj <- restore_suppressed_candidates(match_obj, reference_df,
#'                                             seq_matrix = seq_matrix,
#'                                             model_params = model_params)
#' # With scores: continue to evaluate_likelihoods()
#' # No-score:    continue to assign_scores(score_type = "direct")
#' }
#'
#' @seealso [detect_suppressed_candidates()], [evaluate_likelihoods()],
#'   [assign_scores()], [fetch_ncbi_reference_sequences()] for
#'   \code{keep_out_of_range}, [build_sequence_matrix()] for \code{seq_matrix}
#'   and \code{max_dist}, [train_likelihood_model()] for \code{model_params}
#' @importFrom dplyr bind_rows
#' @importFrom TaxaTools create_taxon_names extended_ranks
#' @export
restore_suppressed_candidates <- function(match_obj,
                                           reference_df,
                                           rank_system         = NULL,
                                           score_col           = "score_original",
                                           observation_id_col  = "observation_id",
                                           delta               = 0.5,
                                           max_per_obs         = 10L,
                                           model_params        = NULL,
                                           alpha               = 0.001,
                                           max_dist            = 0.25,
                                           check_regional_overlap = FALSE,
                                           seq_matrix          = NULL,
                                           min_regional_coverage = 0.5,
                                           accession_col       = "accession",
                                           sequence_col        = NULL,
                                           candidate_species_filter = NULL,
                                           taxaexpect_priors   = NULL,
                                           grid_id_col         = "grid_id",
                                           taxon_col           = "taxon_name",
                                           grid_col            = "grid_id",
                                           theta_col           = "theta_mean",
                                           budget_ratio_cap    = 19,
                                           max_level4_per_anchor = 10L,
                                           verbose             = TRUE) {

  # ---- validate ---------------------------------------------------------------
  if (!is.data.frame(match_obj))
    stop("restore_suppressed_candidates: 'match_obj' must be a data frame.",
         call. = FALSE)
  if (!is.data.frame(reference_df))
    stop("restore_suppressed_candidates: 'reference_df' must be a data frame.",
         call. = FALSE)
  if (!observation_id_col %in% names(match_obj))
    stop(sprintf("restore_suppressed_candidates: column '%s' not found.",
                 observation_id_col), call. = FALSE)

  if (!is.logical(check_regional_overlap) || length(check_regional_overlap) != 1L ||
      is.na(check_regional_overlap))
    stop("restore_suppressed_candidates: 'check_regional_overlap' must be TRUE or FALSE.",
         call. = FALSE)
  if (check_regional_overlap) {
    if (!accession_col %in% names(match_obj))
      stop(sprintf(
        "restore_suppressed_candidates: check_regional_overlap = TRUE requires column '%s' in match_obj.",
        accession_col), call. = FALSE)
    if (!"composite_id" %in% names(reference_df) || !"sequence" %in% names(reference_df))
      stop("restore_suppressed_candidates: check_regional_overlap = TRUE requires ",
           "'composite_id' and 'sequence' columns in reference_df.", call. = FALSE)
  }

  max_per_obs <- as.integer(max_per_obs)

  # ---- auto-detect rank_system ------------------------------------------------
  if (is.null(rank_system)) {
    canonical   <- TaxaTools::extended_ranks
    df_lower    <- tolower(names(match_obj))
    found_lower <- intersect(canonical, df_lower)
    rank_system <- names(match_obj)[match(found_lower, df_lower)]
    if (length(rank_system) < 2L)
      stop("restore_suppressed_candidates: could not auto-detect rank_system. ",
           "Supply it explicitly, e.g. rank_system = c(\"family\",\"genus\",\"species\").",
           call. = FALSE)
    message(sprintf("restore_suppressed_candidates: detected rank_system: %s",
                    paste(rank_system, collapse = ", ")))
  }

  genus_col   <- rank_system[length(rank_system) - 1L]
  species_col <- rank_system[length(rank_system)]

  for (col in c(genus_col, species_col)) {
    if (!col %in% names(match_obj))
      stop(sprintf("restore_suppressed_candidates: column '%s' not found in match_obj.", col),
           call. = FALSE)
    if (!col %in% names(reference_df))
      stop(sprintf("restore_suppressed_candidates: column '%s' not found in reference_df.", col),
           call. = FALSE)
  }

  # ---- score column handling --------------------------------------------------
  has_score  <- score_col %in% names(match_obj)
  no_score_path <- FALSE

  if (!has_score || all(is.na(match_obj[[score_col]]))) {
    # No-score pathway (Rule 3, unchanged by this redesign -- there is no
    # real score evidence to source Purpose A/B from at all): create a
    # synthetic score column and restore every same-genus congener
    # (filtered by candidate_species_filter, if supplied) with a flat
    # synthetic gap, exactly as before this redesign.
    no_score_path <- TRUE
    delta_01 <- delta / 100   # e.g. 0.5 -> 0.005
    if (!has_score) match_obj[[score_col]] <- NA_real_
    # Mark original rows with synthetic H1 score = 1.0
    match_obj[[score_col]] <- 1.0
    if (verbose)
      message(sprintf(
        "restore_suppressed_candidates: no score column -creating synthetic scores ",
        "(H1 = 1.0, restored = %.4f). Use assign_scores(score_type = \"direct\") downstream.",
        1.0 - delta_01
      ))
  }

  # Scale-detect: 0-100 vs 0-1 (used to translate hierarchy-resolved p_match
  # values, always 0-1, onto match_obj's own score scale).
  max_score_global <- suppressWarnings(max(match_obj[[score_col]], na.rm = TRUE))
  scale_100 <- is.finite(max_score_global) && max_score_global > 1

  # ---- every observation is checked (Purpose A is prior-agnostic and does --
  # not depend on a globally detected suppression rule -- see @details).
  obs_ids    <- match_obj[[observation_id_col]]
  all_obs    <- unique(obs_ids)
  target_obs <- all_obs

  # ---- mark hypothesis_type for original rows ---------------------------------
  if (!"hypothesis_type" %in% names(match_obj))
    match_obj$hypothesis_type <- "specific_candidate"

  # ---- reference lookup: genus -> unique species rows -------------------------
  ref_by_genus <- split(reference_df, reference_df[[genus_col]])

  # Shared once per call -- both the Level 0/1/2/3 stripped-id lookups
  # (.resolve_hierarchy_score()) and Level 4's (anchor, candidate) alignment
  # memoization (.check_regional_overlap()) key off this same environment.
  # See regional_overlap.R's own header comment for the real Mugu/
  # PtConception performance case this caching fixes.
  align_cache <- new.env(parent = emptyenv())

  score_transform <- (model_params$Score_Transform %||% "logit")

  # ---- build restored rows ----------------------------------------------------
  restored_list   <- vector("list", length(target_obs))
  n_restored_obs  <- 0L
  n_restored_rows <- 0L
  # A candidate that is neither restored as a real hypothesis row nor
  # confirmed to genuinely not-overlap is still recorded here (one row per
  # such species per observation), distinguishable via `basis`:
  # "regional_reject" (Level 4 ran and found no position overlap) or
  # "no_reference_data" (no evidence could be gathered at all -- Level 0
  # failed and Level 4 also came back empty or was budget-skipped). Same
  # shape expand_unreferenced_hypotheses()'s observation_id-scoped
  # unreferenced_df expects (Session 159), with an additive `basis` column.
  regional_unreferenced_list <- list()

  no_score_target_species <- if (no_score_path && !is.null(candidate_species_filter))
    candidate_species_filter else NULL

  for (i in seq_along(target_obs)) {
    obs_id   <- target_obs[i]
    obs_mask <- obs_ids == obs_id
    obs_rows <- match_obj[obs_mask, , drop = FALSE]

    # Genus of anchor (best-scoring or first row)
    sc_vec    <- obs_rows[[score_col]]
    anchor_idx <- if (any(!is.na(sc_vec))) which.max(sc_vec) else 1L
    anchor_row <- obs_rows[anchor_idx, , drop = FALSE]
    h1_genus   <- anchor_row[[genus_col]]
    h1_score   <- anchor_row[[score_col]]
    anchor_species <- anchor_row[[species_col]]

    if (is.na(h1_genus) || !h1_genus %in% names(ref_by_genus)) next

    max_obs_score <- if (!is.na(h1_score)) h1_score else
      suppressWarnings(max(sc_vec, na.rm = TRUE))

    # Species in genus, excluding those already in this observation. Not
    # pre-filtered by candidate_species_filter here -- Purpose A sweeps
    # every genus congener regardless of that filter (Section 2); the filter
    # is applied later, only when testing Purpose B admission.
    ref_genus_rows  <- ref_by_genus[[h1_genus]]
    present_species <- unique(obs_rows[[species_col]])
    other_species   <- unique(ref_genus_rows[[species_col]])
    other_species   <- other_species[!is.na(other_species) &
                                       !other_species %in% present_species]

    if (no_score_path) {
      # No real evidence exists to source Purpose A/B from -- restore every
      # (optionally filtered) congener with the flat synthetic gap, exactly
      # as this pathway behaved before this redesign.
      if (!is.null(no_score_target_species))
        other_species <- other_species[other_species %in% no_score_target_species]
      if (length(other_species) == 0L) next
      if (length(other_species) > max_per_obs)
        other_species <- other_species[seq_len(max_per_obs)]

      rows_for_obs <- vector("list", length(other_species))
      for (j in seq_along(other_species)) {
        rows_for_obs[[j]] <- .build_restored_row(
          anchor_row, ref_genus_rows, other_species[j], rank_system, species_col,
          score_col = score_col, imputed_score = 1.0 - delta_01,
          restoration_basis = NA_character_
        )
      }
      restored_list[[i]] <- dplyr::bind_rows(rows_for_obs)
      n_restored_obs  <- n_restored_obs  + 1L
      n_restored_rows <- n_restored_rows + length(other_species)
      next
    }

    if (length(other_species) == 0L) next

    # ---- Purpose A's sigma: anchor species' own H1 sigma (floored at the
    # global sigma, matching evaluate_likelihoods()'s own convention), or
    # global sigma alone; unavailable (Purpose A never admits anything) when
    # model_params itself wasn't supplied.
    anchor_transform <- NA_real_
    sigma_to_use     <- NA_real_
    if (!is.null(model_params) && !is.null(model_params$H1_Sigma)) {
      global_sigma_11 <- model_params$H1_Sigma[1L, 1L]
      sigma_to_use <- global_sigma_11
      if (!is.null(model_params$H1_Lookup) && nrow(model_params$H1_Lookup) > 0L) {
        aidx <- match(anchor_species, model_params$H1_Lookup$lookup_key)
        if (!is.na(aidx)) {
          sp_var <- model_params$H1_Lookup$sigma_score[aidx]
          if (!is.na(sp_var) && sp_var > 0)
            sigma_to_use <- max(sp_var, global_sigma_11)
        }
      }
      anchor_score_p   <- if (scale_100) max_obs_score / 100 else max_obs_score
      anchor_transform <- .transform_p(anchor_score_p, score_transform)
    }

    # anchor_accession/anchor_subject_range/query_sequence: needed only by
    # Level 4 (check_regional_overlap = TRUE), computed once per observation
    # (not per candidate -- these depend only on the anchor/query, not on
    # which congener is being checked).
    anchor_accession <- if (accession_col %in% names(anchor_row))
      anchor_row[[accession_col]] else NA_character_
    anchor_subject_range <- NULL
    query_sequence       <- NULL
    if (check_regional_overlap) {
      anchor_subject_range <- if (all(c("subject_start", "subject_end") %in% names(anchor_row))) {
        rng <- c(anchor_row[["subject_start"]], anchor_row[["subject_end"]])
        if (anyNA(rng)) NULL else rng
      } else {
        NULL
      }
      query_sequence <- if (!is.null(sequence_col) && sequence_col %in% names(anchor_row)) {
        anchor_row[[sequence_col]]
      } else {
        NULL
      }
    }

    grid_id <- if (grid_id_col %in% names(anchor_row)) anchor_row[[grid_id_col]] else NA

    rows_for_obs <- list()
    for (sp in other_species) {

      res <- .resolve_hierarchy_score(
        anchor_accession = anchor_accession, anchor_species = anchor_species,
        candidate_species = sp, genus = h1_genus, ref_genus_rows = ref_genus_rows,
        species_col = species_col, seq_matrix = seq_matrix, model_params = model_params,
        score_transform = score_transform, align_cache = align_cache
      )

      basis_note <- NULL  # set only when this candidate ends up unresolved/rejected

      if (is.na(res$level)) {
        # Levels 1-3 didn't resolve this candidate (or Level 0 precheck
        # failed outright) -- try Level 4 when enabled, gated by (a)
        # candidate_species_filter/the compute-budget ratio (Option A,
        # 2026-07-18) and (b) a hard per-anchor attempt cap (Option C,
        # backstop) -- see .worth_level4_check()/.level4_attempt_allowed()'s
        # own headers for the real-data cost story behind both.
        if (check_regional_overlap &&
            .worth_level4_check(anchor_species, sp, grid_id, taxaexpect_priors,
                                 candidate_species_filter = candidate_species_filter,
                                 taxon_col = taxon_col, grid_col = grid_col,
                                 theta_col = theta_col, budget_ratio_cap = budget_ratio_cap) &&
            .level4_attempt_allowed(anchor_accession, max_level4_per_anchor, align_cache)) {
          cand_acc <- ref_genus_rows$composite_id[ref_genus_rows[[species_col]] == sp]
          detail <- .check_regional_overlap(
            anchor_accession      = anchor_accession,
            candidate_accessions  = cand_acc,
            reference_df          = reference_df,
            seq_matrix            = seq_matrix,
            anchor_subject_range  = anchor_subject_range,
            query_sequence        = query_sequence,
            min_coverage          = min_regional_coverage,
            align_cache           = align_cache,
            return_detail         = TRUE
          )
          if (isTRUE(detail$overlap) && !is.na(detail$pid)) {
            res <- list(p_match = detail$pid / 100, level = 4L, source = "tier2_alignment")
          } else if (isFALSE(detail$overlap)) {
            basis_note <- "regional_reject"
          } else {
            basis_note <- "no_reference_data"
          }
        } else if (check_regional_overlap) {
          basis_note <- "no_reference_data"  # budget-skipped
        }
      }

      if (is.na(res$level)) {
        if (!is.null(basis_note)) {
          has_family_col <- "family" %in% names(ref_genus_rows)
          fam_val <- if (has_family_col) {
            fv <- ref_genus_rows$family[ref_genus_rows[[species_col]] == sp]
            if (length(fv) == 0L || is.na(fv[1L])) NA_character_ else as.character(fv[1L])
          } else {
            NA_character_
          }
          regional_unreferenced_list[[length(regional_unreferenced_list) + 1L]] <- data.frame(
            observation_id = obs_id, species = sp, genus = h1_genus, family = fam_val,
            basis = basis_note, stringsAsFactors = FALSE
          )
        }
        next
      }

      # ---- Purpose A: tight, score-only outlier test (same mechanism as
      # evaluate_likelihoods()'s own H1 outlier filter) -- statistically
      # indistinguishable from the anchor's own observed score. Never gated
      # by candidate_species_filter.
      purpose_a_pass <- FALSE
      if (!is.na(anchor_transform) && !is.na(sigma_to_use) && sigma_to_use > 0) {
        cand_transform <- .transform_p(res$p_match, score_transform)
        d_sq  <- (cand_transform - anchor_transform)^2 / sigma_to_use
        p_val <- stats::pchisq(d_sq, df = 1L, lower.tail = FALSE)
        purpose_a_pass <- !is.na(p_val) && p_val >= alpha
      }

      # ---- Purpose B: wide, plausibility-gated max_dist sanity floor.
      in_filter <- is.null(candidate_species_filter) || sp %in% candidate_species_filter
      clears_dist <- !is.na(res$p_match) && res$p_match >= (1 - max_dist)
      purpose_b_pass <- in_filter && clears_dist

      if (!purpose_a_pass && !purpose_b_pass) next

      basis <- if (purpose_a_pass && purpose_b_pass) "both" else
        if (purpose_a_pass) "competitive_score" else "plausible_prior"

      imputed_score <- if (scale_100) res$p_match * 100 else res$p_match

      rows_for_obs[[length(rows_for_obs) + 1L]] <- .build_restored_row(
        anchor_row, ref_genus_rows, sp, rank_system, species_col,
        score_col = score_col, imputed_score = imputed_score, restoration_basis = basis
      )
    }

    if (length(rows_for_obs) == 0L) next
    if (length(rows_for_obs) > max_per_obs)
      rows_for_obs <- rows_for_obs[seq_len(max_per_obs)]

    restored_list[[i]] <- dplyr::bind_rows(rows_for_obs)
    n_restored_obs  <- n_restored_obs  + 1L
    n_restored_rows <- n_restored_rows + length(rows_for_obs)
  }

  restored_df <- dplyr::bind_rows(restored_list)

  regional_unreferenced_df <- if (length(regional_unreferenced_list) > 0L)
    dplyr::bind_rows(regional_unreferenced_list) else NULL
  if (!is.null(regional_unreferenced_df) && verbose)
    message(sprintf(
      paste0("restore_suppressed_candidates: %d congener(s) recorded in ",
             "attr(result, \"regional_unreferenced\") across %d observation(s) -- ",
             "pass to expand_unreferenced_hypotheses() to let them compete as named ",
             "unreferenced_species hypotheses."),
      nrow(regional_unreferenced_df), length(unique(regional_unreferenced_df$observation_id))
    ))

  if (is.null(restored_df) || nrow(restored_df) == 0L) {
    if (verbose)
      message("restore_suppressed_candidates: no candidate cleared Purpose A or ",
              "Purpose B admission for any observation.")
    match_obj$is_restored <- FALSE
    match_obj$restoration_basis <- NA_character_
    attr(match_obj, "regional_unreferenced") <- regional_unreferenced_df
    return(match_obj)
  }

  match_obj$is_restored   <- FALSE
  if (!"restoration_basis" %in% names(match_obj))
    match_obj$restoration_basis <- NA_character_
  restored_df$is_restored <- TRUE

  result <- dplyr::bind_rows(match_obj, restored_df)

  if (verbose)
    message(sprintf(
      "restore_suppressed_candidates: added %d candidate rows across %d observations.",
      n_restored_rows, n_restored_obs
    ))

  attr(result, "regional_unreferenced") <- regional_unreferenced_df
  result
}

#' Build one restored candidate row (shared by the scored and no-score paths)
#' @noRd
.build_restored_row <- function(anchor_row, ref_genus_rows, sp, rank_system, species_col,
                                 score_col, imputed_score, restoration_basis) {
  ref_row <- ref_genus_rows[ref_genus_rows[[species_col]] == sp, , drop = FALSE][1L, ]
  new_row <- anchor_row

  for (rc in rank_system) {
    if (rc %in% names(ref_row) && rc %in% names(new_row))
      new_row[[rc]] <- ref_row[[rc]]
  }

  if ("taxon_name" %in% names(new_row)) {
    tax_present <- intersect(rank_system, names(new_row))
    new_row <- TaxaTools::create_taxon_names(new_row, tax_present)
  }

  new_row[[score_col]] <- imputed_score
  new_row[["hypothesis_type"]] <- "suppressed_candidate"
  new_row[["restoration_basis"]] <- restoration_basis

  if ("accession" %in% names(new_row)) {
    ref_acc <- if ("accession" %in% names(ref_row))
      ref_row[["accession"]] else NA_character_
    new_row[["accession"]] <- paste0("RESTORED_", ref_acc)
  }

  if ("coverage" %in% names(new_row)) new_row[["coverage"]] <- NA_real_

  new_row
}
