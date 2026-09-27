# Extracted from test-verify_taxon_names.R:137

# setup ------------------------------------------------------------------------
library(testthat)
test_env <- simulate_test_env(package = "TaxaTools", path = "..")
attach(test_env, warn.conflicts = FALSE)

# test -------------------------------------------------------------------------
skip_if_offline()
result <- verify_taxon_names("Homo sapiens", backbone_id = 4)
expect_equal(result$score, 1)
