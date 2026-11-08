# TaxaMatch 1.0.0

* First public release.
* Stores and standardizes raw match data from external tools that compare
  biological observations -- eDNA sequences, images, acoustic recordings --
  against reference databases, reading sequence tables and the outputs of
  image and acoustic classifiers.
* Outputs a canonical match object, one row per observation and reference
  match with standard column names, for TaxaLikely.
* Screens reference accessions for taxonomic mislabeling by independent
  BLAST-based congruence checking before the reference set is used, with an
  optional LLM second look at the accessions that fail.
* Applies reviewer overrides to the screening verdicts, and verifies the
  candidates before any reference is removed.
