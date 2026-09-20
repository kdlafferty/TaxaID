# TaxaExpect 0.1.0

## 2026-09-19

* **`generate_uncertain_habitat_evidence()` added.** `estimate_kernel_priors()`
  keeps only records whose point carries `site_habitat`, so a taxon known only
  from points the habitat consensus could not place yields no resident row --
  and the standard workflow's `setdiff(match_list, priors$taxon_name)` then
  hands it to `generate_regional_proximity_evidence()` labelled **zero-bbox**,
  priced as having no records in the search polygon at all and re-queried from
  GBIF. That claim is false: the records are in the bbox and their distance is
  already known exactly. This generator prices them from the measured distance
  to their nearest unplaceable record, on the same saturating decay the
  regional generator uses, with no network call.

  These are ordinary evidence rows carrying
  `source = "uncertain_habitat_proximity"`. They are **not** the
  `main_habitat = NA` habitat-agnostic tier -- that means "matches any
  habitat", is set deliberately by `generate_domestic_food_priors()`, and is
  read by `TaxaAssign::join_priors()` to build the domestic/food wildcard pool.
  An occurrence whose habitat could not be determined is the opposite claim.

  "Unassigned" is decided **closed-world**, from `habitat_levels` -- the
  scheme's own habitat names, which the caller already has -- not from a list
  of sentinel spellings. `NA` and `""` fall out for free, any sentinel invented
  upstream is caught with no code change, and so is a typo. The alternative
  would have made this package responsible for tracking a vocabulary it does
  not own, and the producer is not necessarily TaxaHabitat: a habitat column
  can come from a polygon layer, which is why that dependency is a *Suggests*.
  `habitat_levels` is required, with no default, for the same reason. The
  failure mode moves from silent under-recovery to a warning naming any label
  that is neither a declared habitat nor a recognisable no-verdict marker.

  Validated on a real 8,098,865-record PtConception 12S fetch: 4 taxa
  recovered (*Menidia audens*, *Dorosoma petenense*, *Fistularia corneta*,
  *Eucyclogobius kristinae*) out of 24 carrying unassigned records -- the other
  20 also hold in-stratum records, already have resident priors, and are
  skipped to avoid double-counting.

* **`calibrate_kernel_bandwidth()` gains `sampling_group_col`.**
  `estimate_kernel_priors()` had it; this did not, so lambda was fitted to one
  **pooled** composition and then handed to a per-group estimate. Composition
  is a share within a detection process, so a block's pooled log-loss is
  dominated by whichever group contributed the most records. It never
  announced itself -- the fit succeeds and returns a plausible number, just the
  wrong one for every group but the dominant one.

  Each (block, group) cell is now scored against that group's own composition
  over that group's **own species universe** (smoothing a group over the full
  species set would put `smoothing` mass on every species it can never
  contain, an invisible penalty scaling with how small the group is), and
  cells combine weighted by the target records each group contributed.

  `$by_group` reports each group's own optimum and a **warning fires at >= 2x
  disagreement**, because `estimate_kernel_priors()` still takes a scalar
  `lambda_km` and cannot act on a disagreement -- only report it. Per-group
  lambda in the estimator remains the real resolution and is not attempted here.

* **`calibrate_kernel_bandwidth(min_group_records = )` added**, defaulting to
  `min_block_records`. Block eligibility is decided from the pooled record set
  before grouping exists, so without a per-group bar a block qualifies on its
  pooled count and a thin group joins it with a handful of records -- unlike
  the other way of fitting per group, subsetting and calling this function per
  subset, where a block must carry `min_block_records` of that group's own
  records. The default makes the two routes agree on eligibility so their
  answers are comparable.

  `sampling_group_col = NULL` reproduces the previous behaviour exactly:
  verified by sourcing the pre-change file into a separate environment and
  comparing, max absolute difference in `weighted_logloss` = 0.


## 2026-09-13

* `generate_regional_proximity_evidence(tile_cache_dir = NULL)` added --
  forwarded straight through to Stage 1's
  `TaxaFlag::check_gbif_tile_range(cache_dir = )`, which gained a
  persistent, no-expiry on-disk cache the same day (see TaxaFlag's own
  NEWS entry). Stage 1 was previously re-paid in full, per zero-record
  taxon, on every re-run against unchanged data -- the 2026-09-13
  PtConception run spent 43 minutes here across 256 taxa. When
  `tile_cache_dir` is supplied, one summary line is printed at the end of
  the run reporting how many Stage 1 verdicts came from cache, how many
  were fetched, and the age in days of the oldest cache hit used, e.g.
  `"Stage 1 tile checks: 241 from cache (oldest 37 days), 15 fetched."` --
  so staleness (there is no TTL) is visible rather than silent. `NULL`
  (the default) disables Stage 1 caching entirely, matching every prior
  release of this function.

## 2026-09-12

* New `condition_evidence_on_habitat()`: multiplies an evidence table's
  presence weights by each taxon's weight for the site habitat (from the same
  LLM habitat lookup that stratifies the resident priors), floored at the
  run's zero-evidence clamp. Evidence rows had skipped the habitat
  stratification residents obey: a red deer record 54 km from a marine site
  was priced 480x above a local deer population. Linear in the habitat
  weight, so habitat bleed survives in proportion (steelhead keeps a quarter
  of its regional weight at a marine site).
* `generate_regional_proximity_evidence(year_range = )` now defaults to the
  ecosystem's 2000-to-current-year GBIF window instead of `NULL` (all time),
  and workflows pass their own study window. A 1929 museum specimen of a
  captive siamang 74 km from Point Conception had lifted that species' prior
  480x and produced a species-level call from an 82%-identity match; the
  age discount narrows confidence but never the weight. `NULL` restores the
  all-time fetch.

## 2026-09-07

* Fixed an FFT round-off degeneracy that blanked the theta surface
  (9485592).
* Kernel-budget price is mass/f1 (88d8cc0).

## Polishing Phase (Sessions 57-59)

* New high-level wrapper: `build_priors()` encapsulates GBIF fetch, habitat
  assignment, spatial gridding, model fitting, and prior generation (~18
  cross-package calls into 1).
* Added vignette: building-priors.Rmd.
