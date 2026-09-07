# Re-entry prompt — TaxaWizard metadata re-sync

**Written 2026-09-05.** Deliberately deferred to the END of the current cleanup arc
(TaxaWizard sync, critical fix-review, Fable's ecosystem pass) per the user's own explicit
call: "leave TaxaWizard to the end, who knows what else might change" -- more of the
ecosystem's real function signatures are still actively changing (the 18S PtConception
run is live as of this writing, plus whatever the critical-review pass below turns up),
and re-syncing TaxaWizard's metadata now would likely need re-doing again before this is
actually released.

## What this is

TaxaWizard's conversational workflow-builder reads `inst/metadata/*.json` (one file per
TaxaID package) to know what functions exist, their real parameter names/defaults, and
how they chain together (`inst/graph/workflow_graph.json` + `inst/graph/snippets/*.R`).
This is pure documentation/config -- no runtime dependency on the packages themselves --
which means it silently drifts out of sync with real code whenever a function's signature
changes and nobody remembers to update the matching JSON entry. This has happened
repeatedly (see `[[project_taxawizard_metadata_drift]]` in the memory system, and
TaxaWizard/CLAUDE.md's own 2026-08-09 "metadata-drift audit" session note, which found
95 real drift findings across 4 packages that hadn't been touched since 2026-07-24).

## Why this matters now

Since that 2026-08-09 audit, at least three entire new mechanisms have shipped that
TaxaWizard's graph/metadata has **never been told about at all** (not drift -- genuinely
missing capability, the graph literally cannot route a conversation to these):

1. **The kernel-based prior estimator** (`TaxaExpect::estimate_kernel_priors()`,
   `calibrate_kernel_bandwidth()`, `apply_undetected_evidence()`) -- an entire alternative
   to the GLMM/grid prior path the graph currently only knows about.
2. **The BLAST-based reference-quality screening pipeline** (`TaxaMatch::
   evaluate_reference_accessions()`, `reference_label_verdict.R`'s `score_reference_labels()`,
   `refine_reference_verdicts()`, `corroborate_references_locally()`, `verify_removal_candidates()`,
   `review_flagged_accessions()`) -- a whole new node/edge family in the reference-quality
   space (a smaller BLAST-based screen already got wired into `seq_to_match.R` per
   TaxaWizard/CLAUDE.md's 2026-08-09 note, but that predates most of what's listed above).
3. **`plot_theta_surface()`** (TaxaExpect) -- a new visualization/review gadget, same
   "interactive gadget, no graph representation" category as `review_spatial_flags()` etc.
   (a deliberate, already-documented design choice for gadgets, not an oversight -- see
   TaxaWizard/CLAUDE.md's 2026-08-09 note's item 3 for the precedent).

Plus the usual signature-level drift on everything else that changed in the interim
(see `TaxaAssign/CLAUDE.md`, `TaxaMatch/CLAUDE.md`, `TaxaExpect/CLAUDE.md`'s top session
notes as of 2026-09-04/05 for the full list of what changed -- `add_slash_taxon()`'s
order-invariance fix, `review_assignments()`'s cache/join-key fixes, every new param on
`evaluate_reference_accessions()`, etc.).

## How to do this (matches the established pattern exactly)

1. Re-run the existing structural auditor:
   `Rscript diagnostics/taxawizard_metadata_audit.R` (from the TaxaID root) --
   `formals()`-vs-metadata diff against the real installed packages. Re-install every
   package first (`source("ecosystem_docs/install_all.R")`) so the audit reflects current
   code, not a stale library.
2. Triage findings the same way the 2026-08-09 session did: Tier 1 = graph-wired (a real
   snippet calls this function with a wrong/missing param -- would break or misbehave on
   first real use), Tier 2 = metadata-only (no snippet calls it directly, but a generated
   interview/error-fix suggestion could still be wrong). Fix Tier 1 first.
3. For the three missing mechanisms above, this is NOT a metadata fix -- it's new
   node/edge design, matching the pattern the 2026-08-09 session used for `generate_domestic_food_priors()`/`flag_institution_candidates()` (extend an existing edge's snippet in place, gated behind a boolean placeholder) vs. a genuinely new edge (`kernel-priors` warrants its own alternative `dist_to_priors`-style edge, parallel to the existing GLMM one, not a gated extension -- it's a different estimator, not an add-on step).
4. Verify with `TaxaWizard:::.compute_paths()` directly (not just JSON validity) that a
   few representative multi-step paths still resolve after your edits, same as every prior
   audit did.
5. Update this file's own status line and TaxaWizard/CLAUDE.md's top session note when
   done, per this project's own documentation convention.

## What NOT to do

Don't attempt this until the live 18S PtConception run (and whatever it turns up) has
settled, and until the critical fix-review pass (`ecosystem_docs/REENTRY_PROMPT_critical_fix_review_and_changelog.md`) is done -- both are likely to touch function signatures again, which would mean re-doing part of this sync.

**Status: Steps 1-2 (metadata drift audit + fixes) and step 4 (path-computation
verification) done 2026-09-07 -- see TaxaWizard/CLAUDE.md's own top session note for the
full record (13 genuine fixes, 44 -> 30 remaining findings all confirmed noise/intentional
design). Step 3 (new node/edge design for the 3 wholly-missing mechanisms below) NOT yet
done -- this is a separate, larger design task, not a metadata sync, deliberately not
attempted in the same pass.**
