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
# human decision, not a computed intermediate. Every production workflow used
# to re-open the gadget on every run and overwrite the previous decisions
# (found 2026-09-12; the same class of gap the search polygon had before it was
# persisted). These two helpers keep one small table per site, keyed on
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
#' @param point_id_col,flag_col,habitat_col Column names. Defaults match
#'   \code{review_spatial_flags()}'s output.
#' @return Invisibly, the merged decisions table (\code{point_id},
#'   \code{spatial_flag}, \code{main_habitat}, \code{decided_at}).
#' @seealso \code{\link{apply_spatial_review_decisions}}
#' @export
save_spatial_review_decisions <- function(reviewed, path,
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
  old <- if (file.exists(path)) readRDS(path) else new[0, ]
  old <- old[!old$point_id %in% new$point_id, , drop = FALSE]
  out <- rbind(old, new)
  rownames(out) <- NULL
  dir.create(dirname(path), showWarnings = FALSE, recursive = TRUE)
  saveRDS(out, path)
  message(sprintf("save_spatial_review_decisions: %d point decision(s) saved (%d new or updated) to %s.",
                  nrow(out), nrow(new), basename(path)))
  invisible(out)
}

#' Apply saved spatial-flag decisions before (or instead of) the gadget
#'
#' Overwrites \code{spatial_flag} and \code{main_habitat} on every row whose
#' \code{point_id} has a saved decision, marks the reason, and reports how
#' many flagged points still need a reviewer. Call it on
#' \code{\link{flag_habitat_inconsistencies}}'s output; open
#' \code{\link{review_spatial_flags}} only when
#' \code{attr(result, "n_pending_review") > 0} (or when you deliberately want
#' to re-review). A missing decisions file is not an error: nothing is
#' applied and every flagged point is pending.
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
      changed <- hit & (is.na(occurrence_data[[flag_col]]) |
        occurrence_data[[flag_col]] != dec$spatial_flag[idx] |
        is.na(occurrence_data[[habitat_col]]) |
        occurrence_data[[habitat_col]] != dec$main_habitat[idx])
      occurrence_data[[flag_col]][hit] <- dec$spatial_flag[idx[hit]]
      occurrence_data[[habitat_col]][hit] <- dec$main_habitat[idx[hit]]
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
