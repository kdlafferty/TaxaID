# ==============================================================================
# build_site_table.R
# TaxaMatch -- Unified long-format site table across match-object data types
#
# Exported functions:
#   build_site_table()   Extract or attach per-observation site info
#
# Internal helpers (@noRd):
#   .next_spatial_group_number()   Lowest unused "spatial_group_<n>" number
#   .default_exact_match_group_id()  Group rows sharing an exact (lat, lon)
# ==============================================================================

# .next_spatial_group_number()
#
# Shared by build_site_table()'s default assignment and
# .assign_spatial_groups_from_polygons() (group_observations_by_bbox.R):
# both mint "spatial_group_<n>" labels, and must never collide with each
# other's numbering. Scans whatever spatial_group_id values already exist
# and returns one past the highest "spatial_group_<n>" number found (1L if
# none) -- so a fresh call to build_site_table() and a later interactive
# grouping call always get non-overlapping numbers, without either function
# needing to know anything about the other's own counter.
#' @noRd
.next_spatial_group_number <- function(existing_ids) {
  nums <- suppressWarnings(as.integer(sub("^spatial_group_", "", existing_ids)))
  nums <- nums[!is.na(nums)]
  if (length(nums) == 0L) return(1L)
  max(nums) + 1L
}

# .default_exact_match_group_id()
#
# Session 139: spatial_group_id's default (before any interactive grouping)
# used to be the row's own observation_id -- meaning a genuine multi-site
# observation's own several sites all defaulted to ONE shared group, purely
# because they belong to the same observation, regardless of whether they
# are actually near each other. spatial_group_id is meant to be a LOCATION
# property (do these coordinates belong to the same neighborhood?), not an
# observation property.
#
# Groups rows by EXACT (lat, lon) equality -- not grid-snapping/binning.
# Deliberately no distance tolerance or bin resolution parameter: in this
# ecosystem's actual data flow, shared coordinates come from a site-metadata
# lookup table join (e.g. TaxaMatch::join_event_site_metadata()'s
# SAMPLE_SITE_METADATA pattern), not raw continuous GPS with measurement
# noise -- two rows genuinely share a site if and only if they were joined
# from the same site-metadata row, which means their lat/lon are exactly
# equal, not merely close. An earlier grid-snapping design (rounding to a
# fixed resolution, e.g. 0.1 degrees) was tried and rejected after live
# testing against this template's own bundled data: with a 0.1-degree bin,
# four genuinely distinct observations (three different real/fallback
# coordinates within ~11km of each other) collapsed into one default group,
# reintroducing the exact "swept into an unrelated cluster" ambiguity this
# whole redesign was meant to avoid -- and picking a "correct" bin size is
# not well-posed in general (it depends on how close together a given
# study's real sites happen to be). Exact match has no such tuning parameter
# and no such failure mode.
#' @noRd
.default_exact_match_group_id <- function(lat, lon) {
  key       <- paste(lat, lon, sep = "|")
  uniq_keys <- unique(key)
  labels    <- sprintf("spatial_group_%d",
                       seq(.next_spatial_group_number(character(0)),
                           length.out = length(uniq_keys)))
  labels[match(key, uniq_keys)]
}

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
#'   \code{spatial_group_id}, \code{spatial_group_N}, and
#'   \code{is_default_group}. \code{spatial_group_id} defaults to
#'   \code{"spatial_group_<n>"}, grouping rows that share an \strong{exact}
#'   \code{(lat, lon)} pair (see Details), and \code{spatial_group_N} to the
#'   count of rows sharing that default label -- until
#'   \code{\link[TaxaMatch]{group_observations_by_bbox}} (or
#'   \code{\link[TaxaMatch]{assign_spatial_group}}) updates them in place for
#'   whichever observations get grouped. \code{is_default_group} is
#'   \code{TRUE} for every row until one of those two functions reassigns it;
#'   this is the marker they use to know which rows are still eligible to be
#'   captured by a newly drawn box or manual assignment, so they never need to
#'   re-derive "is this still a default" from \code{spatial_group_id}'s
#'   contents. This guarantees every site table has valid, non-missing
#'   \code{spatial_group_id}/\code{spatial_group_N}/\code{is_default_group}
#'   values from the moment it is built, even before any grouping step runs.
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
#' \strong{Why the default spatial_group_id is location-based, not
#' observation-based (Session 139):} \code{spatial_group_id} is meant to
#' answer "do these coordinates belong to the same neighborhood," a property
#' of \emph{location}, not of which observation happens to own a row.
#' Defaulting it to \code{observation_id} (the pre-Session-139 behavior)
#' meant a genuine multi-site observation's own several sites always
#' defaulted to one shared group purely because they share an observation --
#' regardless of whether those sites were actually near each other -- while
#' two genuinely co-located observations were never grouped by default at
#' all, contradicting this ecosystem's own stated design principle that
#' clustering should be a geometric property of coordinates. The exact-match
#' default fixes both: two of one observation's own sites at different real
#' coordinates now default to different groups (as they should), and two
#' different observations sharing the exact same coordinate (typically
#' because both were joined from the same site-metadata row -- e.g.
#' \code{\link{join_event_site_metadata}}'s pattern) now default to the same
#' group (also as they should) -- \code{\link[TaxaMatch]{group_observations_by_bbox}}'s
#' interactive step remains available as a refinement/override on top of this
#' more sensible default, not the only mechanism that ever creates a shared
#' group.
#'
#' \strong{Why exact match, not grid-snapping/binning to a fixed resolution
#' (also Session 139):} a grid-snapping design (rounding coordinates to a
#' fixed bin size) was tried first and rejected after live testing against
#' this ecosystem's own bundled example data. A 0.1-degree bin collapsed four
#' genuinely distinct observations (a real sample coordinate and a
#' fallback/placeholder coordinate that happened to sit within ~11km of each
#' other) into one default group -- reintroducing the exact "swept into an
#' unrelated cluster" ambiguity this whole redesign exists to avoid. Choosing
#' a "correct" bin size is not well-posed in general: it depends on how close
#' together a given study's real sites happen to be, which this function has
#' no way to know in advance. In this ecosystem's actual data flow, two
#' coordinates that are supposed to represent the same site come from the
#' same site-metadata lookup row (exactly equal), not from independent noisy
#' GPS reads of the same physical spot (nearly, but not exactly, equal) -- so
#' exact match is both simpler and the semantically correct comparison here,
#' with no tuning parameter and no equivalent failure mode.
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
    out$spatial_group_id  <- .default_exact_match_group_id(out$lat, out$lon)
    tab <- table(out$spatial_group_id)
    out$spatial_group_N   <- as.integer(tab[out$spatial_group_id])
    out$is_default_group  <- TRUE

    return(tibble::as_tibble(
      out[, c(id_col, "lat", "lon", "observed_on", "spatial_group_id",
              "spatial_group_N", "is_default_group"), drop = FALSE]
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
  out$spatial_group_id <- .default_exact_match_group_id(out$lat, out$lon)
  tab <- table(out$spatial_group_id)
  out$spatial_group_N  <- as.integer(tab[out$spatial_group_id])
  out$is_default_group <- TRUE

  tibble::as_tibble(
    out[, c(id_col, "lat", "lon", "observed_on", "spatial_group_id",
            "spatial_group_N", "is_default_group"), drop = FALSE]
  )
}
