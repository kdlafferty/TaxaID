# Handoff: the sample identity gate (`classify_sample_identity()` + `review_sample_identity()`)

Built 2026-09-28 from `CaliforniaIntertidal/REENTRY_PROMPT_sample_identity_gate_TaxaFlag.md`.

- **Branch:** `sample-identity-gate`, worktree `~/taxaid-worktrees/sample-identity-gate`.
  It is stacked on `flag-failed-libraries` (ca74d42), which it composes.
- **Not merged, not installed.** Two new exports: the release freeze needs the user's yes.
  `flag-failed-libraries` must merge first, or together with it.

## What it does

### `classify_sample_identity()`

For every unit (sample x marker x run, pooled over replicate libraries) it records two things:

- **LABEL:** blank or sample.
- **APPEARANCE:** `valid_blank`, `valid_sample`, `neither` or `unassessable`.

It then admits a unit only when the two agree, or when a person has recorded a decision.

**Order of operations.**

1. `flag_failed_libraries()` runs first.
2. `validate_controls()` then runs per run, on the libraries that yielded.
3. Nothing in either function is reimplemented.

**Signals.**

- **Composition.** This is `validate_controls()` at replicate level. A blank is sample-like
  when at least half of its assessable replicates are `RESEMBLES_SAMPLE`.
- **Effective diversity.** This is Hill N1 against the marker's reference, meaning the median
  over non-failed runs of the median field unit. Because the reference comes from outside the
  run, it is not circular. A blank at or above 0.5x the reference carries an environmental
  community.
- **Cross-marker agreement.** Reported as `n_markers_flagged` / `n_markers_assessable`.
- **Yield.** Taken from `flag_failed_libraries()`.

**Outcomes.** Four statuses: `concordant`, `discordant`, `suspect` and `unassessable`.

- `unassessable` is never merged with `concordant`.
- **Asymmetric policy (default).** An unassessable blank is held, because it would corrupt the
  control set. An unassessable sample is admitted with the flag carried through.
  `unassessable_policy = "block"` holds both.

**Two decision scopes (the peer's design).**

- **Identity** is per tube, across all markers:
  - `confirm_blank`
  - `confirm_sample`
  - `reassign_to_blank`
  - `reassign_to_sample`
  - `exclude_tube`

  An identity flag in any marker holds every marker of that tube (`tube_flagged`).
- **Library** is per unit: `exclude_library` or `keep_library`.

**Blocking.** Identity questions block the run (`pending_review`, and `on_pending = "error"` in
production). Library failures are excluded by default and do not block, because excluding is
already the conservative outcome and signing off 120 failed libraries is rubber-stamping.
`keep_library` reverses the exclusion.

**Decision record.** The CSV named by `decisions_path` is read, applied, and rewritten.

- User fields are never overwritten.
- `llm_` columns are carried forward.
- The status and appearance a person decided against are pinned (`status_at_decision`,
  `appearance_at_decision`). If the evidence later changes, the gate warns.
- An unknown disposition value, or conflicting identity dispositions for one tube, is an error.

**Runs.** Any run left with no admitted control warns by name (`attr(, "runs")$control_status`).

### `review_sample_identity()`

This is per-tube LLM advice on the held tubes. For each tube it sends:

- every marker's evidence;
- the tube's top taxa;
- the top taxa of that run's field samples;
- a required `context` string describing what a blank is in this study.

What it returns and how it behaves:

- The verdict is one of `clean_blank`, `contaminated_blank`, `sample_labelled_as_blank`,
  `blank_labelled_as_sample`, `valid_sample` or `uncertain`, plus a suggested disposition.
- It is advice only: nothing is admitted on it.
- Results are cached per tube, keyed on content, with a `_identity_review.rds` suffix, so
  `taxaflag_clear_cache()` prunes them.
- A tube the model omits is re-asked and never cached.

## Validation on CalIntertidal (`CaliforniaIntertidal/identity_gate_validation/`)

`build_rl.R` builds the input and `validate.R` runs the §8 checks. **All of the §8 checks pass:**

| §8 requirement | result |
|---|---|
| S067800 18S + COI flagged | discordant in both (`valid_sample` appearance), flagged in 2 of 2 markers, held |
| DWETWXWF, WCOFVUX2 12S flagged | discordant (composition, power ok) |
| JAC2V5IK 12S flagged | held through its tube: 12S itself sits just under the threshold (d 0.937 vs 0.932), but its 18S unit has 4.3x reference diversity |
| 18S JVB6164 (60) + JVB6334 (20) flagged | all 80 `suspect`, issue `library`, excluded |
| S067808 not flagged | concordant, admitted as a control (diversity 0.13x / 0.06x) |
| JVB5058, all 3 markers, not flagged | 66/66 concordant |
| 65 `low_yield` libraries (44 units) not flagged | 44/44 concordant |
| 18S JVB6164 blanks unassessable | 6/6 `unassessable`, not admitted |

- **Runtime:** about 1 minute on 644,041 rows. Most of it is `validate_controls()` across
  35 runs.
- **Review queue:** 225 units are held.
  - 120 are library failures, which are excluded but not pending.
  - 43 tubes await an identity decision (every marker of a flagged tube is held).
  - `"block"` and `"asymmetric"` give the same count here, because no sample is unassessable.
- **Runs with no admitted control:**
  - 18S JVB6164 and 18S JVB6334 (failed runs).
  - 12S JVB2844, whose only blank is S067800.

## Why diversity is needed: a structural limit of `validate_controls()`

`validate_controls()` asks whether a control resembles a FIELD SAMPLE. So it can only ever
detect contamination that came from the samples. A blank contaminated from any other source is
maximally unlike the samples, and so maximally "consistent_with_control". The Hill N1 axis is
orthogonal to that test and catches this case. (Framing from the CalIntertidal session.)

## Spike-ins (found during validation)

**12S spike-in, from Event 5 onward.** Starting with Event 5 (November 2024), JV adds a
`PositiveControl` spike-in to every 12S tube.

- **Spiked runs:** JVB5058, JVB5059, JVB5060, JVB5061, JVB6097, JVB6164 and JVB6334. Every field
  library carries the spike, and every blank is 97-100% spike.
- **Unspiked runs, Events 1-4:** JVB2844, JVB3105, JVB3506 and JVB3735. They carry no spike at all.

**What a spike does to a blank.** A template-free blank in a spiked run is almost entirely spike.
That is what a CLEAN blank looks like, not a positive control. Before this was understood, the
LLM called 14 such blanks positive controls, and the CalIntertidal session briefly read
4ES2CWOF and IJR811PZ as mislabelled. That was retracted.

**How the gate handles it.** `ubiquitous_fraction = 0.9` sets a feature aside before composition
and diversity when BOTH hold, judged per run x marker:

- it is in at least 90% of the run's field units, and
- it is the majority of reads in at least half of that run's blanks.

Both conditions are needed. Field prevalence alone also removed 22 genuinely common plankton
taxa on COI JVB3506 and flipped a `low_yield` sample to `discordant`. With both conditions the
rule selects exactly the seven spiked 12S runs. On JVB6097 it found the spike as `ESV_075708`
without using any name: that sequence is byte-identical to `PositiveControl`. The set-aside
features are listed in `runs$ubiquitous_taxa` and the LLM prompt.

**Beyond this gate.** The same trap applies to `flag_hopped_detections()` on spiked runs. The
CalIntertidal session has recorded it in `build_reads_long_hopflagged.R`.

## Other changes after first validation

- **`hold_reason`** is `own_evidence`, `tube` or `unassessable`. `identity_status` always
  describes the unit's own evidence, and `n_markers_flagged` never counts tube-held units.
- **`reassign_to_positive_control`** gives `admit_as = "positive_control"`. Such a tube is not
  counted as a negative control. The LLM verdict `positive_control_labelled_as_blank` goes with
  it.
- **Rebased** onto `flag-failed-libraries` ab41741, where a run can now fail on single-marker
  evidence. A test pins it: a single-marker failed run whose libraries read
  `low_yield_undetermined` is still caught, because the gate keys on `exclude_library` and
  `run_status`, never on `library_status == "failed"`.
- **Known limit, deferred on purpose:** a marker with fewer than 3 runs. There, the diversity
  reference comes from those same runs, so a sample-side low-diversity rule would be circular.
  What remains is the same-run blank-vs-field comparison, which `validate_controls()`'s
  `RESEMBLES_CONTROL` already covers.

## Validation-script bugs fixed (display names only; no gate verdict depended on them)

1. **Wrong source of names.** The scripts named ESVs from the first `esv_data` row. `esv_data`
   is a BLAST hit list, about 5.6 hits per ESV and up to 100; `read-data.csv` holds JV's single
   consensus row. This put a spurious *Trichoplax* in the 18S JVB3735 names and LLM rationales.
   `build_consensus_names.R` now reads the consensus.
2. **Missing names for JVB6097.** The batch key was cut from the file name, which broke on
   `JVB6097_filtered_Event10_*` files and left every JVB6097 ESV unnamed. The script now reports
   the true lookup gap, which is 0 for every run x marker. ESVs JV left unassigned are 27% of
   18S read rows and 18% of COI read rows; that is data, not a gap.

## Final live LLM review (`identity_gate_validation/llm_review.R`)

- **Setup:** Anthropic, `tubes_per_call` 2, `max_tokens` 8000. The CONTEXT string remains
  PROVISIONAL until Kevin describes the blank protocol.
- **Coverage:** 43 of 43 tubes answered.
- **Verdicts:**

  | verdict | tubes |
  |---|---|
  | `contaminated_blank` | 23 |
  | `clean_blank` | 8 (the spiked 18S JVB6164/JVB6334 blanks, including 4ES2CWOF and IJR811PZ) |
  | `sample_labelled_as_blank` | 5 (S067800 high confidence, DWETWXWF, WCOFVUX2) |
  | `uncertain` | 3 |
  | `valid_sample` | 2 |
  | `blank_labelled_as_sample` | 1 (NXD77NCP) |
  | `positive_control_labelled_as_blank` | 1 (BJL8UXKN, low confidence: 12S 100% *Rhinichthys*) |

- **Pattern for Kevin's protocol question:** JVB3735 blanks repeatedly carry FRESHWATER taxa,
  including *Rhinichthys*, *Etheostoma*, *Cottus*, *Oncorhynchus kisutch*, *Physella* and
  *Gonium*. That fits blanks filled from a freshwater source.

## New finding, not in the re-entry prompt

**18S JVB3735's blanks hold environmental marine protist communities**, and 24 of its 29
blanks are held:

- Diversity is 1.0-4.3x the 18S reference, 50-218 effective species. The taxa include
  ciliates, *Gambierdiscus*, *Pseudo-nitzschia*, *Oxyrrhis marina* and *Trichoplax*.
- Only 10-30% of their ESVs occur in that run's field samples, so this is **not index hopping**.
- `validate_controls()` calls every one of them `consistent_with_control` at full power. They
  are disjoint from the benthic samples, and the test reads disjoint as clean. This is the same
  blind spot as S067800, at 29x the scale.
- COI JVB3735 holds 11 blanks. 18S JVB3506 (3 of 3) and 18S JVB6097 (2 of 4) show the same
  pattern. These are exactly the runs `flag_failed_libraries()` reported as "collapsed control
  contrast".
- **A question for the user/JV:** was the Summer Field Expedition blank protocol different, for
  example bags rinsed in seawater? The gate cannot answer this. It holds these blanks so that a
  person does.

## Proposed wiring (the CalIntertidal session owns the workflow)

The gate goes at ingest, immediately after the `flag_failed_libraries()` call proposed in
`HANDOFF_library_failure_detector.md`. It must run before `make_esv_*_detections.R`,
`11_build_match_objects.R`, `flag_contaminant()` and `validate_controls()`:

```r
ff <- TaxaFlag::flag_failed_libraries(rl_all, library_col = "event_id", sample_col = "Barcode",
  marker_col = "marker", run_col = "batch", count_col = "n_reads", taxon_col = "ESVId",
  control_samples = CTL)
gate <- TaxaFlag::classify_sample_identity(rl_all, failed_libraries = ff,
  library_col = "event_id", sample_col = "Barcode", marker_col = "marker", run_col = "batch",
  count_col = "n_reads", taxon_col = "ESVId", taxon_label_col = "name", control_samples = CTL,
  decisions_path = file.path(OUT_DIR, "identity_decisions.csv"), on_pending = "error")
runs_gate <- attr(gate, "runs")            # report control_status in the output
rl_all   <- dplyr::filter(gate, admit)     # replaces filter(ff, !exclude_library)
CTL      <- unique(rl_all$Barcode[rl_all$admit_as == "control"])   # the control set from here on
```

Once, before the first gated run (optional):

```r
TaxaFlag::review_sample_identity(gate, context = CONTEXT, decisions_path = ..., cache_dir = ...)
```

Notes on the wiring:

- **`taxon_label_col`** needs a display-name column joined from `esv_data`. See
  `identity_gate_validation/validate.R` for the join (first row per marker x batch x ESVId).
- **Downstream control-set definitions** (`is_blank`) must switch to `admit_as == "control"`.
  Otherwise a reassigned tube keeps its old role.

## Merge notes

- **Stacked on `flag-failed-libraries`.** Merge that branch first, or merge this one, which
  contains it.
- **Conflicts with `flag-hopped-detections`, now on main.** It touches the same files as
  `flag-failed-libraries`: `inst/taxaflag_review_response.md` table rows and the helper count,
  and `R/TaxaFlag-package.R`. The helper count on this branch is 42 (30 + 12). Add hopping's 4.
- **TaxaWizard:** two new exports, learned from their formals after reinstall. The graph edge
  would be `reads_to_flagged` (the same edge as the other two).
- **Tests:** TaxaFlag 781 passed, 0 failed. `check()` 0/0/0.
