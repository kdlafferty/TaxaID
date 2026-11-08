# TaxaLikely 1.0.0

* First public release.
* Trains a hierarchical Bayesian model on reference-against-reference match
  scores -- DNA percent identity, image similarity, acoustic scores -- and
  uses it to convert per-observation scores into likelihoods.
* Produces score_likelihood, score_likelihood_mean and score_likelihood_sd
  across candidate taxa for each observation, the columns TaxaAssign requires.
* Builds and audits reference databases: fetches reference sequences, detects
  mislabeled and cross-lineage records, and reports taxonomic completeness
  against the taxa a study could plausibly encounter.
* Expands the candidate set to taxa that have no reference of their own, so a
  species absent from the database can still be considered.
