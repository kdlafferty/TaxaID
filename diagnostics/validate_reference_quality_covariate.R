# ==============================================================================
# Thread-3 validation: does score_likelihood_refq beat score_likelihood?
#
# THE BAR THIS HAS TO CLEAR is the one the QUERY-evidence axis had to clear in
# Session 156. That axis shipped unconditional first and measured 27 helped /
# 2053 hurt on this same real 12S PtConception dataset; gated, it measured
# 163 helped / 3 hurt, and only then became a default. Reference quality enters
# the SAME sigma slot through the SAME gate and has not yet had that run.
#
# WHY THE SESSION-156 METRIC IS NOT ENOUGH HERE. There, "helped" could be read
# off the direction of movement, because the failure being fixed was H1 wrongly
# suppressed -- up was good. Here that reasoning does NOT transfer: widening
# sigma for a candidate with a dubious reference RAISES that candidate's
# likelihood, and whether that is good depends entirely on whether the
# candidate is correct. Direction of movement is a sanity check, not a verdict.
# So this script reports the movement audit for comparability AND a real
# ground-truth arm, and the ground-truth arm is the one that decides.
#
# GROUND TRUTH, and why it is not circular: identify_confident_observations()
# keeps observations whose genus has exactly ONE locally-plausible species in
# the occurrence priors. The species call is then fixed by geography, and the
# likelihood model never enters it. Mild caveat stated rather than hidden --
# calibrate_query_noise() fits its scalar offset on this same set, so the two
# are not fully independent; but that offset is one number shared by every
# candidate, while refq is per-candidate, so it cannot manufacture the
# per-candidate differences measured here.
#
# THE COVARIATE IS ISOLATED: evidence_col is deliberately NOT passed, so
# score_likelihood_evidence == score_likelihood and every difference in
# score_likelihood_refq is attributable to reference quality alone. The
# workflow runs both together; that combined case is a separate question.
#
# THE TWO ARMS, which is the real point of this script:
#   A  MEASURED-LOW  -- label_confidence is low because evidence was gathered
#      and it was bad. This is the mechanism working as designed.
#   B  NO-EVIDENCE   -- label_confidence is EXACTLY 0.5 because the accession
#      had zero valid comparison partners. 0.5 is the honest number for "no
#      evidence either way", but feeding it into the sigma slot widens sigma
#      by 41% on the strength of an absence, which is a PRIOR, not a
#      measurement. Nobody has decided that deliberately. On the real data
#      723 of the 1,418 exposed observations are exposed only this way, so the
#      arms are reported separately and can be judged separately.
#
# Run:  Rscript diagnostics/validate_reference_quality_covariate.R
# Cost: fully offline (no NCBI, no BLAST). A few minutes.
# ==============================================================================

suppressMessages({library(TaxaMatch); library(TaxaLikely); library(dplyr)})

PTCON   <- "/Users/lafferty/My Drive/Rscripts/eDNA/PtConception"
OUT_RDS <- file.path("diagnostics", "validate_reference_quality_covariate.rds")

# Pre-registered pass criterion, stated BEFORE looking at the answer, mirroring
# what the query-evidence axis actually achieved (163:3, i.e. ~54:1):
#   1. helped:hurt >= 10:1 on the ground-truth arm, and
#   2. no confident observation whose correct species was winning under
#      score_likelihood loses to a wrong candidate under score_likelihood_refq.
# Criterion 2 is a veto: a covariate that flips a correct call is not adopted
# on the strength of a favourable ratio elsewhere.
MIN_RATIO <- 10
# ...and a POWER floor. Added after the first run reported a 34:1 PASS that was
# almost entirely artefact (see the power check below): a ratio computed on a
# handful of observations decides nothing, however favourable it looks.
MIN_MOVED_IN_ARM_A <- 20L

# ---- 1. Reconstruct the inputs ----------------------------------------------
message("Loading real PtConception inputs...")
match_obj <- readRDS(file.path(PTCON, "PtConMifishSchulte_match_obj.rds"))
lik_model <- readRDS(file.path(PTCON, "PtConMifishSchulte_lik_model_calibrated.rds"))
priors    <- readRDS(file.path(PTCON, "MifishPriors.rds"))
ev <- score_reference_labels(
  readRDS(file.path(PTCON, "ptcon_ref_eval_cache", "reference_accession_cache.rds"))
)
match_df <- flag_incongruent_references(match_obj, ev)

# Priors are per grid cell; a species is "locally plausible" if it is plausible
# in ANY local cell. Deliberately the permissive reading: it makes FEWER genera
# qualify as single-species, which keeps the ground-truth set pure at the cost
# of size -- the right trade for a truth set.
priors_tax <- priors |>
  group_by(taxon_name, taxon_name_rank) |>
  summarise(theta_mean = max(theta_mean, na.rm = TRUE), .groups = "drop")

confident <- identify_confident_observations(match_df, priors_tax)
message(sprintf("  %d match rows, %d observations; %d confident observations (ground truth).",
                nrow(match_df), n_distinct(match_df$observation_id),
                n_distinct(confident$observation_id)))

# ---- 2. One pass: every likelihood variant is computed together --------------
message("Evaluating likelihoods (score_likelihood and score_likelihood_refq in one pass)...")
lik <- evaluate_likelihoods(
  match_df           = match_df,
  model_params       = lik_model,
  rank_system        = c("family", "genus", "species"),
  n_sims             = 0L,
  ratio_threshold    = 0,
  reference_quality_col = "label_confidence"
)$likelihoods

# ---- 3. Movement audit (Session 156 comparability) ---------------------------
h1 <- lik |> filter(hypothesis_type == "specific_candidate")
moved <- h1 |> filter(abs(score_likelihood_refq - score_likelihood) > 1e-9)
cat("\n================ MOVEMENT AUDIT (all H1 rows) ================\n")
cat(sprintf("H1 rows: %d;  moved: %d (%.2f%%);  up: %d;  down: %d\n",
            nrow(h1), nrow(moved), 100 * nrow(moved) / max(nrow(h1), 1L),
            sum(moved$score_likelihood_refq > moved$score_likelihood),
            sum(moved$score_likelihood_refq < moved$score_likelihood)))
cat(sprintf("Mean H1 relative likelihood: %.4f -> %.4f\n",
            mean(h1$score_likelihood, na.rm = TRUE),
            mean(h1$score_likelihood_refq, na.rm = TRUE)))
cat("NOTE: direction alone is not a verdict here -- see this script's header.\n")

# ---- 4. Ground-truth arm ----------------------------------------------------
# Margin, not the raw normalised value: both columns are normalised to their own
# max within an observation, so a correct candidate that is already winning
# reads 1.0 in both and would look unchanged. The margin against the best
# COMPETING hypothesis (wrong species, or an unreferenced H2/H3) is what
# actually moves, and what a downstream posterior would feel.
truth <- confident |> distinct(observation_id, confident_species)

margins <- lik |>
  inner_join(truth, by = "observation_id") |>
  group_by(observation_id, confident_species) |>
  summarise(
    has_correct  = any(taxon_name == confident_species[1]),
    base_correct = max(score_likelihood[taxon_name == confident_species[1]], -Inf),
    base_rival   = max(score_likelihood[taxon_name != confident_species[1]], -Inf),
    refq_correct = max(score_likelihood_refq[taxon_name == confident_species[1]], -Inf),
    refq_rival   = max(score_likelihood_refq[taxon_name != confident_species[1]], -Inf),
    winner_base  = taxon_name[which.max(score_likelihood)],
    winner_refq  = taxon_name[which.max(score_likelihood_refq)],
    .groups = "drop"
  ) |>
  filter(has_correct, is.finite(base_correct), is.finite(base_rival)) |>
  mutate(
    margin_base = base_correct - base_rival,
    margin_refq = refq_correct - refq_rival,
    delta       = margin_refq - margin_base
  )

# Which arm is each observation in? An observation is NO-EVIDENCE only if every
# sub-0.75 reference behind it is an exactly-0.5 (zero-partner) row; if any
# reference was genuinely measured low, it belongs to the measured arm.
acc_arm <- match_df |>
  filter(!is.na(label_confidence), label_confidence < 0.75) |>
  group_by(observation_id) |>
  summarise(any_measured = any(abs(label_confidence - 0.5) > 1e-9), .groups = "drop")

margins <- margins |>
  left_join(acc_arm, by = "observation_id") |>
  mutate(arm = case_when(is.na(any_measured) ~ "unexposed",
                         any_measured        ~ "A measured-low",
                         TRUE                ~ "B no-evidence (lc = 0.5)"))

report_arm <- function(d, label) {
  d <- d |> filter(abs(delta) > 1e-9)
  helped <- sum(d$delta > 0); hurt <- sum(d$delta < 0)
  cat(sprintf("\n--- %s ---\n  observations moved: %d;  helped: %d;  hurt: %d;  ratio: %s\n",
              label, nrow(d), helped, hurt,
              if (hurt == 0) sprintf("%d:0", helped) else sprintf("%.1f:1", helped / hurt)))
  flips_bad  <- sum(d$winner_base == d$confident_species & d$winner_refq != d$confident_species)
  flips_good <- sum(d$winner_base != d$confident_species & d$winner_refq == d$confident_species)
  cat(sprintf("  winner flips: %d correct->wrong (VETO if > 0), %d wrong->correct\n",
              flips_bad, flips_good))
  invisible(list(moved = nrow(d), helped = helped, hurt = hurt,
                 flips_bad = flips_bad, flips_good = flips_good))
}

cat("\n\n================ GROUND-TRUTH ARM ================\n")
cat(sprintf("Confident observations with the correct species among the candidates: %d\n",
            nrow(margins)))
overall <- report_arm(margins, "ALL confident observations")
for (a in sort(unique(margins$arm))) report_arm(filter(margins, arm == a), a)

# ---- 5. Trace every hurt case ------------------------------------------------
# Session 156 precedent: the 3 hurt cases were each traced to the gate's own
# documented approximation rather than waved off. Same standard here.
hurt_rows <- margins |> filter(delta < -1e-9) |> arrange(delta)
cat("\n\n================ EVERY HURT CASE ================\n")
if (nrow(hurt_rows) == 0L) {
  cat("None.\n")
} else {
  print(as.data.frame(hurt_rows |>
    transmute(observation_id, confident_species, arm,
              margin_base = round(margin_base, 4),
              margin_refq = round(margin_refq, 4),
              delta = round(delta, 4),
              winner_base, winner_refq)), row.names = FALSE)
}

# ---- 6. Verdict against the pre-registered criterion -------------------------
# ---- 5b. POWER CHECK: could this test have decided anything? -----------------
# The first run of this script reported 34:1 PASS. It was not measuring the
# covariate. Two separate problems, both worth printing every run:
#
#  (i) label_confidence NEVER REACHES 1. Its ceiling is the Jeffreys-smoothed
#      vote plus the capped margin -- 0.99939 for a perfectly corroborated
#      5-partner reference. Fed to the sigma slot that is a ratio of 0.99939,
#      i.e. a 0.03% widening applied to EVERY candidate in the dataset. The
#      documentation (this covariate's own @param) promises "1 means a fully
#      corroborated reference, which is the no-op" -- the scale cannot deliver
#      that. Most rows that "moved" moved for this reason, not because their
#      reference was dubious.
#
#  (ii) The covariate is genuinely very sparse. It only acts where a candidate
#      BOTH rests on a dubious reference AND sits far enough from its trained
#      mean for the crossover gate to fire. Those two conditions rarely
#      co-occur: a query matching a dubious reference well is near the mean.
cand_lc <- match_df |>
  group_by(observation_id, taxon_name) |>
  summarise(lc = median(label_confidence, na.rm = TRUE), .groups = "drop")
moved_lc <- moved |> select(observation_id, taxon_name) |>
  inner_join(cand_lc, by = c("observation_id", "taxon_name"))

cat("\n\n================ POWER CHECK ================\n")
cat(sprintf("Ceiling of label_confidence in this cache: %.5f (never 1.0, so every\n  candidate gets a small widening regardless of how well corroborated it is)\n",
            max(match_df$label_confidence, na.rm = TRUE)))
cat(sprintf("Of %d moved H1 rows: %d have lc > 0.99 (artefact of the ceiling),\n  %d have lc < 0.25 (the population this covariate exists for)\n",
            nrow(moved_lc), sum(moved_lc$lc > 0.99, na.rm = TRUE),
            sum(moved_lc$lc < 0.25, na.rm = TRUE)))
conf_ids <- unique(margins$observation_id)
low_ids  <- unique(match_df$observation_id[!is.na(match_df$label_confidence) &
                                             match_df$label_confidence < 0.25])
cat(sprintf("Ground-truth observations: %d;  with a genuinely low candidate: %d;  overlap: %d\n",
            length(conf_ids), length(low_ids), length(intersect(conf_ids, low_ids))))
cat("  -> of that overlap, only the ones where the gate ALSO fires can move at all.\n")

cat("\n\n================ VERDICT ================\n")
arm_a <- margins |> filter(arm == "A measured-low", abs(delta) > 1e-9)
ratio_ok <- overall$hurt == 0 || (overall$helped / overall$hurt) >= MIN_RATIO
veto_ok  <- overall$flips_bad == 0
power_ok <- nrow(arm_a) >= MIN_MOVED_IN_ARM_A
cat(sprintf("criterion 1 -- helped:hurt >= %d:1 ....... %s\n", MIN_RATIO,
            if (ratio_ok) "PASS" else "FAIL"))
cat(sprintf("criterion 2 -- no correct->wrong flip ... %s\n",
            if (veto_ok) "PASS" else "FAIL (veto)"))
cat(sprintf("criterion 3 -- >= %d moved in arm A ..... %s (%d moved)\n",
            MIN_MOVED_IN_ARM_A, if (power_ok) "PASS" else "FAIL", nrow(arm_a)))
cat(sprintf("\n=> %s\n",
  if (!power_ok)
    "INCONCLUSIVE. Criteria 1-2 are computed on too few genuinely-affected observations to mean anything, and the movement that does exist is dominated by the label_confidence ceiling artefact above. Fix the scale so a clean reference maps to exactly 1.0, then re-run; if arm A is still this thin, this dataset cannot decide and a reference set with more dubious accessions is needed."
  else if (ratio_ok && veto_ok)
    "Both criteria met with adequate power on this dataset. Adoption is still a decision, not an automatic consequence."
  else
    "Not adopted. See the arm breakdown for whether the failure is the mechanism or the no-evidence arm."))

saveRDS(list(margins = margins, h1 = h1, overall = overall), OUT_RDS)
cat(sprintf("\nSaved to %s\n", OUT_RDS))
