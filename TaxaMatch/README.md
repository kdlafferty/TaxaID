---
editor_options: 
  markdown: 
    wrap: 72
---

# TaxaMatch

Store and standardize biological match data for the
[TaxaID](https://github.com/DOI-USGS/TaxaID) ecosystem. Ingests raw
match results from external classification tools and produces a
canonical match object for input to TaxaLikely (likelihood conversion)
or TaxaAssign (direct assignment).

The main input to TaxaID is a table where each row pairs an
observation (sequence, image, or sound recording) with a candidate
taxon from a reference database and a match score indicating their
similarity. TaxaMatch standardizes column names and taxonomy so that
downstream packages can interpret this table. Standardization is a
prerequisite for calibrating scores into likelihoods -- without it,
raw scores may be mistaken for probabilities, leading to overconfident
or inconsistent assignments.

TaxaMatch can also produce match tables from raw sequence data via
NCBI BLAST, though most users will start from an existing
bioinformatics pipeline.

## Supported Data Types

| Data type | Input format | Function |
|------------------------|------------------------|------------------------|
| **DNA sequences** | DADA2 seqtab, FASTA, DNAStringSet | `read_sequence_table()` |
| **BLAST results** | Remote NCBI or local rBLAST | `blast_sequences()` |
| **Images** | Animl CSV export | `read_animl_output()` |
| **Acoustics** | BirdNET-Analyzer CSV | `read_birdnet_output()` |

## Installation

``` r
# Requires TaxaTools (foundation package)
devtools::install("path/to/TaxaTools")
devtools::install("path/to/TaxaMatch")
```

## Quick Start

``` r
library(TaxaMatch)

# 1. Read DADA2 output
seqs <- read_sequence_table("seqtab_nochim.rds")

# 2. Filter by length and abundance
filtered <- filter_sequences(seqs, min_length = 100, max_length = 300,
                             min_reads = 10)

# 3. BLAST against NCBI
blast_hits <- blast_sequences(filtered, database = "nt",
                              barcode_term = "12S",
                              min_score = 80)

# 4. Standardize to canonical match object
match_df <- standardize_match_data(blast_hits)

# 5. Remove redundant higher-rank hypotheses
match_df <- filter_redundant_hypotheses(match_df)
# Result: one row per observation_id x taxon hypothesis, ready for TaxaLikely

```

## Key Functions

-   `read_sequence_table()` -- ingest DADA2 seqtab matrix, FASTA, or
    DNAStringSet
-   `filter_sequences()` -- filter ASVs by length range and minimum
    abundance
-   `blast_sequences()` -- remote NCBI BLAST or local rBLAST with score
    window filtering and taxonomy resolution
-   `read_birdnet_output()` -- ingest BirdNET-Analyzer CSV files;
    `observation_id` encodes recording + time window
    (`"{stem}_{start_s}-{end_s}"`); `score` is BirdNET confidence (0--1)
-   `read_animl_output()` -- ingest Animl (MegaDetector + SpeciesNet)
    camera trap CSV; `observation_id` = image filename stem; configurable
    column names; supports long and wide (`n_candidates`) formats
-   `standardize_match_data()` -- canonical column names, taxonomy
    derivation via `TaxaTools::create_taxon_names()`
-   `filter_redundant_hypotheses()` -- drop coarser-rank rows superseded
    by finer-rank rows within the same lineage and observation
-   `report_match()` -- summarize matching for `assemble_report()`

## Acoustic Workflow

BirdNET-Analyzer is a free Python tool from the Cornell Lab of
Ornithology that classifies bird vocalizations in audio files.

**Install BirdNET-Analyzer** (requires Python 3.9+, \~100 MB model
download):

``` bash
pip3 install birdnetlib
```

**Analyze audio files and read results into R:**

``` r
library(TaxaMatch)

# Run BirdNET-Analyzer on a directory of audio files
script <- '
from birdnetlib import Recording
from birdnetlib.analyzer import Analyzer
import os, csv

os.makedirs("birdnet_results", exist_ok=True)
analyzer = Analyzer()
for fname in os.listdir("reference_audio/"):
    if not fname.endswith(".mp3"):
        continue
    rec = Recording(analyzer, os.path.join("reference_audio/", fname),
                    lat=37.5, lon=-122.0, min_conf=0.1)
    rec.analyze()
    out = os.path.join("birdnet_results", fname.replace(".mp3", ".BirdNET.results.csv"))
    with open(out, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["Start (s)", "End (s)", "Scientific name", "Common name", "Confidence"])
        for d in rec.detections:
            w.writerow([d["start_time"], d["end_time"],
                        d["scientific_name"], d["common_name"], d["confidence"]])
'
writeLines(script, "/tmp/run_birdnet.py")
system("python3 /tmp/run_birdnet.py")

# Read results into match object format
match_df <- read_birdnet_output("birdnet_results/",
                                min_confidence = 0.1,
                                top_n          = 3L)

# Standardize and pass to TaxaLikely
match_df <- standardize_match_data(match_df,
                                   observation_id_col = "observation_id",
                                   score_col          = "score")
```

**Expected BirdNET output format:** one CSV per audio file, named
`recording.BirdNET.results.csv`, with columns `Start (s)`, `End (s)`,
`Scientific name`, `Common name`, `Confidence`. The BirdNET-Analyzer
default produces up to 3 detections per 3-second window. Use
`top_n = 1` to keep only the best candidate per window.

**Reference training workflow:** Download ground-truth recordings from
Xeno-canto with `TaxaLikely::fetch_reference_recordings()`, run
BirdNET-Analyzer on the downloaded audio, then join detections back to
the known species via `source_file` to label H1/H2/H3 training
examples.

## Camera Trap Image Workflow

Animl (MegaDetector + SpeciesNet) is an R package on CRAN that
classifies camera trap images. Install it with
`install.packages("animl")` (requires Python ≥ 3.12 via `reticulate`).

**Read Animl results into match object format:**

``` r
library(TaxaMatch)

# Long-format Animl CSV (one row per image x candidate species)
match_df <- read_animl_output(
  "animl_results/",        # directory of Animl export CSVs
  min_confidence = 0.5     # drop low-confidence detections
) |>
  # Remove non-wildlife detections before standardizing
  subset(!species %in% c("empty", "human", "vehicle"))

# Wide-format output (pred1/score1, pred2/score2, pred3/score3 per row)
match_df_wide <- read_animl_output(
  "animl_results/wide.csv",
  species_col  = "pred",
  score_col    = "score",
  n_candidates = 3L
)

# Standardize and pass to TaxaLikely
match_df <- standardize_match_data(match_df,
                                   observation_id_col = "observation_id",
                                   score_col          = "score")
```

**Expected Animl output format (long):** one or more CSV files with
columns `FileName`, `prediction`, `confidence`. `FileName` is the image
path; `prediction` is the species label (scientific name, `"empty"`,
`"human"`, or `"vehicle"`); `confidence` is the classifier posterior
(0--1). Column names are configurable via `file_col`, `species_col`, and
`score_col`.

**Coverage audit:** Check which expected species are absent from the
classifier's known list with
`TaxaLikely::audit_acoustic_coverage(plausible_species, reference_species)`.
Pass the result's `$unreferenced` vector to
`TaxaAssign::suggest_unreferenced_species()` as `unreferenced_taxa`.

## Match Object Output

The canonical match object has one row per `observation_id` x reference
match:

| Column | Description |
|----|----|
| `observation_id` | Query identifier (ESV/ASV ID) |
| `score` | Match score (0--100 for BLAST percent identity) |
| `taxon_name` | Best taxon label at finest available rank |
| `taxon_name_rank` | Rank of `taxon_name` (species, genus, etc.) |
| `family`, `genus`, `species`, ... | Taxonomy columns |

## Vignettes

-   [Match Standardization](vignettes/match-standardization.Rmd) -- full
    workflow

## Part of TaxaID

TaxaMatch standardizes match data for two downstream paths: TaxaLikely
(Bayesian likelihood model) or TaxaAssign (direct LLM-based assignment).

**Ecosystem:** TaxaTools -\> **TaxaMatch** -\> TaxaLikely -\> TaxaAssign

See the [TaxaID README](https://github.com/DOI-USGS/TaxaID) for
ecosystem overview and installation instructions.

## Citation

Lafferty, K.D., 2026, TaxaID -- A modular R ecosystem for Bayesian
taxonomic assignment: U.S. Geological Survey software release,
<https://doi.org/10.5066/xxxxxx>.

## Software Requirements

-   R (\>= 4.1.0)
-   TaxaTools (foundation package, installed first)
-   httr2 and rentrez (for remote NCBI BLAST)
-   Biostrings and rBLAST (optional; for local BLAST)
-   Python 3.9+ and birdnetlib (`pip3 install birdnetlib`; optional,
    for acoustic analysis via BirdNET-Analyzer)

All dependencies are declared in the DESCRIPTION file and installed
automatically.

Developed with [Claude Code](https://claude.ai/code) (Anthropic).
