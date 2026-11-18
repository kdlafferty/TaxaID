# Every registry = path of TaxaExpect runs TaxaTools::registry_ids_for_names()'s checks: a registry edited after the
# freeze is refused, as attach_taxon_ids() refuses it. Fixtures: helper-registry.R.

.ri_edit <- function(reg) {
  reg$names$taxon_id[reg$names$verbatim_name == "Embiotoca caryi"] <- reg$names$taxon_id[reg$names$verbatim_name == "Embiotoca jacksoni"][1]
  reg
}

test_that("the lineage, lookup-by-id and singleton-mirror paths refuse a registry edited after the freeze", {
  .rg_skip(); reg <- .rg_registry(); bad <- .ri_edit(reg)
  expect_error(.registry_lineage_cols(data.frame(taxon_name = "Embiotoca caryi"), bad, "genus", caller = "f"), "^f: .*edited after",
               class = "taxon_registry_invalid")
  st <- .rg_stamp(data.frame(taxon_name = "Embiotoca jacksoni"), reg, "priors")
  expect_error(.registry_lookup_by_id(st, bad, "lookup", st, "x"), "edited after", class = "taxon_registry_invalid")
  occ <- data.frame(taxon_name = c(rep("Embiotoca jacksoni", 6), "Embiotoca caryi"),
                    decimalLatitude = 34 + (0:6) / 100, decimalLongitude = -119, main_habitat = "Marine", stringsAsFactors = FALSE)
  fit <- suppressWarnings(suppressMessages(estimate_kernel_priors(occ, 34, -119, "Marine", lambda_km = 25)))
  expect_error(suppressMessages(generate_undetected_diversity(fit, registry = bad)), "edited after", class = "taxon_registry_invalid")
  # unedited: the same calls pass
  expect_identical(.registry_lineage_cols(data.frame(taxon_name = "Embiotoca caryi"), reg, "genus")$genus, "Hypsurus")
  expect_no_error(suppressMessages(generate_undetected_diversity(fit, registry = reg)))
})

test_that("generate_domestic_food_priors(registry =) places a domestic row by the registry's name table, and refuses an edited registry", {
  .rg_skip(); reg <- .rg_registry(); bad <- .ri_edit(reg)
  mod <- structure(list(params = list(n_records_stratum = 200L)), class = "taxaexpect_kernel_priors")
  inat <- function(taxon_names, ...) tibble::tibble(taxon_name = taxon_names, taxon_id = 1L, matched_name = taxon_names, inat_kingdom = "Animalia",
                                                    n_observations_local = 0L, query_status = "ok", radius_km = 50, captive = "any", quality_grade = "any")
  local_mocked_bindings(fetch_inat_occurrence_counts = inat, .package = "TaxaFetch")
  run <- function(r) suppressWarnings(suppressMessages(generate_domestic_food_priors(mod, lat = 34.1, lng = -119.1, domestic_animal_taxa = "Embiotoca caryi",
                                     food_species_taxa = character(0), known_cultivar_taxa = character(0), registry = r)))
  out <- run(reg)
  expect_identical(out$registry_taxon_id, .rg_id(reg, "Hypsurus caryi"))   # the synonym, placed by its taxon's id
  expect_identical(out$genus, "Hypsurus")
  expect_error(run(bad), "edited after", class = "taxon_registry_invalid")
})
