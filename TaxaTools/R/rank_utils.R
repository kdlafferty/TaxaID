#' Standard Linnaean Rank Order (Coarse to Fine)
#'
#' The 7 major Linnaean ranks used as the default taxonomy hierarchy across
#' the TaxaID ecosystem.  All rank-aware functions accept a `rank_system`
#' parameter that defaults to intersecting data columns with this vector.
#'
#' @format A character vector of length 7.
#' @examples
#' standard_ranks
#' # "kingdom" "phylum" "class" "order" "family" "genus" "species"
#' @export
standard_ranks <- c("kingdom", "phylum", "class", "order",
                     "family", "genus", "species")


#' Extended Rank Order Including Intermediate Ranks (Coarse to Fine)
#'
#' An extended taxonomy hierarchy including sub- and super-ranks commonly
#' found in NCBI, GBIF, and WoRMS.  Used by
#' \code{TaxaMatch::standardize_match_data()} for column detection from
#' diverse reference databases.
#'
#' @format A character vector of length 21.
#' @examples
#' head(extended_ranks)
#' @export
extended_ranks <- c(
  "domain", "kingdom", "subkingdom", "phylum", "subphylum",
  "superclass", "class", "subclass", "superorder", "order", "suborder",
  "superfamily", "family", "subfamily", "tribe",
  "genus", "subgenus", "species", "subspecies", "variety", "form"
)


#' Detect Rank Columns Present in a Data Frame
#'
#' Intersects column names in \code{df} with a reference rank list to find
#' which taxonomy rank columns are present.  When \code{rank_system} is
#' \code{NULL}, auto-detects from \code{\link{standard_ranks}}.  Issues a
#' warning when auto-detection finds nothing and falls back to
#' \code{c("family", "genus", "species")}.
#'
#' @param input_df A data frame whose column names may include taxonomy ranks.
#' @param rank_system Character vector of rank names (coarse to fine), or
#'   \code{NULL} to auto-detect from \code{standard_ranks}.
#' @param warn Logical (default \code{TRUE}).  If \code{TRUE}, emits a
#'   warning when auto-detection finds no standard rank columns and falls
#'   back to the minimum set.
#'
#' @return A character vector of rank names present in \code{df}, ordered
#'   coarse to fine.  If no ranks are detected even after fallback, returns
#'   \code{character(0)}.
#'
#' @examples
#' input_df <- data.frame(family = "Fundulidae", genus = "Fundulus",
#'                        species = "Fundulus parvipinnis", score = 99)
#' detect_ranks(input_df)
#' # "family" "genus" "species"
#'
#' @export
detect_ranks <- function(input_df, rank_system = NULL, warn = TRUE) {
  if (!is.data.frame(input_df)) {
    stop("detect_ranks: input_df must be a data frame")
  }

  col_names <- tolower(names(input_df))

  if (!is.null(rank_system)) {
    return(rank_system[tolower(rank_system) %in% col_names])
  }

  detected <- standard_ranks[standard_ranks %in% col_names]

  if (length(detected) == 0L) {
    fallback <- c("family", "genus", "species")
    detected <- fallback[fallback %in% col_names]
    if (warn) {
      if (length(detected) > 0L) {
        warning(
          "detect_ranks: no standard rank columns detected in data; ",
          "falling back to: ", paste(detected, collapse = ", "), "."
        )
      } else {
        warning("detect_ranks: no rank columns found at all.")
      }
    }
  }

  detected
}
