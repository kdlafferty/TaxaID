# ==============================================================================
# TaxaMatch Workflow: FASTQ to Match Object
# ==============================================================================
# Complete pipeline from raw sequences to a standardized match object ready
# for TaxaLikely (likelihood conversion) or TaxaAssign (posterior computation).
#
# Prerequisite: DADA2 denoising (shown below but not executed by TaxaMatch).
#
# Steps:
#   0. DADA2 denoising (prerequisite — produces sequence table)
#   1. Read sequence table into TaxaMatch format
#   2. Filter sequences by length and abundance
#   3. BLAST against NCBI (remote or local)
#   4. Standardize match data
#   5. Filter redundant hypotheses
#   6. Save match object for downstream use
# ==============================================================================

library(TaxaMatch)
library(TaxaLikely)   # for infer_exclude_predicted() in Step 3b
BiocManager::install("dada2")
library(dada2)        # only needed for Step 0 (DADA2 denoising)
# ==============================================================================
# STEP 0 — DADA2 DENOISING (prerequisite)
# ==============================================================================
# This step runs OUTSIDE TaxaMatch. The output is a sequence table (matrix)
# that TaxaMatch ingests. Shown here for completeness.
#
# library(dada2)
#
# # 0a. Set paths to your FASTQ files
fastq_path <- file.choose()  # select any file in your FASTQ directory, then extract the directory
fastq_path <- dirname(fastq_path)
fwd_files  <- sort(list.files(fastq_path, pattern = "_R1_001.fastq", full.names = TRUE))
rev_files  <- sort(list.files(fastq_path, pattern = "_R2_001.fastq", full.names = TRUE))

fwd_files<-fwd_files[1:1]
rev_files<-rev_files[1:1]
#
#
#
# # 0b. Inspect quality profiles (set truncation lengths from these plots)
plotQualityProfile(fwd_files[1:1])
plotQualityProfile(rev_files[1:1])
#
# # 0c. Filter and trim
filt_path <- file.path(fastq_path, "filtered")
filt_out <- filterAndTrim(
fwd_files, file.path(filt_path, basename(fwd_files)),
rev_files, file.path(filt_path, basename(rev_files)),
truncLen = c(200, 180),  # adjust based on quality profiles
maxN = 0, maxEE = c(2, 2), truncQ = 2, rm.phix = TRUE,
compress = TRUE, multithread = TRUE
)
filt_out
#
# # 0d. Learn error rates
err_fwd <- learnErrors(file.path(filt_path, basename(fwd_files)), multithread = TRUE)
err_rev <- learnErrors(file.path(filt_path, basename(rev_files)), multithread = TRUE)
#
# # 0e. Denoise
dada_fwd <- dada(file.path(filt_path, basename(fwd_files)), err = err_fwd, multithread = TRUE)
dada_rev <- dada(file.path(filt_path, basename(rev_files)), err = err_rev, multithread = TRUE)
#
# # 0f. Merge paired reads
merged <- mergePairs(dada_fwd, file.path(filt_path, basename(fwd_files)),
                      dada_rev, file.path(filt_path, basename(rev_files)))
#
# # 0g. Build sequence table
seqtab <- makeSequenceTable(merged)
#
# # 0h. Remove chimeras
seqtab_nochim <- removeBimeraDenovo(seqtab, method = "consensus", multithread = TRUE)
#
# # Save for TaxaMatch
saveRDS(seqtab_nochim, "seqtab_nochim.rds")


# ==============================================================================
# STEP 1 — READ SEQUENCE TABLE
# ==============================================================================
library(TaxaMatch)
# Option A: From a DADA2 sequence table (most common for eDNA)
seqtab <- readRDS("seqtab_nochim.rds")
seq_df <- read_sequence_table(seqtab)

# Option B: From a FASTA file with semicolon-delimited taxonomy headers
#   Format: accession;kingdom;phylum;class;order;family;genus;species
# seq_df <- read_sequence_table("my_sequences.fasta", header_format = "semicolon")

# Option C: From a FASTA file with a separate taxonomy table
# tax_table <- read.csv("taxonomy.csv")  # must have 'accession' or 'sequence' column
# seq_df <- read_sequence_table("my_sequences.fasta", taxonomy = tax_table)

# Inspect
message(sprintf("%d unique ASVs, lengths %d-%d bp, abundances %d-%d",
                nrow(seq_df),
                min(seq_df$length), max(seq_df$length),
                min(seq_df$abundance), max(seq_df$abundance)))

# Check the length distribution — useful for setting filter bounds
table(cut(seq_df$length, breaks = seq(0, max(seq_df$length) + 50, by = 10)))


# ==============================================================================
# STEP 2 — FILTER SEQUENCES
# ==============================================================================
# Remove sequences that are:
#   - Too short or too long for the marker (likely non-target amplicons)
#   - Too rare (likely PCR/sequencing errors)

# Option A: Auto-detect length bounds from barcode marker
filtered_df <- filter_sequences(
  seq_df,
  barcode_term  = "MiFish",  # auto-resolves to 100-600 bp for 12S MiFish
  min_abundance = 100           # remove singletons
)

# Option B: Specify bounds manually
# filtered_df <- filter_sequences(
#   seq_df,
#   min_length    = 160,
#   max_length    = 190,
#   min_abundance = 5
# )

message(sprintf("%d ASVs retained after filtering", nrow(filtered_df)))


# ==============================================================================
# STEP 3 — BLAST SEQUENCES
# ==============================================================================
# Query NCBI for top matches. The score window algorithm keeps all hits within
# score_range % of each query's top hit, rather than a flat top-N.

# --- Option A: Remote NCBI BLAST (no local database needed) -------------------
# Good for < 500 ASVs. Requires internet. Can take minutes to hours.


blast_hits <- blast_sequences(
  filtered_df,
  method = "remote", database = "nt",
  score_range = 2, max_hits = 20, min_score = 70,
  min_query_coverage = 85, barcode_term = NULL,
  email = "lafferty@ucsb.edu", resolve_taxonomy = TRUE
)

# --- Option B: Local BLAST (requires BLAST+ and a local database) -------------
# Much faster for large datasets. See below for setup instructions.
#
# blast_hits <- blast_sequences(
#   filtered_df,
#   method              = "local",
#   database            = "/path/to/blast_db/nt",
#   score_range         = 2,
#   max_hits            = 20,
#   min_score           = 70,
#   min_query_coverage  = 80,
#   barcode_term        = "MiFish",
#   resolve_taxonomy    = TRUE
# )

message(sprintf(
  "%d hits for %d queries (%d unique species)",
  nrow(blast_hits),
  length(unique(blast_hits$observation_id)),
  length(unique(stats::na.omit(blast_hits$species)))
))


# ==============================================================================
# STEP 3b — INFER EXCLUDE_PREDICTED (for audit_barcode_coverage downstream)
# ==============================================================================
# Inspects accession column to determine whether the BLAST reference excluded
# computationally predicted (XR_/XM_) sequences. Pass to audit_barcode_coverage()
# later (exclude_predicted = exclude_pred %||% TRUE).
# Returns TRUE (no XR_/XM_ found), FALSE (predicted seqs present), or NA (all
# custom/non-NCBI accessions — cannot determine).
exclude_pred <- TaxaLikely::infer_exclude_predicted(blast_hits)
message(sprintf("infer_exclude_predicted: %s",
                if (is.na(exclude_pred)) "NA (cannot determine from accessions)"
                else if (exclude_pred) "TRUE (no predicted sequences found)"
                else "FALSE (predicted sequences present in reference)"))


# ==============================================================================
# STEP 4 — STANDARDIZE MATCH DATA
# ==============================================================================
# Convert BLAST output to the canonical TaxaMatch format expected by TaxaLikely.

match_obj <- standardize_match_data(
  data           = blast_hits,
  observation_id_col  = "observation_id",
  score_col      = "score",
  rank_system = c("family", "genus", "species")
)


# ==============================================================================
# STEP 5 — FILTER REDUNDANT HYPOTHESES
# ==============================================================================
# Remove coarser-rank rows superseded by finer-rank rows within the same lineage.
# E.g., if ASV_1 has both "Gobius niger" (species) and "Gobius" (genus), the
# genus-level row is redundant.

match_obj <- filter_redundant_hypotheses(match_obj)

message(sprintf("Final match object: %d rows, %d queries, %d taxa",
                nrow(match_obj),
                length(unique(match_obj$observation_id)),
                length(unique(match_obj$taxon_name))))


# ==============================================================================
# STEP 6 — SAVE FOR DOWNSTREAM USE
# ==============================================================================
# The match object is now ready for:
#   - TaxaLikely: train_likelihood_model() + evaluate_likelihoods()
#   - TaxaAssign: assign_taxa_llm() or compute_posterior()

saveRDS(match_obj, "match_obj.rds")
match_obj$taxon_name|>unique()

# ==============================================================================
# LOCAL BLAST SETUP INSTRUCTIONS
# ==============================================================================
# To use method = "local", you need:
#
# 1. Install BLAST+ command-line tools:
#    - macOS:  brew install blast
#    - Ubuntu: sudo apt install ncbi-blast+
#    - Windows: download from https://ftp.ncbi.nlm.nih.gov/blast/executables/blast+/LATEST/
#
# 2. Download a reference database. Options:
#
#    a) The full NCBI nt database (~100 GB compressed):
#       update_blastdb.pl --decompress nt
#
#    b) A curated marker-specific database (recommended for eDNA):
#       - MitoFish: https://mitofish.aori.u-tokyo.ac.jp/download/
#       - MIDORI2: https://www.reference-midori.info/download.php
#       - CRUX: generated by the CRUX pipeline (Anacapa toolkit)
#
#    c) Build your own from FASTA:
#       makeblastdb -in my_references.fasta -dbtype nucl -out my_db
#
# 3. Install rBLAST (Bioconductor):
#    BiocManager::install("rBLAST")
#
# 4. Point blast_sequences() to your database:
#    blast_sequences(seq_df, method = "local", database = "/path/to/my_db")
