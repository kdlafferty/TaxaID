# TaxaExpect 0.1.0

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

## Polishing Phase (Sessions 57-59)

* New high-level wrapper: `build_priors()` encapsulates GBIF fetch, habitat
  assignment, spatial gridding, model fitting, and prior generation (~18
  cross-package calls into 1).
* Added vignette: building-priors.Rmd.
