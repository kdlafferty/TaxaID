#' Screen reviewed assignments for identity and presence problems
#'
#' @description
#' Applies a fixed set of rules to the rows of a reviewed assignment table
#' (one row per taxon at a site, as returned by `review_assignments()`) and
#' appends what the rules suggest. The rules combine three kinds of evidence
#' already present on each row: whether the best reference match fits well in
#' absolute terms, the reviewer's geographic, habitat and scope verdicts, and,
#' optionally, the competing hypotheses in the posterior table. Nothing is
#' dropped or changed: every input row is returned in its original order with
#' new columns that say what the screen would do and why.
#'
#' @section Two layers:
#' The screen separates two questions.
#'
#' The \strong{identity layer} asks whether the name on the row can be trusted.
#' Each row follows the first rule that applies:
#' \itemize{
#'   \item I1: good fit and geography likely or possible: keep.
#'   \item I2: good fit but geography unlikely. If the posterior table holds a
#'     referenced (`hypothesis_type` "specific_candidate") and local
#'     (`prior_branch` "kernel_estimated" or "resident_observed", or a
#'     `theta_mean` value) congener or confamilial of the call, observed for
#'     the same `observation_id`, whose best `score_likelihood` is within
#'     `relative_score_gap` of the call's best member, the call moves up to
#'     the genus (congener) or family (confamilial) they share. Otherwise the
#'     row is marked "review" (range expansion or error cannot be told
#'     apart) and the suggested action is "exclude". Without `posterior_df`
#'     every I2 row is "review". Only species and genus calls are tested.
#'   \item I3: poor fit and geography plausible. A call at `move_up_max_rank`
#'     or finer moves up to `best_identity_rank` if that is coarser than the
#'     call, otherwise up one rank. Coarser calls are kept with `poor_fit_flag` TRUE. A named
#'     unreferenced species (`winner_hypothesis_type` "unreferenced_species")
#'     whose geography is "likely" keeps its name.
#'   \item Habitat exclusion: poor fit, geography plausible and habitat
#'     unlikely, at `poor_fit_habitat_exclude_max_rank` or finer: exclude
#'     (applied before the move-up, after the unreferenced exception).
#'   \item I4: poor fit and geography unlikely: exclude.
#' }
#' A missing poor-fit verdict counts as a good fit, and a missing geography
#' verdict counts as plausible, so a missing verdict never triggers a rule.
#'
#' The \strong{presence layer} asks whether the taxon belongs in the study
#' system, for rows the identity layer did not exclude: "out_of_scope" if the
#' scope verdict is unlikely (scope wins), else "off_habitat" if the habitat
#' verdict is anything other than likely or possible, else "resident". A
#' missing habitat verdict leaves `presence` NA. Presence never sets
#' `suggested_action`.
#'
#' @section Flags, never drops:
#' The function returns every input row in the input order. It does not
#' remove rows, rename taxa in place, or alter any input column. The
#' appended columns are suggestions for the caller to act on; filtering is a
#' separate, deliberate step. The suggested action for a "review" row is
#' "exclude", the conservative reading, but `identity_action` keeps the
#' distinction.
#'
#' @section Site-aware screening:
#' `geography_col` may name a per-site column, such as
#' `llm_geographic_plausibility_site` returned by
#' `review_assignments(sites = ...)`. The rules then judge each taxon at each
#' site against that site's own geographic verdict, rather than one verdict
#' for the taxon across the whole study.
#'
#' @section Resolution across all the evidence:
#' With `resolve = TRUE` (the default) the screen takes one more,
#' deterministic step after the rules above. It asks whether the rest of the
#' evidence on the row agrees with the screen's own advice, and records the
#' answer in `flag_resolution`. It makes no LLM call, adds nothing to the
#' review prompt or its cache key, and never changes `suggested_action` or
#' any other column. Acting on it is left to the user.
#'
#' The evidence is read as three independent votes, each "support",
#' "against", "neutral" or "not_evaluated" (the needed columns are absent):
#' \itemize{
#'   \item \strong{SEQ}, the sequence match: `likelihood_support` and
#'     `poor_absolute_fit`. Support: `likelihood_support` >= 0.50 and no
#'     poor fit that counts against. Against: `likelihood_support` < 0.10, or
#'     a poor fit on a call finer than `best_identity_rank` (an unreferenced
#'     species is expected to fit poorly, so for it only
#'     `likelihood_support` counts).
#'   \item \strong{OCC}, occurrence: the occurrence-record side of the prior
#'     (`consensus_has_occurrence_record`, which matches the call's rank; else
#'     `winner_has_occurrence_record`; else `primary_plausibility`) and the
#'     reviewer's geography verdict together cast ONE vote,
#'     because both rest on the same occurrence data and their agreement is
#'     not two confirmations. If they disagree the vote is "split", counted
#'     as neutral. When `domestic_prior_caveat` is TRUE the vote is neutral,
#'     because occurrence databases under-index domestic and captive taxa.
#'   \item \strong{ECO}, habitat: `llm_p_habitat` read with the review's own
#'     cuts. Support needs p of at least 0.70, with `llm_p_habitat_lo` (if
#'     present) at least 0.10; against needs p below 0.10, with
#'     `llm_p_habitat_hi` (if present) below 0.70. A stated range spanning a
#'     cut is neutral.
#' }
#' The posterior is not a fourth vote: it is likelihood times prior, so
#' counting it would count SEQ and OCC twice. The prior is used only to
#' DISCOUNT, never to add support. A \emph{prior-driven} call (`prior_role`
#' "narrowed" or "changed", or `likelihood_support` below half of
#' `consensus_posterior`) has its OCC support set to neutral, since the prior
#' chose the call from the same records the geography verdict reads. A call
#' is \emph{stable} when `consensus_confidence_score` and
#' `robust_lower_posterior` (whichever are present, at least one) are all
#' at least 0.50; only a stable call can be "confirmed". An LLM verdict can raise
#' doubt but never create confidence: every route to "confirmed" or
#' "softened" requires SEQ support.
#'
#' `flag_consistency_score` is (votes for - votes against) / votes cast over
#' SEQ, OCC and ECO, from -1 to 1, NA with fewer than two votes cast. The
#' first rule that applies sets `flag_resolution`:
#' \itemize{
#'   \item R0: no call, or fewer than two votes cast: "not_assessed".
#'   \item R1: advice "exclude" with blank evidence or a `validity_flag`
#'     starting "invalid": "upheld". Positive evidence is never softened.
#'   \item R2: advice "exclude" with all three votes for, or with local
#'     records against an unlikely geography verdict and SEQ support:
#'     "conflicted".
#'   \item R3: advice "exclude": "confirmed" if the score is -1/3 or lower,
#'     else "upheld".
#'   \item R4: advice "verify_range" where the taxon has at least 3 distinct
#'     occurrence-record locations within 50 km of the row's site
#'     (`geo_local_record_location_n`, see below), the study-wide
#'     `llm_geographic_plausibility` is likely or possible, and SEQ
#'     supports: "softened".
#'   \item R5: advice "verify_range" otherwise: "upheld".
#'   \item R6: advice "keep" with SEQ against, or advice "keep" or "move_up"
#'     on a prior-driven call without SEQ support: "escalated". A "move_up"
#'     row is not escalated for SEQ against alone, because the move already
#'     answers the poor match.
#'   \item R7: advice "keep" or "move_up": "confirmed" with SEQ support, a
#'     score of 2/3 or higher, a stable call and a call that is not
#'     prior-driven; else "upheld".
#' }
#' Rank is never a condition. A genus or family call is resolved with the
#' same rules from its own rank-matched columns, so no rank is a dead end
#' (see `add_posthoc_assessment()`, \strong{Why no rank-based
#' short-circuit}).
#'
#' `geo_local_record_location_n` is supplied by the caller: for each row,
#' the number of distinct occurrence-record locations of the taxon (for a
#' genus or family call, of any member) within 50 km of the row's site.
#' Given a table `local_n` with columns `consensus_taxon`, `site` and `n`
#' (distinct `point_id` within 50 km), join it without reordering rows:
#' `reviewed$geo_local_record_location_n <- local_n$n[match(paste(reviewed$consensus_taxon, reviewed$site), paste(local_n$consensus_taxon, local_n$site))]`.
#' Without the column, R4 never fires and those rows read "upheld".
#'
#' @param reviewed_df A data frame with one row per taxon x site unit.
#'   Required columns: `observation_id`, the columns named by `taxon_col`,
#'   `rank_col`, `geography_col`, `poor_fit_col` and `best_identity_rank_col`.
#'   `scope_col` and `habitat_col` are optional; if absent the matching rule is
#'   skipped with a message. A `winner_hypothesis_type` column enables the
#'   unreferenced-species exception. An `n_tubes` column (distinct tubes per
#'   row) enables `isolated_geography_unlikely`. Columns named `genus`,
#'   `family`, `order`, `class` and `phylum`, if present, help resolve the
#'   taxon a call moves up to.
#' @param posterior_df Optional data frame of per-hypothesis posterior rows.
#'   Needed to find relatives for rule I2. Columns: `observation_id`,
#'   `taxon_name`, `taxon_name_rank`, `hypothesis_type`, `genus`, `family`,
#'   `score_likelihood`; and `theta_mean` and/or `prior_branch` to decide
#'   whether a relative is local. Also used, with its `genus` through
#'   `phylum` columns, to resolve move-up target names. `NULL` (default) means
#'   no relatives are found and every I2 row is "review".
#' @param taxon_col,rank_col Names of the consensus taxon and rank columns.
#' @param geography_col,habitat_col,scope_col Names of the reviewer's
#'   geographic, habitat and scope plausibility columns, with values
#'   "likely", "possible" or "unlikely" (anything else counts as missing
#'   for geography, and as not plausible for habitat).
#' @param poor_fit_col Name of the logical column that is TRUE when the best
#'   match fits poorly in absolute terms.
#' @param best_identity_rank_col Name of the column giving the rank at which
#'   the best reference match is identified; used as the move-up target when
#'   it is coarser than the call.
#' @param relative_score_gap Largest allowed shortfall of a relative's
#'   `score_likelihood` below the call's best member for the relative to
#'   qualify under I2 (inclusive). The default 0.25 is a chosen value, not
#'   calibrated; on the test data 0.10 and 0.25 gave identical results.
#' @param move_up_max_rank Coarsest call rank that is moved up under I3.
#'   One of "species", "genus", "family", "order", "class", "phylum",
#'   "kingdom". The default "genus" is a rank limit chosen by the maintainer
#'   and checked against expert review.
#' @param poor_fit_habitat_exclude_max_rank Coarsest call rank at which poor
#'   fit with an unlikely habitat excludes the row. Default "family".
#' @param blank_flag_col Optional name of a logical column marking rows with
#'   blank (contamination) evidence. Where TRUE, `suggested_action` becomes
#'   "exclude" and `identity_reason` has "blank evidence" appended;
#'   `identity_action` is unchanged. The default `NULL` ignores it, because no fixed column
#'   name exists, so the caller names the column.
#' @param resolve Logical. `TRUE` (default) appends `flag_resolution`,
#'   `flag_resolution_basis` and `flag_consistency_score`; see
#'   \strong{Resolution across all the evidence}. `FALSE` returns exactly the
#'   columns and attributes the screen returned before this argument existed.
#'
#' @return `reviewed_df` with these columns appended, in the same row order:
#' \describe{
#'   \item{identity_action}{"keep", "move_up", "exclude" or "review".}
#'   \item{identity_taxon_after}{Taxon after the identity layer: the call
#'     itself, the move-up target (NA if its lineage cannot be resolved), or
#'     NA when excluded.}
#'   \item{identity_rank_after}{Rank of `identity_taxon_after`; NA when
#'     excluded.}
#'   \item{identity_reason}{Plain-words reason naming the rule.}
#'   \item{suggested_action}{"keep", "move_up", "verify_range" or "exclude".
#'     An identity_action of "review" maps to "verify_range" -- the check to
#'     settle is the one its reason names, range expansion versus error -- and
#'     NOT to "exclude": a consumer that drops rows on "exclude" would
#'     otherwise discard a row the screen asked to have looked at.
#'     Blank-flagged rows DO suggest "exclude", and that override still applies
#'     to a "verify_range" row: contamination evidence is positive evidence,
#'     unlike an unsettled range question.}
#'   \item{presence}{"resident", "off_habitat" or "out_of_scope"; NA for
#'     identity-excluded rows and where habitat is missing.}
#'   \item{poor_fit_flag}{TRUE for poor-fit calls kept at a rank coarser than
#'     `move_up_max_rank`.}
#'   \item{isolated_geography_unlikely}{Information only; never acts. TRUE if
#'     the taxon's total tubes across the input (summed `n_tubes`) is at most
#'     3 and geography is unlikely; FALSE otherwise; NA when `reviewed_df` has
#'     no `n_tubes` column or the count is missing.}
#'   \item{flag_resolution}{With `resolve = TRUE`: "confirmed", "upheld",
#'     "softened", "escalated", "conflicted" or "not_assessed". Whether the
#'     rest of the evidence agrees with `suggested_action`; never NA.}
#'   \item{flag_resolution_basis}{With `resolve = TRUE`: the rule that fired
#'     and each vote with the values behind it, e.g.
#'     `"R4; seq=support(ls 0.91); occ=split(records yes, geo unlikely); eco=support(p 0.85); prior_driven=no; stable=yes"`.}
#'   \item{flag_consistency_score}{With `resolve = TRUE`: numeric, -1 to 1,
#'     or NA when fewer than two votes were cast.}
#' }
#' The result also carries `attr(, "rule_counts")`, a data frame with one row
#' per rule (I1, I2_relative, I2_review, I3_move_up, I3_flag_coarse,
#' I3_exception, poor_fit_habitat_exclude, I4, blank_evidence) and `n_rows`,
#' the number of rows on which it fired (0 when none). Rules are exclusive per row
#' except blank_evidence, which is counted in addition. A message reports
#' the same counts, zeros included, and states how many rows the relative move
#' (I2_relative, which depends on `relative_score_gap`) fired on. `rule_counts`
#' has a fixed row set and an `evaluated` column: a rule that ran and fired on
#' nothing has `n_rows` 0 and `evaluated` TRUE; a rule that could not run has
#' `n_rows` NA and `evaluated` FALSE (I2_relative without `posterior_df`,
#' I3_exception without a `winner_hypothesis_type` column,
#' poor_fit_habitat_exclude without the habitat column, blank_evidence with
#' `blank_flag_col = NULL`). Because `rule_counts` is an attribute, dplyr verbs
#' drop it; read it straight off the value `screen_assignments()` returns.
#' With `resolve = TRUE` the result also carries `attr(, "resolution_counts")`:
#' one row per rule R0 to R7 with `n_rows`, and a message reports the same
#' counts, zeros included.
#'
#' @examples
#' reviewed <- data.frame(
#'   observation_id = c("o1", "o2", "o3"),
#'   consensus_taxon = c("Gadus morhua", "Salmo salar", "Oncorhynchus"),
#'   consensus_rank = c("species", "species", "genus"),
#'   best_identity_rank = c("species", "species", "genus"),
#'   poor_absolute_fit = c(FALSE, TRUE, TRUE),
#'   llm_geographic_plausibility = c("likely", "unlikely", "likely"),
#'   llm_habitat_plausibility = c("likely", "likely", "likely"),
#'   llm_scope_plausibility = c("likely", "likely", "likely"),
#'   stringsAsFactors = FALSE
#' )
#' screen_assignments(reviewed)[, c("consensus_taxon", "identity_action",
#'                                   "suggested_action", "presence")]
#' @export
screen_assignments <- function(reviewed_df, posterior_df = NULL,
                               taxon_col = "consensus_taxon",
                               rank_col = "consensus_rank",
                               geography_col = "llm_geographic_plausibility",
                               habitat_col = "llm_habitat_plausibility",
                               scope_col = "llm_scope_plausibility",
                               poor_fit_col = "poor_absolute_fit",
                               best_identity_rank_col = "best_identity_rank",
                               relative_score_gap = 0.25,
                               move_up_max_rank = "genus",
                               poor_fit_habitat_exclude_max_rank = "family",
                               blank_flag_col = NULL,
                               resolve = TRUE) {
  RANKS <- c("species", "genus", "family", "order", "class", "phylum", "kingdom")
  rk <- function(x) match(x, RANKS)

  # ---- validation ---------------------------------------------------------
  if (!is.data.frame(reviewed_df)) stop("`reviewed_df` must be a data frame.", call. = FALSE)
  chr1 <- function(x, nm) if (!is.character(x) || length(x) != 1L || is.na(x))
    stop(sprintf("`%s` must be a single column name.", nm), call. = FALSE)
  for (nm in c("taxon_col", "rank_col", "geography_col", "habitat_col", "scope_col",
               "poor_fit_col", "best_identity_rank_col"))
    chr1(get(nm), nm)
  if (!is.null(blank_flag_col)) chr1(blank_flag_col, "blank_flag_col")
  req <- unique(c("observation_id", taxon_col, rank_col, geography_col,
                  poor_fit_col, best_identity_rank_col))
  miss <- setdiff(req, names(reviewed_df))
  if (length(miss))
    stop("`reviewed_df` is missing required column(s): ", paste(miss, collapse = ", "), call. = FALSE)
  if (!is.null(blank_flag_col) && !blank_flag_col %in% names(reviewed_df))
    stop("`blank_flag_col` '", blank_flag_col, "' is not a column of `reviewed_df`.", call. = FALSE)
  if (!is.logical(resolve) || length(resolve) != 1L || is.na(resolve))
    stop("`resolve` must be TRUE or FALSE.", call. = FALSE)
  if (!is.numeric(relative_score_gap) || length(relative_score_gap) != 1L ||
      is.na(relative_score_gap) || relative_score_gap < 0)
    stop("`relative_score_gap` must be a single non-negative number.", call. = FALSE)
  for (nm in c("move_up_max_rank", "poor_fit_habitat_exclude_max_rank")) {
    v <- get(nm)
    if (!is.character(v) || length(v) != 1L || !v %in% RANKS)
      stop(sprintf("`%s` must be one of: %s.", nm, paste(RANKS, collapse = ", ")), call. = FALSE)
  }
  if (!is.null(posterior_df)) {
    if (!is.data.frame(posterior_df)) stop("`posterior_df` must be a data frame or NULL.", call. = FALSE)
    preq <- c("observation_id", "taxon_name", "taxon_name_rank", "hypothesis_type",
              "genus", "family", "score_likelihood")
    pmiss <- setdiff(preq, names(posterior_df))
    if (length(pmiss))
      stop("`posterior_df` is missing required column(s): ", paste(pmiss, collapse = ", "), call. = FALSE)
    if (!any(c("theta_mean", "prior_branch") %in% names(posterior_df)))
      message("screen_assignments(): `posterior_df` has neither theta_mean nor prior_branch; ",
              "no relative can be judged local, so I2 rows will be 'review'.")
  }

  d <- reviewed_df
  n <- nrow(d)
  tx <- as.character(d[[taxon_col]]); cr <- as.character(d[[rank_col]])
  geo <- as.character(d[[geography_col]])
  if (habitat_col %in% names(d)) hab <- as.character(d[[habitat_col]]) else {
    message("screen_assignments(): column '", habitat_col, "' not found; habitat rules skipped.")
    hab <- rep(NA_character_, n) }
  if (scope_col %in% names(d)) scp <- as.character(d[[scope_col]]) else {
    message("screen_assignments(): column '", scope_col, "' not found; scope rule skipped.")
    scp <- rep(NA_character_, n) }
  bir <- as.character(d[[best_identity_rank_col]])
  good <- !(d[[poor_fit_col]] %in% TRUE)
  geo_plaus <- ifelse(is.na(geo), TRUE, geo %in% c("likely", "possible"))
  wht <- if ("winner_hypothesis_type" %in% names(d)) as.character(d$winner_hypothesis_type) else rep(NA_character_, n)
  obs <- as.character(d$observation_id)

  # ---- lineage lookup for move-up targets ---------------------------------
  lcols <- c("genus", "family", "order", "class", "phylum")
  lsrc <- list()
  if (!is.null(posterior_df))
    lsrc[[1]] <- data.frame(species = posterior_df$taxon_name,
                            posterior_df[intersect(lcols, names(posterior_df))],
                            stringsAsFactors = FALSE)
  if (any(lcols %in% names(d))) {
    lsrc[[2]] <- data.frame(species = ifelse(cr == "species", tx, NA_character_),
                            d[intersect(lcols, names(d))], stringsAsFactors = FALSE)
  }
  lin <- function(name, rank, to) {
    if (is.na(name) || is.na(rank)) return(NA_character_)
    if (rk(to) <= rk(rank)) return(name)
    key <- if (rank == "species") "species" else rank
    for (s in lsrc) {
      if (!key %in% names(s) || !to %in% names(s)) next
      j <- which(s[[key]] == name & !is.na(s[[to]]))[1]
      if (!is.na(j)) return(as.character(s[[to]][j]))
    }
    NA_character_
  }

  # ---- I2 relatives --------------------------------------------------------
  i2 <- which(good & !geo_plaus & !is.na(tx))
  pp <- NULL
  if (!is.null(posterior_df) && length(i2))
    pp <- split(posterior_df[posterior_df$observation_id %in% obs[i2], ],
                as.character(posterior_df$observation_id[posterior_df$observation_id %in% obs[i2]]))
  find_relative <- function(i) {
    r <- cr[i]; p <- pp[[obs[i]]]
    if (is.null(p) || !r %in% c("species", "genus")) return(list(found = FALSE))
    G <- lin(tx[i], r, "genus"); Fm <- lin(tx[i], r, "family")
    in_call <- if (r == "species") p$taxon_name == tx[i] else (p$genus %in% tx[i] | p$taxon_name == tx[i])
    win <- p[in_call %in% TRUE, ]
    wscore <- if (nrow(win) && any(!is.na(win$score_likelihood))) max(win$score_likelihood, na.rm = TRUE) else NA_real_
    th <- if ("theta_mean" %in% names(p)) !is.na(p$theta_mean) else rep(FALSE, nrow(p))
    pb <- if ("prior_branch" %in% names(p)) p$prior_branch %in% c("kernel_estimated", "resident_observed") else rep(FALSE, nrow(p))
    ok <- function(q, idx) {
      keep <- q$taxon_name_rank %in% c("species", "genus") & q$hypothesis_type %in% "specific_candidate" &
        (th[idx] | pb[idx]) & !is.na(wscore) & q$score_likelihood >= wscore - relative_score_gap - 1e-12
      keep %in% TRUE
    }
    if (r == "species" && !is.na(G)) {
      idx <- which(!in_call & p$genus %in% G & p$taxon_name != G); q <- p[idx, ]
      k <- ok(q, idx)
      if (any(k)) return(list(found = TRUE, taxon = G, rank = "genus", names = paste(utils::head(q$taxon_name[k], 3), collapse = "; ")))
    }
    if (!is.na(Fm)) {
      idx <- which(!in_call & p$family %in% Fm & !(p$genus %in% G) & p$taxon_name_rank %in% c("species", "genus"))
      q <- p[idx, ]; k <- ok(q, idx)
      if (any(k)) return(list(found = TRUE, taxon = Fm, rank = "family", names = paste(utils::head(q$taxon_name[k], 3), collapse = "; ")))
    }
    list(found = FALSE)
  }

  # ---- identity layer ------------------------------------------------------
  act <- rep("keep", n); rank_after <- cr; tax_after <- tx
  reason <- rep(NA_character_, n); poor_flag <- rep(FALSE, n)
  rule <- rep(NA_character_, n)
  for (i in seq_len(n)) {
    if (is.na(tx[i])) { reason[i] <- "no call"; next }
    if (good[i] && geo_plaus[i]) { reason[i] <- "I1: good fit, geography plausible: keep name"; rule[i] <- "I1"; next }
    if (good[i]) {
      rel <- find_relative(i)
      if (rel$found) {
        rule[i] <- "I2_relative"
        act[i] <- "move_up"; rank_after[i] <- rel$rank; tax_after[i] <- rel$taxon
        reason[i] <- sprintf("I2: good fit but geography unlikely; local relative scores reasonably (%s): moved to %s", rel$names, rel$rank)
      } else {
        rule[i] <- "I2_review"
        act[i] <- "review"
        reason[i] <- "I2: good fit but geography unlikely and no relative scores reasonably: kept, flagged for review (range expansion vs error); suggested_action is verify_range -- settle the range question, do not drop the detection"
      }
      next
    }
    if (geo_plaus[i]) {
      if (wht[i] %in% "unreferenced_species" && cr[i] %in% "species" && geo[i] %in% "likely") {
        reason[i] <- "I3 exception: poor fit but named unreferenced species with geography likely: keep name"; rule[i] <- "I3_exception"; next }
      if (hab[i] %in% "unlikely" && !is.na(rk(cr[i])) && rk(cr[i]) <= rk(poor_fit_habitat_exclude_max_rank)) {
        rule[i] <- "poor_fit_habitat_exclude"
        act[i] <- "exclude"; rank_after[i] <- NA_character_; tax_after[i] <- NA_character_
        reason[i] <- "Habitat exclusion: poor fit and habitat unlikely: exclude"; next }
      if (is.na(rk(cr[i]))) { reason[i] <- "I3: call rank not recognised: kept"; next }
      if (rk(cr[i]) > rk(move_up_max_rank)) {
        poor_flag[i] <- TRUE; rule[i] <- "I3_flag_coarse"
        reason[i] <- sprintf("I3: poor fit, geography plausible, call at %s (coarser than %s): kept and flagged, not moved up", cr[i], move_up_max_rank)
        next }
      tr <- if (!is.na(bir[i]) && !is.na(rk(bir[i])) && rk(bir[i]) > rk(cr[i])) bir[i] else RANKS[rk(cr[i]) + 1L]
      rule[i] <- "I3_move_up"
      act[i] <- "move_up"; rank_after[i] <- tr; tax_after[i] <- lin(tx[i], cr[i], tr)
      reason[i] <- sprintf("I3: poor fit, geography plausible: moved up to %s", tr)
    } else {
      rule[i] <- "I4"
      act[i] <- "exclude"; rank_after[i] <- NA_character_; tax_after[i] <- NA_character_
      reason[i] <- "I4: poor fit and geography unlikely: exclude"
    }
  }
  # Only I2_review produces "review", so this maps exactly one rule. It used to
  # map it to "exclude", which was not inert: the CalIntertidal reporting layer
  # drops rows on suggested_action == "exclude"
  # (reporting/archive_reports/_setup.R:156-159), so a row the screen wanted
  # LOOKED AT was dropped as though it had been excluded on evidence. Measured
  # on the r12c archive: 132 of the 191 rows suggested "exclude" were relabelled
  # reviews, against 55 genuine identity excludes and 4 from blank evidence.
  # "verify_range" names the check the reason text already states -- range
  # expansion versus error -- so the suggestion is an instruction rather than a
  # verdict. I4 and the habitat rule are untouched: both carry two independent
  # negatives, which is the nearest thing here to positive evidence of error.
  sugg <- ifelse(act == "review", "verify_range", act)

  # ---- blank evidence ------------------------------------------------------
  bl <- rep(FALSE, n)
  if (!is.null(blank_flag_col)) {
    bl <- d[[blank_flag_col]] %in% TRUE
    sugg[bl] <- "exclude"
    reason[bl] <- paste0(reason[bl], "; blank evidence")
  }

  # ---- presence layer ------------------------------------------------------
  surv <- act != "exclude" & !is.na(tx)
  base <- ifelse(is.na(hab), NA_character_, ifelse(hab %in% c("likely", "possible"), "resident", "off_habitat"))
  presence <- ifelse(!surv, NA_character_, ifelse(scp %in% "unlikely", "out_of_scope", base))

  # ---- isolated, geography unlikely (information only) --------------------
  iso <- rep(NA, n)
  if ("n_tubes" %in% names(d)) {
    nt <- as.numeric(d$n_tubes)
    tot <- tapply(nt, tx, function(z) if (anyNA(z)) NA_real_ else sum(z))
    tt <- as.numeric(tot[tx]); tt[is.na(tx)] <- NA_real_
    iso <- ifelse(!(geo %in% "unlikely"), FALSE, ifelse(is.na(tt), NA, tt <= 3))
  }

  d$identity_action <- act
  d$identity_taxon_after <- tax_after
  d$identity_rank_after <- rank_after
  d$identity_reason <- reason
  d$suggested_action <- sugg
  d$presence <- presence
  d$poor_fit_flag <- poor_flag
  d$isolated_geography_unlikely <- as.logical(iso)

  rule_names <- c("I1", "I2_relative", "I2_review", "I3_move_up", "I3_flag_coarse",
                  "I3_exception", "poor_fit_habitat_exclude", "I4", "blank_evidence")
  evaluated <- c(I1 = TRUE, I2_relative = !is.null(posterior_df), I2_review = TRUE,
                 I3_move_up = TRUE, I3_flag_coarse = TRUE,
                 I3_exception = "winner_hypothesis_type" %in% names(reviewed_df),
                 poor_fit_habitat_exclude = habitat_col %in% names(reviewed_df),
                 I4 = TRUE, blank_evidence = !is.null(blank_flag_col))
  counts <- vapply(rule_names, function(r) if (r == "blank_evidence") sum(bl) else sum(rule %in% r), numeric(1))
  counts[!evaluated] <- NA
  attr(d, "rule_counts") <- data.frame(rule = rule_names, n_rows = as.integer(counts),
                                       evaluated = unname(evaluated), stringsAsFactors = FALSE)
  shown <- ifelse(evaluated, as.character(as.integer(counts)), "not evaluated")
  rel_txt <- if (evaluated[["I2_relative"]]) paste0("fired on ", as.integer(counts[["I2_relative"]]), " rows")
             else "not evaluated (no posterior_df)"
  message("screen_assignments(): rows by rule: ", paste0(rule_names, " = ", shown, collapse = ", "), ". ",
          "Relative move (relative_score_gap = ", relative_score_gap, ") ", rel_txt, ".")
  if (resolve) {
    res <- .screen_resolution(d, advice = sugg, tx = tx, cr = cr, bir = bir, wht = wht,
                              blank = bl, poor_fit_col = poor_fit_col,
                              geography_col = geography_col)
    d$flag_resolution <- res$resolution
    d$flag_resolution_basis <- res$basis
    d$flag_consistency_score <- res$score
    rn <- paste0("R", 0:7)
    rc <- data.frame(rule = rn, n_rows = vapply(rn, function(r) sum(res$rule == r), integer(1)),
                     stringsAsFactors = FALSE, row.names = NULL)
    attr(d, "resolution_counts") <- rc
    message("screen_assignments(): resolution by rule: ",
            paste0(rc$rule, " = ", rc$n_rows, collapse = ", "), ".")
  }
  d
}

# Resolution step (see @section Resolution across all the evidence). Reads
# only columns already on the row; every threshold below is named in the
# roxygen section, and the habitat cuts are review_assignments()'s own.
#' @noRd
.screen_resolution <- function(d, advice, tx, cr, bir, wht, blank, poor_fit_col, geography_col) {
  RANKS <- c("species", "genus", "family", "order", "class", "phylum", "kingdom")
  rk <- function(x) match(x, RANKS)
  n <- nrow(d)
  num <- function(nm) if (nm %in% names(d)) suppressWarnings(as.numeric(d[[nm]])) else rep(NA_real_, n)
  chr <- function(nm) if (nm %in% names(d)) as.character(d[[nm]]) else rep(NA_character_, n)
  lgl <- function(nm) if (nm %in% names(d)) as.logical(d[[nm]]) else rep(NA, n)
  f2 <- function(x) ifelse(is.na(x), "NA", formatC(x, format = "f", digits = 2))

  # ---- SEQ ----
  ls <- num("likelihood_support")
  pf <- as.logical(d[[poor_fit_col]])
  unref <- wht %in% "unreferenced_species"
  # A poor fit counts against only a call finer than the rank the best match
  # identifies to (rank-matched); unknown best rank -> counts against.
  finer <- ifelse(is.na(rk(bir)) | is.na(rk(cr)), TRUE, rk(cr) < rk(bir))
  pf_against <- pf %in% TRUE & finer & !unref
  ls_low <- !is.na(ls) & ls < 0.10
  ls_high <- !is.na(ls) & ls >= 0.50
  seq_v <- ifelse(is.na(pf) & is.na(ls), "not_evaluated",
           ifelse(pf_against | ls_low, "against",
           ifelse(ls_high, "support", "neutral")))

  # ---- prior-driven / stable ----
  pr <- chr("prior_role"); cp <- num("consensus_posterior")
  pd_known <- !is.na(pr) | (!is.na(ls) & !is.na(cp))
  pdriven <- pr %in% c("narrowed", "changed") | (!is.na(ls) & !is.na(cp) & ls < 0.5 * cp)
  pdriven[!pd_known] <- NA
  ccs <- num("consensus_confidence_score"); rlp <- num("robust_lower_posterior")
  low_stab <- (!is.na(ccs) & ccs < 0.50) | (!is.na(rlp) & rlp < 0.50)
  stable <- ifelse(is.na(ccs) & is.na(rlp), NA, !low_stab)

  # ---- OCC: records side and geography side, ONE vote ----
  # Rank-matched first: consensus_has_occurrence_record answers for the
  # reported group, so a genus or family call is not judged by one species.
  rec <- if ("consensus_has_occurrence_record" %in% names(d)) lgl("consensus_has_occurrence_record")
  else if ("winner_has_occurrence_record" %in% names(d)) lgl("winner_has_occurrence_record") else {
    pp <- chr("primary_plausibility")
    ifelse(pp %in% c("expected", "unexpected"), TRUE, ifelse(pp %in% "unprecedented", FALSE, NA))
  }
  geo <- chr(geography_col)
  geo_ok <- ifelse(geo %in% c("likely", "possible"), TRUE, ifelse(geo %in% "unlikely", FALSE, NA))
  occ_v <- ifelse(is.na(rec) & is.na(geo_ok), "not_evaluated",
           ifelse(is.na(rec), ifelse(geo_ok, "support", "against"),
           ifelse(is.na(geo_ok), ifelse(rec, "support", "against"),
           ifelse(rec == geo_ok, ifelse(rec, "support", "against"), "split"))))
  occ_note <- occ_v
  dom <- lgl("domestic_prior_caveat") %in% TRUE
  occ_v[dom & occ_v != "not_evaluated"] <- "neutral"
  occ_note[dom & occ_note != "not_evaluated"] <- "neutral(domestic caveat)"
  circ <- occ_v == "support" & pdriven %in% TRUE
  occ_v[circ] <- "neutral"; occ_note[circ] <- "support->neutral(prior-driven)"
  occ_split_records <- rec %in% TRUE & geo_ok %in% FALSE
  occ_note[occ_v == "split"] <- sprintf("split(records %s, geo %s)",
                                        ifelse(rec[occ_v == "split"], "yes", "no"), geo[occ_v == "split"])

  # ---- ECO: habitat with stated range ----
  ph <- num("llm_p_habitat"); lo <- num("llm_p_habitat_lo"); hi <- num("llm_p_habitat_hi")
  eco_v <- ifelse(is.na(ph), "not_evaluated",
           ifelse(ph >= .p_cut_likely & (is.na(lo) | lo >= .p_cut_unlikely), "support",
           ifelse(ph < .p_cut_unlikely & (is.na(hi) | hi < .p_cut_likely), "against", "neutral")))

  # ---- consistency score ----
  votes <- cbind(seq_v, occ_v, eco_v)
  n_for <- rowSums(votes == "support"); n_against <- rowSums(votes == "against")
  n_cast <- rowSums(votes != "not_evaluated")
  score <- ifelse(n_cast >= 2, (n_for - n_against) / pmax(n_cast, 1), NA_real_)

  # ---- rules ----
  invalid <- grepl("^invalid", chr("validity_flag"))
  lrn <- num("geo_local_record_location_n")
  geo_study <- chr("llm_geographic_plausibility")
  seq_sup <- seq_v == "support"
  eps <- 1e-9
  rule <- character(n); out <- character(n)
  for (i in seq_len(n)) {
    a <- advice[i]
    if (is.na(tx[i]) || n_cast[i] < 2) { rule[i] <- "R0"; out[i] <- "not_assessed"; next }
    if (a %in% "exclude") {
      if (blank[i] || invalid[i]) { rule[i] <- "R1"; out[i] <- "upheld"; next }
      if (n_for[i] == 3 || (occ_split_records[i] && seq_sup[i])) { rule[i] <- "R2"; out[i] <- "conflicted"; next }
      rule[i] <- "R3"; out[i] <- if (score[i] <= -1/3 + eps) "confirmed" else "upheld"; next
    }
    if (a %in% "verify_range") {
      if (!is.na(lrn[i]) && lrn[i] >= 3 && geo_study[i] %in% c("likely", "possible") && seq_sup[i]) {
        rule[i] <- "R4"; out[i] <- "softened"; next }
      rule[i] <- "R5"; out[i] <- "upheld"; next
    }
    # keep / move_up
    if ((a %in% "keep" && seq_v[i] == "against") || (pdriven[i] %in% TRUE && !seq_sup[i])) {
      rule[i] <- "R6"; out[i] <- "escalated"; next }
    rule[i] <- "R7"
    out[i] <- if (seq_sup[i] && score[i] >= 2/3 - eps && stable[i] %in% TRUE && pdriven[i] %in% FALSE)
      "confirmed" else "upheld"
  }

  yn <- function(x) ifelse(is.na(x), "unknown", ifelse(x, "yes", "no"))
  basis <- sprintf("%s; seq=%s(ls %s); occ=%s; eco=%s(p %s); prior_driven=%s; stable=%s",
                   rule, seq_v, f2(ls), occ_note, eco_v, f2(ph), yn(pdriven), yn(stable))
  basis[rule == "R4"] <- paste0(basis[rule == "R4"], sprintf("; local_record_locations=%s", lrn[rule == "R4"]))
  basis[rule == "R1"] <- paste0(basis[rule == "R1"], "; blank or invalid validity evidence")
  basis[is.na(tx)] <- "R0; no call"
  list(resolution = out, basis = basis, score = score, rule = rule)
}
