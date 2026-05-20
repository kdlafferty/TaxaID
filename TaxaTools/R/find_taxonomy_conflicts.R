#' Find Taxonomic Conflicts in a Taxonomy Data Frame
#'
#' Detects higher-rank inconsistencies: cases where the same taxon name at
#' one rank is assigned to different parent taxa at a coarser rank across
#' rows.
#'
#' These conflicts arise when merging taxonomy from multiple sources (GBIF +
#' NCBI + WoRMS) or when supplementing verified taxonomy with manual
#' corrections.  Adapted from the GITA pipeline's
#' `f_find_taxonomic_inconsistencies()`, vectorised for performance.
#'
#' @param df Data frame with taxonomy columns (e.g. `family`, `genus`,
#'   `species`).
#' @param rank_system Character vector of rank column names, coarse to fine.
#'   If `NULL` (default), auto-detected via [detect_ranks()].
#'
#' @return A data frame of conflicts with columns:
#'   \describe{
#'     \item{`taxon_name`}{The taxon name that has conflicting higher-rank
#'       assignments.}
#'     \item{`taxon_rank`}{The rank of the conflicting taxon (e.g.
#'       `"genus"`).}
#'     \item{`parent_rank`}{The coarser rank where disagreement was found
#'       (e.g. `"family"`).}
#'     \item{`parent_values`}{Semicolon-separated string of the distinct
#'       parent values found (e.g. `"Cottidae; Scorpaenidae"`).}
#'     \item{`n_values`}{Number of distinct parent values.}
#'   }
#'   Returns an empty data frame (0 rows, same columns) when no conflicts
#'   are found.
#'
#' @examples
#' df <- data.frame(
#'   family  = c("Cottidae", "Scorpaenidae", "Cottidae"),
#'   genus   = c("Cottus",   "Cottus",        "Enophrys"),
#'   species = c("Cottus asper", "Cottus rhotheus", "Enophrys bison"),
#'   stringsAsFactors = FALSE
#' )
#' find_taxonomy_conflicts(df)
#' # Returns: Cottus has conflicting family values (Cottidae; Scorpaenidae)
#'
#' @seealso [detect_ranks()], [change_backbone()]
#' @export
find_taxonomy_conflicts <- function(df, rank_system = NULL) {
  if (!is.data.frame(df))
    stop("find_taxonomy_conflicts: df must be a data frame")

  if (is.null(rank_system))
    rank_system <- detect_ranks(df, warn = TRUE)

  if (length(rank_system) < 2L) {
    message("find_taxonomy_conflicts: fewer than 2 rank columns detected; no conflicts possible.")
    return(.empty_conflict_df())
  }

  # Only use ranks that are actually columns in df

  rank_system <- rank_system[rank_system %in% names(df)]
  if (length(rank_system) < 2L) {
    message("find_taxonomy_conflicts: fewer than 2 rank columns present in df.")
    return(.empty_conflict_df())
  }

  conflicts <- vector("list", length(rank_system) - 1L)
  k <- 0L

  # For each rank (fine to coarse), check parent consistency at every coarser rank

  for (ri in seq(2L, length(rank_system))) {
    child_rank <- rank_system[ri]
    child_vals <- as.character(df[[child_rank]])

    for (pi in seq_len(ri - 1L)) {
      parent_rank <- rank_system[pi]
      parent_vals <- as.character(df[[parent_rank]])

      # Skip rows with NA in either column
      ok <- !is.na(child_vals) & !is.na(parent_vals) &
            nchar(trimws(child_vals)) > 0L & nchar(trimws(parent_vals)) > 0L

      if (!any(ok)) next

      # For each unique child name, count distinct parent values
      child_sub  <- child_vals[ok]
      parent_sub <- parent_vals[ok]

      uniq_children <- unique(child_sub)

      for (ch in uniq_children) {
        parents <- unique(parent_sub[child_sub == ch])
        if (length(parents) > 1L) {
          k <- k + 1L
          conflicts[[k]] <- data.frame(
            taxon_name  = ch,
            taxon_rank  = child_rank,
            parent_rank = parent_rank,
            parent_values = paste(sort(parents), collapse = "; "),
            n_values    = length(parents),
            stringsAsFactors = FALSE
          )
        }
      }
    }
  }

  if (k == 0L)
    return(.empty_conflict_df())

  do.call(rbind, conflicts[seq_len(k)])
}


#' @noRd
.empty_conflict_df <- function() {
  data.frame(
    taxon_name    = character(0),
    taxon_rank    = character(0),
    parent_rank   = character(0),
    parent_values = character(0),
    n_values      = integer(0),
    stringsAsFactors = FALSE
  )
}
