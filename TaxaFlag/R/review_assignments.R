
#' LLM Expert Review of Taxonomic Assignments
#'
#' Sends unique taxa from a consensus table to an LLM for structured expert
#' review. The LLM assesses each taxon for habitat fit, geographic plausibility,
#' contaminant risk, and (optionally) taxonomic scope. It also suggests
#' plausible alternative taxa where appropriate.
#'
#' When \code{plausible_taxa_col} is supplied, the function deduplicates on
#' candidate sets rather than \code{consensus_taxon}. Each unique combination
#' of plausible species becomes one LLM query, giving the LLM full species-level
#' context rather than only the upranked LCA name. This is especially useful
#' when multiple observations share the same genus-level consensus but differ in
#' which specific candidates they contain.
#'
#' Works with any data frame containing a taxon column -- not restricted to
#' TaxaAssign output. Context (geography, habitat) can be supplied as a
#' \code{build_context()} object from TaxaAssign, or as a simple named list.
#'
#' @param df Data frame with at minimum a column of taxon names.
#' @param taxon_col Character. Column name for consensus taxon. Default
#'   \code{"consensus_taxon"}.
#' @param taxon_rank_col Character or \code{NULL}. Column name for consensus
#'   rank (e.g., "species", "genus"). When supplied, the rank is included in
#'   the prompt for context. Default \code{NULL}.
#' @param plausible_taxa_col Character or \code{NULL}. Name of the list column
#'   containing per-observation plausible candidate taxa (e.g.,
#'   \code{"plausible_taxa"} from \code{TaxaAssign::posterior_consensus()}).
#'   When supplied, the LLM receives the full candidate set for each unique
#'   combination rather than just the upranked consensus taxon. Singletons are
#'   reviewed by species name as usual. Unresolved rows (empty candidate set)
#'   are skipped. Default \code{NULL} (current behaviour -- deduplicates on
#'   \code{taxon_col}).
#' @param irreducible_only Logical. When \code{plausible_taxa_col} is supplied
#'   and an \code{irreducible_consensus} column is present in \code{df} (added
#'   by \code{TaxaAssign::add_slash_taxon()}), only candidate sets where
#'   \code{irreducible_consensus == TRUE} are reviewed. Non-irreducible rows
#'   receive \code{NA} review columns. When \code{irreducible_consensus} is
#'   absent, all unique candidate sets are reviewed with a message. Ignored
#'   when \code{plausible_taxa_col = NULL}. Default \code{TRUE}.
#' @param consensus_posterior_col Character or \code{NULL}. Column name for
#'   \code{TaxaAssign::posterior_consensus()}'s \code{consensus_posterior} --
#'   the pipeline's own statistical confidence in the winning taxon. When
#'   present, the median value across every row sharing a taxon/candidate-set
#'   label is shown to the LLM as context (e.g. \code{"pipeline
#'   posterior=0.81"}), so a sharp disagreement between the pipeline's
#'   confidence and the LLM's ecological plausibility judgment can be
#'   surfaced in \code{review_comment}. Purely additive text -- never changes
#'   which rows are reviewed or any output column. Silently skipped when the
#'   named column is absent from \code{df}. Default
#'   \code{"consensus_posterior"} (matches \code{posterior_consensus()}'s own
#'   output). Set to \code{NULL} to disable.
#' @param winner_prior_col Character or \code{NULL}. Column name for
#'   \code{posterior_consensus()}'s \code{winner_prior} -- the occurrence-
#'   database prior for the winning taxon. Same treatment as
#'   \code{consensus_posterior_col}: shown as median context (e.g.
#'   \code{"occurrence prior=0.42"}), silently skipped when absent. Default
#'   \code{"winner_prior"}. Set to \code{NULL} to disable.
#' @param winner_rank_expanded_col Character or \code{NULL}. Column name for
#'   \code{posterior_consensus()}'s \code{winner_rank_expanded} -- \code{TRUE}
#'   when the winning species-level call was manufactured by
#'   \code{join_priors()}'s coarse-rank expansion from occurrence-prior mass
#'   alone, with no direct sequence/image/acoustic evidence discriminating
#'   between candidates. When \code{TRUE} for any row sharing a label, a note
#'   to that effect is added to the LLM's context, since this changes how
#'   much weight the identification itself deserves. Silently skipped when
#'   absent. Default \code{"winner_rank_expanded"}. Set to \code{NULL} to
#'   disable.
#' @param plausible_posteriors_col Character or \code{NULL}. Column name for
#'   \code{posterior_consensus()}'s \code{plausible_posteriors} list column
#'   (per-candidate posterior weights, positionally aligned with
#'   \code{plausible_taxa_col}). Only used when \code{plausible_taxa_col} is
#'   supplied. When present, each multi-candidate label's per-candidate
#'   weights are averaged across every row sharing that label and shown to
#'   the LLM (e.g. \code{"candidate weights: Bos javanicus 72\%, Bos
#'   primigenius 28\%"}), so \code{review_comment} can speak to the specific
#'   weaker member instead of the group as an undifferentiated set. Silently
#'   skipped when absent. Default \code{"plausible_posteriors"}. Set to
#'   \code{NULL} to disable.
#' @param context Named list or data frame describing the study context.
#'   Recognised fields: \code{geography} (or \code{ecoregion}),
#'   \code{habitat} (or \code{main_habitat}), \code{date}. A
#'   \code{build_context()} output works directly. At minimum, supply
#'   \code{geography} and \code{habitat}.
#' @param target_group Character or \code{NULL}. Taxonomic target group
#'   (e.g., \code{"fish"}, \code{"birds"}). When supplied, the LLM
#'   populates \code{scope_plausibility}. Default \code{NULL}.
#' @param marker Character or \code{NULL}. Molecular marker or detection
#'   method (e.g., \code{"12S"}, \code{"COI"}, \code{"camera trap"}).
#'   Provides contaminant context. Default \code{NULL}.
#' @param data_type Character. Detection method. One of \code{"eDNA"} (default),
#'   \code{"acoustic"}, or \code{"image"}. Controls the contaminant assessment
#'   guidance in the LLM prompt.
#' @param llm_fn Function. LLM provider function with signature
#'   \code{function(prompt_str, ...)}. Default
#'   \code{TaxaTools::call_api}.
#' @param taxa_per_call Integer. Maximum taxa (or candidate sets) per LLM call.
#'   Default \code{15L}. Candidate-set entries are longer than single taxon
#'   names; consider reducing to 8--10 when using \code{plausible_taxa_col}.
#' @param max_tokens Integer or \code{NULL}. Maximum response tokens requested
#'   from \code{llm_fn} (forwarded as \code{llm_fn(prompt, max_tokens = max_tokens)}
#'   whenever supplied). Default \code{NULL} -- does not pass \code{max_tokens}
#'   at all, so \code{llm_fn}'s own default applies (\code{3000L} for
#'   \code{TaxaTools::call_api()}). Raise this if \code{max_retries} alone
#'   isn't resolving truncation warnings for your data -- e.g. a long,
#'   multi-marker \code{marker} string can inflate per-taxon response length
#'   enough that even the smallest retry sub-batch still truncates.
#' @param max_retries Integer. When a batch's LLM response is truncated,
#'   empty, or unparseable, the batch is automatically split in half and
#'   retried -- a smaller batch requests a proportionally shorter response,
#'   directly relieving token-budget pressure -- up to \code{max_retries}
#'   times before falling back to \code{NA} defaults for whatever's still
#'   missing. Does not apply to a hard \code{llm_fn} error (e.g. network/auth
#'   failure): a smaller batch can't fix that, so it is reported immediately
#'   without retrying. Default \code{2L}.
#' @param pause_seconds Numeric. Seconds to pause between LLM calls.
#'   Default \code{1}.
#' @param verbose Logical. Print progress messages. Default \code{TRUE}.
#'
#' @return The input data frame with 7 or 8 columns appended:
#' \describe{
#'   \item{\code{habitat_plausibility}}{likely / possible / unlikely}
#'   \item{\code{geographic_plausibility}}{likely / possible / unlikely}
#'   \item{\code{scope_plausibility}}{likely / possible / unlikely, or \code{NA}
#'     if \code{target_group} not supplied}
#'   \item{\code{contamination_risk}}{high / moderate / low}
#'   \item{\code{review_alternatives}}{Comma-separated plausible alternatives,
#'     or \code{NA}}
#'   \item{\code{review_lower_hypotheses}}{Comma-separated finer-rank taxa, or
#'     \code{NA}. Always \code{NA} when \code{plausible_taxa_col} is supplied
#'     (candidates already known).}
#'   \item{\code{review_confidence}}{high / moderate / low}
#'   \item{\code{review_comment}}{Free-text note, or \code{NA}}
#' }
#'
#' @section Pipeline context:
#' When \code{consensus_posterior_col}/\code{winner_prior_col}/
#' \code{winner_rank_expanded_col}/\code{plausible_posteriors_col} match real
#' columns in \code{df} (the defaults match \code{TaxaAssign::
#' posterior_consensus()}'s own output names), a compact \code{"[...]"}
#' annotation is appended to each taxon's line in the LLM prompt -- the
#' pipeline's own median statistical confidence/occurrence prior for that
#' taxon, a note when the winning call was resolved by occurrence-prior
#' tie-break alone (no direct sequence evidence), and, for multi-candidate
#' sets, each candidate's averaged posterior weight. This lets the LLM's
#' free-text \code{review_comment} flag a disagreement between the
#' pipeline's own confidence and its ecological judgment. It is purely
#' additive: it never changes which rows are reviewed, the dedup key, or any
#' output column, and adds only a few tokens per taxon to the prompt. Set any
#' of the four params to \code{NULL} to disable; all four are silently
#' skipped (not an error) when the named column is absent from \code{df}.
#'
#' @seealso \code{\link{flag_contaminant}} for data-driven contaminant
#'   detection, \code{\link{flag_handler}} for temporal proximity flagging,
#'   \code{TaxaAssign::add_slash_taxon()} to add \code{irreducible_consensus}
#'
#' @examples
#' \dontrun{
#' # Standard review (consensus taxon only)
#' reviewed <- review_assignments(
#'   df           = consensus_df,
#'   context      = list(geography = "Palmyra Atoll, central Pacific",
#'                       habitat   = "coral reef"),
#'   target_group = "fish",
#'   marker       = "12S MiFish"
#' )
#'
#' # Candidate-aware review (recommended for upranked assignments)
#' consensus_df <- TaxaAssign::add_slash_taxon(consensus_df)
#' reviewed <- review_assignments(
#'   df                 = consensus_df,
#'   plausible_taxa_col = "plausible_taxa",
#'   irreducible_only   = TRUE,
#'   context            = ctx,
#'   target_group       = "fish"
#' )
#' }
#'
#' @export
review_assignments <- function(df,
                               taxon_col          = "consensus_taxon",
                               taxon_rank_col     = NULL,
                               plausible_taxa_col = NULL,
                               irreducible_only   = TRUE,
                               consensus_posterior_col  = "consensus_posterior",
                               winner_prior_col         = "winner_prior",
                               winner_rank_expanded_col = "winner_rank_expanded",
                               plausible_posteriors_col = "plausible_posteriors",
                               context,
                               target_group       = NULL,
                               marker             = NULL,
                               data_type          = "eDNA",
                               llm_fn             = getOption("TaxaID.llm_fn", TaxaTools::call_api),
                               taxa_per_call      = 15L,
                               max_tokens         = NULL,
                               max_retries        = 2L,
                               pause_seconds      = 1,
                               verbose            = TRUE) {

  # --- Input validation ---
  if (!is.data.frame(df)) stop("'df' must be a data frame.", call. = FALSE)

  if (!taxon_col %in% names(df))
    stop(sprintf("Column '%s' not found in df.", taxon_col), call. = FALSE)

  if (!is.null(taxon_rank_col) && !taxon_rank_col %in% names(df))
    stop(sprintf("Column '%s' not found in df.", taxon_rank_col), call. = FALSE)

  if (!is.null(plausible_taxa_col) && !plausible_taxa_col %in% names(df))
    stop(sprintf("Column '%s' not found in df.", plausible_taxa_col), call. = FALSE)

  # Pipeline-context column-name params are deliberately NOT validated for
  # presence in df -- unlike taxon_rank_col/plausible_taxa_col above, these
  # have non-NULL defaults matching TaxaAssign::posterior_consensus()'s own
  # output names, so an explicit-presence check would break every existing
  # caller whose df predates these columns. Silently skipped instead (see
  # .summarise_pipeline_context()); only the parameter TYPE is checked here.
  for (col_param in list(consensus_posterior_col, winner_prior_col,
                         winner_rank_expanded_col, plausible_posteriors_col)) {
    if (!is.null(col_param) && (!is.character(col_param) || length(col_param) != 1L))
      stop(paste(
        "'consensus_posterior_col', 'winner_prior_col',",
        "'winner_rank_expanded_col', and 'plausible_posteriors_col' must",
        "each be a single character string or NULL."
      ), call. = FALSE)
  }

  if (missing(context) || is.null(context))
    stop("'context' is required. Supply a named list or build_context() output.",
         call. = FALSE)

  valid_types <- c("eDNA", "acoustic", "image")
  if (!is.character(data_type) || length(data_type) != 1L ||
      !data_type %in% valid_types)
    stop(sprintf("'data_type' must be one of: %s", paste(valid_types, collapse = ", ")),
         call. = FALSE)

  # --- Normalise context ---
  ctx <- .normalise_context(context)

  # --- Build taxa_info: candidate-set path or consensus-taxon path ---
  use_candidates <- !is.null(plausible_taxa_col)

  if (use_candidates) {

    raw_sets  <- df[[plausible_taxa_col]]
    taxa_sets <- lapply(raw_sets, function(x) sort(unique(x[!is.na(x) & nzchar(x)])))
    n_cands   <- lengths(taxa_sets)

    # Build display labels (slash notation). Prefer a pre-computed label from
    # TaxaAssign::add_slash_taxon() when present -- its slash-name logic
    # clears the label to NA (falling back to consensus_taxon) for downranked
    # rows where the plausible-genera set no longer matches consensus_taxon,
    # a case .build_candidate_label() below cannot detect on its own (it only
    # sees plausible_taxa, not downranked/consensus_taxon). Rebuilding
    # independently risks producing a DIFFERENT label than add_slash_taxon()
    # would for the same row.
    cand_labels <- if ("consensus_OTU" %in% names(df)) {
      df[["consensus_OTU"]]
    } else {
      vapply(seq_along(taxa_sets), function(i) {
        if (n_cands[i] == 0L) return(NA_character_)
        if (n_cands[i] == 1L) return(taxa_sets[[i]])
        .build_candidate_label(taxa_sets[[i]])
      }, character(1L))
    }

    # Determine which rows to review
    if (irreducible_only) {
      if ("irreducible_consensus" %in% names(df)) {
        include_rows <- df[["irreducible_consensus"]] %in% TRUE
        if (verbose)
          message(sprintf(
            "  irreducible_only = TRUE: %d of %d rows selected for review.",
            sum(include_rows & n_cands > 0L), nrow(df)
          ))
      } else {
        if (verbose)
          message(paste0(
            "  irreducible_only = TRUE but 'irreducible_consensus' column not found. ",
            "Run TaxaAssign::add_slash_taxon() to enable filtering. ",
            "Reviewing all non-empty candidate sets."
          ))
        include_rows <- rep(TRUE, nrow(df))
      }
    } else {
      include_rows <- rep(TRUE, nrow(df))
    }

    # Exclude unresolved rows
    include_rows <- include_rows & n_cands > 0L

    # Store join key on df (label is the key — canonical because sets are sorted)
    df$.join_key <- cand_labels

    # Build taxa_info from unique labels in included rows
    inc_labels <- cand_labels[include_rows]
    inc_ranks  <- if (!is.null(taxon_rank_col)) {
      df[[taxon_rank_col]][include_rows]
    } else {
      rep(NA_character_, sum(include_rows))
    }

    taxa_info <- data.frame(
      taxon_name = inc_labels,
      taxon_rank = inc_ranks,
      stringsAsFactors = FALSE
    )
    taxa_info <- taxa_info[!duplicated(taxa_info$taxon_name), , drop = FALSE]

    if (nrow(taxa_info) == 0L)
      stop("No candidate sets to review after filtering. ",
           "Check 'irreducible_only' and 'plausible_taxa_col'.", call. = FALSE)

  } else {

    # --- Current path: dedup on consensus_taxon ---
    df$.join_key <- df[[taxon_col]]

    taxa <- unique(df[[taxon_col]])
    taxa <- taxa[!is.na(taxa) & nchar(trimws(taxa)) > 0]

    if (length(taxa) == 0L)
      stop(sprintf("No non-NA taxa found in column '%s'.", taxon_col), call. = FALSE)

    if (!is.null(taxon_rank_col)) {
      taxa_info <- unique(df[, c(taxon_col, taxon_rank_col), drop = FALSE])
      names(taxa_info) <- c("taxon_name", "taxon_rank")
      taxa_info <- taxa_info[!is.na(taxa_info$taxon_name) &
                               nchar(trimws(taxa_info$taxon_name)) > 0, , drop = FALSE]
      taxa_info <- taxa_info[!duplicated(taxa_info$taxon_name), , drop = FALSE]
    } else {
      taxa_info <- data.frame(taxon_name = taxa, taxon_rank = NA_character_,
                              stringsAsFactors = FALSE)
    }
  }

  # --- Optional pipeline-context annotation ---------------------------------
  # Purely additive text shown to the LLM (median pipeline posterior /
  # occurrence prior / rank-expanded flag / averaged candidate weights across
  # every row sharing a label) -- never changes which rows are reviewed, the
  # dedup key, or any output column. Grouping is O(n) via split(), not a
  # per-label linear scan, to stay cheap regardless of dataset size.
  label_vec_full <- if (use_candidates) cand_labels else df[[taxon_col]]

  pipeline_ctx <- .summarise_pipeline_context(
    label_vec_full, df, consensus_posterior_col, winner_prior_col,
    winner_rank_expanded_col
  )
  weight_ctx <- if (use_candidates && !is.null(plausible_posteriors_col) &&
                    plausible_posteriors_col %in% names(df)) {
    .summarise_candidate_weights(label_vec_full, df[[plausible_posteriors_col]])
  } else {
    NULL
  }

  if (!is.null(pipeline_ctx) || !is.null(weight_ctx)) {
    pn <- if (!is.null(pipeline_ctx))
      pipeline_ctx$pipeline_note[match(taxa_info$taxon_name, pipeline_ctx$taxon_name)]
    else rep(NA_character_, nrow(taxa_info))
    wn <- if (!is.null(weight_ctx))
      weight_ctx$weight_note[match(taxa_info$taxon_name, weight_ctx$taxon_name)]
    else rep(NA_character_, nrow(taxa_info))
    wn <- ifelse(is.na(wn), NA_character_, paste0("candidate weights: ", wn))
    taxa_info$pipeline_note <- .combine_notes(pn, wn)
  }

  if (verbose)
    message(sprintf("review_assignments: %d unique %s to review.",
                    nrow(taxa_info),
                    if (use_candidates) "candidate sets" else "taxa"))

  # --- Batch and call LLM ---
  n_taxa    <- nrow(taxa_info)
  tpc       <- min(taxa_per_call, n_taxa)
  batch_idx <- split(seq_len(n_taxa), ceiling(seq_len(n_taxa) / tpc))
  n_batches <- length(batch_idx)

  if (verbose)
    message(sprintf("  %d LLM call(s) needed (taxa_per_call = %d).",
                    n_batches, taxa_per_call))

  batch_results <- vector("list", n_batches)

  for (b in seq_along(batch_idx)) {
    taxa_batch <- taxa_info[batch_idx[[b]], , drop = FALSE]

    if (verbose)
      message(sprintf("  Calling LLM (batch %d/%d, %d %s)...",
                      b, n_batches, nrow(taxa_batch),
                      if (use_candidates) "candidate sets" else "taxa"))

    batch_results[[b]] <- .review_batch_with_retry(
      taxa_batch, ctx, target_group, marker, data_type, use_candidates,
      llm_fn, max_tokens, taxon_rank_col, verbose, pause_seconds,
      batch_label = as.character(b), max_retries = max_retries
    )

    if (b < n_batches) Sys.sleep(pause_seconds)
  }

  review_df <- do.call(rbind, batch_results)
  rownames(review_df) <- NULL

  if (verbose)
    message(sprintf("  Review complete. %d %s reviewed.",
                    nrow(review_df),
                    if (use_candidates) "candidate sets" else "taxa"))

  # --- Join back to input by .join_key ---
  merge_key <- data.frame(
    .join_key               = review_df$taxon_name,
    habitat_plausibility    = review_df$habitat_plausibility,
    geographic_plausibility = review_df$geographic_plausibility,
    scope_plausibility      = review_df$scope_plausibility,
    contamination_risk      = review_df$contamination_risk,
    review_alternatives     = review_df$review_alternatives,
    review_lower_hypotheses = review_df$review_lower_hypotheses,
    review_confidence       = review_df$review_confidence,
    review_comment          = review_df$review_comment,
    stringsAsFactors = FALSE
  )

  df$.row_id <- seq_len(nrow(df))
  result <- merge(df, merge_key, by = ".join_key", all.x = TRUE, sort = FALSE)
  result <- result[order(result$.row_id), , drop = FALSE]
  result$.row_id  <- NULL
  result$.join_key <- NULL
  rownames(result) <- NULL

  result
}


# ==============================================================================
# Internal helpers
# ==============================================================================

#' Build slash-style candidate label
#'
#' Constructs a compact slash-species string from a sorted, deduplicated
#' character vector of binomial names (length >= 2). Same-genus candidates
#' are abbreviated; mixed-genus groups are joined with " + ".
#' Mirrors TaxaAssign::.make_slash_name() — duplicated here to avoid a
#' dependency on TaxaAssign internals.
#'
#' @noRd
.build_candidate_label <- function(taxa_vec) {
  first_space <- regexpr(" ", taxa_vec, fixed = TRUE)
  has_space   <- first_space > 0L
  genera   <- ifelse(has_space, substr(taxa_vec, 1L, first_space - 1L), taxa_vec)
  epithets <- ifelse(has_space,
                     substr(taxa_vec, first_space + 1L, nchar(taxa_vec)),
                     taxa_vec)
  unique_genera <- unique(genera)
  if (length(unique_genera) == 1L) {
    paste0(unique_genera, " ", paste(epithets, collapse = "/"))
  } else {
    genus_strings <- vapply(unique_genera, function(g) {
      eps <- epithets[genera == g]
      if (length(eps) == 1L) paste(g, eps) else paste0(g, " ", paste(eps, collapse = "/"))
    }, character(1L))
    paste(genus_strings, collapse = " + ")
  }
}


#' Summarise Pipeline Confidence Context per Unique Taxon/Candidate-Set Label
#'
#' Aggregates \code{TaxaAssign::posterior_consensus()}'s confidence columns
#' (when present) across every \code{df} row sharing a taxon/candidate-set
#' label into one compact annotation string per unique label, so the LLM
#' reviewing a taxon sees the pipeline's OWN statistical confidence alongside
#' its ecological judgment -- without inflating the prompt with one value per
#' observation. Median is used (not mean) for robustness against a handful of
#' outlier observations sharing a common label. Grouping is done once via
#' \code{split()} (O(n)), not a per-label linear scan (O(n * unique labels)).
#' @noRd
.summarise_pipeline_context <- function(label_vec, df, consensus_posterior_col,
                                        winner_prior_col, winner_rank_expanded_col) {
  has_post  <- !is.null(consensus_posterior_col)  && consensus_posterior_col  %in% names(df)
  has_prior <- !is.null(winner_prior_col)         && winner_prior_col         %in% names(df)
  has_rexp  <- !is.null(winner_rank_expanded_col) && winner_rank_expanded_col %in% names(df)
  if (!has_post && !has_prior && !has_rexp) return(NULL)

  keep <- !is.na(label_vec)
  if (!any(keep)) return(NULL)

  groups <- split(which(keep), label_vec[keep])

  notes <- vapply(groups, function(rows) {
    parts <- character(0)
    if (has_post) {
      v <- stats::median(df[[consensus_posterior_col]][rows], na.rm = TRUE)
      if (!is.na(v)) parts <- c(parts, sprintf("pipeline posterior=%.2f", v))
    }
    if (has_prior) {
      v <- stats::median(df[[winner_prior_col]][rows], na.rm = TRUE)
      if (!is.na(v)) parts <- c(parts, sprintf("occurrence prior=%.2f", v))
    }
    if (has_rexp && isTRUE(any(df[[winner_rank_expanded_col]][rows], na.rm = TRUE))) {
      parts <- c(parts, paste0(
        "species-level ID from occurrence-prior tie-break, ",
        "no direct sequence discrimination"
      ))
    }
    if (length(parts) == 0L) NA_character_ else paste(parts, collapse = "; ")
  }, character(1L))

  data.frame(taxon_name = names(groups), pipeline_note = unname(notes),
             stringsAsFactors = FALSE)
}


#' Summarise Per-Candidate Posterior Weights for Multi-Candidate Labels
#'
#' For each unique multi-candidate label (contains \code{"/"} or \code{"+"}),
#' averages the per-candidate posterior weight (from
#' \code{posterior_consensus()}'s \code{plausible_posteriors} list column)
#' across every \code{df} row sharing that label, so the LLM sees which
#' specific member of the slash/plus group carries the most evidence rather
#' than assessing an unweighted set. Singleton labels are skipped -- there is
#' nothing to weight. Grouping via \code{split()} (O(n)), matching
#' \code{.summarise_pipeline_context()}.
#' @noRd
.summarise_candidate_weights <- function(label_vec, post_list) {
  is_multi <- !is.na(label_vec) & grepl("[/+]", label_vec)
  if (!any(is_multi)) return(NULL)

  groups <- split(which(is_multi), label_vec[is_multi])

  notes <- vapply(groups, function(rows) {
    vecs <- post_list[rows]
    vecs <- vecs[lengths(vecs) > 0L]
    if (length(vecs) == 0L) return(NA_character_)
    all_vals <- unlist(vecs, use.names = TRUE)
    agg <- sort(tapply(all_vals, names(all_vals), mean, na.rm = TRUE), decreasing = TRUE)
    paste(sprintf("%s %.0f%%", names(agg), agg * 100), collapse = ", ")
  }, character(1L))

  data.frame(taxon_name = names(groups), weight_note = unname(notes),
             stringsAsFactors = FALSE)
}


#' Combine Two Optional Note Strings
#' @noRd
.combine_notes <- function(a, b) {
  ifelse(is.na(a) & is.na(b), NA_character_,
  ifelse(is.na(a), b,
  ifelse(is.na(b), a, paste0(a, "; ", b))))
}


#' Normalise Context to Standard Fields
#' @noRd
.normalise_context <- function(context) {
  if (is.data.frame(context)) {
    ctx <- as.list(context[1, , drop = TRUE])
  } else if (is.list(context)) {
    ctx <- context
  } else {
    stop("'context' must be a named list or data frame.", call. = FALSE)
  }

  if (is.null(ctx$geography) && !is.null(ctx$ecoregion))
    ctx$geography <- ctx$ecoregion
  if (is.null(ctx$habitat) && !is.null(ctx$main_habitat))
    ctx$habitat <- ctx$main_habitat

  if (is.null(ctx$geography) || is.na(ctx$geography))
    warning("'context$geography' is missing. LLM review will lack geographic context.",
            call. = FALSE)
  if (is.null(ctx$habitat) || is.na(ctx$habitat))
    warning("'context$habitat' is missing. LLM review will lack habitat context.",
            call. = FALSE)

  ctx
}


#' Build Review Prompt for LLM
#' @noRd
.build_review_prompt <- function(taxa_batch, ctx, target_group, marker,
                                 data_type = "eDNA", use_candidates = FALSE) {

  # --- Context block ---
  context_lines <- character(0)
  if (!is.null(ctx$geography) && !is.na(ctx$geography))
    context_lines <- c(context_lines, sprintf("GEOGRAPHY: %s", ctx$geography))
  if (!is.null(ctx$habitat) && !is.na(ctx$habitat))
    context_lines <- c(context_lines, sprintf("HABITAT: %s", ctx$habitat))
  if (!is.null(ctx$date) && !is.na(ctx$date))
    context_lines <- c(context_lines, sprintf("DATE: %s", ctx$date))
  if (!is.null(target_group))
    context_lines <- c(context_lines, sprintf("TARGET GROUP: %s", target_group))
  if (!is.null(marker))
    context_lines <- c(context_lines, sprintf("MARKER / METHOD: %s", marker))

  context_block <- paste(context_lines, collapse = "\n")

  # --- Candidate notation definition (only when reviewing sets) ---
  notation_block <- if (use_candidates) {
    paste0(
      "CANDIDATE NOTATION:\n",
      'When a taxon entry contains "/" or "+", it represents an unresolved ',
      "assignment with multiple equally plausible candidate species:\n",
      '  "/" separates species epithets within the same genus ',
      '(e.g., "Bos javanicus/primigenius" = Bos javanicus or Bos primigenius).\n',
      '  "+" separates candidate groups from different genera ',
      '(e.g., "Bos javanicus/primigenius + Bison bonasus" = one of those three species).\n',
      "Assess the candidate group as a whole. Use review_comment to note if a ",
      "specific member is implausible."
    )
  } else {
    NULL
  }

  # --- Taxa list ---
  taxa_lines <- vapply(seq_len(nrow(taxa_batch)), function(i) {
    tn <- taxa_batch$taxon_name[i]
    tr <- taxa_batch$taxon_rank[i]
    rank_str <- if (!is.na(tr) && nchar(tr) > 0) tr else NULL

    base <- if (use_candidates && grepl("[/+]", tn)) {
      # Multi-candidate entry
      if (!is.null(rank_str)) {
        sprintf("- %s (unresolved candidates; consensus rank: %s)", tn, rank_str)
      } else {
        sprintf("- %s (unresolved candidates)", tn)
      }
    } else {
      # Singleton or consensus-taxon entry
      if (!is.null(rank_str)) {
        sprintf("- %s (rank: %s)", tn, rank_str)
      } else {
        sprintf("- %s", tn)
      }
    }

    # Optional pipeline-context annotation (see .summarise_pipeline_context()/
    # .summarise_candidate_weights()) -- absent/NA for any batch built
    # without it, so this is a no-op unless review_assignments()'s *_col
    # params found a matching column.
    note <- if ("pipeline_note" %in% names(taxa_batch)) taxa_batch$pipeline_note[i] else NA_character_
    if (!is.na(note)) base <- paste0(base, " [", note, "]")
    base
  }, character(1))

  taxa_block <- paste(taxa_lines, collapse = "\n")

  # --- Scope instructions ---
  scope_instruction <- if (!is.null(target_group)) {
    sprintf(
      '  "scope_plausibility": one of "likely", "possible", "unlikely" (does this taxon belong to the target group: %s?),',
      target_group
    )
  } else {
    '  "scope_plausibility": null (no target group specified),'
  }

  # --- Lower hypotheses instructions ---
  # Suppressed when reviewing candidate sets (species already known to pipeline)
  lower_instruction <- if (use_candidates) {
    '  "review_lower_hypotheses": null (candidate species already provided by the pipeline),'
  } else {
    has_ranks <- any(!is.na(taxa_batch$taxon_rank))
    if (has_ranks) {
      '  "review_lower_hypotheses": comma-separated string of finer-rank taxa expected at this location and habitat, or null if taxon is already at species level or you cannot suggest any,'
    } else {
      '  "review_lower_hypotheses": null (no rank information provided),'
    }
  }

  # --- Contaminant guidance ---
  contaminant_guideline <- switch(data_type,
    eDNA     = paste0(
      "For contaminant assessment, consider: Homo sapiens and domestic animals are common ",
      "contaminants in molecular studies. Common lab contaminants include Bos taurus, ",
      "Sus scrofa, Gallus gallus, and other food-source species."
    ),
    acoustic = paste0(
      "For contaminant assessment, consider: human vocalizations and handler noise near ",
      "recording equipment are common false positives. Domestic animals (dogs, livestock) ",
      "and vehicles can produce false species matches."
    ),
    image    = paste0(
      "For contaminant assessment, consider: handler presence during camera setup/teardown ",
      "events and domestic animals are common false positives in camera trap data."
    ),
    paste0(
      "For contaminant assessment, consider taxon-specific false positive sources ",
      "appropriate for the detection method used."
    )
  )

  example_comment <- switch(data_type,
    eDNA     = "Common lab contaminant in eDNA studies",
    acoustic = "Human vocalization detected near recording equipment",
    image    = "Handler detected during camera setup event",
    "Common false positive for this detection method"
  )

  # --- Assemble prompt ---
  header_sections <- c(
    'You are an expert wildlife biologist, biogeographer, and taxonomist.\n',
    'STUDY CONTEXT:\n', context_block, '\n'
  )
  if (!is.null(notation_block))
    header_sections <- c(header_sections, '\n', notation_block, '\n')

  prompt <- paste0(
    paste(header_sections, collapse = ""), '\n',
    'TASK: Review each taxon below and assess whether it is a plausible detection ',
    'given the study context. Return your assessment as a valid JSON array with one ',
    'object per taxon. Return ONLY the JSON array -- no markdown fences, no explanation ',
    'before or after.\n\n',
    'Each object must have these fields:\n',
    '  "taxon_name": the exact taxon name as provided,\n',
    '  "habitat_plausibility": one of "likely", "possible", "unlikely",\n',
    '  "geographic_plausibility": one of "likely", "possible", "unlikely",\n',
    scope_instruction, '\n',
    '  "contamination_risk": one of "low", "moderate", "high",\n',
    '  "review_alternatives": comma-separated string of plausible alternative taxa ',
    'that better fit the geography and habitat, or null if the taxon is plausible,\n',
    lower_instruction, '\n',
    '  "review_confidence": one of "high", "moderate", "low",\n',
    '  "review_comment": a brief free-text note, or null\n\n',
    'GUIDELINES:\n',
    '- "review_alternatives" means "you might have the wrong taxon" -- suggest ',
    'relatives that better fit the context.\n',
    '- ', contaminant_guideline, '\n',
    '- Be conservative with "unlikely" -- only use it when reasonably confident.\n',
    '- If uncertain, use "possible" or "moderate" rather than making a strong claim.\n',
    '- When a taxon line ends with a "[...]" bracket, that is the statistical ',
    'pipeline\'s OWN confidence for this call (posterior/occurrence prior/candidate ',
    'weights), not your input. Use it to flag disagreement between the pipeline\'s ',
    'confidence and your own ecological judgment in review_comment -- e.g. a low ',
    'pipeline posterior alongside your own "likely" rating is worth a note -- but do ',
    'not let it override your independent plausibility assessment itself.\n\n',
    'EXAMPLE OUTPUT FORMAT:\n',
    '[\n',
    '  {"taxon_name": "Gobiidae", "habitat_plausibility": "likely", ',
    '"geographic_plausibility": "likely", "scope_plausibility": "likely", ',
    '"contamination_risk": "low", "review_alternatives": null, ',
    '"review_lower_hypotheses": null, "review_confidence": "high", ',
    '"review_comment": null},\n',
    '  {"taxon_name": "Homo sapiens", "habitat_plausibility": "unlikely", ',
    '"geographic_plausibility": "likely", "scope_plausibility": "unlikely", ',
    '"contamination_risk": "high", "review_alternatives": null, ',
    '"review_lower_hypotheses": null, "review_confidence": "high", ',
    '"review_comment": "', example_comment, '"}\n',
    ']\n\n',
    'TAXA TO REVIEW:\n',
    taxa_block
  )

  prompt
}


#' Call LLM for a Batch, Retrying with Smaller Sub-batches on Truncation/Failure
#'
#' A truncated, empty, or unparseable response is very often caused by the
#' requested batch overflowing \code{llm_fn}'s response token budget --
#' \code{taxa_per_call} is a single global knob, so the safest per-batch fix
#' is to halve just the batch that actually failed and retry (a smaller batch
#' asks for a proportionally shorter response, directly relieving the token
#' pressure) rather than lowering \code{taxa_per_call} for the whole run.
#' A hard \code{llm_fn} error (network/auth/etc.) is deliberately NOT retried
#' this way -- a smaller batch can't fix a broken call, so that error is
#' surfaced once, immediately, exactly as before this mechanism existed.
#' @noRd
.review_batch_with_retry <- function(taxa_batch, ctx, target_group, marker,
                                     data_type, use_candidates, llm_fn,
                                     max_tokens, taxon_rank_col, verbose,
                                     pause_seconds, batch_label, max_retries,
                                     depth = 0L) {

  prompt <- .build_review_prompt(taxa_batch, ctx, target_group, marker,
                                 data_type, use_candidates)

  call_error <- NULL
  raw <- tryCatch(
    if (is.null(max_tokens)) llm_fn(prompt) else llm_fn(prompt, max_tokens = max_tokens),
    error = function(e) {
      call_error <<- conditionMessage(e)
      NULL
    }
  )

  if (!is.null(call_error)) {
    warning(sprintf("LLM call failed for batch %s: %s. Using NA defaults.",
                    batch_label, call_error), call. = FALSE)
    result <- .parse_review_response(NULL, taxa_batch, target_group,
                                     taxon_rank_col, use_candidates)
    attr(result, "status")           <- NULL
    attr(result, "pending_warnings") <- NULL
    return(result)
  }

  parsed  <- .parse_review_response(raw, taxa_batch, target_group,
                                    taxon_rank_col, use_candidates)
  status  <- attr(parsed, "status")
  pending <- attr(parsed, "pending_warnings")

  can_retry <- status %in% c("truncated", "failed") &&
    depth < max_retries && nrow(taxa_batch) > 1L

  if (can_retry) {
    if (verbose)
      message(sprintf(
        "  Batch %s %s (%d taxa) -- retrying as smaller sub-batches...",
        batch_label,
        if (status == "failed") "returned no usable content" else "was truncated",
        nrow(taxa_batch)
      ))
    mid   <- ceiling(nrow(taxa_batch) / 2)
    left  <- taxa_batch[seq_len(mid), , drop = FALSE]
    right <- taxa_batch[(mid + 1L):nrow(taxa_batch), , drop = FALSE]

    left_result <- .review_batch_with_retry(
      left, ctx, target_group, marker, data_type, use_candidates, llm_fn,
      max_tokens, taxon_rank_col, verbose, pause_seconds,
      paste0(batch_label, "a"), max_retries, depth + 1L
    )
    Sys.sleep(pause_seconds)
    right_result <- .review_batch_with_retry(
      right, ctx, target_group, marker, data_type, use_candidates, llm_fn,
      max_tokens, taxon_rank_col, verbose, pause_seconds,
      paste0(batch_label, "b"), max_retries, depth + 1L
    )
    return(rbind(left_result, right_result))
  }

  for (w in pending) warning(w, call. = FALSE)
  attr(parsed, "status")           <- NULL
  attr(parsed, "pending_warnings") <- NULL
  parsed
}


#' Parse LLM Review Response
#'
#' Never calls \code{warning()} directly. Returns the parsed result with two
#' attributes -- \code{status} (\code{"complete"}, \code{"truncated"}, or
#' \code{"failed"}) and \code{pending_warnings} (character vector of
#' not-yet-emitted warning messages) -- so \code{.review_batch_with_retry()}
#' can decide whether to retry with a smaller batch before emitting anything.
#' @noRd
.parse_review_response <- function(response, taxa_batch, target_group,
                                   taxon_rank_col, use_candidates = FALSE) {

  expected_taxa <- taxa_batch$taxon_name
  make_default <- function() {
    data.frame(
      taxon_name              = expected_taxa,
      habitat_plausibility    = NA_character_,
      geographic_plausibility = NA_character_,
      scope_plausibility      = NA_character_,
      contamination_risk      = NA_character_,
      review_alternatives     = NA_character_,
      review_lower_hypotheses = NA_character_,
      review_confidence       = NA_character_,
      review_comment          = NA_character_,
      stringsAsFactors = FALSE
    )
  }

  .with_status <- function(result, status, pending_warnings = character(0)) {
    attr(result, "status")           <- status
    attr(result, "pending_warnings") <- pending_warnings
    result
  }

  if (is.null(response) || !nzchar(trimws(response))) {
    return(.with_status(make_default(), "failed",
                        "Empty LLM response. Returning NA defaults."))
  }

  cleaned <- trimws(response)

  # Strategy 1: Strip markdown fences
  if (grepl("```", cleaned)) {
    fenced <- sub("(?s).*?```(?:json)?\\s*", "", cleaned, perl = TRUE)
    fenced <- sub("(?s)\\s*```.*", "", fenced, perl = TRUE)
    fenced <- trimws(fenced)
  } else {
    fenced <- cleaned
  }

  # Strategy 2: Parse directly
  parsed <- tryCatch(
    jsonlite::fromJSON(fenced, simplifyDataFrame = TRUE),
    error = function(e) NULL
  )

  # Strategy 3: Extract [...] array
  if (is.null(parsed) || !is.data.frame(parsed)) {
    arr_str <- sub("(?s).*?(\\[\\s*\\{[\\s\\S]*\\}\\s*\\]).*", "\\1",
                   cleaned, perl = TRUE)
    parsed <- tryCatch(
      jsonlite::fromJSON(arr_str, simplifyDataFrame = TRUE),
      error = function(e) NULL
    )
  }

  # Strategy 4: Truncated JSON recovery
  if (is.null(parsed) || !is.data.frame(parsed))
    parsed <- .recover_truncated_json(fenced)

  if (is.null(parsed) || !is.data.frame(parsed) || nrow(parsed) == 0L) {
    n <- nchar(trimws(response))
    tail_str <- if (n > 200L) substr(trimws(response), max(1L, n - 200L), n) else trimws(response)
    return(.with_status(make_default(), "failed", sprintf(
      "Could not parse LLM response as JSON. Returning NA defaults.\n  Response length: %d chars; ends with: ...%s",
      n, tail_str
    )))
  }

  pending <- character(0)
  status  <- "complete"

  n_recovered <- nrow(parsed)
  n_expected  <- length(expected_taxa)
  if (n_recovered < n_expected) {
    status  <- "truncated"
    pending <- c(pending, sprintf(
      "LLM response was truncated. Recovered %d of %d taxa from partial JSON.",
      n_recovered, n_expected
    ))
  }

  if (!"taxon_name" %in% names(parsed)) {
    return(.with_status(make_default(), "failed",
                        "LLM response missing 'taxon_name' field. Returning NA defaults."))
  }

  .safe_col <- function(col_name) {
    if (col_name %in% names(parsed)) {
      vals <- as.character(parsed[[col_name]])
      vals[vals %in% c("null", "NULL", "NA")] <- NA_character_
      vals
    } else {
      rep(NA_character_, nrow(parsed))
    }
  }

  result <- data.frame(
    taxon_name              = as.character(parsed$taxon_name),
    habitat_plausibility    = .safe_col("habitat_plausibility"),
    geographic_plausibility = .safe_col("geographic_plausibility"),
    scope_plausibility      = .safe_col("scope_plausibility"),
    contamination_risk      = .safe_col("contamination_risk"),
    review_alternatives     = .safe_col("review_alternatives"),
    review_lower_hypotheses = .safe_col("review_lower_hypotheses"),
    review_confidence       = .safe_col("review_confidence"),
    review_comment          = .safe_col("review_comment"),
    stringsAsFactors = FALSE
  )

  if (is.null(target_group))
    result$scope_plausibility <- NA_character_

  # Suppress lower hypotheses when candidates were supplied (already known)
  if (use_candidates || is.null(taxon_rank_col))
    result$review_lower_hypotheses <- NA_character_

  # Normalize taxon names: strip trailing punctuation + case-fold for matching.
  # LLMs sometimes append periods, commas, or authority strings to names they
  # return. Exact-string join would silently drop those rows. Attempt a
  # normalised fallback: if a result name doesn't match any expected name
  # exactly but matches one after normalisation, remap it to the canonical
  # expected name and warn so the caller can inspect.
  # Also strips a trailing "(rank: ...)" annotation -- taxa_batch's own prompt
  # rendering shows each taxon as "- Cottus (rank: Cottus aleuticus)" when
  # taxon_rank_col is supplied, and "taxon_name: the exact taxon name as
  # provided" can lead the LLM to echo the whole displayed string back,
  # including the parenthetical, rather than just the bare name. Confirmed as
  # a real failure mode 2026-07-14: an entire batch's taxon_name values came
  # back as "Cottus (rank: Cottus aleuticus)" etc., which the previous
  # punctuation-only normalisation couldn't recover -- every taxon in the
  # batch was wrongly treated as omitted and filled with NA, regardless of how
  # easy the taxon itself was to assess.
  .norm <- function(x) {
    x <- sub("(?i)\\s*\\(\\s*rank\\s*:.*\\)\\s*$", "", trimws(x), perl = TRUE)
    tolower(trimws(gsub("[.,;:]+$", "", trimws(x))))
  }
  expected_norm <- .norm(expected_taxa)

  unmatched_idx <- which(!result$taxon_name %in% expected_taxa)
  if (length(unmatched_idx) > 0L) {
    result_norm <- .norm(result$taxon_name)
    remapped <- character(0)
    for (i in unmatched_idx) {
      hit <- which(expected_norm == result_norm[i])
      if (length(hit) == 1L) {
        remapped <- c(remapped,
                      sprintf("'%s' -> '%s'", result$taxon_name[i], expected_taxa[hit]))
        result$taxon_name[i] <- expected_taxa[hit]
      }
    }
    if (length(remapped) > 0L)
      pending <- c(pending, sprintf(
        "LLM returned %d name(s) that required normalised matching: %s",
        length(remapped), paste(remapped, collapse = "; ")
      ))
  }

  # Fill any remaining missing taxa (truly absent from LLM response) with NAs
  missing_taxa <- setdiff(expected_taxa, result$taxon_name)
  if (length(missing_taxa) > 0L) {
    pending <- c(pending, sprintf("LLM omitted %d taxa. Filling with NA defaults: %s",
                    length(missing_taxa),
                    paste(missing_taxa, collapse = ", ")))
    missing_rows <- data.frame(
      taxon_name              = missing_taxa,
      habitat_plausibility    = NA_character_,
      geographic_plausibility = NA_character_,
      scope_plausibility      = NA_character_,
      contamination_risk      = NA_character_,
      review_alternatives     = NA_character_,
      review_lower_hypotheses = NA_character_,
      review_confidence       = NA_character_,
      review_comment          = NA_character_,
      stringsAsFactors = FALSE
    )
    result <- rbind(result, missing_rows)
  }

  result <- result[result$taxon_name %in% expected_taxa, , drop = FALSE]

  .with_status(result, status, pending)
}


#' Recover Parseable Objects from Truncated JSON Array
#' @noRd
.recover_truncated_json <- function(text) {
  if (is.null(text) || !nzchar(trimws(text))) return(NULL)

  arr_start <- regexpr("\\[", text)
  if (arr_start < 0L) return(NULL)

  text_from_arr    <- substring(text, arr_start)
  brace_positions  <- gregexpr("\\}", text_from_arr)[[1]]
  if (brace_positions[1] < 0L) return(NULL)

  for (i in rev(seq_along(brace_positions))) {
    candidate <- paste0(substring(text_from_arr, 1L, brace_positions[i]), "\n]")
    parsed <- tryCatch(
      jsonlite::fromJSON(candidate, simplifyDataFrame = TRUE),
      error = function(e) NULL
    )
    if (is.data.frame(parsed) && nrow(parsed) > 0L) return(parsed)
  }

  NULL
}
