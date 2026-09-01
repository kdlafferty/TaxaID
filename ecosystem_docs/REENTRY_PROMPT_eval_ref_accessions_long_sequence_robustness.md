# REENTRY: evaluate_reference_accessions() long-sequence / throttle robustness

Written 2026-09-01 (Fable 5 session, with the user). Implementation intended
for a delegated agent; live NCBI validation reserved for the user.

## Problem

`TaxaMatch::evaluate_reference_accessions()` is the NCBI-BLAST-based
reference-accession quality screen. The user's real PtConception runs are
GATED on it: sustained NCBI server-side CPU-budget rejections stall the
screen, and repeated re-runs make little forward progress ("ran again and
got no new cache out of it"). An ENTREZ_KEY is set and active (rentrez reads
it automatically), so this is a CPU-budget problem, not a request-rate one.

## What already exists (do NOT rebuild; read these first)

Read `TaxaMatch/CLAUDE.md` top notes for 2026-08-14, 2026-08-25 (cache
version discipline), and 2026-08-30 before writing any code. Already built:

- Chunked processing + per-chunk persistent cache writes
  (`chunk_size = 200L`, 2026-08-14).
- Circuit breaker in `blast_sequences()`/`.blast_remote()`
  (`max_consecutive_batch_failures`, CPU-budget rejections count double;
  `attr(result, "circuit_breaker_tripped")`; failed batches recorded in
  `failed_query_ids`, never miscoded as zero-hit).
- Query-side amplicon trimming (`barcode_term`, `.trim_queries_to_amplicon()`
  in `R/trim_query_to_amplicon.R`), with per-accession error isolation and a
  bounds guard (2026-08-30 crash fix).
- Asymmetric cache TTL: congruent/incongruent cached indefinitely;
  `insufficient_independent_evidence` expires after
  `insufficient_evidence_ttl_days` (180) and is retried.

## The remaining failure mode (confirmed against source, 2026-09-01)

`R/trim_query_to_amplicon.R` (~line 206) says it plainly: *"extracted the
amplicon from %d of %d over-length query sequence(s); the rest are BLASTed
at full length (primer site(s) not found)."* A full mitogenome (~16 kb) or
larger record whose primer sites the degenerate-primer match cannot locate
is submitted to remote BLAST at FULL LENGTH. Long queries consume orders of
magnitude more server CPU than a ~200 bp amplicon, invite the CPU-budget
rejection, trip the circuit breaker, and doom every short query batched
after them. Compounding it, each new run spends budget re-BLASTing expired
"insufficient" rows before ever reaching never-evaluated accessions.

The "never discards or errors, only shortens or leaves unchanged" contract
(deliberate, documented) is what routes untrimmable long sequences into
full-length submission -- the robustness fix must revise that contract
EXPLICITLY (never *silently* discard), not work around it.

## Design (four mechanisms, in priority order)

### 1. Feature-table-guided extraction fallback (the main fix)

When primer matching fails on an over-length sequence, fall back to the
record's own annotation before giving up: fetch the GBSeq feature table and
extract the annotated marker region. The fetch machinery ALREADY EXISTS --
`TaxaMatch::check_marker_mismatch()` (R/check_marker_mismatch.R) fetches
per-accession GBSeq feature tables and matches `/gene` / `/product`
qualifiers against a marker concept; reuse/extract its internals rather
than writing a second fetcher. Mechanism:

- For each still-over-length query after primer trimming, look up the
  feature whose gene/product matches the marker implied by `barcode_term`
  (e.g. 12S -> "12S ribosomal RNA" / "s-rRNA" / "rrnS"; reuse
  check_marker_mismatch()'s existing qualifier-matching logic and synonym
  handling -- do not invent a new vocabulary).
- Extract that feature's coordinate span plus a margin (e.g. 100 bp each
  side, so primer-adjacent context survives), via the same bounds-guarded
  subseq pattern the 2026-08-30 fix established.
- Cost: one batched efetch per chunk's fallback set -- rentrez-cheap,
  nothing like BLAST CPU.
- Batch the feature-table fetches (one efetch for all fallback accessions
  in a chunk), mirroring `.fetch_reference_accession_records()`'s batching.

### 2. Hard submission cap: `max_query_len` (new param)

After BOTH strategies (primer trim, feature-table extraction), any query
still longer than `max_query_len` is NOT submitted. Default: derive from
the marker when `barcode_term` is supplied (e.g. 10x the amplicon range's
upper bound -- generous, but excludes mitogenomes), with a documented
absolute fallback (suggest 5000L) when it is not. Such accessions get a
cached row with a NEW verdict value, suggested name
`"not_evaluated_oversized"`, plus the usual diagnostic columns NA'd, and a
console summary line naming how many were deferred and why. TTL: treat like
"insufficient" (retryable after expiry) so a future annotation/primer fix
can rescue them. This is the contract revision: never SILENTLY discard --
the row exists, labeled, and downstream consumers
(`flag_incongruent_references()` etc.) must treat it as not-evidence
(verify they don't pattern-match it as a flag).

### 3. Length-aware batching in the BLAST layer

`blast_sequences()`/`.blast_remote()` currently batch by sequence COUNT.
Add a cumulative-length cap (`max_batch_bp`, suggest 100000L): a batch
closes when either the count limit or the bp limit is reached, and any
single query exceeding some large share of `max_batch_bp` rides ALONE. This
stops one expensive query from dooming dozens of cheap ones sharing its
batch, and makes circuit-breaker trips lose less progress. Keep the
existing batch-failure bookkeeping semantics untouched.

### 4. Retry-priority ordering + retry switch

In `evaluate_reference_accessions()`: order `needs_eval` so NEVER-evaluated
accessions come before expired-"insufficient" retries (new param
`prioritize_uncached = TRUE`), so a budget-limited run buys new coverage
first. Add `retry_insufficient = TRUE` -- `FALSE` skips expired retries
entirely for that run (the fastpath header's documented complaint: the
cache "RETRIES insufficient accessions every call, so even a cache-served
run grinds against the throttle"). Both additive, defaults preserving
current behavior except the (safe, strictly-better) ordering.

## Constraints and conventions (binding)

- Do NOT bump `.EVAL_REF_ACC_VERSION` (see the 2026-08-25 note: params_key
  is global; a bump forces a full re-BLAST of ~1,163 correctly-cached real
  rows). New verdict values are additive; existing cached rows must remain
  valid and untouched.
- NO live NCBI calls from the implementing agent. All tests offline:
  mock `blast_sequences()`, mock the feature-table fetch
  (`local_mocked_bindings`, the package's established pattern -- see
  test-verify-flagged-references.R). Live validation belongs to the user's
  next NCBI window (write exact re-run instructions per the ecosystem's
  restart/install/un-cache/library checklist convention, including whether
  the persistent accession cache needs anything -- it should NOT).
- Ecosystem conventions: ASCII-only source, native pipe, `.` prefix +
  `@noRd` for internals, `utils::globalVariables()` first line where NSE,
  no blank lines in `@param` blocks, sprintf single-string discipline.
- `devtools::document()` + `test()` (target: 0 failures, baseline 886) +
  `check()` (0/0/0) on TaxaMatch. Do NOT `devtools::install()` -- leave
  installation to the main session after review.
- Update `TaxaMatch/CLAUDE.md` top note + the ecosystem CLAUDE.md
  Recent Breaking Changes table (new params + new verdict value are
  additive rows) + `ecosystem_docs/NAME_CHANGE_HISTORY.md`.
- Work on a feature branch `ncbi-screen-robustness` (user convention:
  feature branches for multi-session work).

## Acceptance (offline)

- A mocked over-length sequence with no primer hits but a matching
  feature-table annotation gets extracted and submitted short.
- A mocked over-length sequence with neither gets `not_evaluated_oversized`,
  is never passed to the (mocked) BLAST layer, and survives a cache
  round-trip with its TTL semantics.
- Length-aware batching: a mocked set where one 40 kb query + many short
  ones produces batches in which the long query rides alone.
- Priority ordering: with a cache holding expired-insufficient rows and new
  accessions supplied, the (mocked) evaluation order puts new first;
  `retry_insufficient = FALSE` skips the expired entirely.
- Existing suite: no regressions (886 baseline).

## Status

- 2026-09-01: doc written; delegated to a Sonnet agent for implementation.
- 2026-09-01: IMPLEMENTED, offline-verified, branch `ncbi-screen-robustness`. All four
  mechanisms shipped as specced above: (1) `.extract_feature_table_fallback()`
  (`TaxaMatch/R/trim_query_to_amplicon.R`), reusing `check_marker_mismatch()`'s fetch/
  matching internals (`.fetch_marker_annotation()` gained `feature_from`/`feature_to`
  columns); (2) `max_query_len` + new `hierarchy_flag = "not_evaluated_oversized"`
  (TTL-retryable, never treated as a flag by `remove_incongruent_references()`/
  `flag_incongruent_references()`); (3) `blast_sequences()`/`.blast_remote()` gain
  `max_batch_bp` via new `.split_batches_by_length()`; (4) `evaluate_reference_
  accessions()` gains `prioritize_uncached` (default `TRUE`) and `retry_insufficient`
  (default `TRUE`). `.EVAL_REF_ACC_VERSION` NOT bumped; all four new params deliberately
  excluded from `params_key` (see `TaxaMatch/CLAUDE.md`'s 2026-09-01 top note for the
  full reasoning) -- the persistent cache needs no clearing and no rows were invalidated.
  One real bug found and fixed while writing tests: `return(NULL)` inside a bare
  `tryCatch({...})` block (no wrapping function) returns from the whole enclosing
  function in R, not just the tryCatch expression -- see the CLAUDE.md note for detail.
  `devtools::document()` clean, `devtools::test()` 950/950 (0 failures, 0 warnings, up
  from the 886 baseline -- 64 new tests), `devtools::check()` 0 errors/0 warnings/0
  notes. NOT reinstalled (out of scope for the implementing agent, per this doc's own
  constraint) -- see "Re-run instructions for the next live NCBI window" below.
  Ecosystem CLAUDE.md's Recent Breaking Changes table and
  `ecosystem_docs/NAME_CHANGE_HISTORY.md` both updated with additive rows.

## Re-run instructions for the next live NCBI window

Follow this ecosystem's restart/install/un-cache/library checklist convention in full --
all four steps, every time, not just a subset:

1. **Restart R** (a fresh session -- a stale in-memory `TaxaMatch` from before this work
   landed is the single most common cause of a "it doesn't work" report that turns out
   to be nothing of the kind).
2. **Install the updated package** from the `ncbi-screen-robustness` branch worktree:
   ```r
   .libPaths(c(path.expand(Sys.getenv("R_LIBS_USER")), .libPaths()))
   devtools::install(
     "/private/tmp/claude-501/-Users-lafferty/bb8c80c5-240a-4a66-a6b3-eda9f8dd7c12/scratchpad/taxaid-ncbi-robustness/TaxaMatch",
     upgrade = "never"
   )
   ```
   (Set `.libPaths()` BEFORE calling `install()` -- this is the documented library
   footgun: a bare `Rscript` call can otherwise silently install to, or load
   dependencies from, the wrong R library, e.g. `TaxaTools` resolving from a stale
   system library instead of `~/Library/R/4.0/library`.) Verify the install actually
   landed the new code before trusting anything downstream:
   ```r
   packageVersion("TaxaMatch")  # sanity check only -- version number itself wasn't bumped
   "max_query_len" %in% names(formals(TaxaMatch::evaluate_reference_accessions))  # must be TRUE
   "max_batch_bp" %in% names(formals(TaxaMatch::blast_sequences))  # must be TRUE
   ```
3. **Un-cache**: nothing to clear. The persistent accession cache
   (`tools::R_user_dir("TaxaMatch", "cache")`, or whatever `cache_dir` your real workflow
   already passes) needs **NO clearing, deletion, or backup-and-surgical-edit** before
   this re-run -- unlike several past sessions' fixes in this file's own history
   (2026-08-11, 2026-08-13), this change deliberately did NOT bump `.EVAL_REF_ACC_
   VERSION` and deliberately did NOT add any of the four new params to `params_key`
   specifically so every already-cached `"congruent"`/`"incongruent"` row (real count:
   ~1,163 across the GreatLakes/PtConception populations) stays valid and untouched. A
   PREVIOUSLY-cached `"insufficient_independent_evidence"` row past its TTL will retry as
   before; nothing new needs to expire or be forced.
4. **Verify `.libPaths()`** right before the real run itself (not just at install time --
   a new R session/terminal can silently reset it):
   ```r
   .libPaths(c(path.expand(Sys.getenv("R_LIBS_USER")), .libPaths()))
   .libPaths()  # confirm ~/Library/R/4.0/library is first
   ```

Then re-run the SAME blocked call the user already had in flight (same `accessions`,
same `cache_dir`) -- no changes needed to the call itself to benefit from mechanisms
1-3 (the barcode_term-scoped rescue chain and length-aware batching apply automatically
whenever `barcode_term` is supplied, exactly as before); to benefit from mechanism 4's
new default ordering, no action is needed either (`prioritize_uncached = TRUE` is now
the default). Optionally pass `max_query_len =` explicitly to override the auto-derived
default, or `retry_insufficient = FALSE` for a run intended to be purely cache-served.

**What to look for in the first real run**, to confirm the fix is doing real work, not
just present:
- A `message()` naming how many accessions were deferred as `"not_evaluated_oversized"`
  this call, and how many were rescued via the feature-table fallback (both new,
  `verbose = TRUE` messages -- see `.evaluate_reference_accessions_chunk()`'s own
  `if (verbose)` blocks in `R/evaluate_reference_accessions.R` and
  `.extract_feature_table_fallback()`'s own in `R/trim_query_to_amplicon.R`).
- Fewer/no `.blast_server_rejected()` CPU-budget-rejection warnings than the pre-fix
  baseline, for the SAME accession population -- the whole point.
- `attr(result, "run_summary")$pct_complete` climbing further per call than before, since
  a budget-limited call now spends its budget on never-evaluated accessions first
  (`prioritize_uncached`).
- After the run: `table(result$hierarchy_flag)` should show a real, non-zero
  `"not_evaluated_oversized"` count only if genuinely unrescuable long sequences exist in
  this population (full mitogenomes/larger with no locatable primer sites AND no
  matching feature-table annotation) -- zero is a perfectly plausible, correct outcome
  too, not evidence the mechanism didn't run.

If a real run surfaces a genuinely new failure mode (e.g. a marker/barcode_term whose
`.resolve_expected_marker()` bridge doesn't yet cover it, or a GBSeq feature-table shape
this fetch code doesn't parse correctly), that is real signal for a follow-up session,
not something to work around silently in the field.
