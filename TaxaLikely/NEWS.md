# TaxaLikely 1.0.0

* First public release.
* Trains a hierarchical Bayesian model on reference-against-reference match
  scores -- DNA percent identity, image similarity, acoustic scores -- and
  uses it to convert per-observation scores into likelihoods.
* Produces score_likelihood, score_likelihood_mean and score_likelihood_sd
  across candidate taxa for each observation, the columns TaxaAssign requires.
* Builds and audits reference databases: fetches reference sequences, removes
  cross-lineage (homonym) contamination from them, and reports taxonomic
  completeness against the taxa a study could plausibly encounter.
* Expands the candidate set to taxa that have no reference of their own, so a
  species absent from the database can still be considered.
* `evaluate_likelihoods()` evaluates the species (H1) density's score term at
  `min(score, mean)` by default (`h1_clamp = TRUE`), so a match better than a
  species' trained mean is never scored lower than one at the mean. This
  matters for a species trained on one divergent reference pair, where the
  unclamped density could rank a 100% match below a much weaker match to a
  congener. `h1_clamp = FALSE` gives the unclamped density.
* `train_likelihood_model()` attaches a reference-consistency table,
  `attr(model, "reference_consistency")`, built from the library's own pairs
  with TaxaMatch's reference-screen functions plus one stated rule for species
  with two references. By default (`exclude_reference_suspects = TRUE`) the
  model is fitted without the references the table marks suspect; they stay
  candidates at evaluation. `exclude_reference_suspects = FALSE` makes the
  table a report only and fits on every reference. Exclusion is the default
  because most users will not screen references separately, and on held-out
  tests with two fish 12S libraries it scores within 0.01 of fitting on
  everything in every cell. TaxaLikely imports TaxaMatch.
* `restore_suppressed_candidates(registry = )` (off by default): with a frozen
  taxon registry, a reference congener whose identifier equals a candidate's is
  not restored as a second candidate, and `candidate_species_filter` matches a
  reference species under any registered name.
* `evaluate_likelihoods()` returns `ring_member_clades`. When the candidates
  tied with an observation's ring anchor (the top transformed score, within
  1e-9, with a real hit preferred over a restored row) hold two or more values at an outer
  ring's rank, that ring is named at their lowest common rank, searching the
  match table's coarser lineage columns too and requiring every tied candidate
  to hold the common value, and `ring_member_clades` lists their values at the
  ring's own rank, separated by `|`; `ring_lca_status` is `"lca"`. When no
  rank among the available lineage columns is common to them, the ring keeps
  the anchor's label, `ring_lca_status` is `"anchor_fallback"`, the members are
  still listed, and `evaluate_likelihoods()` reports the count in a message.
  Both columns are `NA` on every other row. The ring's likelihood is unchanged:
  it is still evaluated at the anchor the tie-break picks, which shares the
  tied candidates' score.
