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

The user confirmed: **always scope filter first.** This is not stylistic — an unscoped
12S fish pool was dominated by birds, and habitat NA-dropping was the only thing
keeping them out of the resident prior.

> ⚠️ **EVERY POOL-DERIVED NUMBER PREVIOUSLY IN THIS SECTION IS VOID.** They were
> measured on `PtConMifishSchulte_raw_gbif.rds`, which the workflow guards with
> `file.exists()` ALONE — no input check — so it was never re-fetched when the family
> list or `YEAR_RANGE` changed. Its zip is not even in `cache_gbif_global`; the only
> pre-existing entry there is the GLOBAL geo-outlier fetch (53 species, `g0` = no
> geometry, 2000–2026). A like-for-like fetch on 2026-09-19 returned **8,109,892**
> raw records where that artifact held 2,014,584, and Sebastidae alone went
> **235,135 → 2,182,813**. The pool was not merely stale in composition; it was
> roughly **4× under-fetched**. Do not resurrect those figures from git history.
>
> Void: 1,817,982 records / 194,463 points / 674 taxa; 495,014 NA records (27.2%);
> 31,383 NA points; the 546-point / 419,034-record / 85% concentration; Anatidae
> 219,403, Laridae 105,097, Hirundinidae 30,848, Gaviidae 21,533,
> Phalacrocoracidae 12,856; Sebastidae 235,135 / Embiotocidae 150,336 /
> Hexagrammidae 50,435; records_post 1,071,874; the 145 residual; the six recovered
> fishes and their distances; the 79-taxa pre-filter figure.

**Re-measured against a real fetch (2026-09-19, sections A and B of
`eDNA/PtConception/VALIDATE_scope_filter_and_uncertain_ptcon12S.R`):**

- 100 families in the ESV list, **69 kept / 31 dropped**, 0 ungrouped taxa, all 69
  keys resolved at FAMILY rank.
- **8,109,892 raw → 8,098,865 post-quality records, 100% `sampling_group == "fishes"`.**
  Zero birds. The filter does what it was built to do.
- 35,326 distinct points at species level, against 194,463 in the old pool — **3.9×
  the rows but 0.18× the points**, because bird records are one-per-locality and
  marine fish data is surveys hitting the same stations repeatedly.
- Rank parsing on the live path is sound: kingdom 0.0% NA (so the kingdom guard can
  fire), class 73.1% NA (the known "GBIF has no class node for ray-finned fishes"
  quirk, harmless — the classifier keys on order and phylum too).
- `Cyprinidae` resolves to **KINGDOM** via `name_backbone` and is recovered to FAMILY
  key 7336 via `name_lookup`. That guard inside `get_keys_from_context()` is the only
  thing between this fetch and a kingdom-wide pull. Do not remove it.

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

**Those 31,383 rows are a coincidence worth not tripping over.** The decision file
carries exactly as many `"Uncertain"` rows as the stale pool had NA points, because
the decisions were seeded from that pool. The count is a true description of the
file (verified by reading it), but it is not a fact about the data any more: a
re-fetch yields 35,326 points where the old pool had 194,463, so most stored
decisions are now orphans keyed to `point_id`s that no longer occur. Harmless —
`apply_spatial_review_decisions()` joins on `point_id` and simply finds no match —
but do not read the file's row count as a measure of how much is unassigned today.

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

## MEASUREMENTS TO CARRY FORWARD

**Read the void notice in PRECEDENCE first.** What follows is split by whether it
rests on an argument about code (durable) or on a count from the stale pool (gone).
That split is the day's lesson: every conclusion resting on an argument survived, and
every one resting on a count from the artifact did not.

**Durable — properties of the code, not of any pool:**

- `main_habitat = NA` means "could not place this point" in an OCCURRENCE table and
  "matches ANY habitat" in a PRIOR table (`join_priors.R:1021`). That collision is
  structural and is what this work exists to fix.
- Kish `n_eff = W^2/sum(w^2)` is **scale-invariant**: 2,000 records at pi=0.3 give
  `n_eff = 2000` and the same prior SD (0.00670) as 2,000 certain records. Soft
  habitat weights would change *what* the model believes, not *how strongly*. Any
  uncertainty discount must be built deliberately (raise `m`, or discount `n_eff`) —
  it is not inherited from the weights.
- A cache guarded by `file.exists()` alone answers "is there an artifact?", never "is
  this artifact still the answer to the question I am now asking?". Both inputs
  moved and nothing noticed. `raw_gbif_path` is the instance; assume siblings exist.

**Void — re-measure before quoting.** The NA-pool characterisations all came from the
stale pool: 31,383 NA points, the "every NA point is genuinely mixed" breadth figures
(median 3.57, 5th percentile 2.67, zero under-threshold near-misses), and the 76.3%
single-species share. The *qualitative* claims may well survive re-measurement — a
single-species point's consensus vector really is that taxon's own weights copied
over, which is an argument, not a count — but no number here should be reused.
Sections C and D of the VALIDATE script produce the replacements.
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
