# Re-entry prompt — workflow structure audit, remaining items

**Written 2026-09-15**, after steps 1-3 of `REENTRY_PROMPT_workflow_structure_audit.md`
were executed. Evidence for everything below:
`WORKFLOW_STRUCTURE_AUDIT_RESULTS_2026_09_15.md` (+ the raw
`workflow_structure_outlines_2026_09_15.txt`). That prompt's steps 1-3 are DONE and its
two "real findings" are CLOSED; step 4a (retire the generic template) is DONE. What is
left is below, ordered cheapest-first, with an honest cost estimate for each.

**A and B were completed 2026-09-15** (commits `01c0d7f`, `d33487b` in the GreatLakes
repo); neither has been RUN yet, so the next real GreatLakes run is their first
verification. **C onward are open.** The session that wrote this was near a token limit
and stopped after the two cheap items deliberately.

Reproduce any outline with the extractor described in the results doc: banner sections
are a `# ===` / `# N.  TITLE` / `# ===` **triple** (requiring the closing rule is what
stops `# 18S spans many kingdoms` from parsing as section "18S"), and bare calls resolve
against the union of the nine `NAMESPACE`s.

---

## A. GreatLakes has no token accounting -- DONE 2026-09-15 (commit 01c0d7f)

`GreatLakes2023_ConsensusWorkflow.R` makes **12** LLM calls (`call_anthropic_api`,
`assign_habitat_biological`, `review_assignments`, `assign_taxa_llm`) and calls
`token_usage()` / `reset_token_usage()` **zero** times. Every sibling reports token usage
in Sections 4, 9 and 10 and stores it in session metadata, so GreatLakes runs carry no
cost record at all.

**Resolved:** five reporting-only additions -- `reset_token_usage()` at load, a report
after the habitat LLM and after `review_assignments()`, a whole-run total beside the
elapsed-time line, and the captured text into `session_meta$token_usage`. Parses cleanly,
**not yet run**. Original note follows.

Copy the pattern from `PtConceptionWorkflow_12S_single_site.R` (Section 4 tail, Section 9
tail, Section 10's `session_meta`). 18S additionally calls `reset_token_usage()` in
Section 0 -- worth adopting so a re-run in a warm session does not inherit the previous
run's counter. Purely additive; no result changes. Verify with `parse()` and one cheap
warm section, not a full run.

## B. `flag_incongruent_references` missing from GreatLakes -- DONE 2026-09-15 (commit d33487b)

**Resolved: a real propagation miss, not deliberate.** Checked first, since this audit
had already been wrong about a GreatLakes "gap" once. The surrounding comments explain
the removal and override logic in detail and never mention the annotation step, and no
site would want less provenance than its siblings. `flag_incongruent_references()` added
after `remove_incongruent_references()`; additive, drops no row, changes no removal
decision. Parses cleanly, **not yet run**. Original note follows.

12S and 18S both call it; GreatLakes runs the rest of the reference screen
(`evaluate_reference_accessions`, `verify_removal_candidates`,
`remove_incongruent_references`) but not this. **Decide whether that is deliberate before
changing anything** -- `[[feedback_verify_purpose_before_flagging]]`, and the audit has
already been wrong once about a GreatLakes "gap" (its Section 6 heading, 2026-09-06).
Read the surrounding comments and `git log -p` that block first. If it is a genuine
propagation miss, it is a one-line addition; if deliberate, add the inline comment saying
so, which is what the other two sites' equivalents have.

## C. Evidence-block placement: 18S Section 5 vs 12S/GL Section 7 (CHEAP, DECISION ONLY)

All three build the same occurrence-side evidence with the same functions in the same
order -- `generate_domestic_food_priors`, `condition_evidence_on_habitat`,
`generate_regional_proximity_evidence`, `generate_presence_curve_evidence`,
`apply_undetected_evidence`, `check_inat_range`, `generate_inat_range_evidence`,
`generate_invasive_watch_evidence` -- but 18S does it in **Section 5** and 12S/GreatLakes
in **Section 7**. Not a bug; it drives where a reader looks and whether "Step 7" is
comparable across the family. Pick one and record the reason. **Do not renumber** without
a separate decision -- the parent prompt's safety note about live scripts with real
checkpointed `.rds` state still stands.

## D. Bring the canonical template current (EXPENSIVE -- the big one)

`eDNA/PtConception/TaxaID_eDNA_Workflow_Template.R` is the template the three PtConception
production scripts were built from, and is now the ONLY template (the generic one was
retired 2026-09-15). It is missing four subsystems that **all three** production scripts
have:

| Subsystem | Functions |
|---|---|
| Kernel priors | `calibrate_kernel_bandwidth`, `estimate_kernel_priors`, `plot_theta_surface` |
| Reference screen | `fetch_ncbi_reference_sequences`, `corroborate_references_locally`, `match_driving_accessions`, `evaluate_reference_accessions`, `review_flagged_accessions`, `resolve_review_overrides`, `verify_removal_candidates`, `remove_incongruent_references` |
| H1 calibration | `calibrate_query_noise` |
| Report assembly | `report_fetch`/`report_habitat`/`report_priors`/`report_likelihood`/`report_assign`/`report_flags`, `assemble_report`, `generate_report` |

Plus `compute_group_priors` and `flag_watch_candidates` in its Section 8.

This is real porting work, not a sweep: the reference screen alone is ~400 lines in 12S
single-site and carries its own checkpoints and cache directories. Budget a full session.
Port FROM `PtConceptionWorkflow_12S_single_site.R` (the most complete single-marker
script) and keep the template's own generic placeholders rather than its source's site
constants. One latent break was already fixed here 2026-09-15
(`TaxaFetch::define_search_polygon` -> `TaxaTools::`); re-run the namespace sweep
afterwards, since porting is exactly how that class of bug arrives.

## E. A Mugu-family template (EXPENSIVE, and ask first)

Step 4b of the parent prompt. No multi-marker template exists. Since
`MuguWilderFishWorkflow.R` was archived 2026-09-12, `MuguFishWorkflow.R` is the only
RUNNING multi-marker workflow, and `CaliforniaIntertidalWorkflow_multi_marker.R` is a
scaffold (31 `## STUB`s, waiting on Altstatt data). A template generalised from one
running instance plus one scaffold may not be worth building yet -- **ask before
starting.** See F first: the two disagree about numbering.

## F. Three numbering families, and no record of which is intended (DECISION ONLY)

The parent prompt records two. CalIntertidal is a third: multi-marker but numbered like
the single-marker family, because it collapses Mugu's Round-1 / cross-marker-update /
Round-2 trio into a single Section 8.

| Step | single-marker | Mugu | CalIntertidal |
|---|---|---|---|
| 8 | TaxaAssign | cross-marker prior update | Bayes (multi-site + multi-marker) |
| 9 | **TaxaFlag review** | **Round 2 Bayes** | **TaxaFlag review** |
| 10 | Filter + output | TaxaFlag review | Filter + output |
| 11 | — | Filter + output | — |

CalIntertidal's convention makes "Step 9" mean TaxaFlag review in three of four workflow
shapes. That is arguably right, but Mugu is then the odd one out and nothing says whether
that is intended or drift. Settle this BEFORE E -- a Mugu-family template bakes one
answer in.

## G. TaxaWizard graph coverage (MEDIUM; the graph itself is correct, do not rush)

`TaxaWizard/inst/graph/workflow_graph.json` is **internally sound**: all 65 functions
named across its 32 edges are genuinely exported -- 0 invalid references -- so the
hand-sync against `NAMESPACE` described in `[[project_taxawizard_metadata_drift]]` works.
The gap is coverage, not correctness. The five running workflows call **89** ecosystem
functions; **41** appear in no edge. Eight are called by all five and are therefore
unambiguous gaps rather than site-specific extras:

    add_posthoc_assessment, adjust_inat_range_priors, apply_coverage_constraints,
    call_anthropic_api, expand_unreferenced_hypotheses, fill_higher_ranks,
    flag_watch_candidates, scientific_to_common

The other 33 are used by 3-4 of 5 (the reference-screen chain, the report-assembly chain,
the spatial-review trio, the evidence generators). The 17 graph functions that no workflow
uses are **not** errors -- BirdNET, image classifiers, CRABS/local FASTA and the
`run_*_pipeline` wrappers are alternate entry points no eDNA site exercises; leave them.

Start with the eight. Each needs a home: a new edge, or an existing edge's `functions`
list. The parent prompt's warning holds -- the graph is hand-audited and currently
correct, so wiring in something unverified risks the opposite of the goal. Regenerate the
89-function list from the outlines file rather than trusting this one if time has passed.

## H. The package bundles no end-to-end runnable example (OPEN, needs a decision)

Retiring `inst/TaxaID_Workflow_Template_TEST.R` removed the only one. The canonical
template lives in the separate `eDNA` repo and is site-specific (PtConception coordinates
and file paths), so it cannot simply be copied into `inst/`. Options: build a genuinely
generic template in `inst/` from the corrected canonical one (after D), point the README
at the per-package `inst/workflows/*.R` and accept the gap (what it says today), or
bundle a small fixture-driven smoke test instead. Not decided.
