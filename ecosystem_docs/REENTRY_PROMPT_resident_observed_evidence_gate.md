# `resident_observed` asserts evidence it never tests

**Status: IMPLEMENTED 2026-09-15 (Opus 5). Option 2 + an explicit evidence
knob, per the user's decision; the rank-coverage defect below was folded in
at the same time. One validation step remains before the numbers are
publishable -- see "Resolution" at the bottom. Raised by a parallel session
2026-09-14, quantified here.**

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


---

## Resolution (2026-09-15, Opus 5)

### Decision: rename + evidence column, no gate

The doc's option 2 plus the explicit evidence signal, chosen by the user
after the measurement below. Option 1 (a minimum-evidence gate) was NOT
applied, because the data will not support picking a threshold today.

### What the measurement actually showed

Per-sampling-group, as this doc asked for, turned out to be **impossible from
the emitted priors**: `sampling_group` is `NA` on effectively every row (792
of 792 at PtCon 12S; only 6 of 1,735 populated at 18S, all evidence/domestic
rows). The grouping lives on the kernel FIT, not on the output. Pooled, per
site:

| site | labelled rows | < 1 eff. record | min |
|---|---|---|---|
| PtCon 12S | 479 | 215 (44.9%) | 0.0000 |
| PtCon 18S | 1521 | 987 (64.9%) | 0.0000 |
| GreatLakes | 90 | 17 (18.9%) | 0.0177 |

Two things this doc could not have known, both load-bearing:

1. **There is no natural threshold.** `log10(effective_records)` is broad and
   continuous from about -6 to +4 with no valley -- any cutoff is a judgment
   call, not a reading off the data. That is the reason the gate was
   declined rather than tuned.
2. **GreatLakes is the least affected site**, by a wide margin, and it is the
   only one with an external check. So the Lamar benchmark was never going to
   be sensitive to this, which weakens it as the validation instrument here.

Also measured, and it reframes the severity: rows under one effective record
already carry a median `theta_mean` of 1.5e-08 against 1.9e-04 for the rest
-- about 13,000x lower. The numerical damage was therefore small; the damage
was **categorical**, through `winner_has_occurrence_record` into the
published Axis-1 plausibility labels.

### Built

- `estimate_kernel_priors()` emits `prior_branch = "kernel_estimated"`.
- `posterior_consensus(min_effective_records = 0)` -- the knob. Default 0 is
  branch-only, i.e. byte-identical to before, so nothing moved.
- `join_priors()` deliberately NOT gated: promotion only lifts to singleton
  parity, and see the theta figures above.
- **Both branch strings are accepted permanently**, via new
  `TaxaAssign/R/kernel_branch.R`. Not transitional -- every prior table
  checkpointed before the rename carries the old string across four sites.
- **17 hardcoded `== "resident_observed"` filters in 6 workflow files** were
  patched. This doc listed seven package files and five test files; it missed
  the workflow layer entirely, and several of those are load-bearing
  (`.not_clamp` drives the species_reference downranking filter). They would
  have matched ZERO rows on the next fresh priors run while looking correct
  against every cached table.

### The rank-coverage defect, folded in

Found while closing item 1, and it is the same fault in the same signal:
`compute_group_priors()`'s `rank_cols` stopped at `family`, so an ORDER-rank
consensus found no group row, read `consensus_has_occurrence_record = FALSE`
and was auto-reported `"unprecedented"`. Real cost: the PtCon 12S
`Perciformes` unit (*Scorpaenichthys marmoratus* + *Hexagrammos*, 20
observations) was flagged unprecedented, TaxaFlag's skepticism gate then
rated it geographically "unlikely" while its own `review_comment` called the
candidates "very common at Pt. Conception", and the export dropped all 20.

Default `rank_cols` now reaches `order` and `class`; a DEFAULT rank absent
from `taxonomy_map` is skipped with a message, an EXPLICIT one still errors.
`fill_higher_ranks()` returns genus/family only, so the six production call
sites propagate order/class via FAMILY (one family, one order), reaching 61%
of PtCon priors taxa against 14% for a direct name join. Verified by running
the patched block on the real objects: 94 family->order pairs, 40 order
groups, `Perciformes` resolving at theta_sum 0.384 over 159 members.

### STILL OPEN -- the one thing left

**The rank change moves plausibility counts, and no site has been re-run.**
The rename moves nothing and needs no validation; the rank fix does. Before
any of these numbers are published:

1. Re-run each affected site (PtCon 12S first -- it has the known casualty,
   and the 20 Perciformes rows are the direct test of whether they now reach
   the export).
2. Re-run the held-out GreatLakes/Lamar check via
   `GreatLakes_kernel_fastpath.R` (benchmark: precision 0.872). Note the
   caveat above -- GreatLakes is the site least affected by the branch
   question, so a flat result there confirms no regression rather than
   confirming the fix.

Tests at implementation: TaxaExpect 649/0, TaxaAssign 806/0, TaxaWizard
641/0; `check()` 0/0/0 on both changed packages. Commits: TaxaID `c493117`,
eDNA `42bb24e` + `cae94e9`, GreatLakes `c609398` + `ba422f4`.
