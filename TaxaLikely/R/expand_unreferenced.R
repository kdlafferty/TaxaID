utils::globalVariables(c("hypothesis_type"))

#' Expand unreferenced hypotheses from genus/family level to named species
#'
#' @description
#' This is the value-modeling half
#' of unreferenced-taxon handling ("borrow a likelihood from referenced
#' relatives"), which belongs next to [unreferenced_candidates()] (the
#' candidate-generation half) rather than in the posterior-computation
#' package. It still requires both a TaxaLikely likelihood object and a
#' TaxaExpect-derived unreferenced-species list, so it must still run after
#' both are available and before [TaxaAssign::compute_posterior()] -- that is
#' a workflow-ordering requirement, not a package-dependency one, since this
#' function only ever consumes plain data frames and never calls into
#' TaxaExpect or TaxaAssign itself.
#'
#' After [evaluate_likelihoods()], the `"unreferenced_species"`
#' hypothesis is labelled at genus level (e.g. `taxon_name = "Fundulus"`,
#' `taxon_name_rank = "genus"`) and the `"unreferenced_genus"` hypothesis at
#' family level.  This function adds one named row per plausible
#' unreferenced species next to those generic rows, enabling
#' [TaxaAssign::compute_posterior()] to join them directly to species-level
#' priors from TaxaExpect.
#'
#' ## Expansion rules (applied per `observation_id`)
#' [evaluate_likelihoods()] builds one `"unreferenced_species"` (H2) row per
#' genus and one `"unreferenced_genus"` (H3) row per family among the
#' observation's candidates. A species is named only from its own genus's
#' ring (the last item concerns the generic rows):
#' \enumerate{
#'   \item A genus with a candidate in the observation has its own genus
#'     ring, and its unreferenced species take that ring (each genus ring is
#'     copied onto the species of its own genus only). Species-level
#'     suppression: an unreferenced species is suppressed only if that exact
#'     species is already a `specific_candidate` for this observation.
#'     Exception: when an H1 `specific_candidate` row is genus-rank
#'     (`taxon_name_rank == "genus"`), the entire genus is suppressed -- the
#'     genus is already represented with its own calibrated score.
#'   \item A species whose genus has no ring in the observation is never
#'     named. A family ring means "some unreferenced genus of this family",
#'     and its local species can number in the dozens, so naming one of them
#'     would be the prior's choice rather than the read's. Such species are
#'     listed as withheld (see below): a referenced genus whose references
#'     did not match the read, or a genus with no reference for the marker.
#'     The generic family row still stands for them.
#'   \item The generic H2 and H3 rows are kept alongside the named rows.
#'     The named rows cover unreferenced species recorded locally; the generic
#'     row stands for species of that genus or family that are neither
#'     referenced nor recorded, which is the unrecorded share the
#'     dark-diversity floor prices in [TaxaAssign::join_priors()]. Dropping it
#'     whenever no named species exists would read "no occurrence record" as
#'     "absent". The one exception is a genus already represented by a
#'     genus-rank `specific_candidate`: that candidate covers the whole genus,
#'     so neither the generic H2 row nor named congeners are added.
#'     `TaxaAssign::add_unreferenced_prior_mass()` excludes the named rows
#'     from the generic row's added mass, so nothing is counted twice.
#' }
#'
#' ## H2 and H3 likelihoods
#' The H2 likelihood is independently modelled by TaxaLikely from sister-species
#' matches (cross-species matches within the same genus in the reference
#' database).  The H3 likelihood is modelled from sister-genus matches.
#' These are not borrowed from H1 rows -- they reflect the expected score
#' distribution for an unreferenced congener or confamilial, respectively.
#' All named species expanded from one ring share that ring's H2 (or H3) likelihood;
#' TaxaExpect priors differentiate among them geographically.
#'
#' ## Building `unreferenced_df`
#' \enumerate{
#'   \item Start with TaxaExpect's plausible species list for the site
#'     (includes `genus` and `family` columns from TaxaFetch).
#'   \item Subtract species already in TaxaMatch -- these have reference
#'     sequences by definition.
#'   \item Call [audit_barcode_coverage()] with
#'     `species_list` = the TaxaExpect species and `match_df` = the TaxaMatch
#'     reference species. Species with NCBI barcode count = 0 are truly
#'     unreferenced.
#'   \item Filter TaxaExpect rows to those confirmed as unreferenced and
#'     select `species`, `genus`, `family`.
#' }
#'
#' ## Pipeline order
#' Run \emph{before} [apply_coverage_constraints()]. That function matches
#' its genus census against genus-rank `unreferenced_species` rows, so it
#' acts on the kept generic H2 row: a genus whose census is complete has no
#' unsequenced species, and its generic row is relabelled (or zeroed).
#'
#' @param likelihood_df Data frame -- the `$likelihoods` component returned by
#'   [evaluate_likelihoods()].  Must contain `observation_id`,
#'   `taxon_name`, `taxon_name_rank`, `hypothesis_type`,
#'   `score_likelihood`, `score_likelihood_mean`, `score_likelihood_sd`.
#' @param unreferenced_df Data frame of unreferenced but plausible species.
#'   Must contain columns `species` (binomial name), `genus`, and `family`.
#'   Built from TaxaExpect rows confirmed as unreferenced by
#'   [audit_barcode_coverage()]. May optionally contain an `observation_id`
#'   column: a row with `NA` (or when the column is absent
#'   entirely) applies to every observation sharing its genus/family, the
#'   original global-list behavior; a row with a real `observation_id`
#'   applies only to that one observation. This lets a caller inject a
#'   species that IS globally referenced (so it would never appear via
#'   [audit_barcode_coverage()]) but lacks reference evidence covering one
#'   specific query's region -- see
#'   [restore_suppressed_candidates()]'s `check_regional_overlap` mechanism,
#'   whose rejected congeners are returned in exactly this shape via
#'   `attr(result, "regional_unreferenced")`.
#'
#' @return `likelihood_df` with named species rows added under each genus
#'   ring where matches are found; generic rows are kept.  Column set is unchanged; new rows carry `NA` for most extra
#'   columns in the input (e.g. `constraint_applied`, which is genuinely
#'   row-specific), except `score_likelihood_cov`, `score_likelihood_evidence`,
#'   and `h2_delta_source` when present -- these, like `score_likelihood`/
#'   `score_likelihood_mean`/`score_likelihood_sd`, describe the shared H2/H3
#'   value itself (identical across every expanded species under one generic
#'   row) rather than anything row-specific, so they are copied through too.
#'
#' @section Withheld rows:
#'   No species is named from a FAMILY ring. Every species a family ring would
#'   otherwise have named is listed in `attr(result, "unreferenced_withheld")`
#'   (`observation_id`, `taxon_name`, `genus`, `family`, `reason`) and counted
#'   in a message. `reason` is `"genus_referenced_unmatched"` when the genus
#'   has references for this marker (a `specific_candidate` row anywhere in
#'   `likelihood_df`) that did not match the read, and `"no_own_genus_ring"`
#'   when the genus has none. The data frame is present, possibly empty, on
#'   every return.
#' @seealso [TaxaAssign::compute_posterior()], [evaluate_likelihoods()],
#'   [audit_barcode_coverage()], [apply_coverage_constraints()],
#'   [restore_suppressed_candidates()] for the `check_regional_overlap`
#'   mechanism that produces an observation-scoped `unreferenced_df` addition
#'
#' @note For a fully runnable, non-`\dontrun{}` demonstration (including how
#'   `result`/`unreferenced_species_result` are derived), see
#'   `inst/review_function_inputs.R` Section 7 in the package source.
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
  # ---- validate ---------------------------------------------------------------
  if (!is.data.frame(likelihood_df)) {
    stop("likelihood_df must be a data frame")
  }
  needed_lik <- c(
    "observation_id", "taxon_name", "taxon_name_rank",
    "hypothesis_type", "score_likelihood",
    "score_likelihood_mean", "score_likelihood_sd"
  )
  miss_lik <- setdiff(needed_lik, names(likelihood_df))
  if (length(miss_lik) > 0L) {
    stop(sprintf(
      "likelihood_df is missing required columns: %s",
      paste(miss_lik, collapse = ", ")
    ))
  }

  if (!is.data.frame(unreferenced_df)) {
    stop("unreferenced_df must be a data frame")
  }
  # Unreferenced species expansion is inherently genus/family-level:
  # species names are matched to genera, and family is used for family-level
  # unreferenced taxon insertion. These three columns are always required.
  needed_unref <- c("species", "genus", "family")
  miss_unref <- setdiff(needed_unref, tolower(names(unreferenced_df)))
  if (length(miss_unref) > 0L) {
    stop(sprintf(
      paste0(
        "unreferenced_df is missing required columns: %s. These are needed because ",
        "unreferenced species expansion matches species to genera and uses family for ",
        "higher-rank insertion."
      ),
      paste(miss_unref, collapse = ", ")
    ))
  }

  if (nrow(unreferenced_df) == 0L) {
    message(paste0(
      "unreferenced_df is empty -- no named species to add; the generic ",
      "unreferenced_species and unreferenced_genus rows are kept."
    ))
    return(likelihood_df)
  }

  # ---- normalise case for matching --------------------------------------------
  unref <- unreferenced_df
  # Input shapes: a row with no species name cannot be a hypothesis; a species
  # listed twice (for the same observation scope) is one hypothesis, not two.
  no_name <- is.na(unref$species) | !nzchar(trimws(as.character(unref$species)))
  if (any(no_name)) {
    message(sprintf("expand_unreferenced_hypotheses: %d unreferenced_df row(s) with no species name dropped.", sum(no_name)))
    unref <- unref[!no_name, , drop = FALSE]
  }
  dup_key <- paste(tolower(trimws(unref$species)),
                   if ("observation_id" %in% names(unref)) unref$observation_id else NA, sep = "\r")
  if (anyDuplicated(dup_key)) unref <- unref[!duplicated(dup_key), , drop = FALSE]
  unref$genus_lc <- tolower(trimws(unref$genus))
  unref$family_lc <- tolower(trimws(unref$family))
  # observation_id is optional. A row with NA (or an absent
  # column entirely) applies to every observation sharing its genus/family --
  # the original, global-unreferenced-species-list behavior. A row with a
  # real observation_id applies ONLY to that one observation. This is what
  # lets restore_suppressed_candidates(check_regional_overlap = TRUE) inject
  # a species that IS globally referenced (so it would never appear in a
  # normal audit_barcode_coverage()-derived unreferenced_df) but has no
  # reference evidence covering this SPECIFIC query's region -- without
  # treating it as globally unreferenced for every other observation where
  # it's a perfectly good, already-referenced H1 candidate.
  if (!"observation_id" %in% names(unref)) unref$observation_id <- NA_character_

  # ---- split by hypothesis type -----------------------------------------------
  h1_rows <- dplyr::filter(likelihood_df, hypothesis_type == "specific_candidate")
  h2_rows <- dplyr::filter(likelihood_df, hypothesis_type == "unreferenced_species")
  h3_rows <- dplyr::filter(likelihood_df, hypothesis_type == "unreferenced_genus")

  # Which genera HAVE references for this marker: every genus that matched any
  # read anywhere in this table (a candidate exists only because a reference
  # does). Used only to label why a species was withheld from a family ring:
  # no species is ever named from one.
  referenced_genera_lc <- unique(tolower(trimws(c(
    sub(" .*$", "", h1_rows$taxon_name[h1_rows$taxon_name_rank != "genus"]),
    h1_rows$taxon_name[h1_rows$taxon_name_rank == "genus"]
  ))))
  referenced_genera_lc <- referenced_genera_lc[!is.na(referenced_genera_lc) & nzchar(referenced_genera_lc)]
  withheld <- list()

  observation_ids <- unique(likelihood_df$observation_id)
  n_h2_species <- 0L
  n_h3_species <- 0L
  result_list <- vector("list", length(observation_ids))

  n_h2_covered <- 0L # individual species suppressed at H2 (already H1 or genus-rank H1)
  n_h2_obs_covered <- 0L # H2 observations suppressed entirely (genus-rank H1, or all species already H1)
  n_h3_covered <- 0L # individual species suppressed at H3
  n_h2_generic_kept <- 0L
  n_h3_generic_kept <- 0L

  for (i in seq_along(observation_ids)) {
    sid <- observation_ids[i]
    h2 <- h2_rows[h2_rows$observation_id == sid, , drop = FALSE]
    h3 <- h3_rows[h3_rows$observation_id == sid, , drop = FALSE]

    named_h2 <- list()
    named_h3 <- list()
    generic_h2 <- list()
    generic_h3 <- list()

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

    # ---- H2: unreferenced species of each genus that has its own ring -------
    # One ring per genus present among the unit's candidates; each is copied
    # onto the unreferenced species of THAT genus only.
    h2_genus_lc_all <- tolower(trimws(h2$taxon_name))
    for (j in seq_len(nrow(h2))) {
      h2_genus_lc <- h2_genus_lc_all[j]
      h2j <- h2[j, , drop = FALSE]

      if (h2_genus_lc %in% h1_genus_rank_lc) {
        # Genus already covered by a genus-rank specific_candidate -- drop all.
        genus_sp_all <- unref[
          unref$genus_lc %in% h2_genus_lc &
            (is.na(unref$observation_id) | unref$observation_id == sid), ,
          drop = FALSE
        ]
        n_h2_covered <- n_h2_covered + max(nrow(genus_sp_all), 1L)
        n_h2_obs_covered <- n_h2_obs_covered + 1L
      } else {
        generic_h2[[length(generic_h2) + 1L]] <- h2j # generic H2 kept
        n_h2_generic_kept <- n_h2_generic_kept + 1L
        genus_sp <- unref[
          unref$genus_lc %in% h2_genus_lc &
            (is.na(unref$observation_id) | unref$observation_id == sid), ,
          drop = FALSE
        ]
        if (nrow(genus_sp) > 0L) {
          # Species-level suppression: only drop species already H1 for this observation.
          already_h1 <- tolower(trimws(genus_sp$species)) %in% h1_species_lc
          n_h2_covered <- n_h2_covered + sum(already_h1)
          genus_sp_keep <- genus_sp[!already_h1, , drop = FALSE]
          if (nrow(genus_sp_keep) > 0L) {
            nr <- data.frame(
              observation_id        = sid,
              taxon_name            = genus_sp_keep$species,
              taxon_name_rank       = "species",
              hypothesis_type       = "unreferenced_species",
              score_likelihood      = h2j$score_likelihood[1L],
              score_likelihood_mean = h2j$score_likelihood_mean[1L],
              score_likelihood_sd   = h2j$score_likelihood_sd[1L],
              stringsAsFactors      = FALSE
            )
            # These, like the three likelihood columns above, are per-observation
            # diagnostics describing the shared H2 value itself -- identical across
            # every expanded species, not row-specific like constraint_applied --
            # so they are copied through rather than left NA.
            for (.col in c("score_likelihood_cov", "score_likelihood_evidence", "h2_delta_source")) {
              if (.col %in% names(h2j)) nr[[.col]] <- h2j[[.col]][1L]
            }
            named_h2[[length(named_h2) + 1L]] <- nr
            n_h2_species <- n_h2_species + nrow(genus_sp_keep)
          } else {
            # All unreferenced species in genus already H1 -- no expansion for this obs.
            n_h2_obs_covered <- n_h2_obs_covered + 1L
          }
        }
      }
    }

    # ---- H3: unreferenced species of each family ring, other genera ---------
    for (k in seq_len(nrow(h3))) {
      h3k <- h3[k, , drop = FALSE]
      h3_family_lc <- tolower(trimws(h3k$taxon_name[1L]))
      h2_genus_lc <- h2_genus_lc_all

      # Exclude: every genus with its own ring (handled above), species already
      # H1, genera covered by genus-rank H1 rows.
      family_sp <- unref[
        unref$family_lc %in% h3_family_lc &
          !unref$genus_lc %in% h2_genus_lc &
          !tolower(trimws(unref$species)) %in% h1_species_lc &
          !unref$genus_lc %in% h1_genus_rank_lc &
          (is.na(unref$observation_id) | unref$observation_id == sid), ,
        drop = FALSE
      ]
      # A species is named ONLY from its own genus's ring. A family ring is
      # "some unreferenced genus of this family"; naming one of its local
      # species would be the prior's choice, not the read's. Every species it
      # would have named is recorded instead, never silent: a referenced
      # genus's references were compared and did not match; an unreferenced
      # genus simply has no ring of its own in this unit.
      if (nrow(family_sp) > 0L) {
        ref_gen <- family_sp$genus_lc %in% referenced_genera_lc
        withheld[[length(withheld) + 1L]] <- data.frame(
          observation_id = sid, taxon_name = family_sp$species,
          genus = family_sp$genus, family = h3k$taxon_name[1L],
          reason = ifelse(ref_gen, "genus_referenced_unmatched", "no_own_genus_ring"),
          stringsAsFactors = FALSE
        )
        family_sp <- family_sp[0L, , drop = FALSE]
      }

      n_h3_covered <- n_h3_covered + sum(
        unref$family_lc %in% h3_family_lc &
          !unref$genus_lc %in% h2_genus_lc &
          (tolower(trimws(unref$species)) %in% h1_species_lc |
            unref$genus_lc %in% h1_genus_rank_lc) &
          (is.na(unref$observation_id) | unref$observation_id == sid),
        na.rm = TRUE
      )

      generic_h3[[length(generic_h3) + 1L]] <- h3k # generic H3 kept
      n_h3_generic_kept <- n_h3_generic_kept + 1L
      if (nrow(family_sp) > 0L) {
        nr <- data.frame(
          observation_id        = sid,
          taxon_name            = family_sp$species,
          taxon_name_rank       = "species",
          hypothesis_type       = "unreferenced_genus",
          score_likelihood      = h3k$score_likelihood[1L],
          score_likelihood_mean = h3k$score_likelihood_mean[1L],
          score_likelihood_sd   = h3k$score_likelihood_sd[1L],
          stringsAsFactors      = FALSE
        )
        # See the matching H2 comment above -- these are shared per-observation
        # diagnostics, not row-specific, so they are copied through too.
        for (.col in c("score_likelihood_cov", "score_likelihood_evidence", "h2_delta_source")) {
          if (.col %in% names(h3k)) nr[[.col]] <- h3k[[.col]][1L]
        }
        named_h3[[length(named_h3) + 1L]] <- nr
        n_h3_species <- n_h3_species + nrow(family_sp)
      }
    }

    result_list[[i]] <- dplyr::bind_rows(c(named_h2, named_h3, generic_h2, generic_h3))
  }

  withheld_df <- if (length(withheld)) do.call(rbind, withheld) else data.frame(
    observation_id = character(0), taxon_name = character(0), genus = character(0),
    family = character(0), reason = character(0), stringsAsFactors = FALSE
  )
  if (nrow(withheld_df) > 0L) {
    message(sprintf(
      "expand_unreferenced_hypotheses: %d species-named family-level row(s) withheld in %d observation(s): a species is named only from its own genus's ring (attr 'unreferenced_withheld' lists them, with the reason).",
      nrow(withheld_df), length(unique(withheld_df$observation_id))
    ))
  }

  expanded <- dplyr::bind_rows(result_list)

  message(sprintf(
    paste0(
      "expand_unreferenced_hypotheses: H2 -> %d named species rows plus %d generic ",
      "row(s) kept (%d observation(s) covered by a genus-rank H1; %d species suppressed ",
      "as already H1); H3 -> %d named species rows plus %d generic row(s) kept ",
      "(%d species suppressed as already H1 or genus-rank H1 covered)."
    ),
    n_h2_species, n_h2_generic_kept, n_h2_obs_covered, n_h2_covered,
    n_h3_species, n_h3_generic_kept, n_h3_covered
  ))

  out <- dplyr::bind_rows(h1_rows, expanded)
  attr(out, "unreferenced_withheld") <- withheld_df
  out
}
