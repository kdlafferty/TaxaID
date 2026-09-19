# Re-entry prompt — rename the occurrence-side habitat NA to "Uncertain"

**Written 2026-09-19.** Deliberately deferred, not forgotten. Proposed by `lafferty-ce`
(the multi-habitat-observations session) while the polygon-selection work was landing, and
held back because it is a cross-package rename with a **cache migration inside it**, and
doing it in the same breath as feature work is how the seeded-decisions problem happened.

---

## THE PROBLEM — one column, two opposite meanings

`main_habitat = NA` means different things on the two sides of the pipeline:

| side | `NA` means | where |
|---|---|---|
| **occurrence** | "we could not determine this point's habitat" | `assign_habitat_biological()` when no habitat reaches `threshold` |
| **prior** | "habitat-agnostic — matches ANY habitat" | `TaxaAssign/R/join_priors.R:1021`, `habitat_agnostic_priors` |

Verified 2026-09-19: `join_priors.R:1021` is literally
`dplyr::filter(is.na(main_habitat), ...)` building the habitat-agnostic prior pool, used by
the domestic/food priors and the global floor row. Meanwhile
`TaxaExpect/R/estimate_kernel_priors.R:278` is `keep <- !is.na(hab) & hab == site_habitat`,
excluding occurrence-side NA from the resident prior.

So the same sentinel in the same column name is an **exclusion** on one side and a
**wildcard** on the other. Nothing is broken today because the two never meet in one frame,
but it is a trap for the next person, and it makes "what does NA mean here" unanswerable
without knowing which table you are holding.

## THE PROPOSAL (ce's, three-way split)

```
main_habitat        "Uncertain"                  the state the model branches on
habitat_candidates  "Freshwater | Marine"        the signature, its own column
attr habitat_proportions                          the weights
```

`spatial_flag_reason` stays a fourth, separate thing (audit text).

The gadget already computes the signature — `.habitat_signature()` in
`TaxaHabitat/R/utils_plot.R` — but currently only for DISPLAY. This would promote it to a
real column.

## BLAST RADIUS — measured, not estimated

`grep -rnE "is\.na\([^)]*(main_habitat|habitat_col|\$habitat|hab)\)" <pkg>/R/` on 2026-09-19:

```
TaxaHabitat  17
TaxaAssign    7
TaxaExpect    4
TaxaFlag      2
             --
             30
```

Note this is **more than the ~23 ce estimated**, and it includes **TaxaFlag**, which was not
in that estimate. Re-run the grep before starting; do not trust this table.

## THE HARD PART — it is a MIGRATION, not a find-and-replace

`TaxaHabitat/R/spatial_review_decisions.R` decides "was this point reassigned by a reviewer?"
by NA-ness of the habitat:

```r
:74   new$habitat_reassigned <- !is.na(new$main_habitat) & (is.na(bh) | bh != new$main_habitat)
:76   new$habitat_reassigned <- !is.na(new$main_habitat)
:98   if (!"habitat_reassigned" %in% names(old)) old$habitat_reassigned <- !is.na(old$main_habitat)
:103  keep_old <- !is.na(oi) & old$habitat_reassigned[...] %in% TRUE &
:104    !is.na(new$main_habitat) & new$main_habitat == old$main_habitat[...]
```

Change the sentinel and **every existing decision file misreads**: an "Uncertain" point would
test `!is.na()` TRUE and be recorded as a reviewer reassignment it never was. That is exactly
the failure class already on record — see `[[project_...]]` / the 2026-09-19 audit that found
all three production decision files 100% seeded (244,860 decisions, zero real reviews) and two
of them masking live classifier changes.

**Three decision files exist and all need migrating, not rewriting:**

```
eDNA/SepulvedaMugu/MuguWilderFish_spatial_review_decisions.rds        (18,461 rows post-cleanup)
eDNA/PtConception/PtConMifishSchulte_spatial_review_decisions.rds     (218,311 rows post-cleanup)
Stats and Data/GreatLakes data/GreatLakes2023BurnsHarbor_spatial_review_decisions.rds  (5,044)
```

They carry `.bak_2026*` backups from the 2026-09-19 stale-seed cleanup. Back up again before
touching them.

## ORDER OF WORK

1. **Migration first, rename second.** Write and test the decision-file migration before
   changing any sentinel, so the cache is already speaking the new vocabulary when the code
   switches.
2. **Re-run the grep.** 30 sites as of 2026-09-19; it will have moved.
3. **Decide the sentinel's scope.** Occurrence-side only, or prior-side too? ce's framing is
   occurrence-side only, which removes the collision in one change and leaves
   `join_priors.R`'s wildcard meaning intact. Renaming both would be a bigger, different
   project.
4. **`habitat_candidates` as a real column** is separable from the rename and could land
   first or not at all. `resolve_habitat_by_geography()` (2026-09-19, `53e89fc`) already
   reduces how many points ever need it — measured 221 of 646 resolved on a PtConception
   extract.
5. **Coordinate with the consumer owner.** ce owns `estimate_kernel_priors()` /
   `join_priors()`; TaxaHabitat owns the column. One decision made once, or the rename lands
   here and the adaptation lands there and they disagree in the middle.

## WHAT IS ALREADY TRUE (do not redo)

- `habitat_proportions` is now **contractually** preserved through
  `flag_habitat_inconsistencies()` and re-attached by `review_spatial_flags()` (`a7e0841`).
  Before that it survived only because R copies attributes through SOME verbs — `[` and
  `dplyr::filter` keep it, `merge()` and `summarise()` drop it.
- A reviewer-resolved point's proportion vector is rewritten **one-hot** and carries
  `habitat_reviewed`, so the weights can never contradict the human decision (`a7e0841`).
- `resolve_habitat_by_geography()` adds `habitat_source` (`"consensus"` / `"geography"`), so
  there is already a provenance column to extend rather than invent (`53e89fc`).
- `.habitat_signature()` exists and is tested.

## WHAT WOULD MAKE THIS NOT WORTH DOING

If `habitat_candidates` never becomes a real column and no downstream mechanism for
multi-habitat observations is built, then "Uncertain" is a cosmetic rename of a sentinel that
only two functions read, for 30 edit sites and a three-file cache migration. ce's own verdict
on 2026-09-19 was that **no such mechanism exists** and composite should stay a review queue.
Re-check that before starting: if it is still true, the honest answer may be a comment in
both files explaining the two meanings, not a rename.
