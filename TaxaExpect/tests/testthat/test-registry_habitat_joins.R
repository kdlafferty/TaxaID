# registry = on the habitat joins: a taxon whose habitat verdict is filed under a synonym finds it by registry id.
# Fixtures in helper-registry.R (Hypsurus caryi, with synonym Embiotoca caryi; Embiotoca jacksoni).

.hab_lookup <- function() data.frame(taxon_name = c("Hypsurus caryi", "Embiotoca jacksoni"), Marine = c(0.8, 0.9),
                                     Freshwater = c(0.2, 0.1), stringsAsFactors = FALSE)

test_that("registry is the LAST formal, default NULL, on all three habitat-join functions", {
  for (f in list(condition_evidence_on_habitat, estimate_kernel_priors, estimate_kernel_priors_from_counts)) {
    expect_identical(utils::tail(names(formals(f)), 1L), "registry")
    expect_null(formals(f)$registry)
  }
})

test_that("condition_evidence_on_habitat: evidence under a synonym finds the verdict by id", {
  .rg_skip(); reg <- .rg_registry()
  ev <- data.frame(taxon_name = c("Embiotoca caryi", "Embiotoca jacksoni"), weight = c(0.1, 0.1), stringsAsFactors = FALSE)
  by_name <- condition_evidence_on_habitat(ev, .hab_lookup(), "Marine", verbose = FALSE)
  expect_true(is.na(by_name$habitat_weight[1]))   # the defect: no verdict found
  by_id <- condition_evidence_on_habitat(.rg_stamp(ev, reg, "joined"), .rg_stamp(.hab_lookup(), reg, "priors"), "Marine",
                                         verbose = FALSE, registry = reg)
  expect_equal(by_id$habitat_weight, c(0.8, 0.9))
  expect_equal(by_id$weight, c(0.08, 0.09))
  expect_error(condition_evidence_on_habitat(ev, .rg_stamp(.hab_lookup(), reg, "priors"), "Marine", verbose = FALSE, registry = reg), "stamp")
})

.occ <- function() data.frame(
  taxon_name = c("Embiotoca jacksoni", "Embiotoca jacksoni", "Embiotoca caryi", "Embiotoca caryi"),
  decimalLatitude = c(34.00, 34.01, 34.02, 34.03), decimalLongitude = -119, main_habitat = c("Marine", "Marine", "Uncertain", "Uncertain"),
  stringsAsFactors = FALSE)

test_that("estimate_kernel_priors: an unplaceable record under a synonym counts at its taxon's weight by id", {
  .rg_skip(); reg <- .rg_registry()
  fit0 <- suppressWarnings(suppressMessages(estimate_kernel_priors(.occ(), 34, -119, "Marine", lambda_km = 25,
            habitat_levels = c("Marine", "Freshwater"), habitat_weights = .hab_lookup())))
  expect_false("Embiotoca caryi" %in% fit0$priors$taxon_name)   # the defect: its records had no weight and were left out
  fit1 <- suppressWarnings(suppressMessages(estimate_kernel_priors(.rg_stamp(.occ(), reg, "joined"), 34, -119, "Marine", lambda_km = 25,
            habitat_levels = c("Marine", "Freshwater"), habitat_weights = .rg_stamp(.hab_lookup(), reg, "priors"), registry = reg)))
  expect_true("Embiotoca caryi" %in% fit1$priors$taxon_name)
  expect_equal(fit1$params$n_records_unplaceable, 2L)
  expect_true(all(c("taxon_id", "taxon_name") %in% names(fit1$params$habitat_weights)))
  expect_true("Hypsurus caryi" %in% fit1$params$habitat_weights$taxon_name)
  expect_error(estimate_kernel_priors(.occ(), 34, -119, "Marine", lambda_km = 25, habitat_levels = c("Marine", "Freshwater"),
                                      habitat_weights = .rg_stamp(.hab_lookup(), reg, "priors"), registry = reg), "stamp")
})

test_that("estimate_kernel_priors_from_counts(taxon_threshold): a counted synonym keeps its taxon's verdict by id", {
  .rg_skip(); reg <- .rg_registry()
  bands <- data.frame(taxon_name = c("Embiotoca caryi", "Embiotoca jacksoni"), band_lo_km = 0, band_hi_km = 25, n = c(5, 8),
                      stringsAsFactors = FALSE)
  run <- function(b, lk, ...) suppressWarnings(suppressMessages(estimate_kernel_priors_from_counts(b, "Marine", lambda_km = 25,
            habitat_filter = "taxon_threshold", habitat_lookup = lk, ...)))
  fp0 <- run(bands, .hab_lookup())
  expect_false("Embiotoca caryi" %in% fp0$priors$taxon_name)   # the defect: dropped for want of a lookup row
  fp1 <- run(.rg_stamp(bands, reg, "joined"), .rg_stamp(.hab_lookup(), reg, "priors"), registry = reg)
  expect_true("Embiotoca caryi" %in% fp1$priors$taxon_name)
})

test_that("generate_undetected_diversity(registry =): a singleton mirror is placed on the registry's tree", {
  .rg_skip(); reg <- .rg_registry()
  expect_identical(utils::tail(names(formals(generate_undetected_diversity)), 1L), "registry")
  occ <- data.frame(taxon_name = c(rep("Embiotoca jacksoni", 6), "Embiotoca caryi"),
                    decimalLatitude = 34 + (0:6) / 100, decimalLongitude = -119, main_habitat = "Marine", stringsAsFactors = FALSE)
  fit <- suppressWarnings(suppressMessages(estimate_kernel_priors(occ, 34, -119, "Marine", lambda_km = 25)))
  tax_text <- data.frame(taxon_name = unique(occ$taxon_name), genus = "Embiotoca", family = "Embiotocidae", stringsAsFactors = FALSE)
  u0 <- suppressMessages(generate_undetected_diversity(fit, taxonomy = tax_text))
  m0 <- u0[u0$undetected_type %in% "singleton_mirror" & u0$source_taxon_name %in% "Embiotoca caryi", ]
  skip_if(nrow(m0) == 0L, "no singleton mirror for the fixture")
  expect_identical(m0$genus, "Embiotoca")   # the defect: filed by the synonym's text
  u1 <- suppressMessages(generate_undetected_diversity(fit, taxonomy = tax_text, registry = reg))
  m1 <- u1[u1$undetected_type %in% "singleton_mirror" & u1$source_taxon_name %in% "Embiotoca caryi", ]
  expect_identical(m1$genus, "Hypsurus"); expect_identical(m1$family, "Embiotocidae")
  expect_identical(m1$source_taxon_id, .rg_id(reg, "Hypsurus caryi"))
})
