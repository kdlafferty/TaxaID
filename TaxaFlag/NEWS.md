# TaxaFlag 1.0.0

* Initial release.
* `report_flags()` detects reference-support columns from
  `TaxaLikely::annotate_reference_support()` and reports their distribution and
  basis breakdown alongside the flags, deliberately outside every flag count:
  they say how much reference data stood behind a call, which neither accuses
  nor clears it.

## New features

* `screen_assignments()` is a post-hoc screen over reviewed calls, one row per
  taxon and site. An identity layer asks whether the name is right, from the
  sequence fit and the reviewer's geography: a good fit where the geography is
  plausible is kept; a good fit where it is unlikely moves up to a local,
  referenced relative that scores as well, or else is marked for review with a
  suggested exclusion; a poor fit moves up one rank (genus- and species-rank
  calls only) or is excluded where geography is unlikely or, at family rank or
  finer, habitat is unlikely. A presence layer then labels each surviving row
  `resident`, `off_habitat` or `out_of_scope` from the habitat and scope
  verdicts; it never excludes by itself, so habitat-filtered reporting decides
  what to drop. `blank_flag_col` adds blank evidence as an exclusion.
  The screen flags and never drops a row, and `attr(, "rule_counts")` reports
  how many rows each rule fired on, and which rules could not be evaluated.
* `review_assignments(sites =, site_col =)` makes geography site-aware. Given
  the study sites with their coordinates, the reviewer states where in the
  study area each taxon is plausible -- a latitude range, a list of sites, or
  everywhere -- and the result is a per-row
  `llm_geographic_plausibility_site` column, with the parsed rule in
  `attr(, "geographic_by_site")`. The study-wide
  `llm_geographic_plausibility` becomes the best verdict across sites. A
  malformed answer falls back to the study-wide verdict at every site. With
  `sites = NULL` the prompt, cache key and output are unchanged.
* `review_assignments()` asks the reviewer for a PROBABILITY per judgement
  rather than a category, and derives the `llm_*_plausibility` and
  `llm_contamination_risk` verdicts from it in code: `unlikely < 0.10 <=
  possible < 0.70 <= likely`, contamination `low < 0.20 <= moderate < 0.70 <=
  high`. The probabilities are returned too, as `llm_p_*`. A cut is applied
  after the cache rather than before it, so changing one takes effect for taxa
  already cached without a single new call.
* The review is shown DNA evidence and the study's own design, and no text
  derived from occurrence records. It sees the best match identity for every
  taxon, whether that match clears any rank threshold for the marker, whether
  a confusable relative could match as well, and whether any reference
  sequence exists for the name -- the evidence the identification rests on,
  which a reviewer judging that name needs. The
  `consensus_posterior_col`, `winner_prior_col`,
  `plausible_posteriors_col`,
  `dist_nearest_occupied_km_col`, `patch_diameter_km_col`,
  `beyond_buffer_col` and the three `inat_*` arguments of
  `review_assignments()` default to `NULL`, so none of those values reaches
  the prompt and the guideline that explains them is not assembled. A review
  shown the pipeline's own confidence cannot contradict it independently, and
  a review shown a taxon's GBIF distance cannot catch an error in the
  occurrence data -- which is one of the things it is for. Pass the column
  names to send any of them. The UNPRECEDENTED flag is read without being
  shown: "no local occurrence record at all" stays out of the prompt, while
  `geographic_disagreement_basis` is still computed from it, so the
  deterministic check for a taxon called plausible where the records hold
  nothing survives the change. Scored against the maintainer's labels, a
  review told the pipeline's numbers and a review told none of them agreed
  with him equally well.
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
