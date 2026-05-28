<img src="USGS_logo_green.png" alt="" width="200"/>

# TaxaID: A Modular R Ecosystem for Bayesian Taxonomic Assignment

# Project Overview and Purpose

Biologists increasingly measure biodiversity from sequence, sound,
and image data, yet current pipelines can have high false-positive and
false-negative rates for taxonomic assignment. TaxaID is a modular
ecosystem of nine R packages that improve taxonomic assignment
accuracy. A typical input is a table of candidate matches for each
observation (sequence, image, or acoustic recording) previously
obtained by querying a reference library. TaxaID can implement
traditional score-threshold approaches, but its main advances are to:

1.  screen for reference-database errors,
2.  detect taxa missing from the reference library,
3.  consider whether a taxon is plausible at the sampling location, and
4.  apply Bayes' Theorem to generate assignment probabilities from
    match scores.

To apply Bayes' Theorem, TaxaID converts match scores to likelihoods,
estimates spatially explicit occurrence-based priors, and computes
posterior probabilities of taxonomic identity. The ecosystem was
designed with eDNA metabarcoding in mind, but image and acoustic
analyses are possible when starting from a table of candidate matches.

The ecosystem supports three workflows, ranging from simple to
comprehensive:

-   **Traditional workflow** -- Select a consensus taxon using score
    thresholds and/or a lowest common ancestor.
-   **LLM-shortcut workflow** -- Use large language models (Anthropic
    Claude, Google Gemini, OpenAI, or local Ollama) to rapidly estimate
    priors and generate consensus assignments.
-   **Bayesian workflow** -- Train a likelihood model on reference data,
    build spatially explicit priors from GBIF occurrences, and compute
    posteriors via Monte Carlo simulation.

These workflows converge at the same posterior consensus step, enabling
direct comparison of model-based and LLM-based assignments.

Many TaxaID functions can use large language models (LLMs), though
most have non-LLM alternatives. LLM integration requires an API key
(see below).

### Common Errors in Taxonomic Assignment

Automated classifiers for DNA, sound, and image data produce taxonomic
assignments with systematic errors that are often difficult to detect.
In a replicated eDNA study from the California rocky intertidal, 28% of
metazoan sequences matched taxa not present on the Pacific Coast (Shea
and Boehm 2024). Camera trap false positive rates can exceed 40% for
rare species (Thompson et al. 2025), and acoustic classifier precision
is highly sensitive to confidence threshold settings (Fairbairn et al.
2025). Raw classifier scores mimic probabilities but are uncalibrated
--- a 0.95 score does not mean 95% confidence (Dussert et al. 2025),
and the same match percentage can be diagnostic for one taxon group but
ambiguous for another (Ficetola et al. 2015). These errors fall into
three categories: false positives (wrong taxon assigned), false
negatives (correct taxon missed), and combined errors where one taxon's
false positive is another's false negative.

#### Reference quality

**Reference mislabeling** (FP) — Mislabeled sequences or images in the
reference database produce confident wrong assignments that propagate to
every query matching that reference. *TaxaLikely detects mislabels
before model training and removes them from match data.*

**Missing reference redirect** (FP + FN) — When the true species is
absent from the reference library, its detections are assigned to the
closest relative — a false positive for that relative and a false
negative for the true species. Reference library gaps are geographically
biased, systematically affecting some regions and taxa more than others
(Marques et al. 2021). *TaxaLikely models the expected score
profile of unreferenced taxa, and TaxaAssign identifies and names
plausible missing species.*

#### Score interpretation

**Overconfident species assignment** (FP + FN) — Uncalibrated raw scores
are taken at face value; even a 100% match may be ambiguous at species
rank if competing candidates score nearly as well. *TaxaLikely's
calibrated likelihoods reveal that a high score with a small gap to
alternatives has low species-level likelihood, regardless of the raw
score.*

**Overly strict thresholds** (FN) — Conservative score cutoffs discard
correct assignments that fall just below arbitrary thresholds. *TaxaID's
probabilistic framework replaces binary thresholds with continuous
likelihoods and posteriors.*

#### Ecological context

**Defensive upranking** (FN) — When multiple similar species produce
near-identical scores, conventional systems uprank to genus to avoid a
false positive, sacrificing species-level resolution. *Spatial priors
from TaxaExpect can break ties: if only one candidate species is
expected at the site, its posterior can support species-level assignment
even when scores alone cannot. Dynamic Bayesian updating further
sharpens priors within a sample after high-confidence detections.*

**Ecologically implausible assignment** (FP) — A species is assigned
that doesn't plausibly occur at the sampling location, season, or
habitat. *Spatially explicit priors from TaxaExpect down-weight
implausible taxa. Dynamic updating within a sample reinforces
ecologically consistent assignments.*

#### Field and lab artifacts

**Contamination or artifact** (FP) — Lab or field contamination, handler
artifacts (camera traps), or equipment carryover introduces real
detections of taxa not present in the environment. *TaxaFlag detects
proportion-based and temporal-proximity artifacts.*

**Allochthonous transport** (FP) — Detections originate from outside the
sampling area: eDNA carried by runoff or currents, sounds from playback
devices or captive animals. *Spatial priors inherently down-weight
species outside their expected habitat.*

*Additionally, TaxaFlag provides LLM-based expert review that can flag
most of these error types post-assignment.*

### Ecosystem Packages

1.  **TaxaTools** cleans and standardizes taxonomic names across
    backbones (GBIF, NCBI, WoRMS, Catalogue of Life) and provides a
    unified interface for calling LLMs from R.
2.  **TaxaFetch** acquires species occurrence records from GBIF,
    DataONE, BioTIME, and published literature.
3.  **TaxaHabitat** classifies taxa into habitat categories using
    LLM-based biological consensus and flags spatial outliers.
4.  **TaxaMatch** standardizes match tables from external tools (BLAST,
    camera-trap classifiers, acoustic detectors) into a common format.
5.  **TaxaLikely** converts match scores into calibrated likelihoods
    using a hierarchical Bayesian model trained on the reference
    library. It also audits references for mislabels and coverage gaps.
6.  **TaxaExpect** builds spatially explicit Bayesian priors by modeling
    species occurrence probability across a geographic grid,
    incorporating habitat and spatial autocorrelation.
7.  **TaxaAssign** computes posterior probabilities from likelihoods and
    priors, generates consensus taxonomy, and produces publication-ready
    reports.
8.  **TaxaFlag** flags anomalous detections after assignment:
    contamination (lab/field blanks), handler artifacts (camera traps),
    and ecologically implausible assignments.
9.  **TaxaWizard** interviews the user about their data and goals, then
    generates a complete R script, methods section, or Shiny
    application.

### Dependency Chain

```
TaxaTools -> TaxaFetch -> TaxaHabitat -> TaxaExpect -> TaxaAssign -> TaxaFlag
TaxaMatch -> TaxaLikely -> TaxaAssign -> TaxaFlag
TaxaWizard (standalone; generates scripts that call the other packages)
```

# Citation

Lafferty, K.D., 2026, TaxaID -- A modular R ecosystem for Bayesian
taxonomic assignment: U.S. Geological Survey software release,
<https://doi.org/10.5066/xxxxxx>.

Kevin D. Lafferty
[![ORCID](https://img.shields.io/badge/ORCID-0000--0001--7583--4593-green)](https://orcid.org/0000-0001-7583-4593)

# Larger Citation

_Associated Manuscript:_ Lafferty, K.D. In prep. TaxaID: A modular R
ecosystem for Bayesian taxonomic assignment from sequence, image, and
acoustic data.

# Licensing

Creative Commons 1.0 Universal (CC0 1.0;
<https://creativecommons.org/publicdomain/zero/1.0/>)

See [LICENSE.md](LICENSE.md) for details. TaxaExpect depends on glmmTMB
(GPL >= 3); the TaxaExpect source code itself is CC0, but binary
distributions that bundle glmmTMB may be subject to GPL terms.

# Related Software

Several R packages and standalone tools address taxonomic assignment
from DNA barcoding data. TaxaID differs from these in its explicit
separation of likelihood and prior, spatially explicit priors built
from occurrence data, and multi-data-type support (DNA, image,
acoustic).

**Table 1.** Comparison of TaxaID with related taxonomic assignment
tools.

| Tool | Approach | Posterior probabilities | Spatial priors | Unreferenced taxa | Multi-data-type |
|---|---|---|---|---|---|
| **TaxaID** | Generative Bayesian (MVN score + gap) | Yes (full distribution) | Yes (GBIF + habitat) | Yes (NCBI census + LLM) | Yes |
| PROTAX (Somervuo et al. 2017) | Bayesian with taxonomy-tree prior | Yes | No | Yes (tree-based) | No (DNA only) |
| BayesANT (Zito et al. 2023) | Bayesian nonparametric (kmer) | Yes | No | Yes (Pitman-Yor) | No (DNA only) |
| IdTaxa / DECIPHER (Murali et al. 2018) | Phylogenetic ML | Bootstrap confidence | No | No | No (DNA only) |
| insect (Wilkinson et al. 2018) | Profile HMM + classification tree | Akaike weights | No | No | No (DNA only) |
| SINTAX (Edgar 2016) | Kmer + bootstrap | Bootstrap confidence | No | No | No (DNA only) |
| RDP Classifier (Wang et al. 2007) | Naive Bayes (8-mer) | Bootstrap confidence | No | No | No (DNA only) |
| DADA2 `assignTaxonomy` (Callahan et al. 2016) | Naive Bayes (kmer) | Bootstrap confidence | No | No | No (DNA only) |
| galaxy-tool-lca (Beentjes et al. 2019) | Score-threshold + LCA (deterministic) | No | No | No (upranked) | No (BLAST/DNA only) |

TaxaID is complementary to several of these tools rather than a
replacement. DADA2 or OBITools handle upstream sequence processing;
TaxaMatch ingests their output. DECIPHER is used internally by
TaxaLikely for reference sequence alignment. The key innovation of
TaxaID is that the same likelihood model can be combined with
different spatial priors at different sites, and that the framework
extends to image and acoustic data via TaxaMatch score
standardization.

The galaxy-tool-lca tool (Beentjes et al. 2019;
<https://github.com/naturalis/galaxy-tool-lca>) is a widely used
Python tool for LCA-based taxonomic assignment from BLAST results,
particularly for freshwater macroinvertebrate eDNA and fungal ITS
metabarcoding. Its core algorithm — filtering BLAST hits by identity,
bitscore, and query coverage, then finding the lowest common ancestor
among passing hits — is conceptually similar to TaxaID's
`score_consensus()`. A notable strength of galaxy-tool-lca is its
explicit use of **query coverage** (the fraction of the query sequence
that aligns to each reference hit) as a mandatory quality filter,
alongside percent identity and bitscore. A 98% identity match that
covers only half the amplicon is weaker evidence than one spanning the
full amplicon, and coverage is already available as a BLAST output
column (`qcovs`). TaxaID's likelihood model currently uses score
(percent identity) and the gap to the second-best candidate as its
primary signals but does not incorporate alignment coverage. Users can
partially address this upstream by filtering on coverage in TaxaMatch
before passing match data to TaxaLikely; incorporating coverage as a
third dimension in the likelihood model is a potential future
enhancement. The analogous quality signal for acoustic reference data
is the Xeno-canto quality grade (A–E per recording), which
`TaxaLikely::fetch_reference_recordings()` already uses to filter
reference recordings before model training.

For contamination detection, the R package decontam (Davis et al.
2018) uses DNA concentration and prevalence to identify contaminants
at the ASV level before taxonomic assignment. TaxaFlag operates after
assignment, flagging implausible taxonomic identities using
proportion-based control comparison, temporal proximity analysis, and
LLM expert review.

# Data and Hardware Requirements

-   **Internet access** is required for GBIF queries, NCBI BLAST, and
    LLM API calls. Offline operation is possible when using cached data
    and local Ollama models.
-   **No specialized hardware** is required. All packages run on
    standard desktop hardware (macOS, Linux, or Windows) with R >=
    4.1.0.
-   **Input data** varies by entry point:
    -   *eDNA workflow*: DADA2 sequence table or FASTA file, plus sample
        metadata.
    -   *Image/acoustic workflow*: match score table with taxonomic
        identifications.
    -   *Name-only workflow*: a list of taxonomic names and site
        coordinates.

# Software Requirements

**Table 2.** Software dependencies required for the TaxaID ecosystem.

| Software | Version | OS bit | Reference |
|---|---|---|---|
| R | >= 4.1.0 | 64 | R Core Team. 2025. R: A Language and Environment for Statistical Computing. V.4.5.2. <https://www.r-project.org>. |
| Bioconductor (DECIPHER, Biostrings) | >= 3.17 | 64 | Gentleman et al. 2004. Bioconductor. <https://www.bioconductor.org>. Required only for `TaxaLikely::build_sequence_matrix()`. |
| rBLAST | >= 0.99 | 64 | Hahsler and Nagar. 2019. rBLAST. <https://github.com/mhahsler/rBLAST>. Optional; required only for local BLAST in TaxaMatch. |

All other R package dependencies are declared in each package's
DESCRIPTION file and will be installed automatically by
`devtools::install()` or `install.packages()`.

### API Keys

To access LLM tools, the user can use a locally installed LLM (Ollama)
or an API key provided by an LLM service (set in `~/.Renviron`). A user
could use a different LLM by modifying one of the existing LLM calls.

| Key | Required By | How to Obtain |
|---|---|---|
| `ANTHROPIC_API_KEY` | TaxaTools (LLM calls) | <https://console.anthropic.com/> |
| `GEMINI_API_KEY` | TaxaTools (LLM calls) | <https://aistudio.google.com/apikey> (free tier) |
| `OPENAI_API_KEY` | TaxaTools (LLM calls) | <https://platform.openai.com/> (paid) |
| `OPENALEX_API_KEY` | TaxaFetch (literature search) | <https://openalex.org/settings/api> (free) |

No API key is needed for GBIF or NCBI queries. At least one LLM provider
key is needed for the LLM-shortcut workflow, TaxaHabitat habitat
assignment, and TaxaWizard.

# Software Installation

``` r
# Install from GitHub
install.packages("remotes")

packages <- c("TaxaTools", "TaxaFetch", "TaxaHabitat", "TaxaMatch",
               "TaxaLikely", "TaxaExpect", "TaxaAssign", "TaxaFlag",
               "TaxaWizard")

for (pkg in packages) {
  remotes::install_github("kdlafferty/TaxaID", subdir = pkg)
}

# Bioconductor dependency (needed for TaxaLikely reference matrix building)
if (!requireNamespace("BiocManager", quietly = TRUE))
  install.packages("BiocManager")
BiocManager::install("DECIPHER")
```

After installation, load the packages:

``` r
library(TaxaTools)    # Name cleaning, LLM providers (auto-detects API keys)
library(TaxaFetch)    # Occurrence data acquisition
library(TaxaHabitat)  # Habitat assignment
library(TaxaMatch)    # Match standardization
library(TaxaLikely)   # Score-to-likelihood conversion
library(TaxaExpect)   # Spatially explicit priors
library(TaxaAssign)   # Posterior computation and consensus
library(TaxaFlag)     # Post-assignment quality flagging
library(TaxaWizard)   # Interactive workflow designer
```

Not all packages are needed for every workflow. At minimum, load
TaxaTools (always required) plus the packages for your workflow.

# Instructions for Using Software

## Packages

| Package | Purpose | License |
|---|---|---|
| [TaxaTools](TaxaTools/) | Name verification, cleaning, parsing, rank lookup, column standardization; LLM provider functions; GBIF backbone census | CC0 |
| [TaxaFetch](TaxaFetch/) | Occurrence data acquisition (GBIF, DataONE, PDF, literature search), source combination | CC0 |
| [TaxaHabitat](TaxaHabitat/) | Habitat assignment via LLM biological consensus; spatial QAQC | CC0 |
| [TaxaMatch](TaxaMatch/) | Match standardization. Sequence input (DADA2/FASTA), BLAST search. | CC0 |
| [TaxaLikely](TaxaLikely/) | Convert match scores to likelihoods using hierarchical Bayesian model; reference QC | CC0 |
| [TaxaExpect](TaxaExpect/) | Spatially explicit Bayesian priors from occurrence and habitat data | CC0 |
| [TaxaAssign](TaxaAssign/) | Posterior computation, consensus taxonomy, report generation | CC0 |
| [TaxaFlag](TaxaFlag/) | Post-assignment anomalous detection flagging (contamination, transport, scope) | CC0 |
| [TaxaWizard](TaxaWizard/) | Conversational LLM workflow designer: guided interview to .R script, .md methods, or Shiny app | CC0 |

## Getting Started

Each package includes a vignette with a worked example:

``` r
# Ecosystem overview (recommended starting point)
vignette("taxaid-ecosystem", package = "TaxaAssign")

# Individual package vignettes
vignette("name-cleaning", package = "TaxaTools")
vignette("data-acquisition", package = "TaxaFetch")
vignette("habitat-assignment", package = "TaxaHabitat")
vignette("match-standardization", package = "TaxaMatch")
vignette("score-to-likelihood", package = "TaxaLikely")
vignette("building-priors", package = "TaxaExpect")
vignette("taxonomic-assignment", package = "TaxaAssign")
vignette("quality-flagging", package = "TaxaFlag")
```

## Workflow Scripts

Detailed, runnable workflow scripts are provided in each package's
`inst/` or `inst/workflows/` directory:

| Workflow | Package | Script |
|---|---|---|
| FASTQ to match data | TaxaMatch | `inst/workflow_fastq_to_match.R` |
| Fetch reference sequences | TaxaLikely | `inst/workflows/1_fetch_references_workflow.R` |
| Flag reference errors | TaxaLikely | `inst/workflows/2_flag_errors_workflow.R` |
| Train likelihood model | TaxaLikely | `inst/workflows/3_train_model_workflow.R` |
| Score to likelihood | TaxaLikely | `inst/workflows/4_score_to_likelihood_workflow.R` |
| Audit coverage | TaxaLikely | `inst/workflows/5_audit_coverage_workflow.R` |
| Fetch occurrences | TaxaFetch | `inst/Merge_sources_workflow.R` |
| Assign habitats | TaxaHabitat | `inst/Habitat_assign_workflow.R` |
| Build priors | TaxaExpect | `inst/TaxaExpect_workflow.R` |
| LLM assignment | TaxaAssign | `inst/TaxaAssign_llm_workflow.R` |
| Bayesian assignment | TaxaAssign | `inst/TaxaAssign_bayesian_workflow.R` |
| Consensus | TaxaAssign | `inst/TaxaAssign_consensus_workflow.R` |

For a step-by-step map of the full pipeline — inputs, outputs, and save
conventions across all packages — see
[ECOSYSTEM_WORKFLOW.md](ecosystem_docs/ECOSYSTEM_WORKFLOW.md).

## High-Level Wrappers

For users who prefer a single-function interface:

``` r
library(TaxaAssign)

# Full Bayesian pipeline (~1 call, plus a saved model generated by TaxaLikely)
result <- run_bayesian_pipeline(match_df, model, site = list(lat = 34.4, lon = -119.8, main_habitat = "Marine"))

# LLM-shortcut pipeline (~1 call)
result <- run_llm_pipeline(match_df, site = list(lat = 34.4, lon = -119.8, main_habitat = "Marine"))
```

## Interactive Workflow Designer

TaxaWizard provides a guided, conversational interface:

``` r
library(TaxaWizard)

# Opens a chat interface that interviews you about your data and goals,
# then generates a complete, runnable R script convertible to a shiny app.
workflow_create()
```

# Data Outputs and Results

The TaxaID ecosystem produces outputs at each stage of the pipeline:

### Occurrence Data and Habitat

-   **Compiled occurrence records** from GBIF, DataONE, BioTIME, and
    literature extraction, standardized to Darwin Core columns
    (`stack_occurrences()`).
-   **Habitat assignments** per taxon via weighted biological consensus
    across multiple habitat classification schemes
    (`assign_habitat_biological()`).
-   **Spatial quality flags** identifying occurrences whose coordinates
    conflict with species habitat expectations
    (`flag_habitat_inconsistencies()`). These may be used to flag errant
    GBIF records.

### Reference Library Assessment

-   **Mislabel detection** identifying swapped or incorrectly labeled
    sequences in reference databases (`flag_reference_errors()`). This
    can help users avoid basing assignments on reference errors.
-   **Coverage audits** enumerating described species per genus and
    flagging taxa absent from the reference library
    (`audit_barcode_coverage()`, `audit_reference_coverage()`). This can
    help users understand limits in precision.
-   **Model diagnostics** summarizing expected match percentages, score
    gaps, and per-species profiles (`interpret_model()`). This can help
    users understand how scores relate to precision.

### Species Distribution Models and Priors

-   **Hierarchical biodiversity models** (glmmTMB) predicting species
    occurrence probability across a geographic grid as a function of
    habitat, spatial autocorrelation, and sampling effort
    (`train_biodiversity_model()`).
-   **Spatially explicit Beta priors** (alpha, beta) for every taxon at
    every grid cell, including undetected diversity estimates for
    plausible but unobserved species (`generate_full_priors()`,
    `build_priors()`).
-   **Interactive theta maps** -- zoomable Leaflet maps showing
    predicted occurrence probability as color-coded grid heatmaps with
    occurrence points overlaid (`plot_theta_map_interactive()`).

### Taxonomic Assignment

-   **Calibrated likelihoods** from a hierarchical Bayesian model
    trained on reference-vs-reference match scores, supporting three
    hypothesis types: known species (H1), unreferenced species (H2), and
    unreferenced genus (H3) (`evaluate_likelihoods()`).
-   **Posterior probabilities** of taxonomic identity for each
    observation, with Monte Carlo uncertainty estimates
    (`compute_posterior()`).
-   **Consensus taxonomy** assignments at the finest rank supported by
    the data, with confidence scores and consensus method labels
    (`posterior_consensus()`, `score_consensus()`).

### Quality Control and Reporting

-   **Quality flags** for anomalous detections: contamination scores
    from lab/field blanks, temporal handler proximity, LLM expert review
    (`flag_contaminant()`, `flag_handler()`, `review_assignments()`).
-   **Publication-ready text** (Methods and Results sections) via
    template-based and LLM-assisted report generation, with per-package
    report sections that assemble into a unified document
    (`generate_report()`, `assemble_report()`).

# Software Inventory

| Package     | Exported Functions | Test Files | Vignette |
|-------------|--------------------|------------|----------|
| TaxaTools   | 22                 | 12         | Yes      |
| TaxaFetch   | 14                 | 15         | Yes      |
| TaxaHabitat | 7                  | 5          | Yes      |
| TaxaMatch   | 5                  | 5          | Yes      |
| TaxaLikely  | 11                 | 9          | Yes      |
| TaxaExpect  | 10                 | 9          | Yes      |
| TaxaAssign  | 14                 | 13         | Yes      |
| TaxaFlag    | 4                  | 4          | Yes      |
| TaxaWizard  | 5                  | 3          | Yes      |

# U.S. Geological Survey Disclaimer

This software is preliminary or provisional and is subject to revision.
It is being provided to meet the need for timely best science. The
software has not received final approval by the U.S. Geological Survey
(USGS). No warranty, expressed or implied, is made by the USGS or the
U.S. Government as to the functionality of the software and related
material nor shall the fact of release constitute any such warranty. The
software is provided on the condition that neither the USGS nor the U.S.
Government shall be held liable for any damages resulting from the
authorized or unauthorized use of the software.

*Non-endorsement of commercial products and services*: Any use of trade,
firm, or product names is for descriptive purposes only and does not
imply endorsement by the U.S. Government.

# References

Beentjes, K.K., Speksnijder, A.G.C.L., Schilthuizen, M., Hoogeveen,
M. and van der Hoorn, B.B. (2019). The effects of spatial scale and
habitat on the composition of the aquatic macroinvertebrate community
as determined by eDNA metabarcoding. *PLOS ONE*, 14(2), e0211143.

Callahan, B.J., McMurdie, P.J., Rosen, M.J., Han, A.W., Johnson,
A.J.A. and Holmes, S.P. (2016). DADA2: High-resolution sample
inference from Illumina amplicon data. *Nature Methods*, 13(7),
581--583.

Davis, N.M., Proctor, D.M., Holmes, S.P., Relman, D.A. and Callahan,
B.J. (2018). Simple statistical identification and removal of
contaminant sequences in marker-gene and metagenomics data.
*Microbiome*, 6, 226.

Dussert, G., Chamaille-Jammes, S., Dray, S. and Miele, V. (2025).
Being confident in confidence scores: calibration in deep learning
models for camera trap image sequences. *Remote Sensing in Ecology and
Conservation*, 11(1), 88--99.

Edgar, R.C. (2016). SINTAX: a simple non-Bayesian taxonomy classifier
for 16S and ITS sequences. *bioRxiv*, 074161.

Fairbairn, A.J., Burmeister, J.S., Weisser, W.W. and Meyer, S.T.
(2025). BirdNET can be as good as experts for acoustic bird monitoring
in a European city. *PLoS One*, 20(9), e0330836.

Ficetola, G.F., Pansu, J., Bonin, A., Coissac, E., Giguet-Covex, C.,
De Barba, M., Gielly, L., Lopes, C.M., Boyer, F., Pompanon, F.,
Raye, G. and Taberlet, P. (2015). Replication levels, false presences
and the estimation of the presence/absence from eDNA metabarcoding
data. *Molecular Ecology Resources*, 15(3), 543--556.

Gentleman, R.C., Carey, V.J., Bates, D.M., Bolstad, B., Dettling, M.,
Dudoit, S., Ellis, B., Gautier, L., Ge, Y., Gentry, J., Hornik, K.,
Hothorn, T., Huber, W., Iacus, S., Irizarry, R., Leisch, F., Li, C.,
Maechler, M., Rossini, A.J., Sawitzki, G., Smith, C., Smyth, G.,
Tierney, L., Yang, J.Y.H. and Zhang, J. (2004). Bioconductor: open
software development for computational biology and bioinformatics.
*Genome Biology*, 5, R80.

Lafferty, K.D., 2026, TaxaID -- A modular R ecosystem for Bayesian
taxonomic assignment: U.S. Geological Survey software release,
<https://doi.org/10.5066/xxxxxx>.

Marques, V., Milhau, T., Albouy, C., Troussellier, M., Dejean, T.,
Valentini, A., Manel, S., Mouillot, D. and Pellissier, L. (2021).
GAPeDNA: assessing and mapping global species gaps in genetic databases
for eDNA metabarcoding. *Diversity and Distributions*, 27(10),
1880--1892.

Murali, A., Bhargava, A. and Wright, E.S. (2018). IDTAXA: a novel
approach for accurate taxonomic classification of microbiome sequences.
*Microbiome*, 6, 140.

Shea, M.M. and Boehm, A.B. (2024). Environmental DNA metabarcoding
differentiates between micro-habitats within the rocky intertidal.
*Environmental DNA*, 6(2), e521.

Somervuo, P., Koskela, S., Pennanen, J., Nilsson, R.H. and
Ovaskainen, O. (2017). Unbiased probabilistic taxonomic classification
for DNA barcoding. *Bioinformatics*, 33(19), 2997--3005.

Thompson, W.L., Kahl, S. and Mathevon, N. (2025). A post-processing
framework for assessing BirdNET identification accuracy and community
composition. *Ibis*, 167(1), 213--229.

Wang, Q., Garrity, G.M., Tiedje, J.M. and Cole, J.R. (2007). Naive
Bayesian classifier for rapid assignment of rRNA sequences into the new
bacterial taxonomy. *Applied and Environmental Microbiology*, 73(16),
5261--5267.

Wilkinson, S.P., Davy, S.K., Bunce, M. and Stat, M. (2018).
Characterising taxonomic assignment quality in environmental DNA
metabarcoding data with the insect R package. *Methods in Ecology and
Evolution*, 11, 1457--1468.

Zito, A., Rigon, T., Ovaskainen, O. and Dunson, D.B. (2023). Bayesian
nonparametric modelling of sequential discoveries. *Methods in Ecology
and Evolution*, 14(6), 1373--1385.
