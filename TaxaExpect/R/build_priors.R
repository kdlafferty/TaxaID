#' Build Occurrence-Based Priors from Taxon Names and Coordinates
#'
#' High-level wrapper that runs the full TaxaFetch + TaxaHabitat + TaxaExpect
#' pipeline in a single call: fetches GBIF occurrences, assigns habitats via
#' LLM, trains a biodiversity model, generates priors, and translates to the
#' target backbone. This encapsulates ~18 function calls across 3 packages
#' into one step.
#'
#' For fine-grained control over any stage, use the individual functions
#' documented in their respective packages. This wrapper implements the
#' standard workflow described in \code{inst/TaxaExpect_workflow.R}.
#'
#' @param taxa Data frame with one or more taxonomy rank columns (e.g.
#'   \code{family}, \code{genus}, \code{species}). Include species-level names
#'   when available -- they are verified against the GBIF backbone to resolve
#'   family-level disagreements between backbones (e.g. Girellidae in NCBI vs
#'   Kyphosidae in GBIF). Unique GBIF families are then passed to
#'   \code{\link[TaxaFetch]{get_keys_from_context}} for occurrence queries.
#'   Typically built from the match object via
#'   \code{TaxaTools::create_taxon_names()} or from a domain-specific species
#'   list.
#' @param lat,lon Numeric scalars. Centre coordinates for the GBIF search
#'   bounding box (decimal degrees).
#' @param search_radius_deg Numeric. Half-width of the GBIF search box in
#'   degrees. Default 2 (~220 km at equator).
#' @param year_range Character. GBIF year filter, e.g. \code{"2015,2025"}.
#'   Default \code{NULL} (all years).
#' @param gbif_limit Integer. Maximum GBIF records per taxon key. Default
#'   \code{10000L}.
#' @param habitat_scheme Passed to
#'   \code{\link[TaxaHabitat]{build_habitat_prompt}}. Default \code{NULL}
#'   (3-category: Marine / Freshwater / Terrestrial).
#' @param llm_fn Function. LLM provider for habitat assignment (follows the
#'   TaxaTools \code{llm_fn} pattern). Default
#'   \code{TaxaTools::call_anthropic_api}.
#' @param max_coord_uncertainty Numeric. Maximum coordinate uncertainty in
#'   metres for \code{\link[TaxaFetch]{filter_gbif_quality}}. Default
#'   \code{500}. Endangered or sensitive species often have intentionally
#'   degraded coordinates (10--30 km uncertainty); increase this value if
#'   such taxa are being entirely excluded.
#' @param habitat_threshold Numeric. Minimum weight for
#'   \code{\link[TaxaHabitat]{assign_habitat_biological}}. Default 0.5.
#' @param geographic_context Optional character string (e.g. \code{"Southern
#'   California"}). Passed to \code{build_habitat_prompt(geographic_context =
#'   ...)} for better ecoregion inference.
#' @param min_phi Numeric. Minimum concentration (alpha + beta) for modelled
#'   priors. Prevents modelled priors from becoming so diffuse that Monte Carlo
#'   posterior estimates are unstable. Default \code{2}. See
#'   \code{\link{generate_full_priors}} for details.
#' @param moran_k Integer. Number of Moran eigenvectors for spatial
#'   autocorrelation. Default \code{5L}. Moran eigenvectors are
#'   inexpensive to compute and generally improve model fit; set to
#'   \code{0} to disable them entirely.
#' @param sd_threshold Numeric. VarCorr SD cutoff for formula screening.
#'   Default 0.20.
#' @param rank_system Character vector of taxonomy ranks, coarse to fine.
#'   Default \code{c("kingdom", "phylum", "class", "order", "family",
#'   "genus", "species")}.
#' @param search_rank Character. The taxonomic rank at which GBIF occurrence
#'   queries are made. Default \code{"family"}, which fetches all species
#'   within each family. Set to \code{"genus"} or \code{"species"} for
#'   narrower queries.
#' @param target_backbone_id Integer. Target backbone for prior taxon names.
#'   Default \code{4L} (NCBI), matching TaxaAssign expectations.
#' @param census_genera Logical. If TRUE (default), queries the GBIF backbone
#'   to enumerate described species within each genus present in the
#'   occurrence data. The census is attached as
#'   \code{attr(result, "gbif_genus_census")} and enables downstream H2
#'   phantom suppression in \code{\link[TaxaAssign]{run_bayesian_pipeline}}.
#'   Set FALSE to skip (saves ~1 sec per genus).
#' @param supplemental_occurrences Optional data frame of additional
#'   occurrence records to stack with GBIF results. Must have
#'   \code{decimalLatitude}, \code{decimalLongitude}, and
#'   \code{taxon_name} columns (or columns mappable via
#'   \code{TaxaTools::rename_cols}).
#' @param checkpoint_dir Optional path. When non-\code{NULL}, intermediate
#'   results are saved as RDS files in this directory for crash recovery.
#' @param verbose Logical. Print progress messages. Default \code{TRUE}.
#'
#' @return A named list with components:
#' \describe{
#'   \item{\code{$priors}}{Data frame of priors (one row per taxon x grid_id x
#'     habitat), with taxon names translated to \code{target_backbone_id}.
#'     Ready for \code{\link[TaxaAssign]{join_priors}}.}
#'   \item{\code{$model}}{The fitted \code{biofreq_model} object from
#'     \code{\link{train_biodiversity_model}}.}
#'   \item{\code{$occurrences}}{The habitat-assigned, gridded occurrence data
#'     frame.}
#'   \item{\code{$grid_result}}{Output of \code{\link{optimize_grid_size}},
#'     including \code{$best_grid}.}
#' }
#'
#' @seealso \code{\link{generate_full_priors}},
#'   \code{\link{train_biodiversity_model}},
#'   \code{\link[TaxaFetch]{fetch_gbif_occurrences}},
#'   \code{\link[TaxaHabitat]{assign_habitat_biological}}
#'
#' @examples
#' \dontrun{
#' bp <- build_priors(
#'   taxa = data.frame(family = c("Fundulidae", "Atherinopsidae", "Gobiidae")),
#'   lat = 34.4, lon = -119.8,
#'   geographic_context = "Santa Barbara Channel, California"
#' )
#' head(bp$priors)
#' print(bp$model)
#' }
#'
#' @export
build_priors <- function(
    taxa,
    lat,
    lon,
    search_radius_deg       = 2,
    year_range              = NULL,
    gbif_limit              = 10000L,
    habitat_scheme          = NULL,
    max_coord_uncertainty   = 500,
    llm_fn                  = getOption("TaxaID.llm_fn", TaxaTools::call_api),
    habitat_threshold       = 0.5,
    geographic_context      = NULL,
    min_phi                 = 2,
    moran_k                 = 5L,
    sd_threshold            = 0.20,
    rank_system             = c("kingdom", "phylum", "class", "order",
                                "family", "genus", "species"),
    search_rank             = "family",
    target_backbone_id      = 4L,
    supplemental_occurrences = NULL,
    census_genera           = TRUE,
    checkpoint_dir          = NULL,
    verbose                 = TRUE
) {

  # --- Check dependencies ---
  if (!requireNamespace("TaxaFetch", quietly = TRUE)) {
    stop(
      "build_priors: the TaxaFetch package is required but not installed.\n",
      "Install it with: devtools::install('<path_to_TaxaFetch>')",
      call. = FALSE
    )
  }
  if (!requireNamespace("TaxaHabitat", quietly = TRUE)) {
    stop(
      "build_priors: the TaxaHabitat package is required but not installed.\n",
      "Install it with: devtools::install('<path_to_TaxaHabitat>')",
      call. = FALSE
    )
  }
  if (!requireNamespace("TaxaTools", quietly = TRUE)) {
    stop(
      "build_priors: the TaxaTools package is required but not installed.\n",
      "Install it with: devtools::install('<path_to_TaxaTools>')",
      call. = FALSE
    )
  }

  # --- Input validation ---
  if (!is.data.frame(taxa)) {
    stop(
      "build_priors: 'taxa' must be a data frame with taxonomy rank columns ",
      "(e.g. family, genus, species).\n",
      "Example: data.frame(family = c('Fundulidae', 'Gobiidae'))",
      call. = FALSE
    )
  }
  if (nrow(taxa) == 0L) {
    stop("build_priors: 'taxa' data frame has zero rows.", call. = FALSE)
  }
  if (!is.numeric(lat) || length(lat) != 1L || !is.numeric(lon) || length(lon) != 1L) {
    stop("build_priors: 'lat' and 'lon' must be single numeric values.")
  }
  if (!is.function(llm_fn)) {
    stop("build_priors: 'llm_fn' must be a function.")
  }
  valid_search_ranks <- c("kingdom", "phylum", "class", "order", "family", "genus", "species")
  if (!is.character(search_rank) || length(search_rank) != 1L ||
      !tolower(search_rank) %in% valid_search_ranks) {
    stop(
      "build_priors: 'search_rank' must be one of: ",
      paste(valid_search_ranks, collapse = ", "),
      call. = FALSE
    )
  }
  search_rank <- tolower(search_rank)

  # Coerce numeric year_range to character string expected by fetch_gbif_occurrences

  if (!is.null(year_range) && is.numeric(year_range)) {
    year_range <- paste(as.integer(year_range), collapse = ",")
  }

  .msg <- function(...) if (verbose) message(...)
  .save <- function(obj, name) {
    if (!is.null(checkpoint_dir)) {
      if (!dir.exists(checkpoint_dir)) dir.create(checkpoint_dir, recursive = TRUE)
      saveRDS(obj, file.path(checkpoint_dir, paste0(name, ".rds")))
      .msg("  [checkpoint] Saved ", name, ".rds")
    }
  }

  # =========================================================================
  # Stage 1: Fetch GBIF occurrences
  # =========================================================================
  .msg("build_priors [1/7]: Fetching GBIF occurrences...")

  # Translate input taxa to GBIF backbone before querying GBIF. Input names
 # may come from any backbone (NCBI for eDNA, WoRMS for marine, etc.) and
  # family-level disagreements (e.g. Girellidae in NCBI vs Kyphosidae in
  # GBIF) cause silent 0-record returns. This is a no-op when names are
  # already GBIF-compatible.
  taxa <- .translate_to_gbif(taxa, rank_system, search_rank, .msg)

  keys <- TaxaFetch::get_keys_from_context(taxa)

  # Filter to usable keys: exclude NONE, ERROR, and HIGHERRANK matches where

  # the resolved rank is drastically coarser than the input (e.g. Cyprinidae
  # resolving to kingdom Animalia, usageKey=1, which would fetch ALL animals).
  rank_hierarchy <- c("KINGDOM", "PHYLUM", "CLASS", "ORDER", "FAMILY", "GENUS", "SPECIES")
  good_match <- !is.na(keys$usageKey) & !keys$matchType %in% c("NONE", "ERROR")

  if ("gbif_rank" %in% names(keys)) {
    input_ranks <- toupper(vapply(seq_len(nrow(taxa)), function(i) {
      cols <- intersect(c("species", "genus", "family", "order", "class", "phylum", "kingdom"),
                        tolower(names(taxa)))
      for (r in cols) {
        val <- taxa[[r]][i]
        if (!is.na(val) && nzchar(trimws(val))) return(toupper(r))
      }
      NA_character_
    }, character(1L)))

    resolved_ranks <- toupper(keys$gbif_rank)
    for (i in seq_len(nrow(keys))) {
      if (!good_match[i] || is.na(input_ranks[i]) || is.na(resolved_ranks[i])) next
      input_pos    <- match(input_ranks[i], rank_hierarchy)
      resolved_pos <- match(resolved_ranks[i], rank_hierarchy)
      if (!is.na(input_pos) && !is.na(resolved_pos) && resolved_pos < input_pos - 1L) {
        .msg(sprintf(
          "  WARNING: '%s' resolved to %s (usageKey %d) -- too coarse, skipping.",
          keys$family[i] %||% keys[[1]][i], resolved_ranks[i], keys$usageKey[i]
        ))
        good_match[i] <- FALSE
      }
    }
  }

  valid_keys <- keys$usageKey[good_match]

  # Layer 2 fallback: if any rows were dropped due to coarse resolution AND
  # the taxa data frame has finer-rank columns, re-query those rows at a finer
  # rank. E.g., if family "Cyprinidae" failed but taxa has genus or species
  # columns, query the genera within Cyprinidae instead.
  dropped <- which(!good_match & !is.na(keys$usageKey))
  if (length(dropped) > 0L) {
    rank_cols_lc <- tolower(names(taxa))
    finer_ranks <- c("species", "genus", "family", "order", "class", "phylum")
    for (di in dropped) {
      # Find the rank that was queried for this row
      queried_rank <- if (exists("input_ranks")) tolower(input_ranks[di]) else NA_character_
      if (is.na(queried_rank)) next
      queried_pos <- match(queried_rank, finer_ranks)
      if (is.na(queried_pos) || queried_pos <= 1L) next  # already at finest rank

      # Look for finer-rank columns in taxa
      candidates <- finer_ranks[seq_len(queried_pos - 1L)]
      avail <- candidates[candidates %in% rank_cols_lc]
      if (length(avail) == 0L) next

      # Build a new taxa frame with finer-rank values from this row's group
      finest <- avail[1L]  # most specific available
      col_idx <- which(rank_cols_lc == finest)
      if (length(col_idx) == 0L) next

      # Find all rows in taxa that share the dropped row's value at the queried rank
      queried_col <- which(rank_cols_lc == queried_rank)
      dropped_val <- taxa[[queried_col[1L]]][di]
      group_rows <- which(taxa[[queried_col[1L]]] == dropped_val)
      finer_vals <- unique(taxa[[col_idx[1L]]][group_rows])
      finer_vals <- finer_vals[!is.na(finer_vals) & nzchar(trimws(finer_vals))]
      if (length(finer_vals) == 0L) next

      .msg(sprintf(
        "  Retrying '%s' at %s level: %s",
        dropped_val, finest, paste(finer_vals, collapse = ", ")
      ))

      # Build a sub-frame with the finer rank + all coarser ranks as context
      sub_df <- data.frame(x = finer_vals, stringsAsFactors = FALSE)
      names(sub_df) <- finest
      # Add coarser ranks from the original row as context
      coarser <- finer_ranks[seq(queried_pos, length(finer_ranks))]
      for (cr in coarser) {
        cr_col <- which(rank_cols_lc == cr)
        if (length(cr_col) > 0L) {
          sub_df[[cr]] <- taxa[[cr_col[1L]]][di]
        }
      }

      sub_keys <- tryCatch(
        TaxaFetch::get_keys_from_context(sub_df),
        error = function(e) NULL
      )
      if (!is.null(sub_keys)) {
        new_valid <- sub_keys$usageKey[!is.na(sub_keys$usageKey) &
                                         !sub_keys$matchType %in% c("NONE", "ERROR", "HIGHERRANK")]
        if (length(new_valid) > 0L) {
          .msg(sprintf("  Recovered %d key(s) at %s level for '%s'.",
                       length(new_valid), finest, dropped_val))
          valid_keys <- c(valid_keys, new_valid)
        }
      }
    }
  }

  valid_keys <- unique(valid_keys)
  if (length(valid_keys) == 0L) {
    stop(
      "build_priors: no valid GBIF usage keys found for the supplied taxa.\n",
      "Check taxon names or try broader taxonomic groups (e.g. order instead of family).",
      call. = FALSE
    )
  }

  bbox <- TaxaFetch::make_bbox_wkt(lat, lon, radius_deg = search_radius_deg)

  gbif_raw <- TaxaFetch::fetch_gbif_occurrences(
    keys       = valid_keys,
    geometry   = bbox,
    year_range = year_range,
    limit      = gbif_limit
  )

  if (is.null(gbif_raw) || nrow(gbif_raw) == 0L) {
    stop(
      "build_priors: zero GBIF records returned.\n",
      "Try increasing search_radius_deg, relaxing year_range, or adding ",
      "supplemental_occurrences.",
      call. = FALSE
    )
  }

  # Track species before filtering to detect purged taxa
  species_before <- if ("species" %in% names(gbif_raw)) {
    table(gbif_raw$species[!is.na(gbif_raw$species) & nzchar(gbif_raw$species)])
  } else NULL

  occurrences <- TaxaFetch::filter_gbif_quality(
    gbif_raw,
    max_coord_uncertainty = max_coord_uncertainty
  )
  .msg(sprintf("  %d GBIF records after quality filtering.", nrow(occurrences)))

  # Warn about species heavily impacted or entirely removed by filtering
  if (!is.null(species_before) && "species" %in% names(occurrences)) {
    species_after <- table(occurrences$species[!is.na(occurrences$species) &
                                                 nzchar(occurrences$species)])
    for (sp in names(species_before)) {
      n_before <- as.integer(species_before[sp])
      n_after  <- if (sp %in% names(species_after)) as.integer(species_after[sp]) else 0L
      pct_lost <- 100 * (n_before - n_after) / n_before
      if (n_after == 0L) {
        warning(
          sprintf(
            "build_priors: all %d record(s) of '%s' removed by quality filtering.\n",
            n_before, sp
          ),
          "  This can happen when coordinates are intentionally degraded ",
          "(e.g. endangered species).\n",
          sprintf("  Try increasing max_coord_uncertainty (current: %g m).",
                  max_coord_uncertainty),
          call. = FALSE
        )
      } else if (pct_lost >= 80) {
        warning(
          sprintf(
            "build_priors: %d of %d records (%.0f%%) of '%s' removed by quality filtering.\n",
            n_before - n_after, n_before, pct_lost, sp
          ),
          sprintf("  Consider increasing max_coord_uncertainty (current: %g m).",
                  max_coord_uncertainty),
          call. = FALSE
        )
      }
    }
  }

  # Stack supplemental sources if provided
  if (!is.null(supplemental_occurrences)) {
    occurrences <- TaxaFetch::stack_occurrences(
      occurrences, supplemental_occurrences
    )
    .msg(sprintf("  %d total records after stacking supplemental data.", nrow(occurrences)))
  }

  # Ensure point_id exists (created by stack_occurrences, but needed even without stacking)
  if (!"point_id" %in% names(occurrences)) {
    occurrences$point_id <- paste(occurrences$decimalLatitude,
                                  occurrences$decimalLongitude, sep = "_")
  }

  # Ensure taxon_name column exists
  if (!"taxon_name" %in% names(occurrences)) {
    available_ranks <- intersect(rank_system, names(occurrences))
    occurrences <- TaxaTools::create_taxon_names(occurrences, rank_system = available_ranks)
  }

  .save(occurrences, "occurrences_raw")

  # =========================================================================
  # Stage 1b: GBIF genus census (taxonomic completeness)
  # =========================================================================
  gbif_census <- NULL
  if (isTRUE(census_genera) &&
      "genusKey" %in% names(occurrences) &&
      requireNamespace("TaxaTools", quietly = TRUE) &&
      !is.null(utils::getFromNamespace("census_genus_species", "TaxaTools"))) {

    genus_df <- unique(occurrences[
      !is.na(occurrences$genusKey) & !is.na(occurrences$genus),
      c("genus", "genusKey"), drop = FALSE
    ])
    genus_df <- genus_df[!duplicated(genus_df$genus), , drop = FALSE]

    if (nrow(genus_df) > 0L) {
      named_keys <- stats::setNames(
        as.integer(genus_df$genusKey), genus_df$genus
      )
      .msg(sprintf("build_priors [1b/7]: GBIF genus census for %d genera...",
                   length(named_keys)))
      gbif_census <- tryCatch(
        TaxaTools::census_genus_species(
          genus_keys    = named_keys,
          rank          = "genus",
          verbose       = verbose
        ),
        error = function(e) {
          .msg(sprintf("  Warning: GBIF genus census failed: %s",
                       conditionMessage(e)))
          NULL
        }
      )
      if (!is.null(gbif_census)) {
        .msg(sprintf("  Censused %d genera; %d total described species.",
                     nrow(gbif_census), sum(gbif_census$total_described)))
      }
    }
  }

  # =========================================================================
  # Stage 2: Assign habitat via LLM
  # =========================================================================
  # Resolve habitat scheme label for messaging
  if (is.null(habitat_scheme)) {
    scheme_label <- "3-category (Marine / Freshwater / Terrestrial)"
  } else if (is.character(habitat_scheme) && length(habitat_scheme) == 1L) {
    scheme_label <- habitat_scheme
  } else if (is.data.frame(habitat_scheme)) {
    scheme_label <- sprintf("custom (%d categories)", dplyr::n_distinct(habitat_scheme[[1]]))
  } else {
    scheme_label <- "unknown"
  }

  .msg("build_priors [2/7]: Assigning habitat via LLM...")
  .msg(sprintf("  Habitat scheme: %s. To change, set habitat_scheme = 'IUCN_L1' or supply a custom data frame.",
               scheme_label))

  species_list <- unique(occurrences$taxon_name)
  species_list <- species_list[!is.na(species_list) & nzchar(species_list)]

  hab_prompt <- TaxaHabitat::build_habitat_prompt(
    taxon_list         = species_list,
    habitat_scheme     = habitat_scheme,
    geographic_context = geographic_context
  )

  # Submit each chunk to the LLM and parse
  raw_texts <- character(hab_prompt$n_chunks)
  for (i in seq_len(hab_prompt$n_chunks)) {
    .msg(sprintf("  Submitting habitat chunk %d of %d to LLM...", i, hab_prompt$n_chunks))
    raw_texts[i] <- llm_fn(hab_prompt$prompts[[i]])
  }

  habitats_list <- lapply(seq_len(hab_prompt$n_chunks), function(i) {
    TaxaHabitat::parse_hierarchical_habitat_response(
      raw_text       = raw_texts[i],
      taxon_list     = hab_prompt$chunks[[i]],
      habitat_scheme = hab_prompt
    )
  })
  habitats_df <- do.call(rbind, habitats_list)

  occurrences <- TaxaHabitat::assign_habitat_biological(
    data           = occurrences,
    habitats_df    = habitats_df,
    threshold      = habitat_threshold
  )

  # Flag spatial inconsistencies (non-blocking)
  tryCatch({
    occurrences <- TaxaHabitat::flag_habitat_inconsistencies(occurrences)
  }, error = function(e) {
    .msg("  Warning: habitat flagging failed (", conditionMessage(e), "). Continuing.")
  })

  .msg(sprintf("  %d records with habitat assigned.", sum(!is.na(occurrences$main_habitat))))
  .save(occurrences, "occurrences_with_habitat")

  # =========================================================================
  # Stage 3: Optimize spatial grid
  # =========================================================================
  .msg("build_priors [3/7]: Optimizing spatial grid...")

  grid_result <- optimize_grid_size(
    observation_data = occurrences,
    n_covariates     = 2L
  )
  .msg(sprintf("  Selected grid size: %.2f degrees.", grid_result$best_grid))

  occurrences_gridded <- create_sites_from_grid(
    occurrences,
    grid_size = grid_result$best_grid
  )

  # =========================================================================
  # Stage 4: Prepare model data + Moran basis
  # =========================================================================
  .msg("build_priors [4/7]: Preparing model data...")

  model_data <- prepare_model_dataframe(occurrences_gridded)

  if (moran_k > 0L) {
    basis <- compute_moran_basis(
      grid_ids = unique(model_data$grid_id),
      k        = moran_k
    )
    model_data <- dplyr::left_join(model_data, basis, by = "grid_id")
    .msg(sprintf("  %d rows, %d species, %d sites, %d Moran eigenvectors.",
                 nrow(model_data),
                 dplyr::n_distinct(model_data$taxon_name),
                 dplyr::n_distinct(model_data$grid_id),
                 moran_k))
  } else {
    .msg(sprintf("  %d rows, %d species, %d sites, Moran eigenvectors disabled.",
                 nrow(model_data),
                 dplyr::n_distinct(model_data$taxon_name),
                 dplyr::n_distinct(model_data$grid_id)))
  }

  # =========================================================================
  # Stage 5: Train biodiversity model
  # =========================================================================
  .msg("build_priors [5/7]: Training biodiversity model...")

  # Build formula dynamically based on moran_k
  if (moran_k > 0L) {
    basis_terms <- paste0("(0 + B", seq_len(moran_k), " | taxon_name)",
                          collapse = " + ")
    formula_str <- paste0(
      "cbind(n_species, n_other) ~ main_habitat + ",
      "(1 | taxon_name) + diag(main_habitat | taxon_name) + ",
      basis_terms, " + ",
      "(0 + lat_r_s | taxon_name) + (0 + lon_r_s | taxon_name) + ",
      "(1 | taxon_name:grid_id)"
    )
  } else {
    formula_str <- paste0(
      "cbind(n_species, n_other) ~ main_habitat + ",
      "(1 | taxon_name) + diag(main_habitat | taxon_name) + ",
      "(0 + lat_r_s | taxon_name) + (0 + lon_r_s | taxon_name) + ",
      "(1 | taxon_name:grid_id)"
    )
  }
  model_formula <- stats::as.formula(formula_str)

  model_fit <- tryCatch({
    screen_spatial_formula(
      data          = model_data,
      formula_full  = model_formula,
      sd_threshold  = sd_threshold,
      delta_aic_max = 2.0,
      verbose       = verbose
    )
  }, error = function(e) {
    n_rows  <- nrow(model_data)
    n_sites <- dplyr::n_distinct(model_data$grid_id)
    n_taxa  <- dplyr::n_distinct(model_data$taxon_name)
    n_hab   <- dplyr::n_distinct(model_data$main_habitat)
    warning(
      "build_priors: model training failed (", conditionMessage(e), ").\n",
      sprintf("  Data: %d rows, %d grid cells, %d taxa, %d habitats.\n", n_rows, n_sites, n_taxa, n_hab),
      "  The spatial model needs more data. Try:\n",
      "  - Larger search_radius_deg (more grid cells)\n",
      "  - Fewer habitat categories (habitat_scheme = NULL for 3 categories)\n",
      "  - Broader taxonomic group (more species)\n",
      "Returning occurrences and grid_result without priors.",
      call. = FALSE
    )
    NULL
  })

  if (is.null(model_fit)) {
    return(list(
      priors      = NULL,
      model       = NULL,
      occurrences = occurrences_gridded,
      grid_result = grid_result
    ))
  }

  .save(model_fit, "model_fit")

  # =========================================================================
  # Stage 6: Generate priors
  # =========================================================================
  .msg("build_priors [6/7]: Generating priors...")

  priors_observed <- generate_full_priors(
    model_obj = model_fit,
    new_sites = model_data,
    min_phi   = min_phi
  )

  priors_undetected <- generate_undetected_diversity(model_obj = model_fit)

  priors_combined <- dplyr::bind_rows(priors_observed, priors_undetected)

  .msg(sprintf("  %d observed + %d undetected = %d total prior rows.",
               nrow(priors_observed), nrow(priors_undetected), nrow(priors_combined)))

  # =========================================================================
  # Stage 7: Translate to target backbone
  # =========================================================================
  .msg("build_priors [7/7]: Translating to backbone ID ", target_backbone_id, "...")

  gbif_taxa_unique <- unique(priors_combined$taxon_name)

  ncbi_lookup <- TaxaTools::verify_taxon_names(gbif_taxa_unique,
                                                backbone_id = target_backbone_id) |>
    TaxaTools::change_backbone(
      input_col          = "user_supplied_name",
      old_backbone_label = "gbif_name",
      new_backbone_label = "target_name"
    )

  # --- Recovery: direct NCBI taxonomy lookup for species demoted to genus ---
  # NOTE: As of Session 72, verify_taxon_names(backbone_id = 4) bypasses
  # GlobalNames and queries NCBI directly, so this recovery step should be a

  # no-op for NCBI backbone. Retained as safety net for other backbones.
  ncbi_lookup <- .recover_demoted_species(ncbi_lookup, target_backbone_id,
                                           rank_system, verbose = verbose)

  translated <- priors_combined |>
    dplyr::left_join(ncbi_lookup, by = c("taxon_name" = "gbif_name")) |>
    dplyr::select(!dplyr::any_of("taxon_name"))
  translated_ranks <- intersect(rank_system, names(translated))
  taxaexpect_priors <- TaxaTools::create_taxon_names(translated, rank_system = translated_ranks)

  n_translated <- sum(!is.na(taxaexpect_priors$taxon_name))
  .msg(sprintf("  %d of %d prior rows have a translated name.",
               n_translated, nrow(taxaexpect_priors)))

  .save(taxaexpect_priors, "taxaexpect_priors")

  .msg("build_priors: done.")

  out <- list(
    priors      = taxaexpect_priors,
    model       = model_fit,
    occurrences = occurrences_gridded,
    grid_result = grid_result
  )
  attr(out, "habitat_scheme") <- scheme_label

  # --- Attach report_params with propagated citations -------------------------
  rp <- list()
  if ("bibliographicCitation" %in% names(occurrences_gridded)) {
    cites <- unique(occurrences_gridded$bibliographicCitation)
    cites <- cites[!is.na(cites) & nzchar(cites)]
    if (length(cites) > 0L) rp$citations <- cites
  }
  # Also check report_params from supplemental_occurrences
  supp_rp <- attr(supplemental_occurrences, "report_params")
  if (!is.null(supp_rp$citations)) {
    rp$citations <- unique(c(rp$citations, supp_rp$citations))
  }
  rp$n_occurrence_records <- nrow(occurrences_gridded)
  rp$habitat_scheme <- scheme_label
  attr(out, "report_params") <- rp

  # Store search center so downstream functions (e.g. join_priors) can
  # default to the location used to build these priors.
  # Attach to both the outer list and the priors data frame itself,
  # since users typically pass priors_result$priors to join_priors().
  attr(out, "search_center") <- list(lat = lat, lon = lon)
  attr(taxaexpect_priors, "search_center") <- list(lat = lat, lon = lon)

  # Attach GBIF genus census (for H2 phantom suppression in TaxaAssign)
  if (!is.null(gbif_census)) {
    attr(out, "gbif_genus_census") <- gbif_census
    attr(taxaexpect_priors, "gbif_genus_census") <- gbif_census
  }

  out$priors <- taxaexpect_priors

  out
}


# --------------------------------------------------------------------------
# Internal: translate taxa data frame to GBIF backbone
# --------------------------------------------------------------------------
#' @noRd
.translate_to_gbif <- function(taxa, rank_system, search_rank, .msg) {

  # Translate input taxa to GBIF backbone by verifying the finest available

  # names against GBIF, then aggregating to `search_rank`. Species-level
  # queries are essential because family-level disagreements (e.g. Girellidae
  # in NCBI vs Kyphosidae in GBIF) can only be resolved through species
  # classification paths.
  #
  # Flow: input names -> verify against GBIF -> change_backbone() ->
  # extract unique values at search_rank -> rebuild taxa data frame.
  rank_cols <- intersect(
    c("species", "genus", "family", "order", "class", "phylum", "kingdom"),
    tolower(names(taxa))
  )
  if (length(rank_cols) == 0L) return(taxa)

  # Extract finest-rank name per row (species > genus > family > ...)
  finest_names <- vapply(seq_len(nrow(taxa)), function(i) {
    for (rc in rank_cols) {
      val <- taxa[[rc]][i]
      if (!is.na(val) && nzchar(trimws(val))) return(trimws(val))
    }
    NA_character_
  }, character(1L))

  unique_names <- unique(finest_names[!is.na(finest_names)])
  if (length(unique_names) == 0L) return(taxa)

  # Verify against GBIF backbone (backbone_id = 11)
  gbif_verified <- tryCatch(
    TaxaTools::verify_taxon_names(unique_names, backbone_id = 11L),
    error = function(e) {
      .msg("  NOTE: GBIF backbone translation failed: ", conditionMessage(e))
      NULL
    }
  )
  if (is.null(gbif_verified) || nrow(gbif_verified) == 0L) return(taxa)

  gbif_parsed <- tryCatch(
    TaxaTools::change_backbone(gbif_verified,
                               input_col = "user_supplied_name"),
    error = function(e) {
      .msg("  NOTE: change_backbone() failed: ", conditionMessage(e))
      NULL
    }
  )
  if (is.null(gbif_parsed) || nrow(gbif_parsed) == 0L) return(taxa)

  # Extract unique GBIF values at the search_rank level from classification
  # paths. This is the key step: species classification paths reveal the
  # correct GBIF family even when family names differ between backbones.
  if (search_rank %in% names(gbif_parsed)) {
    gbif_values <- unique(gbif_parsed[[search_rank]])
    gbif_values <- gbif_values[!is.na(gbif_values) & nzchar(gbif_values)]

    if (search_rank %in% names(taxa)) {
      orig_values <- unique(taxa[[search_rank]])
      orig_values <- orig_values[!is.na(orig_values) & nzchar(orig_values)]

      new_values  <- setdiff(gbif_values, orig_values)
      lost_values <- setdiff(orig_values, gbif_values)

      if (length(new_values) > 0L || length(lost_values) > 0L) {
        .msg(sprintf(
          "  GBIF backbone translation (%s level): %d input -> %d GBIF.",
          search_rank, length(orig_values), length(gbif_values)
        ))
        if (length(new_values) > 0L) {
          .msg(sprintf("    Added: %s", paste(new_values, collapse = ", ")))
        }
        if (length(lost_values) > 0L) {
          .msg(sprintf("    Replaced: %s", paste(lost_values, collapse = ", ")))
        }
      }
    }

    # Rebuild taxa as unique values at search_rank
    taxa <- data.frame(x = gbif_values, stringsAsFactors = FALSE)
    names(taxa) <- search_rank
  } else {
    # search_rank column not in GBIF output -- fall back to per-row
    # replacement of whatever rank columns exist.
    gbif_rank_cols <- intersect(rank_cols, names(gbif_parsed))
    if (length(gbif_rank_cols) == 0L) return(taxa)

    n_changed <- 0L
    for (i in seq_len(nrow(taxa))) {
      fn <- finest_names[i]
      if (is.na(fn)) next
      match_row <- match(fn, gbif_parsed$user_supplied_name)
      if (is.na(match_row)) next
      for (rc in gbif_rank_cols) {
        orig_val <- taxa[[rc]][i]
        gbif_val <- gbif_parsed[[rc]][match_row]
        if (is.na(orig_val) || !nzchar(trimws(orig_val))) next
        if (!is.na(gbif_val) && nzchar(gbif_val) && gbif_val != orig_val) {
          taxa[[rc]][i] <- gbif_val
          n_changed <- n_changed + 1L
        }
      }
    }
    if (n_changed > 0L) {
      .msg(sprintf("  Translated %d taxon name(s) to GBIF backbone.", n_changed))
    }
  }

  taxa
}
