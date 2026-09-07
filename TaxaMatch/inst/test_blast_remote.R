# ==============================================================================
# Field test: blast_sequences() remote BLAST pipeline
# Run interactively in RStudio. Requires internet + NCBI access.
# Fetches 5 known 12S MiFish sequences from NCBI, BLASTs them back, and checks
# that the expected species / accessions come back in the top hits.
# ==============================================================================
# Expected runtime: ~5-10 minutes (NCBI remote BLAST + taxonomy resolution)
# ==============================================================================

library(TaxaMatch)
library(TaxaLikely)
library(rentrez)

# Set your email and (optionally) NCBI API key
MY_EMAIL <- "lafferty@ucsb.edu"
MY_API_KEY <- Sys.getenv("ENTREZ_KEY", unset = NA_character_)
if (is.na(MY_API_KEY) || !nzchar(MY_API_KEY)) MY_API_KEY <- NULL

# ------------------------------------------------------------------------------
# Step 1: Fetch known sequences from NCBI by accession
# All are OQ84xxxx partial 12S sequences (~170bp MiFish amplicons) deposited
# together; confirmed short-amplicon format from prior NCBI fetch.
# Species verified from JVB3105-MiFishU-esv-data.csv (PtConception JV data).
# ------------------------------------------------------------------------------
TEST_ACCESSIONS <- c(
  "OQ846539", # Clinocottus recalvus (snubnose sculpin), 98.8%
  "OQ846195", # Rhacochilus toxotes (rubberlip surfperch), 98.8%
  "OQ846544", # Gibbonsia montereyensis (crevice kelpfish), 99.4%
  "OQ846550", # Oligocottus snyderi (tidewater sculpin), 98.8%
  "OQ846725" # Embiotoca caryi (black perch), 98.2%
)

message("Fetching test sequences from NCBI...")
fasta_text <- rentrez::entrez_fetch(
  db      = "nucleotide",
  id      = TEST_ACCESSIONS,
  rettype = "fasta"
)
cat(substr(fasta_text, 1, 500), "\n...\n")

# Parse FASTA into seq_df compatible with read_sequence_table()
parse_fasta_text <- function(txt) {
  lines <- strsplit(txt, "\n")[[1L]]
  header_idx <- which(startsWith(lines, ">"))
  seq_start <- header_idx + 1L
  seq_end <- c(header_idx[-1L] - 1L, length(lines))

  ids <- sub("^>([^ ]+).*", "\\1", lines[header_idx])
  seqs <- vapply(seq_along(header_idx), function(i) {
    paste(lines[seq_start[i]:seq_end[i]], collapse = "")
  }, character(1L))

  data.frame(
    asv_id = ids,
    sequence = seqs,
    abundance = 1L,
    stringsAsFactors = FALSE
  )
}

seq_df <- parse_fasta_text(fasta_text)
seq_df <- seq_df[nzchar(seq_df$sequence), ]
seq_df$length <- nchar(seq_df$sequence)

message(sprintf(
  "Test seq_df: %d sequences, lengths %d-%d bp",
  nrow(seq_df), min(seq_df$length), max(seq_df$length)
))
print(seq_df[, c("asv_id", "length")])

# ------------------------------------------------------------------------------
# Step 2: Filter sequences (optional for known sequences — just a sanity check)
# ------------------------------------------------------------------------------
seq_df_filtered <- filter_sequences(
  seq_df,
  barcode_term  = "12S",
  min_abundance = 1L # all are abundance = 1 (single reference sequences)
)

# ------------------------------------------------------------------------------
# Step 3: BLAST against NCBI nt
# ------------------------------------------------------------------------------
message("\nRunning remote BLAST (this takes 5-10 minutes)...")
t0 <- proc.time()[["elapsed"]]

blast_hits <- blast_sequences(
  seq_df_filtered,
  method = "remote",
  database = "nt",
  score_range = 2,
  max_hits = 10L,
  min_score = 95, # high threshold — these are known reference seqs
  min_query_coverage = 85,
  barcode_term = "12S",
  email = MY_EMAIL,
  ncbi_api_key = MY_API_KEY,
  resolve_taxonomy = TRUE,
  verbose = TRUE
)

message(sprintf("BLAST finished in %.0f seconds.", proc.time()[["elapsed"]] - t0))
message(sprintf(
  "Result: %d hits for %d queries", nrow(blast_hits),
  length(unique(blast_hits$observation_id))
))

# ------------------------------------------------------------------------------
# Step 4: Inspect results
# ------------------------------------------------------------------------------
cat("\n--- Top hit per query ---\n")
top_hits <- do.call(rbind, lapply(split(blast_hits, blast_hits$observation_id), function(x) {
  x[which.max(x$score), ]
}))
print(top_hits[, intersect(c("observation_id", "accession", "score", "species", "genus"), names(top_hits))])

cat("\n--- Are expected accessions present? ---\n")
for (acc in TEST_ACCESSIONS) {
  found <- any(grepl(sub("\\.[0-9]+$", "", acc), blast_hits$accession, fixed = FALSE))
  message(sprintf("  %s: %s", acc, if (found) "FOUND" else "NOT FOUND"))
}

# ------------------------------------------------------------------------------
# Step 5: Standardize and verify match object structure
# ------------------------------------------------------------------------------
match_obj <- standardize_match_data(
  data               = blast_hits,
  observation_id_col = "observation_id",
  score_col          = "score",
  rank_system        = c("family", "genus", "species")
)

stopifnot(all(c("observation_id", "score_original", "taxon_name", "taxon_name_rank") %in%
  names(match_obj)))
message("\nstandardize_match_data(): OK")
message(sprintf(
  "Final match object: %d rows, %d queries, %d taxa",
  nrow(match_obj), length(unique(match_obj$observation_id)),
  length(unique(match_obj$taxon_name))
))
print(head(match_obj[, c("observation_id", "score_original", "taxon_name", "taxon_name_rank")]))

# infer_exclude_predicted
exclude_pred <- TaxaLikely::infer_exclude_predicted(blast_hits)
message(sprintf("\ninfer_exclude_predicted: %s", exclude_pred))

message("\nField test COMPLETE.")
