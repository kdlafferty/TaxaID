# TaxaFlag 1.0.0

* First public release.
* Flags anomalous detections in assignment results: laboratory and field
  contamination, by comparing read proportions against control samples.
* Detects index hopping between samples, failed libraries, and control
  samples that do not behave as controls.
* Provides LLM expert review of habitat fit, geographic plausibility,
  contaminant risk and taxonomic scope, reporting a probability for each and,
  for habitat and scope, the bounds the model gave with it.
* Appends categorical flag columns to consensus data frames, leaving the
  assignment itself unchanged.
* `screen_assignments(resolve = TRUE)` (the default) reads three axes -- the
  sequence match, occurrence and habitat -- and appends `flag_resolution`,
  `flag_resolution_basis` and `flag_consistency_score`. A row whose evidence
  cannot vote independently of the reviewer's own verdicts reads
  `not_assessed`. `resolve = FALSE` returns the screen's columns alone.
* `compute_local_occurrence_distance(registry = )` (off by default): with a
  frozen taxon registry, occurrence records match the called taxa by registry
  identifier, so records filed under a synonym are counted.
* Every `registry =` argument refuses a registry edited after
  `freeze_taxon_registry()`, as `attach_taxon_ids()` does, through the shared
  check `TaxaTools::registry_ids_for_names()` (error class
  `taxon_registry_invalid`).
