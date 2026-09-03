# local_corroboration_tiers_ptcon.R -- 2026-09-03 offline analysis behind ecosystem_docs/REENTRY_PROMPT_local_corroboration_and_primer_stripped_screen.md.
# Tiers match-candidate accessions by FREE local corroboration (seq_matrix conspecific identity,
# overlap >= MINCOV, independent submission batch) and cross-tabs against the BLAST screen's
# reference_action. Zero NCBI cost. Run: MINCOV=0.8 Rscript local_corroboration_tiers_ptcon.R

.libPaths(c(path.expand(Sys.getenv("R_LIBS_USER")), "~/Library/R/4.0/library", .libPaths()))
suppressPackageStartupMessages(library(dplyr))
setwd("/Users/lafferty/My Drive/Rscripts/eDNA/PtConception")
strip <- function(x) sub("[.][0-9]+$", "", x)
MINCOV <- as.numeric(Sys.getenv("MINCOV", "0.8"))
cat("MINCOV =", MINCOV, "\n")
m  <- readRDS("PtConMifishSchulte_match_obj.rds") |> filter(!is.na(accession)) |> mutate(acc = strip(accession))
rd <- readRDS("PtConMifishSchulte_reference_df.rds") |> mutate(acc = strip(composite_id))
sm <- readRDS("PtConMifishSchulte_seq_matrix.rds")
ev <- TaxaMatch::score_reference_labels(readRDS("ptcon_ref_eval_cache/reference_accession_cache.rds")) |> mutate(acc = strip(accession))
win <- formals(TaxaMatch::evaluate_reference_accessions)$submission_window; if (is.null(win)) win <- 30
cat("submission_window default:", win, "\n")

# which accessions ever drive a (observation, species) likelihood, or are top-1
best_sp <- m |> group_by(observation_id, species) |> slice_max(score_original, n=1, with_ties=TRUE) |> ungroup()
top1    <- m |> group_by(observation_id) |> slice_max(score_original, n=1, with_ties=TRUE) |> ungroup()
cand <- tibble(acc = unique(m$acc)) |>
  mutate(ever_species_best = acc %in% best_sp$acc, ever_top1 = acc %in% top1$acc)

# free internal corroboration from seq_matrix: conspecific ref-ref identity from an INDEPENDENT submission
meta <- rd |> transmute(acc, species, date = as.Date(create_date),
                        prefix = sub("[0-9_]+$", "", acc), num = suppressWarnings(as.numeric(gsub("[^0-9]", "", acc))))
con <- sm |> filter(species.x == species.y, id_x != id_y, coverage >= MINCOV) |> transmute(acc = strip(id_x), partner = strip(id_y), p_match) |>
  left_join(meta |> select(acc, date, prefix, num), by = "acc") |>
  left_join(meta |> select(partner = acc, pdate = date, pprefix = prefix, pnum = num), by = "partner") |>
  mutate(same_batch = (!is.na(date) & !is.na(pdate) & abs(as.numeric(date - pdate)) <= win) |
                      (!is.na(prefix) & !is.na(pprefix) & prefix == pprefix & !is.na(num) & !is.na(pnum) & abs(num - pnum) < win))
corr <- con |> group_by(acc) |> summarise(n_consp = n_distinct(partner),
                                          best_any = max(p_match), best_indep = suppressWarnings(max(p_match[!same_batch])), .groups="drop") |>
  mutate(best_indep = ifelse(is.finite(best_indep), best_indep, NA))
cand <- cand |> left_join(corr, by="acc") |> mutate(n_consp = coalesce(n_consp, 0L)) |>
  left_join(ev |> select(acc, hierarchy_flag, reference_action), by="acc")

for (thr in c(0.97, 0.98, 0.99)) {
  t <- cand |> mutate(tier = case_when(!ever_species_best ~ "never drives a likelihood",
                                        n_consp == 0 ~ "singleton in reference_df",
                                        is.na(best_indep) ~ "conspecifics only from same batch",
                                        best_indep >= thr ~ "independently corroborated (skip)",
                                        TRUE ~ "conspecifics disagree"))
  cat(sprintf("\n=== corroboration threshold %.2f ===\n", thr)); print(table(t$tier))
  cat("-- actions within each tier --\n"); print(table(t$tier, t$reference_action, useNA="ifany"))
}
t <- cand |> mutate(tier = case_when(!ever_species_best ~ "never drives", n_consp == 0 ~ "singleton", is.na(best_indep) ~ "same-batch only", best_indep >= 0.98 ~ "corroborated", TRUE ~ "disagree"))
cat("\nWhere the named cases land (thr 0.98):\n")
print(as.data.frame(t |> filter(acc %in% c("OP056918","OQ846263","KM057967","KM057996","MN883227","KM057978","NC_066931","LC092023","OK172573","MF409245")) |>
  select(acc, tier, ever_top1, n_consp, best_any, best_indep, hierarchy_flag, reference_action)), row.names=FALSE)
cat("\nAccessions ever top-1:", sum(cand$ever_top1), " ever species-best:", sum(cand$ever_species_best), " of", nrow(cand), "\n")

cat("\n=== partners of the named corroborated cases ===\n")
show <- con |> filter(acc %in% c("KM057967","KM057996","MN883227","KM057978","LC092023","OK172573")) |>
  left_join(rd |> select(partner = acc, pslen = slen, p_in_range = in_barcode_range), by="partner") |>
  mutate(partner_in_match = partner %in% m$acc) |>
  select(acc, date, partner, pdate, p_match, same_batch, pslen, p_in_range, partner_in_match) |> arrange(acc, desc(p_match))
print(as.data.frame(show), row.names=FALSE)
cat("\nIn the corroborated tier (thr 0.98), best independent partner identity is exactly 1.0 for",
    sum(t$tier=="corroborated" & t$best_indep >= 0.9999, na.rm=TRUE), "of", sum(t$tier=="corroborated"), "\n")
cat("Corroborated tier where the corroborating conspecific is itself a match candidate:",
    sum(t$tier=="corroborated" & t$acc %in% (con |> filter(!same_batch, p_match>=0.98, partner %in% m$acc) |> pull(acc))), "\n")
cat("\ncreate_date NA in reference_df:", sum(is.na(rd$create_date)), "of", nrow(rd), "\n")
