#' Test Whether Strings Are Valid Species Binomials
#'
#' Returns `TRUE` for strings matching the `"Genus epithet"` pattern and not
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
#' is_valid_species_name(c("Cottus asper", "Cottus sp.", "uncultured bacterium"))
#' # TRUE, FALSE, FALSE
#'
#' @export
is_valid_species_name <- function(x) {
  grepl("^[A-Z][a-z]+ [a-z]", x) &
    !grepl(
      "\\bsp\\.?\\s*$|\\bsp\\b|\\bcf\\.\\s|\\baff\\.\\s|uncultured|environmental|metagenom",
      x, ignore.case = TRUE, perl = TRUE
    )
}
