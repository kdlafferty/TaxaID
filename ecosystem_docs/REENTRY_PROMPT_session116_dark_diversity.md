# Re-entry Prompt — Session 116 Dark Diversity Redesign

**Status:** Design complete. Implementation not yet started. Use this prompt to begin implementation in a new session.

---

## Context summary

During the Session 116 18S workflow debug (PtConceptionWorkflow_18S_2.R, Pt. Conception, June 2026) we identified three issues with the dark diversity prior system in `join_priors()` / TaxaExpect and agreed on a full redesign. The design is fully specified. Implementation was deferred to a new session.

The immediate trigger: H. walallensis, H. sorenseni, and H. cracherodii were receiving dark floor priors despite having genuine model theta estimates (0.0000433, 0.0000326, 0.000203). The current floor promotion in `join_priors()` (lines 683–694) promotes ANY modelled species with `prior_mean < dark_mean` to the dark mean — erasing spatial signal. Additionally, the global floor prior scheme assigns each unreferenced candidate an independent global floor prior, so total dark diversity probability mass scales linearly with the number of candidates proposed — a mass-conservation failure that will not pass peer review.

Full design specification is in the memory file:
`~/.claude/projects/-Users-lafferty/memory/project_dark_diversity_redesign.md`

---

## Three agreed changes

### Issue 1: Workflow bug — theta_epsilon auto-raise not firing

`generate_full_priors(model_obj, new_sites)` is called **without** `undetected = priors_undetected` in all five workflows. Session 108 added theta_epsilon auto-raise to protect Tier 2 species from floor promotion in `join_priors()`, but it only fires when `undetected` is passed.

**Fix**: Generate `priors_undetected` BEFORE calling `generate_full_priors()`, then pass it as the `undetected` parameter. Affects all five workflows.

### Issue 2: Tier 2 floor = singleton mirror mean (not dark mean)

**Fix**: In `join_priors.R`, the floor promotion threshold (lines 683–694) should compare `prior_mean` against the singleton-mirror mean specifically — not `dark_mean` (which averages singleton mirrors + global floor). Compute `singleton_mean` separately from `dark_mean`:

```r
singleton_dark <- taxaexpect_priors |>
  filter(undetected_type == "singleton_mirror") |>
  group_by(grid_id, main_habitat) |>
  summarise(singleton_alpha = mean(alpha), singleton_beta = mean(beta), .groups = "drop")
# Use singleton_mean as floor threshold instead of dark_mean
```

### Issue 3: Hierarchical mass-conserving group priors (major change)

**Problem**: Each unreferenced candidate gets global floor prior independently → total dark diversity mass = n_candidates × global_floor → scales with proposal list size. Not mass-conserving.

**Solution**: Hierarchical singleton grouping. Full algorithm:

Starting from phylum, descending to genus (terminal rank):

For each rank level R (phylum → class → order → family → genus):
1. Find all taxa at rank R within the current parent scope that have ≥1 singleton
2. These taxa get FURTHER SUBDIVIDED at the next rank level
3. All taxa at rank R within current parent scope with 0 singletons form ONE combined group
   → budget = 1 × prior_singleton (for the entire combined group, shared among all candidates in those 0-singleton taxa)
4. At genus level (terminal):
   - 0-singleton genera within parent scope → ONE combined group (consistent with rule above), budget = 1 × prior_singleton shared across all candidates in all such genera
   - (Note: "0-singleton genera form ONE group" not one-per-genus)

**Group budget formula:**
- `effective_singletons = max(1L, n_singletons_in_group)` — virtual floor for zero-groups
- `prior_singleton_value = mean(theta_mean)` of singleton mirrors within the GROUP'S PARENT CLADE (group-specific; fallback to global singleton mean if no parent-clade singletons)
- `group_budget = effective_singletons × prior_singleton_value`
- `prior_per_candidate = group_budget / n_undetected_in_group`

**Three new output columns** added to unreferenced rows in `join_priors()`:
- `dark_diversity_group`: group label (e.g. `"genus:Haliotis"`, `"zero_classes_in_Chordata"`)
- `n_singletons_group`: count of singleton source species in this group
- `n_undetected_group`: count of unreferenced candidates in this group

**Singleton counting**: study-area level (from `model_obj$singletons` — already correct).

---

## Key implementation details

### source_taxon_name problem
- Singleton mirror rows have `taxon_name = NA` (anonymous proxies)
- Taxonomy link is through `source_taxon_name` column (generate_undetected_diversity.R line 175)
- **`source_taxon_name` is NOT currently in saved `taxaexpect_priors`** — it gets dropped somewhere in the pipeline
- Must be retained: add to `generate_undetected_diversity()` output and ensure it survives `bind_rows` + save in workflows

### Taxonomy sourcing strategy
1. **Primary**: join `source_taxon_name` (and unreferenced candidate `taxon_name`) to `occurrences_std` — has full taxonomy (kingdom, phylum, class, order, family, genus) per workflow lines 361–363; fast, no API
2. **Fallback**: `verify_taxon_names()` for taxa not in `occurrences_std` — slower, API call
3. `fill_higher_ranks()` currently only goes to family — either extend it or use `verify_taxon_names()` classification paths (already return phylum/class/order via `classification_path`)

---

## Files requiring changes

### TaxaExpect (package)
- `R/generate_undetected_diversity.R`: add optional `taxonomy` parameter (data frame with `taxon_name`, `genus`, `family`, `order`, `class`, `phylum`) to annotate `source_taxon_name` rows with full hierarchy at creation time; retain `source_taxon_name` in output always

### TaxaAssign (package)
- `R/join_priors.R`:
  - Issue 2: replace `dark_mean` floor threshold with `singleton_mean` threshold (lines 683–694)
  - Issue 3: new helper `.compute_dark_diversity_groups()` that takes unreferenced rows, singleton rows with `source_taxon_name` + taxonomy, and taxonomy lookup; returns group assignments + group budget; called before dark diversity fallback section
  - Add new optional parameter `singleton_taxonomy` (data frame with `source_taxon_name`, `genus`, `family`, `order`, `class`, `phylum`) to enable Issue 3 logic

### Workflows (all five — same changes)
- `PtConceptionWorkflow_12S.R`
- `PtConceptionWorkflow_18S.R`
- `PtConceptionWorkflow_18S_2.R`
- `PtConceptionWorkflow_18S_phytoplankton.R`
- `TaxaID_eDNA_Workflow_Template.R`

Workflow changes needed:
1. Issue 1: Generate `priors_undetected` BEFORE `generate_full_priors()`, pass as `undetected` param
2. Issue 3: Build taxonomy lookup from `occurrences_std`; pass to `generate_undetected_diversity()` AND to `join_priors()` as `singleton_taxonomy`
3. `SITE_GRID_ID`: use focal_grid derivation from `taxaexpect_priors` (already fixed in `18S_2.R`; apply to all other workflows)

---

## Implementation sequence (sequential draft workflow approach)

**Do not touch production files until draft workflow tests pass at each step.**

**Step 1 — Issue 1 only**: Generate `priors_undetected` first, pass to `generate_full_priors()`
→ Test: verify theta_epsilon auto-raise fires; check Tier 2 species no longer floor-promoted

**Step 2 — Issue 2**: Change floor threshold from `dark_mean` to `singleton_mean` in `join_priors()`
→ Test: verify Tier 1/2 species with genuine low theta retain model estimate

**Step 3 — `source_taxon_name` retention**: Fix pipeline so it survives to `taxaexpect_priors`
→ Test: confirm `source_taxon_name` in `taxaexpect_priors` after save/reload

**Step 4 — Taxonomy enrichment**: Add `taxonomy` param to `generate_undetected_diversity()`
→ Test: confirm singleton rows have phylum/class/order/family/genus after taxonomy join

**Step 5 — Issue 3**: Implement `.compute_dark_diversity_groups()` + update `join_priors()`
→ Test with a simple mock dataset: known singletons, known unreferenced candidates, verify group assignments and budgets are as expected before running full pipeline

**Step 6 — End-to-end test**: Run on 18S data using `PtConceptionWorkflow_18S_2.R` draft version

**Step 7 — Production**: Update all five workflows

---

## Starting point suggestion

Read the memory file first:
```r
# In Claude Code session:
# Read: ~/.claude/projects/-Users-lafferty/memory/project_dark_diversity_redesign.md
```

Then read the key source files:
- `TaxaExpect/R/generate_undetected_diversity.R` (understand singleton mirror structure)
- `TaxaAssign/R/join_priors.R` (understand floor promotion at lines 683–694 and dark fallback at lines 643–660)
- `PtConceptionWorkflow_18S_2.R` (current workflow — start draft workflow from this)

Begin with Step 1 (workflow fix only, no package changes).
