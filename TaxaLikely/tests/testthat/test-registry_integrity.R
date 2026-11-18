# restore_suppressed_candidates(registry =) runs TaxaTools::registry_ids_for_names()'s checks: a registry edited after
# the freeze is refused, as attach_taxon_ids() refuses it. Fixtures: helper-registry.R.

test_that("restore_suppressed_candidates(registry =) refuses a registry edited after the freeze", {
  .rg_skip(); reg <- .rg_registry(); bad <- reg
  bad$names$taxon_id[bad$names$verbatim_name == "Embiotoca caryi"] <- bad$names$taxon_id[bad$names$verbatim_name == "Embiotoca jacksoni"][1]
  st <- suppressMessages(TaxaTools::attach_taxon_ids(data.frame(species = "Hypsurus caryi"), reg, "species", "reference"))
  expect_error(.rsc_check_registry(bad, list(reference_df = st)), "^restore_suppressed_candidates: .*edited after",
               class = "taxon_registry_invalid")
  expect_true(.rsc_check_registry(reg, list(reference_df = st)))
})
