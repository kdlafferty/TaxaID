# Round 1 (per-marker) consensus on a small posterior extract: reproduce the saved Round-1 calls
# (consensus_taxon_v1/consensus_rank_v1) under the old lineage, re-run under a new one, diff.
# Rscript homonym_validation/ci_stage1_round1.R <round1_posterior_extract.rds> <new_lineage.rds> [out_prefix]   (cwd = worktree root)
source("homonym_validation/ci_common.R")
ci_run(1, commandArgs(trailingOnly = TRUE))
