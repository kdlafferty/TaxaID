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
