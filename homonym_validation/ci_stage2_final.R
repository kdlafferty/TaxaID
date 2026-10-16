# Round 2 (pooled) consensus on a small posterior extract: reproduce the saved final calls
# (consensus_taxon/consensus_rank/consensus_limit), re-run under a new lineage, diff.
# Rscript homonym_validation/ci_stage2_final.R <round2_posterior_extract.rds> <new_lineage.rds> [out_prefix]   (cwd = worktree root)
source("homonym_validation/ci_common.R")
ci_run(2, commandArgs(trailingOnly = TRUE))
