# greatlakes_screening_approach_comparison_analysis.R
#
# Implements ecosystem_docs/REENTRY_PROMPT_screening_approach_comparison_audit.md
# (Q3 of the 2026-08-08 three-question thread): does TaxaLikely::
# flag_reference_errors() (the REAL "old" pre-training reference screen --
# still live in production via remove_flagged_references(), confirmed
# against TaxaLikely/CLAUDE.md before writing this, NOT the archived
# DECIPHER classify_reference_accessions()) flag more references than
# TaxaMatch::evaluate_reference_accessions() (the NEW BLAST-based screen)
# because it's genuinely more sensitive, or because of a real structural
# false-positive mode (no same-submission-batch independence filter)?
#
# Uses ONLY data already computed by prior real sessions -- no new BLAST/
# NCBI calls. The raw materials existed a day before this reentry doc was
# written (2026-08-07, vs. the doc's 2026-08-08 "design-only, not started"
# header, which was stale): the real, full 10,701-accession GreatLakes 12S
# audit (GreatLakes2023BurnsHarbor_mincov_ncbi_audit_qc.rds, produced by the
# ARCHIVED TaxaLikely::audit_reference_database()/classify_reference_
# accessions(), whose error_type column reproduces flag_reference_errors()'s
# own default rule exactly -- confirmed by reading R/audit_reference_
# database.R directly, not assumed); a 120-accession stratified sample of
# that population (diagnostics/greatlakes_old_approach_comparison_sample.R);
# and a real BLAST-based evaluate_reference_accessions() run against that
# sample plus a small ground-truth/Menidia/other set (132 accessions total,
# GreatLakes2023BurnsHarbor_blast_test_ref_eval_qc.rds).
#
# Re-run this script only if the underlying checkpoints change. All paths
# are outside this monorepo (My Drive/Stats and Data), not under git.

.libPaths(c(path.expand(Sys.getenv("R_LIBS_USER")), .libPaths()))
suppressPackageStartupMessages(library(dplyr))

GL <- "/Users/lafferty/My Drive/Stats and Data/GreatLakes data"
ARCHIVE_DIR <- "/Users/lafferty/My Drive/Rscripts/projects/TaxaID/TaxaLikely/archive_decipher_reference_audit"
source(file.path(ARCHIVE_DIR, "R/audit_reference_database.R"))

# ------------------------------------------------------------------------------
# 1. Population-level OLD-approach flag rate (real, full 10,701-accession DB,
#    no sampling). error_type is the flag_reference_errors()-equivalent
#    verdict; hierarchy_flag on this object is the ARCHIVED DECIPHER taxon-
#    list-scoped check (a different, no-longer-live mechanism), not used
#    below except where explicitly labelled. classify_reference_accessions()
#    is what actually COMPUTES error_type/hierarchy_flag from the raw qc
#    object -- the raw .rds alone doesn't carry them.
# ------------------------------------------------------------------------------
qc_raw  <- readRDS(file.path(GL, "GreatLakes2023BurnsHarbor_mincov_ncbi_audit_qc.rds"))
qc_full <- classify_reference_accessions(qc_raw)
attr(qc_full, "seq_matrix")   <- attr(qc_raw, "seq_matrix")
attr(qc_full, "reference_df") <- attr(qc_raw, "reference_df")

cat("=== FULL population (n=", nrow(qc_full), ") -- OLD approach (flag_reference_errors()-\n",
    "    equivalent) error_type distribution ===\n", sep = "")
print(table(qc_full$error_type, useNA = "ifany"))

old_flagged_full <- qc_full$error_type %in% c("likely_mislabeled", "unverified_singleton_high_match")
n_evaluable <- sum(qc_full$error_type != "excluded_from_alignment")
cat(sprintf(
  "\nOLD approach flagged: %d / %d of the nominal DB (%.2f%%); %d / %d of accessions it\n",
  sum(old_flagged_full), nrow(qc_full), 100 * mean(old_flagged_full),
  sum(old_flagged_full), n_evaluable
))
cat(sprintf("could actually evaluate (%.2f%%) -- %.1f%% of the nominal DB never entered\n",
            100 * sum(old_flagged_full) / n_evaluable, 100 * mean(qc_full$error_type == "excluded_from_alignment")))
cat("flag_reference_errors()'s own pairwise matrix at all (excluded_from_alignment).\n")

# ------------------------------------------------------------------------------
# 2. Old-vs-new overlap on the 132-accession evaluated sample. "Old" here is
#    the SAME error_type column as above (not the archived hierarchy_flag),
#    joined by accession -- the correct comparator per the reentry doc's own
#    confirmed reading. "New" is evaluate_reference_accessions()'s real
#    hierarchy_flag. insufficient_independent_evidence does not count as a
#    new-tool flag (not a positive mislabel claim), per the reentry doc.
# ------------------------------------------------------------------------------
qc_new <- readRDS(file.path(GL, "GreatLakes2023BurnsHarbor_blast_test_ref_eval_qc.rds"))

merged <- qc_new |>
  select(accession, listed_taxon, new_hierarchy_flag = hierarchy_flag,
         new_frac_indep = frac_independent_below_min_congruent_rank,
         best_agreeing_pident, best_disagreeing_pident,
         congruent_evidence_exists_anywhere, finest_common_rank) |>
  inner_join(
    qc_full |> select(accession, old_error_type = error_type,
                       old_hierarchy_flag = hierarchy_flag, integrity_gap,
                       n_self_neighbors, max_foreign_match),
    by = "accession"
  ) |>
  mutate(
    old_flagged = old_error_type %in% c("likely_mislabeled", "unverified_singleton_high_match"),
    new_flagged = new_hierarchy_flag == "incongruent"
  )

cat("\n=== On the n=", nrow(merged), " real evaluated/matched sample ===\n", sep = "")
cat(sprintf("old_flagged: %d (%.1f%%) | new_flagged: %d (%.1f%%)\n",
            sum(merged$old_flagged), 100 * mean(merged$old_flagged),
            sum(merged$new_flagged), 100 * mean(merged$new_flagged)))
print(table(old_flagged = merged$old_flagged, new_flagged = merged$new_flagged))

both     <- merged |> filter(old_flagged, new_flagged)
old_only <- merged |> filter(old_flagged, !new_flagged)
new_only <- merged |> filter(!old_flagged, new_flagged)
jaccard  <- nrow(both) / (nrow(both) + nrow(old_only) + nrow(new_only))
cat(sprintf("both=%d old_only=%d new_only=%d jaccard=%.3f\n",
            nrow(both), nrow(old_only), nrow(new_only), jaccard))

# ------------------------------------------------------------------------------
# 3. Same-submission-batch artifact test for OLD-ONLY flags -- the reentry
#    doc's own core hypothesis (the PV382872-class false positive
#    flag_reference_errors() has no defense against). Uses the EXACT
#    seq_matrix/reference_df that produced qc_full (retained as attributes
#    on qc_full itself), not a same-name-but-different-snapshot file
#    elsewhere in this directory -- verified before use (an earlier, wrong
#    attempt used GreatLakes2023BurnsHarbor_seq_matrix.rds, a much smaller
#    2,493-accession snapshot from an unrelated likelihood-training run,
#    and returned nothing for 21/28 accessions as a result).
# ------------------------------------------------------------------------------
seq_matrix   <- attr(qc_full, "seq_matrix")
reference_df <- attr(qc_full, "reference_df")

.build_lookup <- function(reference_df) {
  ref_ids <- reference_df$composite_id
  has_date <- "create_date" %in% names(reference_df)
  parsed_date <- if (has_date) suppressWarnings(as.Date(reference_df$create_date, format = "%Y/%m/%d")) else rep(as.Date(NA), length(ref_ids))
  is_simple <- grepl("^[A-Za-z]+[0-9]+$", ref_ids)
  data.frame(
    composite_id = ref_ids, acc_date = parsed_date,
    acc_prefix = ifelse(is_simple, sub("^([A-Za-z]+)[0-9]+$", "\\1", ref_ids), NA_character_),
    acc_num = suppressWarnings(ifelse(is_simple, as.numeric(sub("^[A-Za-z]+([0-9]+)$", "\\1", ref_ids)), NA_real_)),
    stringsAsFactors = FALSE
  ) |> distinct(composite_id, .keep_all = TRUE)
}
.same_batch <- function(x_date, x_prefix, x_num, y_date, y_prefix, y_num, submission_window = 30) {
  date_same <- !is.na(x_date) & !is.na(y_date) & abs(as.numeric(x_date - y_date)) <= submission_window
  acc_same  <- !is.na(x_prefix) & !is.na(y_prefix) & x_prefix == y_prefix &
    !is.na(x_num) & !is.na(y_num) & abs(x_num - y_num) < submission_window
  date_same | acc_same
}
.max_foreign_partner <- function(acc, seq_matrix) {
  rows <- seq_matrix |> filter(id_x == acc | id_y == acc)
  if (nrow(rows) == 0L) return(NULL)
  rows <- rows |> mutate(
    partner    = ifelse(id_x == acc, id_y, id_x),
    self_sp    = ifelse(id_x == acc, species.x, species.y),
    partner_sp = ifelse(id_x == acc, species.y, species.x)
  ) |> filter(partner_sp != self_sp)
  if (nrow(rows) == 0L) return(NULL)
  rows |> slice_max(p_match, n = 1, with_ties = FALSE)
}

lookup <- .build_lookup(reference_df)
batch_check <- function(accs) {
  bind_rows(lapply(accs, function(acc) {
    best <- .max_foreign_partner(acc, seq_matrix)
    if (is.null(best)) return(data.frame(accession = acc, partner = NA, same_batch = NA))
    x <- lookup |> filter(composite_id == acc); y <- lookup |> filter(composite_id == best$partner)
    sb <- if (nrow(x) == 1 && nrow(y) == 1)
      .same_batch(x$acc_date, x$acc_prefix, x$acc_num, y$acc_date, y$acc_prefix, y$acc_num) else NA
    data.frame(accession = acc, partner = best$partner, partner_species = best$partner_sp,
               p_match = best$p_match, same_batch = sb)
  }))
}

r_old_only <- batch_check(old_only$accession)
cat("\n=== OLD-ONLY (n=", nrow(old_only), "): same-submission-batch test on the accession that\n",
    "    drove each one's max_foreign_match (window=30 days/accession-numbers) ===\n", sep = "")
print(as.data.frame(r_old_only), row.names = FALSE)
cat(sprintf("\nSame-batch artifact: %d / %d (%.1f%%) of old-only flags.\n",
            sum(r_old_only$same_batch, na.rm = TRUE), nrow(r_old_only),
            100 * mean(r_old_only$same_batch, na.rm = TRUE)))

# ------------------------------------------------------------------------------
# 4. NEW-ONLY flags -- real mislabels old's narrower comparison population
#    structurally couldn't see, or just old's own rule correctly not firing?
# ------------------------------------------------------------------------------
cat("\n=== NEW-ONLY (n=", nrow(new_only), ") -- detail ===\n", sep = "")
print(as.data.frame(new_only |>
  left_join(qc_full |> select(accession, median_self_match, n_self_neighbors2 = n_self_neighbors),
            by = "accession")), row.names = FALSE)

# ------------------------------------------------------------------------------
# 5. Ground-truth cross-check (both tools) for the real, already-adjudicated
#    accessions present in this GreatLakes 12S database.
# ------------------------------------------------------------------------------
gt <- read.csv("/Users/lafferty/My Drive/Rscripts/projects/TaxaID/diagnostics/reference_accession_ground_truth.csv",
               stringsAsFactors = FALSE)
gt_combo <- gt |>
  select(accession, species, expected_verdict) |>
  left_join(qc_full |> select(accession, old_error_type = error_type), by = "accession") |>
  left_join(qc_new |> select(accession, new_hierarchy_flag = hierarchy_flag), by = "accession") |>
  filter(!is.na(old_error_type) | !is.na(new_hierarchy_flag))
cat("\n=== Ground-truth cross-check (accessions present in this GreatLakes DB) ===\n")
print(as.data.frame(gt_combo), row.names = FALSE)

saveRDS(list(qc_full = NULL, merged = merged, old_only_batch = r_old_only, new_only = new_only,
             gt_combo = gt_combo),
       file.path(GL, "GreatLakes2023BurnsHarbor_screening_approach_comparison_results.rds"))
cat("\nSaved results (excluding the large qc_full object) to GreatLakes2023BurnsHarbor_screening_approach_comparison_results.rds\n")
