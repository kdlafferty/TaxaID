# compute_local_occurrence_distance(registry =) runs TaxaTools::registry_ids_for_names()'s checks: a registry edited
# after the freeze is refused, as attach_taxon_ids() refuses it. Fixtures: helper-registry.R.

test_that("compute_local_occurrence_distance(registry =) refuses a registry edited after the freeze", {
  .rg_skip(); reg <- .rg_registry(); bad <- reg
  bad$names$taxon_id[bad$names$verbatim_name == "Embiotoca caryi"] <- bad$names$taxon_id[bad$names$verbatim_name == "Embiotoca jacksoni"][1]
  occ <- data.frame(taxon_name = "Embiotoca caryi", decimalLatitude = 34.4, decimalLongitude = -119.8, stringsAsFactors = FALSE)
  expect_error(suppressMessages(compute_local_occurrence_distance("Embiotoca caryi", 34.4, -119.8, occ, registry = bad)),
               "^compute_local_occurrence_distance: .*edited after", class = "taxon_registry_invalid")
  expect_no_error(suppressMessages(compute_local_occurrence_distance("Embiotoca caryi", 34.4, -119.8, occ, registry = reg)))
})
