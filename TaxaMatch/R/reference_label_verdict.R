# NSE column names referenced via dplyr verbs below would otherwise trip an
# R CMD CHECK "no visible binding" note.
utils::globalVariables(c(
  "id_x", "id_y", "p_match", "w_y", "below_min_congruent",
  "pair_finest_common_rank", "label_confidence", "reference_action",
  "local_tier"
))

# ==============================================================================
# Reference-label verdicts: a numeric label_confidence and a categorical
# reference_action, DERIVED from evaluate_reference_accessions()'s existing
# output columns.
#
# Implements Thread 2 of
# ecosystem_docs/REENTRY_PROMPT_reference_quality_verdicts_and_downstream_use.md
# (written 2026-09-02 after the first complete PtConception screen).
#
# Why this exists, in one paragraph: `hierarchy_flag` is a MAJORITY VOTE over
# the top-N independent neighbours -- percent identity never enters it. In a
# thinly-covered clade the top neighbours are cross-family by construction, so
# a correct reference whose own conspecific matches at 100% still reads
# "incongruent" (the documented Stereolepis false-positive mode). Measured on
# the real 995-accession PtConception run: 12 accessions read "incongruent",
# touching 1,688 observations, but only 4 of them (16 observations) had no
# corroborating evidence anywhere -- the rest included cabezon (OK172573,
# 1,120 observations, agreeing hit at 100%, disagreeing at 96.79). The
# identity diagnostics that separate those two groups
# (`best_agreeing_pident`/`best_disagreeing_pident`/
# `congruent_evidence_exists_anywhere`/`congruent_evidence_best_pident`) have
# existed since 2026-08-07 but NOTHING consulted them. This file is what
# consults them.
# ==============================================================================

#' Vectorised label-confidence from the evidence columns
#'
#' Pure function of already-cached columns -- deliberately, so it can be
#' applied to an evaluation loaded from any existing cache without a
#' `.EVAL_REF_ACC_VERSION` bump or a re-BLAST, and so a caller who changes
#' `margin_scale` gets the new numbers immediately rather than through a
#' cache invalidation.
#'
#' The formula is a log-odds sum of two independent readings of the same
#' evidence:
#'
#' \preformatted{
#'   p_vote   = 1 - frac_independent_below_min_congruent_rank
#'   agree_p  = best_agreeing_pident, else congruent_evidence_best_pident
#'   d        = agree_p - best_disagreeing_pident        (capped, see below)
#'   logit(label_confidence) = logit(p_vote) + d / margin_scale
#' }
#'
#' The second term is written above as `logit(plogis(d / margin_scale))` in the
#' design brief; those are identically equal, and the simplified form is what
#' is implemented and documented, because it says the thing plainly: the
#' percent-identity margin enters as a direct log-odds shift of one unit per
#' `margin_scale` points of identity. `margin_scale` is the single free
#' parameter here (see `score_reference_labels()`'s own `@section
#' Where the numbers come from`).
#'
#' @param frac,best_agree,best_disagree,anywhere,anywhere_pident The
#'   correspondingly-named `evaluate_reference_accessions()` columns.
#' @param n_partners Integer vector or `NULL` (default). The row's own
#'   `n_independent_top_matches`. Where this is `0`, `confidence` is forced to
#'   `NA` -- see the "no partners is not a coin flip" note in the body.
#'   `NULL` skips the rule entirely, for a caller whose evaluation does not
#'   carry the column.
#' @param margin_scale,margin_cap See [score_reference_labels()].
#' @return List with `confidence` (numeric, in (0, 1), `NA` where `frac` is
#'   `NA` or `n_partners` is `0`) and `margin` (the capped `d`, `NA` where no
#'   identity information of any kind exists).
#' @noRd
.label_confidence_from_evidence <- function(frac, best_agree, best_disagree,
                                            anywhere, anywhere_pident,
                                            n_partners = NULL,
                                            margin_scale = 1, margin_cap = 5) {

  n <- length(frac)
  eps <- 1e-6

  # Corroborating identity: the top_n slice's own best agreeing hit if there
  # is one, otherwise the best agreeing hit ANYWHERE in the untruncated
  # independence-filtered pool. The fallback is what spares a correct
  # reference in a thin clade whose top_n window happens to hold no
  # conspecific at all (real case: Oxylebius pictus, KM057978 -- no agreeing
  # hit in its top 5, corroboration at 93.58 outside it).
  agree_p <- ifelse(
    !is.na(best_agree), best_agree,
    ifelse(anywhere %in% TRUE & !is.na(anywhere_pident), anywhere_pident, NA_real_)
  )

  # d, the identity margin, in percent-identity points. The two one-sided
  # cases are the informative ones and must NOT collapse to the same value:
  # "something corroborates the label and nothing contradicts it" is the
  # strongest possible evidence FOR, and "nothing corroborates the label
  # anywhere and something contradicts it" is the strongest evidence
  # AGAINST -- exactly the 4-vs-8 split measured on the real PtConception
  # run. Both-NA (no identity information at all) is neutral, not evidence.
  d <- rep(NA_real_, n)
  both      <- !is.na(agree_p) & !is.na(best_disagree)
  only_ok   <- !is.na(agree_p) &  is.na(best_disagree)
  only_bad  <-  is.na(agree_p) & !is.na(best_disagree)
  d[both]     <- agree_p[both] - best_disagree[both]
  d[only_ok]  <-  margin_cap
  d[only_bad] <- -margin_cap
  d <- pmax(pmin(d, margin_cap), -margin_cap)

  p_vote <- pmin(pmax(1 - frac, eps), 1 - eps)
  shift  <- ifelse(is.na(d), 0, d / margin_scale)
  conf   <- stats::plogis(stats::qlogis(p_vote) + shift)
  conf[is.na(frac)] <- NA_real_

  # NO PARTNERS IS NOT A COIN FLIP (2026-09-04, user-approved).
  # With zero valid partners `frac` falls back to its 0.5 default and `d` is
  # NA, so this arithmetic returns EXACTLY 0.5 -- which lands in the
  # "caution" band and makes the screen assert concern earned by an absence.
  # It is a prior with no data, not a measurement, and the base rate it is
  # implicitly claiming to be near is wrong by a mile: 931 of 989 evaluated
  # PtConception accessions came back "congruent". Measured across four real
  # caches, the split is total and has no exceptions -- all 98 zero-partner
  # rows scored exactly 0.500 and read "caution", while all 55 rows with at
  # least one partner had corroborating evidence and read "keep".
  #
  # The rule keys on n == 0, NOT on hierarchy_flag: an accession with 1-2
  # partners also reads "insufficient_independent_evidence" but does have
  # real evidence, and (measured, 55/55) is corroborated. Flagging on the
  # verdict rather than the partner count would wrongly blank those too.
  #
  # NA here flows through .reference_action_from_confidence()'s existing
  # is.na() rule to reference_action = "untested", which is the honest
  # reading: the accession was submitted, but no usable evidence came back.
  if (!is.null(n_partners)) {
    no_partners <- !is.na(n_partners) & n_partners == 0L
    conf[no_partners] <- NA_real_
  }

  list(confidence = conf, margin = d)
}

#' Score Reference Labels: a Numeric Label Confidence and a Categorical Action
#'
#' Adds two derived columns to an [evaluate_reference_accessions()] result:
#' `label_confidence` (numeric, high = the listed label is more likely
#' CORRECT) and `reference_action` (`"keep"`/`"caution"`/`"inspect"`/
#' `"remove"`/`"untested"`). Evidence and action are deliberately separate
#' columns -- the same split this ecosystem already uses for
#' `TaxaFlag::observation_validity` (numeric) vs `validity_flag`
#' (categorical), and for `TaxaHabitat::flag_institution_candidates()`'s
#' classify-then-review shape. The numeric grades the evidence; the categorical
#' is for humans and for [remove_incongruent_references()].
#'
#' @section Polarity:
#' HIGH `label_confidence` means MORE confidence that the label is correct,
#' i.e. LESS concern. This deliberately does NOT follow the ecosystem's
#' `*_risk`/`*_confusion_risk` convention (where high = more concern), which
#' is why the column is named `label_confidence` and not `label_risk` -- the
#' name states the direction. It is on the same scale and polarity as
#' `score_likelihood` and `TaxaFlag::observation_validity`, which is what a
#' consumer that multiplies it into a weight actually needs.
#'
#' @section No partners is not a coin flip:
#' An accession with ZERO valid comparison partners
#' (`n_independent_top_matches == 0`) has `label_confidence = NA` and
#' `reference_action = "untested"`, rather than the 0.500 the arithmetic
#' would otherwise produce.
#'
#' Why it would otherwise be 0.500: with no partners,
#' `frac_independent_below_min_congruent_rank` falls back to its 0.5 default
#' and the identity margin is `NA`, so the formula reduces to
#' `plogis(qlogis(0.5) + 0)`. That is a prior with no data, not a
#' measurement, and it lands squarely in the `"caution"` band -- i.e. the
#' screen asserting concern earned by an absence, against a base rate of 931
#' congruent out of 989 evaluated PtConception accessions.
#'
#' Measured across four independent real caches (PtConception plus three
#' GreatLakes), the split is total and has no exceptions: all 98 zero-partner
#' rows scored exactly 0.500 and read `"caution"`, while all 55 rows with at
#' least one partner had corroborating evidence
#' (`congruent_evidence_exists_anywhere == TRUE`) and read `"keep"`.
#'
#' The rule keys on the partner COUNT, deliberately not on `hierarchy_flag`.
#' An accession with 1-2 partners also reads
#' `"insufficient_independent_evidence"`, but it does have real evidence and
#' (55 of 55, measured) that evidence corroborates it; keying on the verdict
#' would wrongly blank those too.
#'
#' Some of these rows are a `max_hits` truncation artifact rather than a
#' property of the accession -- re-running PtConception's 34 at
#' `max_hits = 100` resolved 12, including 7 zero-partner rows that moved
#' `"caution"` to `"keep"` (`diagnostics/insufficient_evidence_probe.R`). But
#' 21 of 34 gained no hits at all when the window quintupled, so most of the
#' population is genuinely thin. `"untested"` is the honest reading either
#' way: we do not know.
#'
#' @section Where the numbers come from:
#' `label_confidence` is a pure function of columns
#' [evaluate_reference_accessions()] already caches, so it applies to any
#' existing cache with no `.EVAL_REF_ACC_VERSION` bump and no re-BLAST. Its
#' formula is a log-odds sum of the existing Jeffreys-smoothed vote and the
#' percent-identity margin the vote itself ignores:
#'
#' \preformatted{
#'   logit(label_confidence) = logit(1 - frac_independent_below_min_congruent_rank)
#'                             + d / margin_scale
#'   d = (best_agreeing_pident, else congruent_evidence_best_pident)
#'       - best_disagreeing_pident,  capped to +/- margin_cap
#' }
#'
#' `margin_scale` is the one free parameter: it says how many percent-identity
#' points are worth one unit of log-odds. The default `1` is not fitted -- it
#' is a stated convention, registered as such
#' (`ecosystem_docs/arbitrariness_audit.md`'s subject matter), chosen because
#' at MiFish-U amplicon lengths (~170 bp) one percent identity is roughly 1.7
#' nucleotide differences, the granularity at which this ecosystem already
#' treats identity differences as discriminating at species level. What the
#' default is checked against is behaviour, not fit: on the real 995-accession
#' PtConception evaluation it reproduces the measured, user-approved
#' evidence-gate split exactly (the 4 no-corroboration accessions score
#' <= 0.001 and are the only ones that reach `"remove"`; the 8 spared score
#' 0.056 to 0.97 and reach at worst `"inspect"`), and leaves all 919
#' `"congruent"` accessions at `"keep"`.
#'
#' @section Why `"remove"` also requires no corroboration anywhere:
#' `reference_action == "remove"` is gated on THREE conditions, not just a low
#' `label_confidence`: the accession must be flagged `"incongruent"`, have no
#' corroborating evidence anywhere in the untruncated independence-filtered
#' hit pool, AND score below `action_remove_below`. The corroboration test is
#' a hard veto rather than another additive term because one corroborating
#' record anywhere is qualitatively different from none -- it means some
#' independent submitter's sequence agrees with this label at family or finer.
#' The case that shows why a threshold alone is not enough is `Oxylebius
#' pictus` (`KM057978`), a real, locally-abundant painted greenling whose only
#' corroboration sits outside its top-5 window at 93.58, just below the 94.01
#' that contradicts it. It scores 0.056 -- a hair above the 0.05 default, so
#' the default threshold happens to spare it, but its fate would flip on any
#' small change to `margin_scale` or to `action_remove_below`. The veto is
#' what makes the outcome robust rather than lucky: raise
#' `action_remove_below` to 0.2 and it is still `"inspect"`, while the
#' genuinely uncorroborated accessions are still `"remove"`. That is the right
#' treatment: a borderline reference should be surfaced for review, not
#' deleted.
#'
#' `"remove"` is furthermore unreachable for any flag other than
#' `"incongruent"`. `"insufficient_independent_evidence"` is retryable, not
#' removable (it may simply mean a sparsely-referenced region of the
#' database), `"not_evaluated_oversized"` and
#' `"not_evaluated_wrong_marker"` (2026-09-04) were never submitted to BLAST
#' at all, and `"locally_corroborated"` (2026-09-03) was deliberately not
#' submitted because the caller's own reference set already corroborates it
#' -- it reads `"keep"` with `label_confidence = NA` (there is no BLAST
#' evidence to grade).
#'
#' @section Local corroboration: provenance and the veto (2026-09-03):
#' When `local_corroboration` ([corroborate_references_locally()] output) is
#' supplied, three things happen, and one deliberately does not.
#' `corroboration_source` records where the corroboration for each label
#' came from: `"blast"` (`congruent_evidence_exists_anywhere`), `"local"`
#' (`local_tier == "corroborated"`, or the row was skipped as
#' `"locally_corroborated"`), `"both"`, or `"none"`.
#' `local_best_independent_pident` and `local_n_independent_conspecific`
#' carry the local numbers beside the BLAST ones. And a row that resolves to
#' `"remove"` while the local set corroborates it is VETOED to `"inspect"`,
#' with `action_reason = "vetoed_by_local_corroboration"`.
#'
#' What does not happen: `label_confidence` stays the BLAST-only probability.
#' Local evidence is not folded into it, on purpose, so a reviewer can see
#' the two disagree -- that disagreement is exactly what found the
#' primer-inclusive-query blind spot (`KM057996`, *Zaniolepis frenata*,
#' actioned `"remove"` by BLAST while `OQ846041` in the local set matched it
#' at 100% over 97% of the amplicon; see [evaluate_reference_accessions()]'s
#' `@section Why the query is the primer-stripped amplicon`). All four
#' columns are present (`NA`/`"none"`-filled) even when no table is
#' supplied, so downstream code can rely on them.
#'
#' @param evaluation Data frame. Output of [evaluate_reference_accessions()]
#'   (or any data frame carrying its diagnostic columns -- a cache file read
#'   straight off disk works).
#' @param local_corroboration Data frame or `NULL` (default). Output of
#'   [corroborate_references_locally()]. Joined by version-stripped
#'   accession. See `@section Local corroboration`.
#' @param margin_scale Numeric (default `1`). Percent-identity points per unit
#'   of log-odds. Larger = the identity margin matters less relative to the
#'   vote. See `@section Where the numbers come from`.
#' @param margin_cap Numeric (default `5`). Caps `|d|`, and supplies the value
#'   used for the two one-sided cases (corroborated with nothing contradicting
#'   it; contradicted with nothing corroborating it anywhere).
#' @param action_remove_below,action_inspect_below,action_caution_below Numeric
#'   thresholds on `label_confidence` (defaults `0.05`, `0.25`, `0.75`)
#'   separating `"remove"`/`"inspect"`/`"caution"`/`"keep"`.
#' @param overwrite Logical (default `FALSE`). `TRUE` recomputes and replaces
#'   `label_confidence`/`label_identity_margin`/`reference_action` (and the
#'   local-corroboration columns) if they are already present; `FALSE` errors
#'   instead, so a second call with different parameters can't silently
#'   produce a mixed-provenance table.
#'
#' @return `evaluation` with seven columns added:
#'   \describe{
#'     \item{`label_confidence`}{Numeric in (0, 1). `NA` for a row with no
#'       computed congruence at all (`"not_evaluated_oversized"`,
#'       `"not_evaluated_wrong_marker"`, or a fetch failure).}
#'     \item{`label_identity_margin`}{Numeric, the capped `d` in
#'       percent-identity points. `NA` when the row carries no identity
#'       information of any kind.}
#'     \item{`reference_action`}{`"keep"`, `"caution"`, `"inspect"`,
#'       `"remove"`, or `"untested"`. `"untested"` means NO USABLE EVIDENCE
#'       WAS OBTAINED, which covers two different routes there: the query was
#'       never submitted to BLAST (`"not_evaluated_oversized"`,
#'       `"not_evaluated_wrong_marker"`), or it was submitted and came back
#'       with zero valid comparison partners
#'       (`n_independent_top_matches == 0`; widened to include this case
#'       2026-09-04 -- see `@section No partners is not a coin flip`).}
#'     \item{`action_reason`}{`"vetoed_by_local_corroboration"` where a
#'       `"remove"` was downgraded to `"inspect"` by the local set,
#'       `"locally_corroborated_not_blasted"` for a skipped row, `NA`
#'       otherwise.}
#'     \item{`corroboration_source`}{`"blast"`, `"local"`, `"both"`, or
#'       `"none"`. `NA` for a row with no verdict at all.}
#'     \item{`local_best_independent_pident`}{Percent identity (0-100) of
#'       the best independent local conspecific; `NA` without a table.}
#'     \item{`local_n_independent_conspecific`}{Its count; `NA` without a
#'       table.}
#'   }
#'   Row count and order are unchanged.
#'
#' @seealso [evaluate_reference_accessions()], [refine_reference_verdicts()],
#'   [remove_incongruent_references()], [flag_incongruent_references()]
#'
#' @examples
#' \dontrun{
#' ev <- evaluate_reference_accessions(accs, cache_dir = "ref_eval_cache")
#' ev <- score_reference_labels(ev)
#' table(ev$reference_action)
#' }
#'
#' @export
score_reference_labels <- function(evaluation,
                                   # These five defaults are mirrored in
                                   # `.LABEL_VERDICT_DEFAULTS` (below), which
                                   # is what `refine_reference_verdicts()`
                                   # resolves its own `...` against. A test
                                   # asserts the two stay identical.
                                   margin_scale         = 1,
                                   margin_cap           = 5,
                                   action_remove_below  = 0.05,
                                   action_inspect_below = 0.25,
                                   action_caution_below = 0.75,
                                   overwrite            = FALSE,
                                   local_corroboration  = NULL) {

  if (!is.data.frame(evaluation))
    stop("evaluation must be a data frame.", call. = FALSE)
  if (!is.null(local_corroboration)) {
    if (!is.data.frame(local_corroboration) ||
        !all(c("accession", "local_tier") %in% names(local_corroboration)))
      stop("local_corroboration must be NULL or corroborate_references_locally() output (accession, local_tier).",
           call. = FALSE)
  }
  .pos_num <- function(x, nm) {
    if (!is.numeric(x) || length(x) != 1L || is.na(x) || x <= 0)
      stop(sprintf("%s must be a single positive number.", nm), call. = FALSE)
  }
  .pos_num(margin_scale, "margin_scale")
  .pos_num(margin_cap, "margin_cap")
  for (nm in c("action_remove_below", "action_inspect_below", "action_caution_below")) {
    v <- get(nm)
    if (!is.numeric(v) || length(v) != 1L || is.na(v) || v < 0 || v > 1)
      stop(sprintf("%s must be a single number in [0, 1].", nm), call. = FALSE)
  }
  if (!(action_remove_below <= action_inspect_below &&
        action_inspect_below <= action_caution_below))
    stop("Thresholds must be ordered: action_remove_below <= action_inspect_below <= action_caution_below.",
         call. = FALSE)

  new_cols <- c("label_confidence", "label_identity_margin", "reference_action",
                "action_reason", "corroboration_source",
                "local_best_independent_pident", "local_n_independent_conspecific")
  present  <- intersect(new_cols, names(evaluation))
  if (length(present) > 0L && !isTRUE(overwrite))
    stop(sprintf(
      "evaluation already has column(s) %s -- pass overwrite = TRUE to recompute them.",
      paste(present, collapse = ", ")
    ), call. = FALSE)

  needed <- c("hierarchy_flag", "frac_independent_below_min_congruent_rank",
              "best_agreeing_pident", "best_disagreeing_pident",
              "congruent_evidence_exists_anywhere", "congruent_evidence_best_pident")
  missing_cols <- setdiff(needed, names(evaluation))
  if (length(missing_cols) > 0L)
    stop(sprintf(
      "evaluation is missing required columns: %s",
      paste(missing_cols, collapse = ", ")
    ), call. = FALSE)

  if (nrow(evaluation) == 0L) {
    evaluation$label_confidence      <- numeric(0L)
    evaluation$label_identity_margin <- numeric(0L)
    evaluation$reference_action      <- character(0L)
    evaluation$action_reason         <- character(0L)
    evaluation$corroboration_source  <- character(0L)
    evaluation$local_best_independent_pident   <- numeric(0L)
    evaluation$local_n_independent_conspecific <- integer(0L)
    return(evaluation)
  }

  lc <- .label_confidence_from_evidence(
    frac            = evaluation$frac_independent_below_min_congruent_rank,
    best_agree      = evaluation$best_agreeing_pident,
    best_disagree   = evaluation$best_disagreeing_pident,
    anywhere        = evaluation$congruent_evidence_exists_anywhere,
    anywhere_pident = evaluation$congruent_evidence_best_pident,
    # NULL when the caller's evaluation predates/omits the column -- the
    # zero-partner rule is then skipped rather than guessed at.
    n_partners      = evaluation[["n_independent_top_matches"]],
    margin_scale    = margin_scale,
    margin_cap      = margin_cap
  )

  evaluation$label_confidence      <- lc$confidence
  evaluation$label_identity_margin <- lc$margin

  action <- .reference_action_from_confidence(
    label_confidence = lc$confidence,
    hierarchy_flag   = evaluation$hierarchy_flag,
    anywhere         = evaluation$congruent_evidence_exists_anywhere,
    action_remove_below  = action_remove_below,
    action_inspect_below = action_inspect_below,
    action_caution_below = action_caution_below
  )

  # ---- Local corroboration: provenance + veto (2026-09-03) -----------------
  local <- .local_corroboration_columns(evaluation, local_corroboration)
  is_skipped <- evaluation$hierarchy_flag %in% "locally_corroborated"
  local_ok   <- local$corroborated | is_skipped
  blast_ok   <- evaluation$congruent_evidence_exists_anywhere %in% TRUE & !is_skipped
  no_verdict <- is.na(evaluation$hierarchy_flag)

  source <- ifelse(blast_ok & local_ok, "both",
                   ifelse(blast_ok, "blast", ifelse(local_ok, "local", "none")))
  source[no_verdict] <- NA_character_

  veto   <- .apply_local_veto(action, local_ok)
  reason <- rep(NA_character_, nrow(evaluation))
  reason[veto$vetoed] <- "vetoed_by_local_corroboration"
  reason[is_skipped]  <- "locally_corroborated_not_blasted"

  # A skipped row has no BLAST evidence to grade, so its confidence is NA and
  # its local numbers come from the row itself (the skip wrote them into
  # best_agreeing_pident / n_independent_top_matches) when no table is here
  # to supply them.
  local_pident <- local$best_pident
  local_n      <- local$n_independent
  fill <- is_skipped & is.na(local_pident)
  local_pident[fill] <- evaluation$best_agreeing_pident[fill]
  fill_n <- is_skipped & is.na(local_n)
  local_n[fill_n] <- as.integer(evaluation$n_independent_top_matches[fill_n])

  evaluation$reference_action                <- veto$action
  evaluation$action_reason                   <- reason
  evaluation$corroboration_source            <- source
  evaluation$local_best_independent_pident   <- local_pident
  evaluation$local_n_independent_conspecific <- local_n
  # Best-effort provenance for review_flagged_accessions()'s prompt line
  # (attributes do not survive subsetting; the column values above do).
  if (!is.null(local_corroboration) &&
      !is.null(attr(local_corroboration, "local_corroboration_params")))
    attr(evaluation, "local_corroboration_params") <-
      attr(local_corroboration, "local_corroboration_params")
  evaluation
}

#' Join a corroborate_references_locally() table onto an evaluation
#'
#' @return List of parallel vectors (one per `evaluation` row):
#'   `corroborated` (logical, `FALSE` where no table or no row),
#'   `best_pident` (percent, 0-100, `NA` where unknown), `n_independent`
#'   (integer, `NA` where unknown).
#' @noRd
.local_corroboration_columns <- function(evaluation, local_corroboration) {
  n <- nrow(evaluation)
  out <- list(corroborated = rep(FALSE, n), best_pident = rep(NA_real_, n),
              n_independent = rep(NA_integer_, n))
  if (is.null(local_corroboration) || nrow(local_corroboration) == 0L) return(out)
  lc  <- local_corroboration[!duplicated(.strip_acc_version(local_corroboration$accession)), ,
                             drop = FALSE]
  idx <- match(.strip_acc_version(evaluation$accession), .strip_acc_version(lc$accession))
  hit <- !is.na(idx)
  out$corroborated[hit] <- lc$local_tier[idx[hit]] %in% "corroborated"
  if ("best_independent_pident" %in% names(lc))
    out$best_pident[hit] <- 100 * as.numeric(lc$best_independent_pident[idx[hit]])
  if ("n_independent_conspecific" %in% names(lc))
    out$n_independent[hit] <- as.integer(lc$n_independent_conspecific[idx[hit]])
  out
}

#' The local-corroboration veto, in one place
#'
#' A `"remove"` that the local reference set corroborates becomes
#' `"inspect"`. Used by both [score_reference_labels()] and the trust-
#' weighted re-vote in [refine_reference_verdicts()], so the two cannot
#' drift.
#' @return List: `action` (character, vetoed), `vetoed` (logical).
#' @noRd
.apply_local_veto <- function(action, local_ok) {
  vetoed <- action %in% "remove" & local_ok %in% TRUE
  action[vetoed] <- "inspect"
  list(action = action, vetoed = vetoed)
}

#' Defaults for the label-confidence / action parameters, in one place
#'
#' `score_reference_labels()` and `refine_reference_verdicts()` both need the
#' same six knobs, and `refine_reference_verdicts()` has to hand different
#' subsets of them to two different internals. Resolving `...` against this
#' list once, up front, keeps the two functions' defaults from drifting apart
#' and turns a mistyped argument name into an error instead of a silently
#' ignored value.
#' @noRd
.LABEL_VERDICT_DEFAULTS <- list(
  margin_scale         = 1,
  margin_cap           = 5,
  action_remove_below  = 0.05,
  action_inspect_below = 0.25,
  action_caution_below = 0.75
)

#' @noRd
.resolve_label_params <- function(...) {
  supplied <- list(...)
  unknown <- setdiff(names(supplied), names(.LABEL_VERDICT_DEFAULTS))
  if (length(unknown) > 0L)
    stop(sprintf("Unknown label-verdict parameter(s): %s. Expected any of: %s.",
                 paste(unknown, collapse = ", "),
                 paste(names(.LABEL_VERDICT_DEFAULTS), collapse = ", ")), call. = FALSE)
  utils::modifyList(.LABEL_VERDICT_DEFAULTS, supplied)
}

#' Derive the categorical action from the numeric confidence
#'
#' Split out from [score_reference_labels()] so
#' [refine_reference_verdicts()] can re-derive an action from a re-weighted
#' confidence without duplicating the threshold ladder or the two hard vetoes
#' on `"remove"`.
#' @noRd
.reference_action_from_confidence <- function(label_confidence, hierarchy_flag,
                                              anywhere,
                                              action_remove_below,
                                              action_inspect_below,
                                              action_caution_below) {
  action <- rep("keep", length(label_confidence))
  action[!is.na(label_confidence) & label_confidence < action_caution_below] <- "caution"
  action[!is.na(label_confidence) & label_confidence < action_inspect_below] <- "inspect"

  # Two hard vetoes, both documented in score_reference_labels()'s roxygen:
  # only an "incongruent" verdict is removable at all, and corroborating
  # evidence ANYWHERE spares the accession regardless of how low its
  # confidence is.
  removable <- hierarchy_flag %in% "incongruent" &
    !(anywhere %in% TRUE) &
    !is.na(label_confidence) & label_confidence < action_remove_below
  action[removable] <- "remove"

  # "not_evaluated_wrong_marker" (2026-09-04) reads "untested" alongside
  # "not_evaluated_oversized": no label evidence was gathered either way, and
  # the action vocabulary answers "what should happen to this LABEL", which is
  # a different question from "does this accession belong in this screen".
  # The reason lives in hierarchy_flag, which is where a reviewer can act on
  # it -- deliberately NOT folded into "inspect", whose established meaning is
  # "the label evidence is ambiguous, look at it".
  action[is.na(label_confidence) |
           is.na(hierarchy_flag) |
           hierarchy_flag %in% c("not_evaluated_oversized",
                                 "not_evaluated_wrong_marker")] <- "untested"
  # "locally_corroborated" (2026-09-03): never BLASTed, so label_confidence
  # is NA -- but it is a positive verdict (an independent conspecific in the
  # caller's own reference set), not an untested one. Keep.
  action[hierarchy_flag %in% "locally_corroborated"] <- "keep"
  action
}

# ==============================================================================
# Thread 1: recursive screening -- an accession judged a likely error must not
# itself be used to judge other references.
# ==============================================================================

#' Trust weight for one comparison partner
#'
#' The cascade guard lives here, in one place. Only an accession whose OWN
#' verdict is a confident removal is discounted hard; an `"incongruent"`
#' partner is discounted only in proportion to its own `label_confidence`;
#' and `"insufficient_independent_evidence"` /
#' `"not_evaluated_oversized"` / `"not_evaluated_wrong_marker"` /
#' never-evaluated partners are NOT discounted
#' at all. That last rule is the one that stops the cascade: "we have not
#' gathered enough evidence about this partner" is not evidence that the
#' partner is wrong, and treating it as such lets two mutually-uncertain
#' accessions talk each other down to zero.
#'
#' A `"congruent"` partner is never discounted either, even one whose own
#' `label_confidence` is middling. That is not an oversight: the weighted
#' partner count is compared against `min_independent_partners`, so shaving
#' every ordinary partner from 1.0 to 0.999 would push an accession with
#' exactly three of them to 2.997 and flip it to
#' `"insufficient_independent_evidence"` on nothing but rounding. Discounting
#' is reserved for partners the vote itself already flagged.
#'
#' @return Numeric vector of weights in `[min_partner_weight, 1]`, one per
#'   element of `flag`. `1` wherever no reason to discount was found.
#' @noRd
.partner_trust_weight <- function(flag, action, label_confidence,
                                  min_partner_weight = 0) {
  w <- rep(1, length(flag))
  is_incongruent <- flag %in% "incongruent" & !is.na(label_confidence)
  w[is_incongruent] <- label_confidence[is_incongruent]
  w[action %in% "remove"] <- min_partner_weight
  pmax(pmin(w, 1), min_partner_weight)
}

#' Re-run Reference Verdicts With Each Partner Weighted by Its Own Trustworthiness
#'
#' `evaluate_reference_accessions()`'s verdict is a vote over an accession's
#' closest independent BLAST neighbours in which every neighbour counts
#' exactly once, however dubious that neighbour's own label is. This function
#' re-runs that vote from the cached per-partner votes, scaling each
#' partner's contribution by its own `label_confidence`, and iterates to a
#' fixpoint -- because discounting a partner changes both the numerator and
#' the denominator of everyone else's vote, which can flip verdicts in both
#' directions.
#'
#' Nothing is removed and nothing is overwritten: the refined verdicts arrive
#' as parallel `*_trust` columns beside the originals.
#'
#' @section What this needs, and what happens without it:
#' The individual votes are not in the per-accession cache -- they never were,
#' they were summarised and discarded. `evaluate_reference_accessions()`
#' began persisting them to a sidecar `reference_pair_cache.rds` on
#' 2026-09-02. An accession evaluated before that date, or with
#' `cache_dir = NULL`, has no pair rows, so it CANNOT be refined: it keeps
#' its original verdict, `trust_refined` reads `FALSE`, and a message says how
#' many accessions that applied to. Re-running
#' `evaluate_reference_accessions()` on those accessions is what builds their
#' pair rows; there is no way to reconstruct them without a fresh BLAST.
#'
#' @section Determinism:
#' Every iteration updates every accession simultaneously from the PREVIOUS
#' iteration's confidences (a Jacobi sweep, not Gauss-Seidel), so the result
#' does not depend on the order accessions appear in. The `top_n` slice
#' breaks percent-identity ties by `id_y` rather than by input order, for the
#' same reason.
#'
#' @section What it did on real data (2026-09-02):
#' On the PtConception 12S screen the motivating case was `Askoldia
#' variegata` (`MT627596`), the disagreeing partner in 4 of the 12
#' `"incongruent"` verdicts. Its own row reads
#' `"insufficient_independent_evidence"` with a 100% agreeing hit and nothing
#' disagreeing -- `label_confidence` 0.999. So the honest answer is that
#' weighting does not discount it: it is an under-evaluated partner, not a
#' likely error, and the disagreement it registers is a real family-level
#' distinction in a thinly-covered clade. The mechanism is right and the
#' cascade guard is doing its job; this particular accession was simply not
#' the culprit it looked like.
#'
#' @param evaluation Data frame. Output of [evaluate_reference_accessions()].
#'   `label_confidence`/`reference_action` are computed via
#'   [score_reference_labels()] if absent.
#' @param cache_dir Character or `NULL`. The same `cache_dir`
#'   [evaluate_reference_accessions()] was called with; its
#'   `reference_pair_cache.rds` supplies the per-partner votes. Ignored when
#'   `pair_table` is supplied directly.
#' @param pair_table Data frame or `NULL`. The per-partner votes, if held in
#'   memory rather than on disk -- columns `id_x`, `id_y`, `p_match` (0-1),
#'   `pair_finest_common_rank`.
#' @param rank_system Character vector (default `TaxaTools::standard_ranks`),
#'   coarse to fine -- must be the ladder the pair table's
#'   `pair_finest_common_rank` was computed against.
#' @param min_congruent_rank,top_n,hierarchy_incongruent_threshold,min_independent_partners
#'   The vote parameters, matching [evaluate_reference_accessions()]'s own
#'   defaults. Pass whatever that call used.
#' @param min_partner_weight Numeric (default `0`). Floor on a discounted
#'   partner's weight; `0` means an accession resolved to
#'   `reference_action == "remove"` stops voting entirely.
#' @param max_iter Integer (default `10L`). Iteration cap.
#' @param tol Numeric (default `1e-4`). Converged when no accession's
#'   `label_confidence` moves by more than this.
#' @param verbose Logical (default `TRUE`).
#' @param local_corroboration Data frame or `NULL` (default). Forwarded to
#'   [score_reference_labels()]; the same veto (a locally-corroborated
#'   `"remove"` becomes `"inspect"`) is applied to `reference_action_trust`.
#' @param ... Passed to [score_reference_labels()] (`margin_scale`,
#'   `margin_cap`, the three action thresholds) -- use the SAME values here
#'   as anywhere else in a pipeline, or the refined and unrefined columns are
#'   not comparable.
#'
#' @return `evaluation` with these columns added:
#'   `hierarchy_flag_trust`, `label_confidence_trust`,
#'   `reference_action_trust`, `frac_below_min_congruent_rank_trust`,
#'   `n_effective_partners` (the weighted partner count, which is what
#'   `min_independent_partners` is now compared against), and
#'   `trust_refined` (logical -- `FALSE` where no pair data existed, in which
#'   case the `*_trust` columns simply repeat the unrefined values).
#'   `attr(result, "trust_iterations")` and `attr(result, "trust_converged")`
#'   record the fixpoint's own behaviour.
#'
#' @seealso [score_reference_labels()], [evaluate_reference_accessions()]
#'
#' @examples
#' \dontrun{
#' ev <- evaluate_reference_accessions(accs, cache_dir = "ref_eval_cache")
#' ev <- refine_reference_verdicts(ev, cache_dir = "ref_eval_cache")
#' subset(ev, reference_action != reference_action_trust)
#' }
#'
#' @export
refine_reference_verdicts <- function(evaluation,
                                      cache_dir  = NULL,
                                      pair_table = NULL,
                                      rank_system = TaxaTools::standard_ranks,
                                      min_congruent_rank = "family",
                                      top_n = 5L,
                                      hierarchy_incongruent_threshold = 0.5,
                                      min_independent_partners = 3L,
                                      min_partner_weight = 0,
                                      max_iter = 10L,
                                      tol = 1e-4,
                                      verbose = TRUE,
                                      local_corroboration = NULL,
                                      ...) {

  if (!is.data.frame(evaluation))
    stop("evaluation must be a data frame.", call. = FALSE)
  if (!"accession" %in% names(evaluation))
    stop("evaluation must have an 'accession' column.", call. = FALSE)
  if (is.null(pair_table) && is.null(cache_dir))
    stop("Supply either cache_dir (holding reference_pair_cache.rds) or pair_table.",
         call. = FALSE)
  if (!is.numeric(min_partner_weight) || length(min_partner_weight) != 1L ||
      is.na(min_partner_weight) || min_partner_weight < 0 || min_partner_weight > 1)
    stop("min_partner_weight must be a single number in [0, 1].", call. = FALSE)

  rank_system <- tolower(rank_system)
  min_congruent_rank <- tolower(min_congruent_rank)
  if (!min_congruent_rank %in% rank_system)
    stop(sprintf("min_congruent_rank ('%s') must be one of rank_system's own ranks: %s",
                 min_congruent_rank, paste(rank_system, collapse = ", ")), call. = FALSE)
  min_rank_idx <- which(rank_system == min_congruent_rank)

  lp <- .resolve_label_params(...)
  if (!all(c("label_confidence", "reference_action") %in% names(evaluation)))
    evaluation <- do.call(score_reference_labels,
                          c(list(evaluation, local_corroboration = local_corroboration), lp))
  local_ok <- .local_corroboration_columns(evaluation, local_corroboration)$corroborated |
    evaluation$hierarchy_flag %in% "locally_corroborated"

  if (is.null(pair_table)) pair_table <- .load_reference_pair_cache(cache_dir)
  needed <- c("id_x", "id_y", "p_match", "pair_finest_common_rank")
  missing_cols <- setdiff(needed, names(pair_table))
  if (length(missing_cols) > 0L)
    stop(sprintf("pair_table is missing required columns: %s",
                 paste(missing_cols, collapse = ", ")), call. = FALSE)

  acc <- evaluation$accession
  pairs <- pair_table[pair_table$id_x %in% acc & pair_table$id_x != pair_table$id_y,
                      needed, drop = FALSE]

  # Unrefined values are the fallback for every accession with no pair rows,
  # and the starting point of the iteration for those that have them.
  evaluation$hierarchy_flag_trust   <- evaluation$hierarchy_flag
  evaluation$label_confidence_trust <- evaluation$label_confidence
  evaluation$reference_action_trust <- evaluation$reference_action
  evaluation$frac_below_min_congruent_rank_trust <-
    evaluation$frac_independent_below_min_congruent_rank
  evaluation$n_effective_partners <- NA_real_
  evaluation$trust_refined <- FALSE

  if (nrow(pairs) == 0L) {
    if (verbose)
      message("refine_reference_verdicts(): no cached per-partner votes for any of these ",
              "accessions -- every verdict returned unrefined. Re-run ",
              "evaluate_reference_accessions() with a cache_dir to build them.")
    attr(evaluation, "trust_iterations") <- 0L
    attr(evaluation, "trust_converged")  <- TRUE
    return(evaluation)
  }

  # Fixed across iterations: which partners disagree, and which pairs fall in
  # each accession's top_n window. Weights change from iteration to
  # iteration; percent identity and rank agreement do not, so the slice is
  # computed once. Tie-break on id_y makes the ordering a total order, hence
  # reproducible.
  pair_rank_idx <- match(tolower(pairs$pair_finest_common_rank), rank_system)
  pairs$below <- is.na(pair_rank_idx) | pair_rank_idx < min_rank_idx
  ord <- order(pairs$id_x, -pairs$p_match, pairs$id_y)
  pairs <- pairs[ord, , drop = FALSE]
  pairs$rank_in_group <- stats::ave(seq_len(nrow(pairs)),
                                    pairs$id_x, FUN = seq_along)
  pairs$in_top_n <- pairs$rank_in_group <= top_n

  refined_ids <- unique(pairs$id_x)
  evaluation$trust_refined <- acc %in% refined_ids

  y_idx <- match(pairs$id_y, acc)   # NA => partner not in this evaluation
  x_key <- factor(pairs$id_x, levels = refined_ids)

  lc_prev <- evaluation$label_confidence
  iter <- 0L
  converged <- FALSE

  .grp_sum <- function(v) {
    s <- rowsum(v, x_key, reorder = FALSE)
    as.numeric(s)[match(refined_ids, rownames(s))]
  }
  .grp_max <- function(v, keep) {
    out <- rep(NA_real_, length(refined_ids))
    if (!any(keep)) return(out)
    m <- tapply(v[keep], droplevels(x_key[keep]), max)
    out[match(names(m), refined_ids)] <- as.numeric(m)
    out
  }

  while (iter < max_iter) {
    iter <- iter + 1L

    # Jacobi sweep: every weight below is read from the PREVIOUS iteration's
    # state, so no accession's update can depend on where it sits in the
    # input.
    w_all <- .partner_trust_weight(
      flag             = evaluation$hierarchy_flag_trust[y_idx],
      action           = evaluation$reference_action_trust[y_idx],
      label_confidence = evaluation$label_confidence_trust[y_idx],
      min_partner_weight = min_partner_weight
    )
    w_all[is.na(y_idx)] <- 1   # partner outside this evaluation: not discounted
    counts <- w_all > 0

    w_top <- w_all * pairs$in_top_n
    n_eff <- .grp_sum(w_top)
    k_dis <- .grp_sum(w_top * pairs$below)
    frac  <- (k_dis + 0.5) / (n_eff + 1)

    # Identity diagnostics are recomputed over partners that still carry any
    # weight at all (a hard-zeroed partner should not supply the number that
    # rescues -- or condemns -- the accession it was just disqualified from
    # voting on). They are max-of-identity quantities, so they take the
    # binary "still counts" reading of the weights rather than the
    # continuous one.
    best_agree <- .grp_max(pairs$p_match * 100, counts & pairs$in_top_n & !pairs$below)
    best_disag <- .grp_max(pairs$p_match * 100, counts & pairs$in_top_n &  pairs$below)
    any_agree  <- .grp_sum(as.numeric(counts & !pairs$below)) > 0
    best_any   <- .grp_max(pairs$p_match * 100, counts & !pairs$below)

    flag_new <- ifelse(
      n_eff < min_independent_partners, "insufficient_independent_evidence",
      ifelse(frac >= hierarchy_incongruent_threshold, "incongruent", "congruent")
    )
    # n_eff == 0 covers both "no partners at all" and "every partner was
    # disqualified by the cascade guard" -- both mean no usable evidence
    # survived, which is what the zero-partner rule is about. Largely
    # defensive here: an accession with no pair rows is never refined in the
    # first place, so it cannot reach this branch.
    lc_new <- .label_confidence_from_evidence(
      frac = frac, best_agree = best_agree, best_disagree = best_disag,
      anywhere = any_agree, anywhere_pident = best_any,
      n_partners = ifelse(n_eff == 0, 0L, 1L),
      margin_scale = lp$margin_scale, margin_cap = lp$margin_cap
    )
    action_new <- .reference_action_from_confidence(
      label_confidence = lc_new$confidence, hierarchy_flag = flag_new,
      anywhere = any_agree,
      action_remove_below  = lp$action_remove_below,
      action_inspect_below = lp$action_inspect_below,
      action_caution_below = lp$action_caution_below
    )

    at <- match(refined_ids, acc)
    action_new <- .apply_local_veto(action_new, local_ok[at])$action
    evaluation$hierarchy_flag_trust[at]   <- flag_new
    evaluation$label_confidence_trust[at] <- lc_new$confidence
    evaluation$reference_action_trust[at] <- action_new
    evaluation$frac_below_min_congruent_rank_trust[at] <- frac
    evaluation$n_effective_partners[at]   <- n_eff

    delta <- max(abs(evaluation$label_confidence_trust - lc_prev), na.rm = TRUE)
    lc_prev <- evaluation$label_confidence_trust
    if (is.finite(delta) && delta < tol) { converged <- TRUE; break }
  }

  if (verbose) {
    n_unrefined <- sum(!evaluation$trust_refined)
    changed <- sum(evaluation$reference_action != evaluation$reference_action_trust,
                   na.rm = TRUE)
    message(sprintf(
      "refine_reference_verdicts(): %d accession(s) refined over %d iteration(s)%s; %d action(s) changed%s.",
      length(refined_ids), iter,
      if (converged) "" else sprintf(" (NOT converged at max_iter = %d)", max_iter),
      changed,
      if (n_unrefined > 0L)
        sprintf("; %d accession(s) had no cached per-partner votes and were left unrefined",
                n_unrefined) else ""
    ))
  }

  attr(evaluation, "trust_iterations") <- iter
  attr(evaluation, "trust_converged")  <- converged
  evaluation
}

#' Verify Removal Candidates Against a Wider Evidence Window
#'
#' Re-evaluates ONLY the accessions an evaluation would actually remove, at a
#' larger `max_hits`, and reports which of them stop being removable. Nothing
#' is removed, nothing is written back to the production cache, and no
#' verdict is overwritten -- this is the pre-removal audit step, not a
#' replacement for the screen.
#'
#' @section Why this exists:
#' `congruent_evidence_exists_anywhere` is the hard veto that spares an
#' accession from `reference_action == "remove"` however low its
#' `label_confidence`. It is documented as walking the pool "not limited to
#' `top_n`" -- and it is, but the pool is itself capped by `max_hits`
#' (default 20). On the real PtConception 12S screen, 899 of 989 accessions
#' (91%) came back AT that cap, so in practice "anywhere" has meant "anywhere
#' in the top 20".
#'
#' That was measured, not suspected
#' (`diagnostics/veto_truncation_probe.R`, 2026-09-04): at `max_hits = 100`,
#' `congruent_evidence_exists_anywhere` flipped `FALSE` to `TRUE` for 8 of 15
#' veto-critical accessions, and `OQ846263` (*Rathbunella hypoplecta*) --
#' one of only two accessions that PtConception run would have removed --
#' turned out to be corroborated and dropped to `"inspect"`. `KM057967`
#' (*Jordania zonope*) still removed at 100 hits, correctly: it is a genuine
#' singleton. Both congruent controls were unchanged, as they must be, since
#' widening a window cannot withdraw corroboration already observed.
#'
#' Raising the `max_hits` DEFAULT was considered and deliberately not done:
#' `max_hits` is part of `params_key`, so a change would invalidate every
#' cached row across every project cache (~3,000 real rows) for a screen that
#' has been NCBI-throttled before. Auditing only the removal candidates is
#' the cheap targeted alternative -- a real population is 1-4 accessions, and
#' removal is the one decision this package makes destructively.
#'
#' @section Comparability, and why the params_key is checked:
#' The audit is only meaningful if the re-evaluation differs from the
#' production run in `max_hits` ALONE. Pass through `...` exactly the same
#' verdict-affecting arguments the production screen used -- `barcode_term`
#' above all, since an untrimmed query is a different query. This function
#' compares the `params_key` its own call will produce against the one
#' carried on `evaluation` and warns, naming the fields, if anything other
#' than `max_hits` differs. Heed that warning: a mismatch does not make the
#' call fail, it makes the result mean nothing.
#'
#' @param evaluation An [evaluate_reference_accessions()] result. Needs
#'   `accession` plus either `reference_action` or the diagnostic columns
#'   [score_reference_labels()] derives it from.
#' @param ... Forwarded to [evaluate_reference_accessions()]. Must carry the
#'   production run's own verdict-affecting arguments (see above).
#' @param audit_max_hits Integer (default `100L`). The wider window. Note
#'   that on real data 13 of 34 accessions were still saturated at 100, so a
#'   clean result here bounds the problem rather than closing it.
#' @param cache_dir Directory for the audit's own cache, or `NULL` (default)
#'   for no caching. Because `max_hits` is in `params_key` an audit can never
#'   overwrite a production row, but a separate directory keeps the
#'   production cache free of rows no production call will ever read.
#' @param verbose Logical (default `TRUE`).
#' @return A data frame with one row per removal candidate: `accession`,
#'   `listed_taxon`, `action_production`/`action_audit`,
#'   `anywhere_production`/`anywhere_audit`,
#'   `n_partners_production`/`n_partners_audit`,
#'   `n_hits_audit`, `still_saturated` (the audit itself hit
#'   `audit_max_hits`, so its own window is also truncated), and `spared`
#'   (the accession is no longer actioned `"remove"`). Zero rows, and zero
#'   NCBI calls, when nothing would be removed.
#' @seealso [remove_incongruent_references()], [score_reference_labels()]
#' @export
verify_removal_candidates <- function(evaluation, ...,
                                      audit_max_hits = 100L,
                                      cache_dir = NULL,
                                      verbose = TRUE) {

  if (!is.data.frame(evaluation) || !"accession" %in% names(evaluation))
    stop("evaluation must be a data frame with an 'accession' column.", call. = FALSE)
  if (!is.numeric(audit_max_hits) || length(audit_max_hits) != 1L ||
      is.na(audit_max_hits) || audit_max_hits < 1)
    stop("audit_max_hits must be a single positive number.", call. = FALSE)

  if (!"reference_action" %in% names(evaluation))
    evaluation <- score_reference_labels(evaluation)

  cand <- evaluation[evaluation$reference_action %in% "remove", , drop = FALSE]

  empty <- data.frame(
    accession = character(0L), listed_taxon = character(0L),
    action_production = character(0L), action_audit = character(0L),
    anywhere_production = logical(0L), anywhere_audit = logical(0L),
    n_partners_production = integer(0L), n_partners_audit = integer(0L),
    n_hits_audit = integer(0L), still_saturated = logical(0L),
    spared = logical(0L), stringsAsFactors = FALSE
  )
  if (nrow(cand) == 0L) {
    if (verbose)
      message("verify_removal_candidates(): nothing is actioned 'remove' -- no NCBI call made.")
    return(empty)
  }

  audit <- evaluate_reference_accessions(
    cand$accession, ..., max_hits = as.integer(audit_max_hits),
    cache_dir = cache_dir, verbose = verbose
  )

  # Comparability check. Only meaningful when the production evaluation
  # actually carries a key (a hand-built fixture may not).
  if ("params_key" %in% names(evaluation) && "params_key" %in% names(audit)) {
    prod_key  <- unique(stats::na.omit(cand$params_key))
    audit_key <- unique(stats::na.omit(audit$params_key))
    if (length(prod_key) == 1L && length(audit_key) == 1L && prod_key != audit_key) {
      pf <- strsplit(prod_key, "|", fixed = TRUE)[[1L]]
      af <- strsplit(audit_key, "|", fixed = TRUE)[[1L]]
      # Field 8 IS max_hits and is expected to differ; see .build_params_key().
      if (length(pf) == length(af)) {
        differing <- setdiff(which(pf != af), 8L)
        if (length(differing) > 0L)
          warning(sprintf(
            "verify_removal_candidates(): the audit differs from the production run in more than max_hits (params_key field(s) %s: '%s' vs '%s'). The comparison is not meaningful -- pass the production run's own arguments (barcode_term above all) through `...`.",
            paste(differing, collapse = ", "),
            paste(pf[differing], collapse = ","), paste(af[differing], collapse = ",")
          ), call. = FALSE)
      }
    }
  }

  i <- match(cand$accession, audit$accession)
  out <- data.frame(
    accession    = cand$accession,
    listed_taxon = cand$listed_taxon %||% NA_character_,
    action_production = cand$reference_action,
    action_audit      = audit$reference_action[i],
    anywhere_production = cand$congruent_evidence_exists_anywhere,
    anywhere_audit      = audit$congruent_evidence_exists_anywhere[i],
    n_partners_production = cand$n_independent_top_matches,
    n_partners_audit      = audit$n_independent_top_matches[i],
    n_hits_audit          = audit$n_top_matches_available[i],
    stringsAsFactors = FALSE
  )
  # An audit row that itself came back at the cap tells you the wider window
  # is ALSO truncated -- a "still removable" verdict from such a row is a
  # weaker claim than one from a row with room to spare.
  out$still_saturated <- !is.na(out$n_hits_audit) &
    out$n_hits_audit >= as.integer(audit_max_hits) - 1L
  out$spared <- !(out$action_audit %in% "remove")

  if (verbose) {
    message(sprintf(
      "verify_removal_candidates(): %d of %d removal candidate(s) are no longer removable at max_hits = %d%s.",
      sum(out$spared, na.rm = TRUE), nrow(out), as.integer(audit_max_hits),
      if (any(out$spared, na.rm = TRUE))
        paste0(": ", paste(out$accession[out$spared %in% TRUE], collapse = ", ")) else ""
    ))
    n_sat <- sum(out$still_saturated & !(out$spared %in% TRUE), na.rm = TRUE)
    if (n_sat > 0L)
      message(sprintf(
        "  %d still-removable candidate(s) came back AT the audit window too, so that window is also truncated: %s",
        n_sat, paste(out$accession[out$still_saturated & !(out$spared %in% TRUE)], collapse = ", ")
      ))
  }
  out
}
