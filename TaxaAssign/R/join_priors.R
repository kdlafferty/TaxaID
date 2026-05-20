utils::globalVariables(c(
  "taxon_name", "taxon_name_rank", "grid_id", "main_habitat",
  "undetected_type", "alpha", "beta", "prior_mean", "prior_alpha", "prior_beta",
  "genus", "family", "family.fill", "dark_alpha", "dark_beta"
))

#' Join Likelihoods to TaxaExpect Priors
#'
#' Bridges the gap between TaxaLikely likelihoods and
#' [compute_posterior()]: maps each `observation_id` to a site, joins
#' occurrence-based priors from TaxaExpect, applies a dark diversity
#' fallback for species with no modelled prior, deduplicates, fills
#' missing taxonomy columns, and removes redundant higher-rank
#' hypotheses.
#'
#' ## Site specification
#' The `site` argument accepts two forms:
#' \describe{
#'   \item{Named list (single-site)}{All observations are assigned the same
#'     `grid_id` and `main_habitat`. This is the most common case.
#'     Example: `list(grid_id = "Grid_34p1_m119p1",
#'     main_habitat = "Estuarine Bay")`.}
#'   \item{Data frame (multi-site)}{One row per `observation_id` with
#'     columns `observation_id`, `grid_id`, `main_habitat`. Use when
#'     observations come from different locations.}
#' }
#'
#' ## Dark diversity fallback
#' Dark diversity is an ecological concept: the set of species that
#' belong to the regional species pool and could inhabit a site given
#' its environmental conditions, but have not been observed there. In
#' TaxaAssign, species with no TaxaExpect prior (e.g., referenced
#' species not expected at the site) receive a dark diversity prior:
#' the mean `alpha` and `beta` from Tier 3 (undetected) rows in
#' `taxaexpect_priors` for the same `grid_id` x `main_habitat`.
#' If no site-level Tier 3 rows exist, a global average across all
#' Tier 3 rows is used. This ensures that every hypothesis has a
#' non-zero prior, reflecting the possibility that unobserved species
#' could be present.
#'
#' ## Deduplication and redundancy filtering
#' After the join, rows are deduplicated on `observation_id` x
#' `taxon_name` x `taxon_name_rank` (keeping the highest
#' `prior_mean`). Genus-rank rows with missing taxonomy are filled
#' from `taxon_name` and propagated from other rows sharing the same
#' genus. Finally, [TaxaMatch::filter_redundant_hypotheses()] removes
#' coarser-rank rows superseded by finer-rank rows in the same
#' lineage.
#'
#' @param likelihoods Data frame of likelihoods, typically from
#'   [TaxaLikely::apply_coverage_constraints()] or
#'   [expand_unreferenced_hypotheses()]. Must contain `observation_id`,
#'   `taxon_name`, `taxon_name_rank`.
#' @param taxaexpect_priors Data frame of TaxaExpect priors. One row
#'   per `taxon_name` x `grid_id` x `main_habitat`, with columns
#'   `alpha`, `beta`, `undetected_type`, and taxonomy columns
#'   (`genus`, `family`, etc.).
#' @param site Site specification including habitat. \code{main_habitat}
#'   is always required — the function does not guess which habitat your
#'   observations came from. Accepted formats:
#'   \describe{
#'     \item{Named list with lat/lon}{\code{list(lat = 34.1, lon = -119.1,
#'       main_habitat = "Marine")} — auto-resolves to nearest grid_id.}
#'     \item{Named list with grid_id}{\code{list(grid_id = "...",
#'       main_habitat = "Marine")}}
#'     \item{Data frame (multi-site)}{Columns \code{observation_id},
#'       \code{grid_id}, \code{main_habitat}. Or \code{observation_id},
#'       \code{lat}, \code{lon}, \code{main_habitat}.}
#'   }
#'   If \code{main_habitat} is omitted, the error message lists available
#'   habitats and row counts at the resolved grid cell.
#'   See Details.
#' @param taxonomy_lookup Optional data frame mapping `taxon_name` to
#'   taxonomy columns (e.g. `genus`, `family`). Used to fill taxonomy
#'   for species that have likelihoods but are absent from
#'   `taxaexpect_priors`. Typically built from `match_df` columns.
#'   Default `NULL` (no external taxonomy fill).
#' @param rank_system Character vector of taxonomic ranks from
#'   coarsest to finest. Passed to
#'   [TaxaMatch::filter_redundant_hypotheses()]. Default `NULL`
#'   auto-detects from columns in `likelihoods`.
#'
#' @return A data frame ready for [compute_posterior()], with columns
#'   `prior_mean`, `prior_alpha`, and `prior_beta` added. All input columns are
#'   preserved. Additional columns from `taxaexpect_priors`
#'   (e.g. `alpha`, `beta`, `model_tier`) are included from the
#'   join.
#'
#' @seealso [compute_posterior()], [expand_unreferenced_hypotheses()],
#'   [TaxaLikely::apply_coverage_constraints()]
#'
#' @examples
#' \dontrun{
#' joined <- join_priors(
#'   likelihoods     = expanded_likelihoods,
#'   taxaexpect_priors = priors,
#'   site            = list(grid_id = "Grid_34p4_m119p8", main_habitat = "Marine")
#' )
#' }
#'
#' @importFrom dplyr left_join distinct filter mutate select arrange
#'   group_by summarise coalesce if_else desc
#' @importFrom rlang .data
#' @export
join_priors <- function(likelihoods,
                        taxaexpect_priors,
                        site = NULL,
                        taxonomy_lookup = NULL,
                        rank_system = NULL) {


  # ---- Input validation -----------------------------------------------------
  if (!is.data.frame(likelihoods)) {
    cli::cli_abort("{.arg likelihoods} must be a data frame.")
  }

  needed_lik <- c("observation_id", "taxon_name", "taxon_name_rank")
  missing_lik <- setdiff(needed_lik, names(likelihoods))
  if (length(missing_lik) > 0L) {
    cli::cli_abort(
      "{.arg likelihoods} is missing required column(s): {.field {missing_lik}}"
    )
  }

  if (!is.data.frame(taxaexpect_priors)) {
    cli::cli_abort("{.arg taxaexpect_priors} must be a data frame.")
  }

  needed_priors <- c("taxon_name", "taxon_name_rank",
                     "grid_id", "main_habitat", "alpha", "beta")
  missing_priors <- setdiff(needed_priors, names(taxaexpect_priors))
  if (length(missing_priors) > 0L) {
    cli::cli_abort(
      "{.arg taxaexpect_priors} is missing required column(s): {.field {missing_priors}}"
    )
  }

  # Auto-detect rank_system from likelihoods columns
  if (is.null(rank_system)) {
    rank_system <- TaxaTools::detect_ranks(likelihoods, warn = FALSE)
    if (length(rank_system) == 0L)
      rank_system <- c("family", "genus", "species")
    cli::cli_inform(
      "join_priors: auto-detected rank_system: {paste(rank_system, collapse = ', ')}"
    )
  }

  if (!is.character(rank_system) || length(rank_system) < 2L) {
    cli::cli_abort("{.arg rank_system} must be a character vector of length >= 2.")
  }

  # ---- Build event_meta from `site` ----------------------------------------

  # NULL default: require site with main_habitat
  if (is.null(site)) {
    search_center <- attr(taxaexpect_priors, "search_center")
    if (!is.null(search_center) &&
        !is.null(search_center$lat) && !is.null(search_center$lon)) {
      cli::cli_abort(c(
        "{.arg site} is required, including {.arg main_habitat}.",
        "i" = "Coordinates from build_priors() are available: ({search_center$lat}, {search_center$lon}).",
        "i" = 'Use: site = list(lat = {search_center$lat}, lon = {search_center$lon}, main_habitat = "...")'
      ))
    } else {
      cli::cli_abort(c(
        "{.arg site} is required, including {.arg main_habitat}.",
        "i" = 'Use: site = list(lat = ..., lon = ..., main_habitat = "...")',
        "i" = 'Or:  site = list(grid_id = "...", main_habitat = "...")'
      ))
    }
  }

  # Character shortcut: bare grid_id string — require main_habitat

  if (is.character(site) && length(site) == 1L) {
    grid_rows <- taxaexpect_priors[taxaexpect_priors$grid_id == site &
                                     !is.na(taxaexpect_priors$main_habitat), ]
    if (nrow(grid_rows) == 0L) {
      cli::cli_abort(
        "grid_id {.val {site}} not found in {.arg taxaexpect_priors}."
      )
    }
    hab_counts <- table(grid_rows$main_habitat)
    counts_str <- paste(
      sprintf("  \"%s\" (%d prior rows)", names(hab_counts),
              as.integer(hab_counts)),
      collapse = "\n"
    )
    cli::cli_abort(c(
      "{.arg main_habitat} is required when specifying a grid_id.",
      "i" = "Available habitats at {.val {site}}:",
      " " = counts_str,
      "i" = 'Use: site = list(grid_id = "{site}", main_habitat = "...")'
    ))
  }

  if (is.list(site) && !is.data.frame(site)) {

    # lat/lon path: resolve to nearest existing grid_id in priors
    if (all(c("lat", "lon") %in% names(site))) {
      resolved <- .latlon_to_grid(
        lat               = site$lat,
        lon               = site$lon,
        main_habitat      = site$main_habitat,
        taxaexpect_priors = taxaexpect_priors
      )
      site$grid_id      <- resolved$grid_id
      site$main_habitat <- resolved$main_habitat
    }

    # Single-site shortcut
    needed_site <- c("grid_id", "main_habitat")
    missing_site <- setdiff(needed_site, names(site))
    if (length(missing_site) > 0L) {
      cli::cli_abort(
        "{.arg site} list is missing element(s): {.field {missing_site}}. Supply (grid_id + main_habitat) or (lat + lon)."
      )
    }
    event_meta <- data.frame(
      observation_id    = unique(likelihoods$observation_id),
      grid_id      = site$grid_id,
      main_habitat = site$main_habitat,
      stringsAsFactors = FALSE
    )
    cli::cli_inform(
      "Single-site mode: all {nrow(event_meta)} observation(s) mapped to {.val {site$grid_id}} / {.val {site$main_habitat}}."
    )
  } else if (is.data.frame(site)) {
    # Multi-site
    needed_site <- c("observation_id", "grid_id", "main_habitat")
    missing_site <- setdiff(needed_site, names(site))
    if (length(missing_site) > 0L) {
      cli::cli_abort(
        "{.arg site} data frame is missing column(s): {.field {missing_site}}"
      )
    }
    event_meta <- site

    # Warn about likelihood observation_ids not in site
    lik_ids  <- unique(likelihoods$observation_id)
    site_ids <- unique(event_meta$observation_id)
    unmapped <- setdiff(lik_ids, site_ids)
    if (length(unmapped) > 0L) {
      cli::cli_warn(
        "{length(unmapped)} observation_id(s) in {.arg likelihoods} have no entry in {.arg site}. These will receive NA priors."
      )
    }
  } else {
    cli::cli_abort(
      "{.arg site} must be a named list (single-site) or a data frame (multi-site)."
    )
  }

  # ---- Validate site combos exist in taxaexpect_priors -----------------------
  site_combos <- dplyr::distinct(event_meta, grid_id, main_habitat)
  missing_combos <- dplyr::anti_join(
    site_combos, taxaexpect_priors,
    by = c("grid_id", "main_habitat")
  )
  if (nrow(missing_combos) > 0L) {
    # Find nearest existing grid_id for each missing combo
    all_grids <- unique(taxaexpect_priors$grid_id[!is.na(taxaexpect_priors$grid_id)])
    grid_coords <- .parse_grid_ids(all_grids)

    combo_labels <- vapply(seq_len(nrow(missing_combos)), function(j) {
      gid <- missing_combos$grid_id[j]
      hab <- missing_combos$main_habitat[j]
      # Parse the missing grid_id to coordinates
      parsed <- tryCatch(.parse_grid_ids(gid), error = function(e) NULL)
      nearest_msg <- ""
      if (!is.null(parsed) && nrow(parsed) == 1L) {
        nearest <- .find_nearest_grid(parsed$grid_lat, parsed$grid_lon,
                                       grid_coords)
        nearest_msg <- sprintf(
          " Nearest grid with priors: '%s'. Consider passing site = list(lat, lon) instead of a hardcoded grid_id.",
          nearest
        )
      }
      sprintf("'%s' / '%s' has 0 prior rows -- ALL species will get fallback priors.%s",
              gid, hab, nearest_msg)
    }, character(1L))

    cli::cli_warn(c(
      "{nrow(missing_combos)} grid_id/main_habitat combo(s) not found in {.arg taxaexpect_priors}:",
      stats::setNames(combo_labels, rep("*", length(combo_labels)))
    ))
  }

  # ---- Join likelihoods -> event_meta -> taxaexpect_priors ------------------
  result <- likelihoods |>
    dplyr::left_join(event_meta, by = "observation_id") |>
    dplyr::left_join(
      taxaexpect_priors,
      by = c("taxon_name", "taxon_name_rank", "grid_id", "main_habitat")
    )

  # ---- Dark diversity fallback -----------------------------------------------
  # Site-level: mean alpha/beta from Tier 3 (undetected) rows per grid × habitat
  dark_by_site <- taxaexpect_priors |>
    dplyr::filter(!is.na(undetected_type)) |>
    dplyr::group_by(grid_id, main_habitat) |>
    dplyr::summarise(
      dark_alpha = mean(alpha, na.rm = TRUE),
      dark_beta  = mean(beta, na.rm = TRUE),
      .groups = "drop"
    )

  # Global fallback: average across all Tier 3 rows

  global_dark <- taxaexpect_priors |>
    dplyr::filter(!is.na(undetected_type)) |>
    dplyr::summarise(
      dark_alpha = mean(alpha, na.rm = TRUE),
      dark_beta  = mean(beta, na.rm = TRUE)
    )

  result <- result |>
    dplyr::left_join(dark_by_site, by = c("grid_id", "main_habitat")) |>
    dplyr::mutate(
      dark_alpha = dplyr::coalesce(dark_alpha, global_dark$dark_alpha),
      dark_beta  = dplyr::coalesce(dark_beta, global_dark$dark_beta),
      prior_alpha = dplyr::coalesce(alpha, dark_alpha),
      prior_beta  = dplyr::coalesce(beta, dark_beta),
      prior_mean  = prior_alpha / (prior_alpha + prior_beta)
    )

  # ---- Modelled-species floor: never worse than dark diversity ---------------
  # A species the model has seen (non-NA alpha) at the wrong habitat can get

  # theta ≈ 0, producing prior_alpha << dark_alpha. This inverts the intended
  # ordering: unobserved species beat observed ones. Fix: if a modelled species
  # has prior_mean below the dark diversity mean, promote it to the dark level.
  # The species was observed *somewhere* in training data, so it should receive
  # at least as much prior mass as a completely unobserved species.
  has_model <- !is.na(result$alpha)
  dark_mean <- result$dark_alpha / (result$dark_alpha + result$dark_beta)
  below_dark <- has_model & result$prior_mean < dark_mean
  if (any(below_dark, na.rm = TRUE)) {
    n_promoted <- sum(below_dark, na.rm = TRUE)
    result$prior_alpha[below_dark] <- result$dark_alpha[below_dark]
    result$prior_beta[below_dark]  <- result$dark_beta[below_dark]
    result$prior_mean[below_dark]  <- dark_mean[below_dark]
    cli::cli_inform(
      "join_priors: promoted {n_promoted} modelled row(s) with habitat-mismatch priors to dark diversity floor."
    )
  }

  zero_ab <- which((result$prior_alpha + result$prior_beta) == 0)
  if (length(zero_ab) > 0L) {
    warning(sprintf("join_priors: %d row(s) have alpha + beta = 0; setting prior_mean to 0.5 (uninformative).", length(zero_ab)),
            call. = FALSE)
    result$prior_alpha[zero_ab] <- 0.5
    result$prior_beta[zero_ab] <- 0.5
    result$prior_mean[zero_ab] <- 0.5
  }

  n_no_prior <- sum(is.na(result$prior_mean))
  if (n_no_prior > 0L) {
    cli::cli_warn(
      "{n_no_prior} row(s) have no prior after dark diversity fallback. Check site coverage in TaxaExpect."
    )
  }

  # ---- Dedup + taxonomy fill + redundancy filter -----------------------------
  result <- result |>
    dplyr::arrange(dplyr::desc(prior_mean)) |>
    dplyr::distinct(observation_id, taxon_name, taxon_name_rank, .keep_all = TRUE)

  # Fill taxonomy from taxonomy_lookup (e.g. from match_df reference taxonomy)
  if (!is.null(taxonomy_lookup) && is.data.frame(taxonomy_lookup) &&
      "taxon_name" %in% names(taxonomy_lookup)) {
    tax_cols <- intersect(rank_system, names(taxonomy_lookup))
    if (length(tax_cols) > 0L) {
      lookup_slim <- taxonomy_lookup |>
        dplyr::select(dplyr::all_of(c("taxon_name", tax_cols))) |>
        dplyr::distinct(taxon_name, .keep_all = TRUE)
      for (col in tax_cols) {
        if (col %in% names(result)) {
          # Fill NAs from lookup
          idx <- match(result$taxon_name, lookup_slim$taxon_name)
          na_mask <- is.na(result[[col]]) & !is.na(idx)
          result[[col]][na_mask] <- lookup_slim[[col]][idx[na_mask]]
        } else {
          # Add the column from lookup
          idx <- match(result$taxon_name, lookup_slim$taxon_name)
          result[[col]] <- lookup_slim[[col]][idx]
        }
      }
    }
  }

  # Derive genus from species binomials when genus column is NA
  result <- result |>
    dplyr::mutate(genus = dplyr::coalesce(
      genus,
      dplyr::if_else(taxon_name_rank == "species",
                     sub(" .*", "", taxon_name), NA_character_),
      dplyr::if_else(taxon_name_rank == "genus", taxon_name, NA_character_)
    ))

  # Fill the rank column matching taxon_name_rank from taxon_name itself.
  # e.g. a family-rank row with taxon_name="Girellidae" should have
  # family="Girellidae", an order-rank row should fill the order column, etc.
  rank_cols_in_df <- intersect(rank_system, names(result))
  for (rc in rank_cols_in_df) {
    is_this_rank <- !is.na(result$taxon_name_rank) & result$taxon_name_rank == rc
    needs_val    <- is_this_rank & is.na(result[[rc]]) & !is.na(result$taxon_name)
    if (any(needs_val)) {
      result[[rc]][needs_val] <- result$taxon_name[needs_val]
    }
  }

  # Propagate family from rows that share a genus
  fam_lookup <- result |>
    dplyr::filter(!is.na(genus), !is.na(family)) |>
    dplyr::distinct(genus, family)

  result <- result |>
    dplyr::left_join(fam_lookup, by = "genus", suffix = c("", ".fill")) |>
    dplyr::mutate(family = dplyr::coalesce(family, family.fill)) |>
    dplyr::select(-family.fill)

  # Fill higher taxonomy for genus/family-level rows from other rows in
  # the same lineage. Without this, filter_redundant_hypotheses() cannot
  # detect that e.g. "Girella" (genus) shares a lineage with "Girella
  # nigricans" (species), because the genus row has NA in kingdom/phylum/
  # class/order -- and the filter conservatively retains rows with NA
  # ancestors. Process fine-to-coarse so genus rows filled by species rows
  # can then donate to family rows.
  if (length(rank_cols_in_df) >= 2L) {
    for (rc_idx in rev(seq_along(rank_cols_in_df))) {
      anchor_col <- rank_cols_in_df[rc_idx]
      if (rc_idx == 1L) next
      coarser_cols <- rank_cols_in_df[seq_len(rc_idx - 1L)]
      needs_fill <- which(
        !is.na(result[[anchor_col]]) &
        rowSums(is.na(result[, coarser_cols, drop = FALSE])) > 0L
      )
      if (length(needs_fill) == 0L) next
      donor_lookup <- result[!is.na(result[[anchor_col]]), , drop = FALSE] |>
        dplyr::select(dplyr::all_of(c(anchor_col, coarser_cols))) |>
        dplyr::distinct(.data[[anchor_col]], .keep_all = TRUE)
      for (i in needs_fill) {
        anchor_val <- result[[anchor_col]][i]
        donor_row <- donor_lookup[donor_lookup[[anchor_col]] == anchor_val, ,
                                  drop = FALSE]
        if (nrow(donor_row) == 0L) next
        for (cc in coarser_cols) {
          if (is.na(result[[cc]][i]) && !is.na(donor_row[[cc]][1L])) {
            result[[cc]][i] <- donor_row[[cc]][1L]
          }
        }
      }
    }
  }

  # Fallback: fill remaining taxonomy holes via TaxaTools backbone query.
  # Only fires when sibling propagation left gaps (e.g. no species-level
  # row existed for a genus). Queries are batched on unique taxon_names.
  if (length(rank_cols_in_df) >= 2L &&
      requireNamespace("TaxaTools", quietly = TRUE)) {
    still_missing <- which(
      rowSums(is.na(result[, rank_cols_in_df, drop = FALSE])) > 0L &
      !is.na(result$taxon_name)
    )
    if (length(still_missing) > 0L) {
      names_to_query <- unique(result$taxon_name[still_missing])
      backbone_fill <- tryCatch({
        verified <- TaxaTools::verify_taxon_names(names_to_query,
                                                  backbone_id = 4L)
        TaxaTools::change_backbone(verified,
                                   input_col = "user_supplied_name")
      }, error = function(e) {
        cli::cli_warn(
          "Taxonomy fallback via TaxaTools failed: {conditionMessage(e)}"
        )
        NULL
      })
      if (!is.null(backbone_fill) && nrow(backbone_fill) > 0L) {
        fill_cols <- intersect(rank_cols_in_df, names(backbone_fill))
        # change_backbone() returns user_supplied_name, not taxon_name
        join_col <- if ("user_supplied_name" %in% names(backbone_fill)) {
          "user_supplied_name"
        } else {
          NULL
        }
        if (length(fill_cols) > 0L && !is.null(join_col)) {
          bb_lookup <- backbone_fill |>
            dplyr::select(dplyr::all_of(c(join_col, fill_cols))) |>
            dplyr::distinct(.data[[join_col]], .keep_all = TRUE)
          idx <- match(result$taxon_name[still_missing],
                       bb_lookup[[join_col]])
          for (fc in fill_cols) {
            na_mask <- is.na(result[[fc]][still_missing]) & !is.na(idx)
            if (any(na_mask)) {
              result[[fc]][still_missing[na_mask]] <-
                bb_lookup[[fc]][idx[na_mask]]
            }
          }
          n_filled <- sum(!is.na(idx))
          if (n_filled > 0L) {
            cli::cli_inform(
              "Filled taxonomy for {n_filled} taxon name{?s} via NCBI backbone."
            )
          }
        }
      }
    }
  }

  # Drop coarser-rank rows superseded by finer-rank rows in same lineage
  if (!requireNamespace("TaxaMatch", quietly = TRUE)) {
    cli::cli_warn(
      "{.pkg TaxaMatch} is not installed. Skipping redundant hypothesis filtering."
    )
  } else {
    result <- TaxaMatch::filter_redundant_hypotheses(
      result, rank_system = rank_system
    )
  }

  cli::cli_inform(
    "join_priors: {nrow(result)} row(s) ready for {.fn compute_posterior}."
  )
  result
}
