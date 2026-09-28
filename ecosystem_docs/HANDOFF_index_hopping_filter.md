# Handoff: `TaxaFlag::flag_hopped_detections()` (index hopping / read spillover)

Built 2026-09-27 from `CaliforniaIntertidal/REENTRY_PROMPT_index_hopping_TaxaFlag.md`.
Branch `flag-hopped-detections` (worktree `~/taxaid-worktrees/flag-hopped-detections`),
3 commits on top of `main` 6d28861. **Not merged, not installed.**

## What it does

Flags individual detections (feature x sample) whose reads are no more than the
spillover expected from the same feature elsewhere on the same run:
`E = r * source * share`, with `share = 1/(n-1)` by default. `r` is estimated per run
from a non-native spike (preferred) or from negative controls. It flags, never
deletes, using the unified validity schema (`invalid_index_hop` /
`questionable_index_hop` / `valid` / `NA` = not assessed).

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
