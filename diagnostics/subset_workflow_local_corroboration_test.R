# subset_workflow_local_corroboration_test.R
#
# Abbreviated PtConception-12S screen workflow on a hand-picked subset, to
# confirm the local-corroboration branch (2026-09-03) delivers what the spec
# promises BEFORE the real workflows are rewired. Live NCBI: roughly 5-15
# short queries in the first pass and 1 in the second. Uses its own fresh
# cache directories under diagnostics/ -- the production
# ptcon_ref_eval_cache is never read or written.
#
# Run in RStudio AFTER installing TaxaMatch from the local-corroboration
# branch (the script refuses to run against an old install):
#   source(".../diagnostics/subset_workflow_local_corroboration_test.R")
#
# What each target accession is here to test (real PtCon 12S cases):
#   KM057996  Zaniolepis frenata     locally corroborated by OQ846041 (100%, 97% overlap)
#                                    -> must be SKIPPED, flag "locally_corroborated", keep.
#                                    Second pass forces a BLAST under the amplicon query:
#                                    must now read congruent with OQ846041 as a partner.
#   KM057978  Oxylebius pictus       corroborated by LC104539/OQ846312 -> skipped
#   OK172573  Scorpaenichthys marm.  corroborated (4 partners >= 99.4%) -> skipped
#   KM057967  Jordania zonope        singleton (LC126244 overlaps only 5.6%) -> BLASTed
#   OQ846263  Rathbunella hypoplecta singleton -> BLASTed
#   OP056918  Cryptacanthodes mac.   singleton; flipped remove->congruent with an nt rebuild
#   MN883227  Fundulus luciae        the known true mislabel; local partners at 98.1%
#                                    -> tier "disagree" at 0.99 -> BLASTed, never skipped

.libPaths(c(path.expand(Sys.getenv("R_LIBS_USER")), "~/Library/R/4.0/library", .libPaths()))
library(TaxaMatch)
suppressPackageStartupMessages(library(dplyr))

if (!"query_span" %in% names(formals(TaxaMatch::evaluate_reference_accessions)))
  stop("Installed TaxaMatch predates the local-corroboration branch: install it first ",
       "(see the session's 'To apply these changes' block), restart R, library(TaxaMatch).",
       call. = FALSE)
message("TaxaMatch build: ", packageDescription("TaxaMatch")$Built)

if (!nzchar(Sys.getenv("NCBI_EMAIL", unset = ""))) Sys.setenv(NCBI_EMAIL = "klafferty@usgs.gov")
NCBI_KEY <- Sys.getenv("ENTREZ_KEY", unset = "")

HERE  <- "/Users/lafferty/My Drive/Rscripts/projects/TaxaID/diagnostics"
PTCON <- "/Users/lafferty/My Drive/Rscripts/eDNA/PtConception"
strip <- function(x) sub("[.][0-9]+$", "", x)

targets <- c("KM057996", "KM057978", "OK172573", "KM057967", "OQ846263", "OP056918", "MN883227")
expect_skipped <- c("KM057996", "KM057978", "OK172573")
expect_blasted <- setdiff(targets, expect_skipped)

# ------------------------------------------------------------------------------
# 1. Real inputs (checkpoints the real workflow already wrote)
# ------------------------------------------------------------------------------
match_obj    <- readRDS(file.path(PTCON, "PtConMifishSchulte_match_obj.rds"))
reference_df <- readRDS(file.path(PTCON, "PtConMifishSchulte_reference_df.rds"))
seq_matrix   <- readRDS(file.path(PTCON, "PtConMifishSchulte_seq_matrix.rds"))

# One real observation per target: the observation where the target is the
# top-scoring accession. Keep that observation's top-3 species-best rows so a
# few non-target candidates ride along (as they would in the real workflow).
m <- match_obj |> filter(!is.na(accession)) |> mutate(acc = strip(accession))
species_best <- m |> group_by(observation_id, species) |>
  slice_max(score_original, n = 1, with_ties = FALSE) |> ungroup()
top1 <- m |> group_by(observation_id) |> slice_max(score_original, n = 1, with_ties = FALSE) |> ungroup()
chosen_obs <- vapply(targets, function(a) {
  o <- top1$observation_id[top1$acc == a]
  if (length(o) == 0L) o <- species_best$observation_id[species_best$acc == a]
  if (length(o) == 0L) NA_character_ else o[1L]
}, character(1))
if (anyNA(chosen_obs)) stop("No observation found for: ", paste(targets[is.na(chosen_obs)], collapse = ", "))
match_sub <- species_best |> filter(observation_id %in% chosen_obs) |>
  group_by(observation_id) |> slice_max(score_original, n = 3, with_ties = FALSE) |> ungroup() |>
  select(-acc)
message(sprintf("Subset: %d observations, %d rows, %d distinct accessions.",
                n_distinct(match_sub$observation_id), nrow(match_sub), n_distinct(match_sub$accession)))

# ------------------------------------------------------------------------------
# 2. Free step: local corroboration + which accessions actually drive a likelihood
# ------------------------------------------------------------------------------
local_corr <- corroborate_references_locally(seq_matrix, reference_df)   # full reference set, no NCBI
to_screen  <- match_driving_accessions(match_sub)
# A match candidate absent from the reference set (BLAST found it; the genus
# fetch did not) has no local row at all -- it must be BLASTed, never skipped.
tiers <- tibble(accession = strip(to_screen)) |>
  left_join(local_corr |> select(accession, local_tier, n_independent_conspecific,
                                 best_independent_pident, best_independent_partner), by = "accession") |>
  mutate(local_tier = coalesce(local_tier, "not_in_local_reference_set"))
cat("\n=== Local tiers of the accessions to screen ===\n"); print(as.data.frame(tiers), row.names = FALSE)
tier_of <- setNames(tiers$local_tier, tiers$accession)
check1 <- all(tier_of[expect_skipped] %in% "corroborated") && !any(tier_of[expect_blasted] %in% "corroborated")
cat(sprintf("\nCHECK 1 (tiers as expected: %s corroborated, the rest not): %s\n",
            paste(expect_skipped, collapse = "/"), if (check1) "PASS" else "FAIL"))

# ------------------------------------------------------------------------------
# 3. The screen, exactly as a rewired workflow would call it (fresh cache)
# ------------------------------------------------------------------------------
cache1 <- file.path(HERE, "cache_subset_workflow_test")
if (dir.exists(cache1)) unlink(cache1, recursive = TRUE)
t0 <- proc.time()[["elapsed"]]
match_eval <- evaluate_reference_accessions(
  to_screen,
  cache_dir           = cache1,
  ncbi_api_key        = NCBI_KEY,
  barcode_term        = "MiFishU",            # query_span = "amplicon" is the new default
  local_corroboration = local_corr
)
message(sprintf("Screen took %.0f s.", proc.time()[["elapsed"]] - t0))
rs <- attr(match_eval, "run_summary")
cat("\n=== run_summary ===\n"); print(rs)
match_eval <- score_reference_labels(match_eval, local_corroboration = local_corr, overwrite = TRUE)

show_cols <- intersect(c("accession", "listed_taxon", "hierarchy_flag", "reference_action",
                         "corroboration_source", "action_reason", "n_independent_top_matches",
                         "best_agreeing_pident", "best_disagreeing_pident", "best_disagreeing_taxon",
                         "local_best_independent_pident"), names(match_eval))
ev <- match_eval |> mutate(acc = strip(accession)) |> arrange(match(acc, targets))
cat("\n=== Verdicts, targets first ===\n")
print(as.data.frame(ev |> filter(acc %in% targets) |> select(all_of(show_cols))), row.names = FALSE)
cat("\n--- the non-target accessions that rode along ---\n")
print(as.data.frame(ev |> filter(!acc %in% targets) |> select(all_of(show_cols))), row.names = FALSE)

sk <- ev |> filter(acc %in% expect_skipped)
check2 <- nrow(sk) == length(expect_skipped) && all(sk$hierarchy_flag == "locally_corroborated") &&
  all(sk$reference_action == "keep") && all(sk$corroboration_source == "local")
cat(sprintf("\nCHECK 2 (corroborated targets skipped: flag locally_corroborated / keep / source local): %s\n",
            if (check2) "PASS" else "FAIL"))
bl <- ev |> filter(acc %in% expect_blasted)
check3 <- all(bl$hierarchy_flag != "locally_corroborated")
cat(sprintf("CHECK 3 (singleton/disagree targets were BLASTed, not skipped): %s\n", if (check3) "PASS" else "FAIL"))
cat(sprintf("REPORT  Fundulus MN883227 verdict under the amplicon query: %s / %s (was insufficient / keep)\n",
            bl$hierarchy_flag[bl$acc == "MN883227"], bl$reference_action[bl$acc == "MN883227"]))
cat(sprintf("REPORT  Jordania KM057967: %s / %s ; Rathbunella OQ846263: %s / %s ; Cryptacanthodes OP056918: %s / %s\n",
            bl$hierarchy_flag[bl$acc == "KM057967"], bl$reference_action[bl$acc == "KM057967"],
            bl$hierarchy_flag[bl$acc == "OQ846263"], bl$reference_action[bl$acc == "OQ846263"],
            bl$hierarchy_flag[bl$acc == "OP056918"], bl$reference_action[bl$acc == "OP056918"]))
cat("        (these three were remove/remove/remove-then-congruent under the old query; a change here is\n",
    "        the amplicon query finding short-deposit evidence, or an nt rebuild -- both are fine)\n")

# ------------------------------------------------------------------------------
# 4. Downstream consumers: removal must never touch a corroborated accession;
#    the flag columns must travel onto the match object.
# ------------------------------------------------------------------------------
removed <- remove_incongruent_references(match_sub, match_eval)
gone <- setdiff(unique(strip(match_sub$accession)), unique(strip(removed$accession)))
cat("\nAccessions removed from the subset match object:", if (length(gone)) paste(gone, collapse = ", ") else "(none)", "\n")
check4 <- !"KM057996" %in% gone && !any(expect_skipped %in% gone)
cat(sprintf("CHECK 4 (no locally-corroborated accession removed): %s\n", if (check4) "PASS" else "FAIL"))
flagged <- flag_incongruent_references(match_sub, match_eval)
check5 <- all(c("hierarchy_flag", "reference_action", "corroboration_source") %in% names(flagged))
cat(sprintf("CHECK 5 (flag columns travel onto the match object): %s\n", if (check5) "PASS" else "FAIL"))

# ------------------------------------------------------------------------------
# 5. Second pass: force KM057996 through BLAST under the new amplicon query.
#    This is the direct test of the defect fix (Run C of the probe, but now
#    through the screen itself, verdict and all).
# ------------------------------------------------------------------------------
cache2 <- file.path(HERE, "cache_subset_workflow_test_forced")
if (dir.exists(cache2)) unlink(cache2, recursive = TRUE)
forced <- evaluate_reference_accessions(
  "KM057996", cache_dir = cache2, ncbi_api_key = NCBI_KEY, barcode_term = "MiFishU",
  local_corroboration = local_corr, skip_locally_corroborated = FALSE
)
forced <- score_reference_labels(forced, local_corroboration = local_corr, overwrite = TRUE)
cat("\n=== KM057996 forced through BLAST (amplicon query) ===\n")
print(as.data.frame(forced |> select(all_of(intersect(show_cols, names(forced))))), row.names = FALSE)
pairs <- readRDS(file.path(cache2, "reference_pair_cache.rds")) |> arrange(desc(p_match))
cat("\n--- partners the verdict rests on ---\n")
print(as.data.frame(pairs |> select(id_x, id_y, p_match, pair_finest_common_rank, species_y) |> head(15)), row.names = FALSE)
check6 <- forced$hierarchy_flag[1] == "congruent" && "OQ846041" %in% strip(pairs$id_y)
cat(sprintf("\nCHECK 6 (KM057996 congruent under the amplicon query, OQ846041 among partners): %s\n",
            if (check6) "PASS" else "FAIL"))
cat("        Expect Zaniolepis latipinnis (OQ846089/LC091896) at 100% too: marker cannot separate the pair.\n")

# ------------------------------------------------------------------------------
# 6. Summary + save
# ------------------------------------------------------------------------------
checks <- c(tiers = check1, skipped = check2, blasted = check3, removal = check4, columns = check5, forced_congruent = check6)
cat("\n=== SUMMARY ===\n"); print(checks)
cat(if (all(checks)) "ALL CHECKS PASS -- safe to rewire the workflows.\n" else "At least one check FAILED -- paste this output back before rewiring.\n")
saveRDS(list(match_sub = match_sub, tiers = tiers, run_summary = rs, match_eval = match_eval,
             removed_accessions = gone, forced = forced, forced_pairs = pairs, checks = checks, ran_at = Sys.time()),
        file.path(HERE, "subset_workflow_local_corroboration_test_result.rds"))
message("Saved subset_workflow_local_corroboration_test_result.rds")
