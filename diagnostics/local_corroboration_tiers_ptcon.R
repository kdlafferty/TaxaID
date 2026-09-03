# local_corroboration_tiers_ptcon.R -- 2026-09-03 offline analysis behind ecosystem_docs/REENTRY_PROMPT_local_corroboration_and_primer_stripped_screen.md.
# Tiers match-candidate accessions by FREE local corroboration (seq_matrix conspecific identity,
# overlap >= MINCOV, independent submission batch) and cross-tabs against the BLAST screen's
# reference_action. Zero NCBI cost.
#
# Reimplemented 2026-09-03 (same day, later) THROUGH the shipped functions:
#   TaxaMatch::corroborate_references_locally()  -- the tiers
#   TaxaMatch::match_driving_accessions()        -- "never drives a likelihood"
# so this script is a check that the package reproduces the hand-rolled analysis
# (never-drives 286 / singleton 554 / same-batch-only 23 / disagree 26 / corroborated 106
# at MINCOV 0.8, min_pident 0.99; ties may shift a few). Loads the worktree's TaxaMatch via
# devtools::load_all() so it runs against the branch, not the installed package.
#
# Run: MINCOV=0.8 Rscript local_corroboration_tiers_ptcon.R
#      (optionally TAXAMATCH_DIR=/path/to/TaxaID/TaxaMatch; defaults to ../TaxaMatch)

.libPaths(c(path.expand(Sys.getenv("R_LIBS_USER")), "~/Library/R/4.0/library", .libPaths()))
suppressPackageStartupMessages(library(dplyr))
script_dir <- tryCatch(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE)[1]))),
                       error = function(e) getwd())
taxamatch_dir <- Sys.getenv("TAXAMATCH_DIR", unset = file.path(script_dir, "..", "TaxaMatch"))
suppressMessages(devtools::load_all(taxamatch_dir, quiet = TRUE))
cat("TaxaMatch loaded from:", normalizePath(taxamatch_dir), "\n")

setwd("/Users/lafferty/My Drive/Rscripts/eDNA/PtConception")
strip  <- function(x) sub("[.][0-9]+$", "", x)
MINCOV <- as.numeric(Sys.getenv("MINCOV", "0.8"))
MINPID <- as.numeric(Sys.getenv("MINPID", "0.99"))
cat("MINCOV =", MINCOV, " MINPID =", MINPID, "\n")

m  <- readRDS("PtConMifishSchulte_match_obj.rds") |> filter(!is.na(accession)) |> mutate(acc = strip(accession))
rd <- readRDS("PtConMifishSchulte_reference_df.rds")
sm <- readRDS("PtConMifishSchulte_seq_matrix.rds")
ev <- score_reference_labels(readRDS("ptcon_ref_eval_cache/reference_accession_cache.rds")) |> mutate(acc = strip(accession))
win <- formals(evaluate_reference_accessions)$submission_window
cat("submission_window default:", win, "\n")

# ---- Through the package -------------------------------------------------------
driving <- strip(match_driving_accessions(m))
local   <- corroborate_references_locally(sm, rd, min_overlap = MINCOV, min_pident = MINPID,
                                          submission_window = win)

cand <- tibble(acc = unique(m$acc)) |>
  mutate(ever_species_best = acc %in% driving) |>
  left_join(local |> select(acc = accession, species, n_conspecific, n_independent_conspecific,
                            best_independent_pident, best_independent_partner, local_tier), by = "acc") |>
  left_join(ev |> select(acc, hierarchy_flag, reference_action, corroboration_source), by = "acc") |>
  mutate(local_tier = coalesce(local_tier, "singleton"),   # a candidate absent from reference_df/seq_matrix
         tier = ifelse(!ever_species_best, "never drives", local_tier))

tier_levels <- c("never drives", "singleton", "same_batch_only", "disagree", "corroborated")
cat(sprintf("\n=== tiers at overlap %.2f / identity %.2f (through corroborate_references_locally + match_driving_accessions) ===\n", MINCOV, MINPID))
print(table(factor(cand$tier, levels = tier_levels)))
cat("-- actions within each tier --\n")
print(table(factor(cand$tier, levels = tier_levels), cand$reference_action, useNA = "ifany"))

cat("\nAccessions ever species-best (match_driving_accessions):", length(driving), " of", nrow(cand), "\n")

cat("\nWhere the named cases land:\n")
print(as.data.frame(cand |>
  filter(acc %in% c("OP056918", "OQ846263", "KM057967", "KM057996", "MN883227", "KM057978",
                    "NC_066931", "LC092023", "OK172573", "MF409245")) |>
  select(acc, tier, n_conspecific, n_independent_conspecific, best_independent_pident,
         best_independent_partner, hierarchy_flag, reference_action)), row.names = FALSE)

# ---- The veto, on the real cache -------------------------------------------------
ev_local <- score_reference_labels(readRDS("ptcon_ref_eval_cache/reference_accession_cache.rds"),
                                   local_corroboration = local)
cat("\n=== reference_action before/after the local-corroboration veto (real PtCon cache) ===\n")
print(table(before = ev$reference_action, after = ev_local$reference_action))
cat("\nvetoed rows:\n")
print(as.data.frame(ev_local |> filter(!is.na(action_reason)) |>
  select(accession, listed_taxon, hierarchy_flag, reference_action, action_reason,
         corroboration_source, local_best_independent_pident)), row.names = FALSE)
cat("\ncorroboration_source:\n"); print(table(ev_local$corroboration_source, useNA = "ifany"))

# ---- What the skip would save ------------------------------------------------------
cat("\nOf the", nrow(cand), "match-candidate accessions,",
    sum(cand$tier == "corroborated"), "would be skipped (locally corroborated) and",
    sum(cand$tier == "never drives"), "never drive a likelihood; BLAST population would be",
    sum(!cand$tier %in% c("corroborated", "never drives")), "\n")
cat("\ncreate_date NA in reference_df:", sum(is.na(rd$create_date)), "of", nrow(rd), "\n")
