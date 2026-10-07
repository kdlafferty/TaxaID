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
#' mass, then returns their lowest common ancestor (LCA) as the consensus
#' taxonomic assignment. Hypotheses below `min_posterior` are excluded, or,
#' with `pool_tail = TRUE`, pooled into one tail block that joins the set when
#' the hypotheses above it fall short (see \emph{Details}).
#'
#' **Which hypotheses are included:** All named hypotheses contribute to the
#' LCA -- `"specific_candidate"`, `"unreferenced_species"` (congener without reference
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
#' @param min_posterior Numeric in \[0, 1). Individual posterior below which a
#'   hypothesis cannot enter the plausible set on its own. Default 0.05. Set to
#'   0 to disable. What happens to those hypotheses depends on `pool_tail`.
#' @param posterior_col Character. Name of the posterior column to rank
#'   hypotheses by. Default `"posterior_point_est"`, matching
#'   `run_bayesian_pipeline()` and every production workflow. An
#'   operative-column comparison found the choice second-order for real
#'   consensus results and settled on point estimates: best external
#'   corroboration, deterministic, and exactly auditable as prior x
#'   likelihood products. Pass `"posterior_mean"` to rank by the
#'   Monte Carlo mean instead -- with presence-mixture priors that column
#'   integrates over presence states (see `compute_posterior()`).
#' @param pool_tail Logical. `FALSE` (default): hypotheses below
#'   `min_posterior` are excluded and `cumulative_threshold` is measured against
#'   the remaining mass. `TRUE`: they form one tail block, the threshold is
#'   measured against the TOTAL named posterior mass, and the whole block joins
#'   the plausible set when the hypotheses above the floor fall short. See
#'   \emph{Details}. `tail_mass` is reported either way.
#' @param unnamed_in_threshold Logical (default `TRUE`). Posterior on rows
#'   with no `taxon_name` (a catch-all whose position has no name, e.g. an
#'   unsequenced genus of a family recorded only as a placeholder) cannot join
#'   the LCA but is mass the call does not hold. `TRUE` counts it in the
#'   denominator of `cumulative_threshold`, and an observation whose named
#'   hypotheses cannot reach the threshold of the total is reported
#'   unresolved (`consensus_reason = "unnamed_mass"`). `FALSE` measures the
#'   threshold against named mass only. `unnamed_mass` is reported either way.
#'   Applies to `consensus_method = "lca"`; `"credible_node"` always keeps
#'   every row in the denominator.
#' @param consensus_method `"lca"` (default) or `"credible_node"`. `"lca"`
#'   takes the smallest top set of hypotheses reaching `cumulative_threshold`
#'   and reports their lowest common taxon. `"credible_node"` sums the
#'   posterior of every hypothesis under each taxon, rank by rank from the
#'   finest, and reports the finest taxon holding at least
#'   `cumulative_threshold` of the total posterior of ALL rows; no hypothesis
#'   is dropped below `min_posterior`, and a hypothesis named at a coarser
#'   rank (an unsequenced genus of a family, say) counts toward that taxon and
#'   its ancestors. Each row counts toward the (rank, name) nodes its own
#'   lineage carries: a row with no value at a rank (a backbone with no class
#'   for ray-finned fishes, say) joins no node there but stays in the
#'   denominator, and no rank is ever imputed. Rows with no `taxon_name` count
#'   in the denominator only. A node is identified by its (rank, name), so
#'   rows sharing a name must share one lineage (a homonym, or one taxon
#'   labelled on two backbones, would pool); `lineage_conflict` reports any
#'   name an observation's rows use with two lineages. Requires
#'   `cumulative_threshold` above 0.5, where a credible node is unique.
#'   `rank_system` may run up to `"phylum"` and
#'   `"kingdom"` when those columns are present. Unresolved
#'   (`consensus_reason = "no_credible_node"`) when no node at any rank in
#'   `rank_system` holds the threshold. Why a call is coarser than the finest
#'   rank is reported in `consensus_limit`.
#' @param likelihood_consensus Logical (default `TRUE`). Also compute the
#'   consensus the likelihoods support when the prior is flattened among the
#'   named candidates (each gets the mean of their priors; generic
#'   unsequenced-relative rows keep their own; uniform when there is no
#'   `prior_mean`), same consensus method and
#'   `cumulative_threshold`, `min_posterior` and `pool_tail`, no downranking)
#'   and compare it with the reported call. Adds `likelihood_consensus_taxon`,
#'   `likelihood_consensus_rank`, `prior_role` and `likelihood_support`;
#'   changes no other column. Skipped (columns `NA`) when `posterior_df` has
#'   no `score_likelihood` column. See \emph{Sequence support}.
#' @param robust_prior_s Numeric (default `1`; `0` turns it off). Used with
#'   `consensus_method = "credible_node"`. The occurrence prior is estimated
#'   from finitely many records, so a node is reported only if its posterior
#'   stays at or above `cumulative_threshold` for every prior within an
#'   imprecise-Dirichlet neighbourhood of the estimated one: `s` additional
#'   records of unknown species (Walley 1996; Walley's recommended range is
#'   1-2), against the site's record concentration `N`: the
#'   `prior_site_records` column from [join_priors()] when present, else the
#'   median `alpha + beta` of the observation's kernel-estimated rows (never
#'   floor or dark-diversity rows, whose `alpha + beta` are pseudo-counts). A
#'   call is kept only if it survives `s` further records of the best-fitting
#'   taxon outside it. A call the sequence decides by a wide margin is
#'   unaffected; a marginal call whose candidates carry priors worth only a
#'   few records is coarsened even when the outside taxon fits somewhat
#'   worse, because one record then moves the prior noticeably. The bound is
#'   reported as `robust_lower_posterior`. Skipped (plain credible node) when
#'   `score_likelihood`, `prior_mean`, `prior_alpha` or `prior_beta` is
#'   missing, or when no record count is available.
#' @param cross_phylum_eps Numeric in `[0, 0.5)` (default `0.05`; `0` turns
#'   it off). Used with `consensus_method = "credible_node"`. When the
#'   runner-up phylum holds at least this share of an observation's total
#'   posterior, a call at phylum or finer would rest on a choice between
#'   phyla that the evidence barely makes (typically a low-identity sequence
#'   whose best candidates from two phyla score almost alike). Such a call is
#'   withheld: the call becomes the finest node coarser than phylum in
#'   `rank_system` that holds `cumulative_threshold` (a clade both phyla
#'   share, e.g. a kingdom), or no call when `rank_system` has none, and
#'   `consensus_limit` is `"cross_phylum"`. The share is the plain posterior
#'   share (the robust-prior check does not change it). The value is an error
#'   tolerance: smaller withholds more calls. Applied in the likelihood-only
#'   pass too, so `prior_role` compares calls made under the same rule. Not
#'   applied (with a message) when `rank_system` has no `"phylum"` carried by
#'   `posterior_df`.
#' @param taxonomy_cache_dir Character or `NULL` (default). Passed to
#'   [TaxaTools::verify_taxon_names()] as `cache_dir` when
#'   `lookup_missing_taxonomy = TRUE`: answered lookups are cached so a re-run
#'   reproduces the same labels instead of depending on whether the service
#'   answered this time. Failed lookups are never cached.
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
#'   4 = NCBI, 9 = WoRMS, 11 = GBIF. See
#'   `TaxaTools::verify_taxon_names()` for the full backbone list.
#'   Ignored (may be left `NULL`) when `lookup_missing_taxonomy = FALSE`.
#' @param species_reference Optional. A plausible-species reference used to
#'   downrank unresolved coarse-rank consensus assignments. Accepts two forms:
#'   \itemize{
#'     \item \strong{`unreferenced_species_result`} (from
#'       [TaxaLikely::suggest_unreferenced_species()]): the full LLM-generated plausible
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
#'   consensus taxon. If exactly one, it downranks (recursively -- e.g. family
#'   to unique genus to unique species in one pass). Stops at any rank with
#'   more than one option. Default `NULL` (no downranking). A narrowing must
#'   also survive `downrank_requires_candidate`. Callers
#'   building `species_reference` from a mix of observed and evidence-only
#'   rows should still exclude the evidence-only ones
#'   (`prior_branch != "kernel_estimated"`) before passing it in, so a
#'   downrank reflects a species this observation could plausibly have
#'   produced, not merely one that is locally plausible in the abstract.
#' @param downrank_requires_candidate Logical. When `TRUE` (default), a
#'   downranking step is taken only if the reference's single finer taxon is
#'   at or above a taxon this observation actually scored (its
#'   `plausible_taxa`). A narrowing to a coarser-than-finest rank is kept when
#'   the candidates belong to it (family to genus *Ulva* when the candidates
#'   are *Ulva* species), so this is a taxonomy test, not a string match. Rows
#'   with no `plausible_taxa` column, or an empty one, are not gated. `FALSE`
#'   disables this check, so the reference alone decides. Measured across
#'   four production sites without this gate: 35 of 150 downranked rows
#'   named a taxon outside their own candidate set.
#' @param group_priors Optional data frame from [compute_group_priors()]
#'   (`rank`/`taxon`/`theta_sum`/`n_members` columns), the SUM of
#'   `theta_mean` over every locally modelled member of a genus or family --
#'   not just the candidates one observation's own evidence happened to
#'   surface. Drives `consensus_prior` when a matching (`rank`, `taxon`) row
#'   exists for an observation's `consensus_rank`/`consensus_taxon` (see that
#'   column's own docs below for the full reasoning). Default `NULL`:
#'   `consensus_prior` is `NA` for every row -- there is no fallback
#'   computation, since a candidate-scoped MAX would be a real underestimate,
#'   not a safe approximation.
#' @param min_effective_records Numeric, >= 0. Minimum `effective_records` a
#'   winning row must carry before `winner_has_occurrence_record` is allowed
#'   to read `TRUE`. Default `0` -- branch membership alone decides.
#'
#'   Why this exists: `TaxaExpect::estimate_kernel_priors()` writes
#'   `prior_branch` as a CONSTANT on every row it emits, so the branch records
#'   which generator made the row, never how much evidence stands behind it.
#'   Within that one branch `effective_records` spans roughly ten orders of
#'   magnitude -- on the real PtConception 12S priors, 215 of 479 labelled
#'   rows (44.9%) carried under one Kish effective record, minimum 0.0000; at
#'   18S, 987 of 1521 (64.9%); at GreatLakes only 17 of 90 (18.9%). Reading
#'   the label as an evidence claim therefore reports a quarter to two thirds
#'   of rows as having a local occurrence record on effectively no records at
#'   all, and that verdict feeds the published Axis-1 plausibility categories
#'   via `TaxaFlag::add_posthoc_assessment()`.
#'
#'   No threshold is defaulted ON because there is no natural one: the
#'   distribution is continuous with no valley, so any cutoff is a judgment
#'   call that moves rows between plausibility categories and must be
#'   validated before it is trusted. One Kish effective record is the
#'   defensible starting point if you want one. Changing it from `0` WILL
#'   move `winner_has_occurrence_record`, and therefore the plausibility
#'   counts -- re-run the held-out GreatLakes/Lamar check (current benchmark:
#'   precision 0.872) before relying on the result.
#' @details
#' \strong{Threshold interaction:}
#' \code{min_posterior} and \code{cumulative_threshold} work together. By
#' default the hypotheses below \code{min_posterior} are excluded and the
#' plausible set is the smallest top-ranked set holding
#' \code{cumulative_threshold} of the REMAINING mass. The excluded mass is
#' reported as \code{tail_mass}: a call can rest on a small share of the total
#' (a lone hypothesis at 0.13 beside twenty at 0.02--0.03 is reported as a
#' species, with \code{tail_mass} 0.87).
#'
#' With \code{pool_tail = TRUE} the excluded hypotheses are pooled instead:
#' the hypotheses above the floor are added until they hold
#' \code{cumulative_threshold} of the TOTAL named mass, and when they fall
#' short the whole tail block joins the plausible set, so the consensus is the
#' LCA of everything in it (\code{tail_pooled = TRUE}). A single noise-level
#' hypothesis still cannot coarsen a call on its own, but a flat tail holding
#' most of the mass is no longer renormalised away. This changes the meaning of
#' the threshold (a call at 0.6 with 0.4 below the floor no longer resolves
#' alone), so re-check a validation set before adopting it. Measured on
#' CalIntertidal: species calls 544 to 475 on one subset, including 52 calls
#' with posterior 0.5--0.9. \code{cumulative_threshold = 0.9} is analogous to a
#' 90% credible interval; increase toward 0.95--0.99 for more conservative
#' assignments (more upranking to genus/family); decrease to 0.8 for more
#' aggressive species-level calls.
#'
#' \strong{Parameter sensitivity:} a grid sweep against a real posterior
#' dataset (see the \code{posterior_threshold_sweep.R} diagnostic, TaxaID_dev
#' repository) found the two
#' defaults are not equally load-bearing: \code{min_posterior} has a real,
#' roughly linear effect on how often the pipeline resolves to the finest
#' rank, while \code{cumulative_threshold} does comparatively little
#' independent work once a reasonable \code{min_posterior} floor is already
#' in place. The two interact sharply only in the unrealistic combination of
#' \code{min_posterior = 0} with a very high \code{cumulative_threshold}.
#' This sweep measures resolution \emph{rate}, not \emph{accuracy} -- no
#' ground-truth-validated observation set was available, so a higher
#' resolved-% is not itself evidence those calls are correct.
#'
#' \strong{LCA method:}
#' Lowest Common Ancestor is the standard conservative consensus method in
#' molecular systematics (Huson et al., 2007, MEGAN). The implementation
#' walks from finest to coarsest rank and stops at the first rank where all
#' plausible hypotheses agree.
#'
#' \strong{Why a sole perfect-identity candidate can still be wrong:} H2/H3
#' (`unreferenced_species`/`unreferenced_genus`) hypotheses exist for every
#' query, but their likelihood sits a fixed, training-derived shift below the
#' best H1 candidate's -- so when H1 has a sole candidate at full identity,
#' no amount of locally-informed prior competition can move the call away
#' from it: H2/H3 start too far behind to catch up regardless of how
#' implausible the H1 candidate is ecologically. Ecological implausibility at
#' that confidence has to be caught post hoc, by
#' `TaxaFlag::review_assignments()`'s `plausibility == "unprecedented"` check,
#' not by prior competition inside this function.
#'
#' @section Defaults:
#' A setting that corrects a defect defaults on; one that chooses between
#' defensible rules is opt-in until its trade is measured.
#' `unnamed_in_threshold = TRUE` is a correction: leaving unnamed mass out of
#' the denominator makes `cumulative_threshold` mean something other than it
#' says. `pool_tail` and `consensus_method = "credible_node"` are choices of
#' rule, so they default off (`FALSE`, `"lca"`).
#'
#' @section Sequence support:
#' The posterior multiplies the likelihood by an occurrence prior, so a
#' reported taxon can be one the sequence evidence alone does not single
#' out: when several candidates match equally well, the prior picks among
#' them. That is the intended use of a prior, but the reader of a species
#' list needs to know which calls rest on the sequence and which on where the
#' species is known to occur. With `likelihood_consensus = TRUE` the call is
#' compared with a baseline in which the named candidates' priors are
#' flattened (each gets their mean) while generic unsequenced-relative rows
#' keep their own priors. `likelihood_support` is the share of that baseline
#' in the reported taxon: 0.84 means the sequence nearly makes the call
#' itself and the prior nudged it over `cumulative_threshold`; 0.10 means
#' the prior chose it. `prior_role` records the direction (`"agrees"`,
#' `"narrowed"`, `"broadened"`, `"changed"`). Neither changes the call: in a
#' clade with one local species the prior legitimately concentrates the
#' posterior on it, which is correct inference, so sequence support is
#' reported, not used to move calls.
#'
#' A support above 0.5 means the reported taxon is more probable on the
#' sequence evidence than every alternative combined (named priors
#' flattened); unnamed and generic mass that no named taxon contains counts
#' against every taxon. The gap between the posterior (which clears
#' `cumulative_threshold`) and `likelihood_support` is the part of the call
#' that rests on the prior.
#'
#' @return A dataframe with one row per `observation_id`:
#'   \describe{
#'     \item{`observation_id`}{Sample identifier (same type as input).}
#'     \item{`consensus_taxon`}{Name of the LCA taxon, or `NA` if unresolvable
#'       (all hypotheses excluded or no rank agrees).}
#'     \item{`unreferenced_taxonomy_lookup`}{Character. Outcome of the
#'       taxonomy lookup for this observation's unreferenced hypotheses when
#'       `lookup_missing_taxonomy = TRUE`: `"matched"`, `"not_found"` (the
#'       service answered and had no match) or `"lookup_failed"` (it could
#'       not be asked -- the label may differ on a re-run); the worst outcome
#'       when there are several. `NA` when nothing needed looking up. A filter
#'       for `== "matched"` never keeps a failure.}
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
#'       `NA` when `consensus_taxon` is `NA`. When `downranked = TRUE` this is
#'       the mass of the coarser rank that was actually resolved, not a
#'       re-estimate at the finer reported rank; gate any confidence-threshold
#'       filter on `downranked`.}
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
#'     \item{`n_plausible`}{Number of hypotheses in the plausible set,
#'       including the members of a pooled tail block (0 when there is no
#'       named hypothesis).}
#'     \item{`tail_mass`}{Summed posterior of the hypotheses below
#'       `min_posterior`: how much mass sat in the tail block.}
#'     \item{`lineage_conflict`}{Character. Names that the observation's
#'       own rows use with two different lineages, as `"rank:name"` joined by
#'       `"; "` (e.g. `"genus:Porella"` for a bryozoan and a liverwort genus
#'       of that name, or one genus whose order is labelled two ways); `NA`
#'       when there is none. Such a node pools what may be two taxa; the
#'       inputs should give each name one lineage. Reported only: never
#'       changes a call.}
#'     \item{`consensus_limit`}{With `consensus_method = "credible_node"`:
#'       why the call is coarser than the finest rank in `rank_system` (NA when
#'       it is not coarser). `"backbone"`: at some finer rank, rows resolved
#'       to that rank or finer but with no value there (a gap in their
#'       lineage) hold enough posterior that a node could have reached the
#'       threshold had their lineage been complete. `"robust_prior"`: the
#'       call would be finer without the robust-prior check
#'       (`robust_prior_s`). `"threshold"`: the posterior is spread across
#'       named alternatives at every finer rank. `"rank_not_supplied"`: the
#'       only finer rank that could have given a call is one no row of
#'       `posterior_df` carries at all (the column is absent or empty
#'       throughout); the rank was never provided, which differs from
#'       `"backbone"`, where it is missing from some lineages (e.g. a backbone
#'       with no class for ray-finned fishes). A message names such ranks.
#'       `"cross_phylum"`: a call at phylum or finer was withheld because the
#'       runner-up phylum holds at least `cross_phylum_eps` of the posterior;
#'       the call is the finest coarser node holding the threshold, or none.}
#'     \item{`robust_lower_posterior`}{With `consensus_method =
#'       "credible_node"` and `robust_prior_s > 0`: the lower bound of the
#'       reported taxon's posterior over the imprecise-prior neighbourhood
#'       (see `robust_prior_s`). `NA` otherwise.}
#'     \item{`unnamed_mass`}{Posterior on rows with no `taxon_name`. Not part
#'       of `tail_mass`, which covers named hypotheses only.}
#'     \item{`tail_pooled`}{`TRUE` when the tail block joined the plausible
#'       set because the hypotheses above `min_posterior` held less than
#'       `cumulative_threshold` of the total mass.}
#'     \item{`likelihood_consensus_taxon`, `likelihood_consensus_rank`}{The
#'       call the likelihoods alone support (uniform priors). `NA` when
#'       `likelihood_consensus = FALSE` or there is no `score_likelihood`.}
#'     \item{`prior_role`}{How the prior moved the call relative to the
#'       likelihood-only call: `"agrees"` (same taxon), `"narrowed"` (a finer
#'       taxon inside the likelihood-only call, or a call where the
#'       likelihoods alone made none), `"broadened"` (a coarser taxon
#'       containing it, or no call where the likelihoods made one) or
#'       `"changed"` (a taxon outside it, or nesting that could not be
#'       verified). `NA` when neither pass made a call.}
#'     \item{`likelihood_support`}{Share of the baseline (sequence evidence,
#'       named candidates' priors flattened) that falls in the reported
#'       taxon: how close the sequence alone comes to the call. A call at
#'       posterior 0.92 with support 0.84 was nudged over the threshold by the
#'       prior; one with support 0.10 was chosen by it.}
#'     \item{`plausible_taxa`}{List column: character vector of plausible taxon
#'       names, sorted by descending posterior. Computed BEFORE downranking, so
#'       for a downranked row it reflects the original coarser-rank plausible
#'       set and may not include the downranked species itself.}
#'     \item{`plausible_posteriors`}{List column: named numeric vector of
#'       posterior values for plausible taxa (names = taxon_name). Same
#'       pre-downranking timing as `plausible_taxa` above.}
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
#'       read off `prior_branch` (supplied by [join_priors()] from TaxaExpect
#'       priors) rather than off `prior_mean`'s value: a taxon never reported
#'       locally has `prior_branch = NA`, while a genuine singleton has a real
#'       branch, even though both can share the same numeric floor prior.
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
#'       a NAMED prior row": non-`NA` `prior_branch` (any branch counts,
#'       resident, undetected-evidence, or transport). `NA` when
#'       `posterior_df` carries no `prior_branch` column at all -- i.e. no
#'       prior table was ever joined. A `model_tier` column with no
#'       `prior_branch` column is an error: it identifies a prior table
#'       predating the kernel-priors schema, which this function no longer
#'       reads.}
#'     \item{`winner_has_occurrence_record`, `consensus_prior`,
#'       `consensus_has_occurrence_record`}{Support for the
#'       prior/occurrence-plausibility axis, answering what `winner_prior`'s
#'       VALUE cannot: has this taxon ever been reported here at all? A
#'       never-reported taxon and a genuine singleton can carry the SAME
#'       numeric prior (both land on the dark-diversity floor) while meaning
#'       opposite things, so presence is read off the prior row's provenance
#'       rather than inferred from a low prior.
#'       `winner_has_occurrence_record` is `TRUE` when the winning
#'       hypothesis carries a real occurrence record: `prior_branch` is
#'       `"kernel_estimated"` -- a kernel estimate from real in-habitat local
#'       evidence; `resident_undetected` (evidence-elevated species with zero
#'       local records) and `transport` (domestic/food) winners read `FALSE`,
#'       with a transport winner's interpretation carried separately by
#'       `TaxaFlag::add_posthoc_assessment()`'s `domestic_prior_caveat`.
#'       `NA` when `posterior_df` carries no `prior_branch` column. A
#'       `model_tier` column with no `prior_branch` column is an error (see
#'       above).
#'       `consensus_prior` is a \code{theta_mean}-based group share, not
#'       \code{prior_mean}, because \code{prior_mean} can be inflated by the
#'       confirmation boost above, which would let one confirmed-elsewhere
#'       candidate make its whole group look occurrence-expected regardless
#'       of real occurrence support. Requires `group_priors`: when supplied and it has a
#'       matching (`rank`, `taxon`) row for `consensus_rank`/
#'       `consensus_taxon`, this is the exact SUM of `theta_mean` across
#'       EVERY locally modelled member of the consensus taxon (see
#'       [compute_group_priors()]) -- records are mutually exclusive across
#'       taxa, so this is the group's true share by finite additivity, no
#'       independence assumption needed. `NA` when `group_priors` is not
#'       supplied, or has no matching row. There is deliberately no fallback
#'       to a candidate-scoped MAX -- that value is a
#'       real underestimate on real data (e.g. Gobiidae: max 0.0164 vs. the
#'       true group sum 0.0313), not a safe approximation to degrade to
#'       silently.
#'       `consensus_has_occurrence_record` is the
#'       consensus-scope presence signal that `consensus_prior`'s `NA` cannot
#'       safely double as: `consensus_prior` is
#'       `NA` for two DIFFERENT reasons -- `group_priors` genuinely found no
#'       local member, OR `group_priors` was never supplied at all -- and a
#'       downstream consumer inferring "never reported" from `NA` alone
#'       could not tell them apart, misreading "not checked" as "confirmed
#'       absent". `TRUE`/`FALSE` mean a real lookup against `group_priors`
#'       was performed and found/didn't find a matching group; `NA` means
#'       `group_priors` was not supplied (not checked at all).}
#'   }
#'
#' @seealso [assign_taxa_llm()], [compute_posterior()],
#'   [TaxaLikely::suggest_unreferenced_species()]
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
#' # A non-DNA posterior table (e.g. from an image classifier's candidates)
#' # consensuses the same way -- there is no sequence/image/acoustic evidence
#' # bearing on the LCA computation itself.
#' posterior_df_image <- data.frame(
#'   observation_id = c("IMG_1", "IMG_1"),
#'   taxon_name = c("Puma concolor", "Lynx rufus"),
#'   taxon_name_rank = "species",
#'   hypothesis_type = "specific_candidate",
#'   genus = c("Puma", "Lynx"),
#'   family = "Felidae",
#'   posterior_mean = c(0.85, 0.10),
#'   posterior_point_est = c(0.85, 0.10)
#' )
#' consensus_image <- posterior_consensus(
#'   posterior_df_image,
#'   cumulative_threshold = 0.9,
#'   min_posterior = 0.05
#' )
#' consensus_image[, c("observation_id", "consensus_taxon", "consensus_rank", "is_resolved")]
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
                                downrank_requires_candidate = TRUE,
                                group_priors = NULL,
                                min_effective_records = 0,
                                taxonomy_cache_dir = NULL,
                                pool_tail = FALSE,
                                unnamed_in_threshold = TRUE,
                                consensus_method = c("lca", "credible_node"),
                                likelihood_consensus = TRUE,
                                robust_prior_s = 1,
                                cross_phylum_eps = 0.05) {
  consensus_method <- match.arg(consensus_method)
  if (!is.numeric(cross_phylum_eps) || length(cross_phylum_eps) != 1L ||
    is.na(cross_phylum_eps) || cross_phylum_eps < 0 || cross_phylum_eps >= 0.5) {
    cli::cli_abort("{.arg cross_phylum_eps} must be a single number in [0, 0.5) (0 turns it off).")
  }
  if (!is.logical(pool_tail) || length(pool_tail) != 1L || is.na(pool_tail)) {
    cli::cli_abort("{.arg pool_tail} must be TRUE or FALSE.")
  }
  if (!is.logical(unnamed_in_threshold) || length(unnamed_in_threshold) != 1L ||
    is.na(unnamed_in_threshold)) {
    cli::cli_abort("{.arg unnamed_in_threshold} must be TRUE or FALSE.")
  }
  if (!is.numeric(robust_prior_s) || length(robust_prior_s) != 1L ||
    is.na(robust_prior_s) || robust_prior_s < 0) {
    cli::cli_abort("{.arg robust_prior_s} must be a single non-negative number (0 turns it off).")
  }
  if (!is.logical(likelihood_consensus) || length(likelihood_consensus) != 1L ||
    is.na(likelihood_consensus)) {
    cli::cli_abort("{.arg likelihood_consensus} must be TRUE or FALSE.")
  }
  if (!is.numeric(min_effective_records) ||
    length(min_effective_records) != 1L ||
    is.na(min_effective_records) || min_effective_records < 0) {
    cli::cli_abort(
      "{.arg min_effective_records} must be a single non-negative number."
    )
  }
  # --- Input validation -------------------------------------------------------
  required <- c(
    "observation_id", "taxon_name", "taxon_name_rank",
    "hypothesis_type", posterior_col
  )
  missing_cols <- setdiff(required, names(posterior_df))
  if (length(missing_cols) > 0) {
    cli::cli_abort("posterior_df missing required column(s): {.field {missing_cols}}")
  }
  posterior_df <- .blank_ranks_to_na(posterior_df)
  # A model_tier column with no prior_branch column identifies a prior table
  # from before the kernel-priors schema. posterior_consensus() no longer
  # reads model_tier as a fallback for a missing prior_branch: kernel tables
  # carry model_tier only as a legacy column on their undetected/domestic
  # rows (NA on every resident row), so reading model_tier in prior_branch's
  # place is exactly inverted (confirmed on real GreatLakes kernel output: 86
  # locally-evidenced resident rows all NA-tier).
  if ("model_tier" %in% names(posterior_df) && !"prior_branch" %in% names(posterior_df)) {
    cli::cli_abort(c(
      "posterior_df has a {.field model_tier} column but no \\
      {.field prior_branch} column.",
      "i" = "This is a prior table from before the kernel-priors schema, \\
      which {.fn posterior_consensus} no longer reads.",
      "i" = "Regenerate the priors with \\
      {.fn TaxaExpect::estimate_kernel_priors} (and, if used, \\
      {.code apply_undetected_evidence()} / \\
      {.code generate_domestic_food_priors()}), which write prior_branch \\
      alongside model_tier."
    ))
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
  if (consensus_method == "credible_node" && cumulative_threshold <= 0.5) {
    # Two disjoint nodes can both hold half the mass, so the credible node is
    # unique only above 0.5; at or below it the call would depend on row order.
    cli::cli_abort("{.arg cumulative_threshold} must exceed 0.5 with {.code consensus_method = \"credible_node\"}: a credible node is unique only above one half.")
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
  # Ranks in rank_system that no row of the input carries (the column is
  # absent or empty throughout): no call can resolve there, and a call held
  # coarse by such a rank is stamped "rank_not_supplied", not "backbone".
  # message(), not a warning: Rscript defers warnings to exit.
  unsupplied <- rank_system_eff[vapply(rank_system_eff, function(r) {
    v <- .extract_rank_values(posterior_df, r, rank_system_eff)
    is.null(v) || all(is.na(v))
  }, logical(1))]
  if (length(unsupplied) > 0L) {
    message(sprintf(
      "posterior_consensus: rank_system includes %s, but no row of posterior_df carries a value there; no call can resolve at that rank, and calls held coarse by it are stamped consensus_limit = \"rank_not_supplied\".",
      paste(sprintf("\"%s\"", unsupplied), collapse = ", ")
    ))
  }
  # The cross-phylum rule needs phylum values; say so when it cannot apply.
  if (consensus_method == "credible_node" && cross_phylum_eps > 0 &&
    (!"phylum" %in% rank_system_eff || "phylum" %in% unsupplied)) {
    message("posterior_consensus: cross_phylum_eps is not applied: rank_system has no \"phylum\" carried by posterior_df.")
  }
  if (length(rank_system_eff) == 0L) {
    # detect_ranks() correctly returns character(0) when posterior_df has no
    # rank COLUMNS at all (e.g. TaxaLikely::evaluate_likelihoods()'s own
    # output, which only carries taxon_name/taxon_name_rank forward by
    # design) -- but .find_lca()/.build_species_ref() both index into
    # rank_system by position (rev(rank_system)[[1L]]) and error deep inside
    # with a cryptic "subscript out of bounds" rather than a clear message.
    cli::cli_abort(c(
      "posterior_consensus: could not auto-detect any rank columns in \\
      {.arg posterior_df}, and no {.arg rank_system} was supplied.",
      "i" = "Pass {.arg rank_system} explicitly (e.g. {.code c(\"genus\", \"species\")}) \\
      -- this is expected for input from {.fn TaxaLikely::evaluate_likelihoods}, whose \\
      output does not carry kingdom..species columns forward."
    ))
  }

  # --- Optional taxonomy lookup for unreferenced rows -------------------------
  # Per looked-up name: "matched", "not_found" (the service answered, no
  # match) or "lookup_failed" (it could not be asked). Reported per
  # observation below so a failed lookup can never pass for a genuine
  # absence of taxonomy.
  lookup_status <- character(0L)
  lookup_needed <- NULL
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
        unref_mask <- .is_unreferenced_type(posterior_df$hypothesis_type)
        needs_tax <- unref_mask &
          rowSums(is.na(posterior_df[, tax_cols_present, drop = FALSE])) > 0
        unref_names <- unique(posterior_df$taxon_name[needs_tax])
        if (length(unref_names) > 0) {
          cli::cli_inform(
            "Looking up taxonomy for {length(unref_names)} unreferenced taxon/taxa \\
            via TaxaTools::verify_taxon_names()..."
          )
          lookup_needed <- needs_tax
          verified <- tryCatch(
            {
              # cache_dir is passed ONLY when one was asked for. Passing it
              # unconditionally makes this call fail against a TaxaTools that
              # predates the argument, and the failure arrives as
              # "lookup_failed" on every row, which reads as a service outage
              # rather than as a version mismatch. The default path must not
              # require a matching TaxaTools.
              args <- list(unref_names, backbone_id = backbone_id)
              if (!is.null(taxonomy_cache_dir)) args$cache_dir <- taxonomy_cache_dir
              do.call(TaxaTools::verify_taxon_names, args)
            },
            error = function(e) {
              cli::cli_warn(
                "TaxaTools::verify_taxon_names() failed: {conditionMessage(e)}. \\
                Proceeding without taxonomy lookup."
              )
              NULL
            }
          )
          lookup_status <- stats::setNames(rep("lookup_failed", length(unref_names)), unref_names)
          if (!is.null(verified)) {
            v <- verified[match(unref_names, verified$user_supplied_name), , drop = FALSE]
            ok <- !is.na(v$verified) & v$verified
            matched <- if ("matched" %in% names(v)) v$matched %in% TRUE else ok & !is.na(v$matched_name)
            lookup_status[ok] <- ifelse(matched[ok], "matched", "not_found")
          }
          n_failed <- sum(lookup_status == "lookup_failed")
          if (n_failed > 0L) {
            # message() as well as a warning: Rscript defers warnings to exit,
            # and this is what someone watching a long run needs to see now.
            msg <- sprintf(
              "posterior_consensus: taxonomy lookup FAILED for %d of %d unreferenced taxon/taxa; their observations carry unreferenced_taxonomy_lookup = \"lookup_failed\" (not \"not_found\") and may label differently on a re-run.",
              n_failed, length(unref_names)
            )
            message(msg)
            cli::cli_warn(msg)
          }
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
              # fill only cells that are empty: a lookup must never replace
              # a rank value the row already has (nor blank it with NA)
              fill <- needs_tax & !is.na(idx) & is.na(posterior_df[[tc]]) &
                !is.na(verified_flat[[tc]][idx])
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

  # Each observation's rows, found ONCE by splitting the row indices (original
  # row order kept) instead of scanning every row per observation: the same
  # chunk, in O(N) rather than O(N x observations). NA ids keep the original
  # path, where `==` selects differently.
  row_idx <- if (anyNA(observation_ids)) NULL else
    split(seq_len(nrow(posterior_df)), factor(posterior_df$observation_id, levels = observation_ids))
  results <- lapply(seq_along(observation_ids), function(i) {
    sid <- observation_ids[[i]]
    chunk <- if (is.null(row_idx)) posterior_df[posterior_df$observation_id == sid, ] else
      posterior_df[row_idx[[i]], ]
    .consensus_one_observation(
      chunk, sid, rank_system_eff,
      cumulative_threshold, min_posterior, posterior_col,
      group_priors, min_effective_records, pool_tail, unnamed_in_threshold,
      consensus_method, robust_prior_s, unsupplied, cross_phylum_eps
    )
  })

  result <- dplyr::bind_rows(results)

  # Worst lookup outcome among each observation's looked-up hypotheses:
  # lookup_failed > not_found > matched; NA when nothing needed looking up.
  result$unreferenced_taxonomy_lookup <- NA_character_
  if (length(lookup_status) > 0L && !is.null(lookup_needed)) {
    st <- unname(lookup_status[posterior_df$taxon_name])
    st[!lookup_needed] <- NA_character_
    rank_of <- c(matched = 1L, not_found = 2L, lookup_failed = 3L)
    worst <- tapply(rank_of[st], posterior_df$observation_id, function(x) {
      x <- x[!is.na(x)]
      if (length(x)) names(rank_of)[max(x)] else NA_character_
    })
    result$unreferenced_taxonomy_lookup <- as.character(unname(worst[as.character(result$observation_id)]))
  }

  # --- Optional downranking via species_reference -----------------------------
  if (!is.null(species_reference)) {
    species_ref <- .build_species_ref(species_reference, rank_system_eff)
    if (!is.null(species_ref)) {
      result <- .downrank_consensus(
        result, species_ref, rank_system_eff,
        require_candidate = downrank_requires_candidate
      )
    }
  }

  result <- .add_prior_role(
    result, posterior_df, rank_system_eff, likelihood_consensus,
    cumulative_threshold, min_posterior, pool_tail,
    unnamed_in_threshold, consensus_method, cross_phylum_eps
  )

  attr(result, "report_params") <- list(
    cumulative_threshold = cumulative_threshold,
    min_posterior        = min_posterior,
    posterior_col        = posterior_col,
    cross_phylum_eps     = cross_phylum_eps
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
# Deepest credible node, on each row's own (rank, name) ancestry. A node is a
# (rank, name) pair; a row adds its weight to every node it actually carries
# (a hypothesis named at a coarser rank, e.g. an unsequenced genus of family X,
# counts toward X and its ancestors only) and to none at a rank where its
# lineage has no value. No rank is imputed, and a row lacking a rank stays in
# the denominator as a non-member of every node at that rank. Rows without a
# name have no defined place in the tree: they count in the denominator only.
# The first node, finest rank first, holding at least `threshold` of the total
# is returned. With eps > 0 a node's share is its lower posterior over the
# eps-contamination class around the prior (see .credible_node_robust()).
#
# `limit` says why a call is not at the finest rank of `rank_system` (NA when
# it is): "backbone" when, at some finer rank, the best node plus the weight of
# rows that are resolved to that rank or finer but carry no value there would
# reach the threshold although the node alone does not (a complete lineage
# could have given a finer call); "robust_prior" takes precedence when the
# plain rule (eps = 0) would have called a finer node; "rank_not_supplied"
# when the only such ranks are in `unsupplied` (ranks no row of the whole
# input carries: the rank was never provided, so no lineage is incomplete);
# otherwise "threshold" (the weight is spread across named alternatives).
.credible_node <- function(chunk, w, rank_system, threshold, eps = 0, L = NULL,
                           unsupplied = character(0), cross_phylum_eps = 0) {
  out <- list(taxon = NA_character_, rank = NA_character_, lower = NA_real_, limit = NA_character_)
  w[is.na(w) | w < 0] <- 0
  tot <- sum(w)
  if (!is.finite(tot) || tot <= 0) return(out)
  if (eps > 0) L[is.na(L) | L < 0] <- 0
  named <- !is.na(chunk$taxon_name)
  row_depth <- if ("taxon_name_rank" %in% names(chunk)) match(chunk$taxon_name_rank, rank_system) else rep(NA_integer_, nrow(chunk))
  share <- function(inn, e) {
    if (e <= 0) return(sum(w[inn]) / tot)
    Ls <- if (any(!inn)) max(L[!inn]) else 0
    (1 - e) * sum(w[inn]) / ((1 - e) * tot + e * Ls)
  }
  vals <- lapply(rank_system, function(r) {
    v <- .extract_rank_values(chunk, r, rank_system)
    if (is.null(v)) v <- rep(NA_character_, nrow(chunk))
    v[!named] <- NA_character_
    v
  })
  best_at <- function(i, e) {
    v <- vals[[i]]
    nodes <- unique(v[!is.na(v)])
    if (!length(nodes)) return(list(node = NA_character_, p = 0))
    p <- vapply(nodes, function(nd) share(!is.na(v) & v == nd, e), numeric(1))
    b <- which.max(p)
    list(node = nodes[b], p = unname(p[b]))
  }
  call_i <- NA_integer_
  for (i in rev(seq_along(rank_system))) {
    b <- best_at(i, eps)
    if (b$p >= threshold) {
      call_i <- i
      out$taxon <- b$node
      out$rank <- rank_system[i]
      if (eps > 0) out$lower <- b$p
      break
    }
  }
  # Cross-phylum rule: a call at phylum or finer is withheld when the
  # runner-up phylum holds at least cross_phylum_eps of the total (plain
  # shares). The call moves to the finest node COARSER than phylum that holds
  # the threshold (a clade both phyla share, when rank_system has one), else
  # no call.
  ph_i <- match("phylum", rank_system)
  if (cross_phylum_eps > 0 && !is.na(call_i) && !is.na(ph_i) && call_i >= ph_i) {
    v <- vals[[ph_i]]
    ph_share <- sort(vapply(unique(v[!is.na(v)]), function(nd) sum(w[!is.na(v) & v == nd]) / tot, numeric(1)),
      decreasing = TRUE)
    if (length(ph_share) >= 2L && ph_share[[2L]] >= cross_phylum_eps) {
      out$taxon <- NA_character_
      out$rank <- NA_character_
      out$lower <- NA_real_
      for (i in rev(seq_len(ph_i - 1L))) {
        b <- best_at(i, eps)
        if (b$p >= threshold) {
          out$taxon <- b$node
          out$rank <- rank_system[i]
          if (eps > 0) out$lower <- b$p
          break
        }
      }
      out$limit <- "cross_phylum"
      return(out)
    }
  }
  finer <- if (is.na(call_i)) seq_along(rank_system) else seq_len(length(rank_system))[-seq_len(call_i)]
  if (!length(finer)) return(out)
  plain <- lapply(finer, best_at, e = 0)
  backbone <- vapply(seq_along(finer), function(k) {
    i <- finer[k]
    gap <- named & is.na(vals[[i]]) & (is.na(row_depth) | row_depth >= i)
    plain[[k]]$p < threshold && any(gap) && plain[[k]]$p + sum(w[gap]) / tot >= threshold
  }, logical(1))
  not_supplied <- rank_system[finer] %in% unsupplied
  out$limit <- if (eps > 0 && any(vapply(plain, function(b) b$p >= threshold, logical(1)))) {
    "robust_prior"
  } else if (any(backbone & !not_supplied)) {
    "backbone"
  } else if (any(backbone & not_supplied)) {
    "rank_not_supplied"
  } else {
    "threshold"
  }
  out
}

# Likelihood-only consensus and the prior's role in the reported call.
# The likelihood pass reuses .consensus_one_observation() on each
# observation's score_likelihood normalised to sum to 1 (uniform priors),
# with no group_priors and no downranking, so the two calls differ only by
# the prior. Its per-observation warnings repeat the main pass's and are
# muffled.
.add_prior_role <- function(result, posterior_df, rank_system, enabled,
                            cumulative_threshold, min_posterior, pool_tail,
                            unnamed_in_threshold = TRUE, consensus_method = "lca",
                            cross_phylum_eps = 0) {
  result$likelihood_consensus_taxon <- NA_character_
  result$likelihood_consensus_rank <- NA_character_
  result$prior_role <- NA_character_
  result$likelihood_support <- NA_real_
  if (!enabled || !"score_likelihood" %in% names(posterior_df) || nrow(result) == 0L) {
    return(result)
  }
  # Baseline: the prior flattened AMONG THE NAMED CANDIDATES only (each gets
  # the mean of their priors), generic unsequenced-relative rows keeping
  # their own. The question is whether the prior chose between named species
  # or moved the rank -- not whether the complement would win under a flat
  # prior, which it nearly always would. Without prior_mean: uniform.
  lik <- posterior_df$score_likelihood
  lik[is.na(lik) | lik < 0] <- 0
  w <- lik
  if ("prior_mean" %in% names(posterior_df)) {
    pr <- posterior_df$prior_mean
    pr[is.na(pr) | pr < 0] <- 0
    spec <- posterior_df$hypothesis_type %in% "specific_candidate"
    spec_mean <- stats::ave(ifelse(spec, pr, NA_real_), posterior_df$observation_id,
      FUN = function(v) rep(mean(v, na.rm = TRUE), length(v)))
    pr_flat <- ifelse(spec & is.finite(spec_mean), spec_mean, pr)
    w <- lik * pr_flat
  }
  tot <- stats::ave(w, posterior_df$observation_id, FUN = sum)
  posterior_df$.lik_post <- ifelse(tot > 0, w / tot, 0)
  # split.data.frame() is lapply(split(seq_len(n), f), function(i) x[i, , drop = FALSE]):
  # keep the index split and take each chunk when it is used, the same object
  # without a full-width copy of posterior_df held in memory.
  chunk_idx <- split(seq_len(nrow(posterior_df)), posterior_df$observation_id)
  chunk_of <- function(sid) {
    i <- chunk_idx[[sid]]
    if (is.null(i)) NULL else posterior_df[i, , drop = FALSE]
  }
  ids <- as.character(result$observation_id)
  lik_rows <- suppressWarnings(lapply(ids, function(sid) {
    ch <- chunk_of(sid)
    if (is.null(ch)) return(.empty_consensus_row(sid))
    .consensus_one_observation(
      ch, sid, rank_system, cumulative_threshold, min_posterior,
      ".lik_post", NULL, 0, pool_tail, unnamed_in_threshold, consensus_method,
      cross_phylum_eps = cross_phylum_eps
    )
  }))
  result$likelihood_consensus_taxon <- vapply(lik_rows, function(r) as.character(r$consensus_taxon[[1L]]), character(1))
  result$likelihood_consensus_rank <- vapply(lik_rows, function(r) as.character(r$consensus_rank[[1L]]), character(1))
  result$prior_role <- vapply(seq_along(ids), function(i) {
    .prior_role_one(
      chunk_of(ids[i]), rank_system,
      result$consensus_taxon[i], result$consensus_rank[i],
      result$likelihood_consensus_taxon[i], result$likelihood_consensus_rank[i]
    )
  }, character(1))
  # Share of the baseline (sequence, named priors flattened) held by the
  # reported taxon: the magnitude behind prior_role.
  result$likelihood_support <- vapply(seq_along(ids), function(i) {
    ch <- chunk_of(ids[i])
    tx <- result$consensus_taxon[i]
    rk <- result$consensus_rank[i]
    if (is.null(ch) || is.na(tx) || is.na(rk)) return(NA_real_)
    v <- .extract_rank_values(ch, rk)
    tot <- sum(ch$.lik_post, na.rm = TRUE)
    if (is.null(v) || tot <= 0) return(NA_real_)
    sum(ch$.lik_post[!is.na(v) & v == tx], na.rm = TRUE) / tot
  }, numeric(1))
  result
}

.rank_depth <- function(rank, rank_system) {
  std <- c("kingdom", "phylum", "class", "order", "family", "genus", "species")
  d <- match(rank, rank_system)
  if (is.na(d)) d <- match(rank, std) - length(std) + length(rank_system)
  d
}

# The value at target_rank of the observation's rows whose value at
# taxon_rank is taxon; NA unless exactly one value is found.
.ancestor_at <- function(chunk, taxon, taxon_rank, target_rank) {
  if (is.null(chunk) || is.na(taxon_rank) || is.na(target_rank)) return(NA_character_)
  hit <- chunk[.extract_rank_values(chunk, taxon_rank) %in% taxon, , drop = FALSE]
  if (nrow(hit) == 0L) return(NA_character_)
  anc <- unique(stats::na.omit(.extract_rank_values(hit, target_rank)))
  if (length(anc) == 1L) as.character(anc) else NA_character_
}

.prior_role_one <- function(chunk, rank_system, t_p, r_p, t_l, r_l) {
  if (is.na(t_p) && is.na(t_l)) return(NA_character_)
  if (is.na(t_l)) return("narrowed")
  if (is.na(t_p)) return("broadened")
  if (identical(r_p, r_l)) return(if (identical(t_p, t_l)) "agrees" else "changed")
  d_p <- .rank_depth(r_p, rank_system)
  d_l <- .rank_depth(r_l, rank_system)
  if (is.na(d_p) || is.na(d_l)) return("changed")
  if (d_p > d_l) {
    anc <- .ancestor_at(chunk, t_p, r_p, r_l)
    if (!is.na(anc) && anc == t_l) "narrowed" else "changed"
  } else {
    anc <- .ancestor_at(chunk, t_l, r_l, r_p)
    if (!is.na(anc) && anc == t_p) "broadened" else "changed"
  }
}

# Names that the observation's own rows use for two different lineages: a
# (rank, name) node whose rows carry different non-missing values at some
# coarser rank. The credible node identifies a taxon by (rank, name), so such
# a node pools what may be two taxa (a homonym) or one taxon labelled
# inconsistently; consensus cannot tell which. Reported only; never changes a
# call. NA when there is none.
.lineage_conflicts <- function(chunk, rank_system) {
  named <- chunk[!is.na(chunk$taxon_name), , drop = FALSE]
  if (nrow(named) < 2L || length(rank_system) < 2L) return(NA_character_)
  vals <- lapply(rank_system, function(r) {
    v <- .extract_rank_values(named, r, rank_system)
    if (is.null(v)) rep(NA_character_, nrow(named)) else v
  })
  out <- character(0)
  for (i in 2:length(rank_system)) {
    v <- vals[[i]]
    for (nd in unique(v[!is.na(v)])) {
      inn <- !is.na(v) & v == nd
      if (sum(inn) < 2L) next
      for (j in seq_len(i - 1L)) {
        u <- vals[[j]][inn]
        if (length(unique(u[!is.na(u)])) > 1L) {
          out <- c(out, paste0(rank_system[i], ":", nd))
          break
        }
      }
    }
  }
  if (length(out)) paste(unique(out), collapse = "; ") else NA_character_
}

# Robust credible node (imprecise prior). The occurrence prior is estimated
# from finitely many records, so each node's posterior is taken at its lower
# bound over the epsilon-contamination class {(1 - eps) pi + eps q : q any
# distribution} (Berger & Berliner 1986); eps = s / (N + s) is Walley's (1996)
# imprecise Dirichlet model with N the prior's own concentration (median
# alpha + beta of the observation's kernel-estimated rows). The worst case
# puts all of eps on the best-fitting hypothesis outside the node:
#   lower(v) = (1 - eps) A_v / ((1 - eps) sum(L pi) + eps max_{h not in v} L_h).
# Returns the finest node whose lower posterior reaches the threshold.
.credible_node_robust <- function(chunk, rank_system, s, threshold, unsupplied = character(0),
                                  cross_phylum_eps = 0) {
  L <- chunk$score_likelihood
  L[is.na(L) | L < 0] <- 0
  pi <- chunk$prior_mean
  pi[is.na(pi) | pi < 0] <- 0
  # N = the site's record concentration (join_priors' prior_site_records),
  # else the observation's own kernel-estimated rows. Never the floor or
  # dark-diversity rows: their alpha + beta are pseudo-counts (a few units),
  # which would make eps ~ 0.1 and coarsen nearly every call. With no record
  # count the check is not applied (plain credible node).
  N <- NA_real_
  if ("prior_site_records" %in% names(chunk)) {
    N <- suppressWarnings(stats::median(chunk$prior_site_records[is.finite(chunk$prior_site_records)]))
  }
  if (!is.finite(N) && "prior_branch" %in% names(chunk)) {
    conc <- chunk$prior_alpha + chunk$prior_beta
    kern <- .is_kernel_branch(chunk$prior_branch)
    N <- suppressWarnings(stats::median(conc[kern & is.finite(conc)]))
  }
  if (!is.finite(N) || N <= 0) {
    return(NULL)
  }
  .credible_node(chunk, L * pi, rank_system, threshold, eps = s / (N + s), L = L, unsupplied = unsupplied,
    cross_phylum_eps = cross_phylum_eps)
}

.row_col_or <- function(row, col, default = NA_real_) {
  if (col %in% names(row)) row[[col]][[1L]] else default
}

#' Compute consensus for one observation
#' @noRd
.consensus_one_observation <- function(chunk, sid, rank_system,
                                       cumulative_threshold, min_posterior,
                                       posterior_col, group_priors = NULL,
                                       min_effective_records = 0,
                                       pool_tail = FALSE,
                                       unnamed_in_threshold = TRUE,
                                       consensus_method = "lca",
                                       robust_prior_s = 0,
                                       unsupplied = character(0),
                                       cross_phylum_eps = 0) {
  # credible_node sums every hypothesis, so no hypothesis is dropped below
  # min_posterior: the tail is always part of the plausible set.
  if (consensus_method == "credible_node") pool_tail <- TRUE
  # All named hypotheses contribute to LCA; only the unreferenced_family catch-all
  # is excluded (taxon_name = NA; represents uncharacterised diversity with no name).
  # named_all is kept before any filtering for consensus_posterior computation.
  named_all <- chunk[!is.na(chunk$taxon_name), ]
  # Posterior on unnamed rows: a hypothesis with no name cannot join an LCA, but
  # its mass is still mass the call does not hold.
  unnamed_mass <- sum(chunk[[posterior_col]][is.na(chunk$taxon_name)], na.rm = TRUE)
  extra_denom <- if (unnamed_in_threshold) unnamed_mass else 0

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

  # Plausible set. Hypotheses at or above min_posterior ("survivors") are
  # added in order until they hold cumulative_threshold of the TOTAL named
  # posterior mass. The ones below min_posterior are not discarded: they are
  # pooled into one tail block, which joins the plausible set as a whole when
  # the survivors fall short. A single noise-level hypothesis therefore
  # cannot coarsen a call on its own, but a flat tail holding most of the
  # mass is not renormalised away (a lone survivor at 0.13 beside twenty
  # hypotheses at 0.02-0.03 used to be reported as a species on its own).
  # The consensus of a pooled tail is its members' LCA, via .find_lca().
  named_all <- named_all[order(named_all[[posterior_col]], decreasing = TRUE), ]
  named_total <- sum(named_all[[posterior_col]], na.rm = TRUE)
  if (!is.finite(named_total) || named_total == 0) {
    return(.empty_consensus_row(sid))
  }
  is_survivor <- !is.na(named_all[[posterior_col]]) & named_all[[posterior_col]] >= min_posterior
  named <- named_all[is_survivor, , drop = FALSE]
  tail_rows <- named_all[!is_survivor, , drop = FALSE]
  tail_mass <- sum(tail_rows[[posterior_col]], na.rm = TRUE)

  if (!pool_tail) {
    # Discarding rule: the sub-floor hypotheses are dropped and the threshold
    # is measured against the survivors' own mass. tail_mass is still
    # reported, so a call resting on a small share of the total is visible.
    if (nrow(named) == 0L) {
      cli::cli_warn(
        "observation_id {.val {sid}} has no hypotheses above min_posterior = \\
        {min_posterior}. All {nrow(named_all)} named hypothesis(es) are below \\
        threshold. Consider lowering min_posterior, or pool_tail = TRUE."
      )
      out_empty <- .empty_flagged()
      out_empty$tail_mass <- tail_mass
      out_empty$tail_pooled <- FALSE
      return(out_empty)
    }
    surv_total <- sum(named[[posterior_col]], na.rm = TRUE)
    denom <- surv_total + extra_denom
    cum_prop <- cumsum(named[[posterior_col]]) / denom
  } else {
    denom <- named_total + extra_denom
    cum_prop <- if (nrow(named) > 0L) cumsum(named[[posterior_col]]) / denom else numeric(0)
  }
  n_include <- which(cum_prop >= cumulative_threshold)[1L]
  tail_pooled <- pool_tail && is.na(n_include) && nrow(tail_rows) > 0L
  if (is.na(n_include)) n_include <- nrow(named)

  plausible <- if (tail_pooled) {
    rbind(named[seq_len(n_include), , drop = FALSE], tail_rows)
  } else {
    named[seq_len(n_include), , drop = FALSE]
  }
  n_include <- nrow(plausible)

  # Winner diagnostics: first row of plausible = highest-posterior hypothesis.
  # Extract prior and likelihood values; NA when the source column is absent
  # (e.g. when posterior_df comes from assign_taxa_llm() rather than compute_posterior()).
  winner_row <- plausible[1L, ]
  winner_prior <- .row_col_or(winner_row, "prior_mean")
  winner_likelihood <- .row_col_or(winner_row, "score_likelihood")
  winner_likelihood_cov <- .row_col_or(winner_row, "score_likelihood_cov")
  # winner_theta_mean: the winner's raw occurrence-model share
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

  # winner_rank_expanded: TRUE when the winning hypothesis came
  # from join_priors()'s coarse-rank expansion (.expand_coarse_rank_rows()),
  # i.e. every expanded candidate for that coarse-rank identification shares
  # one inherited, uninformative likelihood -- so this species-level winner
  # was decided entirely by occurrence-prior mass, not by any sequence/image/
  # acoustic evidence discriminating between the candidates. This is
  # intentional, sound behavior (using priors to resolve an otherwise-coarse
  # ID), but a downstream consumer treating every species-level consensus_taxon
  # as equally evidence-supported would be wrong to do so for these rows.
  winner_hypothesis_type <- as.character(.row_col_or(winner_row, "hypothesis_type", NA_character_))
  winner_rank_expanded <- if (is.na(winner_hypothesis_type)) {
    NA
  } else {
    identical(winner_hypothesis_type, "rank_expanded")
  }

  # LCA among plausible hypotheses
  lca <- .find_lca(plausible, rank_system)
  # When the named hypotheses cannot reach cumulative_threshold of the total
  # because posterior sits on unnamed rows, no named taxon holds the call:
  # report it unresolved rather than the LCA of a set that falls short.
  unnamed_blocked <- unnamed_in_threshold && unnamed_mass > 0 &&
    sum(plausible[[posterior_col]], na.rm = TRUE) / denom < cumulative_threshold
  if (unnamed_blocked) {
    lca$taxon <- NA_character_
    lca$rank <- NA_character_
    lca$consensus_reason <- "unnamed_mass"
  }
  robust_lower <- NA_real_
  consensus_limit <- NA_character_
  if (consensus_method == "credible_node") {
    can_robust <- robust_prior_s > 0 &&
      all(c("score_likelihood", "prior_mean", "prior_alpha", "prior_beta") %in% names(chunk))
    node <- if (can_robust) .credible_node_robust(chunk, rank_system, robust_prior_s, cumulative_threshold, unsupplied,
      cross_phylum_eps)
    if (is.null(node)) can_robust <- FALSE
    node <- if (can_robust) {
      node
    } else {
      # every row is in the denominator, named or not (unnamed_in_threshold
      # governs the "lca" method only)
      .credible_node(chunk, chunk[[posterior_col]], rank_system, cumulative_threshold, unsupplied = unsupplied,
        cross_phylum_eps = cross_phylum_eps)
    }
    lca$taxon <- node$taxon
    lca$rank <- node$rank
    lca$consensus_reason <- if (is.na(node$taxon)) "no_credible_node" else "credible_node"
    if (can_robust) robust_lower <- node$lower
    consensus_limit <- node$limit
  }

  # --- Discrimination diagnostics ------------------------------------------
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
  # detect.
  #
  # "Plausible" is read off `prior_branch` (supplied upstream by
  # join_priors() from TaxaExpect priors), NOT off prior_mean's value: a
  # taxon with no local occurrence record at all has `prior_branch = NA`,
  # while a genuine singleton has a real branch -- even though both can
  # share the same numeric floor prior. That is exactly the "never reported
  # here" vs "reported once" distinction, and prior_mean alone cannot
  # express it. Absent column -> NA, matching the optional-upstream-output
  # contract used by the confusion-risk pass-throughs.
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
  #
  # "Plausible" here means "joined to a NAMED prior row" (any branch --
  # resident, undetected-evidence, or transport); a row that fell through to
  # the anonymous dark-diversity floor has NA prior_branch. (A model_tier
  # column with no prior_branch column is rejected up front, in
  # posterior_consensus()'s own input validation -- see there.)
  has_branch <- "prior_branch" %in% names(named_all)
  has_plaus <- has_branch
  plaus_mask <- if (has_branch) !is.na(named_all$prior_branch) else NULL

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

  # --- Occurrence-plausibility support -------------------------------------
  # Two columns supporting the prior/occurrence-plausibility axis, which asks
  # a question `winner_prior`'s VALUE cannot answer on its own: has this taxon
  # ever been reported here at all?
  #
  # A taxon that has never been reported and a genuine singleton can carry the
  # SAME numeric prior -- both land on the dark-diversity floor -- but they
  # mean opposite things ("no evidence it occurs here" vs "recorded once").
  # `prior_branch` separates them: `resident_undetected` (floor/evidence-blend
  # rows -- species with ZERO local records, elevated by regional/watch/iNat
  # evidence) and `transport` (domestic/food) winners read FALSE; only
  # `kernel_estimated` (a real, in-habitat local estimate) reads TRUE. A
  # transport winner's interpretation is carried separately by
  # add_posthoc_assessment()'s domestic_prior_caveat, which is the designed
  # pairing.
  # The branch test reads .is_kernel_branch() (see kernel_branch.R), which
  # stops if `prior_branch` carries a value outside the full accepted set,
  # and is optionally ALSO gated on how much evidence stands behind the row.
  # The branch alone cannot carry that claim -- TaxaExpect writes it as a
  # constant, and within it effective_records spans ~10 orders of magnitude.
  # min_effective_records defaults to 0, i.e. branch-only; raise it to
  # require real local evidence before a winner counts as having an
  # occurrence record.
  winner_has_occurrence_record <- if (has_branch) {
    ok <- .is_kernel_branch(winner_row$prior_branch[[1L]])
    if (isTRUE(ok) && min_effective_records > 0) {
      if (!"effective_records" %in% names(winner_row)) {
        cli::cli_abort(c(
          "{.arg min_effective_records} > 0 requires an \\
          {.field effective_records} column in {.arg posterior_df}, which \\
          is missing.",
          "i" = "This is a prior table from before the kernel-priors \\
          schema; regenerate it with \\
          {.fn TaxaExpect::estimate_kernel_priors}."
        ))
      }
      er <- winner_row$effective_records[[1L]]
      ok <- if (is.na(er)) ok else er >= min_effective_records
    }
    isTRUE(ok)
  } else {
    NA
  }
  # `consensus_prior`: the occurrence-model share for the consensus GROUP,
  # not just its candidates. NA when nothing qualifies -- so NA doubles as
  # the consensus-scope "never reported" signal, needing no separate logical.
  #
  # Reads `theta_mean`, NOT `prior_mean`. `prior_mean`
  # can be substantially inflated by `update_prior_from_consensus()`'s
  # cross-observation confirmation boost -- confirmed on real Mugu data: all
  # 220 `prior_mean >= 0.5` rows in one real dataset were boosts, and the
  # boost's own natural scale is a posterior probability (bounded ~1), not an
  # occurrence share (observed ceiling 0.0865 on that dataset). Reading
  # `prior_mean` here would let one confirmed-elsewhere candidate make its
  # whole consensus group look occurrence-expected regardless of any real
  # occurrence support. `theta_mean` is immune to that boost by construction.
  #
  # Requires `group_priors` (from `compute_group_priors()`): the
  # exact SUM of `theta_mean` over every locally modelled member of the
  # consensus taxon at its own rank -- not just this observation's own
  # candidates, which is all a candidate-scoped MAX could ever see. Records
  # are mutually exclusive across taxa, so a group's true share is the exact
  # sum of its members' shares -- no independence assumption needed (unlike
  # a noisy-OR combination, the wrong model for a compositional share).
  #
  # `NA` when `group_priors` is not supplied, or has no matching (rank,
  # taxon) row -- deliberately NOT a silent fallback to a
  # candidate-scoped MAX: that value is a real
  # underestimate (confirmed on real data, e.g. Gobiidae max=0.0164 vs the
  # true group sum 0.0313), and returning it silently when the caller hasn't
  # supplied `group_priors` would misrepresent an incomplete computation as
  # a complete one.
  # `consensus_has_occurrence_record`: the consensus-scope analogue of
  # `winner_has_occurrence_record`. Inferring "has a record" from whether
  # `consensus_prior` is `NA` alone would conflate two
  # different situations `consensus_prior` alone cannot distinguish:
  # `group_priors` was never supplied (unknown), vs. `group_priors` was
  # supplied and genuinely found no local member (confirmed absent). On real
  # production data (no workflow supplies `group_priors` yet),
  # `consensus_prior` is `NA` for every row for the FIRST reason, so that
  # inference would read every row as confirmed-absent ("unprecedented") --
  # `consensus_plausibility` would read `"unprecedented"` for all 616 real rows.
  # `NA` here means "not checked" (matches `winner_has_occurrence_record`'s
  # own `NA`-when-`prior_branch`-absent convention); `TRUE`/`FALSE` mean a
  # real lookup was performed and found/didn't find a matching group.
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
    tail_mass = tail_mass,
    tail_pooled = tail_pooled,
    unnamed_mass = unnamed_mass,
    robust_lower_posterior = robust_lower,
    consensus_limit = consensus_limit,
    lineage_conflict = .lineage_conflicts(chunk, rank_system),
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
  # consensus_taxon_v1 / consensus_rank_v1: constant within observation -- take first value.
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
#' when the species column is absent (see the species branch's own comment
#' for why this derivation matters). All other missing columns return NA.
#' @noRd
.extract_rank_values <- function(input_df, rank, rank_system = NULL) {
  vals <- .extract_rank_values_raw(input_df, rank)
  # A row never reports a value at a rank finer than its own: an unsequenced-
  # congener row named at genus can still carry its anchor species in a
  # `species` column, which would otherwise count it as that species. Rank
  # order is the standard ladder with any non-standard ranks of the caller's
  # rank_system (e.g. "subgenus") inserted where rank_system places them.
  if ("taxon_name_rank" %in% names(input_df)) {
    std <- .rank_order(rank_system)
    r_d <- match(rank, std)
    row_d <- match(input_df$taxon_name_rank, std)
    if (!is.na(r_d)) vals[!is.na(row_d) & row_d < r_d] <- NA_character_
  }
  vals
}

.extract_rank_values_raw <- function(input_df, rank) {
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
    # Without this branch, a caller whose data has no literal "species"
    # column (e.g. TaxaLikely's real sequence/BLAST pathway, which only
    # produces taxon_name/family/genus) would fall through to the generic
    # "explicit column required" case below, returning all-NA --
    # consensus_posterior/consensus_confidence_score would then silently
    # compute to exactly 0 for every single-hypothesis resolved observation
    # on that pathway, even though the winning candidate's own posterior_mean
    # is correctly high. consensus_taxon itself is unaffected (.find_lca()'s
    # nrow(plausible) == 1 shortcut reads taxon_name/taxon_name_rank directly,
    # bypassing this function), which is why such a gap would be invisible
    # unless the confidence columns were checked specifically. Verified
    # against a real end-to-end Template run using this exact data shape.
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
    tail_mass = NA_real_,
    tail_pooled = NA,
    unnamed_mass = NA_real_,
    robust_lower_posterior = NA_real_,
    consensus_limit = NA_character_,
    lineage_conflict = NA_character_,
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
.downrank_consensus <- function(consensus_df, species_ref, rank_system,
                                require_candidate = TRUE) {
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

  # Rank value(s) a plausible candidate takes at `rk` -- used to check that a
  # proposed narrowing lands at or above a taxon THIS observation actually
  # scored. species_ref is the first source; a binomial's own
  # first word is the genus fallback for a candidate the reference lacks.
  .cand_rank_values <- function(cand, rk) {
    if (length(cand) == 0L) {
      return(character(0))
    }
    if (rk == finest_rank) {
      return(cand)
    }
    col <- .ref_col(rk)
    fin <- .ref_col(finest_rank)
    out <- character(0)
    if (!is.na(col) && !is.na(fin)) {
      hit <- species_ref[
        !is.na(species_ref[[fin]]) & species_ref[[fin]] %in% cand, ,
        drop = FALSE
      ]
      out <- unique(as.character(hit[[col]]))
      out <- out[!is.na(out)]
    }
    if (identical(rk, "genus")) {
      out <- unique(c(out, sub(" .*", "", cand[grepl(" ", cand, fixed = TRUE)])))
    }
    out
  }

  has_plausible <- "plausible_taxa" %in% names(consensus_df)
  n_blocked <- 0L

  consensus_df$downranked <- FALSE

  for (i in seq_len(nrow(consensus_df))) {
    if (isTRUE(consensus_df$is_resolved[i])) next
    cur_rank <- consensus_df$consensus_rank[i]
    cur_taxon <- consensus_df$consensus_taxon[i]
    if (is.na(cur_rank) || is.na(cur_taxon)) next
    if (cur_rank == finest_rank) next

    rank_idx <- match(cur_rank, rank_system)
    if (is.na(rank_idx) || rank_idx >= length(rank_system)) next

    plaus <- character(0)
    if (has_plausible) {
      pv <- consensus_df$plausible_taxa[[i]]
      if (!is.null(pv)) {
        pv <- as.character(pv)
        plaus <- pv[!is.na(pv) & nzchar(pv)]
      }
    }

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

      if (length(finer_vals) != 1L) break # 0 or >1 options -- stop

      # Candidate-set gate. The reference knowing exactly one
      # finer taxon is not enough: that taxon must also be at or above a
      # candidate this observation actually scored, or the row is relabelled
      # to something it has no evidence for while keeping the coarse rank's
      # posterior mass. Measured across four sites without this gate:
      # 35 of 150 downranked rows narrowed outside their own candidate set
      # (PtCon 18S Ulva lactuca x21 over five other Ulva species; PtCon 12S
      # Sardinops sagax over three congeners; Mugu Pseudotolithus senegallus).
      # Narrowing to a COARSER-than-finest rank stays legitimate when the
      # candidates are members of it (family -> genus Ulva is kept), which is
      # why this is a taxonomy test, not a string match on plausible_taxa.
      if (isTRUE(require_candidate) && length(plaus) > 0L) {
        ok_vals <- .cand_rank_values(plaus, finer_rank)
        if (!(finer_vals[[1L]] %in% ok_vals)) {
          n_blocked <- n_blocked + 1L
          break
        }
      }

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

  if (n_blocked > 0L) {
    cli::cli_inform(paste0(
      "posterior_consensus: {n_blocked} downranking step(s) blocked because the ",
      "reference's only finer taxon was not among the observation's own ",
      "candidates (see {.arg downrank_requires_candidate})."
    ))
  }

  consensus_df
}
