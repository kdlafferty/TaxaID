# TaxaExpect 1.0.0

* First public release.
* Estimates theta priors -- each taxon's expected share of the detections at a
  site -- from occurrence records, for use by TaxaAssign.
* Weights occurrence points by distance from the site with a kernel
  estimator, with optional depth and habitat conditioning.
* Adds evidence layers for undetected diversity, regional proximity,
  iNaturalist ranges, invasive watch lists and domestic or food species.
* Reports how sensitive the result is to the kernel settings, and plots the
  prior surface behind it.
* With a frozen taxon registry, `condition_evidence_on_habitat()`,
  `estimate_kernel_priors()`, `estimate_kernel_priors_from_counts()`,
  `generate_undetected_diversity()`, `apply_undetected_evidence()` and
  `generate_domestic_food_priors()` (`registry =`, off by default) match a
  taxon to its habitat verdict and place rows on the taxonomic tree by registry
  identifier, so a name filed under a synonym is still matched and placed.
* Every `registry =` argument refuses a registry edited after
  `freeze_taxon_registry()`, as `attach_taxon_ids()` does, through the shared
  check `TaxaTools::registry_ids_for_names()` (error class
  `taxon_registry_invalid`).
* `generate_regional_proximity_evidence()` resolves names against the GBIF
  Backbone Taxonomy (`checklistKey`), so its keys are Backbone keys under any
  rgbif version, including rgbif 3.9.0 and later, whose default checklist is
  the Catalogue of Life Extended Release. A key that is not a Backbone integer
  is an error (class `taxaid_gbif_key_not_backbone`), not a species left
  unresolved. Name matching needs rgbif 3.8.4 or later.
