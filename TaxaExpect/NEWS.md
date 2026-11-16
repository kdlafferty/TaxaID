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
