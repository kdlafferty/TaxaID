# join_priors(registry =): candidates meet priors by registry id. Fixtures in helper-registry.R.

.jr_site <- list(grid_id = "s1", main_habitat = "Rocky")
.jr_lik <- function(names, ranks = "species", types = "specific_candidate", obs = "E1") {
  data.frame(observation_id = obs, taxon_name = names, taxon_name_rank = ranks, hypothesis_type = types,
             score_likelihood = 0.5, genus = sub(" .*$", "", names), family = "Embiotocidae", stringsAsFactors = FALSE)
}
.jr_pri <- function(names, alpha) {
  data.frame(taxon_name = c(names, NA), taxon_name_rank = "species", grid_id = "s1", main_habitat = "Rocky",
             alpha = c(alpha, 0.5), beta = c(100 - alpha, 99.5), undetected_type = c(rep(NA, length(names)), "tier3"),
             stringsAsFactors = FALSE)
}
.jp <- function(...) suppressWarnings(suppressMessages(join_priors(..., site = .jr_site, rank_system = c("family", "genus", "species"), backbone_id = 11L)))

test_that("registry is the LAST formal of join_priors and defaults to NULL", {
  f <- formals(join_priors)
  expect_identical(utils::tail(names(f), 1L), "registry")
  expect_null(f$registry)
})

test_that("a call under a synonym meets the prior filed under the accepted name (Embiotoca / Hypsurus caryi)", {
  .rg_skip(); reg <- .rg_registry()
  lik <- .jr_lik(c("Embiotoca caryi", "Embiotoca jacksoni"))
  pri <- .jr_pri(c("Hypsurus caryi", "Embiotoca jacksoni"), c(20, 5))
  by_name <- .jp(lik, pri)
  expect_true(is.na(by_name$alpha[by_name$taxon_name == "Embiotoca caryi"]))   # the defect: floored
  out <- .jp(.rg_stamp(lik, reg, "joined"), .rg_stamp(pri, reg, "priors"), registry = reg)
  r <- out[out$taxon_name == "Embiotoca caryi", ]
  expect_identical(nrow(r), 1L)
  expect_equal(r$alpha, 20)
  expect_identical(r$taxon_id, .rg_id(reg, "Hypsurus caryi"))
  expect_identical(r$genus, "Hypsurus")   # lineage from the tree, not the call's own genus column
  expect_identical(out$alpha[out$taxon_name == "Embiotoca jacksoni"], 5)
  expect_false(is.null(attr(out, "taxon_registry")))
  expect_identical(nrow(attr(out, "prior_floor_fallthrough")), 0L)
})

test_that("one observation holding a taxon under two names gives ONE hypothesis, named by the registry", {
  .rg_skip(); reg <- .rg_registry()
  lik <- .jr_lik(c("Embiotoca caryi", "Hypsurus caryi", "Embiotoca jacksoni"))
  pri <- .jr_pri(c("Hypsurus caryi", "Embiotoca jacksoni"), c(20, 5))
  by_name <- .jp(lik, pri)
  expect_identical(sum(by_name$taxon_name %in% c("Embiotoca caryi", "Hypsurus caryi")), 2L)   # the defect: two rows
  out <- .jp(.rg_stamp(lik, reg, "joined"), .rg_stamp(pri, reg, "priors"), registry = reg)
  hc <- out[out$taxon_id == .rg_id(reg, "Hypsurus caryi"), ]
  expect_identical(nrow(hc), 1L)
  expect_identical(hc$taxon_name, "Hypsurus caryi")
  expect_identical(attr(out, "registry_join_counts")$n_likelihood_taxa_under_2plus_names, 1L)
})

test_that("a prior table holding one taxon under two names keeps the accepted name's row", {
  .rg_skip(); reg <- .rg_registry()
  lik <- .jr_lik("Hypsurus caryi")
  pri <- .jr_pri(c("Embiotoca caryi", "Hypsurus caryi"), c(40, 20))
  out <- .jp(.rg_stamp(lik, reg, "joined"), .rg_stamp(pri, reg, "priors"), registry = reg)
  expect_equal(out$alpha[out$taxon_name == "Hypsurus caryi"], 20)
  expect_setequal(attr(out, "merged_prior_rows")$taxon_name, c("Embiotoca caryi", "Hypsurus caryi"))
})

test_that("with a registry no backbone lookup is made", {
  .rg_skip(); reg <- .rg_registry()
  lik <- .jr_lik(c("Embiotoca caryi", "Embiotocidae"), ranks = c("species", "family"),
                 types = c("specific_candidate", "unreferenced_genus"))
  lik$genus[2] <- NA
  pri <- .jr_pri("Hypsurus caryi", 20)
  local_mocked_bindings(verify_taxon_names = function(...) stop("backbone lookup made"), .package = "TaxaTools")
  out <- .jp(.rg_stamp(lik, reg, "joined"), .rg_stamp(pri, reg, "priors"), registry = reg)
  expect_true("Embiotocidae" %in% out$taxon_name)
  expect_identical(out$family[out$taxon_name == "Embiotocidae"], "Embiotocidae")
})

test_that("join_priors(registry =) refuses an unstamped table", {
  .rg_skip(); reg <- .rg_registry()
  expect_error(join_priors(.jr_lik("Hypsurus caryi"), .rg_stamp(.jr_pri("Hypsurus caryi", 20), reg, "priors"),
                           site = .jr_site, backbone_id = 11L, registry = reg), "stamp")
})
