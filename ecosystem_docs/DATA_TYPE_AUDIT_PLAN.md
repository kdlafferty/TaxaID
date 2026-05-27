# Data-Type Generalization Audit Plan

*Session A — 2026-05-27. Plan only — no implementation.*

---

## Summary

- **~119 functions audited** across 9 packages
- **3 rename proposals** (all non-breaking)
- **4 new functions needed** (all additive)
- **4 LLM prompt edits needed** (2 critical, 2 medium)
- **4 workflow file edits needed** (headers + inline notes)
- **2 breaking changes** (both confined to TaxaAssign internals; exported signatures preserved)

### Severity legend
- 🔴 **Critical** — breaks or misleads acoustic/image users today
- 🟡 **Medium** — documentation gap; works but confuses
- 🟢 **Low** — additive gap; missing feature, no current user impact

---

## Per-package findings

### TaxaTools

TaxaTools is almost entirely data-type neutral. Two exported items are correctly
DNA-specific in name; no changes needed. The LLM API functions and taxonomy utilities
work for any observation type.

| Function / Item | Issue type | Proposal | Breaking? |
|---|---|---|---|
| `barcode_length_defaults` | Correctly specific (DNA) | No change; name is accurate | No |
| `resolve_barcode_lengths()` | Correctly specific (DNA) | No change; name is accurate | No |
| `build_report_context()` `data_type` param | 🟡 No defined vocabulary | Document allowed values: `"eDNA"`, `"acoustic"`, `"image"`, `"occurrence"` in roxygen @param | No |
| All LLM API functions | Generic | No change needed | No |
| All taxonomy utilities | Generic | No change needed | No |

**Verdict: 0 changes needed; 1 documentation clarification.**

---

### TaxaMatch

TaxaMatch has made good progress on data-type coverage. Naming is consistent.
The main gap is the planned-but-missing `read_animl_output()`.

| Function | Issue type | Proposal | Breaking? |
|---|---|---|---|
| `read_sequence_table()` | Correctly specific (DNA) | No change | No |
| `filter_sequences()` | Correctly specific (DNA) | No change | No |
| `blast_sequences()` | Correctly specific (DNA) | No change | No |
| `read_birdnet_output()` | Correctly specific (acoustic) | No change | No |
| `standardize_match_data()` | ✅ Correctly generic | No change | No |
| `filter_redundant_hypotheses()` | ✅ Correctly generic | No change | No |
| `report_match()` | ✅ Correctly generic (`data_type` param) | No change | No |
| *(missing)* `read_animl_output()` | 🟢 Gap — camera trap image input | **New function** (see §New functions) | No |

The `phase_classify.md` note "`match_df` when: BLAST output" should be updated to
include BirdNET output. See TaxaWizard section.

**Verdict: 0 code changes; 1 new function needed (additive).**

---

### TaxaLikely

TaxaLikely has the clearest separation of data-type-specific and generic functions.
The DNA side (fetch, build, flag) is correctly named. The acoustic side (fetch recordings,
build acoustic reference) is new and correctly named. The modelling layer (train, evaluate,
interpret) is fully generic.

| Function | Issue type | Proposal | Breaking? |
|---|---|---|---|
| `fetch_reference_sequences()` | Correctly specific (DNA) | No change | No |
| `read_reference_fasta()` | Correctly specific (DNA) | No change | No |
| `build_sequence_matrix()` | Correctly specific (DNA) | No change | No |
| `flag_reference_errors()` | 🟡 Correctly specific (DNA), but name sounds generic | Add `@section Scope:` note in roxygen: "Applies to DNA reference sequences only. For Xeno-canto audio, use quality grade filter. For camera trap images, guidance TBD." | No |
| `remove_flagged_references()` | 🟡 Name implies generic; logic is accession-based | Same as above: add `@section Scope:` note | No |
| `fetch_reference_recordings()` | Correctly specific (acoustic/Xeno-canto) | No change | No |
| `build_acoustic_reference()` | Correctly specific (acoustic) | No change | No |
| `audit_barcode_coverage()` | Correctly specific (DNA) | No change | No |
| `audit_reference_coverage()` | 🟡 Name implies generic; logic is NCBI taxonomy | **Rename to `audit_ncbi_species_coverage()`**. Signals that it is NCBI-specific and not applicable to non-sequence data. | No (old name can alias) |
| `apply_coverage_constraints()` | 🟡 Generic name; only works with output from barcode audit | Add `@seealso` and note: "Input `census_result` must come from `audit_barcode_coverage()` or `audit_ncbi_species_coverage()`. For acoustic data, coverage auditing differs — see Workflow 3b." | No |
| `evaluate_likelihoods()` | ✅ Correctly generic | No change | No |
| `filter_top_hypotheses()` | ✅ Correctly generic | No change | No |
| `train_likelihood_model()` | ✅ Correctly generic | No change | No |
| `interpret_model()` | ✅ Correctly generic | No change | No |
| `report_likelihood()` | ✅ Correctly generic | No change | No |
| *(missing)* `fetch_reference_images()` | 🟢 Gap — no image reference fetcher | **New function** (see §New functions) | No |
| *(missing)* `build_image_reference()` | 🟢 Gap — no image analog of build functions | **New function** (see §New functions) | No |
| *(missing)* `audit_acoustic_coverage()` | 🟢 Gap — no acoustic coverage audit | **New function** (see §New functions) | No |

**Verdict: 1 rename (additive alias OK); 2 doc notes; 3 new functions needed.**

---

### TaxaFetch

TaxaFetch is entirely generic — it operates on occurrences, PDFs, and DataONE metadata,
none of which are observation-type specific. All functions work equally for fish eDNA,
bird acoustic surveys, or camera trap data.

| Function | Issue type | Proposal | Breaking? |
|---|---|---|---|
| All PDF/DataONE/GBIF functions | ✅ Correctly generic | No change | No |

**Verdict: 0 changes needed.**

---

### TaxaHabitat

TaxaHabitat operates on species names and spatial coordinates — completely observation-type
neutral. No changes needed.

| Function | Issue type | Proposal | Breaking? |
|---|---|---|---|
| All functions | ✅ Correctly generic | No change | No |

**Verdict: 0 changes needed.**

---

### TaxaExpect

TaxaExpect operates on GBIF occurrence records, spatial grids, and biodiversity models —
all observation-type neutral. The package produces species-level prior distributions that
are consumed equally by eDNA, acoustic, and image pipelines.

| Function | Issue type | Proposal | Breaking? |
|---|---|---|---|
| All functions | ✅ Correctly generic | No change | No |

**Verdict: 0 changes needed.**

---

### TaxaAssign

TaxaAssign contains the most critical data-type specificity issues. Two functions that
sound generic (`suggest_unreferenced_species`, and within it the NCBI nucleotide queries)
are in fact DNA-only. The LLM prompts for biology/ecology are correctly generic; the
problem is the NCBI API calls in the function body.

#### assign_taxa_llm()

LLM prompts (PRIOR WEIGHT RULES, range_status values, habitat_fit) are fully
data-type-agnostic. The function accepts match scores from any source. The `marker`
parameter in `build_context()` may contain DNA marker names ("12S", "COI") or could
accept "BirdNET" — no code change needed, just documentation.

| Issue | Proposal | Breaking? |
|---|---|---|
| No explicit support for `data_type` param | Add `data_type` param (`"eDNA"`, `"acoustic"`, `"image"`) for downstream routing | No |
| `unreferenced_taxa` param note | Add `@note`: "For acoustic/image data, pass `suggest_unreferenced_species()` output obtained with `data_type='acoustic'` or `data_type='image'`" | No |

#### suggest_unreferenced_species() — 🔴 CRITICAL

The function body calls NCBI nucleotide count queries to determine whether plausible
species "have barcode sequences." This concept — "unreferenced" = no barcode sequence —
is DNA-only. For acoustic data, "unreferenced" means "not in the acoustic model training
dataset" (e.g., not in BirdNET's species list). For image data, "unreferenced" means
"not in the image classifier's training set."

The LLM plausibility prompts themselves are generic (ecology/geography) — only the
NCBI check is specific.

| Issue | Proposal | Breaking? |
|---|---|---|
| 🔴 Hardcoded NCBI nucleotide queries | Add `data_type` param. When `data_type = "acoustic"` or `"image"`: skip NCBI; instead accept a `reference_species` character vector (the model's known-species list, e.g. BirdNET species list). Return same S3 `unreferenced_species_result` structure. | No (additive param) |
| 🔴 NCBI `barcode_term` / `species_list` params | Make these `NULL` by default and ignored when `data_type != "eDNA"`. Add docs explaining the different "unreferenced" concepts by data type. | No |
| Prompt mentions "NCBI sequence-availability check" | When `data_type = "acoustic"`: change inline prompt text: "A species list check will filter species absent from the acoustic reference model — do not pre-filter based on sequence availability." | No (internal prompt) |

#### run_llm_pipeline() / run_bayesian_pipeline()

Both pipeline wrappers accept `match_df` from any source. No data-type assumptions
detected in the pipeline logic itself. The `model_rank_system` auto-detection in
`run_bayesian_pipeline()` works for both DNA (`c("family","genus","species")`) and
acoustic (`c("genus","species")`).

| Issue | Proposal | Breaking? |
|---|---|---|
| 🟡 No `data_type` routing | Add `data_type` param that is passed through to `suggest_unreferenced_species()` | No |

#### build_context()

The ecology/habitat synthesis prompt is generic. The `marker` parameter allows
"12S", "COI", or "BirdNET Acoustic" — no code change needed. Only docs needed.

#### expand_unreferenced_hypotheses()

Works on `hypothesis_type` values — fully generic.

#### score_consensus() / posterior_consensus()

Fully generic — no data-type assumptions.

**Verdict: 1 critical function fix (`suggest_unreferenced_species`), 2 additive `data_type` params, 2 doc notes.**

---

### TaxaFlag

#### review_assignments() — 🔴 CRITICAL

The LLM prompt hardcodes DNA/molecular-specific language in the contaminant guidance:

```
"For contaminant assessment, consider: Homo sapiens and domestic animals are
common contaminants in molecular studies. Common lab contaminants include
Bos taurus, Sus scrofa, Gallus gallus, and other food-source species."
```

And in the example JSON:

```
"review_comment": "Common lab contaminant in eDNA studies"
```

These lines will confuse the LLM when applied to acoustic or camera trap data,
where contaminants are not PCR/lab contaminants at all.

| Issue | Proposal | Breaking? |
|---|---|---|
| 🔴 Hardcoded "molecular studies"/"eDNA studies" | Add `data_type` param (`"eDNA"`, `"acoustic"`, `"image"`). Build prompt contaminant block conditionally: eDNA → current PCR/lab text; acoustic → "Handler artifacts: recording equipment noise, human vocalization, domestic animals are common false positives"; image → "Handler artifacts: camera setup events, human presence, domestic animals are common false positives" | No (additive param) |
| 🔴 Hardcoded lab contaminant example in JSON | Parameterize example output or make example data_type-conditional | No |

#### flag_contaminant()

Generic in logic — compares read counts to control samples. Works for eDNA (read counts),
acoustic (detection counts), or image (detection counts). Correctly generic.

#### flag_handler()

Designed for temporal-proximity detection. Currently mentions "camera trap" in docs —
confirms it was built with image data in mind. Works for acoustic as well (handler noise
near recorder). Generic.

**Verdict: 1 critical prompt fix in `review_assignments()`.**

---

### TaxaWizard

TaxaWizard has good bones but the prompts contain several DNA-centric assumptions
that would confuse the LLM when users describe acoustic or image workflows.

#### phase_classify.md — 🟡 Medium

The `match_df` disambiguation says: "BLAST output, percent identity scores, multiple
candidates per sample." This excludes acoustic match data (BirdNET confidence scores)
and image classifier scores, which also produce multiple candidates per sample.

| Issue | Proposal | Breaking? |
|---|---|---|
| 🟡 `match_df` defined as "BLAST output" | Expand definition: "match_df when: BLAST output, BirdNET acoustic detections, image classifier results — any source with **multiple scored candidates per sample**." | No |

#### phase_parameterize.md — 🟡 Medium

The `barcode_term` guidance is correct for DNA but there is no equivalent guidance for
acoustic or image workflows. A user with BirdNET data who sees `barcode_term` in the
prompt might be confused.

| Issue | Proposal | Breaking? |
|---|---|---|
| 🟡 `barcode_term` docs are DNA-only | Add note: "For acoustic or image data, `barcode_term` is not used. The model was trained directly on your acoustic/image reference data and `evaluate_likelihoods()` does not require a marker name." | No |
| 🟡 No guidance for acoustic `rank_system` | Add: "For BirdNET acoustic data, `rank_system = c('genus', 'species')` is typical unless family ranks were added to the reference." | No |

#### Workflow graph (inst/graph/) — 🟡 Medium

The workflow graph was built around the eDNA pipeline. Acoustic workflow 3b has a
standalone script but may not be represented as a navigable path in the graph.
This should be investigated and new nodes added in Session B.

| Issue | Proposal | Breaking? |
|---|---|---|
| 🟡 Acoustic path may be absent from graph | Audit `inst/graph/workflow_graph.json` in Session B; add nodes: `birdnet_match_df`, `acoustic_reference`, `acoustic_model`. Add edges connecting them to existing `likelihood_df` → `consensus` path. | No |

**Verdict: 2 prompt edits (medium); 1 graph audit deferred to Session B.**

---

## LLM Prompt Audit

| Prompt location | Problematic text | Proposed fix |
|---|---|---|
| `TaxaAssign/R/suggest_unreferenced_species.R`, `.build_plausible_prompt()` | "A separate NCBI sequence-availability check will filter species that have no barcode sequences" | When `data_type != "eDNA"`: change to "A species list check will filter species absent from the [acoustic/image] reference model training set." |
| `TaxaFlag/R/review_assignments.R`, `.build_review_prompt()` | "common contaminants in molecular studies. Common lab contaminants include Bos taurus, Sus scrofa, Gallus gallus" | Add `data_type` param; make contaminant guidance block conditional. See per-package section. |
| `TaxaFlag/R/review_assignments.R`, example JSON | `"Common lab contaminant in eDNA studies"` in `review_comment` | Parameterize or suppress when `data_type != "eDNA"`. |
| `TaxaWizard/inst/prompts/phase_classify.md` | "`match_df` when: BLAST output, percent identity scores, multiple candidates" | Expand to include BirdNET + image classifiers. |
| `TaxaWizard/inst/prompts/phase_parameterize.md` | `barcode_term` guidance without acoustic/image equivalent | Add note explaining `barcode_term` is DNA-only; provide acoustic/image alternatives. |

---

## New Functions Needed

| Function name | Package | Data type | Analogous existing function | Priority |
|---|---|---|---|---|
| `read_animl_output()` | TaxaMatch | Image (camera trap) | `read_birdnet_output()` | 🔴 High — fills named gap from Session 55 |
| `audit_acoustic_coverage()` | TaxaLikely | Acoustic | `audit_barcode_coverage()` | 🟡 Medium — acoustic coverage concept is different from barcode coverage |
| `build_image_reference()` | TaxaLikely | Image | `build_acoustic_reference()`, `build_sequence_matrix()` | 🟢 Low — needs `read_animl_output()` first |
| `fetch_reference_images()` | TaxaLikely | Image | `fetch_reference_sequences()`, `fetch_reference_recordings()` | 🟢 Low — iNaturalist/GBIF images API; needs design |

### Notes on new functions

**`read_animl_output()`** (TaxaMatch) — Planned since Session 55. Should accept the
Animl CSV export format (one row per image × detection with confidence score, species
label, and bounding box). Output: same `match_df` format as `read_birdnet_output()`.
Key differences from acoustic: no time windows (use image path as observation_id);
confidence is classifier posterior, not detection score.

**`audit_acoustic_coverage()`** (TaxaLikely) — For acoustic data, "coverage" means:
which plausible species at this site are absent from the BirdNET species list (or the
user's custom acoustic model)? This is fundamentally simpler than `audit_barcode_coverage()`
— it requires only: (1) a list of plausible species (from LLM or GBIF), and (2) the
known species list from BirdNET or the custom model. No NCBI API calls needed.
This could be implemented as a thin function: `audit_acoustic_coverage(plausible_species, reference_species)`.

**`build_image_reference()`** (TaxaLikely) — Acoustic analog for camera trap images.
Joins image classifier detections (from `read_animl_output()`) to ground-truth species
labels. Label H1/H2/H3 based on classifier top-k results vs. known species in image.
Returns same pair-format dataframe accepted by `train_likelihood_model()`.

**`fetch_reference_images()`** (TaxaLikely) — Fetch labeled wildlife images from
iNaturalist, GBIF multimedia API, or Flickr for building image likelihood models.
Design is complex (license filtering, image quality, size standardization). Defer
until after `read_animl_output()` and `build_image_reference()` are implemented.

---

## Workflow File Edits Needed

These are documentation/header edits within existing workflow scripts — no R code changes.

| File | Edit needed | Severity |
|---|---|---|
| `TaxaLikely/inst/workflows/1_fetch_references_workflow.R` | Add header block: "SCOPE: DNA sequences only. For acoustic reference data, see Workflow 3b. For image reference data, see Workflow 3c (planned)." | 🟡 |
| `TaxaLikely/inst/workflows/2_flag_errors_workflow.R` | Add header block: "SCOPE: DNA sequences only. For Xeno-canto acoustic data, use quality grade filter (`quality = c('A','B')`) in `fetch_reference_recordings()` instead of this workflow." | 🟡 |
| `TaxaLikely/inst/workflows/4_score_to_likelihood_workflow.R` | Add header: "SCOPE: Generic — accepts DNA (Workflow 3) or acoustic (Workflow 3b) model objects. Section 2 (remove_flagged_references) is DNA-only — skip for acoustic." Mark Section 2 inline: `# DNA only — skip for acoustic/image data`. Show rank_system options for each data type. | 🟡 |
| `TaxaLikely/inst/workflows/3b_acoustic_reference_workflow.R` | Add family-rank extension section (from memory file): after genus+species model is working, show how to add `rank_system = c("family","genus","species")` by running `TaxaTools::verify_taxon_names()` on species column. Also add note that family is needed in match_df for `posterior_consensus()` LCA even if model stays at genus+species. | 🟢 |

---

## Breaking Changes

Both breaking changes are internal to the function implementation; exported signatures
gain a new optional parameter with a safe default, so no callers break.

| Change | Migration note |
|---|---|
| `suggest_unreferenced_species(data_type = "eDNA")` — new param with `"eDNA"` default | Existing callers unchanged. New callers with acoustic/image data pass `data_type = "acoustic"` or `data_type = "image"` + `reference_species = <character vector of known species>`. |
| `review_assignments(data_type = "eDNA")` — new param with `"eDNA"` default | Existing callers unchanged. New callers pass `data_type = "acoustic"` or `data_type = "image"` to get data-appropriate contaminant guidance in the LLM prompt. |

---

## Implementation Priority for Session B

1. 🔴 `suggest_unreferenced_species()` — add `data_type` param + `reference_species` param (TaxaAssign)
2. 🔴 `review_assignments()` — add `data_type` param + conditional prompt block (TaxaFlag)
3. 🟡 Workflow 4 header + Section 2 notes (TaxaLikely)
4. 🟡 Workflow 1 + Workflow 2 headers (TaxaLikely)
5. 🟡 `phase_classify.md` — expand `match_df` definition (TaxaWizard)
6. 🟡 `phase_parameterize.md` — add acoustic/image notes for `barcode_term` (TaxaWizard)
7. 🟡 `audit_reference_coverage()` → `audit_ncbi_species_coverage()` rename + alias (TaxaLikely)
8. 🟡 `flag_reference_errors()` + `remove_flagged_references()` scope notes in roxygen (TaxaLikely)
9. 🟡 Workflow 3b family-rank section (TaxaLikely)
10. 🟢 `read_animl_output()` — new function (TaxaMatch)
11. 🟢 `audit_acoustic_coverage()` — new function (TaxaLikely)
12. 🟢 `build_image_reference()` — new function (TaxaLikely), after #10
13. 🟢 TaxaWizard graph acoustic nodes — audit and add (TaxaWizard)
14. 🟢 `fetch_reference_images()` — defer; complex design (TaxaLikely)

---

## Packages with no changes needed

- **TaxaFetch** — occurrence/PDF/DataONE; no observation-type assumptions
- **TaxaHabitat** — species names + spatial geometry; fully generic
- **TaxaExpect** — GBIF occurrence → grid → model → priors; fully generic

These packages form the observation-type-neutral "prior" pipeline. Any eDNA, acoustic,
or image workflow feeds into TaxaExpect's priors without modification.
