# suggest_unreferenced_species.R
# TaxaAssign package
#
# suggest_unreferenced_species() lives in TaxaLikely: it is a
# reference-coverage-auditing function ("which species are missing from my
# reference database"), the same job TaxaLikely::audit_barcode_coverage()
# does, so it belongs next to the function it's an alternative to, not in
# this posterior-computation package. This file is only a thin, deprecated
# forwarding wrapper for callers who reach for it here.

#' Suggest Unreferenced Species Using an LLM (deprecated -- moved to TaxaLikely)
#'
#' @description
#' **Deprecated.** This function has moved to [TaxaLikely::suggest_unreferenced_species()] --
#' see that function's documentation for the full parameter list, algorithm,
#' and return-value description. This wrapper forwards every argument
#' unchanged and exists only so that a caller who hasn't yet updated to
#' `TaxaLikely::suggest_unreferenced_species()` still gets a working call
#' (with a deprecation warning) instead of a hard failure.
#'
#' @param ... Forwarded unchanged to [TaxaLikely::suggest_unreferenced_species()].
#'
#' @return See [TaxaLikely::suggest_unreferenced_species()].
#' @seealso [TaxaLikely::suggest_unreferenced_species()], [assign_taxa_llm()]
#' @export
suggest_unreferenced_species <- function(...) {
  .Deprecated("TaxaLikely::suggest_unreferenced_species")
  if (!requireNamespace("TaxaLikely", quietly = TRUE)) {
    cli::cli_abort(c(
      "suggest_unreferenced_species() has moved to TaxaLikely.",
      "i" = "Install TaxaLikely and call {.fn TaxaLikely::suggest_unreferenced_species} directly."
    ))
  }
  TaxaLikely::suggest_unreferenced_species(...)
}
