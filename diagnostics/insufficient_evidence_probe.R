# ==============================================================================
# What is "insufficient_independent_evidence" actually made of?
#
# It is the largest non-congruent population in every real screen (PtCon 34
# under the live key, GreatLakes pilot 68) and nothing has ever looked at it --
# every prior thread went after "incongruent", which is ~0.5% of a population
# and the only verdict acted on destructively.
#
# The offline decomposition of PtCon's 34 splits exactly in two, with no
# overlap at all:
#
#   17 rows with ZERO valid partners  -> label_confidence exactly 0.500
#                                     -> reference_action "caution"
#                                     -> congruent_evidence_exists_anywhere FALSE
#   17 rows with 1-2 valid partners   -> label_confidence 0.75-0.999
#                                     -> reference_action "keep"
#                                     -> congruent_evidence_exists_anywhere TRUE
#                                        (median best agreeing identity 98.2%)
#
# So half of them already carry corroborating evidence and are only "insufficient"
# because the VOTE wants >= min_independent_partners (3), and the other half
# carry no evidence at all yet read "caution" -- a concern rating earned by an
# absence, against a base rate of 931/989 congruent.
#
# THE QUESTION THIS PROBE ANSWERS: is the zero-partner half a real property of
# these accessions, or the same max_hits truncation the removal veto turned out
# to suffer from (diagnostics/veto_truncation_probe.R, 2026-09-04: 8 of 15
# flipped, and one of two PtCon removals became unremovable)? That probe already
# tested 8 of these 17 -- 7 resolved to "congruent" at max_hits = 100. This one
# covers all 34 so the answer is about the population, not a subset.
#
# Shares veto_truncation_probe.R's cache dir on purpose: same params_key
# (max_hits IS in the key), so those 8 are served free and only the remaining
# 26 cost an NCBI call.
#
# Live NCBI. ~26 new accessions.
# ==============================================================================

.libPaths(c(path.expand(Sys.getenv("R_LIBS_USER")), .libPaths()))
suppressMessages(library(TaxaMatch))

PROD_CACHE <- "/Users/lafferty/My Drive/Rscripts/eDNA/PtConception/ptcon_ref_eval_cache"
PROBE_DIR  <- file.path(
  "/Users/lafferty/My Drive/Rscripts/projects/TaxaID/diagnostics",
  "cache_veto_truncation"
)
LIVE_KEY <- "v5_amplicon_query"
WIDE_MAX_HITS <- 100L

prod <- readRDS(file.path(PROD_CACHE, "reference_accession_cache.rds"))
base <- score_reference_labels(
  prod[grepl(LIVE_KEY, prod$params_key, fixed = TRUE), , drop = FALSE]
)

ins <- base[base$hierarchy_flag %in% "insufficient_independent_evidence", , drop = FALSE]
targets <- ins$accession

# The offline split, recomputed here so the printout is self-contained.
ins$arm <- ifelse(ins$n_independent_top_matches %in% 0L,
                  "zero-partner", "1-2 partners")

message(sprintf(
  "insufficient_evidence_probe: %d target(s) -- %d zero-partner, %d with 1-2 partners.",
  length(targets), sum(ins$arm == "zero-partner"), sum(ins$arm == "1-2 partners")
))

wide <- evaluate_reference_accessions(
  targets,
  cache_dir    = PROBE_DIR,
  ncbi_api_key = Sys.getenv("ENTREZ_KEY"),
  barcode_term = "MiFishU",
  max_hits     = WIDE_MAX_HITS,
  verbose      = TRUE
)

keep_cols <- c("accession", "listed_taxon", "hierarchy_flag",
               "n_independent_top_matches", "n_top_matches_available",
               "congruent_evidence_exists_anywhere",
               "congruent_evidence_best_pident",
               "label_confidence", "reference_action")
cmp <- merge(
  ins[, c(keep_cols, "arm")], wide[, keep_cols],
  by = c("accession", "listed_taxon"), suffixes = c("_20", "_100"), all.x = TRUE
)
cmp$resolved <- !(cmp$hierarchy_flag_100 %in% "insufficient_independent_evidence")

cat("\n================ insufficient at max_hits 20 vs", WIDE_MAX_HITS, "================\n")
print(cmp[order(cmp$arm, cmp$listed_taxon),
          c("accession", "listed_taxon", "arm",
            "n_independent_top_matches_20", "n_independent_top_matches_100",
            "hierarchy_flag_100", "reference_action_20", "reference_action_100")],
      row.names = FALSE)

cat("\n---- headline ----\n")
cat(sprintf("  no longer 'insufficient' at %d hits: %d of %d\n",
            WIDE_MAX_HITS, sum(cmp$resolved, na.rm = TRUE), nrow(cmp)))
cat("\n  by arm:\n")
print(table(arm = cmp$arm, resolved = cmp$resolved))
cat("\n  new verdicts:\n")
print(table(cmp$hierarchy_flag_100, useNA = "ifany"))
cat("\n  action change:\n")
print(table(from = cmp$reference_action_20, to = cmp$reference_action_100))
cat(sprintf("\n  still saturated at %d hits: %d of %d\n", WIDE_MAX_HITS,
            sum(cmp$n_top_matches_available_100 >= WIDE_MAX_HITS - 1L, na.rm = TRUE),
            nrow(cmp)))
# A row that gained NO hits at all when the window quintupled was never
# truncated -- its thinness is real, and no widening will fix it.
cat(sprintf("  gained no hits when the window quintupled: %d\n",
            sum(cmp$n_top_matches_available_100 <= cmp$n_top_matches_available_20,
                na.rm = TRUE)))

saveRDS(list(comparison = cmp, wide = wide, max_hits = WIDE_MAX_HITS,
             run_at = Sys.time()),
        file.path(dirname(PROBE_DIR), "insufficient_evidence_probe.rds"))
cat("\nsaved: diagnostics/insufficient_evidence_probe.rds\n")
