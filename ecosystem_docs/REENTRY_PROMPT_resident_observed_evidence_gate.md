# `resident_observed` asserts evidence it never tests

**Status: OPEN, nothing implemented. Raised by a parallel session 2026-09-14,
quantified here. Deliberately not touched, because seven files read this label
and changing its meaning shifts every downstream filter.**

## The problem

`TaxaExpect::estimate_kernel_priors()` writes the label as a **constant**:

```r
priors <- data.frame(
  ...
  prior_branch = "resident_observed",
  effective_records = c_eff,
```

Every row the kernel estimator emits gets it, regardless of how much evidence
stands behind that row. The name asserts "observed resident"; the code tests
nothing.

Downstream, two consumers read it as a real claim about evidence:

- `TaxaAssign::posterior_consensus()` sets `winner_has_occurrence_record` from
  `prior_branch == "resident_observed"`, which is the Axis-1 plausibility
  signal (`expected` / `unexpected` / `unprecedented`).
- `TaxaAssign::join_priors()` gates its modelled-species floor promotion on
  the same value.

## How bad it is, measured on the real PtConception 12S priors

479 of 792 rows carry the label. Their `effective_records`:

| quantile | 0% | 10% | 25% | 50% | 75% | 90% | 100% |
|---|---|---|---|---|---|---|---|
| effective_records | 0.0000 | 0.0001 | 0.0068 | 1.805 | 83.4 | 2025.6 | 3663.1 |

| threshold | rows below | share of labelled rows |
|---|---|---|
| < 0.01 | 123 | 25.7% |
| < 0.1 | 156 | 32.6% |
| < 1 | 215 | 44.9% |
| < 2 | 244 | 50.9% |

**A quarter of "observed residents" rest on under one hundredth of an
effective record, and the minimum is exactly zero.** Those taxa are currently
reported as having a local occurrence record, and are promotion-eligible.

## The two options

1. **Minimum-evidence gate.** Keep the name, require
   `effective_records >= <threshold>` before applying it, and route the rest to
   a different branch. Honest, but it moves rows between branches, so every
   downstream count changes and the Lamar-validated GreatLakes numbers must be
   re-checked before the change is trusted.
2. **Rename to describe what it tests.** Something like `kernel_estimated`.
   Cheap and truthful, changes no behaviour, but leaves the consumers making a
   plausibility claim the data does not support, so `winner_has_occurrence_record`
   would still need a separate honest definition.

These are not exclusive. The likely right answer is a rename **plus** an
explicit evidence column that the consumers read instead.

## Before changing anything

- The threshold is not obvious and should be chosen from data, not picked.
  `effective_records` is a Kish effective sample size from a distance kernel,
  so "one effective record" is already a defensible floor, but check the
  distribution per sampling group, not pooled.
- Re-run the held-out Lamar validation for GreatLakes afterwards. That is the
  one place in this ecosystem where a prior change has an external check, and
  the current benchmark is precision 0.872.
- Seven files read the label: `TaxaAssign/R/join_priors.R`,
  `TaxaAssign/R/posterior_consensus.R`,
  `TaxaExpect/R/estimate_kernel_priors.R`, three TaxaWizard snippets
  (`std_to_priors_kernel.R`, `post_to_consensus.R`,
  `dist_to_priors_by_group.R`), and the fast-check harness, plus five test
  files that pin the current strings.

No NCBI access is needed to decide this, so it is workable while NCBI is
throttled.
