# TaxaLikely 1.0.0

* Initial release.
* `restore_suppressed_candidates()` scores a restored congener by aligning the
  query to the candidate's own references (`sequence_col`, `min_query_coverage`),
  reported in `restored_score_source` / `restored_reason`. The hierarchy's
  identities, including Level 4's `pid`, are reference-to-reference (Level 4
  aligns the candidate's reference to the anchor's reference; the query only
  locates the anchor range), so they are used only as an imputed fallback,
  `anchor - (100 - ref_ref)`, which never exceeds the anchor.
* `restore_suppressed_candidates(dropped_matches =)` offers a dropped hit's
  species back through its kept references, scored by the same direct
  alignment, so dropping one accession does not drop a species that has other
  good references.
