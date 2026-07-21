utils::globalVariables(c(
  "species", "speciesKey", "decimalLongitude", "decimalLatitude"
))

# ==============================================================================
# check_geographic_outliers.R
# TaxaFetch -- flag bbox-scoped occurrence records that are geographic
# outliers relative to a species' own global GBIF distribution
# ==============================================================================

#' Flag Geographically Isolated Occurrence Records Against a Species' Global Range
#'
#' A bbox-scoped GBIF search (see \code{\link{get_gbif_occurrences}}) can
#' return a single occurrence for a species that is genuinely absent from
#' the study region -- a misidentification, mislabeled specimen, or bad
#' georeference elsewhere in GBIF, sitting far from that species' real
#' range. This function targets exactly that case: for species with few
#' local records, it fetches that species' unrestricted global GBIF
#' occurrences (\code{geometry = NULL}, see \code{\link{fetch_gbif_occurrences}})
#' and tests whether the local record(s) are geographic outliers against
#' that global cloud, via \code{CoordinateCleaner::cc_outl()}. Species with
#' enough local support are never checked -- the global fetch is the
#' expensive step, and a well-supported local species doesn't need it.
#'
#' @param local_occurrences A data frame of bbox-scoped GBIF occurrence
#'   records (e.g. the output of \code{\link{get_gbif_occurrences}} or
#'   \code{\link{filter_gbif_quality}}). Must contain \code{gbifID},
#'   \code{species}, \code{speciesKey}, \code{decimalLatitude}, and
#'   \code{decimalLongitude}.
#' @param min_local_n Integer. Species with fewer than this many records in
#'   \code{local_occurrences} are checked against their global distribution.
#'   Species at or above this count are left untested. Default \code{5L}.
#' @param min_occs Integer. Minimum number of geographically unique global
#'   datapoints required before a species is actually tested by
#'   \code{cc_outl()} -- below this, dispersion statistics are unreliable
#'   and the species is reported as untested rather than silently passed.
#'   Matches \code{CoordinateCleaner::cc_outl()}'s own default. Default
#'   \code{7L}.
#' @param method Character. \code{cc_outl()}'s outlier-detection method:
#'   \code{"distance"} (default here) flags a record whose nearest-neighbour
#'   distance to another same-species record exceeds \code{tdi} -- the most
#'   directly interpretable choice for "isolated from every cluster."
#'   \code{"quantile"} and \code{"mad"} are also available; see
#'   \code{CoordinateCleaner::cc_outl()} for their definitions. Only one of
#'   \code{tdi} (for \code{"distance"}) or \code{mltpl} (for
#'   \code{"quantile"}/\code{"mad"}) is used, depending on \code{method}.
#' @param tdi Numeric. Distance threshold in km, used only when
#'   \code{method = "distance"}. Matches \code{cc_outl()}'s own default,
#'   \code{1000}.
#' @param mltpl Numeric. Interquartile-range/MAD multiplier, used only when
#'   \code{method = "quantile"} or \code{"mad"}. Matches \code{cc_outl()}'s
#'   own default, \code{5}.
#' @param year_range Character. Year range for the global GBIF fetch,
#'   \code{"YYYY,YYYY"}. Default \code{"2000,2024"}, matching
#'   \code{\link{fetch_gbif_occurrences}}'s own default. The global fetch
#'   characterizes the species' broader distribution, not just the local
#'   study window -- widen this if a narrow year range risks under-sampling
#'   a species' real range.
#' @param cache_dir Character or \code{NULL}. Forwarded to
#'   \code{\link{fetch_gbif_occurrences}} for checkpointing the global
#'   fetch. Default \code{tools::R_user_dir("TaxaFetch", "cache")}.
#' @param verbose Logical. Forwarded to \code{cc_outl()}. Default
#'   \code{FALSE}.
#'
#' @return \code{local_occurrences} with three columns added:
#'   \describe{
#'     \item{\code{local_n}}{Number of records for this species in
#'       \code{local_occurrences}.}
#'     \item{\code{global_n_unique}}{Number of geographically unique global
#'       records found for this species. \code{NA} for species never
#'       checked (\code{local_n >= min_local_n}).}
#'     \item{\code{outlier_status}}{One of \code{"not_tested_sufficient_local_data"}
#'       (local_n >= min_local_n, never checked), \code{"insufficient_global_data"}
#'       (checked, but fewer than \code{min_occs} unique global points --
#'       cannot compute a reliable dispersion statistic),
#'       \code{"outlier"} (flagged by \code{cc_outl()}), or
#'       \code{"consistent"} (checked, not flagged). Never a bare logical --
#'       "not tested" and "tested and passed" are kept distinct throughout,
#'       mirroring \code{\link{check_inat_range}}'s \code{range_status}
#'       convention.}
#'   }
#'
#' @details
#' \strong{Why this needs a global fetch at all:} \code{local_occurrences}
#' comes from a bbox-scoped GBIF search, so a species with one local record
#' has nothing else in the same dataset to compare it against --
#' \code{cc_outl()} needs a real distribution, not one point. The global
#' fetch is gated to only the species below \code{min_local_n}, since a
#' well-supported local species needs no such check and the global fetch is
#' the expensive step. This is a targeted, per-species-rare extension of
#' \code{\link{fetch_gbif_occurrences}} (\code{geometry = NULL}) -- see that
#' function for rate-limit/retry/checkpoint behavior, all inherited
#' unchanged here.
#'
#' \strong{\code{min_occs} is a real floor, not a formality:} a species
#' with too few unique global points (even after the global fetch) simply
#' cannot support a reliable outlier test -- \code{cc_outl()} itself passes
#' such species by default rather than testing them. This function makes
#' that distinction explicit via \code{"insufficient_global_data"} rather
#' than folding it into \code{"consistent"}, so a downstream consumer never
#' mistakes "we couldn't check" for "we checked and it's fine."
#'
#' \strong{\code{cc_outl()} is called once per species, not once for the
#' whole batch:} confirmed on real production data (2026-07-20) that its
#' \code{"distance"} method silently switches EVERY species in a single call
#' to a coarser raster approximation whenever ANY ONE species in that call
#' has 10,000 or more records. A species rare in the local bbox can still be
#' globally common, so calling \code{cc_outl()} once across every rare
#' species let one common species silently degrade every other species'
#' precision -- this cleared a real, obvious ~9,000 km outlier (a Mugu
#' \emph{Pseudotolithus epipercus} record) on first live use. Per-species
#' calls scope that raster decision to each species' own record count,
#' where it belongs; the extra R-level call overhead is negligible next to
#' the GBIF fetch itself.
#'
#' @seealso \code{\link{fetch_gbif_occurrences}}, \code{\link{get_gbif_occurrences}},
#'   \code{\link{filter_gbif_quality}}, \code{\link{check_inat_range}}
#'
#' @importFrom dplyr count distinct
#' @export
#'
#' @examples
#' \dontrun{
#' occ <- get_gbif_occurrences(keys = valid_keys, geometry = bbox)
#' occ <- filter_gbif_quality(occ)
#' occ <- check_geographic_outliers(occ, min_local_n = 5L)
#' occ[occ$outlier_status == "outlier", ]
#' }
check_geographic_outliers <- function(
    local_occurrences,
    min_local_n = 5L,
    min_occs    = 7L,
    method      = "distance",
    tdi         = 1000,
    mltpl       = 5,
    year_range  = "2000,2024",
    cache_dir   = tools::R_user_dir("TaxaFetch", "cache"),
    verbose     = FALSE
) {

  # --- Dependency check ---------------------------------------------------
  if (!requireNamespace("CoordinateCleaner", quietly = TRUE)) {
    stop(
      "check_geographic_outliers: package 'CoordinateCleaner' is required.\n",
      "Install it with: install.packages('CoordinateCleaner')"
    )
  }

  # --- Input checks ---------------------------------------------------------
  if (!is.data.frame(local_occurrences)) {
    stop("check_geographic_outliers: 'local_occurrences' must be a data frame.")
  }
  required_cols <- c("gbifID", "species", "speciesKey",
                     "decimalLatitude", "decimalLongitude")
  missing_cols <- setdiff(required_cols, names(local_occurrences))
  if (length(missing_cols) > 0L) {
    stop("check_geographic_outliers: missing required column(s): ",
         paste(missing_cols, collapse = ", "))
  }

  local_occurrences$global_n_unique <- NA_integer_
  local_occurrences$outlier_status  <- "not_tested_sufficient_local_data"

  local_counts <- dplyr::count(local_occurrences, species, name = "local_n")
  local_occurrences$local_n <- local_counts$local_n[
    match(local_occurrences$species, local_counts$species)
  ]

  rare_species <- local_counts$species[local_counts$local_n < min_local_n]

  if (length(rare_species) == 0L) {
    message("check_geographic_outliers: every species clears min_local_n -- nothing to check.")
    return(local_occurrences)
  }

  is_rare_row <- local_occurrences$species %in% rare_species

  rare_keys <- unique(local_occurrences$speciesKey[is_rare_row])
  rare_keys <- rare_keys[!is.na(rare_keys)]

  if (length(rare_keys) == 0L) {
    message(
      "check_geographic_outliers: ", length(rare_species),
      " rare species have no usable speciesKey -- cannot fetch global data."
    )
    local_occurrences$outlier_status[is_rare_row] <- "insufficient_global_data"
    return(local_occurrences)
  }

  message(sprintf(
    paste0(
      "check_geographic_outliers: %d/%d species have fewer than %d local ",
      "record(s) -- fetching global GBIF occurrences for outlier testing."
    ),
    length(rare_species), length(unique(local_occurrences$species)), min_local_n
  ))

  global_occ <- fetch_gbif_occurrences(
    keys       = rare_keys,
    geometry   = NULL,
    year_range = year_range,
    cache_dir  = cache_dir
  )

  if (nrow(global_occ) == 0L) {
    local_occurrences$outlier_status[is_rare_row] <- "insufficient_global_data"
    return(local_occurrences)
  }

  global_counts <- global_occ |>
    dplyr::distinct(species, decimalLongitude, decimalLatitude) |>
    dplyr::count(species, name = "global_n_unique")

  global_occ$.global_n_unique <- global_counts$global_n_unique[
    match(global_occ$species, global_counts$species)
  ]

  # cc_outl() is called ONCE PER SPECIES, not once for the whole combined
  # batch -- confirmed on real production data (2026-07-20) that its
  # "distance" method silently switches EVERY species in a single call to a
  # coarser raster approximation whenever ANY ONE species in that call has
  # >=10,000 records (CoordinateCleaner::cc_outl's own
  # `if (any(record_numbers >= 10000)) { warning("Using raster
  # approximation.") ... }`, scoped to the whole call, not per species). A
  # locally-rare species can still be globally common, so batching every
  # rare species into one cc_outl() call let one common species silently
  # degrade every other species' precision -- this cleared a real, obvious
  # ~9,000 km outlier (a Mugu Pseudotolithus epipercus record) that a
  # per-species call correctly flags. Per-species calls scope that raster
  # decision to each species' own record count, where it belongs.
  #
  # cc_outl() also warns about species below min_occs -- suppressed here
  # because check_geographic_outliers() already reports that per-row and
  # explicitly via outlier_status = "insufficient_global_data", not just to
  # the console.
  cc_pass <- rep(NA, nrow(global_occ))
  for (sp in unique(global_occ$species)) {
    sp_rows <- which(global_occ$species == sp)
    cc_pass[sp_rows] <- suppressWarnings(CoordinateCleaner::cc_outl(
      x        = global_occ[sp_rows, , drop = FALSE],
      lon      = "decimalLongitude",
      lat      = "decimalLatitude",
      species  = "species",
      method   = method,
      mltpl    = mltpl,
      tdi      = tdi,
      min_occs = min_occs,
      value    = "flagged",
      verbose  = verbose
    ))
  }
  global_occ$.cc_pass <- cc_pass

  match_pos <- match(local_occurrences$gbifID[is_rare_row], global_occ$gbifID)

  matched_n_unique <- global_occ$.global_n_unique[match_pos]
  matched_cc_pass   <- global_occ$.cc_pass[match_pos]

  status <- ifelse(
    is.na(matched_n_unique) | matched_n_unique < min_occs,
    "insufficient_global_data",
    ifelse(matched_cc_pass, "consistent", "outlier")
  )

  local_occurrences$global_n_unique[is_rare_row] <- matched_n_unique
  local_occurrences$outlier_status[is_rare_row]  <- status

  local_occurrences
}
