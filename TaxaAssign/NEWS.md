# TaxaAssign 1.0.0

* First public release.
* Estimates the posterior probability that an observation was produced by a
  given taxon, combining likelihoods from TaxaLikely with priors from
  TaxaExpect by Monte Carlo simulation.
* Assigns consensus taxonomy at the rank the evidence supports, up to kingdom
  where the lineage columns carry it, and reports the candidate set behind
  each call.
* Combines priors across sites for multi-site studies.
* Supports updating assignments after new reference data without a full
  rerun: a documented sequence of existing calls, not a single function. The
  taxonomic-assignment vignette gives the steps, including when the likelihood
  model must be retrained, and `posterior_consensus(reference_snapshot = )`
  labels each row with the reference state it was computed against.
* Provides empirical Bayes prior refinement and a score-based consensus for
  comparison, and generates a report of the assignment run.
