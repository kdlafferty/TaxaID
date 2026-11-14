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
* `lookup_gbif_taxa()` matches names against GBIF's backbone taxonomy and
  returns each record's own key, accepted key and the key of every rank in its
  classification, in the shape `TaxaTools::build_taxon_registry()` takes as
  its `lookup`. A record is a synonym when any of its synonym flag, a
  synonym-type status or an accepted key different from its own says so.
* `get_keys_from_context(return_keys = TRUE)` adds GBIF's identifier columns
  from the same backbone record; `cache_dir` keeps a per-row cache keyed on the
  whole request, and a failed request is never cached.
