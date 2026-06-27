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
#'     Species-level suppression: an unreferenced species in the H2 genus is
#'     suppressed only if that exact species is already a `specific_candidate`
#'     for this observation.  Other unreferenced congeners (e.g. F. parvipinnis
#'     when F. lima is H1) are expanded normally and receive the H2
#'     `score_likelihood` / `score_likelihood_mean` / `score_likelihood_sd`.
#'     Exception: when an H1 `specific_candidate` row is genus-rank
#'     (`taxon_name_rank == "genus"`), the entire genus is suppressed -- the
#'     genus is already represented with its own calibrated score.
#'   \item The `"unreferenced_genus"` (H3) row carries a family label.
#'     Unreferenced species whose family matches that label, whose genus
#'     differs from the H2 genus, \emph{and} that are not already a
#'     species-level H1 `specific_candidate` (or whose genus is covered by a
#'     genus-rank H1), receive the H3 likelihood values.
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
#'   `score_likelihood`, `score_likelihood_mean`, `score_likelihood_sd`.
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
                  "hypothesis_type", "score_likelihood",
                  "score_likelihood_mean", "score_likelihood_sd")
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

  n_h2_covered     <- 0L   # individual species suppressed at H2 (already H1 or genus-rank H1)
  n_h2_obs_covered <- 0L   # H2 observations suppressed entirely (genus-rank H1, or all species already H1)
  n_h3_covered     <- 0L   # individual species suppressed at H3

  for (i in seq_along(observation_ids)) {
    sid <- observation_ids[i]
    h2  <- h2_rows[h2_rows$observation_id == sid, , drop = FALSE]
    h3  <- h3_rows[h3_rows$observation_id == sid, , drop = FALSE]

    new_rows <- vector("list", 2L)

    # Per-observation H1 coverage sets.
    # Species-level suppression: an unreferenced species is suppressed only if
    # that exact species is already a specific_candidate for this observation.
    # Exception: when H1 carries a genus-rank hit (taxon_name_rank == "genus"),
    # the whole genus is suppressed -- a genus-rank specific_candidate already
    # represents the full genus with its own calibrated likelihood.
    h1_for_sid <- h1_rows[h1_rows$observation_id == sid, , drop = FALSE]
    h1_genus_rank_lc <- unique(tolower(trimws(
      h1_for_sid$taxon_name[h1_for_sid$taxon_name_rank == "genus"]
    )))
    h1_species_lc <- unique(tolower(trimws(
      h1_for_sid$taxon_name[h1_for_sid$taxon_name_rank != "genus"]
    )))

    # ---- H2: unreferenced species in the best-match genus -------------------
    if (nrow(h2) > 0L) {
      h2_genus_lc <- tolower(trimws(h2$taxon_name[1L]))

      if (h2_genus_lc %in% h1_genus_rank_lc) {
        # Genus already covered by a genus-rank specific_candidate -- drop all.
        genus_sp_all <- unref[unref$genus_lc == h2_genus_lc, , drop = FALSE]
        n_h2_covered     <- n_h2_covered     + max(nrow(genus_sp_all), 1L)
        n_h2_obs_covered <- n_h2_obs_covered + 1L
      } else {
        genus_sp <- unref[unref$genus_lc == h2_genus_lc, , drop = FALSE]
        if (nrow(genus_sp) > 0L) {
          # Species-level suppression: only drop species already H1 for this observation.
          already_h1 <- tolower(trimws(genus_sp$species)) %in% h1_species_lc
          n_h2_covered <- n_h2_covered + sum(already_h1)
          genus_sp_keep <- genus_sp[!already_h1, , drop = FALSE]
          if (nrow(genus_sp_keep) > 0L) {
            new_rows[[1L]] <- data.frame(
              observation_id        = sid,
              taxon_name            = genus_sp_keep$species,
              taxon_name_rank       = "species",
              hypothesis_type       = "unreferenced_species",
              score_likelihood      = h2$score_likelihood[1L],
              score_likelihood_mean = h2$score_likelihood_mean[1L],
              score_likelihood_sd   = h2$score_likelihood_sd[1L],
              stringsAsFactors      = FALSE
            )
            n_h2_species <- n_h2_species + nrow(genus_sp_keep)
          } else {
            # All unreferenced species in genus already H1 -- no expansion for this obs.
            n_h2_obs_covered <- n_h2_obs_covered + 1L
          }
        }
        # else: no locally-plausible unreferenced species -- drop the generic H2 row
      }
    }

    # ---- H3: unreferenced species in the best-match family, other genera ----
    if (nrow(h3) > 0L) {
      h3_family_lc <- tolower(trimws(h3$taxon_name[1L]))
      h2_genus_lc  <- if (nrow(h2) > 0L) tolower(trimws(h2$taxon_name[1L])) else character(0L)

      # Exclude: H2 genus (handled above), species already H1, genera covered
      # by genus-rank H1 rows.
      family_sp <- unref[
        unref$family_lc == h3_family_lc &
        !unref$genus_lc %in% h2_genus_lc &
        !tolower(trimws(unref$species)) %in% h1_species_lc &
        !unref$genus_lc %in% h1_genus_rank_lc,
        , drop = FALSE
      ]

      n_h3_covered <- n_h3_covered + sum(
        unref$family_lc == h3_family_lc &
        !unref$genus_lc %in% h2_genus_lc &
        (tolower(trimws(unref$species)) %in% h1_species_lc |
         unref$genus_lc %in% h1_genus_rank_lc),
        na.rm = TRUE
      )

      if (nrow(family_sp) > 0L) {
        new_rows[[2L]] <- data.frame(
          observation_id        = sid,
          taxon_name            = family_sp$species,
          taxon_name_rank       = "species",
          hypothesis_type       = "unreferenced_genus",
          score_likelihood      = h3$score_likelihood[1L],
          score_likelihood_mean = h3$score_likelihood_mean[1L],
          score_likelihood_sd   = h3$score_likelihood_sd[1L],
          stringsAsFactors      = FALSE
        )
        n_h3_species <- n_h3_species + nrow(family_sp)
      }
      # else: no locally-plausible unreferenced species -- drop the generic H3 row
    }

    result_list[[i]] <- dplyr::bind_rows(new_rows)
  }

  expanded <- dplyr::bind_rows(result_list)
  exp_types <- if (nrow(expanded) > 0L) expanded$hypothesis_type else character(0L)
  n_h2_generic_dropped <- nrow(h2_rows) -
    sum(vapply(result_list, function(x) nrow(x) > 0L && any(x$hypothesis_type == "unreferenced_species"), logical(1L))) -
    n_h2_obs_covered
  n_h3_generic_dropped <- nrow(h3_rows) -
    sum(vapply(result_list, function(x) nrow(x) > 0L && any(x$hypothesis_type == "unreferenced_genus"), logical(1L)))

  message(sprintf(
    paste0("expand_unreferenced_hypotheses: H2 -> %d named species rows ",
           "(%d generic dropped; %d suppressed -- already H1 or genus-rank H1 covered); ",
           "H3 -> %d named species rows (%d generic dropped; %d suppressed -- already H1 or genus-rank H1 covered)."),
    n_h2_species, n_h2_generic_dropped, n_h2_covered,
    n_h3_species, n_h3_generic_dropped, n_h3_covered
  ))

  dplyr::bind_rows(h1_rows, expanded)
}
