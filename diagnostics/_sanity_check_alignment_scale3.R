.libPaths(c(path.expand(Sys.getenv("R_LIBS_USER")), .libPaths()))
suppressPackageStartupMessages({library(Biostrings); library(pwalign)})

prev <- readRDS("diagnostics/referenced_candidate_exclusion_rate_result.rds")
struct_hits <- prev$struct_hits_anchored
reference_df <- readRDS("~/My Drive/Rscripts/eDNA/PtConception/PtConMifishSchulte_reference_df.rds")
match_obj <- readRDS("~/My Drive/Rscripts/eDNA/PtConception/PtConMifishSchulte_match_obj.rds")

query_seq_df <- match_obj[!duplicated(match_obj$observation_id), c("observation_id", "sequence")]
sh <- merge(struct_hits[, c("observation_id","anchor_species","anchor_score")],
            query_seq_df, by = "observation_id")
sh <- unique(sh)

set.seed(2)
samp <- sh[sample(nrow(sh), min(120, nrow(sh))), ]

.best_real_score <- function(query_chr, species_name, reference_df) {
  cand_seqs <- reference_df$sequence[reference_df$species == species_name]
  cand_seqs <- cand_seqs[!is.na(cand_seqs) & nzchar(cand_seqs)]
  if (length(cand_seqs) == 0L) return(c(NA_real_, NA_integer_))
  q <- tryCatch(Biostrings::DNAString(query_chr), error = function(e) NULL)
  if (is.null(q)) return(c(NA_real_, NA_integer_))
  best <- NA_real_; best_rlen <- NA_integer_
  for (cs in cand_seqs) {
    r <- tryCatch(Biostrings::DNAString(cs), error = function(e) NULL)
    if (is.null(r)) next
    aln <- tryCatch(pwalign::pairwiseAlignment(q, r, type = "local"), error = function(e) NULL)
    if (is.null(aln)) next
    pid_val <- tryCatch(pwalign::pid(aln, type = "PID1"), error = function(e) NA_real_)
    if (!is.na(pid_val) && (is.na(best) || pid_val > best)) { best <- pid_val; best_rlen <- nchar(cs) }
  }
  c(best, best_rlen)
}

res <- t(vapply(seq_len(nrow(samp)), function(i)
  .best_real_score(samp$sequence[i], samp$anchor_species[i], reference_df), numeric(2)))
samp$my_pid_anchor <- res[,1]
samp$ref_len <- res[,2]
samp$qlen <- nchar(samp$sequence)
samp$diff <- samp$my_pid_anchor - samp$anchor_score
samp$len_mismatch <- samp$qlen - samp$ref_len

ok <- samp[!is.na(samp$diff), ]
cat("n usable:", nrow(ok), "of", nrow(samp), "\n\n")
cat("=== diff summary ===\n"); print(summary(ok$diff))
cat("\n=== correlation: diff vs anchor_score (recorded identity level) ===\n")
print(cor.test(ok$diff, ok$anchor_score))
cat("\n=== correlation: diff vs length mismatch (qlen - reflen) ===\n")
print(cor.test(ok$diff, ok$len_mismatch))
cat("\n=== correlation: diff vs abs(length mismatch) ===\n")
print(cor.test(ok$diff, abs(ok$len_mismatch)))
cat("\ntable of len_mismatch (should be 0 if same amplicon window):\n")
print(table(ok$len_mismatch))
saveRDS(ok, "diagnostics/_sanity_check_alignment_scale3_result.rds")
