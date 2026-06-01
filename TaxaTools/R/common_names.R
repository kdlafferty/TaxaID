# ==============================================================================
# common_names.R
# TaxaTools -- LLM-assisted common name -> scientific name lookup
#
# Exported:
#   common_to_scientific()
# ==============================================================================


# ==============================================================================
# common_to_scientific()
# ==============================================================================

#' Convert Common Names to Scientific Names
#'
#' Uses a large language model (LLM) to convert a character vector of common
#' names to scientific names, optionally narrowing the search with a taxonomic
#' group and geographic location.  When \code{verify = TRUE} (default), each
#' LLM-suggested scientific name is checked against the specified taxonomic
#' backbone via \code{\link{verify_taxon_names}}, guarding against
#' hallucination.
#'
#' @details
#' Common names are inherently ambiguous: "Robin" means
#' \emph{Turdus migratorius} in North America but \emph{Erithacus rubecula}
#' in Europe; "Hawk" has no unambiguous species referent.  Supplying
#' \code{taxon_group} and \code{location} resolves most ambiguities.  The
#' function sends all names in a single LLM call and returns one row per
#' input name.
#'
#' When a name is too ambiguous to resolve, the LLM returns \code{NA} for
#' \code{scientific_name_llm} with an explanatory \code{notes} entry.  When
#' \code{verify = TRUE} and backbone verification fails (name not found or
#' spelling inconsistent), \code{scientific_name_verified} is \code{NA} and
#' \code{verified} is \code{FALSE}.  Returning the unverified LLM suggestion
#' in a separate column allows the user to inspect and decide rather than
#' silently discarding potentially useful information.
#'
#' @param common_names Character vector of common names to look up.
#' @param taxon_group Character string narrowing the taxonomic search scope
#'   (e.g., \code{"birds"}, \code{"freshwater fish"}, \code{"mammals"}).
#'   Strongly recommended when names could apply to multiple groups.
#'   Default \code{NULL}.
#' @param location Character string providing geographic context for
#'   regionally ambiguous names
#'   (e.g., \code{"Pacific Northwest, USA"}, \code{"United Kingdom"}).
#'   Default \code{NULL}.
#' @param backbone_id Integer. Taxonomic backbone for verification.
#'   \code{11} = GBIF (default), \code{3} = ITIS, \code{4} = NCBI,
#'   \code{9} = WoRMS, \code{1} = Catalogue of Life.
#' @param verify Logical. If \code{TRUE} (default), runs
#'   \code{\link{verify_taxon_names}} on each non-\code{NA} LLM suggestion
#'   and populates \code{scientific_name_verified} and \code{verified}.
#' @param llm_fn Function with signature \code{function(prompt, ...) ->
#'   character(1)}. Default \code{getOption("TaxaID.llm_fn")}.
#' @param ... Additional arguments passed to \code{llm_fn}.
#'
#' @return A data frame with one row per element of \code{common_names}:
#'   \describe{
#'     \item{\code{common_name}}{Input common name (character).}
#'     \item{\code{scientific_name_llm}}{Scientific name suggested by the LLM,
#'       or \code{NA} if ambiguous or unknown.}
#'     \item{\code{scientific_name_verified}}{Backbone-verified scientific name
#'       (from \code{verify_taxon_names}), or \code{NA} if verification failed
#'       or \code{verify = FALSE}.}
#'     \item{\code{backbone_id}}{Backbone used for verification (integer).}
#'     \item{\code{verified}}{Logical; \code{TRUE} if \code{verify = TRUE} and
#'       the backbone returned a match.}
#'     \item{\code{notes}}{Character; LLM explanation for ambiguous or
#'       unresolved names.}
#'   }
#'
#' @seealso \code{\link{verify_taxon_names}}, \code{\link{clean_taxon_names}}
#'
#' @examples
#' \dontrun{
#' library(TaxaTools)
#'
#' # Basic lookup with geographic context
#' result <- common_to_scientific(
#'   common_names = c("Robin", "Song Sparrow", "Bald Eagle"),
#'   taxon_group  = "birds",
#'   location     = "Pacific Northwest, USA"
#' )
#' result[, c("common_name", "scientific_name_verified", "verified")]
#'
#' # Ambiguous name without context: notes column explains
#' result2 <- common_to_scientific("Hawk")
#' result2$notes
#' # "Too coarse without taxon_group or location context"
#'
#' # Camera trap common names from SpeciesNet output
#' result3 <- common_to_scientific(
#'   common_names = c("White-tailed Deer", "Raccoon", "Wild Turkey"),
#'   taxon_group  = "mammals and birds",
#'   location     = "Eastern USA"
#' )
#' }
#'
#' @importFrom dplyr bind_rows
#' @export
common_to_scientific <- function(common_names,
                                   taxon_group = NULL,
                                   location    = NULL,
                                   backbone_id = 11L,
                                   verify      = TRUE,
                                   llm_fn      = getOption("TaxaID.llm_fn"),
                                   ...) {

  # ---- input validation -------------------------------------------------------
  if (!is.character(common_names) || length(common_names) == 0L)
    stop("common_names must be a non-empty character vector", call. = FALSE)
  if (!is.null(taxon_group) && (!is.character(taxon_group) || length(taxon_group) != 1L))
    stop("taxon_group must be a single character string or NULL", call. = FALSE)
  if (!is.null(location) && (!is.character(location) || length(location) != 1L))
    stop("location must be a single character string or NULL", call. = FALSE)
  if (!is.logical(verify) || length(verify) != 1L || is.na(verify))
    stop("verify must be TRUE or FALSE", call. = FALSE)
  if (is.null(llm_fn))
    stop(
      "No LLM function configured. Load TaxaTools with library(TaxaTools) to ",
      "auto-detect a provider, or supply llm_fn explicitly.",
      call. = FALSE
    )
  if (!is.function(llm_fn))
    stop("llm_fn must be a function", call. = FALSE)

  # ---- build prompt -----------------------------------------------------------
  names_block <- paste(
    vapply(seq_along(common_names), function(i)
      sprintf('  %d. "%s"', i, common_names[[i]]), character(1L)),
    collapse = "\n"
  )

  context_lines <- character(0L)
  if (!is.null(taxon_group))
    context_lines <- c(context_lines,
                       sprintf("Taxonomic group: %s", taxon_group))
  if (!is.null(location))
    context_lines <- c(context_lines,
                       sprintf("Geographic location: %s", location))
  context_block <- if (length(context_lines) > 0L)
    paste0("\nContext:\n", paste(context_lines, collapse = "\n"), "\n")
  else
    ""

  prompt <- paste0(
    "You are a taxonomist. Convert the following common names to scientific ",
    "names (binomial nomenclature where possible).\n",
    context_block,
    "\nCommon names:\n",
    names_block,
    "\n\nRespond with a JSON array only -- no markdown, no extra text. ",
    "Each element must have exactly these keys:\n",
    '  "common_name"     : the input common name (string)\n',
    '  "scientific_name" : binomial scientific name, or null if ambiguous/unknown\n',
    '  "notes"           : brief explanation for null entries, else empty string\n',
    "\nIf a name is too coarse or regionally ambiguous to resolve without ",
    "more context, set scientific_name to null and explain in notes.\n",
    "Return exactly ", length(common_names), " elements in the same order as ",
    "the input list."
  )

  # ---- call LLM ---------------------------------------------------------------
  raw <- llm_fn(prompt, ...)

  # ---- parse JSON response ----------------------------------------------------
  # Strip markdown fences if present
  json_text <- gsub("(?s)^```(?:json)?\\s*", "", raw, perl = TRUE)
  json_text <- gsub("(?s)\\s*```$",          "", json_text, perl = TRUE)
  json_text <- trimws(json_text)

  parsed <- tryCatch(
    jsonlite::fromJSON(json_text, simplifyDataFrame = TRUE),
    error = function(e) NULL
  )

  if (is.null(parsed) || !is.data.frame(parsed) ||
      !all(c("common_name", "scientific_name") %in% names(parsed))) {
    warning(
      "Could not parse LLM response as JSON. Returning raw text in 'notes'.",
      call. = FALSE
    )
    return(data.frame(
      common_name             = common_names,
      scientific_name_llm     = NA_character_,
      scientific_name_verified = NA_character_,
      backbone_id             = as.integer(backbone_id),
      verified                = FALSE,
      notes                   = raw,
      stringsAsFactors        = FALSE
    ))
  }

  # Align rows to input order (LLM may reorder)
  llm_names  <- as.character(parsed$common_name)
  llm_sci    <- as.character(parsed$scientific_name)
  llm_sci[llm_sci == "NULL" | llm_sci == "null"] <- NA_character_
  llm_notes  <- if ("notes" %in% names(parsed)) as.character(parsed$notes)
                else rep("", nrow(parsed))

  # Match back to input order
  idx        <- match(tolower(trimws(common_names)),
                      tolower(trimws(llm_names)))
  sci_ordered   <- ifelse(is.na(idx), NA_character_, llm_sci[idx])
  notes_ordered <- ifelse(is.na(idx), "LLM response row not matched",
                          llm_notes[idx])

  # ---- verify via backbone ----------------------------------------------------
  sci_verified <- rep(NA_character_, length(common_names))
  is_verified  <- rep(FALSE,         length(common_names))

  if (verify) {
    to_verify <- !is.na(sci_ordered) & nzchar(sci_ordered)
    if (any(to_verify)) {
      vdf <- verify_taxon_names(
        sci_ordered[to_verify],
        backbone_id = as.integer(backbone_id)
      )
      # verify_taxon_names returns a data frame; verified names in
      # $name_verified (or similar column — use first non-input column)
      verified_col <- if ("name_verified" %in% names(vdf)) "name_verified"
                      else names(vdf)[ncol(vdf)]
      sci_verified[to_verify] <- as.character(vdf[[verified_col]])
      is_verified[to_verify]  <- !is.na(sci_verified[to_verify])
    }
  }

  # ---- assemble output --------------------------------------------------------
  data.frame(
    common_name              = common_names,
    scientific_name_llm      = sci_ordered,
    scientific_name_verified = sci_verified,
    backbone_id              = as.integer(backbone_id),
    verified                 = is_verified,
    notes                    = notes_ordered,
    stringsAsFactors         = FALSE
  )
}
