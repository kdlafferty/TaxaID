# Session A Re-entry Prompt: Data-Type Generalization Audit

## Context

The TaxaID ecosystem (9 R packages) was built primarily around DNA sequence data but has
begun expanding to acoustic data (BirdNET, Sessions 87–89) and plans to support image data
(camera traps via Animl). The goal of Session A is to audit every exported function and
every LLM prompt across all packages and produce a written plan for making functions and
workflows data-type agnostic or explicitly named.

**Do NOT implement changes in Session A. Output is a plan document only.**

## Background to read before starting

1. Check memory files in `~/.claude/projects/.../memory/` — specifically:
   - `project_data_type_audit_task.md` (full task description and current status)
   - `project_workflow_acoustic_todo.md` (acoustic-specific pending items)
2. Review `TaxaID/CLAUDE.md` (ecosystem overview, function inventory, name change log)
3. Key recent changes (Sessions 87–89):
   - `TaxaMatch::read_birdnet_output()` — new function, ingests BirdNET CSV
   - `TaxaLikely::build_acoustic_reference()` — acoustic analog of `build_sequence_matrix()`
   - `TaxaLikely::fetch_reference_recordings()` — Xeno-canto analog of `fetch_reference_sequences()`
   - `TaxaLikely/inst/workflows/3b_acoustic_reference_workflow.R` — acoustic training workflow
   - `4_score_to_likelihood_workflow.R` — generalized for DNA + acoustic

## Audit scope

For each package below, read all exported function signatures and roxygen docs, then
assess each function against the three audit questions.

**Packages to audit (in dependency order):**
1. TaxaTools
2. TaxaMatch
3. TaxaLikely
4. TaxaFetch
5. TaxaHabitat
6. TaxaExpect
7. TaxaAssign
8. TaxaFlag
9. TaxaWizard

## Three audit questions per function

1. **Name**: Is the function name data-type-neutral, or does it imply a specific data type?
   - Correctly specific: `build_sequence_matrix()`, `read_birdnet_output()`
   - Incorrectly generic (hidden assumptions): flag these
   - Incorrectly specific (could easily be generic): flag these

2. **Logic**: Does the function body or its LLM prompts contain data-type-specific
   assumptions that would break or mislead for acoustic/image data?
   - Highest risk: `assign_taxa_llm()`, `suggest_unreferenced_species()`, `build_context()`,
     `review_assignments()`, TaxaWizard phase prompts (phase_classify.md, phase_parameterize.md)
   - Also check: any function that mentions "barcode", "accession", "BLAST", "sequence",
     "percent identity" in its logic or error messages

3. **Variants needed**: Does this function need a data-type-specific variant that doesn't
   exist yet?
   - Known gap: `read_animl_output()` (camera trap images, planned since Session 55)
   - Look for other gaps

## Output format

Produce a single markdown plan document saved to:
`TaxaID/ecosystem_docs/DATA_TYPE_AUDIT_PLAN.md`

Structure:
```
# Data-Type Generalization Audit Plan

## Summary
- N functions audited across 9 packages
- N rename proposals
- N new functions needed
- N prompt edits needed
- N breaking changes

## Per-package findings

### TaxaTools
[table: function | issue type | proposal | breaking?]

... (one section per package)

## LLM prompt audit
[list each prompt file/string, specific problematic text, proposed fix]

## New functions needed
[function name | package | data type | analogous existing function]

## Breaking changes
[list with migration notes]
```
