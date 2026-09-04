# blast_coverage_blindspot_probe.R
#
# Live NCBI probe (2 queries, two small runs) for a hypothesis reached OFFLINE on
# 2026-09-03: evaluate_reference_accessions() cannot see amplicon-only reference
# deposits as corroborators, because its query is the primer-INCLUSIVE trimmed
# span (217 bp for MiFish-U) while a primer-stripped deposit is ~169 bp, giving
# query coverage 169/217 = 77.9% -- below blast_sequences()'s default
# min_query_coverage = 80, which the screen does not override.
#
# Evidence so far (all offline, PtConception 12S):
#   * KM057996 (Zaniolepis frenata) was actioned "remove" (no conspecific evidence
#     anywhere in nt) although the local reference_df holds OQ846041, a 169 bp
#     Zaniolepis frenata deposit from 2023 at 100% identity.
#   * KM057967 (Jordania zonope), also "remove", has LC126244 (806 bp, 2019) at
#     100% locally. 806 bp is NOT explained by the coverage filter -- this probe
#     tells us whether it is a hit-cap, nt-snapshot, or region problem instead.
#   * 1,357 of 4,061 PtCon references (33%) and 679 of 2,750 GreatLakes references
#     (25%) are <= 175 bp, i.e. the whole class is invisible to the screen.
#
# What to look for is printed at the end of each run. Results are saved next to
# this script as blast_coverage_blindspot_probe_result.rds.

.libPaths(c(path.expand(Sys.getenv("R_LIBS_USER")), "~/Library/R/4.0/library", .libPaths()))
library(TaxaMatch)
library(TaxaLikely)
suppressPackageStartupMessages(library(dplyr))

if (!nzchar(Sys.getenv("NCBI_EMAIL", unset = ""))) Sys.setenv(NCBI_EMAIL = "klafferty@usgs.gov")
NCBI_KEY <- Sys.getenv("ENTREZ_KEY", unset = "")

HERE   <- "/Users/lafferty/My Drive/Rscripts/projects/TaxaID/diagnostics"
PTCON  <- "/Users/lafferty/My Drive/Rscripts/eDNA/PtConception"
strip  <- function(x) sub("[.][0-9]+$", "", x)

queries      <- c("KM057967", "KM057996")            # the two "remove" verdicts
corroborators <- c(KM057967 = "LC126244", KM057996 = "OQ846041")  # 100% locally

# ------------------------------------------------------------------------------
# 0. Build the exact queries the screen submits: primer-inclusive trimmed span.
# ------------------------------------------------------------------------------
rd  <- readRDS(file.path(PTCON, "PtConMifishSchulte_reference_df.rds"))
sub <- rd[strip(rd$composite_id) %in% queries, ]
tr  <- TaxaLikely::trim_to_amplicon(sub, barcode_term = "MiFishU", verbose = FALSE)
seq_df <- data.frame(asv_id = strip(tr$composite_id), sequence = tr$sequence,
                     stringsAsFactors = FALSE)
message("Trimmed query lengths (expect ~217): ",
        paste(seq_df$asv_id, nchar(seq_df$sequence), collapse = ", "))

# ------------------------------------------------------------------------------
# RUN A. Raw hits with the coverage filter OFF and a wide window, so we can see
#        whether the corroborators are returned at all and at what coverage.
#        Costs 1 BLAST submission of 2 short queries.
# ------------------------------------------------------------------------------
hits <- blast_sequences(
  seq_df,
  min_query_coverage = 0,     # the screen's effective value is 80
  score_range        = 30,    # the screen's value is 8
  max_hits           = 100,   # the screen's value is 20
  resolve_taxonomy   = TRUE,
  ncbi_api_key       = NCBI_KEY
)
hits <- hits |> mutate(accession = strip(accession)) |>
  group_by(observation_id) |> arrange(desc(bitscore), .by_group = TRUE) |>
  mutate(rank_by_bitscore = row_number()) |> ungroup()

cat("\n=== RUN A: are the local corroborators returned by BLAST at all? ===\n")
found <- hits |> filter(accession %in% corroborators) |>
  select(observation_id, accession, species, score, query_coverage, alignment_length,
         subject_length, bitscore, rank_by_bitscore)
print(as.data.frame(found), row.names = FALSE)
if (nrow(found) == 0L) cat("  (neither corroborator returned, even with 100 hits and no coverage filter)\n")

cat("\n--- conspecific hits per query, split by the screen's 80% coverage rule ---\n")
consp <- hits |> filter(!is.na(species)) |>
  mutate(conspecific = (observation_id == "KM057967" & species == "Jordania zonope") |
                       (observation_id == "KM057996" & species == "Zaniolepis frenata")) |>
  filter(conspecific) |>
  group_by(observation_id) |>
  summarise(n_conspecific_hits = n(),
            n_passing_cov80    = sum(query_coverage >= 80, na.rm = TRUE),
            n_failing_cov80    = sum(query_coverage <  80, na.rm = TRUE),
            best_pident        = max(score), .groups = "drop")
print(as.data.frame(consp), row.names = FALSE)

cat("\n--- top 25 hits per query (what the screen would have seen, before its cap) ---\n")
print(as.data.frame(hits |> filter(rank_by_bitscore <= 25) |>
  select(observation_id, rank_by_bitscore, accession, species, score, query_coverage,
         subject_length, bitscore)), row.names = FALSE)

cat("\nREAD RUN A LIKE THIS:\n",
    " * OQ846041 present, score 100, query_coverage ~78 -> coverage filter confirmed as the mechanism.\n",
    " * LC126244 present, score 100, coverage >= 80  -> it WAS visible; the 2026-09-01 miss was the hit\n",
    "   cap or an nt-snapshot gap (Run B tells which: if Run B now reads congruent, snapshot).\n",
    " * LC126244 absent even here -> not searchable in nt (snapshot) or aligned to a different region.\n",
    " * n_failing_cov80 > 0 for either query -> the screen discarded real conspecific evidence.\n", sep = "")

# ------------------------------------------------------------------------------
# RUN B. The screen itself, default parameters, into a FRESH cache so the real
#        PtCon cache is untouched. Tells us what verdict these two get TODAY and
#        which partners the verdict rests on. Costs 1 more submission.
# ------------------------------------------------------------------------------
probe_cache <- file.path(HERE, "cache_coverage_blindspot_probe")
if (dir.exists(probe_cache)) unlink(probe_cache, recursive = TRUE)
qc <- evaluate_reference_accessions(
  queries, cache_dir = probe_cache, ncbi_api_key = NCBI_KEY, barcode_term = "MiFishU"
)
qc <- TaxaMatch::score_reference_labels(qc, overwrite = TRUE)
cat("\n=== RUN B: today's screen verdict (default params, fresh cache) ===\n")
print(as.data.frame(qc |> select(accession, listed_taxon, hierarchy_flag, reference_action,
                                 n_top_matches_available, n_independent_top_matches,
                                 best_agreeing_pident, best_disagreeing_pident,
                                 best_disagreeing_taxon, congruent_evidence_exists_anywhere)),
      row.names = FALSE)
pairs <- readRDS(file.path(probe_cache, "reference_pair_cache.rds"))
cat("\n--- partners the verdict rests on (pair cache) ---\n")
print(as.data.frame(pairs |> select(id_x, id_y, p_match, pair_finest_common_rank, species_y) |>
                      arrange(id_x, desc(p_match))), row.names = FALSE)
cat("\nREAD RUN B LIKE THIS:\n",
    " * still incongruent/remove, corroborators absent from the pair table -> the blind spot is\n",
    "   live in production today, not a one-day snapshot artefact.\n",
    " * congruent now -> nt snapshot moved (as with OP056918 on 09-02); the coverage finding\n",
    "   from Run A still stands on its own.\n", sep = "")

saveRDS(list(run_a_hits = hits, run_a_found = found, run_a_conspecific = consp,
             run_b_verdicts = qc, run_b_pairs = pairs, ran_at = Sys.time()),
        file.path(HERE, "blast_coverage_blindspot_probe_result.rds"))
message("Saved blast_coverage_blindspot_probe_result.rds")

# ------------------------------------------------------------------------------
# RUN C (added after Runs A/B on 2026-09-03). Runs A/B showed OQ846041 is NOT
# returned even in a 100-hit list with no coverage filter. Offline arithmetic
# says why: under blastn scoring (+2 match / -3 mismatch) a 169-bp perfect
# conspecific scores 338 raw, while every one of the 100 returned relatives at
# >= 93.1% over the full 217-bp query scores >= 359 -- so the short perfect
# match never makes the server's hit list. The fix implied is to submit the
# PRIMER-STRIPPED query (169 bp for MiFish-U): then the conspecific aligns at
# full length (338) and a 93% relative scores only ~278. This run tests exactly
# that with ONE query. Costs 1 submission.
#
# Expected if the mechanism is right: OQ846041 at rank 1 (or tied with other
# 100% hits), score 100, query_coverage 100; the Anarhichas relatives well below.
# Expected if OQ846041 is simply not in nt: still absent.
# ------------------------------------------------------------------------------
q217 <- seq_df$sequence[seq_df$asv_id == "KM057996"]
stopifnot(nchar(q217) == 217L)
q169 <- substr(q217, 22L, 217L - 27L)   # drop MiFish-U F (21 bp) and R (27 bp)
stopifnot(nchar(q169) == 169L)
hits_c <- blast_sequences(
  data.frame(asv_id = "KM057996_stripped", sequence = q169, stringsAsFactors = FALSE),
  min_query_coverage = 0, score_range = 30, max_hits = 100,
  resolve_taxonomy = TRUE, ncbi_api_key = NCBI_KEY
) |> mutate(accession = strip(accession)) |>
  arrange(desc(bitscore)) |> mutate(rank_by_bitscore = row_number())
cat("\n=== RUN C: primer-stripped 169-bp KM057996 query ===\n")
print(as.data.frame(hits_c |> filter(accession == "OQ846041" | rank_by_bitscore <= 10) |>
  select(rank_by_bitscore, accession, species, score, query_coverage, alignment_length,
         subject_length, bitscore)), row.names = FALSE)
cat("\nconspecific (Zaniolepis frenata) hits in Run C:", sum(hits_c$species %in% "Zaniolepis frenata"),
    "; lowest bitscore in the 100-hit list:", min(hits_c$bitscore), "\n")
# Guards so this block can be run alone in a session where the Run B tail errored
if (!exists("pairs")) pairs <- readRDS(file.path(probe_cache, "reference_pair_cache.rds"))
if (!exists("qc")) qc <- readRDS(file.path(probe_cache, "reference_accession_cache.rds"))
saveRDS(list(run_a_hits = hits, run_b_verdicts = qc, run_b_pairs = pairs, run_c_hits = hits_c,
             ran_at = Sys.time()),
        file.path(HERE, "blast_coverage_blindspot_probe_result.rds"))
message("Saved blast_coverage_blindspot_probe_result.rds (with Run C)")
