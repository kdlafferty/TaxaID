#' Aggregate occurrence-model shares to genus/family level
#'
#' Builds the lookup `posterior_consensus(group_priors = ...)` uses to compute
#' a genuinely group-level `consensus_prior` -- the SUM of `theta_mean`
#' across every locally modelled member of a genus or family, not just the
#' few candidates one observation's evidence happened to surface.
#'
#' @section Why sum, and why this needs a separate pass:
#' `theta_mean` (`TaxaExpect::prepare_model_dataframe()`'s
#' `n_species / n_total_at_site`) is a **compositional share of local
#' records** -- one record belongs to exactly one taxon, so shares are
#' mutually exclusive across taxa. That makes the group's true share the
#' *exact* sum of its members' shares, by finite additivity, with no
#' independence assumption required -- unlike a noisy-OR combination
#' (`1 - prod(1 - p_i)`), which assumes independent Bernoulli presence
#' events per taxon and is the wrong model for a compositional share.
#'
#' `posterior_consensus()` only ever sees the candidate rows hypothesized for
#' ONE observation, so it cannot compute a true group sum on its own -- a
#' genus with 13 locally modelled species might have only 2-3 of them appear
#' as candidates for any single BLAST hit. This function does the
#' aggregation once, up front, over the full `taxaexpect_priors` table, so
#' `posterior_consensus()` only needs a cheap lookup per observation.
#'
#' @section Why `"species"` is in the default `rank_cols`:
#' `posterior_consensus()`'s `group_priors` lookup is keyed on
#' `(lca$rank, lca$taxon)`, and most real consensus calls resolve at
#' \strong{species} rank -- but a species has no "group" to sum over in the
#' usual genus/family sense, it IS the row. Without a `rank == "species"`
#' entry, every species-level `consensus_taxon` finds nothing in
#' `group_priors`, and `consensus_has_occurrence_record` reads `FALSE` (not
#' `NA` -- `group_priors` was genuinely supplied, just missing this rank) for
#' the vast majority of real observations, purely from this gap -- confirmed
#' on real production data (504 of 616 real Mugu observations misread
#' "unprecedented"). `rank_cols` therefore defaults to
#' `c("species", "genus", "family")`; when `taxonomy_map` has no explicit
#' `"species"` column, one is auto-derived as `taxon_col`'s own values
#' (identity: a species' "group sum" is just its own `theta_col`, `n_members`
#' = 1). Supply an explicit `"species"` column in `taxonomy_map` to override
#' this (e.g. a backbone-resolved name differing from `taxon_col`), or omit
#' `"species"` from `rank_cols` to disable it entirely.
#'
#' @param taxaexpect_priors Data frame. The full local occurrence-prior
#'   table (e.g. `TaxaExpect::generate_full_priors()`'s output, or the
#'   `taxaexpect_priors` object already used elsewhere in this ecosystem's
#'   workflows). Must contain `taxon_col` and `theta_col`.
#' @param taxonomy_map Data frame supplying genus/family for each taxon in
#'   `taxaexpect_priors` (e.g. `occurrences_clean`, which typically has real
#'   `genus`/`family` columns even when `taxaexpect_priors` itself does not).
#'   Must contain `taxon_col` and every column named in `rank_cols`.
#' @param taxon_col Character. Shared join key between the two inputs
#'   (default `"taxon_name"`).
#' @param theta_col Character. Column in `taxaexpect_priors` holding the
#'   occurrence-model share (default `"theta_mean"`).
#' @param rank_cols Character vector. Which columns in `taxonomy_map` to
#'   aggregate by (default `c("species", "genus", "family")`). See
#'   "Why `"species"` is in the default `rank_cols`" below -- `"species"` is
#'   auto-derived as `taxon_col`'s own identity when `taxonomy_map` has no
#'   explicit `"species"` column.
#'
#' @return A data frame with one row per (rank, taxon) group actually
#'   present in the data: `rank` (the `rank_cols` value, e.g. `"genus"`),
#'   `taxon` (the group's name at that rank), `theta_sum` (sum of `theta_col`
#'   across every member with a non-NA value, capped at 1 as a defensive
#'   guard against model-fit overshoot -- see `posterior_consensus()`'s
#'   `consensus_prior` docs), `n_members` (count of members contributing to
#'   the sum, i.e. locally modelled members only -- a taxon with no
#'   occurrence record does not contribute and is not counted). A group with
#'   zero locally modelled members is simply absent, not a zero row.
#'
#' @seealso [posterior_consensus()]
#'
#' @examples
#' priors <- data.frame(
#'   taxon_name = c("Aa one", "Aa two", "Bb one"),
#'   theta_mean = c(0.02, 0.05, 0.10)
#' )
#' taxonomy <- data.frame(
#'   taxon_name = c("Aa one", "Aa two", "Bb one"),
#'   genus      = c("Aa", "Aa", "Bb"),
#'   family     = c("Fam1", "Fam1", "Fam2")
#' )
#' compute_group_priors(priors, taxonomy)
#'
#' @importFrom stats aggregate
#' @importFrom dplyr bind_rows
#' @export
compute_group_priors <- function(taxaexpect_priors,
                                  taxonomy_map,
                                  taxon_col = "taxon_name",
                                  theta_col = "theta_mean",
                                  rank_cols = c("species", "genus", "family")) {

  if (!is.data.frame(taxaexpect_priors))
    cli::cli_abort("{.arg taxaexpect_priors} must be a data frame.")
  if (!is.data.frame(taxonomy_map))
    cli::cli_abort("{.arg taxonomy_map} must be a data frame.")
  for (col in c(taxon_col, theta_col)) {
    if (!col %in% names(taxaexpect_priors))
      cli::cli_abort("Column {.field {col}} not found in {.arg taxaexpect_priors}.")
  }
  if (!taxon_col %in% names(taxonomy_map))
    cli::cli_abort("Column {.field {taxon_col}} not found in {.arg taxonomy_map}.")

  # "species" is a group of one: auto-derive it as taxon_col's own identity
  # when taxonomy_map has no explicit "species" column, rather than requiring
  # every caller to add that column by hand (see @section above).
  if ("species" %in% rank_cols && !"species" %in% names(taxonomy_map)) {
    taxonomy_map$species <- taxonomy_map[[taxon_col]]
  }

  missing_rank_cols <- setdiff(rank_cols, names(taxonomy_map))
  if (length(missing_rank_cols) > 0)
    cli::cli_abort(
      "{.arg rank_cols} not found in {.arg taxonomy_map}: {.field {missing_rank_cols}}."
    )

  priors_slim <- taxaexpect_priors[, c(taxon_col, theta_col), drop = FALSE]
  names(priors_slim) <- c("taxon_name_", "theta_")
  tax_slim <- taxonomy_map[, c(taxon_col, rank_cols), drop = FALSE]
  names(tax_slim)[1] <- "taxon_name_"

  merged <- merge(priors_slim, tax_slim, by = "taxon_name_", all.x = TRUE)
  # Only taxa with an actual occurrence-model value contribute -- a taxon
  # absent from theta_col has no local record and cannot support a group.
  merged <- merged[!is.na(merged$theta_), , drop = FALSE]

  out_list <- lapply(rank_cols, function(rc) {
    vals <- merged[[rc]]
    ok   <- !is.na(vals) & nzchar(as.character(vals))
    if (!any(ok)) {
      return(data.frame(rank = character(0), taxon = character(0),
                        theta_sum = numeric(0), n_members = integer(0)))
    }
    theta_ok <- merged$theta_[ok]
    taxon_ok <- vals[ok]
    theta_sum <- stats::aggregate(theta_ok, by = list(taxon = taxon_ok), FUN = sum)
    n_members <- stats::aggregate(theta_ok, by = list(taxon = taxon_ok), FUN = length)
    data.frame(
      rank      = rc,
      taxon     = theta_sum$taxon,
      theta_sum = pmin(theta_sum$x, 1),   # defensive cap; see @return
      n_members = n_members$x,
      stringsAsFactors = FALSE
    )
  })

  dplyr::bind_rows(out_list)
}
