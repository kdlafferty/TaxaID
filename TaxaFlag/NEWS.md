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
* `compute_local_occurrence_distance(registry = )` (off by default): with a
  frozen taxon registry, occurrence records match the called taxa by registry
  identifier, so records filed under a synonym are counted.
