# ==============================================================================
# expand_consensus_candidates()
# ==============================================================================

#' Expand a consensus taxon assignment to a full prior-based candidate set
#'
#' For observations where match scores are unavailable or limited (e.g.,
#' morphology-based identifications, upranked consensus outputs, single-candidate
#' classifier outputs such as BirdNET, or legacy databases), constructs a
#' likelihood object from a TaxaExpect priors data frame.  The result is
#' structurally identical to the output of [evaluate_likelihoods()] and feeds
#' directly into `TaxaAssign::compute_posterior()`.
#'
#' When \code{score_col} is \code{NULL} (default), all likelihoods are 1.0
#' (degenerate/uniform) and posteriors are proportional to priors.  When a
#' score column is supplied, the consensus species receives
#' \code{likelihood = score} and all other candidates receive
#' \code{likelihood = 1 - score}, so the score informs how strongly the
#' named candidate dominates competing hypotheses before priors are applied.
#'
#' @details
#' Candidate construction differs by the rank of the consensus taxon:
#'
#' \describe{
#'   \item{Species level}{Candidates = the consensus species plus congeners in
#'     \code{priors_df} that are \emph{not} in \code{referenced_species}.
#'     Referenced congeners are excluded because they would have competed via
#'     match scores had scores been available.  If \code{referenced_species} is
#'     \code{NULL} a warning is issued and all congeners in \code{priors_df} are
#'     included.}
#'   \item{Genus level}{Candidates = all species in \code{priors_df} whose genus
#'     matches the consensus taxon name.  Referenced species are included because
#'     a genus-level consensus means species-level score discrimination failed.}
#'   \item{Family level}{Same as genus level, using family membership.  Subject
#'     to \code{max_candidates} guard (default 50).  Observations exceeding this
#'     limit are returned in \code{$unresolved}.}
#' }
#'
#' Because all candidates receive \code{likelihood = 1.0}, calling
#' [filter_top_hypotheses()] after this function is not meaningful and should be
#' skipped.  [apply_coverage_constraints()] is also typically unnecessary since
#' all candidates are emitted as \code{"specific_candidate"}.
#'
#' @param consensus_df Data frame with one row per observation.  Required
#'   columns: \code{observation_id} (character), \code{taxon_name} (character),
#'   \code{taxon_name_rank} (character; must be one of \code{"species"},
#'   \code{"genus"}, or \code{"family"}).  If \code{score_col} is supplied, the
#'   named column must also be present and contain numeric values in \eqn{[0,
#'   1]}.
#' @param priors_df Data frame from TaxaExpect containing candidate species.
#'   Must contain a \code{"species"} column of binomial names plus taxonomy
#'   columns used for filtering: \code{"genus"} for species- and genus-level
#'   inputs; \code{"family"} for family-level inputs.  Additional columns
#'   (prior values, etc.) are ignored but may be present.
#' @param referenced_species Optional character vector of species names present
#'   in the reference database.  Used only for \code{taxon_name_rank ==
#'   "species"} rows to exclude congeners that would have competed via match
#'   scores.  If \code{NULL} and any species-level rows are present, a warning
#'   is issued and all congeners in \code{priors_df} are included.
#' @param score_col Character string naming the column in \code{consensus_df}
#'   that contains a classifier confidence score (0--1 scale).  When supplied,
#'   the consensus species receives \code{likelihood = score} and all other
#'   candidates receive \code{likelihood = 1 - score}.  When \code{NULL}
#'   (default), all candidates receive \code{likelihood = 1.0} (uniform).
#'   Appropriate for single-best-candidate classifiers such as BirdNET.
#' @param max_candidates Positive integer (default \code{50L}).  Maximum number
#'   of candidates per observation for family-level inputs.  Observations
#'   exceeding this limit are returned in \code{$unresolved} with a warning.
#'
#' @return A named list with two components matching the structure of
#'   [evaluate_likelihoods()]:
#'   \describe{
#'     \item{\code{$likelihoods}}{Data frame with one row per
#'       \code{observation_id} x candidate species: \code{observation_id},
#'       \code{taxon_name}, \code{taxon_name_rank} (\code{"species"}),
#'       \code{hypothesis_type} (\code{"specific_candidate"}),
#'       \code{likelihood_point_est} (1.0 when no score; \code{score} for
#'       consensus species and \code{1 - score} for others when
#'       \code{score_col} is supplied), \code{likelihood_mean} (same as
#'       point estimate), \code{likelihood_sd} (0.0).}
#'     \item{\code{$unresolved}}{Rows from \code{consensus_df} for observations
#'       where no candidates were found in \code{priors_df}, or where the
#'       family-level candidate count exceeded \code{max_candidates}.  Empty
#'       data frame if none.}
#'   }
#'
#' @seealso [evaluate_likelihoods()], [filter_top_hypotheses()]
#'
#' @examples
#' \dontrun{
#' # Morphology-based IDs with no match scores (uniform likelihoods)
#' consensus <- data.frame(
#'   observation_id  = c("obs1", "obs2", "obs3"),
#'   taxon_name      = c("Salmo salar", "Salvelinus", "Salmonidae"),
#'   taxon_name_rank = c("species", "genus", "family")
#' )
#'
#' result <- expand_consensus_candidates(
#'   consensus_df       = consensus,
#'   priors_df          = my_priors,
#'   referenced_species = reference_df$species
#' )
#' head(result$likelihoods)
#'
#' # BirdNET top-1 output: single candidate with classifier confidence score.
#' # Consensus species gets likelihood = score; congeners get 1 - score.
#' birdnet <- data.frame(
#'   observation_id  = c("clip_001", "clip_002"),
#'   taxon_name      = c("Melospiza melodia", "Turdus migratorius"),
#'   taxon_name_rank = c("species", "species"),
#'   confidence      = c(0.87, 0.43)
#' )
#'
#' result2 <- expand_consensus_candidates(
#'   consensus_df       = birdnet,
#'   priors_df          = my_priors,
#'   referenced_species = NULL,
#'   score_col          = "confidence"
#' )
#' head(result2$likelihoods)
#' # observation_id  taxon_name           likelihood_point_est
#' # clip_001        Melospiza melodia    0.87   <- score
#' # clip_001        Melospiza lincolnii  0.13   <- 1 - score
#' }
#'
#' @importFrom dplyr bind_rows n_distinct
#' @export
expand_consensus_candidates <- function(consensus_df,
                                        priors_df,
                                        referenced_species = NULL,
                                        score_col          = NULL,
                                        max_candidates     = 50L) {

  # ---- input validation -------------------------------------------------------
  if (!is.data.frame(consensus_df))
    stop("consensus_df must be a data frame", call. = FALSE)
  needed <- c("observation_id", "taxon_name", "taxon_name_rank")
  missing_cols <- setdiff(needed, names(consensus_df))
  if (length(missing_cols) > 0L)
    stop(sprintf("consensus_df is missing required columns: %s",
                 paste(missing_cols, collapse = ", ")), call. = FALSE)
  if (!is.data.frame(priors_df))
    stop("priors_df must be a data frame", call. = FALSE)
  if (!"species" %in% names(priors_df))
    stop("priors_df must contain a 'species' column", call. = FALSE)
  if (!is.null(referenced_species) && !is.character(referenced_species))
    stop("referenced_species must be a character vector or NULL", call. = FALSE)
  if (!is.null(score_col)) {
    if (!is.character(score_col) || length(score_col) != 1L || !nzchar(score_col))
      stop("score_col must be a single non-empty character string or NULL", call. = FALSE)
    if (!score_col %in% names(consensus_df))
      stop(sprintf("score_col '%s' not found in consensus_df", score_col), call. = FALSE)
    score_vals <- consensus_df[[score_col]]
    if (!is.numeric(score_vals))
      stop(sprintf("consensus_df$%s must be numeric", score_col), call. = FALSE)
    out_of_range <- !is.na(score_vals) & (score_vals < 0 | score_vals > 1)
    if (any(out_of_range))
      stop(sprintf("consensus_df$%s contains values outside [0, 1]", score_col), call. = FALSE)
  }
  if (!is.numeric(max_candidates) || length(max_candidates) != 1L ||
      is.na(max_candidates) || max_candidates < 1L)
    stop("max_candidates must be a single positive integer", call. = FALSE)
  max_candidates <- as.integer(max_candidates)

  names(consensus_df) <- tolower(names(consensus_df))
  names(priors_df)    <- tolower(names(priors_df))

  supported_ranks <- c("species", "genus", "family")
  obs_ranks       <- unique(tolower(trimws(consensus_df$taxon_name_rank)))
  bad_ranks       <- setdiff(obs_ranks, supported_ranks)
  if (length(bad_ranks) > 0L)
    stop(sprintf(
      "Unsupported taxon_name_rank value(s): %s. Supported: %s.",
      paste(bad_ranks, collapse = ", "),
      paste(supported_ranks, collapse = ", ")
    ), call. = FALSE)

  has_species_rows <- any(obs_ranks == "species")
  if (has_species_rows && is.null(referenced_species))
    warning(
      "'referenced_species' is NULL for species-level consensus rows. ",
      "All congeners in priors_df will be included as candidates. ",
      "Provide 'referenced_species' to exclude congeners that competed via match scores.",
      call. = FALSE
    )

  ref_sp_norm    <- unique(trimws(tolower(referenced_species)))   # length 0 if NULL
  priors_df$species <- trimws(priors_df$species)
  has_genus_col  <- "genus"  %in% names(priors_df)
  has_family_col <- "family" %in% names(priors_df)

  # ---- per-observation candidate construction ---------------------------------
  n_obs      <- nrow(consensus_df)
  results    <- vector("list", n_obs)
  unresolved <- vector("list", n_obs)

  for (i in seq_len(n_obs)) {
    row    <- consensus_df[i, , drop = FALSE]
    oid    <- row$observation_id
    tname  <- trimws(row$taxon_name)
    trank  <- tolower(trimws(row$taxon_name_rank))

    # ---- build candidate rows from priors_df by rank -------------------------
    cand_df <- switch(trank,

      "species" = {
        if (!has_genus_col) {
          warning(sprintf(
            "observation_id '%s': priors_df lacks 'genus' column; returning consensus species only.",
            oid), call. = FALSE)
          data.frame(species = tname, stringsAsFactors = FALSE)
        } else {
          # Identify genus: look up in priors_df first; fall back to first word
          genus_match <- priors_df$genus[
            trimws(tolower(priors_df$species)) == tolower(tname)
          ]
          genus_match    <- unique(genus_match[!is.na(genus_match)])
          consensus_genus <- if (length(genus_match) > 0L) genus_match[1L]
                             else strsplit(tname, " ")[[1L]][1L]

          # All congeners with priors
          congeners <- priors_df[
            !is.na(priors_df$genus) &
              trimws(tolower(priors_df$genus)) == tolower(consensus_genus),
            , drop = FALSE
          ]

          # Exclude referenced congeners, but always keep the consensus species
          keep <- !(trimws(tolower(congeners$species)) %in% ref_sp_norm) |
                    trimws(tolower(congeners$species)) == tolower(tname)
          congeners <- congeners[keep, , drop = FALSE]

          # Add consensus species if absent from priors_df
          if (!tolower(tname) %in% trimws(tolower(congeners$species))) {
            add <- data.frame(species = tname, genus = consensus_genus,
                              stringsAsFactors = FALSE)
            if (has_family_col) {
              fam_vals <- unique(congeners$family[!is.na(congeners$family)])
              add$family <- if (length(fam_vals) > 0L) fam_vals[1L] else NA_character_
            }
            congeners <- dplyr::bind_rows(add, congeners)
          }

          congeners
        }
      },

      "genus" = {
        if (!has_genus_col) {
          warning(sprintf(
            "observation_id '%s': priors_df lacks 'genus' column; cannot expand genus-level consensus.",
            oid), call. = FALSE)
          NULL
        } else {
          priors_df[
            !is.na(priors_df$genus) &
              trimws(tolower(priors_df$genus)) == tolower(tname),
            , drop = FALSE
          ]
        }
      },

      "family" = {
        if (!has_family_col) {
          warning(sprintf(
            "observation_id '%s': priors_df lacks 'family' column; cannot expand family-level consensus.",
            oid), call. = FALSE)
          NULL
        } else {
          priors_df[
            !is.na(priors_df$family) &
              trimws(tolower(priors_df$family)) == tolower(tname),
            , drop = FALSE
          ]
        }
      }
    )

    # ---- guard: no candidates ------------------------------------------------
    if (is.null(cand_df) || nrow(cand_df) == 0L) {
      warning(sprintf(
        "No candidates found in priors_df for observation_id '%s' (%s '%s'). Returning in $unresolved.",
        oid, trank, tname), call. = FALSE)
      unresolved[[i]] <- row
      next
    }

    cand_species <- trimws(cand_df$species)
    cand_species <- cand_species[!is.na(cand_species) & nzchar(cand_species)]

    if (length(cand_species) == 0L) {
      warning(sprintf(
        "No valid species names in priors_df candidates for observation_id '%s'. Returning in $unresolved.",
        oid), call. = FALSE)
      unresolved[[i]] <- row
      next
    }

    # ---- guard: family-level candidate overflow ------------------------------
    if (trank == "family" && length(cand_species) > max_candidates) {
      warning(sprintf(
        "observation_id '%s' (family '%s') has %d candidates (> max_candidates = %d). Returning in $unresolved.",
        oid, tname, length(cand_species), max_candidates), call. = FALSE)
      unresolved[[i]] <- row
      next
    }

    # ---- compute likelihoods -------------------------------------------------
    if (!is.null(score_col) && !is.na(row[[score_col]])) {
      sv     <- row[[score_col]]
      likes  <- ifelse(tolower(cand_species) == tolower(tname), sv, 1 - sv)
    } else {
      likes  <- rep(1.0, length(cand_species))
    }

    # ---- build likelihood rows -----------------------------------------------
    results[[i]] <- data.frame(
      observation_id       = oid,
      taxon_name           = cand_species,
      taxon_name_rank      = "species",
      hypothesis_type      = "specific_candidate",
      likelihood_point_est = likes,
      likelihood_mean      = likes,
      likelihood_sd        = 0.0,
      stringsAsFactors     = FALSE
    )
  }

  # ---- assemble output --------------------------------------------------------
  likelihoods_df <- dplyr::bind_rows(results)
  unresolved_df  <- dplyr::bind_rows(unresolved)

  if (is.null(unresolved_df) || nrow(unresolved_df) == 0L)
    unresolved_df <- consensus_df[integer(0L), ]

  n_resolved   <- if (nrow(likelihoods_df) > 0L)
                    dplyr::n_distinct(likelihoods_df$observation_id)
                  else 0L
  n_unresolved <- nrow(unresolved_df)

  message(sprintf(
    "expand_consensus_candidates: %d observation(s) expanded to %d candidate rows; %d unresolved.",
    n_resolved, nrow(likelihoods_df), n_unresolved
  ))

  list(likelihoods = likelihoods_df, unresolved = unresolved_df)
}
