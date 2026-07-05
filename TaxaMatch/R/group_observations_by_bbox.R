# ==============================================================================
# group_observations_by_bbox.R
# TaxaMatch -- Automatic spatial grouping of observations
#
# Moved here from TaxaFetch (Session 134b): this operates on
# build_site_table()'s output and is fundamentally a spatial-grouping concern,
# not a fetch concern. TaxaTools::define_search_polygon() (also moved this
# session) is the shared gadget both this function and TaxaFetch's search-area
# use call.
#
# Exported functions:
#   group_observations_by_bbox()          Interactive multi-polygon grouping wrapper
#
# Internal helpers (@noRd):
#   .bbox_center_radius()                 Compute a centre/radius_deg view from points
#   .assign_spatial_groups_from_polygons() Point-in-polygon spatial_group_id assignment
#   .review_drawn_groups()                End-of-loop edit/delete review step
# ==============================================================================

#' Group Observations by User-Drawn Bounding Boxes
#'
#' Plots all observations' site coordinates and lets the user draw one or
#' more bounding-box polygons (via repeated calls to
#' \code{\link[TaxaTools]{define_search_polygon}}) to define spatial groups.
#' Observations whose coordinates fall within a drawn box share a
#' \code{spatial_group_id} and can use one pooled, community-level
#' occurrence/reference fetch (the existing clustered pipeline design).
#' Observations that never fall inside any drawn box -- including every
#' observation, if the user draws no box at all -- are \strong{not dropped}:
#' they are left at their existing \code{spatial_group_id} (by default, from
#' \code{\link{build_site_table}}, a singleton equal to their own
#' \code{observation_id}), so they flow through the single-observation
#' escalation path (taxonomic broadening: genus -> family -> order) instead
#' of being silently discarded.
#'
#' @param sites Data frame with one row per observation, containing at least
#'   \code{id_col}, \code{lat_col}, and \code{lon_col}. Typically the output
#'   of \code{\link{build_site_table}}, which already carries
#'   \code{spatial_group_id}/\code{spatial_group_N} defaults -- this function
#'   \strong{updates those columns in place} for whichever observations get
#'   captured by a drawn box, leaving everything else untouched. If
#'   \code{sites} has no \code{spatial_group_id}/\code{spatial_group_N}
#'   columns at all (i.e. it did not come from \code{build_site_table()}),
#'   singleton defaults are initialized first, with a message.
#' @param id_col Character. Column identifying each observation. Default
#'   \code{"observation_id"}.
#' @param lat_col,lon_col Character. Latitude/longitude column names. Default
#'   \code{"lat"} / \code{"lon"}.
#' @param tile Character. Leaflet tile provider, passed to
#'   \code{\link[TaxaTools]{define_search_polygon}}. Default
#'   \code{"Esri.OceanBasemap"}.
#'
#' @return \code{sites} with \code{spatial_group_id}/\code{spatial_group_N}
#'   updated in place: observations captured by a drawn box (in draw order;
#'   an observation falling inside more than one box gets the
#'   \strong{most recently drawn} one, with a warning -- see Details) get
#'   \code{"spatial_group_1"}, \code{"spatial_group_2"}, ... and
#'   \code{spatial_group_N} equal to that group's member count. Observations
#'   already in a non-default (previously grouped, or manually assigned via
#'   \code{\link{assign_spatial_group}}) group are left untouched regardless
#'   of geometry. Everything else keeps its existing default. A message
#'   reports how many observations were left at their default
#'   single-observation group and why.
#'
#' @details
#' \strong{Interaction model:} each iteration re-centres
#' \code{\link[TaxaTools]{define_search_polygon}} on the bounding box of the
#' still-ungrouped observations (guaranteed to fully enclose them -- see
#' \code{.bbox_center_radius()}) and overlays them as reference points. Draw a
#' box around a cluster and click \strong{Done} to record that group and
#' continue to the next box; click \strong{Cancel} (the title-bar X) when you
#' are finished drawing boxes. This opens an end-of-loop review: a numbered
#' list of drawn groups with their member counts, where you can enter a
#' number to reopen that group's polygon for reshaping, \code{"delete <n>"}
#' to remove it (releasing its members back to their default), or press
#' Enter to finalize.
#'
#' \strong{Run this as one isolated command in RStudio.} The end-of-loop
#' review step reads console input via \code{readline()}. If you select and
#' run this call together with other lines (e.g. highlighting both
#' \code{grouped <- group_observations_by_bbox(sites)} and a following
#' \code{print(grouped)} and pressing Cmd/Ctrl+Enter once), RStudio queues
#' the remaining line(s) as pending console input -- \code{readline()} will
#' silently consume that queued text as its answer instead of waiting for
#' you to type one, which can finalize early, misinterpret a queued blank
#' line as "done", or otherwise produce a result that does not match what
#' you actually drew. Run this call on its own, watch the console for the
#' box-by-box progress messages and the final review prompt, answer it
#' explicitly, and only then run any follow-up command.
#'
#' \strong{Overlap rule:} if an observation falls inside more than one drawn
#' polygon, the \strong{most recently drawn} polygon's group claims it -- a
#' later box is more likely to be a deliberate correction/refinement of an
#' earlier one covering the same area. A \code{warning()} lists every
#' ambiguous \code{observation_id}.
#'
#' \strong{Fetch-scope consequence (not performed by this function):}
#' multi-member spatial groups are intended to share one pooled bounding-box
#' occurrence/reference fetch. Single-observation spatial groups are intended
#' to be fetched per-observation, scoped to that observation's own candidate
#' taxa, broadened taxonomically rather than spatially.
#' \code{TaxaAssign::update_prior_from_consensus()} must be skipped for
#' single-observation groups -- see its \code{spatial_group_map} argument.
#'
#' @seealso \code{\link{build_site_table}}, \code{\link{assign_spatial_group}},
#'   \code{\link[TaxaTools]{define_search_polygon}}
#'
#' @examples
#' \dontrun{
#' sites <- data.frame(
#'   observation_id = paste0("obs", 1:6),
#'   lat = c(34.40, 34.41, 34.39, 36.60, 36.61, 40.71),
#'   lon = c(-119.86, -119.85, -119.87, -121.90, -121.89, -74.00)
#' )
#' grouped <- group_observations_by_bbox(sites)
#' table(grouped$spatial_group_id)
#' }
#'
#' @export
group_observations_by_bbox <- function(sites,
                                       id_col  = "observation_id",
                                       lat_col = "lat",
                                       lon_col = "lon",
                                       tile    = "Esri.OceanBasemap") {

  if (!is.data.frame(sites) || nrow(sites) == 0L)
    stop("group_observations_by_bbox: 'sites' must be a non-empty data frame.", call. = FALSE)

  required <- c(id_col, lat_col, lon_col)
  missing  <- setdiff(required, names(sites))
  if (length(missing) > 0L)
    stop(sprintf(
      "group_observations_by_bbox: 'sites' missing required column(s): %s",
      paste(missing, collapse = ", ")
    ), call. = FALSE)

  if (anyNA(sites[[lat_col]]) || anyNA(sites[[lon_col]]))
    stop("group_observations_by_bbox: 'sites' has NA coordinates; resolve site info before grouping.",
         call. = FALSE)

  if (!interactive())
    stop("group_observations_by_bbox: must be run in an interactive R session.", call. = FALSE)

  if (!"spatial_group_id" %in% names(sites) || !"spatial_group_N" %in% names(sites)) {
    message(
      "group_observations_by_bbox: 'sites' has no spatial_group_id/spatial_group_N columns -- ",
      "initializing single-observation defaults (run TaxaMatch::build_site_table() first to ",
      "get these automatically)."
    )
    sites$spatial_group_id <- as.character(sites[[id_col]])
    sites$spatial_group_N  <- 1L
  }

  still_default <- sites$spatial_group_id == as.character(sites[[id_col]]) &
                   sites$spatial_group_N == 1L

  polygons <- character(0)
  assigned <- !still_default

  repeat {
    remaining <- sites[!assigned, , drop = FALSE]
    if (nrow(remaining) == 0L) break

    view <- .bbox_center_radius(remaining[[lat_col]], remaining[[lon_col]])

    wkt <- TaxaTools::define_search_polygon(
      lat        = view$lat,
      lon        = view$lon,
      radius_deg = view$radius_deg,
      tile       = tile,
      points     = data.frame(lat = remaining[[lat_col]], lng = remaining[[lon_col]])
    )

    if (is.null(wkt)) {
      message("group_observations_by_bbox: gadget closed without Done (Cancel/X) -- stopped drawing boxes.")
      break  # user is done drawing groups
    }

    polygons <- c(polygons, wkt)

    poly_sf <- sf::st_as_sfc(wkt, crs = 4326L)
    pts_sf  <- sf::st_as_sf(remaining, coords = c(lon_col, lat_col), crs = 4326L)
    inside  <- as.logical(sf::st_within(pts_sf, poly_sf, sparse = FALSE)[, 1])

    matched_ids <- remaining[[id_col]][inside]
    assigned[sites[[id_col]] %in% matched_ids] <- TRUE

    message(sprintf(
      "group_observations_by_bbox: box %d captured %d of %d remaining observation(s); %d still ungrouped.",
      length(polygons), length(matched_ids), nrow(remaining), sum(!assigned)
    ))
  }

  message(sprintf(
    "group_observations_by_bbox: drawing finished -- %d box(es) recorded.",
    length(polygons)
  ))

  polygons <- .review_drawn_groups(
    polygons, sites[still_default, , drop = FALSE],
    id_col = id_col, lat_col = lat_col, lon_col = lon_col, tile = tile
  )

  message(sprintf(
    "group_observations_by_bbox: %d box(es) after review -- applying to spatial_group_id/spatial_group_N.",
    length(polygons)
  ))

  .assign_spatial_groups_from_polygons(sites, polygons, id_col = id_col,
                                       lat_col = lat_col, lon_col = lon_col)
}


# ==============================================================================
# Internal: .bbox_center_radius
# ==============================================================================

#' Compute a centre point and half-width radius spanning a set of coordinates
#'
#' Used to re-centre \code{define_search_polygon()}'s initial view on
#' whichever observations still need a group. Guaranteed to fully enclose
#' every supplied point: \code{radius_deg} is \code{pad} (> 1) times the
#' larger of the two half-ranges, so the initial square this drives is never
#' smaller than the bounding box of \code{lat}/\code{lon} -- deliberate, not
#' incidental (a single remaining point, or several coincident points, still
#' gets a small non-zero radius so the gadget opens with a sensible initial
#' square).
#' @noRd
.bbox_center_radius <- function(lat, lon, pad = 1.2, min_radius_deg = 0.05) {
  lat_rng <- range(lat)
  lon_rng <- range(lon)
  list(
    lat        = mean(lat_rng),
    lon        = mean(lon_rng),
    radius_deg = max(diff(lat_rng) / 2, diff(lon_rng) / 2, min_radius_deg) * pad
  )
}


# ==============================================================================
# Internal: .assign_spatial_groups_from_polygons
# ==============================================================================

#' Assign spatial_group_id to observations from a set of drawn WKT polygons
#'
#' Only touches observations currently at their default single-observation
#' state (\code{spatial_group_id == id_col} value and \code{spatial_group_N
#' == 1L}) -- anything already grouped (from a prior call, or manual
#' assignment via \code{\link{assign_spatial_group}}) is left unchanged
#' regardless of whether a newly drawn polygon happens to cover it
#' geometrically. Among the still-default observations: a point inside a
#' polygon gets that polygon's group ("spatial_group_1", "spatial_group_2",
#' ... in draw order); a point inside more than one polygon gets the
#' \strong{most recently drawn} one (last-drawn-wins), with a warning listing
#' every ambiguous \code{observation_id}. Points inside no polygon at all --
#' including every default observation, when \code{polygons} is empty -- are
#' left at their default, not dropped.
#'
#' @param sites Data frame with \code{id_col}/\code{lat_col}/\code{lon_col}
#'   and existing \code{spatial_group_id}/\code{spatial_group_N} columns.
#' @param polygons Character vector of WKT POLYGON strings, in draw order.
#'   May be length 0 (no boxes drawn).
#' @return \code{sites} with \code{spatial_group_id}/\code{spatial_group_N}
#'   updated.
#' @noRd
.assign_spatial_groups_from_polygons <- function(sites, polygons, id_col = "observation_id",
                                                 lat_col = "lat", lon_col = "lon") {

  is_default <- sites$spatial_group_id == as.character(sites[[id_col]]) &
                sites$spatial_group_N == 1L
  target_idx <- which(is_default)

  if (length(target_idx) == 0L) {
    if (length(polygons) > 0L)
      message("group_observations_by_bbox: every observation is already part of a spatial group; nothing left to assign.")
    return(sites)
  }

  new_group   <- rep(NA_character_, length(target_idx))
  match_count <- rep(0L, length(target_idx))

  if (length(polygons) > 0L) {
    pts_sf <- sf::st_as_sf(sites[target_idx, , drop = FALSE], coords = c(lon_col, lat_col), crs = 4326L)

    for (i in seq_along(polygons)) {
      poly_sf <- tryCatch(sf::st_as_sfc(polygons[[i]], crs = 4326L), error = function(e) NULL)
      if (is.null(poly_sf)) next

      inside <- as.logical(sf::st_within(pts_sf, poly_sf, sparse = FALSE)[, 1])
      match_count[inside] <- match_count[inside] + 1L
      new_group[inside]   <- sprintf("spatial_group_%d", i)  # overwritten by later i: last-drawn-wins
    }

    ambiguous <- which(match_count > 1L)
    if (length(ambiguous) > 0L) {
      warning(sprintf(
        paste0(
          "group_observations_by_bbox: %d observation(s) fell inside more than one drawn ",
          "polygon -- the most recently drawn polygon's group wins. Ambiguous observation_id(s): %s"
        ),
        length(ambiguous),
        paste(utils::head(sites[[id_col]][target_idx[ambiguous]], 10L), collapse = ", ")
      ), call. = FALSE)
    }
  }

  grouped_local <- !is.na(new_group)
  if (any(grouped_local)) {
    sites$spatial_group_id[target_idx[grouped_local]] <- new_group[grouped_local]
  }

  n_leftover <- sum(!grouped_local)
  if (n_leftover > 0L) {
    if (length(polygons) == 0L) {
      message(sprintf(
        paste0(
          "group_observations_by_bbox: no bounding-box groups were drawn -- leaving all %d ",
          "observation(s) at their default single-observation spatial group (each fetched/",
          "escalated on its own, not pooled)."
        ),
        n_leftover
      ))
    } else {
      message(sprintf(
        paste0(
          "group_observations_by_bbox: %d observation(s) fell outside every drawn spatial ",
          "group -- left at their default single-observation spatial group (not dropped); ",
          "each will be fetched/escalated on its own, not pooled with any multi-member group."
        ),
        n_leftover
      ))
    }
  }

  tab <- table(sites$spatial_group_id)
  sites$spatial_group_N <- as.integer(tab[sites$spatial_group_id])

  sites
}


# ==============================================================================
# Internal: .review_drawn_groups
# ==============================================================================

#' End-of-loop review: edit or delete drawn groups before finalizing
#'
#' Console-driven review step shown after the user cancels the draw loop in
#' \code{\link{group_observations_by_bbox}}. Lists each drawn group with its
#' current member count; the user may reopen a group by number (re-launches
#' \code{\link[TaxaTools]{define_search_polygon}} seeded with that group's
#' existing polygon via \code{init_polygon}, so it can be reshaped rather
#' than redrawn from scratch), delete a group by number (its members return
#' to the default pool -- final assignment happens afterward, so this does
#' not require re-entering the draw loop), or press Enter/type "done" to
#' finalize. A no-op (returns \code{polygons} unchanged) when zero polygons
#' were drawn or the session is non-interactive.
#'
#' @param polygons Character vector of WKT POLYGON strings, in draw order.
#' @param candidate_sites Data frame (the still-default subset of \code{sites}
#'   at the start of the draw loop) used to compute per-group member counts
#'   and to overlay reference points while reshaping.
#' @return Character vector of WKT POLYGON strings, possibly edited/shortened.
#' @noRd
.review_drawn_groups <- function(polygons, candidate_sites, id_col, lat_col, lon_col, tile) {
  if (length(polygons) == 0L || !interactive()) return(polygons)

  pts_sf_all <- sf::st_as_sf(candidate_sites, coords = c(lon_col, lat_col), crs = 4326L)

  repeat {
    counts <- vapply(seq_along(polygons), function(i) {
      poly_sf <- tryCatch(sf::st_as_sfc(polygons[[i]], crs = 4326L), error = function(e) NULL)
      if (is.null(poly_sf)) return(0L)
      sum(as.logical(sf::st_within(pts_sf_all, poly_sf, sparse = FALSE)[, 1]))
    }, integer(1L))

    message("\nDrawn spatial groups:")
    for (i in seq_along(polygons)) {
      message(sprintf("  %d. spatial_group_%d -- %d observation(s)", i, i, counts[i]))
    }
    ans <- trimws(readline(
      "Enter a number to edit that group, 'delete <n>' to remove it, or press Enter to finalize: "
    ))

    if (identical(ans, "") || identical(tolower(ans), "done")) break

    if (grepl("^delete\\s+\\d+$", tolower(ans))) {
      idx <- as.integer(sub("^delete\\s+", "", tolower(ans)))
      if (is.na(idx) || idx < 1L || idx > length(polygons)) {
        message("Invalid group number; try again.")
        next
      }
      polygons <- polygons[-idx]
      message(sprintf("Deleted group %d. Remaining groups renumbered.", idx))
      next
    }

    idx <- suppressWarnings(as.integer(ans))
    if (is.na(idx) || idx < 1L || idx > length(polygons)) {
      message("Invalid input; try again.")
      next
    }

    new_wkt <- TaxaTools::define_search_polygon(
      init_polygon = polygons[[idx]],
      tile         = tile,
      points       = data.frame(lat = candidate_sites[[lat_col]], lng = candidate_sites[[lon_col]])
    )
    if (!is.null(new_wkt)) {
      polygons[[idx]] <- new_wkt
    } else {
      message(sprintf("Editing of group %d cancelled; kept original shape.", idx))
    }
  }

  polygons
}
