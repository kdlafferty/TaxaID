# RE-ENTRY: the kernel priors' unseen-species budget, its price, and its scope

Written 2026-09-03 (Opus 5, branch `kernel-priors`), from a long design
session with the user against real Mugu and GreatLakes data. Everything
numeric below was computed in-session from real checkpoints, not recalled.

Read this before touching `theta_present`, `chao_missing`, the budget audit,
or `sampling_group_col` in `estimate_kernel_priors()`.

> **UPDATE 2026-09-03, later the same day (Opus 5).** Read the closing section
> **"2026-09-03 UPDATE: the PtConception 18S diagnostic"** FIRST -- it supersedes
> this document's "Next step, recommended" (done), its cost estimate for that
> step (no GBIF fetch was needed -- an 18S checkpoint already existed), part of
> Finding 2 (mass/Chao is NOT always below the singleton mean), and open decision
> #4 (implemented). Open decision #2 is now evidenced, not blocked; #1 and #3
> remain open and untouched.

## The three quantities, and which job each does

```
theta = w  x  theta_present          (curve pricing; theta_absent = 0)
        |            |
        |            +-- PRICE: "share of a random record, GIVEN present"
        +-- PRESENCE: P(locally present | evidence), from the distance curve

budget audit:  sum(w)  vs  chao_missing      (AUDITED, never enforced)
```

* `sum(w)` = expected NUMBER of named claimants actually present.
* `chao_missing` = estimated TOTAL number present-but-locally-unseen.
* `theta_present` = `missing_mass / chao_missing` -- the average anonymous
  unseen species' share.

The audit and the price are different questions. The shipped code uses the
audit's denominator (`chao_missing`) inside the price, which is how the
price inherits the audit's instability. That is the open issue.

## Real numbers (both sites, 2026-09-03)

| | GreatLakes (Lentic) | Mugu (Coastal-Marine-Estuary-Stream) |
|---|---|---|
| stratum records | 6,157 | 529,091 |
| taxa | 86 | 214 |
| f1 / f2 | 12 / 5 | 39 / 6 |
| `chao_missing` | 14.4 | 126.8 |
| `missing_mass` | 2.93e-03 | 9.75e-04 |
| `theta_present` = mass/Chao | 2.037e-04 | 7.70e-06 |
| mass/f1 (singleton price) | 2.445e-04 | 2.50e-05 |
| ratio Chao/f1 | **1.20x** | **3.25x** |
| `sum(w)` | 6.67 | 0.36 |
| budget utilisation | 46% | 0.28% |
| singleton theta spread | 4x | 19x |

## Finding 1: Chao is radius-unstable at BOTH sites

Holding lambda fixed and moving ONLY the f1/f2 counting radius
(`support_weight`, default `exp(-3)` = 3 lambda):

* Mugu: `theta_present` spans 7.7e-06 to 2.79e-05 -- **4x**. The shipped 3L
  default lands on the WORST point in the sweep (f2 = 6, the minimum
  doubleton count anywhere, hence maximum Chao and minimum price).
* GreatLakes: Chao spans 0.7 (r=50) to 15.1 (r=150) -- **21x**.

f1 is comparatively stable (Mugu 34-49, GL 11-12); **f2 is the erratic term**
(Mugu 5-12, GL 4-11), and `Chao = f1^2/(2 f2)` is hypersensitive to it in
single digits. Bias-corrected Chao does NOT help (Mugu spread 4.07x vs
3.99x), so this is not small-sample estimator bias -- it is real sensitivity
to a boundary the rest of the estimator does not use.

Moving lambda instead is worse: at Mugu, lambda = 25 vs 50 are near-tied on
the calibration criterion (logloss 3.761 vs 3.778, 0.5% apart, both beating
nearest-block in 15/16 blocks) yet `theta_present` differs **2.5x**. LOBO
calibration optimises COMPOSITION PREDICTION, which has no stake in f1/f2 --
so nothing in the pipeline constrains the budget quantity. Lambda is chosen
for one purpose and silently reused to price a second.

## Finding 2: the price and the audit want different reference classes

`mass/f1` is exactly the MEAN THETA OF THE OBSERVED SINGLETONS (verified
identically on real Mugu data: both 2.5e-05). So the choice is:

* `mass/Chao` -- "what is the average ANONYMOUS UNSEEN species worth?"
  Correct for that question, and properly BELOW the singleton mean since an
  unseen species is rarer than a once-seen one. Inherits Chao's instability.
* `mass/f1` -- "what is a species we BARELY DETECT HERE worth?" Uses only
  observed quantities (f1 is counted, not estimated).

Tie-breaker argument (not yet adopted): every claimant reaching
`theta_present` is NAMED and has external evidence (a nearby out-of-bbox
record, invasive-watch status, a verified iNat range) -- that evidence is
what earned it a `w`. Conditional on presence it should look like a species
we barely detect, not like the average member of a hypothesised pool of ~127
undetected species we cannot name.

**NOTE**: `missing_mass / f1` is ALREADY COMPUTED in
`apply_undetected_evidence()` as `kernel_theta_singleton` -- used only for
the veto-bound printout, not as the price. Switching is a one-line change to
an existing quantity.

## Finding 3: the GL validation is ROBUST to that choice

Exact flip analysis on GL's real saved posteriors, scaling every
curve-priced prior by 1.20x (`mass/Chao` -> `mass/f1`):

```
observations with >=2 candidates : 880
winner FLIPS                     : 0  (0.00%)
largest curve-priced challenger/winner ratio: 0.998 (needs >0.833 to flip)
```

The 7 observations with a challenger inside the margin all have curve-priced
WINNERS, so both sides scale together. GL precision 0.853 and +4 species do
not depend on the pricing choice. (First-order argmax on likelihood x theta,
not a full pipeline re-run -- state it as such.)

At Mugu the change is 3.25x, but the budget is 0.28% utilised and the
concerning calls sit on the undetected floor, so little moves there either.

## Finding 4 (CORRECTION -- do not repeat my error)

I initially framed "Chao > B" as IMPOSSIBLE, where B = species recorded in
the stratum but unseen near the site. **That was wrong.** Chao and B count
DISJOINT sets, which is exactly the user's own q decomposition:

* B = recorded elsewhere, not seen nearby -> `qA`, countable, theta computable
* Chao - (present ones from B) = recorded NOWHERE -> `(1-q)A`, must be estimated

So Chao > B is not a contradiction; it means "at least Chao - B of the unseen
are recorded nowhere in the download". At Mugu that is >=68 species absent
from 529,091 records within 280 km -- IMPLAUSIBLE, but not impossible. At GL
it is >=12 absent from an 11,086-record download -- entirely reasonable.

**And q = sum(w)/B is refuted as an audit**: at GL, B = 3 while sum(w) = 6.67,
giving q = 2.22 > 1. Claimants are NOT drawn only from the stratum --
`generate_regional_proximity_evidence()` finds species with records OUTSIDE
the bbox, and invasive-watch species may have no records in the download at
all. **The shipped audit structure (`sum(w)` vs Chao) is correct; keep it.**

## Finding 5: taxonomic scope -- SHIPPED (commit eb98338)

The user's objection: when the occurrence pool is broader than what the assay
detects (water sampled for vertebrate diversity, signal 95% fish), taxa the
assay cannot detect contribute singletons that inflate f1 -- hence Chao,
quadratically -- while adding almost nothing to `missing_mass`, DEFLATING
`theta_present`. Their ~3x estimate is confirmed algebraically; a stark
fixture (20 well-recorded fish + 30 single-record "downwash" taxa) measures
11x, and detectable taxa's own theta is separately diluted.

NOT the explanation at either validated site, checked directly: GL's
curve-priced pool is 376/376 Actinopteri; Mugu's singletons are fish
throughout. It is a no-op on a homogeneous pool BY CONSTRUCTION, which is
also why it cannot disturb either validation.

`estimate_kernel_priors(sampling_group_col=)` now computes theta AND the
budget within group. `NULL` (default) is the previous behaviour exactly --
verified against the real 529,091-record Mugu run at max |delta| = 0 across
all 214 taxa. With >1 group the pooled scalars are NA by design and
`$budget` is authoritative; `apply_undetected_evidence(pricing = "curve")`
REFUSES a multi-group fit rather than mispricing every group but one.

Build the column with `compute_adaptive_sampling_groups()` (merges
order -> class -> phylum only as far as each group needs, phylum ceiling, so
no single rank has to be chosen) or supply your own.

## Open decisions (NOT made)

1. **Switch the price to `mass/f1`?** Evidence says safe (GL 0/880 flips) and
   better-founded (observed vs estimated). Changes Mugu 3.25x. Deliberately
   left as a decision, not a side effect.
2. **Per-group curve pricing.** Blocked: needs real multi-group data, and
   PtConception 18S has NO occurrence or prior checkpoint yet. Currently
   fails loudly with an actionable message.
3. **Singleton theta DISTRIBUTION instead of a scalar.** The observed spread
   is 4x (GL) to 19x (Mugu) and is discarded today. `compute_posterior()`
   already draws presence as a Bernoulli on `w`, so drawing `theta_present`
   from a distribution extends an existing sampler rather than adding one.
   Caveat to settle first: whether the reference class is all regional
   singletons or only those with local support. Regional-only is REFUTED --
   class B spans 19,137x and is bimodal because 55% of its members have their
   single record beyond 75 km; using their kernel theta would DOUBLE-COUNT
   distance, once in `w` and again in `theta_present`.
4. **Report f1, f2 and the radius sensitivity** next to any budget figure so
   a reader can see when it rests on four doubletons. No downside.

## Next step, recommended

The 18S question is entirely PRIOR-SIDE: do the 11 sampling groups actually
produce materially different budgets? That needs `occurrences_clean` + a
`sampling_group` column and one `estimate_kernel_priors(sampling_group_col=)`
call -- NO NCBI, no BLAST, no likelihood model. Do that subset diagnostic
before committing to a full 18S workflow run.

## Reproducibility note (2026-09-03)

Mugu's consensus was proven DETERMINISTIC in-session (two identical calls,
identical output; `lookup_missing_taxonomy = TRUE` changes 0 of 616 rows and
could be switched off to remove a live network call from the analysis path).
A one-observation difference between the 2026-09-02 and 2026-09-03 runs was
NOT reproduced and is most likely the 09-02 session holding stale in-memory
packages (that session hit the corrupt-`.rdb` error the same evening).
`posterior_point_est` is RNG-free (`compute_posterior.R:307`), but
`posterior_mean`/`posterior_sd`/`confidence_score` ARE drawn -- add
`set.seed()` to the workflows for bit-reproducibility of reported
uncertainty.

---

# 2026-09-03 UPDATE: the PtConception 18S diagnostic

Run: `diagnostics/kernel_budget_18S_sampling_groups.R`
(results cached in `diagnostics/kernel_budget_18S_sampling_groups_result.rds`).
Prior-side only -- no NCBI, no BLAST, no likelihood model, no reference fetch.

## The cost estimate above was wrong: no GBIF fetch was needed

This document says "PtConception 18S has NO occurrence or prior checkpoint yet"
and scoped a GBIF download over ~1,300 genera. A real 18S `occurrences_clean`
checkpoint has been sitting in the TaxaID project root since 2026-06-15:
**2,185,193 records, 7,392 taxa, 3,133 genera**, with the workflow's own
11-way `sampling_group` column attached, 970,556 of them in the Marine stratum.
The diagnostic re-derives `sampling_group` from the classification the
checkpoint was built under and requires an exact match (0 mismatches of
2,185,193) before using it, so this is verified provenance, not a filename
guess.

## A real bug found on the way in: the fishes group was 5 records

The workflow's fishes clause read
`class %in% c("Actinopteri", "Chondrichthyes", "Myxini")`. GBIF's backbone
carries **no class at all** for the ray-finned fishes and names the
sharks/rays **"Elasmobranchii"**, so that clause matched 5 of 484,077 real fish
records (the Myxini). The other 484,072 fell through to the
`macroinvertebrates` catch-all, making the largest group **54% fish**. Nothing
downstream complained -- a catch-all group cannot fail loudly.

Fixed 2026-09-03 in all three places the pattern lives:
`PtConceptionWorkflow_18S_2_single_site.R` (empty-string normalization +
class-less-Chordata fish clause + a regression guard that warns if the fish
clause ever goes quiet again), `TaxaID_eDNA_Workflow_Template.R`, and
`18S_stuff/PtConception18S_groupings.r`. This is the same empty-string
taxonomy quirk `compute_adaptive_sampling_groups()` already normalizes with
`na_if()`. **The saved checkpoint still carries the old column**; the
diagnostic re-derives the corrected grouping in memory, so it does not depend
on a checkpoint rebuild.

## The answer: YES, by three independent cuts

Marine stratum, lambda = 25 km (LOBO-calibrated, an interior optimum over
{10, 25, 50, 100}), `support_weight` at its `exp(-3)` default.

| group | n_eff | f1 | f2 | chao_missing | theta_present | x pooled |
|---|---|---|---|---|---|---|
| other_vascular_plants | 27 | 13 | 4 | 21.1 | 2.14e-02 | 2343x |
| terrestrial_arthropods | 24 | 9 | 3 | 13.5 | 1.74e-02 | 1906x |
| zooplankton | 643 | 3 | 7 | 0.64 | 5.08e-03 | 556x |
| birds_mammals | 608 | 4 | 1 | 8.0 | 1.14e-03 | 125x |
| macroalgae | 6,680 | 23 | 9 | 29.4 | 1.20e-04 | 13.1x |
| macroinvertebrates | 38,869 | 108 | 44 | 132.5 | 2.89e-05 | 3.16x |
| fishes | 54,441 | 22 | 6 | 40.3 | 1.15e-05 | 1.26x |
| meiofauna / parasites / sea_grasses | 1-137 | 0 | 0 | 0 | NA (unpriced) | -- |
| **POOLED (what the workflow prices with today)** | 99,975 | 182 | 74 | 223.8 | **9.14e-06** | 1x |

* spread across all priced groups: **1859x**
* spread among groups the 18S assay can actually amplify: **441x**
* spread among groups with n_eff >= 100 (drops the thin downwash groups): **441x**
* `compute_adaptive_sampling_groups(min_n = 100)`, a taxonomy-driven grouping
  independent of the workflow's hand curation: 68 groups, 33 priced,
  spread **6644x**

The 441x figure is the decision-relevant one: it survives deleting both extreme
groups and every group with fewer than 100 effective records. **Per-group curve
pricing is justified** -- the single pooled price underprices every group by
1.26x to 2343x, and the pooled number is not even a compromise between them, it
sits BELOW all seven.

This is also the first measurement of Finding 5's scope effect on a genuinely
heterogeneous pool. Note how it works here: the non-detectable groups
(birds/mammals, land plants, terrestrial arthropods) supply **14% of the pooled
f1 on 0.66% of the pooled n_eff** -- singletons without mass, exactly the
mechanism, inflating Chao while leaving `missing_mass` almost untouched.

## Finding 2 needs a correction: mass/Chao is NOT always below the singleton mean

This document states that `mass/Chao` is "properly BELOW the singleton mean
since an unseen species is rarer than a once-seen one." That holds at
GreatLakes and Mugu but is not general. `mass/Chao < mass/f1` requires
`Chao > f1`, i.e. `f1 > 2*f2`. Real counterexample here: **zooplankton, f1 = 3,
f2 = 7 -> Chao = 0.64**, so the "average anonymous unseen species" is priced
**4.7x ABOVE** a species actually seen once, and the estimated number of unseen
species is below ONE species. Six of the 68 adaptive groups show the same
pattern. Small groups make `f1 < 2*f2` ordinary, so per-group pricing meets
this case routinely where the pooled fit never did.

The consequence for the `apply_undetected_evidence()` curve-mode veto bound
(`w > 19 * theta_singleton / theta_present`) is that its comment's claim of
"unreachable by construction" was an overstatement; the code already computes
the bound and prints the "unreachable" clause conditionally, so the behaviour
was right and only the comment was wrong. Corrected in place.

## What per-group pricing would have to guard (Section 5 of the diagnostic)

Measured, not hypothesized, on the 10 real groups:

* **no singleton anchor** (`f1 = 0`): 3 of 10 groups. No budget at all.
* **mass but no price** (`f1 = 1, f2 = 0`): Chao's `f1(f1-1)/2` fallback returns
  0, so a real `missing_mass` is silently discarded. 8 of 68 adaptive groups;
  `sea_grasses` hits it at lambda 50 and 100.
* **Chao below one species**: zooplankton (0.64), and 6 adaptive groups.
* **price above 1% of the community**: `other_vascular_plants` (2.1%) and
  `terrestrial_arthropods` (1.7%) -- both on ~25 effective records. At
  lambda = 10 `terrestrial_arthropods` prices a single unseen species at
  **0.755**, i.e. 75% of its group's community.
* **thin groups** (`n_eff < 100`): 4 of 10.

A per-group implementation therefore cannot just index `budget$theta_present`
by group. It needs a minimum-support rule and a documented fallback for groups
below it. `mass/f1` (open decision #1) is defined for every group with a
singleton, including the three `mass/Chao` cannot price -- reported for
information only; the two decisions stay independent, and GreatLakes already
settled #1 on its own evidence.

## Open decision #4: IMPLEMENTED

* NEW `TaxaExpect::kernel_budget_sensitivity(fit, occurrence_data,
  support_weight_grid, lambda_grid)`: re-runs the estimator across counting
  radii (and optionally bandwidths) and returns per-group `$budget` rows plus a
  `$summary` giving the f1/f2/Chao ranges, the `theta_present` spread, and the
  count of settings where a group had no price. `$reproduces_fit` is FALSE if
  the supplied occurrence data is not what the fit was computed from. It calls
  the estimator rather than recomputing statistics, so its numbers cannot drift
  from it. Its `print()` carries a CAUTION line naming the smallest `f2`.
* `estimate_kernel_priors()` now records `taxon_col`/`lat_col`/`lon_col`/
  `habitat_col` in `$params` (so a fit can be re-computed from its own
  provenance), and its `print()` shows `f1`, `f2`, `chao_missing` and
  `theta_present` in the UNGROUPED case too, not only for multi-group fits,
  with the same single-digit-f2 caution.
* `apply_undetected_evidence(pricing = "curve")`'s message now names the
  `f1`/`f2` the price came from and says so when `f2` is in single digits.

Measured radius sensitivity on real 18S groups (1-5 bandwidths, lambda fixed):
`other_vascular_plants` 1.9x, `macroalgae` 6.2x, `zooplankton` 19x,
`birds_mammals` 23x, `macroinvertebrates` 38x, `fishes` 66x,
`terrestrial_arthropods` 137x. Over the lambda grid instead: up to 1060x
(`birds_mammals`). Consistent with Mugu's 4x and GreatLakes' 21x, and worse in
the thin groups.

TaxaExpect: 30 new tests (`test-kernel_budget_sensitivity.R`) + 2 in
`test-apply_undetected_evidence.R`; `devtools::test()` 956 passing / 0 failing;
`devtools::check()` 0 errors, 0 warnings, 0 notes. Reaching 0 errors also
required fixing a PRE-EXISTING check failure unrelated to this work:
`vignettes/building-priors.Rmd` set `purl = FALSE` via `opts_chunk$set()` in its
setup chunk, which `knitr::purl()` does not honour (it never executes that
chunk), so R CMD check tangled and sourced the whole documentation-only vignette
and errored on a live `build_priors()` call. Every chunk now carries
`eval = FALSE, purl = FALSE` in its own header, with a comment saying why the
repetition must not be DRY-ed up.

## Still open, untouched

1. **Switch the price to `mass/f1`?** Unchanged. GreatLakes evidence (0/880
   flips) still stands; the 18S per-group ratios are reported in Section 8 of
   the diagnostic for information, deliberately not as an argument.
2. **Per-group curve pricing.** No longer blocked -- evidenced above, and the
   guards it needs are enumerated. Not built: `apply_undetected_evidence()`
   still refuses a multi-group fit with its actionable message.
3. **Singleton theta DISTRIBUTION instead of a scalar.** Unchanged.
