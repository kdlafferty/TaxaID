# Re-entry Prompt — Session 105: Taxonomic Name Synonym Bug (Phanerodon / Rhacochilus vacca)

## Context
Session 104 (`add_posthoc_assessment()` in TaxaFlag) exposed a name-harmonization bug
in the PtConception 12S workflow. Running `add_posthoc_assessment(consensus_final, tiers = priors_combined)` flagged *Phanerodon vacca* as "suspect" when it should be a plausible detection.

## Root Cause (Diagnosed)

The GBIF occurrence record has:
- `scientificName = "Phanerodon vacca (Girard, 1855)"`
- `taxon_name = "Rhacochilus vacca"` (older synonym used by GBIF's backbone)

`priors_combined` therefore contains **Rhacochilus vacca** as tier1 with a meaningful prior.

The NCBI backbone (used by TaxaMatch / the consensus) resolves this species as
**Phanerodon vacca**. So `consensus_final` has `consensus_taxon = "Phanerodon vacca"`.

When `add_posthoc_assessment()` does a lookup of "Phanerodon vacca" in `priors_combined`:
- It finds no tier1 entry under that name
- Falls through to tier2 treatment → `winner_prior` is the *Phanerodon vacca* prior
  (a separate low-prior entry if it exists in GBIF) rather than the tier1 *Rhacochilus vacca* prior
- Combined with `winner_likelihood` < 0.5 → classified as "suspect"

## Key Diagnostic Steps for Session 105

```r
# 1. Confirm the name discrepancy in priors_combined
priors_combined |>
  filter(grepl("vacca", taxon_name, ignore.case = TRUE)) |>
  select(taxon_name, model_tier, theta)

# 2. Confirm what name appears in consensus
consensus_final |>
  filter(grepl("vacca", consensus_taxon, ignore.case = TRUE)) |>
  select(observation_id, consensus_taxon, consensus_rank,
         winner_likelihood, winner_prior, posthoc_assessment)

# 3. Check the ncbi_lookup step — does Phanerodon vacca map to Rhacochilus vacca?
ncbi_lookup |>
  filter(grepl("vacca", user_supplied_name, ignore.case = TRUE) |
         grepl("vacca", ncbi_name, ignore.case = TRUE))

# 4. Confirm what name taxaexpect_priors ends up with after backbone conversion
taxaexpect_priors |>
  filter(grepl("vacca", taxon_name, ignore.case = TRUE)) |>
  select(taxon_name, model_tier)
```

## Design Questions to Resolve

1. **Where does the fix belong?**
   - Option A: In `add_posthoc_assessment()` — accept a synonym map and do name
     reconciliation before the tier lookup. Keeps fix in one place but adds complexity
     to a simple function.
   - Option B: In the workflow (PtConceptionWorkflow_12S.R step 5f) — ensure that
     `priors_combined` uses the same backbone as the consensus *before* calling
     `add_posthoc_assessment()`. This is likely correct: the ncbi_lookup backbone
     conversion that produces `taxaexpect_priors` should also update `model_tier`
     in `priors_combined`. Currently `priors_combined` keeps GBIF names; the
     conversion to NCBI names only propagates to `taxaexpect_priors` (used for
     TaxaAssign), not back to the tier lookup used by TaxaFlag.
   - Option C: In `posterior_consensus()` (TaxaAssign) — attach the tier label at
     consensus time so it travels with the taxon name. But this creates a TaxaAssign
     dependency on the tiers data frame, which is awkward.

2. **Is this a common pattern or Phanerodon-specific?**
   - Check how many other taxa in `priors_combined` have GBIF name ≠ NCBI name by
     checking how many rows of `ncbi_lookup` show `gbif_name != ncbi_name`.
   - If it's widespread, a systematic fix (Option B) is critical.

3. **How should unresolved synonyms be handled?**
   - If NCBI resolves a name that GBIF doesn't have (or vice versa), should the tier
     fall back to "tier2" (current behavior) or be left as NA with a warning?

## Expected Fix Location
Step 5f of PtConceptionWorkflow_12S.R (and _18S.R). After constructing
`taxaexpect_priors` with NCBI names, also update `priors_combined` so that the
tier lookup used by `add_posthoc_assessment()` is on the same backbone:

```r
# After building taxaexpect_priors, reconstruct priors_combined on NCBI names
# so that add_posthoc_assessment() tier lookup matches consensus names
priors_combined_ncbi <- taxaexpect_priors |>
  select(taxon_name, model_tier) |>   # taxon_name is now NCBI name
  distinct()
```

Then pass `priors_combined_ncbi` (not `priors_combined`) to `add_posthoc_assessment()`.

## Files to Read at Session Start
- `PtConceptionWorkflow_12S.R` lines 295–320 (backbone conversion step 5f)
- `TaxaFlag/R/add_posthoc_assessment.R`
- `TaxaTools` (or TaxaExpect) source for `change_backbone()` / `verify_taxon_names()`

## Session Goal
1. Confirm the diagnosis (run the diagnostic queries above)
2. Assess breadth (how many taxa are affected across `priors_combined`)
3. Implement the fix — most likely in the workflow's step 5f, possibly with a
   helper in TaxaFlag or TaxaTools to make synonym-aware tier lookups reusable
4. Re-run `add_posthoc_assessment()` and confirm Phanerodon vacca is no longer "suspect"
5. Update CLAUDE.md and commit

## Status
- Bug confirmed by user during Session 104 testing of `add_posthoc_assessment()` on
  real 12S MiFish data from PtConception (Schulte dataset).
- `add_posthoc_assessment()` itself is correct — the issue is upstream name
  harmonization, not the function logic.
