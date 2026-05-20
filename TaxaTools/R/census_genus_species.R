utils::globalVariables(c("taxonomicStatus", "rank", "canonicalName"))

#' Census described species within genera (or higher ranks) via GBIF backbone
#'
#' Queries the GBIF backbone taxonomy to enumerate all described species within
#' each queried taxon. Optionally compares against a reference species list
#' (e.g., from a match object) to classify genera by completeness.
#'
#' @param genus_keys Named integer vector: names are taxon names (e.g., genus
#'   names), values are GBIF usageKeys. Obtain from GBIF occurrence data
#'   (`genusKey` column) or from `rgbif::name_backbone()`.
#' @param match_species Character vector of species already in the reference
#'   database (e.g., `unique(match_df$species)`). If provided, the function
#'   computes per-genus completeness: how many described species are missing
#'   from the reference. If NULL (default), only the GBIF census is returned
#'   without reference comparison.
#' @param rank Character string indicating the rank of the input keys. Default
#'   `"genus"`. For higher ranks (e.g., `"family"`, `"order"`), the function
#'   recursively enumerates child genera, then species within each genus.
#' @param status_filter Character vector of GBIF `taxonomicStatus` values to
#'   include. Default `"ACCEPTED"`. Set to `c("ACCEPTED", "DOUBTFUL")` to
#'   include taxonomically uncertain species.
#' @param verbose Logical. If TRUE (default), prints progress messages.
#'
#' @return A data frame with one row per queried taxon (genus or higher rank):
#'
#' \describe{
#'   \item{group}{Character. Taxon name (genus/family/order).}
#'   \item{gbif_key}{Integer. GBIF usageKey used for the query.}
#'   \item{total_described}{Integer. Number of accepted species in GBIF backbone.}
#'   \item{in_reference}{Integer. Species found in `match_species` (NA if
#'     `match_species` not provided).}
#'   \item{n_missing}{Integer. `total_described - in_reference` (NA if
#'     `match_species` not provided).}
#'   \item{missing_species}{List-column. Character vector of missing species
#'     names per genus (empty list if `match_species` not provided or genus
#'     is complete).}
#'   \item{described_species}{List-column. Character vector of all described
#'     species names per genus.}
#'   \item{status}{Character. `"complete"`, `"singleton_missing"`, or
#'     `"incomplete"` (NA if `match_species` not provided).}
#' }
#'
#' The complete species list across all queried taxa is available as
#' `attr(result, "all_species")` (a flat character vector).
#'
#' @details
#' For `rank = "genus"`, the function makes one GBIF API call per genus
#' (`rgbif::name_usage(key, data = "children")`). For higher ranks (family,
#' order), it first retrieves child genera, then recurses into each genus —
#' this can be slow for large families (e.g., Gobiidae with 300+ genera).
#'
#' The `status` column classifies each genus by reference completeness:
#' \itemize{
#'   \item `"complete"`: all described species are in the reference (n_missing == 0).
#'     H2 "unreferenced species" hypotheses should be suppressed.
#'   \item `"singleton_missing"`: exactly one described species is missing
#'     (n_missing == 1). The H2 hypothesis can be named directly.
#'   \item `"incomplete"`: multiple described species are missing (n_missing > 1).
#'     A generic H2 phantom is appropriate.
#' }
#'
#' @examples
#' \dontrun{
#' # Census species in genus Clevelandia (GBIF key 2394389)
#' census <- census_genus_species(c(Clevelandia = 2394389))
#'
#' # With reference comparison
#' census <- census_genus_species(
#'   c(Clevelandia = 2394389, Fundulus = 2347676),
#'   match_species = c("Clevelandia ios", "Fundulus parvipinnis")
#' )
#' }
#'
#' @export
census_genus_species <- function(genus_keys,
                                 match_species = NULL,
                                 rank = "genus",
                                 status_filter = "ACCEPTED",
                                 verbose = TRUE) {


  # --- Input validation ---
  if (length(genus_keys) == 0L) {
    stop("`genus_keys` must be a named vector with length >= 1.", call. = FALSE)
  }
  if (is.null(names(genus_keys)) || any(names(genus_keys) == "")) {
    stop("`genus_keys` must be named (names = taxon names, values = GBIF usageKeys).",
         call. = FALSE)
  }
  # Coerce character keys (from rgbif::name_backbone) to numeric
  if (is.character(genus_keys)) {
    nms <- names(genus_keys)
    genus_keys <- suppressWarnings(as.numeric(genus_keys))
    names(genus_keys) <- nms
  }
  if (!is.numeric(genus_keys) || any(is.na(genus_keys))) {
    stop("`genus_keys` values must be numeric (GBIF usageKeys).", call. = FALSE)
  }
  if (!is.null(match_species) && !is.character(match_species)) {
    stop("`match_species` must be a character vector or NULL.", call. = FALSE)
  }
  if (!is.character(rank) || length(rank) != 1L) {
    stop("`rank` must be a single character string.", call. = FALSE)
  }
  if (!is.character(status_filter) || length(status_filter) == 0L) {
    stop("`status_filter` must be a non-empty character vector.", call. = FALSE)
  }
  if (!requireNamespace("rgbif", quietly = TRUE)) {
    stop("Package 'rgbif' is required for census_genus_species(). ",
         "Install with: install.packages('rgbif')", call. = FALSE)
  }

  rank <- tolower(rank)

  # --- If rank is higher than genus, recurse: find child genera first ---
  if (rank != "genus") {
    return(.census_higher_rank(genus_keys, match_species, rank,
                               status_filter, verbose))
  }

  # --- Genus-level census ---
  all_species_flat <- character(0)
  results <- vector("list", length(genus_keys))

  for (i in seq_along(genus_keys)) {
    g_name <- names(genus_keys)[i]
    g_key  <- unname(genus_keys[i])

    if (verbose) {
      message(sprintf("Querying GBIF backbone: %s (key %d) [%d/%d]",
                      g_name, g_key, i, length(genus_keys)))
    }

    species_names <- tryCatch({
      .fetch_children_species(g_key, status_filter)
    }, error = function(e) {
      if (verbose) {
        message(sprintf("  Warning: GBIF query failed for %s: %s", g_name,
                        conditionMessage(e)))
      }
      character(0)
    })

    all_species_flat <- c(all_species_flat, species_names)

    # Compute reference comparison if match_species provided
    if (!is.null(match_species)) {
      missing <- setdiff(species_names, match_species)
      in_ref  <- length(species_names) - length(missing)
      n_miss  <- length(missing)
      status_val <- if (n_miss == 0L) {
        "complete"
      } else if (n_miss == 1L) {
        "singleton_missing"
      } else {
        "incomplete"
      }
    } else {
      missing    <- character(0)
      in_ref     <- NA_integer_
      n_miss     <- NA_integer_
      status_val <- NA_character_
    }

    results[[i]] <- data.frame(
      group           = g_name,
      gbif_key        = as.integer(g_key),
      total_described = length(species_names),
      in_reference    = as.integer(in_ref),
      n_missing       = as.integer(n_miss),
      stringsAsFactors = FALSE
    )
    results[[i]]$missing_species    <- list(missing)
    results[[i]]$described_species  <- list(species_names)
    results[[i]]$status             <- status_val
  }

  out <- do.call(rbind, results)
  rownames(out) <- NULL

  attr(out, "all_species") <- unique(all_species_flat)
  out
}


# --- Internal helpers ---

#' Fetch species children of a GBIF taxon key
#'
#' @param key Integer GBIF usageKey.
#' @param status_filter Character vector of taxonomicStatus values to keep.
#' @return Character vector of species binomials.
#' @noRd
.fetch_children_species <- function(key, status_filter) {
  # GBIF API returns paginated results; default limit is 100, max 1000

  resp <- rgbif::name_usage(key = key, data = "children", limit = 1000)

  if (is.null(resp$data) || nrow(resp$data) == 0L) {
    return(character(0))
  }

  children <- resp$data

  # Filter to species rank and accepted status
  if ("rank" %in% names(children)) {
    children <- children[toupper(children$rank) == "SPECIES", , drop = FALSE]
  }

  if ("taxonomicStatus" %in% names(children) && length(status_filter) > 0L) {
    children <- children[toupper(children$taxonomicStatus) %in%
                           toupper(status_filter), , drop = FALSE]
  }

  if (nrow(children) == 0L) return(character(0))

  # Use canonicalName (binomial without authorship)
  if ("canonicalName" %in% names(children)) {
    species <- children$canonicalName
  } else if ("species" %in% names(children)) {
    species <- children$species
  } else if ("scientificName" %in% names(children)) {
    species <- children$scientificName
  } else {
    return(character(0))
  }

  species[!is.na(species) & nzchar(species)]
}


#' Census described species for higher-rank taxa (family, order, etc.)
#'
#' Recursively enumerates child genera via GBIF backbone, then calls
#' `census_genus_species()` on each genus.
#'
#' @param keys Named integer vector of GBIF usageKeys.
#' @param match_species Character vector of reference species or NULL.
#' @param rank Character rank of the input keys.
#' @param status_filter Character vector of taxonomicStatus values.
#' @param verbose Logical.
#' @return Data frame in the same format as `census_genus_species()`.
#' @noRd
.census_higher_rank <- function(keys, match_species, rank,
                                status_filter, verbose) {

  all_genus_keys <- integer(0)
  all_genus_names <- character(0)

  for (i in seq_along(keys)) {
    parent_name <- names(keys)[i]
    parent_key  <- unname(keys[i])

    if (verbose) {
      message(sprintf("Enumerating genera in %s %s (key %d)...",
                      rank, parent_name, parent_key))
    }

    genera <- tryCatch({
      .fetch_children_genera(parent_key)
    }, error = function(e) {
      if (verbose) {
        message(sprintf("  Warning: GBIF query failed for %s: %s",
                        parent_name, conditionMessage(e)))
      }
      data.frame(name = character(0), key = integer(0),
                 stringsAsFactors = FALSE)
    })

    if (nrow(genera) > 0L) {
      all_genus_names <- c(all_genus_names, genera$name)
      all_genus_keys  <- c(all_genus_keys, genera$key)
      if (verbose) {
        message(sprintf("  Found %d genera in %s", nrow(genera), parent_name))
      }
    }
  }

  if (length(all_genus_keys) == 0L) {
    out <- data.frame(
      group = character(0), gbif_key = integer(0),
      total_described = integer(0), in_reference = integer(0),
      n_missing = integer(0), stringsAsFactors = FALSE
    )
    out$missing_species   <- list()
    out$described_species <- list()
    out$status            <- character(0)
    attr(out, "all_species") <- character(0)
    return(out)
  }

  genus_keys_named <- stats::setNames(all_genus_keys, all_genus_names)

  # Remove duplicates (same genus may appear under multiple parent taxa)
  genus_keys_named <- genus_keys_named[!duplicated(names(genus_keys_named))]

  census_genus_species(
    genus_keys   = genus_keys_named,
    match_species = match_species,
    rank         = "genus",
    status_filter = status_filter,
    verbose      = verbose
  )
}


#' Fetch child genera of a higher-rank GBIF taxon key
#'
#' @param key Integer GBIF usageKey for a family/order/etc.
#' @return Data frame with `name` and `key` columns.
#' @noRd
.fetch_children_genera <- function(key) {
  resp <- rgbif::name_usage(key = key, data = "children", limit = 1000)

  if (is.null(resp$data) || nrow(resp$data) == 0L) {
    return(data.frame(name = character(0), key = integer(0),
                      stringsAsFactors = FALSE))
  }

  children <- resp$data

  # Filter to genus rank and accepted status
  if ("rank" %in% names(children)) {
    children <- children[toupper(children$rank) == "GENUS", , drop = FALSE]
  }
  if ("taxonomicStatus" %in% names(children)) {
    children <- children[toupper(children$taxonomicStatus) == "ACCEPTED", ,
                         drop = FALSE]
  }

  if (nrow(children) == 0L) {
    return(data.frame(name = character(0), key = integer(0),
                      stringsAsFactors = FALSE))
  }

  name_col <- if ("canonicalName" %in% names(children)) {
    "canonicalName"
  } else {
    "scientificName"
  }

  data.frame(
    name = children[[name_col]],
    key  = as.integer(children$key),
    stringsAsFactors = FALSE
  )
}
