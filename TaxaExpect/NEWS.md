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
