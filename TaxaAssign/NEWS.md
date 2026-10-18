# TaxaAssign 1.0.0

* Initial release.

## New features

* `compute_posterior()` pools named unreferenced rows (species-rank
  `unreferenced_species` or `unreferenced_genus` rows) whose point posterior
  is below 0.05 into their ring row, per observation. Pooled rows share their
  ring's likelihood, so the ring's posterior equals the sum of its own and the
  pooled rows' exactly (checked to 1e-12), and the ring's Beta prior is
  moment-matched to the summed mean and variance. Where the ring is coarser
  than genus, a genus whose pooled posteriors sum to 0.05 or more keeps its
  rows. The output has the columns `pooled_n`, `pooled_prior_mass` and
  `pooled_taxa` (all `NA` on non-ring rows) and the attributes `pooled_rows`
  (one row per pooled row) and `pooled_min_posterior`, always present. The
  output can have fewer rows than the input.
* `compute_posterior()` passes the posterior of a closed-genus placeholder (a
  row marked `census_closed_genus_relabeled`) to the genus's referenced
  species in proportion to their own posteriors, on the point estimate and in
  every Monte Carlo simulation. If every species of a genus is sequenced, an
  unsequenced congener is impossible and its mass belongs to the genus. A
  placeholder with no referenced member in the observation keeps its
  posterior; a message counts both cases.
* `add_unreferenced_prior_mass()` is exported. With `named_rows = TRUE` it adds
  one named row per recorded unreferenced local species, carrying its ring's
  likelihood and the species' own occurrence prior. Only a species claimed by
  its own genus ring is named; a family, order, class or phylum ring stands
  for "some unreferenced taxon of this clade", so the species it claims add
  their prior to that ring row unnamed. A species of a genus that has a
  reference for the marker is claimed only by its genus ring and is withheld
  from coarser rings; the withheld rows are in `attr(, "unreferenced_withheld")`
  and every claimed species in `attr(, "unreferenced_scope_members")`.
* `posterior_consensus()` never downranks a call to a species when the call's
  winning hypothesis (`winner_hypothesis_type`) is an unreferenced ring: the
  read fitted an unreferenced relative better than any referenced candidate,
  so naming a referenced species would contradict it. A coarser narrowing
  (family to genus) is still taken, and blocked steps are counted in a
  message.
* `posterior_consensus()` passes `best_identity`, `best_identity_rank` and
  `poor_absolute_fit` from `TaxaLikely::evaluate_likelihoods()` through to the
  consensus table. They are flags only and never change the call.
* `posterior_consensus()` reports what kind of row the final call landed on:
  `consensus_hypothesis_type`, `consensus_unreferenced_scope` and
  `consensus_unreferenced_scope_rank`. These describe the call
  (`consensus_taxon`), whereas `winner_*` describes the highest-posterior
  hypothesis.
* `posterior_consensus(consensus_method = "credible_node")` reports the finest
  taxon holding at least `cumulative_threshold` (above 0.5) of the posterior of
  all rows, from each row's own (rank, name) ancestry. `consensus_limit` says
  why a call is coarser than the finest rank, and `lineage_conflict` reports a
  name used with two lineages within an observation.
* `posterior_consensus(robust_prior_s = 1)` keeps a credible-node call only if
  it survives `s` further records of the best-fitting outside taxon, so a
  marginal call resting on a few site records is coarsened. An outside taxon
  gains at most one record and a node the sequence reaches keeps its own
  recorded member. A skip (missing inputs or no record count) is announced by
  one warning per call.
* `posterior_consensus(cross_phylum_eps = 0.05)` withholds a call finer than
  phylum when the runner-up phylum holds at least that share of the posterior.
  Lineages, not phylum name strings, are compared.
* `update_prior_from_consensus()` pools confirmation evidence within groups
  (`group_cols`, default `"sample_id"`). It raises a row only if the row lies
  inside the observation's likelihood-only credible node, has an occurrence
  record (`theta_mean`) and scores at least as well as every other candidate,
  unreferenced hypotheses included, so a prior boost cannot overturn the
  likelihood ordering. A raise is bounded by `max_raise_factor` (default 2000) times the
  row's prior. The receiver guards need `likelihood_consensus_taxon`,
  `likelihood_consensus_rank` and `theta_mean`; `require_support_columns =
  TRUE` stops, naming any that is missing.
* `add_slash_taxon()` keeps a one-word name (a genus or family ring) whole and
  as its own group, so labels read "Atractoscion + Umbrina + Sciaena umbra"
  instead of repeating the genus.

## Changed behaviour

* `join_priors()` gives the floor-priced ring rows of one observation (at one
  site) a single shared global floor: each of `k` such rings gets floor / `k`,
  with its concentration kept. A unit detects one taxon, so unreferenced prior
  mass does not grow with the number of candidate genera. A ring priced by a
  clade dark-diversity budget is unchanged. Each clade's budget is shared
  among its unrecorded candidates, shrunk toward the parent, and the remainder
  goes to the unsequenced-relative rings.
* `join_priors()` fills a family from a genus only when the genus has one
  family, does not delete unreferenced hypotheses in its redundancy filter,
  and passes `input_rank` to the name verifier so a homonym is resolved by
  rank.
* `combine_multisite_priors()` counts each site once and sums
  `prior_site_records` across the sites it combines. Blank rank values are
  treated as missing throughout.
* `posterior_consensus()` downranks a call to the reference's single finer
  taxon only if the plausible set places at least `min_posterior` on that
  taxon's node (summed over the node), so a target the sequence had excluded
  cannot take the name. Exact ties among candidates are ordered by taxon name
  in byte order, so `plausible_top` and `consensus_hypothesis_type` do not
  depend on input row order.
* `posterior_consensus(pool_tail = FALSE)` is the default: hypotheses below
  `min_posterior` are excluded and `cumulative_threshold` is measured against the remaining
  mass; `pool_tail = TRUE` pools them into one tail block instead.
