# greatlakes_old_approach_comparison_sample.R
#
# Derives diagnostics/greatlakes_old_approach_comparison_sample.csv -- a
# real, stratified sample of 120 accessions from the OLD (archived,
# taxon-list-scoped DECIPHER whole-set-alignment) approach's own final,
# calibrated, full 10,701-accession GreatLakes 12S audit, re-classified via
# the archived classify_reference_accessions(). Used by GreatLakes data/
# AuditNCBI.R (outside this monorepo) to compare the new BLAST-based
# evaluate_reference_accessions() directly against the old approach's own
# verdicts on real, already-computed data -- not a fresh re-derivation each
# run, this script's OUTPUT (the CSV) is what AuditNCBI.R actually reads.
#
# Re-run this script only if the sample itself needs to change (different
# strata, different n, a newer old-approach qc checkpoint). Requires the
# real GreatLakes2023BurnsHarbor_mincov_ncbi_audit_qc.rds checkpoint on
# disk (30MB, the OLD approach's own final real run, 2026-08-06) and the
# archived classify_reference_accessions() source (still present, not
# installed into the TaxaLikely package -- see TaxaLikely/CLAUDE.md's
# 2026-08-07 note on why that whole approach was superseded).

.libPaths(c(path.expand(Sys.getenv("R_LIBS_USER")), .libPaths()))
suppressPackageStartupMessages(library(dplyr))

ARCHIVE_DIR <- "/Users/lafferty/My Drive/Rscripts/projects/TaxaID/TaxaLikely/archive_decipher_reference_audit"
OLD_QC_PATH <- "/Users/lafferty/My Drive/Stats and Data/GreatLakes data/GreatLakes2023BurnsHarbor_mincov_ncbi_audit_qc.rds"
OUT_CSV     <- "/Users/lafferty/My Drive/Rscripts/projects/TaxaID/diagnostics/greatlakes_old_approach_comparison_sample.csv"

source(file.path(ARCHIVE_DIR, "R/audit_reference_database.R"))

qc <- readRDS(OLD_QC_PATH)
classification <- classify_reference_accessions(qc)

cat("-- Full real 10,701-accession OLD-approach classification --\n")
print(table(classification$error_type))
print(table(classification$hierarchy_flag, useNA = "ifany"))
print(table(classification$recommended_list))

set.seed(42)

# Group 1: real false-positive CANDIDATES -- clean by the self-vs-foreign
# score-gap check, but flagged incongruent by the taxon-list-scoped
# hierarchy check. This is the exact mechanism class the real Menidia
# false positives (the whole reason for the 2026-08-07 redesign) belong
# to -- most of these should read "congruent" under the new approach if
# the redesign is actually working, not just working on the one case
# already spot-checked by hand.
grp_fp <- classification |> filter(error_type == "clean", hierarchy_flag == "incongruent")
grp_fp_sample <- grp_fp |> slice_sample(n = min(60, nrow(grp_fp)))

# Group 2: real MISLABEL candidates -- flagged by the self-vs-foreign
# score-gap check (a different mechanism than hierarchy congruence
# entirely). This is this ecosystem's best real shot at a genuine
# species-identity mislabel positive control -- none is confirmed yet
# (reference_accession_ground_truth.csv's own note on AY850362, corrected
# 2026-08-07, explains why that one doesn't count).
grp_mis <- classification |> filter(error_type == "likely_mislabeled")
grp_mis_sample <- grp_mis |> slice_sample(n = min(30, nrow(grp_mis)))

# Group 3: control -- old approach said clean/fine on both checks. Tests
# whether the new approach introduces NEW false positives the old one
# didn't have, not just whether it fixes old ones.
grp_ctrl <- classification |> filter(recommended_list == "whitelist")
grp_ctrl_sample <- grp_ctrl |> slice_sample(n = min(30, nrow(grp_ctrl)))

sample_df <- bind_rows(
  grp_fp_sample   |> mutate(sample_group = "old_hierarchy_false_positive_candidate"),
  grp_mis_sample  |> mutate(sample_group = "old_likely_mislabeled"),
  grp_ctrl_sample |> mutate(sample_group = "old_whitelist_control")
) |> select(accession, listed_taxon, sample_group,
           old_error_type = error_type, old_hierarchy_flag = hierarchy_flag,
           old_recommended_list = recommended_list,
           old_frac_independent_below_min_congruent_rank = frac_independent_below_min_congruent_rank,
           old_integrity_gap = integrity_gap, old_max_foreign_match = max_foreign_match)

cat("\nTotal sampled:", nrow(sample_df), "\n")
print(table(sample_df$sample_group))

write.csv(sample_df, OUT_CSV, row.names = FALSE)
cat("Saved to:", OUT_CSV, "\n")
