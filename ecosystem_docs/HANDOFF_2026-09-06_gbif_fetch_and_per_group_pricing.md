# HANDOFF: GBIF-fetch hardening + per-group curve pricing

Written 2026-09-06 (Opus 5, `main`). Purpose: consolidate this thread into the
chat you are now in, so fewer sessions run in parallel. Everything below is
either COMMITTED, or explicitly NOT DONE with a reason.

Read `ecosystem_docs/REENTRY_PROMPT_kernel_budget_pricing_and_scope.md` (its two
closing UPDATE sections) for the pricing side.

## Commits from this thread (all on `main`, all `check()` 0/0/0)

| commit | what |
|---|---|
| `e287e1b` | PtCon 18S per-group budget diagnostic; `kernel_budget_sensitivity()`; f1/f2 printed beside every budget figure |
| `7ac6d26` | diagnostic: absolute output path |
| `f7b2d82` | **per-group curve pricing, with guards** |
| `929d857` | **GBIF fetch: download integrity, non-blocking prompts, outlier scoping, zip retention** |
| `cd88846` | `download_gbif_occurrences(geometry = NULL)` for a global download |

TaxaExpect 1018 tests / TaxaFetch 740 (2 pre-existing CoordinateCleaner
environment failures in `filter_gbif_quality`, unrelated to any of this).

## What is DONE

**Per-group curve pricing** (`f7b2d82`). `apply_undetected_evidence(pricing =
"curve")` accepts a multi-group kernel fit and prices each taxon at its own
sampling group's Good-Turing budget. Justified by a measured 1859x spread across
groups (441x among groups the assay can amplify), where the single pooled price
sits BELOW all seven priced groups. Three guards, all of which fire on real 18S
data: support (`min_group_n_eff`/`min_group_f1`), a singleton cap (binds exactly
when `f1 < 2*f2`), and a group-wise `pooled_qualifying` fallback. Group
assignment is NEVER inferred from taxonomy -- an unassigned taxon errors.
**Single-group fits are byte-identical** (verified old-vs-new on the real
GreatLakes checkpoint, max |delta| = 0), so the Lamar validation stands.

**GBIF fetch hardening** (`929d857`, `cd88846`), all from real failures in one
overnight run:
* a truncated download was cached as complete (127,733,417 of 130,577,434
  declared bytes) and then failed on every re-run. Now verified before caching,
  with one retry; cache hits verified and self-healing; extraction warning
  promoted to error; the cosmetic cache report can no longer discard the data.
* `utils::menu()` consumed ~600 lines of a sourced workflow as menu answers,
  silently swallowing them so they never executed. **`allow_prompts = FALSE` is
  now the default and NOTHING in `download_gbif_occurrences()` blocks.** Do not
  add a blocking prompt to any function called mid-workflow -- `interactive()`
  cannot tell a human from RStudio pumping queued lines. Same hazard is already
  documented for `readline()` in `TaxaMatch::group_observations_by_bbox()`.
* `check_geographic_outliers()` swept a family-derived pool and earned a GBIF
  rate-limit block at 360/829 keys. New `candidate_taxa`/`candidate_scope`
  (default `"genus"`, keeps congeners); routed through `get_gbif_occurrences()`
  for the backend switch; verdicts cached instead of the raw global cloud; the
  inherited `limit = 10000` truncation of the reference cloud removed.
* `keep_zip` + `taxafetch_clear_cache(zips_only = TRUE)`: 38 zips = 17.0 GB
  against 52 MB for every other cache file combined.

**Five workflow files edited** (outside the repo, not under git; backups
alongside each): the three PtConception + two Mugu workflows all now pass
`candidate_taxa`/`candidate_scope`, all had `overwrite = TRUE` removed from
their GBIF call, and the 18S one gained the fish-grouping fix, a
`REVIEW_INSTITUTION_FLAGS` switch, `GBIF_LIMIT <- NULL`, and
`source(18S_stuff/filter18S_marine.R)`.

## What is NOT done, in priority order

**1. Per-group pricing has never actually run on real data.** The 2026-09-06 18S
run completed (140 min, 11,330 observations, 204 final taxa) but the priors have
NO `pricing_basis` column: the watch block is gated on
`intersect(INVASIVE_TAXA, match_list_taxa_18s)`, and `INVASIVE_TAXA` is a NAS
**marine fish** list that does not intersect an 18S match list. So
`apply_undetected_evidence(pricing = "curve")` was never called. The feature is
correct on the numbers and byte-identical where it is a no-op, but it has not
yet changed a real answer. **This is the single most important open item.**

**2. The 18S occurrence pool lost ~99.9% of its fish, and I probably caused it.**

| | June checkpoint | 2026-09-06 run |
|---|---|---|
| records | 2,185,193 | 1,375,345 |
| Chordata records | 486,786 | **547** |
| Chordata families | 84 | 13 |

Only 3 of June's 84 fish families survive into this run's `match_obj` family
list; the dropped ones are the abundant California taxa (Clupeidae, Carangidae,
Myctophidae, Scombridae, Paralichthyidae, ...). The likely cause is the
`source(file.path(OUT_DIR, "18S_stuff", "filter18S_marine.R"))` line I added at
the top of Step 1 at the user's request. Before it, the function did not exist
in a clean session (the script died at line 235 with "could not find function
filter18S_marine"), so that filter had NEVER run end to end -- adding the source
made a previously dead filter live for the first time. Its vertebrate clause is
explicitly commented out (line 67), so it is not removing fish deliberately;
suspect the `!phylum %in% c("unk_phylum", "")` clause interacting with GBIF's
sparse backbone. NOT diagnosed further. This matters because the `fishes`
sampling group is now 11 taxa / n_eff 90.6 (vs 300 / 54,441 in the diagnostic),
so `WATCH_SAMPLING_GROUP <- "fishes"` would price against 3 singletons.

**3. Axis-1 reads 10,053 `unprecedented` of 11,330 (89%)**, against 855
`expected`. Same shape as the documented 873/885 inversion from the kernel
migration, which was a `model_tier`/`prior_branch` reading bug. May be
legitimate for a broad marker against a fish-depleted pool. Not investigated.

**4. Reclaim 17 GB.** `TaxaFetch::taxafetch_clear_cache(zips_only = TRUE,
dry_run = TRUE)` -> 38 zips, 16.7 GB; everything else 51 MB. Safe now that the
18S run is finished. Metadata is kept, so each query's download key stays
re-fetchable with no new GBIF request.

**5. Generalize the integrity fix (asked for, not built).** Only two binary
download paths exist: the GBIF zip (fixed) and `download_literature_pdfs()`,
which validates the `%PDF` header but not the tail -- so a truncated PDF passes
exactly as the truncated zip did. Separately, **9 caches across 8 files gate
reuse on `file.exists()` alone**. The right general mechanism is an ATOMIC WRITE
helper in TaxaTools (write `<path>.part`, verify, `file.rename()`) -- prevention
rather than detection. See `[[project_cache_integrity_and_cleanup_todo]]`.

**6. `taxamatch_clear_cache()` does not exist** (the user thought it did;
`migrate_reference_cache()` is the function they were remembering). Not a
copy-paste job: TaxaMatch's caches are ONE consolidated `.rds` per directory,
not the file-per-key shape `TaxaTools::list_cache_files()` is built for, so a
naive clear would delete an entire reference screen. Wants two functions: a
file-shaped `taxamatch_clear_cache()` (migration `.bak_*` files, orphans) and a
row-level `taxamatch_prune_cache()` keyed on TTL / retired `params_key`.

## Deliberately REJECTED -- do not rebuild

A GBIF density-tile pre-screen for `check_geographic_outliers()`. The tiles are
alpha-channel presence/absence only ("not a decoded density value"),
`cc_outl()` needs real coordinates, and a pre-screen's job is to SKIP the real
test -- an unvalidated skip risks false negatives on exactly the
misidentifications the check exists to catch. Candidate scoping already removed
the bottleneck.

Also still open and untouched from the pricing thread: decision #1 (switch the
price to `mass/f1`) and decision #3 (singleton theta as a DISTRIBUTION rather
than a scalar). Both have standing evidence; neither was touched.

## In-flight work by OTHER sessions (uncommitted, do not clobber)

At the time of writing the tree has uncommitted changes in TaxaAssign (5 R
files), TaxaFlag (3), TaxaLikely (2 + NAMESPACE), TaxaMatch (2 + NAMESPACE),
TaxaExpect (2), plus several `CLAUDE.md` files. None of it is mine -- my work is
fully committed and TaxaFetch is clean. Establish what those are before
committing anything broad.
