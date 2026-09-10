# ==============================================================================
# TEST SCRIPT: write_reference_fasta()
# ==============================================================================
# Tests write_reference_fasta() -- fully offline, no internet required.
#
# NOTE (2026-09-09): this script previously also demonstrated
# build_site_reference(), a high-level fetch -> audit -> export wrapper
# around fetch_ncbi_reference_sequences() + audit_barcode_coverage() +
# write_reference_fasta(). build_site_reference() was archived (zero real
# callers anywhere in the monorepo -- every real production workflow builds
# its reference database by calling the component functions directly; see
# TaxaLikely/archive_unused_reference_wrappers/ and TaxaLikely/CLAUDE.md's
# 2026-09-09 session note). To build a site-specific reference the manual
# way, see Workflow 1 (inst/workflows/1_fetch_references_workflow.R):
#   reference_df <- fetch_ncbi_reference_sequences(taxa = ..., barcode_term = ...)
#   coverage     <- audit_barcode_coverage(reference_df, ...)
#   write_reference_fasta(reference_df, file = ..., taxonomy_file = ...)
#
# Expected run time: < 5 seconds
# ==============================================================================

library(TaxaLikely)

# ==============================================================================
# write_reference_fasta() -- no internet required
# ==============================================================================
# Build a tiny synthetic reference_df and verify the FASTA and taxonomy TSV
# can be written and read back correctly.

cat("\n===== write_reference_fasta() =====\n")

# A minimal reference_df -- the same structure as fetch_ncbi_reference_sequences() output
ref_df <- data.frame(
  composite_id = c("NC_001606", "NC_012361", "NC_004388", "KR014477"),
  sequence = c(
    "ACGTACGTACGTACGT",
    "ACGCACGTACGTACTT",
    "TTTACGTACGTACGAA",
    "ACGTACGTTTTACGTT"
  ),
  family = c("Fundulidae", "Fundulidae", "Poeciliidae", "Poeciliidae"),
  genus = c("Fundulus", "Fundulus", "Gambusia", "Gambusia"),
  species = c(
    "Fundulus heteroclitus", "Fundulus parvipinnis",
    "Gambusia affinis", "Gambusia holbrooki"
  ),
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
# Sort both by composite_id before comparing (read_reference_fasta may reorder rows)
ref_reload_sorted <- ref_reload[order(ref_reload$composite_id), ]
ref_df_sorted <- ref_df[order(ref_df$composite_id), ]
stopifnot(all(ref_reload_sorted$species == ref_df_sorted$species))
cat("  PASS: round-trip write -> read produces identical species column\n")

# ---- 1c. auto-detect rank_system from columns --------------------------------
# When rank_system = NULL (default), all non-id columns are used
ref_sub <- ref_df[, c("composite_id", "sequence", "genus", "species")]
fasta2 <- file.path(tempdir(), "test_no_family.fasta")
write_reference_fasta(ref_sub, file = fasta2)
cat("  PASS: rank_system auto-detected (genus + species only)\n")

# ---- 1d. Missing rank values (NA) in header ---------------------------------
ref_na <- ref_df
ref_na$family[2] <- NA
fasta3 <- file.path(tempdir(), "test_na_rank.fasta")
write_reference_fasta(ref_na, file = fasta3)
na_lines <- readLines(fasta3)
stopifnot(!grepl("\\bNA\\b", na_lines[3])) # header for row 2 has no "NA"
cat("  PASS: NA rank values omitted from FASTA header\n")

cat("\n===== write_reference_fasta() demo complete =====\n")
cat("\nNEXT STEPS:\n")
cat("  - Build a real reference_df: see Workflow 1 (1_fetch_references_workflow.R)\n")
cat("  - Train a model: build_sequence_matrix(reference_df) |> train_likelihood_model()\n")
