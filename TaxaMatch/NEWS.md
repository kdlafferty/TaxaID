# TaxaMatch 1.0.0

* Initial release.
* `review_flagged_accessions()` supersedes a cached review on the pair the
  lookup keys on, the accession and its input fingerprint, rather than on the
  accession alone. One accession screened under two different inputs -- a
  mitogenome reached through two markers is the ordinary case -- no longer
  evicts the other screen's verdict, so an accession reviewed once is not
  re-asked, and paid for, on every later run.
* Neither hit cap in `blast_sequences()` depends on the order BLAST returned its
  hits. `max_hits` is a per-query floor: every hit sharing the identity of the
  last one kept is also kept, so the count can exceed `max_hits`, because a tie
  there is between different taxa and dropping one would discard a candidate
  species. The overshoot is bounded by what BLAST returned, hence by
  `max_target_seqs`; a tie BLAST itself truncated cannot be recovered.
  `max_hits_per_taxon` is a hard count, because a tie there is between repeated
  deposits of one species, which is what that cap exists to collapse; which of
  several tied deposits survives is settled by identity and then accession.
  Measured on a saved 622-ASV hit set: of the 93 ASVs the per-query cap acted on,
  89 had the cut land inside a run of equal identities and 48 had all twenty kept
  hits at a single identity, median lowest-kept identity 98.99.

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
