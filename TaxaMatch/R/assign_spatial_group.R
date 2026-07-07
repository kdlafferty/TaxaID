# ==============================================================================
# assign_spatial_group.R
# TaxaMatch -- Manual spatial_group_id assignment
#
# Exported functions:
#   assign_spatial_group()   Validating manual spatial_group_id setter
# ==============================================================================

#' Manually Assign a Spatial Group to a Set of Observations
#'
#' Sets \code{spatial_group_id} directly for a named set of observations --
#' for a study where the grouping is already known from metadata, or to
#' hand-correct a few observations after
#' \code{\link{group_observations_by_bbox}}'s interactive step -- without
#' drawing boxes. Guards against the one way this could silently corrupt an
#' existing group: if \code{spatial_group_id} is already in use by an
#' observation \strong{not} named in this call, that would silently expand
#' an unrelated group's membership the next time anyone counts by
#' \code{spatial_group_id}. This function stops instead, so the caller can
#' either include that observation explicitly or choose a different id.
#'
#' @param sites Data frame with (at least) \code{id_col},
#'   \code{spatial_group_id}, and \code{spatial_group_N} columns -- typically
#'   the output of \code{\link{build_site_table}} or
#'   \code{\link{group_observations_by_bbox}}.
#' @param observation_ids Character vector of \code{id_col} values to assign
#'   to \code{spatial_group_id}. Must all already exist in \code{sites}.
#' @param spatial_group_id Character. Single, non-empty group id to assign.
#'   Can be a new id or an existing one (to add members to an already-formed
#'   group); see Details for the collision guard.
#' @param id_col Character. Observation ID column name. Default
#'   \code{"observation_id"}.
#'
#' @return \code{sites} with \code{spatial_group_id} set to
#'   \code{spatial_group_id} for the named observations, \code{spatial_group_N}
#'   recomputed for that group so it stays in sync, and (when present)
#'   \code{is_default_group} set to \code{FALSE} for the named observations --
#'   they are no longer eligible to be captured by a future
#'   \code{\link{group_observations_by_bbox}} call. All other rows are
#'   unaffected.
#'
#' @details
#' \strong{Collision guard:} before assigning, checks whether
#' \code{spatial_group_id} is already used by any observation \emph{outside}
#' \code{observation_ids}. If so, stops with an error naming those
#' observations -- silently pulling in an unintended extra member is worse
#' than a hard stop, since nothing downstream would notice the mistake until
#' a fetch or a prior update used the wrong local species pool.  To
#' genuinely merge groups, include every observation you want in the merged
#' group in \code{observation_ids}.
#'
#' @seealso \code{\link{build_site_table}}, \code{\link{group_observations_by_bbox}}
#'
#' @examples
#' sites <- data.frame(
#'   observation_id   = paste0("obs", 1:4),
#'   lat              = c(34.40, 34.41, 36.60, 40.71),
#'   lon              = c(-119.86, -119.85, -121.90, -74.00),
#'   spatial_group_id = paste0("obs", 1:4),
#'   spatial_group_N  = 1L,
#'   stringsAsFactors = FALSE
#' )
#' # Known from metadata: obs1 and obs2 were collected at the same site
#' assign_spatial_group(sites, c("obs1", "obs2"), "spatial_group_1")
#'
#' @export
assign_spatial_group <- function(sites, observation_ids, spatial_group_id,
                                 id_col = "observation_id") {

  if (!is.data.frame(sites) || nrow(sites) == 0L)
    stop("assign_spatial_group: 'sites' must be a non-empty data frame.", call. = FALSE)

  required <- c(id_col, "spatial_group_id", "spatial_group_N")
  missing  <- setdiff(required, names(sites))
  if (length(missing) > 0L)
    stop(sprintf(
      "assign_spatial_group: 'sites' missing required column(s): %s. Run build_site_table() first.",
      paste(missing, collapse = ", ")
    ), call. = FALSE)

  if (length(observation_ids) == 0L || anyNA(observation_ids))
    stop("assign_spatial_group: 'observation_ids' must be a non-empty vector with no NAs.", call. = FALSE)

  if (!is.character(spatial_group_id) || length(spatial_group_id) != 1L ||
      is.na(spatial_group_id) || !nzchar(spatial_group_id))
    stop("assign_spatial_group: 'spatial_group_id' must be a single non-NA, non-empty string.", call. = FALSE)

  observation_ids <- unique(as.character(observation_ids))
  missing_ids <- setdiff(observation_ids, sites[[id_col]])
  if (length(missing_ids) > 0L)
    stop(sprintf(
      "assign_spatial_group: observation_id(s) not found in 'sites': %s",
      paste(missing_ids, collapse = ", ")
    ), call. = FALSE)

  target_rows <- sites[[id_col]] %in% observation_ids

  colliding <- sites[[id_col]][!target_rows & sites$spatial_group_id == spatial_group_id]
  if (length(colliding) > 0L)
    stop(sprintf(
      paste0(
        "assign_spatial_group: spatial_group_id '%s' is already used by observation(s) not ",
        "named in this call: %s. Include them in 'observation_ids' to merge groups, or choose ",
        "a different spatial_group_id."
      ),
      spatial_group_id, paste(colliding, collapse = ", ")
    ), call. = FALSE)

  sites$spatial_group_id[target_rows] <- spatial_group_id
  sites$spatial_group_N[sites$spatial_group_id == spatial_group_id] <-
    sum(sites$spatial_group_id == spatial_group_id)
  if ("is_default_group" %in% names(sites))
    sites$is_default_group[target_rows] <- FALSE

  sites
}
