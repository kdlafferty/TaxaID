# Handoff: `TaxaFlag::flag_hopped_detections()` (index hopping / read spillover)

Built 2026-09-27 from `CaliforniaIntertidal/REENTRY_PROMPT_index_hopping_TaxaFlag.md`.
Branch `flag-hopped-detections` (worktree `~/taxaid-worktrees/flag-hopped-detections`),
Merged to `main` 2026-09-28 at the user's direction. **Not installed**; the package-review session holds the reinstall gate.

## What it does

Flags individual detections (feature x sample) whose reads are no more than the
spillover expected from the same feature elsewhere on the same run:
`E = r * source * share`, with `share = 1/(n-1)` by default. `r` is estimated per run
from a non-native spike (preferred) or from negative controls. It flags, never
deletes, using the unified validity schema (`invalid_index_hop` /
`questionable_index_hop` / `valid` / `NA` = not assessed).

## Headline

Every candidate hopping signal failed on shape or magnitude once examined. JVB3105
has zero blank reads where hopping predicts thousands. JVB2844 has 26x too many
reads to be hopping. JVB3735 has the right total but the wrong distribution: three
of the ten largest ESVs appear in no blank, and one blank holds 24% of the run's
blank reads. The CalIntertidal session reproduced this independently.

So the filter finds almost nothing to remove in this dataset, which is a real
result. The function should matter on runs where hopping actually operates
(patterned-flow-cell ExAmp chemistry without unique dual indexes).

## Corrections to the re-entry prompt

1. **Event != run.** JVB6097 spans Event10 and Event11. `hop_rate.R` split it by
   file. Ingest's `reads_long$batch` is already the correct run key.
2. **No diffuse index hopping is detectable in this dataset.** 12S run JVB3105: the
   ten biggest ESVs (median 1.9M reads) appear in 0 of 9 blanks, where 0.1% hopping
   predicts about 4 reads in each blank. Most runs come out `bound_only` with
   `r_upper` around 1e-5.
3. **The blank reads on JVB3735/JVB2844/JVB3506 are contamination of the blanks, not
   hopping.** They imply rates of 7-57%, far above anything demultiplexing produces
   (hopping 0.1-2%, up to about 6%; tag jumps about 2%). Those runs are
   `implausible_rate` and not assessed. Projecting them would have flagged 16% of 18S
   detections.
4. ***Acanthurus xanthopterus* is not spillover.** Its whole source on a run is at most
   2,400 reads, spread over dozens of samples. It is a misassignment problem.
5. **The prompt's flat and quantile rules were compared** on the same in-scope
   detections:

   | marker | model: invalid+questionable | reads <= blank max | < 1% of ESV max | < 100 reads |
   |---|---|---|---|---|
   | 12S | 1.34% | 3.59% | 5.63% | 53.7% |
   | 18S | 0.06% (+159,770 not assessed) | 9.91% | 2.85% | 85.5% |
   | COI | 0.50% (+43,032 not assessed) | 3.19% | 0.91% | 83.5% |

## Open decisions for the user

- On the runs that do produce an estimate (12S/COI JVB3735, 18S JVB3506), the
  dispersion sits at its 0.01 floor. The control reads are clumped in a few blanks,
  which is the shape of well-to-well contamination rather than diffuse hopping.
  Should the 1.1% of 12S detections flagged there be applied, or treated as
  questionable at most?
  The CalIntertidal session found that JVB3735 12S blank reads TOTAL about 0.15%,
  inside the hopping band. But `hop_validation/hop_top_probe.rds` shows each of the
  ten biggest ESVs in a median of 6% of the 24 blanks (max 12%), where diffuse
  hopping would reach nearly all of them. The two checks agree on which run has
  excess reads, not on the mechanism.
- The 18S/COI detections on the `implausible_rate` runs are unassessed for spillover.
  `flag_contaminant()` / `validate_controls()` are the tools for those blanks, and
  their verdicts still do not reach `make_esv_*_detections.R` (the prompt's structural
  finding stands).
- `implausible_rate` (refused) runs: 18S JVB3735, 18S JVB2844, COI JVB3506, COI
  JVB2844. The CalIntertidal session ran `validate_controls()`. All verdicts are
  low-power (pooled null), so treat them as indicative:
  - 18S JVB2844: ONE physical blank, S067800 (3 replicates), resembles a sample
    (d_to_samples 0.82-0.86 vs d_to_controls 0.988). S067808 is clean. That is one
    bad blank next to a clean one, not a dirty run.
  - 12S JVB3735 (the run with the 12S flags): 2 of 24 controls resemble a sample.
  - 18S JVB3506 (estimated at 0.25%, not refused): 0 of 3; its blanks agree
    closely with each other.
  - 18S JVB3735: 0 of 30. COI JVB3506: 0 of 33. COI JVB2844: 3 of 7, the SAME
    S067800 replicates. Two independent assays of one tube agree, which does most of
    the evidential work given the low power.
  - So contaminated blanks explain JVB2844 only. On 18S JVB3735 and COI JVB3506 the
    blanks look like controls yet carry field-correlated reads well above the
    hopping band. The cause is unexplained; do not attribute it to dirty blanks.
  - Filter re-run on JVB2844 without S067800 (`hop_validation/jvb2844_drop.R`):
    COI rate 0.286 -> 0 (bound_only, upper 3e-4; that blank WAS the whole signal).
    18S 0.572 -> 0.165 (still implausible_rate; the remaining blanks still carry
    field-correlated 18S reads). Without the max_rate ceiling, this run alone would
    have had 56-83% of its field detections flagged.
  Why it matters beyond this filter: a blank full of field reads dilutes a genuine
  reagent contaminant's share, so `flag_contaminant()` becomes more permissive toward
  real contaminants. It can also make an abundant field taxon look like a contaminant.
  A control flagged RESEMBLES_SAMPLE should be dropped from `control_samples` for BOTH
  functions. The CalIntertidal session already calls `validate_controls()` once per
  run, so its null is per-run. The low power comes from genuinely wide within-run
  sample-to-sample distances, not from grouping.
  USER DECISION (2026-09-28): `flag_hopped_detections()` stays focused on hops.
  Dropping or gating blanks belongs to a separate, future function. Until it
  exists, the workflow chooses `control_samples` explicitly (e.g. excluding
  S067800 on JVB2844).

## Workflow wiring (CalIntertidal session owns it)

The call belongs at ingest, on `reads_long`, before `make_esv_*_detections.R` and
`11_build_match_objects.R`:

```r
res <- TaxaFlag::flag_hopped_detections(rl, event_col = "event_id",
  taxon_col = "observation_id", count_col = "n_reads", run_col = "batch",
  control_samples = unique(rl$event_id[rl$is_blank | rl$is_lab_blank]))
```

This needs TaxaFlag reinstalled from the branch after merge. Add one zero-count row
per blank that sequenced nothing, or that blank is invisible (`attr(, "controls_absent")`).

## Files

- Function and tests: `TaxaFlag/R/flag_hopped_detections.R`,
  `tests/testthat/test-flag_hopped_detections.R` (68 assertions, including simulations
  with a known rate, overdispersion and contamination).
- Validation: `CaliforniaIntertidal/hop_validation/`. Contains `hop_rate.R`
  (preserved from the peer's scratchpad), `hop_filter_validation.R`, the two blank
  probes, `sim_check.R`, and the `.rds` results and log.
- TaxaWizard: a new export. It is learned from formals and Rd after reinstall. No
  graph edge was added; `reads_to_flagged` would be the natural edge.
