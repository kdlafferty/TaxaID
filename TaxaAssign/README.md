---
editor_options: 
  markdown: 
    wrap: 72
---

# TaxaAssign

Bayesian taxonomic assignment from match scores and priors. Part of the
[TaxaID](https://github.com/kdlafferty/TaxaID) ecosystem.

## Overview

TaxaAssign makes a consensus taxonomic assignment to an observation
based on similar labeled accessions found in a reference library. It
uses Bayes' theorem to multiply the likelihood that a match score
corresponds to a particular species (converted from a score by
TaxaLikely) by the prior probability that the species would be selected
at random from a sample of similar species expected from that site and
habitat (estimated from occurrence data by TaxaExpect). After
normalization and Monte Carlo simulation, each candidate receives a
posterior probability. If a single candidate has strong posterior
support, it is assigned as the consensus taxon; otherwise, a coarser
rank (genus, family, etc.) is assigned, by default via lowest common
ancestor. All competing hypotheses and their probabilities are retained
in the output, together with diagnostic columns that say how much of
each call rests on the sequence and how much on the prior (see *Reading
a consensus table* below). The user can also update priors in a second
round: if one observation strongly supports species A, that evidence can
sharpen the prior for species A in other observations from the same
sample, within guards that stop the second round from manufacturing
calls the sequence does not support.

Three workflows:

1.  Conventional: uses match-score thresholds and a lowest common
    ancestor to pick the best candidate. Examples include 100% match,
    maximum match, rank thresholded (e.g., 98% to species, 95% to
    genus..) and can be filtered in advance by a regional list to reduce
    false positives.
2.  LLM Bayesian: an approximate Bayesian assignment, substituting an
    exponential score-weighting proxy for TaxaLikely's modeled
    likelihood and an LLM's biogeographic judgment for TaxaExpect's
    modeled occurrence prior. It exists for rapid analysis when a
    trained TaxaLikely model or TaxaExpect priors aren't available yet
    (or as a quick comparison against the Full Bayesian result on data
    you already have both for). This should be better than conventional
    workflows, but not the statistically defensible outcome that most
    users want, and may be model-dependent (and difficult to reproduce).
3.  Full Bayesian: TaxaLikely's trained likelihood model + TaxaExpect's
    occurrence-modelled priors. The recommended pathway for any real
    analysis: publication-quality, and every one of this ecosystem's
    real production workflows uses it exclusively.

## Installation

``` r
# Requires TaxaTools (foundation package)
devtools::install("path/to/TaxaTools")
devtools::install("path/to/TaxaAssign")
```

## Quick Start

### Full Bayesian workflow

``` r
library(TaxaAssign)

# likelihoods from TaxaLikely::evaluate_likelihoods() |> filter_top_hypotheses()
joined     <- join_priors(likelihoods, priors,       # priors from TaxaExpect
                          site = list(grid_id = "Grid_34p1_m119p1",
                                      main_habitat = "Marine"),
                          backbone_id = 11)          # 11 = GBIF; 4 = NCBI
posteriors <- compute_posterior(joined)
consensus  <- posterior_consensus(posteriors)            # LCA, the default

# Round 2: confirmation update within each sample, then consensus again
# with the same settings (posterior_consensus() attaches them to its result)
updated    <- update_prior_from_consensus(posteriors, consensus,
                                          detections = detections,  # observation_id x sample_id
                                          group_cols = "sample_id")
consensus  <- posterior_consensus(updated)
head(consensus)

# The credible-node method, a more conservative option (see Statistical Methods).
# backbone_id lets the cross-phylum rule compare phyla by lineage, not by name.
consensus_cn <- posterior_consensus(posteriors, consensus_method = "credible_node",
                                    backbone_id = 11)
```

### LLM-shortcut workflow (fast approximation: no trained model/priors needed)

``` r
library(TaxaAssign)

context <- build_context(
  taxon_names     = unique(match_obj$taxon_name),
  geographic_hint = "Point Conception, California (34.45 N, 120.47 W)"
)
result    <- assign_taxa_llm(match_obj, context = context)  # from TaxaMatch
consensus <- posterior_consensus(result, backbone_id = 11)
head(consensus)
```

## Key Functions

Core assignment:

-   `compute_posterior()`: Bayes' theorem with MC uncertainty
-   `assign_taxa_llm()`: LLM-shortcut (priors + likelihoods in one call;
    accepts named unreferenced species from
    `TaxaLikely::suggest_unreferenced_species()` via
    `unreferenced_taxa`; see TaxaLikely's README for the full
    unreferenced-species mechanism)
-   `join_priors()`: merge TaxaExpect priors with likelihood output.
    Both sides must be on one backbone; harmonise the likelihood side
    onto the occurrence backbone, never the priors onto NCBI, which
    silently drops every prior taxon that has never been sequenced. The
    join rate per rank is reported on every call
-   `combine_multisite_priors()`: combine an observation's per-site
    prior rows into one precision-weighted row (needed before
    `compute_posterior()` when the same observation was detected at more
    than one site)
-   `adjust_inat_range_priors()`: elevate priors for candidates that
    fall within their iNaturalist range polygon and have reliable
    observation coverage, for workflows outside TaxaExpect's
    evidence-mixture pathway

Consensus:

-   `posterior_consensus()`: one call per observation from the posterior
    table. Lowest common ancestor of the plausible set by default;
    `consensus_method = "credible_node"` is the more conservative option.
    Also reports the likelihood-only call, the prior's role in the
    reported call, why a call stopped short of species, and (with
    `species_reference`) a downranking to the one locally plausible finer
    taxon
-   `score_consensus()`: conventional score-based consensus, for
    benchmarking against a fixed-threshold pipeline (it reproduces that
    pipeline's known limits on purpose)
-   `update_prior_from_consensus()`: the Round 2 confirmation update,
    computed within each sample or site, with receiver guards so that a
    raised prior can choose among candidates the sequence cannot separate
    but never overturn one it argues against
-   `add_slash_taxon()`: label ambiguous candidate sets with slash-taxon
    notation and flag which of them are irreducible
-   `compute_group_priors()`: aggregate occurrence-model shares to
    genus/family level for use as `posterior_consensus()`'s
    `group_priors`
-   `add_unreferenced_prior_mass()`: give the generic unreferenced rows
    the prior mass of the local relatives that are actually unreferenced,
    instead of the dark-diversity floor `join_priors()` assigns them. A
    posterior is normalised over the hypotheses an observation carries,
    so without this the generic rows cannot express that none of the
    named candidates is plausible at the site

Context and reporting:

-   `build_context()`: auto-populate site context from taxon names
-   `generate_report()`: publication-ready Methods + Results text
-   `report_assign()`: lightweight section for `assemble_report()`

## Statistical Methods

TaxaAssign computes Bayesian posterior probabilities for each candidate
taxonomic assignment:

$$P(H_i \mid D) = \frac{L(D \mid H_i) \times \pi(H_i)}{\sum_j L(D \mid H_j) \times \pi(H_j)}$$

where $L$ is the likelihood (TaxaLikely's trained model, or the
LLM-shortcut pathway's exponential score-weighting proxy) and $\pi$ is
the prior (TaxaExpect's occurrence model, or the LLM-shortcut pathway's
LLM-estimated biogeographic prior).

-   Monte Carlo uncertainty propagation: priors are modelled as
    Beta($\alpha$, $\beta$) distributions and likelihoods as
    Normal(mean, sd); 1000 simulations (default) propagate both sources
    of uncertainty into posterior means, SDs, and confidence scores
    (fraction of simulations won).
-   Two workflows: the full Bayesian workflow uses calibrated
    likelihoods from TaxaLikely's hierarchical model and
    spatially-explicit priors from TaxaExpect's kernel-based composition
    estimator; the LLM-Bayesian workflow uses exponential score
    weighting ($L_i = e^{\lambda s_i}$) and LLM-estimated priors with
    information-quality-driven Beta concentration.
-   Posterior consensus, the conventional default (`consensus_method =
    "lca"`): the consensus ranks hypotheses by the point-estimate
    posterior, drops those below `min_posterior` (default 0.05), then
    accumulates the remainder in decreasing order until they reach
    `cumulative_threshold` (default 0.90) of the posterior mass; if
    several taxa remain, their lowest common ancestor (LCA) is the call.
    Posterior on rows with no taxon name (an unsequenced relative that
    only a placeholder represents) counts in the denominator, so a call
    cannot rest on mass the named candidates do not hold; `pool_tail`
    optionally lets a flat tail of small hypotheses coarsen a call
    instead of being renormalised away.
-   Weighted LCA, node summing (`consensus_method = "credible_node"`):
    report the most specific node whose descendants together hold at
    least `cumulative_threshold` (default 90%) of the posterior. Instead
    of picking a top set and climbing to its ancestor, the posterior of
    every hypothesis is summed under each taxon, rank by rank from the
    finest. No hypothesis is dropped, so a rare tail of alternatives
    still counts against a species call, and a hypothesis named at a
    coarser rank counts toward that taxon and its ancestors. This is the
    analogue of MEGAN's weighted LCA. It contrasts with the default
    `"lca"`, which keeps the candidates above `min_posterior` (default
    5%), takes the smallest group of those holding 90% of the surviving
    mass, and reports their lowest common ancestor — so the sub-5%
    candidates are discarded rather than counted. The plain node-summing
    setting is `consensus_method = "credible_node"` with `robust_prior_s
    = 0` and `cross_phylum_eps = 0`; the function and argument names are
    unchanged.

    What the evidence shows, from an ablation over three datasets. Node
    summing moves calls in both directions, not simply toward coarser
    ones: on CalIntertidal it made 1,304 units finer (mostly 1,163
    phylum to class) where the LCA top set spanned lineages, and 4,507
    coarser. On Great Lakes, scored against an independent survey of the
    same water body (a survey, not ground truth, so a call it does not
    list is unconfirmed rather than wrong), species precision was 0.882
    against 0.878 for LCA. Two refinements were measured and then
    switched off for that setting, though both keep their own defaults
    in the function. The robust prior bound (`robust_prior_s`) withheld
    85 survey-supported species pairs to avoid 16 unsupported ones, a
    poor exchange, so it is set to 0. The cross-phylum guard
    (`cross_phylum_eps`) changed nothing either way on the two
    single-phylum fish studies and, on CalIntertidal, moved 201 units
    without touching a single known-correct or known-wrong call, so
    there is no evidence to judge it on; it is set to 0 as well.
-   Robust prior bound (`robust_prior_s`, default 1, active with the
    credible node): the occurrence prior is an estimate from finitely
    many records, so a node is reported only if its posterior stays at
    or above the threshold when one further record of unknown species is
    added to the site (an imprecise-Dirichlet neighbourhood; Walley
    1996). A call the sequence decides by a wide margin is unaffected; a
    marginal call whose candidates carry priors worth only a few records
    is coarsened. Two rules keep the bound from eliminating a species
    into its congener: the outside taxon gains at most one site record,
    and less when its own evidence is thinner than a record, and it
    gains that record only at a node the sequence itself reaches that
    holds a locally recorded member, so a sequence good to genus in a
    genus with one locally recorded species keeps the genus. The site's
    record count is `prior_site_records`, which `join_priors()` carries
    from the kernel prior; the bound is reported as
    `robust_lower_posterior`.
-   Cross-phylum rule (`cross_phylum_eps`, default 0.05, credible node
    only): when the runner-up phylum holds at least this share of the
    posterior, a call finer than phylum would rest on a choice between
    phyla that the evidence barely makes, so the call is withheld to the
    finest node at phylum or coarser that holds the threshold. Given
    `backbone_id`, phyla are compared by lineage rather than by name
    string, so a clade carried as a phylum on some rows and as a rank
    inside another phylum on others does not count as a competitor;
    without it the comparison falls back to names, with a message.
-   Downranking (`species_reference`, off by default): refines a coarse
    call to the one finer taxon that exists at the study site, step by
    step while each step is unambiguous. By default
    (`downrank_requires_candidate = TRUE`) the finer taxon must be at or
    above a taxon the observation actually scored, and a step to species
    needs at least `min_posterior` on that species, so the reference can
    pick among candidates but cannot name a taxon the sequence excluded.
    The call's posterior is then the coarser node's; `downranked` says
    so.
-   Deterministic ties: candidates with exactly equal posteriors are
    ordered by name in byte order, so the leading taxon in `plausible_taxa`
    and `plausible_top` is the same on every machine and locale. Calls
    never change on a tie, since tied species already back off to their
    LCA; only which of several equals is listed first.
-   Round 2, the confirmation update: a species supported in one
    observation raises its prior in unresolved observations of the same
    group, analogous to shrinkage estimators (Efron and Morris 1973),
    with the group defined by `detections` (a sample, a site, or any
    combination of columns) and study-wide pooling only when no grouping
    is given. Support is soft and leave-one-out: every observation's
    posterior for the species counts fractionally, discounted by
    `confirmation_discount` (default 0.25, so about four correlated
    observations carry the weight of one) and saturating, so the update
    is continuous in its inputs. Only referenced candidates give or
    receive support (unreferenced-relative rows would confirm one
    another circularly), the target is rescaled onto the site's largest
    occurrence share and bounded by `max_raise_factor`, and four receiver
    guards apply: a row is raised only inside its observation's
    likelihood-only call, only when it has an occurrence record, only
    when its likelihood is at least every other candidate's, and only
    when it beats the runner-up by more than the likelihoods' own noise.
    A species guard then undoes every raise in an observation where
    Round 2 would create a species call that the likelihood alone does
    not make. Each guard reports what it held back.
-   Taxonomy lookups for unreferenced rows (`lookup_missing_taxonomy`)
    pass each hypothesis's own rank, so a name that is both a genus and
    a subgenus resolves; a failed lookup is reported as `"lookup_failed"`
    on the observation, distinct from `"not_found"`, and is never cached
    as an answer.
-   Dark diversity fallback: "dark diversity" is an ecological concept
    (Pärtel et al. 2011) for species that belong to the regional species
    pool and could plausibly occur at a site given its environmental
    conditions, but have not actually been observed there yet.
    TaxaExpect computes per-species Tier 3 ("undetected species")
    estimates using this concept. See TaxaExpect's README for the full
    occurrence-modeling mechanism. For species with no prior row from
    TaxaExpect at all, `join_priors()` builds its own fallback from
    those Tier 3 estimates, site-level or global averaging, or (with
    `singleton_taxonomy`) mass-conserving hierarchical group priors,
    preventing false negatives from incomplete occurrence data (and
    allowing novel species discovery). See `join_priors()`'s own
    documentation for the full mechanism.

## Reading a consensus table

`posterior_consensus()` returns one row per observation. Beyond
`consensus_taxon`, `consensus_rank` and `consensus_posterior`, read:

-   `likelihood_consensus_taxon` / `likelihood_consensus_rank`: the call
    the likelihoods alone support, with the named candidates' priors
    flattened. `prior_role` says how the prior moved the reported call
    relative to it (`"agrees"`, `"narrowed"`, `"broadened"`,
    `"changed"`), and `likelihood_support` is the share of that
    likelihood-only baseline falling in the reported taxon: 0.84 means
    the sequence nearly makes the call itself, 0.10 means the prior
    chose it. Neither moves a call; they are reported so a species list
    can say which calls rest on where the species is known to occur.
-   `consensus_limit` (credible node): why a call is coarser than
    species: `"threshold"` (mass spread across alternatives),
    `"robust_prior"` (the bound above), `"cross_phylum"`, `"backbone"`
    (lineage gaps in the backbone at a finer rank) or
    `"rank_not_supplied"`.
-   `robust_lower_posterior`, `tail_mass`, `unnamed_mass`,
    `tail_pooled`, `lineage_conflict`: the quantities behind the rules
    above.
-   `downranked`, `winner_rank_expanded`, `consensus_hypothesis_type`,
    `consensus_unreferenced_scope`: whether the name came from the
    reference or the records rather than from a sequence match.
-   `unreferenced_taxonomy_lookup`: `"matched"`, `"not_found"` or
    `"lookup_failed"`; a filter for `"matched"` never keeps a failure.
-   `winner_has_occurrence_record`, `consensus_has_occurrence_record`,
    `consensus_prior`: whether the called taxon has a local occurrence
    record, read by `TaxaFlag::add_posthoc_assessment()`.

A call is made per observation, so when observations are formed per
sequence and per site, the same sequence can be called at species at one
site and at genus at another. That is the per-site prior doing its work,
not a defect; a species list should say whether it reports what the
sequence resolves, what a site resolves, or what holds across sites.

For the full statistical derivation, assumptions, and references, see
[`inst/TaxaAssign_supplemental_methods.md`](inst/TaxaAssign_supplemental_methods.md).

## Vignettes

-   [Taxonomic Assignment](vignettes/taxonomic-assignment.Rmd): full
    workflow
-   [TaxaID Ecosystem Overview](vignettes/taxaid-ecosystem.Rmd):
    cross-package guide

## Part of TaxaID

TaxaAssign is the convergence point of the TaxaID ecosystem. It receives
likelihoods from TaxaLikely and priors from TaxaExpect, then passes
assignments to TaxaFlag for quality screening.

Ecosystem: TaxaLikely + TaxaExpect -\> TaxaAssign -\> TaxaFlag

See the [TaxaID README](https://github.com/kdlafferty/TaxaID) for
ecosystem overview and installation instructions.

## Citation

Lafferty, K.D., TaxaID: A modular R ecosystem for Bayesian taxonomic
assignment: U.S. Geological Survey software, provisional release, not
yet citable. <https://github.com/kdlafferty/TaxaID>

A citable version with a DOI will be released through the USGS software
release process.

## Software Requirements

-   R (\>= 4.1.0; R Core Team 2025)
-   TaxaTools (foundation package)
-   TaxaLikely and TaxaExpect (for the Bayesian workflow; in Suggests)
-   An Application Programming Interface (API) key for an LLM provider
    (Anthropic Claude, Google Gemini, OpenAI, or local Ollama; see
    TaxaTools) is needed for the LLM-shortcut workflow

All dependencies are declared in the DESCRIPTION file and installed
automatically.

Developed with Claude Code (Anthropic PBC, San Francisco, California).

## References

Efron, B. and Morris, C. (1973). Stein's estimation rule and its
competitors, an empirical Bayes approach. *Journal of the American
Statistical Association*, 68(341), 117--130.

Pärtel, M., Szava-Kovats, R. and Zobel, M. (2011). Dark diversity:
shedding light on absent species. *Trends in Ecology & Evolution*,
26(3), 124--128.

Walley, P. (1996). Inferences from multinomial data: learning about a
bag of marbles (with discussion). *Journal of the Royal Statistical
Society: Series B*, 58(1), 3--57.

R Core Team (2025). R: A Language and Environment for Statistical
Computing. V.4.5.2. R Foundation for Statistical Computing, Vienna,
Austria. <https://www.r-project.org>
