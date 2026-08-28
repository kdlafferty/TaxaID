# Extracted from test-posterior_consensus.R:745

# setup ------------------------------------------------------------------------
library(testthat)
test_env <- simulate_test_env(package = "TaxaAssign", path = "..")
attach(test_env, warn.conflicts = FALSE)

# prequel ----------------------------------------------------------------------
make_posterior <- function(observation_id, taxon_name, taxon_name_rank,
                            hypothesis_type, posterior_mean,
                            genus = NULL, family = NULL, species = NULL) {
  df <- data.frame(
    observation_id       = observation_id,
    taxon_name      = taxon_name,
    taxon_name_rank = taxon_name_rank,
    hypothesis_type = hypothesis_type,
    posterior_mean  = posterior_mean,
    stringsAsFactors = FALSE
  )
  if (!is.null(genus))   df$genus   <- genus
  if (!is.null(family))  df$family  <- family
  if (!is.null(species)) df$species <- species
  df
}
make_competitor_df <- function(model_tier = c("tier1", "tier2", NA, NA),
                                posterior_mean = c(0.55, 0.20, 0.15, 0.10)) {
  df <- data.frame(
    observation_id  = rep("obs1", 4),
    taxon_name      = c("Aa one", "Aa two", "Bb one", "Bb two"),
    taxon_name_rank = rep("species", 4),
    hypothesis_type = rep("specific_candidate", 4),
    posterior_mean  = posterior_mean,
    genus           = c("Aa", "Aa", "Bb", "Bb"),
    family          = rep("Fam1", 4),
    species         = c("Aa one", "Aa two", "Bb one", "Bb two"),
    model_tier      = model_tier,
    species_confusion_risk = rep(0.10, 4),
    genus_confusion_risk   = rep(0.30, 4),
    family_confusion_risk  = rep(0.60, 4),
    stringsAsFactors = FALSE
  )
  df
}
make_theta_df <- function(model_tier      = c("tier1", "tier2", NA, NA),
                           posterior_mean  = c(0.55, 0.20, 0.15, 0.10),
                           prior_mean      = c(0.99, 0.05, NA, NA),
                           theta_mean      = c(0.02, 0.05, NA, NA)) {
  df <- data.frame(
    observation_id  = rep("obs1", 4),
    taxon_name      = c("Aa one", "Aa two", "Bb one", "Bb two"),
    taxon_name_rank = rep("species", 4),
    hypothesis_type = rep("specific_candidate", 4),
    posterior_mean  = posterior_mean,
    prior_mean      = prior_mean,
    theta_mean      = theta_mean,
    genus           = c("Aa", "Aa", "Bb", "Bb"),
    family          = rep("Fam1", 4),
    species         = c("Aa one", "Aa two", "Bb one", "Bb two"),
    model_tier      = model_tier,
    stringsAsFactors = FALSE
  )
  df
}

# test -------------------------------------------------------------------------
df <- make_theta_df(posterior_mean = c(0.47, 0.47, 0.03, 0.03),
                      prior_mean     = c(0.9999, 0.05, NA, NA))
gp <- data.frame(rank = "genus", taxon = "Aa", theta_sum = 0.02 + 0.05,
                   n_members = 2L, stringsAsFactors = FALSE)
out <- posterior_consensus(df, rank_system = c("family", "genus", "species"),
                             group_priors = gp)
