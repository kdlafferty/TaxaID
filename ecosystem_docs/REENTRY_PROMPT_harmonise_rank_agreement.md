# assign_sampling_group(harmonise = TRUE) accepts a homonym at the wrong rank

**Status: CLOSED 2026-09-15 (Opus 5). Implemented in BOTH harmonisers, tested,
and verified end-to-end on the real 18S run.** See the "What was built" section
at the bottom, and CLAUDE.md's dated entry. The one thing still outstanding is
that PtCon 18S Step 10 has not been RE-RUN for real -- the export on disk is
still the old one.

Original status when written: OPEN, not started. Found 2026-09-15 on the PtCon
18S rerun. Needed a package rebuild, so it was queued with a package-proofing
pass, same handling as `REENTRY_PROMPT_xml_parse_huge_reference_fetch.md`.

## The bug

`TaxaTools::assign_sampling_group(harmonise = TRUE)` calls
`.harmonise_taxonomy_to_backbone()` (`R/sampling_group.R:453`), which resolves
each unique RANK VALUE through `verify_taxon_names(backbone_id =)` and
`change_backbone()`. **It accepts whatever the backbone returns, without
checking that the matched rank is the rank of the column being harmonised.**

`verify_taxon_names()` has returned `matched_rank` since 2026-07-25, added for
precisely this hazard (the "Inu Inu" chain -- see TaxaMatch/CLAUDE.md). The
harmoniser does not read it.

## The real case

GBIF's backbone contains a **fly genus** named *Polychaeta*:

```
user_supplied_name  matched_name  matched_rank  classification_path
Polychaeta          Polychaeta    genus         Animalia|Arthropoda|Insecta|Diptera|...
```

So a row whose CLASS column reads `Polychaeta` (the annelid class -- correct in
NCBI) is matched against a GENUS in a different phylum, and the whole lineage is
overwritten:

| column | NCBI (correct) | after harmonise (wrong) |
|---|---|---|
| kingdom | Metazoa | Animalia |
| phylum | **Annelida** | **Arthropoda** |
| class | **Polychaeta** | **Insecta** |
| order | NA | **Diptera** (fabricated) |

Measured on the real run: **7 taxa, 17 rows** -- `Maldanidae`, `Aricidea`,
`Phyllochaetopterus`, `Scoloplos armiger`, `Ophelina acuminata`,
`Notomastus hemipodus`, `Capitellidae`. Every one a marine polychaete worm.

Two consequences, and the second is the dangerous one:

1. `sampling_group` becomes `terrestrial_arthropods` for all 7. **This happens
   whether or not the caller keeps the harmonised rank columns**, because the
   group is computed from them.
2. With the harmonised ranks kept, `classify_18S_functional()` then reads
   Insecta/Diptera, marks them non-marine, and the marine filter DROPS them from
   the species list. Silent -- they simply are not there.

## Why a rank-agreement check is the fix

Checked against GBIF for every rank name in the real 18S export:

| name | column rank | matched rank | agree? |
|---|---|---|---|
| Bacillariophyceae | class | class | yes |
| Dinophyceae | class | class | yes |
| Ochrophyta / Myzozoa / Cryptophyta / Annelida | phylum | phylum | yes |
| Chromista / Protozoa | kingdom | kingdom | yes |
| **Polychaeta** | **class** | **genus** | **NO** |
| Bacillariophyta | phylum | class | no (see below) |

Requiring the matched rank to equal the column's rank rejects `Polychaeta` and
keeps every legitimate resolution, including all the diatom lineage names the
2026-09-15 rerun depends on.

**The one case needing thought** is `Bacillariophyta`: NCBI files it as a PHYLUM,
GBIF matches it at CLASS rank (as `Bacillariophyceae`). That is a genuine
NCBI-vs-GBIF rank-assignment difference for the same clade, not a homonym, and
strict equality would reject it. Two defensible readings:

- Strict equality, and accept that the phylum column keeps its NCBI value for
  diatoms. Grouping is unaffected (the diatom rule is class-level by design --
  see the sampling-group work), but `classify_18S_functional()` reads phylum, so
  check whether diatoms still pass its marine test before adopting this.
- Accept a match whose rank differs but whose returned lineage still CONTAINS the
  original value (GBIF's `Bacillariophyceae` path contains `Ochrophyta`, i.e. the
  clade agrees and only the rank label moved), and reject when the lineage does
  not (GBIF's `Polychaeta` path contains no `Annelida`). This is the more precise
  rule and also catches the homonym; it costs one substring check on
  `classification_path`.

The second is recommended. Verify against both real cases before adopting either.

## How to verify

```r
d <- data.frame(kingdom = "Metazoa", phylum = "Annelida",
                class = "Polychaeta", order = NA_character_)
TaxaTools::assign_sampling_group(d, harmonise = TRUE, backbone_id = 11L,
                                 verbose = FALSE)
# WANT: phylum stays Annelida, class stays Polychaeta,
#       sampling_group = macroinvertebrates (NOT terrestrial_arthropods)
```

and re-run PtCon 18S Step 10 -- the 7 taxa above should appear in the
macroinvertebrate list, and the phytoplankton list should keep its 955 rows.

## Scope beyond 18S

`harmonise = TRUE` is currently used only by
`PtConceptionWorkflow_18S_2_single_site.R` Step 10 (added 2026-09-15 to fix F5).
But the same homonym risk applies to ANY caller harmonising an NCBI-backbone
frame against GBIF, and `CaliforniaIntertidal/scope_classifier.R`'s own
`harmonize_ranks_to_gbif()` is documented as the same idiom -- check it for the
identical gap.

A cheaper, narrower question worth asking at the same time: how many other
class-rank names in these datasets are homonyms of genera somewhere in GBIF?
`Polychaeta` was found by accident, because its taxa happened to get dropped and
the drop was noticed. A corrupted lineage that stays marine is silent.


---

# What was built (2026-09-15)

## The rule that shipped: two exact tests, not one

A resolution is accepted when EITHER holds:

1. **`matched_rank` equals the probe COLUMN's rank.** The ordinary case (90 of
   the run's 97 unique names). It is also the only thing that can vouch for a
   SYNONYM resolution, where the returned name is deliberately *not* the name
   asked about -- a name-in-lineage test alone would reject every one of those.
2. **The rank differs, but the returned lineage carries the probe name ITSELF
   at the probe's own rank.** A same-clade duplication rather than a homonym:
   GBIF holds a genus *Spionidae* inside family Spionidae, and a genus
   *Arthropoda* inside phylum Arthropoda, so the terminal match is a genus
   while every rank above it is the lineage the row already had.

A row failing both keeps its ORIGINAL taxonomy -- the same fallback an
unresolved name already got -- and is named in a warning.

## Three of this document's own claims were wrong or incomplete

**1. The recommended rule does not work as written.** This document recommended
"accept a match whose rank differs but whose returned lineage still CONTAINS the
original value", citing `Bacillariophyta`. Checked live: GBIF's answer for
`Bacillariophyta` is `Chromista|Ochrophyta|Bacillariophyceae`, which does NOT
contain `Bacillariophyta`; and NCBI gives diatoms **no kingdom at all**
(verified: `parse_classification_path(..., "kingdom")` returns NA for
*Chaetoceros*, *Thalassiosira*, *Pseudo-nitzschia*), so such a row has no other
original value to test either. The rule rescues nothing there.

Worse, the loose form is **unsafe**. Letting a `kingdom` match carry the test
re-admits *Polychaeta* for any caller whose input already says `"Animalia"`
rather than NCBI's `"Metazoa"` -- GBIF's fly-genus path starts `Animalia|...`.
Only the accident of NCBI's vocabulary made that rule look safe on this dataset.
Rule 2 above is the precise version: anchored at the probe's own rank, never at
kingdom.

**2. `Bacillariophyta` is not "the one case needing thought" -- it does not
arise.** The probe is the FINEST non-NA rank, and every diatom row in the real
run carries an ORDER (`Thalassiosirales`, `Bacillariales`, ...), which resolves
rank-for-rank. `Bacillariophyta` is not among the 97 names the run resolves.
Rejecting it is harmless anyway: the diatom rule is class-level by design and
`classify_18S_functional()` keys diatoms on the CLASS
(`diatom_cls <- c("Bacillariophyceae", ...)`), never on that phylum value.

**3. "How many other class-rank names are homonyms?" -- answered, and the
answer is not zero.** Scanning every (name, rank) pair in the run's NCBI-side
taxonomy (288 pairs) against GBIF found **15 rank disagreements**. Rule 2
rescues 8. Of the 7 rejected, **five are genuine cross-lineage homonyms**:

| name | column rank | what GBIF actually matched |
|---|---|---|
| Polychaeta | class | tachinid fly genus, `Animalia\|Arthropoda\|Insecta\|Diptera\|Tachinidae\|Polychaeta` |
| Ctenophora | phylum | crane-fly genus, `Animalia\|Arthropoda\|Insecta\|Diptera\|Tipulidae\|Ctenophora` |
| Ciliophora | phylum | a **FUNGUS** genus, `Fungi\|Ascomycota\|Ciliophora` |
| Appendicularia | class | a flowering-plant genus, `Plantae\|Tracheophyta\|Magnoliopsida\|Myrtales\|Melastomataceae\|Appendicularia` |
| Pilidiophora | class | a gregarine genus, `Chromista\|Myzozoa\|Conoidasida\|Eugregarinorida\|Actinocephalidae\|Pilidiophora` |

The other two rejections (`Bacillariophyta`, `Bigyra`) are real NCBI-vs-GBIF
rank-assignment differences for the same clade, not homonyms; they fall back to
their NCBI values harmlessly.

This document's own closing intuition was right: *Polychaeta* was found only
because its taxa were dropped and the drop was noticed. Four more were sitting
in the same dataset, and a corrupted lineage that stays marine is silent.

## Files changed

- **`TaxaTools/R/sampling_group.R`** -- `.harmonise_taxonomy_to_backbone()` now
  records each probe's SOURCE RANK, carries `matched_rank` through the lookup
  (taken from `verify_taxon_names()`'s own output, not `change_backbone()`'s
  pass-through), and applies the gate before the write-back. New roxygen
  section *Rank agreement*. Also fixed while there: the cache-merge `rbind()`
  subset only the cached side, so it errored whenever a later batch resolved a
  rank the cached one never carried.
- **`eDNA/CaliforniaIntertidal/scope_classifier.R`** -- `harmonize_ranks_to_gbif()`
  gets the identical gate. It already tracked `probe_rank`, but only for
  reporting. A rejected row is treated exactly as an unresolved one, so the
  existing `fallback_to_source` path restores its source taxonomy. New
  `gbif_rank_rejected` output column so the count is visible, not silent.
- **`TaxaTools/tests/testthat/test-sampling_group.R`** -- 6 new tests, fully
  offline (only `verify_taxon_names()` is mocked, so `change_backbone()`'s real
  path parsing is exercised). Every fixture row is a verified live GBIF answer.
  63 pass, 0 fail.

## Stale caches are discarded, not trusted

A cache written before the gate carries no `matched_rank`, so its entries cannot
be checked. Both functions detect that and re-resolve rather than reuse --
re-running with an old `cache_dir` is exactly when a silent re-admission would
be least likely to be noticed. Two such caches hold the corrupted *Polychaeta*
lineage on disk right now and will be discarded on their next run:
`PtCon18SSchulte_sampling_group_harmonise_cache/sampling_group_harmonise_cache.rds`
and `CaliforniaIntertidal/gbif_rank_lookup.rds`.

## Verification

The document's own `assign_sampling_group()` snippet now returns
`phylum = Annelida`, `class = Polychaeta`,
`sampling_group = macroinvertebrates`, with a warning naming the rejection.

Step 10 was then replayed for real from `PtCon18SSchulte_reviewed.rds` (the
saved pre-export checkpoint), reproducing the run's taxonomy, harmonisation,
`classify_18S_functional()` and marine filter:

- all **7 taxa / 17 rows** group `macroinvertebrates` and **all 17 pass
  `marine = TRUE`**, so none is dropped;
- `macroinvertebrates` **491 -> 508** (exactly the 17 recovered rows);
- `phytoplankton` **955**, `macroalgae` 190, `zooplankton` 312, `parasites` 1,
  `NA` 7 -- all unchanged, as required.

## Still outstanding

**The 18S export on disk is still the old one** -- Step 10 has not been re-run
for real, only replayed. `PtCon18SSchulte_final_consensus.csv` and the
`*_macroinvertebrates_final_species_list.csv` still lack the 7 taxa.

`TaxaMatch::convert_taxonomy_backbone()` was checked and does NOT have this gap:
it has read `matched_rank` since 2026-07-25 and clears ranks finer than the
matched one. The other `change_backbone()` callers (`TaxaExpect_workflow.R`,
`TaxaFetch/inst/*_workflow.R`) translate a `taxon_name` rather than expanding a
higher-rank name into a row's whole lineage, so the hazard does not apply.

`R CMD check` on TaxaTools: **1 error, pre-existing and unrelated**
(`vignettes/name-cleaning.Rmd`, `object 'match_df' not found`), 0 warnings,
0 notes.
