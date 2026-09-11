# screen_training_references_standalone.R  (2026-09-11)
#
# Run a site's TRAINING reference screen (workflow Step 7a.11) outside the
# workflow, as a resumable job that keeps going until NCBI has answered for
# every accession -- instead of the 4-5 hour production run spending hours
# grinding against NCBI's CPU-budget throttle and then stopping at 70%.
#
# It uses exactly the same call the workflow makes, against the SAME persistent
# cache directory, so the next workflow run serves the whole screen from cache
# in seconds. Nothing else is touched: no checkpoint is rewritten, no model is
# retrained. Kill it and re-run it any time; it resumes from the cache.
#
# Usage (from a shell; Rscript reads ~/.Renviron, so ENTREZ_KEY is available):
#   Rscript screen_training_references_standalone.R GreatLakes
#   Rscript screen_training_references_standalone.R PtCon12S   # also serves 12S multi-site
#   Rscript screen_training_references_standalone.R PtCon18S
#   Rscript screen_training_references_standalone.R GreatLakes 6   # max hours (default 8)
#
# Mugu has no training-set screen (its workflows never used one), so it is not
# listed. Pending counts before this script existed: GreatLakes 761, PtCon 12S
# 1,866, PtCon 18S unknown (never completed).

.libPaths(c(path.expand("~/Library/R/4.0/library"), .libPaths()))
suppressMessages({ library(dplyr); library(TaxaMatch) })

SITES <- list(
  GreatLakes = list(
    dir = "/Users/lafferty/My Drive/Stats and Data/GreatLakes data",
    prefix = "GreatLakes2023BurnsHarbor", barcode_term = "MiFishU",
    cache = "GreatLakes2023BurnsHarbor_training_screen_pilot_ref_eval_cache"
  ),
  PtCon12S = list(
    dir = "/Users/lafferty/My Drive/Rscripts/eDNA/PtConception",
    prefix = "PtConMifishSchulte", barcode_term = "MiFishU",
    cache = "ptcon_training_ref_eval_cache"
  ),
  PtCon18S = list(
    dir = "/Users/lafferty/My Drive/Rscripts/eDNA/PtConception",
    prefix = "PtCon18SSchulte", barcode_term = "18S",
    cache = "ptcon18s_training_ref_eval_cache"
  )
)

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1L || !args[1] %in% names(SITES)) {
  stop("Usage: Rscript screen_training_references_standalone.R <", paste(names(SITES), collapse = "|"), "> [max_hours]")
}
site <- SITES[[args[1]]]
max_hours <- if (length(args) >= 2L) as.numeric(args[2]) else 8

setwd(site$dir)
.p <- function(tag) file.path(site$dir, paste0(site$prefix, "_", tag, ".rds"))
stopifnot(file.exists(.p("seq_matrix")), file.exists(.p("reference_df")))
seq_matrix   <- readRDS(.p("seq_matrix"))
reference_df <- readRDS(.p("reference_df"))
cat(sprintf("[%s] %s: %d references, seq_matrix %d rows (checkpoints from %s)\n",
            format(Sys.time(), "%H:%M"), args[1], length(unique(reference_df$composite_id)),
            nrow(seq_matrix), format(file.mtime(.p("reference_df")), "%Y-%m-%d %H:%M")))

# Same free pre-filter the workflow computes (pure R, no network).
local_corr <- corroborate_references_locally(seq_matrix, reference_df)

t0 <- Sys.time(); pass <- 0L
repeat {
  pass <- pass + 1L
  ref_eval <- evaluate_reference_accessions(
    accessions                = unique(reference_df$composite_id),
    barcode_term              = site$barcode_term,
    local_corroboration       = local_corr,
    skip_locally_corroborated = TRUE,
    cache_dir                 = file.path(site$dir, site$cache),
    ncbi_api_key              = Sys.getenv("ENTREZ_KEY") %||% NULL
  )
  rs <- attr(ref_eval, "run_summary")
  cat(sprintf("[%s] pass %d: %d/%d complete (%.1f%%), %d evaluated this pass, %d pending, breaker %s | actions: %s\n",
              format(Sys.time(), "%H:%M"), pass, rs$n_total - rs$n_pending, rs$n_total, rs$pct_complete,
              rs$n_evaluated_this_call, rs$n_pending, rs$circuit_breaker_tripped,
              paste(names(table(ref_eval$reference_action)), table(ref_eval$reference_action), collapse = " ")))
  if (rs$n_pending == 0L) { cat("DONE: every accession has a verdict. The next workflow run serves this screen from cache.\n"); break }
  elapsed_h <- as.numeric(difftime(Sys.time(), t0, units = "hours"))
  if (elapsed_h >= max_hours) { cat(sprintf("Stopping after %.1f h with %d pending; re-run later to continue.\n", elapsed_h, rs$n_pending)); break }
  if (rs$n_evaluated_this_call == 0L && !isTRUE(rs$circuit_breaker_tripped)) {
    cat("No progress and no breaker -- the pending set may be all not-evaluated verdicts inside their TTL. Stopping.\n"); break
  }
  wait_min <- max(5, rs$recommended_pause_minutes %||% 15)
  cat(sprintf("  NCBI throttled; sleeping %d min before the next pass...\n", as.integer(wait_min)))
  Sys.sleep(wait_min * 60)
}
rm_acc <- ref_eval$accession[ref_eval$reference_action %in% "remove"]
cat(sprintf("Removal candidates so far (%d): %s\n", length(rm_acc), paste(rm_acc, collapse = ", ")))
