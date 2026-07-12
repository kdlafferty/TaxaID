#' Expand unreferenced hypotheses from genus/family level to named species
#'
#' @description
#' **Deprecated.** Moved to [TaxaLikely::expand_unreferenced_hypotheses()] (Session 150).
#' TaxaLikely already owns unreferenced-*candidate* generation
#' ([TaxaLikely::unreferenced_candidates()]); this keeps both halves of
#' unreferenced-taxon handling -- generating the candidates and modeling
#' their likelihoods -- in one package. This function is a thin forwarding
#' wrapper kept for backward compatibility; it has no logic of its own.
#'
#' @param likelihood_df See [TaxaLikely::expand_unreferenced_hypotheses()].
#' @param unreferenced_df See [TaxaLikely::expand_unreferenced_hypotheses()].
#'
#' @return See [TaxaLikely::expand_unreferenced_hypotheses()].
#'
#' @seealso [TaxaLikely::expand_unreferenced_hypotheses()]
#'
#' @export
expand_unreferenced_hypotheses <- function(likelihood_df, unreferenced_df) {
  .Deprecated(
    msg = paste0(
      "'expand_unreferenced_hypotheses' has moved to TaxaLikely. ",
      "Use TaxaLikely::expand_unreferenced_hypotheses() instead; ",
      "forwarding for backward compatibility."
    )
  )
  TaxaLikely::expand_unreferenced_hypotheses(likelihood_df, unreferenced_df)
}
