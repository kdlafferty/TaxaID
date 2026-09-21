utils::globalVariables(c("score_val"))

# score_consensus.R
# TaxaAssign package
#
# Conventional score-based consensus taxonomy.  Works directly from raw match
# scores (percent identity, similarity, etc.) without Bayesian machinery.
#
# Purpose: this
# exists to REPRODUCE the consensus logic of conventional non-Bayesian
# pipelines, so a user can compare TaxaID's own Bayesian pathway (TaxaLikely
# -> compute_posterior() -> posterior_consensus()) against what a conventional
# pipeline would have called on the same data.  It is a mimicry/benchmarking
# tool, not TaxaID's own species-level discriminator -- see the roxygen
# "Purpose" note below.
#
# TWO conventions are reproduced, selected by `consensus_mode`:
#   "gap"     (default) -- the common fixed-threshold / LCA convention: a
#              fixed min_score floor, an optional max_gap window, then a
#              strict-unanimity LCA over the retained taxa.
#   "bracket"           -- the adaptive-bracket-with-agreement-fraction
#              convention used by Jonah Ventures: a 1%-wide bracket anchored
#              at the ESV's top score, then any taxon holding >= 90% of the
#              hits in that bracket is reported at its rank (NA otherwise),
#              with an optional widen-the-bracket fallback.
#
# Jonah Ventures' documented rule is the bracket/agreement-fraction rule
# implemented as consensus_mode = "bracket"; the gap-mode rule reproduces the
# generic fixed-threshold/LCA convention, not theirs specifically.  The
# distinction matters for published comparisons: strict unanimity upranks
# more readily than a 90% agreement rule, so a TaxaID-vs-score_consensus()
# comparison run in gap mode is biased toward TaxaID on resolution.
#
# Exported functions:
#   score_consensus()        Score-based consensus from a match dataframe
#
# Internal helpers:
#   .score_consensus_one()          Per-observation consensus
#   .find_consensus_by_agreement()  Rank walk under an agreement fraction
#   .rank_agreement_fraction()      Fraction of rows carrying a taxon at a rank
#   .rank_is_coarser_than()         Rank-order comparison for the fallback rule
#   .cap_rank_by_threshold()        Apply rank-specific score thresholds
#   .uprank_to_whitelist()          Uprank consensus to nearest whitelisted rank


# ==============================================================================
# Main exported function
# ==============================================================================

#' Derive Consensus Taxonomy from Raw Match Scores
#'
#' For each `observation_id`, applies conventional score-based filtering to derive a
#' consensus taxonomic assignment.  Two conventional decision rules are
#' available, selected by `consensus_mode`.
#'
#' **`consensus_mode = "gap"` (default) -- fixed-threshold / LCA convention:**
#'
#' 1. **Score filter:** discard hits below `min_score`.
#' 2. **Gap filter:** among remaining hits, keep only those within `max_gap` of
#'    the top score (per sample).
#' 3. **LCA:** compute the lowest common ancestor (LCA) of the retained taxa.
#' 4. **Rank threshold cap:** if `rank_thresholds` is supplied, cap the
#'    consensus at the finest rank whose minimum score the top hit meets.
#' 5. **Whitelist upranking:** if `whitelist` is supplied, verify the consensus
#'    taxon appears in the whitelist.  If not, uprank to the coarsest rank
#'    where at least one whitelist member agrees with the retained candidates.
#'
#' **`consensus_mode = "bracket"` -- adaptive-bracket / agreement-fraction
#' convention (the rule Jonah Ventures documents):**
#'
#' 1. **Score filter:** discard hits below `min_score` (as above).
#' 2. **Bracket:** retain hits scoring in `(top - bracket_width, top]`, where
#'    `top` is this observation's highest surviving score.
#' 3. **Agreement:** walking finest rank to coarsest, report the taxon holding
#'    at least `agreement_fraction` of the *retained hits* at that rank;
#'    report `NA` at that rank otherwise.  The consensus is the finest rank
#'    with a non-`NA` label.
#' 4. **Fallback:** if `bracket_fallback` is supplied and its condition is met,
#'    repeat steps 2-3 with the wider bracket it names.
#' 5. **Rank threshold cap** and **whitelist upranking** then apply exactly as
#'    in `"gap"` mode.
#'
#' This function does not require a trained likelihood model or priors.  It is
#' the conventional approach used in most metabarcoding and BLAST-based
#' pipelines.
#'
#' @section Purpose -- why this function exists alongside the Bayesian pathway:
#' `score_consensus()` is deliberately a **reproduction of a conventional,
#' non-Bayesian pipeline's decision rule**, not TaxaID's own species-level
#' discriminator. Its purpose is to let a user run the exact same match data
#' through both approaches and compare: what would a conventional workflow
#' have called here, versus what does TaxaID's Bayesian pathway
#' (`TaxaLikely`'s bivariate-normal likelihoods -> [compute_posterior()] ->
#' [posterior_consensus()]) call? This is the intended, load-bearing use case
#' -- mirroring another pipeline's process so its output can be directly
#' compared against TaxaID's.
#'
#' **Which convention is reproduced.** `"gap"` mode
#' reproduces the **common fixed-threshold / LCA convention**: a fixed
#' percent-identity floor, an optional gap window, per-rank thresholds, and a
#' strict-unanimity LCA. `"bracket"` mode reproduces the
#' **adaptive-bracket-with-agreement-fraction convention used by Jonah
#' Ventures**: a 1%-wide bracket anchored at the ESV's top score, a taxon
#' reported at a rank only when it holds at least 90% of the hits in that
#' bracket, `NA` at that rank otherwise, and a widen-to-2% fallback when a
#' match of 97% or better still returns no family. `"gap"` mode is NOT "the
#' GITA / Jonah Ventures convention" -- `"bracket"` mode is. The
#' difference is not cosmetic for a published comparison: **strict unanimity
#' (`agreement_fraction = 1`) upranks more readily than a 90% rule**, so a
#' TaxaID-vs-`score_consensus()` comparison run in gap mode is biased toward
#' TaxaID on resolution.
#'
#' **Prefer a provider's delivered taxonomy when you have it.** When a
#' commercial provider ships its own consensus taxonomy alongside the read
#' data (Jonah Ventures' `*-read-data.csv` carries `Kingdom`...`Species` per
#' ESV; the companion `*-esv-data.csv` carries the bracketed hit table it was
#' derived from), **comparing against that delivered taxonomy is more
#' defensible than reconstructing their rule**: the reconstruction cannot see
#' their reference library, their taxonomic backbone, or their own
#' undocumented tie-breaking, so any disagreement confounds the algorithm with
#' the database. `"bracket"` mode is for the case where a delivered
#' taxonomy is *not* shipped -- or for showing what the published rule alone
#' would have produced.
#'
#' Because of this, `rank_thresholds`' known inability to reliably separate a
#' true species from its closest congener (percent-identity alone cannot do
#' this at almost any real-world threshold -- see Details) is **not a defect
#' to fix in this function**: it is a faithful reproduction of the same
#' limitation those conventional pipelines actually have. "Fixing" it (e.g. by
#' gating on reference completeness, or routing through the bivariate-normal
#' model) would defeat the comparison this function exists to provide. If you
#' need real species-vs-congener discrimination for an actual assignment,
#' use [posterior_consensus()], not this function.
#'
#' @param match_df Data frame.
#'   One row per `observation_id` x reference hit.  Required columns: `observation_id`,
#'   `taxon_name`, `taxon_name_rank`, and the column named by `score_col`.
#'   Taxonomy columns (e.g. `family`, `genus`, `species`) are used for LCA
#'   resolution when present; genus is always derivable from species binomials.
#' @param min_score Numeric.  Minimum score to retain a hit.  Hits below this
#'   value are discarded before any other filtering.  Scale must match the
#'   `score_col` values (e.g. 97 for percent identity, 0.97 for proportion).
#'   Default `0` (no filtering). Note: an ROC-style sweep against real 12S
#'   reference data (see the `score_floor_roc_sweep.R` diagnostic, TaxaID_dev
#'   repository) found
#'   that `min_score`/raw percent-identity alone cannot discriminate a true
#'   species from its closest congener at almost any real-world threshold
#'   (true-positive and congeneric-false-positive rates track each other
#'   almost exactly up to ~97). `min_score`'s real value is excluding
#'   obviously-wrong cross-family hits, not fine species-level discrimination
#'   -- that discrimination is `rank_thresholds`' job (see below).
#' @param max_gap Numeric.  Maximum score difference from the top hit (per
#'   sample).  All hits within `max_gap` of the best score contribute to the
#'   LCA.  For example, `max_gap = 1` keeps all hits within 1 unit of the top
#'   score.  Default `Inf` (all hits above `min_score` contribute).
#' @param rank_thresholds Named numeric vector, or `NULL`.  Maps rank names to
#'   minimum scores, e.g. `c(species = 97, genus = 95, family = 90)`.  After
#'   the LCA is computed, the consensus is capped at the finest rank whose
#'   threshold the top score meets.  If the top score fails all thresholds, the
#'   sample is unresolvable.  Applied independently of the LCA — so even if all
#'   hits agree on species, the consensus is demoted to genus if the top score
#'   is below the species threshold.
#'   **No default -- errors if omitted.** This function has no
#'   way to know the marker or even whether `score_col` holds a DNA/image/
#'   acoustic score, so no single fixed threshold set (e.g. the GITA/Jonah
#'   Ventures convention, `c(species = 98, genus = 95, family = 90,
#'   phylum = 85)`) is safe to assume for
#'   every caller (see Details for the full reasoning). Supply one of:
#'   (1) your own thresholds, on whichever scale `score_col` uses (percent
#'   identity or 0-1 proportion -- see the auto-rescale note below), or
#'   (2) marker-specific thresholds derived from your own reference data via
#'   `TaxaLikely::compute_rank_thresholds()` (per-rank Youden's J on a
#'   `build_sequence_matrix()`-style pairwise distance matrix). Pass
#'   `rank_thresholds = NULL` explicitly to disable rank capping entirely.
#'   If `score_col`'s values look like a 0-1 proportion scale (max <= 1)
#'   rather than 0-100 percent-identity, a supplied 0-100-scale
#'   `rank_thresholds` is automatically rescaled by /100 (with an
#'   informational message) -- pass your own already-scaled
#'   `rank_thresholds` to silence this.
#' @param whitelist Character vector or `NULL`.  Plausible taxon names (any
#'   rank).  When supplied, the consensus taxon must appear in this list;
#'   otherwise the consensus is upranked to the coarsest rank where a
#'   whitelist member agrees with the retained candidates.  Default `NULL`
#'   (no whitelist filtering).
#' @param score_col Character.  Column name containing match scores.
#'   Default `"score_original"`.
#' @param rank_system Character vector of taxonomy column names, coarse to
#'   fine (e.g. `c("family", "genus", "species")`).  If `NULL` (default),
#'   standard columns present in `match_df` are detected automatically.
#' @param consensus_mode Character, one of `"gap"` (default) or `"bracket"`.
#'   `"gap"` is: `min_score` floor ->
#'   `max_gap` window -> LCA over the *distinct retained taxa*.  `"bracket"`
#'   selects the Jonah Ventures rule: `min_score` floor -> a `bracket_width`
#'   window anchored at the top score -> agreement rule over the *retained
#'   hits* (not distinct taxa -- JV's rule counts hits).  `max_gap` is ignored
#'   in `"bracket"` mode; `bracket_width`/`bracket_fallback` are ignored in
#'   `"gap"` mode.
#' @param agreement_fraction Numeric in `(0, 1]`.  A taxon is reported at a
#'   rank when it appears in at least this fraction of the retained rows.
#'   `1` (default) is strict unanimity, i.e. a classical LCA.  Jonah Ventures
#'   uses `0.9`.  Applies in **both** modes: in `"gap"` mode it generalises
#'   the LCA step, and `agreement_fraction = 1` there reduces to a classical
#'   strict-unanimity LCA.  The comparison is inclusive at the boundary
#'   (9 of 10 rows resolves at `agreement_fraction = 0.9`), and is made with
#'   a small floating-point tolerance so that e.g. `27/30 >= 0.9` cannot fail
#'   on binary representation.  If two or more taxa clear the bar at the same
#'   rank (possible only when `agreement_fraction <= 0.5`), `NA` is reported
#'   at that rank rather than an arbitrary winner -- JV: "If several taxa
#'   within a taxonomic level match the ESV, an NA is reported for that
#'   taxonomic level."
#'
#'   **Rows whose label at a rank is missing count toward the denominator,
#'   not toward any taxon.** A hit with no family assigned is evidence
#'   *against* a family-level consensus, not a row to be quietly dropped;
#'   dropping it would inflate agreement, and JV's own delivered output
#'   contains `NA` ranks.
#' @param bracket_width Numeric, positive.  Width of the score bracket in
#'   `score_col`'s own units.  Jonah Ventures uses `1` (one percent-identity
#'   point), which is the default.  Hits scoring in
#'   `(top - bracket_width, top]` are retained.  Only used when
#'   `consensus_mode = "bracket"`.
#'
#'   **The lower bound is exclusive, and Jonah Ventures' own is not** (confirmed
#'   while validating against their delivered Pt Conception MiFish
#'   taxonomy; see the `jv_bracket_consensus_validation.R` diagnostic,
#'   TaxaID_dev repository).  Their
#'   delivered detailed-hit tables do contain hits at exactly `top - 1`, and
#'   those hits demonstrably contributed to their published consensus, so
#'   their real interval is the closed `[top - 1, top]`.  The exclusive bound
#'   implemented here is the documented published description read literally.
#'   It matters for 1 ESV in 14,719 across both Pt Conception MiFish runs, so
#'   it is left as specified rather than quietly widened; pass
#'   `bracket_width = 1 + 1e-6` for the closed-interval behaviour.
#' @param bracket_fallback `NULL` (default, no fallback) or a named list with
#'   elements `min_score`, `rank` and `width` describing a widen-the-bracket
#'   rule.  Jonah Ventures' published rule is
#'   `list(min_score = 97, rank = "family", width = 2)`: *if* the top score is
#'   at least `min_score` **and** the bracket produced no taxonomy at
#'   `rank` or finer (i.e. no family-level name would be printed), the
#'   observation is recomputed with a bracket of width `width`.  Only used
#'   when `consensus_mode = "bracket"`.
#'
#'   Widening is **not** monotone in resolution: adding hits usually dilutes
#'   agreement, but it can also break a tie in favour of one label (e.g. a
#'   1:1 split at 1% becoming 1:19 at 2%), which is the case in which the
#'   fallback actually rescues a family-level call.  The widened result
#'   replaces the narrow one whenever the fallback fires, whether or not it
#'   resolved -- `bracket_width_used` records which bracket produced the row.
#'
#' @details
#' \strong{Why `rank_thresholds` has no default:}
#' `min_score` and `max_gap` alone provide essentially no protection against
#' confusing a species with its closest congener -- an ROC-style sweep against
#' real 12S reference data found true-positive (within-species) and
#' false-positive (congeneric) rates track almost identically up to a ~97
#' percent-identity threshold (see the `score_floor_roc_sweep.R` diagnostic,
#' TaxaID_dev repository).
#' This is a real limitation of percent-identity thresholds generally --
#' `rank_thresholds` is what does the real species-level discrimination this
#' function offers, so a caller getting NO thresholds at all would have no
#' real protection against that confusion.
#'
#' No single fixed threshold set (e.g. the conventional GITA/Jonah Ventures
#' percent-identity convention) is safe to assume universally: this
#' function has no way to know what marker `score_col` was scored against,
#' or even whether the data is DNA, image, or acoustic evidence at all --
#' the real, calibrated threshold for "98% identity means species-level
#' confidence" is a property of the SPECIFIC marker and reference database,
#' not a universal constant (mirrors `TaxaAssign::join_priors()`'s
#' `backbone_id` precedent: no safe default exists when the correct value
#' depends on data the function itself cannot see). The function therefore
#' requires the caller to make this choice explicitly -- either supplying
#' real thresholds directly, or deriving marker-specific ones from real
#' reference data via `TaxaLikely::compute_rank_thresholds()` (which uses
#' the identical genus-/family-equal-weighted, Empirical-Bayes-shrunk
#' per-rank Youden's J logic the `score_floor_roc_sweep.R` diagnostic
#' prototyped). Pass `rank_thresholds = NULL` explicitly only if the specific
#' pipeline you're mirroring genuinely has no rank-threshold step (rare).
#'
#' @return A data frame with one row per `observation_id`:
#'   \describe{
#'     \item{`observation_id`}{Sample identifier.}
#'     \item{`consensus_taxon`}{LCA taxon name, or `NA` if unresolvable.}
#'     \item{`consensus_rank`}{Rank of the LCA (e.g. `"genus"`), or `NA`.}
#'     \item{`consensus_reason`}{How the consensus was reached:
#'       `"unanimous"` (all retained taxa agree at the finest rank),
#'       `"single"` (only one taxon retained after filtering),
#'       `"lca"` (upranked because retained taxa disagree at finer ranks),
#'       `"bracket"` (`"bracket"` mode: resolved by the agreement rule inside
#'       the initial bracket), `"bracket_widened"` (`"bracket"` mode:
#'       resolved only after `bracket_fallback` widened the bracket),
#'       `"threshold"` (rank-capped by `rank_thresholds`), or `NA`
#'       (unresolvable).  `"threshold"` takes precedence over the bracket
#'       reasons when a rank cap also fired, exactly as it does over
#'       `"unanimous"`/`"lca"`; read `bracket_width_used` to see whether the
#'       fallback ran on such a row.}
#'     \item{`is_resolved`}{`TRUE` when the consensus is at the finest rank in
#'       `rank_system`.}
#'     \item{`top_score`}{Highest score among retained hits for this sample.}
#'     \item{`n_retained`}{Number of hits retained after score + gap filtering
#'       (before rank threshold and whitelist steps).}
#'     \item{`n_taxa`}{Number of distinct `taxon_name` values among retained
#'       hits.}
#'     \item{`retained_taxa`}{List column: character vector of distinct taxon
#'       names among retained hits, sorted by descending score.}
#'     \item{`rank_capped`}{Logical.  `TRUE` when the consensus rank was
#'       demoted by `rank_thresholds`.  Only present when `rank_thresholds`
#'       is non-`NULL`.}
#'     \item{`whitelist_capped`}{Logical.  `TRUE` when the consensus was
#'       upranked because the original taxon was absent from `whitelist`.
#'       Only present when `whitelist` is non-`NULL`.}
#'     \item{`bracket_width_used`}{Numeric.  The bracket width that actually
#'       produced this row -- `bracket_width` normally, `bracket_fallback$width`
#'       when the fallback fired, and `NA_real_` in `"gap"` mode (which has no
#'       bracket).  Always present, so the column set does not change with
#'       `consensus_mode`.}
#'     \item{`agreement_achieved`}{Numeric.  The fraction of the rows the
#'       consensus was computed over (retained hits in `"bracket"` mode,
#'       distinct retained taxa in `"gap"` mode) that carry
#'       `consensus_taxon` at `consensus_rank` -- recomputed at the *final*
#'       reported rank, so it still describes the row after a rank cap or a
#'       whitelist uprank.  `NA_real_` when unresolvable, and also when the
#'       final rank has no column and no derivation in the retained rows (so
#'       the fraction is not computable rather than genuinely zero).}
#'   }
#'
#' @section Attributes:
#' `attr(out, "report_params")` is always set, recording the call's own
#' parameterization for downstream reporting (e.g.
#' `TaxaAssign::generate_report()`): `min_score`, `max_gap`,
#' `rank_thresholds`, `has_whitelist` (logical, whether `whitelist` was
#' supplied), `consensus_mode`, `agreement_fraction`, `bracket_width`
#' (`NA_real_` in `"gap"` mode), and `bracket_fallback` (`NULL` in `"gap"`
#' mode).
#'
#' @seealso [posterior_consensus()] for the Bayesian posterior-based approach.
#'
#' @examples
#' match_df <- data.frame(
#'   observation_id  = c("S1", "S1", "S1"),
#'   taxon_name      = c("Gadus morhua", "Gadus chalcogrammus", "Gadus"),
#'   taxon_name_rank = c("species", "species", "genus"),
#'   score_original  = c(99, 98.5, 90),
#'   genus           = "Gadus",
#'   family          = "Gadidae"
#' )
#' sc <- score_consensus(
#'   match_df,
#'   min_score       = 97,
#'   rank_thresholds = c(species = 98, genus = 95, family = 90)
#' )
#' sc[, c("observation_id", "consensus_taxon", "consensus_rank", "is_resolved")]
#'
#' # Jonah Ventures' published rule: 1% bracket, 90% agreement, widen to 2%
#' # when a >= 97% match still yields no family.
#' jv <- score_consensus(
#'   match_df,
#'   consensus_mode     = "bracket",
#'   agreement_fraction = 0.9,
#'   bracket_width      = 1,
#'   bracket_fallback   = list(min_score = 97, rank = "family", width = 2),
#'   rank_thresholds    = NULL
#' )
#' jv[, c(
#'   "consensus_taxon", "consensus_rank", "agreement_achieved",
#'   "bracket_width_used"
#' )]
#'
#' # A non-DNA score works the same way (BirdNET confidence, scaled to 0-100)
#' acoustic_df <- data.frame(
#'   observation_id  = c("R1", "R1"),
#'   taxon_name      = c("Turdus migratorius", "Turdus"),
#'   taxon_name_rank = c("species", "genus"),
#'   score_original  = c(92, 78),
#'   genus           = "Turdus",
#'   family          = "Turdidae"
#' )
#' sc_acoustic <- score_consensus(
#'   acoustic_df,
#'   min_score       = 70,
#'   rank_thresholds = c(species = 90, genus = 70, family = 50)
#' )
#' sc_acoustic[, c("observation_id", "consensus_taxon", "consensus_rank", "is_resolved")]
#'
#' @importFrom cli cli_abort cli_inform
#' @importFrom dplyr bind_rows
#'
#' @export
score_consensus <- function(match_df,
                            min_score = 0,
                            max_gap = Inf,
                            whitelist = NULL,
                            score_col = "score_original",
                            rank_system = NULL,
                            rank_thresholds,
                            consensus_mode = c("gap", "bracket"),
                            agreement_fraction = 1,
                            bracket_width = 1,
                            bracket_fallback = NULL) {
  # --- Input validation -------------------------------------------------------
  consensus_mode <- match.arg(consensus_mode)
  if (missing(rank_thresholds)) {
    cli::cli_abort(c(
      "{.arg rank_thresholds} must be specified explicitly.",
      "i" = "There is no safe default: this function has no way to know the \\
      marker or data type {.field score_col} was scored against, so no \\
      single fixed threshold set is safe to assume. Either supply your own \\
      named vector (e.g. {.code c(species = 98, genus = 95, family = 90)}), \\
      derive marker-specific thresholds from your own reference data via \\
      {.fn TaxaLikely::compute_rank_thresholds}, or pass \\
      {.code rank_thresholds = NULL} explicitly to disable rank-based \\
      capping entirely."
    ))
  }
  required <- c("observation_id", "taxon_name", "taxon_name_rank", score_col)
  missing_cols <- setdiff(required, names(match_df))
  if (length(missing_cols) > 0) {
    cli::cli_abort("match_df missing required column(s): {.field {missing_cols}}")
  }
  if (!is.numeric(match_df[[score_col]])) {
    cli::cli_abort("Column {.field {score_col}} must be numeric.")
  }
  if (!is.numeric(min_score) || length(min_score) != 1L) {
    cli::cli_abort("{.arg min_score} must be a single numeric value.")
  }
  if (!is.numeric(max_gap) || length(max_gap) != 1L || max_gap < 0) {
    cli::cli_abort("{.arg max_gap} must be a single non-negative numeric value.")
  }
  if (!is.null(rank_thresholds)) {
    if (!is.numeric(rank_thresholds) || is.null(names(rank_thresholds))) {
      cli::cli_abort("{.arg rank_thresholds} must be a named numeric vector.")
    }
  }
  if (!is.null(whitelist)) {
    if (!is.character(whitelist)) {
      cli::cli_abort("{.arg whitelist} must be a character vector.")
    }
  }
  if (!is.numeric(agreement_fraction) || length(agreement_fraction) != 1L ||
    is.na(agreement_fraction) || agreement_fraction <= 0 ||
    agreement_fraction > 1) {
    cli::cli_abort(
      "{.arg agreement_fraction} must be a single numeric value in (0, 1]."
    )
  }
  if (!is.numeric(bracket_width) || length(bracket_width) != 1L ||
    is.na(bracket_width) || bracket_width <= 0) {
    cli::cli_abort("{.arg bracket_width} must be a single positive numeric value.")
  }
  if (!is.null(bracket_fallback)) {
    if (!is.list(bracket_fallback)) {
      cli::cli_abort(
        "{.arg bracket_fallback} must be {.code NULL} or a named list with \\
        elements {.field min_score}, {.field rank} and {.field width}."
      )
    }
    fb_missing <- setdiff(c("min_score", "rank", "width"), names(bracket_fallback))
    if (length(fb_missing) > 0) {
      cli::cli_abort(
        "{.arg bracket_fallback} is missing element{?s}: {.field {fb_missing}}."
      )
    }
    if (!is.numeric(bracket_fallback$min_score) ||
      length(bracket_fallback$min_score) != 1L) {
      cli::cli_abort("{.arg bracket_fallback}$min_score must be a single numeric value.")
    }
    if (!is.numeric(bracket_fallback$width) ||
      length(bracket_fallback$width) != 1L || bracket_fallback$width <= 0) {
      cli::cli_abort("{.arg bracket_fallback}$width must be a single positive numeric value.")
    }
    if (!is.character(bracket_fallback$rank) || length(bracket_fallback$rank) != 1L) {
      cli::cli_abort("{.arg bracket_fallback}$rank must be a single rank name.")
    }
    if (consensus_mode != "bracket") {
      cli::cli_inform(
        "score_consensus: {.arg bracket_fallback} is ignored when \\
        {.arg consensus_mode} is {.val {consensus_mode}}."
      )
    }
  }

  # --- Auto-scale rank_thresholds if score_col looks like a 0-1 proportion --
  # A caller-supplied rank_thresholds is commonly written on the 0-100
  # percent-identity scale (e.g. the conventional GITA/Jonah Ventures
  # thresholds species=98, genus=95, family=90, phylum=85).
  # score_consensus() itself is scale-agnostic
  # (min_score's own doc: "97 for percent identity, 0.97 for proportion"), so
  # applying 0-100-scale thresholds blindly to 0-1-scale data would silently
  # make every observation unresolvable (no score could ever clear a
  # threshold of 85+). Detect and rescale, following the same
  # `if (max(x) > 1) treat-as-percent else treat-as-proportion` convention
  # used elsewhere in the ecosystem (TaxaLikely::.normalize_scores(),
  # assign_scores(), restore_suppressed_candidates()$delta).
  if (!is.null(rank_thresholds) && any(rank_thresholds > 1)) {
    max_score <- suppressWarnings(max(match_df[[score_col]], na.rm = TRUE))
    if (is.finite(max_score) && max_score <= 1) {
      rank_thresholds <- rank_thresholds / 100
      cli::cli_inform(
        "score_consensus: {.field {score_col}} values look like a 0-1 \\
        proportion scale (max = {round(max_score, 3)}); rescaling \\
        {.arg rank_thresholds} by /100 to match. Pass {.arg rank_thresholds} \\
        explicitly (already on your data's scale) to silence this."
      )
    }
  }

  # --- Resolve rank system ----------------------------------------------------
  if (is.null(rank_system)) {
    rank_system <- TaxaTools::detect_ranks(match_df)
  } else {
    # .find_lca() infers coarsest/finest from POSITION -- warn if a
    # user-supplied vector disagrees in order with the standard Linnaean
    # ranking, since that would silently swap "coarsest" and "finest".
    .check_rank_system_order(rank_system, "score_consensus")
  }

  # bracket_fallback$rank has to name a rank the rank walk actually visits --
  # validated here rather than above because rank_system may be auto-detected.
  if (!is.null(bracket_fallback) && consensus_mode == "bracket" &&
    !bracket_fallback$rank %in% rank_system) {
    cli::cli_abort(c(
      "{.arg bracket_fallback}$rank ({.val {bracket_fallback$rank}}) is not in \\
      the rank system.",
      "i" = "Available rank{?s}: {.field {rank_system}}."
    ))
  }

  # --- Process each sample ----------------------------------------------------
  observation_ids <- unique(match_df$observation_id)
  cli::cli_inform(
    "Computing score-based consensus for {length(observation_ids)} observation(s)..."
  )
  if (consensus_mode == "bracket") {
    cli::cli_inform(
      "  mode: bracket (width {bracket_width}, agreement \\
      {agreement_fraction}{if (is.null(bracket_fallback)) '' else \\
      paste0(', fallback to width ', bracket_fallback$width)})"
    )
  }

  results <- lapply(observation_ids, function(sid) {
    chunk <- match_df[match_df$observation_id == sid, ]
    .score_consensus_one(
      chunk, sid, score_col, min_score, max_gap,
      rank_thresholds, whitelist, rank_system,
      consensus_mode, agreement_fraction, bracket_width, bracket_fallback
    )
  })

  out <- dplyr::bind_rows(results)

  attr(out, "report_params") <- list(
    min_score          = min_score,
    max_gap            = max_gap,
    rank_thresholds    = rank_thresholds,
    has_whitelist      = !is.null(whitelist),
    consensus_mode     = consensus_mode,
    agreement_fraction = agreement_fraction,
    bracket_width      = if (consensus_mode == "bracket") bracket_width else NA_real_,
    bracket_fallback   = if (consensus_mode == "bracket") bracket_fallback else NULL
  )

  out
}


# ==============================================================================
# Internal helpers
# ==============================================================================

#' Compute score-based consensus for one observation
#'
#' Handles both `consensus_mode` values.  The two modes differ in exactly two
#' places -- which hits are retained (a `max_gap` window vs. an anchored
#' `bracket_width` bracket) and what the agreement rule counts over (distinct
#' retained taxa vs. retained hits).  Everything downstream (rank-threshold
#' capping, whitelist upranking) is shared and unchanged.
#' @noRd
.score_consensus_one <- function(chunk, sid, score_col, min_score, max_gap,
                                 rank_thresholds, whitelist, rank_system,
                                 consensus_mode = "gap",
                                 agreement_fraction = 1,
                                 bracket_width = 1,
                                 bracket_fallback = NULL) {
  finest_rank <- rank_system[length(rank_system)]

  .empty_score_row <- function() {
    out <- data.frame(
      observation_id = sid,
      consensus_taxon = NA_character_,
      consensus_rank = NA_character_,
      consensus_reason = NA_character_,
      is_resolved = FALSE,
      top_score = NA_real_,
      n_retained = 0L,
      n_taxa = 0L,
      retained_taxa = I(list(character(0))),
      stringsAsFactors = FALSE
    )
    if (!is.null(rank_thresholds)) out$rank_capped <- FALSE
    if (!is.null(whitelist)) out$whitelist_capped <- FALSE
    out$bracket_width_used <- NA_real_
    out$agreement_achieved <- NA_real_
    out
  }

  # Step 1: minimum score filter
  scores <- chunk[[score_col]]
  keep1 <- !is.na(scores) & scores >= min_score
  if (!any(keep1)) {
    return(.empty_score_row())
  }

  top_score <- max(scores[keep1], na.rm = TRUE)

  # Step 2 + 3: retention window, then the agreement rule over the retained
  # rows.  Wrapped in a closure because `bracket_fallback` needs to run the
  # whole thing a second time at a wider width.
  #
  # Note on the bracket: Jonah Ventures describe "first considering 100%
  # matches, and then going down in 1% steps until hits are present for each
  # ESV".  That is equivalent to anchoring a single bracket at THIS
  # observation's own top score -- every step from 100% down to the top score
  # is empty by construction, so there is nothing to iterate over and the
  # first non-empty bracket is always (top - width, top].  There is
  # deliberately no loop here; none was forgotten.  (Checked against JV's own
  # delivered detailed-hit tables: per-ESV hit sets there span a 1-point
  # range that is NOT aligned to integer percent boundaries -- e.g. 98.8-99.4
  # -- which rules out a fixed 99-100 / 98-99 grid and confirms the anchored
  # reading.)
  #
  # The `>` (rather than `>=`) is the published description read literally.
  # JV's real bound is inclusive -- see the bracket_width roxygen.  Affects
  # 1 ESV in 14,719 on the Pt Conception MiFish data.
  run_window <- function(width) {
    keep2 <- if (consensus_mode == "bracket") {
      keep1 & scores > (top_score - width)
    } else {
      keep1 & scores >= (top_score - max_gap)
    }
    if (!any(keep2)) {
      return(NULL)
    }

    kept <- chunk[keep2, , drop = FALSE]
    # Sort by score descending for retained_taxa ordering
    kept <- kept[order(kept[[score_col]], decreasing = TRUE), , drop = FALSE]
    # Deduplicate to unique taxon names (keep best score per taxon)
    taxa_unique <- kept[!duplicated(kept$taxon_name), , drop = FALSE]

    # "gap" mode reaches its consensus over the DISTINCT retained taxa (this
    # is the classical LCA behaviour and must not change).  "bracket"
    # mode counts HITS, because JV's rule is "taxonomy present in at least
    # 90% of the hits" -- a species backed by 8 accessions is 8 hits there,
    # not 1.
    basis <- if (consensus_mode == "bracket") kept else taxa_unique

    list(
      kept = kept,
      taxa_unique = taxa_unique,
      basis = basis,
      cons = .find_consensus_by_agreement(basis, rank_system, agreement_fraction)
    )
  }

  res <- run_window(bracket_width)
  if (is.null(res)) {
    return(.empty_score_row())
  }

  bracket_width_used <- if (consensus_mode == "bracket") bracket_width else NA_real_
  widened <- FALSE

  # Step 4 (bracket mode only): widen the bracket when a high-scoring
  # observation still returns no taxonomy at the fallback rank or finer.
  # JV: "If matches of 97% or higher are present but no family level taxonomy
  # is returned, the bracket is increased to 2%".  "No family level taxonomy
  # returned" is read as "the consensus is coarser than family, or absent" --
  # in a hierarchical Kingdom..Species output a genus- or species-level
  # consensus DOES print a family, so those cases are not eligible.
  if (consensus_mode == "bracket" && !is.null(bracket_fallback) &&
    top_score >= bracket_fallback$min_score &&
    .rank_is_coarser_than(res$cons$rank, bracket_fallback$rank, rank_system)) {
    widened_res <- run_window(bracket_fallback$width)
    if (!is.null(widened_res)) {
      res <- widened_res
      bracket_width_used <- bracket_fallback$width
      widened <- TRUE
    }
  }

  kept <- res$kept
  taxa_unique <- res$taxa_unique
  n_retained <- nrow(kept)
  n_taxa <- nrow(taxa_unique)

  lca <- res$cons
  is_resolved <- !is.na(lca$rank) && lca$rank == finest_rank
  consensus_reason <- lca$consensus_reason
  if (consensus_mode == "bracket" && !is.na(lca$taxon)) {
    consensus_reason <- if (widened) "bracket_widened" else "bracket"
  }

  rank_capped <- FALSE
  whitelist_capped <- FALSE

  # Step 5: rank threshold capping
  if (!is.null(rank_thresholds) && !is.na(lca$rank)) {
    cap_result <- .cap_rank_by_threshold(
      lca, top_score, rank_thresholds,
      rank_system, taxa_unique
    )
    if (!is.na(cap_result$rank) && cap_result$rank != lca$rank) {
      rank_capped <- TRUE
      consensus_reason <- "threshold"
    }
    lca <- cap_result
    is_resolved <- !is.na(lca$rank) && lca$rank == finest_rank
  }

  # Step 6: whitelist upranking
  if (!is.null(whitelist) && !is.na(lca$taxon)) {
    uprank_result <- .uprank_to_whitelist(
      lca, whitelist, taxa_unique,
      rank_system
    )
    if (!is.na(uprank_result$rank) && uprank_result$rank != lca$rank) {
      whitelist_capped <- TRUE
    }
    # If upranking failed entirely (no whitelist match at any rank),
    # mark as unresolvable
    if (is.na(uprank_result$taxon)) {
      whitelist_capped <- TRUE
    }
    lca <- uprank_result
    is_resolved <- !is.na(lca$rank) && lca$rank == finest_rank
  }

  # Recomputed at the FINAL rank so the diagnostic still describes the row
  # after a rank cap or whitelist uprank moved it.
  agreement_achieved <- .rank_agreement_fraction(res$basis, lca$rank, lca$taxon)

  out <- data.frame(
    observation_id = sid,
    consensus_taxon = lca$taxon,
    consensus_rank = lca$rank,
    consensus_reason = consensus_reason,
    is_resolved = is_resolved,
    top_score = top_score,
    n_retained = n_retained,
    n_taxa = n_taxa,
    retained_taxa = I(list(taxa_unique$taxon_name)),
    stringsAsFactors = FALSE
  )
  if (!is.null(rank_thresholds)) out$rank_capped <- rank_capped
  if (!is.null(whitelist)) out$whitelist_capped <- whitelist_capped
  out$bracket_width_used <- as.numeric(bracket_width_used)
  out$agreement_achieved <- as.numeric(agreement_achieved)
  out
}


#' Consensus rank walk under an agreement fraction
#'
#' Walks `rank_system` finest to coarsest.  At each rank, a taxon is reported
#' when it holds at least `agreement_fraction` of ALL rows in `df` -- rows
#' whose label at that rank is missing count toward the denominator but toward
#' no taxon, so an unlabelled hit is evidence against a consensus at that rank
#' rather than a row to drop.  If no taxon clears the bar, or if more than one
#' does (possible only at `agreement_fraction <= 0.5`), the rank yields NA and
#' the walk continues coarser -- JV: "If several taxa within a taxonomic level
#' match the ESV, an NA is reported for that taxonomic level."
#'
#' Returns a list with `taxon`, `rank`, `consensus_reason` and `agreement`.
#' @noRd
.find_consensus_by_agreement <- function(df, rank_system, agreement_fraction) {
  if (nrow(df) == 0L) {
    return(list(
      taxon = NA_character_, rank = NA_character_,
      consensus_reason = NA_character_, agreement = NA_real_
    ))
  }

  # agreement_fraction == 1 IS strict unanimity, which .find_lca() already
  # implements (including its single-row shortcut and its reason vocabulary).
  # Delegating rather than reimplementing is what guarantees that the default
  # path -- consensus_mode = "gap", agreement_fraction = 1 -- is bit-for-bit
  # a classical strict-unanimity LCA.
  if (agreement_fraction >= 1) {
    out <- .find_lca(df, rank_system)
    out$agreement <- if (is.na(out$rank)) NA_real_ else 1
    return(out)
  }

  finest_rank <- rank_system[[length(rank_system)]]
  n <- nrow(df)
  # Inclusive at the boundary (9/10 resolves at 0.9), with a tolerance so the
  # decision cannot turn on binary representation of e.g. 27/30 vs 0.9.
  tol <- .Machine$double.eps^0.5

  for (rk in rev(rank_system)) {
    vals <- .extract_rank_values(df, rk)
    present <- vals[!is.na(vals)]
    if (length(present) == 0L) next

    tab <- table(present)
    meets <- tab[(as.numeric(tab) / n) >= (agreement_fraction - tol)]
    if (length(meets) != 1L) next

    reason <- if (rk == finest_rank) "unanimous" else "lca"
    return(list(
      taxon = names(meets)[[1L]],
      rank = rk,
      consensus_reason = reason,
      agreement = as.numeric(meets)[[1L]] / n
    ))
  }

  list(
    taxon = NA_character_, rank = NA_character_,
    consensus_reason = NA_character_, agreement = NA_real_
  )
}


#' Fraction of rows in `df` carrying `taxon` at rank `rk`
#'
#' Denominator is every row, including rows with no label at `rk`.  Returns
#' `NA_real_` (not 0) when no row carries the taxon at that rank: that happens
#' when the rank has no column and no derivation, in which case the fraction is
#' not computable rather than genuinely zero.
#' @noRd
.rank_agreement_fraction <- function(df, rk, taxon) {
  if (is.null(df) || nrow(df) == 0L || is.na(rk) || is.na(taxon)) {
    return(NA_real_)
  }
  vals <- .extract_rank_values(df, rk)
  n_hit <- sum(!is.na(vals) & vals == taxon)
  if (n_hit == 0L) {
    return(NA_real_)
  }
  n_hit / length(vals)
}


#' Is `rank` coarser than `reference` (or absent) in `rank_system`?
#'
#' `rank_system` runs coarse to fine, so a smaller index is coarser.  An `NA`
#' rank (nothing resolved at all) counts as coarser -- it certainly did not
#' produce a name at `reference` or finer.
#' @noRd
.rank_is_coarser_than <- function(rank, reference, rank_system) {
  if (is.na(rank)) {
    return(TRUE)
  }
  idx <- match(rank, rank_system)
  ref_idx <- match(reference, rank_system)
  if (is.na(ref_idx)) {
    return(FALSE)
  }
  # A rank outside rank_system cannot be placed; treat it as not coarser so
  # the fallback does not fire on an unplaceable rank.
  if (is.na(idx)) {
    return(FALSE)
  }
  idx < ref_idx
}


#' Cap consensus rank based on score thresholds
#'
#' If the top score does not meet the threshold for the current consensus rank,
#' demotes to the coarsest rank whose threshold IS met.  If no threshold is met,
#' returns NA (unresolvable).
#'
#' Also re-derives the consensus taxon at the demoted rank from the retained
#' hits (all retained hits must agree at the new rank).
#' @noRd
.cap_rank_by_threshold <- function(lca, top_score, rank_thresholds,
                                   rank_system, taxa_df) {
  # Find the finest rank whose threshold the top score meets (vectorized:
  # threshold_ranks is already ordered finest-to-coarsest, so the first TRUE
  # is the answer).
  threshold_ranks <- intersect(rev(rank_system), names(rank_thresholds))
  meets_threshold <- top_score >= unlist(rank_thresholds[threshold_ranks], use.names = FALSE)
  first_met <- which(meets_threshold)[1L]
  allowed_rank <- if (is.na(first_met)) NA_character_ else threshold_ranks[[first_met]]

  if (is.na(allowed_rank)) {
    return(list(taxon = NA_character_, rank = NA_character_))
  }

  # If current LCA rank is already at or coarser than allowed_rank, no change
  lca_idx <- match(lca$rank, rank_system)
  allowed_idx <- match(allowed_rank, rank_system)
  if (!is.na(lca_idx) && lca_idx <= allowed_idx) {
    return(lca)
  }

  # Demote: find the LCA at the allowed rank
  vals <- .extract_rank_values(taxa_df, allowed_rank)
  vals <- vals[!is.na(vals)]
  if (length(vals) == 0L) {
    return(list(taxon = NA_character_, rank = NA_character_))
  }

  if (length(unique(vals)) == 1L) {
    return(list(taxon = vals[[1L]], rank = allowed_rank))
  }

  # Multiple values at allowed_rank — walk coarser to find agreement
  allowed_idx_in_sys <- match(allowed_rank, rank_system)
  if (is.na(allowed_idx_in_sys) || allowed_idx_in_sys <= 1L) {
    return(list(taxon = NA_character_, rank = NA_character_))
  }

  for (i in seq(allowed_idx_in_sys - 1L, 1L)) {
    rk <- rank_system[i]
    vals <- .extract_rank_values(taxa_df, rk)
    vals <- vals[!is.na(vals)]
    if (length(vals) > 0 && length(unique(vals)) == 1L) {
      return(list(taxon = vals[[1L]], rank = rk))
    }
  }

  list(taxon = NA_character_, rank = NA_character_)
}


#' Uprank consensus to the nearest whitelisted rank
#'
#' If the consensus taxon is in the whitelist, returns it unchanged.
#' Otherwise, walks from the current rank toward coarser ranks, checking at
#' each rank whether all retained candidates agree on a value that appears
#' in the whitelist.
#' @noRd
.uprank_to_whitelist <- function(lca, whitelist, taxa_df, rank_system) {
  if (is.na(lca$taxon)) {
    return(lca)
  }

  # Check if current consensus is in whitelist

  if (lca$taxon %in% whitelist) {
    return(lca)
  }

  # Walk coarser from the current rank
  cur_idx <- match(lca$rank, rank_system)
  if (is.na(cur_idx)) {
    return(list(taxon = NA_character_, rank = NA_character_))
  }

  if (cur_idx <= 1L) {
    return(list(taxon = NA_character_, rank = NA_character_))
  }

  for (i in seq(cur_idx - 1L, 1L)) {
    rk <- rank_system[i]
    vals <- .extract_rank_values(taxa_df, rk)
    vals <- vals[!is.na(vals)]
    if (length(vals) == 0L) next
    if (length(unique(vals)) == 1L && vals[[1L]] %in% whitelist) {
      return(list(taxon = vals[[1L]], rank = rk))
    }
  }

  list(taxon = NA_character_, rank = NA_character_)
}
