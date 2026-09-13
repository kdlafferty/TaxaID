# TaxaExpect 0.1.0

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
