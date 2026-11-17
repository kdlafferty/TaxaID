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
* `add_unreferenced_prior_mass()` counts a local unreferenced species toward
  a placeholder hypothesis only at the finest rank where its lineage has a
  referenced taxon for the marker (`withhold = "finest"`, the default);
  `withhold = "genus"` applies that test at genus only.
* `join_priors(taxonomy_cache_dir = )` passes a name cache to the taxonomy
  fallback's lookups, so a rerun with a filled cache makes no name requests.
* Provides empirical Bayes prior refinement and a score-based consensus for
  comparison, and generates a report of the assignment run.
* With a frozen taxon registry, `join_priors()`, `add_unreferenced_prior_mass()`
  and `posterior_consensus()` (`registry =`, off by default) match taxa by
  registry identifier instead of by name: a call under a synonym finds the
  prior filed under the accepted name, one taxon under two names is one
  hypothesis, lineage comes from the registry's tree (no backbone lookup), and
  output names are the registry's accepted names, with each row's own name kept
  in `taxon_name_verbatim`. `posterior_consensus()` keys `group_priors` and
  `species_reference` by registry identifier as well, and refuses a name in
  either that the registry does not hold.
* A ring row with `ring_member_clades` set gets, in
  `add_unreferenced_prior_mass()`, the prior mass of the union of its member
  clades at the ring's own rank, not of everything under the rank it is named
  at; with `registry =`, a member clade with no single registry id, or with an
  id at another rank, is withheld and listed in
  `attr(, "ring_member_clades_withheld")`. In `join_priors(registry =)` such a
  ring is keyed at the registry's lowest common ancestor of the observation's
  candidates in its member clades, which can be finer or coarser than the
  likelihood table's label, and its `ring_lca_status` becomes
  `"lca_registry"`; it is listed in `attr(, "ring_rows_rekeyed")` with outcome
  `"lca_registry"` (or `"lca_registry_none"` where no ancestor is shared). Both
  apply to a ring that kept its anchor's label (`"anchor_fallback"`) as well.
  A candidate the registry could not place (a run-local id with no ancestor at
  the ring's rank or above) is missing data in that search, not a lineage of
  its own; a member clade whose candidates are all unplaced is represented by
  the registry's own taxon of that name (one id, at the ring's own rank), and
  one with neither is not guessed. `attr(, "ring_rows_rekeyed")` lists
  `n_unplaced_candidates` and `member_clades_from_registry` for each such ring.
