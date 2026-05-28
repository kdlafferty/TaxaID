# ==============================================================================
# TEST SCRIPT: Local Reference Library Functions
# ==============================================================================
# Tests write_reference_fasta() and build_site_reference().
#
# Structure:
#   PART 1 -- write_reference_fasta() [OFFLINE: no internet required]
#   PART 2 -- build_site_reference() [ONLINE: queries NCBI]
#
# Run PART 1 first to verify the write/read round-trip works before
# committing to an NCBI download. PART 2 uses a small taxa list and
# max_sequences = 60 (~2 min with NCBI rate limiting at 3 req/s).
#
# Expected run time:
#   Part 1: < 5 seconds
#   Part 2: 2-5 minutes (NCBI rate-limited; use ENTREZ_KEY to speed up)
# ==============================================================================

library(TaxaLikely)

# ==============================================================================
# PART 1: write_reference_fasta() -- no internet required
# ==============================================================================
# Build a tiny synthetic reference_df and verify the FASTA and taxonomy TSV
# can be written and read back correctly.

cat("\n===== PART 1: write_reference_fasta() =====\n")

# A minimal reference_df -- the same structure as fetch_reference_sequences() output
ref_df <- data.frame(
  composite_id = c("NC_001606", "NC_012361", "NC_004388", "KR014477"),
  sequence     = c(
    "ACGTACGTACGTACGT",
    "ACGCACGTACGTACTT",
    "TTTACGTACGTACGAA",
    "ACGTACGTTTTACGTT"
  ),
  family  = c("Fundulidae", "Fundulidae", "Poeciliidae", "Poeciliidae"),
  genus   = c("Fundulus", "Fundulus", "Gambusia", "Gambusia"),
  species = c("Fundulus heteroclitus", "Fundulus parvipinnis",
              "Gambusia affinis", "Gambusia holbrooki"),
  stringsAsFactors = FALSE
)

# ---- 1a. Write FASTA only ----------------------------------------------------
fasta_path <- file.path(tempdir(), "test_reference.fasta")
write_reference_fasta(ref_df, file = fasta_path)

lines <- readLines(fasta_path)
cat("FASTA output (first 4 lines):\n")
cat(head(lines, 4), sep = "\n")
stopifnot(startsWith(lines[1], ">NC_001606"))
stopifnot(grepl("Fundulus heteroclitus", lines[1]))
cat("  PASS: FASTA headers contain species names\n")

# ---- 1b. Write FASTA + taxonomy TSV (round-trip) ----------------------------
tsv_path <- file.path(tempdir(), "test_taxonomy.tsv")
write_reference_fasta(ref_df, file = fasta_path, taxonomy_file = tsv_path)

tsv_lines <- readLines(tsv_path)
cat("\nTaxonomy TSV (first 2 lines):\n")
cat(head(tsv_lines, 2), sep = "\n")

# Read back via read_reference_fasta()
ref_reload <- read_reference_fasta(
  fasta_path    = fasta_path,
  rank_system   = c("family", "genus", "species"),
  taxonomy_file = tsv_path
)
cat("\nReloaded reference_df:\n")
print(ref_reload[, c("composite_id", "family", "genus", "species")])

stopifnot(nrow(ref_reload) == nrow(ref_df))
stopifnot(all(ref_reload$species == ref_df$species))
cat("  PASS: round-trip write → read produces identical species column\n")

# ---- 1c. auto-detect rank_system from columns --------------------------------
# When rank_system = NULL (default), all non-id columns are used
ref_sub <- ref_df[, c("composite_id", "sequence", "genus", "species")]
fasta2   <- file.path(tempdir(), "test_no_family.fasta")
write_reference_fasta(ref_sub, file = fasta2)
cat("  PASS: rank_system auto-detected (genus + species only)\n")

# ---- 1d. Missing rank values (NA) in header ---------------------------------
ref_na <- ref_df
ref_na$family[2] <- NA
fasta3 <- file.path(tempdir(), "test_na_rank.fasta")
write_reference_fasta(ref_na, file = fasta3)
na_lines <- readLines(fasta3)
stopifnot(!grepl("\\bNA\\b", na_lines[3]))  # header for row 2 has no "NA"
cat("  PASS: NA rank values omitted from FASTA header\n")

cat("\n===== PART 1 complete =====\n")


# ==============================================================================
# PART 2: build_site_reference() -- REQUIRES INTERNET (NCBI)
# ==============================================================================
# Downloads sequences for 3 small fish species, audits barcode coverage, and
# exports a FASTA. Uses strict limits to minimise download volume.
#
# Expected sequences: ~10-30 per species = ~30-90 total.
# To speed up: set ENTREZ_KEY in ~/.Renviron (free NCBI API key; see
# https://www.ncbi.nlm.nih.gov/account/).

cat("\n===== PART 2: build_site_reference() =====\n")
cat("NOTE: This part queries NCBI and requires internet access.\n")
cat("      Expected time: 2-5 minutes without API key.\n\n")

# Three species with well-characterised MiFish 12S records.
# Species-level (not genus-level) taxa → smaller, faster downloads.
taxa <- c("Fundulus heteroclitus", "Gambusia affinis", "Lepomis macrochirus")
output_dir <- file.path(tempdir(), "site_reference_test")

lib <- build_site_reference(
  taxa          = taxa,
  barcode_term  = "MiFishU",
  rank_system   = c("family", "genus", "species"),
  output_dir    = output_dir,     # saves reference.fasta + taxonomy TSV
  flag_errors   = FALSE,          # skip DECIPHER step (fast)
  audit_coverage = TRUE,          # check NCBI for species with no barcodes
  max_sequences  = 60L,           # safety limit (each species gets ~max/3)
  max_per_species = 5L,
  max_date       = "2024/12/31"   # reproducible: fix GenBank state
)

# ---- Inspect results ---------------------------------------------------------
cat("\n--- reference_df ---\n")
print(head(lib$reference_df[, c("composite_id", "genus", "species")], 10))
cat(sprintf("Total sequences: %d\n", nrow(lib$reference_df)))
cat(sprintf("Unique species:  %d\n", length(unique(lib$reference_df$species))))

cat("\n--- Coverage census (per genus) ---\n")
if (nrow(lib$census) > 0)
  print(lib$census)

cat("\n--- Unreferenced species (no barcode in NCBI) ---\n")
if (length(lib$unreferenced) > 0) {
  cat(paste(" -", lib$unreferenced), sep = "\n")
} else {
  cat("  None (all described species have barcodes)\n")
}

# ---- Verify FASTA was written ------------------------------------------------
fasta_out <- file.path(output_dir, "reference.fasta")
tsv_out   <- file.path(output_dir, "reference_taxonomy.tsv")
stopifnot(file.exists(fasta_out))
stopifnot(file.exists(tsv_out))
cat(sprintf("\nFASTA written to: %s\n", fasta_out))
cat(sprintf("Taxonomy TSV:     %s\n", tsv_out))
cat("  PASS: output files exist\n")

# ---- Reload and verify round-trip -------------------------------------------
ref2 <- read_reference_fasta(
  fasta_path    = fasta_out,
  taxonomy_file = tsv_out,
  rank_system   = c("family", "genus", "species")
)
stopifnot(nrow(ref2) == nrow(lib$reference_df))
cat(sprintf("  PASS: reloaded %d sequences from FASTA\n", nrow(ref2)))

# ---- Sequence length distribution -------------------------------------------
lens <- nchar(lib$reference_df$sequence)
cat(sprintf("\nSequence lengths: min=%d, median=%d, max=%d bp\n",
            min(lens), as.integer(median(lens)), max(lens)))
hist(lens, main = "Sequence lengths (test reference)", xlab = "bp", col = "steelblue")

# ---- (Optional) train a model on the small reference -------------------------
# Uncomment to proceed to model training -- requires DECIPHER + Biostrings.
# ref_matrix <- build_sequence_matrix(lib$reference_df,
#                                      rank_system = c("family", "genus", "species"))
# model <- train_likelihood_model(ref_matrix)
# interpret_model(model)

cat("\n===== PART 2 complete =====\n")
cat("\nNEXT STEPS:\n")
cat("  - Expand taxa list to all genera expected at your site (from TaxaExpect)\n")
cat("  - Pass lib$unreferenced to TaxaAssign::suggest_unreferenced_species()\n")
cat("  - Train a model: build_sequence_matrix(lib$reference_df) |> train_likelihood_model()\n")
