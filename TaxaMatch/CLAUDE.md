# CLAUDE.md — TaxaMatch
# Package-specific context. Ecosystem context is in TaxaID/CLAUDE.md (auto-loaded).
# Last updated: 2026-09-01 (Sonnet 5, branch ncbi-screen-robustness -- implements
# ecosystem_docs/REENTRY_PROMPT_eval_ref_accessions_long_sequence_robustness.md end to
# end: the four mechanisms the reentry doc specced to stop long/unrescuable query
# sequences from eating `evaluate_reference_accessions()`'s NCBI CPU budget and stalling
# real PtConception runs. Delegated by the user; live NCBI validation deliberately
# reserved for their next window -- everything below is offline-verified only.
#
# (1) Feature-table-guided extraction fallback (the main fix) -- new
# `.extract_feature_table_fallback()` (`R/trim_query_to_amplicon.R`): when
# `.trim_queries_to_amplicon()` leaves a query over-length (primer sites not found),
# this checks the accession's OWN annotated GBSeq feature table for a `/gene`/`/product`
# qualifier matching the marker `barcode_term` implies, and extracts that feature's
# coordinate span (+/- a 100bp margin) instead of submitting the full record. Reuses
# `check_marker_mismatch()`'s existing fetch/matching internals directly -- no second
# fetcher, no new qualifier vocabulary, per the reentry doc's explicit instruction.
# `.fetch_marker_annotation()` (`R/check_marker_mismatch.R`) gained two new columns,
# `feature_from`/`feature_to` (parsed from `GBFeature_intervals/GBInterval`, min/max
# across intervals) -- additive; `check_marker_mismatch()` itself never reads them, so
# its own behavior and tests are byte-unchanged. A small new bridge,
# `.resolve_expected_marker()`/`.MIFISH_STYLE_TO_MARKER`, maps MiFish/Teleo-style
# `barcode_term` primer-SET names (which never literally contain "12S") onto
# `.resolve_marker_pattern()`'s own existing marker vocabulary -- every other
# `barcode_term` value (`"18S_2"`, `"COI-Leray"`, etc.) already resolves via that
# function's own substring fallback, unchanged. Extraction uses plain `substr()` (GenBank
# feature coordinates index directly into `GBSeq_sequence`, 1-based inclusive) -- no
# `Biostrings` call needed for this step, and deliberately does NOT reverse-complement a
# minus-strand feature, since `blast_sequences()` never sets an explicit strand and
# already searches both regardless (documented explicitly in the new function's own
# roxygen, not silently assumed).
#
# Found and fixed a real bug while writing this function's own tests (not caught by
# manual review): `return(NULL)` inside a bare `tryCatch({...})` block with no wrapping
# function of its own returns from the ENCLOSING FUNCTION in R, not just supplies the
# tryCatch expression's value -- the first draft's "no match" and "out-of-bounds span"
# early-outs were each returning `NULL` from `.extract_feature_table_fallback()` ITSELF,
# silently abandoning every remaining accession still to be processed in that call's
# loop the moment the first non-rescuable one was hit. Fixed by wrapping the per-
# accession extraction logic in its own local `extract_one()` closure inside the
# `tryCatch()`, so `return(NULL)` only ever exits that one accession's own attempt. 3
# tests caught this immediately (each expecting an unchanged sequence back got `NULL`
# for the whole function instead) -- flagging this pattern in case it recurs elsewhere
# in this codebase's other bare-`tryCatch({...break-out-of-loop...})` call sites.
#
# (2) Hard submission cap -- new `max_query_len` param (default `NULL`, resolving to
# `10x` the marker's own `amplicon_range` upper bound when `barcode_term` is supplied,
# else a flat `5000`; `Inf` disables). After BOTH rescue strategies, a query still over
# `max_query_len` is NEVER submitted to BLAST -- gets a real cached row instead, new
# `hierarchy_flag` value `"not_evaluated_oversized"`, every diagnostic column `NA`. This
# is the contract revision the reentry doc called for: the pre-existing "never discards
# or errors, only shortens or leaves unchanged" contract is honored EXPLICITLY (a
# labeled, TTL-retryable non-result -- same asymmetric TTL treatment as
# `"insufficient_independent_evidence"`, so a later annotation/primer fix or a raised
# `max_query_len` can rescue it), not silently (never just BLASTed at full length
# unconditionally, the prior behavior). Verified downstream: `flag_incongruent_
# references()`/`remove_incongruent_references()` never pattern-match this new value as
# a flag (`remove_insufficient_evidence = TRUE` only ever adds
# `"insufficient_independent_evidence"` to what's removed, never the new verdict --
# confirmed by a dedicated test, not just read). `verify_flagged_references()`'s
# whitelist-based `keep_flags` also naturally excludes it by default, identical to how
# `"insufficient_independent_evidence"` is already excluded unless
# `trust_insufficient_evidence = TRUE` -- no code change needed there, verified by
# inspection.
#
# (3) Length-aware BLAST batching -- `blast_sequences()`/`.blast_remote()` gain
# `max_batch_bp` (default `100000L`). New internal `.split_batches_by_length()`
# (`R/blast_sequences.R`) replaces the old count-only `split(seq_len(n),
# ceiling(seq_len(n)/batch_size))` in both the initial batch plan and the halved-batch-
# size retry pass: a batch closes on EITHER the count cap or a cumulative-bp cap,
# whichever comes first, and any single query at or above half of `max_batch_bp` rides
# ALONE (closing whatever batch was accumulating first). `Inf` restores the exact old
# count-only behavior (confirmed byte-identical to the old `split()` call via a dedicated
# test). Existing circuit-breaker/failed-batch bookkeeping is completely untouched --
# `.split_batches_by_length()` only changes what goes INTO each batch index, not how
# batch failures are counted or retried.
#
# (4) Retry-priority ordering + retry switch -- `evaluate_reference_accessions()` gains
# `prioritize_uncached` (default `TRUE` -- reorders `needs_eval` so never-before-cached
# accessions are evaluated before expired `"insufficient_independent_evidence"`/
# `"not_evaluated_oversized"` retries; the ONE new default that changes existing
# behavior, deliberately, since it's a pure processing-order change that never alters
# which accessions end up evaluated) and `retry_insufficient` (default `TRUE`; `FALSE`
# serves an expired capped row from cache AS-IS instead of retrying it this call --
# directly answers the fastpath header's documented complaint that a call meant to be
# purely cache-served still "RETRIES insufficient accessions every call, so even a
# cache-served run grinds against the throttle").
#
# Cache-version discipline (binding constraint, re-verified before shipping): NONE of
# the four new `evaluate_reference_accessions()` params (`max_query_len`, `max_batch_bp`,
# `prioritize_uncached`, `retry_insufficient`) were added to `params_key`, and
# `.EVAL_REF_ACC_VERSION` was NOT bumped -- worked through explicitly, not just asserted:
# `params_key` is one global string applied uniformly to every cached row (the same
# 2026-08-11/13 precedent this file already documents), so adding a new token to it would
# have changed EVERY row's own key regardless of whether the new param's actual value
# differed, forcing a full re-BLAST of the real ~1,163-row GreatLakes/PtConception cache
# on the very next call -- exactly the outcome this whole feature exists to prevent. All
# four instead behave like the pre-existing `chunk_size`/`max_consecutive_batch_failures`
# precedent: call mechanics/scheduling policy, not verdict-affecting inputs, so changing
# them between calls never invalidates an already-`"congruent"`/`"incongruent"`-cached
# row (confirmed by a dedicated regression test). `"not_evaluated_oversized"`'s own TTL-
# based retryability does the real work of letting a later `max_query_len` change
# eventually reach an already-cached oversized row, without needing a global key bump.
#
# 64 new offline tests (950 total, up from 886): `.split_batches_by_length()` (count-cap
# parity with the old `split()`, bp-cap-closes-before-count-cap, solo-ride isolation, NA-
# length handling, `blast_sequences()` end-to-end batch-plan verification via a mocked
# `.blast_submit()`), `.extract_feature_table_fallback()`/`.resolve_expected_marker()`
# (match/no-match/no-annotation/degenerate-span/fetch-failure cases, plus the full
# `evaluate_reference_accessions(barcode_term=)` integration path), `max_query_len`
# (oversized defer + never-BLASTed, `Inf` disables, cache round-trip with TTL retry,
# downstream flag-safety), `prioritize_uncached`/`retry_insufficient` (evaluation-order
# proof via a call-order-recording mock, `FALSE` preserves caller order, zero-new-NCBI-
# call proof for a purely cache-served run, a genuinely-new accession still evaluates
# normally), and the params_key-exclusion regression test above. `devtools::document()`
# clean, `devtools::test()` 950/950 (0 failures, 0 warnings), `devtools::check()`
# 0 errors/0 warnings/0 notes. NOT reinstalled -- per the reentry doc's own constraint
# (`devtools::install()` explicitly out of scope for the implementing agent) and this
# ecosystem's restart/install/un-cache/library checklist convention, installation is left
# to the user's own next session; exact re-run instructions (including that the
# persistent accession cache needs NO clearing) are appended to the reentry doc's own
# Status section.
# Previous update, 2026-08-30 (Sonnet 5 -- real production crash fixed in
# .trim_queries_to_amplicon()/.extract_amplicon_one_tm() (R/trim_query_to_amplicon.R),
# found live: `evaluate_reference_accessions(barcode_term = "MiFishU")` on a real
# PtConception 995-accession screen crashed chunk 1/5 (200 accessions) with a bare
# IRanges "Invalid sequence coordinates" error from `Biostrings::subseq()`, killing the
# whole chunk on one bad accession -- 101 accessions from earlier calls stayed safely
# cached, but the in-flight chunk's progress was lost entirely, with no way to identify
# or skip just the offending accession. Root cause not fully pinned to a single
# reproducible trigger (the coordinate math in `.extract_amplicon_one_tm()` is
# structurally supposed to keep `fwd_start`/`rev_end` within the subject sequence's own
# bounds, since both come from `Biostrings::matchPattern()` hits on that same subject --
# but real production data hit an inconsistent state regardless). Fixed at both layers,
# per this function's own already-documented "never discards or errors, only shortens or
# leaves unchanged" contract: (1) an explicit bounds/ordering guard
# (`fwd_start < 1L || rev_end > seq_len || fwd_start > rev_end`) before the `subseq()`
# call, converting an invalid span into the same "primers not found" outcome an ordinary
# no-match already gets; (2) a `tryCatch()` around each per-accession call inside
# `.trim_queries_to_amplicon()`'s loop, so ANY unforeseen extraction error (not just the
# specific coordinate case the guard targets) degrades to leaving that one sequence
# untrimmed rather than aborting the whole batch -- restoring genuine per-accession
# isolation, matching the same pattern already used elsewhere in this file for fetch
# failures. New regression test
# (`test-trim-query-to-amplicon.R`, ".trim_queries_to_amplicon() isolates a per-accession
# extraction error instead of crashing the whole batch") mocks `.extract_amplicon_one_tm()`
# to throw on the first of two sequences, confirming the first is left untrimmed and the
# second is still processed normally. No cache-version bump needed -- the only behavior
# change is that a previously-crashing (never-cached) accession now succeeds; every
# already-cached row is unaffected. `devtools::test()` 886/886 (0 failures, 0 warnings, up
# from 883), `devtools::check()` 0/0/0, reinstalled and verified at
# `~/Library/R/4.0/library` (`Built` timestamp 2026-08-31 01:52:40 UTC). The user's blocked
# PtConception `evaluate_reference_accessions()` run (995 unique accessions, 101 already
# cached) can now be safely re-run from where it left off -- the persistent cache means
# the 101 cached accessions won't be re-BLASTed.
# Previous update, 2026-08-21, continued (Sonnet 5 -- convert_taxonomy_backbone()'s rank-
# collapse fix (this file's own entry directly below) was verified against a REAL re-run of
# the GreatLakes2023 production workflow and still found 33 stale `taxon_name = "Ictalurus"`/
# `taxon_name_rank = "species"` rows -- the first fix was real but INCOMPLETE, not a stale-
# cache artifact as first suspected. Root-caused a SECOND, structurally different failure
# mode by reading the real query's own `taxonomy_collision` column directly
# (`"backbone_4[species]"` -- i.e. FOUND in NCBI, species column flagged CHANGED) rather than
# guessing: NCBI's own taxonomy database genuinely contains real leaf-level nodes for
# informally-named specimens (e.g. `"Ictalurus sp. UM 105-1789"`), RANKED "species" BY NCBI
# ITSELF -- `found_mask = TRUE`, `matched_rank` genuinely IS `"species"` (fully backbone-
# consistent, so the existing `matched_rank`-driven correction correctly does nothing at
# all), but the classification path's own species-rank VALUE is that same informal label,
# which `clean_taxon_names()` correctly collapses to `"Ictalurus"` when building
# `target_species`. No rank-MISMATCH-based correction (the original mechanism, or the
# not-found-only fix below) can ever see this -- the backbone's own rank claim is genuinely
# self-consistent; only the collapse signal itself reveals the problem.
#
# Generalized the not-found-only fix into ONE unified mechanism (replacing it, not adding a
# third parallel block) covering all three sources that can populate `taxon_name`: (A) a
# found row using its own rank's `target_<rank>` value directly (the newly-discovered case --
# `target_collapsed_mat`, threaded through the same `target_<rk>` construction loop that
# already builds `target_<rk>` itself, tracks `collapsed_to_genus` per rank/row); (B) a found
# row falling back to `matched_name_clean` (its own `collapsed_to_genus` now consulted too,
# though not yet observed triggering on real data); (C) the original not-found fallback case.
# Whichever source actually produced the final value is the one consulted -- never mixed
# across cases. Considered and explicitly REJECTED a shape-based re-derivation instead (e.g.
# `TaxaTools::is_plausible_binomial()` on the final value) -- that function's binomial regex
# requires a literal space immediately after the genus token, which a real hyphenated genus
# (*Pseudo-nitzschia*, already a real fixture elsewhere in this ecosystem's test suite) fails,
# which would have wrongly demoted every hyphenated-genus species row; a dedicated regression
# test (`Pseudo-nitzschia australis`, found=TRUE, nothing collapsed) confirms the shipped
# collapse-tracking approach does NOT make this mistake.
#
# Live end-to-end re-verified against the INSTALLED package for BOTH real cases side by side:
# the not-found open-nomenclature case (unchanged from the first fix) and this new found-but-
# placeholder-species-node case both correctly resolve to `taxon_name = "Ictalurus"`,
# `taxon_name_rank = "genus"`, `species = NA`. 2 new tests added to the 6 from the first fix
# (8 total this session): the real found-case placeholder-node demotion, and the
# *Pseudo-nitzschia* false-positive regression guard. `devtools::test()` 883/883 (0 failures,
# up from 876), `devtools::check()` 0 errors/0 warnings/0 notes, reinstalled and verified at
# `~/Library/R/4.0/library`.
# Previous update, 2026-08-21 (Sonnet 5 -- convert_taxonomy_backbone() gains a SECOND,
# genuinely separate rank-correction mechanism for NOT-found rows, closing what was AT THE
# TIME believed to be the full root cause of a real "Ictalurus" bug found live-debugging real
# GreatLakes2023 production data -- see the entry directly above for the second, structurally
# different case found when this fix was verified against a real re-run and only partially
# held (see TaxaTools/CLAUDE.md's matching 2026-08-21 note for the full chain-of-functions
# investigation this session did before writing any fix, per the user's explicit "does not
# require repeated post-hoc fixes" instruction). Real bug: 33 real `match_obj_restored` rows
# had `taxon_name = "Ictalurus"` (a bare genus) but `taxon_name_rank = "species"` -- a bare
# genus silently treated downstream as if it were a real species (e.g.
# `TaxaExpect::generate_regional_proximity_evidence()`'s GBIF species-rank lookup would
# have resolved the GENUS's own key, a separate bug already fixed 2026-08-21 elsewhere in
# TaxaExpect as a downstream safeguard, not the root cause).
#
# The EXISTING rank-correction mechanism (2026-07-25, "Inu Inu" fix, still unchanged) only
# ever fires for a row the target backbone actually FOUND, just at a coarser rank than
# claimed (driven by `verify_taxon_names()`'s `matched_rank`). "Ictalurus cf. pricei
# USON-01120-1" -- a real, restored candidate's raw reference-row species value, a specimen-
# voucher-tagged open-nomenclature label -- fails an exact-name backbone lookup entirely
# (`found_mask = FALSE`), a genuinely different code path with no prior coverage. This
# function's OWN not-found fallback already correctly collapses `taxon_name` to
# "Ictalurus" via `TaxaTools::clean_taxon_names()` (a pre-existing 2026-07-24 fix), but had
# no way to know a collapse had happened, so `taxon_name_rank` stayed stale.
#
# Fix (superseded/generalized by the entry above the same day): uses `TaxaTools::
# clean_taxon_names()`'s new `collapsed_to_genus` attribute (same-day companion fix, see
# TaxaTools/CLAUDE.md) on the not-found fallback value.
#
# Grepped the whole monorepo for other `clean_taxon_names()` call sites that build a
# `taxon_name`/`taxon_name_rank` pair the same vulnerable way (assigning a cleaned name
# without ever touching the rank column) -- several exist (`TaxaAssign_llm_workflow.R`,
# `inst/TaxaID_Workflow_Template_TEST.R`, several TaxaWizard snippets), but none of them sit
# between a restored/derived candidate row and `TaxaAssign::join_priors()` the way this
# function does for the real production pipeline this bug was found on -- `TaxaExpect::
# generate_domestic_food_priors()`/`generate_invasive_watch_evidence()`'s own
# `clean_taxon_names()` calls are for list-matching normalization, not rank-labeled row
# construction (and already hardcode `taxon_name_rank = "species"` per the 2026-08-20 fix).
# Not touched this session -- flagged, not a silent gap, since this fix's real reach is
# `convert_taxonomy_backbone()` itself (called on every real production match object before
# `join_priors()`), not every individual `clean_taxon_names()` call site ecosystem-wide.
# Previous update, 2026-08-14, continued (Sonnet 5 -- review_flagged_accessions() gains a
# persistent, accession-keyed LLM-review cache, same session, prompted directly by the
# user after confirming the new evaluate_reference_accessions() rate-limit resilience
# against a real live run (see the note directly below): they pointed out
# review_flagged_accessions() has NO such protection -- every call re-reviews its entire
# in-scope set from scratch, a real, avoidable LLM API cost for accessions already
# reviewed. Follows the exact same `cache_dir` default/convention as
# evaluate_reference_accessions()/investigate_flagged_accession()
# (`tools::R_user_dir("TaxaMatch", "cache")`, `NULL` disables), but the invalidation
# design is deliberately different: keyed on accession + a plain concatenated content
# fingerprint of the review-relevant input columns (listed_taxon/hierarchy_flag/finest_
# common_rank/the identity diagnostics/taxonomy_resolution_source/
# listed_taxon_is_species/the independence-filtering counts -- see new
# `.accession_review_fingerprint()`), not a TTL -- an LLM review of a FIXED input is
# deterministic enough that "did the input actually change" is the correct signal, not
# "has enough time passed" (unlike evaluate_reference_accessions()'s own
# `insufficient_evidence_ttl_days`, where new NCBI deposits really can change the answer
# over time with no change to the CACHED row's own fields). A re-evaluated accession whose
# `hierarchy_flag`/diagnostics genuinely changed therefore gets a fresh review
# automatically; an unchanged one never does, no matter how much time has passed. New
# `accession_review_cache_hit` output column lets a caller see which rows were served from
# cache. Cache is written incrementally, once per LLM batch actually sent (mirrors
# evaluate_reference_accessions()'s own per-chunk write, same session) -- an interruption
# partway through a large review run only loses the in-flight batch. A row with NA
# `accession_likely_explanation` (a hard `llm_fn` failure, an unparseable response, or an
# LLM-omitted accession -- never legitimately null by prompt design, unlike
# `accession_review_comment`) is deliberately EXCLUDED from the cache write, so a
# transient failure gets retried next call rather than permanently cached as if it were a
# real answer. `.load_accession_review_cache()` mirrors `.load_reference_accession_
# cache()`'s exact schema-mismatch handling (discard the whole file, warn, start fresh).
#
# `devtools::document()` clean; `devtools::test()` 832/832 (0 failures, up from 817 -- 15
# new offline tests: first-call-caches/second-call-serves-from-cache-with-zero-new-LLM-
# calls, a changed input triggers a real re-review while unchanged accessions stay cache
# hits, cache written once per LLM batch (verified via a call-counting mock on
# `.save_accession_review_cache()`), a failed/NA review is NOT cached and is retried next
# call, old-schema cache gracefully discarded). All 10 PRE-EXISTING tests updated to pass
# `cache_dir = NULL` explicitly -- without this they would have hit the real machine-wide
# default cache directory during `devtools::test()`, a real state-pollution risk caught
# before it happened, not after. `devtools::check()` 0 errors/0 warnings/0 notes.
# Reinstalled and verified at `~/Library/R/4.0/library`, including a live smoke test
# against the installed package (first call: 1 LLM call, both accessions fresh; second
# call, unchanged input: 0 new LLM calls, both accessions `accession_review_cache_hit =
# TRUE`). `AuditNCBI_Goal2_MatchCandidateScreen.R`'s own Step 6 (outside this monorepo, not
# under git) updated to pass an explicit project-scoped `cache_dir` (matching Step 4's own
# `evaluate_reference_accessions()` cache convention) instead of the machine-wide default.
# Previous update, 2026-08-14 (Sonnet 5 -- NCBI rate-limit/timeout resilience for
# `evaluate_reference_accessions()`, prompted directly by the user asking how the
# function could be made more robust to a sustained NCBI rate limit mid-run, after
# noticing this was already a real, documented risk (the "only writes its cache ONCE, at
# the very end" limitation `AuditNCBI_Goal2_MatchCandidateScreen.R`'s own header comment
# already warned about, with a MANUAL chunk-the-list-yourself workaround). Two real
# mechanisms, one in each of the two files this whole reference-accession-quality feature
# spans:
#
# (1) `blast_sequences()`/`.blast_remote()` gains a circuit breaker
# (`max_consecutive_batch_failures`, default `3L`): tracks a WEIGHTED count of
# consecutive BLAST-batch failures (a `.blast_server_rejected()` CPU-budget rejection --
# a real, unambiguous throttle signal from NCBI itself -- counts double; a plain poll
# timeout or submission failure counts once, since either could just be one unusually
# slow/large batch) and stops submitting further batches once the threshold is reached,
# rather than continuing to pay up to `poll_max_wait` (30 min default) for every one of
# potentially dozens of already-doomed remaining batches. When it trips: every batch
# never even attempted is added to `attr(result, "failed_query_ids")` alongside whatever
# already failed (so nothing is silently miscoded as a real zero-hit result, the same
# correctness concern `poll_max_wait`/`failed_query_ids` were built to address for the
# single-batch-timeout case); the halved-batch-size retry pass is skipped entirely (no
# point re-submitting batches already judged doomed); a new `attr(result,
# "circuit_breaker_tripped")` lets a caller react differently from an isolated failure.
# `Inf` disables it, fully restoring the old unconditional-retry-every-batch behavior.
# New internal `.blast_rate_limit_sleep()` wraps the existing `Sys.sleep(11)` NCBI
# rate-limit pauses purely so tests can mock it to a no-op -- a circuit-breaker test
# exercising several consecutive batches would otherwise cost real wall-clock minutes for
# no verification benefit; production behavior (a real 11-second sleep) is unchanged.
#
# (2) `evaluate_reference_accessions()` itself gains `chunk_size` (default `200L`,
# matching the workflow script's own previously-manual convention) and now processes
# `needs_eval` in chunks, writing the persistent cache after EACH chunk rather than once
# at the very end -- automating exactly the manual workaround
# `AuditNCBI_Goal2_MatchCandidateScreen.R`'s header comment already documented. The
# per-accession-set computation (fetch records, hybrid-proxy resolution, BLAST, hierarchy
# congruence, `computed_rows`) was extracted verbatim into a new internal
# `.evaluate_reference_accessions_chunk()`, called once per chunk from a loop in the main
# function; when a chunk's own `blast_sequences()` call reports `circuit_breaker_tripped`,
# the loop stops entirely (no further chunks attempted) and every accession in a
# never-reached chunk is folded into `missing_acc` the same way a genuinely-failed one is.
# New `attr(result, "run_summary")` (`n_total`/`n_from_cache`/`n_evaluated_this_call`/
# `n_pending`/`pct_complete`/`circuit_breaker_tripped`/`recommended_pause_minutes`) plus an
# actionable `message()` on a circuit-breaker trip: how many accessions resolved this call
# (as a %), how many are still pending, and a recommendation to re-run the SAME call after
# a pause (already-cached accessions are read straight from cache, not re-BLASTed) --
# explicitly notes when `cache_dir = NULL` that nothing will actually be resumable, since
# there is nothing to resume FROM in that case.
#
# Real design decisions (both later confirmed via `AskUserQuestion` with the user before
# implementing, not assumed): the circuit breaker lives in `blast_sequences()` itself, not
# only in `evaluate_reference_accessions()`, so every other real/future caller of
# `blast_sequences()` (`investigate_flagged_accession()` included) benefits automatically;
# chunking is ON by default (not opt-in), matching the workflow script's own real,
# validated manual-chunking precedent rather than requiring every caller to discover and
# ask for it.
#
# `devtools::document()` clean; `devtools::test()` 817/817 (0 failures, up from 798 -- 20
# new offline tests: 7 for the `blast_sequences()` circuit breaker itself (weighted
# scoring, non-consecutive-failures-reset, `Inf` disables it, retry-pass-skipped-when-
# tripped, input validation), 5 for the `evaluate_reference_accessions()` chunking/
# circuit-breaker interaction (identical verdicts chunked vs. unchunked, cache written
# once per chunk not once for the whole call -- verified via a call-counting mock on
# `.save_reference_accession_cache()` -- a circuit-breaker trip correctly leaves an
# earlier chunk's real verdict on disk while the un-reached chunk is never even fetched,
# `run_summary` reports 100%/no-trip on an ordinary successful call). `devtools::check()`
# 0 errors/0 warnings/0 notes. Reinstalled and verified at `~/Library/R/4.0/library`.
# Real example usage added to `AuditNCBI_Goal2_MatchCandidateScreen.R`'s own header
# comment and Step 4 (outside this monorepo, not under git) -- the manual "split into
# chunks of 200 yourself" advice replaced with a note that this is now automatic.
# Previous update, 2026-08-13, continued (Sonnet 5 -- implements Question 2 of
# ecosystem_docs/REENTRY_PROMPT_flagged_accession_second_look.md: new
# `review_flagged_accessions()` (R/review_flagged_accessions.R), an LLM second-look
# reviewer for `evaluate_reference_accessions()`'s flagged/borderline output, following
# `TaxaFlag::review_assignments()`'s established "narrative-judgment layer added ON TOP
# of statistical flags, never replacing them, never auto-acting" pattern. Answers all
# four of that reentry doc's own open design questions -- see this file's Function
# Inventory entry and the reentry doc's own updated status note for the full record; in
# short: scoped by default to `hierarchy_flag %in% c("incongruent",
# "insufficient_independent_evidence")` plus `listed_taxon_is_species == FALSE`
# (~7% of a real population, matching the reentry doc's own sizing); outputs a free-text
# `accession_review_comment` plus two small structured fields
# (`accession_likely_explanation`/`accession_review_confidence`), never a re-decided
# `hierarchy_flag` (the exact `trusted_rank` cautionary shape this ecosystem has already
# hit once -- see `[[project_rank_trust_mechanism_removed]]`); placed in TaxaMatch, not
# TaxaFlag (every other reference-accession-quality function already lives here, and no
# new TaxaMatch -> TaxaFlag dependency edge is needed since this calls
# `TaxaTools::call_api()` the same way `review_assignments()` does). Prompt content is
# lifted directly from `inst/reference_accession_evaluation_guide.md`'s own 5-category
# decision framework and worked real examples (Stereolepis doederleini, Abylopsis
# eschscholtzii, NC_028197/"Serranidae sp. JL-2015"), not re-derived.
#
# One new `evaluate_reference_accessions()` output column shipped alongside it, needed to
# answer the reentry doc's own open question ("does the LLM need the disagreeing taxon's
# actual NAME, not just its identity percentage?" -- answer: yes): `best_disagreeing_taxon`,
# the listed species of the SAME highest-identity independent hit `best_disagreeing_pident`
# is already computed from (both read off the same position in the same
# desc(p_match)-sorted slice inside `.compute_hierarchy_congruence()`, so the two stay
# consistent by construction) -- the identical "already computed as part of the
# rank-agreement walk, then silently discarded" pattern the 2026-08-07 identity-diagnostics
# columns themselves were, not a new BLAST/NCBI call. Chosen deliberately over a fresh
# per-review lookup specifically so the LLM-review step adds zero new NCBI cost.
#
# `devtools::document()` clean; `devtools::test()` 778/778 (0 failures, up from 765 -- 13
# new offline tests for `review_flagged_accessions()`, all with a stub `llm_fn`, never a
# real provider call, plus 2 new tests pinning `best_disagreeing_taxon`'s value against
# `best_disagreeing_pident`'s own, and confirming NA when nothing disagrees);
# `devtools::check()` 0 errors/0 warnings/0 notes; reinstalled and verified at
# `~/Library/R/4.0/library`, including a live smoke test against the installed package
# (not just `load_all()`) reproducing this doc's own real Stereolepis
# doederleini/NC_028197 motivating case end to end with a stub LLM. Not yet run against a
# real LLM provider or real flagged GreatLakes output -- left as the natural next step,
# per this project's own "explicit test/re-run instructions" convention (see the reentry
# doc's own updated status note for the exact command).
# Previous update, same day (Sonnet 5 -- closes out the real 5-row incongruent tail left by the
# 2026-08-11 modifier fix, via a new `require_species_resolved_partner = TRUE` param on
# `.compute_hierarchy_congruence()` (`evaluate_reference_accessions.R`). Motivated by a live
# investigation of the user's "review the 3 [non-hybrid] candidates, then do Stereolepis"
# request: `Niphon spinosus` and `Pseudorasbora parva` turned out weak/inconclusive on direct
# re-BLAST, not confirmed problems; `Stereolepis doederleini` (2 real accessions) was traced to
# its one real independent NCBI hit being `NC_028197`, "Serranidae sp. JL-2015" -- a
# non-species-resolved reference (family name + informal specimen code, not a real binomial).
# Whether such a partner happens to "agree" or "disagree" isn't meaningful evidence either way,
# since its own identity is only fuzzily determined -- so it's now excluded from the vote
# entirely (`is_valid_partner` gains `is_species_resolved_y`, applying the exact same
# `TaxaTools::is_plausible_binomial()` check `listed_taxon_is_species` already applies to the
# QUERY side, now applied to the HIT side too).
#
# Live-verified before shipping, not assumed: a direct re-BLAST of `LC649807`'s AMPLICON-TRIMMED
# sequence (not the full mitogenome -- the amplicon-trimmed version is what the real pipeline
# actually submits via `barcode_term = "MiFishU"`, and BLASTing the short, more conserved region
# surfaces a much broader real hit pool -- 20 hits/9 taxa -- than an earlier, methodologically
# mismatched full-mitogenome test had found) showed the fix behaves exactly as designed
# (`NC_028197` correctly excluded) but does NOT rescue Stereolepis after all: real,
# species-resolved, independent hits from 4 OTHER families (Sinipercidae, Banjosidae,
# Epigonidae, Pentacerotidae, all at 94.9-95.9% identity) are genuinely present and genuinely
# disagree. This overturned the original working theory (pure taxonomic isolation) -- the real
# picture is that MiFish-U's short 12S region doesn't discriminate *Stereolepis doederleini*
# well from several unrelated families, a genuine "poor marker resolving power for this
# lineage" case, not a "too few real competitors" one. User's explicit call, given this: accept
# it as a correctly-earned flag (real, independent, resolved evidence), no further weighting
# mechanism -- closing out the Stereolepis half of `ecosystem_docs/REENTRY_PROMPT_
# flagged_accession_second_look.md` (see that doc's own updated status).
#
# `.EVAL_REF_ACC_VERSION` deliberately NOT bumped (reverted from an initial `"v5_..."` bump
# partway through this session, once it became clear `params_key` is one global string applied
# uniformly to every cached row, not conditional per row -- bumping it would have forced a full
# re-BLAST of all ~1,163 already-correctly-cached real GreatLakes rows for a fix whose effect is
# narrow and, on the one real case fully investigated, a no-op on the final verdict). Same
# surgical-cache-row-removal pattern as the 2026-08-11 modifier fix: backed up the real
# persistent cache (`reference_accession_cache.rds.bak_pre_species_resolved_partner_fix`), then
# removed exactly the 22 rows NOT already `"congruent"` (the only rows where this filter could
# plausibly change what a reviewer sees), leaving the other 1,141 rows to keep hitting cache
# untouched. Real re-run result (partial -- NCBI rejected 2 of 3 BLAST batches for exceeding its
# server CPU budget, the same throttling pattern already documented 2026-08-10): 4 incongruent
# (2x Stereolepis, `NC_028197` itself -- expected, it's the non-species-resolved reference,
# already separately flagged via `listed_taxon_is_species = FALSE` -- and `Pseudorasbora parva`,
# matching the earlier weak/inconclusive finding), 18 insufficient, 20 still pending retry
# (including `Niphon spinosus`, not yet re-evaluated). `devtools::test()` 0 failures
# (full suite, including 4 new offline tests for `require_species_resolved_partner`),
# `devtools::check()` 0/0/0, reinstalled and re-verified at `~/Library/R/4.0/library`.
#
# Also new this session: `TaxaMatch/inst/reference_accession_evaluation_guide.md` -- a
# comprehensive, worked-example-driven guide to every `evaluate_reference_accessions()` output
# column (written for both a human reviewer and the LLM second-look reviewer function the
# reentry prompt above still has open), and `TaxaTools::clean_taxon_names(strip_modifiers=)`
# from 2026-08-11 (see that entry directly below, unchanged this session).
# Previous update, 2026-08-11 (Sonnet 5 -- a fourth real gap in the hybrid-maternal-proxy fix,
# found the moment a full real GreatLakes run actually completed successfully (1163/1183
# evaluated, 20 retrying next call): 3 real accessions -- "androgenetic"/"autodiploid"/
# "autotetraploid Carassius auratus red var. x Megalobrama amblycephala" -- still read
# "incongruent"/"hybrid_unresolved". Root cause: a real breeding/ploidy-manipulation
# modifier prefixes the maternal parent's own name with a lowercase word, which
# TaxaTools::clean_taxon_names() correctly refuses (no capital-letter start) -- exactly the
# 2026-08-10 fix's own documented, intentional fallback case, just not yet resolved
# further. The maternal-inheritance argument still holds for all three: androgenesis/
# autoploidy manipulate the NUCLEAR genome, not which egg's cytoplasm (and therefore
# mitochondria) the offspring develops in, so the mtDNA barcode is still genuinely the
# first-listed parent's. Fixed by stripping a SINGLE leading lowercase word (not a
# repeated run of them) before clean_taxon_names() runs -- verified empirically before
# choosing the narrower (single, not repeated) form: a repeated strip on a hypothetical
# "unidentified hybrid x Megalobrama amblycephala" would have consumed the literal " x "
# hybrid marker itself along with both leading lowercase words, silently misattributing
# the SECOND-listed (and biologically unrelated) taxon as the maternal parent -- confirmed
# this exact failure mode directly before shipping, not just reasoned about. A no-op for
# any label that already starts with a capital letter, so this only ever widens what gets
# resolved, never changes an existing resolution. New regression test confirms the 3 real
# modifier-prefixed accessions now resolve (`hybrid_maternal_proxy`, `congruent`); the
# existing `hybrid_unresolved` fallback test was updated to a genuinely still-unresolvable
# two-leading-lowercase-word case (doubling as the misattribution regression guard).
# `devtools::test()` 0 failures (100/100 in this file, up from 98), `devtools::check()`
# 0/0/0, reinstalled. `.EVAL_REF_ACC_VERSION` deliberately NOT bumped this time (unlike the
# 2026-08-10 fix) -- this narrower change only affects accessions matching this exact
# modifier-prefix pattern, confirmed via the regression suite to be a no-op for every other
# accession shape, so forcing a full cache invalidation (and therefore a full re-BLAST of
# all ~1,163 already-correctly-cached accessions) would have been real, unnecessary NCBI
# cost -- especially with today's fair-use throttling concern still live. Instead, the 3
# specific real cached rows (PQ240359/PV257635/PQ240357, all still carrying today's own
# params_key from the fix immediately below) were surgically removed from the real
# persistent cache directly (backed up first as `reference_accession_cache.rds.
# bak_pre_modifier_word_fix`), so only those 3 accessions get re-evaluated on the next run.
# Previous update, 2026-08-10, continued (Sonnet 5 -- a third real bug, found the moment the
# hybrid-maternal-proxy fix (below) was actually run against the full real GreatLakes
# population: a sustained NCBI server-side CPU-budget rejection wave affected 100% of the
# 414 accessions still needing evaluation (every batch, at both batch_size=20 and the
# batch_size=10 fallback retry, rejected) -- and this crashed the ENTIRE call
# ("arguments imply differing number of rows: 0, 1"), losing all progress from that call
# since the persistent cache only writes once, at the very end. Root cause, confirmed via
# a minimal offline reproduction (not guessed): when literally every remaining accession in
# one evaluate_reference_accessions() call fails BLAST, query_meta -- and therefore
# congruence, built from it -- both correctly end up 0 rows, but computed_rows's
# data.frame() call unconditionally mixed those 0-length columns with three scalar columns
# (evaluated_at = now, cache_hit = FALSE, params_key = params_key) -- base R's data.frame()
# does not recycle a length-1 scalar down to 0 rows the way it recycles a scalar UP into a
# longer common length, it errors instead. This was a real, pre-existing landmine (nothing
# to do with the hybrid fix itself, confirmed by reproducing it against non-hybrid
# accessions too) that had simply never been reachable before today's first-ever
# total-rejection-of-an-entire-call event. Fixed: computed_rows is only built
# `if (nrow(congruence) > 0L)`, matching the existing `computed_rows <- NULL` default --
# a call where everything fails now degrades gracefully to the same NA-verdict-per-
# accession, "not cached, will retry next call" behavior the existing partial-failure
# case already has, instead of crashing. New regression test reproduces the exact
# real scenario (every accession failing BLAST within one call, mixed with the
# already-passing partial-failure test immediately above it in the same file).
# `devtools::test()` 0 failures (full suite, 98/98 in this file, up from 94), `devtools::
# check()` 0/0/0, reinstalled. The underlying total-rejection wave itself is a separate,
# real, external NCBI fair-use-throttling event (not a bug this fix addresses) --
# very likely triggered by today's own cumulative heavy real usage across this whole
# debugging thread (the amplicon-fix pilot, the full 1,183-accession run, and this
# crashed attempt, plus live verification calls); see this file's top-of-session note
# below for the recommendation to wait before the next real attempt.
# Previous update, 2026-08-10 (Sonnet 5 -- two real fixes found live-debugging the user's
# GreatLakes Goal-2 match-candidate screen (AuditNCBI_Goal2_MatchCandidateScreen.R), both
# via direct live NCBI verification, not guessed. (1) trim_query_to_amplicon.R's
# plausible-span check (barcode_term = "MiFishU" auto-trim, added 2026-08-09) compared the
# FULL primer-inclusive matched span against min_len/max_len (130-210bp, a general
# marker-length window meant for filtering raw sequence widths) instead of a bound derived
# from the primer pair's own amplicon_range + primer length -- confirmed live against two
# real fish mitogenomes (Danio rerio, Cyprinus carpio, both from NC_002333/NC_001606) that
# BOTH give an identical real full span of 221bp, ~11bp over the old 210bp ceiling, so
# EVERY genuine real MiFish-U hit was being rejected as "implausible" and BLASTed at full
# mitogenome length instead -- the actual root cause of a real 92/92 (100%) extraction
# failure and the resulting catastrophic remote-BLAST slowdown that originally motivated
# this whole debugging thread. Fixed: the plausibility bound now derives from
# primer_info$amplicon_range + combined primer length when barcode_term auto-resolved
# min_len/max_len (an explicit caller-supplied min_len/max_len is still honored as-is,
# unchanged). The identical bug, same duplicated algorithm, was fixed the same day in
# TaxaLikely::trim_to_amplicon() -- see that package's own CLAUDE.md note and its Known
# Footguns entry (amended, not deleted -- the original "0/107 Sebastes rescued, confirmed
# not a bug" investigation's Paralabrax finding still stands on its own evidence, but the
# broader "0% rescue is correct behavior" conclusion does not, since the two failure modes
# were indistinguishable in that investigation's own data). Post-fix pilot run: 86/92
# extracted (a plausible, non-systematic remainder), full 1,183-accession run completed in
# a fraction of the pre-fix estimated wall time.
#
# (2) Real hybrid-cross false-positive mode found reviewing that same full run's 13
# "incongruent" hierarchy_flag results with the user: 10 of 13 were real, correctly-labeled
# hybrid-cross accessions (e.g. "Ctenopharyngodon idella x Megalobrama amblycephala"), not
# mislabels. Confirmed live via direct efetch against several real accessions: NCBI's OWN
# taxonomy entry for a hybrid-labeled organism is genuinely incomplete -- lineage terminates
# at "unclassified Cyprinoidei", no family/genus/species populated at all -- so such an
# accession structurally CANNOT agree with any independent BLAST hit at family rank or
# finer (nothing on the query side to compare), which the rank-walk mechanically reads as
# maximal disagreement. The 3 non-hybrid accessions in the same flagged list all had
# complete normal lineages down to genus, confirming this is specific to the hybrid case,
# not a general problem. Per the user's explicit choice (offered 3 options: mark hybrids as
# a separate non-applicable status; resolve to the maternal parent species' real lineage;
# leave as-is) -- option 2: new mechanism resolves a hybrid-labeled accession's lineage at
# every rank COARSER than species from its maternal parent species instead (fish mtDNA is
# maternally inherited, so this is the biologically correct comparison, not a guess);
# species.x is deliberately left as the accession's own real hybrid label unchanged, since a
# hybrid genuinely is not the same SPECIES as its parent -- only coarser ranks get the
# substitution. Maternal parent name extracted via TaxaTools::clean_taxon_names()'s existing
# 3-token simplification (already keeps only the first genus+epithet, discarding
# " x ..." onward -- confirmed this is the "TaxaID decision to not use hybrids" the user
# was recalling, already implicit in that function, not previously wired into this specific
# check); resolved via TaxaTools::verify_taxon_names(backbone_id = 4L) (NCBI, same authority
# every other taxonomy resolution in this function uses). Detection requires BOTH a
# standalone " x " token in the listed organism name (the standard nomenclatural hybrid
# marker, verified against all 13 real flagged accessions -- correctly separates the 10 real
# hybrids from the 3 non-hybrids with zero false positives either direction) AND the
# accession's own resolved family being unresolvable -- so an ordinary non-hybrid taxon with
# a genuinely incomplete NCBI lineage is never routed through this maternal-parent
# substitution, which would have no biological justification without a real hybrid cross
# (a dedicated regression test confirms this). New `taxonomy_resolution_source` output
# column ("direct"/"hybrid_maternal_proxy"/"hybrid_unresolved" -- the last for a hybrid-
# marker-detected label `TaxaTools::clean_taxon_names()` still can't parse into a usable
# proxy, e.g. "androgenetic Carassius auratus red var. x Megalobrama amblycephala", which
# doesn't start with a capital letter -- an honest admission, not a guess) lets a reviewer
# see which path produced any given verdict. `.EVAL_REF_ACC_VERSION` bumped
# ("v4_hybrid_maternal_proxy") so previously-cached rows (computed under the old, false-
# positive-prone logic) are correctly treated as stale and recomputed, not served as fresh.
# 3 new tests (real hybrid case verified end-to-end against a live-data-shaped fixture,
# including a mocked TaxaTools::verify_taxon_names() cross-package call -- this file's own
# header note already documents that as an established, previously-used pattern; the
# unparseable-label fallback; and a dedicated non-hybrid-with-incomplete-lineage regression
# confirming the proxy mechanism never fires without a real hybrid marker). `devtools::test()`
# 0 failures (full suite unaffected elsewhere), `devtools::check()` 0/0/0, reinstalled and
# verified at `~/Library/R/4.0/library`. Not yet re-run against the full 1,183-accession
# GreatLakes population with this second fix in place -- left for the user's next full run.
# Previous update, 2026-08-08 (Sonnet 5 -- implements ecosystem_docs/REENTRY_PROMPT_
# investigate_flagged_accession_prefilter_group_posthoc.md's top three menu items
# (Question 1's Option A fix, Question 2 item 4, Question 3 items 1-2), per that doc's own
# "Suggested next-session scope" ranking. Cluster-level mislabel detection (Question 3 item
# 3, the doc's own highest-value idea) and Question 4's items were left undone, exactly as
# the doc itself flagged -- item 3 needs real batch data with genuine disagreement-taxon
# overlap to design against meaningfully, not available yet.
#
# (1) Question 1, Option A: investigate_flagged_accession()'s two comparisons
# (conspecific/disagreeing-taxon self- and cross-consistency) now run via new internal
# .blast_against_comparison_set() (reuses blast_sequences() itself, the SAME mechanism
# that originally produced the real evidence making MZ605481 a confirmed candidate_mislabel
# -- 20 independent, coverage-safe Cyprinus carpio hits at 100% identity) instead of a
# hand-rolled pwalign::pairwiseAlignment() loop. The pairwise-alignment path's real
# coverage-blindness problem (a short query vs. a much longer full-mitogenome reference can
# find a tiny, spuriously-perfect local-alignment fragment) is exactly what
# blast_sequences()'s own min_query_coverage already guards against by construction --
# confirmed this was the actual root cause of the real MZ605481 "inconclusive in both
# directions" result the reentry doc itself documents (0 of 30+ candidate accessions
# cleared a 50% coverage floor via NCBI's length-unaware [Organism] species search). This
# is a post-hoc filter (BLASTs against the same broad database, then keeps only hits whose
# accession is in the caller's own comparison set), not a scope-restricted search --
# considered and rejected NCBI's entrez_query gi-list restriction mechanism (the reentry
# doc's other suggested option) as unnecessary extra complexity once the post-hoc-filter
# approach was confirmed sufficient. .align_against_comparison_set() (the old pwalign-based
# function) removed entirely; pwalign dropped from DESCRIPTION Suggests (now unused
# anywhere in this package).
#
# (2) Question 2, item 4: new check_marker_mismatch() (R/check_marker_mismatch.R) -- a
# single cheap GBSeq XML fetch (new internal .fetch_marker_annotation(), reads the feature
# table's /gene and /product qualifiers, same rentrez::entrez_fetch(rettype="gb",
# retmode="xml") endpoint this file's other NCBI fetchers already use) cross-checked
# against a small hand-curated marker-synonym lookup (.MARKER_ANNOTATION_PATTERNS -- 12S/
# 16S/18S/COI/CO1/COX1/cytb/matK/rbcL/trnL/ITS/ITS2). Directly grounded in the real,
# already-confirmed AY850362 case (a genuine 16S-vs-12S marker mislabel, GreatLakes 12S
# audit, 2026-08-06/07) -- the reentry doc's own item 3 first tried and refuted a coarser
# hypothesis (a disagreement resolved only at family/order/phylum signals a marker
# mislabel, while genus/species signals a species mislabel) directly against MZ605481 (a
# real confirmed SPECIES mislabel whose own disagreement is ALSO recorded at order rank),
# so this function checks the record's own annotated gene/product text instead, not its
# taxonomic rank of disagreement. No BLAST, no alignment -- meant to route a flagged
# accession to a completely different, much simpler resolution path (correct the marker
# label, or exclude the accession from this marker's own reference set) before ever
# reaching investigate_flagged_accession()'s much more expensive deep dive.
#
# (3) Question 3, items 1-2: investigate_flagged_accession() gains a persistent,
# accession-keyed cache (default cache_dir = tools::R_user_dir("TaxaMatch", "cache")),
# mirroring evaluate_reference_accessions()'s own asymmetric-TTL philosophy -- a
# "inconclusive_length_mismatch"-class result (BOTH comparisons failed to clear
# min_coverage on either side, the real MZ605481-class outcome) expires after
# inconclusive_ttl_days (default 30) and is retried; any other result is cached
# indefinitely. New investigate_flagged_accessions() (plural) batch wrapper shares a single
# in-memory NCBI-species-search cache across a whole flagged-accession list -- a
# listed_species or disagreeing_taxon repeated across several independently-flagged
# accessions is now fetched from NCBI at most once per batch, not once per accession -- and
# reuses the same persistent cache investigate_flagged_accession() itself writes to/reads
# from, so mixing single and batch calls across sessions on overlapping accessions is
# correctly cache-coherent. Required refactoring the original monolithic function body into
# an internal .investigate_flagged_accession_core() (shared by both entry points, driven by
# an optional shared_cache environment) plus a standalone .print_investigation_summary()
# (so a cache HIT still prints the identical narrative summary a fresh computation would,
# without recomputing).
#
# 20 new tests (test-investigate-flagged-accession.R, test-check-marker-mismatch.R), fully
# offline via local_mocked_bindings() on .fetch_reference_accession_records()/
# .search_species_accessions()/blast_sequences()/.fetch_marker_annotation(), matching this
# package's established mocking convention -- including a real caching/TTL/batch-sharing
# integration test suite mirroring evaluate_reference_accessions()'s own (old-schema-cache
# graceful discard, TTL expiry via backdated evaluated_at, call-counting mocks confirming
# NCBI searches are genuinely shared across a batch, not just structurally plausible).
# devtools::test() 679/679 (0 failures, up from 605), devtools::check() 0 errors/0
# warnings/0 notes, reinstalled and verified at ~/Library/R/4.0/library. Not done this
# session, per the reentry doc's own explicit deferral: Question 3 item 3 (cluster-level
# mislabel detection across a batch -- the doc's own highest-value idea, needs real batch
# data with genuine disagreement-taxon overlap to design against) and all of Question 4
# (voucher/publication-context check, geographic/range plausibility cross-check,
# submission-batch-wide pattern check).
# Same day, continued (Sonnet 5 -- the offline-tested Option A fix above was live-tested
# against the real MZ605481 case immediately after shipping, at the user's explicit request
# ("what's next, test or code?" -> "y"). It failed, twice more, before actually working --
# each failure found and fixed via direct live debugging, not guessed at from documentation:
# (1) .blast_against_comparison_set()'s original design was a POST-HOC FILTER (BLAST
# unrestricted against the full database, then keep only hits matching the comparison set)
# -- returned ZERO matches on both sides even though 30 real conspecific accessions were
# independently confirmed to exist, because they simply never ranked among BLAST's own
# top hits (an unrelated sample from a different search, no guaranteed overlap). Fixed by
# switching to NCBI's ENTREZ_QUERY mechanism (new entrez_query param threaded through
# .blast_submit()/.blast_remote(), internal-only, backward compatible), which restricts the
# BLAST search SPACE itself to the comparison-set accessions -- verified in isolation first
# against one known-good accession (OP739039, correctly recovered at 100% identity/coverage)
# before re-running the full case. (2) Re-running with that fix STILL returned zero matches
# -- direct inspection of the real candidate accessions found the true root cause one level
# further upstream: Pseudorasbora parva has a published reference genome, and 26 of 30
# "other accessions of this species" (via a plain NCBI [Organism] search) were whole-
# chromosome shotgun-assembly records 60-80+ million bp long, which also silently fail to
# fetch full sequence content (too large for NCBI's inline GBSeq_sequence). This is exactly
# the reentry doc's own originally-deferred "Option B" (length-ratio candidate pre-
# filtering) -- deferred at design time as "cheaper but doesn't fully solve the problem,"
# confirmed live to be a REQUIRED companion to Option A, not an alternative to it.
# .search_species_accessions() gained reference_length/max_length_ratio params (default
# ratio 3x, the reentry doc's own tentative "2-3x?" suggestion) using NCBI's real slen
# ESummary field (confirmed live: field name is lowercase "slen", not "length"). (3) The
# first length-filter implementation (widen the client-side search to retmax=500, then
# filter by ESummary's slen) hit a real, independent HTTP 414 "request is too large" error
# on the unbatched entrez_summary() call for 500 IDs -- silently swallowed by the existing
# tryCatch, masquerading as "0 found." Fixed with the same 100-per-batch convention already
# used elsewhere in this file. Even after fixing that, Cyprinus carpio (67,744 total nuccore
# records) STILL returned zero candidates -- its real short mitochondrial-gene deposits
# simply aren't within NCBI's default-sort first 500 [Organism]-search results. Root cause
# traced one level further: length restriction needs to happen SERVER-SIDE, not client-side
# -- rewired the search term itself to `"species"[Organism] AND lo:hi[SLEN]`, confirmed live
# to correctly restrict the search space independent of total record count (Pseudorasbora
# parva: 6 real, genuine "12S rRNA" 177bp records now surface immediately; Cyprinus carpio:
# real COX1/ribosomal-RNA-gene records surface immediately). A final full live re-run
# produced exactly the pattern the doc's own narrative interpretation calls the strongest
# evidence of a genuine mislabel: self-consistency 3/3 accessions clearing coverage, mean
# 87.64% identity (87.08-88.20%); cross-taxon 2/2 clearing coverage, mean 99.42% identity
# (98.84-100.00%) -- MZ605481 is a confirmed candidate_mislabel in the ground-truth CSV.
# .investigate_params_key()'s version string bumped (v1 -> v2) so any real cache row written
# under the broken v1 logic is correctly invalidated, not served as a stale "fresh" hit.
# New .filter_and_cap_accessions()/.valid_reference_length() extracted as pure, directly
# unit-testable helpers (this package's convention mocks only its own internal NCBI-fetch
# wrappers, never raw rentrez calls) -- 5 new offline tests reproduce the exact real
# chromosome-vs-barcode length-distribution shape found live. devtools::test() 696/696 (0
# failures, up from 685 immediately post-shipping), devtools::check() 0 errors/0 warnings/0
# notes, reinstalled and re-verified at ~/Library/R/4.0/library after each of the three
# fixes. See TaxaID/CLAUDE.md's own matching continued note for the ecosystem-level summary.
# Previous update, 2026-08-07, continued yet again (Sonnet 5 -- real bug found on the FIRST
# live re-run of the identity-diagnostics work below, against the real GreatLakes cache:
# `.load_reference_accession_cache()` trusted an on-disk cache file's column schema
# unconditionally. A real cache written before this session's new diagnostic columns
# existed has fewer columns than the current `out_cols` list; `.EVAL_REF_ACC_VERSION`
# correctly invalidates individual stale ROWS via `params_key`, but that can't rescue a
# file whose COLUMN SCHEMA doesn't match -- `cache_hit_rows[, out_cols]` errored
# ("undefined columns selected") even with zero matching rows, since the missing columns
# don't exist in the loaded frame at all regardless of row count. Fixed: the loader now
# compares the loaded file's columns against the current empty-schema template and
# discards the whole file (with a `warning()`, not silent) on any mismatch, symmetric with
# how a `params_key` mismatch already discards individual rows -- the correct response to
# a schema mismatch is starting fresh, not a partial/patched read. New regression test
# writes a real old-schema cache file directly and confirms it's discarded gracefully
# (warns, recomputes, does not error). `devtools::test()` 605/605 (up from 601),
# `devtools::check()` 0/0/0, reinstalled. Anyone with an existing
# `*_ref_eval_cache/reference_accession_cache.rds` from before this session's diagnostic-
# column additions will see this warning once per cache dir, then it self-heals (rewritten
# in the new schema going forward).
# Previous update, 2026-08-07, continued yet further (Sonnet 5 -- follows up on an Opus
# design-consult about the Abylopsis ambiguity (see this file's own note directly below
# for the case) with two of the consult's concrete recommendations, both implemented the
# same day. (1) New `flag_incongruent_references()` -- annotates a match object with the
# full evaluation (hierarchy_flag + all identity/coverage diagnostics) WITHOUT removing
# any row, now the documented RECOMMENDED default; `remove_incongruent_references()`
# remains available but its own roxygen now explicitly says to reach for it deliberately,
# after review, not as a default pipeline step -- the exact "flag, don't auto-drop on an
# uncertain database-derived verdict" correction this ecosystem has already made twice
# before for unrelated mechanisms (`apply_coverage_constraints()`'s `"zero"` ->
# `"relabel"` default; `filter_gbif_quality()`'s `exclude_institution` ->
# `flag_institution`), cited directly by the consult as precedent. (2)
# `.compute_hierarchy_congruence()` gains 5 new output columns -- `best_hit_pident`,
# `best_agreeing_pident`, `best_disagreeing_pident`, `congruent_evidence_exists_anywhere`,
# `congruent_evidence_best_pident` -- surfacing two pieces of information the function was
# already computing and then discarding: real BLAST percent-identity (previously used only
# to ORDER hits before being dropped), and whether ANY independent hit anywhere in the
# full pre-`top_n` pool corroborates the listed rank (not just within the `top_n`-truncated
# slice `hierarchy_flag` itself is computed from). The consult's own math: a HIGH-identity
# disagreeing hit is a real mislabel signal; a MODERATE-identity one is unremarkable for a
# conserved marker with poor resolving power at that rank -- information `hierarchy_flag`
# alone cannot convey, and directly actionable for the real Abylopsis case (both flagged
# accessions' disagreeing hits are consistently a sister family at very high identity,
# still ambiguous between "real mislabel" and "marker/coverage limitation" per the
# consult's own identifiability argument -- this doesn't resolve that, it gives a reviewer
# the actual numbers to judge it with). `.compute_hierarchy_congruence()` is explicitly
# noted as no longer byte-identical to the archived TaxaLikely original (dead code, not
# kept in sync). Real bug fixed before shipping: the rank-agreement walk previously ran
# only on the `top_n`-sliced pool; computing `congruent_evidence_exists_anywhere` required
# restructuring it to run on the full independence-filtered pool FIRST, then slice for the
# `hierarchy_flag` verdict -- a genuine internal reordering, not just additive columns
# bolted on after. Cache schema bumped again (`.EVAL_REF_ACC_VERSION`,
# `"v3_pident_and_anywhere_diagnostics"`) so old cached rows are correctly treated as stale
# rather than silently missing the new columns forever. Also: a small, curated ground-truth
# accession list (`TaxaID/diagnostics/reference_accession_ground_truth.csv`) was added --
# a real known mislabel (`AY850362`, GreatLakes 12S, confirmed 2026-08-06), 4 real
# known-correct-but-thin-coverage accessions from the same audit, the real ambiguous
# Abylopsis pair, and 4 real Menidia accessions (the original motivating false-positive
# case) -- wired into both real external `AuditNCBI.R` workflow scripts (GreatLakes and
# PtConception, outside this monorepo, not under git) as a per-run sanity check against
# already-adjudicated cases, not just fresh unknowns. `devtools::test()` 601/601 (0
# failures, up from 577), `devtools::check()` 0 errors/0 warnings/0 notes, reinstalled.
# See the Opus consult's own full writeup (relayed to the user in-session, not saved as a
# separate doc file per this session's own conversational flow) for the parts NOT yet
# acted on: the graded-likelihood-weighting question itself remains open (the consult's
# own recommendation was these two cheaper diagnostic/default-behavior fixes FIRST, then
# revisit weighting only if they turn out to actually separate real mislabel from
# real-but-ambiguous cases at scale -- not yet tested at scale).
# Previous update, 2026-08-07, continued (Sonnet 5 -- evaluate_reference_accessions()
# gains a full kingdom->species rank_system (was family/genus/species only), prompted by
# a real live-testing result the same day: two independent real PtConception 18S
# accessions for Abylopsis eschscholtzii (KY594854, an unvouchered environmental-amplicon
# clone; KX384617, a voucher-backed NHMUK museum specimen from a peer-reviewed checklist
# paper) both flagged "incongruent", and the user pulled the real BLAST hits by hand and
# found they weren't unrelated organisms at all -- consistently Diphyidae, a SISTER
# family within the same order (Siphonophorae, Calycophorae) as the listed Abylidae. The
# old family/genus/species-only rank_system had no way to report that: finest_common_rank
# collapsed straight to NA the instant family failed, giving identical output for "same
# order, different family" (weak signal, likely 18S's well-documented poor resolving
# power in this clade + thin Abylidae coverage, not necessarily a mislabel) and "no
# agreement even at phylum" (a genuinely strong red flag) -- exactly the ambiguity the
# user flagged when asking "is this accession weak evidence, or a real mislabel" with no
# way from the output alone to tell. Fix: rank_system is now TaxaTools::standard_ranks
# (the full kingdom->species ladder); hierarchy_flag's classification threshold is
# UNCHANGED (still fires at min_congruent_rank, default "family") -- only
# finest_common_rank gets more to report. Query-side taxonomy for every rank is now
# resolved via the internal .resolve_taxonomy_by_acc() (the SAME NCBI-taxonomy-DB
# mechanism already used to classify BLAST hits) instead of TaxaTools::fill_higher_ranks()
# (GNVerifier-backed, and only ever resolved genus+family) -- keeps both sides of every
# comparison on one consistent authority, and removes a cross-backbone dependency this
# function never needed. A real, previously-invisible test-environment bug was found and
# fixed while making this change: the integration tests mocked blast_sequences()/
# .fetch_reference_accession_records() but never .resolve_taxonomy_by_acc() (a brand new
# internal call this fix added) -- since it happened to fail fast and gracefully against
# fictional test accession names, the "fully offline" test suite was silently making real,
# live NCBI calls on every run without erroring or visibly hanging (confirmed by timing:
# 6.67s before the fix, 1.02s after mocking it properly -- the tell that something network-
# bound was happening despite every test passing). New unit test pins the exact regression
# this was built for: an accession whose top hits disagree at family but share its own
# order now reports finest_common_rank = "order", not NA. `devtools::test()` 577/577 (0
# failures, up from 576), `devtools::check()` 0 errors/0 warnings/0 notes, reinstalled.
# See [[the reentry doc's own item 5]] -- still open, not addressed here: this coarse-rank
# diagnostic makes the ambiguity VISIBLE, it doesn't resolve it into a principled graded
# confidence weight; that remains real, deferred future work.
# Previous update, 2026-08-07 (Sonnet 5 -- implements ecosystem_docs/REENTRY_PROMPT_
# blast_based_reference_quality.md: new evaluate_reference_accessions() (per-accession
# BLAST-based reference-quality evaluation) + remove_incongruent_references() (the early,
# narrow hard-filter consumer, mirrors TaxaLikely::remove_flagged_references()'s
# established pattern). Supersedes, for the accession-quality question specifically, the
# taxon-list-scoped DECIPHER whole-set-alignment approach the reentry doc's own design
# session abandoned earlier the same week (TaxaLikely::audit_reference_database()/
# classify_reference_accessions(), archived at TaxaLikely/archive_decipher_reference_
# audit/) -- that approach's "among"/foreign comparison population for any accession was
# exactly and only whatever else the caller's own `taxa` argument happened to fetch, with
# real, live-confirmed false positives (15 genuine, Smithsonian-vouchered Menidia
# accessions flagged "incongruent" purely because Menidia's family had no other
# representative in a real 6-genus GreatLakes test) and a structural false-negative gap
# (a mislabeled accession's true contaminating identity can only be caught if its genus
# happened to be on the same caller's list). BLASTing each accession against a broad,
# unrestricted database removes the taxa-list dependency for both directions at once.
#
# Implementation duplicates (not reaches across packages for) three small, already-
# validated pieces of TaxaLikely's archived congruence machinery --
# .build_submission_batch_lookup()/.same_submission_batch() (the same-submission-batch
# independence-filter helpers) and .compute_hierarchy_congruence() itself (the Jeffreys-
# smoothed rank-agreement math, unchanged) -- mirroring this exact two-package
# precedent already set by .parse_lat_lon() (duplicated between TaxaLikely/R/fetch.R and
# TaxaMatch/R/blast_sequences.R for the identical "TaxaMatch must never depend on
# TaxaLikely" reason). What's genuinely NEW, not duplicated, is the caller:
# evaluate_reference_accessions() builds the id_x/id_y/{rank}.x/{rank}.y-shaped pair table
# .compute_hierarchy_congruence() expects directly from real, unrestricted BLAST hits
# (via blast_sequences() itself, resolve_taxonomy = TRUE) instead of a narrow DECIPHER
# alignment -- a genuinely broader comparison population fed through the identical,
# already-validated math. New .fetch_reference_accession_records() (one combined GBSeq
# XML round trip per batch, rentrez::entrez_fetch(rettype="gb", retmode="xml")) gives
# sequence + listed organism + submission create-date all at once, reusing the exact
# accession-keyed NCBI-fetch pattern .resolve_locations_by_acc() (R/blast_sequences.R)
# already established -- including its version-suffix-stripped join-back-to-caller's-
# own-requested-string defensive pattern, load-bearing here since the returned accession
# string becomes id_x/composite_id for the hierarchy-congruence join. Query taxonomy
# (family/genus/species) is derived via .extract_genus() (already in utils_shared.R) +
# TaxaTools::fill_higher_ranks() (this ecosystem's established genus->family lookup);
# hit taxonomy comes free from blast_sequences(resolve_taxonomy = TRUE)'s own output.
#
# Persistent, cross-run cache (default tools::R_user_dir("TaxaMatch", "cache"), keyed by
# accession alone, not by taxon/genus/project -- the user's own stated design intent, a
# real compounding advantage over the old AuditNCBI.R workflow's per-project `taxa` list):
# asymmetric TTL, per the user's explicit choice ("option b" of two offered) --
# "congruent"/"incongruent" verdicts cached indefinitely (an accession's own sequence/
# label doesn't change once deposited); only "insufficient_independent_evidence" expires
# (insufficient_evidence_ttl_days, default 180) and is retried, since new NCBI deposits
# could genuinely change that answer. A cached row is also invalidated by any change to
# a parameter that affects the verdict itself (a params_key string, not a cryptographic
# hash -- no new dependency needed). Within-call dedup happens unconditionally
# (unique(accessions)), independent of caching, per the reentry doc's own framing.
#
# A real, structural bug was found and fixed before shipping, via testing against the
# genuinely common "brand-new species, zero BLAST hits at all" case, not by inspection:
# the initial version's empty-hits fallback built a bare one-column (id_x only) congruence
# frame, which silently made every such accession VANISH from the final output entirely
# (a downstream merge()'s right side had no n_independent_top_matches/etc. columns to
# bring in, so ifelse()/data.frame() calls on NULL columns collapsed the whole result to
# zero rows) -- fixed with a properly-shaped empty frame carrying all five expected
# columns; a dedicated regression test (a genuinely hit-less accession) guards this.
# Two smaller real bugs also found via live testthat runs: a base merge() call with
# differing by.x/by.y names, where BOTH frames already had a real column literally named
# "accession" (the BLAST hit's own subject accession vs. the query-side join key) --
# replaced with dplyr::left_join(by = c(x = y)), which is unambiguous about which side's
# same-named column survives; and `cache_hit_rows$cache_hit <- TRUE` erroring
# ("replacement has 1 row, data has 0") whenever the cache-hit subset was legitimately
# zero rows -- scalar assignment onto a NEW column of a zero-row data frame does not
# recycle the way it does on an existing column. `devtools::test()` 576/576 (0 failures,
# up from 523 -- 53 new, fully offline via local_mocked_bindings() on
# .fetch_reference_accession_records()/blast_sequences()/TaxaTools::fill_higher_ranks(),
# matching this package's own asNamespace()-wrapper convention for internal-function unit
# tests and TaxaExpect's established cross-package .package= mocking convention),
# `devtools::check()` 0 errors/0 warnings/0 notes (withr added to Suggests, matching
# TaxaTools's own existing precedent, for the caching tests' tempdir isolation).
# Reinstalled and verified at `~/Library/R/4.0/library`.
#
# NOT done this session, explicitly flagged as real, agreed-on future work (per the
# reentry doc's own item 5, deliberately left undesigned): the full per-accession quality
# signal (frac_independent_below_min_congruent_rank etc., not just the binary blacklist
# decision remove_incongruent_references() consumes) needs to survive through every
# TaxaMatch/TaxaLikely transformation between the early filter and
# TaxaLikely::evaluate_likelihoods(), so it can inflate/discount likelihood the way
# score_likelihood_cov already does for alignment coverage -- no signature or mechanism
# decided yet, flag as its own task when picked up. Also not done: AuditNCBI.R/
# AuditNCBI_README.md's fate once this exists (rewrite vs. retire, not decided); local
# BLAST (method = "local") not evaluated for large batch compilations; not yet wired into
# any real production workflow.
# Previous update, 2026-08-03 (Sonnet 5 -- blast_sequences() real subject-length filter bug
# fixed, found live debugging why real reference sequences (Ameiurus melas/natalis) for
# a real GreatLakes2023 12S ASV never appeared as BLAST candidates despite the user
# confirming (via a direct pairwiseAlignment() check) that real, well-matching reference
# sequences existed for them. Root cause: .filter_blast_hits()'s subject-length filter
# checked `hits$slen` (the GenBank record's OWN total sequence length) instead of
# `hits$length` (the aligned region's length) against `subject_len_range` -- silently
# discarding a perfect congener match whenever that congener happened to be deposited as
# part of a long mitogenome record rather than a short barcode-only submission. Fixed by
# switching the check to `hits$length`; extensive new @details documentation added
# explaining the real motivating case. A second hypothesis (NCBI's implicit megablast
# default suppressing hits) was tested first and found NOT to be the actual cause (live
# A/B test with the fix already applied returned identical results either way) but was
# kept anyway per the user's explicit "let's fix both" -- explicit > implicit undocumented
# defaults is a real improvement independent of whether it was the bug. New `megablast`
# param (default FALSE, matches the pre-existing implicit behavior byte-for-byte) threaded
# through `.blast_remote()`/`.blast_local()`/`.blast_submit()`.
#
# Also added, same session, per the user's explicit request ("can we set a max hits per
# taxon?"): new `max_hits_per_taxon` param. Real complication found and solved along the
# way: remote BLAST XML never actually populates real per-hit taxids
# (`.parse_blast_xml()` hardcodes `staxids = NA_character_` on every row), so grouping by
# `staxids` directly would have been silently inert for the exact use case that motivated
# this feature. Fixed via a `stage`/`taxon_group_col` restructuring of
# `.filter_blast_hits()` (steps 1-3 run first as `stage="basic"`; taxonomy is then
# resolved via a new extracted `.attach_taxonomy()` helper -- tries taxid-based
# resolution first, falls back to accession-based; a combined `.taxon_group` key
# (species > genus > staxids > row-unique fallback) is built; then `.filter_blast_hits()`
# runs the remaining steps grouped by that real key). Gated behind
# `resolve_taxonomy = TRUE` to avoid unwanted extra NCBI taxonomy calls for callers not
# using this feature; the default (`resolve_taxonomy = FALSE` or `max_hits_per_taxon =
# NULL`) path is completely unchanged. Live-verified end to end against the real
# motivating ASV with all three fixes active: 9 unique species across 3 genera now
# correctly surface as candidates (previously just 1). `devtools::test()` 523/523 (0
# failures), `devtools::check()` 0 errors/0 warnings/0 notes, reinstalled to
# `~/Library/R/4.0/library`.
#
# Same session, `inst/workflow_fastq_to_match.R` (the generic FASTQ-to-match template,
# used as a starting point for future studies beyond GreatLakes) updated to demonstrate
# `max_hits_per_taxon`/explicit `megablast` in both its remote and local BLAST examples,
# plus two new cautionary comments aimed at whoever adapts this template to their own
# multi-run study: (1) merge identical sequences across sequencing runs BY IDENTITY
# before calling `blast_sequences()`, not after reconciling two already-BLASTed match
# objects (the real GreatLakes2023 pipeline was doing the latter until this same session
# -- see the ecosystem-level note in `TaxaID/CLAUDE.md` for the architecture fix and the
# real BLAST-volume/consistency cost this avoids); (2) after any TaxaMatch upgrade, a
# resumability scheme that only reblasts previously-zero-hit ASVs will NOT catch an ASV
# left with a real-but-incomplete candidate set by a since-fixed bug (it already "has a
# hit") -- a full reblast is the safe default post-upgrade, a real, previously-latent risk
# this exact debugging session ran into with the GreatLakes production data.
# Previous update, 2026-07-25, later same day (Sonnet 5 -- convert_taxonomy_backbone() now
# ALSO clears rank columns finer than a row's corrected rank (e.g. species -> NA when a
# row is demoted to genus), not just taxon_name/taxon_name_rank -- found only by the user
# actually testing the same-day taxon_name_rank fix (row directly below) against the real
# Mugu_Match_from_BLAST.R production script, not by inspection. Root cause: that script
# calls TaxaTools::create_taxon_names() a SECOND time immediately after convert_taxonomy_
# backbone(), specifically to re-derive taxon_name from rank columns after backbone
# conversion (a real, existing step, not hypothetical). The per-column rank fallback
# (documented, unchanged) deliberately keeps species = "Inu sp. 1 sensu..." in place when
# GBIF has no species-level target for it -- correct in isolation, but that second
# create_taxon_names() call then saw species still populated, applied "most specific
# non-NA rank wins", and silently REVERTED the whole taxon_name_rank fix back to the wrong
# species-level label. Confirmed live against the real accession (LC765844): after the
# first fix alone, taxon_name/taxon_name_rank were briefly correct ("Luciogobius"/"genus")
# immediately after convert_taxonomy_backbone() but reverted to ("Inu"/"species") by the
# time match_12s.rds was saved. Fixed by clearing every rank column finer than
# matched_rank on the same rows the name/rank correction already applies to -- so ANY
# downstream re-derivation (this one, or a future one) sees a genuinely NA species column
# and can't accidentally resurrect the stale value. genus itself is untouched by this
# clearing (it's AT the corrected rank, not finer than it) -- confirmed already correctly
# updated to "Luciogobius" by the pre-existing per-column mechanism regardless (GBIF did
# resolve a real target_genus), only species (no target available) needed either fix. New
# dedicated regression test reproduces the exact two-call sequence
# (convert_taxonomy_backbone() then create_taxon_names()) that exposed this in production.
# devtools::test() 0 failures (test-convert_taxonomy_backbone.R 47/47 up from 43, full
# suite 508/508), devtools::check() 0/0/0. Reinstalled to ~/Library/R/4.0/library.
#
# Separately, real friction diagnosing this: the user's live RStudio session (a different
# project, SepulvedaMugu.Rproj, with no project-level .Rprofile of its own) kept loading
# TaxaMatch from the SYSTEM DEFAULT library
# (/Library/Frameworks/R.framework/.../Resources/library) instead of ~/Library/R/4.0/
# library, even after .rs.restartR() -- confirmed directly (`.libPaths()` showed only the
# system path; `any(grepl("matched_rank", deparse(body(TaxaMatch::convert_taxonomy_
# backbone))))` was FALSE in their session while TRUE when checked independently with
# .libPaths() forced to the correct directory). Root cause not fully resolved this
# session -- ~/.Renviron correctly sets R_LIBS_USER and ~/.Rprofile was already fixed in
# an earlier session (no longer clobbers .libPaths()), so something else in this specific
# project's startup chain still isn't landing right. Worked around by using
# devtools::load_all() directly on both package source directories instead of relying on
# library()/the installed copy at all -- confirmed working. A durable fix (a project-level
# .Rprofile for SepulvedaMugu.Rproj, mirroring what the TaxaID project has) was offered to
# the user but not yet implemented -- flagged for a future session if this recurs.
# Previous update, 2026-07-25 (Sonnet 5 -- convert_taxonomy_backbone() now corrects
# taxon_name_rank on fallback, closing the second half of a real "Inu Inu" fabricated-
# pseudo-binomial artifact found in real Mugu output. Root cause: when a row's own
# taxon_name_rank has no matching target-backbone value at that same rank (a real case:
# an informally-named NCBI reference resolves against GBIF to genus "Luciogobius" only,
# no species-level entry -- see TaxaTools/CLAUDE.md's same-day note for the full
# investigation, including why this is a synonym relationship GBIF's backbone recognizes
# and NCBI's own taxonomy does not), taxon_name correctly fell back to the coarser
# matched_name_clean value, but taxon_name_rank silently kept its stale, now-wrong rank
# label -- reporting a bare genus ("Luciogobius") as if it were still species-level. A
# downstream slash-name builder (TaxaAssign::add_slash_taxon()'s .make_slash_name())
# then treated that mislabeled single-word name as if it needed splitting into genus+
# epithet and manufactured a fabricated doubled binomial ("Inu Inu") from it -- the exact
# symptom the user first spotted in real review_assignments() output. Fixed using
# TaxaTools::verify_taxon_names()'s new matched_rank column (same-day companion fix,
# reports the rank a match ACTUALLY resolved at): when the taxon_name fallback fires, the
# row's own claimed rank was wrong, so taxon_name_rank is now corrected to matched_rank
# alongside the name itself -- a small, targeted addition (~15 lines), not a rewrite of
# the existing rank_col_idx logic, which is left untouched for the common case where a
# row's own claimed rank DOES have a valid target. Gracefully skipped (not an error) when
# `verified` lacks matched_rank -- e.g. a verify_fn injected for offline testing that
# predates this change -- confirmed via a dedicated backward-compatibility test using
# exactly the shape every pre-existing mock verify_fn in this file already has. 2 new
# tests reproduce the real Inu case directly (one confirming the fix engages, one
# confirming it's a no-op without matched_rank). devtools::test() 43/43 in
# test-convert_taxonomy_backbone.R (up from 41), full suite 504/504, devtools::check()
# 0/0/0. Reinstalled to ~/Library/R/4.0/library. See TaxaTools/CLAUDE.md's matching
# same-day note for the upstream fix and the full multi-backbone verification record, and
# TaxaID/CLAUDE.md's Recent Breaking Changes table for the cross-package summary.
# Previous update, 2026-07-24 (Sonnet 5 -- convert_taxonomy_backbone() now cleans the
# not-found (fallback-to-original) path too via TaxaTools::clean_taxon_names(), not just
# the target-backbone-matched path. Found while reviewing the domestic/food-priors
# residual-count exercise on real PtConception 18S data: a compound hybrid-formula taxon
# name straight from a raw NCBI reference accession label
# ("((Citrus unshiu x Citrus sinensis) x Citrus reticulata) x Citrus reticulata") reached
# match_obj$taxon_name/species completely unmodified. Traced to source: this function
# already called clean_taxon_names() on matched_name/target_<rank> (the successfully-
# verified path) but never on the value used when the target backbone has no match for an
# exotic name -- the raw original passed straight through. Fixed via new
# taxon_col_clean_fallback/rank_clean_fallback (clean_taxon_names() applied once to the
# original values, used wherever the not-found fallback is referenced) -- deliberately
# does NOT change what's sent to verify_fn or which rows count as "found"; only the
# fallback value's formatting changes. clean_taxon_names()'s existing bracket-strip +
# 3-token split already handles this case correctly once given the chance to run
# (produces "Citrus unshiu" for the example above). 4 new tests
# (test-convert_taxonomy_backbone.R), including a verification that found/not-found
# classification itself is unchanged. devtools::test() 0 failures (500, up from 496),
# devtools::check() 0/0/0. Reinstalled to ~/Library/R/4.0/library. See TaxaExpect/CLAUDE.md's
# and TaxaFetch/CLAUDE.md's matching notes for the companion iNaturalist-backbone-mismatch
# fix from the same design conversation.
# Previous update, 2026-07-23 (Sonnet 5 -- new read_speciesnet_output(), prompted by the
# user asking whether TaxaFetch was "missing an opportunity to use SpeciesNet" after a
# Gemini-drafted function (a placeholder parser, own comment admitted guessing at field
# names, plus a locally-redefined %||% that violates this ecosystem's TaxaTools-import
# convention). Design worked through with the user step by step rather than built from
# the draft: (1) package placement corrected to TaxaMatch (classifier-output ingestion),
# not TaxaFetch (occurrence acquisition); (2) confirmed TaxaMatch already has
# read_animl_output()/read_wildlife_insights_output() for SpeciesNet-adjacent sources,
# so the question became whether either was a sufficient substitute for the real,
# current SpeciesNet CLI; (3) checked the real Wildlife Insights platform's own docs
# (bulk downloads are a CSV bundle -- images.csv/sequences.csv, not JSON at all) and the
# real Animl cloud platform's export docs (CSV drops bounding boxes entirely, exports
# only the single "winning" reviewed label per object, excludes unreviewed images) --
# both are lossy/non-matching relative to real SpeciesNet output, so a new function was
# warranted, not redundant; (4) the user surfaced Markoff & Galaktionovs 2025
# (arXiv:2510.14594, written by Animal Detect's own CTO/CEO) mid-design, which confirmed
# SpeciesNet's taxonomic rollup to genus/family/order/class/kingdom is a deliberate
# precision-over-recall ensemble behavior, not an edge case -- directly settling the
# "what to extract" question: the raw top-5 `classifications` block (pre-rollup,
# pre-geofencing) is the right primary multi-candidate source for TaxaLikely's scored
# pathway, not the already-conservative `prediction` field, since this ecosystem's own
# Bayesian coarse-rank-resolution machinery (join_priors()/TaxaExpect priors/TaxaLikely
# H2-H3) is arguably a more principled way to do what Animal Detect's own bespoke
# CLIP+triplet-loss re-classification system is patching for (their own paper's
# "Current limitations" section names "Bayesian confidence intervals" as future work).
# The exact real label format (`uuid;class;order;family;genus;species;common_name`,
# 7 semicolon-delimited fields) was pulled directly from the shipped taxonomy file
# (`data/model_package/taxonomy_release.txt` in `google/cameratrapai`) rather than
# assumed from the README's paraphrase -- verified against real rollup examples at
# every rank (species/genus/family/order/class) plus the non-taxonomic placeholders
# ("blank"/"animal"/"vehicle"/"no cv result") before writing tests. New
# read_speciesnet_output() + .parse_speciesnet_label()/.speciesnet_detection_coverage()
# helpers in R/read_image_classifiers.R; optional include_coverage/min_detection_conf
# mirrors read_animl_output()'s existing bbox_cols->coverage convention. Along the way,
# a real, previously undetected gap was found in read_wildlife_insights_output(): its
# dict-keyed-by-filename JSON assumption doesn't match either real candidate source
# checked this session (real Wildlife Insights is CSV; real SpeciesNet CLI's
# `predictions` is a LIST, not a dict) -- and a prior code review
# (inst/taxamatch_review.Rmd, Session ~20260720) had already flagged suspicion about
# this exact function's premise ("Confirming whether multi-candidate output is actually
# supported by the SpeciesNet JSON schema" was left as an open question, never
# resolved). Zero real callers found anywhere in the monorepo via grep (only its own
# tests, README, and TaxaWizard template snippets/prompts) -- the user confirmed
# removal outright (matching this ecosystem's established zero-caller-removal bar,
# e.g. fetch_reference_sequences()/audit_barcode_coverage_ncbi()/
# expand_consensus_candidates()) rather than deprecation, since read_speciesnet_output()
# is a real replacement for its one claimed real-world use case. Removed: the function,
# .parse_wi_predictions()/.empty_wi_result() helpers, and its 14-test block from
# test-read_image.R. Repointed the same session: TaxaMatch-package.R (3 refs), both
# READMEs (root + package), TaxaWizard's workflow_graph.json (2 edges),
# snippets/image_to_match.R, snippets/image_refs_to_matrix.R, prompts/phase_classify.md,
# metadata/TaxaMatch.json (full entry replaced with read_speciesnet_output()'s real
# signature), metadata/TaxaLikely.json (one description reference). Historical/frozen
# records left untouched per this ecosystem's own convention (a record of past state,
# not current documentation): inst/taxamatch_review.Rmd,
# inst/taxamatch_review_response.md, ecosystem_docs/parameter_audit_2026-07-06*.md.
# Found along the way while rewriting the two TaxaWizard image snippets: EVERY existing
# read_*() entry in TaxaWizard's own metadata/TaxaMatch.json uses `"name": "data"` as
# the first input parameter, but every real read_*() function in this file actually
# takes `files` as its first argument (`data` isn't even a valid formal for
# read_animl_output()/read_birdnet_output()/read_inaturalist_cv_output() -- would error
# "unused argument" if a generated script actually called it) -- the same class of
# drift already flagged in [[project_taxawizard_metadata_drift]]. Fixed narrowly for
# the code touched this session (the new speciesnet branch in both snippets correctly
# uses `files =`; read_speciesnet_output()'s own metadata entry uses `"name": "files"`)
# but the pre-existing animl/inaturalist_cv/birdnet metadata entries and snippet
# branches were left as-is -- out of scope for this session, the broader audit item
# stands. devtools::test() 494/494 TaxaMatch (508 minus 14 removed), TaxaWizard 367/367
# unaffected; devtools::check() TaxaMatch 0 errors/0 warnings/0 notes. Reinstall still
# pending.
# Previous update, 2026-07-20 (Sonnet 5 -- full code + domain review response against
# inst/taxamatch_review.Rmd (10 files: blast.R, convert_taxonomy_backbone.R,
# read_acoustic.R, read_image.R, report_match.R, score_image_inat.R,
# sequence_input.R, standardize_match_data.R, TaxaMatch-package.R,
# taxonomy_consistency.R), findings and response recorded in
# inst/taxamatch_review_response.md (new file, following the TaxaFetch review
# response's format). Following the review's own file-rename suggestions, 3 files
# renamed to match their single exported function: blast.R -> blast_sequences.R,
# read_acoustic.R -> read_birdnet_output.R, read_image.R ->
# read_image_classifiers.R (holds 3 related image-classifier readers).
#
# Two real bugs found via LIVE verification (not just code reading), both in
# score_image_inat.R: (1) .extract_exif_info()'s manual S/W sign-flip logic
# double-applied the hemisphere sign -- exifr::read_exif() already returns signed
# decimal degrees (confirmed against a real exiftool-written fixture with known
# S-latitude/W-longitude), so the existing code silently flipped a
# correctly-negative value back to positive for every Southern-hemisphere
# latitude and Western-hemisphere longitude. Fixed by trusting exifr's own sign
# and removing the redundant re-flip. (2) Confirmed live against the real iNaturalist
# CV API (fresh token, real image, HTTP 200) that scores are on a 0-100 scale
# (combined_score ~53.8, top-10 sum ~84.4, not summing to ~1) -- score_image_inat.R's
# own doc was already correct, but read_image.R's read_inaturalist_cv_output()
# roxygen showed a fabricated 0-1-scale example and an @return claiming "(0-1)",
# both fixed; the v2 API endpoint referenced in that file's doc example was also
# corrected to v1 (the endpoint confirmed live-working, and what score_image_inat.R
# itself actually calls).
#
# Most other fixes are DRY consolidation (new R/utils_shared.R: .check_pkg(),
# .extract_genus(), .stop_missing_files(), .validate_min_conf_top_n(),
# .apply_top_n(), .warn_na_coercion(), .warn_duplicate_basenames(), .fmt_time() --
# applied across blast_sequences.R, read_birdnet_output.R,
# read_image_classifiers.R, score_image_inat.R, sequence_input.R), real doc/logic
# bugs (report_match.R's score_original-vs-score doc mismatch and unused verbose
# param; the "%g%%" score formatting that would have printed "0.87%" for a 0-1
# acoustic/image confidence score; standardize_match_data.R's top-level
# `.standard_match_ranks <- TaxaTools::extended_ranks` package-load-time side
# effect, an R CMD CHECK/CRAN-policy issue, moved inside `.detect_rank_cols()`),
# and a handful of cheap, real perf fixes (taxonomy_consistency.R's
# add_lowest_consistent_rank() replaced a which(obs_ids == id) O(n x unique_obs)
# rescan with a precomputed split() index; sequence_input.R's
# .parse_semicolon_headers() replaced a do.call(rbind, lapply(...)) growth
# pattern with a pre-allocated matrix). read_birdnet_output.R's observation_id
# now formats start_s/end_s to a fixed 1 decimal place (was bare numeric-to-string
# coercion, which can render inconsistently across platforms/R versions) --
# the one behavioral change with an existing-test update (test-read_acoustic.R's
# expected ID string). One design item deliberately declined: renaming
# standardize_match_data()'s `data` parameter (base R's `data()` function name) --
# unlike the internal `df` renames applied elsewhere, this is a public,
# already-shipped parameter name and renaming it would be a breaking signature
# change for every call site using `data = ...`.
#
# devtools::test() 456/456 (0 failures, 0 warnings -- one real false-positive-
# generating warning bug in my own first attempt at .warn_duplicate_basenames()
# found and fixed via this same test run: it flagged legitimate long-format data
# -- the same image path repeated across multiple candidate-species rows -- as a
# basename collision; fixed to check (basename, full path) pairs, not raw
# basenames, before warning). devtools::check() 0 errors/0 warnings/0 notes.
# lintr: 0 issues in every file this session touched (verified via a filtered
# lint_package() run scoped to just those files); the ~20 object_usage_linter
# false positives from cross-file utils_shared.R helper calls were confirmed
# real-and-correct via codetools::checkUsage() on the loaded namespace (same
# false-positive class TaxaFetch's own CLAUDE.md already documents for
# lint_package()'s per-file static analysis) and suppressed via whole-file
# .lintr exclusions (not per-line, given the number of new cross-file call sites
# and this ecosystem's own documented line-number-drift risk with per-line
# exclusions). Reinstalled to ~/Library/R/4.0/library.
#
# Previous update, 2026-07-16 (Session 159 -- blast_sequences() now retains subject-side
# alignment coordinates (new `subject_start`/`subject_end` output columns), both the
# remote (`.parse_blast_xml()`, extracts `Hsp_hit-from`/`Hsp_hit-to`) and local
# (`.blast_local()`, adds `sstart send` to the rBLAST `-outfmt 6` field list) paths. Found
# needed while debugging a real Mugu 12S misassignment (Fundulus parvipinnis vs F. lima):
# TaxaLikely's new restore_suppressed_candidates(check_regional_overlap = TRUE) (same
# session, see TaxaLikely/CLAUDE.md) needs to know WHERE within a query's top-hit reference
# sequence the alignment actually fell, to tell whether a same-genus congener's OWN
# reference covers the same genomic position or a different, non-overlapping one -- BLAST
# already computes this (`Hsp_hit-from`/`Hsp_hit-to`), it was just never parsed or retained
# anywhere downstream; only the query-side coordinates (`Hsp_query-from`/`-to`) were kept.
# Purely additive -- `subject_start`/`subject_end` (1-based, BLAST tabular convention,
# `subject_start > subject_end` on the minus strand) pass straight through
# `.filter_blast_hits()` unchanged (row-filtering only, no column subsetting there) into
# the final output; no existing column renamed or removed. 5 new tests (test-blast.R):
# `.parse_blast_xml()` correctly extracts real hit-from/hit-to values (verified against the
# exact real Fundulus lima case, position 515-613) and correctly returns NA when a fixture
# HSP omits them (pre-existing test, unaffected). `devtools::test()` 64/64 in this file (up
# from 59), `devtools::check()` 0 errors/0 warnings/0 notes.
# Previous update, 2026-07-11 (Session 151 -- ecosystem soundness-review item 14
# (blast_sequences()'s score_window) fixed: default score_range widened 2 -> 8, backed by
# a new real-data leave-one-out check (diagnostics/score_window_leave_one_out.R at the
# TaxaID root), not a guess. The review flagged that a fixed 2-point tolerance window can
# silently drop the true species from blast_sequences()'s output entirely -- before
# TaxaLikely/TaxaAssign ever see it, with no way to recover it downstream -- whenever a
# confusable congener happens to score higher, and that this had only ever been
# field-tested on 5 easy PtConception queries with clear top hits at 98%+ identity.
# Method: treat each reference sequence in a real reference-vs-reference distance matrix
# as a leave-one-out query against every other sequence in the same matrix, and ask how
# often (and by how much) a congener outscores the sequence's own true species. Run
# against three independent real 12S datasets: Sebastes (54 species, real
# MiFish-window-filtered data) -- 3/113 events, all trivial (0.6 pts, none dropped at the
# old default); Chromis (26 species) -- 3/33 events, 4.7-7.1 pts, ALL THREE would have
# been silently dropped at score_range=2; a real 6-genus PtConception 12S set -- 1/11
# events, 2.5 pts, also dropped. Pooled: 4 of 7 real congener-outscoring events (57%)
# exceeded the old default. New default (8) covers every gap actually observed with
# margin -- documented explicitly as evidence-backed given what's been measured so far,
# not proof against a more extreme future case; max_hits=20 (unchanged) still bounds
# candidate volume regardless of window width, and the wider window is exactly what
# preserves TaxaLikely::train_likelihood_model()'s "gap" feature (its own key H1/H2/H3
# discriminator) for the bivariate-normal model to actually use, rather than this coarse
# pre-filter silently deciding the case on raw percent-identity alone -- directly closing
# the review's own cross-cutting pattern #3 (percent-identity thresholds can't reliably
# discriminate species from congener; route that decision through the bivariate-normal
# path instead). Two real workflow scripts hardcoding the old value updated
# (blast_sequences_workflow.R, workflow_fastq_to_match.R). New test pins the default at
# 8. devtools::test() 451/451, check() clean. See
# ecosystem_docs/STATISTICAL_COMPONENT_SOUNDNESS_REVIEW.md's item 14 for the full record.
# Previous update, 2026-07-06 (Session 139 — two related fixes, both found via live testing,
# not code reading. (1) build_site_table()'s default spatial_group_id changed from
# observation_id to an exact-(lat,lon)-match grouping (new is_default_group marker column
# replaces the old spatial_group_id==observation_id heuristic group_observations_by_bbox()/
# assign_spatial_group() used to detect "still default"). A grid-snapping design (round to
# a fixed bin size) was tried first and rejected after it collapsed four genuinely distinct
# real observations into one default cluster on this ecosystem's own bundled test data --
# exact match has no such tuning parameter and matches this ecosystem's actual data flow
# (shared coordinates come from a site-metadata table join, not noisy independent GPS).
# New .next_spatial_group_number() helper keeps default-assigned and interactively-drawn
# "spatial_group_<n>" labels from colliding. (2) Spatial-grouping applet usability redesign:
# TaxaTools::define_search_polygon() gained title/done_label/cancel_label params (backward
# compatible) so group_observations_by_bbox() can describe what each button does in context
# ("Group These Points"/"No More Groups" instead of generic Done/Cancel) and show per-group
# progress in the title itself; the gadget's initial zoom is now one step further out so the
# starting (unshrunk) box is actually visible on first open. See Session 139 note below for
# the full record, including a real live bug (define_search_polygon() returning NULL on
# Cancel crashed several calls downstream in TaxaID_Workflow_Template_TEST.R's Section 3 with
# a confusing error) found and fixed the same way.
# Session 137 continued — join_event_site_metadata() added:
# Phase 4 (DNA/BLAST half) of the observation-pipeline-wiring plan. Produces a site_df for
# build_site_table() from an event-level detections table joined against a
# separately-maintained site-metadata table, generalizing the ecosystem's existing
# blank-identification lookup-table pattern to carry site coordinates. Data-type-agnostic
# (DNA/BLAST and acoustic both reduce to the same join); wired live into
# TaxaID_Workflow_Template_TEST.R's Section 2.5 using the bundled Reads_Table's real
# sample_1/sample_2/control_1 columns as genuinely different sites -- surfaced and fixed a
# real bug in Section 3's multi-member-vs-singleton branching along the way (see Session
# 137 note below). Acoustic half deferred -- no real multi-site BirdNET deployment data
# exists yet to wire against honestly. Session 137 — score_image_workflow.R: Phase 3 of the
# observation-pipeline-wiring plan. New OVERRIDE_SITE_LATLNG flag makes the previously-
# unconditional SITE_LAT/SITE_LNG override explicit (default TRUE, matching this bundled
# photo set's real EXIF-less trail-camera files); FALSE lets score_image_inat() read each
# photo's own real EXIF coordinates. New build_site_table() call checkpoints
# image_site_table. Live-verified both flag settings against the real bundled 52-photo
# set (82%/60% top-1 accuracy respectively, matching prior documented results -- no
# regression). See Session 137 note below. Session 135 — blast_sequences(resolve_location=) added to
# extract GenBank lat_lon/country qualifiers for BLAST hit accessions; closes the
# BLAST-hit-side half of the location-metadata gap flagged in ecosystem_docs/
# TODO_validation_benchmark.md's "Sourcing location data" section. See Session 135 note
# below. Session 134b — group_observations_by_bbox() moved here from
# TaxaFetch and substantially reworked (default-to-observation_id behavior, last-drawn-wins
# overlap rule, end-of-loop review/edit/delete step); new assign_spatial_group() manual
# helper; build_site_table() now populates spatial_group_id/spatial_group_N defaults on
# every row. sf added to Imports. See Session 134b note below. Session 134 — build_site_table()
# added: unified long-format site table across image/DNA/acoustic pathways, see Session 134
# note below. Session 132 — non-portable filenames from Session 129's camera-trap expansion
# fixed, see Session 132 note below.)

---

## Package Purpose
Stores and standardizes raw match data produced by external biological classification
programs (DNA barcoding pipelines, image classifiers, acoustic recognizers). Produces
a canonical match object for input to TaxaLikely.

Now also provides a complete FASTQ-to-match pipeline: ingest DADA2 sequence tables or
FASTA files, filter by length/abundance, BLAST against NCBI (remote or local), and
standardize results.

**Revised 2026-08-07** (implements `ecosystem_docs/REENTRY_PROMPT_blast_based_reference_
quality.md`): TaxaMatch now also screens match data against reference-accession quality
*in service of producing a clean match object* -- `evaluate_reference_accessions()`
BLASTs each accession's own sequence against a broad, unrestricted database and computes
a per-accession taxonomic-hierarchy congruence verdict; `remove_incongruent_references()`
is the early, narrow hard filter consuming it (mirrors `TaxaLikely::
remove_flagged_references()`'s existing pattern). This does NOT make TaxaMatch a
wholesale reference-database-auditing package -- `TaxaLikely::audit_reference_database()`/
`classify_reference_accessions()`/`repair_thin_evidence()` (the broader, taxon-list-scoped
reference-QC toolkit, archived at `TaxaLikely/archive_decipher_reference_audit/`) remain
TaxaLikely's domain for anything beyond this narrow, match-object-cleaning use. Package
placement was settled explicitly with the user: this function's primary real use edits/
filters the match object, which must happen *before* TaxaExpect ever builds a taxon list
to generate priors for -- strictly upstream of any TaxaLikely call -- so it has to live
here, in the package that already owns match-object standardization, not downstream in
TaxaLikely (which TaxaMatch must never depend on). See TaxaMatch's own top session note
for the full record, including what's still open (graded per-accession weighting surviving
through to `TaxaLikely::evaluate_likelihoods()` -- real, agreed-on future work, not
designed or implemented yet).

TaxaMatch does NOT perform score-to-likelihood conversion or general-purpose reference
quality auditing (taxon-list-scoped mislabel/completeness checks) -- those functions live
in TaxaLikely.

**Status: All functions written and passing `devtools::check()` (0 errors, 0 warnings, 0 notes).**

---

## Dependency Chain

TaxaTools → TaxaFetch → TaxaHabitat → TaxaExpect → TaxaAssign
TaxaMatch → TaxaLikely → TaxaAssign

TaxaMatch depends on TaxaTools for `rename_cols()`, `create_taxon_names()`, (Session
134b) `define_search_polygon()` (called by `group_observations_by_bbox()`), and
`TaxaTools::standard_ranks` (the canonical kingdom->species rank ladder, used by
`.attach_taxonomy()` and, since 2026-08-07 continued, `evaluate_reference_accessions()`
-- see that function's own CLAUDE.md note below; an earlier same-day version called
`TaxaTools::fill_higher_ranks()` for query-side taxonomy, superseded the same day by
`.resolve_taxonomy_by_acc()`, already internal to this package).
Also depends on `httr2` (remote BLAST API), `rentrez` + `xml2` (taxonomy resolution), and
(Session 134b) `sf` (point-in-polygon spatial-group assignment).
`Biostrings` and `rBLAST` are in Suggests (FASTA reading and local BLAST, respectively).

---

## Match Data Sources

| Source type | Example program | Score column | Sample ID column | Reference list |
|---|---|---|---|---|
| DNA barcoding | DADA2 + BLAST | `PercMatch` (0-100) | `ESVId` | NCBI nucleotide |
| Image classifier | Animl (MegaDetector + SpeciesNet) | `confidence` (0-1) | image_id / crop_id | SpeciesNet species list (~1,295 spp) |
| Acoustic recognizer | BirdNET | `confidence` (0-1) | recording_id × detection | BirdNET species list (~6,000+ spp) |

Raw column names vary by source — `standardize_match_data()` handles the rename.

### Image classifier details (Animl — Complete)

- **R package:** `animl` on CRAN (wraps Python backend; requires Python >= 3.12)
- **Pipeline:** `detect()` (MegaDetector bounding boxes) → `classify()` (species prediction) → `sequence_classification()` (temporal refinement)
- **Output:** CSV with species, confidence, bounding boxes; multi-level taxonomy fallback (species → genus → family when confidence is low)
- **Export formats:** CSV, COCO JSON, Timelapse CSV, folder organization
- **Score interpretation:** CNN confidence (0-1); NOT comparable to BLAST % identity — requires separate likelihood model calibration in TaxaLikely
- **Ingest function:** `read_animl_output()` — implemented in `R/read_image_classifiers.R` (Session 93)
- **Reference:** https://docs.animl.camera/

### Acoustic recognizer details (BirdNET — Complete)

- **Tool:** BirdNET (Cornell Lab of Ornithology); CNN-based acoustic classifier
- **Output:** CSV with start_time, end_time, scientific_name, common_name, confidence (0-1); top-N candidates per detection
- **Score interpretation:** CNN confidence (0-1); same calibration caveat as image classifiers
- **Species coverage:** ~6,000+ bird species; species list is queryable (reference DB equivalent for completeness audits)
- **R interfaces:** BirdNET-R, warbleR (acoustic analysis), or direct Python CLI
- **Ingest function:** `read_birdnet_output()` — implemented in `R/read_birdnet_output.R` (Session 93)
- **Reference:** https://birdnet.cornell.edu/

### Design notes for non-sequence data types

1. **Ingest functions** (`read_animl_output()`, `read_birdnet_output()`) are thin — read CSV, apply `col_map`, pass to `standardize_match_data()`. No model fitting or classification happens in TaxaMatch.
2. **Score calibration** is fundamentally different from DNA: CNN confidence is not % identity. TaxaLikely's `train_likelihood_model()` handles this — it is score-agnostic and works on any 0-1 normalised score. But the training reference for image/acoustic data is the model's own species list, not NCBI sequences.
3. **Completeness audits** query the model's known species list (not NCBI). A new `audit_model_coverage()` function in TaxaLikely (or adapted `audit_reference_coverage()`) would compare expected species against the model's taxon list.
4. **Multi-level taxonomy fallback** (Animl reports genus when unsure of species) maps directly to `taxon_name_rank` — no architecture change needed.
5. **Priority:** Secondary to sequence pipeline. Placeholder stubs now; real implementation when test data (BirdNET CSV, Animl export) are available.

---

## Canonical Match Object (output of `standardize_match_data()`)

One row per `observation_id` × reference accession match.

| Column | Renamed from | Required | Notes |
|---|---|---|---|
| `observation_id` | `ESVId` (DNA) | Yes | Unique query identifier |
| `score_original` | `PercMatch` (DNA) | Yes | Raw match score — preserved unchanged; downstream packages add `score_norm`, `score_softmax`, `score_likelihood` |
| `taxon_name` | derived | Yes | Best taxon from `create_taxon_names()` |
| `taxon_name_rank` | derived | Yes | Rank of `taxon_name` |
| taxonomy cols | `Kingdom`…`Species` | Yes | Kept as-is from source |
| `TestId` | keep | No | Marker/barcode type; not renamed, not modelled |
| `Accession` | keep | No | Reference accession; not renamed, not modelled |

**Sample context** (site, date, replicate) is stored in a separate table and joined to
likelihood output downstream — it is NOT part of the match object.

---

## Function Inventory

### Sequence input and filtering

| Function | File | Status | Description |
|---|---|---|---|
| `read_sequence_table()` | R/sequence_input.R | Written | Ingest DADA2 seqtab matrix, FASTA file, or DNAStringSet; optional taxonomy join |
| `filter_sequences()` | R/sequence_input.R | Written | Filter ASVs by length range and minimum abundance; `barcode_term` auto-detection |

### BLAST search

| Function | File | Status | Description |
|---|---|---|---|
| `blast_sequences()` | R/blast_sequences.R | Written, field-tested | Remote NCBI BLAST (httr2) or local rBLAST; score window filtering; taxonomy resolution. **Session 135**: `resolve_location = FALSE` param — when `TRUE`, fetches each unique hit accession's full GBSeq XML record (`.resolve_locations_by_acc()`) and appends `lat`/`lon`/`country` parsed from the `source` feature's `lat_lon`/`country` qualifiers (`.parse_lat_lon()`); independent of `resolve_taxonomy` (taxonomy comes from the NCBI taxonomy DB, location from the full nucleotide record — neither fetch gives you the other). **Session 151**: `score_range` default widened `2` → `8` — a leave-one-out check against 3 real 12S reference datasets found the old 2-pt window silently dropped the true species in 4/7 real congener-outscoring events; see roxygen's "Score window validation" section and `diagnostics/score_window_leave_one_out.R`. **2026-08-03**: real bug fixed -- the subject-length filter checked `slen` (whole GenBank record length) instead of `length` (aligned region length), discarding real congener matches deposited as long mitogenomes. New `megablast` param (explicit, default `FALSE`, matches prior implicit behavior). New `max_hits_per_taxon` param (requires `resolve_taxonomy = TRUE` on remote results, since remote BLAST XML never populates real per-hit taxids; new internal `.attach_taxonomy()` + `.filter_blast_hits(stage=, taxon_group_col=)` restructuring makes this work off a real resolved species/genus key instead). **2026-08-14**: gains `max_consecutive_batch_failures` (default `3L`) -- a circuit breaker in `.blast_remote()`'s batch loop, distinct from `poll_max_wait` (which bounds ONE batch's own timeout): stops submitting further batches once a weighted count of consecutive failures is reached (a `.blast_server_rejected()` CPU-budget rejection counts double, a plain timeout/submission failure counts once), skips the halved-batch-size retry pass entirely once tripped, and marks every never-attempted batch's queries as failed too (via `failed_query_ids`) so nothing is silently miscoded as a real zero-hit result. New `attr(result, "circuit_breaker_tripped")`. `Inf` disables it. New internal `.blast_rate_limit_sleep()` wraps the existing `Sys.sleep(11)` calls solely so tests can mock it to a no-op. |

### Image and acoustic input

| Function | File | Status | Description |
|---|---|---|---|
| `score_image_inat()` | R/score_image_inat.R | Complete | Submit image(s) directly to iNaturalist CV API; returns canonical match object. Accepts single file, file vector, or directory. Per-image EXIF lat/lng/date extraction (requires `exifr` Suggests). User-supplied `lat`/`lng`/`observed_on` override EXIF and apply to all images. Outputs `observation_id`, `taxon_name`, `taxon_name_rank`, `score_original` (= `combined_score`), `genus`, `common_name`, `iconic_taxon_name`, `taxon_id`, `n_observations`, `vision_score`, `combined_score`, `freq_score`, `geo_prior_weight` (= combined/vision), `lat`, `lng`, `observed_on`, `folder_1`/`folder_2`/... (nested path metadata). Requires `httr` (Imports), `tibble`, `dplyr`. `exifr` in Suggests. Run `convert_taxonomy_backbone()` + `fill_higher_ranks()` before `join_priors()`. |
| `read_animl_output()` | R/read_image_classifiers.R | Complete | Ingest Animl CSV export (MegaDetector + SpeciesNet); map confidence + taxonomy to match object. Accepts long format (default) or wide format via `n_candidates`. Configurable column names via `file_col`, `species_col`, `score_col`. `observation_id` = image filename stem. `min_confidence` and `top_n` filters. |
| `read_inaturalist_cv_output()` | R/read_image_classifiers.R | Complete | Ingest saved iNaturalist CV API JSON response files (one JSON per image). `score_type` = `"combined_score"` (default) or `"score"`. Returns `observation_id`, `score`, `species`, `genus`, `common_name`, `taxon_rank`, `source_file`. `min_confidence`, `top_n` filters. Requires `jsonlite`. |
| ~~`read_wildlife_insights_output()`~~ | R/read_image_classifiers.R | **Removed, 2026-07-23** | Targeted a dict-keyed-by-filename JSON shape that matched neither the real Wildlife Insights platform (CSV bulk downloads, not JSON) nor the real SpeciesNet CLI (`predictions` is a list, not a dict) -- see this file's 2026-07-23 note. Zero real callers anywhere in the monorepo (grep-confirmed). Removed outright (not deprecated, per this ecosystem's established zero-caller-removal bar); superseded by `read_speciesnet_output()` below. Dependents repointed the same session: `TaxaWizard/inst/graph/workflow_graph.json` (2 edges), `.../snippets/image_to_match.R`, `.../snippets/image_refs_to_matrix.R`, `.../prompts/phase_classify.md`, `.../metadata/TaxaMatch.json`, `.../metadata/TaxaLikely.json`, both READMEs. |
| `read_speciesnet_output()` | R/read_image_classifiers.R | Complete, 2026-07-23 | Ingest real SpeciesNet CLI (`google/cameratrapai`) `predictions_json` output. Verified directly against the shipped taxonomy file (`data/model_package/taxonomy_release.txt`): labels are `uuid;class;order;family;genus;species;common_name`, 7 semicolon-delimited fields, any of the 5 taxonomic fields may be empty (SpeciesNet's own conservative taxonomic rollup). Treats the raw top-5 `classifications` block (pre-rollup, pre-geofencing) as the primary multi-candidate source, not the already-rolled-up `prediction` field -- see roxygen `@details` for the rationale (informed by Markoff & Galaktionovs 2025, arXiv:2510.14594). Returns `observation_id`, `score`, `species`, `genus`, `family`, `order`, `class`, `common_name`, `taxon_rank`, `ensemble_prediction`/`ensemble_prediction_score`/`ensemble_prediction_source` (per-image ensemble metadata, repeated across candidate rows), `lat`/`lon`/`country`, `source_file`. `min_confidence`, `top_n` filters. Optional `include_coverage`/`min_detection_conf` add `coverage`/`detection_conf` from MegaDetector `detections` bboxes (mirrors `read_animl_output()`'s `bbox_cols` convention). Requires `jsonlite`. 52 new tests, all against real label strings pulled from the shipped taxonomy file (not synthetic guesses). |
| `read_birdnet_output()` | R/read_birdnet_output.R | Complete | Ingest BirdNET-Analyzer CSV (detections × species × confidence); map to match object. Accepts file vector or directory path. `observation_id = "{file_stem}_{start_s}-{end_s}"`. `min_confidence` and `top_n` filters. |

### Site table and spatial grouping (Sessions 134, 134b)

| Function | File | Status | Description |
|---|---|---|---|
| `build_site_table()` | R/build_site_table.R | Complete | Unifies per-observation site info (`observation_id`, `lat`, `lon`, `observed_on`) across all three match-object pathways into one long-format table. Image pathway (`score_image_inat()` output): extracted directly from embedded `lat`/`lng`/`observed_on`. DNA/BLAST and acoustic pathways: neither carries site info in the match object itself, so `site_df` must be supplied externally; may have more than one row per `observation_id` -- this is the correct shape for a sequence ASV genuinely detected at several real sample sites in one sequencing run (see Session 134 note). **Session 134b:** also populates `spatial_group_id`/`spatial_group_N` on every row from the moment the table is built. **Session 139 (default changed):** `spatial_group_id` now defaults to `"spatial_group_<n>"`, grouping rows by **exact** `(lat, lon)` match -- not the row's own `observation_id` (spatial_group_id is a location property; two different observations sharing an exact site coordinate, e.g. both joined from the same site-metadata row, now correctly default to the same group, and one observation's own several genuinely different sites now correctly default to *different* groups). A grid-snapping design (round to a fixed bin size) was tried first and rejected -- see the function's own `@details` for why exact match is both simpler and semantically correct here, and no bin size is well-posed in general. New `is_default_group` column (always `TRUE` here) replaces the old `spatial_group_id == observation_id` heuristic `group_observations_by_bbox()`/`assign_spatial_group()` used to infer "still default" -- both now just check this boolean directly. `default_grid_size` parameter from an earlier same-session iteration was removed entirely (superseded by exact match, never shipped in a release). |
| `group_observations_by_bbox()` | R/group_observations_by_bbox.R | Complete | **Session 134b, moved here from TaxaFetch and reworked** (see that session's note below for the full design rationale). Interactive: loops `TaxaTools::define_search_polygon()` (re-centred each time on still-default observations, guaranteed to fully enclose them) to collect one or more group polygons, then an end-of-loop review step (list drawn groups by member count; re-open one by number to reshape via `init_polygon`; `"delete <n>"` to remove one, releasing its members back to default; Enter to finalize). Updates `spatial_group_id`/`spatial_group_N` **in place** on a `build_site_table()`-shaped input -- only touches observations still at their default single-observation state; anything already grouped (prior call, or `assign_spatial_group()`) is left untouched regardless of geometry. Overlap rule: **last-drawn-wins** with a `warning()` naming every ambiguous `observation_id`. Internal helpers `.bbox_center_radius()`, `.assign_spatial_groups_from_polygons()`, and `.review_drawn_groups()`'s non-interactive/zero-polygon paths are pure and unit-tested without a live gadget session. **Session 139:** checks `is_default_group` directly instead of re-deriving "still default" from `spatial_group_id`'s contents (needed once `build_site_table()`'s default label stopped being `observation_id`-shaped); newly drawn groups' `"spatial_group_<n>"` numbering now starts past whatever numbers `build_site_table()`'s own exact-match default already used (`.next_spatial_group_number()`), so the two numbering sources can never collide; also sets `is_default_group = FALSE` for captured/reshaped rows. Gadget calls now pass context-specific `title`/`done_label`/`cancel_label` ("Group These Points"/"No More Groups", with per-iteration progress in the title) instead of relying on `define_search_polygon()`'s generic defaults -- see `TaxaTools::define_search_polygon()`'s own Session 139 note. |
| `assign_spatial_group()` | R/assign_spatial_group.R | Complete | **Session 134b.** Manual `spatial_group_id` setter for a named set of observations -- for a study where grouping is already known from metadata, or to hand-correct a few observations after `group_observations_by_bbox()`. Validates every named `observation_id` exists; **collision guard**: stops if the target `spatial_group_id` is already used by an observation *not* named in the call (would otherwise silently expand an unrelated group's membership) -- include that observation explicitly to merge groups instead. Recomputes `spatial_group_N` in sync. **Session 139:** also clears `is_default_group` (sets `FALSE`) for the named observations when that column is present; no-ops harmlessly on older-shaped input without it. |
| `join_event_site_metadata()` | R/join_event_site_metadata.R | Complete | **Session 137 (Phase 4).** Produces a `site_df` for `build_site_table()` from any event-level detections table (one row per `id_col` x `event_col` pair actually observed) joined against a separately-maintained site-metadata table (`event_col` + `lat`/`lon`/`observed_on`) -- the same "sample column -> attribute lookup table" pattern already used ecosystem-wide to identify blanks (`BLANKS_MARCH`/`BLANKS_AUG` in `PtConceptionWorkflow_12S.R`, `control_samples` in `TaxaFlag::flag_contaminant()`), generalized to carry site coordinates instead of (or alongside) blank status. Data-type-agnostic: DNA/BLAST (Reads-table sample columns, already pivoted to long format and filtered to real detections) and acoustic (recording/device identifiers) both reduce to the same join, so one function serves both rather than duplicating it per pathway. `control_samples` param excludes blanks before joining (blanks are not real site detections). Warns (does not error) on events with no matching site-metadata row -- those rows get `NA` `lat`/`lon` rather than being silently dropped. |

### Reference-accession quality (new, 2026-08-07)

| Function | File | Status | Description |
|---|---|---|---|
| `investigate_flagged_accession()` | R/investigate_flagged_accession.R | Written, tested (offline), 2026-08-08 | Deep-dive verification for ONE `evaluate_reference_accessions()`-flagged accession: self-consistency (vs. other real accessions of its own listed species) and cross-taxon consistency (vs. other real accessions of its top independent disagreeing BLAST hit's species), both independence-filtered the same way `evaluate_reference_accessions()` is. **2026-08-08**: both comparisons now run via `.blast_against_comparison_set()` (internal, reuses `blast_sequences()` itself) instead of a hand-rolled `pwalign::pairwiseAlignment()` loop -- see this file's top session note (Option A of `ecosystem_docs/REENTRY_PROMPT_investigate_flagged_accession_prefilter_group_posthoc.md`). Gains a persistent, accession-keyed cache (`cache_dir`, asymmetric TTL: `"inconclusive_length_mismatch"` verdicts expire after `inconclusive_ttl_days`, default 30; any other verdict cached indefinitely). |
| `investigate_flagged_accessions()` | R/investigate_flagged_accession.R | Written, tested (offline), new 2026-08-08 | Batch wrapper -- shares one in-memory NCBI-species-search cache across a whole flagged-accession list (a `listed_species`/`disagreeing_taxon` repeated across several accessions is only fetched from NCBI once per batch) and shares `investigate_flagged_accession()`'s own persistent cache. Does NOT do cross-accession pattern detection (see this file's top session note for why that's deliberately separate, not-yet-designed future work). |
| `check_marker_mismatch()` | R/check_marker_mismatch.R | Written, tested (offline), new 2026-08-08 | Cheap pre-filter (Question 2, item 4 of the reentry prompt above): a single GBSeq XML fetch checks a flagged accession's own annotated `/gene`/`/product` feature-table qualifier against the marker an evaluation was scoped to (e.g. does a "12S"-scoped audit's flagged record actually say `/product="16S ribosomal RNA"`?) -- no BLAST, no alignment, meant to route a flagged accession to a much simpler resolution path (correct the marker label) before ever reaching `investigate_flagged_accession()`'s deep dive. Directly grounded in a real confirmed case (`AY850362`, a genuine 16S-vs-12S marker mislabel) -- see this file's top session note for why the earlier "coarse rank of disagreement signals marker mislabel" hypothesis was tested and refuted first. |
| `evaluate_reference_accessions()` | R/evaluate_reference_accessions.R | Written, tested (offline) | Implements `ecosystem_docs/REENTRY_PROMPT_blast_based_reference_quality.md`. For each accession, BLASTs its own sequence against a broad, unrestricted database (`method`/`database`/`score_range`/`min_score`/`max_hits` passed through to `blast_sequences()`), applies the same-submission-batch independence filter, and computes a Jeffreys-smoothed `hierarchy_flag` (`"congruent"`/`"incongruent"`/`"insufficient_independent_evidence"`) -- the same congruence math `TaxaLikely::audit_reference_database()`/`classify_reference_accessions()` used to compute from a narrow, taxon-list-scoped DECIPHER alignment, now fed from real, broad BLAST hits instead. `finest_common_rank` walks the FULL `kingdom`->`species` ladder (2026-08-07), not just `family`/`genus`/`species`. **2026-08-07, continued**: gains 5 identity/coverage-anywhere diagnostic columns (`best_hit_pident`/`best_agreeing_pident`/`best_disagreeing_pident`/`congruent_evidence_exists_anywhere`/`congruent_evidence_best_pident`) -- see this file's own top session note and `evaluate_reference_accessions()`'s own `@section Identity diagnostics` for why: `hierarchy_flag` alone cannot distinguish a genuine mislabel from "correct label, thin coverage/poor marker resolving power at this rank," and these columns give a reviewer the real percent-identity numbers to judge that with. **2026-08-13**: internal `.compute_hierarchy_congruence()` gains `require_species_resolved_partner = TRUE` -- excludes a comparison partner whose own listed species isn't resolved to species level from the vote entirely (real motivating case: `Stereolepis doederleini`'s one real independent hit was `NC_028197`, a family-name-plus-specimen-code reference, not a real binomial). See this file's own top session note and `evaluate_reference_accessions()`'s `@section Species-resolved comparison partners`. **2026-08-13, continued**: gains `best_disagreeing_taxon` -- the listed species of the same highest-identity independent hit `best_disagreeing_pident` is already computed from (same row, so the two stay consistent by construction); needed by `review_flagged_accessions()` (below) so an LLM second-look reviewer can recognize a known hybrid-cross partner or informal specimen code by name, not just by percent identity. `NA` when nothing disagrees. Persistent, accession-keyed cross-run cache (`cache_dir`, default `tools::R_user_dir("TaxaMatch", "cache")`), asymmetric TTL (`insufficient_evidence_ttl_days`, default 180 -- only `"insufficient_independent_evidence"` expires; `"congruent"`/`"incongruent"` cached indefinitely). See this file's own top session note for the full design record and the real bugs found/fixed before shipping. **Full output-column interpretation guide**: `inst/reference_accession_evaluation_guide.md` (new 2026-08-13) -- written for both a human reviewer and `review_flagged_accessions()` (below). **2026-08-14**: gains `chunk_size` (default `200L`) and `max_consecutive_batch_failures` (default `3L`, forwarded to `blast_sequences()`) -- `needs_eval` is now processed `chunk_size` accessions at a time, with the persistent cache written after EACH chunk (not once at the very end), so an interruption only loses whatever chunk was still in flight. When a chunk's own `blast_sequences()` call reports `circuit_breaker_tripped`, the remaining chunks are never attempted this call (their accessions fold into `missing_acc`, same treatment as any other not-yet-evaluated accession). New `attr(result, "run_summary")` and an actionable `message()` on a circuit-breaker trip -- see this file's own top session note. |
| `flag_incongruent_references()` | R/evaluate_reference_accessions.R | Written, tested (offline), 2026-08-07 continued | **The RECOMMENDED default consumer.** Left-joins `evaluate_reference_accessions()`'s full output (hierarchy_flag + all diagnostics) onto a match object by accession (version-suffix-stripped), never removes a row. Added after a real live case (`Abylopsis eschscholtzii`) showed why an unreviewed hard drop is the wrong default -- see this file's own top session note. |
| `remove_incongruent_references()` | R/evaluate_reference_accessions.R | Written, tested (offline) | The harder, deliberate opt-in -- mirrors `TaxaLikely::remove_flagged_references()`'s exact pattern. Drops only rows whose accession was flagged `"incongruent"` by `evaluate_reference_accessions()` (version-suffix-stripped match); `"insufficient_independent_evidence"` is retained by default (`remove_insufficient_evidence = FALSE`). **No longer the recommended default pipeline step as of 2026-08-07 continued** -- its own roxygen now says to reach for `flag_incongruent_references()` first and only use this deliberately, after reviewing the identity diagnostics. Deliberately consumes only the binary blacklist decision, not the full quality signal -- see this file's top session note for the TaxaLikely-side graded-weighting work this does NOT yet do. |
| `verify_flagged_references()` | R/evaluate_reference_accessions.R | Written, tested (offline), new 2026-08-18 | Bridges `TaxaLikely::flag_reference_errors()`'s free/offline (but known over-flagging) mislabel screen to this function -- **without** BLASTing an entire training reference database. Takes `flag_reference_errors()`'s output (or a plain accession vector), screens only the `"likely_mislabeled"` subset (`error_types` param) via `evaluate_reference_accessions()`, and returns `verified_clean` (accessions NOT confirmed `"incongruent"` -- pass straight to `TaxaLikely::flag_reference_errors(verified_clean=)`/`train_likelihood_model(verified_clean=)`). Built after discovering `train_likelihood_model()` calls `flag_reference_errors()` unconditionally on every training run and silently drops flagged accessions -- a real pilot on GreatLakes 12S data found 0 of 40 randomly-sampled `"likely_mislabeled"` accessions confirmed as genuine mislabels (85% false positives). Screening only the flagged subset (not the whole ~2,650-accession reference set, which is LARGER than a typical match-candidate screening population on real data) keeps NCBI cost bounded -- see `TaxaID/CLAUDE.md`'s top session note for the full cost analysis and pilot numbers. |
| `review_flagged_accessions()` | R/review_flagged_accessions.R | Written, tested (offline), new 2026-08-13 | Implements Question 2 of `ecosystem_docs/REENTRY_PROMPT_flagged_accession_second_look.md` -- an LLM second-look reviewer for `evaluate_reference_accessions()`'s flagged/borderline rows, mirroring `TaxaFlag::review_assignments()`'s architecture (batching + retry-by-halving-on-truncation + JSON parsing) without a cross-package dependency on TaxaFlag. Default scope: `hierarchy_flag %in% c("incongruent", "insufficient_independent_evidence")` (`hierarchy_flags` param) plus `listed_taxon_is_species == FALSE` (`include_non_species_resolved`, default `TRUE`, orthogonal axis). Prompt content is lifted directly from `inst/reference_accession_evaluation_guide.md`'s own 5-category decision framework and worked examples. Output: `accession_likely_explanation` (`"genuine_mislabel"`/`"poor_marker_resolution"`/`"sister_family_thin_coverage"`/`"hybrid_or_specimen_code_artifact"`/`"uncertain"`), `accession_review_confidence` (`"high"`/`"moderate"`/`"low"`), `accession_review_comment` (free text) -- never a re-decided `hierarchy_flag`. See this file's own top session note for the full design-question-by-design-question record. **2026-08-14, continued**: gains `cache_dir` (default `tools::R_user_dir("TaxaMatch", "cache")`, same convention as `evaluate_reference_accessions()`) -- a persistent cache keyed on accession + a content fingerprint of the review-relevant input columns (`.accession_review_fingerprint()`), not a TTL, so a re-evaluated accession whose `hierarchy_flag`/diagnostics genuinely changed gets a fresh review automatically while an unchanged one is served from cache indefinitely. New `accession_review_cache_hit` output column. Written incrementally, once per LLM batch. A failed/NA review is never cached (retried next call, not treated as a permanent verdict). See this file's own top session note. |

### Standardization (original)

| Function | File | Status | Description |
|---|---|---|---|
| `standardize_match_data()` | R/standardize_match_data.R | Written | Rename columns, derive `taxon_name`, validate structure |
| `filter_redundant_hypotheses()` | R/standardize_match_data.R | Written | Drop higher-rank rows superseded by finer-rank rows within the same lineage and sample |
| `add_lowest_consistent_rank()` | R/taxonomy_consistency.R | Written | Per-observation: find finest rank with a single unambiguous value across all candidate rows. `majority_threshold` param (numeric in (0,1]) switches to majority mode — consistent when top value reaches threshold. Majority mode adds `rank_majority_value`, `rank_majority_fraction`, `is_rank_outlier` columns. `na_as_inconsistent` controls NA handling. Auto-detects `rank_system` from `TaxaTools::extended_ranks`. |
| `convert_taxonomy_backbone()` | R/convert_taxonomy_backbone.R | Written | Remap rank columns (order/family/genus/species) from source backbone to target backbone (e.g. NCBI→GBIF). Vectorized: `match()`-based index into verified table — ~100× faster than row-by-row loop for large data frames. Per-column fallback: ranks the target omits are kept unchanged. Adds `taxonomy_backbone` and `taxonomy_collision` diagnostic columns; sets `backbone_cols` R attribute. **2026-07-24:** the not-found fallback value is now also cleaned via `TaxaTools::clean_taxon_names()` (previously only the target-backbone-matched path was) — fixes a real case where an exotic compound hybrid-formula name from a raw NCBI accession label passed through completely uncleaned when GBIF had no match for it. Does not change which rows count as "found." **2026-07-25:** `taxon_name_rank` is now corrected (not just `taxon_name`) when a row's own claimed rank has no matching target value and falls back to a coarser resolved name — uses `verify_taxon_names()`'s new `matched_rank` column when present, silently skipped otherwise (backward compatible). Closes the "Inu Inu" fabricated-pseudo-binomial bug. **2026-07-25, later same day:** rank columns FINER than the corrected rank are now also cleared to `NA` on the same rows (e.g. `species` when demoted to genus) — closes a real regression found by testing against production (`Mugu_Match_from_BLAST.R`'s own second `create_taxon_names()` call was silently reverting the rank fix by reading the still-populated, now-stale `species` column). **2026-08-21:** a SECOND, independent rank-correction mechanism added, covering any row whose final `taxon_name` value was produced by `TaxaTools::clean_taxon_names()` collapsing a real second token to genus-only -- regardless of source (a not-found row's fallback cleaning; a found row's `matched_name_clean` fallback; or, discovered when the first version of this fix was verified against a real re-run and still found stale rows, a found row whose OWN claimed rank genuinely matches the backbone's answer but whose rank VALUE itself is an informal placeholder name, e.g. a real NCBI taxonomy node literally named `"Ictalurus sp. UM 105-1789"`, ranked "species" by NCBI itself -- no rank-mismatch-based correction can ever see this case). Uses `collapsed_to_genus` (the same-day `TaxaTools::clean_taxon_names()` companion fix) tracked through the pipeline, not a shape-based re-derivation (rejected -- would misfire on real hyphenated genera like *Pseudo-nitzschia*). See this file's top session notes for the full two-round "Ictalurus" bug this closes. NOTE: generic utility — move to TaxaTools after manuscript review. |

### Internal helpers

| Function | File | Description |
|---|---|---|
| `.resolve_taxonomy()` | R/blast_sequences.R | NCBI taxid to full lineage (kingdom-species) via rentrez + xml2 |
| `.resolve_locations_by_acc()` | R/blast_sequences.R | **Session 135.** Accession → `lat`/`lon`/`country` via full GBSeq XML record (`db="nucleotide", rettype="gb", retmode="xml"`) — the record type `.resolve_taxonomy()`/`.resolve_taxonomy_by_acc()` never touch. Accessions passed directly as `id`, no search/summary round trip. |
| `.parse_lat_lon()` | R/blast_sequences.R | **Session 135.** Parses INSDC `lat_lon` qualifier strings (`"36.789 N 121.947 W"`) into signed decimal `c(lat=, lon=)`. Deliberately duplicated from TaxaLikely's identical helper (`R/fetch.R`) rather than shared — matches this ecosystem's existing pre-manuscript stance on small NCBI-fetcher overlap (see `project_blast_ncbi_fetcher_todo` memory / TaxaLikely's Session 115 note). |
| `.parse_taxonomy_xml()` | R/blast_sequences.R | Parse NCBI taxonomy XML response |
| `.blast_remote()` | R/blast_sequences.R | Remote NCBI BLAST URL API with batching, rate limiting, RID polling |
| `.blast_local()` | R/blast_sequences.R | Local BLAST via rBLAST wrapper |
| `.filter_blast_hits()` | R/blast_sequences.R | Score window algorithm: min_score + query coverage + subject length + score_range + max_hits |
| `.parse_blast_xml()` | R/blast_sequences.R | Parse BLAST XML output into standardized hit data frame |
| `.resolve_taxonomy_from_accessions()` | R/blast_sequences.R | Accession-to-taxonomy bridge when taxids unavailable (XML format) |
| *(removed — Session 57)* | R/sequence_input.R, R/blast_sequences.R | `.barcode_length_defaults` and `.resolve_barcode_lengths_local()` moved to TaxaTools; now `TaxaTools::resolve_barcode_lengths()` |
| `.parse_semicolon_headers()` | R/sequence_input.R | Parse FASTA headers: accession;kingdom;...;species |
| `.check_pkg()`, `.extract_genus()`, `.stop_missing_files()`, `.validate_min_conf_top_n()`, `.apply_top_n()`, `.warn_na_coercion()`, `.warn_duplicate_basenames()`, `.fmt_time()` | R/utils_shared.R | **2026-07-20, new file.** Shared internal helpers consolidating patterns duplicated across the `read_*()`/`blast_sequences()`/`score_image_inat()` ingest functions (package-review response, see top-of-file session note). |

---

## Workflow Scripts

| File | Purpose |
|---|---|
| `inst/workflow_standardize.R` | Original: load match data, standardize, filter redundant |
| `inst/workflow_fastq_to_match.R` | FASTQ-to-match pipeline: DADA2 output, filter, BLAST, standardize |
| `inst/workflows/score_image_workflow.R` | Layer-1 (Session 124): live `score_image_inat()` call on bundled real camera-trap photos (`inst/extdata/example_images/camera_trap_photos/`) → `fill_higher_ranks()` → checkpoint for TaxaLikely. **Expanded Session 129**: 6 photos/5 species → 52 photos/8 species, organized into per-species subfolders (`recursive = TRUE`; `folder_1` drives ground truth via `FOLDER_TO_SPECIES`, since filenames are camera-generated sequence numbers, not species names). Added a `TARGET_ICONIC_TAXA = "Mammalia"` post-scoring filter — iNaturalist returns off-scope candidates (two plants, one bird, confirmed on this exact photo set) that a mammal-only study can never actually assign to; filtering before `unreferenced_candidates()`/`assign_scores()` lets real candidates absorb that probability mass instead. `top_n` raised 5→8 as a safety margin. **Session 137 (Phase 3 of the observation-pipeline-wiring plan):** new `OVERRIDE_SITE_LATLNG` CONFIG flag (default `TRUE`, matching this bundled photo set's own real requirement — its trail-camera files carry no EXIF GPS at all) makes the previously-unconditional `SITE_LAT`/`SITE_LNG` override explicit; `FALSE` passes `lat = NULL, lng = NULL` so `score_image_inat()` reads each photo's own real EXIF coordinates instead of stomping on them with one global site. New Step 2.5 calls `TaxaMatch::build_site_table()` (no `site_df` needed — the image pathway's output already carries embedded lat/lng either way) and checkpoints the result as `image_site_table`; not consumed further in this script (still stops at TaxaLikely, per its own scope) but ready for a future TaxaAssign continuation. |
| `inst/workflows/score_acoustic_workflow.R` | Layer-1 (Session 124): `read_birdnet_output()` on real BirdNET-Analyzer CSVs (produced by `sources/birdnet_csv_export.py`, a companion Python script outside this package) → `create_taxon_names()` + `fill_higher_ranks()` → checkpoint for TaxaLikely |
| `inst/workflows/blast_sequences_workflow.R` | Layer-1 (Session 126): live remote `blast_sequences()` call on 5 real PtConception 12S MiFish sequences (same accessions as Session 115's field test, fetched live by accession from NCBI) → `standardize_match_data()` (with `coverage_col = "query_coverage"`) → checkpoint for TaxaLikely's sequence Layer-1 script |

---

## Score Window Algorithm (blast_sequences)

Rather than a flat top-N cutoff, `blast_sequences()` filters per query:
1. Remove hits below `min_score` (default 70%)
2. Remove hits with query coverage below `min_query_coverage` (default 80%)
3. Remove hits with subject length outside barcode range (via `barcode_term`)
4. Per query: keep all hits within `score_range` of the top hit (default 2%)
5. Apply `max_hits` safety cap per query (default 20)

A clear top match may return only 1-3 hits. An ambiguous query retains all
plausible candidates.

---

## Barcode Length Defaults

**Session 57 (Prompt 16):** Local copies of `.barcode_length_defaults` and
`.resolve_barcode_lengths_local()` removed from `R/sequence_input.R` and `R/blast_sequences.R`.
Now uses `TaxaTools::barcode_length_defaults` and `TaxaTools::resolve_barcode_lengths()`
(single source of truth). See TaxaTools CLAUDE.md for the full barcode length table.

---

## `filter_redundant_hypotheses()`

**Purpose:** When a match pipeline returns both species-level and genus-level hits for the
same sample, the genus-level row is redundant — it adds no information that the species
row doesn't already provide, and it inflates the taxon list sent to TaxaLikely / TaxaAssign.
This function removes such redundant higher-rank rows while retaining genus/family rows
for lineages that have NO species-level match.

**Critical design point — redundancy is lineage-local, not global:**
A genus-level row for *Gobius* is redundant only if a *Gobius* species row also appears
for the same `observation_id`. It is NOT redundant merely because some other species-level row
(e.g., *Acanthogobius flavimanus*) exists in the same sample. Dropping all genus rows
whenever any species match exists would silently discard real alternative hypotheses.

**Algorithm:**

1. Convert `taxon_name_rank` to a numeric rank score using the supplied `rank_system`
   vector (e.g., `c("kingdom","phylum","class","order","family","genus","species")`).
   Position in vector = score; species = highest, kingdom = lowest.

2. For each `observation_id × row`, determine whether any other row in the same `observation_id`
   satisfies BOTH:
   - Its rank score is strictly higher (finer rank), AND
   - It shares the same values in ALL taxonomy columns that correspond to ranks coarser
     than or equal to the current row's rank.
   (This checks "is this row an ancestor of any finer-rank row?")

3. Drop rows for which step 2 is TRUE.

**No score column required** — the only ordering information needed is the rank ordering
vector and the taxonomy columns (kingdom → species). The DNA/image/acoustic match score
is irrelevant to this filter.

**Input requirements:**
- `match_df` with `observation_id`, `taxon_name_rank`, and the full set of taxonomy columns
  named in `rank_system` (populated down to the matched rank; finer ranks are NA).
- `rank_system`: character vector, coarsest first (e.g., `kpcofgs`).
  Rows with `taxon_name_rank` not found in `rank_system` are retained unchanged with a
  warning.

**Signature (proposed):**
```r
filter_redundant_hypotheses <- function(match_df,
                                         rank_system = c("kingdom","phylum","class",
                                                        "order","family","genus","species"))
```

**Example:** sample S1 has rows for *Gobius paganellus* (species), *Gobius* sp. (genus),
and *Acanthogobius* sp. (genus). The *Gobius* genus row is dropped (superseded by
*G. paganellus*). The *Acanthogobius* genus row is retained (no species match for that
lineage).

**Where to call it:** Inside `standardize_match_data()` as an optional step, or as a
standalone exported function called explicitly. Recommend standalone so callers can
inspect before and after. Should run AFTER `create_taxon_names()` so `taxon_name_rank`
is already populated.

**Note for implementation:** The prototype `f_filter_redundant_higher_hypotheses()` in
`TaxaAssign/inst/TaxaAssign_llm_workflow.R` (Session 36) uses a score-column approach
that conflates rank ordering with match quality and applies a global (not lineage-local)
filter. The rewrite described here supersedes it. The `f_score_ordinal_col()` helper in
the same workflow file has been removed (Session 39); rank scoring is now handled inline
inside `filter_redundant_hypotheses()` via `match()`.

---

## Key Design Notes

- Column renaming uses `TaxaTools::rename_cols()` with a source-specific `col_map`
- Taxonomic name derivation uses `TaxaTools::create_taxon_names()`
- Output must conform exactly to the match object spec above before passing to TaxaLikely
- `TestId` (marker type) and `Accession` (reference accession) are retained but not
  renamed and play no role in the likelihood model

---

## Session Notes

**Session 139 (2026-07-06): default spatial_group_id redesign (exact-match, not observation_id) + spatial-grouping applet usability fixes**

Branch `main`. Found live, during the user's own interactive Phase 6 testing of
`TaxaID_Workflow_Template_TEST.R` (session continuing from `ecosystem_docs/
REENTRY_PROMPT_session138_multisite_posterior_combination.md`'s Phase 6) -- not from
reading code.

**The core insight, from the user directly:** `build_site_table()`'s default
`spatial_group_id = observation_id` conflates two different things. `spatial_group_id` is
supposed to answer "do these coordinates belong together," a property of *location* -- but
defaulting it to the row's own observation made a genuine multi-site observation's several
sites always share one group (regardless of whether they're actually near each other),
while two different observations sharing an exact site coordinate (e.g. two ASVs both
detected in the same physical sample) never defaulted to sharing a group at all, even
though that's real, meaningful co-location information. This directly contradicts this
ecosystem's own stated Session 134 design principle that clustering should be a geometric
property of coordinates, not a submission-process property.

**First attempt (grid-snapping) tried and rejected, live, same session:** a design
rounding `(lat, lon)` to a fixed bin size (`TaxaExpect::create_sites_from_grid()`'s own
label format, `"Grid_{lat_r}_{lon_r}"`) was implemented first. Live-tested against this
template's own real bundled data with a `0.1`-degree default bin: it collapsed **four**
genuinely distinct observations (a real sample coordinate and a fallback/placeholder
coordinate that happened to sit within ~11km of each other) into one default cluster --
reintroducing, automatically and silently, the exact "swept into an unrelated cluster"
ambiguity this whole redesign exists to prevent. Choosing a "correct" bin size is not
well-posed in general (depends on how close together a given study's real sites happen to
be, which this function has no way to know). **User's fix, adopted:** group by **exact**
`(lat, lon)` match instead -- no tuning parameter, and correct for this ecosystem's actual
data flow, where shared coordinates come from a site-metadata table join (e.g.
`join_event_site_metadata()`'s pattern), not independent noisy GPS reads of the same
physical spot. `default_grid_size` (added, then removed the same session) never shipped
in any released state.

**`is_default_group` column added** (`build_site_table()` sets it `TRUE` on every row) to
replace the old `spatial_group_id == observation_id & spatial_group_N == 1` heuristic
`group_observations_by_bbox()`/`.assign_spatial_groups_from_polygons()` used to infer
"still at default" -- needed once the default label stopped being `observation_id`-shaped,
but a cleaner mechanism regardless (decouples "is this default" from having to know or
guess what the default label looks like). `group_observations_by_bbox()` migrates an
older-shaped `sites` input missing this column via the old heuristic, with a message, so
existing cached/saved site tables keep working. `assign_spatial_group()` also clears it
for manually-assigned rows when present (no-ops harmlessly otherwise).

**Numbering-collision guard added:** once both `build_site_table()`'s exact-match default
*and* `group_observations_by_bbox()`'s drawn groups mint `"spatial_group_<n>"` labels, they
could collide (e.g. a default group already named `spatial_group_1`, then a freshly drawn
box also starting its own count at 1) -- a real, live-tested risk that didn't exist before
this session, since the old `observation_id`-shaped default could never collide with the
`"spatial_group_<n>"` format by construction. New `.next_spatial_group_number()` helper
(shared internal, in `build_site_table.R`) scans existing `spatial_group_id` values and
returns one past the highest `"spatial_group_<n>"` number found; both the default
assignment and the drawn-group numbering now go through it.

**Spatial-grouping applet usability redesign** (same session, prompted directly by the
user hitting real confusion live): `TaxaTools::define_search_polygon()` gained `title`/
`done_label`/`cancel_label` parameters (backward-compatible defaults unchanged) -- see
that package's own Session 139 note for the full detail. `group_observations_by_bbox()`'s
draw loop now passes `done_label = "Group These Points"`, `cancel_label = "No More
Groups"`, and a per-iteration `title` showing live progress (`"Draw Spatial Group N (M
observation(s) still ungrouped)"`) instead of relying on the gadget's generic "Done"/
"Cancel" wording; `.review_drawn_groups()`'s reshape call similarly now reads "Save
Shape"/"Keep Original Shape" with a `"Reshape Spatial Group N"` title.

**Real bug found and fixed the same way** (live testing, not code reading):
`TaxaID_Workflow_Template_TEST.R`'s Section 3 calls `TaxaTools::define_search_polygon()`
directly for a multi-member group's pooled search area, but never checked whether it
returned `NULL` (which it does when its own gadget is cancelled) before passing that
straight into `TaxaFetch::get_gbif_occurrences(geometry = ...)` -- which crashed several
calls downstream with a confusing "geometry must be a single WKT string" error instead of
a clear message naming the actual problem. Fixed with a direct `stop()` in the template
naming the affected group and its members. Also added per-group progress `message()`s to
Section 3's loop (both the pooled and escalation-ladder branches) after the user reported
the multi-step loop was "hard to debug since the function groups a lot of processes."

`devtools::document()` + `devtools::test()` (450 expectations, 0 failures) +
`devtools::check()` (0 errors, 0 warnings, 0 notes) all clean, twice (once after the
exact-match/is_default_group work, again after the applet-redesign work). New/updated
tests across `test-build_site_table.R` (exact-match default behavior, co-located vs.
differently-located observations, `.next_spatial_group_number()` directly),
`test-group_observations_by_bbox.R` (`is_default_group` propagation, numbering-collision
avoidance), and `test-assign_spatial_group.R` (`is_default_group` clearing, backward
compatibility without the column).

**Not done this session:** the two-pass split (define every group's geometry before
fetching any of them) that the taxon-centric GBIF-fetch-efficiency design depends on --
see `ecosystem_docs/REENTRY_PROMPT_session139_gbif_fetch_efficiency.md`'s own
same-session addition for why this session's applet work makes that split newly relevant,
without implementing it.

**Session 137 continued (2026-07-05): join_event_site_metadata() — Phase 4 (DNA/BLAST half) of the observation-pipeline-wiring plan**

Branch `single-observation-pipeline`. Per `ecosystem_docs/REENTRY_PROMPT_session137_
observation_pipeline_wiring.md`'s Phase 4, this needed the user's real answer before any
implementation, not just engineering: how does an event_id/sample ID actually connect to
a physical site and collection date? Real event_ids found in this ecosystem (Palmyra:
`"Palmyra01"`; PtConception: `"XBK316KS"`, `"Blank1.0"`) are opaque lab codes with no
embedded site/time info -- confirmed by reading the actual production workflows, not
assumed. User's answer: eDNA studies already construct a lookup table connecting sample
columns to attributes (the existing `BLANKS_MARCH`/`BLANKS_AUG` pattern for identifying
blanks is the same idea) -- the same kind of table should carry lat/lon/site name. For
acoustic, the user described two plausible real shapes (fixed BirdWeather-style
recorders, each with one site; or a field trip submitting recordings from several sites)
but was explicitly unsure which shape real data will actually take -- so that half stays
deferred rather than guessed at.

`join_event_site_metadata(detections, site_metadata, event_col = "event_id", id_col =
"observation_id", lat_col = "lat", lon_col = "lon", observed_on_col = "observed_on",
control_samples = NULL)` added (`R/join_event_site_metadata.R`). Deliberately
data-type-agnostic -- DNA/BLAST (Reads-table sample columns, already pivoted to long
format by the calling workflow's own study-specific `pivot_longer()`, since that pivot
step is genuinely idiosyncratic per lab/study and not something to force into one shared
function) and acoustic (recording/device identifiers) both reduce to "join an event
identifier against a metadata table of where/when that event happened," so one function
serves both rather than duplicating the join per pathway. `control_samples` reuses the
same param name as `TaxaFlag::flag_contaminant()` for consistency. Returns a
`site_df`-shaped tibble directly feedable to `build_site_table()`.

Wired live into `inst/TaxaID_Workflow_Template_TEST.R`'s Section 2.5 (not just added and
left unused): new `SAMPLE_SITE_METADATA` config table gives the bundled `Reads_Table`'s
`sample_1`/`sample_2`/`control_1` columns genuinely different real coordinates, so this
template's own bundled test data now exercises actual multi-site behavior (previously,
Phase 2's wiring could only be verified structurally, on one hardcoded placeholder
point). Also added a fallback path for any `decontaminated_table` observation with no
Reads_Table row at all (this template's own `conflict_row` demo taxon, added purely to
show GBIF taxonomy-conflict handling in Section 1 -- never a real sequenced sample) so no
observation is silently dropped from spatial grouping.

**Real bug found and fixed by actually testing this against the bundled Reads_Table
values (not by reading code):** one bundled ASV (`OQ846725`) has real, non-blank reads
in both `sample_1` and `sample_2` -- a genuine multi-site single observation.
`build_site_table()` hardcodes `spatial_group_N = 1L` on every row unconditionally in its
`site_df` branch (only `group_observations_by_bbox()` recomputes it via real `table()`
counting, and only after grouping actually runs) -- so this ASV's two site rows both
read as `spatial_group_N = 1`, even though `site_table` genuinely has 2 rows sharing
that `spatial_group_id`. `TaxaID_Workflow_Template_TEST.R`'s Section 3 branching
originally checked `group_sites$spatial_group_N[1L] >= 2L` (the stored, possibly-stale
column) rather than `nrow(group_sites) >= 2L` (what is actually in `site_table` for that
group) -- meaning a multi-site ASV would have silently been misrouted to the
single-observation escalation branch, which only reads the *first* site row
(`group_sites$lat[1L]`/`lon[1L]`), quietly dropping its second site's context entirely.
Fixed by switching to `nrow(group_sites) >= 2L`, which is correct whether or not
`group_observations_by_bbox()` has run. Documented as a known, deliberately-not-"fixed"
limitation in `SAMPLE_SITE_METADATA`'s own comment: a multi-site single ASV now routes
to the multi-member pooled-fetch branch (a reasonable fallback -- pools its own two
sites' occurrence context) rather than the correct-but-unbuilt per-`(observation_id,
site)` treatment, which is explicitly Phase 5's job, not this session's.

Verified via a standalone reproduction of Section 2/2.5's logic against the real bundled
`Reads_Table` values (BLAST/GBIF calls stood in for, same reasoning as Phase 2 -- a full
live run needs BLAST/NCBI/GBIF/Anthropic plus two interactive Shiny gadgets, out of scope
for this session, deferred to Phase 6): confirmed the multi-site ASV produces exactly 2
site rows sharing one `spatial_group_id`, the blank-only ASV correctly falls through to
the no-site fallback, and the fix correctly reclassifies the multi-site case as
multi-member. 20 new tests (`test-join_event_site_metadata.R`), fully offline.
`devtools::document()` + `devtools::test()` (426 expectations, 0 failures) +
`devtools::check()` (0 errors, 0 warnings, 0 notes) all clean.

`score_acoustic_workflow.R` gets a documentation-only note (no code change): this
tutorial's real BirdNET data (Xeno-canto downloads from scattered, uncontrolled
locations) has no honest site-metadata table to join against, so the acoustic half of
Phase 4 stays deferred rather than wired against fabricated coordinates -- matching this
script's own "NO SYNTHETIC DATA" convention. The two real-world shapes the user
described (fixed-recorder devices vs. multi-site field-trip submissions) are documented
inline for whenever real deployment data exists to confirm which applies.

**Session 137 (2026-07-05): score_image_workflow.R — Phase 3 of the observation-pipeline-wiring plan**

Branch `single-observation-pipeline`. Per `ecosystem_docs/REENTRY_PROMPT_session137_
observation_pipeline_wiring.md`'s Phase 3 (the smallest of the four workflow-wiring
phases): this script previously passed `SITE_LAT`/`SITE_LNG` to `score_image_inat()`
unconditionally, silently overriding every photo's own EXIF coordinates (per that
function's own documented behavior) even though `score_image_inat()` already supports
real per-photo EXIF-derived coordinates.

Added `OVERRIDE_SITE_LATLNG` CONFIG flag (default `TRUE`). When `TRUE`, behavior is
unchanged from before this session (`lat = SITE_LAT, lng = SITE_LNG` passed through).
When `FALSE`, `lat = NULL, lng = NULL` is passed instead, so `score_image_inat()` reads
each photo's own real EXIF GPS. `TRUE` is the right default specifically for this
script's own bundled photo set (confirmed directly: these Bushnell trail-camera JPEGs
carry no GPS EXIF at all -- `OVERRIDE_SITE_LATLNG = FALSE` produces all-`NA` `lat`/`lng`
on this exact photo set), not a generic recommendation -- the comment block makes this
explicit so a user swapping in their own photos with real per-photo EXIF GPS knows to
flip it.

New Step 2.5 calls `TaxaMatch::build_site_table()` on the checkpointed match object (no
`site_df` needed -- the image pathway's output always carries embedded `lat`/`lng`,
either the uniform override or real EXIF, so `build_site_table()` extracts it directly)
and checkpoints the result as `image_site_table`. Not consumed further in this script
(unchanged scope -- still stops at TaxaLikely, per its own header note) but now produced
and saved for whenever a future TaxaAssign continuation for these species needs it,
matching the "Output" block's own updated documentation.

Live-verified both flag settings against the real bundled 52-photo/8-species set (not
just parsed): `OVERRIDE_SITE_LATLNG = TRUE` reproduces the documented 82% top-1 CV
accuracy (42/51, matching Session 129's result exactly -- confirms no regression from
this session's change) and correctly reports "51 spatial group(s)" (every photo defaults
to its own singleton group; `build_site_table()` does not itself deduplicate identical
coordinates into one group -- that's `group_observations_by_bbox()`'s job, out of scope
for this script). `OVERRIDE_SITE_LATLNG = FALSE` confirmed `lat` is `NA` for all 51
scored photos (no EXIF GPS present, as expected) and top-1 accuracy correctly drops to
60% (30/50) without the geographic prior -- consistent with the already-documented
finding that supplying real lat/lng measurably helps. `build_site_table()` handled the
all-`NA`-coordinate case without erroring in both live runs.

**Not done this session** (Phases 1-2 already landed in earlier Session 137 work; Phases
4-7 remain open): the Reads-table relocation, the TaxaAssign `(observation_id, site)`
schema question, the end-to-end test matrix, and documentation. See the reentry prompt
for the full sequenced plan.

**Session 135 (2026-07-05): blast_sequences(resolve_location=) — GenBank location extraction for BLAST hits**

Companion to TaxaLikely's same-session fetch-side work — together they close two of
the three location-metadata gaps flagged in `ecosystem_docs/
TODO_validation_benchmark.md`'s "Sourcing location data from online reference
records" section (BOLD's equivalent remains a separate, unchecked TBD; wiring either
into a real `build_site_table()` `site_df` call is left for benchmark-harness time).
Explicitly scoped to this plumbing only — the leave-one-out benchmark harness itself
stays gated behind the user's 2026-07-04 directive.

Confirmed directly: `.resolve_taxonomy()` and `.resolve_taxonomy_by_acc()` only ever
reach the NCBI **taxonomy** database (lineage), never `db="nucleotide"`, so a BLAST
hit's collection coordinates were never in scope regardless of `resolve_taxonomy`.
Added `.parse_lat_lon()` (INSDC `lat_lon` qualifier parser, identical to TaxaLikely's
own — deliberately duplicated rather than shared, matching this ecosystem's existing
pre-manuscript stance) and `.resolve_locations_by_acc()` (fetches full GBSeq XML by
accession directly, no search→summary round trip). `blast_sequences(resolve_location =
FALSE)` — new opt-in trailing param; when `TRUE`, resolves unique hit accessions and
left-joins `lat`/`lon`/`country` onto the output (version-suffix-stripped join key on
both sides, defensive since `GBSeq_primary-accession` is already version-free but
BLAST's `sacc` isn't guaranteed to be).

New tests in `test-blast.R`: `.parse_lat_lon()` (5 cases, same coverage as TaxaLikely's
mirror), `.resolve_locations_by_acc()` empty-input typing, `resolve_location` input
validation. `devtools::document()` + `devtools::test()` (406 expectations, 0 failures,
0 warnings) + `devtools::check()` (0 errors, 0 warnings, 0 notes) all clean.

**Session 134b (2026-07-04): group_observations_by_bbox() moved here and reworked; assign_spatial_group() added**

Branch `single-observation-pipeline`. Follow-up to Session 134 below and to TaxaFetch's
Session 134 (`group_observations_by_bbox()` originally landed there). After the user
reviewed that implementation and raised design questions before committing (recorded in
`ecosystem_docs/REENTRY_PROMPT_session134b_grouping_implemented.md`), three decisions
were confirmed and implemented this session:

- **Package placement:** `group_observations_by_bbox()` moved from TaxaFetch to TaxaMatch.
  It operates on `build_site_table()`'s output and decides `spatial_group_id` membership --
  a spatial-grouping concern that belongs next to the site table, not a fetch concern.
  `TaxaTools::define_search_polygon()` (also moved this session, from TaxaFetch) is the
  shared gadget both this function and TaxaFetch's search-area use now call.
- **`build_site_table()` reframed as the source of truth for `spatial_group_id`/
  `spatial_group_N` defaults**, not `group_observations_by_bbox()`. Every site table now
  gets `spatial_group_id` (default = the row's own `observation_id`) and `spatial_group_N`
  (default = `1L`) from the moment it's built -- solving the original worry that a
  downstream function could assume these columns exist on a site table that never went
  through grouping. `group_observations_by_bbox()` **updates these columns in place**
  for whichever observations get captured by a drawn box; this simplified the "leftover"
  handling considerably -- an observation outside every drawn box just keeps its existing
  default, no separate singleton-numbering logic needed (the old
  `"spatial_group_<n>"`-for-everyone convention from TaxaFetch's Session 134 is
  superseded by this simpler default-to-`observation_id` shape; multi-member groups still
  use `"spatial_group_1"`, `"spatial_group_2"`, ... in draw order).
- **Manual assignment mechanism:** `assign_spatial_group()` added, a validating helper
  rather than "just document that the column is editable" -- the user wanted the
  collision guard (see Function Inventory entry above) rather than relying on callers to
  get it right by hand.

Also implemented, per the reentry prompt's "settled after further review" items:
- **Last-drawn-wins overlap rule** (reversing the old first-drawn-wins): when an
  observation falls inside more than one drawn polygon, the most recently drawn one's
  group wins, with a `warning()` naming every ambiguous `observation_id`. Required
  restructuring `.assign_spatial_groups_from_polygons()` to check every still-default
  point against every polygon (not just points still "remaining" as boxes are drawn),
  since two drawn boxes can geometrically overlap even though the interactive loop's own
  view-narrowing heuristic only shows "not yet captured" points at each step.
- **End-of-loop review/edit/delete step** (`.review_drawn_groups()`): after the user
  cancels the draw loop, a numbered summary of drawn groups with member counts; entering
  a number reopens that group's polygon via `TaxaTools::define_search_polygon(
  init_polygon = ...)` for reshaping (new gadget param, see TaxaTools/CLAUDE.md);
  `"delete <n>"` removes a group, releasing its members back to the default pool;
  Enter/`"done"` finalizes. No-op (returns polygons unchanged) when zero polygons were
  drawn or the session is non-interactive -- same testing boundary as the gadget itself.
- **Default starting polygon full-enclosure guarantee confirmed, not just assumed:**
  `.bbox_center_radius()`'s `radius_deg = max(half-ranges) * pad` (pad = 1.2) was already
  correct but only implicitly so; added an explicit test
  (`.bbox_center_radius()`'s "fully enclose every input point" case) and documented it as
  a guaranteed property in the roxygen, per the reentry prompt's request to confirm this
  before relying on it.

**Live-testing hazard found and mitigated (same session, after a real user report) --
initial hypothesis corrected below:** the first live run produced a fully unchanged
result -- a box was drawn around a real cluster and "Done" was clicked, but the returned
table showed no grouping applied at all, and no second gadget opened. Two mitigations
were added while investigating: (1) `message()` progress feedback throughout the draw
loop (box N captured M of N remaining; how many boxes recorded after Cancel; how many
after review) so a live run's console transcript makes the actual sequence of events
visible instead of opaque; (2) an explicit roxygen `@details` warning about running
`group_observations_by_bbox()` as one isolated command, since its review step reads
console input via `readline()` and RStudio can queue a following line as pending console
input if both are submitted together. Both are harmless and worth keeping, but **neither
was the actual root cause** -- an initial "RStudio queues the next line as readline()'s
answer" hypothesis was floated and written up here, but the real bug (found via
extended debugging, including Claude's Chrome browser-automation tools reproducing the
exact gadget in a real browser) was that **`TaxaTools::define_search_polygon()`'s Done
button never returned a value at all** when opened via RStudio's `dialogViewer()` --
confirmed reproducible even in a bare, no-loop, no-`readline()` standalone call. See
`TaxaTools/CLAUDE.md`'s Session 134b note for the full root-cause record and fix
(`define_search_polygon()` now defaults to `shiny::paneViewer(minHeight = 500)` instead
of `dialogViewer()` -- `browserViewer()` was the first fix and also confirmed working,
but the user pointed out `paneViewer()` matches this ecosystem's other mapping gadgets
and should be preferred for a consistent interaction style, which was then verified
directly against this exact gadget too). With that fixed, `group_observations_by_bbox()`
needed no code changes of its own -- it inherits the new default automatically, so it
now opens each box-drawing step in RStudio's Viewer pane, same as before the bug, just
via a different (working) viewer call. The `readline()`-queuing hazard documented above
is still real and still worth avoiding, just wasn't what happened here.

**Not done this session** (still open, see the reentry prompt's remaining items): the
search-area-vs-spatial-group reconciliation (`points` param support for group-coloring
was added to `define_search_polygon()`, but the actual per-group search-area drawing
workflow is deferred to the fetch-scope-wiring session), fetch-scope branching itself
(pooled fetch for multi-member groups vs. taxonomic escalation for singletons), the
Reads-table relocation, and the TaxaAssign `(observation_id, site)` schema question.

16 new/rewritten tests in `test-group_observations_by_bbox.R` (fully offline; the old
15-test TaxaFetch version was rewritten for the new default-to-`observation_id` behavior
and last-drawn-wins logic, not just moved verbatim), plus 10 new tests in
`test-assign_spatial_group.R` and 2 new tests in `test-build_site_table.R` for the new
default columns. `sf` added to `DESCRIPTION` Imports. `devtools::document()` +
`devtools::test()` (390 expectations, 0 failures) + `devtools::check()` (0 errors, 0
warnings, 0 notes) all clean.

**Session 134 (2026-07-03): build_site_table() -- unified long-format site table**

Branch `single-observation-pipeline`. Closes (partially) the site-table contract gap
flagged in `ecosystem_docs/REENTRY_PROMPT_session134_single_observation_pipeline.md`
(also `~/.claude/projects/-Users-lafferty/memory/project_site_table_contract_gap.md`):
per-observation `lat`/`lon` is inconsistently present across the three match-object
pathways. Confirmed directly this session (not assumed): `read_birdnet_output()`'s
output carries **zero** site metadata -- only detection-window start/end times and the
source recording filename, nothing GPS-like at all. So acoustic (like DNA/BLAST) needs
site info supplied externally; only the image pathway (`score_image_inat()`) has it
embedded.

`build_site_table(match_df, site_df = NULL, id_col = "observation_id")` added
(`R/build_site_table.R`): when `match_df` carries embedded `lat`/`lng` (image pathway),
extracts and renames to the canonical `lat`/`lon`/`observed_on` shape directly, ignoring
(with a warning) any `site_df` supplied alongside. Otherwise requires `site_df`
(`observation_id`/`lat`/`lon`, optional `observed_on`) and joins it in, explicitly
allowing more than one `site_df` row per `observation_id` -- this is the correct,
intended shape for the ASV multi-site case flagged in the reentry prompt (a sequence
ASV genuinely detected at several real sites within one sequencing run produces multiple
`(observation_id, site)` rows sharing one likelihood, not a single row with one site).
14 new tests (`test-build_site_table.R`), fully offline. `devtools::test()`: 342
expectations, 0 failures. `devtools::check()`: 0 errors, 0 warnings, 0 notes.

**Not done this session** (left for the dedicated follow-up the reentry prompt already
flagged): relocating the Reads-table (ASV x sample matrix, each sample column carrying
an associated place + time) wide-to-long parsing logic from `TaxaFlag`'s
`inst/contaminant_workflow.R` pivot step into a proper TaxaMatch function that feeds
`build_site_table()`'s `site_df` argument directly for the sequence pathway -- confirmed
this session that no such reusable function exists yet anywhere in the ecosystem, only
an ad hoc `pivot_longer()` in that one workflow script, which doesn't yet parse
per-sample place/time out of the sample-label convention. `TaxaAssign`'s downstream
`(observation_id, site)` schema question (whether `join_priors()`/`compute_posterior()`/
`posterior_consensus()` need to key on the pair rather than `observation_id` alone) is
also still open, unaffected by this session's work.

**Session 132 (2026-07-03): non-portable filenames fixed (rename)**

Closed out the "known issue for next session" flagged at the end of Session 129's
note below. Renamed the `ground squirrel` folder → `ground_squirrel` and all 39
`" copy.JPG"` files → `"_copy.JPG"` under
`inst/extdata/example_images/camera_trap_photos/` via `git mv` (underscore
convention, matching `camera_trap_photos/` itself from Session 124). Updated the
`FOLDER_TO_SPECIES` key in `score_image_workflow.R` to `"ground_squirrel"` to
match. `devtools::check()`: 0 errors, 0 warnings, 0 notes — "checking for portable
file names" now OK. Live-verified by re-running `score_image_workflow.R`'s Steps
1-2 (real iNaturalist CV call, all 52 photos): 0 NA `true_species` values across
294 rows, `ground_squirrel`'s photos all correctly resolve to `Otospermophilus
beecheyi`, and top-1 accuracy (82%, 42/51) matches the prior session's pattern —
no regression from the rename. `devtools::install()` re-shipped the renamed data
to the canonical library (`/Library/Frameworks/R.framework/Versions/4.5-arm64/
Resources/library`) — note `Rscript -e` does not source `~/.Rprofile` the way
RStudio does, so a plain `Rscript`-driven `devtools::install()` can silently
target the wrong `.libPaths()[1]` (this session hit a stale `~/Library/R/4.0/
library` on the first attempt); `devtools::install()`'s existing-install
detection recovered by updating the already-installed copy in place, but calling
`.libPaths()` explicitly first is safer than relying on that.

**Session 129 (2026-07-03): score_image_workflow.R expanded to 8 species/52 photos; taxonomic-scope filter added**

Expanded from the original 6-photo/5-species diversity-only set (Session 124) to get
enough replicate photos per species to move past a small-n result on whether
`TaxaLikely::correct_training_bias()` should be enabled by default for the image
pathway — see `TaxaLikely/CLAUDE.md`'s Session 129 note for the calibration finding this
made possible (short answer: `tau ≈ 0`, correction should not be applied here).

- 3 new species added, all real photos of the user's own: Raccoon (*Procyon lotor*,
  Procyonidae), California Ground Squirrel (*Otospermophilus beecheyi*, Sciuridae),
  Virginia Opossum (*Didelphis virginiana*, Didelphidae) — 7 families total now.
- Photos reorganized from a flat file list into per-species subfolders (folder name =
  common name). `score_image_inat()` already supported `recursive = TRUE` and its own
  `folder_1` path-metadata column — used directly rather than hand-rolling file discovery
  or a per-filename ground-truth lookup, which would no longer have worked once filenames
  became camera-generated sequence numbers instead of descriptive names.
- **Real off-scope candidates found and filtered:** running the expanded set surfaced
  that iNaturalist's CV model returns candidates from any iconic taxon, not just mammals
  — *Baccharis pilularis* ("coyote brush", a plant) and *Acacia longifolia* both appeared
  for coyote.JPG, and a screech owl (*Megascops kennicottii* — the same taxon originally
  flagged as a `correct_training_bias()` flip in Session 128) appeared for rabbit.JPG.
  Added `TARGET_ICONIC_TAXA = "Mammalia"`, filtered right after scoring and before
  `unreferenced_candidates()`/`assign_scores()` ever see the candidates — this changes
  the actual likelihood math (removes competing probability mass), not just a post-hoc
  annotation. `top_n` raised 5→8 as a safety margin since filtering can remove some of
  each photo's candidate slate; a guard warns (does not silently drop) if any photo loses
  every candidate to the filter.

**Not done — known issue for next session:** the newly added photo filenames contain
spaces (`"01150531 copy.JPG"`) and the `"ground squirrel"` folder name does too, both
triggering `R CMD check`'s non-portable-filenames WARNING — the exact same issue class
already fixed once in this file's history (Session 124's `"camera trap photos"` →
`"camera_trap_photos"` rename), now recurring. Needs a rename across ~30 files plus a
matching key update to `FOLDER_TO_SPECIES` in `score_image_workflow.R`; not done this
session since it touches many tracked files. **Fixed in Session 132 (see above).**

**Session 126 (2026-07-01): Layer-1 workflow script for sequence/BLAST data type**

`inst/workflows/blast_sequences_workflow.R` added — the third and last Layer-1 data-type
script for TaxaMatch (image and acoustic done Session 124). Reproduces Session 115's
already-field-tested `inst/test_blast_remote.R` field test in the Layer-1 workflow-script
convention (`DEBUG_MODE`, explicit checkpoints, Output block) rather than introducing a
new example dataset: 5 real 12S MiFish sequences from the user's own PtConception eDNA
study, fetched live from NCBI by accession (OQ846539/OQ846195/OQ846544/OQ846550/OQ846725).
Live-tested, 0 errors: 5/5 (100%) top BLAST hits correct at ≥98% identity, matching Session
115's result exactly.

One addition beyond the original field test script: `standardize_match_data()` is now
called with `coverage_col = "query_coverage"`, renaming BLAST's own alignment-quality
metric to the canonical `coverage` column so TaxaLikely's `evaluate_likelihoods(
min_coverage = ...)` can consume it directly with no extra join — the original Session 115
script didn't carry this column through.

This is the first of a two-package mini-chain; it stops at the canonical match object
(`taxamatch_blast_match_obj` — 18 rows, 5 queries, 12 unique taxa across the 3-batch score
window). Consumer: TaxaLikely's sequence Layer-1 script (`build_sequence_matrix()` →
`train_likelihood_model()` → `evaluate_likelihoods()`) — see
`ecosystem_docs/REENTRY_PROMPT_session124_image_acoustic_workflows.md`, Stage 2, item 2.

**Session 124 (2026-07-01): Layer-1 workflow scripts for image and acoustic data types**

Item 4 of `ecosystem_docs/REENTRY_PROMPT_session123_layer1_workflows.md` — image/
acoustic was the recommended starting point (structurally simpler than sequence/BLAST,
no DECIPHER/reference-fetch step). Both new scripts are 100% real, live-tested, no
synthetic data:

- `score_image_workflow.R`: live `score_image_inat()` calls against real Bushnell
  trail-camera photos of 5 mammal species across 4 families (Bobcat, Coyote, Brush
  Rabbit, Western Spotted Skunk, Striped Skunk ×2; Central California coastal scrub,
  34.41 N / -119.86 W). Deliberately a DIVERSITY OF TAXA rather than many replicate
  photos of one species or a single confusable pair — consistent with how the
  BLAST/sequence field test (Session 115) demonstrates pipeline mechanics across a
  handful of real queries, not a CV-accuracy calibration study. 5/6 (83%) top-1 correct
  once the real site lat/lng was supplied (2 of 6 flipped from wrong to correct vs. no
  location — `combined_score` blends vision confidence with local occurrence
  frequency). The one miss (coyote.JPG) is a genuine name/geo-prior collision: top
  candidate was *Baccharis pilularis* ("coyote brush"), a locally abundant plant, not a
  taxonomic near-miss.
- `score_acoustic_workflow.R`: ingests real BirdNET-Analyzer CSV output (produced by
  `sources/birdnet_csv_export.py`, a companion Python script — not part of this R
  package — that downloads real Xeno-canto recordings and runs the actual BirdNET model
  via `birdnetlib`) for three confusable Calidris sandpipers. 37/42 (88%) detection
  windows correct; the misses are genuine acoustic confusion (background noise,
  Least Sandpiper mistaken for Western/Semipalmated), not bugs.

**Earlier iteration used bird photos that were replaced.** The first version of
`score_image_workflow.R` used Semipalmated/Western Sandpiper photos from the user's
manuscript folder (10/10, 100% — see superseded design notes below) — replaced after
the user pointed out those were screenshots sourced from eBird/Macaulay-Library-linked
checklists, not photos they had rights to redistribute in this public package. Also
discovered mid-session: `TaxaMatch/inst/extdata/` already contained untracked copies of
those same bird photos (Google Drive multi-parent-folder linking, not something this
session created) — left in place rather than deleted via `rm`, since deleting a
multi-parented Drive file through the desktop sync client can trash the object
everywhere it appears, including the user's original manuscript folder. The user needs
to unlink that folder-location manually via Drive's UI before those files are safe to
remove from the local filesystem.

**Bugs/gaps found by actually running these scripts (not caught by reading code):**
- `unreferenced_candidates()` needs >= 2 populated rank columns; both
  `score_image_inat()` and `read_birdnet_output()` output only `genus` (no `family`,
  no separate `species` column) — fixed in both scripts via
  `TaxaTools::fill_higher_ranks()` + `species <- taxon_name` (full binomial;
  convention confirmed from `fill_higher_ranks()`'s own `@examples`, which does the
  same rename for a sibling function).
- `read_birdnet_output()`'s output has no `taxon_name`/`taxon_name_rank` at all (only
  `species`/`genus`) — same cross-script contract gap as TaxaFetch's Bug #12 from the
  five-package chain; fixed via `TaxaTools::create_taxon_names()`.
- `assign_scores(score_type = "probability")` errors/warns when scores exceed 1 —
  correct for BirdNET's already-bounded 0-1 confidence, but iNat's `combined_score` is
  UNBOUNDED (observed values up to ~3000 on an easy photo) and needs
  `score_type = "similarity_softmax"` instead. Confirmed both score types
  ratio-normalize by the winning candidate's own score (`sc / max_sc` /
  `sc_softmax / max_ss`) — the winner's `score_likelihood` is therefore always exactly
  1.0 by construction; the meaningful comparison across observations is which taxon
  won, not the likelihood magnitude.
- Xeno-canto's v2 API (`https://xeno-canto.org/api/2/recordings`, used by the user's
  original `birdnet_calidris_selftest.py`) now 404s — fully removed, not just an auth
  change. v3 (`https://xeno-canto.org/api/3/recordings`) requires a key AND
  tag-based query syntax (`gen:X sp:Y type:call`, not free-text `query=X Y type:call`).
  **This also affects production code**: `TaxaLikely::.xc_recording_count()`
  (`R/coverage.R`) still calls the dead v2 endpoint — `audit_acoustic_coverage(
  xc_recordings = TRUE)` currently returns `NA` for every species silently (checks
  `resp_status != 200`, no warning). Not fixed this session (out of scope for the
  image/acoustic Layer-1 workflow task; flagged for the user to decide whether to fix).
- Xeno-canto now requires per-application API keys, not personal ones (confirmed from
  xeno-canto.org/explore/api) — the user registered/confirmed a key specifically for
  this workflow rather than reusing a personal one already in `~/.Renviron`.
- `INAT_API_TOKEN` is a short-lived JWT; this session's stored token had already expired
  (~1 week old) — a 401 means regenerate the token, not a code bug.
- Non-portable file names/paths: bundling real example photos under
  `inst/extdata/example_images/` triggered an R CMD check WARNING for directory names
  containing spaces (`"camera trap photos"`) — renamed to `camera_trap_photos`
  (underscore) to fix; 0 warnings after.

Sessions 27–82 archived in ecosystem_docs/session_notes/TaxaMatch_sessions.md.

**Sessions 83–85 (2026-05-21 to 2026-05-23)**
- No TaxaMatch-specific changes. Ecosystem: `call_api()` generic dispatcher (TaxaTools), WERC
  review integration.

**Session 86 (2026-05-23)**
- No code changes. `DISCLAIMER.md` + `LICENSE.md` deleted from package root (centralised at
  TaxaID/ root). Disclaimer section removed from `README.md`.

**Session 87 (2026-05-26)**
- `read_birdnet_output()` implemented in `R/read_acoustic.R` (was Planned since Session 55).
  Reads BirdNET-Analyzer CSV output (one file per recording). Accepts file vector or directory.
  `observation_id = "{file_stem}_{start_s}-{end_s}"`. `score` = Confidence (0-1). `genus` derived
  from first word of Scientific name. `min_confidence` and `top_n` filters. `source_file` column
  for ground-truth join back to Xeno-canto reference metadata.
  Internal helper `.parse_birdnet_file()` validates required BirdNET columns.
- 9 offline tests in `tests/testthat/test-read_acoustic.R` (synthetic `tempfile()` + `write.csv()`
  BirdNET data — no real recordings needed).
- `devtools::check()`: 0 errors, 0 notes (2 pre-existing vignette warnings).

**Session 88 (2026-05-26)**
- Bug fix: `.parse_birdnet_file()` crashed with `"arguments imply differing number of rows: 1, 0"`
  when a BirdNET CSV contained only a header row and no detections (e.g., BirdNET found nothing
  above the confidence threshold in a short or quiet recording). Root cause: `source_file = basename(f)`
  has length 1 but all other columns (`start_vals`, `end_vals`, etc.) are `numeric(0)` / `character(0)`.
  Fix: added early return for `nrow(df) == 0L` that produces a correctly typed 0-row data frame
  and emits an informational message naming the empty file.
- 2 new tests in `test-read_acoustic.R` (total now 11): empty CSV returns 0-row data frame with
  correct columns; mix of empty + non-empty files returns only rows from non-empty file.
- `devtools::check()`: 0 errors, 0 warnings, 0 notes.

**Session 93 (2026-05-27)**
- `read_inaturalist_cv_output()` added to `R/read_image.R`. Reads per-image JSON files saved from the
  iNaturalist computer vision API. `score_type = "combined_score"` (default) or `"score"`. Returns
  `observation_id`, `score`, `species`, `genus`, `common_name`, `taxon_rank`, `source_file`. Accepts
  directory of JSON files or a file vector. `min_confidence` and `top_n` filters. 8 offline tests.
- `read_wildlife_insights_output()` added to `R/read_image.R`. Reads SpeciesNet / Wildlife Insights
  batch predictions JSON (top-level `"predictions"` dict keyed by image filename). `label_col = "label"`,
  `score_col = "score"` configurable. Returns `observation_id`, `score`, `species`, `genus`, `category`,
  `source_file`. `min_confidence`, `top_n` filters. 8 offline tests.
- `jsonlite` added to DESCRIPTION Imports (required by both new reader functions; `requireNamespace`
  guard allows graceful error if not installed).
- README "Other Image Classifiers" section updated: dedicated reader functions shown with example code;
  classifier comparison table updated.
- `devtools::check()`: 0 errors, 0 warnings, 1 note (pre-existing top-level files).

**Session 119 (2026-06-24)**
- `score_image_inat()` added to `R/score_image_inat.R`. Submits image(s) directly to the
  iNaturalist CV API (`POST https://api.inaturalist.org/v1/computervision/score_image`) and
  returns a canonical match object. Accepts a single file path, a character vector of paths,
  or a directory (all JPEG/PNG files non-recursively). `observation_id` = filename stem.
- Per-image EXIF extraction via `exifr` (Suggests): reads `GPSLatitude`, `GPSLongitude`,
  `GPSLatitudeRef`, `GPSLongitudeRef`, `DateTimeOriginal`/`CreateDate` when `lat`/`lng`/
  `observed_on` are NULL. User-supplied scalar args override EXIF and apply to all images.
- Path folder columns (`folder_1`, `folder_2`, ...): directory levels between the input base
  path and each image file are output as separate columns, enabling study design metadata
  (site/date/treatment folders) to flow downstream.
- Output is already in canonical match object format: `observation_id`, `taxon_name`,
  `taxon_name_rank`, `score_original` (= `combined_score`). Supplemental columns:
  `genus`, `common_name`, `iconic_taxon_name`, `taxon_id`, `n_observations` (from
  `taxon$observations_count` in the CV response — no extra API call needed),
  `vision_score`, `combined_score`, `freq_score`, `geo_prior_weight` (= combined/vision),
  `lat`, `lng`, `observed_on`.
- Downstream note: run `convert_taxonomy_backbone()` then `fill_higher_ranks()` before
  `join_priors()` — documented in `@details`. `family` column not populated (not in CV response).
- `httr`, `dplyr`, `tibble` added to DESCRIPTION Imports. `exifr` added to Suggests.
- Internal helpers: `.resolve_image_files()`, `.path_folder_components()`,
  `.extract_exif_info()`, `.parse_inat_cv_response()`.
- `devtools::check()`: 0 errors, 0 notes, 1 pre-existing warning (TaxaLikely cross-references).

**Session 115 (2026-06-22)**
- Bug fix: `.blast_submit()` used `!!!params` (rlang splice) in `httr2::req_body_form()` call.
  `rlang` is not in TaxaMatch Imports; without it `!!!params` evaluates as `!(!(!params))` →
  error on a list. Remote BLAST would always fail at submission. Fixed to
  `do.call(httr2::req_body_form, c(list(httr2::request(base_url)), params))`.
- `blast_sequences()` field-tested on 5 PtConception MiFish sequences (OQ84xxxx series,
  168-170 bp). All 5/5 top hits returned at 100% to correct species; score window, taxonomy
  resolution, and `standardize_match_data()` all confirmed working end-to-end. Runtime ~18s
  for 1 batch of 5 sequences.
  Test script: `inst/test_blast_remote.R`.
- `workflow_fastq_to_match.R`: `library(dada2)` commented out (optional; only needed for
  Step 0). `infer_exclude_predicted()` call added as Step 3b (Session 114 addition).
- Shared NCBI fetcher design decision: no `.ncbi_fetch_records()` abstraction pre-manuscript.
  The three NCBI use-cases differ fundamentally (blast_sequences is reverse: accession → taxid
  → lineage; fetch_reference_sequences and audit_barcode_coverage are forward: taxon → NCBI).
  Only shared piece is taxid→lineage resolution (~30 lines each). Consolidate into TaxaTools
  after manuscript review.
- `devtools::check()`: 0 errors, 0 notes, 1 pre-existing warning (cross-references to removed
  TaxaLikely functions from Session 97).

**Session 113 (2026-06-19)**
- `add_lowest_consistent_rank()` added to `R/taxonomy_consistency.R`. Strict mode
  (default): rank consistent when every non-blank candidate value is identical.
  New `majority_threshold` param (numeric in (0,1]): switches to majority mode where
  rank is consistent if top non-blank value accounts for ≥ threshold of non-blank
  candidates. Majority mode adds three columns: `rank_majority_value`,
  `rank_majority_fraction`, `is_rank_outlier`. `is_rank_outlier = TRUE` for rows whose
  value at `lowest_consistent_rank` differs from the majority value; NA/blank rows are
  FALSE (missing data, not a contradiction). Interaction filter pattern:
  `!(is_rank_outlier & lowest_consistent_rank %in% coarse_ranks)` — removes rows only
  when both conditions are true simultaneously. Note: `NA %in% c(...)` returns FALSE, so
  NA `lowest_consistent_rank` observations silently pass such filters.
  8 new majority-mode tests in `test-taxonomy_consistency.R`; 73/73 tests passing.
- `convert_taxonomy_backbone()` rewritten as vectorized implementation. Replaced
  O(N×K) row-by-row loop with `match()`-based index into `verified` table +
  `ifelse()` per column. Logical matrix for collision detection; `apply()` only on
  changed-row subset. `strsplit` called once per unique name (not once per rank × name).
  NA taxon_name rows now get NA backbone/collision columns (not `source_label`).
  Fixed `path[[idx]]` out-of-bounds when GNVerifier returns path/ranks vectors of
  unequal length: guard `|| idx > length(path)` added.
  `devtools::check()`: 0 errors, 0 warnings, 0 notes.

**Session 110 (2026-06-16)**
- `convert_taxonomy_backbone()` added to `R/convert_taxonomy_backbone.R`.
  Remaps rank columns (default: order, family, genus, species) from a source backbone
  to a target backbone via `verify_taxon_names()`. Per-column fallback: ranks the target
  backbone omits are left unchanged (no NA introduction). Adds `taxonomy_backbone` and
  `taxonomy_collision` diagnostic columns; sets `backbone_cols` R attribute + prints
  summary message. `update_taxon_name = TRUE` (default) cleans authority strings from
  accepted names and saves original to `taxon_name_original`. `verify_fn` parameter
  allows offline testing via dependency injection.
  `taxonomy_collision` values: `"consistent"`, `"backbone_N[col1,col2]"` (target applied,
  changed columns listed), `"backbone_N"` or `"original"` (not found in target).
  32 offline tests in `tests/testthat/test-convert_taxonomy_backbone.R`.
  NOTE: generic utility — should move to TaxaTools after manuscript review.
- `TaxaMatch-package.R` Standardization section updated.
- `devtools::check()`: 0 errors, 0 notes, 1 pre-existing warning (removed TaxaLikely
  cross-reference links from Session 97).
