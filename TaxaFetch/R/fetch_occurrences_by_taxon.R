# ==============================================================================
# fetch_occurrences_by_taxon.R
# TaxaFetch -- taxon-centric batched GBIF occurrence fetch. Groups a fetch
# scope by taxon key (instead of by observation/site) so that overlapping or
# identical search areas for the same taxon are queried exactly once, and
# different taxa sharing an identical search area are combined into one
# call. See ecosystem_docs/REENTRY_PROMPT_session139_gbif_fetch_efficiency.md
# for the design discussion this implements.
# ==============================================================================

#' Fetch GBIF Occurrences Grouped by Taxon Key
#'
#' Given a fetch scope expressed as one row per (site, candidate taxon) pair,
#' unions the search geometry for each distinct taxon key and issues exactly
#' one \code{\link{get_gbif_occurrences}} call per taxon key (or per group of
#' taxon keys that end up sharing an identical unioned geometry -- see
#' \code{combine_shared_geometry}). This avoids two problems that arise when
#' occurrence fetches are instead grouped by observation/site: (1) the same
#' GBIF record can be counted twice if two separately-issued queries for the
#' same taxon have overlapping search geometry, and (2) unrelated round trips
#' are issued when several taxa share the exact same search area.
#'
#' @param taxon_geometry_map A data frame with (at least) columns
#'   \code{taxon_key} (integer or numeric GBIF usage key) and \code{geometry}
#'   (character, one WKT polygon per row -- see \code{\link{make_bbox_wkt}} /
#'   \code{\link[TaxaTools]{define_search_polygon}}). One row per (site,
#'   candidate taxon) pair: the same \code{taxon_key} may appear in multiple
#'   rows (different sites where that taxon is a genuine candidate), and the
#'   same \code{geometry} may appear for multiple \code{taxon_key} values
#'   (several taxa considered over the same search area). Rows with
#'   \code{NA}/empty \code{taxon_key} or \code{geometry} are dropped; exact
#'   duplicate rows are dropped before unioning.
#' @param year_range,limit Forwarded to \code{\link{get_gbif_occurrences}}.
#' @param combine_shared_geometry Logical. Default \code{TRUE}. After
#'   unioning each taxon key's own geometry, taxon keys whose resulting
#'   unioned geometry is identical are combined into a single multi-key call
#'   -- different taxa over the same search area is a clean win to combine
#'   (no wasted download volume either way, just one fewer round trip). Set
#'   \code{FALSE} to always issue one call per taxon key.
#' @param ... Forwarded to \code{\link{get_gbif_occurrences}} (e.g.
#'   \code{key_threshold}, \code{rank_filter}, \code{columns}, \code{cache_dir},
#'   \code{overwrite}, \code{exclude_absent}, \code{basis_keep}).
#'
#' @return A tibble, same schema as \code{\link{get_gbif_occurrences}}
#'   (records from every issued query, row-bound).
#'
#' @details
#' \strong{What this does not (yet) handle:} GBIF's occurrence search API has
#' a real, uncharacterized WKT-complexity ceiling (\code{rgbif::occ_data()}
#' ships a \code{geom_big}/\code{geom_size}/\code{geom_n} escape valve for
#' this, which \code{get_gbif_occurrences()} does not currently expose) --
#' unioning a very large number of disjoint site geometries into one
#' \code{MULTIPOLYGON} could in principle hit this, and this function does
#' not guard against it. A combined query covering more area/taxa can also
#' return more total matching records than any of the original separate
#' queries would have, which interacts with \code{get_gbif_occurrences()}'s
#' own per-key \code{limit} in a way that has not been characterized. Neither
#' limitation is silently masked here -- if GBIF's API rejects an
#' over-complex geometry, the underlying \code{get_gbif_occurrences()} call
#' will error as it would for any other invalid geometry.
#'
#' @seealso \code{\link{get_gbif_occurrences}}, \code{\link{make_bbox_wkt}},
#'   \code{\link{get_keys_from_context}}
#'
#' @importFrom dplyr bind_rows
#' @importFrom sf st_as_sfc st_union st_as_text
#' @export
#'
#' @examples
#' \dontrun{
#' # Two sites, overlapping local boxes, both candidates for the same genus
#' box_a <- make_bbox_wkt(lat = 34.40, lon = -120.41, radius_deg = 0.05)
#' box_b <- make_bbox_wkt(lat = 34.47, lon = -120.36, radius_deg = 0.05)
#' key   <- get_keys_from_context(data.frame(genus = "Sebastes"))$usageKey
#'
#' taxon_geometry_map <- data.frame(
#'   taxon_key = c(key, key),
#'   geometry  = c(box_a, box_b)
#' )
#'
#' # One query over the union of both boxes, not two overlapping queries
#' occ <- fetch_occurrences_by_taxon(taxon_geometry_map, year_range = "2000,2024")
#' }
fetch_occurrences_by_taxon <- function(taxon_geometry_map,
                                        year_range = "2000,2024",
                                        limit = NULL,
                                        combine_shared_geometry = TRUE,
                                        ...) {

  # --- Input checks ---------------------------------------------------------
  if (!is.data.frame(taxon_geometry_map)) {
    stop("fetch_occurrences_by_taxon: 'taxon_geometry_map' must be a data frame.",
         call. = FALSE)
  }
  required_cols <- c("taxon_key", "geometry")
  missing_cols  <- setdiff(required_cols, names(taxon_geometry_map))
  if (length(missing_cols) > 0L) {
    stop(sprintf(
      "fetch_occurrences_by_taxon: 'taxon_geometry_map' is missing required column(s): %s",
      paste(missing_cols, collapse = ", ")
    ), call. = FALSE)
  }
  if (!is.logical(combine_shared_geometry) || length(combine_shared_geometry) != 1L ||
      is.na(combine_shared_geometry)) {
    stop("fetch_occurrences_by_taxon: 'combine_shared_geometry' must be TRUE or FALSE.",
         call. = FALSE)
  }

  map <- taxon_geometry_map[, required_cols, drop = FALSE]
  map$taxon_key <- suppressWarnings(as.integer(map$taxon_key))
  map$geometry  <- as.character(map$geometry)
  map <- map[!is.na(map$taxon_key) & !is.na(map$geometry) & nzchar(map$geometry), , drop = FALSE]
  map <- unique(map)

  if (nrow(map) == 0L) {
    stop("fetch_occurrences_by_taxon: no valid (taxon_key, geometry) rows after cleaning.",
         call. = FALSE)
  }

  # --- Union geometry per taxon key ------------------------------------------
  taxon_keys <- unique(map$taxon_key)
  unioned    <- vector("character", length(taxon_keys))

  for (i in seq_along(taxon_keys)) {
    geoms     <- map$geometry[map$taxon_key == taxon_keys[i]]
    sfc       <- sf::st_as_sfc(geoms, crs = 4326)
    unioned[i] <- sf::st_as_text(sf::st_union(sfc))
  }

  per_taxon <- data.frame(
    taxon_key = taxon_keys,
    geometry  = unioned,
    stringsAsFactors = FALSE
  )

  # --- Combine taxa sharing an identical unioned geometry --------------------
  query_groups <- if (isTRUE(combine_shared_geometry)) {
    split(per_taxon$taxon_key, per_taxon$geometry)
  } else {
    split(per_taxon$taxon_key, per_taxon$taxon_key)
  }

  message(sprintf(
    "fetch_occurrences_by_taxon: %d taxon key(s) -> %d GBIF quer%s.",
    length(taxon_keys), length(query_groups),
    if (length(query_groups) == 1L) "y" else "ies"
  ))

  geom_lookup <- stats::setNames(per_taxon$geometry, as.character(per_taxon$taxon_key))

  results <- vector("list", length(query_groups))
  for (i in seq_along(query_groups)) {
    keys_i <- query_groups[[i]]
    geom_i <- geom_lookup[[as.character(keys_i[1L])]]
    results[[i]] <- get_gbif_occurrences(
      keys       = keys_i,
      geometry   = geom_i,
      year_range = year_range,
      limit      = limit,
      ...
    )
  }

  dplyr::bind_rows(results)
}
