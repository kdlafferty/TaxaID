#' Extract and Clean Taxon Names from a Character Vector
#'
#' Cleans a character vector of taxon names by normalising whitespace,
#' removing \code{NA}s, removing names that do not begin with a capital letter
#' (e.g., codes, placeholders, artefacts), converting underscore-separated
#' binomials to space-separated ones (e.g. \code{"Corallina_officinalis"} ->
#' \code{"Corallina officinalis"}, as produced by Jonah Ventures and SILVA
#' pipelines), trimming abbreviated second words (sp., spp., etc.) to
#' genus-only, stripping bracket artefacts, and stripping a single known
#' leading breeding/ploidy-manipulation modifier word (e.g.
#' \code{"androgenetic Carassius auratus"} -> \code{"Carassius auratus"}).
#' Returns a clean character vector suitable for API calls or downstream
#' filtering.
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
#' @param strip_modifiers A character vector of known leading modifier words
#'   (case-insensitive, matched against the FIRST whitespace-delimited token
#'   only, and only ever removed once per name -- never a repeated strip).
#'   Defaults to a curated list of real breeding/ploidy-manipulation terms
#'   found on real GenBank hybrid-cross records (\code{"androgenetic"},
#'   \code{"gynogenetic"}, \code{"autodiploid"}, \code{"autotriploid"},
#'   \code{"autotetraploid"}, \code{"allodiploid"}, \code{"allotriploid"},
#'   \code{"allotetraploid"}, \code{"diploid"}, \code{"triploid"},
#'   \code{"tetraploid"}, \code{"polyploid"}). Deliberately does NOT include
#'   uncertainty-hedge words (\code{"possible"}, \code{"putative"},
#'   \code{"probable"}, \code{"tentative"}, \code{"presumed"}, etc.) or
#'   \code{"hybrid"}/\code{"unidentified"} themselves -- those genuinely
#'   change what the name means (a hedge should keep failing the capital-
#'   letter filter below, not get silently rescued into a confident
#'   binomial; \code{"hybrid X x Y"} with no named first parent has no real
#'   maternal-parent identity to recover). Pass a custom vector to extend or
#'   replace the default list; \code{character(0)} disables this step
#'   entirely (restores this function's pre-2026-08-11 behavior).
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
clean_taxon_names <- function(name_vec, remove_abbr = NULL, strip_modifiers = NULL) {

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

  if (is.null(strip_modifiers)) {
    strip_modifiers <- c(
      "androgenetic", "gynogenetic", "autodiploid", "autotriploid",
      "autotetraploid", "allodiploid", "allotriploid", "allotetraploid",
      "diploid", "triploid", "tetraploid", "polyploid"
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

  # --- Strip a single leading breeding/ploidy-manipulation modifier word,
  # ALSO before the capital-letter filter (found live, 2026-08-11, on real
  # GenBank hybrid-cross records: "androgenetic Carassius auratus red var.
  # x Megalobrama amblycephala" etc.) -- these terms describe a real,
  # confirmed genetic/breeding state, not uncertainty, so removing them is
  # safe in the same sense bracket-stripping is: it reveals the genuinely
  # intended name underneath, rather than rescuing a name that SHOULD stay
  # rejected. Matched case-insensitively against the FIRST token only, and
  # only ever stripped once (not a repeated run) -- deliberately narrow, to
  # avoid ever consuming a second, unrelated leading word (e.g. a genuinely
  # unidentified/unnamed first parent in a hybrid cross) and silently
  # treating the wrong taxon as intended.
  if (length(strip_modifiers) > 0L) {
    modifier_pattern <- paste0("^(", paste(strip_modifiers, collapse = "|"), ")\\s+")
    x <- sub(modifier_pattern, "", x, ignore.case = TRUE, perl = TRUE)
  }

  # --- Set non-conforming names to NA (preserves vector length) ---
  # Names that are NA, empty, or do not begin with a capital letter become NA.
  bad <- is.na(x) | !grepl("^[[:upper:]]", x)
  x[bad] <- NA_character_

  # --- Replace underscore-as-space in binomial names --------------------------
  # Some pipelines (e.g. Jonah Ventures, SILVA) encode spaces as underscores:
  # "Corallina_officinalis" => "Corallina officinalis"
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
