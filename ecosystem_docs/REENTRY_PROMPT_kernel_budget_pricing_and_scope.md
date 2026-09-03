# RE-ENTRY: the kernel priors' unseen-species budget, its price, and its scope

Written 2026-09-03 (Opus 5, branch `kernel-priors`), from a long design
session with the user against real Mugu and GreatLakes data. Everything
numeric below was computed in-session from real checkpoints, not recalled.

Read this before touching `theta_present`, `chao_missing`, the budget audit,
or `sampling_group_col` in `estimate_kernel_priors()`.

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
