#' Spatial-isolation signal for a taxon from GBIF's occurrence-density map tiles
#'
#' Downloads the GBIF occurrence-density PNG tile(s) covering a query point
#' and a surrounding buffer, and reports how isolated that point is from the
#' taxon's known range: whether the point itself falls in an occupied cell,
#' the real-world distance to the nearest occupied cell, and the size of the
#' occupied blob nearest the point (a weak proxy for "one lone report" vs.
#' "a small cluster of independent reports").
#'
#' This is the cheap, global, approximate complement to
#' [compute_local_occurrence_distance()]'s free, local, exact view: the
#' local function can only speak to whatever bounding box a study's own GBIF
#' fetch covered, while this one gives the missing global context (is a
#' species that is novel to this study also far from its known range
#' everywhere, or is it novel here simply because no one sampled here
#' before) for the cost of a handful of small tile downloads, regardless of
#' how many occurrence records exist worldwide.
#'
#' @section What the PNG can and can't tell you:
#' GBIF's density tiles encode density as a colour ramp, which is not a
#' reliable source for exact counts. This function only ever reads the
#' **alpha channel** (transparent = zero occurrences in that cell, any
#' non-zero alpha = at least one) -- a presence/absence signal, not a
#' decoded density value. `patch_size_px`/`patch_area_km2` are weak,
#' resolution-limited proxies for how much local support an isolated
#' detection has (a bigger blob suggests more than one independent nearby
#' report), not an exact record count; for that, follow up with a targeted
#' GBIF occurrence query at just the flagged point.
#'
#' @section What isolation does and doesn't mean:
#' A point far from the nearest occupied cell is equally consistent with a
#' genuine rarity/vagrancy report and with a misidentified or mis-georeferenced
#' record -- this function cannot distinguish the two on geometry alone. Error
#' screening against implausible occurrences belongs to
#' `TaxaFetch::check_geographic_outliers()`; this function is for a
#' downstream, different question -- for a detection already judged
#' plausible, how far outside the species' main range does it sit.
#'
#' @section Zoom escalation:
#' A fixed `zoom`/`buffer_px` only ever covers a bounded window (e.g. the
#' default is roughly continental scale) -- a species genuinely absent from
#' that window could be just outside it, or on another continent, and a flat
#' "not found" (`NA` distance) can't tell those apart. When `escalate = TRUE`
#' (the default) and nothing is found at `zoom`, the same `buffer_px` window
#' is re-tried one zoom level coarser (each step downward roughly doubles the
#' real-world ground the same pixel buffer covers), continuing down to
#' `min_zoom` (default `0L` -- the whole world in a single tile) until an
#' occupied cell is found or `min_zoom` is exhausted. This is cheap in the
#' common case: escalation only fires for calls that would otherwise return
#' `NA`, each step costs the same handful of tiles as the original call, and
#' it terminates as soon as anything is found -- confirmed on a real case
#' (a European species queried from the Great Lakes) resolving after 3 extra
#' steps at a real, plausible transatlantic distance, instead of `NA`. Set
#' `escalate = FALSE` to restore the original single-zoom, bounded-latency
#' behaviour, where `beyond_buffer` means only "not within this one window."
#' `resolution_km_per_px`/`dist_nearest_occupied_km`/`patch_size_px` etc. are
#' always reported at `zoom_used` (whichever level actually found something,
#' or the originally requested `zoom` if nothing was found at any level) --
#' compare against `zoom_used`, not `zoom`, when judging precision.
#'
#' @param taxon_key Integer. GBIF backbone `usageKey` for the taxon. Resolve
#'   via `TaxaFetch::get_keys_from_context()` or `rgbif::name_backbone()`.
#' @param query_lat,query_lon Numeric scalars. The point to check.
#'   `query_lat` must be within Web Mercator's valid range
#'   (approximately -85.05 to 85.05 -- the projection is undefined at the
#'   poles).
#' @param zoom Integer in `[0, 12]`. Starting tile zoom level. Controls both
#'   the real-world size of each density cell and how much ground a fixed
#'   `buffer_px` covers -- a coarser (smaller) zoom gives a wider, coarser
#'   view for the same download cost; a finer (larger) zoom gives tighter
#'   precision over a smaller area. Default `6L` is roughly continental
#'   scale (tens to low hundreds of km per pixel, depending on latitude).
#' @param buffer_px Integer. How far around the query point to scan for the
#'   nearest occupied cell, in tile pixels. Tiles are fetched in whole
#'   512x512 blocks, so this is rounded up to the nearest multiple of 512.
#' @param escalate Logical. Widen the search to coarser zoom levels when
#'   nothing is found at `zoom` -- see "Zoom escalation" above. Default
#'   `TRUE`.
#' @param min_zoom Integer in `[0, zoom]`. Coarsest zoom level escalation is
#'   allowed to reach. Default `0L` (the whole world, one tile). Ignored
#'   when `escalate = FALSE`.
#' @param base_url Character. GBIF map tile base URL. Exposed for testing.
#'
#' @return A one-row data frame:
#'   \describe{
#'     \item{taxon_key, query_lat, query_lon}{As supplied.}
#'     \item{zoom_requested}{The `zoom` argument, as supplied.}
#'     \item{zoom_used}{The zoom level the reported values were actually
#'       computed at -- `zoom_requested` unless escalation stepped down to
#'       find something. `NA` when `escalate = TRUE` (the default) and
#'       nothing was found anywhere from `zoom` down to `min_zoom` (nothing
#'       was ever "used"). When `escalate = FALSE`, this is always
#'       `zoom_requested`, even if nothing was found there -- the single
#'       attempted zoom is still reported, for reference.}
#'     \item{escalated}{Logical. `TRUE` when `zoom_used != zoom_requested`
#'       -- the answer came from a coarser search than requested.}
#'     \item{tile_size}{Pixel width/height of one fetched tile (512, GBIF's
#'       `@1x.png` size).}
#'     \item{n_tiles_fetched}{Total tiles downloaded across every zoom level
#'       attempted -- transparency on the real cost of the call, including
#'       any escalation.}
#'     \item{resolution_km_per_px}{Real-world ground distance per pixel at
#'       `query_lat`/`zoom_used` (Web Mercator distorts by latitude and
#'       zoom) -- the unit `patch_size_px`/`patch_area_km2` are derived
#'       from.}
#'     \item{point_occupied}{Logical. Does the query point's own cell (at
#'       `zoom_used`) have at least one occurrence?}
#'     \item{dist_nearest_occupied_km}{Distance from the query point to the
#'       nearest occupied cell found. `0` when `point_occupied`. `NA` when
#'       `beyond_buffer`.}
#'     \item{patch_size_px}{Size (in cells, at `zoom_used`) of the occupied
#'       blob nearest the point (8-connected), grown from that nearest
#'       cell. Growth is capped at a small fixed number of iterations for
#'       bounded latency (see `patch_size_capped`), so this is exact for a
#'       small/isolated patch (the case this function is for) but only a
#'       lower bound once a patch is large enough to hit the cap. `NA` when
#'       `beyond_buffer`.}
#'     \item{patch_size_capped}{Logical. `TRUE` when patch growth hit the
#'       iteration cap before converging -- `patch_size_px`/`patch_area_km2`
#'       are then a lower bound, not exact. In practice this itself is
#'       informative: a capped patch is, by construction, one that already
#'       covers a wide area at `zoom_used`, i.e. clearly not an isolated
#'       report. `NA` when `beyond_buffer`.}
#'     \item{patch_area_km2}{`patch_size_px * resolution_km_per_px^2` -- the
#'       pixel count converted to real-world area, since a raw pixel count
#'       is only interpretable alongside the zoom it was measured at. A
#'       lower bound when `patch_size_capped`. `NA` when `beyond_buffer`.}
#'     \item{patch_diameter_km}{`sqrt(patch_size_px) * resolution_km_per_px`
#'       -- a rough linear length scale for the same patch, in the same
#'       units as `dist_nearest_occupied_km`, meant for eyeballing the two
#'       against each other (e.g. "the isolated point is 340 km from a
#'       patch about 15 km across"). A lower bound when `patch_size_capped`.
#'       `NA` when `beyond_buffer`.}
#'     \item{beyond_buffer}{Logical. With `escalate = TRUE` (default):
#'       `TRUE` only when no occupied cell was found anywhere from `zoom`
#'       down to `min_zoom` -- with the default `min_zoom = 0`, this means
#'       the species has no occurrence anywhere in GBIF's density map at
#'       all (a real, decisive finding, not just "outside this window").
#'       With `escalate = FALSE`: `TRUE` when nothing was found within the
#'       single requested `zoom`/`buffer_px` window.}
#'   }
#'
#' @seealso [compute_local_occurrence_distance()]
#'
#' @examples
#' \dontrun{
#' check_gbif_tile_range(
#'   taxon_key = 2379089,  # Neogobius melanostomus
#'   query_lat = 41.67, query_lon = -87.15
#' )
#' }
#'
#' @export
check_gbif_tile_range <- function(taxon_key,
                                   query_lat,
                                   query_lon,
                                   zoom = 6L,
                                   buffer_px = 512L,
                                   escalate = TRUE,
                                   min_zoom = 0L,
                                   base_url = "https://api.gbif.org/v2/map/occurrence/density") {

  if (!is.numeric(taxon_key) || length(taxon_key) != 1L || is.na(taxon_key)) {
    stop("check_gbif_tile_range: taxon_key must be a single non-NA numeric GBIF usageKey.")
  }
  if (!is.numeric(query_lat) || length(query_lat) != 1L || is.na(query_lat) ||
      query_lat < -85.05 || query_lat > 85.05) {
    stop("check_gbif_tile_range: query_lat must be a single numeric value within Web Mercator's valid range (-85.05 to 85.05).")
  }
  if (!is.numeric(query_lon) || length(query_lon) != 1L || is.na(query_lon)) {
    stop("check_gbif_tile_range: query_lon must be a single non-NA numeric value.")
  }
  if (!is.numeric(zoom) || length(zoom) != 1L || is.na(zoom) || zoom < 0 || zoom > 12 || zoom != round(zoom)) {
    stop("check_gbif_tile_range: zoom must be a single integer in [0, 12].")
  }
  if (!is.numeric(buffer_px) || length(buffer_px) != 1L || is.na(buffer_px) || buffer_px <= 0) {
    stop("check_gbif_tile_range: buffer_px must be a single positive numeric value.")
  }
  if (!is.logical(escalate) || length(escalate) != 1L || is.na(escalate)) {
    stop("check_gbif_tile_range: escalate must be a single non-NA logical value.")
  }
  if (!is.numeric(min_zoom) || length(min_zoom) != 1L || is.na(min_zoom) ||
      min_zoom < 0 || min_zoom > zoom || min_zoom != round(min_zoom)) {
    stop("check_gbif_tile_range: min_zoom must be a single integer in [0, zoom].")
  }
  for (pkg in c("httr2", "png")) {
    if (!requireNamespace(pkg, quietly = TRUE)) {
      stop(sprintf(
        "check_gbif_tile_range: package '%s' is required. Install with: install.packages('%s')",
        pkg, pkg
      ))
    }
  }

  zoom      <- as.integer(zoom)
  min_zoom  <- as.integer(min_zoom)
  tile_size <- 512L  # GBIF's @1x.png tile size -- confirmed empirically, NOT the 256px slippy-map convention

  zoom_seq <- if (escalate) seq.int(zoom, min_zoom, by = -1L) else zoom

  n_tiles_fetched_total <- 0L
  first_attempt <- NULL
  found_attempt <- NULL
  zoom_used     <- NA_integer_

  for (z in zoom_seq) {
    attempt <- .check_gbif_tile_range_at_zoom(taxon_key, query_lat, query_lon, z, buffer_px, base_url, tile_size)
    n_tiles_fetched_total <- n_tiles_fetched_total + attempt$n_tiles_fetched
    if (is.null(first_attempt)) first_attempt <- attempt
    if (attempt$found) {
      found_attempt <- attempt
      zoom_used <- z
      break
    }
  }

  escalated     <- escalate && !is.na(zoom_used) && zoom_used != zoom
  beyond_buffer <- is.null(found_attempt)

  if (beyond_buffer) {
    reference    <- first_attempt
    zoom_used_out <- if (escalate) NA_integer_ else zoom  # nothing was ever "used" successfully; NA under escalation, the single attempted zoom otherwise
    dist_km <- NA_real_
    patch_size_px <- NA_integer_; patch_size_capped <- NA
    patch_area_km2 <- NA_real_; patch_diameter_km <- NA_real_
  } else {
    reference <- found_attempt
    zoom_used_out <- zoom_used
    dist_km <- found_attempt$dist_nearest_occupied_km
    patch_size_px <- found_attempt$patch_size_px
    patch_size_capped <- found_attempt$patch_size_capped
    patch_area_km2 <- patch_size_px * found_attempt$resolution_km_per_px^2
    patch_diameter_km <- sqrt(patch_size_px) * found_attempt$resolution_km_per_px
  }

  data.frame(
    taxon_key                = taxon_key,
    query_lat                = query_lat,
    query_lon                = query_lon,
    zoom_requested            = zoom,
    zoom_used                 = zoom_used_out,
    escalated                 = escalated,
    tile_size                = tile_size,
    n_tiles_fetched          = n_tiles_fetched_total,
    resolution_km_per_px     = reference$resolution_km_per_px,
    point_occupied            = reference$point_occupied,
    dist_nearest_occupied_km = dist_km,
    patch_size_px            = patch_size_px,
    patch_size_capped        = patch_size_capped,
    patch_area_km2            = patch_area_km2,
    patch_diameter_km         = patch_diameter_km,
    beyond_buffer             = beyond_buffer,
    stringsAsFactors = FALSE
  )
}

#' One zoom level's worth of tile fetch + presence/distance/patch computation
#' Extracted from check_gbif_tile_range() so the public function can retry
#' this at successively coarser zoom levels (see that function's "Zoom
#' escalation" section) without duplicating the tile-stitching logic.
#' @noRd
.check_gbif_tile_range_at_zoom <- function(taxon_key, query_lat, query_lon, zoom, buffer_px, base_url, tile_size) {
  loc <- .lonlat_to_tile_pixel(query_lat, query_lon, zoom, tile_size)

  n_tiles     <- 2L^zoom
  tile_radius <- as.integer(ceiling(buffer_px / tile_size))
  x_range     <- seq.int(loc$xtile - tile_radius, loc$xtile + tile_radius)
  y_range     <- seq.int(loc$ytile - tile_radius, loc$ytile + tile_radius)
  y_range     <- y_range[y_range >= 0L & y_range < n_tiles]  # tiles outside Mercator's y-range don't exist (poles)

  mosaic <- matrix(0, nrow = length(y_range) * tile_size, ncol = length(x_range) * tile_size)
  n_tiles_fetched <- 0L
  for (yi in seq_along(y_range)) {
    for (xi in seq_along(x_range)) {
      xw <- ((x_range[xi] %% n_tiles) + n_tiles) %% n_tiles  # wrap the antimeridian
      alpha <- .fetch_gbif_tile_alpha(base_url, zoom, xw, y_range[yi], taxon_key, tile_size)
      n_tiles_fetched <- n_tiles_fetched + 1L
      row_off <- (yi - 1L) * tile_size
      col_off <- (xi - 1L) * tile_size
      mosaic[(row_off + 1L):(row_off + tile_size), (col_off + 1L):(col_off + tile_size)] <- alpha
    }
  }

  y0_idx <- which(y_range == loc$ytile)
  if (length(y0_idx) == 0L) {
    # Not reachable given check_gbif_tile_range()'s own query_lat validation
    # (-85.05 to 85.05 is valid at every zoom) -- a hard stop, not a soft
    # skip, since it would indicate a real bug in the tile math, not an
    # expected runtime condition.
    stop("check_gbif_tile_range: query point's own tile row falls outside Web Mercator's valid latitude range.")
  }
  x0_idx <- which(x_range == loc$xtile)
  pt_row <- (y0_idx - 1L) * tile_size + loc$py + 1L
  pt_col <- (x0_idx - 1L) * tile_size + loc$px + 1L

  presence <- mosaic > 0
  point_occupied <- presence[pt_row, pt_col]
  res_km_per_px  <- .mercator_resolution_km(query_lat, zoom, tile_size)

  occ_idx <- which(presence, arr.ind = TRUE)
  if (nrow(occ_idx) == 0L) {
    return(list(
      found = FALSE, n_tiles_fetched = n_tiles_fetched,
      resolution_km_per_px = res_km_per_px, point_occupied = point_occupied
    ))
  }

  d2 <- (occ_idx[, 1] - pt_row)^2 + (occ_idx[, 2] - pt_col)^2
  nearest_i <- which.min(d2)
  dist_km <- sqrt(d2[nearest_i]) * res_km_per_px
  patch   <- .grow_patch_size(presence, occ_idx[nearest_i, 1], occ_idx[nearest_i, 2])

  list(
    found = TRUE, n_tiles_fetched = n_tiles_fetched,
    resolution_km_per_px = res_km_per_px, point_occupied = point_occupied,
    dist_nearest_occupied_km = dist_km,
    patch_size_px = patch$size, patch_size_capped = patch$capped
  )
}

#' Web Mercator lon/lat -> tile x/y + in-tile pixel offset
#' Standard XYZ slippy-map formulas, verified empirically against real GBIF
#' tiles (a known-present species' own tile pixel resolves alpha > 0).
#' @noRd
.lonlat_to_tile_pixel <- function(lat, lon, zoom, tile_size) {
  n <- 2^zoom
  lat_rad <- lat * pi / 180
  xtile_f <- (lon + 180) / 360 * n
  ytile_f <- (1 - log(tan(lat_rad) + 1 / cos(lat_rad)) / pi) / 2 * n
  xtile <- floor(xtile_f)
  ytile <- floor(ytile_f)
  list(
    xtile = as.integer(xtile),
    ytile = as.integer(ytile),
    px    = as.integer(floor((xtile_f - xtile) * tile_size)),
    py    = as.integer(floor((ytile_f - ytile) * tile_size))
  )
}

#' Real-world ground resolution (km/pixel) at a latitude/zoom
#' Standard Web Mercator formula (156543.03392 m/px at zoom 0 for 256px
#' tiles), rescaled for GBIF's 512px tiles.
#' @noRd
.mercator_resolution_km <- function(lat, zoom, tile_size) {
  (156543.03392 * cos(lat * pi / 180) / 2^zoom) * (256 / tile_size) / 1000
}

#' Fetch one GBIF density tile's alpha channel as a tile_size x tile_size matrix
#' GBIF returns HTTP 204 (no body) for a tile with zero occurrences --
#' confirmed empirically, not an error case, handled as an all-zero matrix.
#' @noRd
.fetch_gbif_tile_alpha <- function(base_url, zoom, x, y, taxon_key, tile_size) {
  url <- sprintf("%s/%d/%d/%d@1x.png?taxonKey=%d", base_url, zoom, x, y, taxon_key)
  resp <- httr2::req_perform(
    httr2::req_error(httr2::request(url), is_error = function(resp) FALSE)
  )
  status <- httr2::resp_status(resp)
  if (status == 204L) {
    return(matrix(0, tile_size, tile_size))
  }
  if (status != 200L) {
    warning(sprintf(
      "check_gbif_tile_range: tile z=%d/x=%d/y=%d returned HTTP %d -- treated as empty.",
      zoom, x, y, status
    ), call. = FALSE)
    return(matrix(0, tile_size, tile_size))
  }
  img <- png::readPNG(httr2::resp_body_raw(resp))
  # GBIF's @1x.png tiles are always RGBA (confirmed empirically) -- guarded
  # rather than assumed, since indexing a non-existent 4th channel would
  # otherwise fail with an opaque "subscript out of bounds" far from this
  # call site.
  if (length(dim(img)) < 3L || dim(img)[3] < 4L) {
    stop(sprintf(
      "check_gbif_tile_range: tile z=%d/x=%d/y=%d has %d channel(s), expected 4 (RGBA) -- GBIF's tile format may have changed.",
      zoom, x, y, if (length(dim(img)) < 3L) 1L else dim(img)[3]
    ), call. = FALSE)
  }
  img[, , 4]
}

#' 8-connected dilation of a logical matrix by one cell
#' Includes the cell itself (dr=0, dc=0) alongside its 8 neighbours, matching
#' standard morphological dilation -- an already-TRUE cell stays TRUE, and a
#' FALSE cell flips to TRUE only if it or any neighbour is TRUE. Verified
#' directly: dilating a 3x3 all-TRUE matrix with a single FALSE corner
#' produces an all-TRUE result (every one of that corner's neighbours is
#' TRUE), not a no-op -- correct region-growing behaviour.
#' @noRd
.dilate8 <- function(m) {
  nr <- nrow(m); nc <- ncol(m)
  padded <- matrix(FALSE, nr + 2L, nc + 2L)
  padded[2:(nr + 1L), 2:(nc + 1L)] <- m
  out <- matrix(FALSE, nr, nc)
  for (dr in -1:1) {
    for (dc in -1:1) {
      out <- out | padded[(2L + dr):(nr + 1L + dr), (2L + dc):(nc + 1L + dc)]
    }
  }
  out
}

#' Size (in cells) of the 8-connected occupied blob containing (seed_row, seed_col)
#' Vectorised region growing (repeated dilation intersected with the
#' presence mask) rather than a per-cell flood fill. Cost is dominated by
#' iteration count, which scales with the patch's real geometric extent, not
#' its cell count -- confirmed empirically against a real, densely-covering
#' species (American Robin, Ohio): a small isolated patch (52 cells, the
#' real round-goby/Burns-Harbor case) converges in 9 iterations, but a
#' patch spanning most of a 3-tile mosaic needed 65 (~3.8s just for growth).
#' Since a widespread patch IS the "not a rarity report" signal on its own
#' -- its exact size isn't needed to draw that conclusion -- max_iter is
#' capped low (default 15, chosen from the real isolated-patch case above
#' plus margin) so latency stays bounded regardless of species; `capped`
#' tells the caller the reported size is a lower bound, not exact.
#' @noRd
.grow_patch_size <- function(presence, seed_row, seed_col, max_iter = 15L) {
  region <- matrix(FALSE, nrow(presence), ncol(presence))
  region[seed_row, seed_col] <- TRUE
  capped <- TRUE
  for (i in seq_len(max_iter)) {
    grown <- .dilate8(region) & presence
    if (identical(grown, region)) {
      capped <- FALSE
      break
    }
    region <- grown
  }
  list(size = sum(region), capped = capped)
}
