# TaxaExpect 0.1.0

## 2026-09-12

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
