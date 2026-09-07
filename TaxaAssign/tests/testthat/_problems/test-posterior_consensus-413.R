# Extracted from test-posterior_consensus.R:413

# setup ------------------------------------------------------------------------
library(testthat)
test_env <- simulate_test_env(package = "TaxaAssign", path = "..")
attach(test_env, warn.conflicts = FALSE)

# prequel ----------------------------------------------------------------------
make_posterior <- function(observation_id, taxon_name, taxon_name_rank,
                           hypothesis_type, posterior_mean,
                           genus = NULL, family = NULL, species = NULL) {
  df <- data.frame(
    observation_id = observation_id,
    taxon_name = taxon_name,
    taxon_name_rank = taxon_name_rank,
    hypothesis_type = hypothesis_type,
    posterior_mean = posterior_mean,
    stringsAsFactors = FALSE
  )
  if (!is.null(genus)) df$genus <- genus
  if (!is.null(family)) df$family <- family
  if (!is.null(species)) df$species <- species
  df
}

# test -------------------------------------------------------------------------
df <- make_posterior(
  observation_id  = c("s1", "s1"),
  taxon_name      = c("Fundulus parvipinnis", "Fundulus catus"),
  taxon_name_rank = rep("species", 2),
  hypothesis_type = rep("specific_candidate", 2),
  posterior_mean  = c(0.3, 0.7) # Fundulus catus wins
)
df$prior_mean <- c(0.12, 0.05)
df$score_likelihood <- c(0.88, 0.60)
df$score_likelihood_cov <- c(0.80, 0.55)
out <- posterior_consensus(df, rank_system = c("genus", "species"))
