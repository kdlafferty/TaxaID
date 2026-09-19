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

# ------------------------------------------------------------------------------
# Point-in-polygon for interactive lasso selection
# ------------------------------------------------------------------------------

#' Web Mercator y for a vector of latitudes
#'
#' leaflet.draw's polygon edges are straight lines in SCREEN space, i.e. in Web
#' Mercator -- not in raw latitude. Ray-casting in raw lat therefore tests a
#' slightly different boundary than the one the reviewer actually drew and can
#' see. Projecting latitude to Mercator y before the cast makes the test agree
#' with the drawn shape exactly. Longitude needs no transform (Mercator x is
#' linear in longitude).
#'
#' @param lat Numeric vector of latitudes in degrees.
#' @return Numeric vector of Mercator y values.
#' @noRd
.mercator_y <- function(lat) {
  # Clamp at the Mercator poles; leaflet cannot display beyond ~85 anyway.
  lat <- pmax(pmin(as.numeric(lat), 89.9), -89.9)
  log(tan((45 + lat / 2) * pi / 180))
}

#' Vectorised even-odd point-in-polygon test
#'
#' Ray casting (even-odd / crossing-number rule), vectorised over POINTS and
#' looping over the polygon's EDGES -- so cost is O(n_points * n_vertices) with
#' the inner work done in compiled vector ops. A 10,000-point selection against
#' a 60-vertex hand-drawn coastline is ~600k arithmetic operations, i.e.
#' milliseconds. Callers should bbox-prefilter first so n_points is the
#' candidate set, not the whole dataset.
#'
#' No external geometry dependency on purpose: \pkg{sf}'s lon/lat predicates go
#' through \code{sf_use_s2()}, which is GLOBAL state, and an interactive gadget
#' must not mutate a session-wide setting mid-review.
#'
#' Does not handle a polygon crossing the antimeridian (+/-180). Selections
#' there would need the ring split; no TaxaID study area is affected.
#'
#' @param lon,lat Numeric vectors of point coordinates (same length).
#' @param poly_lon,poly_lat Numeric vectors of polygon ring vertices. A repeated
#'   closing vertex is optional and is dropped if present.
#' @return Logical vector, one per point, \code{TRUE} when inside the ring.
#' @noRd
.points_in_polygon <- function(lon, lat, poly_lon, poly_lat) {
  n <- length(lon)
  if (n == 0L) {
    return(logical(0L))
  }

  nv <- length(poly_lon)
  if (nv != length(poly_lat)) {
    return(rep(FALSE, n))
  }
  # Drop the repeated closing vertex GeoJSON rings carry.
  if (nv > 1L &&
    isTRUE(poly_lon[[1L]] == poly_lon[[nv]]) &&
    isTRUE(poly_lat[[1L]] == poly_lat[[nv]])) {
    poly_lon <- poly_lon[-nv]
    poly_lat <- poly_lat[-nv]
    nv <- nv - 1L
  }
  if (nv < 3L) {
    return(rep(FALSE, n))
  }

  py <- .mercator_y(poly_lat)
  y <- .mercator_y(lat)

  inside <- logical(n)
  j <- nv
  for (i in seq_len(nv)) {
    yi <- py[[i]]
    yj <- py[[j]]
    # An edge only matters if it straddles the point's horizontal ray. When
    # yi == yj (a horizontal edge) this is FALSE everywhere, which is also what
    # keeps the (yj - yi) division below from ever seeing a zero denominator.
    straddle <- (yi > y) != (yj > y)
    if (any(straddle)) {
      xi <- poly_lon[[i]]
      xj <- poly_lon[[j]]
      x_int <- xi + (y[straddle] - yi) * (xj - xi) / (yj - yi)
      inside[straddle] <- xor(inside[straddle], lon[straddle] < x_int)
    }
    j <- i
  }

  inside
}

#' Validate review_spatial_flags()'s bulk-selection size gate arguments
#'
#' Split out of \code{review_spatial_flags()} so it is reachable from tests --
#' the function itself refuses to run outside an interactive session, which
#' would otherwise mask every argument error behind that guard.
#'
#' @param bulk_confirm_threshold,bulk_max See \code{\link{review_spatial_flags}}.
#' @return \code{TRUE}, invisibly. Called for its side effect of erroring.
#' @noRd
.check_bulk_args <- function(bulk_confirm_threshold, bulk_max) {
  if (!is.numeric(bulk_confirm_threshold) || length(bulk_confirm_threshold) != 1L ||
    is.na(bulk_confirm_threshold) || bulk_confirm_threshold < 1) {
    stop("review_spatial_flags: 'bulk_confirm_threshold' must be a single number >= 1.")
  }
  if (!is.numeric(bulk_max) || length(bulk_max) != 1L ||
    is.na(bulk_max) || bulk_max < 1) {
    stop("review_spatial_flags: 'bulk_max' must be a single number >= 1.")
  }
  if (bulk_max < bulk_confirm_threshold) {
    stop(sprintf(
      paste0(
        "review_spatial_flags: 'bulk_max' (%s) is below 'bulk_confirm_threshold' (%s).\n",
        "  Every selection past the threshold would be refused rather than",
        " offered for confirmation."
      ),
      format(bulk_max), format(bulk_confirm_threshold)
    ))
  }
  invisible(TRUE)
}

#' Decide what a bulk selection of n points should do
#'
#' Split out of \code{review_spatial_flags()}'s \code{.gate_bulk()} so the
#' threshold logic is reachable from tests without a Shiny session. The gate
#' NEVER truncates -- see \code{review_spatial_flags()}'s "Bulk selection"
#' section for why a partial application is the one unacceptable outcome.
#'
#' @param n Integer. Points the action would touch.
#' @param threshold,max See \code{review_spatial_flags()}'s
#'   \code{bulk_confirm_threshold} / \code{bulk_max}.
#' @return One of \code{"none"}, \code{"apply"}, \code{"confirm"},
#'   \code{"refuse"}.
#' @noRd
.bulk_gate_decision <- function(n, threshold, max) {
  if (n == 0L) {
    return("none")
  }
  if (n > max) {
    return("refuse")
  }
  if (n > threshold) {
    return("confirm")
  }
  "apply"
}

#' Reverse one grouped history entry
#'
#' Split out of \code{review_spatial_flags()}'s Undo Last observer so grouped
#' undo is testable without a Shiny session. Each history entry covers EVERY
#' point touched by one action (a whole polygon selection), which is what lets
#' one click reverse the lot.
#'
#' @param fl,rs,habs Named character vectors keyed on \code{point_id}:
#'   current flags, reasons and habitats.
#' @param entry One history entry: parallel vectors \code{point_id},
#'   \code{old_flag}, \code{old_reason}, \code{old_habitat} (the last being
#'   \code{NA} for a flag-only change).
#' @return A list with the restored \code{fl}, \code{rs}, \code{habs}.
#' @noRd
.undo_group_state <- function(fl, rs, habs, entry) {
  ids <- entry$point_id
  fl[ids] <- entry$old_flag
  rs[ids] <- entry$old_reason
  had_hab <- !is.na(entry$old_habitat)
  if (any(had_hab)) {
    habs[ids[had_hab]] <- entry$old_habitat[had_hab]
  }
  list(fl = fl, rs = rs, habs = habs)
}

# ------------------------------------------------------------------------------
# Habitat-realm name patterns (see flag_habitat_inconsistencies()'s .realm())
# ------------------------------------------------------------------------------

#' Word-boundary patterns for marine / freshwater habitat names
#'
#' Kept as package constants rather than inline literals so the two stay
#' visibly SYMMETRIC. They were not, once: marine terms were "^"-anchored and
#' freshwater terms were not, which silently exempted 529,488 real Mugu rows
#' from spatial QC. Any edit to one should be weighed against the other.
#'
#' Inflections are enumerated instead of using bare prefixes, so a terrestrial
#' name cannot collide by accident ("Ponderosa Pine" must not match "pond").
#' @noRd
.marine_name_pattern <- paste0(
  "\\b(marine|ocean|oceanic|pelagic|neritic|intertidal|subtidal|",
  "littoral|reef|reefs|kelp|seagrass|estuary|estuarine|estuaries|",
  # "deepwater" is a REALM term, not a depth term. Mugu's own scheme lists
  # Pelagic and Deepwater as separate categories and is right to: the taxa
  # carrying it there are demersal -- Microstomus pacificus, Xeneretmus
  # ritteri, Bathyagonus pentacanthus, Icelinus spp., on the bottom between
  # -798 m and the shelf. Mapping it to Pelagic would assert a water-column
  # position these species do not occupy. Classifying it MARINE and letting
  # the bathymetry zones (marine_shallow / marine_deep / marine_abyssal,
  # cut at depth_neritic_m and depth_oceanic_m) carry the depth dimension
  # keeps the two axes separate, which is what they are.
  "deepwater|deep-water)\\b"
)

#' @noRd
.freshwater_name_pattern <- paste0(
  "\\b(freshwater|wetland|wetlands|aquatic|lake|lakes|river|rivers|riverine|",
  "stream|streams|pond|ponds|marsh|marshes|bog|bogs|fen|fens|riparian|",
  # Lentic (standing water) and lotic (flowing water) are the standard
  # limnological terms and are what the GreatLakes sites actually use. Without
  # them BOTH GreatLakes plates classified 100% of points as realm "unknown"
  # and were skipped entirely -- 6,217 and 11,154 rows, every run, reported as
  # "habitat 'Lentic' not found in habitat scheme -- skipped". Verified against
  # both saved occurrences_clean checkpoints on 2026-09-19.
  "lentic|lotic)\\b"
)

# ------------------------------------------------------------------------------
# Habitat breadth (Levins' B) from a weight table
# ------------------------------------------------------------------------------

#' Levins' niche breadth over a set of habitat weight columns
#'
#' `Habitat` is an argmax, so it renders a near-uniform weight vector and a
#' decisive one as the same confident-looking string. Measured on real
#' PtConception 12S data, *Larus delawarensis* reads `"Marine"` off weights of
#' Marine 0.30 / Estuarine 0.20 / Freshwater 0.30 / Terrestrial 0.20 -- a tie
#' broken arbitrarily by column order. This recovers the information the argmax
#' discards.
#'
#' Levins' B = 1 / sum(p^2) over the scheme's habitat columns, with the weights
#' renormalised to sum to 1 first. Units are **effective number of habitats**:
#' 1.0 is a pure specialist, and the maximum is the number of habitat columns
#' (perfectly even use of all of them). Standardise to 0-1 if needed with
#' (B - 1) / (n - 1).
#'
#' `Other_weight` is deliberately EXCLUDED. It measures the LLM failing to place
#' a taxon in the scheme at all, which is a different thing from a taxon that
#' genuinely spans habitats -- "no information" versus "broad niche". Read the
#' two columns together: high breadth with low `Other_weight` is a real
#' generalist; high `Other_weight` means the verdict itself is weak.
#'
#' @param df Data frame containing the habitat weight columns.
#' @param hab_cols Character. The scheme's habitat column names, excluding
#'   `Other_weight`.
#' @return Numeric vector, one per row. `NA` where the scheme weights are all
#'   zero or missing (nothing to measure breadth over).
#' @noRd
.compute_habitat_breadth <- function(df, hab_cols) {
  hab_cols <- intersect(hab_cols, names(df))
  n <- nrow(df)
  if (n == 0L || length(hab_cols) == 0L) {
    return(rep(NA_real_, n))
  }
  w <- as.matrix(df[, hab_cols, drop = FALSE])
  storage.mode(w) <- "double"
  w[is.na(w) | w < 0] <- 0
  tot <- rowSums(w)
  out <- rep(NA_real_, n)
  ok <- tot > 0
  if (any(ok)) {
    p <- w[ok, , drop = FALSE] / tot[ok]
    out[ok] <- 1 / rowSums(p^2)
  }
  out
}
