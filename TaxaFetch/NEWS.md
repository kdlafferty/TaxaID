# TaxaFetch 1.0.0

* First public release.
* Acquires and combines taxonomic occurrence data from GBIF and DataONE for a
  spatial area and taxonomic group the caller specifies.
* Aligns column naming to DarwinCore conventions and applies record-quality
  filtering, deduplication and geographic outlier checks.
* Searches the literature, retrieves PDFs and extracts species-locality
  records from them, for taxa whose records are not in the aggregators.
* Returns a data frame of occurrences across locations and times, for
  TaxaHabitat and then TaxaExpect.
