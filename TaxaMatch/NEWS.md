# TaxaMatch (development)

## Bug fixes (2026-09-19)

* `read_sequence_table()`: **abundance auto-detection summed any numeric column
  the name denylist did not know about.** It inferred the abundance columns by
  type -- numeric, minus `.non_abundance_col_names` -- so a BLAST-annotated ESV
  table had its alignment metrics added to the read counts. Demonstrated on a
  three-row table: a true abundance of 13/7/5 came back as **562/404/607** once
  `pident`, `bitscore` and `evalue` were summed in.

  Two screens now apply, because neither is sufficient alone:

  1. The name list gains the common alignment and classifier metrics
     (`pident`, `evalue`, `bitscore`, `length`, `qstart`/`qend`, `qcovs`,
     `bootstrap`, `confidence`, coordinates, and others).
  2. A new positive value test, `.looks_like_counts()`: read counts are
     non-negative and whole. This catches a metric under a provider's own
     naming that no list could anticipate, and rejections are **warned**, not
     messaged.

  The second is needed because a name list can never be complete; the first is
  needed because a BLAST `bitscore` is a non-negative integer and passes the
  value test. **Auto-detection still cannot be made complete** -- an integer
  metric under an unrecognised name would still be summed -- so the
  documentation now says plainly that `abundance_cols` is the only way to be
  certain.

  The message now also names the numeric columns skipped by name, so the whole
  auto-detection decision is visible rather than only its positive half.

  No production caller is affected: nothing outside this package's own example
  workflows calls `read_sequence_table()`, and the DADA2 matrix path is
  unchanged. This was latent.

  Found by grepping `is.numeric` across all nine packages after the same
  failure family appeared twice in TaxaHabitat the same day -- inferring a
  contract from column types rather than being told it.

## 2026-09-12

* Reference screen no longer errors on a marker with no registered primer
  pair (18S; 4a910ab).

## 2026-09-10

* `blast_sequences()`: `attr(out, "report_params")` now records
  `min_query_coverage`, the coverage floor the match object was built under,
  read by `TaxaLikely::evaluate_likelihoods()` to check it against the model's
  `min_pair_coverage`.
* `verify_removal_candidates()`: `spared` is `NA` (was `TRUE`) when the audit's
  own BLAST never completed (`action_audit` untested/NA); the summary message
  names un-audited accessions separately. Seen live on a real audit where all 8
  candidates timed out at NCBI and every row read "spared".

## 2026-09-07

* New `verify_local_corroborations()` (65a5d09).
* Four defects fixed from the formal review (179c8c7).
* `filter_redundant_hypotheses()`: fixed a false-positive warning
  (6b9f743).

## Polishing Phase (Sessions 57-59)

* `filter_redundant_hypotheses()`: `rank_order` param renamed to
  `rank_system` for ecosystem consistency.
* Removed duplicate `%||%` definition (now imported from TaxaTools).
* Replaced inline rank definitions with `TaxaTools::standard_ranks`.
* Added vignette: match-standardization.Rmd.
