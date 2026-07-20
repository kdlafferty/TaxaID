# ==============================================================================
# Problem 1 rate estimate, Part 2: REAL query-vs-candidate alignment
# ==============================================================================
#
# Follows referenced_candidate_exclusion_rate.R, whose free seq_matrix-based
# estimate covered only 5% of the 4,049 structurally-flagged (observation,
# missing_species) pairs and was an ESTIMATE (query treated as if it behaved
# like its own top-hit reference) even where available.
#
# This script computes the REAL score(query, missing_species) for every
# flagged pair directly -- a local pairwise alignment of the observation's
# own raw sequence (match_obj$sequence, real data for this dataset) against
# the missing species' actual reference sequence(s) in reference_df. Same
# alignment method restore_suppressed_candidates()'s Tier 2b already uses
# (pwalign::pairwiseAlignment(type = "local")), same %identity convention as
# match_obj$score_original (PID1 = matches / alignment length).
#
# IMPORTANT SCOPE CAVEAT (see the conversation this grew out of): this
# produces a real AMBIGUITY rate -- how often a referenced, locally-plausible
# species was structurally excluded despite scoring close enough to have
# been a genuine competing candidate -- NOT a confirmed ERROR rate. Knowing
# two species score near-identically against a real query tells you there's
# a real identification problem; it does not tell you which one is correct.
# The dominant real case (Citharichthys sordidus / C. xanthostigma) has TWO
# locally-plausible species in one genus, which structurally disqualifies it
# from identify_confident_observations()'s only ground-truth mechanism
# (requires exactly one locally-plausible species per genus) -- there is no
# independent way to know which sanddab a given read actually came from.
# ==============================================================================

library(dplyr)
.libPaths(c(path.expand(Sys.getenv("R_LIBS_USER")), .libPaths()))
suppressPackageStartupMessages({
  library(Biostrings)
  library(pwalign)
})

DATA_DIR <- "~/My Drive/Rscripts/eDNA/PtConception"
PREFIX   <- "PtConMifishSchulte"

prev <- readRDS(file.path("diagnostics", "referenced_candidate_exclusion_rate_result.rds"))
struct_hits <- prev$struct_hits_anchored |>
  select(observation_id, missing_species, genus, theta_mean,
         anchor_accession, anchor_score, anchor_species)

match_obj    <- readRDS(file.path(DATA_DIR, paste0(PREFIX, "_match_obj.rds")))
reference_df <- readRDS(file.path(DATA_DIR, paste0(PREFIX, "_reference_df.rds")))

# one raw query sequence per observation_id (identical across candidate rows)
# NOTE: dplyr::slice()/group_by() collide with an S4 generic from
# Biostrings/IRanges once those packages are loaded -- use base R here.
query_seq_df <- match_obj[!duplicated(match_obj$observation_id),
                           c("observation_id", "sequence")]

struct_hits <- struct_hits |> left_join(query_seq_df, by = "observation_id")

cat(sprintf("Rows to check: %d (%d distinct observations, %d distinct missing species)\n",
            nrow(struct_hits), length(unique(struct_hits$observation_id)),
            length(unique(struct_hits$missing_species))))

# ---- dedupe: many observations share an identical raw ASV sequence --------
uniq_pairs <- struct_hits |>
  distinct(sequence, missing_species) |>
  filter(!is.na(sequence), nzchar(sequence))

cat(sprintf("Distinct (sequence, missing_species) pairs needing real alignment: %d\n",
            nrow(uniq_pairs)))

.best_real_score <- function(query_chr, species_name, reference_df) {
  cand_seqs <- reference_df$sequence[reference_df$species == species_name]
  cand_seqs <- cand_seqs[!is.na(cand_seqs) & nzchar(cand_seqs)]
  if (length(cand_seqs) == 0L) return(NA_real_)
  q <- tryCatch(Biostrings::DNAString(query_chr), error = function(e) NULL)
  if (is.null(q)) return(NA_real_)
  best <- NA_real_
  for (cs in cand_seqs) {
    r <- tryCatch(Biostrings::DNAString(cs), error = function(e) NULL)
    if (is.null(r)) next
    aln <- tryCatch(pwalign::pairwiseAlignment(q, r, type = "local"), error = function(e) NULL)
    if (is.null(aln)) next
    pid_val <- tryCatch(pwalign::pid(aln, type = "PID1"), error = function(e) NA_real_)
    if (!is.na(pid_val) && (is.na(best) || pid_val > best)) best <- pid_val
  }
  best
}

t0 <- Sys.time()
uniq_pairs$real_score <- vapply(seq_len(nrow(uniq_pairs)), function(i) {
  .best_real_score(uniq_pairs$sequence[i], uniq_pairs$missing_species[i], reference_df)
}, numeric(1))
cat(sprintf("Real alignment wall time: %.1fs for %d pairs\n",
            as.numeric(difftime(Sys.time(), t0, units = "secs")), nrow(uniq_pairs)))

struct_hits_real <- struct_hits |>
  left_join(uniq_pairs, by = c("sequence", "missing_species")) |>
  mutate(real_gap = anchor_score - real_score)

cat("\n=== REAL (not estimated) gap distribution ===\n")
print(summary(struct_hits_real$real_gap))
cat(sprintf("\nRows where no candidate reference sequence was usable at all: %d / %d\n",
            sum(is.na(struct_hits_real$real_score)), nrow(struct_hits_real)))

n_obs_total <- length(unique(match_obj$observation_id))
for (w in c(1, 2, 5, 8, 15)) {
  n_obs_w <- length(unique(struct_hits_real$observation_id[
    !is.na(struct_hits_real$real_gap) & struct_hits_real$real_gap <= w]))
  cat(sprintf("  Observations with a REAL, close-scoring excluded candidate\n"))
  cat(sprintf("    (real_gap <= %2d pts): %5d / %d (%.2f%%)\n",
              w, n_obs_w, n_obs_total, 100 * n_obs_w / n_obs_total))
}

cat("\nTop missing species among REAL hits (real_gap <= 8):\n")
gated8 <- struct_hits_real |> filter(!is.na(real_gap), real_gap <= 8)
if (nrow(gated8) > 0) {
  print(gated8 |> count(missing_species, genus, sort = TRUE))
} else {
  cat("  (none)\n")
}

# ---- spot-check: print full detail for a handful of real examples ---------
cat("\n=== Spot-check: 10 real examples with the tightest real_gap ===\n")
spot <- struct_hits_real |>
  filter(!is.na(real_gap)) |>
  arrange(real_gap) |>
  select(observation_id, anchor_species, anchor_score, missing_species,
         real_score, real_gap, theta_mean) |>
  head(10)
print(spot, width = Inf)

saveRDS(struct_hits_real,
        file.path("diagnostics", "referenced_candidate_exclusion_rate_real_result.rds"))
