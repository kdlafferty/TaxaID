# TaxaFlag 0.1.0

## 2026-09-13

* `check_gbif_tile_range(cache_dir = )`: a persistent, no-expiry on-disk
  cache for Stage 1 of `TaxaExpect::generate_regional_proximity_evidence()`,
  which was calling this function once per zero-record taxon with no
  caching at all -- the 2026-09-13 PtConception run spent 43 minutes here
  across 256 taxa, re-paid in full on every re-run against unchanged data.
  One small `.rds` per key (taxon_key + query_lat/query_lon rounded to 4
  decimal places + buffer_px + zoom + escalate + min_zoom + base_url); the
  full key is stored inside the file and verified on read, so a hash
  collision costs one re-fetch and can never return another taxon/
  location's verdict (same pattern as `TaxaHabitat::build_habitat_lookup()`/
  `TaxaTools::scientific_to_common()`). No TTL, by design -- a hit is always
  used, however old; `taxaflag_clear_cache()` is the only way to force a
  refresh. A thrown error (a missing package, a malformed tile) is never
  cached; every successful completion, `beyond_buffer = TRUE` included, is a
  real decisive verdict and is cached. New `attr(out, "cache_age_days")`
  reports the age of a cache hit in days (`NA` on a miss/uncached call).
* `taxaflag_clear_cache()` now also reports/prunes the new tile-range cache
  (files ending `_tile_range.rds`), alongside the existing per-taxon review
  cache.
* `TaxaExpect::generate_regional_proximity_evidence()` gains
  `tile_cache_dir = NULL`, forwarded straight through to Stage 1; when
  supplied, one summary line is emitted at the end of the run, e.g.
  `"Stage 1 tile checks: 241 from cache (oldest 37 days), 15 fetched."`

## 2026-09-07

* `review_assignments()` output columns renamed with an `llm_` prefix
  (`llm_habitat_plausibility`, `llm_geographic_plausibility`,
  `llm_scope_plausibility`, `llm_contamination_risk`) so a "likely"/"unlikely"
  verdict's source is legible from the column name alone; new consensus-scope
  skepticism gate (`consensus_plausibility_col`/`consensus_discrimination_col`)
  requires the LLM to cite specific evidence before rating an
  unprecedented/indistinguishable taxon likely/possible; new deterministic
  `geographic_disagreement_basis` column flags an LLM verdict that disagrees
  with either ground (78dbb82).
* Four defects fixed: canonical-set dedup preventing duplicated rows,
  a JSON-injection guard in `.parse_json_text()`, `flag_watch_candidates()`'s
  NA-winner fallback, and a NULL `matched_name` guard in
  `review_spatial_context()` (3f5fd8f).
* `review_assignments(cache_dir = )`: per-taxon verdict cache (2026-09-04).
