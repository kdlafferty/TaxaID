# compare_sebastes_chromis_discrimination.R
#
# Direct side-by-side comparison of the manuscript claim (BayesianID_perspective,
# "Modeling likelihoods from scores"): does a 100% 12S match discriminate
# species better within Chromis (damselfish) than within Sebastes (rockfish)?
# Both are real California-relevant marine fish genera, and -- unlike the
# rejected Paralabrax attempt this replaced -- both are now explicitly
# restricted to the same real MiFish amplicon window (see
# sebastes_chromis_confirmation.R's header for the full history of why).
#
# Applies the same cleaning steps as diagnostics/seq_matrix_score_distribution.R
# (blank-name filter, per-species pair thinning) to both
# sebastes_seq_matrix.rds and chromis_seq_matrix.rds (built by
# sebastes_chromis_confirmation.R), then reports p_self, p_cross_congeneric,
# spike_ratio, and LR(H1 vs congeneric) for each side by side.
# ==============================================================================

library(dplyr)

MAX_PAIRS_PER_SP <- 20L
SET_SEED         <- 42L
DIAG_DIR <- "/Users/lafferty/My Drive/Rscripts/projects/TaxaID/diagnostics"

set.seed(SET_SEED)

summarize_group <- function(sm_raw, tag) {

  sm <- sm_raw |>
    mutate(
      same_species = !is.na(species.x) & !is.na(species.y) & species.x == species.y,
      same_genus   = !is.na(genus.x)   & !is.na(genus.y)   & genus.x   == genus.y,
      pair_type = case_when(
        same_species               ~ "within-species",
        !same_species & same_genus ~ "congeneric",
        TRUE                       ~ "other"
      )
    )

  within_raw <- sm |> filter(pair_type == "within-species") |>
    filter(species.x != "" & !is.na(species.x))   # blank-name filter

  within_thinned <- within_raw |>
    group_by(species.x) |>
    slice(sample(seq_len(dplyr::n()), size = min(MAX_PAIRS_PER_SP, dplyr::n()))) |>
    ungroup()

  sm_final <- bind_rows(
    sm |> filter(pair_type != "within-species"),
    within_thinned
  )

  p_self             <- mean(within_thinned$p_match == 1.0)
  p_cross_congeneric <- mean(sm_final$p_match[sm_final$pair_type == "congeneric"] == 1.0)
  n_exact            <- sum(within_thinned$p_match == 1.0)
  n_near_exact       <- sum(within_thinned$p_match >= 0.995 & within_thinned$p_match < 1.0)
  spike_ratio        <- n_exact / max(n_near_exact, 1L)
  lr_congeneric      <- if (p_cross_congeneric > 0) p_self / p_cross_congeneric else NA_real_

  data.frame(
    group                    = tag,
    n_species                = length(unique(within_raw$species.x)),
    n_within_pairs           = nrow(within_thinned),
    n_congeneric_pairs       = sum(sm_final$pair_type == "congeneric"),
    p_self                   = round(p_self, 4),
    p_cross_congeneric       = round(p_cross_congeneric, 4),
    spike_ratio              = round(spike_ratio, 2),
    lr_congeneric            = round(lr_congeneric, 2),
    pct100_discriminates     = ifelse(is.na(lr_congeneric), NA,
                                       lr_congeneric > 1)
  )
}

sebastes_sm <- readRDS(file.path(DIAG_DIR, "sebastes_seq_matrix.rds"))
chromis_sm  <- readRDS(file.path(DIAG_DIR, "chromis_seq_matrix.rds"))

comparison <- bind_rows(
  summarize_group(sebastes_sm, "Sebastes"),
  summarize_group(chromis_sm,  "Chromis")
)

cat("=== Sebastes vs. Chromis: does a 100% match discriminate species? ===\n\n")
print(comparison, row.names = FALSE)

cat("\nInterpretation:\n")
cat("  LR(H1 vs congeneric) = p_self / p_cross_congeneric.\n")
cat("  >1 means a 100% match is more consistent with the true species than a congener (discriminates).\n")
cat("  <=1 means a 100% match is just as (or more) consistent with a congener -- the 100% rule fails.\n")
