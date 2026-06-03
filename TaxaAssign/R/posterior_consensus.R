# posterior_consensus.R
# TaxaAssign package
#
# Derives a consensus taxonomic assignment from a posterior dataframe.
# Returns one row per observation_id: the lowest common ancestor (LCA) among the
# minimal set of top-ranked hypotheses that collectively account for a
# user-defined fraction of the named-taxon posterior probability.
#
# Exported functions:
#   posterior_consensus()     LCA-based consensus from a posterior dataframe
#
# Internal helpers:
#   .consensus_one_observation()  Per-observation LCA computation
#   .find_lca()              LCA from a set of plausible hypothesis rows
#   .extract_rank_values()   Extract rank values from df (column or derived)
#   .empty_consensus_row()   NA-filled result for unresolvable observations
#   .build_species_ref()     Normalise species_reference to a data.frame
#   .downrank_consensus()    Downrank coarse LCA when reference has one finer taxon


# ==============================================================================
# Main exported function
# ==============================================================================

#' Derive Consensus Taxonomy from a Posterior Dataframe
#'
#' For each `observation_id`, identifies the minimal set of top-ranked hypotheses
#' that together account for `cumulative_threshold` of the named-taxon posterior
#' mass (after excluding hypotheses below `min_posterior`), then returns their
#' lowest common ancestor (LCA) as the consensus taxonomic assignment.
#'
#' **Which hypotheses are included:** All named hypotheses contribute to the
#' LCA — `"specific_candidate"`, `"unreferenced_species"` (congener without reference
#' sequence), `"unreferenced_genus"` (family-level unreferenced taxon: named species
#' from a genus absent in the reference), and `"unresolved_species"` (a species from a
#' census-complete genus whose identity is ambiguous among the known reference members;
#' produced by [TaxaLikely::apply_coverage_constraints()] with
#' `constraint_behavior = "relabel"`). Only the `"unknown_species"` catch-all row is
#' excluded.
#'
#' **LCA resolution:** The LCA is determined by walking taxonomy ranks from
#' finest to coarsest and finding the finest rank at which all plausible
#' hypotheses agree. Explicit taxonomy columns (e.g. `family`, `genus`,
#' `species`) are used when present in `posterior_df`; genus can always be
#' derived from a species binomial even when no `genus` column is present.
#' Family and above require an explicit column.
#'
#' **Taxonomy columns in posterior_df:** `assign_taxa_llm()` automatically
#' carries taxonomy columns from `match_df` into its output. When using the
#' full pipeline (`compute_posterior()`), taxonomy columns pass through from
#' `evaluate_likelihoods()`. Unreferenced species rows have `NA` in taxonomy columns;
#' set `lookup_missing_taxonomy = TRUE` to attempt lookup via
#' `TaxaTools::verify_taxon_names()`.
#'
#' @param posterior_df Dataframe. Output of [compute_posterior()] or
#'   [assign_taxa_llm()]. Required columns: `observation_id`, `taxon_name`,
#'   `taxon_name_rank`, `hypothesis_type`, and the column named by
#'   `posterior_col`.
#' @param rank_system Optional character vector of taxonomy column names,
#'   coarse-to-fine (e.g. `c("family", "genus", "species")`). If `NULL`
#'   (default), standard taxonomy columns present in `posterior_df` are
#'   detected automatically from `kingdom, phylum, class, order, family,
#'   genus, species`. Genus is always derivable from species binomials even
#'   when the `genus` column is absent.
#' @param cumulative_threshold Numeric in (0, 1]. Cumulative posterior
#'   probability threshold for the plausible hypothesis set. Hypotheses are
#'   included in descending posterior order until this fraction of total
#'   probability is reached. At 0.90, the plausible set contains the fewest
#'   hypotheses accounting for at least 90% of posterior mass, analogous to a
#'   90% credible interval. Default 0.9. For example, at 0.9 with posteriors
#'   (0.6, 0.25, 0.10, 0.05), the plausible set includes the top 2
#'   hypotheses (0.6 + 0.25 = 0.85 < 0.9, so the third is also included:
#'   0.6 + 0.25 + 0.10 = 0.95 >= 0.9). The LCA of these three hypotheses
#'   becomes the consensus.
#' @param min_posterior Numeric in \[0, 1). Minimum individual posterior
#'   probability to retain a hypothesis. Hypotheses below this threshold are
#'   excluded before computing the LCA consensus. At 0.05, a hypothesis must
#'   hold at least 5% posterior probability to influence the consensus taxon.
#'   Default 0.05. Set to 0 to disable.
#' @param posterior_col Character. Name of the posterior column to rank
#'   hypotheses by. Default `"posterior_mean"`.
#' @param lookup_missing_taxonomy Logical. If `TRUE`, calls
#'   `TaxaTools::verify_taxon_names()` to fill in taxonomy columns for
#'   `"unreferenced_species"` rows that have `NA` in those columns. Requires
#'   TaxaTools to be installed and may make network requests. Default `FALSE`.
#' @param backbone_id Integer. Taxonomic backbone to use when
#'   `lookup_missing_taxonomy = TRUE`. Passed to
#'   `TaxaTools::verify_taxon_names()`. Common values: 1 = Catalogue of Life,
#'   11 = GBIF (default), 9 = WoRMS. See ecosystem CLAUDE.md for full list.
#' @param species_reference Optional. A plausible-species reference used to
#'   downrank unresolved coarse-rank consensus assignments. Accepts two forms:
#'   \itemize{
#'     \item \strong{`unreferenced_species_result`} (from
#'       [suggest_unreferenced_species()]): the full LLM-generated plausible
#'       species list is extracted automatically from
#'       \code{attr(x, "plausible")}. This includes referenced species (e.g.
#'       \emph{Leptocottus armatus}) that the LLM flagged as plausible but that
#'       were filtered out of the unreferenced vector by the NCBI step.
#'       Use in the LLM workflow by passing the same object supplied to
#'       \code{assign_taxa_llm(unreferenced_taxa = ...)}.
#'     \item \strong{data.frame}: must contain a \code{taxon_name} column
#'       (species-level names) and columns named after each coarser rank in
#'       \code{rank_system} (e.g. \code{genus}, \code{family}). Pass
#'       \code{taxaexpect_species_df} in the Bayesian workflow.
#'   }
#'   For each unresolved row where `consensus_rank` is not the finest rank,
#'   the function looks up how many taxa at the next finer rank belong to the
#'   consensus taxon. If exactly one, it downranks (recursively — e.g. family
#'   to unique genus to unique species in one pass). Stops at any rank with
#'   more than one option. Default `NULL` (no downranking).
#'
#' @details
#' \strong{Threshold interaction:}
#' \code{min_posterior} and \code{cumulative_threshold} work together:
#' \code{min_posterior} removes obvious noise hypotheses first (those with
#' negligible posterior mass), then \code{cumulative_threshold} selects the
#' plausible set from the remainder. Setting \code{min_posterior = 0} disables
#' noise filtering; setting it too high (e.g. 0.3) may exclude genuine
#' competing hypotheses. \code{cumulative_threshold = 0.9} is analogous to a
#' 90\% credible interval; increase toward 0.95--0.99 for more conservative
#' assignments (more upranking to genus/family); decrease to 0.8 for more
#' aggressive species-level calls.
#'
#' \strong{LCA method:}
#' Lowest Common Ancestor is the standard conservative consensus method in
#' molecular systematics (Huson et al., 2007, MEGAN). The implementation
#' walks from finest to coarsest rank and stops at the first rank where all
#' plausible hypotheses agree.
#'
#' @return A dataframe with one row per `observation_id`:
#'   \describe{
#'     \item{`observation_id`}{Sample identifier (same type as input).}
#'     \item{`consensus_taxon`}{Name of the LCA taxon, or `NA` if unresolvable
#'       (all hypotheses excluded or no rank agrees).}
#'     \item{`consensus_rank`}{Rank of the LCA (e.g. `"genus"`, `"family"`),
#'       or `NA`.}
#'     \item{`consensus_reason`}{How the consensus was reached:
#'       `"unanimous"` (all plausible hypotheses agree at the finest rank),
#'       `"single"` (only one hypothesis in the plausible set),
#'       `"lca"` (upranked because hypotheses disagree at finer ranks),
#'       `"threshold"` (rank-capped by `rank_thresholds` in
#'       [score_consensus()]), or `NA` (unresolvable).}
#'     \item{`is_resolved`}{`TRUE` when the LCA is at the finest rank in
#'       `rank_system` (i.e. a single unambiguous species-level assignment).}
#'     \item{`consensus_posterior`}{Sum of named posterior probabilities within
#'       the consensus taxon at its assigned rank.  Because posteriors are
#'       probabilities (full space = 1.0), this raw sum equals the probability
#'       of the consensus taxon without requiring a denominator.  Computed over
#'       \emph{all} named hypotheses before `min_posterior` and
#'       `cumulative_threshold` filtering, so it is independent of threshold
#'       settings and suitable for post-hoc confidence filtering (e.g. keep
#'       only assignments with `consensus_posterior >= 0.95`).
#'       `NA` when `consensus_taxon` is `NA`.}
#'     \item{`consensus_confidence_score`}{Sum of `confidence_score` values for
#'       all named hypotheses within the consensus taxon (computed over all named
#'       hypotheses, not just the plausible set).  `confidence_score` is the
#'       fraction of Monte Carlo simulations in which a hypothesis produced the
#'       highest posterior; summing over in-LCA hypotheses gives the fraction of
#'       simulations in which \emph{any} member of the consensus taxon won.
#'       Complementary to `consensus_posterior`: while `consensus_posterior`
#'       reflects mean posterior mass, `consensus_confidence_score` reflects how
#'       consistently that taxon dominated across simulations.  `NA` when
#'       `confidence_score` is absent from `posterior_df` (e.g. input from
#'       [assign_taxa_llm()]) or when `consensus_taxon` is `NA`.}
#'     \item{`n_plausible`}{Number of hypotheses in the plausible set (0 if
#'       all hypotheses were excluded).}
#'     \item{`plausible_taxa`}{List column: character vector of plausible taxon
#'       names, sorted by descending posterior.}
#'     \item{`plausible_posteriors`}{List column: named numeric vector of
#'       posterior values for plausible taxa (names = taxon_name).}
#'     \item{`downranked`}{Logical. `TRUE` when the initial LCA rank was
#'       coarser than the final `consensus_rank` due to downranking via
#'       `species_reference`. Only present when `species_reference` is
#'       non-`NULL`. `FALSE` for all rows that were not downranked.}
#'   }
#'
#' @seealso [assign_taxa_llm()], [compute_posterior()],
#'   [suggest_unreferenced_species()]
#'
#' @examples
#' \dontrun{
#' consensus <- posterior_consensus(
#'   result_updated,
#'   cumulative_threshold = 0.9,
#'   min_posterior = 0.05
#' )
#' head(consensus)
#' }
#'
#' @importFrom cli cli_abort cli_inform cli_warn
#' @importFrom dplyr bind_rows
#' @importFrom stats setNames
#'
#' @export
posterior_consensus <- function(posterior_df,
                                rank_system             = NULL,
                                cumulative_threshold    = 0.9,
                                min_posterior           = 0.05,
                                posterior_col           = "posterior_mean",
                                lookup_missing_taxonomy = FALSE,
                                backbone_id             = 11L,
                                species_reference       = NULL) {

  # --- Input validation -------------------------------------------------------
  required <- c("observation_id", "taxon_name", "taxon_name_rank",
                 "hypothesis_type", posterior_col)
  missing_cols <- setdiff(required, names(posterior_df))
  if (length(missing_cols) > 0)
    cli::cli_abort("posterior_df missing required column(s): {.field {missing_cols}}")
  if (!is.numeric(cumulative_threshold) || length(cumulative_threshold) != 1L ||
      cumulative_threshold <= 0 || cumulative_threshold > 1)
    cli::cli_abort("{.arg cumulative_threshold} must be a single number in (0, 1].")
  if (!is.numeric(min_posterior) || length(min_posterior) != 1L ||
      min_posterior < 0 || min_posterior >= 1)
    cli::cli_abort("{.arg min_posterior} must be a single number in [0, 1).")
  if (!is.null(species_reference) &&
      !is.data.frame(species_reference) &&
      !inherits(species_reference, "unreferenced_species_result"))
    cli::cli_abort(
      "{.arg species_reference} must be a data.frame, an \\
      {.cls unreferenced_species_result} object, or NULL."
    )

  # --- Resolve rank system ----------------------------------------------------
  if (is.null(rank_system)) {
    rank_system_eff <- TaxaTools::detect_ranks(posterior_df)
  } else {
    # Keep user order but restrict to known standard ranks first; append others
    rank_system_eff <- rank_system
  }

  # --- Optional taxonomy lookup for unreferenced rows -------------------------
  if (lookup_missing_taxonomy) {
    if (!requireNamespace("TaxaTools", quietly = TRUE)) {
      cli::cli_warn(
        "TaxaTools not installed; skipping taxonomy lookup for unreferenced taxa."
      )
    } else {
      tax_cols_present <- intersect(rank_system_eff, names(posterior_df))
      if (length(tax_cols_present) > 0) {
        unref_mask <- posterior_df$hypothesis_type %in%
          c("unreferenced_species", "unreferenced_genus")
        needs_tax  <- unref_mask &
          rowSums(is.na(posterior_df[, tax_cols_present, drop = FALSE])) > 0
        unref_names <- unique(posterior_df$taxon_name[needs_tax])
        if (length(unref_names) > 0) {
          cli::cli_inform(
            "Looking up taxonomy for {length(unref_names)} unreferenced taxon/taxa \\
            via TaxaTools::verify_taxon_names()..."
          )
          verified <- tryCatch(
            TaxaTools::verify_taxon_names(unref_names, backbone_id = backbone_id),
            error = function(e) {
              cli::cli_warn(
                "TaxaTools::verify_taxon_names() failed: {conditionMessage(e)}. \\
                Proceeding without taxonomy lookup."
              )
              NULL
            }
          )
          if (!is.null(verified)) {
            # change_backbone() parses the pipe-delimited classification_path /
            # classification_ranks into flat family/genus/species columns and
            # renames user_supplied_name to taxon_name for easy matching.
            verified_flat <- TaxaTools::change_backbone(
              verified,
              input_col          = "user_supplied_name",
              old_backbone_label = "taxon_name",
              new_backbone_label = "matched_name"
            )
            idx <- match(posterior_df$taxon_name, verified_flat$taxon_name)
            for (tc in intersect(tax_cols_present, names(verified_flat))) {
              fill <- needs_tax & !is.na(idx)
              if (!any(fill)) next
              posterior_df[[tc]][fill] <- verified_flat[[tc]][idx[fill]]
            }
          }
        }
      }
    }
  }

  # --- Process each observation ------------------------------------------------
  observation_ids <- unique(posterior_df$observation_id)
  cli::cli_inform(
    "Computing consensus taxonomy for {length(observation_ids)} observation(s)..."
  )

  results <- lapply(observation_ids, function(sid) {
    chunk <- posterior_df[posterior_df$observation_id == sid, ]
    .consensus_one_observation(chunk, sid, rank_system_eff,
                           cumulative_threshold, min_posterior, posterior_col)
  })

  result <- dplyr::bind_rows(results)

  # --- Optional downranking via species_reference -----------------------------
  if (!is.null(species_reference)) {
    species_ref <- .build_species_ref(species_reference, rank_system_eff)
    if (!is.null(species_ref))
      result <- .downrank_consensus(result, species_ref, rank_system_eff)
  }

  attr(result, "report_params") <- list(
    cumulative_threshold = cumulative_threshold,
    min_posterior        = min_posterior,
    posterior_col        = posterior_col
  )
  result
}


# ==============================================================================
# Internal helpers
# ==============================================================================

#' Compute consensus for one observation
#' @noRd
.consensus_one_observation <- function(chunk, sid, rank_system,
                                   cumulative_threshold, min_posterior,
                                   posterior_col) {

  # All named hypotheses contribute to LCA; only the unreferenced_family catch-all
  # is excluded (taxon_name = NA; represents uncharacterised diversity with no name).
  # named_all is kept before any filtering for consensus_posterior computation.
  named_all       <- chunk[!is.na(chunk$taxon_name), ]
  named_total_all <- sum(named_all[[posterior_col]], na.rm = TRUE)

  prior_updated_flag <- if ("prior_updated" %in% names(chunk))
    any(chunk$prior_updated, na.rm = TRUE) else NULL

  .empty_flagged <- function() {
    row <- .empty_consensus_row(sid)
    if (!is.null(prior_updated_flag)) row$prior_updated <- prior_updated_flag
    for (v1_col in c("consensus_taxon_v1", "consensus_rank_v1")) {
      if (v1_col %in% names(chunk))
        row[[v1_col]] <- chunk[[v1_col]][[1L]]
    }
    if ("consensus_taxon_v1" %in% names(row)) {
      v1 <- row$consensus_taxon_v1
      row$taxon_changed <- !is.na(v1)   # was assigned before, now unresolvable
    }
    row
  }


  if (nrow(named_all) == 0L) {
    warning(sprintf(
      "posterior_consensus: observation_id '%s' has no named hypotheses (all rows have NA taxon_name or are unreferenced_family). Consensus is NA.", sid
    ), call. = FALSE)
    return(.empty_flagged())
  }

  # Apply minimum posterior filter (named_all preserved above for consensus_posterior)
  named <- named_all[named_all[[posterior_col]] >= min_posterior, ]
  if (nrow(named) == 0L) {
    warning(sprintf(
      "posterior_consensus: observation_id '%s' has no hypotheses above min_posterior = %g. All %d named hypothesis(es) are below threshold. Consider lowering min_posterior.",
      sid, min_posterior, nrow(named_all)
    ), call. = FALSE)
    return(.empty_flagged())
  }

  # Sort descending by posterior
  named <- named[order(named[[posterior_col]], decreasing = TRUE), ]

  # Cumulative threshold within named-taxon posterior mass (post-filter)
  named_total <- sum(named[[posterior_col]], na.rm = TRUE)
  if (named_total == 0)
    return(.empty_consensus_row(sid))

  cum_prop  <- cumsum(named[[posterior_col]]) / named_total
  n_include <- which(cum_prop >= cumulative_threshold)[1L]
  if (is.na(n_include)) n_include <- nrow(named)

  plausible <- named[seq_len(n_include), ]

  # LCA among plausible hypotheses
  lca         <- .find_lca(plausible, rank_system)
  finest_rank <- rank_system[length(rank_system)]
  is_resolved <- !is.na(lca$rank) && lca$rank == finest_rank
  consensus_reason <- lca$consensus_reason

  # consensus_posterior: sum of named posterior values within the LCA taxon.
  # Posteriors are probabilities so the raw sum IS the probability of the LCA
  # taxon -- no denominator is needed (full probability space = 1.0).
  # We use named_all (pre-filter) as the source so the value is independent of
  # min_posterior and cumulative_threshold. Rows may have been filtered after
  # compute_posterior(), so the present rows may not sum to 1; summing directly
  # avoids the divide-by-present-rows trap (which always returns 1.0 for
  # single-hypothesis observations).
  rank_vals_all <- if (!is.na(lca$rank) && !is.na(lca$taxon))
    .extract_rank_values(named_all, lca$rank) else NULL

  in_lca <- if (!is.null(rank_vals_all))
    !is.na(rank_vals_all) & rank_vals_all == lca$taxon else NULL

  consensus_posterior <- if (!is.null(in_lca)) {
    sum(named_all[[posterior_col]][in_lca], na.rm = TRUE)
  } else {
    NA_real_
  }

  # consensus_confidence_score: sum of confidence_score for in-LCA hypotheses.
  # confidence_score (from compute_posterior()) = fraction of MC simulations
  # where that hypothesis produced the highest posterior. Summing over in-LCA
  # hypotheses gives the fraction of simulations where the consensus taxon won.
  # Only available when posterior_df contains a confidence_score column.
  consensus_confidence_score <- if (!is.null(in_lca) &&
                                    "confidence_score" %in% names(named_all)) {
    sum(named_all$confidence_score[in_lca], na.rm = TRUE)
  } else {
    NA_real_
  }

  out <- data.frame(
    observation_id                  = sid,
    consensus_taxon            = lca$taxon,
    consensus_rank             = lca$rank,
    consensus_reason           = consensus_reason,
    is_resolved                = is_resolved,
    consensus_posterior        = consensus_posterior,
    consensus_confidence_score = consensus_confidence_score,
    n_plausible                = n_include,
    plausible_taxa       = I(list(plausible$taxon_name)),
    plausible_posteriors = I(list(stats::setNames(
      plausible[[posterior_col]], plausible$taxon_name
    ))),
    stringsAsFactors     = FALSE
  )

  # Propagate pass-through columns added by update_prior_from_consensus().
  # prior_updated: any row TRUE means the observation was updated.
  # consensus_taxon_v1 / consensus_rank_v1: constant within observation — take first value.
  if ("prior_updated" %in% names(chunk))
    out$prior_updated <- any(chunk$prior_updated, na.rm = TRUE)

  for (v1_col in c("consensus_taxon_v1", "consensus_rank_v1")) {
    if (v1_col %in% names(chunk))
      out[[v1_col]] <- chunk[[v1_col]][[1L]]
  }

  # Derive taxon_changed when v1 columns are present
  if (all(c("consensus_taxon_v1") %in% names(out))) {
    v1  <- out$consensus_taxon_v1
    cur <- out$consensus_taxon
    out$taxon_changed <- !is.na(v1) & (is.na(cur) | cur != v1)
  }

  out
}


#' Find the LCA among plausible hypothesis rows
#'
#' Returns a list with `taxon`, `rank`, and `consensus_reason`.
#' Possible reasons: `"unanimous"` (all agree at finest rank),
#' `"lca"` (upranked because candidates disagree at finer ranks),
#' `"single"` (only one hypothesis in the plausible set).
#' @noRd
.find_lca <- function(plausible, rank_system) {
  if (nrow(plausible) == 0L)
    return(list(taxon = NA_character_, rank = NA_character_,
                consensus_reason = NA_character_))
  if (nrow(plausible) == 1L)
    return(list(taxon = plausible$taxon_name[[1L]],
                rank  = plausible$taxon_name_rank[[1L]],
                consensus_reason = "single"))

  finest_rank <- rev(rank_system)[[1L]]

  # Walk finest to coarsest; stop at first rank where all agree
  for (rk in rev(rank_system)) {
    vals <- .extract_rank_values(plausible, rk)
    if (all(!is.na(vals)) && length(unique(vals)) == 1L) {
      reason <- if (rk == finest_rank) "unanimous" else "lca"
      return(list(taxon = vals[[1L]], rank = rk,
                  consensus_reason = reason))
    }
  }

  list(taxon = NA_character_, rank = NA_character_,
       consensus_reason = NA_character_)
}


#' Extract rank values from a hypothesis dataframe, deriving where possible
#'
#' Uses an explicit column when present; derives genus from a species binomial
#' when the genus column is absent. All other missing columns return NA.
#' @noRd
.extract_rank_values <- function(df, rank) {
  if (rank == "genus") {
    # Derive genus from binomial as fallback for any NA values
    derived <- ifelse(
      df$taxon_name_rank == "species", sub(" .*", "", df$taxon_name),
      ifelse(df$taxon_name_rank == "genus", df$taxon_name, NA_character_)
    )
    if (rank %in% names(df)) {
      vals <- as.character(df[[rank]])
      return(ifelse(is.na(vals), derived, vals))
    }
    return(derived)
  }

  if (rank %in% names(df))
    return(as.character(df[[rank]]))

  # All other ranks require an explicit column
  rep(NA_character_, nrow(df))
}


#' Return an empty consensus row for unresolvable observations
#' @noRd
.empty_consensus_row <- function(sid) {
  data.frame(
    observation_id                  = sid,
    consensus_taxon            = NA_character_,
    consensus_rank             = NA_character_,
    consensus_reason           = NA_character_,
    is_resolved                = FALSE,
    consensus_posterior        = NA_real_,
    consensus_confidence_score = NA_real_,
    n_plausible                = 0L,
    plausible_taxa       = I(list(character(0))),
    plausible_posteriors = I(list(stats::setNames(numeric(0), character(0)))),
    stringsAsFactors     = FALSE
  )
}


#' Normalise species_reference to a plain data.frame
#'
#' Accepts either an unreferenced_species_result (extracts attr "plausible" and
#' derives genus from binomial) or a data.frame (returned as-is after column
#' check). Returns NULL with a warning if the reference is empty or unusable.
#' @noRd
.build_species_ref <- function(x, rank_system) {
  finest_rank <- rank_system[length(rank_system)]

  if (inherits(x, "unreferenced_species_result")) {
    plausible <- attr(x, "plausible")
    if (is.null(plausible) || length(plausible) == 0L) {
      cli::cli_warn(
        "species_reference has an empty {.field plausible} attribute; \\
        skipping downranking."
      )
      return(NULL)
    }
    # Derive genus from binomial (first word); sufficient for genus -> species step.
    return(data.frame(
      taxon_name = plausible,
      genus      = sub(" .*", "", plausible),
      stringsAsFactors = FALSE
    ))
  }

  # data.frame path: must have taxon_name (or finest rank col) + at least one
  # coarser rank column so there is something to look up against.
  has_finest <- "taxon_name" %in% names(x) || finest_rank %in% names(x)
  if (!has_finest) {
    cli::cli_warn(
      "species_reference data.frame has no {.field taxon_name} or \\
      {.field {finest_rank}} column; skipping downranking."
    )
    return(NULL)
  }
  x
}


#' Downrank coarse-rank consensus rows when species_reference has exactly one
#' finer taxon for the consensus taxon
#'
#' Operates row-by-row on the consensus data.frame returned by
#' posterior_consensus(). For each unresolved row whose consensus_rank is not
#' the finest rank, walks down through rank_system: at each step, counts the
#' distinct finer-rank taxa in species_ref that belong to the current taxon.
#' If exactly one, downranks and continues. Stops at any rank with zero or
#' more than one option (conservative). Updates consensus_taxon, consensus_rank,
#' is_resolved, and downranked in place.
#' @noRd
.downrank_consensus <- function(consensus_df, species_ref, rank_system) {
  finest_rank <- rank_system[length(rank_system)]

  # Map a rank name to its column in species_ref.
  # For the finest rank, prefer "taxon_name" (TaxaExpect / plausible convention)
  # then fall back to the rank name itself.
  .ref_col <- function(rk) {
    if (rk == finest_rank) {
      if ("taxon_name" %in% names(species_ref)) return("taxon_name")
      if (rk %in% names(species_ref))           return(rk)
      return(NA_character_)
    }
    if (rk %in% names(species_ref)) return(rk)
    NA_character_
  }

  consensus_df$downranked <- FALSE

  for (i in seq_len(nrow(consensus_df))) {
    if (isTRUE(consensus_df$is_resolved[i])) next
    cur_rank  <- consensus_df$consensus_rank[i]
    cur_taxon <- consensus_df$consensus_taxon[i]
    if (is.na(cur_rank) || is.na(cur_taxon)) next
    if (cur_rank == finest_rank) next

    rank_idx <- match(cur_rank, rank_system)
    if (is.na(rank_idx) || rank_idx >= length(rank_system)) next

    changed <- FALSE

    for (j in seq(rank_idx + 1L, length(rank_system))) {
      finer_rank <- rank_system[j]
      coarse_col <- .ref_col(cur_rank)
      finer_col  <- .ref_col(finer_rank)

      if (is.na(coarse_col) || is.na(finer_col)) break

      candidates <- species_ref[
        !is.na(species_ref[[coarse_col]]) &
        species_ref[[coarse_col]] == cur_taxon, , drop = FALSE]

      finer_vals <- unique(candidates[[finer_col]])
      finer_vals <- finer_vals[!is.na(finer_vals)]

      if (length(finer_vals) != 1L) break  # 0 or >1 options — stop

      cur_rank  <- finer_rank
      cur_taxon <- finer_vals[[1L]]
      changed   <- TRUE
    }

    if (changed) {
      consensus_df$consensus_taxon[i] <- cur_taxon
      consensus_df$consensus_rank[i]  <- cur_rank
      consensus_df$is_resolved[i]     <- (cur_rank == finest_rank)
      consensus_df$downranked[i]      <- TRUE
    }
  }

  consensus_df
}
