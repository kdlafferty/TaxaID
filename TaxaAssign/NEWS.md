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
* Every `registry =` argument refuses a registry edited after
  `freeze_taxon_registry()`, as `attach_taxon_ids()` does, through the shared
  check `TaxaTools::registry_ids_for_names()` (error class
  `taxon_registry_invalid`).
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
  the ring's rank or above, or no id at all) is missing data in that search,
  not a lineage of its own, and its member clade is never dropped, so the
  ring is never named finer than its members; a member clade whose candidates are all unplaced is represented by
  the registry's own taxon of that name (one id, at the ring's own rank), and
  one with neither is not guessed. `attr(, "ring_rows_rekeyed")` lists
  `n_unplaced_candidates` and `member_clades_from_registry` for each such ring.
* `add_unreferenced_prior_mass()` always attaches
  `attr(, "ring_member_clades_withheld")`; without a registry it is an empty
  table.
* Without a registry (`registry = NULL`), `join_priors()` matches likelihoods
  and priors by name, so both must use one naming: a call under a name the
  priors file under another (an NCBI name against the GBIF accepted name, say)
  takes the global floor, and only `join_priors()`'s message reports it. With
  `registry =` such names meet by identifier.
* Ring hypotheses are typed by any rank of the caller's rank system
  (`unreferenced_infraorder`, `unreferenced_subclass`, ...): `join_priors()`
  keeps them, and a ring's own rank is the rank above its type in that rank
  system.
* `join_priors()` stops with a message when the likelihoods have no lineage
  columns (`family`, and `genus` without a registry) and `taxonomy_lookup`
  does not supply them; fill them with `TaxaTools::fill_higher_ranks()`, or
  from the registry with `TaxaTools::parent_at()`.
* `add_unreferenced_prior_mass(rank_system = )` (`NULL` by default: the
  standard ranks) reads the run's rank system: a ring at an intermediate rank
  (an `unreferenced_family` ring at infraorder, an `unreferenced_order` ring at
  subclass) gets its scope and the unreferenced mass of its local relatives.
  A ring row whose type the ranks in use cannot place keeps the floor prior,
  and a message counts such rows.
