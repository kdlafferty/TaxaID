#' @keywords internal
"_PACKAGE"

#' TaxaLikely: Convert Match Scores to Likelihoods
#'
#' Trains a hierarchical Bayesian model on reference-vs-reference match scores
#' and applies it to convert per-observation scores into likelihoods for
#' taxonomic assignment. Supports three hypothesis types: known species (H1),
#' unreferenced species (H2), and unreferenced genus (H3).
#'
#' @section Reference acquisition:
#' \itemize{
#'   \item \code{\link{fetch_ncbi_reference_sequences}} -- download from NCBI
#'   \item \code{\link{read_reference_fasta}} -- read local FASTA + taxonomy
#' }
#'
#' @section Model training:
#' \itemize{
#'   \item \code{\link{build_sequence_matrix}} -- pairwise distance matrix
#'   \item \code{\link{train_likelihood_model}} -- fit hierarchical model
#'     (reference-quality screening happens upstream, in TaxaMatch -- see
#'     \code{\link{train_likelihood_model}}'s own documentation)
#' }
#'
#' @section Inference:
#' \itemize{
#'   \item \code{\link{evaluate_likelihoods}} -- apply model to match data
#'   \item \code{\link{filter_top_hypotheses}} -- keep finest-rank candidates
#' }
#'
#' @section Unreferenced taxa:
#' \itemize{
#'   \item \code{\link{unreferenced_candidates}} -- generate generic H2/H3
#'     placeholder rows
#'   \item \code{\link{expand_unreferenced_hypotheses}} -- model their
#'     likelihoods and expand into named species (moved from TaxaAssign,
#'     Session 150)
#' }
#'
#' @section Reference quality:
#' \itemize{
#'   \item \code{\link{audit_barcode_coverage}} -- check completeness
#' }
#'
#' @section Reporting:
#' \itemize{
#'   \item \code{\link{report_likelihood}} -- generate Methods/Results section
#' }
#'
#' @name TaxaLikely-package
#' @aliases TaxaLikely
NULL
