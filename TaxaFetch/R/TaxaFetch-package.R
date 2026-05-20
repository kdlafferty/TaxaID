#' @keywords internal
"_PACKAGE"

#' TaxaFetch: Fetch and Prepare Taxonomic Occurrence Data
#'
#' Acquires occurrence records from GBIF, DataONE, BioTIME, and published
#' literature (PDF extraction), then combines them into a standardized format
#' for downstream analysis. Outputs are data frames with DarwinCore-convention
#' columns including coordinates, timestamps, and bibliographic citations.
#'
#' @section Data acquisition:
#' \itemize{
#'   \item \code{\link{fetch_gbif_occurrences}} -- download GBIF records
#'   \item \code{\link{read_biotime_study}} -- read BioTIME studies
#'   \item \code{\link{fetch_dataone_occurrences}} -- DataONE records
#'   \item \code{\link{search_literature}} -- find relevant papers via OpenAlex
#' }
#'
#' @section PDF extraction:
#' \itemize{
#'   \item \code{\link{screen_pdf_structure}} -- characterize PDF tables
#'   \item \code{\link{build_pdf_extract_prompt}} -- build LLM extraction prompt
#'   \item \code{\link{parse_pdf_extract_response}} -- parse LLM extraction output
#' }
#'
#' @section Combining sources:
#' \itemize{
#'   \item \code{\link{stack_occurrences}} -- row-bind and add point_id
#'   \item \code{\link{filter_gbif_quality}} -- spatial quality filtering
#' }
#'
#' @section Reporting:
#' \itemize{
#'   \item \code{\link{report_fetch}} -- generate Methods/Results section
#' }
#'
#' @name TaxaFetch-package
#' @aliases TaxaFetch
NULL
