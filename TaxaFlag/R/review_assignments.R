
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
                               context,
                               target_group       = NULL,
                               marker             = NULL,
                               data_type          = "eDNA",
                               llm_fn             = getOption("TaxaID.llm_fn", TaxaTools::call_api),
                               taxa_per_call      = 15L,
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

    # Build display labels (slash notation)
    cand_labels <- vapply(seq_along(taxa_sets), function(i) {
      if (n_cands[i] == 0L) return(NA_character_)
      if (n_cands[i] == 1L) return(taxa_sets[[i]])
      .build_candidate_label(taxa_sets[[i]])
    }, character(1L))

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

    prompt <- .build_review_prompt(taxa_batch, ctx, target_group, marker,
                                   data_type, use_candidates)

    raw <- tryCatch(
      llm_fn(prompt),
      error = function(e) {
        warning(sprintf("LLM call failed for batch %d: %s. Using NA defaults.",
                        b, conditionMessage(e)), call. = FALSE)
        NULL
      }
    )

    batch_results[[b]] <- .parse_review_response(
      raw, taxa_batch, target_group, taxon_rank_col, use_candidates
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

    if (use_candidates && grepl("[/+]", tn)) {
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
    '- If uncertain, use "possible" or "moderate" rather than making a strong claim.\n\n',
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


#' Parse LLM Review Response
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

  if (is.null(response) || !nzchar(trimws(response))) {
    warning("Empty LLM response. Returning NA defaults.", call. = FALSE)
    return(make_default())
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
    warning(
      "Could not parse LLM response as JSON. Returning NA defaults.\n",
      "  Response length: ", n, " chars; ends with: ...", tail_str,
      call. = FALSE
    )
    return(make_default())
  }

  n_recovered <- nrow(parsed)
  n_expected  <- length(expected_taxa)
  if (n_recovered < n_expected)
    warning(sprintf(
      "LLM response was truncated. Recovered %d of %d taxa from partial JSON.",
      n_recovered, n_expected
    ), call. = FALSE)

  if (!"taxon_name" %in% names(parsed)) {
    warning("LLM response missing 'taxon_name' field. Returning NA defaults.",
            call. = FALSE)
    return(make_default())
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
  .norm <- function(x) tolower(trimws(gsub("[.,;:]+$", "", trimws(x))))
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
      warning(sprintf(
        "LLM returned %d name(s) that required normalised matching: %s",
        length(remapped), paste(remapped, collapse = "; ")
      ), call. = FALSE)
  }

  # Fill any remaining missing taxa (truly absent from LLM response) with NAs
  missing_taxa <- setdiff(expected_taxa, result$taxon_name)
  if (length(missing_taxa) > 0L) {
    warning(sprintf("LLM omitted %d taxa. Filling with NA defaults: %s",
                    length(missing_taxa),
                    paste(missing_taxa, collapse = ", ")), call. = FALSE)
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

  result
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
