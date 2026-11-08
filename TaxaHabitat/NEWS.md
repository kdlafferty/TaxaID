# TaxaHabitat 1.0.0

* First public release.
* Assigns habitat classifications to occurrence records against a scheme the
  caller supplies, using LLM prompts, with an on-disk cache keyed to the
  question asked rather than to the name alone.
* Performs spatial quality control against a coastline layer and GEBCO
  bathymetry, and fills habitats the consensus left unresolved from point
  geography.
* Flags records whose coordinates fall on museums, universities and other
  institutions, and supports interactive review of flagged points.
* Produces habitat-annotated, spatially screened records for TaxaExpect.
