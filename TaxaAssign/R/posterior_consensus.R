# posterior_consensus.R
# TaxaAssign package
#
# Derives a consensus taxonomic assignment from a posterior dataframe.
# Returns one row per observation_id: the lowest common ancestor (LCA) among the
# minimal set of top-ranked hypotheses that collectively account for a
# user-defined fraction of the named-taxon posterior probability.
#
# Exported functions:
#   posterior_consensus()     LCA-based consensus from a posterior dataframe
#
# Internal helpers:
#   .consensus_one_observation()  Per-observation LCA computation
#   .find_lca()              LCA from a set of plausible hypothesis rows
#   .extract_rank_values()   Extract rank values from df (column or derived)
#   .empty_consensus_row()   NA-filled result for unresolvable observations
#   .build_species_ref()     Normalise species_reference to a data.frame
#   .downrank_consensus()    Downrank coarse LCA when reference has one finer taxon


# ==============================================================================
# Main exported function
# ==============================================================================

#' Derive Consensus Taxonomy from a Posterior Dataframe
#'
#' For each `observation_id`, identifies the minimal set of top-ranked hypotheses
#' that together account for `cumulative_threshold` of the named-taxon posterior
#' mass (after excluding hypotheses below `min_posterior`), then returns their
#' lowest common ancestor (LCA) as the consensus taxonomic assignment.
#'
#' **Which hypotheses are included:** All named hypotheses contribute to the
#' LCA — `"specific_candidate"`, `"unreferenced_species"` (congener without reference
#' sequence), `"unreferenced_genus"` (family-level unreferenced taxon: named species
#' from a genus absent in the reference), and `"unresolved_species"` (a species from a
#' census-complete genus whose identity is ambiguous among the known reference members;
#' produced by [TaxaLikely::apply_coverage_constraints()] with
#' `constraint_behavior = "relabel"`). Only the `"unknown_species"` catch-all row is
#' excluded.
#'
#' **LCA resolution:** The LCA is determined by walking taxonomy ranks from
#' finest to coarsest and finding the finest rank at which all plausible
#' hypotheses agree. Explicit taxonomy columns (e.g. `family`, `genus`,
#' `species`) are used when present in `posterior_df`; genus can always be
#' derived from a species binomial even when no `genus` column is present.
#' Family and above require an explicit column.
#'
#' **Taxonomy columns in posterior_df:** `assign_taxa_llm()` automatically
#' carries taxonomy columns from `match_df` into its output. When using the
#' full pipeline (`compute_posterior()`), taxonomy columns pass through from
#' `evaluate_likelihoods()`. Unreferenced species rows have `NA` in taxonomy columns;
#' set `lookup_missing_taxonomy = TRUE` to attempt lookup via
#' `TaxaTools::verify_taxon_names()`.
#'
#' @param posterior_df Dataframe. Output of [compute_posterior()] or
#'   [assign_taxa_llm()]. Required columns: `observation_id`, `taxon_name`,
#'   `taxon_name_rank`, `hypothesis_type`, and the column named by
#'   `posterior_col`.
#' @param rank_system Optional character vector of taxonomy column names,
#'   coarse-to-fine (e.g. `c("family", "genus", "species")`). If `NULL`
#'   (default), standard taxonomy columns present in `posterior_df` are
#'   detected automatically from `kingdom, phylum, class, order, family,
#'   genus, species`. Genus is always derivable from species binomials even
#'   when the `genus` column is absent.
#' @param cumulative_threshold Numeric in (0, 1]. Cumulative posterior
#'   probability threshold for the plausible hypothesis set. Hypotheses are
#'   included in descending posterior order until this fraction of total
#'   probability is reached. At 0.90, the plausible set contains the fewest
#'   hypotheses accounting for at least 90% of posterior mass, analogous to a
#'   90% credible interval. Default 0.9. For example, at 0.9 with posteriors
#'   (0.6, 0.25, 0.10, 0.05), the plausible set includes the top 2
#'   hypotheses (0.6 + 0.25 = 0.85 < 0.9, so the third is also included:
#'   0.6 + 0.25 + 0.10 = 0.95 >= 0.9). The LCA of these three hypotheses
#'   becomes the consensus.
#' @param min_posterior Numeric in \[0, 1). Minimum individual posterior
#'   probability to retain a hypothesis. Hypotheses below this threshold are
#'   excluded before computing the LCA consensus. At 0.05, a hypothesis must
#'   hold at least 5% posterior probability to influence the consensus taxon.
#'   Default 0.05. Set to 0 to disable.
#' @param posterior_col Character. Name of the posterior column to rank
#'   hypotheses by. Default `"posterior_point_est"` -- aligned (2026-08-28)
#'   with `run_bayesian_pipeline()` and every production workflow, which had
#'   always passed the point-estimate column explicitly while this function
#'   alone defaulted to `"posterior_mean"` (undocumented drift; the
#'   three-way operative-column experiment in
#'   `ecosystem_docs/REENTRY_PROMPT_undetected_evidence_mixture_redesign.md`
#'   (D8) found the choice second-order and settled on point estimates: best
#'   external corroboration, deterministic, and exactly auditable as
#'   prior x likelihood products). Pass `"posterior_mean"` to rank by the
#'   Monte Carlo mean instead -- with presence-mixture priors that column
#'   integrates over presence states (see `compute_posterior()`).
#' @param lookup_missing_taxonomy Logical. If `TRUE`, calls
#'   `TaxaTools::verify_taxon_names()` to fill in taxonomy columns for
#'   `"unreferenced_species"` rows that have `NA` in those columns. Requires
#'   TaxaTools to be installed and may make network requests. Default `FALSE`.
#' @param backbone_id Integer. Taxonomic backbone to use when
#'   `lookup_missing_taxonomy = TRUE`. Passed to
#'   `TaxaTools::verify_taxon_names()`. Required (errors) when
#'   `lookup_missing_taxonomy = TRUE` -- no default, since the correct
#'   backbone depends on which backbone your input taxonomy was verified
#'   against, which varies by project. Common values: 1 = Catalogue of Life,
#'   4 = NCBI, 9 = WoRMS, 11 = GBIF. See ecosystem CLAUDE.md for full list.
#'   Ignored (may be left `NULL`) when `lookup_missing_taxonomy = FALSE`.
#' @param species_reference Optional. A plausible-species reference used to
#'   downrank unresolved coarse-rank consensus assignments. Accepts two forms:
#'   \itemize{
#'     \item \strong{`unreferenced_species_result`} (from
#'       [suggest_unreferenced_species()]): the full LLM-generated plausible
#'       species list is extracted automatically from
#'       \code{attr(x, "plausible")}. This includes referenced species (e.g.
#'       \emph{Leptocottus armatus}) that the LLM flagged as plausible but that
#'       were filtered out of the unreferenced vector by the NCBI step.
#'       Use in the LLM workflow by passing the same object supplied to
#'       \code{assign_taxa_llm(unreferenced_taxa = ...)}.
#'     \item \strong{data.frame}: must contain a \code{taxon_name} column
#'       (species-level names) and columns named after each coarser rank in
#'       \code{rank_system} (e.g. \code{genus}, \code{family}). Pass
#'       \code{taxaexpect_species_df} in the Bayesian workflow.
#'   }
#'   For each unresolved row where `consensus_rank` is not the finest rank,
#'   the function looks up how many taxa at the next finer rank belong to the
#'   consensus taxon. If exactly one, it downranks (recursively — e.g. family
#'   to unique genus to unique species in one pass). Stops at any rank with
#'   more than one option. Default `NULL` (no downranking).
#' @param group_priors Optional data frame from [compute_group_priors()]
#'   (`rank`/`taxon`/`theta_sum`/`n_members` columns), the SUM of
#'   `theta_mean` over every locally modelled member of a genus or family --
#'   not just the candidates one observation's own evidence happened to
#'   surface. Drives `consensus_prior` when a matching (`rank`, `taxon`) row
#'   exists for an observation's `consensus_rank`/`consensus_taxon` (see that
#'   column's own docs below for the full reasoning). Default `NULL`:
#'   `consensus_prior` is `NA` for every row -- there is no fallback
#'   computation (removed 2026-07-30; the previous candidate-scoped MAX was a
#'   real underestimate, not a safe approximation).
#' @details
#' \strong{Threshold interaction:}
#' \code{min_posterior} and \code{cumulative_threshold} work together:
#' \code{min_posterior} removes obvious noise hypotheses first (those with
#' negligible posterior mass), then \code{cumulative_threshold} selects the
#' plausible set from the remainder. Setting \code{min_posterior = 0} disables
#' noise filtering; setting it too high (e.g. 0.3) may exclude genuine
#' competing hypotheses. \code{cumulative_threshold = 0.9} is analogous to a
#' 90\% credible interval; increase toward 0.95--0.99 for more conservative
#' assignments (more upranking to genus/family); decrease to 0.8 for more
#' aggressive species-level calls.
#'
#' \strong{Parameter sensitivity:} a grid sweep against a real posterior
#' dataset (see \code{diagnostics/posterior_threshold_sweep.R}) found the two
#' defaults are not equally load-bearing: \code{min_posterior} has a real,
#' roughly linear effect on how often the pipeline resolves to the finest
#' rank, while \code{cumulative_threshold} does comparatively little
#' independent work once a reasonable \code{min_posterior} floor is already
#' in place. The two interact sharply only in the unrealistic combination of
#' \code{min_posterior = 0} with a very high \code{cumulative_threshold}.
#' This sweep measures resolution \emph{rate}, not \emph{accuracy} -- no
#' ground-truth-validated observation set was available, so a higher
#' resolved-\% is not itself evidence those calls are correct.
#'
#' \strong{LCA method:}
#' Lowest Common Ancestor is the standard conservative consensus method in
#' molecular systematics (Huson et al., 2007, MEGAN). The implementation
#' walks from finest to coarsest rank and stops at the first rank where all
#' plausible hypotheses agree.
#'
#' @return A dataframe with one row per `observation_id`:
#'   \describe{
#'     \item{`observation_id`}{Sample identifier (same type as input).}
#'     \item{`consensus_taxon`}{Name of the LCA taxon, or `NA` if unresolvable
#'       (all hypotheses excluded or no rank agrees).}
#'     \item{`consensus_rank`}{Rank of the LCA (e.g. `"genus"`, `"family"`),
#'       or `NA`.}
#'     \item{`consensus_reason`}{How the consensus was reached:
#'       `"unanimous"` (all plausible hypotheses agree at the finest rank),
#'       `"single"` (only one hypothesis in the plausible set),
#'       `"lca"` (upranked because hypotheses disagree at finer ranks),
#'       `"threshold"` (rank-capped by `rank_thresholds` in
#'       [score_consensus()]), or `NA` (unresolvable).}
#'     \item{`is_resolved`}{`TRUE` when the LCA is at the finest rank in
#'       `rank_system` (i.e. a single unambiguous species-level assignment).}
#'     \item{`consensus_posterior`}{Sum of named posterior probabilities within
#'       the consensus taxon at its assigned rank.  Because posteriors are
#'       probabilities (full space = 1.0), this raw sum equals the probability
#'       of the consensus taxon without requiring a denominator.  Computed over
#'       \emph{all} named hypotheses before `min_posterior` and
#'       `cumulative_threshold` filtering, so it is independent of threshold
#'       settings and suitable for post-hoc confidence filtering (e.g. keep
#'       only assignments with `consensus_posterior >= 0.95`).
#'       `NA` when `consensus_taxon` is `NA`.}
#'     \item{`consensus_confidence_score`}{Sum of `confidence_score` values for
#'       all named hypotheses within the consensus taxon (computed over all named
#'       hypotheses, not just the plausible set).  `confidence_score` is the
#'       fraction of Monte Carlo simulations in which a hypothesis produced the
#'       highest posterior; summing over in-LCA hypotheses gives the fraction of
#'       simulations in which \emph{any} member of the consensus taxon won.
#'       Complementary to `consensus_posterior`: while `consensus_posterior`
#'       reflects mean posterior mass, `consensus_confidence_score` reflects how
#'       consistently that taxon dominated across simulations.  `NA` when
#'       `confidence_score` is absent from `posterior_df` (e.g. input from
#'       [assign_taxa_llm()]) or when `consensus_taxon` is `NA`.}
#'     \item{`n_plausible`}{Number of hypotheses in the plausible set (0 if
#'       all hypotheses were excluded).}
#'     \item{`plausible_taxa`}{List column: character vector of plausible taxon
#'       names, sorted by descending posterior.}
#'     \item{`plausible_posteriors`}{List column: named numeric vector of
#'       posterior values for plausible taxa (names = taxon_name).}
#'     \item{`downranked`}{Logical. `TRUE` when the initial LCA rank was
#'       coarser than the final `consensus_rank` due to downranking via
#'       `species_reference`. Only present when `species_reference` is
#'       non-`NULL`. `FALSE` for all rows that were not downranked.}
#'     \item{`winner_prior`}{Prior probability (`prior_mean`) of the
#'       consensus taxon, taken from the highest-posterior hypothesis in the
#'       plausible set. Use with `winner_likelihood` / `winner_likelihood_cov`
#'       to detect implausible winners (e.g. a low-prior taxon winning due to
#'       a reference error). `NA` when `prior_mean` is absent from
#'       `posterior_df` (e.g. input from [assign_taxa_llm()]) or when
#'       `consensus_taxon` is `NA`. NOTE: when `prior_mean` was sourced from
#'       TaxaExpect, this value can be substantially inflated by
#'       `update_prior_from_consensus()`'s cross-observation confirmation
#'       boost -- it is NOT interchangeable with `winner_theta_mean` below for
#'       occurrence-plausibility purposes; see that function's own "Rescaling
#'       onto the occurrence scale" section.}
#'     \item{`winner_theta_mean`}{The consensus taxon's raw occurrence-model
#'       share (`theta_mean`, from `TaxaExpect::prepare_model_dataframe()` --
#'       the fraction of local records attributable to this taxon; a
#'       compositional share, not a presence probability). Unlike
#'       `winner_prior`, this is immune to `update_prior_from_consensus()`'s
#'       confirmation boost by construction, since that boost only ever
#'       modifies `prior_mean`. `NA` when `theta_mean` is absent from
#'       `posterior_df` or when `consensus_taxon` is `NA`.}
#'     \item{`winner_likelihood`}{Point-estimate sequence-match likelihood
#'       (`score_likelihood`) of the consensus taxon. `NA` when absent from
#'       `posterior_df` or when `consensus_taxon` is `NA`.}
#'     \item{`winner_likelihood_cov`}{Coverage-adjusted sequence-match
#'       likelihood (`score_likelihood_cov`) of the consensus taxon. `NA`
#'       when absent from `posterior_df` or when `consensus_taxon` is `NA`.}
#'     \item{`winner_hypothesis_type`}{Character. The `hypothesis_type` of
#'       the winning (highest-posterior) hypothesis row, e.g.
#'       `"specific_candidate"`, `"unreferenced_species"`, or
#'       `"rank_expanded"` (see `winner_rank_expanded` below). `NA` when the
#'       winning row's `hypothesis_type` value is itself `NA`, or when
#'       `consensus_taxon` is `NA`.}
#'     \item{`winner_rank_expanded`}{Logical. `TRUE` when the winning
#'       hypothesis was manufactured by `join_priors()`'s coarse-rank
#'       expansion (`.expand_coarse_rank_rows()`) rather than resolved from a
#'       real species-level match. This means the reported species-level
#'       `consensus_taxon` was decided entirely by occurrence-prior mass
#'       among candidates that all inherited one identical, uninformative
#'       likelihood from the original coarse-rank (e.g. family-level)
#'       identification -- no sequence/image/acoustic evidence discriminated
#'       between them. This is intentional, sound behavior (using local
#'       occurrence priors to resolve an otherwise-coarse ID) -- this column
#'       exists so a downstream consumer can distinguish it from a
#'       genuinely evidence-resolved species call, not to flag it as an
#'       error. `NA` when `winner_hypothesis_type` is `NA`; `FALSE`
#'       otherwise.}
#'     \item{`winner_species_confusion_risk`, `winner_genus_confusion_risk`,
#'       `winner_family_confusion_risk`, `winner_own_rank_confusion_risk`}{Numeric. A
#'       SECOND, model-independent diagnostic alongside
#'       `TaxaLikely::evaluate_likelihoods()`'s `species_confusion_risk`/
#'       `genus_confusion_risk`/`family_confusion_risk`/`own_rank_confusion_risk`
#'       columns on the winning row. Each is a one-sided tail probability: how
#'       often would a REAL congener/confamilial/cross-family pair score this
#'       high or higher, given the winning candidate's own raw match score --
#'       HIGHER values mean MORE confusable, i.e. WEAKER evidence for that
#'       rank (see `evaluate_likelihoods()`'s own `@section Confusion risk`
#'       for the full interpretation). All three of
#'       `winner_species_confusion_risk`/`winner_genus_confusion_risk`/
#'       `winner_family_confusion_risk` are populated
#'       (where computable) regardless of `winner_hypothesis_type`;
#'       `winner_own_rank_confusion_risk` is a convenience pointer at whichever
#'       matches the winner's own resolved rank. `NA` when the source
#'       column is absent from `posterior_df` (e.g. any upstream call
#'       predating these columns) or when `consensus_taxon` is `NA`. Purely
#'       informational -- never changes `consensus_taxon`/`consensus_rank`.}
#'     \item{`consensus_confusion_risk`}{Numeric. The same confusion-risk
#'       quantity, but rank-matched to `consensus_rank` rather than to
#'       `primary_taxon`'s own rank (which is what
#'       `winner_own_rank_confusion_risk` reports). When the LCA has climbed
#'       to genus or family, the species-level value answers the wrong
#'       question -- this one asks "could a confamilial genus (or a different
#'       family) have scored this well", matching the rank actually being
#'       reported. `NA` when `consensus_rank` is `NA`, is coarser than family,
#'       or the corresponding source column is absent.}
#'     \item{`primary_n_plausible_competitors`,
#'       `consensus_n_plausible_competitors`}{Integer. How many
#'       locally-plausible RIVAL candidates this observation actually competed
#'       against -- the question a confusion-risk value structurally cannot
#'       answer, since it describes the marker's discriminating power for a
#'       taxon in the abstract and never sees this observation's candidate
#'       set. Read the two together: a low confusion risk means a relative
#'       *could not* have looked this good, while a non-zero competitor count
#'       means a plausible relative *was actually given the chance* to. A
#'       count of `0` with an otherwise clean-looking call is the signature of
#'       a reference-database representation gap -- the locally plausible
#'       relatives were never in the candidate pool at all, so no threshold
#'       applied to the existing candidates could have caught it.
#'       "Plausible" means the candidate carries a real occurrence record,
#'       read off `model_tier` (supplied by [join_priors()] from TaxaExpect
#'       priors) rather than off `prior_mean`'s value: a taxon never reported
#'       locally has `model_tier = NA`, while a genuine singleton has a real
#'       tier, even though both can share the same numeric floor prior.
#'       Counted over every named hypothesis for the observation, before
#'       `min_posterior`/`cumulative_threshold` filtering (a candidate that
#'       competed and lost still competed), and EXCLUDING the row's own taxon
#'       -- whether the winner itself is plausible is a prior-side question
#'       already answered by `winner_prior`. A count of `0` therefore means
#'       "nothing plausible to lose to", never "the winner is implausible".
#'       The `primary_` version counts rival taxa; the `consensus_` version
#'       counts distinct plausible groups at `consensus_rank` (rival genera
#'       when the LCA landed at genus, rival families at family), reducing to
#'       the `primary_` count at species rank. "Plausible" means "joined to
#'       a NAMED prior row": non-`NA` `prior_branch` when that column is
#'       present (kernel-priors schema, 2026-08-31 -- any branch counts,
#'       resident, undetected-evidence, or transport), else non-`NA`
#'       `model_tier` (legacy GLMM tables). Both are `NA` when
#'       `posterior_df` carries neither column.}
#'     \item{`winner_has_occurrence_record`, `consensus_prior`,
#'       `consensus_has_occurrence_record`}{Support for the
#'       prior/occurrence-plausibility axis, answering what `winner_prior`'s
#'       VALUE cannot: has this taxon ever been reported here at all? A
#'       never-reported taxon and a genuine singleton can carry the SAME
#'       numeric prior (both land on the dark-diversity floor) while meaning
#'       opposite things, so presence is read off the prior row's provenance
#'       rather than inferred from a low prior.
#'       `winner_has_occurrence_record` is `TRUE` when the winning
#'       hypothesis carries a real occurrence record. When `posterior_df`
#'       has a `prior_branch` column (kernel-priors schema, 2026-08-31) this
#'       means `prior_branch == "resident_observed"` -- a kernel estimate
#'       from real in-habitat local evidence; `resident_undetected`
#'       (evidence-elevated species with zero local records) and
#'       `transport` (domestic/food) winners read `FALSE`, with a transport
#'       winner's interpretation carried separately by
#'       `TaxaFlag::add_posthoc_assessment()`'s `domestic_prior_caveat`.
#'       Legacy GLMM tables (no `prior_branch`) keep the original
#'       non-`NA`-`model_tier` reading; `NA` when `posterior_df` has
#'       neither column.
#'       `consensus_prior` is a \code{theta_mean}-based group share
#'       (2026-07-30; previously \code{prior_mean} -- changed because
#'       \code{prior_mean} can be inflated by the confirmation boost above,
#'       which would let one confirmed-elsewhere candidate make its whole
#'       group look occurrence-expected regardless of real occurrence
#'       support). Requires `group_priors`: when supplied and it has a
#'       matching (`rank`, `taxon`) row for `consensus_rank`/
#'       `consensus_taxon`, this is the exact SUM of `theta_mean` across
#'       EVERY locally modelled member of the consensus taxon (see
#'       [compute_group_priors()]) -- records are mutually exclusive across
#'       taxa, so this is the group's true share by finite additivity, no
#'       independence assumption needed. `NA` when `group_priors` is not
#'       supplied, or has no matching row. There is deliberately no fallback
#'       to a candidate-scoped MAX (removed 2026-07-30) -- that value is a
#'       real underestimate on real data (e.g. Gobiidae: max 0.0164 vs. the
#'       true group sum 0.0313), not a safe approximation to degrade to
#'       silently.
#'       `consensus_has_occurrence_record` (2026-07-30, new) is the
#'       consensus-scope presence signal `consensus_prior`'s `NA` can no
#'       longer safely double as (fixed a real bug: `consensus_prior` is
#'       `NA` for two DIFFERENT reasons -- `group_priors` genuinely found no
#'       local member, OR `group_priors` was never supplied at all -- and a
#'       downstream consumer inferring "never reported" from `NA` alone
#'       could not tell them apart, misreading "not checked" as "confirmed
#'       absent"). `TRUE`/`FALSE` mean a real lookup against `group_priors`
#'       was performed and found/didn't find a matching group; `NA` means
#'       `group_priors` was not supplied (not checked at all).}
#'   }
#'
#' @seealso [assign_taxa_llm()], [compute_posterior()],
#'   [suggest_unreferenced_species()]
#'
#' @examples
#' posterior_df <- data.frame(
#'   observation_id = c("S1", "S1", "S1"),
#'   taxon_name = c("Gadus morhua", "Gadus chalcogrammus", "Gadus"),
#'   taxon_name_rank = c("species", "species", "genus"),
#'   hypothesis_type = "specific_candidate",
#'   genus = "Gadus",
#'   family = "Gadidae",
#'   posterior_mean = c(0.75, 0.20, 0.05),
#'   posterior_point_est = c(0.75, 0.20, 0.05)
#' )
#' consensus <- posterior_consensus(
#'   posterior_df,
#'   cumulative_threshold = 0.9,
#'   min_posterior = 0.05
#' )
#' consensus[, c("observation_id", "consensus_taxon", "consensus_rank", "is_resolved")]
#'
#' @importFrom cli cli_abort cli_inform cli_warn
#' @importFrom dplyr bind_rows
#' @importFrom stats setNames
#'
#' @export
posterior_consensus <- function(posterior_df,
                                rank_system = NULL,
                                cumulative_threshold = 0.9,
                                min_posterior = 0.05,
                                posterior_col = "posterior_point_est",
                                lookup_missing_taxonomy = FALSE,
                                backbone_id = NULL,
                                species_reference = NULL,
                                group_priors = NULL) {
  # --- Input validation -------------------------------------------------------
  required <- c(
    "observation_id", "taxon_name", "taxon_name_rank",
    "hypothesis_type", posterior_col
  )
  missing_cols <- setdiff(required, names(posterior_df))
  if (length(missing_cols) > 0) {
    cli::cli_abort("posterior_df missing required column(s): {.field {missing_cols}}")
  }
  if (!is.null(group_priors)) {
    if (!is.data.frame(group_priors)) {
      cli::cli_abort("{.arg group_priors} must be a data.frame (see {.fn compute_group_priors}) or NULL.")
    }
    missing_gp <- setdiff(c("rank", "taxon", "theta_sum"), names(group_priors))
    if (length(missing_gp) > 0) {
      cli::cli_abort("{.arg group_priors} missing required column(s): {.field {missing_gp}}")
    }
  }
  if (!is.numeric(cumulative_threshold) || length(cumulative_threshold) != 1L ||
    cumulative_threshold <= 0 || cumulative_threshold > 1) {
    cli::cli_abort("{.arg cumulative_threshold} must be a single number in (0, 1].")
  }
  if (!is.numeric(min_posterior) || length(min_posterior) != 1L ||
    min_posterior < 0 || min_posterior >= 1) {
    cli::cli_abort("{.arg min_posterior} must be a single number in [0, 1).")
  }
  if (!is.null(species_reference) &&
    !is.data.frame(species_reference) &&
    !inherits(species_reference, "unreferenced_species_result")) {
    cli::cli_abort(
      "{.arg species_reference} must be a data.frame, an \\
      {.cls unreferenced_species_result} object, or NULL."
    )
  }

  # --- Resolve rank system ----------------------------------------------------
  if (is.null(rank_system)) {
    rank_system_eff <- TaxaTools::detect_ranks(posterior_df)
  } else {
    # Keep user order but restrict to known standard ranks first; append others
    rank_system_eff <- rank_system
    # .find_lca()/.build_species_ref() infer coarsest/finest from POSITION --
    # warn if a user-supplied vector disagrees in order with the standard
    # Linnaean ranking, since that would silently swap "coarsest" and "finest".
    .check_rank_system_order(rank_system_eff, "posterior_consensus")
  }
  if (length(rank_system_eff) == 0L) {
    # detect_ranks() correctly returns character(0) when posterior_df has no
    # rank COLUMNS at all (e.g. TaxaLikely::evaluate_likelihoods()'s own
    # output, which only carries taxon_name/taxon_name_rank forward by
    # design) -- but .find_lca()/.build_species_ref() both index into
    # rank_system by position (rev(rank_system)[[1L]]) and error deep inside
    # with a cryptic "subscript out of bounds" rather than a clear message.
    # Found 2026-09-05 building diagnostics/fast_workflows/run_fast_smoketest.R.
    cli::cli_abort(c(
      "posterior_consensus: could not auto-detect any rank columns in \\
      {.arg posterior_df}, and no {.arg rank_system} was supplied.",
      "i" = "Pass {.arg rank_system} explicitly (e.g. {.code c(\"genus\", \"species\")}) \\
      -- this is expected for input from {.fn TaxaLikely::evaluate_likelihoods}, whose \\
      output does not carry kingdom..species columns forward."
    ))
  }

  # --- Optional taxonomy lookup for unreferenced rows -------------------------
  if (lookup_missing_taxonomy) {
    if (is.null(backbone_id)) {
      cli::cli_abort(c(
        "{.arg backbone_id} must be specified explicitly when \\
        {.arg lookup_missing_taxonomy} = TRUE.",
        "i" = "There is no safe default: the correct backbone depends on \\
        which backbone your input taxonomy was verified against, and this \\
        varies by project. Common values: {.val 11} (GBIF), {.val 4} (NCBI). \\
        See TaxaTools::verify_taxon_names()'s backbone_id docs, or \\
        https://verifier.globalnames.org/ for the full list."
      ))
    }
    if (!requireNamespace("TaxaTools", quietly = TRUE)) {
      cli::cli_warn(
        "TaxaTools not installed; skipping taxonomy lookup for unreferenced taxa."
      )
    } else {
      tax_cols_present <- intersect(rank_system_eff, names(posterior_df))
      if (length(tax_cols_present) > 0) {
        unref_mask <- posterior_df$hypothesis_type %in%
          c("unreferenced_species", "unreferenced_genus")
        needs_tax <- unref_mask &
          rowSums(is.na(posterior_df[, tax_cols_present, drop = FALSE])) > 0
        unref_names <- unique(posterior_df$taxon_name[needs_tax])
        if (length(unref_names) > 0) {
          cli::cli_inform(
            "Looking up taxonomy for {length(unref_names)} unreferenced taxon/taxa \\
            via TaxaTools::verify_taxon_names()..."
          )
          verified <- tryCatch(
            TaxaTools::verify_taxon_names(unref_names, backbone_id = backbone_id),
            error = function(e) {
              cli::cli_warn(
                "TaxaTools::verify_taxon_names() failed: {conditionMessage(e)}. \\
                Proceeding without taxonomy lookup."
              )
              NULL
            }
          )
          if (!is.null(verified)) {
            # change_backbone() parses the pipe-delimited classification_path /
            # classification_ranks into flat family/genus/species columns and
            # renames user_supplied_name to taxon_name for easy matching.
            verified_flat <- TaxaTools::change_backbone(
              verified,
              input_col          = "user_supplied_name",
              old_backbone_label = "taxon_name",
              new_backbone_label = "matched_name"
            )
            idx <- match(posterior_df$taxon_name, verified_flat$taxon_name)
            for (tc in intersect(tax_cols_present, names(verified_flat))) {
              fill <- needs_tax & !is.na(idx)
              if (!any(fill)) next
              posterior_df[[tc]][fill] <- verified_flat[[tc]][idx[fill]]
            }
          }
        }
      }
    }
  }

  # --- Process each observation ------------------------------------------------
  observation_ids <- unique(posterior_df$observation_id)
  cli::cli_inform(
    "Computing consensus taxonomy for {length(observation_ids)} observation(s)..."
  )

  results <- lapply(observation_ids, function(sid) {
    chunk <- posterior_df[posterior_df$observation_id == sid, ]
    .consensus_one_observation(
      chunk, sid, rank_system_eff,
      cumulative_threshold, min_posterior, posterior_col,
      group_priors
    )
  })

  result <- dplyr::bind_rows(results)

  # --- Optional downranking via species_reference -----------------------------
  if (!is.null(species_reference)) {
    species_ref <- .build_species_ref(species_reference, rank_system_eff)
    if (!is.null(species_ref)) {
      result <- .downrank_consensus(result, species_ref, rank_system_eff)
    }
  }

  attr(result, "report_params") <- list(
    cumulative_threshold = cumulative_threshold,
    min_posterior        = min_posterior,
    posterior_col        = posterior_col
  )
  result
}


# ==============================================================================
# Internal helpers
# ==============================================================================

#' Read a single-row data frame's column, or a default when the column is
#' absent (an optional upstream output, e.g. a source predating this column,
#' or posterior_df coming from assign_taxa_llm() rather than
#' compute_posterior()). Consolidates a pattern repeated ~8 times below for
#' the winner_* pass-through columns.
#' @noRd
.row_col_or <- function(row, col, default = NA_real_) {
  if (col %in% names(row)) row[[col]][[1L]] else default
}

#' Compute consensus for one observation
#' @noRd
.consensus_one_observation <- function(chunk, sid, rank_system,
                                       cumulative_threshold, min_posterior,
                                       posterior_col, group_priors = NULL) {
  # All named hypotheses contribute to LCA; only the unreferenced_family catch-all
  # is excluded (taxon_name = NA; represents uncharacterised diversity with no name).
  # named_all is kept before any filtering for consensus_posterior computation.
  named_all <- chunk[!is.na(chunk$taxon_name), ]

  prior_updated_flag <- if ("prior_updated" %in% names(chunk)) {
    any(chunk$prior_updated, na.rm = TRUE)
  } else {
    NULL
  }

  .empty_flagged <- function() {
    row <- .empty_consensus_row(sid)
    if (!is.null(prior_updated_flag)) row$prior_updated <- prior_updated_flag
    for (v1_col in c("consensus_taxon_v1", "consensus_rank_v1")) {
      if (v1_col %in% names(chunk)) {
        row[[v1_col]] <- chunk[[v1_col]][[1L]]
      }
    }
    if ("consensus_taxon_v1" %in% names(row)) {
      v1 <- row$consensus_taxon_v1
      row$taxon_changed <- !is.na(v1) # was assigned before, now unresolvable
    }
    row
  }


  if (nrow(named_all) == 0L) {
    cli::cli_warn(
      "observation_id {.val {sid}} has no named hypotheses (all rows have NA \\
      taxon_name or are unreferenced_family). Consensus is NA."
    )
    return(.empty_flagged())
  }

  # Apply minimum posterior filter (named_all preserved above for consensus_posterior)
  named <- named_all[named_all[[posterior_col]] >= min_posterior, ]
  if (nrow(named) == 0L) {
    cli::cli_warn(
      "observation_id {.val {sid}} has no hypotheses above min_posterior = \\
      {min_posterior}. All {nrow(named_all)} named hypothesis(es) are below \\
      threshold. Consider lowering min_posterior."
    )
    return(.empty_flagged())
  }

  # Sort descending by posterior
  named <- named[order(named[[posterior_col]], decreasing = TRUE), ]

  # Cumulative threshold within named-taxon posterior mass (post-filter)
  named_total <- sum(named[[posterior_col]], na.rm = TRUE)
  if (named_total == 0) {
    return(.empty_consensus_row(sid))
  }

  cum_prop <- cumsum(named[[posterior_col]]) / named_total
  n_include <- which(cum_prop >= cumulative_threshold)[1L]
  if (is.na(n_include)) n_include <- nrow(named)

  plausible <- named[seq_len(n_include), ]

  # Winner diagnostics: first row of plausible = highest-posterior hypothesis.
  # Extract prior and likelihood values; NA when the source column is absent
  # (e.g. when posterior_df comes from assign_taxa_llm() rather than compute_posterior()).
  winner_row <- plausible[1L, ]
  winner_prior <- .row_col_or(winner_row, "prior_mean")
  winner_likelihood <- .row_col_or(winner_row, "score_likelihood")
  winner_likelihood_cov <- .row_col_or(winner_row, "score_likelihood_cov")
  # winner_theta_mean (2026-07-30): the winner's raw occurrence-model share
  # (TaxaExpect::prepare_model_dataframe()'s theta_mean = n_species /
  # n_total_at_site, a compositional share of local records), distinct from
  # winner_prior (prior_mean), which can be substantially inflated by
  # TaxaAssign::update_prior_from_consensus()'s cross-observation confirmation
  # boost -- a different sample space entirely (see that function's own
  # "Rescaling onto the occurrence scale" section). Occurrence-plausibility
  # diagnostics below use this, not winner_prior, so a boost elsewhere in the
  # dataset cannot make an occurrence-implausible taxon read as "expected".
  winner_theta_mean <- .row_col_or(winner_row, "theta_mean")

  # Confusion-risk pass-through (TaxaLikely::evaluate_likelihoods()'s
  # species_confusion_risk/genus_confusion_risk/family_confusion_risk/
  # own_rank_confusion_risk -- a model-independent diagnostic read directly
  # off the actual winning row rather than recomputed here. Optional
  # upstream output: NA when the source column is
  # absent (e.g. any call predating these columns, or assign_taxa_llm()
  # input). Purely informational -- never changes consensus_taxon/
  # consensus_rank. See TaxaFlag::add_posthoc_assessment()'s confusion-risk
  # wiring for how a downstream consumer reads these.
  winner_species_confusion_risk <- .row_col_or(winner_row, "species_confusion_risk")
  winner_genus_confusion_risk <- .row_col_or(winner_row, "genus_confusion_risk")
  winner_family_confusion_risk <- .row_col_or(winner_row, "family_confusion_risk")
  winner_own_rank_confusion_risk <- .row_col_or(winner_row, "own_rank_confusion_risk")

  # winner_rank_expanded (Session 149): TRUE when the winning hypothesis came
  # from join_priors()'s coarse-rank expansion (.expand_coarse_rank_rows()),
  # i.e. every expanded candidate for that coarse-rank identification shares
  # one inherited, uninformative likelihood -- so this species-level winner
  # was decided entirely by occurrence-prior mass, not by any sequence/image/
  # acoustic evidence discriminating between the candidates. This is
  # intentional, sound behavior (using priors to resolve an otherwise-coarse
  # ID), but a downstream consumer treating every species-level consensus_taxon
  # as equally evidence-supported would be wrong to do so for these rows --
  # see ecosystem_docs/STATISTICAL_COMPONENT_SOUNDNESS_REVIEW.md.
  winner_hypothesis_type <- as.character(.row_col_or(winner_row, "hypothesis_type", NA_character_))
  winner_rank_expanded <- if (is.na(winner_hypothesis_type)) {
    NA
  } else {
    identical(winner_hypothesis_type, "rank_expanded")
  }

  # LCA among plausible hypotheses
  lca <- .find_lca(plausible, rank_system)

  # --- Discrimination diagnostics (2026-07-27) ----------------------------
  # Two questions the winner_*_confusion_risk columns above cannot answer on
  # their own, because a confusion-risk value describes the marker's
  # discriminating power for that taxon in the abstract and never sees this
  # observation's actual candidate set:
  #   1. Could a relative have looked this good?       -> *_confusion_risk
  #   2. Did any plausible relative actually compete?  -> the counts below
  # Read together they separate "won a real contest" from "won by default
  # because nothing locally plausible was ever in the running" -- the latter
  # being a reference-database representation gap, not evidence of a good
  # match, and not something any threshold on the existing candidates can
  # detect (see the Sciaenidae case in
  # TaxaFlag/REENTRY_PROMPT_axis2_multifactor_diagnostic_redesign.md).
  #
  # "Plausible" is read off `model_tier` (supplied upstream by join_priors()
  # from TaxaExpect priors), NOT off prior_mean's value: a taxon with no local
  # occurrence record at all has `model_tier = NA`, while a genuine singleton
  # has a real tier -- even though both can share the same numeric floor
  # prior. That is exactly the "never reported here" vs "reported once"
  # distinction, and prior_mean alone cannot express it. Absent column ->
  # NA, matching the optional-upstream-output contract used by the
  # confusion-risk pass-throughs.
  #
  # Counted over `named_all` (every named hypothesis for this observation),
  # not the post-filter `plausible` set -- a candidate that competed and lost
  # still competed. Same reasoning as consensus_posterior below, which also
  # uses named_all so the value is independent of min_posterior and
  # cumulative_threshold.
  #
  # The row's OWN taxon is excluded from its own count. Whether the winner
  # itself is plausible is a prior-side question already answered by
  # winner_prior; keeping that separate from "how many plausible rivals did it
  # beat" is deliberate, so the two read as independent signals. A count of 0
  # therefore means "nothing plausible to lose to", never "the winner is
  # implausible".
  has_tier <- "model_tier" %in% names(named_all)
  # Kernel-priors schema (2026-08-31): `prior_branch` supersedes `model_tier`
  # when present. "Plausible" here means "joined to a NAMED prior row" (any
  # branch -- resident, undetected-evidence, or transport); a row that fell
  # through to the anonymous dark-diversity floor has NA in both columns.
  # Kernel tables carry model_tier only as a legacy column on their
  # undetected/domestic rows (NA on every resident row), so reading
  # model_tier there is exactly inverted -- confirmed on real GreatLakes
  # kernel output (86 locally-evidenced resident rows all NA-tier).
  has_branch <- "prior_branch" %in% names(named_all)
  has_plaus <- has_branch || has_tier
  plaus_mask <- if (has_branch) {
    !is.na(named_all$prior_branch)
  } else if (has_tier) {
    !is.na(named_all$model_tier)
  } else {
    NULL
  }

  # taxon_name is a required column (checked at input validation), unlike the
  # winner_* pass-throughs above, so no presence check is needed here.
  winner_taxon <- as.character(winner_row$taxon_name[[1L]])

  primary_n_plausible_competitors <- if (has_plaus) {
    others <- if (is.na(winner_taxon)) {
      rep(TRUE, nrow(named_all))
    } else {
      is.na(named_all$taxon_name) | named_all$taxon_name != winner_taxon
    }
    as.integer(sum(plaus_mask & others, na.rm = TRUE))
  } else {
    NA_integer_
  }

  # Consensus-scoped version: distinct plausible groups at the LCA's own rank,
  # excluding the consensus taxon itself. At species rank this reduces to the
  # primary count; at genus/family it counts rival genera/families, which is
  # the rank-appropriate reading of "did it compete".
  consensus_n_plausible_competitors <- if (has_plaus && !is.na(lca$rank) && !is.na(lca$taxon)) {
    grp <- .extract_rank_values(named_all, lca$rank)
    if (is.null(grp)) {
      NA_integer_
    } else {
      ok <- plaus_mask & !is.na(grp) & grp != lca$taxon
      as.integer(length(unique(grp[which(ok)])))
    }
  } else {
    NA_integer_
  }

  # --- Occurrence-plausibility support (2026-07-28) -----------------------
  # Two columns supporting the prior/occurrence-plausibility axis, which asks
  # a question `winner_prior`'s VALUE cannot answer on its own: has this taxon
  # ever been reported here at all?
  #
  # A taxon that has never been reported and a genuine singleton can carry the
  # SAME numeric prior -- both land on the dark-diversity floor -- but they
  # mean opposite things ("no evidence it occurs here" vs "recorded once").
  # `model_tier` separates them: it is populated only for taxa with a real
  # occurrence record, and is NA for a candidate that fell through to the
  # floor or to a hierarchical dark-diversity group prior. Verified on real
  # Mugu data: 0 of 1014 floor-prior rows carry a tier, while 547 rows have no
  # tier yet a prior ABOVE the floor (one reaching 0.975, because its
  # dark-diversity group had only 3 members) -- so thresholding the prior
  # value alone would call a never-reported taxon "expected". Hence a separate
  # presence signal rather than a lower cutoff.
  # Under the kernel-priors schema, "has occurrence record" narrows to the
  # resident_observed branch: a kernel estimate from real, in-habitat local
  # evidence. resident_undetected (floor/evidence-blend rows -- species with
  # ZERO local records, elevated by regional/watch/iNat evidence) and
  # transport (domestic/food) winners correctly read FALSE: under the legacy
  # model_tier logic those legacy-columned rows read TRUE while every
  # genuinely evidenced resident row read FALSE -- fully inverted (real
  # GreatLakes B8 run: 873/885 "unprecedented"). A transport winner's
  # interpretation is carried separately by add_posthoc_assessment()'s
  # domestic_prior_caveat, which is the designed pairing.
  winner_has_occurrence_record <- if (has_branch) {
    isTRUE(winner_row$prior_branch[[1L]] == "resident_observed")
  } else if (has_tier) {
    !is.na(winner_row$model_tier[[1L]])
  } else {
    NA
  }
  # `consensus_prior`: the occurrence-model share for the consensus GROUP,
  # not just its candidates. NA when nothing qualifies -- so NA doubles as
  # the consensus-scope "never reported" signal, needing no separate logical.
  #
  # Reads `theta_mean`, NOT `prior_mean` (changed 2026-07-30). `prior_mean`
  # can be substantially inflated by `update_prior_from_consensus()`'s
  # cross-observation confirmation boost -- confirmed on real Mugu data: all
  # 220 `prior_mean >= 0.5` rows in one real dataset were boosts, and the
  # boost's own natural scale is a posterior probability (bounded ~1), not an
  # occurrence share (observed ceiling 0.0865 on that dataset). Reading
  # `prior_mean` here would let one confirmed-elsewhere candidate make its
  # whole consensus group look occurrence-expected regardless of any real
  # occurrence support. `theta_mean` is immune to that boost by construction.
  #
  # Requires `group_priors` (2026-07-30, from `compute_group_priors()`): the
  # exact SUM of `theta_mean` over every locally modelled member of the
  # consensus taxon at its own rank -- not just this observation's own
  # candidates, which is all a candidate-scoped MAX could ever see. Records
  # are mutually exclusive across taxa, so a group's true share is the exact
  # sum of its members' shares -- no independence assumption needed (unlike
  # a noisy-OR combination, the wrong model for a compositional share).
  #
  # `NA` when `group_priors` is not supplied, or has no matching (rank,
  # taxon) row -- deliberately NOT a silent fallback to the old
  # candidate-scoped MAX (removed 2026-07-30): that value is a real
  # underestimate (confirmed on real data, e.g. Gobiidae max=0.0164 vs the
  # true group sum 0.0313), and returning it silently when the caller hasn't
  # supplied `group_priors` would misrepresent an incomplete computation as
  # a complete one.
  # `consensus_has_occurrence_record`: the consensus-scope analogue of
  # `winner_has_occurrence_record`, and the fix for a real bug found
  # 2026-07-30 -- `add_posthoc_assessment()` previously inferred "has a
  # record" from whether `consensus_prior` was `NA`, which conflated two
  # different situations `consensus_prior` alone cannot distinguish:
  # `group_priors` was never supplied (unknown), vs. `group_priors` was
  # supplied and genuinely found no local member (confirmed absent). On real
  # production data (no workflow supplies `group_priors` yet),
  # `consensus_prior` is `NA` for every row for the FIRST reason, and the old
  # inference read every row as confirmed-absent ("unprecedented") --
  # `consensus_plausibility` read `"unprecedented"` for all 616 real rows.
  # `NA` here means "not checked" (matches `winner_has_occurrence_record`'s
  # own `NA`-when-`model_tier`-absent convention); `TRUE`/`FALSE` mean a real
  # lookup was performed and found/didn't find a matching group.
  consensus_prior <- NA_real_
  consensus_has_occurrence_record <- NA
  if (!is.null(group_priors) && !is.na(lca$rank) && !is.na(lca$taxon)) {
    gp_row <- group_priors[group_priors$rank == lca$rank & group_priors$taxon == lca$taxon, , drop = FALSE]
    consensus_has_occurrence_record <- nrow(gp_row) > 0L
    if (nrow(gp_row) > 0L) consensus_prior <- gp_row$theta_sum[[1L]]
  }

  # Confusion risk matched to the CONSENSUS rank, rather than to
  # primary_taxon's own rank (which is what winner_own_rank_confusion_risk
  # reports). When the LCA has climbed to genus or family, the species-level
  # value is answering the wrong question.
  consensus_confusion_risk <- {
    cr_col <- switch(as.character(lca$rank),
      species = "species_confusion_risk",
      genus   = "genus_confusion_risk",
      family  = "family_confusion_risk",
      NA_character_
    )
    if (!is.na(cr_col) && cr_col %in% names(winner_row)) {
      winner_row[[cr_col]][[1L]]
    } else {
      NA_real_
    }
  }

  finest_rank <- rank_system[length(rank_system)]
  is_resolved <- !is.na(lca$rank) && lca$rank == finest_rank
  consensus_reason <- lca$consensus_reason

  # consensus_posterior: sum of named posterior values within the LCA taxon.
  # Posteriors are probabilities so the raw sum IS the probability of the LCA
  # taxon -- no denominator is needed (full probability space = 1.0).
  # We use named_all (pre-filter) as the source so the value is independent of
  # min_posterior and cumulative_threshold. Rows may have been filtered after
  # compute_posterior(), so the present rows may not sum to 1; summing directly
  # avoids the divide-by-present-rows trap (which always returns 1.0 for
  # single-hypothesis observations).
  rank_vals_all <- if (!is.na(lca$rank) && !is.na(lca$taxon)) {
    .extract_rank_values(named_all, lca$rank)
  } else {
    NULL
  }

  in_lca <- if (!is.null(rank_vals_all)) {
    !is.na(rank_vals_all) & rank_vals_all == lca$taxon
  } else {
    NULL
  }

  consensus_posterior <- if (!is.null(in_lca)) {
    sum(named_all[[posterior_col]][in_lca], na.rm = TRUE)
  } else {
    NA_real_
  }

  # consensus_confidence_score: sum of confidence_score for in-LCA hypotheses.
  # confidence_score (from compute_posterior()) = fraction of MC simulations
  # where that hypothesis produced the highest posterior. Summing over in-LCA
  # hypotheses gives the fraction of simulations where the consensus taxon won.
  # Only available when posterior_df contains a confidence_score column.
  consensus_confidence_score <- if (!is.null(in_lca) &&
    "confidence_score" %in% names(named_all)) {
    sum(named_all$confidence_score[in_lca], na.rm = TRUE)
  } else {
    NA_real_
  }

  out <- data.frame(
    observation_id = sid,
    consensus_taxon = lca$taxon,
    consensus_rank = lca$rank,
    consensus_reason = consensus_reason,
    is_resolved = is_resolved,
    consensus_posterior = consensus_posterior,
    consensus_confidence_score = consensus_confidence_score,
    n_plausible = n_include,
    winner_prior = winner_prior,
    winner_theta_mean = winner_theta_mean,
    winner_likelihood = winner_likelihood,
    winner_likelihood_cov = winner_likelihood_cov,
    winner_hypothesis_type = winner_hypothesis_type,
    winner_rank_expanded = winner_rank_expanded,
    winner_species_confusion_risk = winner_species_confusion_risk,
    winner_genus_confusion_risk = winner_genus_confusion_risk,
    winner_family_confusion_risk = winner_family_confusion_risk,
    winner_own_rank_confusion_risk = winner_own_rank_confusion_risk,
    consensus_confusion_risk = consensus_confusion_risk,
    primary_n_plausible_competitors = primary_n_plausible_competitors,
    consensus_n_plausible_competitors = consensus_n_plausible_competitors,
    winner_has_occurrence_record = winner_has_occurrence_record,
    consensus_prior = consensus_prior,
    consensus_has_occurrence_record = consensus_has_occurrence_record,
    plausible_taxa = I(list(plausible$taxon_name)),
    plausible_posteriors = I(list(stats::setNames(
      plausible[[posterior_col]], plausible$taxon_name
    ))),
    stringsAsFactors = FALSE
  )

  # Propagate pass-through columns added by update_prior_from_consensus().
  # prior_updated: any row TRUE means the observation was updated.
  # consensus_taxon_v1 / consensus_rank_v1: constant within observation — take first value.
  if ("prior_updated" %in% names(chunk)) {
    out$prior_updated <- any(chunk$prior_updated, na.rm = TRUE)
  }

  for (v1_col in c("consensus_taxon_v1", "consensus_rank_v1")) {
    if (v1_col %in% names(chunk)) {
      out[[v1_col]] <- chunk[[v1_col]][[1L]]
    }
  }

  # Derive taxon_changed when v1 columns are present
  if (all(c("consensus_taxon_v1") %in% names(out))) {
    v1 <- out$consensus_taxon_v1
    cur <- out$consensus_taxon
    out$taxon_changed <- !is.na(v1) & (is.na(cur) | cur != v1)
  }

  out
}


#' Find the LCA among plausible hypothesis rows
#'
#' Returns a list with `taxon`, `rank`, and `consensus_reason`.
#' Possible reasons: `"unanimous"` (all agree at finest rank),
#' `"lca"` (upranked because candidates disagree at finer ranks),
#' `"single"` (only one hypothesis in the plausible set).
#' @noRd
.find_lca <- function(plausible, rank_system) {
  if (nrow(plausible) == 0L) {
    return(list(
      taxon = NA_character_, rank = NA_character_,
      consensus_reason = NA_character_
    ))
  }
  if (nrow(plausible) == 1L) {
    return(list(
      taxon = plausible$taxon_name[[1L]],
      rank = plausible$taxon_name_rank[[1L]],
      consensus_reason = "single"
    ))
  }

  finest_rank <- rev(rank_system)[[1L]]

  # Walk finest to coarsest; stop at first rank where all agree
  for (rk in rev(rank_system)) {
    vals <- .extract_rank_values(plausible, rk)
    if (all(!is.na(vals)) && length(unique(vals)) == 1L) {
      reason <- if (rk == finest_rank) "unanimous" else "lca"
      return(list(
        taxon = vals[[1L]], rank = rk,
        consensus_reason = reason
      ))
    }
  }

  list(
    taxon = NA_character_, rank = NA_character_,
    consensus_reason = NA_character_
  )
}


#' Extract rank values from a hypothesis dataframe, deriving where possible
#'
#' Uses an explicit column when present; derives genus from a species binomial
#' when the genus column is absent, and derives species from `taxon_name`
#' when the species column is absent (Session 152 -- see the species branch's
#' own comment for why this was missing and what it silently broke). All
#' other missing columns return NA.
#' @noRd
.extract_rank_values <- function(input_df, rank) {
  if (rank == "genus") {
    # Derive genus from binomial as fallback for any NA values
    derived <- ifelse(
      input_df$taxon_name_rank == "species", sub(" .*", "", input_df$taxon_name),
      ifelse(input_df$taxon_name_rank == "genus", input_df$taxon_name, NA_character_)
    )
    if (rank %in% names(input_df)) {
      vals <- as.character(input_df[[rank]])
      return(ifelse(is.na(vals), derived, vals))
    }
    return(derived)
  }

  if (rank == "species") {
    # Derive species from taxon_name as fallback for any NA values --
    # taxon_name IS the species-level value whenever taxon_name_rank ==
    # "species" (the binomial itself), mirroring the genus derivation above.
    # Session 152: this branch was missing entirely (fell through to the
    # generic "explicit column required" case below, returning all-NA
    # whenever no literal "species" column existed) -- TaxaLikely's real
    # sequence/BLAST pathway never produces one (only taxon_name/family/
    # genus), so consensus_posterior/consensus_confidence_score silently
    # computed to exactly 0 for every single-hypothesis resolved observation
    # on that pathway, even though the winning candidate's own posterior_mean
    # was correctly high. consensus_taxon itself was unaffected (.find_lca()'s
    # nrow(plausible) == 1 shortcut reads taxon_name/taxon_name_rank directly,
    # bypassing this function), which is why the bug was invisible unless the
    # confidence columns were checked specifically. Found via a real end-to-end
    # Template run using this exact data shape.
    #
    # This trusts taxon_name_rank == "species" to mean taxon_name really is a
    # full binomial (not, say, a bare genus mislabeled "species"). That
    # contract is enforced upstream, not re-checked here: e.g.
    # TaxaMatch::convert_taxonomy_backbone() corrects taxon_name_rank
    # whenever a row's taxon_name falls back to a coarser resolved name
    # (see that package's "Inu Inu" fabricated-pseudo-binomial fix). The same
    # genus-derivation branch above makes the identical assumption for
    # taxon_name_rank == "genus".
    derived <- ifelse(input_df$taxon_name_rank == "species", input_df$taxon_name, NA_character_)
    if (rank %in% names(input_df)) {
      vals <- as.character(input_df[[rank]])
      return(ifelse(is.na(vals), derived, vals))
    }
    return(derived)
  }

  if (rank %in% names(input_df)) {
    return(as.character(input_df[[rank]]))
  }

  # All other ranks require an explicit column
  rep(NA_character_, nrow(input_df))
}


#' Return an empty consensus row for unresolvable observations
#' @noRd
.empty_consensus_row <- function(sid) {
  data.frame(
    observation_id = sid,
    consensus_taxon = NA_character_,
    consensus_rank = NA_character_,
    consensus_reason = NA_character_,
    is_resolved = FALSE,
    consensus_posterior = NA_real_,
    consensus_confidence_score = NA_real_,
    n_plausible = 0L,
    winner_prior = NA_real_,
    winner_theta_mean = NA_real_,
    winner_likelihood = NA_real_,
    winner_likelihood_cov = NA_real_,
    winner_hypothesis_type = NA_character_,
    winner_rank_expanded = NA,
    winner_species_confusion_risk = NA_real_,
    winner_genus_confusion_risk = NA_real_,
    winner_family_confusion_risk = NA_real_,
    winner_own_rank_confusion_risk = NA_real_,
    consensus_confusion_risk = NA_real_,
    primary_n_plausible_competitors = NA_integer_,
    consensus_n_plausible_competitors = NA_integer_,
    winner_has_occurrence_record = NA,
    consensus_prior = NA_real_,
    consensus_has_occurrence_record = NA,
    plausible_taxa = I(list(character(0))),
    plausible_posteriors = I(list(stats::setNames(numeric(0), character(0)))),
    stringsAsFactors = FALSE
  )
}


#' Normalise species_reference to a plain data.frame
#'
#' Accepts either an unreferenced_species_result (extracts attr "plausible" and
#' derives genus from binomial) or a data.frame (returned as-is after column
#' check). Returns NULL with a warning if the reference is empty or unusable.
#' @noRd
.build_species_ref <- function(x, rank_system) {
  finest_rank <- rank_system[length(rank_system)]

  if (inherits(x, "unreferenced_species_result")) {
    plausible <- attr(x, "plausible")
    if (is.null(plausible) || length(plausible) == 0L) {
      cli::cli_warn(
        "species_reference has an empty {.field plausible} attribute; \\
        skipping downranking."
      )
      return(NULL)
    }
    # Derive genus from binomial (first word); sufficient for genus -> species step.
    return(data.frame(
      taxon_name = plausible,
      genus = sub(" .*", "", plausible),
      stringsAsFactors = FALSE
    ))
  }

  # data.frame path: must have taxon_name (or finest rank col) + at least one
  # coarser rank column so there is something to look up against.
  has_finest <- "taxon_name" %in% names(x) || finest_rank %in% names(x)
  if (!has_finest) {
    cli::cli_warn(
      "species_reference data.frame has no {.field taxon_name} or \\
      {.field {finest_rank}} column; skipping downranking."
    )
    return(NULL)
  }
  x
}


#' Downrank coarse-rank consensus rows when species_reference has exactly one
#' finer taxon for the consensus taxon
#'
#' Operates row-by-row on the consensus data.frame returned by
#' posterior_consensus(). For each unresolved row whose consensus_rank is not
#' the finest rank, walks down through rank_system: at each step, counts the
#' distinct finer-rank taxa in species_ref that belong to the current taxon.
#' If exactly one, downranks and continues. Stops at any rank with zero or
#' more than one option (conservative). Updates consensus_taxon, consensus_rank,
#' is_resolved, and downranked in place.
#' @noRd
.downrank_consensus <- function(consensus_df, species_ref, rank_system) {
  finest_rank <- rank_system[length(rank_system)]

  # Map a rank name to its column in species_ref.
  # For the finest rank, prefer "taxon_name" (TaxaExpect / plausible convention)
  # then fall back to the rank name itself.
  .ref_col <- function(rk) {
    if (rk == finest_rank) {
      if ("taxon_name" %in% names(species_ref)) {
        return("taxon_name")
      }
      if (rk %in% names(species_ref)) {
        return(rk)
      }
      return(NA_character_)
    }
    if (rk %in% names(species_ref)) {
      return(rk)
    }
    NA_character_
  }

  consensus_df$downranked <- FALSE

  for (i in seq_len(nrow(consensus_df))) {
    if (isTRUE(consensus_df$is_resolved[i])) next
    cur_rank <- consensus_df$consensus_rank[i]
    cur_taxon <- consensus_df$consensus_taxon[i]
    if (is.na(cur_rank) || is.na(cur_taxon)) next
    if (cur_rank == finest_rank) next

    rank_idx <- match(cur_rank, rank_system)
    if (is.na(rank_idx) || rank_idx >= length(rank_system)) next

    changed <- FALSE

    for (j in seq(rank_idx + 1L, length(rank_system))) {
      finer_rank <- rank_system[j]
      coarse_col <- .ref_col(cur_rank)
      finer_col <- .ref_col(finer_rank)

      if (is.na(coarse_col) || is.na(finer_col)) break

      candidates <- species_ref[
        !is.na(species_ref[[coarse_col]]) &
          species_ref[[coarse_col]] == cur_taxon, ,
        drop = FALSE
      ]

      finer_vals <- unique(candidates[[finer_col]])
      finer_vals <- finer_vals[!is.na(finer_vals)]

      if (length(finer_vals) != 1L) break # 0 or >1 options — stop

      cur_rank <- finer_rank
      cur_taxon <- finer_vals[[1L]]
      changed <- TRUE
    }

    if (changed) {
      consensus_df$consensus_taxon[i] <- cur_taxon
      consensus_df$consensus_rank[i] <- cur_rank
      consensus_df$is_resolved[i] <- (cur_rank == finest_rank)
      consensus_df$downranked[i] <- TRUE
    }
  }

  consensus_df
}
