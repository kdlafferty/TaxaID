# ==============================================================================
# PRIOR-SIDE DIAGNOSTIC: do PtConception 18S's sampling groups produce
# materially different Good-Turing budgets?
#
# Answers open decision #2 of
# ecosystem_docs/REENTRY_PROMPT_kernel_budget_pricing_and_scope.md
# ("Per-group curve pricing. Blocked: needs real multi-group data"), and
# supplies the real multi-group evidence for open decision #4 (report f1, f2
# and the radius sensitivity next to any budget figure).
#
# WHY THIS AND NOT A WORKFLOW RUN. The question is entirely prior-side:
#   occurrences_clean + a sampling_group column
#     -> estimate_kernel_priors(sampling_group_col = "sampling_group")
#     -> read $budget
# No NCBI, no BLAST, no likelihood model, no reference fetch -- so it sidesteps
# the NCBI throttling that has blocked every PtConception run since 2026-08, and
# it decides whether per-group curve pricing is worth building BEFORE building
# it. If the groups' budgets are similar the whole thread closes cheaply; if
# they span orders of magnitude, the work is justified in advance.
#
# WHY THE GBIF FETCH THE RE-ENTRY DOC BUDGETED FOR IS NOT NEEDED. That doc
# records "PtConception 18S has NO occurrence or prior checkpoint yet" and
# scoped a GBIF download over ~1,300 genera. That is wrong: a real 18S
# occurrences_clean checkpoint (2,185,193 records, 7,392 taxa, 3,133 genera,
# with the workflow's own sampling_group column already attached) has been in
# the TaxaID project root since 2026-06-15. Section 1 VERIFIES it rather than
# trusting the filename -- it re-derives sampling_group from the classification
# the checkpoint was built under and requires an EXACT match, so a checkpoint
# from some other run would fail loudly here instead of quietly producing a
# budget.
#
# WHAT SECTION 2 FOUND, and why the analysis uses a corrected grouping. The
# workflow's fishes clause (class %in% c("Actinopteri", "Chondrichthyes",
# "Myxini")) matched 5 of 484,077 real fish records: GBIF's backbone carries no
# class for the ray-finned fishes and calls the sharks/rays "Elasmobranchii".
# The other 484,072 fell through to the "macroinvertebrates" catch-all, making
# the largest group 54% fish. Fixed 2026-09-03 in the workflow, the workflow
# template, and 18S_stuff/PtConception18S_groupings.r; re-derived here so the
# budget is computed on the corrected grouping without needing the (network-
# bound) checkpoint rebuild first.
#
# WHAT IT REPORTS
#   1. Checkpoint provenance + grouping re-derivation check.
#   2. The fish-misgrouping audit, and the corrected grouping.
#   3. Bandwidth calibration (LOBO) on the Marine stratum.
#   4. Pooled budget (sampling_group_col = NULL) vs per-group budget -- the
#      Finding-5 scope effect, measured for the first time on a genuinely
#      heterogeneous pool (GreatLakes and Mugu are both all-fish, where the
#      mechanism is a no-op by construction).
#   5. Small-group hazards of per-group pricing (Chao below one species, prices
#      above any observed share, groups with unseen mass but no price at all).
#   6. The same budget with compute_adaptive_sampling_groups() instead of the
#      hand classification -- an independent grouping that does not depend on
#      the workflow's curation.
#   7. Radius (support_weight) and lambda sensitivity of every per-group budget.
#   8. mass/f1 vs mass/Chao per group. REPORTED ONLY. The pricing switch is a
#      separate, independent decision (GreatLakes already settled it on its own
#      evidence); the two are deliberately kept untangled so neither borrows the
#      other's justification.
#
# Run:  Rscript diagnostics/kernel_budget_18S_sampling_groups.R  (from anywhere;
#       every path is absolute, rooted at PROJECT_ROOT below), or source() it
#       interactively.
# Cost: no network. ~2 s per kernel fit at 2.2M records; the sweeps dominate.
# ==============================================================================

suppressMessages({
  library(dplyr)
  library(TaxaExpect)
})

# Absolute paths on BOTH sides, deliberately. A relative OUT_RDS resolves only
# when the working directory happens to be the TaxaID project root, so running
# this interactively (RStudio, or any other wd) read the occurrences fine and
# then failed on the very last line with "cannot open the connection" -- after
# every expensive computation had already been done.
PROJECT_ROOT <- "/Users/lafferty/My Drive/Rscripts/projects/TaxaID"
OCC_RDS <- file.path(PROJECT_ROOT, "PtCon18SSchulte_occurrences_clean.rds")
OUT_RDS <- file.path(PROJECT_ROOT, "diagnostics",
                     "kernel_budget_18S_sampling_groups_result.rds")
if (!dir.exists(dirname(OUT_RDS)))
  stop("Output directory not found: ", dirname(OUT_RDS),
       " -- edit PROJECT_ROOT at the top of this script.")

# Site + stratum: the 18S workflow's own values (PtConceptionWorkflow_18S_2_
# single_site.R Section 0). Not re-derived here -- this diagnostic must price
# the site the workflow actually prices.
STUDY_LAT    <- 34.4
STUDY_LON    <- -120.4
SITE_HABITAT <- "Marine"
SITE_ID      <- sprintf("Site_%.2f_%.2f", STUDY_LAT, STUDY_LON)

.rule <- function(txt) cat("\n", strrep("=", 78), "\n", txt, "\n",
                           strrep("=", 78), "\n", sep = "")
.spread <- function(v) {
  v <- v[is.finite(v) & v > 0]
  if (length(v) < 2L) return(NA_real_)
  max(v) / min(v)
}

# ==============================================================================
# 1. CHECKPOINT PROVENANCE AND VALIDATION
# ==============================================================================
.rule("1. Checkpoint")

stopifnot(file.exists(OCC_RDS))
occ <- readRDS(OCC_RDS)
cat(sprintf("file      : %s\n", OCC_RDS))
cat(sprintf("mtime     : %s\n", format(file.info(OCC_RDS)$mtime, "%Y-%m-%d %H:%M")))
cat(sprintf("records   : %s\n", format(nrow(occ), big.mark = ",")))
cat(sprintf("taxa      : %s   genera: %s\n",
            format(dplyr::n_distinct(occ$taxon_name), big.mark = ","),
            format(dplyr::n_distinct(occ$genus), big.mark = ",")))
cat(sprintf("lat range : %.3f .. %.3f    lon range: %.3f .. %.3f\n",
            min(occ$decimalLatitude, na.rm = TRUE), max(occ$decimalLatitude, na.rm = TRUE),
            min(occ$decimalLongitude, na.rm = TRUE), max(occ$decimalLongitude, na.rm = TRUE)))
cat("\nmain_habitat:\n"); print(sort(table(occ$main_habitat, useNA = "ifany"), decreasing = TRUE))

# --- The classification the checkpoint was built under (FROZEN) --------------
# Verbatim from PtConceptionWorkflow_18S_2_single_site.R as it stood on
# 2026-06-15, kept here as a provenance test and NOT updated when the workflow
# changes: an exact match proves this file is that workflow's output.
.sampling_group_checkpoint <- function(d) {
  dplyr::case_when(
    d$order == "Alismatales" ~ "sea_grasses",
    d$class %in% c("Magnoliopsida", "Pinopsida", "Cycadopsida", "Polypodiopsida",
                   "Lycopodiopsida", "Bryopsida", "Sphagnopsida", "Marchantiopsida",
                   "Jungermanniopsida", "Anthocerotopsida", "Haplomitriopsida") ~ "other_vascular_plants",
    d$class %in% c("Florideophyceae", "Bangiophyceae", "Compsopogonophyceae",
                   "Ulvophyceae", "Charophyceae") ~ "macroalgae",
    d$phylum %in% c("Chlorophyta", "Prasinodermophyta") |
      d$class %in% c("Stylonematophyceae", "Rhodellophyceae", "Klebsormidiophyceae",
                     "Coleochaetophyceae", "Chlorokybophyceae", "Mesostigmatophyceae",
                     "Zygnemophyceae") ~ "phytoplankton",
    d$class %in% c("Actinopteri", "Chondrichthyes", "Myxini") ~ "fishes",
    d$class %in% c("Aves", "Mammalia") ~ "birds_mammals",
    d$class %in% c("Insecta", "Arachnida", "Collembola", "Chilopoda") ~ "terrestrial_arthropods",
    d$class %in% c("Monogenea", "Cestoda", "Trematoda") |
      d$order %in% c("Siphonostomatoida", "Poecilostomatoida", "Bivalvulida",
                     "Multivalvulida", "Porocephalida", "Raillietiellida") ~ "parasites",
    d$order %in% c("Euphausiacea", "Pteropoda") ~ "zooplankton",
    d$class %in% c("Hexanauplia", "Appendicularia", "Hydrozoa", "Cubozoa", "Scyphozoa",
                   "Branchiopoda", "Ostracoda") |
      d$phylum %in% c("Ctenophora", "Chaetognatha") ~ "zooplankton",
    d$phylum %in% c("Ciliophora", "Protalveolata") |
      d$class %in% c("Intramacronucleata", "Postciliodesmatophora") ~ "zooplankton",
    d$phylum == "Apicomplexa" | d$class == "Perkinsea" ~ "parasites",
    d$phylum %in% c("Nematoda", "Tardigrada", "Gastrotricha", "Kinorhyncha",
                    "Xenacoelomorpha", "Priapulida") |
      d$class == "Eurotatoria" ~ "meiofauna",
    TRUE ~ "macroinvertebrates"
  )
}
regen <- .sampling_group_checkpoint(occ)
n_mismatch <- sum(regen != occ$sampling_group, na.rm = TRUE) +
  sum(is.na(regen) != is.na(occ$sampling_group))
cat(sprintf("\nsampling_group re-derived under the 2026-06-15 classification:\n"))
cat(sprintf("  mismatches vs the saved column: %d of %s\n",
            n_mismatch, format(nrow(occ), big.mark = ",")))
if (n_mismatch > 0L)
  stop("Checkpoint's sampling_group does not match the classification it was ",
       "built under -- this is not the file this diagnostic thinks it is.")

# ==============================================================================
# 2. GROUPING AUDIT: the fish clause, and the corrected grouping
# ==============================================================================
.rule("2. Grouping audit (found 2026-09-03) and the corrected grouping")

occ$class_norm <- dplyr::na_if(occ$class, "")
fishlike <- occ$phylum == "Chordata" &
  !(occ$class_norm %in% c("Aves", "Mammalia", "Ascidiacea", "Amphibia",
                          "Reptilia", "Leptocardii", "Appendicularia", "Thaliacea"))
fishlike[is.na(fishlike)] <- FALSE
cat(sprintf("Chordata records that are fish (non-bird/mammal/tunicate) : %s\n",
            format(sum(fishlike), big.mark = ",")))
cat(sprintf("  of which GBIF gives NO class at all                     : %s\n",
            format(sum(fishlike & is.na(occ$class_norm)), big.mark = ",")))
cat("  their classes as GBIF supplies them:\n")
print(sort(table(occ$class_norm[fishlike], useNA = "ifany"), decreasing = TRUE))
cat("\n  where the 2026-06-15 classification actually put them:\n")
print(sort(table(occ$sampling_group[fishlike]), decreasing = TRUE))
cat("\n  top orders among the class-less ones (all ray-finned fish orders):\n")
print(head(sort(table(occ$order[fishlike & is.na(occ$class_norm)]), decreasing = TRUE), 8))

# --- The workflow's CURRENT (fixed) classification ---------------------------
# Same case_when, with empty-string normalization and a fish clause that
# matches the GBIF backbone as it really is. Kept in sync with
# PtConceptionWorkflow_18S_2_single_site.R Step 4.
.sampling_group_current <- function(d) {
  ph <- dplyr::na_if(d$phylum, ""); cl <- dplyr::na_if(d$class, "")
  or <- dplyr::na_if(d$order, "")
  dplyr::case_when(
    or == "Alismatales" ~ "sea_grasses",
    cl %in% c("Magnoliopsida", "Pinopsida", "Cycadopsida", "Polypodiopsida",
              "Lycopodiopsida", "Bryopsida", "Sphagnopsida", "Marchantiopsida",
              "Jungermanniopsida", "Anthocerotopsida", "Haplomitriopsida") ~ "other_vascular_plants",
    cl %in% c("Florideophyceae", "Bangiophyceae", "Compsopogonophyceae",
              "Ulvophyceae", "Charophyceae") ~ "macroalgae",
    ph %in% c("Chlorophyta", "Prasinodermophyta") |
      cl %in% c("Stylonematophyceae", "Rhodellophyceae", "Klebsormidiophyceae",
                "Coleochaetophyceae", "Chlorokybophyceae", "Mesostigmatophyceae",
                "Zygnemophyceae") ~ "phytoplankton",
    cl %in% c("Actinopteri", "Actinopterygii", "Teleostei", "Chondrichthyes",
              "Elasmobranchii", "Holocephali", "Myxini", "Petromyzonti",
              "Cephalaspidomorphi", "Sarcopterygii", "Coelacanthi",
              "Dipneusti") |
      (ph == "Chordata" & is.na(cl)) ~ "fishes",
    cl %in% c("Aves", "Mammalia") ~ "birds_mammals",
    cl %in% c("Insecta", "Arachnida", "Collembola", "Chilopoda") ~ "terrestrial_arthropods",
    cl %in% c("Monogenea", "Cestoda", "Trematoda") |
      or %in% c("Siphonostomatoida", "Poecilostomatoida", "Bivalvulida",
                "Multivalvulida", "Porocephalida", "Raillietiellida") ~ "parasites",
    or %in% c("Euphausiacea", "Pteropoda") ~ "zooplankton",
    cl %in% c("Hexanauplia", "Appendicularia", "Hydrozoa", "Cubozoa", "Scyphozoa",
              "Branchiopoda", "Ostracoda") |
      ph %in% c("Ctenophora", "Chaetognatha") ~ "zooplankton",
    ph %in% c("Ciliophora", "Protalveolata") |
      cl %in% c("Intramacronucleata", "Postciliodesmatophora") ~ "zooplankton",
    ph == "Apicomplexa" | cl == "Perkinsea" ~ "parasites",
    ph %in% c("Nematoda", "Tardigrada", "Gastrotricha", "Kinorhyncha",
              "Xenacoelomorpha", "Priapulida") |
      cl == "Eurotatoria" ~ "meiofauna",
    TRUE ~ "macroinvertebrates"
  )
}
occ$sampling_group_shipped <- occ$sampling_group
occ$sampling_group_fixed   <- .sampling_group_current(occ)
cat("\nRecords moved by the fix:\n")
moved <- occ$sampling_group_shipped != occ$sampling_group_fixed
print(table(from = occ$sampling_group_shipped[moved],
            to   = occ$sampling_group_fixed[moved]))

marine <- dplyr::filter(occ, !is.na(main_habitat), main_habitat == SITE_HABITAT)
cat(sprintf("\nMarine stratum: %s records, %s taxa\n",
            format(nrow(marine), big.mark = ","),
            format(dplyr::n_distinct(marine$taxon_name), big.mark = ",")))
cat("\nMarine-stratum records per group, BEFORE the fix:\n")
print(sort(table(marine$sampling_group_shipped), decreasing = TRUE))
cat("\nMarine-stratum records per group, AFTER the fix:\n")
print(sort(table(marine$sampling_group_fixed), decreasing = TRUE))

# ==============================================================================
# 3. BANDWIDTH CALIBRATION
# ==============================================================================
.rule("3. Bandwidth calibration (leave-one-block-out composition prediction)")

LAMBDA_GRID <- c(10, 25, 50, 100)
cal <- calibrate_kernel_bandwidth(
  occ, SITE_HABITAT,
  lambda_grid       = LAMBDA_GRID,
  block_size_deg    = 0.5,
  min_block_records = 20L
)
print(cal$results)
LAMBDA <- cal$best$lambda_km
cat(sprintf("\nbest lambda_km = %g (weighted logloss %.4f)\n", LAMBDA,
            cal$best$weighted_logloss))

# ==============================================================================
# 4. POOLED vs PER-GROUP BUDGET  (the Finding-5 scope effect, measured)
# ==============================================================================
.rule("4. Pooled budget vs per-sampling-group budget")

.fit <- function(group_col = NULL, lambda = LAMBDA, sw = exp(-3), data = occ)
  estimate_kernel_priors(data, STUDY_LAT, STUDY_LON, SITE_HABITAT,
                         lambda_km = lambda, m = 1, site_id = SITE_ID,
                         sampling_group_col = group_col, support_weight = sw)

fit_pooled   <- .fit(NULL)
fit_shipped  <- .fit("sampling_group_shipped")
fit_grouped  <- .fit("sampling_group_fixed")

cat("\nPOOLED (sampling_group_col = NULL -- what the workflow prices with today):\n")
print(fit_pooled$budget)
cat(sprintf("  n_eff = %.0f, taxa = %d\n", fit_pooled$n_eff, nrow(fit_pooled$priors)))

cat("\nPER GROUP, pre-fix grouping (for the record):\n")
print(fit_shipped$budget[, c("sampling_group", "n_taxa", "n_eff", "f1", "f2",
                             "missing_mass", "chao_missing", "theta_present")],
      row.names = FALSE)

cat("\nPER GROUP, corrected grouping (the analysis grouping):\n")
bud <- fit_grouped$budget
print(bud, row.names = FALSE)

cmp <- bud |>
  dplyr::mutate(
    pooled_theta_present = fit_pooled$theta_present,
    ratio_group_over_pooled = theta_present / fit_pooled$theta_present
  ) |>
  dplyr::arrange(dplyr::desc(ratio_group_over_pooled))
cat("\nMISPRICING FACTOR of the single pooled price, per group\n")
cat("  (>1 = pooling UNDERPRICES this group's unseen species; <1 = overprices)\n")
print(cmp[, c("sampling_group", "n_taxa", "n_eff", "f1", "f2",
              "missing_mass", "chao_missing", "theta_present",
              "ratio_group_over_pooled")], row.names = FALSE)

sp_all <- .spread(bud$theta_present)
cat(sprintf("\ntheta_present spread across groups with a defined price: %.4gx (%d of %d groups priced)\n",
            sp_all, sum(is.finite(bud$theta_present)), nrow(bud)))

# Groups the 18S assay can actually amplify vs the rest. Finding 5 of the
# re-entry doc is exactly this split: taxa the assay cannot detect contribute
# singletons that inflate f1 (hence Chao, quadratically) while adding almost
# nothing to missing_mass, deflating the pooled theta_present.
ASSAY_GROUPS <- c("macroinvertebrates", "zooplankton", "meiofauna",
                  "phytoplankton", "macroalgae", "parasites", "fishes",
                  "sea_grasses")
bud$assay_detectable <- bud$sampling_group %in% ASSAY_GROUPS
cat("\nWhat the non-detectable groups contribute to the POOLED budget\n")
cat("  (the downwash the pooled number silently absorbs):\n")
nd <- bud[!bud$assay_detectable, , drop = FALSE]
print(nd[, c("sampling_group", "n_taxa", "n_eff", "f1", "f2", "missing_mass",
             "theta_present")], row.names = FALSE)
cat(sprintf("\n  non-detectable share of pooled f1   : %d of %d (%.0f%%)\n",
            sum(nd$f1), fit_pooled$f1, 100 * sum(nd$f1) / max(fit_pooled$f1, 1L)))
cat(sprintf("  non-detectable share of pooled n_eff: %.0f of %.0f (%.2f%%)\n",
            sum(nd$n_eff), fit_pooled$n_eff, 100 * sum(nd$n_eff) / fit_pooled$n_eff))

# The spread that actually decides the question. The two extreme groups are
# 23-27 effective records of habitat-misassigned downwash, so a sceptic can
# reasonably discount them -- these two restrictions remove that objection.
sp_assay <- .spread(bud$theta_present[bud$assay_detectable])
sp_thick <- .spread(bud$theta_present[bud$n_eff >= 100])
cat(sprintf("\n  spread among ASSAY-DETECTABLE groups only : %.4gx (%d priced)\n",
            sp_assay, sum(is.finite(bud$theta_present) & bud$assay_detectable)))
cat(sprintf("  spread among groups with n_eff >= 100    : %.4gx (%d priced)\n",
            sp_thick, sum(is.finite(bud$theta_present) & bud$n_eff >= 100)))

# ==============================================================================
# 5. SMALL-GROUP HAZARDS OF PER-GROUP PRICING
# ==============================================================================
.rule("5. Small-group hazards -- what per-group pricing would have to guard")

haz <- bud |>
  dplyr::mutate(
    no_singleton_anchor  = f1 == 0,
    mass_but_no_price    = f1 > 0 & (!is.finite(theta_present)),
    chao_below_one       = f1 > 0 & chao_missing > 0 & chao_missing < 1,
    price_above_singleton = is.finite(theta_present) & f1 > 0 &
      theta_present > missing_mass / f1,
    price_above_1pct     = is.finite(theta_present) & theta_present > 0.01,
    thin_group           = n_eff < 100
  )
print(haz[, c("sampling_group", "n_eff", "f1", "f2", "chao_missing", "theta_present",
              "no_singleton_anchor", "mass_but_no_price", "chao_below_one",
              "price_above_singleton", "price_above_1pct", "thin_group")],
      row.names = FALSE)
cat("\nno_singleton_anchor   : f1 = 0, no budget at all (falls back to the caller's ladder).\n")
cat("mass_but_no_price     : missing_mass > 0 but chao_missing = 0 -- Chao's f1(f1-1)/2\n")
cat("                        branch at f1 = 1, f2 = 0. The mass is real and is discarded.\n")
cat("chao_below_one        : the estimated number of unseen species is below ONE species,\n")
cat("                        so mass/Chao INFLATES the price rather than dividing it.\n")
cat("price_above_singleton : theta_present > missing_mass/f1, i.e. the 'average anonymous\n")
cat("                        unseen species' is priced ABOVE a species we have actually\n")
cat("                        seen once. Happens exactly when f1 < 2*f2. The re-entry doc's\n")
cat("                        Finding 2 asserts mass/Chao is 'properly BELOW the singleton\n")
cat("                        mean'; that holds at GreatLakes and Mugu but is NOT general.\n")
cat("thin_group            : n_eff < 100 effective records -- every budget quantity here\n")
cat("                        rests on a handful of records.\n")

# ==============================================================================
# 6. ADAPTIVE GROUPING  (independent of the workflow's hand curation)
# ==============================================================================
.rule("6. compute_adaptive_sampling_groups() as an independent grouping")

# The adaptive grouper's min_n criterion is a per-SITE record count, so it needs
# a spatial binning to measure effort against. 0.5 deg matches the LOBO block
# size used for bandwidth calibration above -- the same spatial scale the rest
# of this analysis is validated at.
marine_gridded <- create_sites_from_grid(marine, grid_size = 0.5)
ADAPT_MIN_N <- 100
adapt <- compute_adaptive_sampling_groups(
  marine_gridded,
  rank_system = c("order", "class", "phylum"),
  min_n       = ADAPT_MIN_N
)
cat(sprintf("min_n = %g -> %d adaptive groups (%d flagged below min_n)\n",
            ADAPT_MIN_N, dplyr::n_distinct(adapt$sampling_group),
            dplyr::n_distinct(adapt$sampling_group[adapt$sampling_group_below_min_n])))
adapt$sampling_group_adaptive <- adapt$sampling_group

fit_adaptive <- estimate_kernel_priors(
  adapt, STUDY_LAT, STUDY_LON, SITE_HABITAT,
  lambda_km = LAMBDA, m = 1, site_id = SITE_ID,
  sampling_group_col = "sampling_group_adaptive")
bud_a <- fit_adaptive$budget[order(-fit_adaptive$budget$n_eff), ]
cat("\nAdaptive-group budget, 20 largest groups by n_eff:\n")
print(head(bud_a, 20), row.names = FALSE)
cat(sprintf("\ntheta_present spread across adaptive groups: %.4gx (%d of %d priced)\n",
            .spread(bud_a$theta_present), sum(is.finite(bud_a$theta_present)), nrow(bud_a)))
cat(sprintf("adaptive groups with chao_missing < 1 but f1 > 0: %d\n",
            sum(bud_a$f1 > 0 & bud_a$chao_missing > 0 & bud_a$chao_missing < 1)))
cat(sprintf("adaptive groups with unseen mass but no price   : %d\n",
            sum(bud_a$f1 > 0 & !is.finite(bud_a$theta_present))))

# ==============================================================================
# 7. RADIUS AND BANDWIDTH SENSITIVITY  (open decision #4)
# ==============================================================================
.rule("7. Sensitivity of every per-group budget to the counting radius and lambda")

# support_weight is the kernel weight at which a record starts counting toward
# f1/f2. Sweeping it moves ONLY the counting radius, holding lambda fixed --
# the same sweep that found Chao 4x-unstable at Mugu and 21x at GreatLakes.
SUPPORT_GRID <- exp(-c(1, 2, 3, 4, 5))   # 1..5 bandwidths; exp(-3) is the default
sens_radius <- do.call(rbind, lapply(SUPPORT_GRID, function(sw) {
  b <- .fit("sampling_group_fixed", sw = sw)$budget
  b$support_weight <- sw
  b$radius_lambdas <- -log(sw)
  b$radius_km <- -log(sw) * LAMBDA
  b
}))
cat(sprintf("Counting-radius sweep at lambda = %g km (%d radii x %d groups)\n",
            LAMBDA, length(SUPPORT_GRID), dplyr::n_distinct(sens_radius$sampling_group)))
for (g in sort(unique(sens_radius$sampling_group))) {
  s <- sens_radius[sens_radius$sampling_group == g, ]
  if (all(s$f1 == 0)) next
  cat(sprintf("\n  %s\n", g))
  print(s[, c("radius_lambdas", "radius_km", "f1", "f2", "missing_mass",
              "chao_missing", "theta_present")], row.names = FALSE)
  cat(sprintf("    theta_present spread over the radius sweep: %.3gx | f1 %d-%d, f2 %d-%d\n",
              .spread(s$theta_present), min(s$f1), max(s$f1), min(s$f2), max(s$f2)))
}

# The packaged form of this sweep (2026-09-03, open decision #4). Reported here
# so the diagnostic exercises the function it motivated, on the same real data.
cat("\n\nkernel_budget_sensitivity() on the corrected grouped fit:\n")
print(kernel_budget_sensitivity(fit_grouped, occ,
                                support_weight_grid = SUPPORT_GRID))

# Lambda sweep: lambda is chosen by LOBO composition prediction, which has no
# stake in f1/f2, so nothing in the pipeline constrains the budget it implies.
sens_lambda <- do.call(rbind, lapply(LAMBDA_GRID, function(lam) {
  b <- .fit("sampling_group_fixed", lambda = lam)$budget
  b$lambda_km <- lam
  b
}))
cat("\n\nBandwidth sweep (support_weight at its default exp(-3)):\n")
for (g in sort(unique(sens_lambda$sampling_group))) {
  s <- sens_lambda[sens_lambda$sampling_group == g, ]
  if (all(s$f1 == 0)) next
  cat(sprintf("\n  %s\n", g))
  print(s[, c("lambda_km", "n_eff", "f1", "f2", "missing_mass",
              "chao_missing", "theta_present")], row.names = FALSE)
  cat(sprintf("    theta_present spread over the lambda grid: %.3gx\n",
              .spread(s$theta_present)))
}

# ==============================================================================
# 8. mass/f1 vs mass/Chao, PER GROUP  (open decision #1 -- REPORTED, NOT ADOPTED)
# ==============================================================================
.rule("8. Reference class for the price: mass/Chao (shipped) vs mass/f1")

price <- bud |>
  dplyr::transmute(
    sampling_group, f1, f2,
    theta_chao = theta_present,
    theta_f1   = ifelse(f1 > 0, missing_mass / f1, NA_real_),
    ratio_f1_over_chao = theta_f1 / theta_chao
  )
print(price, row.names = FALSE)
cat("\nReported so the two decisions stay independent. GreatLakes already settled\n")
cat("the pricing switch on its own evidence (0/880 winner flips); nothing here is\n")
cat("offered as further justification for it. Note only that mass/f1 is DEFINED\n")
cat("for every group with a singleton, including the ones mass/Chao cannot price.\n")

# ==============================================================================
# 9. VERDICT
# ==============================================================================
.rule("9. Verdict on per-group curve pricing")

cat(sprintf("Groups present in the Marine stratum : %d\n", nrow(bud)))
cat(sprintf("Groups with a defined theta_present  : %d\n", sum(is.finite(bud$theta_present))))
cat(sprintf("theta_present spread across groups   : %.4gx\n", sp_all))
cat(sprintf("Pooled theta_present                 : %.4g\n", fit_pooled$theta_present))
cat(sprintf("Pooled f1 / f2 / chao_missing        : %d / %d / %.1f\n",
            fit_pooled$f1, fit_pooled$f2, fit_pooled$chao_missing))
cat(sprintf("Worst per-group mispricing factor    : %.4gx (%s)\n",
            max(cmp$ratio_group_over_pooled, na.rm = TRUE),
            cmp$sampling_group[which.max(cmp$ratio_group_over_pooled)]))
cat(sprintf("Smallest per-group mispricing factor : %.4gx (%s)\n",
            min(cmp$ratio_group_over_pooled, na.rm = TRUE),
            cmp$sampling_group[which.min(cmp$ratio_group_over_pooled)]))
cat(sprintf("Spread, assay-detectable groups only : %.4gx\n", sp_assay))
cat(sprintf("Spread, groups with n_eff >= 100     : %.4gx\n", sp_thick))
cat("\nThe question the diagnostic was built to answer -- do the sampling groups\n")
cat("produce materially different budgets -- is answered YES by three independent\n")
cat("cuts: the hand grouping, the same grouping restricted to groups the assay can\n")
cat("actually amplify, and the taxonomy-driven adaptive grouping. Per-group curve\n")
cat("pricing is justified. Section 5 says what it would have to guard against.\n")

saveRDS(list(
  occ_file = OCC_RDS,
  study = list(lat = STUDY_LAT, lon = STUDY_LON, habitat = SITE_HABITAT,
               site_id = SITE_ID),
  grouping_fix = list(
    n_records_moved = sum(moved),
    move_table = table(from = occ$sampling_group_shipped[moved],
                       to   = occ$sampling_group_fixed[moved])),
  calibration = cal$results,
  lambda = LAMBDA,
  budget_pooled = fit_pooled$budget,
  pooled_scalars = list(n_eff = fit_pooled$n_eff, f1 = fit_pooled$f1,
                        f2 = fit_pooled$f2, missing_mass = fit_pooled$missing_mass,
                        chao_missing = fit_pooled$chao_missing,
                        theta_present = fit_pooled$theta_present),
  budget_grouped_prefix = fit_shipped$budget,
  budget_grouped = bud,
  mispricing = cmp,
  hazards = haz,
  budget_adaptive = bud_a,
  adaptive_min_n = ADAPT_MIN_N,
  sensitivity_radius = sens_radius,
  sensitivity_lambda = sens_lambda,
  price_reference_class = price,
  spreads = list(all_groups = sp_all, assay_detectable = sp_assay,
                 n_eff_at_least_100 = sp_thick,
                 adaptive = .spread(bud_a$theta_present)),
  generated = Sys.time()
), OUT_RDS)
cat(sprintf("\nSaved: %s\n", OUT_RDS))
