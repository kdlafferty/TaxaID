utils::globalVariables(c("taxon_name", "group", "is_complete"))

#' Run the Full Bayesian Assignment Pipeline
#'
#' High-level wrapper that chains TaxaLikely likelihoods + TaxaExpect priors
#' through the full TaxaAssign Bayesian workflow: evaluate likelihoods, audit
#' coverage, expand unreferenced hypotheses, join priors, compute posteriors,
#' derive consensus, and refine via empirical Bayes.
#'
#' This encapsulates ~10 function calls (Sections 1-5 of
#' \code{inst/TaxaAssign_bayesian_workflow.R}) into a single step. For
#' fine-grained control, use the individual functions directly.
#'
#' @param match_df Data frame. Standardized match object from
#'   \code{\link[TaxaMatch]{standardize_match_data}}, with columns
#'   \code{observation_id}, \code{score}, \code{taxon_name}, \code{taxon_name_rank},
#'   and taxonomy columns.
#' @param model_params A \code{taxa_model_params} object from
#'   \code{\link[TaxaLikely]{train_likelihood_model}}.
#' @param taxaexpect_priors Priors from TaxaExpect. Accepts either a data
#'   frame (from \code{\link[TaxaExpect]{generate_full_priors}}) or the full
#'   list returned by \code{TaxaExpect::build_priors()} (the \code{$priors}
#'   element is extracted automatically).
#' @param site Site context for prior joining, including habitat.
#'   \code{main_habitat} is always required — the function does not guess
#'   which habitat your observations came from. Accepted formats:
#'   \describe{
#'     \item{Named list with lat/lon}{\code{list(lat = 34.1, lon = -119.1,
#'       main_habitat = "Marine")} -- auto-resolves to nearest grid cell.}
#'     \item{Named list with grid_id}{\code{list(grid_id = "...",
#'       main_habitat = "...")}}
#'     \item{Data frame (multi-site)}{Columns \code{observation_id},
#'       \code{grid_id}, \code{main_habitat} -- OR -- \code{observation_id},
#'       \code{lat}, \code{lon}, \code{main_habitat}.}
#'   }
#'   If \code{main_habitat} is omitted, the error message lists available
#'   habitats at the resolved grid cell so you can choose the right one.
#' @param rank_system Character vector of taxonomy ranks, coarse to fine.
#'   Used for taxonomy fill, prior join, and consensus LCA. Default
#'   \code{c("order", "family", "genus", "species")}.
#' @param model_rank_system Character vector of ranks present in
#'   \code{match_df} (and the trained model). Used for
#'   \code{evaluate_likelihoods()} and \code{filter_top_hypotheses()}.
#'   Default \code{NULL} auto-detects from the intersection of
#'   \code{rank_system} and \code{names(match_df)}.
#' @param n_sims Integer. Monte Carlo simulations for likelihood evaluation
#'   and posterior computation. Default \code{1000L}.
#' @param ratio_threshold Numeric. Minimum likelihood ratio for retaining
#'   hypotheses in \code{evaluate_likelihoods()}. Default 0.01.
#' @param barcode_term Character. Barcode marker for
#'   \code{audit_barcode_coverage()} when \code{unreferenced_df} is
#'   \code{NULL}. Default \code{"12S"}.
#' @param unreferenced_df Optional data frame of unreferenced species (columns
#'   \code{species}, \code{genus}, \code{family}). When \code{NULL} (default),
#'   unreferenced species are auto-detected via
#'   \code{\link[TaxaLikely]{audit_barcode_coverage}}. Set to an empty
#'   data frame to skip unreferenced expansion entirely.
#' @param constraint_behavior Character. How to handle unreferenced species in
#'   fully-sampled genera: \code{"relabel"} (default) or \code{"zero"}.
#'   Passed to \code{\link[TaxaLikely]{apply_coverage_constraints}}.
#' @param cumulative_threshold Numeric. Posterior probability threshold for
#'   consensus. Default 0.90.
#' @param min_posterior Numeric. Minimum posterior to be considered plausible.
#'   Default 0.05.
#' @param posterior_col Character. Column name for posterior values. Default
#'   \code{"posterior_point_est"}.
#' @param backbone_id Integer. Backbone for taxonomy lookup in consensus.
#'   Default \code{4L} (NCBI).
#' @param lookup_missing_taxonomy Logical. Look up missing taxonomy in
#'   consensus. Default \code{TRUE}.
#' @param presence_multiplier Numeric. Multiplier for empirical Bayes
#'   refinement of confirmed species. Default 5.
#' @param species_reference Optional. Passed to \code{\link{posterior_consensus}}
#'   for downranking. Accepts an \code{unreferenced_species_result} or data
#'   frame.
#' @param generate_report Logical. Generate a Methods + Results report.
#'   Default \code{FALSE}.
#' @param report_params Named list of additional arguments passed to
#'   \code{\link{generate_report}} (e.g. \code{data_type}, \code{marker},
#'   \code{study_description}).
#' @param llm_fn Optional function. LLM provider for report generation.
#'   Only used when \code{generate_report = TRUE}. Default \code{NULL}
#'   (template-only report, no LLM Results text).
#' @param verbose Logical. Print progress messages. Default \code{TRUE}.
#'
#' @return A named list with components:
#' \describe{
#'   \item{\code{$consensus}}{Final consensus data frame (one row per
#'     \code{observation_id}), after empirical Bayes refinement.}
#'   \item{\code{$result}}{Full posterior data frame (after refinement),
#'     with all hypotheses per observation.}
#'   \item{\code{$coverage}}{Coverage audit result from
#'     \code{audit_barcode_coverage()}, or \code{NULL} if
#'     \code{unreferenced_df} was user-supplied.}
#'   \item{\code{$likelihoods}}{The expanded, constraint-applied likelihood
#'     data frame (for inspection).}
#'   \item{\code{$unreferenced}}{Data frame of unreferenced species used for
#'     expansion, or \code{NULL} if skipped.}
#'   \item{\code{$report}}{Report text from \code{generate_report()}, or
#'     \code{NULL} if \code{generate_report = FALSE}.}
#' }
#'
#' @seealso \code{\link{run_llm_pipeline}} for the LLM-based alternative,
#'   \code{\link{compute_posterior}}, \code{\link{posterior_consensus}}
#'
#' @examples
#' \dontrun{
#' out <- run_bayesian_pipeline(
#'   match_df          = match_obj,
#'   model_params      = trained_model,
#'   taxaexpect_priors = priors,
#'   site = list(grid_id = "Grid_34p1_m119p1", main_habitat = "Estuarine Bay")
#' )
#' head(out$consensus)
#' }
#'
#' @export
run_bayesian_pipeline <- function(
    match_df,
    model_params,
    taxaexpect_priors,
    site,
    rank_system          = c("order", "family", "genus", "species"),
    model_rank_system    = NULL,
    n_sims               = 1000L,
    ratio_threshold      = 0.01,
    barcode_term         = "12S",
    unreferenced_df      = NULL,
    constraint_behavior  = c("relabel", "zero"),
    cumulative_threshold = 0.90,
    min_posterior         = 0.05,
    posterior_col         = "posterior_point_est",
    backbone_id          = 4L,
    lookup_missing_taxonomy = TRUE,
    presence_multiplier  = 5,
    species_reference    = NULL,
    generate_report      = FALSE,
    report_params        = list(),
    llm_fn               = NULL,
    verbose              = TRUE
) {

  constraint_behavior <- match.arg(constraint_behavior)

  # --- Check dependencies ---
  if (!requireNamespace("TaxaLikely", quietly = TRUE)) {
    stop(
      "run_bayesian_pipeline: the TaxaLikely package is required.\n",
      "Install it with: devtools::install('<path_to_TaxaLikely>')",
      call. = FALSE
    )
  }

  .msg <- function(...) if (verbose) message(...)

  # --- Resolve model_rank_system ---
  # The likelihood model only knows ranks present in match_df (typically
  # family/genus/species). The wider rank_system is used for taxonomy
  # fill, prior join, and consensus LCA.
  if (is.null(model_rank_system)) {
    match_ranks <- intersect(rank_system, names(match_df))
    if (length(match_ranks) < 2L) {
      stop(
        "run_bayesian_pipeline: fewer than 2 rank_system columns found in match_df: ",
        paste(match_ranks, collapse = ", "),
        "\nAvailable columns: ", paste(names(match_df), collapse = ", "),
        call. = FALSE
      )
    }
    model_rank_system <- match_ranks
    .msg(sprintf("  Auto-detected model_rank_system from match_df: %s",
                 paste(model_rank_system, collapse = ", ")))
  }

  # --- Accept build_priors() output ---
  # If taxaexpect_priors is a list with $priors, extract the data frame
  if (is.list(taxaexpect_priors) && !is.data.frame(taxaexpect_priors) &&
      "priors" %in% names(taxaexpect_priors)) {
    .msg("Detected build_priors() output; extracting $priors.")
    taxaexpect_priors <- taxaexpect_priors$priors
  }

  # --- Resolve site (supports lat/lon, grid_id, or data.frame) ---
  .msg("Resolving site...")
  observation_ids <- unique(match_df$observation_id)
  event_meta <- .resolve_site(site, observation_ids, taxaexpect_priors)

  # --- Validation: check input consistency ---
  # 1. Verify site grid_ids exist in priors
  site_grids <- unique(event_meta$grid_id)
  prior_grids <- unique(taxaexpect_priors$grid_id)
  missing_grids <- setdiff(site_grids, prior_grids)
  if (length(missing_grids) > 0L) {
    stop(sprintf(
      paste0("run_bayesian_pipeline: site grid_id(s) not found in ",
             "taxaexpect_priors: %s\n",
             "Available grid_ids: %s\n",
             "Hint: use site = list(lat = ..., lon = ...) to auto-match."),
      paste(missing_grids, collapse = ", "),
      paste(utils::head(prior_grids, 10L), collapse = ", ")
    ), call. = FALSE)
  }

  # 2. Check genus overlap between match_df and taxaexpect_priors
  if ("genus" %in% names(match_df) && "genus" %in% names(taxaexpect_priors)) {
    match_genera <- unique(match_df$genus[!is.na(match_df$genus)])
    prior_genera <- unique(taxaexpect_priors$genus[!is.na(taxaexpect_priors$genus)])
    overlap <- length(intersect(match_genera, prior_genera))
    pct <- if (length(match_genera) > 0L) overlap / length(match_genera) else 1
    if (pct < 0.5) {
      warning(sprintf(
        paste0("Low genus overlap between match_df and taxaexpect_priors: ",
               "%d of %d genera (%.0f%%). Objects may be from different ",
               "datasets or regions."),
        overlap, length(match_genera), pct * 100
      ), call. = FALSE)
    }
  }

  # 3. Check species-habitat consistency: how many candidate taxa have
  #    non-zero priors at the resolved habitat?
  site_habitats <- unique(event_meta$main_habitat)
  site_grid_ids <- unique(event_meta$grid_id)
  theta_col <- if ("theta_mean" %in% names(taxaexpect_priors)) "theta_mean" else "prior_mean"
  theta_vals <- taxaexpect_priors[[theta_col]]
  match_taxa <- unique(match_df$taxon_name[!is.na(match_df$taxon_name)])
  if (!is.null(theta_vals) && length(match_taxa) > 0L) {
    keep <- taxaexpect_priors$grid_id %in% site_grid_ids &
      taxaexpect_priors$main_habitat %in% site_habitats &
      !is.na(theta_vals) & theta_vals > 0
    habitat_priors <- taxaexpect_priors[keep, , drop = FALSE]
    taxa_with_prior <- intersect(match_taxa,
                                 unique(habitat_priors$taxon_name))
  } else {
    taxa_with_prior <- character(0)
  }
  if (length(match_taxa) > 0L) {
    taxa_pct <- length(taxa_with_prior) / length(match_taxa)
    if (taxa_pct < 0.5) {
      warning(sprintf(
        paste0("Only %d of %d candidate taxa (%.0f%%) have non-zero priors ",
               "for habitat '%s'. The habitat scheme or site coordinates ",
               "may not match the study system. Consider a finer scheme ",
               "(habitat_scheme = 'IUCN_L1') or check site coordinates."),
        length(taxa_with_prior), length(match_taxa), taxa_pct * 100,
        paste(site_habitats, collapse = " / ")
      ), call. = FALSE)
    } else {
      .msg(sprintf("  %d of %d candidate taxa (%.0f%%) have non-zero priors at habitat '%s'.",
                   length(taxa_with_prior), length(match_taxa), taxa_pct * 100,
                   paste(site_habitats, collapse = " / ")))
    }
  }

  # =========================================================================
  # Stage 0: Remove flagged reference errors from match_df
  # =========================================================================
  if (!is.null(model_params$reference_errors) &&
      nrow(model_params$reference_errors) > 0L &&
      "accession" %in% names(match_df)) {
    match_df <- TaxaLikely::remove_flagged_references(match_df,
                                                       model_params$reference_errors)
  }

  # =========================================================================
  # Stage 1: Evaluate likelihoods
  # =========================================================================
  .msg("run_bayesian_pipeline [1/6]: Evaluating likelihoods...")

  lik_result <- TaxaLikely::evaluate_likelihoods(
    match_df     = match_df,
    model_params = model_params,
    rank_system  = model_rank_system,
    n_sims       = n_sims,
    ratio_threshold = ratio_threshold
  )

  if (nrow(lik_result$unresolved) > 0L) {
    .msg(sprintf("  %d unresolved observation_ids (no usable likelihoods).",
                 dplyr::n_distinct(lik_result$unresolved$observation_id)))
  }

  top_likelihoods <- TaxaLikely::filter_top_hypotheses(
    lik_result$likelihoods, rank_system = model_rank_system
  )
  .msg(sprintf("  %d top-hypothesis rows.", nrow(top_likelihoods)))

  # =========================================================================
  # Stage 1b: GBIF genus census — three-tier H2 logic
  # =========================================================================
  gbif_census <- attr(taxaexpect_priors, "gbif_genus_census")

  if (!is.null(gbif_census)) {
    # Compare census against match_df reference species (no additional API calls)
    match_species <- unique(match_df$species[!is.na(match_df$species) &
                                               nzchar(match_df$species)])

    # Compute per-genus completeness from existing census data
    for (ci in seq_len(nrow(gbif_census))) {
      described <- gbif_census$described_species[[ci]]
      missing   <- setdiff(described, match_species)
      gbif_census$in_reference[ci] <- length(described) - length(missing)
      gbif_census$n_missing[ci]    <- length(missing)
      gbif_census$missing_species[[ci]] <- missing
      gbif_census$status[ci] <- if (length(missing) == 0L) {
        "complete"
      } else if (length(missing) == 1L) {
        "singleton_missing"
      } else {
        "incomplete"
      }
    }

    # Identify complete and singleton-missing genera
    complete_genera <- gbif_census$group[gbif_census$status == "complete"]
    singleton_genera <- gbif_census$group[gbif_census$status == "singleton_missing"]

    n_suppressed <- 0L
    n_renamed    <- 0L

    if (length(complete_genera) > 0L) {
      # Suppress H2 rows for complete genera
      is_h2_complete <- top_likelihoods$hypothesis_type == "unreferenced_species" &
        top_likelihoods$taxon_name %in% complete_genera
      n_suppressed <- sum(is_h2_complete)
      if (n_suppressed > 0L) {
        top_likelihoods <- top_likelihoods[!is_h2_complete, , drop = FALSE]
      }
    }

    if (length(singleton_genera) > 0L) {
      # Rename H2 rows for singleton-missing genera to the named species
      singleton_map <- gbif_census[gbif_census$status == "singleton_missing", ]
      for (j in seq_len(nrow(singleton_map))) {
        g <- singleton_map$group[j]
        named_sp <- singleton_map$missing_species[[j]]
        if (length(named_sp) != 1L) next
        idx <- which(top_likelihoods$hypothesis_type == "unreferenced_species" &
                       top_likelihoods$taxon_name == g)
        if (length(idx) > 0L) {
          top_likelihoods$taxon_name[idx] <- named_sp
          top_likelihoods$taxon_name_rank[idx] <- "species"
          n_renamed <- n_renamed + length(idx)
        }
      }
    }

    if (n_suppressed > 0L || n_renamed > 0L) {
      .msg(sprintf(
        "  GBIF census: %d H2 rows suppressed (complete genera), %d renamed (singleton missing).",
        n_suppressed, n_renamed
      ))
    }

    # Feed all_species into audit_barcode_coverage if available
    gbif_all_species <- attr(gbif_census, "all_species")
  } else {
    gbif_all_species <- NULL
  }

  # =========================================================================
  # Stage 2: Unreferenced species detection
  # =========================================================================
  coverage <- NULL

  if (is.null(unreferenced_df)) {
    .msg("run_bayesian_pipeline [2/6]: Auditing barcode coverage (NCBI)...")

    # --- Optimization A: Audit only genera/families present in H2/H3 rows ---
    h2_genera <- top_likelihoods |>
      dplyr::filter(hypothesis_type == "unreferenced_species") |>
      dplyr::pull(taxon_name) |>
      unique() |>
      tolower() |>
      trimws()
    h3_families <- top_likelihoods |>
      dplyr::filter(hypothesis_type == "unreferenced_genus") |>
      dplyr::pull(taxon_name) |>
      unique() |>
      tolower() |>
      trimws()

    reference_species_df <- match_df[!duplicated(match_df$species),
                                      c("genus", "species"), drop = FALSE]
    # Filter to genera that appear in likelihoods (reduces NCBI API calls)
    if (length(h2_genera) > 0L || length(h3_families) > 0L) {
      reference_species_df <- reference_species_df |>
        dplyr::filter(tolower(trimws(genus)) %in% c(h2_genera, h3_families))
    }

    # Build species list from TaxaExpect priors, filtered to relevant genera
    taxaexpect_species_df <- taxaexpect_priors |>
      dplyr::select(dplyr::any_of(c("taxon_name", "genus", "family"))) |>
      dplyr::distinct() |>
      dplyr::filter(!is.na(taxon_name))

    # Prefer GBIF census species list (more complete than NCBI taxonomy)
    if (!is.null(gbif_all_species) && length(gbif_all_species) > 0L) {
      taxaexpect_species <- gbif_all_species
      .msg("  Using GBIF census species list for audit_barcode_coverage().")
    } else {
      taxaexpect_species <- taxaexpect_species_df |>
        dplyr::filter(
          tolower(trimws(genus)) %in% h2_genera |
          tolower(trimws(family)) %in% h3_families
        ) |>
        dplyr::pull(taxon_name)
      if (length(taxaexpect_species) == 0L) taxaexpect_species <- NULL
    }

    .msg(sprintf("  Auditing %d reference species across %d genera.",
                 nrow(reference_species_df), length(h2_genera)))

    if (nrow(reference_species_df) > 0L) {
      coverage <- TaxaLikely::audit_barcode_coverage(
        match_df     = reference_species_df,
        barcode_term = barcode_term,
        species_list = taxaexpect_species,
        target_rank  = "genus"
      )
    } else {
      coverage <- list(
        census       = data.frame(group = character(), total = integer(),
                                  in_reference = integer(), unreferenced = integer(),
                                  is_complete = logical(), stringsAsFactors = FALSE),
        unreferenced = character()
      )
      .msg("  No genera need auditing -- skipping NCBI queries.")
    }

    # --- Optimization B: Pre-filter unreferenced_df to relevant genera/families ---
    unreferenced_df <- taxaexpect_species_df |>
      dplyr::filter(taxon_name %in% coverage$unreferenced) |>
      dplyr::rename(species = taxon_name)
    if (nrow(unreferenced_df) > 0L) {
      unreferenced_df <- unreferenced_df |>
        dplyr::filter(
          tolower(trimws(genus)) %in% h2_genera |
          tolower(trimws(family)) %in% h3_families
        )
    }

    .msg(sprintf("  %d unreferenced species detected.", nrow(unreferenced_df)))
  } else {
    .msg("run_bayesian_pipeline [2/6]: Using user-supplied unreferenced species.")
  }

  # =========================================================================
  # Stage 3: Expand + constrain
  # =========================================================================
  .msg("run_bayesian_pipeline [3/6]: Expanding unreferenced hypotheses...")

  if (nrow(unreferenced_df) > 0L) {
    expanded <- expand_unreferenced_hypotheses(top_likelihoods, unreferenced_df)
  } else {
    expanded <- top_likelihoods
  }

  if (!is.null(coverage)) {
    census_result <- dplyr::mutate(
      coverage$census,
      taxon_name = group,
      rank = "genus",
      status = ifelse(is_complete, "complete", "incomplete")
    )
    final_likelihoods <- TaxaLikely::apply_coverage_constraints(
      expanded, census_result, constraint_behavior = constraint_behavior
    )
  } else {
    final_likelihoods <- expanded
  }

  .msg(sprintf("  %d likelihood rows after expansion + constraints.", nrow(final_likelihoods)))

  # =========================================================================
  # Stage 4: Join priors
  # =========================================================================
  .msg("run_bayesian_pipeline [4/6]: Joining TaxaExpect priors...")

  # Build taxonomy lookup from match_df for species not in TaxaExpect priors
  tax_cols_available <- intersect(rank_system, names(match_df))
  taxonomy_lookup <- if (length(tax_cols_available) > 0L) {
    match_df |>
      dplyr::select(dplyr::all_of(c("taxon_name", tax_cols_available))) |>
      dplyr::distinct(taxon_name, .keep_all = TRUE)
  } else {
    NULL
  }

  # --- Optimization C: Pre-filter priors to target site + Tier 3 rows ---
  # Keeps site-matching rows for the join AND all undetected-type rows
  # for the dark diversity fallback (which needs global Tier 3 data).
  site_grid_ids  <- unique(event_meta$grid_id)
  site_habitats  <- unique(event_meta$main_habitat)
  priors_filtered <- taxaexpect_priors |>
    dplyr::filter(
      (grid_id %in% site_grid_ids & main_habitat %in% site_habitats) |
      !is.na(undetected_type)
    )
  .msg(sprintf("  Priors pre-filtered: %d -> %d rows.",
               nrow(taxaexpect_priors), nrow(priors_filtered)))

  likelihoods_ready <- join_priors(
    likelihoods       = final_likelihoods,
    taxaexpect_priors = priors_filtered,
    site              = event_meta,
    taxonomy_lookup   = taxonomy_lookup,
    rank_system       = rank_system
  )

  .msg(sprintf("  %d rows ready for posterior computation.", nrow(likelihoods_ready)))

  # =========================================================================
  # Stage 5: Compute posterior
  # =========================================================================
  .msg("run_bayesian_pipeline [5/6]: Computing posteriors...")

  result <- compute_posterior(likelihoods_ready, n_sims = n_sims)
  .msg(sprintf("  %d posterior rows, %d observations.",
               nrow(result), dplyr::n_distinct(result$observation_id)))

  # =========================================================================
  # Stages 6-8: Consensus + Empirical Bayes + Report (shared helper)
  # =========================================================================

  # Build species_reference from TaxaExpect if not supplied
  if (is.null(species_reference)) {
    species_reference <- taxaexpect_priors |>
      dplyr::select(dplyr::any_of(c("taxon_name", "genus", "family"))) |>
      dplyr::distinct() |>
      dplyr::filter(!is.na(taxon_name))
  }

  refined <- .run_consensus_and_report(
    result                = result,
    species_reference     = species_reference,
    cumulative_threshold  = cumulative_threshold,
    min_posterior         = min_posterior,
    posterior_col         = posterior_col,
    lookup_missing_taxonomy = lookup_missing_taxonomy,
    backbone_id           = backbone_id,
    rank_system           = rank_system,
    presence_multiplier   = presence_multiplier,
    n_sims                = n_sims,
    generate_report_flag  = generate_report,
    report_params         = report_params,
    unreferenced_result   = unreferenced_df,
    llm_fn                = llm_fn,
    verbose               = verbose,
    .msg                  = .msg,
    stage_prefix          = "run_bayesian_pipeline [6/6]"
  )

  .msg("run_bayesian_pipeline: done.")

  list(
    consensus    = refined$consensus,
    result       = refined$result,
    coverage     = coverage,
    likelihoods  = final_likelihoods,
    unreferenced = unreferenced_df,
    report       = refined$report
  )
}
