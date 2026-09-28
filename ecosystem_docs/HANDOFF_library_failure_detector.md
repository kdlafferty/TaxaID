# Handoff: `TaxaFlag::flag_failed_libraries()`: did each library and run actually sequence?

Built 2026-09-28 from `CaliforniaIntertidal/REENTRY_PROMPT_library_failure_detection_TaxaFlag.md`.
Branch `flag-failed-libraries` (worktree `~/taxaid-worktrees/flag-failed-libraries`), on
top of `main` 318517e. **Not merged, not installed.** It is a new export, so the release
freeze needs the user's yes before it goes to `main`.

## What it does

Takes the long reads table for **all markers at once** and gives a verdict for each
library (sample x marker x replicate column) and for each run (run x marker).

- **The test.** Depths are compared on a log10 scale. Each marker's reference depth is
  the median over runs of each run's median field-library depth. A library **fails**
  only when it is at least `fold_threshold` (default 10) below BOTH:
  - its marker's reference, and
  - its own sample's other markers (the cross-marker residual).

  Libraries that fail the first pass are dropped as predictors in a second pass.
- **Not failure.** A library that is low in every marker is `low_yield`: the sample
  itself is sparse, which is a finding, and the library is not excluded. A library whose
  sample has no other marker is `low_yield_undetermined`, because the function cannot
  tell failure from low biomass.
- **Two granularities.** A run is `failed` when at least 50% of its field libraries
  fail. That gives one run-level cause instead of 66 separate failures. The other run
  verdicts are:
  - `low_yield`: the run is low but there is no cross-marker support either way.
  - `pass`.
  - `not_testable`: the marker has fewer than 3 runs and no `reference_depth`, so the
    reference is the run itself. This is a separate outcome from `pass`.
- **Gate, never silent.** `exclude_library = TRUE` marks each failed library and every
  library of an uncleared failed run, controls included. A warning then says
  "DO NOT ANALYSE without review". `cleared_runs = "<run>|<marker>"` lifts the gate and
  keeps the verdict.
- **Controls.** Each run reports `control_richness_ratio` and `control_contrast`
  (`collapsed` at a ratio of 0.5 or more). This is reported only and never used to
  exclude anything.
- **Absence.** A sample with libraries in some markers of a run but none in another is
  listed in `attr(, "libraries_absent")`. It gets no verdict, because the table cannot
  say whether that library was ever made. Libraries known to exist go in
  `expected_libraries` and enter at depth 0.

## Validation on CalIntertidal (`CaliforniaIntertidal/failed_library_validation/`)

| run x marker | verdict | detail |
|---|---|---|
| 18S JVB6164 | **failed** | 60/60 libraries; median 568 reads, 60x below the 18S reference; controls collapsed (ratio 1.13) |
| 18S JVB6334 | **failed** | 20/20; median 1,011, 34x below |
| JVB5058, all 3 markers | pass | 0 failed |
| 12S/COI of JVB6164 and JVB6334 | pass | 0 failed; the same extracts sequenced fine |
| **12S JVB2844** | **low_yield** | not in the re-entry prompt; see below |

**Not flagging sparse but valid samples.** 65 libraries came out `low_yield` because
their samples are low in every marker. None of them are excluded.

**Scattered failures.** 194 individual libraries failed on healthy runs, most of them 12S
replicates:

| run | failed libraries |
|---|---|
| 12S JVB3506 | 95 |
| 12S JVB2844 | 36 |
| 12S JVB3105 | 35 |

These failed libraries have a median of 270 reads and a median richness of about 5.
**122 of the 194 have same-marker sibling replicates at least 10x deeper.** The detector
never looks at siblings, so this is independent confirmation that most of them are PCR
dropouts.

## New findings (not in the re-entry prompt)

1. **12S JVB2844 is a partly failed run.**
   - Median 2,947 reads against a 12S reference of about 42,000; a quarter of its
     libraries have fewer than 190 reads.
   - 15 samples that have 18S and COI libraries on this run have no 12S library at all.
   - COI on the same run is also low (median 2,842), so the detector will not call it
     failed. It returns `low_yield`, which is the honest answer.
   - Ask JV about this run alongside the 18S question.
2. **A collapsed control contrast is not unique to failed runs.** 18S JVB3735 (1.11),
   18S JVB3506 (0.98), 18S JVB2844 (0.56) and COI JVB3735 (0.84) sequenced normally but
   have blanks as rich as the field. This matches the hopping handoff's unexplained
   field-correlated blank reads. It is reported and never used to exclude.
3. **Libraries missing from a marker.** `reads_long` has no zero rows, so a library that
   sequenced nothing is invisible. Without a submission manifest, `libraries_absent` is
   as far as the table can go.

## Limits, stated in the roxygen

- **Narrow markers.** On a taxonomically narrow marker, `failed` means failed or target
  absent. For example, 12S in a sample with no vertebrate DNA looks exactly like a failed
  library. Agreement among the sample's same-marker replicates separates the two. The
  function does not use it (the 122/194 check above did it by hand).
  - **Option, not built:** add a sibling-replicate signal as a third deviation.
- **Positive controls** are not used; this dataset has none.

## Workflow wiring (the CalIntertidal session owns it)

Call this at ingest, on the combined three-marker `reads_long`. It must come before
`make_esv_*_detections.R`, `11_build_match_objects.R`, `flag_contaminant()` and
`validate_controls()`:

```r
rl_all <- dplyr::bind_rows(lapply(names(MARKERS), function(mk)
  pc_build_inputs(ARCHIVE_ROOT, marker = mk, crosswalk = CROSSWALK,
                  corrections = CORRECTIONS)$reads_long |>
    dplyr::mutate(marker = MARKERS[[mk]], is_blank = dplyr::coalesce(is_blank, FALSE))))
ff <- TaxaFlag::flag_failed_libraries(rl_all,
  library_col = "event_id", sample_col = "Barcode", marker_col = "marker",
  run_col = "batch", count_col = "n_reads", taxon_col = "ESVId",
  control_samples = unique(rl_all$Barcode[rl_all$is_blank | rl_all$is_lab_blank]))
rl_all <- dplyr::filter(ff, !exclude_library)   # and report attr(ff, "runs") in the output
```

Runtime is 1.4 s on 644,041 rows. Downstream summaries should state the exclusion,
e.g. "18S JVB6164/JVB6334 excluded: library failure".

## Merge notes

- `inst/taxaflag_review_response.md` and `R/TaxaFlag-package.R` are also edited by the
  unmerged `flag-hopped-detections` branch. Whichever branch merges second gets a small
  conflict:
  - the table rows are adjacent;
  - the helper count needs to become 34 (24 + 4 for hopping + 6 for this branch).
- TaxaWizard: new export, learned from formals and Rd after reinstall. A natural graph
  edge would be `reads_to_flagged` (the same edge proposed for hopping).
- Tests: `test-flag_failed_libraries.R` has 59 assertions. The full suite is 639/0 and
  `check()` is 0/0/0.
