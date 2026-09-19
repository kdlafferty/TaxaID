# Re-entry prompt — route Uncertain habitat deliberately, and rename the occurrence-side NA

**Written 2026-09-19 by `lafferty-f4`; restructured same day by `lafferty-ce` after the user
decided the routing question.** Read the STATUS CHANGE first — the original version of this
prompt told you to check whether the work was worth doing at all. That check has now been
answered, and it changes what the job is.

---

## STATE ON DISK (2026-09-19)

Step 1 is **done and committed, not pushed**:

- `eDNA` repo (branch `master`, **no remote** — nothing here is visible to the
  external reviewer): pre-fetch scope filter + `sampling_group_col` in
  `PtConception/PtConceptionWorkflow_12S_single_site.R`, propagated to
  `PtConception/TaxaID_eDNA_Workflow_Template.R`. `.bak_pre_scopefilter_*`
  backups sit beside both.
- `TaxaID` repo (branch `main`, in sync with `origin/main`): this document.
  **Do not push mid-implementation** — `main` is what the external reviewer sees.

Steps 2 and 3 are not started. No feature branch was opened: `eDNA` has no
remote at all, and the only pushable repo holds just this document.

---

## STATUS CHANGE — the kill-criterion is resolved

The first draft ended with "what would make this not worth doing": if no downstream mechanism
for multi-habitat observations is built, the rename is cosmetic — 30 edit sites and a cache
migration to change a sentinel two functions read. It cited `ce`'s verdict that no such
mechanism exists. That verdict was correct **for composite habitat labels**, and it still is:
composite stays a review queue, `main_habitat` stays single-valued.

But on 2026-09-19 the user decided something different and narrower:

> "Uncertain records are routed deliberately to the evidence branch."

That **is** the mechanism, and it is the one that makes the sentinel load-bearing. Today the
routing already happens, but **by accident**:

```r
# PtConceptionWorkflow_12S_single_site.R:1758
zero_bbox_taxa <- setdiff(match_list_taxa_12s, taxaexpect_priors$taxon_name)
```

A species with no prior row lands in `zero_bbox_taxa` and is priced by
`generate_regional_proximity_evidence()` **as a taxon with no records in the bbox at all**.
That is false for a species whose records exist but sit at unresolvable points — it may have
thousands nearby. The pipeline cannot tell "no records" from "records we could not place",
because both arrive as absence, and nothing reports the difference.

So the job is no longer a rename. It is:

1. **scope filter first** (user-confirmed ordering — see PRECEDENCE),
2. rename the occurrence-side sentinel so the two states are distinguishable,
3. **use the distinction**: route Uncertain-habitat taxa to the evidence branch explicitly,
   labelled as such, instead of letting them masquerade as regionally absent.

Step 3 is the deliverable. Steps 1 and 2 are what make it possible. If you find yourself doing
only step 2, stop and re-read this section.

## PRECEDENCE — scope filter before any of this

The user confirmed: **always scope filter first.** This is not stylistic. Measured on the real
PtConception 12S pool (1,817,982 records, 194,463 points, 2026-09-19):

- 495,014 records (27.2%) currently carry `main_habitat = NA` and are dropped by both live
  consumers.
- **546 points — 1.7% of the NA points — hold 419,034 of those records, 85% of the loss.**
- Their taxonomy: Anatidae 219,403, Laridae 105,097, Hirundinidae 30,848, Gaviidae 21,533,
  Phalacrocoracidae 12,856. Birds, at dense coastal-wetland localities.
- The assigned-Marine pool for contrast: Sebastidae 235,135, Embiotocidae 150,336,
  Hexagrammidae 50,435. Fish.

**Dropping NA is currently acting, by accident, as a scope filter on a 12S fish marker.** Any
change that resolves or routes those records — this work, or
`resolve_habitat_by_geography()` — admits 419k bird records into a prior whose workflow does
not pass `sampling_group_col`, so everything shares one composition and one Good-Turing
budget. Same failure already on record from the coastwide fetch (33.4% birds/mammals, 54,621
rows of swallows). It will look like an upstream improvement and land as a downstream
regression.

Do the family scope filter and wire `sampling_group_col` before measuring anything here.
Every number in this prompt was taken pre-scope-filter and will move.

## THE COLLISION — one column, two opposite meanings

| side | `NA` means | where |
|---|---|---|
| **occurrence** | "we could not determine this point's habitat" | `assign_habitat_biological()` when no habitat reaches `threshold` |
| **prior** | "habitat-agnostic — matches ANY habitat" | `TaxaAssign/R/join_priors.R:1021` |

Both re-verified 2026-09-19. `join_priors.R:1021` is literally
`dplyr::filter(is.na(main_habitat), !is.na(taxon_name), !is.na(alpha))` building
`habitat_agnostic_priors`; `estimate_kernel_priors.R:278` is
`keep <- !is.na(hab) & hab == site_habitat`. Exclusion on one side, wildcard on the other.
Nothing is broken today because the two never meet in one frame.

## THE PROPOSAL — three-way split

```
main_habitat        "Uncertain"                  the state the model branches on
habitat_candidates  "Freshwater | Marine"        the signature, its own column
attr habitat_proportions                          the weights
```

`spatial_flag_reason` stays a fourth, separate thing (audit text). Keeping the signature out
of `main_habitat` is the point: it stops composite pseudo-classes entering a column that four
packages join on.

Scope: **occurrence-side only.** That removes the collision in one change and leaves
`join_priors.R`'s wildcard intact. Renaming the prior side too is a bigger, different project.

## BLAST RADIUS — re-run this, do not trust the table

```
grep -rnE "is\.na\([^)]*(main_habitat|habitat_col|\$habitat|hab)\)" <pkg>/R/
```

2026-09-19: TaxaHabitat 17, TaxaAssign 7, TaxaExpect 4, TaxaFlag 2 = **30**. Re-run before
starting; `ce`'s earlier estimate of ~23 used a narrower pattern and missed TaxaFlag entirely.

## THE DECISION-FILE HAZARD — verified, and SMALLER than the first draft said

The first draft called the cache migration "the hard part" and said migration must come first.
That was derived from reading the code without checking the files. **All three files were
inspected on 2026-09-19:**

| file | rows | `habitat_reassigned` col | NA habitat | reassigned TRUE |
|---|---|---|---|---|
| `Rscripts/eDNA/PtConception/PtConMifishSchulte_…` | 218,311 | present | 31,383 | **0** |
| `Rscripts/eDNA/SepulvedaMugu/MuguWilderFish_…` | 18,461 | present | 127 | **0** |
| `Stats and Data/GreatLakes data/GreatLakes2023BurnsHarbor_…` | 5,044 | present | 472 | **0** |

Consequences, against `spatial_review_decisions.R`:

- **Line 98** (`if (!"habitat_reassigned" %in% names(old)) old$habitat_reassigned <- !is.na(old$main_habitat)`)
  is the phantom-reassignment risk the first draft warned about. It **cannot fire** — all three
  files already carry the column. The risk is latent, for files produced before it existed.
- **Lines 103–104** require `old$habitat_reassigned %in% TRUE`. Zero such rows exist anywhere,
  so `keep_old` is FALSE regardless of the sentinel.
- **Lines 74/76** run on *new* data at save time, which speaks the new vocabulary after the rename.

**What actually remains** is a value remap: 31,982 stored rows carry `main_habitat = NA` and
would sit in a column whose live vocabulary says `"Uncertain"`, giving one column two
vocabularies. Fix with a remap on load in `apply_spatial_review_decisions()`, or one rewrite of
three files. That is an afternoon, not a migration project. Keep line 98 correct for old files
regardless.

**Two path corrections to the first draft:**

- The GreatLakes file is **not** under `Rscripts/`. Full path:
  `/Users/lafferty/My Drive/Stats and Data/GreatLakes data/GreatLakes2023BurnsHarbor_spatial_review_decisions.rds`.
  (Consistent with the standing note that GreatLakes lives outside `eDNA/` — here it is outside
  `Rscripts/` entirely. A grep rooted at `Rscripts/` finds two of three files.)
- It has **no `.bak_*` backup.** PtCon and Mugu carry `.bak_20260918_211229` / `.bak_20260918_211214`
  from the stale-seed cleanup; GreatLakes does not. **Back it up before touching it.**

## ORDER OF WORK

1. **Family scope filter + `sampling_group_col`.** Precedes everything. Re-measure after.
2. **Remap the three decision files** (or handle on load), GreatLakes backed up first.
3. **Rename**, occurrence-side only. Re-run the grep.
4. **Route Uncertain to the evidence branch deliberately** — the actual deliverable. The
   species must reach `generate_regional_proximity_evidence()` flagged as "has nearby records
   of unresolved habitat", not as zero-bbox. Decide whether its evidence weight differs from a
   genuinely unrecorded taxon's; it should, because the evidence is stronger.
5. **`habitat_candidates` as a real column** — separable, may land first or not at all.

## WHAT IS ALREADY TRUE (verified 2026-09-19, do not redo)

- `habitat_proportions` is **contractually** preserved: set at
  `assign_habitat_biological.R:429` and `:683`, read and re-attached by
  `flag_habitat_inconsistencies.R:156` and `resolve_habitat_geography.R:192` (`a7e0841`).
  Independently confirmed that `[`, `filter`, `mutate`, `select`, `left_join`, `arrange`,
  `distinct`, `bind_rows` and the RDS round trip preserve it; `summarise()`, `data.frame()`
  and `merge()` drop it.
- A reviewer-resolved point's proportion vector is rewritten **one-hot** and carries
  `habitat_reviewed`, so weights cannot contradict a human decision (`a7e0841`).
- `resolve_habitat_by_geography()` exists (`resolve_habitat_geography.R:93`) and adds
  `habitat_source` (`"consensus"` / `"geography"`) — extend that column, do not invent one
  (`53e89fc`).
- `.habitat_signature()` exists (`utils_plot.R:546`) and is tested.
- `habitat_candidates` does **not** exist as a column anywhere.

## MEASUREMENTS TO CARRY FORWARD (pre-scope-filter, PtCon 12S)

- 31,383 NA points / 495,014 records (27.2%).
- **Every** NA point is genuinely mixed: median Levins breadth 3.57 of a possible 4, 5th
  percentile 2.67. **Zero** under-threshold near-misses at `threshold = 0.5` — the
  "unambiguous signal the threshold rejected" case in `assign_habitat_biological()`'s own docs
  does not occur on this data.
- 76.3% of NA points hold exactly one species, where the consensus vector is that taxon's own
  weights copied over and the location contributes nothing. Geography is the only thing that
  can resolve those.
- Kish `n_eff = W^2/sum(w^2)` is **scale-invariant**: 2,000 records at pi=0.3 give
  `n_eff = 2000` and the same prior SD (0.00670) as 2,000 certain records. Soft habitat
  weights would change *what* the model believes, not *how strongly*. Any uncertainty discount
  must be built deliberately (raise `m`, or discount `n_eff`) — it is not inherited from the
  weights. Relevant if step 5 ever leads to weighted habitat strata.

## SHARED-LIBRARY CONSTRAINT

Three sessions share one R library. Reinstalling a package under another session's live R
process can break it via lazy-load byte offsets, and "the change was additive" is not a
defence. This work reinstalls TaxaHabitat, TaxaExpect, TaxaAssign and TaxaFlag. **One session
does the rename end to end**; the others must not have those packages loaded while it runs.
