utils::globalVariables(character(0))

#' Add a post-hoc plausibility assessment to a consensus data frame
#'
#' Classifies each row of a \code{posterior_consensus()} output using signals
#' already present in the data: sequence-match evidence
#' (\code{winner_likelihood}) and prior establishment status (taxon tier from
#' \code{priors_combined}) drive the base 3 x 2 classification below; an
#' optional third, independent signal (\code{absolute_fit_pvalue_col},
#' absolute rather than relative goodness of fit) can override any of those
#' four categories -- see \code{@section Weak absolute evidence}. The result
#' is a single categorical column \code{posthoc_assessment} suitable for
#' filtering or LLM-assisted review.
#'
#' \strong{Classification logic (3 x 2 table):}
#' \tabular{lll}{
#'   \strong{Prior tier} \tab \strong{Likelihood supported} \tab \strong{Likelihood limited} \cr
#'   tier1 (expected)          \tab \code{"sensible"}      \tab \code{"limited_evidence"} \cr
#'   tier2 (unexpected)        \tab \code{"unexpected"}    \tab \code{"suspect"}          \cr
#'   tier3_undetected          \tab \code{"unprecedented"} \tab \code{"suspect"}          \cr
#' }
#'
#' \strong{Special cases:}
#' \itemize{
#'   \item \code{consensus_rank != finest_rank}: tier lookup is not meaningful
#'     at coarser ranks; returns \code{"vague_rank"}.
#'   \item \code{winner_likelihood = NA}: likelihoods were not modelled (e.g.
#'     output from \code{assign_taxa_llm()} or unresolved observations);
#'     returns \code{"modeled"}.
#'   \item Taxon not found in \code{tiers}: treated as tier2 (no occurrence
#'     record in the prior model).
#' }
#'
#' \strong{Likelihood threshold:} \code{winner_likelihood} is ratio-normalised
#' within each observation (best hypothesis = 1.0).  A value below
#' \code{likelihood_threshold} (default 0.5) means another hypothesis had
#' more than twice the sequence-match density as the winner -- the winner won
#' primarily via prior strength.
#'
#' @section Domestic/synanthropic species caveat (Session 149):
#' GBIF- and iNaturalist-derived occurrence priors structurally under-index
#' captive/domestic organisms (pets, livestock) -- a data-curation property of
#' those sources, not a modelling choice. A domestic species can therefore
#' land in \code{tier2}/\code{tier3_undetected} (an artificially low prior)
#' even when the sequence-match or image/acoustic evidence for it is strong,
#' producing an \code{"unexpected"}/\code{"unprecedented"} label that looks
#' like a suspicious call but is really just a database gap -- likelihood
#' (from e.g. NCBI BLAST or iNaturalist image recognition, both of which
#' handle domestic species classification fine) contrasting with a low prior
#' that came from an occurrence database with no domestic-species coverage.
#' Passing \code{domestic_taxa} re-labels exactly this combination (strong
#' likelihood + a low-tier prior) to \code{"domestic_prior_caveat"} instead,
#' so a reviewer sees "trust the ID, question the rarity" rather than a
#' generic low-plausibility flag. This is deliberately conservative: it only
#' fires when the prior is expected to be an under-count (see
#' \code{domestic_prior_source}), never invents or elevates a prior itself.
#' If your prior pipeline already augments occurrence data with known local
#' domestic/synanthropic presence (rather than relying on raw GBIF/iNat), set
#' \code{domestic_prior_source = "augmented"} to disable this re-labelling,
#' since the low-tier signal is then informative on its own.
#'
#' @param consensus_df Data frame.  Output of
#'   \code{TaxaAssign::posterior_consensus()}, containing at minimum
#'   \code{winner_likelihood_col}, \code{consensus_taxon_col}, and
#'   \code{consensus_rank_col}.
#' @param tiers Data frame.  Taxon-tier lookup with at least \code{taxon_col}
#'   and \code{tier_col}.  Typically built as
#'   \code{dplyr::bind_rows(priors_observed, priors_undetected)} and passed
#'   directly; tier3 taxa (from \code{generate_undetected_diversity()}) are
#'   recognised by tier value \code{"tier3_undetected"}.
#' @param winner_likelihood_col Character.  Column in \code{consensus_df}
#'   holding the winner's ratio-normalised likelihood (default
#'   \code{"winner_likelihood"}).  Pass \code{"winner_likelihood_cov"} to use
#'   the coverage-adjusted value instead.
#' @param consensus_taxon_col Character.  Column holding the consensus taxon
#'   name (default \code{"consensus_taxon"}).
#' @param consensus_rank_col Character.  Column holding the consensus rank
#'   (default \code{"consensus_rank"}).
#' @param taxon_col Character.  Column in \code{tiers} to join on (default
#'   \code{"taxon_name"}).
#' @param tier_col Character.  Column in \code{tiers} holding the tier label
#'   (default \code{"model_tier"}).
#' @param likelihood_threshold Numeric in (0, 1).  Likelihood cutoff for
#'   "supported" vs "limited" evidence (default \code{0.5}).  Below this, the
#'   winner had less than half the sequence density of the best-matching
#'   hypothesis.
#' @param finest_rank Character.  The rank at which tier lookups are valid
#'   (default \code{"species"}).  Rows where \code{consensus_rank} differs
#'   receive \code{"vague_rank"}.
#' @param domestic_taxa Character vector or \code{NULL} (default).  Taxon
#'   names (matched against \code{consensus_taxon_col}) that are domestic or
#'   synanthropic for your study system (e.g. \code{"Felis catus"},
#'   \code{"Canis familiaris"}, \code{"Bos taurus"}) -- there is no built-in
#'   default list, since what counts as "domestic" is study-system-specific.
#'   \code{NULL} disables this feature entirely (matches
#'   \code{\link{flag_handler}}'s \code{handler_taxa} convention). See the
#'   Domestic/synanthropic species caveat section below.
#' @param domestic_prior_source Character.  One of \code{"wild"} (default) or
#'   \code{"augmented"}. \code{"wild"} assumes \code{tiers} came from a raw
#'   occurrence database (GBIF/iNaturalist) with no domestic-species
#'   augmentation, so a strong-likelihood + low-tier domestic-species row is
#'   re-labelled \code{"domestic_prior_caveat"}. \code{"augmented"} means the
#'   prior pipeline already incorporated known local domestic/synanthropic
#'   presence, so the low tier is treated as informative and no re-labelling
#'   happens. Ignored when \code{domestic_taxa} is \code{NULL}.
#' @param absolute_fit_pvalue_col Character.  Column in \code{consensus_df}
#'   holding the winning hypothesis's own one-sided ABSOLUTE (not relative)
#'   goodness-of-fit p-value, passed through unchanged from
#'   \code{TaxaLikely::evaluate_likelihoods()} via
#'   \code{TaxaAssign::posterior_consensus()}'s \code{winner_absolute_fit_pvalue}
#'   column (default \code{"winner_absolute_fit_pvalue"}). When present and
#'   below \code{weak_evidence_pvalue}, the row is labelled
#'   \code{"unsupported_rank"} regardless of what the other signals say --
#'   see \code{@section Weak absolute evidence} below. Silently ignored (no
#'   error) when absent from \code{consensus_df} -- an optional upstream
#'   output, not required input.
#' @param weak_evidence_pvalue Numeric in \code{[0, 1]} (default
#'   \code{0.001}).  Threshold for \code{absolute_fit_pvalue_col}: a value
#'   below this triggers \code{"unsupported_rank"}.  Not itself empirically
#'   validated against known real misidentification cases -- treat it as a
#'   starting point, not a calibrated constant.
#'
#' @section Weak absolute evidence (\code{"unsupported_rank"}):
#' \code{winner_likelihood_col} is ratio-normalised WITHIN one observation
#' (the best hypothesis is always exactly 1.0) -- it can read as strong
#' evidence even when every candidate fit poorly in absolute terms, simply
#' because nothing competitive existed to normalise against (e.g. a weak
#' match winning by default with no real competition; a real motivating
#' example, found on real data: 8 real PtConception 12S observations
#' confidently identified as \emph{Urocyon cinereoargenteus}/\emph{Canis
#' lupaster} -- real terrestrial canids -- at species level in a marine fish
#' survey, each with \code{winner_absolute_fit_pvalue} ~ 0.002-0.004).
#' \code{absolute_fit_pvalue_col} carries a different, absolute answer to a
#' related question: is this call's own fit to its trained distribution
#' believable at all, tested independently of any competing candidate. A
#' value below \code{weak_evidence_pvalue} means the reported call's own
#' evidence is weak in absolute terms -- this can happen even for a row the
#' other four signals would call \code{"sensible"}, which is why this check
#' runs last and can override any of them. Purely informational: never
#' changes \code{consensus_taxon} or \code{consensus_rank} themselves, only
#' how the existing values are labelled.
#'
#' 2026-07-19: this replaced an earlier design comparing
#' \code{TaxaLikely::evaluate_likelihoods()}'s \code{trusted_rank}
#' ladder-walk output (via a \code{trusted_rank_col} param) against
#' \code{consensus_rank_col}. That mechanism was found unreliable on real
#' data: \code{trusted_rank} was computed for
#' \code{evaluate_likelihoods()}'s own top-LIKELIHOOD hypothesis, which is
#' not always the same hypothesis that wins the POSTERIOR reported here once
#' priors are applied downstream (confirmed on a real 12S dataset: roughly
#' 30\% mismatch). Reading \code{absolute_fit_pvalue_col} directly off the
#' actual winning row has no such mismatch.
#'
#' @return \code{consensus_df} with one column appended:
#' \describe{
#'   \item{\code{posthoc_assessment}}{Character.  One of: \code{"sensible"},
#'     \code{"limited_evidence"}, \code{"unexpected"}, \code{"suspect"},
#'     \code{"unprecedented"}, \code{"vague_rank"}, \code{"modeled"},
#'     (only when \code{domestic_taxa} is supplied)
#'     \code{"domestic_prior_caveat"}, and (only when
#'     \code{absolute_fit_pvalue_col} is present in \code{consensus_df})
#'     \code{"unsupported_rank"}.}
#' }
#'
#' @examples
#' cons <- data.frame(
#'   observation_id    = c("obs1", "obs2", "obs3", "obs4", "obs5", "obs6"),
#'   consensus_taxon   = c("Oncorhynchus mykiss", "Homo sapiens",
#'                         "Salmo salar", "Sardina pilchardus",
#'                         "Rare sp.", "Cottus sp."),
#'   consensus_rank    = c("species", "species", "species",
#'                         "species", "species", "genus"),
#'   winner_likelihood = c(0.95, 0.03, 0.15, 0.80, 0.70, 0.90),
#'   winner_prior      = c(0.40, 0.80, 0.35, 0.002, NA, 0.10),
#'   stringsAsFactors  = FALSE
#' )
#' tiers <- data.frame(
#'   taxon_name  = c("Oncorhynchus mykiss", "Homo sapiens",
#'                   "Salmo salar", "Sardina pilchardus"),
#'   model_tier  = c("tier1", "tier1", "tier1", "tier3_undetected"),
#'   stringsAsFactors = FALSE
#' )
#' add_posthoc_assessment(cons, tiers)
#'
#' # Domestic-species caveat: a cat with a strong ID but a database-driven
#' # low prior gets a distinct label instead of looking "suspect".
#' cons2 <- data.frame(
#'   observation_id    = c("obs7", "obs8"),
#'   consensus_taxon   = c("Felis catus", "Made-up sp."),
#'   consensus_rank    = c("species", "species"),
#'   winner_likelihood = c(0.90, 0.90),
#'   stringsAsFactors  = FALSE
#' )
#' tiers2 <- data.frame(
#'   taxon_name = character(0),
#'   model_tier = character(0),
#'   stringsAsFactors = FALSE
#' )
#' add_posthoc_assessment(cons2, tiers2, domestic_taxa = "Felis catus")
#'
#' @seealso \code{\link{flag_contaminant}}, \code{\link{flag_handler}},
#'   \code{\link{review_assignments}}
#' @export
add_posthoc_assessment <- function(
    consensus_df,
    tiers,
    winner_likelihood_col = "winner_likelihood",
    consensus_taxon_col   = "consensus_taxon",
    consensus_rank_col    = "consensus_rank",
    taxon_col             = "taxon_name",
    tier_col              = "model_tier",
    likelihood_threshold  = 0.5,
    finest_rank           = "species",
    domestic_taxa         = NULL,
    domestic_prior_source = c("wild", "augmented"),
    absolute_fit_pvalue_col = "winner_absolute_fit_pvalue",
    weak_evidence_pvalue  = 0.001) {

  domestic_prior_source <- match.arg(domestic_prior_source)

  # ---- validate ----------------------------------------------------------------
  if (!is.data.frame(consensus_df))
    stop("add_posthoc_assessment: 'consensus_df' must be a data frame.", call. = FALSE)
  if (!is.data.frame(tiers))
    stop("add_posthoc_assessment: 'tiers' must be a data frame.", call. = FALSE)
  for (col in c(winner_likelihood_col, consensus_taxon_col, consensus_rank_col)) {
    if (!col %in% names(consensus_df))
      stop(sprintf("add_posthoc_assessment: column '%s' not found in consensus_df.", col),
           call. = FALSE)
  }
  for (col in c(taxon_col, tier_col)) {
    if (!col %in% names(tiers))
      stop(sprintf("add_posthoc_assessment: column '%s' not found in tiers.", col),
           call. = FALSE)
  }
  if (!is.numeric(likelihood_threshold) || length(likelihood_threshold) != 1L ||
      is.na(likelihood_threshold) || likelihood_threshold <= 0 ||
      likelihood_threshold >= 1)
    stop("add_posthoc_assessment: 'likelihood_threshold' must be a single number in (0, 1).",
         call. = FALSE)
  if (!is.null(domestic_taxa) && !is.character(domestic_taxa))
    stop("add_posthoc_assessment: 'domestic_taxa' must be a character vector or NULL.",
         call. = FALSE)
  if (!is.numeric(weak_evidence_pvalue) || length(weak_evidence_pvalue) != 1L ||
      is.na(weak_evidence_pvalue) || weak_evidence_pvalue < 0 || weak_evidence_pvalue > 1)
    stop("add_posthoc_assessment: 'weak_evidence_pvalue' must be a single number in [0, 1].",
         call. = FALSE)

  # ---- build tier lookup -------------------------------------------------------
  tiers_clean <- tiers[!is.na(tiers[[taxon_col]]), ]
  tier_lookup  <- stats::setNames(
    as.character(tiers_clean[[tier_col]]),
    as.character(tiers_clean[[taxon_col]])
  )

  # ---- extract vectors ---------------------------------------------------------
  n     <- nrow(consensus_df)
  lik   <- consensus_df[[winner_likelihood_col]]
  taxon <- as.character(consensus_df[[consensus_taxon_col]])
  rank  <- as.character(consensus_df[[consensus_rank_col]])

  # ---- classify ----------------------------------------------------------------
  assessment <- character(n)

  # Step 1: vague_rank — NA or non-species consensus rank
  vague_mask <- is.na(rank) | rank != finest_rank
  assessment[vague_mask] <- "vague_rank"

  # Step 2: modeled — NA likelihood (not already vague_rank)
  modeled_mask <- !vague_mask & is.na(lik)
  assessment[modeled_mask] <- "modeled"

  # Step 3: remaining rows → classify by tier + likelihood
  active_mask <- !vague_mask & !modeled_mask
  if (any(active_mask)) {
    tier_vec <- tier_lookup[taxon]          # NA for taxa not in tiers
    lik_ok   <- lik >= likelihood_threshold

    # tier1: expected
    t1 <- active_mask & !is.na(tier_vec) & tier_vec == "tier1"
    assessment[t1 &  lik_ok] <- "sensible"
    assessment[t1 & !lik_ok] <- "limited_evidence"

    # tier2 OR not in tiers (no occurrence record)
    t2 <- active_mask & (is.na(tier_vec) | tier_vec == "tier2")
    assessment[t2 &  lik_ok] <- "unexpected"
    assessment[t2 & !lik_ok] <- "suspect"

    # tier3_undetected (or any unrecognised tier value)
    t3 <- active_mask & !is.na(tier_vec) & !tier_vec %in% c("tier1", "tier2")
    assessment[t3 &  lik_ok] <- "unprecedented"
    assessment[t3 & !lik_ok] <- "suspect"

    # Domestic/synanthropic species caveat (Session 149): a strong-likelihood
    # call to a known domestic taxon that landed in tier2/tier3 purely
    # because GBIF/iNat under-index captive organisms is not the same kind
    # of "unexpected"/"unprecedented" as a genuinely surprising wild
    # detection -- re-label it distinctly rather than let it look equally
    # suspect. Deliberately narrow: only fires when the likelihood itself is
    # strong (the ID is trustworthy) and the low tier is the thing in
    # question, and only when the caller confirms the prior source didn't
    # already account for domestic species.
    if (!is.null(domestic_taxa) && domestic_prior_source == "wild") {
      domestic_mask <- active_mask & lik_ok & (t2 | t3) & taxon %in% domestic_taxa
      assessment[domestic_mask] <- "domestic_prior_caveat"
    }
  }

  # Step 4: unsupported_rank (weak absolute evidence) -- overrides ANY of the
  # above, including "sensible", since it answers a different question.
  # winner_likelihood_col is ratio-normalised WITHIN the observation (best
  # hypothesis = 1.0 by construction) -- it can be lik_ok = TRUE even when
  # every candidate fit poorly in absolute terms, if there was nothing
  # competitive to normalise against (see TaxaLikely::evaluate_likelihoods()'s
  # absolute_fit_pvalue). absolute_fit_pvalue_col carries the WINNING
  # candidate's own one-sided absolute goodness-of-fit p-value -- a value
  # below weak_evidence_pvalue means the reported call's own fit is poor in
  # absolute terms, regardless of how strong the relative likelihood or
  # occurrence prior looked. Purely informational -- never changes
  # consensus_taxon/consensus_rank. Silently skipped (no error) when
  # absolute_fit_pvalue_col is absent from consensus_df -- an optional
  # upstream output, not required input, since most existing consensus_df
  # objects predate it.
  #
  # 2026-07-19: replaced the earlier trusted_rank-based design (comparing
  # TaxaLikely::evaluate_likelihoods()'s rank-trust ladder-walk output against
  # consensus_rank via canonical rank order) with this simpler, more reliable
  # direct threshold check. The ladder-walk's trusted_rank was computed for
  # evaluate_likelihoods()'s own top-LIKELIHOOD hypothesis, which is not
  # always the same hypothesis that wins the POSTERIOR reported here once
  # priors are applied downstream -- confirmed on real data (~30% mismatch on
  # a real 12S dataset), making the old design unreliable in a way this one
  # is not: absolute_fit_pvalue is always read directly off the actual
  # winning row, with no intermediate ladder-walk to go stale. See
  # [[project_job2_unreferenced_relatives]] in the TaxaID memory system for
  # the full investigation.
  if (absolute_fit_pvalue_col %in% names(consensus_df)) {
    fit_pvalue <- as.numeric(consensus_df[[absolute_fit_pvalue_col]])
    mismatch_mask <- !is.na(fit_pvalue) & fit_pvalue < weak_evidence_pvalue
    assessment[mismatch_mask] <- "unsupported_rank"
  }

  consensus_df$posthoc_assessment <- assessment
  consensus_df
}
