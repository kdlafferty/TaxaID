#' @keywords internal
"_PACKAGE"

#' TaxaAssign: Bayesian Taxonomic Assignment
#'
#' Estimates the posterior probability that a biological sample (sequence,
#' image, sound) was produced by a particular taxon, using Bayes' theorem.
#' Combines per-taxon likelihoods with spatial priors to compute posteriors,
#' then determines consensus taxonomy at the appropriate rank.
#'
#' @section Posterior computation:
#' \itemize{
#'   \item \code{\link{compute_posterior}} -- Bayes' theorem with MC uncertainty
#'   \item \code{\link{assign_taxa_llm}} -- LLM-shortcut (priors + likelihoods)
#'   \item \code{\link{join_priors}} -- merge TaxaExpect priors with likelihoods
#' }
#'
#' @section Consensus:
#' \itemize{
#'   \item \code{\link{posterior_consensus}} -- LCA from posterior probabilities
#'   \item \code{\link{score_consensus}} -- conventional score-based consensus
#'   \item \code{\link{update_prior_from_consensus}} -- empirical Bayes
#'     refinement
#' }
#'
#' @section Unreferenced species:
#' Two separate mechanisms, one per workflow -- not used together. Full
#' Bayesian: \code{TaxaLikely::audit_barcode_coverage()} feeds
#' \code{TaxaLikely::expand_unreferenced_hypotheses()} (models likelihoods for
#' named unreferenced taxa). LLM-shortcut:
#' \code{TaxaLikely::suggest_unreferenced_species()} (a fast, LLM-first
#' alternative to \code{audit_barcode_coverage()}; moved here from this
#' package in 2026-09-08) feeds \code{\link{assign_taxa_llm}}'s own
#' \code{unreferenced_taxa} parameter directly.
#' \itemize{
#'   \item \code{\link{suggest_unreferenced_species}} -- deprecated forwarding
#'     wrapper; call \code{TaxaLikely::suggest_unreferenced_species()} directly
#'   \item \code{TaxaLikely::expand_unreferenced_hypotheses()} -- models
#'     likelihoods for named unreferenced taxa (lives in TaxaLikely, next to
#'     \code{TaxaLikely::unreferenced_candidates()})
#' }
#'
#' @section High-level wrappers:
#' \itemize{
#'   \item \code{\link{run_bayesian_pipeline}} -- full Bayesian workflow
#'   \item \code{\link{run_llm_pipeline}} -- LLM-shortcut workflow
#' }
#'
#' @section Reporting:
#' \itemize{
#'   \item \code{\link{generate_report}} -- full publication-ready report
#'   \item \code{\link{report_assign}} -- lightweight section for assembly
#' }
#'
#' @name TaxaAssign-package
#' @aliases TaxaAssign
NULL
