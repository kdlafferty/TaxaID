# Consensus Taxonomy Methods — Comparative Overview
# How different tools assign a consensus taxon from eDNA match data
# Last updated: 2026-05-31

---

## Background

Every eDNA pipeline must answer the same question: given that an observed
sequence (or sound clip, or image) matches multiple reference taxa with
similar scores, what is the consensus taxonomic assignment and how confident
should we be? The tools and services available take meaningfully different
approaches to this problem, with real consequences for sensitivity, specificity,
and the handling of taxa missing from the reference database.

This document surveys the major approaches in current use and positions the
TaxaID Bayesian workflow relative to them.

---

## The Core Problem

A match object typically contains multiple candidate taxa per observation, each
with a similarity score. Three challenges arise:

1. **Score ambiguity** — multiple taxa score similarly; no single winner is clear.
2. **Reference gaps** — the true source taxon may have no reference sequence
   at all, so it can never appear as a named candidate.
3. **Geographic plausibility** — a high-scoring reference taxon may be
   biogeographically implausible at the sampling location.

Methods differ in whether and how they address each challenge.

---

## Method Comparison

| Method | Tool(s) | Approach | Handles unreferenced taxa | Geographic / occurrence data | Probabilistic output | How upranked consensus is reached |
|---|---|---|---|---|---|---|
| **Score threshold** | Legacy OTU pipelines | Fixed % identity cutoff; assign at species level if score ≥ threshold, else drop or assign to higher rank | No — dropped or pooled with no modelling | No | No | Manually set thresholds per rank (e.g., ≥97% species, ≥95% genus) |
| **100% match + LCA** | Wilderlabs | Only perfect matches retained; LCA resolves ties among them | No — any imperfect match is discarded | No | No | LCA when multiple taxa share 100% match |
| **LCA** | MEGAN, Kraken, Bracken | Retain hits within a score window of the best; assign to lowest common ancestor | Partial — LCA may reach genus or family, but the cause is ambiguity not modelling | No | Confidence score only (fraction of reads agreeing) | Automatic via LCA traversal |
| **Consensus LCA** | Jonah Ventures (DADA2 + BLAST) | (1) Keep hits within 1% of best score. (2) At each taxonomic level, keep assignment if >90% of retained hits agree. (3) LCA for remaining ambiguity | No | No | No | 90% agreement filter at each rank before LCA |
| **Phylogenetic placement + LCA** | Tronko / eDNA Explorer | Place query on gene tree (including inner nodes); LCA for near-ties; GBIF occurrence overlay post-hoc | Partial — inner node placement approximates an unreferenced taxon; no explicit modelling | Post-hoc visual overlay only (GBIF); not integrated into assignment | No | Automatic via inner node or LCA; GBIF comparison flags implausible results |
| **Bootstrap classifier** | DADA2/DECIPHER IDTAXA, SINTAX | Pseudo-bootstrap confidence across reference subsets; assign at finest rank exceeding confidence threshold | No | No | Bootstrap confidence (not a posterior probability) | At user-specified confidence threshold |
| **Coverage-weighted LCA** | galaxy-tool-lca | LCA weighted by query coverage (qcovs); penalises partial-alignment hits | No | No | No | Automatic, coverage-weighted |
| **Bayesian likelihood + prior** | **TaxaLikely + TaxaAssign** | Model score distributions (H1/H2/H3); multiply by occurrence-based priors from TaxaExpect; compute posterior probability | Yes — H2 (unreferenced species, genus represented) and H3 (unreferenced genus) hypotheses; no-score pathway via `expand_consensus_candidates()` | Integrated: TaxaExpect priors encode occurrence and habitat data before assignment | Yes — posterior probability + SD per hypothesis | Explicit candidate expansion: genus/family consensus → species candidates from priors; posteriors decide |

---

## Key Distinctions

### Reference gap handling

Every non-Bayesian method collapses the reference coverage problem into a
binary: a species either has a reference sequence and could appear as a
candidate, or it does not and is invisible to the pipeline. None have a
mechanism for reasoning that "this species has no reference sequence but is
highly plausible given where we sampled."

TaxaLikely models this explicitly via H2 (unreferenced species whose genus is
represented) and H3 (unreferenced genus) hypotheses. When no match scores are
available at all, `expand_consensus_candidates()` adds species with TaxaExpect
priors as candidates with uniform likelihoods, so posteriors reflect geographic
plausibility even in the absence of barcode evidence.

### Geographic / occurrence data

The closest analog to geographic integration in non-Bayesian tools is eDNA
Explorer's post-hoc GBIF comparison: after consensus is assigned, users can
visually check whether the result appears in GBIF near the sampling location.
This is a useful sanity check, but it is:

- **Post-hoc**: occurrence data does not influence the assignment, only flags it
- **Binary**: GBIF presence/absence, not a continuous plausibility estimate
- **Manual**: requires user interpretation rather than an automatic update

TaxaExpect priors encode occurrence and habitat data as a continuous Beta
distribution *before* assignment. When multiplied by the likelihood, the prior
updates the posterior in proportion to geographic plausibility — species common
at the sampling location receive higher posteriors even when their match score
is similar to a geographically unlikely alternative.

### Score thresholds vs. score distributions

Score threshold methods (including the 100% match approach and divergence
filters) treat a cutoff as a proxy for confidence: scores above the line are
trusted, scores below are not. The cutoff is chosen heuristically and applies
uniformly regardless of the taxon.

TaxaLikely instead models the *distribution* of scores expected for a true
match (H1) versus a near-miss (H2/H3). A 97% identity is strong evidence for
some taxa and weak evidence for others, depending on within-species variance in
the reference. The likelihood reflects this: it is high when the observed score
falls near the species-specific mean, and low when it falls in the tail.

### The Jonah Ventures consensus LCA

The Jonah Ventures pipeline is the most resolution-preserving non-Bayesian
approach in common use. The 90% agreement filter at each taxonomic level
prevents unnecessary upranking: if 9 of 10 near-best hits agree on genus X,
the assignment stays at genus rather than being forced to family by one
discordant hit. This is a discrete approximation of what a posterior
probability threshold achieves in the Bayesian framework, without requiring
a model or priors.

Its main limitation, shared with all LCA methods, is that it has no mechanism
for expressing uncertainty quantitatively. An assignment that barely cleared
90% agreement looks identical in output to one with 100% agreement.

### Wilderlabs: the conservative extreme

Wilderlabs' 100% match requirement is the most conservative defensible
threshold. Any imperfect match is discarded rather than assigned at a coarser
rank. This minimises false positives at species level at the cost of
substantial missed detections — any species not perfectly represented in the
reference library (common for non-model organisms or degraded eDNA) is
systematically underdetected. This trade-off is appropriate for applications
where a false positive is worse than a false negative (e.g., regulatory
species lists), but will underestimate richness in community ecology contexts.

---

## The No-Score Pathway

When observations have a consensus taxon but no match scores — morphology-based
identifications, expert IDs, upranked consensus from a previous run, or
legacy databases — TaxaLikely provides `expand_consensus_candidates()` as an
alternative entry point.

This function builds a degenerate likelihood object (all likelihoods = 1.0)
and populates the candidate set from TaxaExpect priors:

- **Species-level consensus**: adds unreferenced congeners (species with priors
  but no reference sequence); referenced congeners that would have competed via
  scores are excluded
- **Genus/family-level consensus**: adds all species in the group with priors,
  regardless of reference status — score discrimination already failed

Because all likelihoods are uniform, `TaxaAssign::compute_posterior()` produces
posteriors proportional to priors. This is Bayesian assignment using occurrence
data only, with no barcode evidence — analogous to eDNA Explorer's GBIF
comparison but integrated into the probability pipeline rather than applied
post-hoc.

See `TaxaLikely/inst/workflows/6_no_score_pathway_workflow.R` for the full
implementation.

---

## Summary

| Challenge | Threshold / LCA methods | TaxaLikely + TaxaAssign |
|---|---|---|
| Score ambiguity | Heuristic cutoff or LCA | Likelihood model over score distributions |
| Reference gaps | Not addressed | H2/H3 hypotheses; `expand_consensus_candidates()` |
| Geographic plausibility | Post-hoc flag (eDNA Explorer) or absent | Integrated prior from TaxaExpect |
| Uncertainty quantification | None or bootstrap confidence | Posterior probability + SD |
| No-score observations | Not applicable | `expand_consensus_candidates()` with uniform likelihood |
