#' Extract and Clean Taxon Names from a Character Vector
#'
#' Cleans a character vector of taxon names by normalising whitespace,
#' removing \code{NA}s, removing names that do not begin with a capital letter
#' (e.g., codes, placeholders, artefacts), converting underscore-separated
#' binomials to space-separated ones (e.g. \code{"Corallina_officinalis"} ->
#' \code{"Corallina officinalis"}, as produced by Jonah Ventures and SILVA
#' pipelines), trimming abbreviated second words (sp., spp., etc.) to
#' genus-only, and stripping bracket artefacts. Returns a clean character
#' vector suitable for API calls or downstream filtering.
#'
#' This function operates on a plain character vector, not a dataframe.
#' Common patterns for dataframe workflows:
#' \preformatted{
#' # Pattern 1 -- extract a unique vector for API calls:
#' name_vec <- df |> dplyr::pull(taxon_name) |> clean_taxon_names()
#'
#' # Pattern 2 -- clean the column in place:
#' df <- df |> dplyr::mutate(taxon_name = clean_taxon_names(taxon_name))
#' }
#'
#' @param name_vec A character vector (or factor) of taxon names.
#' @param remove_abbr A character vector of second-word tokens that flag the
#'   name as genus-only (the abbreviation is dropped). Defaults to a standard
#'   list of common abbreviations and placeholder terms. Pass a custom vector
#'   to extend or replace the default list.
#'
#' @return A character vector the same length as \code{name_vec}. Names that
#'   do not start with a capital letter, are \code{NA}, or consist only of an
#'   abbreviation are set to \code{NA}.
#'
#' @seealso \code{\link{create_taxon_names}} to generate the \code{taxon_name}
#'   column that is typically passed to this function.
#'
#' @importFrom stringr str_squish str_split_fixed
#'
#' @export
#'
#' @examples
#' nms <- c("Homo sapiens", "mus musculus", NA, "sp.", "Canis lupus sp.",
#'          "Homo sapiens", "[Bacillus] subtilis", "Unknown")
#' clean_taxon_names(nms)
#' # Returns: c("Homo sapiens", NA, NA, NA, "Canis lupus",
#' #            "Homo sapiens", "Bacillus subtilis", NA)
clean_taxon_names <- function(name_vec, remove_abbr = NULL) {

  # --- Input validation ---
  if (is.factor(name_vec)) name_vec <- as.character(name_vec)
  if (!is.character(name_vec)) stop("`name_vec` must be a character vector.")

  if (is.null(remove_abbr)) {
    remove_abbr <- c(
      "sp", "sp.", "spp", "spp.", "spec", "species",
      "unknown", "unk", "unk.", "n.sp", "n.sp.",
      "", "?", "x", "aff.", "cf.", "clone",
      "partial", "isolate", "voucher"
    )
  }

  # --- Normalise whitespace; coerce any "NA" string to real NA ---
  x <- stringr::str_squish(as.character(name_vec))
  x[x %in% c("NA", "<NA>")] <- NA_character_

  # --- Strip bracket artefacts BEFORE the capital-letter filter ---
  # e.g. "[Bacillus] subtilis" -> "Bacillus subtilis" so it passes the
  # capital-letter check below. Re-squish after removal.
  x <- gsub("\\[|\\]|[()]", "", x, perl = TRUE)
  x <- stringr::str_squish(x)

  # --- Set non-conforming names to NA (preserves vector length) ---
  # Names that are NA, empty, or do not begin with a capital letter become NA.
  bad <- is.na(x) | !grepl("^[[:upper:]]", x)
  x[bad] <- NA_character_

  # --- Replace underscore-as-space in binomial names --------------------------
  # Some pipelines (e.g. Jonah Ventures, SILVA) encode spaces as underscores:
  # "Corallina_officinalis" -> "Corallina officinalis"
  # Rule: exactly one underscore, no spaces, uppercase-start genus, lowercase-
  # start epithet. Does NOT affect clade codes (MAST-4), OTU IDs (OTU_001),
  # or multi-underscore strings.
  binomial_under <- !is.na(x) &
    grepl("^[A-Z][A-Za-z.-]+_[a-z][A-Za-z.-]*$", x, perl = TRUE)
  x[binomial_under] <- gsub("_", " ", x[binomial_under], fixed = TRUE)

  # --- Split into at most three tokens: genus | epithet | remainder ---
  # str_split_fixed always returns exactly n columns, so no ragged results.
  # NA inputs produce NA in all columns, which ifelse propagates correctly.
  mat     <- stringr::str_split_fixed(x, " ", n = 3)
  genus   <- mat[, 1]
  epithet <- mat[, 2]
  # mat[, 3] (remainder / author string) is discarded intentionally;
  # it is already excluded by limiting the split to 3 tokens and using
  # only columns 1 and 2. No further regex trimming is required.

  # --- Reduce to genus-only if the epithet is an abbreviation or absent ---
  # Single-character epithets are abbreviations (e.g., "P." for a species),
  # not valid species names; require at least 2 characters.
  keep_epithet <- nchar(epithet) >= 2 & !(epithet %in% remove_abbr)
  cleaned      <- ifelse(keep_epithet, paste0(genus, " ", epithet), genus)

  # Names that were bad get NA (genus from split of NA is "NA" string; fix that)
  cleaned[bad] <- NA_character_

  cleaned
}
