#' @keywords internal
"_PACKAGE"

#' TaxaMatch: Store and Standardize Biological Match Data
#'
#' Ingests raw match data from external tools (BLAST, image classifiers,
#' acoustic recognizers) and produces a canonical match object for input to
#' TaxaLikely. Also provides remote/local BLAST search and sequence filtering.
#'
#' @section Sequence input:
#' \itemize{
#'   \item \code{\link{read_sequence_table}} -- ingest DADA2, FASTA, or
#'     DNAStringSet
#'   \item \code{\link{filter_sequences}} -- filter by length and abundance
#' }
#'
#' @section BLAST search:
#' \itemize{
#'   \item \code{\link{blast_sequences}} -- remote NCBI or local BLAST search
#' }
#'
#' @section Standardization:
#' \itemize{
#'   \item \code{\link{standardize_match_data}} -- canonical column names
#'   \item \code{\link{filter_redundant_hypotheses}} -- drop superseded ranks
#'   \item \code{\link{convert_taxonomy_backbone}} -- remap rank columns to a
#'     target backbone (e.g. NCBI -> GBIF); adds \code{taxonomy_backbone} and
#'     \code{taxonomy_collision} diagnostic columns
#' }
#'
#' @section Reporting:
#' \itemize{
#'   \item \code{\link{report_match}} -- generate Methods/Results section
#' }
#'
#' @name TaxaMatch-package
#' @aliases TaxaMatch
NULL
