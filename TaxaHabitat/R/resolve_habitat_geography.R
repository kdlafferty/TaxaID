# ==============================================================================
# Resolve an unassigned habitat from where the point actually is
# ==============================================================================

#' Can this habitat exist in this physical zone?
#'
#' Admissibility is decided at HABITAT level, not realm level, because realm is
#' too coarse for the case that motivates this. A gull's candidates are
#' typically `Estuarine | Freshwater | Marine`; over open ocean both Estuarine
#' and Marine are "marine realm", so a realm rule finds two matches and gives
#' up, when the answer is plainly Marine. Estuarine is a transitional COASTAL
#' habitat and does not occur in open water.
#'
#' Derived from the package's own realm vocabulary rather than a hard-coded
#' habitat list, so it survives a site using a different scheme.
#'
#' @param hab Character vector of habitat names.
#' @param zone One of `"ocean"`, `"inland"`, `"coastal"`.
#' @return Logical vector, one per habitat.
#' @noRd
.habitat_admissible <- function(hab, zone) {
  h <- tolower(trimws(hab))
  is_marine <- grepl(.marine_name_pattern, h, perl = TRUE)
  is_estuar <- grepl("\\b(estuary|estuarine|estuaries)\\b", h, perl = TRUE)
  switch(zone,
    ocean   = is_marine & !is_estuar,
    inland  = !is_marine,
    coastal = rep(TRUE, length(h)),
    rep(FALSE, length(h))
  )
}

#' Resolve Unassigned Habitats From Point Geography
#'
#' Fills in `main_habitat` for points the assemblage consensus could not
#' resolve, by asking where the point actually is. A taxon whose weights span
#' freshwater, estuarine and marine is not uncertain about its habitat -- it
#' uses all three -- so over open ocean it is marine, and inland it is not.
#' The consensus threshold cannot express that, because it never sees the
#' location.
#'
#' Only points with **exactly one** admissible candidate are resolved. A point
#' at the shoreline, where the map cannot separate marine from estuarine from
#' terrestrial, is left unassigned deliberately: that is a real ambiguity and
#' belongs in [review_spatial_flags()], not in an automatic rule.
#'
#' @section What resolves, and what does not:
#' \describe{
#'   \item{ocean}{Only a marine, non-estuarine candidate.}
#'   \item{inland}{Any non-marine candidate. Resolves only when one such
#'     candidate exists -- a `Freshwater | Terrestrial` point inland stays
#'     ambiguous, because without a lake or river layer the map cannot tell a
#'     pond from a hillside.}
#'   \item{coastal}{Nothing. Every habitat is admissible within
#'     `coast_buffer_m` of the shore, so geography discriminates nothing.}
#' }
#' **Measured on the full production PtConception 12S pool** (220,311 points,
#' 31,383 unassigned): **6,222 points resolved, 20%** -- 2,940 ocean, 3,282
#' inland -- leaving 25,161 where geography discriminates nothing. 5.9 seconds.
#'
#' A 6,523-point coastal extract of the same site gave 34% (221 of 646), and
#' that figure was previously quoted here. It is **not representative**: the
#' extract is coastal-heavy, and its unassigned points are Cottidae, whereas
#' production's are 97%-by-record birds (Laridae, Anatidae, Gaviidae). Quote
#' the production number. The general lesson is that a fixture chosen for
#' convenience validated the mechanism without exercising the case that
#' matters.
#'
#' What it resolves in production is itself worth knowing: **27,400 records, of
#' which 97% are birds** -- Laridae 17,737, Anatidae 3,095, Gaviidae 2,399,
#' Phalacrocoracidae 2,004. Those records are currently excluded from the
#' resident prior only because their habitat is unassigned, which is an
#' accident rather than a scope decision. If birds are out of scope for the
#' marker, filter families before the fetch; do not rely on this function
#' declining to resolve them. Note also that the remaining 467,614 unassigned
#' records stay unassigned -- most bird records sit at coastal points, where
#' nothing resolves -- so the volume entering the prior is far smaller than the
#' unassigned pool's size suggests.
#'
#' @section Provenance:
#' A resolved point gets `habitat_source = "geography"`; a point the consensus
#' had already settled keeps `"consensus"`. A geography-resolved habitat is a
#' weaker claim than an assemblage consensus and it feeds habitat-stratified
#' priors, so the distinction is recorded in the data rather than left to be
#' inferred. The point's `habitat_proportions` vector is **not** rewritten --
#' the taxon really does use those habitats; only `main_habitat` is decided.
#'
#' @param occurrence_data Output of [assign_habitat_biological()], carrying a
#'   `"habitat_proportions"` attribute. Without it nothing can be resolved and
#'   the input is returned unchanged with a message.
#' @param habitat_col,lat_col,lon_col Column names.
#' @param candidate_mass Passed to the candidate rule; see
#'   [review_spatial_flags()].
#' @param coast_buffer_m Half-width of the coastal band, in metres. Points
#'   within it are treated as shoreline and left unresolved. Default `1000`,
#'   matching [flag_habitat_inconsistencies()].
#' @param verbose Logical. Report what was resolved.
#' @return `occurrence_data` with `main_habitat` filled in where geography was
#'   decisive, plus a `habitat_source` column. The `"habitat_proportions"`
#'   attribute is preserved.
#' @seealso [assign_habitat_biological()], [flag_habitat_inconsistencies()],
#'   [review_spatial_flags()]
#' @export
#' @examples
#' \dontrun{
#' occ <- assign_habitat_biological(occurrences, habitat_lookup, threshold = 0.5)
#' occ <- resolve_habitat_by_geography(occ)
#' flagged <- flag_habitat_inconsistencies(occ)
#' }
resolve_habitat_by_geography <- function(occurrence_data,
                                         habitat_col = "main_habitat",
                                         lat_col = "decimalLatitude",
                                         lon_col = "decimalLongitude",
                                         candidate_mass = 0.8,
                                         coast_buffer_m = 1000,
                                         verbose = TRUE) {
  if (!is.data.frame(occurrence_data)) {
    stop("resolve_habitat_by_geography: 'occurrence_data' must be a dataframe.")
  }
  for (col in c(habitat_col, lat_col, lon_col, "point_id")) {
    if (!col %in% names(occurrence_data)) {
      stop(sprintf("resolve_habitat_by_geography: column '%s' not found.", col))
    }
  }
  props <- attr(occurrence_data, "habitat_proportions")
  if (is.null(props) || !is.data.frame(props) || !"point_id" %in% names(props)) {
    if (verbose) {
      message(
        "resolve_habitat_by_geography: no 'habitat_proportions' attribute -- ",
        "nothing to resolve. Run assign_habitat_biological() first."
      )
    }
    return(occurrence_data)
  }
  prop_cols <- setdiff(names(props), "point_id")

  hab <- as.character(occurrence_data[[habitat_col]])
  if (!"habitat_source" %in% names(occurrence_data)) {
    occurrence_data[["habitat_source"]] <- ifelse(
      .is_habitat_unassigned(hab), NA_character_, "consensus"
    )
  }

  unresolved <- unique(occurrence_data[["point_id"]][.is_habitat_unassigned(hab)])
  if (length(unresolved) == 0L) {
    if (verbose) message("resolve_habitat_by_geography: nothing unassigned.")
    return(occurrence_data)
  }

  # Geography for the unresolved points only. Reuses
  # flag_habitat_inconsistencies()'s own layer machinery rather than
  # duplicating the land polygon / coastline / bathymetry setup: give the
  # points a placeholder habitat so that function does not skip them (it drops
  # NA-habitat rows before computing anything), then read the geography back
  # out. Only the unresolved subset is processed.
  sub <- occurrence_data[occurrence_data[["point_id"]] %in% unresolved, , drop = FALSE]
  sub <- sub[!duplicated(sub[["point_id"]]), , drop = FALSE]
  for (cc in c("elevation_m", "dist_to_coast_km", "spatial_flag", "spatial_flag_reason")) {
    sub[[cc]] <- NULL
  }
  sub[[habitat_col]] <- "Marine"
  geo <- suppressWarnings(suppressMessages(
    flag_habitat_inconsistencies(
      sub,
      habitat_col = habitat_col, lat_col = lat_col, lon_col = lon_col,
      coast_buffer_m = coast_buffer_m, verbose = FALSE
    )
  ))

  zone <- ifelse(
    is.na(geo$elevation_m), NA_character_,
    ifelse(geo$dist_to_coast_km <= coast_buffer_m / 1000, "coastal",
      ifelse(geo$elevation_m > 0, "inland", "ocean")
    )
  )

  pm <- as.matrix(props[match(geo[["point_id"]], props$point_id), prop_cols, drop = FALSE])
  decided <- vapply(seq_along(zone), function(i) {
    if (is.na(zone[i])) {
      return(NA_character_)
    }
    cd <- .candidate_habitats(stats::setNames(pm[i, ], prop_cols), candidate_mass)
    if (length(cd) == 0L) {
      return(NA_character_)
    }
    ok <- cd[.habitat_admissible(cd, zone[i])]
    if (length(ok) == 1L) ok else NA_character_
  }, character(1L))

  got <- !is.na(decided)
  if (any(got)) {
    map <- stats::setNames(decided[got], geo[["point_id"]][got])
    hit <- occurrence_data[["point_id"]] %in% names(map)
    occurrence_data[[habitat_col]][hit] <- unname(map[occurrence_data[["point_id"]][hit]])
    occurrence_data[["habitat_source"]][hit] <- "geography"
  }

  if (verbose) {
    message(sprintf(
      paste0(
        "resolve_habitat_by_geography: resolved %s of %s unassigned point(s) (%.0f%%).\n",
        "  by zone: %s\n",
        "  still unassigned: %s (geography discriminates nothing there)"
      ),
      format(sum(got), big.mark = ","), format(length(unresolved), big.mark = ","),
      100 * mean(got),
      paste(sprintf("%s=%s", names(table(zone[got])), table(zone[got])), collapse = ", "),
      format(sum(!got), big.mark = ",")
    ))
  }
  attr(occurrence_data, "habitat_proportions") <- props
  occurrence_data
}
