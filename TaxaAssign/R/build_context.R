#' Build Site Context from Taxon Names
#'
#' Infers a site-level context data frame (\code{main_habitat}, \code{ecoregion},
#' \code{date}) from a list of candidate taxon names using LLM-based habitat
#' assignment. This automates the manual creation of the \code{context} argument
#' required by \code{\link{assign_taxa_llm}}.
#'
#' The function calls \code{\link[TaxaHabitat]{build_habitat_prompt}} to generate
#' an LLM prompt, submits it via \code{llm_fn}, parses the response with
#' \code{\link[TaxaHabitat]{parse_hierarchical_habitat_response}}, and summarises
#' the assemblage with \code{\link[TaxaHabitat]{consensus_habitat}}. A final
#' short LLM call synthesises a natural-language habitat description from the
#' habitat proportions and species list, which is more informative for
#' transitional environments (e.g. estuaries, coastal lagoons) than the
#' mechanical argmax of habitat weights.
#'
#' @param taxon_names Character vector of scientific names (e.g.
#'   \code{unique(match_df$taxon_name)}).
#' @param geographic_hint Optional character string describing the approximate
#'   geographic region (e.g. \code{"Southern California"}, \code{"Chesapeake Bay
#'   watershed"}). Passed to \code{build_habitat_prompt(geographic_context = ...)}.
#'   When non-NULL, the LLM also returns an \code{ecoregion_best_guess} column.
#' @param date Optional character string for the sampling date or year
#'   (e.g. \code{"2025"}). Passed through to the returned \code{ctx} data frame.
#' @param habitat_scheme Passed to
#'   \code{\link[TaxaHabitat]{build_habitat_prompt}}. Default \code{NULL}
#'   (Marine / Freshwater / Terrestrial).
#' @param llm_fn Function or NULL. LLM provider following the TaxaTools
#'   \code{llm_fn} pattern. Default NULL resolves to
#'   \code{TaxaTools::call_anthropic_api} (requires TaxaTools).
#' @param chunk_size Integer. Maximum taxa per prompt chunk. Default 60.
#'
#' @return A one-row data frame with columns:
#' \describe{
#'   \item{ecoregion}{Character. Inferred ecoregion, or \code{NA} if
#'     \code{geographic_hint} was \code{NULL}.}
#'   \item{main_habitat}{Character. Consensus habitat across the assemblage.}
#'   \item{date}{Character. Passed through from the \code{date} argument.}
#' }
#' The per-species habitat weight table is attached as
#' \code{attr(result, "habitats_df")} for inspection.
#'
#' @seealso \code{\link{assign_taxa_llm}},
#'   \code{\link[TaxaHabitat]{build_habitat_prompt}},
#'   \code{\link[TaxaHabitat]{consensus_habitat}}
#'
#' @export
#'
#' @examples
#' \dontrun{
#' ctx <- build_context(
#'   taxon_names     = unique(match_df$taxon_name),
#'   geographic_hint = "Southern California",
#'   date            = "2025",
#'   llm_fn          = TaxaTools::call_anthropic_api  # or any llm_fn provider
#' )
#' result <- assign_taxa_llm(match_df, context = ctx, llm_fn = llm_fn)
#'
#' # Inspect per-species habitat weights
#' attr(ctx, "habitats_df")
#' }

build_context <- function(taxon_names,
                          geographic_hint = NULL,
                          date            = NULL,
                          habitat_scheme  = NULL,
                          llm_fn          = NULL,
                          chunk_size      = 60L) {

  # --- Resolve llm_fn default ---
  llm_fn <- .resolve_llm_fn(llm_fn, "build_context")

  # --- Check TaxaHabitat availability ---
  if (!requireNamespace("TaxaHabitat", quietly = TRUE)) {
    stop(
      "build_context: the TaxaHabitat package is required but not installed.\n",
      "Install it with: devtools::install('<path_to_TaxaHabitat>')",
      call. = FALSE
    )
  }

  # --- Input validation ---
  if (!is.character(taxon_names) || length(taxon_names) == 0) {
    stop("build_context: 'taxon_names' must be a non-empty character vector.")
  }
  if (!is.null(date) && (!is.character(date) || length(date) != 1L)) {
    stop("build_context: 'date' must be NULL or a single character string.")
  }
  if (!is.function(llm_fn)) {
    stop("build_context: 'llm_fn' must be a function.")
  }

  taxon_names <- unique(trimws(taxon_names))
  taxon_names <- taxon_names[!is.na(taxon_names) & nzchar(taxon_names)]

  # --- Step 1: build habitat prompt ---
  prompt <- TaxaHabitat::build_habitat_prompt(
    taxon_list         = taxon_names,
    habitat_scheme     = habitat_scheme,
    geographic_context = geographic_hint,
    chunk_size         = chunk_size
  )

  # --- Step 2: submit each chunk to the LLM ---
  raw_texts <- character(prompt$n_chunks)
  for (i in seq_len(prompt$n_chunks)) {
    message(sprintf("build_context: submitting chunk %d of %d to LLM...",
                    i, prompt$n_chunks))
    raw_texts[i] <- llm_fn(prompt$prompts[[i]])
  }

  # --- Step 3: parse LLM responses ---
  habitats_list <- lapply(seq_len(prompt$n_chunks), function(i) {
    TaxaHabitat::parse_hierarchical_habitat_response(
      raw_text       = raw_texts[i],
      taxon_list     = prompt$chunks[[i]],
      habitat_scheme = prompt
    )
  })
  habitats_df <- do.call(rbind, habitats_list)

  # --- Step 4: compute consensus proportions ---
  consensus <- TaxaHabitat::consensus_habitat(habitats_df)
  props     <- attr(consensus, "habitat_proportions")

  # --- Step 5: LLM synthesis of habitat description ---
  # The argmax habitat can be misleading for transitional environments

  # (e.g. a coastal lagoon scores ~60% Freshwater / ~40% Marine, but the
  # argmax "Freshwater" misses the estuarine character). A short synthesis
  # call lets the LLM interpret the proportions in geographic context.
  synthesis_prompt <- .build_synthesis_prompt(
    taxon_names        = taxon_names,
    props              = props,
    geographic_hint    = geographic_hint,
    ecoregion          = consensus$ecoregion
  )
  message("build_context: synthesising habitat description...")
  synthesis_raw    <- llm_fn(synthesis_prompt)
  synthesis        <- .parse_synthesis_response(synthesis_raw)
  main_habitat     <- synthesis$main_habitat
  ecoregion        <- synthesis$ecoregion

  # Fall back to mechanical consensus if synthesis fails

  if (is.na(main_habitat)) main_habitat <- consensus$main_habitat
  if (is.na(ecoregion))    ecoregion    <- consensus$ecoregion

  # --- Step 6: assemble ctx data frame ---
  ctx <- data.frame(
    ecoregion    = ecoregion,
    main_habitat = main_habitat,
    date         = if (is.null(date)) NA_character_ else date,
    stringsAsFactors = FALSE
  )
  attr(ctx, "habitats_df") <- habitats_df
  attr(ctx, "habitat_proportions") <- props

  message(sprintf(
    "build_context: main_habitat = '%s', ecoregion = '%s'",
    if (is.na(ctx$main_habitat)) "(NA)" else ctx$main_habitat,
    if (is.na(ctx$ecoregion)) "(NA)" else ctx$ecoregion
  ))

  ctx
}


# ==============================================================================
# Internal helpers
# ==============================================================================

#' Build a short synthesis prompt from habitat proportions
#' @noRd
.build_synthesis_prompt <- function(taxon_names, props, geographic_hint,
                                    ecoregion) {
  # Format proportions as a readable string (only habitats > 1%)
  props_above <- props[props > 0.01]
  props_str   <- paste(
    sprintf("%s: %.0f%%", names(props_above), props_above * 100),
    collapse = ", "
  )

  # Representative species (up to 10)
  sp_sample <- utils::head(taxon_names, 10)
  sp_str    <- paste(sp_sample, collapse = ", ")
  if (length(taxon_names) > 10) {
    sp_str <- paste0(sp_str, sprintf(" (and %d more)", length(taxon_names) - 10))
  }

  geo_line <- if (!is.null(geographic_hint)) {
    sprintf("Geographic region: %s\n", geographic_hint)
  } else ""

  eco_line <- if (!is.na(ecoregion)) {
    sprintf("Ecoregion from per-species consensus: %s\n", ecoregion)
  } else ""

  paste0(
    "You are an expert ecologist. Based on the species assemblage and habitat ",
    "proportions below, describe the most likely sampling habitat and ecoregion.\n\n",
    geo_line,
    eco_line,
    "Habitat proportions across the assemblage: ", props_str, "\n",
    "Representative species: ", sp_str, "\n\n",
    "Respond with EXACTLY two lines, no other text:\n",
    "main_habitat: <short habitat description, 3-8 words, e.g. 'coastal lagoon / estuary'>\n",
    "ecoregion: <most specific recognized ecoregion name>\n"
  )
}


#' Parse the two-line synthesis response
#' @noRd
.parse_synthesis_response <- function(raw) {
  lines <- trimws(strsplit(trimws(raw), "\n")[[1]])
  lines <- lines[nzchar(lines)]

  main_habitat <- NA_character_
  ecoregion    <- NA_character_

  for (ln in lines) {
    if (grepl("^main_habitat:", ln, ignore.case = TRUE)) {
      main_habitat <- trimws(sub("^main_habitat:\\s*", "", ln, ignore.case = TRUE))
    } else if (grepl("^ecoregion:", ln, ignore.case = TRUE)) {
      ecoregion <- trimws(sub("^ecoregion:\\s*", "", ln, ignore.case = TRUE))
    }
  }

  # Clean up empty strings
  if (!is.na(main_habitat) && !nzchar(main_habitat)) main_habitat <- NA_character_
  if (!is.na(ecoregion) && !nzchar(ecoregion)) ecoregion <- NA_character_

  list(main_habitat = main_habitat, ecoregion = ecoregion)
}
