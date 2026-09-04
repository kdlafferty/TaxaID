# ==============================================================================
# Is evaluate_reference_accessions()'s verdict repeatable?
#
# WHY: OP056918 (Cryptacanthodes maculatus) read "incongruent" with no
# corroborating evidence anywhere on 2026-09-01 and "congruent" with four
# conspecific hits at 100% on 2026-09-02, under an IDENTICAL params_key. The
# corroborating records had been in GenBank since January, so elapsed time was
# not the cause, and the primer-trimming fix (2026-09-02) was verified not to
# change what is submitted to BLAST. That leaves NCBI's own hit selection.
#
# WHAT THIS DOES: evaluates the same 12 accessions THREE times back to back,
# each into its own fresh cache directory so every replicate is a real BLAST
# rather than a cache hit, then diffs (a) the verdicts and (b) the actual sets
# of hit accessions behind them.
#
# WHAT TO CONCLUDE:
#   verdicts identical, hit sets identical  -> BLAST is stable right now; the
#     09-01 -> 09-02 flip was something else (a one-off degraded response, or
#     a genuine nt index update between those dates).
#   verdicts identical, hit sets differ     -> the hit set churns but the
#     verdict is robust to it. Reassuring; max_hits could still bite in a
#     thinner clade.
#   verdicts differ                         -> the verdict is not reproducible
#     at a fixed params_key. That is a correctness problem for any removal
#     decision, and max_hits/top_n are the first knobs to look at.
#
# Run:  Rscript diagnostics/blast_verdict_repeatability_probe.R
# Cost: 3 x 12 accessions, one BLAST batch each. No persistent cache is
#       written outside the temp dirs, so this cannot pollute a real project.
# ==============================================================================

suppressMessages(library(TaxaMatch))

N_REPS <- 3L
OUT_RDS <- file.path("diagnostics", "blast_verdict_repeatability_probe.rds")

# The 12 accessions that read "incongruent" on the PtConception 12S screen --
# the population any removal decision is drawn from, and the one where thin
# coverage makes the top-N vote most sensitive to which hits come back.
ACCS <- c("OK172573", "MF409245", "KM057978", "OP056918", "NC_066931",
          "OQ846263", "KM057967", "OR582690", "KM057996", "LC672490",
          "AP012503", "NC_053053")

DIAG <- c("hierarchy_flag", "n_independent_top_matches",
          "frac_independent_below_min_congruent_rank", "best_hit_pident",
          "best_agreeing_pident", "best_disagreeing_pident",
          "congruent_evidence_exists_anywhere", "label_confidence",
          "reference_action")

reps <- vector("list", N_REPS)
for (k in seq_len(N_REPS)) {
  message(sprintf("\n=== replicate %d/%d ===", k, N_REPS))
  cdir <- file.path(tempdir(), paste0("repeatability_rep", k))
  dir.create(cdir, showWarnings = FALSE, recursive = TRUE)
  ev <- evaluate_reference_accessions(
    ACCS, cache_dir = cdir,
    ncbi_api_key = Sys.getenv("ENTREZ_KEY"), barcode_term = "MiFishU"
  )
  reps[[k]] <- list(
    eval  = as.data.frame(ev)[match(ACCS, ev$accession), , drop = FALSE],
    pairs = TaxaMatch:::.load_reference_pair_cache(cdir)
  )
}

# ---- (a) do the VERDICTS agree across replicates? ---------------------------
cat("\n\n================ VERDICT STABILITY ================\n")
unstable <- character(0)
for (a in ACCS) {
  rows <- do.call(rbind, lapply(reps, function(r) r$eval[r$eval$accession == a, DIAG]))
  n_distinct_rows <- nrow(unique(rows))
  if (n_distinct_rows > 1L) {
    unstable <- c(unstable, a)
    cat(sprintf("\n--- %s (%s): %d DISTINCT outcomes across %d replicates ---\n",
                a, reps[[1]]$eval$listed_taxon[reps[[1]]$eval$accession == a],
                n_distinct_rows, N_REPS))
    print(rows, row.names = FALSE, digits = 4)
  }
}
if (length(unstable) == 0L) {
  cat(sprintf("All %d accessions returned an IDENTICAL verdict and identical diagnostics in all %d replicates.\n",
              length(ACCS), N_REPS))
} else {
  cat(sprintf("\n%d of %d accessions are UNSTABLE: %s\n",
              length(unstable), length(ACCS), paste(unstable, collapse = ", ")))
}

# ---- (b) do the HIT SETS agree? ---------------------------------------------
# The verdict can be stable while the evidence under it churns; that is a
# materially different (and much less alarming) finding than an unstable
# verdict, so it is reported separately rather than folded in.
cat("\n\n================ HIT-SET STABILITY ================\n")
hitset <- function(r, a) sort(unique(r$pairs$id_y[r$pairs$id_x == a]))
summary_rows <- do.call(rbind, lapply(ACCS, function(a) {
  sets <- lapply(reps, hitset, a = a)
  common <- Reduce(intersect, sets)
  allids <- Reduce(union, sets)
  data.frame(
    accession = a,
    n_valid_partners = paste(vapply(sets, length, integer(1)), collapse = "/"),
    n_in_all_reps = length(common),
    n_in_some_reps = length(allids) - length(common),
    jaccard = if (length(allids) == 0L) NA_real_ else
      round(length(common) / length(allids), 3),
    stringsAsFactors = FALSE
  )
}))
print(summary_rows, row.names = FALSE)

churned <- summary_rows$accession[!is.na(summary_rows$jaccard) & summary_rows$jaccard < 1]
cat(sprintf("\n%d of %d accessions had a hit set that differed between replicates.\n",
            length(churned), length(ACCS)))
for (a in churned) {
  sets <- lapply(reps, hitset, a = a)
  cat(sprintf("  %s: only-in-some = %s\n", a,
              paste(setdiff(Reduce(union, sets), Reduce(intersect, sets)), collapse = ", ")))
}

saveRDS(reps, OUT_RDS)
cat(sprintf("\nSaved %d replicates to %s\n", N_REPS, OUT_RDS))
