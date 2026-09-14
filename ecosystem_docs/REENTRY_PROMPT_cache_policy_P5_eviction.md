# Cache policy P5 — eviction: BUILT 2026-09-14. This file is now the
# open-items list, not a work order.

**Every decided item from `CACHE_POLICY_REVIEW_2026_09_14.md` Part 5 is
implemented.** P5 landed in session 3; read **Part 10** of that review for
what was built, what it deliberately does not touch, and why.

## State of the tree

- Branch **`cache-policy-p1-p2`**, **UNCOMMITTED**. P1, P2, P3, P4, P5, P6,
  P7, the GBIF geometry fix and the two gaps P5 turned up are all in the
  working tree. Ask before committing; the user has not requested it.
- Packages changed and reinstalled: **TaxaTools**, **TaxaLikely**,
  **TaxaFetch**.
- **Test baselines.** TaxaTools 992 / 0 fail. TaxaLikely 1,256 / 0.
  **TaxaFetch 810 / 2 FAIL, and those 2 are PRE-EXISTING** in
  `test-filter_gbif_quality.R` (CoordinateCleaner, unrelated to cache work).
  Do not spend time on them thinking you broke something.
- Reinstall with `devtools::install("<pkg>", quick = TRUE, upgrade = FALSE)`
  — `upgrade = FALSE`, not `"never"`, which this devtools rejects.

## Open — decisions for the user, not tasks to start

**1. Nothing has actually been deleted yet.** By design: the sweep defaults
to a dry run and the zips need an explicit call. The two commands, when the
user wants them:

```r
TaxaLikely::taxalikely_evict_unreachable_cache(dry_run = FALSE)   # 1,584 files, 1.2 MB
TaxaFetch::taxafetch_clear_cache(orphans_only = TRUE, dry_run = TRUE)  # look first
```

The second now sees the 122 MB `.truncated_20260905` quarantine file and the
0-byte zip, which no clear function could reach before. Check the dry run
before dropping `dry_run`. **Do not clear anything while a workflow is
running.**

**2. The `fasta/` key — FIXED, see Part 11.** It now keys (and requests) the
versioned accession via a new `acc_version` column and `.fasta_cache_keys()`.
No meta key was widened and nothing was orphaned: a meta file cached before
`acc_version` existed cannot see a GenBank revision anyway, so it correctly
falls back to the bare accession and is reported. **What remains: a live
end-to-end run.** NCBI began returning 500s and then its throttling signature
mid-session, so a cold `fetch_ncbi_reference_sequences()` against a throwaway
`cache_dir` — confirming versioned filenames land in `fasta/` — was not run.
Worth doing when NCBI is healthy.

**3. Legacy notes that repeat on every run.** The `sel_params` note
(TaxaLikely) and the geometry note (TaxaFetch) fire until those files are
rewritten. A backfill or a verified-stamp pass would end them; doing nothing
is also defensible.

## Closed — do not re-open

- **The single-site `reference_df` read: CLOSED, do not build it.** Decided
  in Part 10 on the measurement Part 5 decision 7 was waiting for: warm
  Step 7a is 3 seconds, so the entire available win is under three seconds
  against a second staleness surface. This is the fourth time the question
  has come up; it is now answered. The WRITE at `12S:1113` stays regardless
  — multi-site FAST depends on it via `.reuse()`.
- **TaxaMatch has no `clear_cache()`, and should not.** Row-level and
  TTL'd; clearing at file granularity would discard live rows. P5's
  eviction never treats its directories as file-per-key.
- **TaxaExpect defaulting `cache_dir` to `R_user_dir("TaxaFetch", ...)` is
  correct**, and **`taxatools_clear_cache()` having no default `cache_dir`
  is correct.** Both were checked against what they are FOR. See Part 9.

## Two traps worth carrying forward

- **Keep `.ref_cache_grammar()` in lockstep with `.ref_cache_file()`.** A
  widening mirrored in the grammar but not the key would delete LIVE files.
  `test-fetch-cache-eviction.R` generates names over a 288-cell argument
  grid and asserts every one matches. If that test fails after a key
  change, update the grammar in the same change — never relax the test.
- **An exported function can ship unexported.** A helper placed between a
  roxygen block and its `function` definition steals the `@export`, and
  `devtools::document()` says nothing. Put internal helpers ABOVE the
  documented function's roxygen block, and verify after installing:
  `"your_fn" %in% getNamespaceExports("TaxaLikely")`.
