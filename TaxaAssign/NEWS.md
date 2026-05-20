# TaxaAssign (development version)

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
