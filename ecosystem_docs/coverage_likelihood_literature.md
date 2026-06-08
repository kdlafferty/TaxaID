# Coverage as a Likelihood Feature: Literature Notes

*Created: 2026-06-03. For TaxaLikely trivariate model development and planned manuscript.*

---

## Background

TaxaLikely's current likelihood model uses two features — logit-transformed match
score (absolute fit) and gap to the best alternative (relative uniqueness) — as a
bivariate normal. The proposed extension adds alignment coverage as a third dimension,
making the model trivariate. A 98% identity match spanning 50% of the amplicon is
weaker evidence than 98% over the full amplicon; the interaction between identity and
coverage is the mechanistic basis for this extension.

---

## TODO: Manuscript

This literature review is the seed for a methods paper describing the trivariate
likelihood model. Key contributions:

1. **Novel application:** No published paper has formally modeled query/alignment
   coverage as a continuous dimension in a multivariate normal likelihood function
   for amplicon-based taxonomic assignment.
2. **Empirical gap:** The coverage × identity interaction on false-positive rates
   has been stated conceptually but never formally tested in a metabarcoding context.
3. **Mislabeling gap:** No paper has quantified mislabeling rates as a continuous
   function of sequence completeness in barcode reference databases.
4. **Formal precedent exists in metagenomics** (imGLAD, CAIM, Metax) but not in
   amplicon/barcode work — the manuscript would bridge these fields.

When preparing the manuscript, revisit each paper below in full to extract
quantitative effect sizes and statistical details not captured here.

---

## Literature Search Results

### Is alignment coverage an independent predictor beyond identity?

**Short answer: Yes, but the amplicon evidence treats it as a threshold, not a
continuous predictor. The independent-predictor case is strongest in ancient DNA
and metagenomics.**

#### Lan et al. 2019 — *Genes (Basel)*
*"Improving Species Identification of Ancient Mammals Based on Next-Generation
Sequencing Data"*
- Direct test of qcovs and percent similarity as separate variables.
- **Key finding:** All incorrectly identified cases were concentrated at
  qcovs < 96%. Accuracy = 100% above that threshold, 83.3% below.
- qcovs did **not** significantly improve discrimination between competing
  candidates (p = 0.378) — coverage affects the accuracy *floor* but not the
  H1/H2 gap.
- Recommended combined threshold: ≥ 98% similarity AND ≥ 96% qcovs.
- No formal interaction term modeled.
- URL: https://pmc.ncbi.nlm.nih.gov/articles/PMC6679096/

#### TUIT (Tuzhikov et al. 2014) — *Biotechniques*
*"TUIT, a BLAST-Based Tool for Taxonomic Classification of Nucleotide Sequences"*
- Uses **rank-specific combined thresholds** for both identity and coverage:
  - Species: 97.5% identity + 95% query coverage
  - Genus: 95% identity + 90% query coverage
  - Family: 80% identity + 90% query coverage
- Values are heuristic, not statistically derived, but the rank-specific structure
  acknowledges coverage as an independent constraint at each taxonomic level.
- URL: https://pmc.ncbi.nlm.nih.gov/articles/PMC4186660/

#### Bayer et al. 2025 — *Molecular Ecology Resources*
*"A Comprehensive Evaluation of Taxonomic Classifiers in Marine Vertebrate eDNA Studies"*
- Fixed query coverage = 100%; varied only identity (97% vs 100%).
- Informative in treating coverage as a prerequisite gate rather than a
  continuous predictor.
- URL: https://pmc.ncbi.nlm.nih.gov/articles/PMC12415807/

#### QIIME 2 classify-consensus-blast
- Default: 80% identity AND 80% qcovs as independent filters.
- 2020 forum discussion (Bokulich/Pastorelli) explicitly noted that a
  "weighted predictor rather than a threshold would require a much more
  complex decision function" and was never implemented.
- URL: https://docs.qiime2.org/2024.5/plugins/available/feature-classifier/classify-consensus-blast/

---

### Coverage × identity interaction on false-positive rates

**Short answer: No paper has formally modeled this interaction in the amplicon
metabarcoding context. The gap is real.**

- de Filippo et al. 2018 (*BMC Biology*, "Quantifying and reducing spurious
  alignments for ultra-short ancient DNA") is the closest: short sequences achieve
  high identity by chance in locally conserved regions. Modeled via length bins and
  artificial mutation experiments, not a formal interaction term.
  URL: https://pmc.ncbi.nlm.nih.gov/articles/PMC6202837/
- SequenceServer metabarcoding tutorial and QIIME2 forum state the interaction
  qualitatively ("98% over 400 bp is better than 100% over 50 bp") but neither
  provides empirical interaction analysis.
- **Mechanistic basis for the interaction:** a short alignment with high identity
  is more likely to be a coincidental match in a locally conserved region, not a
  true whole-sequence match. The trivariate model would capture this as off-diagonal
  covariance in the 3×3 Σ matrix.

---

### Mislabeling rates as a function of sequence completeness

**Short answer: Partial sequences are flagged as problematic, but no paper has
quantified mislabeling rate vs. sequence length in barcode databases.**

- Keck et al. 2023 (*Molecular Ecology Resources*, "Navigating the seven challenges
  of taxonomic reference databases in metabarcoding analyses") — identifies seven
  challenge categories including mislabelling but does not analyze mislabeling
  rate as a function of sequence length or completeness.
  URL: https://onlinelibrary.wiley.com/doi/10.1111/1755-0998.13746
- Chorlton 2024 (*Frontiers in Bioinformatics*, "Ten common issues with reference
  sequence databases and how to mitigate them") — in whole-genome context: "99.7%
  of contaminated contigs are shorter than 10 kbp." Principle (contamination
  enriched in short fragments) applies to barcodes but has not been tested there.
  URL: https://pmc.ncbi.nlm.nih.gov/articles/PMC10978663/
- Kozlov et al. 2016 (*Nucleic Acids Research*, SATIVA) — used only full-length
  16S (> 1400 bp). Did not test mislabeling rate vs. length — a gap noted by the
  authors.
  URL: https://pmc.ncbi.nlm.nih.gov/articles/PMC4914121/

---

### Formal probabilistic/likelihood models with coverage as a feature

**Short answer: Strong formal precedent exists in metagenomics; nothing comparable
in amplicon metabarcoding.**

#### imGLAD (Castro et al. 2018) — *PeerJ* — **Most directly relevant**
*"imGLAD: accurate detection and quantification of target organisms in metagenomes"*
- Logistic regression combining sequencing breadth (SB = covered bases / genome
  length) and sequencing depth (SD). Joint bivariate model outperformed either
  feature alone. Breadth was the more robust single feature when closely related
  genomes were present.
- At 2% genome breadth, 95% classification accuracy vs MetaPhlAn's 16%.
- Formal analogy to amplicons: breadth ≈ qcovs; depth ≈ read count / percent identity.
- URL: https://pmc.ncbi.nlm.nih.gov/articles/PMC6216955/

#### CAIM (Acheampong et al. 2024) — *Briefings in Bioinformatics*
*"CAIM: coverage-based analysis for identification of microbiome"*
- Uses genome breadth coverage as a deterministic filter (not likelihood model).
  At 15% genome-coverage cutoff, eliminates false-positive taxa that passed
  relative-abundance filters. Shows breadth is orthogonal to relative abundance.
- Analogy: qcovs in amplicon data : genome breadth coverage :: depth : read depth.
- URL: https://academic.oup.com/bib/article/25/5/bbae424/7747595

#### Metax (Deng, Safaei & McHardy 2025) — *bioRxiv* (preprint)
*"Metax: A Coverage-Informed Probabilistic Framework for Accurate Cross-Domain
Taxon Profiling"*
- Probabilistic modeling of genome coverage; outperformed CAIM, Metapresence,
  and others in > 500-sample benchmarks.
- **Caveat:** genome-level breadth in whole-genome metagenomics, not query/alignment
  coverage in amplicons. Full likelihood function not available in preprint abstract.
- URL: https://www.biorxiv.org/content/10.64898/2025.12.04.692287v1

#### Metapresence (Sanguineti et al. 2024) — *mSystems*
*"Metapresence: a tool for accurate species detection in metagenomics based on
genome-wide distribution of mapping reads"*
- Uses Breadth-Expected Breadth Ratio (BER) and Fraction of Unexpected Gaps (FUG)
  from Poisson/exponential distribution theory. Shows that coverage *distribution*
  (not just mean) carries independent information. BER sensitive to sequence
  similarity — a complication analogous to partial alignments inflating qcovs.
- TPR = 0.99, TNR = 1.0 in CAMI benchmarks.
- URL: https://pmc.ncbi.nlm.nih.gov/articles/PMC11338496/

#### PROTAX-GPU (Li et al. 2024) — *Philosophical Transactions of the Royal Society B*
*"PROTAX-GPU: a scalable probabilistic taxonomic classification system for DNA barcodes"*
- Multinomial regression with four features per rank: binary known-taxon indicator,
  binary reference-availability indicator, distance to nearest neighbor, distance
  to second-nearest neighbor.
- **Does not incorporate alignment coverage.** Uses pre-aligned sequences only.
  Noted as a gap.
- URL: https://pmc.ncbi.nlm.nih.gov/articles/PMC11047247/

---

## Summary Table

| Question | Evidence | Verdict |
|---|---|---|
| Coverage is an independent predictor beyond identity | Empirical (ancient DNA); threshold practice in eDNA | Moderate: routinely applied as independent gate; accuracy drops below threshold |
| Coverage × identity interaction on false positives | Conceptual only; no formal analysis in amplicons | **Gap in literature.** Well-motivated; not tested. |
| Mislabeling rate ~ sequence completeness | Indirect (whole genome); not tested in barcodes | **Gap in literature.** |
| Formal likelihood/probabilistic model with coverage | Metagenomics (imGLAD, CAIM, Metax, Metapresence) | Strong analogy; no direct amplicon application. **Novel.** |

---

## Implications for TaxaLikely Trivariate Model

1. **The 3×3 covariance matrix in the trivariate MVN captures the coverage ×
   identity interaction naturally** via off-diagonal terms — no separate interaction
   term engineering needed.
2. **Coverage is likely to affect the H1 distribution width more than it shifts
   the H1/H2 centroid separation** (consistent with Lan et al.: floor effect, not
   gap effect). This suggests the covariance terms (not just the coverage mean) will
   be important.
3. **H2/H3 coverage behavior:** Coverage is a property of the query/amplicon quality
   more than of taxon identity. H2/H3 rows should likely inherit the same coverage
   dimension as the H1 anchor — i.e., the H2/H3 delta offset applies to score and
   gap, but coverage is shared (modeled as a property of the observation, not the
   hypothesis).
4. **Threshold inference from match object minimum:** Most workflows apply a coverage
   filter before passing data to TaxaLikely; inferring the effective threshold as
   `min(match_df$coverage)` avoids requiring user input. An explicit override
   parameter should be provided.
5. **Data-type agnosticism:** Coverage can be qcovs (BLAST), alignment breadth
   fraction, amplicon overlap fraction, Xeno-canto quality grade (ordinal), or
   classifier confidence — all should be normalizable to (0, 1) and logit-transformable
   via the existing `.normalize_scores()` infrastructure.
