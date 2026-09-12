# ==============================================================================
# common_names.R
# TaxaTools -- Common name <-> scientific name lookups
#
# Exported:
#   common_to_scientific
#   scientific_to_common
# Internal:
#   .gbif_common_names
#   .itis_common_names
#   .llm_common_names
# ==============================================================================


# ==============================================================================
# common_to_scientific
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
                                 location = NULL,
                                 backbone_id = 11L,
                                 verify = TRUE,
                                 llm_fn = getOption("TaxaID.llm_fn"),
                                 ...) {
  # ---- input validation -------------------------------------------------------
  if (!is.character(common_names) || length(common_names) == 0L) {
    stop("common_names must be a non-empty character vector", call. = FALSE)
  }
  if (!is.null(taxon_group) && (!is.character(taxon_group) || length(taxon_group) != 1L)) {
    stop("taxon_group must be a single character string or NULL", call. = FALSE)
  }
  if (!is.null(location) && (!is.character(location) || length(location) != 1L)) {
    stop("location must be a single character string or NULL", call. = FALSE)
  }
  if (!is.logical(verify) || length(verify) != 1L || is.na(verify)) {
    stop("verify must be TRUE or FALSE", call. = FALSE)
  }
  if (is.null(llm_fn)) {
    stop(
      "No LLM function configured. Load TaxaTools with library(TaxaTools) to ",
      "auto-detect a provider, or supply llm_fn explicitly.",
      call. = FALSE
    )
  }
  if (!is.function(llm_fn)) {
    stop("llm_fn must be a function", call. = FALSE)
  }

  # ---- build prompt -----------------------------------------------------------
  names_block <- paste(
    vapply(seq_along(common_names), function(i) {
      sprintf('  %d. "%s"', i, common_names[[i]])
    }, character(1L)),
    collapse = "\n"
  )

  context_lines <- character(0L)
  if (!is.null(taxon_group)) {
    context_lines <- c(
      context_lines,
      sprintf("Taxonomic group: %s", taxon_group)
    )
  }
  if (!is.null(location)) {
    context_lines <- c(
      context_lines,
      sprintf("Geographic location: %s", location)
    )
  }
  if (length(context_lines) > 0L) {
    context_block <- paste0("\nContext:\n", paste(context_lines, collapse = "\n"), "\n")
  } else {
    context_block <- ""
  }

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
  json_text <- gsub("(?s)\\s*```$", "", json_text, perl = TRUE)
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
      common_name = common_names,
      scientific_name_llm = NA_character_,
      scientific_name_verified = NA_character_,
      backbone_id = as.integer(backbone_id),
      verified = FALSE,
      notes = raw,
      stringsAsFactors = FALSE
    ))
  }

  # Align rows to input order (LLM may reorder)
  llm_names <- as.character(parsed$common_name)
  llm_sci <- as.character(parsed$scientific_name)
  llm_sci[llm_sci == "NULL" | llm_sci == "null"] <- NA_character_
  llm_notes <- if ("notes" %in% names(parsed)) {
    as.character(parsed$notes)
  } else {
    rep("", nrow(parsed))
  }

  # Match back to input order
  idx <- match(
    tolower(trimws(common_names)),
    tolower(trimws(llm_names))
  )
  sci_ordered <- ifelse(is.na(idx), NA_character_, llm_sci[idx])
  notes_ordered <- ifelse(is.na(idx), "LLM response row not matched",
    llm_notes[idx]
  )

  # ---- verify via backbone ----------------------------------------------------
  sci_verified <- rep(NA_character_, length(common_names))
  is_verified <- rep(FALSE, length(common_names))

  if (verify) {
    to_verify <- !is.na(sci_ordered) & nzchar(sci_ordered)
    if (any(to_verify)) {
      vdf <- verify_taxon_names(
        sci_ordered[to_verify],
        backbone_id = as.integer(backbone_id)
      )
      # verify_taxon_names returns a data frame; verified names in
      # $name_verified (or similar column — use first non-input column)
      verified_col <- if ("name_verified" %in% names(vdf)) {
        "name_verified"
      } else {
        names(vdf)[ncol(vdf)]
      }
      sci_verified[to_verify] <- as.character(vdf[[verified_col]])
      is_verified[to_verify] <- !is.na(sci_verified[to_verify])
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


# ==============================================================================
# scientific_to_common() -- internal helpers
# ==============================================================================

# Returns list(primary = character(1), alternatives = character(1) or NA)
# or NULL when nothing found.
#' @noRd
.gbif_common_names <- function(name) {
  if (!requireNamespace("rgbif", quietly = TRUE)) {
    stop("Package 'rgbif' is required for backbone_id = 11. ",
      "Install with: install.packages('rgbif')",
      call. = FALSE
    )
  }
  bb <- tryCatch(
    rgbif::name_backbone(name = name, strict = FALSE),
    error = function(e) NULL
  )
  if (is.null(bb) || identical(bb$matchType, "NONE")) {
    return(NULL)
  }
  # Use speciesKey when available; fall back to usageKey for higher ranks
  key <- if (!is.null(bb$speciesKey) && !is.na(bb$speciesKey)) {
    bb$speciesKey
  } else {
    bb$usageKey
  }
  if (is.null(key) || is.na(key)) {
    return(NULL)
  }
  vn <- tryCatch(
    rgbif::name_usage(key = key, data = "vernacularNames"),
    error = function(e) NULL
  )
  if (is.null(vn) || is.null(vn$data) || nrow(vn$data) == 0L) {
    return(NULL)
  }
  eng <- vn$data[!is.na(vn$data$language) & vn$data$language == "eng",
    "vernacularName",
    drop = TRUE
  ]
  eng <- unique(trimws(as.character(eng)))
  eng <- eng[nzchar(eng)]
  if (length(eng) == 0L) {
    return(NULL)
  }
  list(
    primary = eng[[1L]],
    alternatives = if (length(eng) > 1L) {
      paste(eng[-1L], collapse = "; ")
    } else {
      NA_character_
    }
  )
}

#' @noRd
.itis_common_names <- function(name) {
  if (!requireNamespace("taxize", quietly = TRUE)) {
    stop("Package 'taxize' is required for backbone_id = 3. ",
      "Install with: install.packages('taxize')",
      call. = FALSE
    )
  }
  tsn <- tryCatch(
    suppressMessages(
      taxize::get_tsn(name, accepted = TRUE, ask = FALSE, messages = FALSE)
    ),
    error = function(e) NA_character_
  )
  if (length(tsn) == 0L || is.na(tsn[[1L]])) {
    return(NULL)
  }
  rec <- tryCatch(
    taxize::itis_getrecord(tsn[[1L]]),
    error = function(e) NULL
  )
  if (is.null(rec)) {
    return(NULL)
  }
  cn <- tryCatch(rec$commonNameList$commonNames, error = function(e) NULL)
  if (is.null(cn) || nrow(cn) == 0L) {
    return(NULL)
  }
  eng <- cn[tolower(cn$language) == "english", "commonName", drop = TRUE]
  eng <- unique(trimws(as.character(eng)))
  eng <- eng[nzchar(eng)]
  if (length(eng) == 0L) {
    return(NULL)
  }
  list(
    primary = eng[[1L]],
    alternatives = if (length(eng) > 1L) {
      paste(eng[-1L], collapse = "; ")
    } else {
      NA_character_
    }
  )
}

# Batch LLM lookup for a character vector of scientific names.
# Returns a data frame with columns: scientific_name, common_name,
# common_name_alternatives (may be NA).
#' @noRd
.llm_common_names <- function(names, llm_fn, location = NULL,
                              batch_size = 20L, verbose = TRUE, ...) {
  location_line <- if (!is.null(location)) {
    sprintf("\nGeographic context: %s. Prefer common names in use for this region.\n", location)
  } else {
    ""
  }

  .parse_one_batch <- function(batch_names) {
    names_block <- paste(
      vapply(seq_along(batch_names), function(i) {
        sprintf('  %d. "%s"', i, batch_names[[i]])
      }, character(1L)),
      collapse = "\n"
    )
    prompt <- paste0(
      "You are a taxonomist. Provide English common names for the following ",
      "scientific names.", location_line,
      "\nScientific names:\n", names_block,
      "\n\nRespond with a JSON array only -- no markdown, no extra text. ",
      "Each element must have exactly these keys:\n",
      "  \"scientific_name\"           : the input scientific name (string)\n",
      "  \"common_name\"               : primary English common name, or null if none\n",
      "  \"common_name_alternatives\"  : comma-separated list of other English common ",
      "names as a single string, or null if none\n",
      "\nReturn exactly ", length(batch_names),
      " elements in the same order as the input list."
    )
    raw <- llm_fn(prompt, ...)
    json_text <- gsub("(?s)^```(?:json)?\\s*", "", raw, perl = TRUE)
    json_text <- gsub("(?s)\\s*```$", "", json_text, perl = TRUE)
    json_text <- trimws(json_text)
    parsed <- tryCatch(
      jsonlite::fromJSON(json_text, simplifyDataFrame = TRUE),
      error = function(e) NULL
    )
    if (is.null(parsed) || !is.data.frame(parsed) ||
      !"scientific_name" %in% names(parsed)) {
      warning(sprintf(
        "Could not parse LLM response as JSON for batch starting with '%s'.",
        batch_names[[1L]]
      ), call. = FALSE)
      return(data.frame(
        scientific_name          = batch_names,
        common_name              = NA_character_,
        common_name_alternatives = NA_character_,
        llm_parsed               = FALSE,
        stringsAsFactors         = FALSE
      ))
    }
    llm_sci <- as.character(parsed$scientific_name)
    llm_cn <- if ("common_name" %in% names(parsed)) {
      as.character(parsed$common_name)
    } else {
      rep(NA_character_, nrow(parsed))
    }
    llm_alt <- if ("common_name_alternatives" %in% names(parsed)) {
      as.character(parsed$common_name_alternatives)
    } else {
      rep(NA_character_, nrow(parsed))
    }
    llm_cn[llm_cn %in% c("NULL", "null", "NA")] <- NA_character_
    llm_alt[llm_alt %in% c("NULL", "null", "NA")] <- NA_character_
    idx <- match(tolower(trimws(batch_names)), tolower(trimws(llm_sci)))
    data.frame(
      scientific_name          = batch_names,
      common_name              = ifelse(is.na(idx), NA_character_, llm_cn[idx]),
      common_name_alternatives = ifelse(is.na(idx), NA_character_, llm_alt[idx]),
      # TRUE when the batch parsed: a NULL common name from a parsed batch is
      # the LLM's real answer ("no common name exists"), a NULL from an
      # unparseable batch is not an answer at all. The caller's cache keeps
      # only the former.
      llm_parsed               = TRUE,
      stringsAsFactors         = FALSE
    )
  }

  # Split into batches and combine. One message per batch (2026-09-12): the
  # real PtConception 18S run sent 1,151 names in 58 sequential calls with
  # no output at all, which read as a hung workflow.
  n_batches <- ceiling(length(names) / batch_size)
  batches <- vector("list", n_batches)
  for (b in seq_len(n_batches)) {
    idx <- ((b - 1L) * batch_size + 1L):min(b * batch_size, length(names))
    if (isTRUE(verbose)) {
      message(sprintf(
        "scientific_to_common(): LLM batch %d/%d (%d name(s))...",
        b, n_batches, length(idx)
      ))
    }
    batches[[b]] <- .parse_one_batch(names[idx])
  }
  do.call(rbind, batches)
}


# ---- per-name on-disk cache --------------------------------------------------
# One small .rds per (name, backbone_id, location), the same file-per-key
# shape TaxaFlag::review_assignments(cache_dir=) and
# TaxaHabitat::build_habitat_lookup(cache_dir=) use, so
# TaxaTools::list_cache_files()/report_and_clear_cache() manage it. The full
# key is stored inside the file and verified on read, so a hash collision
# costs one re-asked name and can never return another name's answer.

#' @noRd
.common_name_cache_key <- function(name, backbone_id, location) {
  list(
    name        = tolower(trimws(name)),
    backbone_id = if (is.null(backbone_id)) NA_integer_ else as.integer(backbone_id),
    location    = if (is.null(location)) NA_character_ else location
  )
}

#' @noRd
.common_name_cache_path <- function(cache_dir, key) {
  file.path(cache_dir, paste0(rlang::hash(key), "_common_name.rds"))
}

#' @noRd
.read_common_name_cache <- function(cache_dir, key) {
  path <- .common_name_cache_path(cache_dir, key)
  if (!file.exists(path)) return(NULL)
  hit <- tryCatch(readRDS(path), error = function(e) NULL)
  if (is.null(hit) || !identical(hit$key, key) || !is.list(hit$row)) return(NULL)
  hit$row
}

#' @noRd
.write_common_name_cache <- function(cache_dir, key, row) {
  saveRDS(list(key = key, row = row), .common_name_cache_path(cache_dir, key))
  invisible(TRUE)
}


#' Report and clear the scientific_to_common() cache
#'
#' \code{scientific_to_common(cache_dir = )} keeps one small \code{.rds} per
#' looked-up name. This helper reports what the directory holds and deletes
#' it (optionally only files older than \code{older_than_days}), via the
#' shared \code{\link{report_and_clear_cache}} engine -- the same shape as
#' \code{TaxaFetch::taxafetch_clear_cache()} and
#' \code{TaxaFlag::taxaflag_clear_cache()}.
#'
#' @param cache_dir Character. The directory passed to
#'   \code{scientific_to_common(cache_dir = )}.
#' @param older_than_days Numeric or \code{NULL}. Only files older than this
#'   many days are targeted; \code{NULL} (default) targets every file.
#' @param dry_run Logical. If \code{TRUE}, reports without deleting.
#' @return Invisibly, the data frame of targeted files (see
#'   \code{\link{list_cache_files}}).
#' @export
#' @examples
#' \dontrun{
#' taxatools_clear_cache("my_run_common_name_cache", dry_run = TRUE)
#' }
taxatools_clear_cache <- function(cache_dir, older_than_days = NULL, dry_run = FALSE) {
  inv <- list_cache_files(cache_dir, "_common_name\\.rds$")
  report_and_clear_cache(inv, "taxatools_clear_cache", cache_dir,
    older_than_days = older_than_days, dry_run = dry_run
  )
}


# ==============================================================================
# scientific_to_common
# ==============================================================================

#' Convert Scientific Names to Common Names
#'
#' Looks up English common names for a character vector of scientific names.
#' By default queries the GBIF vernacular names database (\code{backbone_id = 11})
#' or ITIS (\code{backbone_id = 3}), falling back to an LLM when a backbone
#' returns no results (\code{use_llm = TRUE}, the default).  Set
#' \code{backbone_id = NULL} to use the LLM for all names without a backbone
#' query.
#'
#' @details
#' Backbone sources return structured, curated common names and are preferred
#' when available.  GBIF filters to vernacular names with \code{language = "eng"};
#' ITIS filters to \code{language = "English"}.  The first name returned becomes
#' \code{common_name}; remaining names become \code{common_name_alternatives}
#' (semicolon-delimited).
#'
#' When \code{backbone_id} is not \code{3} or \code{11} (or is \code{NULL}),
#' only the LLM is used.  A warning is issued for unsupported backbone IDs.
#' When a backbone package is required but not installed, an error is thrown
#' with installation instructions.
#'
#' The \code{location} parameter is passed to the LLM and biases name
#' selection toward regionally appropriate common names (e.g., Pacific vs.
#' Atlantic range variants, locally used vernacular names).  It has no effect
#' on backbone-sourced results.  To apply geographic context to all names,
#' set \code{backbone_id = NULL} so the LLM handles the full lookup.
#'
#' @param scientific_names Character vector of scientific names to look up.
#' @param backbone_id Integer or \code{NULL}.  Backbone for structured lookup:
#'   \code{11} = GBIF (default, uses \pkg{rgbif}), \code{3} = ITIS (uses
#'   \pkg{taxize}).  Other values trigger a warning and fall through to the LLM.
#'   \code{NULL} skips backbone lookup entirely.
#' @param location Character string providing geographic context for the LLM
#'   (e.g., \code{"Southern California Bight"}, \code{"Pacific Northwest, USA"}).
#'   Biases the LLM toward regionally appropriate common names.  Has no effect
#'   on backbone-sourced results.  Default \code{NULL}.
#' @param use_llm Logical.  If \code{TRUE}, taxa with no backbone result are
#'   sent to the LLM in a single batched call.  Default \code{FALSE}: returns
#'   \code{NA} for unresolved taxa without an LLM call.
#' @param llm_fn Function with signature \code{function(prompt, ...) ->
#'   character(1)}.  Required when \code{use_llm = TRUE} or
#'   \code{backbone_id} is unsupported / \code{NULL}.  Default
#'   \code{getOption("TaxaID.llm_fn")}.
#' @param cache_dir Character or \code{NULL} (default, no cache). A
#'   directory holding one small \code{.rds} per looked-up name, keyed on
#'   the name (case/whitespace-insensitive), \code{backbone_id} and
#'   \code{location}. A name found there is served without any backbone or
#'   LLM call; a name resolved this call is written back. A name the LLM was
#'   asked about and answered "no common name" IS cached (that is its
#'   answer); a name from a batch the LLM answered unparseably is NOT (it
#'   will be re-asked), and neither is a backbone miss on a
#'   \code{use_llm = FALSE} call (a later \code{use_llm = TRUE} call must
#'   still be able to ask). Manage it with \code{\link{taxatools_clear_cache}}.
#'   Added 2026-09-12: a real 18S workflow spent 58 silent LLM calls on
#'   1,151 names, then repeated them on every re-run.
#' @param verbose Logical (default \code{TRUE}). Print a one-line summary
#'   (cache / backbone / LLM counts) and one line per LLM batch.
#' @param ... Additional arguments passed to \code{llm_fn}.
#'
#' @return A data frame with one row per element of \code{scientific_names}:
#'   \describe{
#'     \item{\code{scientific_name}}{Input scientific name (character).}
#'     \item{\code{common_name}}{Primary English common name, or \code{NA}.}
#'     \item{\code{common_name_alternatives}}{Semicolon-delimited additional
#'       English common names, or \code{NA}.}
#'     \item{\code{source}}{One of \code{"gbif"}, \code{"itis"}, \code{"llm"},
#'       or \code{"none"}.}
#'     \item{\code{backbone_id}}{Integer backbone ID used, or \code{NA} for LLM
#'       or no-result rows.}
#'   }
#'
#' @seealso \code{\link{common_to_scientific}}, \code{\link{verify_taxon_names}}
#'
#' @examples
#' \dontrun{
#' library(TaxaTools)
#'
#' # GBIF backbone (default)
#' result <- scientific_to_common(
#'   c("Oncorhynchus mykiss", "Salmo salar")
#' )
#' result[, c("scientific_name", "common_name", "source")]
#'
#' # ITIS backbone
#' result2 <- scientific_to_common(
#'   c("Oncorhynchus mykiss", "Salmo salar"),
#'   backbone_id = 3L
#' )
#'
#' # LLM only with geographic context
#' result3 <- scientific_to_common(
#'   c("Eschrichtius robustus", "Oncorhynchus mykiss"),
#'   backbone_id = NULL,
#'   location    = "Southern California Bight, Pacific Ocean"
#' )
#'
#' # Backbone with LLM fallback disabled (return NA when backbone finds nothing)
#' result4 <- scientific_to_common(
#'   c("Oncorhynchus mykiss", "Rare taxon sp."),
#'   use_llm = FALSE
#' )
#' }
#'
#' @export
scientific_to_common <- function(scientific_names,
                                 backbone_id = 11L,
                                 location = NULL,
                                 use_llm = FALSE,
                                 llm_fn = getOption("TaxaID.llm_fn"),
                                 cache_dir = NULL,
                                 verbose = TRUE,
                                 ...) {
  # ---- input validation -------------------------------------------------------
  if (!is.character(scientific_names) || length(scientific_names) == 0L) {
    stop("scientific_names must be a non-empty character vector", call. = FALSE)
  }
  if (!is.null(location) && (!is.character(location) || length(location) != 1L)) {
    stop("location must be a single character string or NULL", call. = FALSE)
  }
  if (!is.null(backbone_id)) {
    backbone_id <- as.integer(backbone_id)
    if (!backbone_id %in% c(3L, 11L)) {
      warning(sprintf(
        "backbone_id %d is not supported for common name lookup (use 3 = ITIS or 11 = GBIF). Falling back to LLM.",
        backbone_id
      ), call. = FALSE)
      backbone_id <- NULL
    }
  }
  if (!is.logical(use_llm) || length(use_llm) != 1L || is.na(use_llm)) {
    stop("use_llm must be TRUE or FALSE", call. = FALSE)
  }
  if (!is.null(cache_dir) && (!is.character(cache_dir) || length(cache_dir) != 1L || is.na(cache_dir))) {
    stop("cache_dir must be a single character string or NULL", call. = FALSE)
  }
  if (!is.logical(verbose) || length(verbose) != 1L || is.na(verbose)) {
    stop("verbose must be TRUE or FALSE", call. = FALSE)
  }
  llm_needed <- is.null(backbone_id) || use_llm
  if (llm_needed && is.null(llm_fn)) {
    stop(
      "No LLM function configured. Load TaxaTools with library(TaxaTools) to ",
      "auto-detect a provider, or supply llm_fn explicitly. ",
      "To use backbone-only lookup without LLM fallback, set use_llm = FALSE.",
      call. = FALSE
    )
  }
  if (!is.null(llm_fn) && !is.function(llm_fn)) {
    stop("llm_fn must be a function", call. = FALSE)
  }

  # ---- initialise output vectors ----------------------------------------------
  n <- length(scientific_names)
  out_cn <- rep(NA_character_, n)
  out_alt <- rep(NA_character_, n)
  out_source <- rep("none", n)
  out_backbone <- rep(NA_integer_, n)
  from_cache <- rep(FALSE, n)
  asked_llm <- rep(FALSE, n)
  llm_parsed <- rep(FALSE, n)

  # ---- cache read -------------------------------------------------------------
  cache_keys <- NULL
  if (!is.null(cache_dir)) {
    if (!dir.exists(cache_dir)) dir.create(cache_dir, recursive = TRUE)
    cache_keys <- lapply(scientific_names, .common_name_cache_key,
      backbone_id = backbone_id, location = location
    )
    for (i in seq_len(n)) {
      hit <- .read_common_name_cache(cache_dir, cache_keys[[i]])
      if (!is.null(hit)) {
        out_cn[[i]] <- hit$common_name
        out_alt[[i]] <- hit$common_name_alternatives
        out_source[[i]] <- hit$source
        out_backbone[[i]] <- hit$backbone_id
        from_cache[[i]] <- TRUE
      }
    }
  }

  # ---- backbone lookup (per-taxon) --------------------------------------------
  if (!is.null(backbone_id)) {
    lookup_fn <- if (backbone_id == 11L) .gbif_common_names else .itis_common_names
    for (i in which(!from_cache)) {
      res <- tryCatch(lookup_fn(scientific_names[[i]]), error = function(e) {
        warning(
          sprintf(
            "Backbone lookup failed for '%s': %s",
            scientific_names[[i]], conditionMessage(e)
          ),
          call. = FALSE
        )
        NULL
      })
      if (!is.null(res)) {
        out_cn[[i]] <- res$primary
        out_alt[[i]] <- res$alternatives
        out_source[[i]] <- if (backbone_id == 11L) "gbif" else "itis"
        out_backbone[[i]] <- backbone_id
      }
    }
  }

  # ---- LLM fallback for unresolved taxa ---------------------------------------
  needs_llm <- out_source == "none" & !from_cache
  llm_idx <- if (use_llm && any(needs_llm) && !is.null(llm_fn)) {
    which(needs_llm)
  } else if (is.null(backbone_id) && !is.null(llm_fn)) {
    # backbone_id = NULL: pure LLM path for every name not served from cache
    which(!from_cache)
  } else {
    integer(0)
  }
  if (isTRUE(verbose)) {
    message(sprintf(
      "scientific_to_common(): %d name(s) -- %d from cache, %d resolved by backbone, %d to the LLM%s.",
      n, sum(from_cache), sum(out_source != "none" & !from_cache), length(llm_idx),
      if (length(llm_idx)) sprintf(" in %d batch(es)", ceiling(length(llm_idx) / 20L)) else ""
    ))
  }
  if (length(llm_idx) > 0L) {
    llm_res <- .llm_common_names(scientific_names[llm_idx], llm_fn,
      location = location, verbose = verbose, ...
    )
    for (j in seq_along(llm_idx)) {
      i <- llm_idx[[j]]
      asked_llm[[i]] <- TRUE
      llm_parsed[[i]] <- isTRUE(llm_res$llm_parsed[[j]])
      if (!is.na(llm_res$common_name[[j]])) {
        out_cn[[i]] <- llm_res$common_name[[j]]
        out_alt[[i]] <- llm_res$common_name_alternatives[[j]]
        out_source[[i]] <- "llm"
      }
    }
  }

  # ---- cache write ------------------------------------------------------------
  # A row is worth keeping when it carries a real answer: resolved by a
  # backbone or the LLM, or asked of the LLM in a batch that parsed (its NA
  # is the answer "no common name"). Never a backbone miss that was not put
  # to the LLM, and never a row from an unparseable batch.
  if (!is.null(cache_dir)) {
    worth_caching <- !from_cache & (out_source != "none" | (asked_llm & llm_parsed))
    for (i in which(worth_caching)) {
      .write_common_name_cache(cache_dir, cache_keys[[i]], list(
        common_name              = out_cn[[i]],
        common_name_alternatives = out_alt[[i]],
        source                   = out_source[[i]],
        backbone_id              = out_backbone[[i]]
      ))
    }
    if (isTRUE(verbose) && any(worth_caching)) {
      message(sprintf("scientific_to_common(): %d name(s) written to the cache at %s.", sum(worth_caching), cache_dir))
    }
  }

  # ---- assemble output --------------------------------------------------------
  data.frame(
    scientific_name          = scientific_names,
    common_name              = out_cn,
    common_name_alternatives = out_alt,
    source                   = out_source,
    backbone_id              = out_backbone,
    stringsAsFactors         = FALSE
  )
}
