#' Remove Flagged Reference Sequences from a Match Object
#'
#' Filters a match data frame to remove rows corresponding to reference
#' sequences flagged by \code{\link{flag_reference_errors}}. This produces a
#' cleaned match object suitable for downstream use in TaxaAssign (both
#' Bayesian and LLM workflows).
#'
#' Only sequences flagged as \code{"likely_mislabeled"} are removed by default.
#' Sequences flagged as \code{"unverified_singleton_high_match"} are ambiguous
#' (may be correctly labeled singletons) and are retained unless
#' \code{remove_unverified_singletons = TRUE}.
#'
#' Accession version suffixes (e.g. \code{".1"}, \code{".2"}) are stripped
#' before matching, so \code{flag_reference_errors()} output (which uses
#' version-free IDs from \code{build_reference_matrix()}) matches correctly
#' against \code{match_df$accession} values that may include versions.
#'
#' @param match_df Data frame. A standardized match object (from
#'   \code{\link[TaxaMatch]{standardize_match_data}}) containing an
#'   \code{accession} column.
#' @param reference_errors Data frame. Output of
#'   \code{\link{flag_reference_errors}}, with columns \code{id_x} and
#'   \code{error_type}.
#' @param remove_unverified_singletons Logical (default \code{FALSE}). If
#'   \code{TRUE}, also removes \code{"unverified_singleton_high_match"}
#'   sequences in addition to \code{"likely_mislabeled"}.
#'
#' @return The input \code{match_df} with flagged rows removed. Unchanged if
#'   no flagged accessions are found.
#'
#' @seealso [flag_reference_errors()], [train_likelihood_model()]
#'
#' @examples
#' \dontrun{
#' ref_matrix <- build_reference_matrix(reference_df,
#'                                      rank_system = c("family", "genus", "species"))
#' errors <- flag_reference_errors(ref_matrix)
#' match_obj <- remove_flagged_references(match_obj, errors)
#' saveRDS(match_obj, "match_obj.rds")
#' }
#'
#' @export
remove_flagged_references <- function(match_df,
                                      reference_errors,
                                      remove_unverified_singletons = FALSE) {

  if (!is.data.frame(match_df))
    stop("match_df must be a data frame.", call. = FALSE)
  if (!is.data.frame(reference_errors))
    stop("reference_errors must be a data frame.", call. = FALSE)

  needed <- c("id_x", "error_type")
  missing_cols <- setdiff(needed, names(reference_errors))
  if (length(missing_cols) > 0L)
    stop(sprintf(
      "reference_errors is missing required columns: %s",
      paste(missing_cols, collapse = ", ")
    ), call. = FALSE)

  if (!"accession" %in% names(match_df)) {
    warning(
      "match_df has no 'accession' column -- cannot match against flagged ",
      "reference IDs. Returning match_df unchanged.",
      call. = FALSE
    )
    return(match_df)
  }

  # Determine which error types to remove

  types_to_remove <- "likely_mislabeled"
  if (isTRUE(remove_unverified_singletons))
    types_to_remove <- c(types_to_remove, "unverified_singleton_high_match")

  bad_ids <- reference_errors$id_x[reference_errors$error_type %in% types_to_remove]

  if (length(bad_ids) == 0L) {
    message("No flagged references to remove.")
    return(match_df)
  }

  # Strip version suffixes from accessions for matching
  acc_clean <- sub("\\.[0-9]+$", "", match_df$accession)
  flagged_mask <- acc_clean %in% bad_ids

  n_rows_removed <- sum(flagged_mask)
  n_accessions <- length(unique(acc_clean[flagged_mask]))

  if (n_rows_removed == 0L) {
    message("No flagged accessions found in match_df.")
    return(match_df)
  }

  result <- match_df[!flagged_mask, , drop = FALSE]

  message(sprintf(
    "Removed %d row(s) (%d accession(s)) flagged as %s.",
    n_rows_removed, n_accessions,
    paste(types_to_remove, collapse = " or ")
  ))

  result
}
