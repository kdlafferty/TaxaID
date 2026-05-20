# ==============================================================================
# WORKFLOW 1: BUILD A REFERENCE SEQUENCE DATABASE
# ==============================================================================
# Purpose: Assemble a reference_df of DNA sequences + taxonomy for model
#   building. This is the starting point for Workflows 2-4.
#
# Two paths:
#   A. Fetch sequences from NCBI (most users)
#   B. Load a local FASTA file (if you already have a reference database)
#
# Output: reference_df -- a data frame with columns:
#   composite_id  (accession or sequence ID)
#   sequence      (DNA string)
#   family, genus, species (or whatever rank_system you use)
#
# Next steps:
#   Workflow 2 (flag_errors_workflow.R)  -- find mislabeled references
#   Workflow 3 (train_model_workflow.R)  -- train a likelihood model
# ==============================================================================

library(TaxaLikely)

# ==============================================================================
# PATH A: FETCH FROM NCBI
# ==============================================================================
# Use this when you need sequences beyond what's in your match object.
# The match object only contains sequences that matched your queries --
# a biased subset. A good model needs the broader picture: within-species
# variation, between-species distances, and related taxa.
#
# fetch_reference_sequences() searches NCBI by taxon name + barcode marker.
# It does a count-first estimation before committing to any download, so
# you can see how large the search is before proceeding.
match_obj <- readRDS(file.choose())  # select your match data file (.rds)
match_obj$family|>unique()
# ---- A1. Define your search -------------------------------------------------
# taxa: character vector of taxon names at any rank.
#   Can be genera, families, orders, or even a class.
#   Each is searched separately; results are combined.
taxa <- match_obj$family|>unique()
taxa <- c("Cyprinidae","Percidae","Salmonidae","Centrarchidae","Catostomidae",
"Coregonidae","Ictaluridae","Cottidae","Esocidae","Gasterosteidae",
"Clupeidae","Petromyzontidae","Atherinopsidae","Umbridae","Lepisosteidae")

# barcode_term: the marker(s) to search for.
#   Use a vector for synonyms: c("COI", "Co1", "Coxi", "Cox1")
barcode_term <- "12S"

# rank_system: coarse to fine, matching the taxonomy columns you want.
rank_system <- c("family", "genus", "species")

# ---- A2. Estimate search size (automatic) -----------------------------------
# fetch_reference_sequences() always runs a count-first pass.
# If the total exceeds max_sequences (default 10,000), it stops and
# shows you the per-taxon counts so you can adjust.
#
# For very large taxa (e.g., an entire class like "Actinopterygii"),
# you may need to:
#   - Break into smaller groups (families or genera)
#   - Add date filtering (min_date / max_date)
#   - Increase max_sequences if you're prepared to wait

# ---- A3. Fetch ---------------------------------------------------------------
reference_df <- fetch_reference_sequences(
  taxa         = taxa,
  barcode_term = barcode_term,
  rank_system  = rank_system

  # Optional controls:
  # min_len = 100,        # override auto-detected length filter
  # max_len = 600,        # (NULL = use barcode_term defaults)
  # max_per_species = 5,  # stratified downsampling (default 5)
  # max_per_genus = NULL,  # genus-level cap (NULL = no cap)
  # max_sequences = 10000, # safety valve before downloading
  # blacklist_regex = "uncultured|environmental|predicted",
  # min_date = "2010/01/01",  # earliest publication date
  # max_date = "2024/12/31",  # latest publication date
  # cache_dir = "ncbi_cache",  # enable resumable downloads
  # ncbi_api_key = Sys.getenv("ENTREZ_KEY")  # faster rate limit
)

# Inspect the result
str(reference_df)
cat("Sequences:", nrow(reference_df), "\n")
cat("Unique species:", length(unique(reference_df$species)), "\n")
cat("Unique genera:", length(unique(reference_df$genus)), "\n")

# ---- A4. Explore sequence lengths (optional) ---------------------------------
# Understanding the length distribution can help you decide whether to
# tighten or loosen length filters. Short or very long sequences may
# indicate quality issues.
hist(nchar(reference_df$sequence),
     main = "Sequence length distribution",
     xlab = "Length (bp)", breaks = 30)

# ---- A5. Save for later use -------------------------------------------------
saveRDS(reference_df, "reference_df.rds")
message("Saved reference_df.rds")


# ==============================================================================
# PATH B: LOAD A LOCAL FASTA FILE
# ==============================================================================
# Use this when you already have a reference database on disk:
#   - A CRUX database
#   - A GenBank bulk download
#   - A custom curated FASTA from a collaborator
#
# You need two things:
#   1. A FASTA file (.fasta, .fa, .fna)
#   2. A taxonomy table (data frame or CSV) mapping accession -> taxonomy
#
# The taxonomy table must have a composite_id column matching the accession
# IDs in your FASTA headers, plus columns for each rank. Example:
#
#   composite_id,  family,       genus,       species
#   NC_001606,     Fundulidae,   Fundulus,    Fundulus heteroclitus
#   NC_012361,     Fundulidae,   Fundulus,    Fundulus parvipinnis
#   NC_004388,     Poeciliidae,  Gambusia,    Gambusia affinis
#
# FASTA header format: the first token after ">" is used as the ID.
# Version suffixes (.1, .2) are automatically stripped.
#   >NC_001606.1 Fundulus heteroclitus mitochondrion, complete genome
#   ATGCGATCGA...

# ---- B1. Prepare taxonomy table ---------------------------------------------
# Option 1: Read from CSV
# taxonomy <- read.csv("my_reference_taxonomy.csv", stringsAsFactors = FALSE)

# Option 2: Build from your match object (if accessions overlap)
# match_obj <- readRDS("path/to/match_obj.rds")
# taxonomy <- unique(match_obj[, c("accession", "family", "genus", "species")])
# names(taxonomy)[1] <- "composite_id"

# ---- B2. Read FASTA and join taxonomy ----------------------------------------
# reference_df <- read_reference_fasta(
#   fasta_path  = "my_references.fasta",
#   taxonomy    = taxonomy,
#   rank_system = c("family", "genus", "species")
# )
#
# str(reference_df)
# saveRDS(reference_df, "reference_df.rds")

message("\nWorkflow 1 complete.")
message("Next: Workflow 2 (flag reference errors) or Workflow 3 (train model)")
