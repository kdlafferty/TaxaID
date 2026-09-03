# local_corroboration_tiers_greatlakes.R -- 2026-09-03 offline analysis behind ecosystem_docs/REENTRY_PROMPT_local_corroboration_and_primer_stripped_screen.md.
# Tiers match-candidate accessions by FREE local corroboration (seq_matrix conspecific identity,
# overlap >= MINCOV, independent submission batch) and cross-tabs against the BLAST screen's
# reference_action. Zero NCBI cost. Run: MINCOV=0.8 Rscript local_corroboration_tiers_greatlakes.R

.libPaths(c(path.expand(Sys.getenv("R_LIBS_USER")), "~/Library/R/4.0/library", .libPaths()))
suppressPackageStartupMessages(library(dplyr))
GL <- "/Users/lafferty/My Drive/Stats and Data/GreatLakes data"; P <- "GreatLakes2023BurnsHarbor"
strip <- function(x) sub("[.][0-9]+$", "", x)
MINCOV <- as.numeric(Sys.getenv("MINCOV", "0.8"))
cat("MINCOV =", MINCOV, "\n")
m  <- readRDS(file.path(GL, paste0(P, "_match_obj.rds"))) |> filter(!is.na(accession)) |> mutate(acc = strip(accession))
rd <- readRDS(file.path(GL, paste0(P, "_reference_df.rds"))) |> mutate(acc = strip(composite_id))
sm <- readRDS(file.path(GL, paste0(P, "_seq_matrix.rds")))
ev <- TaxaMatch::score_reference_labels(readRDS(file.path(GL, paste0(P, "_goal2_screen_ref_eval_cache/reference_accession_cache.rds")))) |> mutate(acc = strip(accession))
win <- 5
best_sp <- m |> group_by(observation_id, species) |> slice_max(score_original, n=1, with_ties=TRUE) |> ungroup()
cand <- tibble(acc = unique(m$acc)) |> mutate(ever_species_best = acc %in% best_sp$acc)
meta <- rd |> transmute(acc, date = as.Date(create_date), prefix = sub("[0-9_]+$", "", acc), num = suppressWarnings(as.numeric(gsub("[^0-9]", "", acc))))
con <- sm |> filter(species.x == species.y, id_x != id_y, coverage >= MINCOV) |> transmute(acc = strip(id_x), partner = strip(id_y), p_match) |>
  left_join(meta, by = "acc") |> left_join(meta |> rename(partner = acc, pdate = date, pprefix = prefix, pnum = num), by = "partner") |>
  mutate(same_batch = (!is.na(date) & !is.na(pdate) & abs(as.numeric(date - pdate)) <= win) |
                      (!is.na(prefix) & !is.na(pprefix) & prefix == pprefix & !is.na(num) & !is.na(pnum) & abs(num - pnum) < win))
corr <- con |> group_by(acc) |> summarise(n_consp = n_distinct(partner), best_indep = suppressWarnings(max(p_match[!same_batch])), .groups="drop") |>
  mutate(best_indep = ifelse(is.finite(best_indep), best_indep, NA))
cand <- cand |> left_join(corr, by="acc") |> mutate(n_consp = coalesce(n_consp, 0L)) |> left_join(ev |> select(acc, hierarchy_flag, reference_action), by="acc")
t <- cand |> mutate(tier = case_when(!ever_species_best ~ "never drives", n_consp == 0 ~ "singleton", is.na(best_indep) ~ "same-batch only", best_indep >= 0.99 ~ "corroborated >=0.99", TRUE ~ "disagree"))
cat("BurnsHarbor match candidates:", nrow(cand), " screened rows:", nrow(ev), "\n"); print(table(t$tier))
print(table(t$tier, t$reference_action, useNA="ifany"))
cat("\nincongruent / non-keep rows:\n")
print(as.data.frame(t |> filter(hierarchy_flag %in% "incongruent" | reference_action %in% c("remove","inspect")) |> select(acc, tier, n_consp, best_indep, hierarchy_flag, reference_action)), row.names=FALSE)
