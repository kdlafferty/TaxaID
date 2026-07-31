utils::globalVariables(character(0))

#' Add post-hoc plausibility and discrimination assessments to a consensus data frame
#'
#' Appends two independent, orthogonal diagnostic axes to a
#' \code{TaxaAssign::posterior_consensus()} output, reported for
#' \code{primary_taxon} and \code{consensus_taxon} separately: occurrence
#' plausibility (Axis 1 -- \code{primary_plausibility}/
#' \code{consensus_plausibility}, "how expected is this taxon here?") and
#' discrimination (Axis 2 -- \code{primary_discrimination}/
#' \code{consensus_discrimination}, "could the evidence tell this taxon
#' apart from a plausible relative?"). Neither axis gates or overrides the
#' other, and neither is folded into a single combined categorical -- see
#' \code{@section} below for both, and the "Retirement" section for why the
#' earlier single-column \code{posthoc_assessment} design (with its
#' \code{"vague_rank"} short-circuit for any non-species rank) was removed.
#'
#' @section Retirement of \code{posthoc_assessment} (2026-07-30):
#' The original design cross-tabulated sequence-match evidence against a
#' taxon-tier lookup into one 9-category column, including
#' \code{"vague_rank"} -- returned for EVERY row whose \code{consensus_rank}
#' was not \code{"species"}, short-circuiting classification entirely rather
#' than reporting a coarser-but-still-informative answer. Measured on a real
#' 616-observation Mugu dataset: 109 observations (17.7\%) got
#' \code{"vague_rank"} and were never assessed at all. This is exactly the
#' failure mode the Axis 1/Axis 2 redesign replaces it with: both axes are
#' computed at whatever rank the data actually resolved to, reported
#' alongside each other, with no rank at which classification simply stops.
#' \code{posthoc_assessment}, \code{tiers}, \code{taxon_col}, \code{tier_col},
#' and \code{finest_rank} are all removed -- there is no replacement for the
#' 3x2 tier-times-likelihood table itself, since \code{primary_plausibility}
#' (occurrence side) and \code{primary_discrimination} (evidence side)
#' already answer the same two questions without collapsing them into one
#' column or gating either on rank.
#'
#' @section Domestic/synanthropic species caveat (Session 149, redesigned 2026-07-30):
#' GBIF- and iNaturalist-derived occurrence priors structurally under-index
#' captive/domestic organisms (pets, livestock) -- a data-curation property of
#' those sources, not a modelling choice. A domestic species can therefore
#' show \code{primary_plausibility = "unexpected"}/\code{"unprecedented"}
#' (an artificially low occurrence share) even when the sequence-match or
#' image/acoustic evidence for it is strong, looking like a suspicious call
#' when it is really just a database gap. Passing \code{domestic_taxa} flags
#' exactly this combination (strong likelihood + low occurrence
#' plausibility) via the new \code{domestic_prior_caveat} column, so a
#' reviewer sees "trust the ID, question the rarity" rather than treating
#' the occurrence-implausibility flag at face value. This is deliberately
#' conservative: it only fires when the prior is expected to be an
#' under-count (see \code{domestic_prior_source}), never invents or elevates
#' a prior itself, and -- unlike the retired \code{posthoc_assessment}
#' design, which re-labelled the combined column in place -- is now its own
#' small additive column, matching the axes' own "report alongside, never
#' override" design. If your prior pipeline already augments occurrence data
#' with known local domestic/synanthropic presence (rather than relying on
#' raw GBIF/iNat), set \code{domestic_prior_source = "augmented"} to disable
#' this flag, since \code{primary_plausibility} is then informative on its
#' own.
#'
#' @param consensus_df Data frame.  Output of
#'   \code{TaxaAssign::posterior_consensus()}, containing at minimum
#'   \code{winner_likelihood_col}, \code{consensus_taxon_col}, and
#'   \code{consensus_rank_col}.
#' @param winner_likelihood_col Character.  Column in \code{consensus_df}
#'   holding the winner's ratio-normalised likelihood (default
#'   \code{"winner_likelihood"}).  Used only by the domestic-species caveat
#'   (see below) -- a strong value here means the ID itself is trustworthy,
#'   independent of whether the occurrence prior underrepresents the taxon.
#' @param consensus_taxon_col Character.  Column holding the consensus taxon
#'   name (default \code{"consensus_taxon"}).  Used only by the
#'   domestic-species caveat, to match against \code{domestic_taxa}.
#' @param consensus_rank_col Character.  Column holding the consensus rank
#'   (default \code{"consensus_rank"}).  Drives which
#'   \code{expected_theta_threshold} entry \code{consensus_plausibility}
#'   compares against.
#' @param likelihood_threshold Numeric in (0, 1).  Likelihood cutoff the
#'   domestic-species caveat uses for "the ID itself is trustworthy" (default
#'   \code{0.5}).  Below this, the winner had less than half the
#'   sequence-match density of the best-matching hypothesis.  Unused when
#'   \code{domestic_taxa} is \code{NULL}.
#' @param domestic_taxa Character vector or \code{NULL} (default).  Taxon
#'   names (matched against \code{consensus_taxon_col}) that are domestic or
#'   synanthropic for your study system (e.g. \code{"Felis catus"},
#'   \code{"Canis familiaris"}, \code{"Bos taurus"}) -- there is no built-in
#'   default list, since what counts as "domestic" is study-system-specific.
#'   \code{NULL} disables this feature entirely (matches
#'   \code{\link{flag_handler}}'s \code{handler_taxa} convention). See the
#'   Domestic/synanthropic species caveat section above.
#' @param domestic_prior_source Character.  One of \code{"wild"} (default) or
#'   \code{"augmented"}. \code{"wild"} assumes the underlying occurrence prior
#'   came from a raw occurrence database (GBIF/iNaturalist) with no
#'   domestic-species augmentation, so a strong-likelihood +
#'   low-plausibility domestic-species row is flagged via
#'   \code{domestic_prior_caveat}. \code{"augmented"} means the prior
#'   pipeline already incorporated known local domestic/synanthropic
#'   presence, so low occurrence plausibility is treated as informative and
#'   the flag never fires. Ignored when \code{domestic_taxa} is \code{NULL}.
#' @param primary_confusion_risk_col Character.  Column in \code{consensus_df}
#'   holding \code{TaxaAssign::posterior_consensus()}'s
#'   \code{winner_own_rank_confusion_risk} -- the confusion-risk value
#'   rank-matched to \code{primary_taxon}'s own resolved rank (default
#'   \code{"winner_own_rank_confusion_risk"}).  Drives
#'   \code{primary_discrimination}.  See \code{@section Discrimination
#'   (Axis 2)} below.
#' @param consensus_confusion_risk_col Character.  Column holding the
#'   confusion-risk value rank-matched to \code{consensus_taxon} (default
#'   \code{"consensus_confusion_risk"}).  Drives
#'   \code{consensus_discrimination}.
#' @param discriminating_threshold Numeric in \code{[0, 1]} (default
#'   \code{0.05}).  Below this, the resolved rank is \code{"discriminating"}.
#' @param indistinguishable_threshold Numeric in \code{[0, 1]}, \code{>=
#'   discriminating_threshold} (default \code{0.5}).  At or above this, the
#'   resolved rank is \code{"indistinguishable"}; between the two
#'   thresholds, \code{"weak"}.
#'
#' @section Discrimination (Axis 2) (\code{primary_discrimination}/\code{consensus_discrimination}):
#' A confusion-risk value (\code{TaxaLikely::evaluate_likelihoods()}'s
#' \code{species_confusion_risk}/\code{genus_confusion_risk}/
#' \code{family_confusion_risk}, passed through by
#' \code{posterior_consensus()}) is a model-independent, score-ONLY
#' diagnostic: given the winning candidate's own raw match score, how often
#' would a REAL congener/confamilial/cross-family pair score this high or
#' higher? HIGHER values mean MORE confusable, i.e. WEAKER evidence for the
#' resolved rank -- a genuine risk-style metric (high=concern), unlike
#' \code{score_likelihood}/\code{posterior_mean}/\code{confidence_score}
#' elsewhere in this ecosystem, which are all high=good -- see
#' \code{evaluate_likelihoods()}'s own \code{@section Confusion risk} for
#' the full interpretation.
#'
#' \code{primary_discrimination}/\code{consensus_discrimination} tier that
#' raw value into three ordinal bands (plus \code{"not_modeled"} when the
#' source column is absent or \code{NA}): \code{"discriminating"} (\code{<
#' 0.05}), \code{"weak"} (\code{0.05}-\code{0.5}), \code{"indistinguishable"}
#' (\code{>= 0.5}). Both breaks are interpretable statements about a genuine
#' one-sided tail probability rather than fitted cutoffs.
#'
#' These are reported \strong{alongside} \code{primary_plausibility}/
#' \code{consensus_plausibility} (Axis 1) rather than combined with them --
#' Axis 1 asks whether the taxon is expected to be here at all; Axis 2 asks
#' whether the evidence could discriminate it from a plausible relative.
#' Neither substitutes for the other. This design is deliberately additive
#' rather than a recomputing/overriding mechanism -- the cautionary
#' precedent is the \code{trusted_rank} ladder-walk (built 2026-07-19,
#' removed 2026-07-20 after a real ~30\% likelihood/posterior-winner
#' mismatch plus a downranking-cancellation bug -- see
#' \code{[[project_rank_trust_mechanism_removed]]} in the TaxaID memory
#' system).
#'
#' @param winner_theta_col Character.  Column in \code{consensus_df} holding
#'   the winning hypothesis's own raw occurrence-model share (default
#'   \code{"winner_theta_mean"}, from
#'   \code{TaxaAssign::posterior_consensus()}).  Drives
#'   \code{primary_plausibility}.  Deliberately reads \code{theta_mean}, NOT
#'   \code{winner_prior}/\code{prior_mean} -- see @section Occurrence
#'   plausibility below for why the two are not interchangeable.
#' @param winner_record_col Character.  Column indicating whether the winning
#'   hypothesis's taxon carries a real occurrence record at all (default
#'   \code{"winner_has_occurrence_record"}).  This, NOT a low theta value, is
#'   what makes a call \code{"unprecedented"}.
#' @param consensus_prior_col Character.  Column holding the occurrence-model
#'   share (\code{theta_mean}-based group sum, see
#'   \code{TaxaAssign::posterior_consensus()}'s own docs) for the consensus
#'   taxon (default \code{"consensus_prior"}).
#' @param consensus_record_col Character.  Column indicating whether the
#'   consensus taxon's group carries a real occurrence record at all
#'   (default \code{"consensus_has_occurrence_record"}).  This, NOT
#'   \code{consensus_prior_col}'s \code{NA}-ness, is what makes a call
#'   \code{"unprecedented"} at consensus scope -- \code{consensus_prior} is
#'   \code{NA} for two different reasons (no local member found, OR
#'   \code{group_priors} was never supplied to \code{posterior_consensus()}
#'   at all) that this column alone cannot distinguish; a taxon with
#'   \code{NA} here is \code{"not_modeled"}, not \code{"unprecedented"}.
#' @param expected_theta_threshold Named numeric vector, no default -- this
#'   genuinely depends on the taxon assemblage being scored and there is no
#'   universal safe value (mirrors \code{TaxaAssign::join_priors()}'s
#'   \code{backbone_id} / \code{TaxaAssign::score_consensus()}'s
#'   \code{rank_thresholds}, both required for the same reason). Names must
#'   be rank labels (e.g. \code{c(species = ..., genus = ..., family =
#'   ...)}); \code{"species"} is required, since \code{primary_plausibility}
#'   always compares against it (see @section Occurrence plausibility). A
#'   recorded taxon at or above the threshold for ITS OWN rank is
#'   \code{"expected"}; below it, \code{"unexpected"}; a rank with no entry
#'   in this vector gets \code{"not_modeled"} rather than an unsafe
#'   cross-rank comparison. Recommended: the median \code{theta_sum} at each
#'   rank from \code{TaxaAssign::compute_group_priors()} (species from
#'   \code{median(taxaexpect_priors$theta_mean, na.rm = TRUE)} directly,
#'   since \code{compute_group_priors()} is only built for genus/family) --
#'   an "at least as expected as a typical local taxon at this rank"
#'   reading, avoiding a fitted or absolute cutoff. See @section Occurrence
#'   plausibility.
#'
#' @section Occurrence plausibility (\code{primary_plausibility}/\code{consensus_plausibility}):
#' An ordinal answer to "how expected is this taxon here?", reported for
#' \code{primary_taxon} and \code{consensus_taxon} separately and computed
#' at whatever rank the data actually resolved to -- never short-circuited
#' for a coarser rank, the specific defect the retired \code{"vague_rank"}
#' category had.
#'
#' \code{"unprecedented"} is driven by RECORD PRESENCE, never by a low value.
#' A never-reported taxon and a genuine singleton can carry the same numeric
#' value -- both land on the dark-diversity floor -- while meaning opposite
#' things, so no threshold on the value can separate them.
#'
#' \strong{Reads \code{theta_mean}, not \code{prior_mean} (fixed 2026-07-30).}
#' \code{prior_mean} can be substantially inflated by
#' \code{TaxaAssign::update_prior_from_consensus()}'s cross-observation
#' confirmation boost, which has no gate on occurrence-record presence.
#' Measured on real Mugu data: of 616 winning candidates, 110 had
#' \code{winner_prior >= 0.5}, and on that same dataset EVERY row with
#' \code{prior_mean >= 0.5} was a boosted row -- so an \code{expected} call
#' built on \code{prior_mean} would mean "confirmed elsewhere in this
#' dataset", not "expected here on occurrence grounds". \code{theta_mean}
#' (\code{TaxaExpect::prepare_model_dataframe()}'s raw occurrence-model share,
#' a compositional share of local records -- see
#' \code{TaxaAssign::update_prior_from_consensus()}'s own "Rescaling onto the
#' occurrence scale" section) is immune to that boost by construction, since
#' the boost only ever modifies \code{prior_mean}.
#'
#' A single absolute threshold (the previous design used \code{0.5} on the
#' \code{prior_mean} scale) is also a unit mismatch on the \code{theta_mean}
#' scale: \code{theta_mean} is a share of local records, not a presence
#' probability, so comparing it to "50/50 odds" is not a meaningful
#' comparison. Beyond that, a SINGLE threshold applied at every rank is
#' itself biased: a genus/family-level \code{consensus_prior} (the SUM of
#' \code{theta_mean} across every locally modelled group member, from
#' \code{TaxaAssign::posterior_consensus(group_priors = ...)}) is
#' mechanically larger than any one species' own share just from summing
#' more terms -- measured on real Mugu data, 27 of 28 real families clear
#' the SPECIES-level median purely by having more members, not because they
#' are more locally expected. \code{expected_theta_threshold} is therefore a
#' RANK-MATCHED vector: \code{primary_plausibility} (always the winning
#' candidate's own species-level share) is compared against the
#' \code{"species"} entry; \code{consensus_plausibility} is compared against
#' whichever entry matches that row's own \code{consensus_rank_col} value.
#' A \code{consensus_rank} with no matching entry (e.g. a coarser rank the
#' caller didn't supply a threshold for) gets \code{"not_modeled"} rather
#' than being compared against the wrong rank's threshold.
#'
#' @return \code{consensus_df} with five columns appended:
#' \describe{
#'   \item{\code{primary_plausibility}, \code{consensus_plausibility}}{
#'     Character.  Occurrence plausibility (Axis 1) of \code{primary_taxon}
#'     and of \code{consensus_taxon}: \code{"expected"}, \code{"unexpected"},
#'     \code{"unprecedented"}, or \code{"not_modeled"} when nothing is
#'     computable -- including when \code{consensus_rank} has no matching
#'     entry in \code{expected_theta_threshold}.  \code{NA} when the required
#'     source columns are absent from \code{consensus_df}.}
#'   \item{\code{primary_discrimination}, \code{consensus_discrimination}}{
#'     Character.  Discrimination (Axis 2) of \code{primary_taxon} and of
#'     \code{consensus_taxon}: \code{"discriminating"}, \code{"weak"},
#'     \code{"indistinguishable"}, or \code{"not_modeled"} when the source
#'     confusion-risk column is absent or \code{NA}.  See \code{@section
#'     Discrimination (Axis 2)} above.}
#'   \item{\code{domestic_prior_caveat}}{Logical.  \code{TRUE} when the
#'     winning taxon is in \code{domestic_taxa}, \code{domestic_prior_source
#'     = "wild"}, the ID itself is trustworthy (\code{winner_likelihood_col}
#'     \code{>= likelihood_threshold}), and \code{primary_plausibility} is
#'     \code{"unexpected"} or \code{"unprecedented"} -- i.e. the occurrence
#'     plausibility flag for this row is a likely database-coverage artifact,
#'     not a genuine surprise. \code{FALSE} otherwise, including when
#'     \code{domestic_taxa} is \code{NULL} (the feature is disabled). See
#'     @section Domestic/synanthropic species caveat above.}
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
#'   winner_theta_mean = c(0.010, 0.020, 0.009, 0.0005, NA, 0.003),
#'   winner_has_occurrence_record = c(TRUE, TRUE, TRUE, TRUE, FALSE, TRUE),
#'   stringsAsFactors  = FALSE
#' )
#' # expected_theta_threshold has no default -- a named vector, one entry
#' # per rank ("species" required). Typically the median theta at that rank
#' # (species: median(taxaexpect_priors$theta_mean); genus/family: median of
#' # TaxaAssign::compute_group_priors()'s theta_sum at that rank).
#' add_posthoc_assessment(cons,
#'                        expected_theta_threshold = c(species = 0.008, genus = 0.02))
#'
#' # Domestic-species caveat: a cat with a strong ID but a database-driven
#' # low occurrence plausibility gets a distinct flag rather than looking
#' # like a genuinely surprising detection.
#' cons2 <- data.frame(
#'   observation_id    = c("obs7", "obs8"),
#'   consensus_taxon   = c("Felis catus", "Made-up sp."),
#'   consensus_rank    = c("species", "species"),
#'   winner_likelihood = c(0.90, 0.90),
#'   winner_theta_mean = c(0.0002, 0.0002),
#'   winner_has_occurrence_record = c(TRUE, TRUE),
#'   stringsAsFactors  = FALSE
#' )
#' add_posthoc_assessment(cons2, domestic_taxa = "Felis catus",
#'                        expected_theta_threshold = c(species = 0.008))
#'
#' @seealso \code{\link{flag_contaminant}}, \code{\link{flag_handler}},
#'   \code{\link{review_assignments}}
#' @export
add_posthoc_assessment <- function(
    consensus_df,
    winner_likelihood_col = "winner_likelihood",
    consensus_taxon_col   = "consensus_taxon",
    consensus_rank_col    = "consensus_rank",
    likelihood_threshold  = 0.5,
    domestic_taxa         = NULL,
    domestic_prior_source = c("wild", "augmented"),
    primary_confusion_risk_col    = "winner_own_rank_confusion_risk",
    consensus_confusion_risk_col  = "consensus_confusion_risk",
    discriminating_threshold      = 0.05,
    indistinguishable_threshold   = 0.5,
    winner_theta_col              = "winner_theta_mean",
    winner_record_col             = "winner_has_occurrence_record",
    consensus_prior_col           = "consensus_prior",
    consensus_record_col          = "consensus_has_occurrence_record",
    expected_theta_threshold) {

  if (missing(expected_theta_threshold))
    stop(
      "add_posthoc_assessment: 'expected_theta_threshold' has no default -- it depends on ",
      "the taxon assemblage being scored. Supply a named vector, e.g. ",
      "c(species = median(taxaexpect_priors$theta_mean, na.rm = TRUE), ",
      "genus = median(group_priors$theta_sum[group_priors$rank == \"genus\"]), ",
      "family = median(group_priors$theta_sum[group_priors$rank == \"family\"])).",
      call. = FALSE
    )

  domestic_prior_source <- match.arg(domestic_prior_source)

  # ---- validate ----------------------------------------------------------------
  if (!is.data.frame(consensus_df))
    stop("add_posthoc_assessment: 'consensus_df' must be a data frame.", call. = FALSE)
  for (col in c(winner_likelihood_col, consensus_taxon_col, consensus_rank_col)) {
    if (!col %in% names(consensus_df))
      stop(sprintf("add_posthoc_assessment: column '%s' not found in consensus_df.", col),
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
  if (!is.character(primary_confusion_risk_col) || length(primary_confusion_risk_col) != 1L)
    stop("add_posthoc_assessment: 'primary_confusion_risk_col' must be a single character string.",
         call. = FALSE)
  if (!is.character(consensus_confusion_risk_col) || length(consensus_confusion_risk_col) != 1L)
    stop("add_posthoc_assessment: 'consensus_confusion_risk_col' must be a single character string.",
         call. = FALSE)
  if (!is.numeric(discriminating_threshold) || length(discriminating_threshold) != 1L ||
      is.na(discriminating_threshold) || discriminating_threshold < 0 ||
      discriminating_threshold > 1)
    stop("add_posthoc_assessment: 'discriminating_threshold' must be a single number in [0, 1].",
         call. = FALSE)
  if (!is.numeric(indistinguishable_threshold) || length(indistinguishable_threshold) != 1L ||
      is.na(indistinguishable_threshold) || indistinguishable_threshold < 0 ||
      indistinguishable_threshold > 1)
    stop("add_posthoc_assessment: 'indistinguishable_threshold' must be a single number in [0, 1].",
         call. = FALSE)
  if (discriminating_threshold > indistinguishable_threshold)
    stop("add_posthoc_assessment: 'discriminating_threshold' must be <= 'indistinguishable_threshold'.",
         call. = FALSE)
  if (!is.numeric(expected_theta_threshold) || length(expected_theta_threshold) == 0L ||
      is.null(names(expected_theta_threshold)) || any(!nzchar(names(expected_theta_threshold))) ||
      any(is.na(expected_theta_threshold)) ||
      any(expected_theta_threshold < 0) || any(expected_theta_threshold > 1))
    stop("add_posthoc_assessment: 'expected_theta_threshold' must be a named numeric vector ",
         "(rank -> threshold) with values in [0, 1], e.g. c(species = 0.003, genus = 0.003, ",
         "family = 0.017).", call. = FALSE)
  if (!"species" %in% names(expected_theta_threshold))
    stop("add_posthoc_assessment: 'expected_theta_threshold' must include a 'species' entry -- ",
         "primary_plausibility always compares against it.", call. = FALSE)

  # ---- extract vectors ---------------------------------------------------------
  n     <- nrow(consensus_df)
  lik   <- consensus_df[[winner_likelihood_col]]
  taxon <- as.character(consensus_df[[consensus_taxon_col]])
  rank  <- as.character(consensus_df[[consensus_rank_col]])

  # ---- Axis 2: discrimination (2026-07-30) ------------------------------------
  # `primary_discrimination` / `consensus_discrimination`. See @section
  # Discrimination (Axis 2) for the full design rationale.
  .discrimination <- function(risk) {
    out <- rep("not_modeled", length(risk))
    ok  <- !is.na(risk)
    out[ok & risk < discriminating_threshold] <- "discriminating"
    out[ok & risk >= discriminating_threshold & risk < indistinguishable_threshold] <- "weak"
    out[ok & risk >= indistinguishable_threshold] <- "indistinguishable"
    out
  }

  primary_discrimination <- rep(NA_character_, n)
  if (primary_confusion_risk_col %in% names(consensus_df)) {
    primary_discrimination <- .discrimination(
      as.numeric(consensus_df[[primary_confusion_risk_col]])
    )
  }

  consensus_discrimination <- rep(NA_character_, n)
  if (consensus_confusion_risk_col %in% names(consensus_df)) {
    consensus_discrimination <- .discrimination(
      as.numeric(consensus_df[[consensus_confusion_risk_col]])
    )
  }

  # ---- Axis 1: occurrence plausibility (2026-07-28, theta-based 2026-07-30) ---
  # `primary_plausibility` / `consensus_plausibility` -- one ordinal answer to
  # "how expected is this taxon here?", computed at whatever rank the data
  # actually resolved to. See @section Occurrence plausibility for the full
  # design rationale (theta_mean vs prior_mean, rank-matched thresholds).
  #
  # `rank` is a per-row vector of rank labels; a rank absent from
  # expected_theta_threshold's names looks up as NA (base R vector-by-name
  # indexing), which correctly falls through to `not_modeled` below rather
  # than an unsafe cross-rank comparison.
  .plausibility <- function(theta, has_record, rank_vec) {
    out <- rep("not_modeled", length(theta))
    known <- !is.na(has_record)
    out[known & !has_record] <- "unprecedented"
    thr <- unname(expected_theta_threshold[rank_vec])
    ok <- known & has_record & !is.na(theta) & !is.na(thr)
    out[ok & theta >= thr] <- "expected"
    out[ok & theta <  thr] <- "unexpected"
    out
  }

  # primary_plausibility always compares against the "species" threshold:
  # winner_theta_col is the WINNING candidate's own share, and a winning
  # candidate is essentially always resolved at species rank in this
  # ecosystem's real data (confirmed: all 616 real winners in one Mugu
  # dataset were species-rank). There is no winner-rank column to read a
  # per-row value from, so this is a documented assumption, not a lookup.
  primary_plausibility <- rep(NA_character_, n)
  if (winner_theta_col %in% names(consensus_df) &&
      winner_record_col %in% names(consensus_df)) {
    primary_plausibility <- .plausibility(
      as.numeric(consensus_df[[winner_theta_col]]),
      as.logical(consensus_df[[winner_record_col]]),
      rep("species", n)
    )
  }

  # Consensus scope. `consensus_prior`'s NA does not reliably mean "never
  # reported": since `posterior_consensus()`'s old candidate-scoped MAX
  # fallback for `consensus_prior` was removed, `consensus_prior` is ALSO NA
  # whenever `group_priors` was never supplied to `posterior_consensus()` at
  # all -- true of every real production workflow today, none of which wire
  # it in yet. Reading presence off `consensus_prior_col`'s own NA-ness
  # cannot distinguish these two cases, so presence is read directly from
  # `consensus_record_col` (`TaxaAssign::posterior_consensus()`'s dedicated
  # `consensus_has_occurrence_record` column, added specifically to carry
  # this signal) instead of inferred. When `group_priors` was never
  # supplied, `consensus_record_col` is `NA` for every row, which
  # `.plausibility()`'s `known <- !is.na(has_record)` gate correctly
  # resolves to `"not_modeled"`, never `"unprecedented"`.
  consensus_plausibility <- rep(NA_character_, n)
  if (consensus_prior_col %in% names(consensus_df) &&
      consensus_record_col %in% names(consensus_df)) {
    consensus_plausibility <- .plausibility(
      as.numeric(consensus_df[[consensus_prior_col]]),
      as.logical(consensus_df[[consensus_record_col]]),
      rank
    )
  }

  # ---- Domestic/synanthropic species caveat (Session 149, redesigned 2026-07-30) --
  # See @section above. Redesigned to read primary_plausibility (Axis 1)
  # instead of the retired tier lookup -- same underlying occurrence-gap
  # signal, sourced from the more principled theta_mean-based mechanism.
  domestic_prior_caveat <- rep(FALSE, n)
  if (!is.null(domestic_taxa) && domestic_prior_source == "wild") {
    lik_ok <- !is.na(lik) & lik >= likelihood_threshold
    low_plausibility <- !is.na(primary_plausibility) &
      primary_plausibility %in% c("unexpected", "unprecedented")
    domestic_prior_caveat <- lik_ok & low_plausibility & taxon %in% domestic_taxa
  }

  consensus_df$primary_plausibility     <- primary_plausibility
  consensus_df$consensus_plausibility   <- consensus_plausibility
  consensus_df$primary_discrimination   <- primary_discrimination
  consensus_df$consensus_discrimination <- consensus_discrimination
  consensus_df$domestic_prior_caveat    <- domestic_prior_caveat
  consensus_df
}
