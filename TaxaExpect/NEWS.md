# TaxaExpect 1.0.0

* Initial release.

## New arguments

* `estimate_kernel_priors()`, `calibrate_kernel_bandwidth()` and
  `estimate_kernel_priors_from_counts()` take `habitat_levels` (the scheme's
  declared habitats) and `habitat_weights` (the `TaxaHabitat` lookup), supplied
  together or not at all. A record whose habitat could not be placed (`NA`,
  `""`, `"Uncertain"`, `"Unknown"`, `"Unassigned"`) counts at its taxon's own
  probability of occupying the site habitat, as a fraction of a record in the
  kernel weight, the effective sample size and the bandwidth cross-validation.
  A record placed in a different declared habitat, or labelled `"Other"` (a
  placed verdict), stays excluded; an unfamiliar label is excluded and named in
  a warning. A taxon with no weight contributes nothing. Use it instead of
  `generate_uncertain_habitat_evidence()` for the same records, which would
  count them twice. `plot_theta_surface()` reads both from the fit.

## Changed behaviour

* The fit from `estimate_kernel_priors()` records `n_records_whole`, the number
  of whole detections. `generate_undetected_diversity()` and
  `generate_domestic_food_priors()` use it as the Good-Turing sample size,
  since a fraction of a record is not a detection, and `print()` shows the
  weighted stratum count.
