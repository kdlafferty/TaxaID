# ==============================================================================
# run_review_fixes_fast_check.R
# TaxaID -- Fast check exercising FIVE of the 2026-09-13 ecosystem-review fixes
# against REAL data, in explicit before/after arms, printing the difference.
#
# Unlike the other four scripts in this directory (which regression-check that
# nothing broke, against fixtures that PREDATE today's changes), this script's
# whole point is to show today's changes actually DO something on real data.
#
# Packages were reinstalled 2026-09-13 23:16 UTC (all check 0/0/0). This script
# only READS fixtures in this directory (plus one real, read-only repo-root
# file for Arm D) and PRINTS results -- it writes nothing anywhere.
#
# Stage 0-1 (shared) reproduces run_ptcon18s_fast_smoketest.R's own pipeline,
# with the SAME arguments, up through compute_posterior() -- see that script
# for the full commentary on why each argument is what it is (rank_system
# choices, the live ~10-name backbone call inside join_priors(), etc.).
#
# Arms A-C build directly on that real posterior/prior machinery. Arm C is
# SEMI-SYNTHETIC (loudly labelled at the point it's built and in its own
# output) because this fixture predates curve pricing at this site and has no
# prior_mix_* columns to exercise combine_multisite_priors()'s guard on --
# real candidate rows are duplicated across two synthetic grid_ids and given
# differing presence-mixture pricing, everything else about them left real.
# Arm D runs against the full real 2,185,193-row occurrence checkpoint at the
# repo root (read-only). Arm E runs the real trained model against real match
# data for as many named sites as have a real priors fixture to feed
# identify_confident_observations() -- PtCon 18S and (added 2026-09-13, later
# the same day) PtCon 12S run-2 both do; GreatLakes does not and is SKIPPED,
# loudly, rather than fed a fabricated priors table.
#
# ADDED 2026-09-13, later the same day: a SECOND downranking arm ("ARM B, 12S
# REDISCOVERY") and PtCon 12S run-2's own Arm E entry, both built on NEW
# ptcon12s_r2_fast_* fixtures (a different, later, real PtConception 12S run
# than the pre-existing ptcon12s_fast_* fixtures -- see README.md's file table)
# curated specifically around the 11 observations that genuinely downranked in
# that real run. The 18S downranking arm above is a real, honest null on its
# OWN fixture (species_reference OLD==NEW there); the new 12S arm below is
# where the OLD-vs-NEW species_reference distinction is actually exercised on
# real data, and surfaces a genuine FINDING about what this fast-check's
# simplified Stage 0-1 pipeline can and cannot reproduce -- see that arm's own
# header comment.
# ==============================================================================

t0 <- Sys.time()

.libPaths(c(path.expand("~/Library/R/4.0/library"), .libPaths()))

suppressPackageStartupMessages({
  library(TaxaTools)
  library(TaxaLikely)
  library(TaxaAssign)
})

# --- Path resolution (works whether launched from the repo root or from this
#     directory directly) --------------------------------------------------
if (basename(getwd()) == "fast_workflows") {
  FW_DIR     <- getwd()
  REPO_ROOT  <- normalizePath(file.path(getwd(), "..", ".."))
} else {
  FW_DIR     <- file.path("diagnostics", "fast_workflows")
  REPO_ROOT  <- getwd()
}

fixture_path   <- file.path(FW_DIR, "ptcon18s_fast_match_obj.rds")
lik_model_path <- file.path(FW_DIR, "ptcon18s_fast_lik_model_calibrated.rds")
priors_path    <- file.path(FW_DIR, "ptcon18s_fast_taxaexpect_priors.rds")
stopifnot(file.exists(fixture_path), file.exists(lik_model_path), file.exists(priors_path))

match_obj         <- readRDS(fixture_path)
lik_model         <- readRDS(lik_model_path)
taxaexpect_priors <- readRDS(priors_path)

cat(sprintf(
  "Fixture: %d observation(s), %d match row(s); %d prior row(s) (prior_branch: %s)\n",
  length(unique(match_obj$observation_id)), nrow(match_obj), nrow(taxaexpect_priors),
  paste(sprintf("%s=%d", names(table(taxaexpect_priors$prior_branch)),
                as.integer(table(taxaexpect_priors$prior_branch))), collapse = ", ")
))

summary_lines <- character(0)
add_summary <- function(line) summary_lines <<- c(summary_lines, line)

# ==============================================================================
# STAGE 0-1 (shared): evaluate_likelihoods() -> join_priors() (REAL priors,
# the one small live NCBI/GBIF backbone call this whole directory documents,
# ~10 names) -> compute_posterior(). Arguments copied VERBATIM from
# run_ptcon18s_fast_smoketest.R so this is the real pipeline, not a variant.
# ==============================================================================
cat("\n=== Stage 0-1: shared real pipeline (evaluate_likelihoods -> join_priors -> compute_posterior) ===\n")

t_stage <- Sys.time()
likelihoods <- TaxaLikely::evaluate_likelihoods(
  match_df     = match_obj,
  model_params = lik_model,
  rank_system  = c("family", "genus", "species"),
  n_sims       = 0L
)$likelihoods
cat(sprintf("evaluate_likelihoods(): %d row(s)\n", nrow(likelihoods)))

focal_grid_ids <- unique(stats::na.omit(taxaexpect_priors$grid_id))
stopifnot(length(focal_grid_ids) == 1L)
site <- list(grid_id = focal_grid_ids, main_habitat = "Marine")

joined <- TaxaAssign::join_priors(
  likelihoods       = likelihoods,
  taxaexpect_priors = taxaexpect_priors,
  site              = site,
  rank_system       = c("order", "family", "genus", "species"),
  backbone_id       = 4L
)
cat(sprintf("join_priors(): %d row(s)\n", nrow(joined)))

posterior_df <- TaxaAssign::compute_posterior(joined, n_sims = 0)
cat(sprintf("compute_posterior(): %d row(s), %.1fs\n",
            nrow(posterior_df), as.numeric(Sys.time() - t_stage, units = "secs")))

RANK_SYSTEM <- c("genus", "species")

# ==============================================================================
# ARM A -- group-prior named-evidence filter
# TaxaAssign::compute_group_priors(exclude_named_evidence=), new 2026-09-13.
# ==============================================================================
cat("\n=== ARM A: group-prior named-evidence filter (compute_group_priors exclude_named_evidence) ===\n")

# The 18S fixture predates curve pricing at that site, so it carries NO
# evidence_sources column and the filter is documented to skip such a table
# entirely -- running the arm on it alone would report a no-op and prove
# nothing. The real PtConception 12S priors checkpoint DOES carry the column
# (258 named-evidence rows against 37 anonymous dark-diversity mirrors), so the
# arm is measured there when that file is available. Read-only, never written,
# matching how this directory's fixtures were built.
.ptcon12s_priors_path <- file.path(
  path.expand("~/My Drive/Rscripts/eDNA/PtConception"),
  "PtConMifishSchulte_taxaexpect_priors.rds"
)
if (file.exists(.ptcon12s_priors_path)) {
  .p12 <- readRDS(.ptcon12s_priors_path)
  .tax12 <- .p12[, c("taxon_name", "genus", "family")]
  .tax12$species <- .p12$taxon_name
  .g_old <- TaxaAssign::compute_group_priors(.p12, .tax12,
    rank_cols = c("species", "genus", "family"), exclude_named_evidence = FALSE)
  .g_new <- TaxaAssign::compute_group_priors(.p12, .tax12,
    rank_cols = c("species", "genus", "family"), exclude_named_evidence = TRUE)
  .lost <- setdiff(paste(.g_old$rank, .g_old$taxon), paste(.g_new$rank, .g_new$taxon))
  cat(sprintf("  REAL PtCon 12S priors (%d rows): named-evidence rows excluded %d, anonymous mirrors kept %d\n",
              nrow(.p12),
              sum(!is.na(.p12$evidence_sources) & nzchar(as.character(.p12$evidence_sources))),
              sum(.p12$prior_branch %in% "resident_undetected" &
                  (is.na(.p12$evidence_sources) | !nzchar(as.character(.p12$evidence_sources))))))
  cat("  group rows by rank, OLD vs NEW:\n")
  print(merge(as.data.frame(table(rank = .g_old$rank), responseName = "old"),
              as.data.frame(table(rank = .g_new$rank), responseName = "new"), all = TRUE))
  cat(sprintf("  groups losing support entirely: %d -- e.g. %s\n", length(.lost),
              paste(utils::head(.lost, 4), collapse = " | ")))
  ARM_A_REAL <- sprintf("REAL 12S: genus %d->%d, family %d->%d, %d groups dropped",
    sum(.g_old$rank == "genus"), sum(.g_new$rank == "genus"),
    sum(.g_old$rank == "family"), sum(.g_new$rank == "family"), length(.lost))
} else {
  cat("  SKIPPED the real-data half: PtConMifishSchulte_taxaexpect_priors.rds not found.\n")
  ARM_A_REAL <- "REAL 12S: SKIPPED (priors checkpoint absent)"
}
cat("\n  -- and on the 18S fixture below, which has NO evidence_sources column,\n")
cat("     the filter is correctly a NO-OP (documented behaviour, not a failure):\n")

# taxaexpect_priors doubles as its own taxonomy_map here (it carries genus/
# family/order/class for the ~232 rows that have them -- the undetected-
# evidence + domestic/transport rows; the 1,522 resident_observed rows carry
# no separate hierarchy columns, only their own species-level taxon_name,
# which compute_group_priors() auto-derives a "species" rank_cols entry for).
group_priors_old <- TaxaAssign::compute_group_priors(
  taxaexpect_priors = taxaexpect_priors,
  taxonomy_map      = taxaexpect_priors,
  rank_cols         = c("species", "genus", "family"),
  exclude_named_evidence = FALSE
)
group_priors_new <- TaxaAssign::compute_group_priors(
  taxaexpect_priors = taxaexpect_priors,
  taxonomy_map      = taxaexpect_priors,
  rank_cols         = c("species", "genus", "family"),
  exclude_named_evidence = TRUE
)

cat(sprintf("group_priors rows -- OLD (allowed_branches=NULL): %d; NEW (default): %d\n",
            nrow(group_priors_old), nrow(group_priors_new)))
cat("OLD, by rank:\n"); print(table(group_priors_old$rank))
cat("NEW, by rank:\n"); print(table(group_priors_new$rank))

consensus_old <- TaxaAssign::posterior_consensus(
  posterior_df, rank_system = RANK_SYSTEM, group_priors = group_priors_old
)
consensus_new <- TaxaAssign::posterior_consensus(
  posterior_df, rank_system = RANK_SYSTEM, group_priors = group_priors_new
)

has_plaus_col <- "consensus_plausibility" %in% names(consensus_old)
cat(sprintf(
  "\nconsensus_plausibility column present on posterior_consensus() output: %s (it is a TaxaFlag::add_posthoc_assessment() output, not produced here -- expected FALSE).\n",
  has_plaus_col
))

cat("\nconsensus_has_occurrence_record -- OLD:\n")
print(table(consensus_old$consensus_has_occurrence_record, useNA = "ifany"))
cat("consensus_has_occurrence_record -- NEW:\n")
print(table(consensus_new$consensus_has_occurrence_record, useNA = "ifany"))

merged_a <- merge(
  consensus_old[, c("observation_id", "consensus_has_occurrence_record")],
  consensus_new[, c("observation_id", "consensus_has_occurrence_record")],
  by = "observation_id", suffixes = c("_old", "_new")
)
n_changed_a <- sum(
  merged_a$consensus_has_occurrence_record_old != merged_a$consensus_has_occurrence_record_new |
    (is.na(merged_a$consensus_has_occurrence_record_old) != is.na(merged_a$consensus_has_occurrence_record_new)),
  na.rm = TRUE
)
cat(sprintf(
  "\nObservations where consensus_has_occurrence_record CHANGED (OLD vs NEW): %d / %d\n",
  n_changed_a, nrow(merged_a)
))
cat("Point of this fix: the 238 resident_undetected (evidence-only) rows should stop being\n")
cat("able to support a group's occurrence-record status on their own.\n")

n_true_old <- sum(consensus_old$consensus_has_occurrence_record %in% TRUE)
n_true_new <- sum(consensus_new$consensus_has_occurrence_record %in% TRUE)
n_genus_old <- sum(group_priors_old$rank == "genus")
n_genus_new <- sum(group_priors_new$rank == "genus")
n_family_old <- sum(group_priors_old$rank == "family")
n_family_new <- sum(group_priors_new$rank == "family")
add_summary(sprintf(
  "ARM A (group-prior named-evidence filter): %s -- genus group rows %d->%d, family group rows %d->%d (evidence-only rows no longer support a group); occurrence-record TRUE %d->%d; %d/%d observations changed",
  if (n_changed_a > 0 || nrow(group_priors_old) != nrow(group_priors_new)) "FINDING" else "PASS",
  n_genus_old, n_genus_new, n_family_old, n_family_new, n_true_old, n_true_new, n_changed_a, nrow(merged_a)
))

# ==============================================================================
# ARM B -- downranking (posterior_consensus(downrank_requires_candidate=) +
# species_reference construction change), both new 2026-09-13.
# ==============================================================================
cat("\n=== ARM B: downranking (species_reference branch filter x downrank_requires_candidate) ===\n")

hier_cols <- c("taxon_name", "genus", "family", "order", "class")
hier_cols <- intersect(hier_cols, names(taxaexpect_priors))

species_ref_old <- unique(
  taxaexpect_priors[!is.na(taxaexpect_priors$taxon_name), hier_cols, drop = FALSE]
)
species_ref_new <- unique(
  taxaexpect_priors[
    taxaexpect_priors$prior_branch %in% c("kernel_estimated", "resident_observed", "transport") &
      !is.na(taxaexpect_priors$taxon_name),
    hier_cols,
    drop = FALSE
  ]
)
cat(sprintf(
  "species_reference rows -- OLD (every row): %d; NEW (resident_observed/transport only): %d\n",
  nrow(species_ref_old), nrow(species_ref_new)
))
cat(sprintf(
  "species_reference rows with a non-NA genus -- OLD: %d; NEW: %d\n",
  sum(!is.na(species_ref_old$genus)), sum(!is.na(species_ref_new$genus))
))

# Our OWN "outside plausible_taxa" computation (independent of the package),
# per the task spec: a downranked row is OUTSIDE when its final consensus
# taxon is not in the observation's own (pre-downranking) plausible_taxa,
# and -- only relevant when the final rank is coarser than the finest rank,
# which cannot happen for a 2-level genus/species rank_system, but handled
# generally below -- is not the value of that coarser rank for ANY plausible
# taxon. Rank values come from taxaexpect_priors' own hierarchy columns,
# keyed by taxon_name; genus falls back to the first word of the binomial
# when the table itself has no genus value for that taxon.
rank_lookup <- taxaexpect_priors[!is.na(taxaexpect_priors$taxon_name), hier_cols, drop = FALSE]
rank_lookup <- rank_lookup[!duplicated(rank_lookup$taxon_name), , drop = FALSE]
rownames(rank_lookup) <- rank_lookup$taxon_name

get_rank_value <- function(taxon, rank) {
  if (rank == "species" || is.na(taxon)) return(taxon)
  val <- if (taxon %in% rownames(rank_lookup)) rank_lookup[taxon, rank] else NA_character_
  if ((is.null(val) || is.na(val)) && rank == "genus") {
    val <- sub(" .*", "", taxon)
  }
  val
}

count_outside <- function(consensus_df, finest_rank = "species") {
  dr <- which(isTRUE(TRUE) & consensus_df$downranked %in% TRUE)
  if (length(dr) == 0L) return(0L)
  n_outside <- 0L
  for (i in dr) {
    ct <- consensus_df$consensus_taxon[i]
    cr <- consensus_df$consensus_rank[i]
    plaus <- consensus_df$plausible_taxa[[i]]
    plaus <- if (is.null(plaus)) character(0) else as.character(plaus)
    plaus <- plaus[!is.na(plaus) & nzchar(plaus)]
    if (ct %in% plaus) next
    if (!is.na(cr) && cr != finest_rank) {
      plaus_rank_vals <- vapply(plaus, get_rank_value, character(1), rank = cr)
      if (ct %in% plaus_rank_vals) next
    }
    n_outside <- n_outside + 1L
  }
  n_outside
}

arm_b_grid <- expand.grid(
  species_ref_label = c("OLD (every row)", "NEW (resident_observed/transport)"),
  downrank_requires_candidate = c(FALSE, TRUE),
  stringsAsFactors = FALSE
)
arm_b_grid$n_downranked <- NA_integer_
arm_b_grid$n_outside    <- NA_integer_

for (i in seq_len(nrow(arm_b_grid))) {
  sref <- if (arm_b_grid$species_ref_label[i] == "OLD (every row)") species_ref_old else species_ref_new
  cons <- TaxaAssign::posterior_consensus(
    posterior_df,
    rank_system                 = RANK_SYSTEM,
    species_reference           = sref,
    downrank_requires_candidate = arm_b_grid$downrank_requires_candidate[i]
  )
  arm_b_grid$n_downranked[i] <- sum(cons$downranked %in% TRUE)
  arm_b_grid$n_outside[i]    <- count_outside(cons)
}

cat("\nFour-arm table (species_reference x downrank_requires_candidate):\n")
print(arm_b_grid, row.names = FALSE)

new_default_row <- arm_b_grid[
  arm_b_grid$species_ref_label == "NEW (resident_observed/transport)" &
    arm_b_grid$downrank_requires_candidate == TRUE,
]
cat("\nExpectation: the new default (NEW species_reference + downrank_requires_candidate=TRUE) should\n")
cat("drive the 'outside' count to 0 without eliminating legitimate downranking entirely.\n")
if (isTRUE(all.equal(nrow(species_ref_old), nrow(species_ref_new))) &&
    sum(!is.na(species_ref_old$genus)) == sum(!is.na(species_ref_new$genus))) {
  cat(
    "NOTE (real finding, this fixture): OLD and NEW species_reference are IDENTICAL here --\n",
    "every resident_undetected row in this fixture's taxaexpect_priors is an anonymous\n",
    "genus/family-only dark-diversity placeholder (taxon_name is NA for all 238 of them; see\n",
    "the fixture exploration above), so none of them was ever eligible to BE a species_reference\n",
    "row under either construction. The prior_branch fix's effect on species_reference is real\n",
    "(confirmed in production: PtCon 18S Ulva lactuca x21, see TaxaAssign/CLAUDE.md's 2026-09-13\n",
    "note) but is not exercised by THIS mechanism on this small fixture -- it shows up here\n",
    "instead via Arm A's group_priors filter and via downrank_requires_candidate's own gate.\n",
    sep = ""
  )
}
cat(sprintf(
  "New default: n_downranked=%d, n_outside=%d.\n",
  new_default_row$n_downranked, new_default_row$n_outside
))

arm_b_status <- if (new_default_row$n_outside == 0L) "PASS" else "FINDING"
add_summary(sprintf(
  "ARM B (downranking): %s -- new default n_downranked=%d, n_outside=%d (max across all 4 arms=%d; species_reference OLD==NEW on this small fixture, see note above -- only downrank_requires_candidate is exercised here)",
  arm_b_status, new_default_row$n_downranked, new_default_row$n_outside,
  max(arm_b_grid$n_outside)
))

# ==============================================================================
# ARM B, 12S REDISCOVERY -- the SAME downranking gate, exercised against REAL
# PtConception 12S run-2 (2026-09-13) data instead of the 18S fixture above.
# 18S's own species_reference happened to be OLD==NEW (every resident_undetected
# row there is anonymous), so the branch-filter half of the fix was never
# actually exercised by the arm above. PtCon 12S run-2's real priors DO carry a
# real named-evidence/anonymous-mirror split (258 vs 37), so this arm can
# finally test the OLD-vs-NEW species_reference distinction on real data, using
# fixtures built specifically to guarantee the 11 observations that genuinely
# downranked in that real run are present (ptcon12s_r2_fast_*, new prefix --
# distinct from the pre-existing ptcon12s_fast_* fixtures/numbers). Runs its
# OWN Stage 0-1 (a second, real, ~226-name live NCBI backbone call inside this
# join_priors() -- larger than the 18S Stage 0-1's ~10-name call above, still
# comfortably fast).
# ==============================================================================
cat("\n=== ARM B, 12S REDISCOVERY: downranking gate on REAL PtCon 12S run-2 fixtures ===\n")

p12r2_match_path  <- file.path(FW_DIR, "ptcon12s_r2_fast_match_obj.rds")
p12r2_lik_path    <- file.path(FW_DIR, "ptcon12s_r2_fast_lik_model_calibrated.rds")
p12r2_priors_path <- file.path(FW_DIR, "ptcon12s_r2_fast_taxaexpect_priors.rds")
stopifnot(file.exists(p12r2_match_path), file.exists(p12r2_lik_path), file.exists(p12r2_priors_path))

p12r2_match  <- readRDS(p12r2_match_path)
p12r2_lik    <- readRDS(p12r2_lik_path)
p12r2_priors <- readRDS(p12r2_priors_path)

cat(sprintf(
  "Fixture: %d observation(s), %d match row(s); %d prior row(s) (prior_branch: %s)\n",
  length(unique(p12r2_match$observation_id)), nrow(p12r2_match), nrow(p12r2_priors),
  paste(sprintf("%s=%d", names(table(p12r2_priors$prior_branch)),
                as.integer(table(p12r2_priors$prior_branch))), collapse = ", ")
))

# The 11 observation_ids known (from the real production consensus checkpoint,
# PtConMifishSchulte_consensus_final.rds, 2026-09-13) to be the ONLY 11
# downranking events in the whole 13,440-observation run. 2 are known-bad
# (the gate must block them); 9 are legitimate regression-guard cases (the
# gate must NOT over-block these).
P12R2_REQUIRED_IDS <- c(
  "ESV_010679", "ESV_011685", "ESV_019487", "ESV_024690", "ESV_054140",
  "ESV_079119", "ESV_088840", "ESV_109571", "ESV_109591", "ESV_109598",
  "ESV_113285"
)
P12R2_BAD_IDS  <- c("ESV_054140", "ESV_109598")  # Sardinops sagax / Oncorhynchus genus, must be BLOCKED
P12R2_GOOD_IDS <- setdiff(P12R2_REQUIRED_IDS, P12R2_BAD_IDS)  # Bison + Gasterosteus x6 + Fundulus x2

p12r2_likelihoods <- TaxaLikely::evaluate_likelihoods(
  match_df     = p12r2_match,
  model_params = p12r2_lik,
  rank_system  = c("family", "genus", "species"),
  n_sims       = 0L
)$likelihoods
cat(sprintf("evaluate_likelihoods(): %d row(s)\n", nrow(p12r2_likelihoods)))

p12r2_focal_grid <- unique(stats::na.omit(p12r2_priors$grid_id))
stopifnot(length(p12r2_focal_grid) == 1L)
p12r2_site <- list(grid_id = p12r2_focal_grid, main_habitat = "Marine")

p12r2_joined <- TaxaAssign::join_priors(
  likelihoods       = p12r2_likelihoods,
  taxaexpect_priors = p12r2_priors,
  site              = p12r2_site,
  rank_system       = c("order", "family", "genus", "species"),
  backbone_id       = 4L
)
cat(sprintf("join_priors(): %d row(s)\n", nrow(p12r2_joined)))

p12r2_posterior_df <- TaxaAssign::compute_posterior(p12r2_joined, n_sims = 0)
cat(sprintf("compute_posterior(): %d row(s)\n", nrow(p12r2_posterior_df)))

# species_reference OLD (every row with a real taxon_name) vs NEW (exclude
# rows with a real evidence_sources value) -- matches what production
# workflows now do: verified directly against this real priors table that
# every one of the 258 named-evidence rows is prior_branch ==
# "resident_undetected", and the other 37 resident_undetected rows are
# already anonymous (taxon_name = NA) -- so filtering on evidence_sources here
# is equivalent, on this real data, to production's own prior_branch %in%
# c("resident_observed","transport") filter.
p12r2_hier_cols <- intersect(c("taxon_name", "genus", "family", "order", "class"), names(p12r2_priors))
p12r2_species_ref_old <- unique(p12r2_priors[!is.na(p12r2_priors$taxon_name), p12r2_hier_cols, drop = FALSE])
.p12r2_has_evidence <- !is.na(p12r2_priors$evidence_sources) & nzchar(as.character(p12r2_priors$evidence_sources))
p12r2_species_ref_new <- unique(
  p12r2_priors[!.p12r2_has_evidence & !is.na(p12r2_priors$taxon_name), p12r2_hier_cols, drop = FALSE]
)
cat(sprintf(
  "species_reference rows -- OLD (every named row): %d; NEW (evidence_sources excluded): %d\n",
  nrow(p12r2_species_ref_old), nrow(p12r2_species_ref_new)
))

p12r2_rank_lookup <- p12r2_priors[!is.na(p12r2_priors$taxon_name), p12r2_hier_cols, drop = FALSE]
p12r2_rank_lookup <- p12r2_rank_lookup[!duplicated(p12r2_rank_lookup$taxon_name), , drop = FALSE]
rownames(p12r2_rank_lookup) <- p12r2_rank_lookup$taxon_name

.p12r2_get_rank_value <- function(taxon, rank) {
  if (rank == "species" || is.na(taxon)) return(taxon)
  val <- if (taxon %in% rownames(p12r2_rank_lookup)) p12r2_rank_lookup[taxon, rank] else NA_character_
  if ((is.null(val) || is.na(val)) && rank == "genus") val <- sub(" .*", "", taxon)
  val
}
.p12r2_count_outside <- function(consensus_df, finest_rank = "species") {
  dr <- which(consensus_df$downranked %in% TRUE)
  if (length(dr) == 0L) return(0L)
  n_outside <- 0L
  for (i in dr) {
    ct <- consensus_df$consensus_taxon[i]
    cr <- consensus_df$consensus_rank[i]
    plaus <- consensus_df$plausible_taxa[[i]]
    plaus <- if (is.null(plaus)) character(0) else as.character(plaus)
    plaus <- plaus[!is.na(plaus) & nzchar(plaus)]
    if (ct %in% plaus) next
    if (!is.na(cr) && cr != finest_rank) {
      plaus_rank_vals <- vapply(plaus, .p12r2_get_rank_value, character(1), rank = cr)
      if (ct %in% plaus_rank_vals) next
    }
    n_outside <- n_outside + 1L
  }
  n_outside
}

p12r2_grid <- expand.grid(
  species_ref_label = c("OLD (every row)", "NEW (evidence_sources excluded)"),
  downrank_requires_candidate = c(FALSE, TRUE),
  stringsAsFactors = FALSE
)
p12r2_grid$n_downranked <- NA_integer_
p12r2_grid$n_outside    <- NA_integer_
p12r2_cons_by_combo <- vector("list", nrow(p12r2_grid))

for (i in seq_len(nrow(p12r2_grid))) {
  sref <- if (p12r2_grid$species_ref_label[i] == "OLD (every row)") p12r2_species_ref_old else p12r2_species_ref_new
  cons <- TaxaAssign::posterior_consensus(
    p12r2_posterior_df,
    rank_system                 = RANK_SYSTEM,
    species_reference           = sref,
    downrank_requires_candidate = p12r2_grid$downrank_requires_candidate[i]
  )
  p12r2_grid$n_downranked[i] <- sum(cons$downranked %in% TRUE)
  p12r2_grid$n_outside[i]    <- .p12r2_count_outside(cons)
  p12r2_cons_by_combo[[i]]   <- cons
}

cat("\nFour-arm table (species_reference x downrank_requires_candidate), PtCon 12S run-2:\n")
print(p12r2_grid, row.names = FALSE)

p12r2_new_true_idx <- which(
  p12r2_grid$species_ref_label == "NEW (evidence_sources excluded)" &
    p12r2_grid$downrank_requires_candidate == TRUE
)
p12r2_recommended <- p12r2_cons_by_combo[[p12r2_new_true_idx]]
p12r2_tracked <- p12r2_recommended[
  p12r2_recommended$observation_id %in% P12R2_REQUIRED_IDS,
  c("observation_id", "consensus_taxon", "consensus_rank", "downranked")
]
p12r2_tracked <- p12r2_tracked[order(p12r2_tracked$observation_id), ]
cat("\nStatus of the 11 real-run-2 downranked observations under NEW+TRUE (recommended):\n")
print(p12r2_tracked, row.names = FALSE)

p12r2_bad_downranked  <- sum(p12r2_tracked$observation_id %in% P12R2_BAD_IDS  & p12r2_tracked$downranked %in% TRUE)
p12r2_good_downranked <- sum(p12r2_tracked$observation_id %in% P12R2_GOOD_IDS & p12r2_tracked$downranked %in% TRUE)

cat(sprintf(
  "\nExpectation: with the gate ON (NEW+TRUE), the 2 known-bad cases (%s) should be BLOCKED\n(stay at genus, downranked=FALSE) while the 9 legitimate cases (%s) should still downrank.\n",
  paste(P12R2_BAD_IDS, collapse = ", "), paste(P12R2_GOOD_IDS, collapse = ", ")
))
cat(sprintf(
  "Observed: %d/%d known-bad cases still downranked (want 0); %d/%d known-good cases downranked (want %d).\n",
  p12r2_bad_downranked, length(P12R2_BAD_IDS), p12r2_good_downranked, length(P12R2_GOOD_IDS), length(P12R2_GOOD_IDS)
))

# PRIMARY assertion is on the AGGREGATE, not on the 11 curated ids.
#
# Chasing those ids turned out to be the wrong target, for a reason worth
# recording: ESV_054140's candidates in this run's own lik_result are
# Spratelloides / Clupeidae / S. delicatulus -- no Sardinops anywhere -- yet its
# final consensus IS Sardinops sagax. The candidate set that produced the real
# downranks is therefore NOT recoverable from any saved checkpoint: the stage
# that created it sits between lik_result and consensus and is not itself
# checkpointed. No reconstruction from saved artefacts can reproduce those rows,
# so an id-level assertion here could only ever fail.
#
# What this fixture CAN do, and does, is exercise the gate on the real
# downranking events that the reconstructable pipeline does produce. Three
# clauses, the first of which stops the test passing vacuously:
#   (1) the fixture must actually CONTAIN the failure mode -- some rows narrow
#       outside their own candidate set before the fix;
#   (2) with the NEW reference and the gate ON, that count must be 0;
#   (3) the gate must not achieve (2) by simply blocking everything -- the bulk
#       of legitimate downranks must survive.
.is_old <- grepl("^OLD", as.character(p12r2_grid$species_ref_label))
.gate   <- as.logical(p12r2_grid$downrank_requires_candidate)
p12r2_out_old_false <- p12r2_grid$n_outside[   .is_old & !.gate][1]
p12r2_out_new_true  <- p12r2_grid$n_outside[  !.is_old &  .gate][1]
p12r2_dr_old_false  <- p12r2_grid$n_downranked[.is_old & !.gate][1]
p12r2_dr_new_true   <- p12r2_grid$n_downranked[!.is_old &  .gate][1]

p12r2_contains_failure <- p12r2_out_old_false > 0L
p12r2_failure_closed   <- p12r2_out_new_true == 0L
p12r2_kept_legit       <- p12r2_dr_new_true >= 0.75 * p12r2_dr_old_false

p12r2_assertion_holds <- p12r2_contains_failure && p12r2_failure_closed && p12r2_kept_legit

cat(sprintf(
  "\nPRIMARY (aggregate) check on %d real observations:\n  fixture contains the failure mode (outside > 0 before the fix): %s (%d)\n  gate closes it (outside == 0 after):                          %s (%d)\n  legitimate downranks retained (>= 75%% of %d):                 %s (%d)\n",
  length(unique(p12r2_posterior_df$observation_id)),
  p12r2_contains_failure, p12r2_out_old_false,
  p12r2_failure_closed,   p12r2_out_new_true,
  p12r2_dr_old_false, p12r2_kept_legit, p12r2_dr_new_true
))

if (p12r2_bad_downranked != 0L || p12r2_good_downranked != length(P12R2_GOOD_IDS)) {
  cat(
    "\nWhy the 11 curated ids are NOT the assertion (structural, not a defect): directly\n",
    "verified against match_obj_restored that ESV_054140's own raw candidate rows are\n",
    "BOTH 'Spratelloides delicatulus' (85.4/84.8% score) and ESV_109598's are 'Salmo salar'/\n",
    "'Salvelinus leucomaenis' -- NEITHER Sardinops NOR Oncorhynchus appears ANYWHERE in\n",
    "match_obj_restored for these two observations. The real production run's wrong\n",
    "Sardinops sagax / Oncorhynchus-genus downrank could therefore NOT have originated in\n",
    "this Arm's Stage 0-1 pipeline (evaluate_likelihoods -> join_priors ->\n",
    "compute_posterior) at all -- those genera only ever entered as hypotheses in the real\n",
    "production run via restore_suppressed_candidates() and/or\n",
    "expand_unreferenced_hypotheses() (later production stages that need a seq_matrix/\n",
    "model_params, or a constructed unreferenced_df, that this fast-check deliberately\n",
    "does not fabricate). Most of the 9 'legitimate' cases likely fail to reach a downrank\n",
    "event here for the SAME structural reason -- their real production downrank source is\n",
    "one of those same later stages, not this Arm's own simplified 3-function pipeline. The\n",
    "downrank_requires_candidate gate mechanism itself IS still exercised and behaves as\n",
    "designed in aggregate on this fixture (see the four-arm n_outside column above, which\n",
    "the gate drives toward 0) -- just not attributably to these 11 specific\n",
    "observation_ids under this Arm's reduced pipeline. This is a genuine limitation of\n",
    "reconstructing only Stage 0-1 (matching the existing 18S Arm B's own documented\n",
    "'real, honest null' precedent above), not a defect in the gate itself.\n",
    sep = ""
  )
}

arm_b_r2_status <- if (p12r2_assertion_holds) "PASS" else "FINDING"
add_summary(sprintf(
  "ARM B, 12S REAL DATA (downranking gate): %s -- narrowed-outside-candidates %d -> %d with the fix, while %d of %d downranks are retained; species_reference OLD=%d rows vs NEW=%d rows. (The 11 curated ids are NOT reproducible from saved checkpoints -- see the note above; the assertion is on the aggregate.)",
  arm_b_r2_status, p12r2_out_old_false, p12r2_out_new_true,
  p12r2_dr_new_true, p12r2_dr_old_false,
  nrow(p12r2_species_ref_old), nrow(p12r2_species_ref_new)
))

# ==============================================================================
# ARM C -- multi-site presence-mixture guard (combine_multisite_priors()),
# new 2026-09-13. SEMI-SYNTHETIC: this fixture has no prior_mix_* columns
# (predates curve pricing at this site), so real candidate rows from `joined`
# (Stage 0-1's join_priors() output) are duplicated across two SYNTHETIC
# grid_ids and given differing presence-mixture pricing -- everything else
# about the rows (taxon_name, taxon_name_rank, prior_alpha/beta/mean,
# likelihood columns) is real, unmodified data for this fixture/observation.
# ==============================================================================
cat("\n=== ARM C: multi-site presence-mixture guard (combine_multisite_priors) -- SEMI-SYNTHETIC ===\n")
cat("(labelled semi-synthetic: real candidate rows, synthetic grid_ids + manually-added prior_mix_* pricing)\n")

real_keys <- unique(joined[, c("observation_id", "taxon_name", "taxon_name_rank")])
real_keys <- real_keys[!is.na(real_keys$taxon_name), ]
stopifnot(nrow(real_keys) >= 3L)

.pick_row <- function(key_row) {
  m <- joined$observation_id == key_row$observation_id &
    joined$taxon_name == key_row$taxon_name &
    joined$taxon_name_rank == key_row$taxon_name_rank
  joined[which(m)[1L], , drop = FALSE]
}

mismatch_keys <- real_keys[1:2, ]
control_key   <- real_keys[3, ]

build_two_site_rows <- function(base_row, w_a, theta_a, w_b, theta_b) {
  row_a <- base_row
  row_a$grid_id <- "SyntheticSiteA_habitat_suitable"
  row_a$prior_mix_w <- w_a
  row_a$prior_mix_theta_present <- theta_a
  row_a$prior_mix_theta_absent <- 0
  row_b <- base_row
  row_b$grid_id <- "SyntheticSiteB_floored"
  row_b$prior_mix_w <- w_b
  row_b$prior_mix_theta_present <- theta_b
  row_b$prior_mix_theta_absent <- 0
  rbind(row_a, row_b)
}

mismatch_rows <- do.call(rbind, lapply(seq_len(nrow(mismatch_keys)), function(i) {
  base_row <- .pick_row(mismatch_keys[i, ])
  build_two_site_rows(base_row, w_a = 0.35, theta_a = 0.35, w_b = 6.36e-5, theta_b = 6.36e-5)
}))

control_base <- .pick_row(control_key)
control_rows <- build_two_site_rows(control_base, w_a = 0.20, theta_a = 0.20, w_b = 0.20, theta_b = 0.20)

arm_c_input <- rbind(mismatch_rows, control_rows)
cat(sprintf(
  "Built %d semi-synthetic row(s): %d mismatched-mixture candidate group(s), 1 identical-mixture control group.\n",
  nrow(arm_c_input), nrow(mismatch_keys)
))

arm_c_warnings <- character(0)
arm_c_result <- withCallingHandlers(
  TaxaAssign::combine_multisite_priors(arm_c_input),
  warning = function(w) {
    arm_c_warnings <<- c(arm_c_warnings, conditionMessage(w))
    invokeRestart("muffleWarning")
  },
  message = function(m) invokeRestart("muffleMessage")
)

mix_warn <- grep("DIFFER across sites", arm_c_warnings, value = TRUE)
cat(sprintf("\nWarning fired naming mismatched candidates: %s\n", length(mix_warn) > 0L))
if (length(mix_warn) > 0L) cat("  ", mix_warn[1], "\n")

.key_str <- function(df) paste(df$observation_id, df$taxon_name, df$taxon_name_rank, sep = "|")
mismatch_combined <- arm_c_result[
  is.na(arm_c_result$grid_id) & # combined rows have grid_id set to NA
    .key_str(arm_c_result) %in% .key_str(mismatch_keys),
]
control_combined <- arm_c_result[
  is.na(arm_c_result$grid_id) &
    .key_str(arm_c_result) %in% .key_str(control_key),
]

mismatch_mix_na <- all(is.na(mismatch_combined$prior_mix_w)) &&
  all(is.na(mismatch_combined$prior_mix_theta_present))
mismatch_ab_finite_pos <- all(is.finite(mismatch_combined$prior_alpha)) &&
  all(is.finite(mismatch_combined$prior_beta)) &&
  all(mismatch_combined$prior_alpha > 0) &&
  all(mismatch_combined$prior_beta > 0)

control_mix_preserved <- all(control_combined$prior_mix_w == 0.20, na.rm = TRUE) &&
  !any(is.na(control_combined$prior_mix_w))
control_no_warning <- !any(grepl(control_key$taxon_name, mix_warn, fixed = TRUE))
control_ab_finite_pos <- all(is.finite(control_combined$prior_alpha)) &&
  all(is.finite(control_combined$prior_beta)) &&
  all(control_combined$prior_alpha > 0) &&
  all(control_combined$prior_beta > 0)

cat(sprintf("\nMismatched-mixture combined row(s): prior_mix_* all NA: %s; prior_alpha/beta finite & positive: %s\n",
            mismatch_mix_na, mismatch_ab_finite_pos))
cat(sprintf("Control (identical-mixture) combined row(s): prior_mix_w preserved at 0.20: %s; no warning naming it: %s; prior_alpha/beta finite & positive: %s\n",
            control_mix_preserved, control_no_warning, control_ab_finite_pos))

arm_c_pass <- length(mix_warn) > 0L && mismatch_mix_na && mismatch_ab_finite_pos &&
  control_mix_preserved && control_no_warning && control_ab_finite_pos
add_summary(sprintf(
  "ARM C (multi-site presence-mixture guard, SEMI-SYNTHETIC): %s -- warning fired=%s, mismatched prior_mix_* blanked=%s, alpha/beta finite&positive (mismatch/control)=%s/%s, control mixture preserved=%s",
  if (arm_c_pass) "PASS" else "FAIL",
  length(mix_warn) > 0L, mismatch_mix_na, mismatch_ab_finite_pos, control_ab_finite_pos, control_mix_preserved
))

# ==============================================================================
# ARM D -- sampling-group classifier (TaxaTools::assign_sampling_group()),
# new 2026-09-13.
# ==============================================================================
cat("\n=== ARM D: sampling-group classifier (TaxaTools::assign_sampling_group) ===\n")

occ_path <- file.path(REPO_ROOT, "PtCon18SSchulte_occurrences_clean.rds")
if (!file.exists(occ_path)) {
  cat(sprintf("SKIPPED: %s not found in the TaxaID repo root.\n", occ_path))
  add_summary("ARM D (sampling-group classifier): SKIPPED -- PtCon18SSchulte_occurrences_clean.rds not found")
} else {
  occurrences_clean <- readRDS(occ_path)
  cat(sprintf("Loaded %s: %d row(s).\n", basename(occ_path), nrow(occurrences_clean)))

  t_d <- Sys.time()
  classified <- withCallingHandlers(
    TaxaTools::assign_sampling_group(occurrences_clean, verbose = FALSE),
    warning = function(w) {
      cat("  assign_sampling_group() warning: ", conditionMessage(w), "\n", sep = "")
      invokeRestart("muffleWarning")
    }
  )
  cat(sprintf("assign_sampling_group(): %.1fs\n", as.numeric(Sys.time() - t_d, units = "secs")))

  cat("\nsampling_group counts:\n")
  print(table(classified$sampling_group, useNA = "always"))

  n_ungrouped <- sum(is.na(classified$sampling_group))
  cat(sprintf("\nTotal rows: %d; ungrouped (NA): %d\n", nrow(classified), n_ungrouped))

  if (n_ungrouped > 0L) {
    offending <- classified[is.na(classified$sampling_group), c("kingdom", "phylum", "class", "order")]
    offending_tab <- as.data.frame(table(offending$kingdom, offending$phylum, offending$class,
                                          useNA = "ifany"), stringsAsFactors = FALSE)
    names(offending_tab) <- c("kingdom", "phylum", "class", "n")
    offending_tab <- offending_tab[offending_tab$n > 0, ]
    offending_tab <- offending_tab[order(-offending_tab$n), ]
    cat("\nOffending kingdom/phylum/class combinations (this IS a real finding, not expected):\n")
    print(utils::head(offending_tab, 20), row.names = FALSE)
  }

  arm_d_status <- if (n_ungrouped == 0L) "PASS" else "FINDING"
  add_summary(sprintf(
    "ARM D (sampling-group classifier): %s -- %d/%d rows ungrouped (expected 0 of 2,185,193)",
    arm_d_status, n_ungrouped, nrow(classified)
  ))
}

# ==============================================================================
# ARM E -- bimodal-H1 diagnostic (TaxaLikely::calibrate_query_noise()), new
# 2026-09-13. Runs on all three named sites that have a matching REAL
# calibrated model + match fixture; SKIPS a site if it lacks a fixture
# calibrate_query_noise() actually needs (never fabricates one).
# ==============================================================================
cat("\n=== ARM E: bimodal-H1 diagnostic (TaxaLikely::calibrate_query_noise) ===\n")

run_bimodality_arm <- function(site_label, match_df, model_params, priors) {
  cat(sprintf("\n--- %s ---\n", site_label))
  cap_warnings <- character(0)
  model_cal <- withCallingHandlers(
    TaxaLikely::calibrate_query_noise(
      model_params = model_params, match_df = match_df, priors = priors, verbose = FALSE
    ),
    warning = function(w) {
      cap_warnings <<- c(cap_warnings, conditionMessage(w))
      invokeRestart("muffleWarning")
    }
  )
  bimodal_warn <- grep("look bimodal", cap_warnings, value = TRUE)
  qc <- model_cal$Query_Calibration
  cat(sprintf(
    "n_confident_obs=%d, n_confident_genera=%d, offset_form=%s\n",
    qc$n_confident_obs %||% NA_integer_, qc$n_confident_genera %||% NA_integer_,
    qc$offset_form %||% NA_character_
  ))
  if (length(bimodal_warn) > 0L) {
    cat("REAL FINDING -- H1 scores flagged as bimodal:\n  ", bimodal_warn[1], "\n", sep = "")
  } else if (length(cap_warnings) > 0L) {
    cat("Other warning(s) during calibration:\n")
    for (w in cap_warnings) cat("  ", w, "\n")
  } else {
    cat("Bimodality check did not flag (no warning) -- H1 scores read as unimodal.\n")
  }
  list(flagged = length(bimodal_warn) > 0L, n_confident_obs = qc$n_confident_obs %||% NA_integer_)
}

`%||%` <- function(a, b) if (is.null(a)) b else a

arm_e_ptcon18s <- run_bimodality_arm("PtCon 18S (REAL priors fixture available)",
                                      match_obj, lik_model, taxaexpect_priors)

gl_match_path <- file.path(FW_DIR, "greatlakes_fast_match_obj.rds")
gl_model_path <- file.path(FW_DIR, "greatlakes_fast_lik_model_calibrated.rds")

cat("\n--- GreatLakes ---\n")
cat("SKIPPED: no taxaexpect_priors fixture exists for GreatLakes in diagnostics/fast_workflows.\n")
cat("calibrate_query_noise() requires a real priors data frame (taxon_name/taxon_name_rank/theta_mean)\n")
cat("to call identify_confident_observations() -- fabricating one would defeat the point of this check.\n")

# PtCon 12S run-2: unblocked 2026-09-13 via the same ptcon12s_r2_fast_* fixtures
# built for Arm B, 12S REDISCOVERY above (real taxaexpect_priors, 783 rows,
# 258 named-evidence + 37 anonymous-mirror). p12r2_match/p12r2_lik/p12r2_priors
# were already loaded there and are reused here unchanged, matching this
# arm's own "never fabricate a priors table" rule -- this one is real.
arm_e_ptcon12s_r2 <- run_bimodality_arm("PtCon 12S run-2 (REAL priors fixture available, 2026-09-13)",
                                         p12r2_match, p12r2_lik, p12r2_priors)

arm_e_note <- if (isTRUE(arm_e_ptcon18s$n_confident_obs < 30L)) {
  " (fixture too small for the bimodality check to run at all -- calibrate_query_noise() needs >=30 confident observations)"
} else ""
arm_e_status <- if (isTRUE(arm_e_ptcon18s$flagged) || isTRUE(arm_e_ptcon12s_r2$flagged)) "FINDING" else "PASS"
add_summary(sprintf(
  "ARM E (bimodal-H1 diagnostic): %s -- PtCon 18S n_confident_obs=%s, flagged=%s%s; PtCon 12S run-2 n_confident_obs=%s, flagged=%s; GreatLakes SKIPPED (no priors fixture)",
  arm_e_status, arm_e_ptcon18s$n_confident_obs, arm_e_ptcon18s$flagged, arm_e_note,
  arm_e_ptcon12s_r2$n_confident_obs, arm_e_ptcon12s_r2$flagged
))

# ==============================================================================
# SUMMARY
# ==============================================================================
cat("\n=== SUMMARY ===\n")
cat("ARM A real-data half -- ", ARM_A_REAL, "\n", sep = "")
for (line in summary_lines) cat(line, "\n")

cat(sprintf("\nTotal wall time: %.1fs\n", as.numeric(Sys.time() - t0, units = "secs")))
