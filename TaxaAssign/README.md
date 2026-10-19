---
editor_options: 
  markdown: 
    wrap: 72
---

# TaxaAssign

Bayesian taxonomic assignment from match scores and priors. Part of the
[TaxaID](https://github.com/kdlafferty/TaxaID) ecosystem.

## Overview

TaxaAssign is the "decider". It makes a consensus taxonomic assignment
to an observation based on similar labeled accessions found in a
reference library. To do so, it applies Bayes' theorem to multiply the
likelihood that a match score corresponds to a particular species
(converted from a score by TaxaLikely) by the prior probability that the
species would be selected at random from a sample of similar species
expected from that site and habitat (estimated from occurrence data by
TaxaExpect). After normalization and Monte Carlo simulation, each
candidate receives a posterior probability. If a single candidate has
strong posterior support, it is assigned as the consensus taxon;
otherwise, a coarser rank (genus, family, etc.) is assigned, by default
via lowest common ancestor (LCA). All competing hypotheses and their
probabilities are retained in the output, together with diagnostic
columns that say how much of each call rests on the likelihood and how
much on the prior (see *Reading a consensus table* below). The user can
also update priors in a second round: if one observation strongly
supports species A, that evidence can sharpen the prior for species A in
other observations from the same sample, within guards that stop the
second round from manufacturing calls the likelihood does not support.

Three workflows:

1.  Conventional: uses match-score thresholds and a lowest common
    ancestor to pick the best candidate. Examples include 100% match,
    maximum match, rank thresholded (e.g., 98% to species, 95% to
    genus) and can be filtered in advance by a regional list to reduce
    false positives.
2.  LLM Bayesian: an approximate Bayesian assignment, substituting an
    exponential score-weighting proxy for TaxaLikely's modeled
    likelihood and an LLM's biogeographic judgment for TaxaExpect's
    modeled occurrence prior. It exists for rapid analysis when a
    trained TaxaLikely model or TaxaExpect priors aren't available yet
    (or as a quick comparison against the Full Bayesian result on data
    you already have both for). This should be better than conventional
    workflows, but not the statistically defensible outcome that most
    users want, and may be model-dependent (and difficult to reproduce
    exactly).
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
    silently drops every prior taxon that has no reference. The join
    rate per rank is reported on every call
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
    `consensus_method = "credible_node"` is the more conservative
    option. Also reports the likelihood-only call, the prior's role in
    the reported call, why a call stopped short of species, and (with
    `species_reference`) a downranking to the one locally plausible
    finer taxon

-   `score_consensus()`: conventional score-based consensus, for
    benchmarking against a fixed-threshold pipeline (it reproduces that
    pipeline's known limits on purpose)

-   `update_prior_from_consensus()`: the Round 2 confirmation update,
    computed within each sample or site, with receiver guards so that a
    raised prior can choose among candidates the likelihood cannot
    separate but never overturn one it argues against

-   `add_slash_taxon()`: label ambiguous candidate sets with slash-taxon
    notation and flag which of them are irreducible

-   `compute_group_priors()`: aggregate occurrence-model shares to
    genus/family level for use as `posterior_consensus()`'s
    `group_priors`

-   `add_unreferenced_prior_mass()`: give each placeholder row (an
    unreferenced local relative of a candidate) the prior of the local
    species that actually lack references, instead of the generic
    dark-diversity floor. Without it, when no named candidate fits the
    site, a poor candidate can win by default, because probability is
    shared only among the candidates present. With `named_rows = TRUE`,
    each such species gets its own row and can be reported by name

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

-   Two workflows: the full Bayesian workflow uses calibrated
    likelihoods from TaxaLikely's hierarchical model and
    spatially-explicit priors from TaxaExpect's kernel-based composition
    estimator; the LLM-Bayesian workflow uses exponential score
    weighting ($L_i = e^{\lambda s_i}$) and LLM-estimated priors with
    information-quality-driven Beta concentration.

The sections below follow the pipeline. Each names the function it
describes, and each argument is written as
`function(argument = default)`.

### Priors: `join_priors()` and `add_unreferenced_prior_mass()`

-   Even unrecorded taxa get non-zero priors. "Dark diversity" is an
    ecological concept (Pärtel et al. 2011) for species that belong to
    the regional species pool and could plausibly occur at a site given
    its environmental conditions, but have not actually been observed
    there yet. TaxaExpect computes per-species Tier 3 ("undetected
    species") estimates using this concept; see TaxaExpect's README. For
    species with no prior row from TaxaExpect at all, `join_priors()`
    builds its own fallback from those Tier 3 estimates, site-level or
    global averaging, or (with `join_priors(singleton_taxonomy = )`)
    mass-conserving hierarchical group priors. This prevents false
    negatives from incomplete occurrence data and allows novel species
    discovery. See `join_priors()`'s own documentation for the full
    mechanism.

-   `add_unreferenced_prior_mass()` gives each placeholder row (an
    unreferenced local relative of a candidate) the prior of the local
    species that actually lack references, instead of the generic
    dark-diversity floor. With
    `add_unreferenced_prior_mass(named_rows = TRUE)`, each such species
    gets its own row and can be reported by name; the default (`FALSE`)
    keeps them pooled in the placeholder.

### Posteriors: `compute_posterior()`

-   Monte Carlo uncertainty propagation: priors are modelled as
    Beta($\alpha$, $\beta$) distributions and likelihoods as
    Normal(mean, sd); `compute_posterior(n_sims = 1000)` simulations
    propagate both sources of uncertainty into posterior means, SDs, and
    confidence scores (fraction of simulations won).

-   Posteriors are normalised over the candidates for an observation.
    Placeholder (unreferenced) rows keep some of that probability mass,
    so a named candidate cannot win just because its alternatives have
    no reference.

### Consensus: `posterior_consensus()`

Consensus picks one call per observation from the candidates'
posteriors. This becomes complicated when different taxa have
competitive scores.

-   Lowest common ancestor, the conventional default
    (`posterior_consensus(consensus_method = "lca")`): candidates below
    `min_posterior = 0.05` are dropped, then the rest are accumulated in
    decreasing order until they reach `cumulative_threshold = 0.90` of
    the posterior. If more than one taxon remains, the call is their
    lowest common ancestor: e.g., a shared genus or family.

-   Weighted LCA, or node summing
    (`posterior_consensus(consensus_method = "credible_node")`): reports
    the most specific taxon whose descendants together hold at least
    `cumulative_threshold` (90%) of the posterior. Picture the
    candidates as the tips of a tree, each holding a posterior, and sum
    toward the root until a node holds 90% of the probability mass. This
    is the analogue of MEGAN's weighted LCA. Unlike LCA, it does not
    discard candidates below 5%, so many weak alternatives still count
    against a species call.

-   Slim prior information can be discounted
    (`posterior_consensus(robust_prior_s = 1)`, credible node only).
    This reduces the chance that a call rests on chance variation in a
    few occurrence records (an imprecise-Dirichlet neighbourhood; Walley
    1996). Here, a marginal call whose candidates' priors rest on few
    records is moved up to a coarser rank. The site's record count is `prior_site_records`, which
    `join_priors()` carries from the kernel prior; the bound is reported
    as `robust_lower_posterior`.

-   Cross-phylum rule (`posterior_consensus(cross_phylum_eps = 0.05)`,
    credible node only). In rare cases, competing candidates come from
    different phyla. If the second phylum holds at least 5% of the
    posterior, the evidence cannot really tell the phyla apart, so the
    call is held at phylum or coarser. With
    `posterior_consensus(backbone_id = )`, a group that one source
    treats as a phylum and another places inside a phylum is recognised
    as one lineage, not counted as a competitor; without `backbone_id`,
    names are compared, with a message.

-   Downranking (`posterior_consensus(species_reference = )`, off unless
    a species list is supplied) refines a coarse call using the site's
    species list. If a call stops at genus and the site has only one
    recorded species in that genus, the call becomes that species. For
    example, *Girella* at a site where only *G. nigricans* is recorded
    becomes *G. nigricans*. Safeguard
    (`posterior_consensus(downrank_requires_candidate = TRUE)`): the
    species must be one of the observation's own candidates, with at least
    `min_posterior` (5%), so the list can choose among the candidates
    but never introduce a new one. `downranked = TRUE` marks these
    calls.

-   Taxonomy lookups
    (`posterior_consensus(lookup_missing_taxonomy = TRUE)`): placeholder
    rows arrive without a full classification, so their family, order
    and so on are looked up online. The lookup uses each row's rank, so
    a name used at two ranks (such as a genus and a subgenus) resolves
    correctly. A failed lookup (e.g., no internet) is marked
    `"lookup_failed"`, not `"not_found"`, and is not saved, so a rerun
    tries again.

-   Deterministic ties (convention): candidates with exactly equal
    posteriors are ordered by name in byte order, so the leading taxon
    in `plausible_taxa` and `plausible_top` is the same on every machine
    and locale. Calls never change on a tie, since tied species already
    back off to their LCA; only which of several equals is listed first.

### Round 2: `update_prior_from_consensus()`

A species confidently identified in one observation is assumed to be more
likely present in other observations from the same sample or site
(set by `update_prior_from_consensus(detections = )`; study-wide only if
none is given), so its prior is raised there, analogous to shrinkage
estimators (Efron and Morris 1973). Safeguards:

-   Each supporting observation counts only partly
    (`confirmation_discount = 0.25`: about four observations count as
    one), and the raise is capped (`max_raise_factor`).
-   Only candidates with references give or receive support.
-   A raise cannot override the likelihood: the species must already
    lead on likelihood alone, by more than the noise, and have a local
    occurrence record.
-   If Round 2 would still create a species call that the likelihood
    alone does not support, every raise in that observation is undone.

Each safeguard reports how many raises it blocked.

## Reading a consensus table

`posterior_consensus()` returns one row per observation. Beyond
`consensus_taxon`, `consensus_rank` and `consensus_posterior`, there are
many diagnostic columns so a user can understand how the decision was
made and possibly re-evaluate it. Most importantly, the candidates that
make up the call are kept in `plausible_taxa` (use `add_slash_taxon()`
for slash-taxon notation). Several other statistics are kept, which may
help a user interpret an unexpected finding.

-   Each consensus row keeps a record of the likelihood and prior
    contributions to the posterior. `likelihood_consensus_taxon` /
    `likelihood_consensus_rank`: the call the likelihoods alone support
    (e.g., what a score-based consensus would have likely called).
    `prior_role` indicates consistency with the likelihood (`"agrees"`,
    `"narrowed"`, `"broadened"`, `"changed"`), and `likelihood_support`
    reports the share of that likelihood in the consensus: e.g., 0.84
    means the likelihood is the deciding factor, 0.10 means the prior
    determines the outcome.
-   `consensus_limit` (credible node): why the call stops short of
    species: `"threshold"` (mass spread across alternatives),
    `"robust_prior"` (the bound above), `"cross_phylum"`, `"backbone"`
    (lineage gaps in the backbone at a finer rank) or
    `"rank_not_supplied"`.
-   `robust_lower_posterior`, `tail_mass`, `unnamed_mass`,
    `tail_pooled`, `lineage_conflict`: the quantities behind the rules
    above.
-   `downranked`, `winner_rank_expanded`, `consensus_hypothesis_type`,
    `consensus_unreferenced_scope`: whether the name came from the
    reference or the records rather than from a match.
-   `unreferenced_taxonomy_lookup`: `"matched"`, `"not_found"` or
    `"lookup_failed"`; a filter for `"matched"` never keeps a failure.
-   `winner_has_occurrence_record`, `consensus_has_occurrence_record`,
    `consensus_prior`: whether the called taxon has a local occurrence
    record, read by `TaxaFlag::add_posthoc_assessment()`.

Note that a consensus is proposed per observation. This means the
identical information (image, sound, sequence) can point to a different
taxon depending on the prior (which might vary across sites or visits,
habitats, or other contexts). This is particularly likely for vague
information which is more likely decided by the prior than by the
likelihood.

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
