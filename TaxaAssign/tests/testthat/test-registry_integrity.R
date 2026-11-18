# Every registry = path of TaxaAssign runs TaxaTools::registry_ids_for_names()'s checks: a registry edited after the
# freeze (its content no longer matches its digest) is refused, as attach_taxon_ids() refuses it. Fixtures:
# helper-registry.R.

.ri_edit <- function(reg) {
  reg$names$taxon_id[reg$names$verbatim_name == "Embiotoca caryi"] <- reg$names$taxon_id[reg$names$verbatim_name == "Embiotoca jacksoni"][1]
  reg
}

test_that("each internal registry path refuses a registry edited after the freeze", {
  .rg_skip(); reg <- .rg_registry(); bad <- .ri_edit(reg)
  st <- .rg_stamp(data.frame(taxon_name = "Embiotoca jacksoni"), reg, "priors")
  expect_error(.registry_check_tables(bad, list(priors = st)), "edited after", class = "taxon_registry_invalid")
  expect_error(.registry_check_ids(st, bad, "x"), "edited after", class = "taxon_registry_invalid")
  expect_error(.registry_member_ids("Embiotocidae", bad), "edited after", class = "taxon_registry_invalid")
  expect_error(.registry_resolve_names("Embiotoca caryi", "species", bad), "edited after", class = "taxon_registry_invalid")
  # the same calls pass on the unedited registry
  expect_true(.registry_check_tables(reg, list(priors = st)))
  expect_identical(unname(.registry_member_ids("Embiotocidae", reg)), reg$taxa$taxon_id[reg$taxa$name == "Embiotocidae"])
  expect_identical(as.vector(.registry_resolve_names("Embiotoca caryi", "species", reg)), .rg_id(reg, "Hypsurus caryi"))
})

test_that("join_priors(registry =) refuses a registry edited after the freeze", {
  .rg_skip(); reg <- .rg_registry(); bad <- .ri_edit(reg)
  lik <- .rg_stamp(data.frame(observation_id = "o1", taxon_name = "Embiotoca jacksoni", taxon_name_rank = "species",
                              hypothesis_type = "specific_candidate", score_likelihood = 0.5, family = "Embiotocidae", stringsAsFactors = FALSE),
                   reg, "joined")
  pri <- .rg_stamp(data.frame(taxon_name = c("Embiotoca jacksoni", NA), taxon_name_rank = "species", grid_id = "s1", main_habitat = "Rocky",
                              alpha = c(20, 1), beta = c(80, 999), undetected_type = c(NA, "global_floor"), stringsAsFactors = FALSE), reg, "priors")
  expect_error(suppressMessages(join_priors(lik, pri, site = list(grid_id = "s1", main_habitat = "Rocky"), rank_system = c("family", "genus", "species"),
                                            backbone_id = 11L, registry = bad)), "edited after", class = "taxon_registry_invalid")
})
