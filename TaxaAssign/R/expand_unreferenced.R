utils::globalVariables(c("hypothesis_type"))

#' Expand unreferenced hypotheses from genus/family level to named species
#'
#' After [TaxaLikely::evaluate_likelihoods()], the `"unreferenced_species"`
#' hypothesis is labelled at genus level (e.g. `taxon_name = "Fundulus"`,
#' `taxon_name_rank = "genus"`) and the `"unreferenced_genus"` hypothesis at
#' family level.  This function replaces those generic rows with one named row
#' per plausible unreferenced species, enabling [compute_posterior()] to join
#' them directly to species-level priors from TaxaExpect.
#'
#' ## Expansion rules (applied per `observation_id`)
#' \enumerate{
#'   \item The `"unreferenced_species"` (H2) row carries a genus label.
#'     Unreferenced species whose genus matches that label receive the H2
#'     `likelihood_point_est` / `likelihood_mean` / `likelihood_sd`.
#'   \item The `"unreferenced_genus"` (H3) row carries a family label.
#'     Unreferenced species whose family matches that label \emph{and} whose
#'     genus differs from the H2 genus receive the H3 likelihood values.
#'   \item If no named species are found for the H2 genus (none are locally
#'     plausible), the generic H2 row is dropped.  Likewise for H3.
#' }
#'
#' ## H2 and H3 likelihoods
#' The H2 likelihood is independently modelled by TaxaLikely from sister-species
#' matches (cross-species matches within the same genus in the reference
#' database).  The H3 likelihood is modelled from sister-genus matches.
#' These are not borrowed from H1 rows -- they reflect the expected score
#' distribution for an unreferenced congener or confamilial, respectively.
#' All named species produced by expansion share the same H2 (or H3) likelihood;
#' TaxaExpect priors differentiate among them geographically.
#'
#' ## Building `unreferenced_df`
#' \enumerate{
#'   \item Start with TaxaExpect's plausible species list for the site
#'     (includes `genus` and `family` columns from TaxaFetch).
#'   \item Subtract species already in TaxaMatch -- these have reference
#'     sequences by definition.
#'   \item Call [TaxaLikely::audit_barcode_coverage()] with
#'     `species_list` = the TaxaExpect species and `match_df` = the TaxaMatch
#'     reference species.  Species with NCBI barcode count = 0 are truly
#'     unreferenced.
#'   \item Filter TaxaExpect rows to those confirmed as unreferenced and
#'     select `species`, `genus`, `family`.
#' }
#'
#' ## Pipeline order
#' Run \emph{before} [TaxaLikely::apply_coverage_constraints()]: coverage
#' constraints must see the named rows, not the generic genus/family rows.
#'
#' @param likelihood_df Data frame -- the `$likelihoods` component returned by
#'   [TaxaLikely::evaluate_likelihoods()].  Must contain `observation_id`,
#'   `taxon_name`, `taxon_name_rank`, `hypothesis_type`,
#'   `likelihood_point_est`, `likelihood_mean`, `likelihood_sd`.
#' @param unreferenced_df Data frame of unreferenced but plausible species.
#'   Must contain columns `species` (binomial name), `genus`, and `family`.
#'   Built from TaxaExpect rows confirmed as unreferenced by
#'   [TaxaLikely::audit_barcode_coverage()].
#'
#' @return `likelihood_df` with generic `"unreferenced_species"` and
#'   `"unreferenced_genus"` rows replaced by named species rows where matches
#'   are found.  Column set is unchanged; new rows carry `NA` for any extra
#'   columns in the input (e.g. `constraint_applied`).
#'
#' @seealso [compute_posterior()], [TaxaLikely::evaluate_likelihoods()],
#'   [TaxaLikely::audit_barcode_coverage()],
#'   [TaxaLikely::apply_coverage_constraints()]
#'
#' @examples
#' \dontrun{
#' expanded <- expand_unreferenced_hypotheses(
#'   result$likelihoods,
#'   unreferenced_df = unreferenced_species_result
#' )
#' }
#'
#' @importFrom dplyr bind_rows filter
#' @export
expand_unreferenced_hypotheses <- function(likelihood_df, unreferenced_df) {

  # ---- Input validation -------------------------------------------------------
  if (!is.data.frame(likelihood_df))
    stop("likelihood_df must be a data frame")
  needed_lik <- c("observation_id", "taxon_name", "taxon_name_rank",
                  "hypothesis_type", "likelihood_point_est",
                  "likelihood_mean", "likelihood_sd")
  miss_lik <- setdiff(needed_lik, names(likelihood_df))
  if (length(miss_lik) > 0L)
    stop(sprintf("likelihood_df is missing required columns: %s",
                 paste(miss_lik, collapse = ", ")))

  if (!is.data.frame(unreferenced_df))
    stop("unreferenced_df must be a data frame")
  # Unreferenced species expansion is inherently genus/family-level:
  # species names are matched to genera, and family is used for family-level
  # unreferenced taxon insertion. These three columns are always required.
  needed_unref <- c("species", "genus", "family")
  miss_unref <- setdiff(needed_unref, tolower(names(unreferenced_df)))
  if (length(miss_unref) > 0L)
    stop(sprintf(
      "unreferenced_df is missing required columns: %s. These are needed because unreferenced species expansion matches species to genera and uses family for higher-rank insertion.",
      paste(miss_unref, collapse = ", ")
    ))

  if (nrow(unreferenced_df) == 0L) {
    message(paste0(
      "unreferenced_df is empty -- dropping all generic unreferenced_species ",
      "and unreferenced_genus rows (no plausible species to expand into)."
    ))
    return(dplyr::filter(
      likelihood_df,
      !hypothesis_type %in% c("unreferenced_species", "unreferenced_genus")
    ))
  }

  # ---- Normalise case for matching --------------------------------------------
  unref           <- unreferenced_df
  unref$genus_lc  <- tolower(trimws(unref$genus))
  unref$family_lc <- tolower(trimws(unref$family))

  # ---- Split by hypothesis type -----------------------------------------------
  h1_rows <- dplyr::filter(likelihood_df, hypothesis_type == "specific_candidate")
  h2_rows <- dplyr::filter(likelihood_df, hypothesis_type == "unreferenced_species")
  h3_rows <- dplyr::filter(likelihood_df, hypothesis_type == "unreferenced_genus")

  observation_ids   <- unique(likelihood_df$observation_id)
  n_h2_species <- 0L
  n_h3_species <- 0L
  result_list  <- vector("list", length(observation_ids))

  for (i in seq_along(observation_ids)) {
    sid <- observation_ids[i]
    h2  <- h2_rows[h2_rows$observation_id == sid, , drop = FALSE]
    h3  <- h3_rows[h3_rows$observation_id == sid, , drop = FALSE]

    new_rows <- vector("list", 2L)

    # ---- H2: unreferenced species in the best-match genus -------------------
    if (nrow(h2) > 0L) {
      h2_genus_lc <- tolower(trimws(h2$taxon_name[1L]))
      genus_sp    <- unref[unref$genus_lc == h2_genus_lc, , drop = FALSE]

      if (nrow(genus_sp) > 0L) {
        new_rows[[1L]] <- data.frame(
          observation_id            = sid,
          taxon_name           = genus_sp$species,
          taxon_name_rank      = "species",
          hypothesis_type      = "unreferenced_species",
          likelihood_point_est = h2$likelihood_point_est[1L],
          likelihood_mean      = h2$likelihood_mean[1L],
          likelihood_sd        = h2$likelihood_sd[1L],
          stringsAsFactors     = FALSE
        )
        n_h2_species <- n_h2_species + nrow(genus_sp)
      }
      # else: no locally-plausible unreferenced species — drop the generic H2 row
    }

    # ---- H3: unreferenced species in the best-match family, other genera ----
    if (nrow(h3) > 0L) {
      h3_family_lc <- tolower(trimws(h3$taxon_name[1L]))
      h2_genus_lc  <- if (nrow(h2) > 0L) tolower(trimws(h2$taxon_name[1L])) else character(0L)

      family_sp <- unref[
        unref$family_lc == h3_family_lc & !unref$genus_lc %in% h2_genus_lc,
        , drop = FALSE
      ]

      if (nrow(family_sp) > 0L) {
        new_rows[[2L]] <- data.frame(
          observation_id            = sid,
          taxon_name           = family_sp$species,
          taxon_name_rank      = "species",
          hypothesis_type      = "unreferenced_genus",
          likelihood_point_est = h3$likelihood_point_est[1L],
          likelihood_mean      = h3$likelihood_mean[1L],
          likelihood_sd        = h3$likelihood_sd[1L],
          stringsAsFactors     = FALSE
        )
        n_h3_species <- n_h3_species + nrow(family_sp)
      }
      # else: no locally-plausible unreferenced species — drop the generic H3 row
    }

    result_list[[i]] <- dplyr::bind_rows(new_rows)
  }

  expanded <- dplyr::bind_rows(result_list)
  exp_types <- if (nrow(expanded) > 0L) expanded$hypothesis_type else character(0L)
  n_h2_generic_dropped <- nrow(h2_rows) -
    sum(vapply(result_list, function(x) nrow(x) > 0L && any(x$hypothesis_type == "unreferenced_species"), logical(1L)))
  n_h3_generic_dropped <- nrow(h3_rows) -
    sum(vapply(result_list, function(x) nrow(x) > 0L && any(x$hypothesis_type == "unreferenced_genus"), logical(1L)))

  message(sprintf(
    paste0("expand_unreferenced_hypotheses: H2 -> %d named species rows ",
           "(%d generic dropped); H3 -> %d named species rows (%d generic dropped)."),
    n_h2_species, n_h3_generic_dropped, n_h3_species, n_h3_generic_dropped
  ))

  dplyr::bind_rows(h1_rows, expanded)
}
