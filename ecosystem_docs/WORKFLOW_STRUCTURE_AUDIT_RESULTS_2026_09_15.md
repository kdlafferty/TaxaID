# Production workflow structural audit — RESULTS

**Run 2026-09-15.** Executes steps 1-3 of
`REENTRY_PROMPT_workflow_structure_audit.md`'s "How to do the outlining". Steps 4
(template/graph decisions) and the graph wiring are left for the user, per that doc.

Raw machine-generated outlines: `workflow_structure_outlines_2026_09_15.txt`
(section banner, `message("--- Step N")`, resolved `pkg::function` call set, and
`.save()`/`saveRDS()` checkpoints, per section, for all 8 files).

All three repos are now under git (`eDNA/`, `GreatLakes data/`, and the `TaxaID/`
monorepo), so every claim below is checkable with `git log -p`.

---

## 1. The 2026-09-06 file inventory was stale in four ways

| 2026-09-06 survey said | Reality on 2026-09-15 |
|---|---|
| `PtConceptionWorkflow_12S_multi_site.R`, 1,771 lines, live | **Retired** in commit `1bba8c5` (2026-09-13). Superseded by `_12S_multi_site_FAST.R` |
| `MuguWilderFishWorkflow.R`, 1,684 lines, live | **Retired** — moved to `SepulvedaMugu/_archive_retired_scripts_2026_09_12/`, which `.gitignore` excludes |
| (not listed) | **`CaliforniaIntertidal/CaliforniaIntertidalWorkflow_multi_marker.R`**, 835 lines, added in `7c4d431` |
| (not listed) | **`PtConceptionWorkflow_12S_multi_site_FAST.R`**, 781 lines — the real multi-site path |

Every surviving file has also grown 15-30% since the survey. Current inventory:

| File | Location | Lines | Family | Status |
|---|---|---:|---|---|
| `TaxaID_Workflow_Template_TEST.R` | `TaxaID/inst/` | 1,635 | generic 0,2,2.5,3-8 | **structurally dead — see §4** |
| `TaxaID_eDNA_Workflow_Template.R` | `eDNA/PtConception/` | 1,506 | single-marker 0-10 | canonical template, behind on 4 subsystems (§3) |
| `PtConceptionWorkflow_12S_single_site.R` | `eDNA/PtConception/` | 2,735 | single-marker 0-10 | running |
| `PtConceptionWorkflow_18S_2_single_site.R` | `eDNA/PtConception/` | 2,937 | single-marker 0-10 | running |
| `PtConceptionWorkflow_12S_multi_site_FAST.R` | `eDNA/PtConception/` | 781 | resume/partial (0, 2.5, 5, 5.5, 8-10) | running |
| `GreatLakes2023_ConsensusWorkflow.R` | `Stats and Data/GreatLakes data/` | 2,419 | single-marker 0-10 (+1.5, 8j, 8k) | running |
| `MuguFishWorkflow.R` | `eDNA/SepulvedaMugu/` | 2,425 | multi-marker 0-11 | running |
| `CaliforniaIntertidalWorkflow_multi_marker.R` | `eDNA/CaliforniaIntertidal/` | 835 | multi-marker on 0-10 | **scaffold, 31 `## STUB`s** |

## 2. Both of the prompt's "two real findings, deliberately NOT fixed" are now closed

- **`lab_contaminant_risk` latent break — CLOSED, no action needed.** Of the two
  files named, one (`_12S_multi_site.R`) is retired and the other
  (`TaxaID_Workflow_Template_TEST.R`) was fixed: its line 350 now reads
  `filter(validity_flag=="invalid_lab_contaminant")`. A sweep of all 8 live files
  found **zero** surviving `lab_contaminant_risk` *filters* — the remaining textual
  hits are comments recording the 2026-07-24 rename, plus a deliberate
  back-compatibility shim in the 18S workflow (lines 2037-2050) that maps the old
  column onto the `validity_flag` schema.
- **18S_2's "missing Section 6" — was never real.** `# 6.  MATCH STANDARDISATION`
  sits at line 1449 with an inline comment explaining that
  `standardize_match_data()`/`convert_taxonomy_backbone()` legitimately moved to
  Step 1 (the GBIF fetch needs backbone-resolved taxonomy), leaving Step 6 as a
  provenance join. Labelled during a 2026-09-07 pass. The original survey's regex
  simply missed it.

## 3. What the canonical template has fallen behind on

`TaxaID_eDNA_Workflow_Template.R` is the template all three single-marker
production scripts were built from. Four subsystems now exist in **all three**
production scripts and in **none** of the template:

| Subsystem | Template | 12S | 18S | GL |
|---|---|---|---|---|
| Kernel priors (`calibrate_kernel_bandwidth`, `estimate_kernel_priors`, `plot_theta_surface`) | — | X | X | X |
| Reference screen (`fetch_ncbi_reference_sequences`, `corroborate_references_locally`, `match_driving_accessions`, `evaluate_reference_accessions`, `review_flagged_accessions`, `resolve_review_overrides`, `verify_removal_candidates`, `remove_incongruent_references`) | — | X | X | X |
| H1 calibration (`calibrate_query_noise`) | — | X | X | X |
| Report assembly (`report_fetch`/`report_habitat`/`report_priors`/`report_likelihood`/`report_assign`/`report_flags`, `assemble_report`, `generate_report`) | — | X | X | X |

Also template-only: `compute_group_priors` and `flag_watch_candidates` are missing
from its Section 8. The template is **not** abandoned — it was last touched
2026-09-14 — it just never received the kernel-priors or reference-screen
migrations.

**One latent break found and fixed in this pass.** Template line 280 called
`TaxaFetch::define_search_polygon()`; that function is exported by **TaxaTools**,
not TaxaFetch (TaxaFetch's own Rd cross-references point at `[TaxaTools]`). All
three production scripts already call it correctly. As written the template threw
`'define_search_polygon' is not an exported object from 'namespace:TaxaFetch'` at
its first GBIF step. Changed to `TaxaTools::` on both lines 280 and 419 (the latter
commented); file re-parses cleanly. This is the same shape of bug as the
`lab_contaminant_risk` finding: a rename that propagated to the production scripts
but not to their template.

## 4. `TaxaID_Workflow_Template_TEST.R` — the decision the prompt asked us to raise

The evidence is now decisive, and it is worse than "possibly stale". Its Section 5
calls **eight functions that no longer exist in any of the nine packages**:

```
TaxaExpect::optimize_grid_size          (L939)
TaxaExpect::create_sites_from_grid      (L941, L1019)
TaxaExpect::prepare_model_dataframe     (L943)
TaxaExpect::compute_moran_basis         (L958)
TaxaExpect::screen_spatial_formula      (L998)
TaxaExpect::generate_full_priors        (L1085)
TaxaExpect::plot_theta_map_interactive  (L1137)
```

These are the pre-kernel-pivot focal-grid/GLMM prior API. They are **not guarded** —
no `if (USE_KERNEL_PRIORS)` branch, no deprecation comment — so the file cannot run
past line 939. It also has no Step 1 (load), no match-standardisation step, and no
filter+output step, and its numbering is off by one against every production script
(its Step 6 = TaxaLikely; production Step 7 = TaxaLikely).

Yet it was last committed **2026-09-14**, same day as everything else. It is in
exactly the state `PtConceptionWorkflow_12S_multi_site.R` was in when it was retired
in `1bba8c5`: *"kept receiving ecosystem-wide patches, so it looked alive."*

Contrast `MuguFishWorkflow.R` lines 890-901, which calls three of the same dead
functions — but inside the `else` branch of a hardcoded `USE_KERNEL_PRIORS <- TRUE`,
explicitly annotated *"This else branch is no longer functional."* That is
documented dead code, not a break; no action needed there.

**DECIDED 2026-09-15: RETIRED**, at the user's instruction. Moved with its `.bak`
to `archive_retired_workflow_template_2026_09_15/` (README there), `git rm`'d from
`inst/`, and excluded from the package build via `.Rbuildignore`. Recorded in
`NAME_CHANGE_HISTORY.md`.

Two things the retirement itself turned up:

- The seven functions are **not lost** -- they sit in
  `TaxaExpect/archive_glmm_prior_pipeline/R/`, archived 2026-09-09 when the GLMM
  prior-fitting chain was retired. This template was that chain's **last remaining
  caller**, which is the cleaner statement of why it had to go.
- The root `README.md` was advertising it as *"a genuinely runnable, self-contained
  worked example that exercises the full pipeline end to end"* and as the way to
  *"confirm your installation and API keys work"*. That has been false since
  2026-09-09. Corrected.

**Open gap this leaves:** the `TaxaID` package now bundles no end-to-end runnable
example. The canonical template lives in the separate `eDNA` repo and is itself
behind on the four subsystems in §3.

## 5. Real structural divergences within the single-marker family

Everything below is a genuine difference, not a regex artifact. Most have a
defensible reason; the two marked **GAP** do not.

- **Evidence-generation block placement.** 12S and GL build occurrence-side evidence
  (`generate_domestic_food_priors`, `condition_evidence_on_habitat`,
  `generate_regional_proximity_evidence`, `generate_presence_curve_evidence`,
  `apply_undetected_evidence`, `check_inat_range`, `generate_inat_range_evidence`,
  `generate_invasive_watch_evidence`) inside **Section 7**; 18S does the identical
  block in **Section 5**. Same functions, same order, different section. Worth
  settling on one, since it drives where a reader looks.
- **Match standardisation position.** 12S and the template do it at Step 6; 18S and
  GL do it at Step 1 and leave Step 6 as a provenance join. Both 18S and GL document
  why inline. Legitimate, but it means "Step 6" is not comparable across the family.
- **GL promotes 8j/8k to top-level banners** (`SCORE-BASED CONSENSUS`,
  `LLM-SHORTCUT CONSENSUS`) where 12S/18S keep them as sub-comments inside Section 8.
  GL is also the only file with an `LLM-SHORTCUT` comparison arm at all, and the only
  one with a `1.5 TAXONOMIC SCOPE FILTER`.
- **GAP — GreatLakes has no token accounting.** It makes 12 LLM calls
  (`call_anthropic_api`, `assign_habitat_biological`, `review_assignments`,
  `assign_taxa_llm`) but calls `token_usage()` / `reset_token_usage()` **zero** times.
  Every other workflow reports token usage in Sections 4, 9 and 10 and stores it in
  session metadata. GL's runs therefore carry no cost record.
- **GAP — `flag_incongruent_references` is in 12S and 18S but not GL**, even though
  GL runs the rest of the reference screen (`evaluate_reference_accessions`,
  `verify_removal_candidates`, `remove_incongruent_references`). Worth confirming
  this is deliberate rather than a missed propagation.
- `reset_token_usage` is called only by 18S; `assign_sampling_group` only by 18S
  (12S/GL reference `sampling_group` solely inside `dplyr::any_of()`, which tolerates
  the column's absence — not a bug).
- Checkpoint counts diverge widely: template 18, 12S 29, 18S 30, GL 36. GL's extra
  checkpoints are its score-consensus and LLM-shortcut comparison arms; 18S's are
  SILVA and multi-fit kernel objects.

## 6. Numbering families: there are now three, not two

The prompt records "two legitimate numbering families". `CaliforniaIntertidal` adds a
third pattern — it is **multi-marker but numbered like the single-marker family**:

| Step | Single-marker (12S/18S/GL) | Mugu (multi-marker) | CalIntertidal (multi-marker) |
|---|---|---|---|
| 5 | TaxaExpect priors | TaxaExpect priors | Kernel priors |
| 6 | Match standardisation | Scored likelihoods | Match standardisation |
| 7 | TaxaLikely | Round 1 Bayes | Scored likelihoods |
| 8 | TaxaAssign | Cross-marker prior update | Bayes (multi-site + multi-marker) |
| 9 | **TaxaFlag review** | **Round 2 Bayes** | **TaxaFlag review** |
| 10 | Filter + output | TaxaFlag review | Filter + output |
| 11 | — | Filter + output | — |

CalIntertidal collapses Mugu's Round-1/cross-marker/Round-2 trio into a single
Section 8, which re-aligns Steps 9 and 10 with the single-marker family. That is
arguably the better convention — it means "Step 9" finally means TaxaFlag review in
three of the four running workflow shapes — but right now Mugu is the odd one out
and nothing records which is intended.

CalIntertidal is a **scaffold, not drift**: 31 explicit `## STUB` markers, no data
yet (per the Altstatt dependency). Its gaps should not be read as divergence.

## 7. TaxaWizard graph vs. ground truth

`TaxaWizard/inst/graph/workflow_graph.json`: 25 nodes (10 inputs / 9 intermediates /
6 outputs) and 32 edges naming 65 functions.

- **The graph is internally sound.** Every one of its 65 named functions is genuinely
  exported by the package that claims it — **0 invalid references**. The hand-sync
  against `NAMESPACE` described in `[[project_taxawizard_metadata_drift]]` is working.
- **But it under-covers reality.** The five running production workflows call **89**
  ecosystem functions; **41 of those appear in no edge**. Of those 41, **eight are
  called by all five workflows**, so they are unambiguous graph gaps rather than
  site-specific extras:

  `add_posthoc_assessment`, `adjust_inat_range_priors`, `apply_coverage_constraints`,
  `call_anthropic_api`, `expand_unreferenced_hypotheses`, `fill_higher_ranks`,
  `flag_watch_candidates`, `scientific_to_common`

  The other 33 are used by 3-4 of 5 (the reference-screen chain, the report-assembly
  chain, the spatial-review trio, the evidence generators).
- The 17 graph functions that no running workflow uses are **not** errors — they are
  TaxaWizard's alternate entry points (BirdNET, image classifiers, CRABS/local FASTA,
  the `run_*_pipeline` wrappers) which no eDNA site exercises.

Per the prompt's own warning, none of this has been wired into the graph. The gap
list above is the evidence a future pass would need; the graph itself is untouched.
