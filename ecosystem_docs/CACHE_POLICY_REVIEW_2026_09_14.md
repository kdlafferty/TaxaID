# Cache policy review — measured findings and proposed policy

**Date: 2026-09-14. Status: policy DECIDED by the user 2026-09-14; nothing implemented yet (12S run active).** See Part 5 for the recorded decisions and Part 7 for what the multi-site question surfaced.
Answers `REENTRY_PROMPT_cache_policy_review.md`. Per that prompt's own
non-goals, no caching behaviour was changed in any function; this document
exists to get the policy decided in writing first.

All numbers below are measured on this machine today, not estimated.

---

## Part 1 — Three premises in the re-entry prompt are wrong

The prompt frames the reference fetch as "nothing cached". It is not. This
matters, because the fix it proposes follows from the wrong diagnosis.

### 1.1 The reference fetch is heavily cached, and always has been

`PtConceptionWorkflow_12S_single_site.R:1078` calls
`fetch_ncbi_reference_sequences()` **without `cache_dir`**, so it falls
through to the signature default at `TaxaLikely/R/fetch.R:720`,
`tools::R_user_dir("TaxaLikely", "cache")`. What 2026-07-13 deleted was the
*workflow-level* `reference_df`/`seq_matrix` `.rds` checkpoint. The
*function-level* per-taxon cache underneath it was never touched and has
been serving that step continuously.

Measured, from the last completed 12S run
(`PtConMifishSchulte_run_20260912_2200.log`, Step 7):

| | |
|---|---|
| taxa queried | 218 |
| **taxa served from cache** | **215** |
| taxa actually re-fetched | 0 (`"sequences after filtering"` appears 0 times) |

On disk: 3,516 cached `_meta.rds` files, 14 MB, in
`~/Library/Caches/org.R-project.R/R/TaxaLikely`. The 411 files matching the
current 12S parameter set were written 2026-08-29 to 2026-09-05.

### 1.2 The 12S workflow's stated invariant is false

The comment above that call says the caching was "removed rather than
patched with a staleness check, **so this step can never again silently
serve stale reference data**."

It serves stale reference data on every run. 215 of 218 genera in the last
run came off disk from files up to 16 days old, behind a bare
`file.exists()` gate (`TaxaLikely/R/fetch.R:1139`) with no TTL and no
`inputs` declaration. This is the exact footgun `TaxaID/CLAUDE.md` names
under Known R Footguns, live in the step whose comment claims immunity to
it. The 2026-07-13 response removed the visible, project-local, auditable
cache and left the invisible one running.

### 1.3 `.cache_ok(inputs=)` on the reference fetch would NOT have prevented the 2026-09-14 incident

This is the important one.

`fetch_ncbi_reference_sequences()` has three network phases. Only the middle
one is cached:

| phase | cost per run | cached? |
|---|---|---|
| 1. Count queries (`fetch.R:796`) | 1 `entrez_search` per taxon — **218** | **No.** Unconditional loop |
| 2. Per-taxon accession metadata (`fetch.R:1097`) | 1–2 calls per taxon | Yes — `file.exists()` gate, no TTL |
| 3. FASTA download (`.fetch_fasta_batched`) | **3,983 sequences**, batches of 200 | **No.** No cache of any kind |

The count loop runs **before** the cache check, for every taxon, whether or
not that taxon's payload is already on disk. An `NA` count sets
`retmax_cap` to 0, and the taxon is dropped before its cache file is ever
consulted.

So on 2026-09-14, all seven genera whose count query failed — Medialuna,
Zalophus, Tursiops, Symphurus, Apodichthys, Cymatogaster, Delphinus — **had
valid cached metadata sitting on disk, written 2026-08-29.** Verified file
by file. The run threw away data it already had, because an uncached
preliminary query failed.

That reclassifies the incident. It was not caused by too much caching
(2026-07-13) or by too little (the prompt's reading). It was caused by
**cache-bypass ordering: an uncached, network-dependent query gating a
cached payload.** No amount of `inputs=` declaration fixes that. Making
phase 1 cache-aware does.

---

## Part 2 — Findings

**F1. The largest cache in the ecosystem is the one nobody can see.**
`download_gbif_occurrences()` defaults to `R_user_dir("TaxaFetch")` and
**no workflow overrides it** — verified at all 7 call sites (12S:461,
18S:502, Mugu:432, CalIntertidal:459, GL:118 and :548, Template:269).
Those are the multi-GB GBIF zips behind the 23 GB and 17 GB incidents.
Meanwhile the workflows *do* define `CACHE_DIR_GBIF_GLOBAL <-
file.path(OUT_DIR, "cache_gbif_global")` and pass it to the small
downstream caches. The visibility is exactly inverted: kilobyte caches live
in the project, gigabyte caches live in a hidden directory.

Residue today in `~/Library/Caches/org.R-project.R/R/TaxaFetch`: 163 MB in
6 files, including a 122 MB `0002305-...zip.truncated_20260905` quarantine
file and a 0-byte zip. Nothing ever reaps these.

**F2. Every cache-key change silently orphans the previous generation.**
`fetch.R`'s key has accreted components, each added after a real staleness
crash (`barcode_term` Session 159, `rank_sfx2`, `oor_sfx2`, dates,
lengths) — each one correct. But nothing removes the superseded files.
`rank_sfx2` is appended unconditionally, so **1,584 of 3,516 files (45%)
lack `_rk-` and can never be hit again.** Only 1.2 MB here; the same
mechanism at GBIF-zip scale is the multi-GB incidents. Content-keying
without eviction does not replace a cache, it doubles it.

Visible in the key inventory: `12S_l100_5000_d` (432 files, dead) sits
beside `12S_l100_5000_d_rk-family-genus-species` (411, live), plus dead
`12S_l100_1200_d` (201) from the `max_len` widening.

**F3. `.cache_ok()` is not a primitive. It is copy-pasted into 3 scripts.**
Defined at `PtConception 12S:201`, `PtConception 18S:171`, and
`GreatLakes2023_ConsensusWorkflow.R:276`. All three are byte-identical
today — so there is no drift bug to fix yet, only the certainty of one.
It lives in no package, is exported by nothing, has no tests, and cannot be
called by the 26 package files that would benefit from it. The prompt calls
it "the right primitive the ecosystem already invented in September"; it is
better described as a good idea that never became a primitive.

**F4. Coverage of the clear functions is 4 of 7 caching packages.**
Five `<pkg>_clear_cache()` functions over the one shared engine
(`TaxaTools::report_and_clear_cache()`), as stated. But **TaxaMatch has
none**, despite four cache-taking functions defaulting to
`R_user_dir("TaxaMatch")` (`evaluate_reference_accessions`,
`investigate_flagged_accession`, `investigate_flagged_accessions`,
`review_flagged_accessions`). TaxaExpect has none and points its default at
*TaxaFetch's* directory (`generate_regional_proximity_evidence.R:243`) — a
cross-package default nobody would guess. Also
`taxatools_clear_cache(cache_dir)` takes no default while the other four
do.

**F5. The defaults and the practice already disagree.** 11 functions default
caching ON to a hidden directory. 11 parameters default to `NULL` (off).
There is no principle separating the two groups. At the workflow level the
practice is already almost exactly the policy the prompt proposes —
explicit `file.path(OUT_DIR, ...)` dirs everywhere — with the two
exceptions that matter most: `download_gbif_occurrences()` (F1) and the 12S
reference fetch (1.1).

**F6. The user's two worries are both real, and they are the same bug.**
"Fills up the hard drive" = F1 + F2: invisible location, no eviction.
"Hours of redundant processing" = 1.3: 218 count queries and a
3,983-sequence FASTA download re-run every time, around a cache that
already holds the answer. Both follow from caching decided per-function
rather than per-workflow.

**F7. Out of scope but worth knowing.** `~/Library/Caches/org.R-project.R/R`
totals 783 MB, of which **605 MB is `pkgcache`** — R's own package binary
cache, nothing to do with TaxaID. Worth not mistaking for ecosystem growth
next time the directory is inspected.

---

## Part 3 — The three questions, answered

**1. Does the user keep control?** No, less than the prompt assumes. Every
`cache_dir` is a parameter, so control is *available*; but the defaults put
the two biggest and most consequential caches (GBIF zips, reference
metadata) in a hidden directory, and both are reached by call sites that
pass no `cache_dir` at all. The analyst cannot see them from the project,
did not choose them, and — for TaxaMatch — has no function to clear them.

**2. Internal or external decision?** Agreed with the prompt's starting
position, with one correction. The *mechanism* inside the functions is
good: content-keyed per-file `.rds`, full key in the filename, and a
documented history of widening the key after each staleness crash. Keep it.
The *decision* should be the caller's. But `cache_dir = NULL` as the
uniform default is not sufficient on its own — 1.3 shows a function can
have a perfect cache and still redo the work, so the policy has to cover
**which phases of a function are cache-aware**, not only where the files
land.

**3. Should this be systematic?** Yes, and it should be smaller than the
prompt's candidate scope. Most of the value is in four changes, not a
26-file sweep.

---

## Part 4 — Proposed policy

Ordered by value per unit of risk. P1–P3 are the ones that pay.

**P1. An uncached query must never gate a cached payload.** In
`fetch_ncbi_reference_sequences()`, check each taxon's cache file *before*
its count query and skip the count entirely on a hit. This alone: removes
215 of 218 count queries per 12S run, removes the exposure that caused the
2026-09-14 incident, and makes `on_count_failure` a real failsafe instead
of a report. Adopt the rule ecosystem-wide as a review check.

**P2. Cache phase 3.** The FASTA download (3,983 sequences/run) is the
largest uncached cost in the step and is trivially content-keyed by
accession. Per-accession or per-batch `.rds` under the same `cache_dir`.

**P3. The big caches move into the project.** Change
`download_gbif_occurrences()`'s default to `NULL` and pass
`CACHE_DIR_GBIF_GLOBAL` at the 7 call sites — the constant already exists
in every one of those workflows. Same for the 12S reference fetch: pass
`CACHE_DIR_REF` explicitly, as Mugu (`:1191`) and CaliforniaIntertidal
(`:588`) already do. This is where the hard-drive worry actually lives.

**P4. `.cache_ok()` becomes `TaxaTools::cache_ok()`,** exported and tested,
and the three script copies call it. No behaviour change — the bodies are
identical today. Do this before they drift, not after.

**P5. Eviction on key change.** When a cache write finds files matching the
same `(taxon, barcode)` prefix but an older key shape, delete them. Turns
every future key widening from "doubles the cache" into "replaces it".
Cheap, and it is the actual fix for F2 and for the multi-GB incidents.

**P6. One `taxaid_cache_report()`** over the existing engine, summing all
seven package directories plus any project-local dirs it is pointed at, with
per-directory sizes and an age histogram. Reporting only. Plus the missing
`taxamatch_clear_cache()` (F4). Defer a size *budget* until the report has
run a few times — F7 shows the current picture is easy to misread.

### What I recommend against

- **A blanket `cache_dir = NULL` sweep across all 26 files.** The prompt
  proposes it; I think it buys little and risks a lot. 11 functions would
  change default behaviour at once, mid-project, and the workflows already
  pass explicit dirs nearly everywhere. Do P3's two genuine offenders
  instead and leave the rest alone.
- **Mandatory `inputs=` declaration on every cache.** Right idea, wrong
  reach. The per-taxon caches derive from NCBI, not from a local artifact,
  so they have no `inputs` to declare — their staleness axis is *time*, and
  the answer there is a TTL, which TaxaMatch already does for its
  row-level cache. Require `inputs=` only where a cache derives from a file
  the workflow itself writes (the GBIF/outlier/bbox chain, which already
  has it).
- **Re-caching `reference_df` at the workflow level right now.** It is
  already cached one layer down (1.1). Re-adding a workflow-level cache
  before P1/P2 would add a second staleness surface over the one that is
  actually misbehaving.

---

## Part 5 — Decisions needed from you

**DECIDED 2026-09-14:**

1. **P1 + P2 — BUILD BOTH.** (Subject to the multi-site question, answered
   in Part 7: no conflict.)
2. **P3 — move the GBIF zips into `OUT_DIR` per project.** Cost of losing
   cross-workflow sharing is near zero: the key already differs per site
   (`s6938816_g164` vs `s37994429_g217`), so no sharing exists to lose.
   Multi-site and single-site share one `OUT_DIR`, so they keep sharing.
3. **P5 — auto-evict small metadata `.rds`; report-and-confirm before
   deleting GBIF zips.**
4. **The false 12S comment (1.2) — correct it** once the run is done.
5. **TTL — report age loudly, no TTL.** No automatic re-fetch; staleness
   becomes visible at load instead. `.reuse()` already does this (Part 7).
6. **P7 — `.reuse()` gains `inputs=` and WARNS on stale, then proceeds.**
   Not a hard stop: a `stop()` in a reuse path is how caching got deleted
   outright in this project twice.
7. **Do NOT restore the single-site `reference_df` read yet.** Revisit after
   P1/P2 are in and measured; re-adding it now would stack a second
   staleness surface on the one actually misbehaving. The write at `:1113`
   stays, since multi-site depends on it.

### Additional bug found, to be fixed SEPARATELY from this policy

`.gbif_dl_meta_path()` (`download_gbif_occurrences.R:1221`) keys geometry as
**`nchar(geometry)`**, not its content. Editing a bbox coordinate from
`-122.385` to `-122.386` preserves the length: same key, cache hit, wrong
region's occurrences. GreatLakes and 12S are shielded by their own
workflow-level `.cache_ok()` gates; any other caller is exposed. Fix as a
standalone bug, per this review's non-goal of folding architecture into bug
fixes.

**Second key gap, found while factoring `.ref_cache_file()`, then CLOSED
(2026-09-14).** The key captures everything deciding which sequences are
*fetched*, but not everything deciding which are *kept*. The cached object
is written after blacklist filtering and after `slice_sample()` downsampling
(`fetch.R:1415`, `saveRDS()` at `:1443`), and **four** selection-shaping
inputs were absent from the key:

| input | in key? | direction of harm |
|---|---|---|
| `max_per_species` | no | **under-fill** — a cache built at 10 served to a call asking for 50 |
| `max_per_genus` | no | **under-fill** |
| `blacklist_regex` | no | **under-fill** if the blacklist is later narrowed |
| `retmax_cap` (from `max_sequences` / `min_per_taxon` / the other taxa's counts) | no | over-fill / inconsistency, not degradation |

Practical exposure was low — every production workflow passes
`max_per_species = 10L` and none sets `max_per_genus`, `blacklist_regex`,
`max_sequences` or `min_per_taxon` — but the class is exactly the one that
produced the `barcode_term` and `rank_system` crashes.

**Fixed without touching the key.** Widening the key would orphan all ~3,516
existing files at once (F2), the growth mechanism P5 exists to stop. So the
first three are now **stored inside the cached object** (`attr(meta,
"sel_params")`) and verified on read: a mismatch is a cache miss and the
taxon re-fetches; a legacy file with no attribute is accepted and reported,
since it genuinely cannot be verified. Nothing was orphaned, and the key is
still free for P5 to widen later.

`retmax_cap` is deliberately excluded from that check: it is not a caller
setting but a function of the whole taxa vector, so including it would
invalidate the cache on nearly every call. Note P1 does change it — cached
taxa no longer dilute the budget, so an uncached taxon now gets a *larger*
`retmax_cap` than before. That direction adds sequences rather than removing
them, so it cannot cause silent under-fill; it does mean a genus first
cached in a cold 222-taxon run holds fewer summaries than one added later to
a warm cache.

## Part 6 — Sequencing

Nothing here is implemented, and nothing should be until the 12S run
finishes: P1/P2 touch `TaxaLikely/R/fetch.R`, which that run will call at
Step 7, and installing a changed TaxaLikely mid-run is the corrupted
lazy-load hazard. The run has since passed Step 7, but still calls TaxaLikely later
(`audit_barcode_coverage()`, workflow `:1844`), so the lazy-load hazard is
NOT past and the no-install rule stands until the run ends.

Order once it is clear: **P4** (lift `.cache_ok()` into
`TaxaTools::cache_ok()`, pure move) → **P1** (cache check before count
query) → **P2** (FASTA cache) → **re-run 12S to measure** → **P7**
(`.reuse(inputs=)`, warn-only) → **P3** (GBIF zips to `OUT_DIR`) → **P5**
(eviction: auto for small, confirm for zips) → **P6** (`taxaid_cache_report()`
+ the missing `taxamatch_clear_cache()`) → **revisit the single-site
`reference_df` read** → correct the false 12S comment (1.2).

Separately and independently: the `nchar(geometry)` key bug above.



---

## Part 7 — Multi-site, and what it surfaced (added 2026-09-14, after Part 5)

Raised by the user: on a multi-site run where every site sits inside one
bounding box, do we do a single GBIF and NCBI search rather than one per
site?

**Yes — and by a stronger mechanism than the caches this review is about.**
`PtConceptionWorkflow_12S_multi_site_FAST.R` calls
`download_gbif_occurrences()` zero times and `fetch_ncbi_reference_sequences()`
zero times. It reuses the single-site run's checkpoints through `.reuse()`
(`:146`): `occurrences_clean`, `all_occurrences`, `bbox`, `reference_df`,
and ten more. One GBIF search and one NCBI search serve every site; the
per-site differences come from the priors fit, not from separate searches.
(The retired `PtConceptionWorkflow_12S_multi_site.R` did issue its own
searches — once for the whole run, still not per-site.)

Three consequences.

**7.1 P1/P2 do not touch the multi-site path.** They speed up the
single-site run that *produces* the checkpoints. Nothing to reconcile.

**7.2 The 2026-07-13 "removal" is doubly mis-described.** The single-site
workflow still **writes** `reference_df` at `:1113` — only the read-back was
removed — and `PtConMifishSchulte_reference_df.rds` (332 KB, written today
11:09) is a load-bearing dependency of the multi-site FAST workflow. So the
artifact exists, is current, and is already trusted by a downstream
workflow; it is simply never read by the run that creates it. Re-enabling
that read behind a staleness gate is a much smaller change than Part 1
implied.

**7.3 `.reuse()` is the real staleness gap — and it is where `inputs=`
belongs.** `.reuse()` is `file.exists()` → `stop()` or `readRDS()`, with no
validation. A multi-site FAST run will silently consume a `reference_df`
from an arbitrarily old single-site run: the exact 2026-07-13 Girella
failure mode, relocated into the multi-site path and never noticed. Unlike
the per-taxon NCBI caches, these checkpoints derive from **local files the
workflow itself writes**, so they have real `inputs` to declare. This is the
one place the re-entry prompt's mandatory-`inputs=` proposal is exactly
right, and Part 4 was wrong to give it no home.

Note `.reuse()` already prints each checkpoint's mtime and size on load —
it is already an implementation of "report age loudly, no TTL", which is
the policy chosen for the metadata cache in Part 5. Generalise that.

**P7 — DECIDED: build it, warn-and-continue.** `.reuse(tag, inputs = NULL)`
gains the staleness check and warns — not `stop()`s — when a checkpoint
predates its declared inputs, then uses it anyway. Warn rather than fail,
consistent with the Part 5 TTL decision and because a hard stop in a reuse
path is how caching got deleted outright in this project twice.

### Live confirmation (today's 12S run, Step 7 at log line 17314)

| | |
|---|---|
| taxa served from cache | **222** |
| count queries still issued | 222 (all of them; P1 would remove all 222) |
| count failures | **0** — the 2026-09-14 failures were transient, as suspected |


---

## Part 8 — Implementation status (2026-09-14, after the 12S run finished)

**Built, tested and installed: P4, P1, P2.** Branch `cache-policy-p1-p2`,
not committed.

| item | what changed |
|---|---|
| **P4** | `TaxaTools::cache_ok()` — exported, documented, 6 tests. Body byte-identical to the three script copies; they can now call it instead. |
| **P1** | `fetch.R`: new Step 0 serves every cached taxon before the count loop; cached taxa issue no count query, are excluded from the `max_sequences` budget (they fetch nothing), are reported as `cached (n rows)` rather than `error`, and are no longer mis-counted as count failures. The `total == 0L` early return is now guarded on `!any(is_cached)` — without that guard, an all-cached call would have returned an EMPTY reference_df. |
| **P2** | `.fetch_fasta_cached()`: one `.rds` per accession under `<cache_dir>/fasta/`, keyed on the versioned accession so a GenBank version bump re-downloads. |
| refactor | Both inline cache-key constructions replaced by `.ref_cache_file()`, verified to reproduce existing filenames byte-for-byte (`Abudefduf_12S_l100_5000_d_rk-family-genus-species_meta.rds`), so none of the 3,516 cached files were orphaned. |
| **selection guard** | `max_per_species` / `max_per_genus` / `blacklist_regex` recorded in `attr(meta, "sel_params")` and verified on read, on both the broad and priority paths. Mismatch = cache miss; legacy file = used, with a note. Closes the under-fill class without widening the key. |

**Tests.** TaxaLikely 1,213 pass / 0 fail / 0 error (baseline 1,190 —
+23 assertions, no new warnings). TaxaTools 938 pass / 0 fail / 0 error.
`test-fetch-cache-before-count.R` pins the 2026-09-14 incident directly (a
cached taxon survives when every count query throws), the audit trail (a
taxon that is neither cached nor counted is still named in
`count_failures`, while a cached taxon is not falsely reported), and the
selection-parameter guard (mismatch re-fetches, match reuses, legacy is
used with a note).

**Live check against the real 3,516-file cache** (Abudefduf, Medialuna,
Zalophus — two of them among the seven genera lost on 09-14):

```
Cache: 3 of 3 taxon/taxa served from disk (no count query issued).
  Age 15.7-15.7 days (oldest written 2026-08-29). No TTL by policy.
NCBI hit counts by taxon (0 total):
  Abudefduf: cached (77 row(s))    Medialuna: cached (3 row(s))
  Zalophus: cached (2 row(s))
82 sequences, 17 unique species     elapsed 1.4 s
```
Second run, exercising P2: `FASTA cache: 82 of 82 already on disk;
downloading 0` — 0.16 s.


### Validated on the real 12S run (2026-09-14, run finished 14:16 local)

The first full PtConception 12S run on the new code. No log captured Step 7
(the sink was lost when the header was re-run interactively), so this is
reconstructed from artifacts.

| | previous healthy runs | the 09-14 incident run | **this run** |
|---|---|---|---|
| taxa served from cache | 222 | 215 | **222** |
| count queries issued | 222 | 222 | **0** |
| count failures | 0 | **7** | **0** |
| reference_df | 4,061 seq / 1,104 spp | 3,983 / 1,087 | **4,061 / 1,104** |

So the incident cost 78 sequences and 17 species, and the new code
reproduces the healthy reference set exactly while removing the mechanism
that lost them: a cached taxon issues no count query, so it cannot be
dropped by a transient NCBI failure.

All seven genera lost on 09-14 are present with data: Medialuna 3, Zalophus
2, Tursiops 20, Symphurus 37, Apodichthys 5, Cymatogaster 7, Delphinus 4.

Cache state after the run: **0 meta files rewritten** (every taxon was a
hit), 3,516 meta files unchanged — nothing orphaned by the refactor — and a
new `fasta/` subdirectory holding 4,061 files, populated during this run
(12:31-13:03 local, ~32 min of downloading).

**Warm-cache cost of Step 7a, measured directly** on all 221 genera:

```
Cache: 220 of 221 taxon/taxa served from disk (no count query issued).
FASTA cache: 4,061 of 4,061 sequence(s) already on disk; downloading 0.
ELAPSED: 3 s      rows: 4061 | species: 1104 | failures: 0
```

~36 minutes to 3 seconds, identical output. The FASTA download (P2) was the
dominant remaining cost and is now paid once.

All 411 current-key 12S cache files are still `legacy` (no `sel_params`), so
the unverifiable-settings note will repeat on every run until those files
are rewritten. Expected: a cache hit never rewrites the file.

**Session 2 (2026-09-14, after the 12S run): P4 completed, P7, P3, P6 and
the geometry bug all built.** See Part 9.

---

## Part 9 - Session 2 implementation (2026-09-14)

| item | status | what |
|---|---|---|
| **P4** | **COMPLETE** | The three workflow copies of `.cache_ok` deleted; each is now `.cache_ok <- TaxaTools::cache_ok` (12S, 18S, GreatLakes). Call sites unchanged. |
| **P7** | **DONE** | `.reuse(tag, inputs = NULL)` in `PtConceptionWorkflow_12S_multi_site_FAST.R`, plus `.reuse_path()`. WARNS and continues, never stops. 9 dependency declarations wired from the producer's own `.save()` order. Adds a run-cohort check: a checkpoint >24 h older than the single-site `session_metadata` it is reused with is flagged as mixed vintage. |
| **P3** | **DONE** | All 6 `download_gbif_occurrences()` call sites now pass `cache_dir = CACHE_DIR_GBIF_GLOBAL` (12S, 18S, Mugu, CaliforniaIntertidal, GreatLakes, Template). The constant was added to the Template, which lacked it. Package default left alone deliberately - Part 4 recommends against a blanket `NULL` sweep. |
| **P6** | **DONE (report)** | `TaxaTools::taxaid_cache_report()` - scans all six package caches plus any `extra_dirs`, recursively (so TaxaLikely's `fasta/` counts), sorted by size, flags stores >= `warn_gb` and stores where file count dwarfs apparent size. Reports only; never deletes. 4 tests. |
| geometry bug | **FIXED** | `download_gbif_occurrences()` now records the full `geometry` in its cached metadata and verifies it on read; a mismatch is a cache MISS rather than a wrong-region hit. Key left unchanged (widening it would orphan every zip). Legacy entries warn. 3 tests. |
| 12S false comment | **CORRECTED** | The "can never again silently serve stale reference data" claim replaced with what actually happens, plus the measured 222/222 figure. |

**Tests after session 2:** TaxaTools 950 pass / 0 fail, TaxaFetch 784 pass /
2 fail (both pre-existing, `test-filter_gbif_quality.R`, CoordinateCleaner),
TaxaLikely 1,213 pass / 0 fail. All three packages reinstalled.

### Two findings from Part 2 / Part 8 were WRONG, and are withdrawn

- **TaxaMatch does not need a `clear_cache()` function.** Its cache is the
  row-level TTL'd shape (`reference_accession_cache.rds`,
  `reference_pair_cache.rds` - a few files holding many entries, 8-40 KB
  each). `cache_utils.R`'s own header already says that shape is out of
  scope for the shared engine, and clearing at file granularity would
  discard live rows. The absence is correct by design, not a gap.
- **TaxaExpect's "cross-package default nobody would guess" is correct.**
  `generate_regional_proximity_evidence()`'s `cache_dir` is documented as
  forwarded to the Stage 2 TaxaFetch call, so defaulting to TaxaFetch's
  cache is right.
- **`taxatools_clear_cache()` having no default is also correct.** It
  targets the `common_names` / `sampling_group` caches, which both default
  to `cache_dir = NULL`. TaxaTools' `R_user_dir` holds only
  `model_cache.json`, a different mechanism.

### Still open

**P5 (eviction)** is the only decided item not built - see
`REENTRY_PROMPT_cache_policy_P5_eviction.md`. Deliberately not done at the
end of a long session: it is the one piece that deletes files, and this
project's history with over-eager cache deletion is the reason this review
exists.

Also outstanding, all reported and none urgent:
- 163 MB in the hidden TaxaFetch cache is now unreferenced by any workflow
  (P3 moved them project-local). Includes a 122 MB `.truncated_20260905`
  quarantine file and a 0-byte zip. P5's job, or a manual
  `taxafetch_clear_cache()`.
- 1,584 of 3,516 TaxaLikely meta files (45%) lack `_rk-` and are
  provably unreachable. P5's clearest target.
- The `fasta/` store (4,061 files) has no eviction either.
- Legacy `sel_params` / legacy geometry notes repeat every run until those
  files are rewritten.
- Revisit the single-site `reference_df` read now that P1/P2 are measured.

---

## Part 10 - Session 3: P5 built, and the review closes (2026-09-14)

**P5 is implemented. Every decided item from Part 5 is now built.**
Branch `cache-policy-p1-p2`, still uncommitted.

### What eviction rests on

One claim, and it is a proof rather than a heuristic: **a cache file whose
name the current key construction cannot produce for ANY arguments can
never be hit again.** `rank_sfx` is appended unconditionally in
`.ref_cache_file()`, so no argument combination yields a name lacking
`_rk-`; that alone covers 1,584 of the 3,517 meta files on this machine.

That claim is expressed as a regular expression, `.ref_cache_grammar()`,
sitting next to `.ref_cache_file()` in `TaxaLikely/R/fetch.R`. The two are
pinned together by a test that generates names over a 288-cell grid of
argument combinations (taxon names with spaces and slashes, single- and
multi-term barcodes, both length windows, all three date configurations,
out-of-range on and off, both `rank_system` sets in live use, both
prefixes) and asserts every one matches. A future key widening that is not
mirrored in the grammar leaves the superseded generation on disk forever; a
grammar widened without the key would delete LIVE files. The test catches
the second, which is the dangerous direction.

Measured against the real cache, non-destructively:

```
taxalikely_evict_unreachable_cache: 1584 of 3517 reference-cache file(s)
  are unreachable (1933 still live).
  1584 file(s), 1.2 MB would be removed.
```

1,507 of the 1,584 have a live counterpart under the same taxon and barcode
- textbook supersession. The other 77 are taxa that have simply not been
queried under the current key (*Acinetobacter*, *Anabaena*, *Artemia* -
leftovers from a wider taxa vector); they are unreachable either way, since
a new query for them would produce a new name.

### What it deliberately does NOT evict

`12S_l100_600_d_rk-...` and `12S_l100_5000_d_rk-...` are different
**queries**, not successive generations, and a caller may legitimately want
both. The same is true of two different `rank_system` sets, and both are in
live use here: `_rk-family-genus-species` (1,393 files, 12S/18S) and
`_rk-kingdom-phylum-class-order-family-genus-species` (540, GreatLakes
MiFishU). Only an unproducible SHAPE is evictable; a differing VALUE never
is. A test pins this too.

### What was built

| | |
|---|---|
| `TaxaLikely:::.ref_cache_grammar()` | The proof, as a regex. Kept beside `.ref_cache_file()`; lockstep enforced by test. |
| `TaxaLikely:::.ref_cache_stem()` / `.ref_cache_stem_of()` | Taxon+barcode identity, built forward and parsed back right-to-left. Scopes eviction to one taxon WITHOUT prefix matching, which would let `Abudefduf_` also claim `Abudefduf_saxatilis_`. Pinned by a round-trip test. |
| `fetch_ncbi_reference_sequences(evict_unreachable_cache = TRUE)` | Automatic eviction, on the WRITE path only, scoped to the taxon just rewritten, capped at 5 MB per file, and it says what it removed. Wired into both the broad and priority write sites. |
| `TaxaLikely::taxalikely_evict_unreachable_cache()` | The whole-store sweep. **`dry_run = TRUE` by default**, unlike every sibling `<pkg>_clear_cache()`: those are told what to delete, this one decides for itself, so it shows you first. `max_file_mb = 5` reports and spares anything large, per Part 5 decision 3. |

### Two gaps found while building it, both fixed

- **P2's `fasta/` store was invisible to every clear function.**
  `TaxaTools::list_cache_files()` was non-recursive, and
  `.taxalikely_cache_patterns` had no `_seq\.rds$` entry, so the 4,061
  files P2 added could not be reached by `taxalikely_clear_cache()` at all.
  `list_cache_files()` gains `recursive = FALSE` (default preserves every
  existing caller) and now also drops directories, which the old code would
  have handed to `file.remove()` if one ever matched a pattern.
- **A 122 MB quarantined download was invisible for the same reason.**
  `0002305-...zip.truncated_20260905` - 75% of TaxaFetch's cache - matched
  no pattern, because the pattern was `\.zip$` and the file ends in
  `.truncated_20260905`. TaxaFetch now recognises zip SIDECARS (`X.zip.*`)
  and, since metadata only ever names `X.zip`, treats them as orphans by
  construction. `taxafetch_clear_cache(orphans_only = TRUE)` now reaches it.

### The false comment in `taxalikely_clear_cache.R`, corrected

That file claimed "there is no known duplicate/orphan-accumulation
mechanism here (each query maps to exactly one deterministic file, with no
overwrite concept to leave a stale copy behind)". Wrong, and it is the
same class of error as the 12S comment corrected in Part 9. The
accumulation mechanism is not overwriting, it is key widening, and it had
already produced 45% waste when that sentence was being read as reassurance.

### Decision recorded: the single-site `reference_df` read stays CLOSED

Part 5 decision 7 deferred this until P1/P2 were measured. They are, and
the measurement settles it: warm Step 7a runs in **3 seconds** (221 genera,
identical output, down from ~36 minutes). A workflow-level `reference_df`
cache can therefore save **under three seconds**, against adding a second
staleness surface over the one that just cost a two-day investigation. **Do
not build it.** Do not re-open it a fourth time.

The WRITE at `PtConceptionWorkflow_12S_single_site.R:1113` stays regardless:
`PtConceptionWorkflow_12S_multi_site_FAST.R` depends on that file through
`.reuse()`, which since Part 9 declares its `inputs` and warns on stale.

### Tests

| package | before P5 | after P5 |
|---|---|---|
| TaxaTools | 950 / 0 fail | **992 / 0 fail** |
| TaxaLikely | 1,213 / 0 fail | **1,256 / 0 fail** |
| TaxaFetch | 784 / 2 fail | **810 / 2 fail** |

TaxaFetch's 2 failures are the same pre-existing CoordinateCleaner ones in
`test-filter_gbif_quality.R`, unrelated to any cache work. All three
packages reinstalled; `taxalikely_evict_unreachable_cache` verified present
in `getNamespaceExports("TaxaLikely")` (the Part 9 unexported-helper trap).

### Nothing has been deleted

The 1,584 unreachable files and the 163 MB TaxaFetch store are still on
disk. `taxalikely_evict_unreachable_cache()` defaults to a dry run and the
zips need an explicit call, exactly as decided. Running them is the user's
call.

### One finding this raised, NOT part of P5 -- FIXED, see Part 11

**The `fasta/` cache key is not versioned, and its documentation says it
is.** `.fetch_fasta_cached()`'s roxygen states it is "keyed on the FULL
accession including its version suffix, so a GenBank version bump misses
the cache and re-downloads rather than serving a superseded sequence."
It is not. The accessions it receives come from `combined_meta$acc`, which
is populated from ESummary's `caption` field (`fetch.R:217`) - and
`caption` is the accession WITHOUT its version; the versioned field is
`accessionversion`. Confirmed on disk: 0 of the 4,061 cached files carry a
version suffix (`AB000667_seq.rds`, and its stored `composite_id` is
`"AB000667"`). The 34 filenames that look versioned are RefSeq `XM_`
prefixes.

Consequence: a GenBank version bump is a cache HIT, and the superseded
sequence is served indefinitely, since nothing in that store expires. The
`sub("\\.[0-9]+$", "", ...)` calls at `:1680` and inside
`.fetch_fasta_cached()` are no-ops that made the gap invisible.

This is a decision, not a bug fix, and it belongs to the user:
switching the key to `accessionversion` would orphan all 4,061 files at
once - which P5 now handles, but only if the eviction grammar is extended
to the fasta store, which today it deliberately is not. Doing nothing is
also defensible: reference sequence records are revised rarely, and the
cache can be dropped wholesale with `taxalikely_clear_cache()` now that it
can see the store at all. **What must not stand is the comment**, which
currently tells the next reader that a staleness axis is closed when it is
open.

---

## Part 11 - The `fasta/` cache key is now versioned (2026-09-14)

The user's reaction to the Part 10 finding was the right one: *"it was
carefully constructed, so I am surprised there is an error."* It WAS
carefully constructed -- and re-checking from source confirmed the
construction is correct in every part except its input.

### Re-verified before changing anything

| claim | how checked | result |
|---|---|---|
| `caption` is unversioned, `accessionversion` is versioned | live `rentrez::entrez_summary()` | `caption=AB000667`, `accessionversion=AB000667.1`. Both on the SAME batched call, like `create_date` -- zero extra round trips. |
| `entrez_fetch()` accepts a versioned id | live, versioned vs unversioned side by side | Identical records returned. |
| FASTA headers carry the version regardless | live | Always `>AB000667.1 ...`, even when asked unversioned. |
| A non-existent version errors | live, `AB000667.99` | No -- returns 0 records. So it lands on the existing "not written, retried next run" path. |
| The parser/write-back were built for versioned input | source | Yes. `.parse_fasta_text()` strips versions from headers, and the write-back maps stripped ids back to the requested string (`stripped <- sub(...)`). Both are no-ops on unversioned input, which is exactly why this stayed invisible. |

So the machinery was right and only the input was wrong. That is why nothing
downstream had to move.

### What actually changed

- **`.fetch_summaries_batched()` gains `acc_version`** from
  `x$accessionversion`, NA-safe like every other field.
- **`acc` deliberately STAYS unversioned.** Three things depend on that, and
  all three were traced before deciding: `composite_id` is derived from it
  (`sub("\\.[0-9]+$", "", acc)`); `.fetch_locations_batched()` returns
  `GBSeq_primary-accession`, which carries no version, and is merged on
  `composite_id`; and the accession dedupe (`!duplicated(combined_meta$acc)`)
  relies on unversioned values to collapse two revisions of one record.
- **New `.fasta_cache_keys(meta)`** coalesces `acc_version` over `acc` PER
  ROW and reports how many rows fell back. The call site keys AND requests
  that same string, so the record NCBI returns is the record the key names.

### Why the legacy fallback is not a half-fix

A meta file written before `acc_version` existed cannot supply a version --
and cannot NOTICE one either. Its accession list is frozen at the moment it
was cached, so no GenBank revision is visible from it in the first place.

The threat is precisely: *metadata refreshed, sequence stale.* With an
unversioned key that is a cache HIT and the superseded sequence is served
under the new metadata. The protection therefore has to engage exactly when
a revision first becomes detectable -- the re-fetch that rewrites the meta --
and that is when `acc_version` appears. A cache key should be exactly as
fresh as the metadata it derives from. Falling back to `acc` for a
cache-served taxon is that, not a gap.

This is also why **no meta cache key was widened and nothing was orphaned**.
Widening it to carry versions would have re-fetched all 222 taxa from NCBI to
fix a staleness axis those taxa cannot currently observe.

### Cost, stated plainly

A taxon that is re-fetched after this change will re-download its sequences
once, because its new versioned keys miss the existing unversioned files
(~32 min for a full cold 12S run, and only for taxa actually re-fetched --
with every meta currently cached, that is close to nothing today). Serving
the old file under a versioned key was considered and rejected: it is the
exact bug this fixes. The superseded files stay on disk and are removable
with `taxalikely_clear_cache()`, which since Part 10 can finally see that
store.

### Tests: 27 new assertions, `test-fetch-fasta-versioned-key.R`

The load-bearing one is **"a versioned key does NOT hit a legacy unversioned
file"** -- if that ever starts passing by hitting the old file, the fix is
silently undone. Also pinned: per-row coalescing (the real
`dplyr::bind_rows()` shape when a legacy meta and a fresh one are combined);
an unversioned key still hitting its unversioned file, so the existing store
is not quietly invalidated; `composite_id` staying version-stripped; the
stripped-header-to-versioned-key write-back; and that a RefSeq `XM_` prefix
cannot collide with a version suffix (those 34 "versioned-looking" files).

`.fetch_summaries_batched()` is tested against a REAL recorded ESummary
record captured live this session.

**TaxaLikely 1,283 pass / 0 fail** (was 1,256). `devtools::check()` 0/0/0,
reinstalled.

### Not done: a live end-to-end run

Attempted three times and abandoned, not because of this code: NCBI began
returning HTTP 500s and then the `"subscript out of bounds"` throttling
signature this codebase documents. Given this project's history of multi-day
NCBI blocks, hammering it further was the wrong trade. The two facts that
genuinely needed live confirmation -- the ESummary field values and
`entrez_fetch()`'s handling of versioned ids -- were both obtained live
earlier in the session, before the throttling began. **A cold
`fetch_ncbi_reference_sequences()` run against a throwaway `cache_dir`,
confirming versioned filenames appear in `fasta/`, is still worth doing when
NCBI is healthy.**
