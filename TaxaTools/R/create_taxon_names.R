#' Create Most Specific Taxon Name Column
#'
#' Takes a dataframe with separate taxonomic rank columns and adds two new
#' columns: \code{taxon_name} (the value from the most specific non-NA rank)
#' and \code{taxon_name_rank} (the name of that rank, in lowercase). Column
#' matching is case-insensitive, so rank columns named "Kingdom" or "KINGDOM"
#' match the same as "kingdom".
#'
#' If all rank columns are \code{NA} for a row, both output columns are
#' \code{NA} silently.
#'
#' @param df A data frame containing taxonomic rank columns.
#' @param rank_system A character vector of column names (any case) listing
#'   taxonomic ranks from broadest to most specific, e.g.
#'   \code{c("kingdom", "phylum", "class", "order", "family", "genus", "species")}.
#'   The function walks this vector from right to left and returns the first
#'   non-empty value.
#'
#' @return The input data frame with two columns appended:
#' \describe{
#'   \item{taxon_name}{The most specific non-NA rank value for each row.}
#'   \item{taxon_name_rank}{The rank label (lowercase) corresponding to
#'     \code{taxon_name}. \code{NA} when all ranks are \code{NA}.}
#' }
#'
#' @seealso \code{\link{clean_taxon_names}} to extract a clean, deduplicated
#'   vector of names from the resulting dataframe for downstream API calls.
#'
#' @importFrom dplyr mutate across all_of coalesce na_if
#'
#' @export
#'
#' @examples
#' df <- data.frame(
#'   kingdom = "Animalia",
#'   genus   = "Homo",
#'   species = NA_character_
#' )
#' create_taxon_names(df, c("kingdom", "genus", "species"))
#' # taxon_name = "Homo", taxon_name_rank = "genus"
create_taxon_names <- function(df, rank_system) {

  # --- Input validation ---
  if (!is.data.frame(df)) stop("`df` must be a data frame.")
  if (!is.character(rank_system) || length(rank_system) == 0) {
    stop("`rank_system` must be a non-empty character vector of column names.")
  }
  if (nrow(df) == 0L) {
    df$taxon_name      <- character(0)
    df$taxon_name_rank <- character(0)
    return(df)
  }

  # --- Case-insensitive column matching ---
  rank_cols_lower <- tolower(rank_system)
  df_names_lower  <- tolower(names(df))

  # Check for ambiguous column names after lowercasing
  dup_lower <- df_names_lower[duplicated(df_names_lower) & df_names_lower %in% rank_cols_lower]
  if (length(dup_lower) > 0L) {
    stop(
      "Ambiguous column names after case-insensitive matching: ",
      paste(unique(dup_lower), collapse = ", "),
      ". Rename columns so that rank names are unique when lowercased."
    )
  }

  missing_cols <- setdiff(rank_cols_lower, df_names_lower)
  if (length(missing_cols) > 0) {
    stop(
      "Column(s) not found in `df`: ", paste(missing_cols, collapse = ", "),
      "\nCheck spelling and confirm `rank_system` matches your dataframe column names."
    )
  }

  # Map lowercase rank requests back to the actual (possibly mixed-case) column names
  actual_cols <- names(df)[match(rank_cols_lower, df_names_lower)]

  # --- Coerce rank columns to character, treating "" as NA ---
  df_clean <- df |>
    dplyr::mutate(dplyr::across(
      dplyr::all_of(actual_cols),
      ~ dplyr::na_if(as.character(.), "")
    ))

  # --- Walk from most specific (right) to broadest (left) ---
  # coalesce() returns the first non-NA value across a list of vectors,
  # so reversing the rank order means "most specific wins".
  check_order <- rev(actual_cols)

  name_vecs <- lapply(check_order, function(col) df_clean[[col]])
  rank_vecs <- lapply(check_order, function(col) {
    ifelse(!is.na(df_clean[[col]]), tolower(col), NA_character_)
  })

  final_name <- do.call(dplyr::coalesce, name_vecs)
  final_rank <- do.call(dplyr::coalesce, rank_vecs)

  df |> dplyr::mutate(taxon_name = final_name, taxon_name_rank = final_rank)
}
