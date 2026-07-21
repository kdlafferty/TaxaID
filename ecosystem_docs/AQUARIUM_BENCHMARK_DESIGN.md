# Aquarium Mock-Community Benchmark — Design Doc

**Status:** Design finalized 2026-07-20; ready to move to implementation.
**Supersedes/operationalizes:** `TODO_validation_benchmark.md` (the earlier,
dataset-agnostic design discussion). That doc's 2026-07-04 hold — "do not begin
implementation until all planned ecosystem package functions are complete" —
is treated as lifted as of this design's finalization; confirm before coding
if that precondition has genuinely been met.
**Feeds:** `TaxaID_consensus` manuscript (*Environmental DNA*, Method article)
— "how well do different TaxaID consensus-building choices change conclusions,
on real eDNA data."

---

## 1. Goal

Reproduce Morey et al. (2020)'s error-tabulation approach (true positive /
false positive / false negative / plausible, scored against a known aquarium
species list) but generalize the comparison axis from *markers* (their COI vs.
12S vs. 16S) to *consensus/classification methods* — score-threshold, LCA,
bootstrap/naive-Bayes, and TaxaID's Bayesian variants — evaluated per-marker
and pooled, on real aquarium mock-community data with genuinely known ground
truth.

## 2. Datasets

| Dataset | Location | Known composition | Markers | Raw data |
|---|---|---|---|---|
| **Miya et al. 2015** (MiFish paper) | Okinawa Churaumi Aquarium, 4 tanks | 180 species (Table 6) | 12S (MiFish-U) | DDBJ DRA DRR030411–030428 |
| **Morey, Bartley & Hanner 2020** | Ripley's Aquarium of Canada, Rainbow Reef tank | 107 species / 44 genera / 17 families (Table S1) | COI, 12S, 16S | NCBI SRA PRJNA604594 |
| **Silverbrand 2021** (M.S. thesis, candidate 3rd) | New England Aquarium, Gulf of Maine taxa | TBD — check thesis | 12S MiFish-U, 16S MarVer3, COI | Contact Silverbrand/Kinnison (UMaine) or DigitalCommons ETD 3538; not yet confirmed public |

Morey is the priority dataset (clearest existing error-tabulation scheme to
mirror; multi-marker, matching TaxaID's own multi-marker workflow pattern in
`MuguWilderFishWorkflow.R`). Miya is the larger/cleaner secondary benchmark.
Silverbrand is a stretch goal pending raw-data confirmation.

## 3. Benchmark design: two orthogonal factors

**Engine** (which method produces the initial consensus call) × **Reviewed**
(that engine's raw output vs. passed through `TaxaFlag::review_assignments()`).

`review_assignments()` is explicitly generic — its own docs state it "works
with any data frame containing a taxon column, not restricted to TaxaAssign
output," and `plausible_taxa_col` is optional, so engines without a
candidate-set column (score-threshold, DADA2, IDTAXA) still get reviewed on
taxon + rank alone. This makes "does LLM review help" a standalone result,
independent of which engine produced the call, rather than a TaxaID-specific
variant.

**Adapter requirement:** every engine's output must be normalized to a common
minimal schema (`observation_id`, `consensus_taxon`, `consensus_rank`,
optionally `plausible_taxa`) before `review_assignments()` can be called
uniformly across all of them. This is real but small per-engine glue code, not
new statistics.

### 3a. Per-marker vs. pooled

Mirror Morey's own structure: a per-marker TP/FP/FN/Plausible table for each
of COI/12S/16S individually, plus a pooled "all markers" table (their Figure
1/2 "Total" column analog). Given 12S will dominate detections, the 12S-only
table is the headline result; COI/16S and pooled are supporting.

## 4. Method short-list (Tier 1 + Tier 2 only for this pass)

| Tier | Method | Source | Implementation |
|---|---|---|---|
| 1 | Naive flat threshold (Morey's own approach) | Morey, Bartley & Hanner 2020 | `score_consensus(min_score = 97, max_gap = 0)` applied identically to all three markers — no genus/family tiers, reproducing exactly what Morey did |
| 1 | 100%-match + LCA (Wilderlabs-style) | — | `score_consensus(min_score = 100)` |
| 1 | Marker-aware literature threshold | See Section 4a for per-marker values, sourced from Pappalardo et al. 2025's literature compilation (COI) and Miya et al. 2015 (12S) | `score_consensus(rank_thresholds = <marker-specific>)`, run separately per marker |
| 1 | Consensus-LCA (Jonah Ventures-style) | DADA2+BLAST pipelines | `score_consensus(max_gap = 1, rank_thresholds = ...)` |
| 1 | TaxaID Bayesian (full) | This project | `run_bayesian_pipeline()` |
| 1 | TaxaID Bayesian variants | This project | toggle presence_multiplier, dark-diversity floor, cross-marker prior update |
| 1 | TaxaID hybrid (LLM likelihood + TaxaExpect prior) | This project | swap `TaxaLikely` model for LLM-elicited likelihood, keep GBIF-based prior |
| 1 | TaxaID LLM-only | This project | `run_llm_pipeline()` |
| 2 | Bootstrap naive-Bayes | Wang et al. 2007 (RDP); Callahan et al. 2016 (DADA2) | `dada2::assignTaxonomy()` |
| 2 | Bootstrap classifier (IDTAXA) | Murali et al. 2018 | `DECIPHER::IdTaxa()` |

Every row above is additionally run with and without the LLM review layer
(Section 3), giving the full engine × reviewed matrix. Tier 3 methods
(coverage-weighted LCA, plain LCA, phylogenetic placement) and Tier 3-adjacent
external tools (PROTAX, BayesANT, SINTAX) remain out of scope for this pass —
cited as related work, not run.

### 4a. Marker-specific literature thresholds (resolves 2026-07-20 open item)

| Marker | Species | Genus | Family | Order/Phylum | Source | Notes |
|---|---|---|---|---|---|---|
| COI | 98% | 95% | 90% | 85% (**phylum**, not order) | Elbrecht et al. 2017; Gibson et al. 2015; Leray et al. 2015; Machida et al. 2009; Ransome et al. 2017 (as compiled in Pappalardo et al. 2025) | Well-established 4-tier convention; matches TaxaAssign's `score_consensus()` default numerically. **Resolved 2026-07-20**: relabeled -- `score_consensus()`'s default is now `c(species=98, genus=95, family=90, phylum=85)`, not `order=85`. No genuine order-level COI threshold was found in this literature survey to substitute in its place, so a 5th order tier was not added. |
| 12S (MiFish) | ≥97% | 95–<97% | — | — | Miya et al. 2015 pipeline convention | Only a 2-tier scheme in common use; no widely-cited family/order tier for 12S in the fish-eDNA literature. |
| 16S (vertebrate mitochondrial) | — | — | — | — | **No usable convention found — checked Roblet et al. 2024, ruled out.** | The only well-cited "16S threshold" scheme (Yarza et al. 2014: 97/94.5/86.5/82/78.5/75) is for *prokaryotic* 16S rRNA — a different molecule under different evolutionary constraints than vertebrate mitochondrial 16S. Importing it would be a real error, not a shortcut. Roblet, Priouzeau, Gambini, Dérijard & Sabourault (2024, *Environmental DNA*, "Primer set evaluation and sampling method assessment for the monitoring of fish communities in the North-western part of the Mediterranean Sea through eDNA metabarcoding," doi:10.1002/edn3.554) was checked as a candidate source (uses Fish16S/Vert16S/AcMDB07 16S primers on real fish samples) but does **not** contain a percent-identity rank-threshold rule — full-text check of every numeric percentage in the paper found only (a) SumaClust's 97% identity used for OTU/MOTU *clustering* (dereplication, not taxonomic assignment), (b) a 95% reference-similarity cutoff used only to flag likely chimeras, and (c) manual, biogeography-based reassignment of implausible-range hits (ecotag best-hit + expert curation) rather than a fixed threshold scheme. The "97.79%... resolved at species level" figure in that paper is a *result* (fraction of MOTUs resolved), not a method threshold — easy to misread as a threshold on a skim. Decision still needed: default to the COI 4-tier scheme for 16S in this benchmark (a judgment call, not literature-backed), or derive a 16S-specific value from Morey's own reference data before running. Worth noting Roblet et al.'s biogeography-based reassignment approach as another literature example of researchers sidestepping a fixed threshold for 16S specifically, in the absence of a good convention — supports 7g's "opinions vary" theme rather than resolving this gap. |

This table replaces the placeholder single default previously used for all
three Tier-1 threshold-style rows above, and is why the method list now
includes both a "naive flat threshold" row (reproducing Morey's own 97%-flat
approach) and a separate "marker-aware literature threshold" row — the
comparison between those two is itself a small, citable result (does
marker-awareness alone, with no Bayesian machinery, already improve on what
Morey published?).

## 5. Metrics

**Core (plotted):**
- **Coverage** — fraction of known species with at least one correct detection
- **Recall/sensitivity** — TP / (known species with usable references)
- **Precision (PPV)** — TP / (TP + FP) — *note: distinct from "rank
  resolution" below; pick unambiguous names in the eventual manuscript*
- **Rank resolution** — finest taxonomic rank at which the call was made
  (species > genus > family > order)

**Supplementary (not headline-plotted, but reported):**
- **Calibration (Brier score)** — only computable for engines that expose a
  probability (TaxaID variants); the empirical payoff of the Bayesian
  argument specifically, since bootstrap-confidence methods don't claim
  calibration
- **Hierarchical rank-distance** — formalized as hierarchical precision/recall
  (hP/hR), following Kiritchenko et al. (2006) and Silla & Freitas (2011),
  with the unified-view refinements in Kosmopoulos et al. (2015). For each
  observation *i*, let `P_i` be the ancestor path (inclusive) of the
  *predicted* taxon down to whatever rank the call was made at, and `T_i` the
  ancestor path of the *true* (species-level) taxon. Then:

  ```
  hP = Σ|P_i ∩ T_i| / Σ|P_i|      (aggregated across all observations)
  hR = Σ|P_i ∩ T_i| / Σ|T_i|
  hF = 2·hP·hR / (hP + hR)
  ```

  A call of "Fundulus" (genus) when the truth is *Fundulus parvipinnis*
  contributes a partial match (family+genus overlap, missing species) rather
  than a binary right/wrong — this directly answers the open question in the
  original `TODO_validation_benchmark.md` about scoring precision across a
  rank hierarchy that isn't always the same depth. hP/hR/hF are computed
  ecosystem-wide (all observations pooled), not per-observation, so a single
  number summarizes each engine.
- **Community-level recovery** — one-line "recovered X of Y known species"
  per engine (Jaccard/Sørensen against the known list), reported as a sanity
  check, not a plotted axis — this is the number Morey/Miya/Kelly all already
  reported informally

**Cost axes (tracked alongside, not blended into the metrics above):**
- Wall-clock runtime per engine per marker
- Engineering-cost tier (existing-function-call / thin-wrapper / new-code /
  external-software — matches the Tier 1/2/3 structure in Section 4)
- LLM token count, via `reset_token_usage()` / `token_usage()` (already
  instrumented in the ecosystem; costs nothing new to add)

## 6. Visualization

**Primary (Figure 1 candidate):** 2D bubble plot — x = precision (PPV), y =
rank resolution, bubble size = coverage, color = method category
(threshold/LCA/bootstrap/Bayesian), faceted by marker (12S/16S/COI/pooled).
Locked as placeholder per 2026-07-20 discussion.

**Supplementary:** parallel-coordinates plot covering the full metric set
including cost/tokens/calibration, which don't share a common 0–1 scale with
the core four and don't fit cleanly into the bubble plot.

Explicitly deferred: 3D scatter (hard to read in print; reviewers often
request a 2D alternative anyway) and radar chart (readability degrades past
~5–6 methods, area-distortion issues).

## 7. Literature review (for the eventual manuscript's Introduction/Discussion)

### 7a. Empirical benchmarks using mock communities (closest precedent to this study)

- **Hleap, Littlefair, Steinke, Hebert & Cristescu (2021).** "Assessment of
  current taxonomic assignment strategies for metabarcoding eukaryotes."
  *Molecular Ecology Resources* 21:2190–2203. Compared 7 methods (incl.
  IDTAXA, BLAST Top Hit, LCA) on COI mock communities of varying richness/
  abundance; found ML/bootstrap methods more sensitive to reference-database
  heterogeneity and completeness than similarity-based methods, and
  recommended *combining* IDTAXA + BLAST Top Hit + LCA for confidence — the
  closest existing precedent to a multi-method mock-community comparison, and
  the most directly citable "why compare methods at all" paper.
- **Bik et al. (2021).** "Just keep it simple? Benchmarking the accuracy of
  taxonomy assignment software in metabarcoding studies." *Molecular Ecology
  Resources* 21. Contrarian finding: simpler methods (BLAST, QIIME2 feature
  classifier) *outperformed* more sophisticated probabilistic/ML approaches
  at family-level assignment, though all methods struggled at genus/species
  with sparse eukaryotic reference databases. Directly relevant counterpoint
  to cite and address — our benchmark should be able to say whether this
  holds for aquarium-known-truth data specifically.
- **O'Rourke, Bokulich, Jusino et al. (2020).** "A total crapshoot? Evaluating
  bioinformatic decisions in animal diet metabarcoding analyses." *Ecology
  and Evolution* 10.1002/ece3.6594. Broader bioinformatic-decision framing
  (denoising vs. clustering, database choice) rather than consensus method
  specifically, but establishes the "researcher degrees of freedom" framing
  directly relevant to your hypothesis about differing user motivations.

### 7b. Threshold critiques (supports TaxaID's own internal finding)

- **Pappalardo et al. (2025).** "Taxon-specific BLAST percent identity
  thresholds for identification of unknown sequences using metabarcoding."
  *Methods in Ecology and Evolution*. Argues a single global identity
  threshold (e.g. 97%) is not optimal across taxa because lineages evolve at
  different rates; derives taxon-specific thresholds for marine eukaryotes
  (COI, 16S) at multiple false-positive-rate targets. Directly corroborates
  TaxaAssign's own internal ROC-sweep finding (Session 147,
  `STATISTICAL_COMPONENT_CATALOG.md`) that raw percent identity "cannot
  discriminate a true species from its closest congener at almost any
  real-world threshold" — worth citing as independent confirmation. Concretely:
  applying the widely-used global COI thresholds they compiled (85% phylum,
  90% family, 95% genus, 98% species — see Section 4a) to real marine
  community datasets produced hidden false-positive rates of 0–3.4% at
  phylum, up to 14% at family (median 2%), up to 21% at genus (median 5%),
  and up to 44% at species (median 12%) — i.e. the "conventional" thresholds
  this benchmark's naive baselines rely on are already documented to carry
  substantial, rank-dependent hidden error even before our own data is run.
  Also source of the per-marker threshold table in Section 4a; also
  originates the best-hit vs. best-shared BLAST tie-breaking distinction,
  which is a smaller, separate design choice from consensus method per se
  but worth being consistent about when building match objects.
- **Phillips et al. (2022).** "Lack of Statistical Rigor in DNA Barcoding
  Likely Invalidates the Presence of a True Species' Barcode Gap." *Frontiers
  in Ecology and Evolution* 10.3389/fevo.2022.859099. More combative framing:
  argues apparent "barcode gaps" are often an artifact of undersampled
  within-species haplotype variation, and that distance/threshold-based
  species delimitation broadly lacks statistical rigor. Useful as the
  strongest available critique of threshold-based consensus, though it's a
  polemical piece and should be cited as one perspective, not settled
  consensus.

### 7c. Classifier/bootstrap-method literature (Tier 2 baselines)

- **Wang, Garrity, Tiedje & Cole (2007).** RDP naive-Bayes classifier —
  already cited in TaxaID's README.
- **Edgar (2016).** SINTAX — kmer + bootstrap, no training required; found
  comparable or better accuracy than RDP with a simpler algorithm, but higher
  over-classification error than IDTAXA in later comparisons.
- **Murali, Bhargava & Wright (2018).** IDTAXA — already cited; independent
  benchmarks (ScienceDirect 2022 comparison of prokaryotic classifiers) found
  IDTAXA has lower over-classification error and generally higher accuracy
  than BLAST, SINTAX, RDP, and MAPSeq across curated 16S databases, though
  performance is sensitive to training-database choice.

### 7d. Probabilistic/Bayesian motivation (closest intellectual precedent to TaxaID itself)

- **Somervuo, Koskela, Pennanen, Nilsson & Ovaskainen (2017).** "Unbiased
  probabilistic taxonomic classification for DNA barcoding." *Bioinformatics*
  33:2997–3005 (PROTAX) — already cited in TaxaID's README Table 1.
- **Somervuo et al. (2017).** "Quantifying uncertainty of taxonomic placement
  in DNA barcoding and metabarcoding." *Methods in Ecology and Evolution*
  — a companion paper not yet in the README's citation list; worth adding,
  since it argues the calibration/uncertainty case independently of PROTAX's
  specific tree-prior mechanism, closer in spirit to TaxaID's calibration
  argument.
- **PROTAX-GPU (2024).** Scalability extension of PROTAX — worth a passing
  mention re: computational-cost tradeoffs (your time/cost axis), since GPU
  acceleration is one answer to the "Bayesian methods are slower" critique.

### 7e. Guidance/opinion pieces on method choice and reporting

- **"Guidance and best practices for species identification using eDNA
  metabarcoding — When do you call a cod a cod?"** *Metabarcoding and
  Metagenomics* (2026); also covered by NOAA PMEL. Directly addresses your
  hypothesis: different labs' choices (primer, bioinformatics, taxonomic
  assignment method) can turn the same sample into a species-level vs.
  genus-level "cod" call, and the paper explicitly recommends
  context-dependent reporting (consensus level vs. listing all candidate
  species) rather than a one-size-fits-all rule — i.e., the guidance
  literature already accepts that method choice is partly a judgment call,
  not a solved optimization problem.

### 7f. Hierarchical evaluation metrics (grounding for the rank-distance metric, Section 5)

- **Kiritchenko, Matwin, Nock & Famili (2006).** "Learning and Evaluation in
  the Presence of Class Hierarchies: Application to Text Categorization."
  *Conference of the Canadian Society for Computational Studies of
  Intelligence* (Canadian AI 2006). Original definition of hierarchical
  precision/recall (hP/hR), crediting partially-correct classifications by
  ancestor-path overlap rather than binary right/wrong.
- **Silla & Freitas (2011).** "A survey of hierarchical classification across
  different application domains." *Data Mining and Knowledge Discovery*
  22:31–72. Standard survey reference synthesizing hP/hR/hF across domains;
  the usual citation when applying these metrics outside text
  classification.
- **Kosmopoulos et al. (2015).** "Evaluation measures for hierarchical
  classification: a unified view and novel approaches." *Data Mining and
  Knowledge Discovery* 29(3). Refines and unifies hP/hR-style measures;
  worth citing for the more careful treatment of multi-path/DAG hierarchies,
  though standard single-path Linnaean rank hierarchy (order > family >
  genus > species) doesn't need the DAG generalization.

### 7g. Does pipeline/method choice even matter? (mixed evidence — nuance to include)

- Diatom DNA metabarcoding bioinformatics-pipeline comparison across six
  European countries (ScienceDirect) found pipeline choice significantly
  changed biotic-index scores and final ecological assessment — supports
  "choice matters."
- A 2025 comparison of five bioinformatic pipelines for fish eDNA (MDPI
  *Fishes*) found, by contrast, that pipeline choice did *not* significantly
  affect ecological interpretation for that specific fish dataset — a useful
  counterpoint showing the effect size may be system/taxon-dependent, which
  is itself worth noting rather than overclaiming that method choice always
  matters.

---

## 8. Open items before implementation

Status as of 2026-07-20 (session following initial design):

- [ ] **Silverbrand data — externally blocked.** Kevin has emailed
      Silverbrand/Kinnison (UMaine) about New England Aquarium raw data.
      Nothing actionable until a reply arrives; proceed with Morey + Miya in
      the meantime and treat Silverbrand as an optional third dataset to add
      later.
- [x] **`score_consensus()` marker-aware thresholds — sourced from literature**
      (Section 4a): COI 98/95/90/85 (species/genus/family/phylum — note
      "phylum" not "order," see caveat in 4a); 12S ≥97% species, 95–<97%
      genus (2-tier only). **16S: decision made 2026-07-20 to derive
      empirically rather than borrow COI's scheme** — see
      `REENTRY_PROMPT_derive_16S_threshold.md` for the full spec (uses
      `morey_table_s1_species_list.csv`, already extracted from Morey's
      supplementary Table S1, + `diagnostics/score_floor_roc_sweep.R`
      adapted for 16S). Not yet run — needs R, which this Cowork session
      doesn't have. The 100%-match and max_gap parameters for the other
      Tier-1 rows are still untested against real score distributions and
      remain open pending real match_df objects.
- [ ] **Per-engine adapter functions — deferred, not abandoned.** Needs real
      match_df objects from Morey/Miya to write against; premature to code
      blind. Target schema is already specified in Section 3.
- [x] **BLAST query-coverage — resolved as a design decision, not a fact to
      confirm.** Morey's raw data is FASTQ reads (SRA PRJNA604594), not
      pre-computed BLAST output — we build match objects ourselves from those
      reads via our own BLASTN run, so query coverage isn't something to
      "check for" in their deposited data. It's simply a matter of requesting
      `qcovs` in our own `-outfmt` string. Decision: include it by default
      when we build match_df for both datasets, since it costs nothing and
      keeps coverage-weighted LCA available as a later Tier-3 addition
      without re-running BLAST.
- [x] **Hierarchical rank-distance metric — formalized.** See Section 5 and
      literature review 7f: hierarchical precision/recall/F (hP/hR/hF) per
      Kiritchenko et al. (2006), Silla & Freitas (2011), Kosmopoulos et al.
      (2015).
- [x] **Somervuo et al. (2017, MEE) citation — added** to `README.md`'s
      reference list.
