# ==============================================================================
# taxonomy_consistency.R
# TaxaMatch — Per-observation taxonomy consistency annotation
# ==============================================================================


#' Add lowest consistent rank to a match object
#'
#' For each observation, finds the finest taxonomic rank that has a single
#' unambiguous value across all candidate rows.  When four barnacle candidates
#' share the same order but differ in family, genus, and species, the
#' observation receives \code{lowest_consistent_rank = "order"}.
#'
#' Designed to run after \code{\link{standardize_match_data}()} and (optionally)
#' \code{\link{convert_taxonomy_backbone}()}.  The resulting column can be used
#' to filter out observations that are only resolvable to a coarse rank, or as a
#' diagnostic to guide manual review.
#'
#' \strong{Strict mode} (default, \code{majority_threshold = NULL}): a rank is
#' consistent only when every non-blank candidate value is identical.
#'
#' \strong{Majority mode} (\code{majority_threshold} in (0, 1]): a rank is
#' consistent when the single most-common non-blank value accounts for at least
#' \code{majority_threshold} of all non-blank candidate values.  This handles
#' the common case where one reference-library accession carries a misassigned
#' rank value that would otherwise collapse the observation to a coarser rank.
#' Three additional columns are added (see \strong{Value}).
#'
#' \strong{Warning:} removing rows flagged by \code{is_rank_outlier} changes the
#' candidate set seen by \code{\link[TaxaLikely]{evaluate_likelihoods}()}.  Do
#' so before the likelihood step, and inspect the flagged rows before discarding
#' them.
#'
#' @param match_obj Data frame.  Standardised match object containing at least
#'   \code{observation_id_col} and the rank columns named in \code{rank_system}.
#' @param rank_system Character vector or \code{NULL}.  Rank columns to check,
#'   ordered coarse-to-fine (e.g.
#'   \code{c("order","family","genus","species")}).  Auto-detected when
#'   \code{NULL} by matching column names against
#'   \code{TaxaTools::extended_ranks}.
#' @param observation_id_col Character.  Name of the observation identifier
#'   column (default \code{"observation_id"}).
#' @param na_as_inconsistent Logical.  When \code{TRUE}, blank (\code{""}) and
#'   \code{NA} values count as a distinct category: a rank is flagged
#'   inconsistent when some candidates have no value and others do.  Default
#'   \code{FALSE}: blanks and \code{NA}s are ignored and only non-blank values
#'   are compared.
#' @param majority_threshold Numeric in (0, 1] or \code{NULL} (default).  When
#'   supplied, switches to majority mode: a rank is treated as consistent if the
#'   single most-common non-blank value accounts for at least this fraction of
#'   all non-blank candidate values.  A value of \code{0.8} requires 4 of 5
#'   candidates to agree.  Values \eqn{\le 0.5} are technically valid but
#'   semantically unusual (the "minority" would qualify as the majority).
#'
#' @return \code{match_obj} with one new column in strict mode, or four new
#'   columns in majority mode:
#' \describe{
#'   \item{\code{lowest_consistent_rank}}{Character.  The finest rank for which
#'     the consistency criterion is satisfied.  \code{NA} when no rank passes.}
#'   \item{\code{rank_majority_value}}{(\emph{majority mode only}) Character.
#'     The majority value at \code{lowest_consistent_rank} for the observation.
#'     \code{NA} when \code{lowest_consistent_rank} is \code{NA}.}
#'   \item{\code{rank_majority_fraction}}{(\emph{majority mode only}) Numeric.
#'     Fraction of non-blank candidates that hold \code{rank_majority_value}.
#'     \code{NA} when \code{lowest_consistent_rank} is \code{NA}.}
#'   \item{\code{is_rank_outlier}}{(\emph{majority mode only}) Logical.
#'     \code{TRUE} for rows whose value at \code{lowest_consistent_rank} differs
#'     from \code{rank_majority_value}.  Rows with \code{NA}/blank values at
#'     that rank are \code{FALSE} (missing data, not a contradiction).
#'     All rows are \code{FALSE} when \code{lowest_consistent_rank} is
#'     \code{NA}.}
#' }
#'   All original columns of \code{match_obj} are retained unchanged; only
#'   the columns above are added.
#'
#' @details
#' **Edge cases:** An observation with a single candidate row is always fully consistent
#' at every rank (nothing to disagree with), so
#' \code{lowest_consistent_rank} resolves to the finest rank in
#' \code{rank_system} regardless of how well-supported that single
#' candidate actually is -- this can give a false sense of resolution for a
#' genuinely weak match.
#'
#' A rank column that is entirely blank/\code{NA} for an observation counts
#' as trivially consistent (no disagreement is possible with zero non-blank
#' values), which does not block finer ranks from being evaluated. If all
#' candidates lack a \code{family} value but agree on \code{genus}, this
#' function can report \code{lowest_consistent_rank = "species"} even though
#' every \code{family} value is missing -- this is deliberate (missing data
#' should not prevent resolving finer ranks that ARE populated), but it
#' means a "consistent" result does not imply every coarser rank was
#' actually checked against real data.
#'
#' Internally, \code{na_as_inconsistent = TRUE} mode uses the sentinel
#' string \code{"__MISSING__"} to make blanks/NAs count as their own
#' category. If any real taxon name in your data literally equals
#' \code{"__MISSING__"}, it would be misinterpreted as a blank placeholder
#' -- an extremely unlikely collision in practice.
#'
#' @examples
#' m <- data.frame(
#'   observation_id = rep("obs1", 4),
#'   order   = rep("Sessilia", 4),
#'   family  = c("Balanidae", "Archaeobalanidae", "Balanidae", "Chthamalidae"),
#'   genus   = c("Amphibalanus", "Semibalanus", "Balanus", "Chthamalus"),
#'   species = c("Amphibalanus improvisus", "Semibalanus balanoides",
#'               "Balanus balanus", "Chthamalus fragilis")
#' )
#' # Strict mode: lowest consistent rank = order (3 different families)
#' add_lowest_consistent_rank(m, rank_system = c("order", "family", "genus", "species"))
#'
#' # Majority mode: 3/4 rows share "Balanidae"; threshold 0.75 -> family is consistent
#' add_lowest_consistent_rank(m, rank_system = c("order", "family", "genus", "species"),
#'                             majority_threshold = 0.75)
#'
#' @seealso [standardize_match_data()], [filter_redundant_hypotheses()]
#' @export
add_lowest_consistent_rank <- function(match_obj,
                                        rank_system          = NULL,
                                        observation_id_col   = "observation_id",
                                        na_as_inconsistent   = FALSE,
                                        majority_threshold   = NULL) {

  # ---- validate ---------------------------------------------------------------
  if (!is.data.frame(match_obj))
    stop("add_lowest_consistent_rank: 'match_obj' must be a data frame.",
         call. = FALSE)
  if (!observation_id_col %in% names(match_obj))
    stop(sprintf("add_lowest_consistent_rank: column '%s' not found.",
                 observation_id_col), call. = FALSE)
  if (!is.logical(na_as_inconsistent) || length(na_as_inconsistent) != 1L ||
      is.na(na_as_inconsistent))
    stop("add_lowest_consistent_rank: 'na_as_inconsistent' must be TRUE or FALSE.",
         call. = FALSE)
  if (!is.null(majority_threshold)) {
    if (!is.numeric(majority_threshold) || length(majority_threshold) != 1L ||
        is.na(majority_threshold) || majority_threshold <= 0 ||
        majority_threshold > 1)
      stop("add_lowest_consistent_rank: 'majority_threshold' must be a single ",
           "number in (0, 1].", call. = FALSE)
    if (majority_threshold <= 0.5)
      warning(
        "add_lowest_consistent_rank: majority_threshold <= 0.5 is technically ",
        "valid but semantically unusual -- with 2 candidate values evenly ",
        "split, both would qualify as 'the majority'. If you meant 'a ",
        "majority of candidates agree' in the everyday sense, use a value ",
        "> 0.5.", call. = FALSE
      )
  }

  # ---- auto-detect rank_system ------------------------------------------------
  if (is.null(rank_system)) {
    # Shared with standardize_match_data.R's own auto-detection (same
    # TaxaTools::extended_ranks matching logic) rather than duplicating it.
    rank_system <- .detect_rank_cols(match_obj)
    if (length(rank_system) < 2L)
      stop("add_lowest_consistent_rank: could not auto-detect rank_system. ",
           "Supply it explicitly, e.g. ",
           "rank_system = c(\"family\", \"genus\", \"species\").",
           call. = FALSE)
  }

  rank_system_orig <- rank_system
  rank_system <- rank_system[rank_system %in% names(match_obj)]
  if (length(rank_system) == 0L)
    stop("add_lowest_consistent_rank: none of the rank_system columns found ",
         "in match_obj.", call. = FALSE)
  if (length(rank_system) < length(rank_system_orig))
    warning(sprintf(
      "add_lowest_consistent_rank: rank_system name(s) not found in match_obj and silently ignored: %s",
      paste(setdiff(rank_system_orig, rank_system), collapse = ", ")
    ), call. = FALSE)

  # ---- helper: extract values to compare --------------------------------------
  # In strict mode (na_as_inconsistent = FALSE): returns only non-blank values.
  # In na_as_inconsistent = TRUE mode: replaces blanks/NAs with a sentinel so
  # they count as a distinct category in both strict and majority calculations.
  .get_vals <- function(x) {
    x <- as.character(x)
    if (na_as_inconsistent) {
      x[is.na(x) | !nzchar(x)] <- "__MISSING__"
      x
    } else {
      x[!is.na(x) & nzchar(x)]
    }
  }

  # ---- per-observation computation --------------------------------------------
  obs_ids      <- match_obj[[observation_id_col]]
  # Every per-observation result below is looked up BY NAME out of a named
  # vector (per_obs_rank[obs_key] etc.), and names are always character. A
  # numeric/integer observation_id column would therefore index those vectors
  # POSITIONALLY instead -- silently returning NA for every row whose id is
  # larger than the number of distinct observations, i.e. usually all of them.
  # Confirmed: integer ids c(10, 10, 20) returned lowest_consistent_rank =
  # NA for all three rows, where the identical data with character ids
  # returns "family"/"family"/"species". Coerced once, here, so the lookups
  # cannot silently change meaning with the column's storage type.
  obs_key      <- as.character(obs_ids)
  unique_ids   <- unique(obs_ids)
  majority_mode <- !is.null(majority_threshold)

  # Precomputed once (split() groups row indices by obs_ids in one pass)
  # rather than re-scanning the full obs_ids vector with which(obs_ids == id)
  # inside the lapply below -- the latter is O(n x unique_obs), which matters
  # for large acoustic/camera-trap datasets with thousands of candidates per
  # observation. split() drops NA-valued groups entirely (matching
  # which(obs_ids == NA)'s existing behavior of never matching anything,
  # since NA == NA is NA, not TRUE): idx_list[[as.character(NA)]] is
  # therefore NULL, and subsetting by NULL below produces the same empty
  # result as the old integer(0) from which().
  idx_list <- split(seq_len(nrow(match_obj)), obs_ids)

  per_obs_list <- lapply(unique_ids, function(id) {
    idx <- idx_list[[as.character(id)]]

    rank_results <- lapply(rank_system, function(rc) {
      vals <- .get_vals(match_obj[[rc]][idx])
      n    <- length(vals)

      if (n == 0L) {
        # All blank/NA — no disagreement possible
        return(list(consistent   = TRUE,
                    majority_val  = NA_character_,
                    majority_frac = NA_real_))
      }

      tab      <- sort(table(vals), decreasing = TRUE)
      maj_val  <- names(tab)[1L]
      maj_frac <- as.numeric(tab[1L]) / n

      if (majority_mode) {
        consistent <- maj_frac >= majority_threshold
      } else {
        consistent <- length(tab) <= 1L   # strict: only one distinct value
      }

      list(consistent   = consistent,
           # Revert sentinel to NA for output -- "__MISSING__" is an internal
           # .get_vals() marker, never a value we want to surface.
           majority_val  = if (maj_val == "__MISSING__") NA_character_ else maj_val,
           majority_frac = maj_frac)
    })
    names(rank_results) <- rank_system

    consistent <- vapply(rank_results, `[[`, logical(1L), "consistent")

    if (!any(consistent)) {
      return(list(rank          = NA_character_,
                  majority_val  = NA_character_,
                  majority_frac = NA_real_))
    }

    # rank_system is ordered coarse-to-fine, so the LAST (highest-index) TRUE
    # entry in `consistent` is the finest rank that still passes.
    best_idx <- max(which(consistent))
    list(rank          = rank_system[best_idx],
         majority_val  = rank_results[[best_idx]]$majority_val,
         majority_frac = rank_results[[best_idx]]$majority_frac)
  })
  names(per_obs_list) <- unique_ids

  # ---- extract broadcast vectors ----------------------------------------------
  # vapply() over the named per_obs_list already returns a vector named by
  # unique_ids (matching names(per_obs_list) set above) -- no separate
  # names<-() assignment needed here.
  per_obs_rank <- vapply(per_obs_list, `[[`, character(1L), "rank")

  # ---- broadcast lowest_consistent_rank to all rows --------------------------
  match_obj[["lowest_consistent_rank"]] <- unname(per_obs_rank[obs_key])

  # ---- majority mode: add fraction, majority value, and outlier flag ----------
  if (majority_mode) {
    per_obs_majv <- vapply(per_obs_list, `[[`, character(1L), "majority_val")
    per_obs_majf <- vapply(per_obs_list, `[[`, double(1L),    "majority_frac")

    match_obj[["rank_majority_value"]]    <- unname(per_obs_majv[obs_key])
    match_obj[["rank_majority_fraction"]] <- unname(per_obs_majf[obs_key])

    # is_rank_outlier: vectorised per rank.
    # A row is an outlier when its value at lowest_consistent_rank is non-blank
    # AND differs from the majority value for its observation.
    # Rows with blank/NA values at that rank are FALSE (missing, not contradicting).
    is_outlier           <- rep(FALSE, nrow(match_obj))
    majority_val_per_row <- unname(per_obs_majv[obs_key])
    lcr_per_row          <- unname(per_obs_rank[obs_key])

    for (rk in rank_system) {
      mask <- !is.na(lcr_per_row) & lcr_per_row == rk
      if (!any(mask)) next
      row_vals <- as.character(match_obj[[rk]][mask])
      maj_vals <- majority_val_per_row[mask]
      is_outlier[mask] <- !is.na(row_vals)  & nzchar(row_vals) &
                          !is.na(maj_vals)  & (row_vals != maj_vals)
    }

    match_obj[["is_rank_outlier"]] <- is_outlier
  }

  match_obj
}
