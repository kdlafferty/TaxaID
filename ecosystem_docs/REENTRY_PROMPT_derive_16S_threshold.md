# Reentry prompt: derive an empirical 16S percent-identity threshold

**From:** Cowork session, 2026-07-20, aquarium mock-community benchmark design
(`AQUARIUM_BENCHMARK_DESIGN.md`). **Read that doc first** for full context —
this prompt only covers the one remaining open item it couldn't resolve
without R: a defensible 16S percent-identity threshold for
`score_consensus()`'s marker-aware baseline (Section 4a).

**Why this is needed:** COI has a well-established 4-tier threshold
convention (98/95/90/85 species/genus/family/phylum, per Elbrecht et al.
2017, Machida et al. 2009, etc.) and 12S has Miya et al. (2015)'s 2-tier
scheme (≥97% species, 95–<97% genus). No equivalent exists for vertebrate
mitochondrial 16S — Yarza et al. (2014)'s 16S convention is for prokaryotic
16S rRNA (wrong molecule) and Roblet et al. (2024) was checked and ruled out
(uses OTU-clustering and chimera-filter parameters, not a species-assignment
threshold). Decision made 2026-07-20: derive it empirically from real
reference-sequence data instead of guessing or borrowing COI's numbers.

**State at handoff:**
- Morey et al. (2020)'s supplementary Table S1 (107 Rainbow Reef tank
  species, abundance, per-marker GenBank reference availability, detection
  results, in-silico primer binding) has been downloaded, parsed, and saved
  as `ecosystem_docs/morey_table_s1_species_list.csv` (108 lines incl.
  header, 11 columns, verified against the paper's reported N=107).
- `diagnostics/score_floor_roc_sweep.R` already does exactly this kind of
  empirical ROC-style threshold derivation for 12S/18S data (real
  within-species/congeneric/confamilial/cross-family ground truth from a
  `seq_matrix`, Youden's J-optimal threshold, comparison against conventional
  thresholds). It just needs to be pointed at a 16S `seq_matrix` instead.
- This Cowork session has no R available, so none of the steps below have
  actually been run yet — this is a spec, not a completed result.

## Task: build a 16S seq_matrix for the Morey species and run the sweep

### Step 1 — Load the species list and filter to those with 16S references

```r
library(dplyr)
library(TaxaTools)
library(TaxaLikely)

species_df <- read.csv(
  "~/My Drive/Rscripts/projects/TaxaID/ecosystem_docs/morey_table_s1_species_list.csv"
)

species_16s <- species_df |> filter(ref_16s == "Yes")
message(sprintf("%d of %d species have a 16S reference sequence (per Morey's Table S1).",
                nrow(species_16s), nrow(species_df)))
# Worth reporting this count in the eventual manuscript as a documented
# reference-gap figure, independent of the threshold question itself.
```

### Step 2 — Expand taxonomy (need genus/family for fetch + seq_matrix grouping)

```r
ncbi_names <- verify_taxon_names(species_16s$species, backbone_id = 4)
tax_wide <- as.data.frame(setNames(
  lapply(c("family", "genus", "species"), function(rk) {
    unname(mapply(
      TaxaTools::parse_classification_path,
      ncbi_names$classification_path,
      ncbi_names$classification_ranks,
      MoreArgs = list(target_rank = rk)
    ))
  }),
  c("family", "genus", "species")
))
tax_wide$ScientificName <- ncbi_names$user_supplied_name
```

### Step 3 — Fetch 16S reference sequences from NCBI

```r
genera <- sort(unique(tax_wide$genus[!is.na(tax_wide$genus) & tax_wide$genus != ""]))
message(sprintf("%d genera for 16S reference fetch.", length(genera)))

CACHE_DIR <- "~/My Drive/Rscripts/projects/TaxaID/ecosystem_docs/cache_16s_reference"
if (!dir.exists(CACHE_DIR)) dir.create(CACHE_DIR)

reference_df_16s <- fetch_ncbi_reference_sequences(
  taxa         = genera,
  barcode_term = "16S",
  rank_system  = c("family", "genus", "species"),
  cache_dir    = CACHE_DIR
)
saveRDS(reference_df_16s,
        "~/My Drive/Rscripts/projects/TaxaID/ecosystem_docs/morey_16S_reference_df.rds")
```

### Step 4 — Build the sequence matrix

```r
seq_matrix_16s <- build_sequence_matrix(
  reference_df_16s,
  rank_system        = c("family", "genus", "species"),
  filter_unnamed     = TRUE,
  max_seqs_per_taxon = 20L
)
saveRDS(seq_matrix_16s,
        "~/My Drive/Rscripts/projects/TaxaID/diagnostics/morey_16S_seq_matrix.rds")
message(sprintf("%d sequence pairs in the 16S matrix.", nrow(seq_matrix_16s)))
```

### Step 5 — Run the ROC sweep

Copy `diagnostics/score_floor_roc_sweep.R` to
`diagnostics/score_floor_roc_sweep_16S_morey.R` and change only:

```r
SM_PATH <- "~/My Drive/Rscripts/projects/TaxaID/diagnostics/morey_16S_seq_matrix.rds"
GITA_JV_THRESHOLDS <- c(species = 98, genus = 95, family = 90, order = 85)  # keep for comparison, not as a target
```

Run it. Report back:
- The Youden's-J-optimal threshold (`best_j`) for species-vs-congeneric
  discrimination
- TPR/FPR at that threshold, and at 97 (12S's species value) and 98 (COI's
  species value) for comparison
- Whether the curve even reaches a usable operating point, or whether — like
  several of Pappalardo et al. (2025)'s invertebrate phyla — 16S simply
  cannot separate species/congeners at any threshold for this species set
  (a real possible outcome, not a failure of the method)

### Step 6 — Update the design doc

Replace the 16S row in `ecosystem_docs/AQUARIUM_BENCHMARK_DESIGN.md`
Section 4a with the derived threshold(s), and note in the same row that
`species_16s` (Step 1's count) of 107 species actually had usable 16S
reference data — this number matters independently of the threshold value
and should be carried into the manuscript's reference-gap discussion
(Section 7, `TaxaLikely` H2/H3 framing).

## What to do if something breaks

- If `fetch_ncbi_reference_sequences()` returns very few sequences per
  genus, that's itself informative (reference-gap finding), not necessarily
  a bug — check `audit_barcode_coverage()` before assuming something's wrong.
- If the ROC curve shows no threshold cleanly separating within-species from
  congeneric pairs (flat or near-flat Youden's J across the whole grid),
  don't force a number — report that finding as-is. It would be a genuinely
  interesting result (16S may just not resolve species within some of these
  reef-fish genera), not a dead end.
- This whole task needs real NCBI network access and R with `TaxaTools`,
  `TaxaLikely`, `dplyr` installed — confirm those are available before
  starting rather than partway through.
