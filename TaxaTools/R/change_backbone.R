# Bare column names used in dplyr NSE contexts below.
# classification_ranks, classification_path: created by verify_taxon_names(); read in mutate().
# ranks, paths: intermediate list columns created and consumed within the pipeline.
# tax_list: intermediate list column passed to unnest_wider().
utils::globalVariables(c(
  "classification_ranks", "classification_path",
  "ranks", "paths", "tax_list"
))

#' Translate Taxon Names Between Taxonomic Backbones
#'
#' Post-processes the output of \code{\link{verify_taxon_names}} to (1) rename
#' the source and translated name columns with meaningful backbone labels, and
#' (2) parse the pipe-delimited \code{classification_path} and
#' \code{classification_ranks} columns into a wide-format taxonomy table
#' (one column per rank: kingdom, phylum, class, etc.).
#'
#' This function does \strong{not} call any API. The backbone translation is
#' performed by the upstream \code{verify_taxon_names()} call -- this function
#' only reshapes and labels the result. The backbone ID passed to
#' \code{verify_taxon_names()} determines which backbone the names are translated
#' \emph{into}; \code{old_backbone_label} and \code{new_backbone_label} are
#' purely descriptive column labels in the output.
#'
#' \strong{Typical two-step usage:}
#' \preformatted{
#' # Step 1: verify_taxon_names() does the translation (backbone_id = 11 is GBIF).
#' # Step 2: change_backbone() labels and reshapes the result.
#' verify_taxon_names(ncbi_names, backbone_id = 11) |>
#'   change_backbone(
#'     input_col          = "user_supplied_name",
#'     old_backbone_label = "NCBI",
#'     new_backbone_label = "GBIF"
#'   )
#'
#' # To translate back (GBIF -> NCBI), call verify_taxon_names() again with the
#' # NCBI backbone ID (4), then pipe to change_backbone() with swapped labels.
#' }
#'
#' The \code{score} and \code{verified} columns from \code{verify_taxon_names}
#' are retained in the output so you can inspect translation quality before
#' using the result downstream.
#'
#' @param df A dataframe returned by \code{\link{verify_taxon_names}}, containing
#'   at minimum: \code{user_supplied_name}, \code{matched_name},
#'   \code{classification_path}, and \code{classification_ranks}.
#' @param input_col Character. The name of the column in \code{df} holding the
#'   original (source backbone) names. Typically \code{"user_supplied_name"}.
#' @param old_backbone_label Character. The label to assign to the source-name
#'   column in the output (e.g., \code{"NCBI"} or \code{"GBIF"}).
#'   Default is \code{"source_name"}.
#' @param new_backbone_label Character. The label to assign to the translated-name
#'   column in the output (e.g., \code{"GBIF"} or \code{"NCBI"}).
#'   Default is \code{"translated_name"}.
#'
#' @return A dataframe with:
#' \describe{
#'   \item{\code{<old_backbone_label>}}{Original names (renamed from \code{input_col}).}
#'   \item{\code{<new_backbone_label>}}{Translated names (renamed from \code{matched_name}).}
#'   \item{\code{score}}{Match confidence score from \code{verify_taxon_names}.
#'     Review rows with low scores before using the translation downstream.}
#'   \item{\code{verified}}{Logical API-success flag from \code{verify_taxon_names}.}
#'   \item{kingdom, phylum, ...}{Wide-format rank columns parsed from
#'     \code{classification_path}. Column names are the rank labels returned by
#'     the backbone (typically lowercase Linnaean ranks). Ranks absent for a
#'     given row are \code{NA}.}
#' }
#' The intermediate columns \code{classification_path} and
#' \code{classification_ranks} are dropped after parsing.
#'
#' @seealso \code{\link{verify_taxon_names}} which must be called upstream to
#'   produce the input dataframe for this function.
#'
#' @importFrom dplyr rename mutate select
#' @importFrom tidyr unnest_wider
#' @importFrom purrr map2 map
#' @importFrom rlang sym :=
#'
#' @export
#'
#' @examples
#' \dontrun{
#' # Translate NCBI names to GBIF taxonomy
#' ncbi_names <- c("Homo sapiens", "Mus musculus")
#'
#' verify_taxon_names(ncbi_names, backbone_id = 11) |>  # 11 = GBIF
#'   change_backbone(
#'     input_col          = "user_supplied_name",
#'     old_backbone_label = "NCBI",
#'     new_backbone_label = "GBIF"
#'   )
#' }
change_backbone <- function(df,
                             input_col,
                             old_backbone_label = "source_name",
                             new_backbone_label = "translated_name") {

  # --- Input validation ---
  if (!is.data.frame(df)) stop("`df` must be a data frame.")
  if (!is.character(input_col) || length(input_col) != 1) {
    stop("`input_col` must be a single column name string.")
  }
  if (!is.character(old_backbone_label) || length(old_backbone_label) != 1) {
    stop("`old_backbone_label` must be a single string.")
  }
  if (!is.character(new_backbone_label) || length(new_backbone_label) != 1) {
    stop("`new_backbone_label` must be a single string.")
  }

  if (nrow(df) == 0L) {
    warning("change_backbone: input has 0 rows. Returning empty data frame.")
    df[[old_backbone_label]] <- character(0)
    df[[new_backbone_label]] <- character(0)
    return(df)
  }

  required_cols <- c(input_col, "matched_name", "classification_ranks", "classification_path")
  missing_cols  <- setdiff(required_cols, names(df))
  if (length(missing_cols) > 0) {
    stop(
      "Required column(s) missing from `df`: ", paste(missing_cols, collapse = ", "),
      "\n`df` should be the direct output of verify_taxon_names()."
    )
  }

  # --- Rename source and translated name columns ---
  # !!sym() on both sides avoids bare-name R CMD check warnings.
  df |>
    dplyr::rename(
      !!rlang::sym(old_backbone_label) := !!rlang::sym(input_col),
      !!rlang::sym(new_backbone_label) := !!rlang::sym("matched_name")
    ) |>

    # --- Parse pipe-delimited rank and path strings into paired lists ---
    dplyr::mutate(
      ranks = strsplit(classification_ranks, "\\|"),
      paths = strsplit(classification_path,  "\\|")
    ) |>

    # --- Build a named character vector per row: name = rank, value = taxon ---
    dplyr::mutate(
      tax_list = purrr::map2(ranks, paths, function(r, p) {
        # Guard against NA or zero-length splits (e.g., unverified names)
        # strsplit(NA, ...) returns list(NA_character_), not list(character(0))
        if (length(r) == 0 || length(p) == 0 ||
            (length(r) == 1L && is.na(r[1L])) ||
            (length(p) == 1L && is.na(p[1L])) ||
            all(is.na(r)) || all(is.na(p))) return(NULL)

        keep   <- !is.na(r) & nchar(r) > 0 & !is.na(p) & nchar(p) > 0
        named  <- stats::setNames(p[keep], r[keep])

        # Drop "unranked" entries -- backbone sometimes inserts these
        named[names(named) != "unranked"]
      })
    ) |>

    # --- Drop intermediate columns before widening ---
    dplyr::select(-ranks, -paths, -classification_ranks, -classification_path) |>

    # --- Expand the named-vector list column into one column per rank ---
    # Ranks absent for a given row become NA automatically.
    tidyr::unnest_wider(tax_list)
}
