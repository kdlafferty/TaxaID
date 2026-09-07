# Extracted from test-posterior_consensus.R:37

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
  observation_id = c("s1", "s1", "s2"),
  taxon_name = c("Fundulus parvipinnis", "Fundulus catus", "Gobiosoma bosc"),
  taxon_name_rank = c("species", "species", "species"),
  hypothesis_type = rep("specific_candidate", 3),
  posterior_mean = c(0.6, 0.4, 1.0)
)
out <- posterior_consensus(df, rank_system = c("genus", "species"))
