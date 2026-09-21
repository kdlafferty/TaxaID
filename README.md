---
editor_options: 
  markdown: 
    wrap: 72
---

<img src="USGS_logo_green.png" width="200"/>

# TaxaID: A Modular R Ecosystem for Bayesian Taxonomic Assignment

# Project Overview and Purpose

Biologists increasingly measure biodiversity from sequence, sound, and
image data, yet current pipelines can have high false-positive and
false-negative rates for taxonomic assignment. TaxaID is a modular
ecosystem of nine packages for the R programming language (R Core Team
2025; see Table 2, Software Requirements) that improve taxonomic
assignment accuracy. A typical input is a table of candidate matches for
each observation (sequence, image, or acoustic recording) previously
obtained by querying a reference library. TaxaID can implement
traditional score-threshold approaches (e.g., a fixed percent-identity
cutoff paired with lowest-common-ancestor assignment, as in
galaxy-tool-lca; Beentjes et al. 2019 -- see Related Software, below),
but its main advances are to:

1.  screen for reference-database errors
2.  detect and patch missing references
3.  convert match scores to likelihoods
4.  consider whether a taxon is apriori plausible at the sampling
    location
5.  apply Bayes' Theorem to generate assignment probabilities from
    likelihoods and priors
6.  make assignments transparent
7.  use LLMs to improve assignments, assist with workflows, and review
    results
8.  create shiny apps for clients to process their data

To apply Bayes' Theorem, TaxaID converts match scores to likelihoods,
estimates spatially explicit occurrence-based priors (from GBIF and/or
user data), and computes posterior probabilities of taxonomic identity.
The ecosystem was designed with eDNA metabarcoding in mind, but image
and acoustic analyses are possible when starting from a table of
candidate matches.

**If an AI assistant is reading this repository** (an agentic coding
tool, or a person asking an AI assistant something like "how do I do
taxonomic assignment for eDNA?" or "assign species from these BLAST
results"), start at `llm_prompts/START_HERE.md`. It routes a stated
biological goal to the right TaxaID workflow via the package's own
workflow graph, rather than guessing at individual functions -- see
[Interactive Workflow Designer](#interactive-workflow-designer), below,
for how that graph is generated and kept in sync with the installed
packages.

The ecosystem supports three types of workflows, ranging from simple to
comprehensive:

-   **Traditional workflow** -- Select a consensus taxon using score
    thresholds and/or a lowest common ancestor (covers many current
    approaches).
-   **LLM-shortcut workflow** -- Use large language models (LLMs) --
    Anthropic Claude (Anthropic PBC, San Francisco, California), Google
    Gemini (Google LLC, Mountain View, California), OpenAI (OpenAI OpCo,
    LLC, San Francisco, California), or local Ollama (Ollama, Palo Alto,
    California) -- to rapidly estimate priors and generate consensus
    assignments.
-   **Bayesian workflow** (the main purpose of TaxaID)-- Train a
    likelihood model on reference data, build spatially explicit priors
    from GBIF (Global Biodiversity Information Facility; GBIF
    Secretariat, Copenhagen, Denmark) occurrences, and compute
    posteriors via Monte Carlo simulation.

These workflows converge at the same posterior consensus step, enabling
direct comparison of model-based and LLM-based assignments.

Many TaxaID functions can use large language models (LLMs), though most
have non-LLM alternatives. LLM integration requires an Application
Programming Interface (API) key (see below).

### Common Errors in Taxonomic Assignment

Automated classifiers for DNA, sound, and image data produce taxonomic
assignments with systematic errors that are often difficult to detect.
False presences are frequent in eDNA metabarcoding (Ficetola et al.
2015). In a replicated eDNA study from the California rocky intertidal,
about 28% of the species detected could not be confirmed as occurring in
the California Current System (Shea and Boehm 2024). Auto-classified
camera trap images carry error rates near 10% even at well-studied sites
(Henrich et al. 2026), and acoustic classifier precision is highly
sensitive to confidence threshold settings (Thompson et al. 2025;
Fairbairn et al. 2025). Raw classifier scores mimic probabilities but
are uncalibrated; 95% score does not mean 95% confidence (Dussert et al.
2025), and the same match percentage can be diagnostic for one taxon
group but ambiguous for another (Pappalardo et al. 2025). These errors
fall into three categories: false positives (FP; wrong taxon assigned,
or overly confident in), false negatives (FN; correct taxon missed or
underestimated), and combined errors where one taxon's false positive is
another's false negative. FP/FN labels below mark which category each
error mechanism produces.

#### Reference database quality

**Reference mislabeling** (FP). Mislabeled sequences or images already
present in the reference database can lead to false positives.
*TaxaMatch* can check if accessions might be mislabeled so they can be
removed before training models and generating consensus taxonomies. This
generally follows three steps: *corroborate_references_locally()* is a
relatively fast initial check for whether a reference has internal
consistency within the data (i.e., a reference is similar to other
same-named references). However, being overly cautious (removing correct
references that don't match well) biases the reference library (most
suspicious references are correct). This merits a more extensive
evaluation of suspect references. For sequences, TaxaMatch uses
*evaluate_reference_accessions()* using a BLAST search to see if an
accession matches taxa related to its label, and
*review_flagged_accessions()* gives flagged/borderline accessions a
third look from an LLM; after which *resolve_review_overrides()* double
checks if flagged accessions should be kept or removed.

**Missing reference redirect** (FP + FN). The reference database itself
is usually incomplete: when the true species has no entry in the
reference library at all, its detections are assigned to the closest
relative that does have an entry, a false positive for that relative and
a false negative for the true species. Reference library gaps are
geographically biased, systematically affecting some regions and taxa
more than others (Marques et al. 2021). *TaxaLikely models the expected
score profile of unreferenced taxa, and TaxaAssign identifies and names
plausible missing species.*

#### Score interpretation

**Overconfident species assignment** (FP + FN). Even when the correct
species is present in the reference database, its raw match score is
uncalibrated and taken at face value; a 100% match may still be
ambiguous at species rank if competing candidates score nearly as well.
Unlike the reference-gap problems above, this error arises purely from
how scores are interpreted, not from what the reference database
contains. *TaxaLikely's calibrated likelihoods account for the fact that
a high score with a small gap to alternatives has low species-level
likelihood, regardless of the raw score.*

**Overly strict thresholds** (FN). Conservative score cutoffs discard
correct assignments that fall just below arbitrary thresholds. *TaxaID's
probabilistic framework replaces binary thresholds with continuous
likelihoods and posteriors.*

#### Ecological context

**Defensive upranking** (FN). When multiple similar species produce
near-identical scores, conventional systems uprank to genus to avoid a
false positive, sacrificing species-level resolution. *Spatial priors
from TaxaExpect can break ties; if only one candidate species is
expected at the site, its posterior can support species-level assignment
even when scores alone cannot. Dynamic Bayesian updating further
sharpens priors within a sample after high-confidence detections support
species presence.*

**Ecologically implausible assignment** (FP). A species is assigned that
doesn't plausibly occur at the sampling location, season, or habitat.
*Spatially explicit priors from TaxaExpect down-weight implausible taxa.
Dynamic updating within a sample reinforces ecologically consistent
assignments.*

#### Field and lab artifacts

**Contamination or artifact** (FP). Lab or field contamination, handler
artifacts (camera traps), or equipment carryover introduces real
detections of taxa not present in the environment. *TaxaFlag* can use
information from blanks to remove contaminants from the source.
Downstream, *TaxaFlag* uses LLM review toalert the user to candidates
that look like contaminants or allocthonous transport from outside the
sampling area: eDNA carried by runoff or currents, sounds from playback
devices or captive animals.

### Ecosystem Packages

1.  **TaxaTools** cleans and standardizes taxonomic names across
    backbones (GBIF; NCBI, the National Center for Biotechnology
    Information, U.S. National Library of Medicine, National Institutes
    of Health, Bethesda, Maryland; WoRMS, the World Register of Marine
    Species, Flanders Marine Institute (VLIZ), Ostend, Belgium;
    Catalogue of Life, hosted by Naturalis Biodiversity Center, Leiden,
    Netherlands) and provides a unified interface for calling LLMs from
    within the package.
2.  **TaxaMatch** standardizes match tables from external tools (BLAST,
    the Basic Local Alignment Search Tool -- Altschul et al. 1990,
    hosted by NCBI; camera-trap classifiers; acoustic detectors) into a
    common format, and screens reference accessions for mislabels via
    independent BLAST-based taxonomic congruence checking before the
    reference set is used for model training.
3.  **TaxaLikely** converts match scores into calibrated likelihoods
    using a hierarchical Bayesian model trained on the reference library
    and auditing references for coverage gaps.
4.  **TaxaFetch** acquires species occurrence records from GBIF, DataONE
    (Data Observation Network for Earth; University of New Mexico,
    Albuquerque, New Mexico), BioTIME (University of St Andrews, St
    Andrews, Scotland, United Kingdom), and published literature
    (including from PDFs).
5.  **TaxaHabitat** classifies taxa into habitat categories using
    LLM-based biological consensus and flags spatial outliers.
6.  **TaxaExpect** builds spatially explicit Bayesian priors by modeling
    expected species composition (each taxon's relative share of the
    detections at a site) from observation records, incorporating
    habitat and spatial autocorrelation.
7.  **TaxaAssign** computes posterior probabilities from likelihoods and
    priors, generates consensus taxonomy, and produces publication-ready
    reports.
8.  **TaxaFlag** flags anomalous detections after assignment:
    contamination (lab/field blanks), handler artifacts (camera traps),
    and ecologically implausible assignments.
9.  **TaxaWizard** interviews the user about their data and goals, then
    generates a complete R script, methods section, or Shiny
    application.

See the Readme.md file for each package for more details.

### Dependency Chain (import order)

```         
TaxaTools -> TaxaFetch -> TaxaHabitat -> TaxaExpect -> TaxaAssign -> TaxaFlag
TaxaMatch -> TaxaLikely -> TaxaAssign -> TaxaFlag
TaxaWizard (standalone; generates scripts that call the other packages)
```

The diagram below shows how information flows among packages: external
data sources (parallelograms), external reference/occurrence databases
(cylinders), the nine packages (rectangles), and final outputs (rounded
terminals). `TaxaTools` is a cross-cutting utility (name cleaning,
backbone conversion, LLM calls) rather than a single pipeline step,
which is why it feeds several downstream packages directly rather than
sitting in one place in the chain.

``` mermaid
flowchart TD
    %% Data sources
    SEQ[/"DNA sequences\n(FASTA / DADA2)"/]
    ACOUS[/"Acoustic & camera-trap output\n(BirdNET / SpeciesNet / Animl)"/]
    PRECONSENSUS[/"Pre-existing consensus\n(morphology / expert IDs)"/]
    LOCALREF[("Local reference DB\n(CRABS / FASTA)")]
    NCBI[("NCBI / BOLD")]
    GBIF[("GBIF / DataONE / iNaturalist")]

    %% Packages
    TaxaTools["TaxaTools"]
    TaxaMatch["TaxaMatch"]
    TaxaFetch["TaxaFetch"]
    TaxaHabitat["TaxaHabitat"]
    TaxaLikely["TaxaLikely"]
    TaxaExpect["TaxaExpect"]
    TaxaAssign["TaxaAssign"]
    TaxaFlag["TaxaFlag"]
    TaxaWizard["TaxaWizard"]

    %% Outputs
    OUT_CONSENSUS(["Consensus assignment\n+ methods report"])
    OUT_REVIEWED(["Reviewed / flagged\ndetections"])
    OUT_PRIORMAP(["Prior probability map"])
    OUT_REFAUDIT(["Reference coverage audit"])

    %% Sources into packages
    SEQ --> TaxaMatch
    ACOUS --> TaxaMatch
    PRECONSENSUS --> TaxaTools
    PRECONSENSUS --> TaxaFlag
    LOCALREF --> TaxaLikely
    NCBI --> TaxaLikely
    GBIF --> TaxaFetch

    %% Package-to-package data flow
    TaxaMatch --> TaxaTools
    TaxaTools --> TaxaFetch
    TaxaTools --> TaxaLikely
    TaxaTools --> TaxaExpect
    TaxaTools --> TaxaAssign
    TaxaFetch --> TaxaHabitat
    TaxaHabitat --> TaxaExpect
    TaxaLikely --> TaxaAssign
    TaxaExpect --> TaxaAssign
    TaxaMatch --> TaxaAssign
    TaxaAssign --> TaxaFlag

    %% Packages to outputs
    TaxaAssign --> OUT_CONSENSUS
    TaxaFlag --> OUT_REVIEWED
    TaxaExpect --> OUT_PRIORMAP
    TaxaLikely --> OUT_REFAUDIT

    %% TaxaWizard sits outside the dependency chain
    TaxaWizard -.->|generates workflow scripts calling| TaxaTools

    classDef source fill:#e8f3ff,stroke:#5b8def,color:#1a3a6b;
    classDef pkg fill:#fff7e6,stroke:#d99a2b,color:#5c3d05;
    classDef output fill:#e9f9ee,stroke:#3fa85a,color:#1c4a2a;
    classDef wizard fill:#f5e9ff,stroke:#9b59b6,color:#3d1f52,stroke-dasharray:4 3;

    class SEQ,ACOUS,PRECONSENSUS,LOCALREF,NCBI,GBIF source;
    class TaxaTools,TaxaMatch,TaxaFetch,TaxaHabitat,TaxaLikely,TaxaExpect,TaxaAssign,TaxaFlag pkg;
    class OUT_CONSENSUS,OUT_REVIEWED,OUT_PRIORMAP,OUT_REFAUDIT output;
    class TaxaWizard wizard;
```

`TaxaWizard` uses this flowchart to help users generate scripts
(`TaxaWizard/inst/graph/workflow_graph.json`); see the *Pipeline
Overview* section below for the finer-grained, object-level version.

# Citation

Lafferty, K.D., 2026, TaxaID: A modular R ecosystem for Bayesian
taxonomic assignment: U.S. Geological Survey software release,
<https://doi.org/10.5066/xxxxxx>.

Kevin D. Lafferty
[![ORCID](https://img.shields.io/badge/ORCID-0000--0001--7583--4593-green)](https://orcid.org/0000-0001-7583-4593)

# Larger Citation

*Associated Manuscript:* Lafferty, K.D. In prep. TaxaID: A modular R
ecosystem for Bayesian taxonomic assignment from sequence, image, and
acoustic data.

# Licensing

Creative Commons 1.0 Universal (CC0 1.0;
<https://creativecommons.org/publicdomain/zero/1.0/>)

See [LICENSE.md](LICENSE.md) for details. TaxaExpect depends on glmmTMB
(GPL \>= 3); the TaxaExpect source code itself is CC0, but binary
distributions that bundle glmmTMB may be subject to GPL terms.

# Use of Large Language Models

TaxaID uses large language models in two distinct ways, and they should
not be confused.

**In the software.** Several functions call an LLM as part of the
analysis: TaxaHabitat assigns habitat categories by biological
consensus, TaxaFlag reviews assignments for ecological plausibility,
TaxaAssign offers an LLM-elicited alternative to the modelled prior, and
TaxaWizard generates workflow scripts. All of these route through a
common provider interface (`TaxaTools::call_api()`), so any supported
provider can be used, and every one of them except TaxaWizard has a
non-LLM alternative. Functions that make billed API calls cache their
results to disk, so re-running a workflow does not pay for the same call
twice.

**In writing the code.** The TaxaID source code was written with the
assistance of Anthropic Claude models, used through Claude Code. Claude
Sonnet did the bulk of the development; Claude Opus and Claude Fable
were used more recently. Because this assistance was continuous rather
than confined to particular functions, per-function annotation would
imply a precision that does not exist, so this repository-level
statement is the annotation. All of it was reviewed and tested before
release: every package carries a `testthat` suite, and each was checked
with `R CMD check` before release. The author reviewed the code and
takes responsibility for it.

# Related Software

Several R packages and standalone tools address taxonomic assignment
from DNA barcoding data. TaxaID differs from these in its explicit
separation of likelihood and prior, spatially explicit priors built from
occurrence data, and multi-data-type support (DNA, image, acoustic).

**Table 1.** Comparison of TaxaID with related taxonomic assignment
tools.

| Tool | Approach | Posterior probabilities | Spatial priors | Unreferenced taxa | Multi-data-type |
|------------|------------|------------|------------|------------|------------|
| **TaxaID** | Generative Bayesian (MVN score + gap) | Yes (full distribution) | Yes (GBIF + habitat) | Yes (NCBI census + LLM) | Yes |
| PROTAX (Somervuo et al. 2016) | Bayesian with taxonomy-tree prior | Yes | No | Yes (tree-based) | No (DNA only) |
| BayesANT (Zito et al. 2023) | Bayesian nonparametric (kmer) | Yes | No | Yes (Pitman-Yor) | No (DNA only) |
| IdTaxa / DECIPHER (Murali et al. 2018) | Phylogenetic ML | Bootstrap confidence | No | No | No (DNA only) |
| insect (Wilkinson et al. 2018) | Profile HMM + classification tree | Akaike weights | No | No | No (DNA only) |
| SINTAX (Edgar 2016) | Kmer + bootstrap | Bootstrap confidence | No | No | No (DNA only) |
| RDP Classifier (Wang et al. 2007) | Naive Bayes (8-mer) | Bootstrap confidence | No | No | No (DNA only) |
| DADA2 `assignTaxonomy` (Callahan et al. 2016) | Naive Bayes (kmer) | Bootstrap confidence | No | No | No (DNA only) |
| galaxy-tool-lca (Beentjes et al. 2019) | Score-threshold + LCA (deterministic) | No | No | No (upranked) | No (BLAST/DNA only) |

TaxaID is complementary to several of these tools (and may load them for
some purposes). DADA2 or OBITools handle upstream sequence processing;
TaxaMatch ingests their output. DECIPHER is used internally by
TaxaLikely for reference sequence alignment. The key innovation of
TaxaID is that the same likelihood model can be combined with different
spatial priors at different sites, and that the framework extends to
image and acoustic data via TaxaMatch score standardization.

A large recent benchmark (Orsholm et al. 2026), spanning several tools
listed in Table 1 (PROTAX, BayesANT) alongside similarity-,
composition-, and phylogenetic-placement-based classifiers, confirms
that no single algorithm dominates the reference-gap problem:
phylogenetic placement (EPA-ng) performed best for arthropod COI
barcodes, while composition-based classifiers (SINTAX, RDP-NBC, IDTAXA)
performed best for fungal ITS, reflecting real differences in how
alignable each marker is. This supports TaxaID's own approach of
treating reference-database completeness as a first-class, explicitly
modeled problem rather than assuming one classification strategy
generalizes across markers.

The galaxy-tool-lca code (Beentjes et al. 2019;
<https://github.com/naturalis/galaxy-tool-lca>) is a widely used tool,
written in Python (Python Software Foundation, Wilmington, Delaware),
for LCA-based taxonomic assignment from BLAST results, particularly for
freshwater macroinvertebrate eDNA and fungal Internal Transcribed Spacer
(ITS) metabarcoding. Its core algorithm, which filters BLAST hits by
identity, bitscore, and query coverage, then finds the lowest common
ancestor among passing hits, is conceptually similar to TaxaID's
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
enhancement. The analogous quality signal for acoustic reference data is
the Xeno-canto (Xeno-canto Foundation, Netherlands, with support from
Naturalis Biodiversity Center, Leiden; <https://xeno-canto.org/>)
quality grade (A–E per recording); a dedicated helper for calibrating a
quality-grade filtering threshold from it existed in TaxaLikely through
2026-09-09 and was archived after a real A/B test found the accuracy
gain came with a real coverage cost (see TaxaLikely's own README and
CLAUDE.md) -- a threshold can still be applied directly against the
recorded quality-grade column before model training.

A parallel line of work addresses a different need: making metabarcoding
output interpretable for managers and other non-specialist stakeholders
through graphical interfaces. TaxonTableTools (Macher et al. 2021)
provides platform-independent exploration and visualization of
metabarcoding tables. The Pest Alert Tool (Zaiko et al. 2023) and
BIOWATCH (Pearman et al. 2026) are targeted screening applications: both
compare query sequences against a curated database of species of
interest -- non-indigenous, pathogenic, endangered, or commercially
important taxa -- and report which of those species appear in a dataset.
BIOWATCH generalizes the Pest Alert Tool's fixed Aotearoa-New Zealand
marine list to user-defined species lists, markers, and regions,
assembling custom BLAST databases with CRABS (Jeunen et al. 2023) and
adding control- and replicate-based checks alongside spatio-temporal
display of accumulated detections.

Several BIOWATCH steps have direct TaxaID counterparts: region-scoped
species lists drawn from a map polygon
(`TaxaTools::define_search_polygon()` with TaxaFetch), reference
retrieval and in-silico amplicon trimming
(`TaxaLikely::fetch_ncbi_reference_sequences()`,
`fetch_bold_reference_sequences()`, `trim_to_amplicon()`; CRABS output
itself is read by `TaxaLikely::read_crabs_output()`), database
completeness auditing (`TaxaLikely::audit_barcode_coverage()`),
control-based contaminant screening (`TaxaFlag::flag_contaminant()`),
and watch-list surveillance (`TaxaFlag::flag_watch_candidates()`,
`TaxaExpect::generate_invasive_watch_evidence()`). The substantive
difference lies in how detection confidence is expressed. These tools
resolve a detection into ordinal tiers -- BIOWATCH labels a detection
*Likely* when a single species uniquely holds the top percent identity
within a bit-score window, and *Putative* when several species tie --
which is a uniqueness heuristic applied to raw scores rather than a
probability, and Pearman et al. (2026) identify probabilistic confidence
metrics as future work. That is what TaxaID supplies: a calibrated
likelihood combined with a spatially explicit prior yields a posterior
probability for each candidate.

The two designs also differ in their exposure to reference-database
gaps. A screening database restricted to target species plus their
congeners guarantees that every query returns a best hit from within
that restricted set, so a sequence from a taxon with no representation
at all can still be reported against a target -- the missing-reference
redirect described above, and the reason TaxaID treats the
absent-species response (H3) as an explicitly modeled hypothesis rather
than a filtering threshold. Conversely, TaxaID has no counterpart to
BIOWATCH's long-term detection ledger, which accumulates detections with
sampling metadata across years for spatio-temporal display. TaxaID's
scope ends at the assignment; analysis of the resulting detections is
left to dedicated occupancy and trend tools.

**Table 1b.** Comparison of TaxaID (image path) with standalone image
classifiers. TaxaID converts raw classifier confidence scores into
calibrated likelihoods via a reference training set with known species
identity, then multiplies those likelihoods by spatially explicit
priors; the tools below produce the raw scores that TaxaMatch and
TaxaLikely process.

| Tool | Taxa scope | Score output | Spatial priors | Unreferenced taxa | R access |
|------------|------------|------------|------------|------------|------------|
| **TaxaID (image path)** | Any (classifier-agnostic) | Calibrated likelihoods → Bayesian posteriors | Yes (GBIF + habitat) | Yes (coverage audit) | Native |
| animl / SpeciesNet (Tabak et al. 2019; Wildlife Insights\*) | Camera trap mammals | Confidence (0--1), top-5; rollup ensemble | No | No | `animl` R package |
| iNaturalist computer vision | General wildlife (108,000+ taxa) | Softmax (0--1), top-10; genus/family fallback | Limited (app UI only) | No | `rinat` (indirect) |
| InsectNet (Chiranjeevi et al. 2025) | Insects (2,526 spp, 17 orders) | Conformal prediction sets; OOD energy score | No | Limited (OOD flag) | Web app only |
| Seek / iNaturalist mobile | General wildlife | Community consensus | No | No | None |
| Wildlife Insights\* | Camera trap wildlife | Confidence (0--1), rollup ensemble | No | No | None (web platform) |

\* Wildlife Insights is a collaboration led by Conservation
International (Arlington, Virginia) with Google LLC (Mountain View,
California), the Wildlife Conservation Society (Bronx Zoo, Bronx, New
York), WWF, the Smithsonian Institution, and others.

TaxaID is downstream of, not competing with, these classifiers. The key
point is that raw confidence scores from neural networks are
uncalibrated softmax outputs; a 90% confidence score does not mean a 90%
chance the identification is correct. TaxaLikely addresses this by
fitting a generative model to a labeled reference set with known species
identity, capturing the full score distribution for correct matches
(H1), wrong-species matches (H2), and absent-species responses (H3).
`animl` (Conservation Technology Lab, San Diego Zoo Wildlife Alliance,
San Diego, California) results are read directly by
`TaxaMatch::read_animl_output()`; iNaturalist (a joint initiative of the
California Academy of Sciences and the National Geographic Society, San
Francisco, California) CV JSON output is read by
`TaxaMatch::read_inaturalist_cv_output()`; SpeciesNet CLI
(`google/cameratrapai`; Google LLC, Mountain View, California) batch
predictions are read by `TaxaMatch::read_speciesnet_output()`. For
acoustic and image data, TaxaLikely acts as a post-classifier
calibration layer: classifier output is standardized to `match_df` by
TaxaMatch, then `unreferenced_candidates()` + `assign_scores()` convert
classifier confidence scores to likelihoods (no separate
reference-building step required).

InsectNet (Chiranjeevi et al. 2025) is a notable recent advance for
invertebrate specialists, achieving 96.4% top-1 accuracy across 2,526
species in 17 insect orders. Its standout methodological innovation is
replacing point confidence scores with **conformal prediction sets**:
rather than a single species estimate, the model returns a set of
candidate species guaranteed to contain the true species with ≥97.5%
probability, backed by an energy-based out-of-distribution score that
flags images outside the training distribution. The conformal guarantee
is conceptually related to TaxaID's H1/H2/H3 framework; the true species
is either in the candidate set (H1/H2) or flagged as OOD (H3 analog).
The outputs are not directly compatible with `train_likelihood_model()`,
however, given the lack of access to InsectNet's underlying softmax
scores.

For contamination detection, the R package decontam (Davis et al. 2018)
uses DNA concentration and prevalence to identify contaminants at the
ASV level before taxonomic assignment. TaxaFlag's proportion-based
control comparison (`flag_contaminant()`) is typically applied the same
way, before assignment, to remove likely contaminants when field or lab
blanks are defined. However, TaxaFlag also runs a second, post-hoc pass
after assignment: temporal proximity analysis, LLM expert review, and a
combined view that rejoins the earlier contaminant flags against the
final assignments.

Two further differences are worth stating, because both address gaps that
are not specific to this software.

First, **decontam assumes the control labels are correct, and nothing in
the conventional toolkit checks them.** A field sample mislabelled as a
blank makes the real community look like contamination, so any
control-comparison method then filters genuine signal. Its frequency
method also requires DNA concentration, which many eDNA workflows do not
record, leaving only the prevalence method. `validate_controls()` tests
the labels themselves, in both directions, on the principle that a
control is defined by what it *lacks* rather than by what it contains: it
compares each control's compositional distance to the field samples it
sits with against the null of sample-to-sample distance at that same
site. It therefore uses no taxonomy, no habitat model and no assumption
about the blank medium, and it reports its own statistical power so that
"nothing flagged" can be distinguished from "nothing testable".

Second, a prevalence or proportion score answers *how associated is this
sequence with the controls*, which is symmetric, whereas the question is
directional: contamination flows control → sample, while **carryover**
flows sample → control when a blank picks up a little of an abundant
local taxon. The first should be removed and the second must not be.
`flag_contaminant(require_control_evidence = TRUE)` separates them, and
declines to assign any contamination verdict to a sequence that was never
detected in a control. With `site_col`, site multiplicity becomes a
discriminant rather than merely extra power: a systemic contaminant
appears in controls across many sites irrespective of which sites'
samples carry it, whereas carryover concentrates at the one site whose
samples are full of it. That distinction resolves the usual trade-off
between pooling controls for power and pairing them per collection event
for specificity.

# Data and Hardware Requirements {#data-and-hardware-requirements}

-   **Internet access** is required for GBIF queries, NCBI BLAST, and
    LLM API calls. Offline operation is possible when using cached data
    and local Ollama models.
-   **NCBI rate limits**: a large remote-BLAST run (e.g.
    `TaxaMatch::evaluate_reference_accessions()` over hundreds of
    reference accessions) can hit NCBI's own fair-use rate limiting or
    CPU-budget throttling partway through. TaxaMatch has some functions
    designed to make remote BLAST more robust. Importantly, it knows
    when to stop trying; `blast_sequences()`'s circuit breaker
    (`max_consecutive_batch_failures`) detects sustained failures and
    stops early rather than waiting out every remaining doomed batch;
    `evaluate_reference_accessions()` caches its results incrementally
    (`chunk_size`) so an interrupted or throttled run only loses
    whatever chunk was in flight, and reports a recommended pause before
    resuming the same call. `TaxaMatch::review_flagged_accessions()`'s
    LLM second-look review is real, billed API cost too, and caches on
    the same principle (`cache_dir`); re-running it only pays for
    accessions whose inputs genuinely changed since the last review, not
    the whole set again.
-   **No specialized hardware** is required. All packages run on
    standard desktop hardware (macOS, Linux, or Windows) with R \>=
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
|------------------|------------------|------------------|------------------|
| R | \>= 4.1.0 | 64 | R Core Team. 2025. R: A Language and Environment for Statistical Computing. V.4.5.2. <https://www.r-project.org>. |
| Bioconductor (DECIPHER, Biostrings) | \>= 3.17 | 64 | Gentleman et al. 2004. Bioconductor. <https://www.bioconductor.org>. Required only for `TaxaLikely::build_sequence_matrix()`. |
| rBLAST | \>= 0.99 | 64 | Hahsler and Nagar. 2024. rBLAST. Bioconductor. <https://doi.org/10.18129/B9.bioc.rBLAST>. Optional; required only for local BLAST in TaxaMatch. |

All other R package dependencies are declared in each package's
DESCRIPTION file and will be installed automatically by
`devtools::install()` or `install.packages()`.

### API Keys {#api-keys}

To access LLM tools, the user can use a locally installed LLM (Ollama)
or an API key provided by an LLM service (set in `~/.Renviron`). A user
could use a different LLM by modifying one of the existing LLM calls.

| Key | Required By | How to Obtain |
|------------------------|------------------------|------------------------|
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
  remotes::install_github("DOI-USGS/TaxaID", subdir = pkg)
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
|------------------------|------------------------|------------------------|
| [TaxaTools](TaxaTools/) | Name verification, cleaning, parsing, rank lookup, column standardization; LLM provider functions; GBIF backbone census | CC0 |
| [TaxaFetch](TaxaFetch/) | Occurrence data acquisition (GBIF, DataONE, PDF, literature search), source combination | CC0 |
| [TaxaHabitat](TaxaHabitat/) | Habitat assignment via LLM biological consensus; spatial QAQC | CC0 |
| [TaxaMatch](TaxaMatch/) | Match standardization. Sequence input (DADA2/FASTA), BLAST search. | CC0 |
| [TaxaLikely](TaxaLikely/) | Convert match scores to likelihoods using hierarchical Bayesian model; reference QC | CC0 |
| [TaxaExpect](TaxaExpect/) | Spatially explicit Bayesian priors from occurrence and habitat data | CC0 |
| [TaxaAssign](TaxaAssign/) | Posterior computation, consensus taxonomy, report generation | CC0 |
| [TaxaFlag](TaxaFlag/) | Post-assignment anomalous detection flagging (contamination, transport, scope) | CC0 |
| [TaxaWizard](TaxaWizard/) | Conversational LLM workflow designer: guided interview to .R script, .md methods, or Shiny app | CC0 |

## Pipeline Overview

The diagram below shows the full set of supported workflow paths. Every
path converges at the assignment step; users can start from whichever
inputs they have.

``` mermaid
flowchart TD
    %% Field data inputs → match_df
    F1["seqtab / FASTA\n(eDNA / metabarcoding)"] -->|TaxaMatch| MD
    F2["BirdNET CSVs\n(acoustic)"] -->|read_birdnet_output| MD
    F3["camera trap classifier output\nAniml · iNat CV · Wildlife Insights"] -->|read_animl/inat/wi_output| MD
    MD(["match_df"])

    %% Reference library building → model_params (DNA only)
    R1["taxa names"] -->|"fetch_ncbi_reference_sequences\n+ audit_barcode_coverage"| RD
    R2["CRABS / local FASTA"] -->|"read_crabs_output
read_reference_fasta"| RD
    RD(["reference_df"]) -->|build_sequence_matrix| RMAT(["DNA matrix"])
    RMAT -->|train_likelihood_model| MP(["model_params"])

    %% Priors
    TL["taxa + location"] -->|"TaxaFetch + TaxaHabitat
+ TaxaExpect"| PR(["prior_df"])

    %% Likelihoods — three entry points
    MD & MP -->|"evaluate_likelihoods\n(DNA: uses model_params)"| LK
    MD -->|"assign_scores\n(acoustic / image: no model)"| LK
    CON["consensus_df\n(morphology / expert IDs)"] -->|"unreferenced_candidates\n+ assign_scores"| LK
    LK(["likelihoods"])

    %% Assignment
    LK -->|compute_posterior| PO
    PR -->|compute_posterior| PO
    PO(["posteriors"]) -->|"posterior_consensus
+ generate_report"| OUT["consensus assignment\n+ methods report"]
```

*TaxaWizard can generate a complete R script for any of the paths above
via a guided interview: `workflow_create()`.*

## Which Entry Point Do I Need?

If you're not sure where to start, the fastest path is often the least
code: `TaxaWizard::workflow_create()` interviews you about your data and
goals and generates a complete, runnable R script for you (see
[Interactive Workflow Designer](#interactive-workflow-designer), below).
An AI assistant working from a stated goal should do the same thing
programmatically -- identify the workflow graph node/edge before
guessing at individual functions, rather than writing ad-hoc R against
remembered function names. For example: *"I have BLAST results from an
eDNA metabarcoding study. I want to assign species only when the
sequence matches at 100%, and otherwise retain a higher-level
assignment"* is a match-scores-in, consensus-out request -- the
`match_to_consensus_score` edge (score-based consensus, no Bayesian
priors or LLM), with the 100% rule translated to that edge's
`min_score`/rank-threshold parameters rather than a hand-written filter.
See [Using TaxaID with any LLM](TaxaWizard/README.md#using-taxaid-with-any-llm)
in the TaxaWizard README for the full mechanism and how to point a
non-Claude-Code AI assistant at it.

If you'd rather find the right starting point yourself, match your data
to a row below:

| Your starting point | Start here |
|------------------------------------|------------------------------------|
| DADA2 sequence table or FASTA file (eDNA/metabarcoding) | `TaxaMatch::read_sequence_table()` / `TaxaMatch::blast_sequences()` -- see `TaxaMatch/inst/workflow_fastq_to_match.R` |
| BirdNET CSV output (acoustic) | `TaxaMatch::read_birdnet_output()` -- see `TaxaMatch/inst/workflow_image_acoustic.R` |
| Camera-trap classifier output (Animl / iNaturalist CV / SpeciesNet) | `TaxaMatch::read_animl_output()` / `read_inaturalist_cv_output()` / `read_speciesnet_output()` |
| A table of candidate matches you've already built (any data type) | Start at `TaxaLikely::evaluate_likelihoods()` (or `assign_scores()` for a no-training-data pathway) |
| Expert/morphological IDs with no match scores at all | `TaxaLikely::unreferenced_candidates()` + `assign_scores(score_type = "none")` |
| Just a list of taxon names and site coordinates (no observation data yet) | Fetch occurrences (e.g. `TaxaFetch::get_gbif_occurrences()`), then `TaxaExpect::estimate_kernel_priors()` -- see `TaxaExpect/README.md`'s Quick Start. |

For a worked example of a single pipeline stage, see that package's own
`inst/workflows/*.R` scripts and its vignette -- e.g.
`TaxaLikely/inst/workflows/sequence_likelihood_workflow.R`,
`TaxaMatch/inst/workflows/blast_sequences_workflow.R`,
`TaxaAssign/inst/workflows/compute_posteriors_workflow.R`.

To build a complete workflow for a new site, start from
`TaxaID_eDNA_Workflow_Template.R` (in the separate `eDNA` repository, at
`eDNA/PtConception/`) -- the template the three PtConception production
workflows were built from.

**To confirm your installation works**, run one of the fast smoke tests.
Each chains `evaluate_likelihoods()` -\> `compute_posterior()` -\>
`posterior_consensus()` -\> `add_slash_taxon()` against a small *real*
fixture extracted from a completed production run, in a few seconds,
with no network calls and no API key:

``` r
# from the repository root -- the fixture paths are relative to it
source("diagnostics/fast_workflows/run_fast_smoketest.R")            # ~7 s
source("diagnostics/fast_workflows/run_greatlakes_fast_smoketest.R") # ~6 s
```

Both print warnings about hypotheses below `min_posterior` and about
genus-level names in `plausible_taxa`. Those are expected: the fixtures
use a flat placeholder prior, which is loudly labelled in each script.
See `diagnostics/fast_workflows/README.md`.

### The workflow template

`inst/TaxaID_Workflow_Template.R` is a single-site template covering the
canonical path from raw sequences to reviewed assignments. Edit its
Section 0, supply your own input, and run it top to bottom. It carries no
study's data and no real paths.

**It is generated, not written.** `diagnostics/build_workflow_template.R`
assembles it from the workflow graph's own snippets -- the same files
TaxaWizard generates scripts from -- resolving each step's inputs from the
graph's edge wiring and each parameter from one configuration table.

That indirection is the point, and it is worth explaining because this
package spent a long time on the other approach.
`inst/TaxaID_Workflow_Template_TEST.R` filled this role until 2026-09-15,
when it was retired: its Section 5 called seven functions archived with the
GLMM prior-fitting chain on 2026-09-09, so it had not been runnable for
months while still receiving patches. The canonical template in the `eDNA`
repository had independently fallen behind on four subsystems. Two
hand-maintained templates, both stale, both looking maintained.

The conclusion drawn at the time was that a second in-package copy of a
workflow is what caused it, so the template was not replaced. That was the
right diagnosis of the wrong unit: the problem is not a second copy, it is
a second copy that nothing compares to the first. This one is compared.
`TaxaWizard/tests/testthat/test-workflow-template.R` regenerates it and
fails if the committed file differs, and separately asserts that it parses,
that every `Pkg::fn` it calls is a real export, and that every named
argument is a real formal. A snippet change that never reached the template
breaks the build rather than quietly making the template wrong.

To update it after changing a snippet:

```bash
Rscript diagnostics/build_workflow_template.R
```

See `archive_retired_workflow_template_2026_09_15/README.md` for the
retired one.

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
|------------------------|------------------------|------------------------|
| FASTQ to match data (eDNA) | TaxaMatch | `inst/workflow_fastq_to_match.R` |
| Image and acoustic identification | TaxaMatch | `inst/workflow_image_acoustic.R` |
| Fetch reference sequences (DNA) | TaxaLikely | `inst/workflows/1_fetch_references_workflow.R` |
| Flag reference errors | TaxaLikely | `inst/workflows/2_flag_errors_workflow.R` |
| Train likelihood model (DNA) | TaxaLikely | `inst/workflows/3_train_model_workflow.R` |
| Score to likelihood (image/acoustic) | TaxaLikely | `inst/workflows/image_acoustic_likelihood_workflow.R` |
| Score to likelihood (DNA) | TaxaLikely | `inst/workflows/4_score_to_likelihood_workflow.R` |
| Audit reference coverage | TaxaLikely | `inst/workflows/5_audit_coverage_workflow.R` |
| No-score pathway (morphology/expert IDs) | TaxaLikely | `inst/workflows/6_no_score_pathway_workflow.R` |
| **Demo: local reference library** | TaxaLikely | `inst/workflows/local_reference_demo.R` |
| Fetch occurrences | TaxaFetch | `inst/Merge_sources_workflow.R` |
| Assign habitats | TaxaHabitat | `inst/workflows/assign_habitat_workflow.R` |
| Build priors | TaxaExpect | `inst/TaxaExpect_workflow.R` |
| LLM assignment | TaxaAssign | `inst/TaxaAssign_llm_workflow.R` |
| Bayesian assignment | TaxaAssign | `inst/TaxaAssign_bayesian_workflow.R` |

For a step-by-step map of the full pipeline — inputs, outputs, and save
conventions across all packages — see
[ECOSYSTEM_WORKFLOW.md](ecosystem_docs/ECOSYSTEM_WORKFLOW.md).

## High-Level Wrappers

For users who prefer a single-function interface:

``` r
library(TaxaAssign)

# Full Bayesian pipeline (~1 call, plus a saved model generated by TaxaLikely)
result <- run_bayesian_pipeline(match_df, model_params, taxaexpect_priors = taxaexpect_priors,
                                 backbone_id = 11)  # 11 = GBIF backbone; 4 = NCBI

# LLM-shortcut pipeline (~1 call)
result <- run_llm_pipeline(match_df, geographic_hint = "34.4 N, -119.8 W", habitat_scheme = "Marine",
                            backbone_id = 11)  # 11 = GBIF backbone; 4 = NCBI
```

## Interactive Workflow Designer {#interactive-workflow-designer}

TaxaWizard provides a guided, conversational interface:

``` r
library(TaxaWizard)

# Opens a chat interface that interviews you about your data and goals,
# then generates a complete, runnable R script convertible to a shiny app.
workflow_create()
```

# Troubleshooting

**"No LLM provider configured" or an LLM call silently returns a
uniform/degraded result.** Confirm the relevant key (see [API
Keys](#api-keys), above) is set in `~/.Renviron`, not just your current
shell session, then restart R. Provider auto-detection runs when a
TaxaID package is attached with `library()` -- calling functions only
via `TaxaTools::call_api()` (fully namespaced, no `library()` call)
skips it. If you're running a script non-interactively (`Rscript`, not
RStudio) and still see this after setting the key, pass a provider
explicitly:

``` r
llm_fn <- function(prompt) TaxaTools::call_api(prompt, provider = "anthropic")
```

**A recent bug fix or package update doesn't seem to have taken
effect.** The most common cause is an R session that had the old version
loaded before the update was installed. After any
`remotes::install_github()` (or `devtools::install()` from source):

``` r
.rs.restartR()                          # restart, clearing anything already loaded
library(TaxaTools)                       # reload every package you use
packageDescription("TaxaTools")$Built    # confirm this build is recent, not stale
```

If a workflow caches intermediate results to `.rds` checkpoint files
(most of the worked-example scripts under each package's `inst/` do this
so long steps aren't re-run unnecessarily), a fix to logic *downstream*
of an existing checkpoint won't show up until that checkpoint is deleted
or the workflow is re-run with caching disabled -- a raw-data fetch
cache generally does not need clearing when only downstream
filtering/statistical logic changed, but check the specific script's own
caching comments if a fix genuinely doesn't seem to be taking effect.

**GBIF or NCBI calls are slow, throttled, or fail partway through a
large fetch.** See the NCBI rate-limit note under [Data and Hardware
Requirements](#data-and-hardware-requirements) -- functions that make
many requests (`evaluate_reference_accessions()`, `blast_sequences()`,
`download_gbif_occurrences()`) support `cache_dir`, so an interrupted
run can resume from where it left off instead of restarting from
scratch.

**Getting help.** If none of the above resolves it, please open an issue
at <https://github.com/DOI-USGS/TaxaID/issues> with your R version, the
exact error message, and a minimal reproducible example if possible --
this helps other users hitting the same issue find the answer too, and
keeps a public record other than a private email thread.

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
    sequences in reference databases, via a free local-corroboration
    check followed by a BLAST-based screen
    (`TaxaMatch::corroborate_references_locally()`,
    `TaxaMatch::evaluate_reference_accessions()`). This can help users
    avoid basing assignments on reference errors.
-   **Coverage audits** enumerating described species per genus and
    flagging taxa absent from the reference library
    (`audit_barcode_coverage()`, `audit_reference_coverage()`). This can
    help users understand limits in precision.
-   **Model diagnostics** summarizing expected match percentages, score
    gaps, and per-species profiles (`interpret_model()`). This can help
    users understand how scores relate to precision.

### Expected Composition and Priors

-   **Site-centered kernel estimation** (current recommended path)
    predicting each taxon's expected share of the detections at a focal
    site from a distance-weighted (geo x optional-covariate) kernel over
    nearby occurrence records, with bandwidth chosen by
    leave-one-block-out composition prediction
    (`estimate_kernel_priors()`, `calibrate_kernel_bandwidth()`).
-   **Beta priors** (alpha, beta) for every taxon at the focal site,
    including undetected diversity estimates (Good-Turing/Chao-anchored)
    for plausible but unobserved species
    (`generate_undetected_diversity()`).
-   **KDE prior-field maps** -- static or interactive Leaflet views of
    the estimator evaluated continuously across a lattice, not just at
    one site (`plot_theta_surface()`).

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
| TaxaTools   | 48                 | 23         | Yes      |
| TaxaFetch   | 32                 | 25         | Yes      |
| TaxaHabitat | 17                 | 7          | Yes      |
| TaxaMatch   | 32                 | 21         | Yes      |
| TaxaLikely  | 32                 | 24         | Yes      |
| TaxaExpect  | 15                 | 12         | Yes      |
| TaxaAssign  | 16                 | 16         | Yes      |
| TaxaFlag    | 11                 | 10         | Yes      |
| TaxaWizard  | 5                  | 4          | No       |

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

Altschul, S.F., Gish, W., Miller, W., Myers, E.W. and Lipman, D.J.
(1990). Basic local alignment search tool. *Journal of Molecular
Biology*, 215(3), 403--410.

Beentjes, K.K., Speksnijder, A.G.C.L., Schilthuizen, M., Hoogeveen, M.,
Pastoor, R. and van der Hoorn, B.B. (2019). Increased performance of DNA
metabarcoding of macroinvertebrates by taxonomic sorting. *PLOS ONE*,
14(12), e0226527.

Callahan, B.J., McMurdie, P.J., Rosen, M.J., Han, A.W., Johnson, A.J.A.
and Holmes, S.P. (2016). DADA2: High-resolution sample inference from
Illumina amplicon data. *Nature Methods*, 13(7), 581--583.

Chiranjeevi, S., Saadati, M., Deng, Z.K., Koushik, J., Jubery, T.Z.,
Mueller, D.S., O'Neal, M., Merchant, N., Singh, Aarti, Singh, A.K.,
Sarkar, S., Singh, Arti and Ganapathysubramanian, B. (2025). InsectNet:
Real-time identification of insects using an end-to-end machine learning
pipeline. *PNAS Nexus*, 4(1), pgae575.
<https://doi.org/10.1093/pnasnexus/pgae575>

Davis, N.M., Proctor, D.M., Holmes, S.P., Relman, D.A. and Callahan,
B.J. (2018). Simple statistical identification and removal of
contaminant sequences in marker-gene and metagenomics data.
*Microbiome*, 6, 226.

Dussert, G., Chamaillé-Jammes, S., Dray, S. and Miele, V. (2025). Being
confident in confidence scores: calibration in deep learning models for
camera trap image sequences. *Remote Sensing in Ecology and
Conservation*, 11(1), 88--99.

Edgar, R.C. (2016). SINTAX: a simple non-Bayesian taxonomy classifier
for 16S and ITS sequences. *bioRxiv*, 074161.

Fairbairn, A.J., Burmeister, J.S., Weisser, W.W. and Meyer, S.T. (2025).
BirdNET can be as good as experts for acoustic bird monitoring in a
European city. *PLoS One*, 20(9), e0330836.

Ficetola, G.F., Pansu, J., Bonin, A., Coissac, E., Giguet-Covex, C., De
Barba, M., Gielly, L., Lopes, C.M., Boyer, F., Pompanon, F., Rayé, G.
and Taberlet, P. (2015). Replication levels, false presences and the
estimation of the presence/absence from eDNA metabarcoding data.
*Molecular Ecology Resources*, 15(3), 543--556.

Gentleman, R.C., Carey, V.J., Bates, D.M., Bolstad, B., Dettling, M.,
Dudoit, S., Ellis, B., Gautier, L., Ge, Y., Gentry, J., Hornik, K.,
Hothorn, T., Huber, W., Iacus, S., Irizarry, R., Leisch, F., Li, C.,
Maechler, M., Rossini, A.J., Sawitzki, G., Smith, C., Smyth, G.,
Tierney, L., Yang, J.Y.H. and Zhang, J. (2004). Bioconductor: open
software development for computational biology and bioinformatics.
*Genome Biology*, 5, R80.

Hahsler, M. and Nagar, A. (2024). rBLAST: R Interface for the Basic
Local Alignment Search Tool. R package version 0.99.4. Bioconductor.
<https://doi.org/10.18129/B9.bioc.rBLAST>

Henrich, M., Fiderer, C., Klamm, A., Schneider, A., Ballmann, A., Stein,
J., Kratzer, R., Reiner, R., Greiner, S., Twietmeyer, S., Rönitz, T.,
Spicher, V., Chamaillé-Jammes, S., Miele, V., Dussert, G. and Heurich,
M. (2026). Camera traps and deep learning enable efficient large-scale
density estimation of wildlife in temperate forest ecosystems. *Remote
Sensing in Ecology and Conservation*, 12(1), 148--163.

Jeunen, G.-J., Dowle, E., Edgecombe, J., von Ammon, U., Gemmell, N.J.
and Cross, H. (2023). crabs -- A software program to generate curated
reference databases for metabarcoding sequencing data. *Molecular
Ecology Resources*, 23(3), 725--738.

Lafferty, K.D., 2026, TaxaID -- A modular R ecosystem for Bayesian
taxonomic assignment: U.S. Geological Survey software release,
<https://doi.org/10.5066/xxxxxx>.

Macher, T.-H., Beermann, A.J. and Leese, F. (2021). TaxonTableTools: a
comprehensive, platform-independent graphical user interface software to
explore and visualise DNA metabarcoding data. *Molecular Ecology
Resources*, 21(5), 1705--1714.

Marques, V., Milhau, T., Albouy, C., Dejean, T., Manel, S., Mouillot, D.
and Juhel, J.-B. (2021). GAPeDNA: assessing and mapping global species
gaps in genetic databases for eDNA metabarcoding. *Diversity and
Distributions*, 27(10), 1880--1892.

Murali, A., Bhargava, A. and Wright, E.S. (2018). IDTAXA: a novel
approach for accurate taxonomic classification of microbiome sequences.
*Microbiome*, 6, 140.

Orsholm, J., Zito, A., Somervuo, P., Harrison, J.P., Koskela, M.,
Ovaskainen, O., Braga, M.P., Chazot, N., Roslin, T. and Furneaux, B.
(2026). Discovering the unseen: A performance comparison of taxonomic
classification methods for unknown DNA barcodes. *Methods in Ecology and
Evolution*, 17(9), 2574--2593.

Pappalardo, P., Hemmi, J.M., Machida, R.J., Leray, M., Collins, A.G. and
Osborn, K.J. (2025). Taxon-specific BLAST percent identity thresholds
for identification of unknown sequences using metabarcoding. *Methods in
Ecology and Evolution*, 16(10), 2380--2394.

Pearman, J.K., Aylagas, E. and Carvalho, S. (2026). BIOWATCH: a R shiny
application for the detection of species of interest in metabarcoding
datasets. *BMC Bioinformatics*, 27, 147.
<https://doi.org/10.1186/s12859-026-06468-2>

R Core Team (2025). *R: A Language and Environment for Statistical
Computing*. Version 4.5.2. R Foundation for Statistical Computing,
Vienna, Austria. <https://www.r-project.org>

Shea, M.M. and Boehm, A.B. (2024). Environmental DNA metabarcoding
differentiates between micro-habitats within the rocky intertidal.
*Environmental DNA*, 6(2), e521.

Somervuo, P., Koskela, S., Pennanen, J., Nilsson, R.H. and Ovaskainen,
O. (2016). Unbiased probabilistic taxonomic classification for DNA
barcoding. *Bioinformatics*, 32(19), 2920--2927.

Somervuo, P., Yu, D.W., Xu, C.C.Y., Ji, Y., Hultman, J., Wirta, H. and
Ovaskainen, O. (2017). Quantifying uncertainty of taxonomic placement in
DNA barcoding and metabarcoding. *Methods in Ecology and Evolution*,
8(4), 398--407.

Tabak, M.A., Norouzzadeh, M.S., Wolfson, D.W., Sweeney, S.J.,
Vercauteren, K.C., Snow, N.P., Halseth, J.M., Di Salvo, P.A., Lewis,
J.S., White, M.D., Teton, B., Beasley, J.C., Schlichting, P.E.,
Boughton, R.K., Wight, B., Newkirk, E.S., Ivan, J.S., Odell, E.A.,
Brook, R.K., Lukacs, P.M., Moeller, A.K., Mandeville, E.G., Clune, J.
and Miller, R.S. (2019). Machine learning to classify animal species in
camera trap images: applications in ecology. *Methods in Ecology and
Evolution*, 10(4), 585--590.

Thompson, M.C., Ducey, M.J., Gunn, J.S. and Rowe, R.J. (2025). A
post-processing framework for assessing BirdNET identification accuracy
and community composition. *Ibis*, 167(2), 530--542.

Wang, Q., Garrity, G.M., Tiedje, J.M. and Cole, J.R. (2007). Naive
Bayesian classifier for rapid assignment of rRNA sequences into the new
bacterial taxonomy. *Applied and Environmental Microbiology*, 73(16),
5261--5267.

Wilkinson, S.P., Davy, S.K., Bunce, M. and Stat, M. (2018). Taxonomic
identification of environmental DNA with informatic sequence
classification trees. *PeerJ Preprints*, 6, e26812v1.
<https://doi.org/10.7287/peerj.preprints.26812v1>

Zaiko, A., Greenfield, P., Abbott, C., von Ammon, U., Bilewitch, J.,
Bunce, M., Cristescu, M.E., Chariton, A., Dowle, E., Geller, J.,
Ardura Gutierrez, A., Hajibabaei, M., Haggard, E., Inglis, G.J.,
Lavery, S.D., Samuiloviene, A., Simpson, T., Stat, M., Stephenson, S.,
Sutherland, J., Thakur, V., Westfall, K., Wood, S.A., Wright, M.,
Zhang, G. and Pochon, X. (2023). Pest Alert Tool: a web-based
application for flagging species of concern in metabarcoding datasets.
*Nucleic Acids Research*, 51(W1), W438--W442.

Zito, A., Rigon, T. and Dunson, D.B. (2023). Inferring taxonomic
placement from DNA barcoding aiding in discovery of new taxa. *Methods
in Ecology and Evolution*, 14(2), 529--542.
