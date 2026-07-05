# ==============================================================================
# build_site_table.R
# TaxaMatch -- Unified long-format site table across match-object data types
#
# Exported functions:
#   build_site_table()   Extract or attach per-observation site info
# ==============================================================================

#' Build a Unified Long-Format Site Table
#'
#' Produces one standardized site table -- \code{observation_id}, \code{lat},
#' \code{lon}, \code{observed_on} -- regardless of which data-type pathway
#' produced \code{match_df}. This closes a contract gap across the three
#' pathways: \code{\link{score_image_inat}}'s output already carries
#' per-observation \code{lat}/\code{lng}/\code{observed_on}, but
#' \code{\link{standardize_match_data}} (DNA/BLAST) and
#' \code{\link{read_birdnet_output}} (acoustic) carry neither -- for those,
#' site information must be supplied separately via \code{site_df}.
#'
#' @param match_df A match-object data frame from any TaxaMatch ingest
#'   function (\code{\link{score_image_inat}}, \code{\link{read_birdnet_output}},
#'   \code{\link{standardize_match_data}}, ...).
#' @param site_df Data frame with (at minimum) \code{id_col}, \code{lat}, and
#'   \code{lon} columns, required when \code{match_df} has no embedded
#'   \code{lat}/\code{lng}. Optional \code{observed_on} column. \strong{May
#'   have more than one row per \code{id_col} value} -- this is the correct
#'   shape for a sequence ASV genuinely detected at several real sample
#'   sites (the same \code{observation_id} legitimately gets one row per
#'   site); do not pre-collapse to one row per observation before calling.
#'   Ignored (with a warning) when \code{match_df} already carries embedded
#'   site info.
#' @param id_col Character. Observation ID column name, present in both
#'   \code{match_df} and \code{site_df}. Default \code{"observation_id"}.
#'
#' @return A tibble in long format: one row per \code{(observation_id, site)}
#'   pair actually present in \code{match_df}, with columns \code{id_col},
#'   \code{lat}, \code{lon}, \code{observed_on} (\code{NA} where unknown),
#'   \code{spatial_group_id}, and \code{spatial_group_N}. The two
#'   \code{spatial_group_*} columns start out as "every observation is its
#'   own singleton group" -- \code{spatial_group_id} defaults to the row's own
#'   \code{id_col} value and \code{spatial_group_N} to \code{1L} -- until
#'   \code{\link[TaxaMatch]{group_observations_by_bbox}} (or
#'   \code{\link[TaxaMatch]{assign_spatial_group}}) updates them in place for
#'   whichever observations get grouped. This guarantees every site table has
#'   valid, non-missing \code{spatial_group_id}/\code{spatial_group_N} values
#'   from the moment it is built, even before any grouping step runs.
#'
#' @details
#' \strong{Why site info can't just be joined in generically:} the image
#' pathway embeds site info directly in the match object (one value per
#' image); the acoustic pathway's BirdNET-Analyzer CSV output carries no site
#' metadata at all (confirmed directly in \code{read_birdnet_output()}'s
#' columns -- only detection window start/end times and the source
#' filename); the DNA/BLAST pathway's \code{observation_id} is an ASV
#' identifier that can be genuinely detected at multiple real sites within
#' one sequencing run. \code{site_df} is therefore required (not derived)
#' for the acoustic and DNA/BLAST pathways -- callers must build it from
#' whatever recording-filename or sample-metadata convention their own study
#' uses.
#'
#' @seealso \code{\link{score_image_inat}}, \code{\link{read_birdnet_output}},
#'   \code{\link{standardize_match_data}}
#'
#' @examples
#' # Image pathway: site info already embedded, extracted directly
#' img_matches <- data.frame(
#'   observation_id = c("IMG_001", "IMG_002"),
#'   lat = c(34.41, 34.41), lng = c(-119.86, -119.86),
#'   observed_on = c("2024-06-01", "2024-06-01")
#' )
#' build_site_table(img_matches)
#'
#' # Acoustic/DNA pathway: site info supplied externally, multi-site OK
#' asv_matches <- data.frame(observation_id = c("ASV1", "ASV1", "ASV2"))
#' site_info <- data.frame(
#'   observation_id = c("ASV1", "ASV1", "ASV2"),
#'   lat = c(34.41, 36.60, 34.41), lon = c(-119.86, -121.90, -119.86)
#' )
#' build_site_table(asv_matches, site_df = site_info)
#'
#' @export
build_site_table <- function(match_df, site_df = NULL, id_col = "observation_id") {

  if (!is.data.frame(match_df) || nrow(match_df) == 0L)
    stop("build_site_table: 'match_df' must be a non-empty data frame.", call. = FALSE)
  if (!id_col %in% names(match_df))
    stop(sprintf("build_site_table: 'match_df' missing id column '%s'.", id_col), call. = FALSE)

  has_embedded <- all(c("lat", "lng") %in% names(match_df))

  if (has_embedded) {
    if (!is.null(site_df))
      warning(
        "build_site_table: 'match_df' already carries embedded lat/lng; ",
        "ignoring supplied 'site_df'.",
        call. = FALSE
      )

    keep <- c(id_col, "lat", "lng",
             if ("observed_on" %in% names(match_df)) "observed_on")
    out  <- unique(match_df[, keep, drop = FALSE])
    names(out)[names(out) == "lng"] <- "lon"
    if (!"observed_on" %in% names(out)) out$observed_on <- NA_character_
    out$spatial_group_id <- as.character(out[[id_col]])
    out$spatial_group_N  <- 1L

    return(tibble::as_tibble(
      out[, c(id_col, "lat", "lon", "observed_on", "spatial_group_id", "spatial_group_N"), drop = FALSE]
    ))
  }

  if (is.null(site_df))
    stop(
      "build_site_table: this match object has no embedded site info. ",
      "Supply 'site_df' with '", id_col, "', 'lat', and 'lon' columns ",
      "(one or more rows per observation).",
      call. = FALSE
    )

  required <- c(id_col, "lat", "lon")
  missing  <- setdiff(required, names(site_df))
  if (length(missing) > 0L)
    stop(sprintf(
      "build_site_table: 'site_df' missing required column(s): %s",
      paste(missing, collapse = ", ")
    ), call. = FALSE)

  ids       <- unique(match_df[[id_col]])
  unmatched <- setdiff(ids, unique(site_df[[id_col]]))
  if (length(unmatched) > 0L)
    warning(sprintf(
      "build_site_table: %d observation(s) in 'match_df' have no matching row in 'site_df': %s",
      length(unmatched),
      paste(utils::head(unmatched, 5L), collapse = ", ")
    ), call. = FALSE)

  out <- site_df[site_df[[id_col]] %in% ids, , drop = FALSE]
  if (!"observed_on" %in% names(out)) out$observed_on <- NA_character_
  out$spatial_group_id <- as.character(out[[id_col]])
  out$spatial_group_N  <- 1L

  tibble::as_tibble(
    out[, c(id_col, "lat", "lon", "observed_on", "spatial_group_id", "spatial_group_N"), drop = FALSE]
  )
}
