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
#'   \item{suggested_action}{"keep", "move_up" or "exclude". "review" rows
#'     and blank-flagged rows suggest "exclude".}
#'   \item{presence}{"resident", "off_habitat" or "out_of_scope"; NA for
#'     identity-excluded rows and where habitat is missing.}
#'   \item{poor_fit_flag}{TRUE for poor-fit calls kept at a rank coarser than
#'     `move_up_max_rank`.}
#'   \item{isolated_geography_unlikely}{Information only; never acts. TRUE if
#'     the taxon's total tubes across the input (summed `n_tubes`) is at most
#'     3 and geography is unlikely; FALSE otherwise; NA when `reviewed_df` has
#'     no `n_tubes` column or the count is missing.}
#' }
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
                               blank_flag_col = NULL) {
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
  for (i in seq_len(n)) {
    if (is.na(tx[i])) { reason[i] <- "no call"; next }
    if (good[i] && geo_plaus[i]) { reason[i] <- "I1: good fit, geography plausible: keep name"; next }
    if (good[i]) {
      rel <- find_relative(i)
      if (rel$found) {
        act[i] <- "move_up"; rank_after[i] <- rel$rank; tax_after[i] <- rel$taxon
        reason[i] <- sprintf("I2: good fit but geography unlikely; local relative scores reasonably (%s): moved to %s", rel$names, rel$rank)
      } else {
        act[i] <- "review"
        reason[i] <- "I2: good fit but geography unlikely and no relative scores reasonably: kept, flagged for review (range expansion vs error)"
      }
      next
    }
    if (geo_plaus[i]) {
      if (wht[i] %in% "unreferenced_species" && cr[i] %in% "species" && geo[i] %in% "likely") {
        reason[i] <- "I3 exception: poor fit but named unreferenced species with geography likely: keep name"; next }
      if (hab[i] %in% "unlikely" && !is.na(rk(cr[i])) && rk(cr[i]) <= rk(poor_fit_habitat_exclude_max_rank)) {
        act[i] <- "exclude"; rank_after[i] <- NA_character_; tax_after[i] <- NA_character_
        reason[i] <- "Habitat exclusion: poor fit and habitat unlikely: exclude"; next }
      if (is.na(rk(cr[i]))) { reason[i] <- "I3: call rank not recognised: kept"; next }
      if (rk(cr[i]) > rk(move_up_max_rank)) {
        poor_flag[i] <- TRUE
        reason[i] <- sprintf("I3: poor fit, geography plausible, call at %s (coarser than %s): kept and flagged, not moved up", cr[i], move_up_max_rank)
        next }
      tr <- if (!is.na(bir[i]) && !is.na(rk(bir[i])) && rk(bir[i]) > rk(cr[i])) bir[i] else RANKS[rk(cr[i]) + 1L]
      act[i] <- "move_up"; rank_after[i] <- tr; tax_after[i] <- lin(tx[i], cr[i], tr)
      reason[i] <- sprintf("I3: poor fit, geography plausible: moved up to %s", tr)
    } else {
      act[i] <- "exclude"; rank_after[i] <- NA_character_; tax_after[i] <- NA_character_
      reason[i] <- "I4: poor fit and geography unlikely: exclude"
    }
  }
  sugg <- ifelse(act == "review", "exclude", act)

  # ---- blank evidence ------------------------------------------------------
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
  d
}
