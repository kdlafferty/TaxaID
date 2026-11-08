# TaxaFlag 1.0.0

* First public release.
* Flags anomalous detections in assignment results: laboratory and field
  contamination, by comparing read proportions against control samples, and,
  for time-stamped data, handler-related artifacts among detections close to
  the start or end of a sampling period.
* Detects index hopping between samples, failed libraries, and control
  samples that do not behave as controls.
* Provides LLM expert review of habitat fit, geographic plausibility,
  contaminant risk and taxonomic scope, reporting a probability for each and,
  for habitat and scope, the bounds the model gave with it.
* Appends categorical flag columns to consensus data frames, leaving the
  assignment itself unchanged.
