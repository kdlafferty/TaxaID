# ==============================================================================
# test_infer_exclude_predicted.R
# Four scenarios covering the full return-value space of infer_exclude_predicted()
#
# Usage pattern:  !isFALSE(ep)
#   !isFALSE(TRUE) -> TRUE   (confirmed: no predicted sequences)
#   !isFALSE(FALSE) -> FALSE  (confirmed: predicted sequences present)
#   !isFALSE(NA)  -> TRUE   (unknown: safe default, treat as excluded)
#
# Note: ep %||% TRUE does NOT work — %||% replaces NULL, not NA.
# ==============================================================================

library(TaxaLikely)

# ==============================================================================
# Case 1: NCBI accessions, no predicted sequences
# Mimics a 12S MiFish reference (GenBank + curated RefSeq NR_).
# Expected: TRUE  (reference excludes predicted)
# ==============================================================================

match_ncbi <- data.frame(
  observation_id = paste0("ESV_", 1:6),
  accession      = c("AB123456.1", "KP891234.2", "NR_036856.1",
                     "MH213045.1", "NR_024642.1", "AB987654.1"),
  genus          = "Sebastes",
  species        = "Sebastes mystinus",
  score_original = 99,
  stringsAsFactors = FALSE
)

cat("\n--- Case 1: NCBI-only accessions (12S / GenBank + NR_) ---\n")
ep1 <- infer_exclude_predicted(match_ncbi)
cat("Result:", ep1, "  exclude_predicted =", !isFALSE(ep1), "\n")


# ==============================================================================
# Case 2: Mixed NCBI + JV vouchers
# Mimics an 18S reference with Jonah Ventures custom sequences alongside NCBI.
# Expected: TRUE  (NCBI subset has no XR_/XM_; custom accessions noted)
# ==============================================================================

match_mixed <- data.frame(
  observation_id = paste0("ESV_", 1:8),
  accession      = c("AB123456.1", "NR_036856.1", "KP891234.2",
                     "JV_voucher_00001", "JV_voucher_00002", "JV_voucher_00003",
                     "MH213045.1", "NR_024642.1"),
  genus          = "Haliotis",
  species        = c(rep("Haliotis rufescens", 4), rep("Haliotis fulgens", 4)),
  score_original = 98,
  stringsAsFactors = FALSE
)

cat("\n--- Case 2: Mixed NCBI + JV_voucher (18S with Jonah Ventures) ---\n")
ep2 <- infer_exclude_predicted(match_mixed)
cat("Result:", ep2, "  exclude_predicted =", !isFALSE(ep2), "\n")


# ==============================================================================
# Case 3: Predicted sequences present
# Mimics a reference built from the full NCBI database including XR_/XM_ records.
# Expected: FALSE  (reference includes predicted — do not exclude)
# ==============================================================================

match_predicted <- data.frame(
  observation_id = paste0("ESV_", 1:6),
  accession      = c("AB123456.1", "NR_036856.1", "XR_003654321.1",
                     "XM_012345678.2", "KP891234.2", "NM_001234567.1"),
  genus          = "Gadus",
  species        = "Gadus morhua",
  score_original = 97,
  stringsAsFactors = FALSE
)

cat("\n--- Case 3: Predicted (XR_/XM_) accessions present ---\n")
ep3 <- infer_exclude_predicted(match_predicted)
cat("Result:", ep3, "  exclude_predicted =", !isFALSE(ep3), "\n")


# ==============================================================================
# Case 4: No accession column (WilderLab / Mugu workflow)
# WilderLab match objects are built from ESV taxonomy tables and carry no
# accession column — the pipeline never goes through NCBI BLAST.
# infer_exclude_predicted() returns NA; !isFALSE(NA) gives TRUE (safe default).
# Expected: NA -> !isFALSE(NA) -> TRUE
# ==============================================================================

match_wilderlab <- data.frame(
  observation_id  = paste0("ESV_", 1:4),
  taxon_name      = "Sebastes mystinus",
  taxon_name_rank = "species",
  genus           = "Sebastes",
  species         = "Sebastes mystinus",
  score_original  = 100,
  stringsAsFactors = FALSE
)

cat("\n--- Case 4: No accession column (WilderLab/Mugu — no BLAST) ---\n")
ep4 <- infer_exclude_predicted(match_wilderlab)
cat("Result:", ep4, "  exclude_predicted =", !isFALSE(ep4),
    " <- NA coalesced to TRUE via !isFALSE()\n")


# ==============================================================================
# Summary
# ==============================================================================

cat(
  "\nCase | Scenario                    | Result | exclude_predicted\n",
  "-----|-----------------------------+--------+------------------\n",
  sprintf("  1  | NCBI only (GenBank/NR_)     | %-5s  | %s\n", ep1, !isFALSE(ep1)),
  sprintf("  2  | Mixed NCBI + JV vouchers    | %-5s  | %s\n", ep2, !isFALSE(ep2)),
  sprintf("  3  | Predicted XR_/XM_ present   | %-5s  | %s\n", ep3, !isFALSE(ep3)),
  sprintf("  4  | No accession column (Mugu)  | %-5s  | %s\n", ep4, !isFALSE(ep4)),
  sep = ""
)
