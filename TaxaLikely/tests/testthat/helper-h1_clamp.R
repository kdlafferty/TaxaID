# Fixtures for test-h1_clamp.R. The 12S_ESV_027213 shape (CI 12S r15): a reference labelled with species A was trained on
# a single divergent pair (n = 2, mean far below a true match), so a 100% read to A sits far ABOVE A's H1 mean, and v1.0's
# symmetric H1 density ranks it below a 91.8% match to a congener.
.hc_params <- function() {
  nm <- c("score_logit", "gap_logit")
  structure(list(
    H1_Lookup = data.frame(
      lookup_key = c("Pleuro verticalis", "Pleuro coenosus", "Pleuro decurrens"), rank = "species",
      mu_score = c(-0.277, -0.20, -0.12), mu_gap = c(0.05, 0.05, 0.05),
      sigma_score = c(0.0005, 0.004, 0.004), n_obs_species = c(2L, 12L, 8L), stringsAsFactors = FALSE
    ),
    H1_Global_Mu = c(score_logit = -0.10, gap_logit = 0.05),
    H1_Sigma = matrix(c(0.004, 0.001, 0.001, 0.01), 2L, dimnames = list(nm, nm)),
    H2 = list(delta = 0.15, sigma = matrix(c(0.01, 0, 0, 0.01), 2L, dimnames = list(nm, nm))),
    H3 = list(delta = 0.30, sigma = matrix(c(0.02, 0, 0, 0.01), 2L, dimnames = list(nm, nm))),
    Stats = list(n_species = 3L, n_singletons = 0L, prior_weight = 10),
    Score_Transform = "sqrt_mismatch", Rank_System = c("family", "genus", "species")
  ), class = "taxa_model_params")
}
.hc_query <- function(score = c(100, 91.8, 97.0), taxa = c("Pleuro verticalis", "Pleuro coenosus", "Pleuro decurrens"), id = "U027213") {
  q <- data.frame(observation_id = id, taxon_name = taxa, score = score, taxon_name_rank = "species",
                  genus = "Pleuro", family = "Pleuronectidae", stringsAsFactors = FALSE)
  q$species <- q$taxon_name
  q
}
.hc_eval <- function(q, ...) {
  suppressMessages(evaluate_likelihoods(q, .hc_params(), c("family", "genus", "species"), ratio_threshold = 0, ...))
}
