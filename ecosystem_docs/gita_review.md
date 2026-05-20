# GITA Function Review

**Prompt 8 — TaxaID Polishing Roadmap**
**Generated:** 2026-04-13 (Session 56)

---

## Overview

Reviewed all 1160 lines and ~25 functions in `inst/GITA functions_24.R` against
the current TaxaID ecosystem (7 packages). The GITA file represents ~3 years of
iterative development for the General Identification and Taxonomic Assignment
pipeline — the direct predecessor to TaxaID.

Findings organized into three categories per the roadmap specification:
1. **Gap-filling functions** — GITA ideas with no TaxaID equivalent
2. **Better implementations** — GITA code with superior algorithms or edge-case handling
3. **Statistical methods** — approaches worth adopting

---

## Function-by-Function Comparison

| # | GITA Function | TaxaID Equivalent | Recommendation | Effort |
|---|---|---|---|---|
| G1 | `f_collate_names()` | `TaxaTools::clean_taxon_names()` | TaxaID version is better (length-preserving, bracket-aware). **No action.** | — |
| G2 | `f_spellcheck_sci_names()` | `TaxaTools::verify_taxon_names()` | TaxaID version is better (batched, multiple backbones, returns classification). **No action.** | — |
| G3 | `f_submit_list_to_api()` | `TaxaTools::verify_taxon_names()` internal | Both use Global Names Verifier. TaxaID batches better. **No action.** | — |
| G4 | `f_robust_list_to_api()` | *(no formal equivalent)* | Exponential backoff retry wrapper. TaxaID has ad-hoc retry blocks in 7+ locations (see Redundancy Audit D6). **Consider extracting shared helper** (already recommended in D6). | Low |
| G5 | `f_generalize_taxonomy_ranks()` | `TaxaLikely::.generalize_ranks()` | Already assessed in Prompt 5 (Taxonomy Rank Review §3). Decision: do NOT promote to TaxaTools; use `standard_ranks` + `detect_ranks()` instead. **No action beyond Prompt 5 plan.** | — |
| G6 | `f_ungeneralize_taxonomy_ranks()` | *(dead code in GITA; dropped from TaxaLikely)* | Reverse of G5. Never called in GITA's own codebase beyond examples. Confirmed dead. **No action.** | — |
| G7 | `taxon_list_to_taxon_hierarchy()` | `TaxaTools::verify_taxon_names()` + `change_backbone()` | GITA version uses `taxize::classification()` (GBIF/ITIS). TaxaID uses Global Names Verifier (broader backbone coverage). TaxaID pipeline is more flexible. **No action.** | — |
| G8 | `f_find_taxonomic_inconsistencies()` | **NO EQUIVALENT** | **GAP.** Detects higher-rank conflicts across taxonomy tables (e.g., same species listed under different families in different sources). See §Gap Analysis G8 below. | Med |
| G9 | `f_define_multi_table()` | **NO EQUIVALENT** | **GAP.** Companion to G8: builds a "multi table" of taxa assigned to multiple higher-rank lineages, with source tracking. See §Gap Analysis G9 below. | Med |
| G10 | `f_apply_multi_table()` | **NO EQUIVALENT** | **GAP (minor).** Applies corrections from a multi table to a taxonomy frame. Mechanical join — trivial to implement if G8/G9 are adopted. | Low |
| G11 | `f_create_taxon_name()` | `TaxaTools::create_taxon_names()` | Functionally identical. TaxaID version accepts `rank_system` parameter and handles case-insensitive columns. **No action.** | — |
| G12 | `f_hit_dominance()` | *(no direct equivalent)* | Frequency-based dominance filter: keeps only taxa appearing in ≥N% of hits per sample. TaxaID uses score-based filtering (`filter_top_hypotheses()`, `ratio_threshold`). See §Better Approaches G12 below. | Low |
| G13 | `f_summarize_match()` | `TaxaLikely::evaluate_likelihoods()` internal | Both compute median score per taxon per sample. TaxaID version is more sophisticated (logit transform, gap metric, H1/H2/H3 model). **No action.** | — |
| G14 | `f_consensus_table()` | `TaxaAssign::posterior_consensus()` + `score_consensus()` | GITA: 11-level nested `ifelse` LCA. TaxaID: clean `.find_lca()` rank walker. TaxaID implementation is clearly better. See §Better Approaches G14 for one GITA edge-case worth noting. | Low |
| G15 | `f_reduce_poor_match_specificity()` | `TaxaAssign::score_consensus()` `rank_thresholds` | Same concept: uprank consensus when score below threshold. TaxaID version is more flexible (named vector, any rank). **No action.** | — |
| G16 | `f_local_relatives()` | `TaxaAssign::suggest_unreferenced_species()` | Similar goal: identify plausible unreferenced taxa. GITA uses taxonomic proximity (congeneric/confamilial); TaxaID uses LLM + NCBI barcode verification. TaxaID approach is more comprehensive. See §Statistical Methods G16 below. | — |
| G17 | `f_downrank()` | `TaxaAssign::posterior_consensus()` `species_reference` param | Same concept: downrank genus/family consensus when reference has only one finer-rank taxon. TaxaID version is recursive and handles deeper hierarchies. **No action.** | — |
| G18 | `f_expandTaxonDistributionTable()` | *(partially covered by TaxaExpect prior propagation)* | Expands species-level distribution data to genus/family by aggregation. TaxaExpect's `generate_full_priors()` does this implicitly when building hierarchical priors. See §Gap Analysis G18 below. | Low |
| G19 | `f_search_sequence_by_gene()` | `TaxaLikely::audit_barcode_coverage()` | Functionally equivalent: NCBI nucleotide search by taxon + gene marker + date range. TaxaID version adds exponential backoff, length filtering, and `retmax=0` count-only queries. GITA version has one useful pattern: see §Better Approaches G19. | Low |
| G20 | `f_filter_redundant_higher_hypotheses()` | `TaxaMatch::filter_redundant_hypotheses()` | Same concept and algorithm. TaxaID version accepts `rank_system` parameter and handles edge cases (NA lineage columns). **No action.** | — |
| G21 | `f_calculate_geographic_plausibility()` | `TaxaAssign::assign_taxa_llm()` `range_status` | GITA: taxize/GBIF-based point-in-range check. TaxaID: LLM-based range assessment. See §Statistical Methods G21 below. | Med |

---

## Gap Analysis

### G8: `f_find_taxonomic_inconsistencies()` — **Recommended for TaxaID**

**What it does:** Takes a taxonomy data frame and identifies taxa where the same
name at one rank is assigned to multiple different higher-rank parents across
different rows. For example:
- "Cottus" listed under family "Cottidae" in row 5 but "Scorpaenidae" in row 12
- "Gambusia" listed under order "Cyprinodontiformes" and "Perciformes"

These conflicts arise when merging taxonomy from multiple sources (GBIF + NCBI +
WoRMS), which is a core TaxaID use case.

**Why TaxaID needs this:** The `change_backbone()` + `verify_taxon_names()` pipeline
resolves names against a single backbone at a time. When users combine data from
multiple backbones or supplement verified taxonomy with manual corrections, conflicts
can slip through. No current function detects them.

**Where it would fit:** `TaxaTools` — it is a pure taxonomy-cleaning utility with
no dependencies beyond base R and dplyr. It would naturally pair with
`change_backbone()` in the taxonomy QC workflow.

**Implementation notes:**
- GITA version uses nested `for` loops with `unique()`/`which()`. Straightforward
  to vectorize with `dplyr::group_by()` + `n_distinct()`.
- Should accept `rank_system` parameter (not hard-coded ranks).
- Return a data frame of conflicts: `taxon_name`, `taxon_name_rank`,
  `conflicting_rank`, `values_found`, `n_sources`.

**Effort:** Medium (1-2 hours). Algorithm is simple; the value is in testing edge
cases and integration with existing TaxaTools workflow.

### G9: `f_define_multi_table()` — **Consider alongside G8**

**What it does:** Builds a correction table from G8's output: for each conflicted
taxon, selects the "majority" assignment (most common higher-rank value across rows)
or flags for manual review.

**Recommendation:** If G8 is implemented, G9 is a natural companion. However,
TaxaID's `change_backbone()` already provides a more principled resolution mechanism
(re-verify against a single authoritative backbone). G9's majority-vote approach
is a heuristic.

**Decision:** Implement G8 (detection) in TaxaTools. Defer G9 (resolution) —
the recommended user action for detected conflicts is to re-verify via
`change_backbone()`, not majority-vote correction.

### G18: `f_expandTaxonDistributionTable()` — **Low priority**

**What it does:** Takes species-level occurrence/distribution data and propagates
it upward: if species X is present at site A, then genus(X) and family(X) are also
present at site A. Creates aggregated rows at genus and family level.

**TaxaID coverage:** `TaxaExpect::generate_full_priors()` implicitly handles this
during prior estimation — priors for unreferenced genus rows are derived from
within-family species patterns. The explicit table expansion is not needed in the
Bayesian workflow.

**Gap assessment:** Minor. Useful for non-Bayesian workflows (e.g., simple
presence/absence checklists), but not a core TaxaID need. Could be a utility in
TaxaTools if users request it.

**Recommendation:** No action now. Note as a potential TaxaTools utility for future.

---

## Better Approaches in GITA

### G12: `f_hit_dominance()` — Hit frequency as a filter

**GITA approach:** For each sample, count how many BLAST hits map to each taxon.
Keep only taxa appearing in ≥ a threshold fraction of hits (e.g., "Cottus asper"
appears in 8 of 10 hits → keep; "Enophrys bison" appears in 1 of 10 → drop).

**TaxaID approach:** `filter_top_hypotheses()` uses score-based filtering (keep
candidates within `ratio_threshold` of top score). `evaluate_likelihoods()` takes
max score per taxon across accessions.

**Assessment:** Hit dominance captures a different signal from score magnitude.
A taxon appearing in 8/10 hits at 97% identity is more convincing than one appearing
in 1/10 hits at 99% identity. TaxaID's score-based filtering misses this dimension.

**Recommendation:** Consider adding a `min_hit_fraction` parameter to
`filter_top_hypotheses()` or `standardize_match_data()` in TaxaMatch. Low effort
(one `dplyr::add_count()` + filter). Not urgent — the Bayesian model in TaxaLikely
partially accounts for this via the multi-accession score distribution.

### G14: `f_consensus_table()` — Tied-rank handling

**GITA approach:** The 11-level nested `ifelse` is brittle, but it handles one
edge case well: when two candidate species have identical scores AND identical
taxonomy up to family, it reports consensus at family level with an explicit
"tied at species" note.

**TaxaID approach:** `.find_lca()` in `posterior_consensus.R` handles ties implicitly
(LCA of two species in the same family = family). But it does not flag *why* the
consensus is at family level (could be a tie vs. genuine disagreement).

**Recommendation:** Add a `consensus_reason` column to `posterior_consensus()` and
`score_consensus()` output. Values: "unanimous", "majority", "tie", "threshold".
Low effort, high diagnostic value.

### G19: `f_search_sequence_by_gene()` — Query construction pattern

**GITA approach:** Builds NCBI queries with explicit `[GENE]` field tags:
```
"Genus species"[ORGN] AND ("gene1"[GENE] OR "gene2"[GENE])
```

**TaxaID approach:** `audit_barcode_coverage()` uses `[ALL]` field for barcode terms,
which is broader but can return false positives (e.g., papers mentioning the gene
in their abstract).

**Recommendation:** Switch NCBI barcode queries from `[ALL]` to `[GENE]` field tag
where applicable. Quick fix in `.build_search_term()` (TaxaLikely/R/fetch.R). Some
barcode terms (e.g., "MiFish") are primer names, not gene names — need fallback to
`[ALL]` for those.

---

## Statistical Methods Worth Adopting

### G16: Taxonomic proximity as geographic plausibility signal

**GITA approach:** `f_local_relatives()` looks for congeneric species at nearby
sites. If genus X has 3 species confirmed nearby, an unmatched sequence identified
as genus X is more plausible than one identified as genus Y (zero local relatives).

**TaxaID coverage:** `assign_taxa_llm()` gets range plausibility from LLM judgment.
`generate_full_priors()` uses GBIF occurrence + habitat to estimate priors. Neither
explicitly uses taxonomic proximity as a signal.

**Assessment:** Taxonomic proximity is a valid ecological signal (phylogenetic niche
conservatism). However, it is largely captured by TaxaExpect's hierarchical prior
model — species in well-represented genera naturally get higher priors at sites
where congeners are detected. The explicit "count local relatives" heuristic adds
complexity for marginal gain.

**Recommendation:** No action — TaxaExpect's hierarchical model implicitly captures
this. Document the design rationale.

### G21: `f_calculate_geographic_plausibility()` — Algorithmic range check

**GITA approach:** Queries GBIF for occurrence records near the study site. If a
species has GBIF records within a radius, it is "geographically plausible." Returns
a plausibility score based on distance to nearest occurrence.

**TaxaID approach:** LLM-based `range_status` ("native"/"introduced"/"unlikely") in
`assign_taxa_llm()`. GBIF occurrence data via TaxaFetch, but used for habitat
assignment and prior estimation, not direct range checking.

**Assessment:** The algorithmic approach has advantages over LLM:
- Reproducible (same query → same result)
- Quantitative (distance in km, not categorical)
- No API key required
- Verifiable against GBIF records

But the LLM approach has advantages:
- Handles species with zero GBIF records (range knowledge from literature)
- Contextual (understands introduced vs. native ranges)
- Faster for large species lists (one LLM call vs. hundreds of GBIF queries)

**Recommendation:** Consider a hybrid: use GBIF occurrence distance as a
quantitative signal alongside LLM range assessment. This could strengthen the
`assign_taxa_llm()` context block. Medium effort — requires TaxaFetch integration.
Not urgent for first release.

---

## Summary of Recommendations

### Act on now (Phase 2+)

| Priority | Item | Target package | Effort |
|---|---|---|---|
| **Medium** | G8: `find_taxonomy_conflicts()` — detect higher-rank inconsistencies | TaxaTools | 1-2 hrs |
| **Low** | G14: Add `consensus_reason` column to consensus functions | TaxaAssign | 30 min |
| **Low** | G19: Use `[GENE]` field tag in NCBI queries | TaxaLikely | 20 min |

### Consider for future releases

| Priority | Item | Target package | Effort |
|---|---|---|---|
| **Low** | G12: `min_hit_fraction` filter parameter | TaxaMatch | 30 min |
| **Low** | G21: GBIF distance-based range check alongside LLM | TaxaFetch + TaxaAssign | 2-3 hrs |
| **Skip** | G9/G10: Multi-table correction | — | `change_backbone()` handles this better |
| **Skip** | G18: Distribution table expansion | — | TaxaExpect handles implicitly |

### Functions where TaxaID is clearly better

| GITA Function | TaxaID Equivalent | Why TaxaID is better |
|---|---|---|
| `f_collate_names()` | `clean_taxon_names()` | Length-preserving, bracket-aware |
| `f_spellcheck_sci_names()` | `verify_taxon_names()` | Batched, multi-backbone, classification paths |
| `f_consensus_table()` | `posterior_consensus()` + `score_consensus()` | Clean walker vs. 11-level nested ifelse; rank-general |
| `f_reduce_poor_match_specificity()` | `score_consensus()` rank_thresholds | Named vector for any rank, not hard-coded |
| `f_local_relatives()` | `suggest_unreferenced_species()` | LLM + NCBI verification vs. simple taxonomic proximity |
| `f_downrank()` | `posterior_consensus()` species_reference | Recursive, handles deeper hierarchies |
| `f_search_sequence_by_gene()` | `audit_barcode_coverage()` | Backoff, length filtering, count-only queries |

### Key insight

The GITA codebase represents a procedural, rule-based approach to taxonomic
assignment. TaxaID has successfully replaced most of these rules with either:
- **Statistical models** (TaxaLikely likelihood model replaces score thresholds)
- **LLM judgment** (TaxaAssign replaces hard-coded geographic checks)
- **Bayesian integration** (TaxaAssign posterior replaces nested-ifelse consensus)

The one area where GITA has capability TaxaID lacks is **taxonomy conflict
detection** (G8) — a straightforward data-cleaning utility that should be added
to TaxaTools.
