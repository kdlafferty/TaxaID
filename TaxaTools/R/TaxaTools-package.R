#' @keywords internal
"_PACKAGE"

#' TaxaTools: Taxonomic Name Standardization and LLM Utilities
#'
#' Provides helper functions for cleaning, verifying, and standardizing
#' taxonomic names across multiple backbones (GBIF, NCBI, WoRMS, Catalogue of
#' Life). Also provides LLM provider functions for calling Anthropic, OpenAI,
#' Gemini, and Ollama APIs, and utilities for assembling pipeline reports.
#'
#' @section Name cleaning and verification:
#' \itemize{
#'   \item \code{\link{clean_taxon_names}} -- remove formatting artifacts
#'   \item \code{\link{verify_taxon_names}} -- check names against backbone APIs
#'   \item \code{\link{create_taxon_names}} -- derive canonical taxon label at
#'     finest available rank
#'   \item \code{\link{rename_cols}} -- rename columns to DarwinCore conventions
#' }
#'
#' @section LLM providers:
#' \itemize{
#'   \item \code{\link{call_anthropic_api}} -- Claude (Anthropic)
#'   \item \code{\link{call_gemini_api}} -- Gemini (Google)
#'   \item \code{\link{call_openai_api}} -- GPT (OpenAI)
#'   \item \code{\link{call_ollama_api}} -- Local models (Ollama)
#' }
#'
#' @section Report assembly:
#' \itemize{
#'   \item \code{\link{new_report_section}} -- create a report section object
#'   \item \code{\link{assemble_report}} -- combine sections into unified report
#' }
#'
#' @name TaxaTools-package
#' @aliases TaxaTools
NULL
