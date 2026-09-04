# ==============================================================================
# Small-subset test of the partner-trust fixpoint (Thread 1 of
# ecosystem_docs/REENTRY_PROMPT_reference_quality_verdicts_and_downstream_use.md)
#
# WHY A SMALL LIST: refine_reference_verdicts() needs the per-partner votes,
# which evaluate_reference_accessions() only began persisting on 2026-09-02
# (reference_pair_cache.rds). No existing cache has them, and rebuilding them
# for the full 995-accession PtConception screen is an overnight NCBI job. This
# script exercises the whole mechanism end to end on ~15 + ~40 accessions
# instead, chosen so the interesting cases are all present.
#
# WHAT IT DOES, in two BLAST stages:
#   Stage 1  Evaluate the 12 real PtConception "incongruent" accessions plus
#            3 congruent controls. This builds their pair tables.
#   Stage 2  Read the pair cache, find the accessions that actually VOTED
#            against them (previously unknowable -- only the disagreeing
#            taxon's NAME was ever stored), and evaluate those partners too,
#            so they have verdicts of their own to be weighted by.
#   Stage 3  Run refine_reference_verdicts() over the union and report every
#            verdict the trust weighting moved.
#
# Stage 2 is the point: partner trust can only discount a partner that is
# ITSELF in the evaluation. Stage 1 alone would leave every partner at weight
# 1 and the fixpoint a no-op by construction.
#
# Run:  Rscript diagnostics/partner_trust_small_test.R
# Cost: two BLAST rounds over ~55 accessions total, resumable (everything is
#       cached per chunk, so re-running only costs whatever failed).
# ==============================================================================

suppressMessages(library(TaxaMatch))

CACHE_DIR <- file.path("diagnostics", "cache_partner_trust_test")
OUT_RDS   <- file.path("diagnostics", "partner_trust_small_test_result.rds")
MAX_PARTNERS <- 40L   # keep stage 2 small; partners are ranked by how often
                      # they voted against a stage-1 accession

# The 12 accessions that read "incongruent" on the first complete PtConception
# 12S screen (995 accessions, 2026-09-02), plus 3 ordinary congruent controls
# to confirm the fixpoint leaves settled verdicts alone.
INCONGRUENT <- c(
  "OK172573",   # Scorpaenichthys marmoratus -- cabezon, 1,120 observations
  "MF409245",   # Eschrichtius robustus
  "KM057978",   # Oxylebius pictus -- corroborated only outside the top-5 window
  "OP056918",   # Cryptacanthodes maculatus -- no corroboration anywhere
  "NC_066931",  # Apodichthys flavidus
  "OQ846263",   # Rathbunella hypoplecta -- no corroboration anywhere
  "KM057967",   # Jordania zonope        -- no corroboration anywhere
  "OR582690",   # Zaprora silenus
  "KM057996",   # Zaniolepis frenata     -- no corroboration anywhere
  "LC672490",   # Eurymen gyrinus
  "AP012503",   # Nesiarchus nasutus
  "NC_053053"   # Toxostoma redivivum
)
CONTROLS <- c(
  "MT627596",   # Askoldia variegata -- the disagreeing partner in 4 of the 12,
                #   and the accession that motivated this whole thread
  "MN883227",   # Fundulus luciae -- the known unpublished-library case
  "OQ846539"    # Clinocottus recalvus -- an ordinary insufficient-evidence row
)

message("=== Stage 1: evaluate the flagged accessions and their controls ===")
stage1 <- evaluate_reference_accessions(
  unique(c(INCONGRUENT, CONTROLS)),
  cache_dir    = CACHE_DIR,
  ncbi_api_key = Sys.getenv("ENTREZ_KEY"),
  barcode_term = "MiFishU"
)
print(table(stage1$hierarchy_flag, stage1$reference_action))

pairs <- TaxaMatch:::.load_reference_pair_cache(CACHE_DIR)
if (nrow(pairs) == 0L)
  stop("Stage 1 produced no pair table -- nothing was re-BLASTed this run. ",
       "Check the cache_dir and the NCBI key.")

message(sprintf("\n=== Stage 2: %d pair rows cached; picking the partners that disagree ===",
                nrow(pairs)))

# A partner is worth evaluating when it actually votes AGAINST one of the
# stage-1 accessions -- an agreeing partner's own trustworthiness cannot
# change a verdict in the direction this thread cares about.
rank_idx <- match(tolower(pairs$pair_finest_common_rank),
                  tolower(TaxaTools::standard_ranks))
min_idx  <- which(tolower(TaxaTools::standard_ranks) == "family")
pairs$below <- is.na(rank_idx) | rank_idx < min_idx

disagreers <- sort(table(pairs$id_y[pairs$below]), decreasing = TRUE)
partners   <- setdiff(names(disagreers), c(INCONGRUENT, CONTROLS))
partners   <- head(partners, MAX_PARTNERS)
message(sprintf("  %d distinct disagreeing partner(s); evaluating the top %d:\n  %s",
                length(disagreers), length(partners),
                paste(partners, collapse = ", ")))

stage2 <- evaluate_reference_accessions(
  unique(c(INCONGRUENT, CONTROLS, partners)),
  cache_dir    = CACHE_DIR,
  ncbi_api_key = Sys.getenv("ENTREZ_KEY"),
  barcode_term = "MiFishU"
)

message("\n=== Stage 3: partner-trust fixpoint ===")
refined <- refine_reference_verdicts(stage2, cache_dir = CACHE_DIR)

changed <- refined[
  !is.na(refined$reference_action) &
    (refined$reference_action != refined$reference_action_trust |
       refined$hierarchy_flag != refined$hierarchy_flag_trust), ]

cat("\n--- verdicts the trust weighting moved ---\n")
if (nrow(changed) == 0L) {
  cat("None. Every partner kept full weight (see .partner_trust_weight()'s\n",
      "cascade guard: an under-evaluated partner is not a discredited one).\n")
} else {
  print(changed[, c("accession", "listed_taxon", "hierarchy_flag",
                    "hierarchy_flag_trust", "label_confidence",
                    "label_confidence_trust", "n_effective_partners",
                    "reference_action", "reference_action_trust")],
        row.names = FALSE, digits = 4)
}

cat("\n--- the 12 originally-incongruent accessions, refined ---\n")
print(refined[refined$accession %in% INCONGRUENT,
              c("accession", "listed_taxon", "label_confidence",
                "label_confidence_trust", "n_effective_partners",
                "reference_action", "reference_action_trust", "trust_refined")],
      row.names = FALSE, digits = 4)

saveRDS(refined, OUT_RDS)
cat(sprintf("\nSaved to %s (%d accessions, %d refined).\n",
            OUT_RDS, nrow(refined), sum(refined$trust_refined)))
