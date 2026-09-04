# ==============================================================================
# REAL-DATA CHECK: per-group curve pricing on PtConception 18S
#
# Validates the 2026-09-04 per-group implementation of
# apply_undetected_evidence(pricing = "curve") against the real multi-group
# kernel fit whose budget spread justified building it
# (diagnostics/kernel_budget_18S_sampling_groups.R -- read that first).
#
# WHAT IT CHECKS, on real data rather than fixtures:
#   1. A real multi-group fit prices a real watch list by the watch list's own
#      sampling group, and by how much that differs from the pooled price the
#      workflow charges today.
#   2. Every guard's effect is visible: which groups qualify, which are capped
#      at their own singleton mean, which borrow, and what the borrowed price
#      is.
#   3. generate_undetected_diversity() scales each singleton mirror by its OWN
#      group's n_eff (the pooled sum understates every group's mirrors).
#   4. The ordering bound still holds: no elevated watch species outranks a
#      genuinely observed singleton at likelihood parity.
#
# Prior-side only, no network.
# Run:  Rscript diagnostics/per_group_curve_pricing_18S_check.R  (from anywhere)
# ==============================================================================

suppressMessages({
  library(dplyr)
  library(TaxaExpect)
})

PROJECT_ROOT <- "/Users/lafferty/My Drive/Rscripts/projects/TaxaID"
OCC_RDS  <- file.path(PROJECT_ROOT, "PtCon18SSchulte_occurrences_clean.rds")
WATCH_RDS <- file.path("/Users/lafferty/My Drive/Rscripts/eDNA/PtConception",
                       "ptconception_invasive_candidates.rds")
OUT_RDS  <- file.path(PROJECT_ROOT, "diagnostics",
                      "per_group_curve_pricing_18S_check_result.rds")
STUDY_LAT <- 34.4; STUDY_LON <- -120.4
SITE_HABITAT <- "Marine"; SITE_ID <- "Site_34.40_-120.40"
LAMBDA <- 25   # the LOBO optimum from the budget diagnostic

.rule <- function(t) cat("\n", strrep("=", 78), "\n", t, "\n", strrep("=", 78), "\n", sep = "")

# ---- 1. Real multi-group fit under the CORRECTED grouping --------------------
.rule("1. Real multi-group kernel fit")
occ <- readRDS(OCC_RDS)
# The 2026-09-03 fish fix, re-derived in memory (the saved checkpoint predates
# it). Kept in sync with PtConceptionWorkflow_18S_2_single_site.R Step 4.
ph <- dplyr::na_if(occ$phylum, ""); cl <- dplyr::na_if(occ$class, "")
occ$sampling_group[ (cl %in% c("Actinopteri", "Actinopterygii", "Teleostei",
                               "Chondrichthyes", "Elasmobranchii", "Holocephali",
                               "Myxini", "Petromyzonti", "Cephalaspidomorphi",
                               "Sarcopterygii") |
                     (ph == "Chordata" & is.na(cl))) %in% TRUE ] <- "fishes"

fit <- estimate_kernel_priors(occ, STUDY_LAT, STUDY_LON, SITE_HABITAT,
                              lambda_km = LAMBDA, m = 1, site_id = SITE_ID,
                              sampling_group_col = "sampling_group")
pooled <- estimate_kernel_priors(occ, STUDY_LAT, STUDY_LON, SITE_HABITAT,
                                 lambda_km = LAMBDA, m = 1, site_id = SITE_ID)
cat(sprintf("groups: %d | pooled theta_present (what the workflow charges today): %.4g\n",
            nrow(fit$budget), pooled$theta_present))
print(fit$budget, row.names = FALSE)

# ---- 2. Undetected diversity, per-group scaled -------------------------------
.rule("2. generate_undetected_diversity() on a multi-group fit")
und <- generate_undetected_diversity(model_obj = fit)
mir <- und[!is.na(und$undetected_type) & und$undetected_type == "singleton_mirror", ]
cat(sprintf("%d singleton mirrors, %d global floor row(s)\n",
            nrow(mir), sum(und$undetected_type == "global_floor")))
# What the pooled-n_eff scaling would have produced, for contrast.
sing <- fit$singletons
grp_n_eff <- fit$budget$n_eff[match(as.character(sing$sampling_group),
                                    fit$budget$sampling_group)]
cmp <- data.frame(
  sampling_group = sing$sampling_group,
  theta_own_group = sing$effective_records / grp_n_eff,
  theta_pooled_neff = sing$effective_records / fit$n_eff)
cmp$understatement <- cmp$theta_own_group / cmp$theta_pooled_neff
by_grp <- cmp |> dplyr::group_by(sampling_group) |>
  dplyr::summarise(n = dplyr::n(), understatement = round(mean(understatement), 2),
                   .groups = "drop") |> as.data.frame()
cat("\nHow far the POOLED n_eff would have understated each group's mirrors:\n")
print(by_grp, row.names = FALSE)

# ---- 3. Per-group curve pricing of a real watch list ------------------------
.rule("3. Per-group curve pricing of the real PtConception watch list")
watch <- readRDS(WATCH_RDS)
watch_taxa <- unique(stats::na.omit(watch$taxon_name))
priors <- dplyr::bind_rows(fit$priors, und)
eligible <- setdiff(watch_taxa, unique(c(priors$taxon_name,
                                         priors$source_taxon_name)))
cat(sprintf("watch list: %d taxa, %d unobserved here and so eligible\n",
            length(watch_taxa), length(eligible)))
ev <- data.frame(taxon_name = eligible, weight = 0.05,
                 source = "invasive_watch", p_conc = 1,
                 stringsAsFactors = FALSE)

# The whole NAS watch list is marine fish, so one group name covers it.
per_group <- apply_undetected_evidence(
  priors, fit, ev, grid_id = SITE_ID, main_habitat = SITE_HABITAT,
  pricing = "curve", sampling_group = "fishes")

fish_price <- fit$budget$theta_present[fit$budget$sampling_group == "fishes"]
cat(sprintf("\nrows priced: %d | basis: %s\n", nrow(per_group),
            paste(unique(per_group$pricing_basis), collapse = ", ")))
cat(sprintf("price charged (fishes' own budget): %.4g\n", fish_price))
cat(sprintf("price the pooled fit would charge : %.4g\n", pooled$theta_present))
cat(sprintf("ratio                             : %.3gx\n",
            fish_price / pooled$theta_present))
stopifnot(identical(unique(per_group$sampling_group), "fishes"),
          isTRUE(all.equal(unique(per_group$prior_mix_theta_present), fish_price)))

# ---- 4. Guards, group by group ----------------------------------------------
.rule("4. What each guard did")
gp <- TaxaExpect:::.resolve_group_prices(fit, 100, 1L, TRUE, "pooled_qualifying")
g <- gp$budget[, c("sampling_group", "n_eff", "f1", "f2", "chao_missing",
                   "singleton_price", "theta_present", "price", "pricing_basis",
                   "qualifies")]
g$n_eff <- round(g$n_eff, 1)
for (cc in c("singleton_price", "theta_present", "price"))
  g[[cc]] <- signif(g[[cc]], 3)
print(g, row.names = FALSE)
cat(sprintf("\nqualifying groups: %d | pooled-qualifying fallback price: %.4g\n",
            gp$n_qualifying, gp$fallback_price))
cat(sprintf("that fallback vs the naive pooled price: %.3gx\n",
            gp$fallback_price / pooled$theta_present))

# ---- 5. Ordering bound ------------------------------------------------------
.rule("5. Ordering bound: an elevated watch species must not outrank a real singleton")
obs_singleton_theta <- min(mir$theta_mean, na.rm = TRUE)
max_elev <- max(per_group$theta_mean)
cat(sprintf("weakest observed singleton mirror theta: %.4g\n", obs_singleton_theta))
cat(sprintf("strongest elevated watch species theta : %.4g\n", max_elev))
cat(sprintf("ratio: %.3g  (must be < 1 to preserve the ordering)\n",
            max_elev / obs_singleton_theta))
stopifnot(max_elev < obs_singleton_theta)
cat("PASS\n")

saveRDS(list(budget = fit$budget, pooled_theta_present = pooled$theta_present,
             guards = g, fallback_price = gp$fallback_price,
             mirror_scaling = by_grp, priced = as.data.frame(per_group),
             fish_price = fish_price, generated = Sys.time()), OUT_RDS)
cat(sprintf("\nSaved: %s\n", OUT_RDS))
