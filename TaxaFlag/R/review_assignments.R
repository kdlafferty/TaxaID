
#' LLM Expert Review of Taxonomic Assignments
#'
#' Sends unique taxa from a consensus table to an LLM for structured expert
#' review. The LLM assesses each taxon for habitat fit, geographic plausibility,
#' contaminant risk, and (optionally) taxonomic scope. It also suggests
#' plausible alternative taxa and finer-rank hypotheses where appropriate.
#'
#' Works with any data frame containing a taxon column -- not restricted to
#' TaxaAssign output. Context (geography, habitat) can be supplied as a
#' \code{build_context()} object from TaxaAssign, or as a simple named list.
#'
#' @param df Data frame with at minimum a column of taxon names.
#' @param taxon_col Character. Column name for consensus taxon. Default
#'   \code{"consensus_taxon"}.
#' @param taxon_rank_col Character or \code{NULL}. Column name for consensus
#'   rank (e.g., "species", "genus"). When supplied AND rank is coarser than
#'   species, the LLM populates \code{review_lower_hypotheses}. Default
#'   \code{NULL}.
#' @param context Named list or data frame describing the study context.
#'   Recognised fields: \code{geography} (or \code{ecoregion}),
#'   \code{habitat} (or \code{main_habitat}), \code{date}. A
#'   \code{build_context()} output works directly. At minimum, supply
#'   \code{geography} and \code{habitat}.
#' @param target_group Character or \code{NULL}. Taxonomic target group
#'   (e.g., \code{"fish"}, \code{"birds"}). When supplied, the LLM
#'   populates \code{review_scope}. Default \code{NULL}.
#' @param marker Character or \code{NULL}. Molecular marker or detection
#'   method (e.g., \code{"12S"}, \code{"COI"}, \code{"camera trap"}).
#'   Provides contaminant context. Default \code{NULL}.
#' @param llm_fn Function. LLM provider function with signature
#'   \code{function(prompt_str, ...)}. Default
#'   \code{TaxaTools::call_anthropic_api}.
#' @param taxa_per_call Integer. Maximum taxa per LLM call. Default
#'   \code{15L}. Kept moderate to avoid LLM response truncation (each
#'   taxon requires ~100-150 output tokens).
#' @param pause_seconds Numeric. Seconds to pause between LLM calls.
#'   Default \code{1}.
#' @param verbose Logical. Print progress messages. Default \code{TRUE}.
#'
#' @return The input data frame with 8 columns appended:
#' \describe{
#'   \item{\code{review_habitat}}{expected / occasional / unlikely}
#'   \item{\code{review_geography}}{expected / occasional / unlikely}
#'   \item{\code{review_scope}}{in_scope / marginal / out_of_scope (NA if
#'     \code{target_group} not supplied)}
#'   \item{\code{review_contaminant}}{unlikely / possible / likely}
#'   \item{\code{review_alternatives}}{Comma-separated plausible alternatives
#'     at the same rank, or NA}
#'   \item{\code{review_lower_hypotheses}}{Comma-separated finer-rank taxa
#'     expected at this location, or NA}
#'   \item{\code{review_confidence}}{high / moderate / low}
#'   \item{\code{review_comment}}{Free-text note, or NA}
#' }
#'
#' @seealso \code{\link{flag_contaminant}} for data-driven contaminant detection,
#'   \code{\link{flag_handler}} for temporal proximity flagging
#'
#' @examples
#' \dontrun{
#' # Basic review with geography and habitat
#' reviewed <- review_assignments(
#'   df         = consensus_df,
#'   taxon_col  = "consensus_taxon",
#'   context    = list(geography = "Palmyra Atoll, central Pacific",
#'                     habitat   = "coral reef"),
#'   target_group = "fish",
#'   marker       = "12S MiFish"
#' )
#'
#' # Using build_context() output from TaxaAssign
#' reviewed <- review_assignments(
#'   df         = consensus_df,
#'   taxon_col  = "consensus_taxon",
#'   context    = ctx,
#'   target_group = "fish"
#' )
#' }
#'
#' @export
review_assignments <- function(df,
                               taxon_col      = "consensus_taxon",
                               taxon_rank_col = NULL,
                               context,
                               target_group   = NULL,
                               marker         = NULL,
                               llm_fn         = TaxaTools::call_anthropic_api,
                               taxa_per_call  = 15L,
                               pause_seconds  = 1,
                               verbose        = TRUE) {

  # --- Input validation ---
  if (!is.data.frame(df)) stop("'df' must be a data frame.", call. = FALSE)

  if (!taxon_col %in% names(df))
    stop(sprintf("Column '%s' not found in df.", taxon_col), call. = FALSE)

  if (!is.null(taxon_rank_col) && !taxon_rank_col %in% names(df))
    stop(sprintf("Column '%s' not found in df.", taxon_rank_col), call. = FALSE)

  if (missing(context) || is.null(context))
    stop("'context' is required. Supply a named list or build_context() output.",
         call. = FALSE)

  # --- Normalise context ---
  ctx <- .normalise_context(context)

  # --- Extract unique taxa ---
  taxa <- unique(df[[taxon_col]])
  taxa <- taxa[!is.na(taxa) & nchar(trimws(taxa)) > 0]

  if (length(taxa) == 0L)
    stop(sprintf("No non-NA taxa found in column '%s'.", taxon_col), call. = FALSE)

  # Build taxa info data frame
  if (!is.null(taxon_rank_col)) {
    taxa_info <- unique(df[, c(taxon_col, taxon_rank_col), drop = FALSE])
    names(taxa_info) <- c("taxon_name", "taxon_rank")
    taxa_info <- taxa_info[!is.na(taxa_info$taxon_name) &
                             nchar(trimws(taxa_info$taxon_name)) > 0, ,
                           drop = FALSE]
    # Deduplicate (keep first rank per taxon)
    taxa_info <- taxa_info[!duplicated(taxa_info$taxon_name), , drop = FALSE]
  } else {
    taxa_info <- data.frame(taxon_name = taxa, taxon_rank = NA_character_,
                            stringsAsFactors = FALSE)
  }

  if (verbose)
    message(sprintf("review_assignments: %d unique taxa to review.", nrow(taxa_info)))

  # --- Batch and call LLM ---
  n_taxa <- nrow(taxa_info)
  tpc <- min(taxa_per_call, n_taxa)
  batch_idx <- split(seq_len(n_taxa), ceiling(seq_len(n_taxa) / tpc))
  n_batches <- length(batch_idx)

  if (verbose)
    message(sprintf("  %d LLM call(s) needed (taxa_per_call = %d).",
                    n_batches, taxa_per_call))

  batch_results <- vector("list", n_batches)

  for (b in seq_along(batch_idx)) {
    taxa_batch <- taxa_info[batch_idx[[b]], , drop = FALSE]

    if (verbose)
      message(sprintf("  Calling LLM (batch %d/%d, %d taxa)...",
                      b, n_batches, nrow(taxa_batch)))

    prompt <- .build_review_prompt(taxa_batch, ctx, target_group, marker)

    raw <- tryCatch(
      llm_fn(prompt),
      error = function(e) {
        warning(sprintf("LLM call failed for batch %d: %s. Using NA defaults.",
                        b, conditionMessage(e)), call. = FALSE)
        NULL
      }
    )

    batch_results[[b]] <- .parse_review_response(
      raw, taxa_batch, target_group, taxon_rank_col
    )

    if (b < n_batches) Sys.sleep(pause_seconds)
  }

  review_df <- do.call(rbind, batch_results)
  rownames(review_df) <- NULL

  if (verbose) {
    message(sprintf("  Review complete. %d taxa reviewed.", nrow(review_df)))
  }

  # --- Join back to input ---
  # Rename taxon_name to match the user's column name for merging
  merge_key <- data.frame(
    key        = review_df$taxon_name,
    review_habitat          = review_df$review_habitat,
    review_geography        = review_df$review_geography,
    review_scope            = review_df$review_scope,
    review_contaminant      = review_df$review_contaminant,
    review_alternatives     = review_df$review_alternatives,
    review_lower_hypotheses = review_df$review_lower_hypotheses,
    review_confidence       = review_df$review_confidence,
    review_comment          = review_df$review_comment,
    stringsAsFactors = FALSE
  )
  names(merge_key)[1] <- taxon_col

  # Preserve original row order through merge
  df$.row_id <- seq_len(nrow(df))
  result <- merge(df, merge_key, by = taxon_col, all.x = TRUE, sort = FALSE)
  result <- result[order(result$.row_id), , drop = FALSE]
  result$.row_id <- NULL
  rownames(result) <- NULL

  result
}


#' Normalise Context to Standard Fields
#'
#' Accepts either a build_context() data frame or a named list and returns
#' a list with standardised field names.
#'
#' @param context Named list or data frame.
#' @return Named list with fields: geography, habitat, date.
#' @noRd
.normalise_context <- function(context) {
  if (is.data.frame(context)) {
    # build_context() returns a 1-row data frame
    ctx <- as.list(context[1, , drop = TRUE])
  } else if (is.list(context)) {
    ctx <- context
  } else {
    stop("'context' must be a named list or data frame.", call. = FALSE)
  }

  # Normalise field names
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
#'
#' Constructs a structured prompt asking the LLM to review a batch of taxa.
#'
#' @param taxa_batch Data frame with columns taxon_name, taxon_rank.
#' @param ctx Normalised context list.
#' @param target_group Character or NULL.
#' @param marker Character or NULL.
#' @return Character string (the prompt).
#' @noRd
.build_review_prompt <- function(taxa_batch, ctx, target_group, marker) {

  # --- Context block ---
  context_lines <- character(0)
  if (!is.null(ctx$geography) && !is.na(ctx$geography))
    context_lines <- c(context_lines,
                       sprintf("GEOGRAPHY: %s", ctx$geography))
  if (!is.null(ctx$habitat) && !is.na(ctx$habitat))
    context_lines <- c(context_lines,
                       sprintf("HABITAT: %s", ctx$habitat))
  if (!is.null(ctx$date) && !is.na(ctx$date))
    context_lines <- c(context_lines,
                       sprintf("DATE: %s", ctx$date))
  if (!is.null(target_group))
    context_lines <- c(context_lines,
                       sprintf("TARGET GROUP: %s", target_group))
  if (!is.null(marker))
    context_lines <- c(context_lines,
                       sprintf("MARKER / METHOD: %s", marker))

  context_block <- paste(context_lines, collapse = "\n")

  # --- Taxa list ---
  taxa_lines <- vapply(seq_len(nrow(taxa_batch)), function(i) {
    tn <- taxa_batch$taxon_name[i]
    tr <- taxa_batch$taxon_rank[i]
    if (!is.na(tr) && nchar(tr) > 0) {
      sprintf("- %s (rank: %s)", tn, tr)
    } else {
      sprintf("- %s", tn)
    }
  }, character(1))

  taxa_block <- paste(taxa_lines, collapse = "\n")

  # --- Scope instructions ---
  scope_instruction <- if (!is.null(target_group)) {
    sprintf(
      '  "review_scope": one of "in_scope", "marginal", "out_of_scope" (does this taxon belong to the target group: %s?),',
      target_group
    )
  } else {
    '  "review_scope": null (no target group specified),'
  }

  # --- Lower hypotheses instructions ---
  has_ranks <- any(!is.na(taxa_batch$taxon_rank))
  lower_instruction <- if (has_ranks) {
    '  "review_lower_hypotheses": comma-separated string of finer-rank taxa (e.g., likely species within a genus) expected at this location and habitat, or null if taxon is already at species level or you cannot suggest any,'
  } else {
    '  "review_lower_hypotheses": null (no rank information provided),'
  }

  # --- Build full prompt ---
  prompt <- sprintf(
    'You are an expert wildlife biologist, biogeographer, and taxonomist.

STUDY CONTEXT:
%s

TASK: Review each taxon below and assess whether it is a plausible detection given the study context. Return your assessment as a valid JSON array with one object per taxon. Return ONLY the JSON array -- no markdown fences, no explanation before or after.

Each object must have these fields:
  "taxon_name": the exact taxon name as provided,
  "review_habitat": one of "expected", "occasional", "unlikely" (does this taxon live in this habitat type?),
  "review_geography": one of "expected", "occasional", "unlikely" (is this taxon found in this geographic region?),
%s
  "review_contaminant": one of "unlikely", "possible", "likely" (is this a common lab or field contaminant, or a human-associated taxon that commonly appears as contamination?),
  "review_alternatives": comma-separated string of plausible alternative taxa at the same rank that better fit the geography and habitat, or null if the taxon is plausible,
%s
  "review_confidence": one of "high", "moderate", "low" (your overall confidence in these assessments),
  "review_comment": a brief free-text note with any additional context, or null

GUIDELINES:
- "review_alternatives" means "you might have the wrong taxon" -- suggest relatives that better fit the context. Most useful when habitat or geography is "unlikely".
- "review_lower_hypotheses" means "you have the right group but could narrow it down" -- suggest species expected at this location when the consensus is at genus or family level.
- For contaminant assessment, consider: Homo sapiens and domestic animals are common contaminants in molecular studies. Common lab contaminants include Bos taurus, Sus scrofa, Gallus gallus, and other food-source species.
- Be conservative with "unlikely" -- only use it when you are reasonably confident the taxon does not belong.
- If you are uncertain, use "occasional" or "moderate" rather than making a strong claim.

EXAMPLE OUTPUT FORMAT:
[
  {"taxon_name": "Gobiidae", "review_habitat": "expected", "review_geography": "expected", "review_scope": "in_scope", "review_contaminant": "unlikely", "review_alternatives": null, "review_lower_hypotheses": "Clevelandia ios, Gillichthys mirabilis", "review_confidence": "high", "review_comment": null},
  {"taxon_name": "Homo sapiens", "review_habitat": "unlikely", "review_geography": "expected", "review_scope": "out_of_scope", "review_contaminant": "likely", "review_alternatives": null, "review_lower_hypotheses": null, "review_confidence": "high", "review_comment": "Common lab contaminant in eDNA studies"}
]

TAXA TO REVIEW:
%s',
    context_block, scope_instruction, lower_instruction, taxa_block
  )

  prompt
}


#' Parse LLM Review Response
#'
#' Extracts JSON array from LLM response and validates fields.
#'
#' @param response Character string (raw LLM response) or NULL.
#' @param taxa_batch Data frame with expected taxa.
#' @param target_group Character or NULL.
#' @param taxon_rank_col Character or NULL (whether rank info was provided).
#' @return Data frame with review columns, one row per taxon.
#' @noRd
.parse_review_response <- function(response, taxa_batch, target_group,
                                   taxon_rank_col) {

  expected_taxa <- taxa_batch$taxon_name
  make_default <- function() {
    data.frame(
      taxon_name              = expected_taxa,
      review_habitat          = NA_character_,
      review_geography        = NA_character_,
      review_scope            = NA_character_,
      review_contaminant      = NA_character_,
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

  # Extract JSON array — try multiple strategies
  cleaned <- trimws(response)

  # Strategy 1: Strip markdown code fences (use lazy .*? to match FIRST fence)
  if (grepl("```", cleaned)) {
    fenced <- sub("(?s).*?```(?:json)?\\s*", "", cleaned, perl = TRUE)
    fenced <- sub("(?s)\\s*```.*", "", fenced, perl = TRUE)
    fenced <- trimws(fenced)
  } else {
    fenced <- cleaned
  }

  # Strategy 2: Try parsing the fence-stripped text directly
  parsed <- tryCatch(
    jsonlite::fromJSON(fenced, simplifyDataFrame = TRUE),
    error = function(e) NULL
  )

  # Strategy 3: Extract [...] bracket-delimited array
  if (is.null(parsed) || !is.data.frame(parsed)) {
    arr_str <- sub("(?s).*?(\\[\\s*\\{[\\s\\S]*\\}\\s*\\]).*", "\\1",
                   cleaned, perl = TRUE)
    parsed <- tryCatch(
      jsonlite::fromJSON(arr_str, simplifyDataFrame = TRUE),
      error = function(e) NULL
    )
  }

  # Strategy 4: Truncated JSON recovery — find last complete object and close array
  if (is.null(parsed) || !is.data.frame(parsed)) {
    parsed <- .recover_truncated_json(fenced)
  }

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

  # Report partial recovery
  n_recovered <- nrow(parsed)
  n_expected <- length(expected_taxa)
  if (n_recovered < n_expected) {
    warning(sprintf(
      "LLM response was truncated. Recovered %d of %d taxa from partial JSON.",
      n_recovered, n_expected
    ), call. = FALSE)
  }

  if (!"taxon_name" %in% names(parsed)) {
    warning("LLM response missing 'taxon_name' field. Returning NA defaults.",
            call. = FALSE)
    return(make_default())
  }

  # Extract fields with safe defaults
  .safe_col <- function(col_name) {
    if (col_name %in% names(parsed)) {
      vals <- as.character(parsed[[col_name]])
      vals[vals == "null" | vals == "NULL" | vals == "NA"] <- NA_character_
      vals
    } else {
      rep(NA_character_, nrow(parsed))
    }
  }

  result <- data.frame(
    taxon_name              = as.character(parsed$taxon_name),
    review_habitat          = .safe_col("review_habitat"),
    review_geography        = .safe_col("review_geography"),
    review_scope            = .safe_col("review_scope"),
    review_contaminant      = .safe_col("review_contaminant"),
    review_alternatives     = .safe_col("review_alternatives"),
    review_lower_hypotheses = .safe_col("review_lower_hypotheses"),
    review_confidence       = .safe_col("review_confidence"),
    review_comment          = .safe_col("review_comment"),
    stringsAsFactors = FALSE
  )

  # Nullify review_scope if target_group was not supplied
  if (is.null(target_group))
    result$review_scope <- NA_character_

  # Nullify review_lower_hypotheses if rank info was not supplied
  if (is.null(taxon_rank_col))
    result$review_lower_hypotheses <- NA_character_

  # Handle missing taxa -- fill with NA defaults
  missing_taxa <- setdiff(expected_taxa, result$taxon_name)
  if (length(missing_taxa) > 0L) {
    warning(sprintf("LLM omitted %d taxa. Filling with NA defaults.",
                    length(missing_taxa)), call. = FALSE)
    missing_rows <- data.frame(
      taxon_name              = missing_taxa,
      review_habitat          = NA_character_,
      review_geography        = NA_character_,
      review_scope            = NA_character_,
      review_contaminant      = NA_character_,
      review_alternatives     = NA_character_,
      review_lower_hypotheses = NA_character_,
      review_confidence       = NA_character_,
      review_comment          = NA_character_,
      stringsAsFactors = FALSE
    )
    result <- rbind(result, missing_rows)
  }

  # Drop any extra taxa the LLM hallucinated
  result <- result[result$taxon_name %in% expected_taxa, , drop = FALSE]

  result
}


#' Recover Parseable Objects from Truncated JSON Array
#'
#' When an LLM response is cut off mid-JSON (due to max_tokens), this finds
#' the last complete object in the array and closes it so the partial result
#' can still be parsed.
#'
#' @param text Character. The (possibly truncated) JSON text.
#' @return Data frame from the recovered portion, or NULL if recovery fails.
#' @noRd
.recover_truncated_json <- function(text) {
  if (is.null(text) || !nzchar(trimws(text))) return(NULL)


  # Find the array start
  arr_start <- regexpr("\\[", text)
  if (arr_start < 0L) return(NULL)

  text_from_arr <- substring(text, arr_start)

  # Find the position of the last complete "}" that ends an object

  # Walk backward through "}" positions and try closing the array after each
  brace_positions <- gregexpr("\\}", text_from_arr)[[1]]
  if (brace_positions[1] < 0L) return(NULL)

  # Try from the last "}" backward
  for (i in rev(seq_along(brace_positions))) {
    candidate <- paste0(
      substring(text_from_arr, 1L, brace_positions[i]),
      "\n]"
    )
    parsed <- tryCatch(
      jsonlite::fromJSON(candidate, simplifyDataFrame = TRUE),
      error = function(e) NULL
    )
    if (is.data.frame(parsed) && nrow(parsed) > 0L) return(parsed)
  }

  NULL
}
