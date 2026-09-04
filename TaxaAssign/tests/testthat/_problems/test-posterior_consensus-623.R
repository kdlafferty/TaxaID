# Extracted from test-posterior_consensus.R:623

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

# test -------------------------------------------------------------------------
out_sp <- posterior_consensus(
    make_competitor_df(posterior_mean = c(0.97, 0.01, 0.01, 0.01)),
    rank_system = c("family", "genus", "species"))
