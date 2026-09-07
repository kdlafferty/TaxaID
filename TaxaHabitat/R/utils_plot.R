# ==============================================================================
# Shared internal helpers for plot and review functions
#
# Used by:
#   review_spatial_flags(), review_institution_flags()
#
# None of these functions are exported. .he() in particular is defined ONLY
# here (a single package-namespace-scoped definition) and called by both
# gadget files above -- a code review flagged this as a possible naming
# collision, but a single `.` prefixed helper shared by multiple files in
# the same package is ordinary R namespace scoping, not a collision; a
# collision would require a SECOND definition of the same name, which does
# not exist (confirmed via grep across R/).
# ==============================================================================


#' Build deduplicated point-level summary from occurrence data
#'
#' Reduces a full occurrence dataframe to one row per \code{point_id x habitat}
#' combination. Generates a synthetic \code{point_id} from rounded coordinates
#' if the column is absent. Optionally aggregates a species label string per
#' point for use in popups and tooltips.
#'
#' @param data Occurrence dataframe.
#' @param habitat_col,lat_col,lon_col Column name strings.
#' @param taxon_col Character column name for taxon labels, or \code{NULL}.
#' @param max_species Integer. Maximum species to list before truncating with
#'   "... and N more". Default \code{10L}.
#' @return A dataframe with columns \code{point_id}, \code{lon}, \code{lat},
#'   \code{habitat}, and optionally \code{spp_label}.
#' @noRd

.build_habitat_pts <- function(data, habitat_col, lat_col, lon_col,
                               taxon_col, max_species = 10L) {
  pts <- data.frame(
    lon = as.numeric(data[[lon_col]]),
    lat = as.numeric(data[[lat_col]]),
    habitat = as.character(data[[habitat_col]]),
    stringsAsFactors = FALSE
  )

  # Use existing point_id or synthesise from rounded coordinates
  if ("point_id" %in% names(data)) {
    pts$point_id <- as.character(data[["point_id"]])
  } else {
    pts$point_id <- paste0(round(pts$lon, 6L), "_", round(pts$lat, 6L))
  }

  if (!is.null(taxon_col) && taxon_col %in% names(data)) {
    pts$taxon <- as.character(data[[taxon_col]])
  }

  # Missing/empty habitat -> a real "Unknown" category, NOT a dropped row. A
  # point can have valid coordinates but a failed/below-threshold habitat
  # classification (a real, common case -- e.g. assign_habitat_biological()'s
  # own confidence threshold can leave a substantial fraction of real
  # occurrence data with NA main_habitat: confirmed live on the real
  # GreatLakes workflow data, 1,569 of 5,974 rows, 26%) and it should still
  # get a marker to review, not silently vanish from the gadget entirely
  # while still being counted in review_spatial_flags()'s sidebar view/flag
  # tallies (built from the unfiltered input data, not this pts object) --
  # that mismatch is exactly what made Flag-mode clicks/rectangle-selects
  # appear to do nothing: a real fraction of "points in view" had no marker
  # to click at all. Reassigning an "Unknown" point to a real habitat via
  # review_spatial_flags()'s existing Reassign Habitat mode also now doubles
  # as a manual fix path for these classification gaps.
  pts$habitat[is.na(pts$habitat) | !nzchar(pts$habitat)] <- "Unknown"

  # Drop only genuinely unmappable rows (no coordinates or no point identity).
  keep <- !is.na(pts$lon) & !is.na(pts$lat) & !is.na(pts$point_id)
  pts <- pts[keep, ]

  if (nrow(pts) == 0L) {
    return(pts)
  }

  # Aggregate species per point_id before deduplication
  if (!is.null(taxon_col) && "taxon" %in% names(pts)) {
    spp_by_point <- tapply(
      pts$taxon,
      pts$point_id,
      function(x) {
        spp <- sort(unique(x[!is.na(x) & nzchar(x)]))
        if (length(spp) == 0L) {
          return("(none)")
        }
        if (length(spp) > max_species) {
          paste0(
            paste(spp[seq_len(max_species)], collapse = ", "),
            sprintf(" ... and %d more", length(spp) - max_species)
          )
        } else {
          paste(spp, collapse = ", ")
        }
      }
    )
    pts$spp_label <- spp_by_point[pts$point_id]
  }

  # Deduplicate to one row per point_id x habitat
  pts <- pts[!duplicated(pts[, c("point_id", "habitat")]), ]

  pts
}


#' Assign colours to habitat levels
#'
#' Returns a named character vector mapping each habitat label to a hex colour.
#' Uses a 12-colour ecological palette for up to 12 habitats; falls back to
#' \code{grDevices::rainbow} for larger sets. A user-supplied \code{colors}
#' vector takes priority; any habitats not covered receive \code{"#aaaaaa"}
#' with a warning.
#'
#' @param hab_levels Character vector of sorted unique habitat names.
#' @param colors Named character vector of user-supplied colours, or
#'   \code{NULL}.
#' @return Named character vector, same length as \code{hab_levels}.
#' @noRd

# Default 12-colour ecological palette. Shared by .habitat_palette() (initial
# assignment) and .extend_habitat_palette() (mid-session additions) so both
# draw from the same fixed sequence -- extending never means duplicating this
# literal in two places and letting them drift apart.
.eco_habitat_colors <- c(
  "#2166ac", # deep blue      -- Marine
  "#74add1", # mid blue       -- Marine Neritic / Freshwater
  "#4dac26", # green          -- Terrestrial / Forest
  "#d6604d", # terracotta     -- Rocky / Arid
  "#8073ac", # purple         -- Subterranean / Cave
  "#f4a582", # peach          -- Estuarine / Coastal
  "#1b7837", # dark green     -- Woodland / Savanna
  "#bf812d", # brown          -- Grassland / Desert
  "#35978f", # teal           -- Wetlands
  "#de77ae", # pink           -- Artificial
  "#fdbf6f", # amber          -- Introduced Vegetation
  "#969696" # grey           -- Other / Unknown
)

.habitat_palette <- function(hab_levels, colors = NULL) {
  n_hab <- length(hab_levels)

  if (!is.null(colors)) {
    missing_hab <- setdiff(hab_levels, names(colors))
    if (length(missing_hab) > 0L) {
      warning(
        ".habitat_palette: the following habitats are not in the user-supplied ",
        "'colors' vector and will be shown in grey: ",
        paste(missing_hab, collapse = ", "),
        call. = FALSE
      )
      extra <- stats::setNames(rep("#aaaaaa", length(missing_hab)), missing_hab)
      colors <- c(colors, extra)
    }
    return(colors[hab_levels])
  }

  if (n_hab <= length(.eco_habitat_colors)) {
    pal <- stats::setNames(.eco_habitat_colors[seq_len(n_hab)], hab_levels)
  } else {
    pal <- stats::setNames(
      grDevices::rainbow(n_hab, s = 0.7, v = 0.85),
      hab_levels
    )
  }

  pal
}


#' Add colours for new habitat levels without disturbing existing ones
#'
#' Used by \code{\link{review_spatial_flags}} when a reviewer reassigns a
#' point to a habitat value that did not exist in the original dataset (e.g.
#' typed via the "Other" text box). Unlike calling \code{.habitat_palette()}
#' again on the full, re-sorted level set -- which reassigns colours by
#' POSITION and would silently recolour every already-displayed point
#' whenever the new value sorts earlier than an existing one -- this appends
#' a colour for each genuinely new level only, leaving every existing
#' mapping untouched.
#'
#' @param pal Named character vector, an existing palette (e.g. from
#'   \code{.habitat_palette()}).
#' @param new_levels Character vector of habitat labels to ensure are present
#'   in the returned palette. Labels already in \code{names(pal)} are
#'   ignored.
#' @return Named character vector: \code{pal} with any genuinely new levels
#'   appended.
#' @noRd

.extend_habitat_palette <- function(pal, new_levels) {
  new_levels <- setdiff(unique(new_levels), names(pal))
  if (length(new_levels) == 0L) {
    return(pal)
  }

  avail <- setdiff(.eco_habitat_colors, pal)
  n_new <- length(new_levels)

  if (length(avail) >= n_new) {
    new_colors <- avail[seq_len(n_new)]
  } else {
    n_extra <- n_new - length(avail)
    new_colors <- c(avail, grDevices::rainbow(n_extra, s = 0.7, v = 0.85))
  }

  c(pal, stats::setNames(new_colors, new_levels))
}


#' Lightweight HTML escaping
#'
#' Escapes \code{&}, \code{<}, \code{>}, and \code{"} for safe embedding in
#' Leaflet popup and tooltip HTML strings.
#'
#' @param x Character vector.
#' @return Character vector of the same length.
#' @noRd

.he <- function(x) {
  x <- gsub("&", "&amp;", as.character(x), fixed = TRUE)
  x <- gsub("<", "&lt;", x, fixed = TRUE)
  x <- gsub(">", "&gt;", x, fixed = TRUE)
  x <- gsub("\"", "&quot;", x, fixed = TRUE)
  x
}
