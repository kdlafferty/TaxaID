utils::globalVariables(c("taxon_name", "genus", "family", "family.local",
                          "family.api", "family.fb"))

#' Fill Higher Taxonomic Ranks from Local Data and Backbone APIs
#'
#' @description
#' Given a character vector of taxon names (typically species binomials), derives
#' `genus` (first word of the binomial) and looks up `family` using a
#' priority-ordered fallback chain:
#'
#' 1. **Local sources** — data frames already in scope (e.g. `reference_df`,
#'    `match_obj`, `gbif_std`).  Fast, offline, covers most cases.
#' 2. **Primary backbone** — `verify_taxon_names()` queried at genus level
#'    (`backbone_id`; default NCBI = 4).
#' 3. **Fallback backbone** — repeated with `fallback_backbone_id` (default
#'    GBIF = 11) for any genera still unresolved.
#'
#' Queries are made at the **genus level**, so species absent from a backbone
#' (e.g. newly described species, cross-backbone synonyms) are still resolved
#' provided their genus is present.
#'
#' @param taxon_names Character vector of taxon names.  Binomial species names
#'   are expected; genus is extracted as the first word.  Single-word names
#'   (genus only) are accepted and returned as-is in the `genus` column.
#' @param local_sources List of data frames to consult before any API call.
#'   Each element must contain at least `genus` and `family` columns; elements
#'   lacking those columns are silently skipped.  Sources are consulted in
#'   order; the first non-NA family for each genus wins.
#' @param backbone_id Integer.  Primary backbone for API fallback.
#'   Default `4L` (NCBI).  Set `NULL` to skip the API entirely.
#' @param fallback_backbone_id Integer.  Secondary backbone used when
#'   `backbone_id` returns no match.  Default `11L` (GBIF).  Set `NULL` or
#'   equal to `backbone_id` to skip.
#' @param verbose Logical.  Print progress messages for API lookups.
#'   Default `TRUE`.
#'
#' @return A tibble with one row per element of `taxon_names` (preserving
#'   duplicates and order), with columns:
#'   \describe{
#'     \item{`taxon_name`}{The original input name.}
#'     \item{`genus`}{First word of `taxon_name`, EXCEPT when an API lookup
#'       resolved that genus to a backbone-flagged synonym at genus rank --
#'       in that case the backbone's own currently-accepted genus name is
#'       returned instead (2026-07-25; see `@section Genus correction`
#'       below). Local-source-only lookups (no API call needed) always keep
#'       the locally-extracted genus unchanged.}
#'     \item{`family`}{Looked-up family, or `NA` if unresolved.}
#'   }
#'   A warning is issued for any names whose family could not be resolved after
#'   all fallbacks.
#'
#' @section Genus correction (2026-07-25):
#' Before this fix, `genus` was always the locally-extracted first word of
#' `taxon_name`, even when the API lookup showed that genus was a taxonomic
#' synonym under the queried backbone -- e.g. an informally-named reference
#' ("Inu sp. 1 sensu Shibukawa et al., 2020.") extracted `genus = "Inu"`,
#' and stayed `"Inu"` even though GBIF's own backbone resolves it to the
#' currently-accepted genus `"Luciogobius"`. This mattered beyond cosmetics:
#' `TaxaAssign::join_priors()` joins this function's `genus`/`family` output
#' against a likelihood-side coarse-rank `taxon_name` (produced by
#' `TaxaMatch::convert_taxonomy_backbone()`, which -- also as of 2026-07-25
#' -- prefers the current name over a synonym) via an EXACT STRING match. If
#' the two functions disagreed on which form to report for the same genus,
#' that join silently failed and the observation lost its coarse-rank
#' species expansion entirely, falling back to the dark-diversity floor
#' instead of real occurrence-based priors. `genus` is now corrected to the
#' backbone's resolved name whenever an API lookup found one cleanly at
#' genus rank, keeping this function consistent with
#' `convert_taxonomy_backbone()`. Verified backbone-general (both NCBI and
#' GBIF checked live for the real "Inu" case) before shipping.
#'
#' @details
#' **Backbone queries are at genus level.**  `verify_taxon_names()` is called
#' with the unique unresolved genera (not the full species names).  This means
#' a species absent from NCBI is still resolved provided its genus is present
#' — which covers the vast majority of cross-backbone synonym situations.
#'
#' **Column name conflicts in local sources** (e.g. a source has both `genus`
#' and `Genus`) are handled by `tolower(names(...))` before joining.
#'
#' @seealso [verify_taxon_names()], [parse_classification_path()]
#'
#' @examples
#' \dontrun{
#' unreferenced_df <- fill_higher_ranks(
#'   coverage$unreferenced,
#'   local_sources = list(reference_df, match_obj, gbif_std)
#' )
#' # rename for expand_unreferenced_hypotheses():
#' unreferenced_df <- dplyr::rename(unreferenced_df, species = taxon_name)
#' }
#'
#' @importFrom dplyr bind_rows filter distinct left_join mutate coalesce
#'   select any_of
#' @importFrom tibble tibble
#' @export
fill_higher_ranks <- function(taxon_names,
                               local_sources        = list(),
                               backbone_id          = 4L,
                               fallback_backbone_id = 11L,
                               verbose              = TRUE) {

  # ---- Input validation ------------------------------------------------------
  if (!is.character(taxon_names) || length(taxon_names) == 0L)
    stop("taxon_names must be a non-empty character vector")
  if (!is.list(local_sources))
    stop("local_sources must be a list of data frames")
  if (!is.null(backbone_id) && (!is.numeric(backbone_id) ||
      length(backbone_id) != 1L || is.na(backbone_id)))
    stop("backbone_id must be a single integer or NULL")
  if (!is.null(fallback_backbone_id) && (!is.numeric(fallback_backbone_id) ||
      length(fallback_backbone_id) != 1L || is.na(fallback_backbone_id)))
    stop("fallback_backbone_id must be a single integer or NULL")
  if (!is.logical(verbose) || length(verbose) != 1L || is.na(verbose))
    stop("verbose must be TRUE or FALSE")

  # ---- Working table: unique non-NA names + extracted genus ------------------
  all_names  <- taxon_names
  valid_mask <- !is.na(taxon_names) & nzchar(trimws(taxon_names))

  work <- tibble::tibble(
    taxon_name = unique(taxon_names[valid_mask]),
    genus      = sub(" .*", "", unique(taxon_names[valid_mask])),
    family     = NA_character_
  )

  # ---- Step 1: Local sources -------------------------------------------------
  local_lookup <- .build_genus_family_lookup(local_sources)

  if (nrow(local_lookup) > 0L) {
    na_idx  <- is.na(work$family)
    if (any(na_idx)) {
      filled <- dplyr::left_join(
        work[na_idx, c("taxon_name", "genus"), drop = FALSE],
        local_lookup, by = "genus"
      )
      work$family[na_idx] <- filled$family
    }
  }

  # ---- Step 2: Primary backbone API (genus-level query) ----------------------
  missing_genera <- unique(work$genus[is.na(work$family)])

  if (length(missing_genera) > 0L && !is.null(backbone_id)) {
    if (verbose) message(sprintf(
      "fill_higher_ranks: %d genera not in local sources; querying backbone %d...",
      length(missing_genera), as.integer(backbone_id)
    ))
    api_lookup <- .lookup_family_from_backbone(missing_genera,
                                                as.integer(backbone_id))
    if (nrow(api_lookup) > 0L) {
      na_idx <- is.na(work$family)
      if (any(na_idx)) {
        filled <- dplyr::left_join(
          work[na_idx, c("taxon_name", "genus"), drop = FALSE],
          api_lookup, by = "genus"
        )
        work$family[na_idx] <- filled$family
        # Correct genus to the backbone's resolved form wherever a match was
        # actually found (in lockstep with family above -- resolved_genus is
        # only non-NA for rows that also passed the family filter inside
        # .lookup_family_from_backbone()); coalesce leaves genus unchanged
        # for any row that didn't match at all.
        work$genus[na_idx] <- dplyr::coalesce(filled$resolved_genus, work$genus[na_idx])
      }
    }
  }

  # ---- Step 3: Fallback backbone ---------------------------------------------
  still_missing <- unique(work$genus[is.na(work$family)])

  if (length(still_missing) > 0L &&
      !is.null(fallback_backbone_id) &&
      !identical(as.integer(fallback_backbone_id), as.integer(backbone_id))) {
    if (verbose) message(sprintf(
      "fill_higher_ranks: %d genera still unresolved; trying fallback backbone %d...",
      length(still_missing), as.integer(fallback_backbone_id)
    ))
    fb_lookup <- .lookup_family_from_backbone(still_missing,
                                               as.integer(fallback_backbone_id))
    if (nrow(fb_lookup) > 0L) {
      na_idx <- is.na(work$family)
      if (any(na_idx)) {
        filled <- dplyr::left_join(
          work[na_idx, c("taxon_name", "genus"), drop = FALSE],
          fb_lookup, by = "genus"
        )
        work$family[na_idx] <- filled$family
        work$genus[na_idx] <- dplyr::coalesce(filled$resolved_genus, work$genus[na_idx])
      }
    }
  }

  # ---- Warn about any remaining NAs ------------------------------------------
  n_na <- sum(is.na(work$family))
  if (n_na > 0L) {
    unresolved <- work$taxon_name[is.na(work$family)]
    warning(sprintf(
      "fill_higher_ranks: %d taxon(s) have no family after all lookups:\n  %s",
      n_na, paste(unresolved, collapse = "\n  ")
    ), call. = FALSE)
  }

  # ---- Re-expand to original length (preserve duplicates and order) ----------
  result_map <- work[, c("taxon_name", "genus", "family"), drop = FALSE]

  out <- tibble::tibble(taxon_name = all_names)
  out$genus  <- result_map$genus[match(all_names, result_map$taxon_name)]
  out$family <- result_map$family[match(all_names, result_map$taxon_name)]

  # NAs for originally-NA/blank inputs
  out$genus[!valid_mask]  <- NA_character_
  out$family[!valid_mask] <- NA_character_

  out
}


# ==============================================================================
# Exported helper: parse_classification_path()
# ==============================================================================

#' Parse a Rank Value from a Pipe-Delimited Classification Path
#'
#' @description
#' Extracts a single rank value from the `classification_path` and
#' `classification_ranks` columns returned by [verify_taxon_names()].
#' Both columns use `|` as a delimiter and are positionally aligned.
#'
#' @param path Character scalar.  Pipe-delimited taxon names, e.g.
#'   `"Animalia|Chordata|Cottidae|Cottus"`.
#' @param ranks Character scalar.  Pipe-delimited rank labels aligned
#'   with `path`, e.g. `"kingdom|phylum|family|genus"`.
#' @param target_rank Character scalar.  The rank to extract, e.g.
#'   `"family"` or `"order"`.
#'
#' @return The matched taxon name string, or `NA_character_` if
#'   `target_rank` is not present in `ranks` or inputs are `NA`.
#'
#' @details
#' This function is vectorised over `path` and `ranks` via [mapply()].
#' To parse an entire column from [verify_taxon_names()] output use:
#'
#' ```r
#' verified <- verify_taxon_names(stringr::word(species_names, 1))
#' families <- mapply(
#'   parse_classification_path,
#'   verified$classification_path,
#'   verified$classification_ranks,
#'   MoreArgs = list(target_rank = "family")
#' )
#' ```
#'
#' @seealso [verify_taxon_names()], [fill_higher_ranks()]
#'
#' @examples
#' parse_classification_path(
#'   path        = "Animalia|Chordata|Cottidae|Cottus",
#'   ranks       = "kingdom|phylum|family|genus",
#'   target_rank = "family"
#' )
#' # [1] "Cottidae"
#'
#' parse_classification_path(
#'   path        = "Animalia|Chordata|Cottidae|Cottus",
#'   ranks       = "kingdom|phylum|family|genus",
#'   target_rank = "order"
#' )
#' # [1] NA
#'
#' @export
parse_classification_path <- function(path, ranks, target_rank) {
  .extract_classified_rank(path, ranks, target_rank)
}


# ==============================================================================
# Internal helpers
# ==============================================================================

# Build a genus→family lookup from a list of data frames.
# Each source must have genus + family columns (case-insensitive check).
# Returns a tibble(genus, family) with no NAs and first-source-wins dedup.
#' @noRd
.build_genus_family_lookup <- function(sources) {
  parts <- lapply(sources, function(df) {
    if (!is.data.frame(df)) return(NULL)
    names(df) <- tolower(names(df))
    if (!all(c("genus", "family") %in% names(df))) return(NULL)
    df[, c("genus", "family"), drop = FALSE]
  })
  parts <- Filter(Negate(is.null), parts)
  if (length(parts) == 0L)
    return(tibble::tibble(genus = character(), family = character()))

  dplyr::bind_rows(parts) |>
    dplyr::filter(!is.na(genus), !is.na(family),
                  nzchar(trimws(genus)), nzchar(trimws(family))) |>
    dplyr::distinct(genus, .keep_all = TRUE)
}


# Query verify_taxon_names() for a vector of genera, then parse family from
# classification_path + classification_ranks (pipe-delimited).
# Returns tibble(genus, resolved_genus, family). `genus` is always the QUERY
# genus (the join key back to the caller's own `work` table); `resolved_genus`
# is the backbone's own resolved name when the match cleanly resolved at
# genus rank, NA otherwise -- kept separate from `genus` so the caller can
# still join on the original spelling while writing the corrected value back.
#' @noRd
.lookup_family_from_backbone <- function(genera, backbone_id) {
  empty <- tibble::tibble(genus = character(), resolved_genus = character(),
                          family = character())

  verified <- tryCatch(
    verify_taxon_names(genera, backbone_id = backbone_id),
    error = function(e) {
      warning(sprintf(
        "fill_higher_ranks: backbone %d query failed: %s",
        backbone_id, conditionMessage(e)
      ), call. = FALSE)
      NULL
    }
  )

  if (is.null(verified) || nrow(verified) == 0L) return(empty)

  families <- mapply(
    .extract_classified_rank,
    verified$classification_path,
    verified$classification_ranks,
    MoreArgs = list(target_rank = "family"),
    SIMPLIFY  = TRUE
  )

  # Prefer the backbone's own resolved genus over the query genus when the
  # match cleanly resolved at genus rank -- keeps this function consistent
  # with TaxaMatch::convert_taxonomy_backbone()'s own current-name preference
  # (2026-07-25): a genus that is a taxonomic synonym under this backbone
  # (confirmed real case: GBIF resolves "Inu" to "Luciogobius") is now
  # reported the same way regardless of which function in the ecosystem
  # touched it, instead of being split across two different labels depending
  # on whether a taxon's genus was derived here or via convert_taxonomy_
  # backbone() -- exactly the mismatch that silently broke
  # TaxaAssign::join_priors()'s exact-string genus/family match between the
  # likelihood side and the priors side. `matched_rank` is present only from
  # a `verify_taxon_names()` built 2026-07-25 or later; absent, this is a
  # no-op and `genus` passes through unchanged, matching the old behavior.
  has_matched_rank <- "matched_rank" %in% names(verified)
  resolved_genus <- if (has_matched_rank) {
    ifelse(
      !is.na(verified$matched_rank) & verified$matched_rank == "genus" &
        !is.na(verified$matched_name) & nzchar(verified$matched_name),
      verified$matched_name,
      NA_character_
    )
  } else {
    rep(NA_character_, nrow(verified))
  }

  result <- tibble::tibble(
    genus          = verified$user_supplied_name,
    resolved_genus = resolved_genus,
    family         = families
  ) |>
    dplyr::filter(!is.na(family), nzchar(trimws(family))) |>
    dplyr::distinct(genus, .keep_all = TRUE)

  result
}


# Parse one rank value from pipe-delimited classification_path +
# classification_ranks strings.  Returns NA_character_ if rank not found.
#' @noRd
.extract_classified_rank <- function(path, ranks, target_rank) {
  if (is.na(path) || is.na(ranks) || !nzchar(path) || !nzchar(ranks))
    return(NA_character_)
  rank_vec <- strsplit(ranks, "|", fixed = TRUE)[[1L]]
  path_vec <- strsplit(path,  "|", fixed = TRUE)[[1L]]
  idx <- which(rank_vec == target_rank)
  if (length(idx) == 0L || idx[1L] > length(path_vec))
    return(NA_character_)
  path_vec[idx[1L]]
}
