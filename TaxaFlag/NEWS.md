# TaxaFlag 1.0.0

* Initial release.
* `report_flags()` detects reference-support columns from
  `TaxaLikely::annotate_reference_support()` and reports their distribution and
  basis breakdown alongside the flags, deliberately outside every flag count:
  they say how much reference data stood behind a call, which neither accuses
  nor clears it.
