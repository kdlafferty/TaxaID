# ==============================================================================
# Is the removal veto truncation-blind?
#
# `score_reference_labels()` gives `reference_action == "remove"` two HARD
# vetoes, and the load-bearing one is
# `congruent_evidence_exists_anywhere == FALSE`: corroborating evidence
# ANYWHERE spares an accession however low its label_confidence. That column
# is documented as "anywhere in the full independence-filtered pool, not
# limited to top_n" -- but the pool it walks is itself capped by `max_hits`
# (default 20L), and on the real PtCon 12S screen 899 of 989 accessions
# (91%) come back AT that cap. So "anywhere" means "anywhere in the top 20",
# and an accession whose top 20 are saturated by a divergent clade can read
# "no corroboration anywhere" while a conspecific sits at rank 21.
#
# That matters more now than it did on 2026-09-02: the primer-stripped v5
# re-run cut `remove` from 4 accessions to 2, so the veto is carrying nearly
# the whole destructive decision.
#
# THE TEST: re-evaluate the veto-critical accessions at max_hits = 100 and
# ask whether `congruent_evidence_exists_anywhere` flips FALSE -> TRUE.
#
#   - If it flips for OQ846263 or KM057967, that removal was an artifact of
#     the 20-hit window and the PtCon removal set is smaller still.
#   - If it flips for the saturated insufficient rows, `max_hits` (not the
#     independence filter) is what starves them of partners.
#   - The congruent controls must NOT change: max_hits is a widening, so an
#     already-corroborated accession cannot lose corroboration. A control
#     that moves means the probe itself is unsound.
#
# `max_hits` is part of params_key, so this cannot collide with the
# production cache -- but it writes to its own cache dir anyway, the same
# convention blast_verdict_repeatability_probe.R uses.
#
# Live NCBI. ~15 accessions, one BLAST each.
# ==============================================================================

.libPaths(c(path.expand(Sys.getenv("R_LIBS_USER")), .libPaths()))
suppressMessages(library(TaxaMatch))

PROD_CACHE <- "/Users/lafferty/My Drive/Rscripts/eDNA/PtConception/ptcon_ref_eval_cache"
PROBE_DIR  <- file.path(
  "/Users/lafferty/My Drive/Rscripts/projects/TaxaID/diagnostics",
  "cache_veto_truncation"
)
LIVE_KEY <- "5|family|5|0.5|3|8|70|20|remote|nt|amplicon|v5_amplicon_query"
WIDE_MAX_HITS <- 100L

dir.create(PROBE_DIR, showWarnings = FALSE, recursive = TRUE)

prod <- readRDS(file.path(PROD_CACHE, "reference_accession_cache.rds"))
base <- score_reference_labels(prod[prod$params_key == LIVE_KEY, , drop = FALSE])

# ---- Target set -------------------------------------------------------------
# (1) every "incongruent" row -- the only removable population, so the only
#     place the veto can change a destructive outcome;
# (2) "insufficient" rows with ZERO valid partners despite a saturated hit
#     slate -- the pool was there and none of it counted;
# (3) two congruent controls that also saturate, as the soundness check.
incong <- base$accession[base$hierarchy_flag %in% "incongruent"]
starved <- base$accession[
  base$hierarchy_flag %in% "insufficient_independent_evidence" &
    base$n_independent_top_matches %in% 0L &
    base$n_top_matches_available >= 19L
]
controls <- utils::head(
  base$accession[base$hierarchy_flag %in% "congruent" &
                   base$n_top_matches_available >= 19L], 2L
)
targets <- unique(c(incong, starved, controls))

message(sprintf(
  "veto_truncation_probe: %d target(s) -- %d incongruent, %d starved-insufficient, %d congruent control(s).",
  length(targets), length(incong), length(starved), length(controls)
))

# ---- The widened re-evaluation ----------------------------------------------
# No local_corroboration: the question is what BLAST alone can see, and
# skip_locally_corroborated would exempt exactly the accessions under test.
wide <- evaluate_reference_accessions(
  targets,
  cache_dir    = PROBE_DIR,
  ncbi_api_key = Sys.getenv("ENTREZ_KEY"),
  barcode_term = "MiFishU",
  max_hits     = WIDE_MAX_HITS,
  verbose      = TRUE
)
# evaluate_reference_accessions() already applies score_reference_labels()
# to its own output, so calling it again here errors (overwrite guard).
# `base` above DOES need the call: it is read straight off the cache file,
# which stores only the raw diagnostic columns.

# ---- Comparison -------------------------------------------------------------
keep_cols <- c("accession", "listed_taxon", "hierarchy_flag",
               "n_independent_top_matches", "n_top_matches_available",
               "congruent_evidence_exists_anywhere",
               "congruent_evidence_best_pident",
               "label_confidence", "reference_action")
cmp <- merge(
  base[base$accession %in% targets, keep_cols],
  wide[, keep_cols],
  by = c("accession", "listed_taxon"), suffixes = c("_20", "_100"), all = TRUE
)
cmp$anywhere_flipped <- (cmp$congruent_evidence_exists_anywhere_20 %in% FALSE) &
  (cmp$congruent_evidence_exists_anywhere_100 %in% TRUE)
cmp$action_changed <- cmp$reference_action_20 != cmp$reference_action_100

cat("\n================ max_hits 20 vs", WIDE_MAX_HITS, "================\n")
print(cmp[, c("accession", "listed_taxon", "hierarchy_flag_20", "hierarchy_flag_100",
              "n_top_matches_available_100", "n_independent_top_matches_20",
              "n_independent_top_matches_100", "anywhere_flipped",
              "reference_action_20", "reference_action_100")],
      row.names = FALSE)

cat("\n---- headline ----\n")
cat(sprintf("  'anywhere' flipped FALSE->TRUE: %d of %d\n",
            sum(cmp$anywhere_flipped, na.rm = TRUE), nrow(cmp)))
cat(sprintf("  reference_action changed:       %d\n",
            sum(cmp$action_changed, na.rm = TRUE)))
rm_lost <- cmp$accession[cmp$reference_action_20 %in% "remove" &
                           !(cmp$reference_action_100 %in% "remove")]
cat(sprintf("  'remove' no longer removable:   %d%s\n", length(rm_lost),
            if (length(rm_lost)) paste0(" -- ", paste(rm_lost, collapse = ", ")) else ""))
ctrl <- cmp[cmp$accession %in% controls, ]
cat(sprintf("  control(s) unchanged:           %s\n",
            if (all(!ctrl$action_changed %in% TRUE)) "YES" else "NO -- PROBE UNSOUND"))
cat(sprintf("  still saturated at %d hits:      %d\n", WIDE_MAX_HITS,
            sum(cmp$n_top_matches_available_100 >= WIDE_MAX_HITS - 1L, na.rm = TRUE)))

saveRDS(list(comparison = cmp, wide = wide, targets = targets,
             max_hits = WIDE_MAX_HITS, run_at = Sys.time()),
        file.path(dirname(PROBE_DIR), "veto_truncation_probe.rds"))
cat("\nsaved: diagnostics/veto_truncation_probe.rds\n")
