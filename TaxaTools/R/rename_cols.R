# ==============================================================================
# rename_cols.R
# TaxaTools — Rename data frame columns to a target naming convention
# ==============================================================================

#' Rename Data Frame Columns to a Target Convention
#'
#' Renames columns in a data frame using either a user-supplied explicit map or
#' a set of built-in case-insensitive regex patterns that cover common
#' alternatives to DarwinCore column names. Intended as the first step when
#' aligning supplemental occurrence data to a shared column naming convention
#' before combining sources with \code{stack_occurrences()}.
#'
#' @param input_df A data frame whose columns are to be renamed.
#' @param col_map Named character vector or \code{NULL}. When supplied, each
#'   \strong{name} is an existing column name in \code{input_df} and each
#'   \strong{value} is the desired new name. Both must be \strong{quoted
#'   strings}:
#'   \preformatted{
#'   col_map = c("Latitude"   = "decimalLatitude",
#'               "Longitude"  = "decimalLongitude",
#'               "SurveyDate" = "eventDate")
#'   }
#'   When \code{col_map} is supplied it \strong{replaces} the default pattern
#'   matching entirely — only the mappings you specify are applied. When
#'   \code{NULL} (default), the built-in regex patterns are used instead
#'   (see Details).
#' @param strict Logical. Controls behaviour when a \code{col_map} key is not
#'   found in \code{input_df}.
#'   \itemize{
#'     \item \code{FALSE} (default): warns about unmatched keys and renames
#'       whatever it can. Suitable when \code{rename_cols()} is applied to
#'       frames that may only contain some of the target columns.
#'     \item \code{TRUE}: stops with an error if any \code{col_map} key is
#'       absent from \code{input_df}. Use in scripts where all mappings must succeed.
#'   }
#'   Has no effect when \code{col_map = NULL} (default patterns always
#'   skip non-matching columns silently).
#'
#' @return The input data frame with columns renamed as specified. Column
#'   types, row names, and all other attributes are preserved. Columns not
#'   mentioned in \code{col_map} (or not matched by the default patterns) are
#'   left unchanged.
#'
#' @details
#' \strong{Default pattern matching (when \code{col_map = NULL}):}
#' The following case-insensitive regex patterns are applied. A column is
#' renamed only when its name matches exactly one pattern; ambiguous matches
#' (multiple columns matching the same pattern) are skipped with a warning.
#' \itemize{
#'   \item \code{lat}, \code{latitude} -> \code{decimalLatitude}
#'   \item \code{lon}, \code{long}, \code{longitude} -> \code{decimalLongitude}
#'   \item \code{date}, \code{SurveyDate}, \code{CollectionDate},
#'     \code{EventDate}, \code{DateCollected} -> \code{eventDate}
#'   \item \code{site}, \code{location}, \code{locality} -> \code{verbatimLocality}
#' }
#' Matching is case-insensitive so \code{Lat}, \code{LAT}, and \code{lat} all
#' match. If the target column already exists in \code{input_df} (e.g.
#' \code{input_df} already has \code{decimalLatitude}), that pattern is skipped.
#'
#' \strong{User col_map replaces defaults:} When \code{col_map} is supplied,
#' none of the default patterns are applied.
#'
#' \strong{Quoted strings required:} Both names and values in a user-supplied
#' \code{col_map} must be quoted. Unquoted bare names cause an
#' \code{"object not found"} error before the function is called.
#'
#' \strong{Scientific name columns:} No default pattern maps to
#' \code{scientificName} or \code{taxon_name}. Column names such as
#' \code{Species} are ambiguous (they may hold the epithet only, not the full
#' binomial) and must be mapped explicitly via \code{col_map} after confirming
#' column content.
#'
#' @section The col_map pattern across TaxaID:
#' The \code{col_map} concept is used consistently across the TaxaID ecosystem
#' wherever column names need to be reconciled:
#' \itemize{
#'   \item \strong{TaxaTools}: \code{rename_cols()} — general-purpose column
#'     rename with DarwinCore defaults.
#'   \item \strong{TaxaMatch}: \code{standardize_match_data()} — map BLAST/DADA2
#'     output column names to the canonical match object format.
#'   \item \strong{TaxaFetch}: \code{stack_occurrences()} — align column names
#'     across occurrence data sources before row-binding.
#' }
#' In all cases, \code{col_map} is a named character vector where names are
#' existing column names and values are desired target names.
#'
#' @seealso \code{\link{create_taxon_names}}
#'
#' @export
#'
#' @examples
#' df <- data.frame(Latitude  = 34.1,
#'                  Longitude = -119.1,
#'                  date      = "2022-01-01",
#'                  species   = "Clevelandia ios")
#'
#' # Default pattern matching
#' rename_cols(df)
#'
#' # Explicit col_map — replaces default patterns entirely
#' rename_cols(df,
#'             col_map = c("Latitude"  = "decimalLatitude",
#'                         "Longitude" = "decimalLongitude",
#'                         "date"      = "eventDate",
#'                         "species"   = "scientificName"))
#'
#' \dontrun{
#' # Pipe-friendly
#' df_std <- my_survey |>
#'   rename_cols(col_map = c("Lat" = "decimalLatitude",
#'                           "Lon" = "decimalLongitude"))
#'
#' # strict = TRUE stops if any key is missing
#' df_std <- rename_cols(my_survey,
#'                       col_map = c("Lat" = "decimalLatitude"),
#'                       strict  = TRUE)
#' }

rename_cols <- function(input_df,
                        col_map = NULL,
                        strict  = FALSE) {

  # --- Input validation -------------------------------------------------------
  if (!is.data.frame(input_df)) stop("`input_df` must be a data frame.")
  if (!is.logical(strict) || length(strict) != 1L || is.na(strict)) {
    stop("`strict` must be a single logical value (TRUE or FALSE).")
  }

  # --- Branch: user col_map vs default pattern matching ----------------------
  if (!is.null(col_map)) {

    # Validate col_map type — catches unquoted bare-name mistakes
    if (!is.character(col_map) || is.null(names(col_map)) ||
        any(!nzchar(names(col_map)))) {
      stop(
        "`col_map` must be a named character vector with quoted strings on ",
        "both sides.\n",
        "  Correct:   col_map = c(\"Latitude\" = \"decimalLatitude\")\n",
        "  Incorrect: col_map = c(Latitude = decimalLatitude)  ",
        "# unquoted values cause 'object not found' errors"
      )
    }

    # Check keys exist in input_df
    missing_keys <- setdiff(names(col_map), names(input_df))
    if (length(missing_keys) > 0L) {
      msg <- paste0(
        "rename_cols: col_map key(s) not found in `input_df`: ",
        paste(missing_keys, collapse = ", "), "\n",
        "  Column names are case-sensitive.\n",
        "  Available columns: ", paste(names(input_df), collapse = ", ")
      )
      if (strict) stop(msg) else warning(msg, call. = FALSE)
    }

    # Apply renames
    to_rename            <- intersect(names(col_map), names(input_df))
    idx                  <- match(to_rename, names(input_df))
    names(input_df)[idx] <- col_map[to_rename]

  } else {

    # Default regex pattern → DarwinCore target map.
    # Applied case-insensitively against column names when col_map = NULL.
    # Each pattern must match at most one column; ambiguous matches are skipped.
    dwc_patterns <- c(
      "^lat(itude)?$"                                       = "decimalLatitude",
      "^lon(gitude)?$|^long$"                               = "decimalLongitude",
      "^(survey|collection|event)?date$|^date(collected)?$" = "eventDate",
      "^(site|location|locality)$"                          = "verbatimLocality"
    )

    # Default: case-insensitive regex pattern matching
    renamed_targets <- character(0)

    for (pattern in names(dwc_patterns)) {
      target  <- dwc_patterns[[pattern]]
      matches <- which(grepl(pattern, names(input_df), ignore.case = TRUE))

      if (length(matches) == 0L)        next  # no match — skip silently
      if (target %in% names(input_df))  next  # already correctly named
      if (target %in% renamed_targets)  next  # already claimed this session

      if (length(matches) > 1L) {
        warning(sprintf(
          "rename_cols: pattern for '%s' matched multiple columns (%s) -- skipping.",
          target, paste(names(input_df)[matches], collapse = ", ")
        ), call. = FALSE)
        next
      }

      names(input_df)[matches] <- target
      renamed_targets          <- c(renamed_targets, target)
    }
  }

  input_df
}
