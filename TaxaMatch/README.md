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
| **Images** | Animl CSV export | Planned |
| **Acoustics** | BirdNET CSV | Planned |

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
-   `standardize_match_data()` -- canonical column names, taxonomy
    derivation via `TaxaTools::create_taxon_names()`
-   `filter_redundant_hypotheses()` -- drop coarser-rank rows superseded
    by finer-rank rows within the same lineage and observation
-   `report_match()` -- summarize matching for `assemble_report()`

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

All dependencies are declared in the DESCRIPTION file and installed
automatically.
