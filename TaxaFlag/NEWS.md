# TaxaFlag 1.0.0

* Initial release.
* `report_flags()` detects reference-support columns from
  `TaxaLikely::annotate_reference_support()` and reports their distribution and
  basis breakdown alongside the flags, deliberately outside every flag count:
  they say how much reference data stood behind a call, which neither accuses
  nor clears it.

## New features

* `flag_backbone_conflicts()` flags a name that the taxonomy carries at more
  than one rank, or under more than one parent at the same rank, learned from
  the data rather than from a list of taxa. It cannot see synonymy (many names
  for one organism), so zero conflicts says nothing about duplicate organisms.
* `review_assignments()` takes `poor_absolute_fit_col` and `best_identity_col`
  (defaults `"poor_absolute_fit"` and `"best_identity"`; `NULL` disables). When
  a taxon's best raw match falls below every rank threshold for its marker, the
  reviewer is told so, with the identity, and a guideline states that a weak
  match makes the NAME uncertain at the called rank but is not by itself
  grounds for an "unlikely" habitat, geography or scope rating. Likelihoods are
  normalised to the unit maximum, so a poor best match can otherwise be called
  confidently.
* `review_assignments(consensus_provenance = TRUE)` tells the reviewer when a
  call's name came from the occurrence records rather than the sequence: the
  call landed on an unreferenced relative, with the scope and its rank, and
  whether the records offered one candidate or several. The sequence settled
  only that an unreferenced relative beats every referenced candidate.

## Changed behaviour

* `review_assignments()` states "no reference sequence" only for a reviewed
  label that is itself a named unreferenced species. The line follows the
  label, not the call, so a referenced species that some units call at a
  family ring does not carry it.
* `review_assignments()` judges geography on evidence and at the call's rank.
  An "unprecedented" pipeline flag caps the rating at "possible" unless there
  is specific local evidence and never inverts it ("unlikely" needs positive
  out-of-range evidence); the indistinguishable-sequence flag weakens the name,
  not the ecology. When the reviewed label is not the call, the prompt shows
  "pipeline call: <taxon> (<rank>)" and treats the call at its rank as the
  claim.
* Each taxon line sent by `review_assignments()` carries an id (`[T<i>]`) that
  the answer echoes; answers are matched by id, then by name. A response that
  matches none of several sets counts as failed so the halving retry runs, and
  a re-ask that recovers nothing switches to one set per call.
* `review_assignments()` combines `geographic_hint` and the synthesised
  ecoregion of a `build_context()` result as "hint (ecoregion)" when no
  explicit `geography` is given. The ecoregion is one string for the whole
  taxon list, so pass `geography` to control the line on a multi-ecoregion
  study.
* The default `llm_fn` calls `TaxaTools::call_api()` with the provider's
  default and sends no temperature, because some current models reject the
  parameter. The review cache key carries a version string and fingerprints the
  deparsed source of `llm_fn`: a temperature, model or provider written
  literally into it moves the key, while one supplied indirectly (a variable,
  option or closure) does not, so use a new `cache_dir` or `model_label` after
  changing such a value.

## Bug fixes

* `check_gbif_tile_range()` marks a tile that returns an HTTP status other than
  200 or 204 as `tile_fetch_failed` (an attribute on the verdict) and does not
  cache it, so an outage is
  not stored as an absence of records.
