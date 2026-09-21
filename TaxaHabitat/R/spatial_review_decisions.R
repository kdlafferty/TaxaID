# ==============================================================================
# spatial_review_decisions.R
# TaxaHabitat -- persist and re-apply a reviewer's spatial-flag decisions
#
# Exported:
#   save_spatial_review_decisions
#   apply_spatial_review_decisions
#
# review_spatial_flags() is an interactive gadget whose output -- which flagged
# points a reviewer confirmed, dismissed, or moved to another habitat -- is a
# human decision, not a computed intermediate. Without persistence, every
# production workflow run would re-open the gadget and overwrite the previous
# decisions. These two helpers keep one small table per site, keyed on
# point_id (TaxaFetch::stack_occurrences() builds point_id from the
# coordinates, so it is stable across runs), and let a workflow open the
# gadget only for flagged points that carry no decision yet.
# ==============================================================================

#' Save a reviewer's spatial-flag decisions
#'
#' Extracts one row per \code{point_id} from \code{review_spatial_flags()}'s
#' output -- the reviewed \code{spatial_flag} and \code{main_habitat} -- and
#' merges it into the decisions file at \code{path} (a newer decision for the
#' same point replaces the older one).
#'
#' @param reviewed Data frame returned by \code{\link{review_spatial_flags}}
#'   (must carry \code{point_id}, \code{spatial_flag}, \code{main_habitat}).
#' @param path Character. The \code{.rds} decisions file, one per site.
#' @param before Optional data frame: the table the gadget was opened on
#'   (\code{flag_habitat_inconsistencies()}'s output). When supplied, a
#'   point's habitat is recorded as a reviewer REASSIGNMENT only where it
#'   differs from \code{before}; otherwise the habitat is treated as the
#'   automatic assignment of the day and is NOT frozen for later runs.
#'   \strong{Without \code{before}, this function cannot tell an automatic
#'   habitat from a reviewer reassignment at all}: every non-\code{NA}
#'   \code{main_habitat} in \code{reviewed} is recorded as a reassignment
#'   (the conservative reading) and will be re-applied VERBATIM by
#'   \code{\link{apply_spatial_review_decisions}} on every later run --
#'   freezing that point's habitat at whatever the automatic classifier
#'   happened to say the day it was reviewed, even if the classifier's own
#'   logic later changes for the better. Pass \code{before} whenever the
#'   pre-review table is available to avoid this.
#' @param point_id_col,flag_col,habitat_col Column names. Defaults match
#'   \code{review_spatial_flags()}'s output.
#' @return Invisibly, the merged decisions table (\code{point_id},
#'   \code{spatial_flag}, \code{main_habitat}, \code{habitat_reassigned},
#'   \code{decided_at}).
#' @seealso \code{\link{apply_spatial_review_decisions}}
#' @export
save_spatial_review_decisions <- function(reviewed, path, before = NULL,
                                          point_id_col = "point_id",
                                          flag_col = "spatial_flag",
                                          habitat_col = "main_habitat") {
  if (!is.data.frame(reviewed)) stop("save_spatial_review_decisions: `reviewed` must be a data frame.", call. = FALSE)
  for (cc in c(point_id_col, flag_col, habitat_col)) {
    if (!cc %in% names(reviewed)) stop(sprintf("save_spatial_review_decisions: `reviewed` has no column '%s'.", cc), call. = FALSE)
  }
  if (!is.character(path) || length(path) != 1L || is.na(path)) stop("save_spatial_review_decisions: `path` must be a single file path.", call. = FALSE)
  new <- data.frame(
    point_id     = as.character(reviewed[[point_id_col]]),
    spatial_flag = as.character(reviewed[[flag_col]]),
    main_habitat = as.character(reviewed[[habitat_col]]),
    decided_at   = format(Sys.time(), "%Y-%m-%d %H:%M"),
    stringsAsFactors = FALSE
  )
  new <- new[!is.na(new$point_id) & !is.na(new$spatial_flag), , drop = FALSE]
  new <- new[!duplicated(new$point_id), , drop = FALSE]
  if (!is.null(before)) {
    if (!is.data.frame(before) || !all(c(point_id_col, habitat_col) %in% names(before))) {
      stop("save_spatial_review_decisions: `before` must be a data frame with the point_id and habitat columns.", call. = FALSE)
    }
    bh <- as.character(before[[habitat_col]])[match(new$point_id, as.character(before[[point_id_col]]))]
    # .is_habitat_unassigned(), not !is.na(): an "Uncertain" point is NOT a
    # reviewer reassignment, and testing NA alone would record every unplaceable
    # point as one.
    new$habitat_reassigned <- !.is_habitat_unassigned(new$main_habitat) &
      (.is_habitat_unassigned(bh) | bh != new$main_habitat)
  } else {
    new$habitat_reassigned <- !.is_habitat_unassigned(new$main_habitat)
    # Without `before` there is no way to tell a point whose habitat the
    # reviewer CHANGED from one they merely confirmed, so every non-NA
    # habitat is recorded as a reassignment and will be re-applied verbatim
    # on every later run -- freezing whatever the automatic classifier said
    # the day of the review. Warn rather than let a seeding script do this
    # silently.
    n_frozen <- sum(new$habitat_reassigned)
    if (n_frozen > 0L) {
      warning(sprintf(
        paste0(
          "save_spatial_review_decisions: `before` was not supplied, so %d point(s) with a ",
          "non-NA %s are recorded as habitat REASSIGNMENTS and will be re-applied verbatim on ",
          "every later run, freezing the automatic habitat for those points. Pass `before = ` ",
          "(the pre-review table) to record only genuine changes."
        ),
        n_frozen, habitat_col
      ), call. = FALSE)
    }
  }
  old <- if (file.exists(path)) readRDS(path) else new[0, ]
  # Kept correct for OLD files, which store NA and may predate the column.
  if (!"habitat_reassigned" %in% names(old)) {
    old$habitat_reassigned <- !.is_habitat_unassigned(old$main_habitat)
  }
  # A reassignment recorded earlier survives a later review that left it in place
  # (the gadget was opened on the already-applied table, so "unchanged" there
  # means "still the reassigned value", not "back to automatic").
  oi <- match(new$point_id, old$point_id)
  keep_old <- !is.na(oi) & old$habitat_reassigned[ifelse(is.na(oi), 1L, oi)] %in% TRUE &
    !.is_habitat_unassigned(new$main_habitat) &
    new$main_habitat == old$main_habitat[ifelse(is.na(oi), 1L, oi)]
  new$habitat_reassigned[keep_old] <- TRUE
  old <- old[!old$point_id %in% new$point_id, , drop = FALSE]
  out <- rbind(old[, names(new), drop = FALSE], new)
  rownames(out) <- NULL
  dir.create(dirname(path), showWarnings = FALSE, recursive = TRUE)
  saveRDS(out, path)
  message(sprintf("save_spatial_review_decisions: %d point decision(s) saved (%d new or updated) to %s.",
                  nrow(out), nrow(new), basename(path)))
  invisible(out)
}

#' Apply saved spatial-flag decisions before (or instead of) the gadget
#'
#' Overwrites \code{spatial_flag} on every row whose \code{point_id} has a
#' saved decision (and \code{main_habitat} where the decision was a reviewer
#' reassignment), marks the reason, and reports how
#' many flagged points still need a reviewer. Call it on
#' \code{\link{flag_habitat_inconsistencies}}'s output; open
#' \code{\link{review_spatial_flags}} only when
#' \code{attr(result, "n_pending_review") > 0} (or when you deliberately want
#' to re-review). A missing decisions file is not an error: nothing is
#' applied and every flagged point is pending.
#'
#' @details
#' A saved \code{spatial_flag} and a saved reassigned \code{main_habitat} are
#' both re-applied AS-IS -- neither is re-validated against the current run's
#' own automatic classification. If the automatic classifier's logic changes
#' between the run that produced a decision and a later run, the saved
#' decision still overwrites whatever the newer automatic classification
#' would have said, silently.
#'
#' @param occurrence_data Data frame from
#'   \code{\link{flag_habitat_inconsistencies}} (carries \code{point_id},
#'   \code{spatial_flag}, \code{spatial_flag_reason}, \code{main_habitat}).
#' @param path Character. The decisions file written by
#'   \code{\link{save_spatial_review_decisions}}.
#' @param point_id_col,flag_col,reason_col,habitat_col Column names.
#' @return \code{occurrence_data} with decisions applied and attributes
#'   \code{n_applied} (rows changed), \code{n_pending_review} (distinct
#'   points whose flag is not \code{"likely"} and that carry no decision) and
#'   \code{pending_point_ids}.
#' @seealso \code{\link{save_spatial_review_decisions}}
#' @export
apply_spatial_review_decisions <- function(occurrence_data, path,
                                           point_id_col = "point_id",
                                           flag_col = "spatial_flag",
                                           reason_col = "spatial_flag_reason",
                                           habitat_col = "main_habitat") {
  if (!is.data.frame(occurrence_data)) stop("apply_spatial_review_decisions: `occurrence_data` must be a data frame.", call. = FALSE)
  for (cc in c(point_id_col, flag_col, habitat_col)) {
    if (!cc %in% names(occurrence_data)) stop(sprintf("apply_spatial_review_decisions: `occurrence_data` has no column '%s'.", cc), call. = FALSE)
  }
  if (!is.character(path) || length(path) != 1L || is.na(path)) stop("apply_spatial_review_decisions: `path` must be a single file path.", call. = FALSE)
  pid <- as.character(occurrence_data[[point_id_col]])
  dec <- if (file.exists(path)) readRDS(path) else NULL
  n_applied <- 0L
  if (!is.null(dec) && nrow(dec) > 0L) {
    idx <- match(pid, dec$point_id)
    hit <- !is.na(idx)
    if (any(hit)) {
      if (!"habitat_reassigned" %in% names(dec)) {
        dec$habitat_reassigned <- !.is_habitat_unassigned(dec$main_habitat)
      }
      reassign <- hit & dec$habitat_reassigned[ifelse(is.na(idx), 1L, idx)] %in% TRUE
      .ne <- function(a, b) (is.na(a) != is.na(b)) | (!is.na(a) & !is.na(b) & a != b)
      changed <- (hit & .ne(occurrence_data[[flag_col]], dec$spatial_flag[idx])) |
        (reassign & .ne(occurrence_data[[habitat_col]], dec$main_habitat[idx]))
      occurrence_data[[flag_col]][hit] <- dec$spatial_flag[idx[hit]]
      occurrence_data[[habitat_col]][reassign] <- dec$main_habitat[idx[reassign]]
      if (reason_col %in% names(occurrence_data)) {
        occurrence_data[[reason_col]][hit] <- paste0(
          "reviewer decision (", dec$decided_at[idx[hit]], "); auto: ",
          occurrence_data[[reason_col]][hit])
      }
      n_applied <- sum(changed, na.rm = TRUE)
    }
  }
  decided <- if (is.null(dec)) character(0) else dec$point_id
  pending <- unique(pid[!is.na(occurrence_data[[flag_col]]) &
    occurrence_data[[flag_col]] != "likely" & !pid %in% decided])
  attr(occurrence_data, "n_applied") <- n_applied
  attr(occurrence_data, "n_pending_review") <- length(pending)
  attr(occurrence_data, "pending_point_ids") <- pending
  message(sprintf(
    "apply_spatial_review_decisions: %d saved decision(s) on file; %d row(s) changed by them; %d flagged point(s) still need review.",
    if (is.null(dec)) 0L else nrow(dec), n_applied, length(pending)))
  occurrence_data
}
