#' Test Whether Strings Are Plausible Species Binomials
#'
#' Returns TRUE for strings that are structurally plausible species binomials
#' matching the `"Genus epithet"` pattern and not
#' matching common placeholder patterns (`sp.`, `cf.`, `aff.`, `uncultured`,
#' `environmental`, `metagenom`).
#'
#' Useful for filtering NCBI taxonomy results and occurrence records to
#' described, named species only.
#'
#' @param x Character vector of taxon name strings.
#' @return Logical vector, same length as `x`.
#'
#' @examples
#' is_plausible_binomial(c("Cottus asper", "Cottus sp.", "uncultured bacterium"))
#' # TRUE, FALSE, FALSE
#'
#' @export
is_plausible_binomial <- function(x) {
  grepl("^[A-Z][a-z]+ [a-z]", x) &
    !grepl(
      "\\bsp\\.?\\s*$|\\bsp\\b|\\bcf\\.\\s|\\baff\\.\\s|uncultured|environmental|metagenom",
      x, ignore.case = TRUE, perl = TRUE
    )
}
