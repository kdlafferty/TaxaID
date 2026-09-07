# Extracted from test-posterior_consensus.R:296

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
df <- rbind(
  make_posterior(
    "s1", "Fundulus parvipinnis", "species",
    "specific_candidate", 0.55
  ),
  make_posterior(
    "s1", "Fundulus sp_unref", "species",
    "unreferenced_species", 0.45
  )
)
out <- posterior_consensus(df, rank_system = c("genus", "species"))
