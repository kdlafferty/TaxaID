# TaxaAssign (development version)

## 2026-09-12

* `combine_multisite_priors()` no longer returns `NaN`/`Inf` priors when every
  site's prior for a candidate is J-shaped (`alpha <= 1`: the dark-diversity
  floor, singleton mirrors, evidence-blend rows). The logit-space rule
  underflowed to a mean of exactly 0 there; such candidates now combine on
  the probability scale. Found on the first real multi-site run (PtConception
  12S, 349 of 4,469 rows); moderate priors and mixed J-shaped/informative
  cases are unchanged.
* `score_consensus(consensus_mode = "bracket")`: implements Jonah Ventures'
  actual published rule (1% bracket anchored at the ESV's top score, a taxon
  reported at a rank only when it holds >= 90% of the hits in that bracket,
  widened to 2% when a 97%+ match returns no family). `"gap"` mode is
  unchanged and remains the default. The roxygen's earlier claim that gap
  mode reproduced "the GITA/Jonah Ventures convention" was wrong and has
  been removed.

## 2026-09-07

* `update_prior_from_consensus()`: veto-bound cap and variance carry-through
  (a691025).
* Three bugs fixed from the post-review audit (c92398d).

## Polishing Phase (Sessions 57-59)

* New high-level wrappers: `run_bayesian_pipeline()` (~10 calls into 1)
  and `run_llm_pipeline()` (~7 calls into 1).
* `assign_taxa_llm()`: new `prior_weight_guide` param exposes previously
  hardcoded LLM prior weight ranges.
* `posterior_consensus()` and `score_consensus()`: new `consensus_reason`
  output column.
* Replaced inline rank definitions with `TaxaTools::standard_ranks` /
  `TaxaTools::detect_ranks()`.
* DESCRIPTION title and description rewritten for CRAN compliance.
* Added vignettes: taxonomic-assignment.Rmd and taxaid-ecosystem.Rmd
  (ecosystem overview).
* Added tests: join_priors, update_prior, and 28 cross-package integration
  tests.
