# TaxaMatch 1.0.0

* Initial release.

## New features

* `evaluate_reference_accessions()` adds `query_over_amplicon`, `TRUE` when the
  sequence submitted for an accession is longer than the marker's target
  amplicon. Its identities then describe a wider region than the queries being
  screened. The function warns once with the count and median and longest
  submitted length; what is submitted is not altered. `query_len_submitted` and
  `query_trim_path` are documented alongside it.

## Changed behaviour

* `evaluate_reference_accessions()` applies the maternal-parent proxy for a
  hybrid-labelled accession only for a maternally inherited marker. For other
  markers (or when no marker is given) no proxy is applied and `taxonomy_resolution_source`
  reads `"hybrid_marker_not_maternal"`, because a nuclear or biparental
  sequence does not identify the maternal parent.
* `refine_reference_verdicts()` refines only accessions the screen evaluated
  (non-`NA` `hierarchy_flag`), and uses only pair rows cast under the same
  screen settings. An accession that was never evaluated receives no verdict.
* `standardize_match_data()` reads a blank rank value in a match object as `NA`
  (naming the column and count), so an absent rank is never carried as an empty
  string.
* `convert_taxonomy_backbone()` corrects `taxon_name_rank` to `"genus"` when a
  cleaned name collapses to its genus, and passes each name's rank to the
  backbone verifier as `input_rank`.
