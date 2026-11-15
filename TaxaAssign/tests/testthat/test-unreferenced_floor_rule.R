# tests/testthat/test-unreferenced_floor_rule.R
#
# The floor rule in add_unreferenced_prior_mass(withhold = ): a local
# unreferenced species adds its prior only to the ring at the finest rank
# where its lineage has a referenced taxon for the marker. With
# withhold = "genus" only a referenced GENUS withholds it from coarser rings.
# Fully offline.

# One unit: a referenced Sebastes candidate and an ORDER ring (Perciformes,
# "an unsequenced family of Perciformes"). Local unreferenced species:
#   Decapterus muroadsi  -- family Carangidae, which HAS a reference
#                           (Trachurus symmetricus), genus unreferenced;
#   Sebastolobus alascanus -- family Sebastidae, referenced via the candidate;
#   Lycodes pacificus    -- family Zoarcidae, no reference at any finer rank.
.fr_joined <- function(family_ring = FALSE) {
  j <- data.frame(
    observation_id = "E1",
    taxon_name = c("Sebastes mystinus", "Perciformes"),
    taxon_name_rank = c("species", "order"),
    hypothesis_type = c("specific_candidate", "unreferenced_family"),
    score_likelihood = c(0.4, 0.2), score_likelihood_mean = c(0.4, 0.2), score_likelihood_sd = 0,
    prior_mean = c(1e-3, 1e-6), prior_alpha = c(1, 0.001), prior_beta = c(999, 999.999),
    grid_id = "site1", main_habitat = "Marine",
    species = c("Sebastes mystinus", NA), genus = c("Sebastes", NA),
    family = c("Sebastidae", NA), order = "Perciformes",
    stringsAsFactors = FALSE
  )
  if (family_ring) {
    j <- rbind(j, data.frame(
      observation_id = "E1", taxon_name = "Carangidae", taxon_name_rank = "family",
      hypothesis_type = "unreferenced_genus", score_likelihood = 0.3, score_likelihood_mean = 0.3,
      score_likelihood_sd = 0, prior_mean = 1e-6, prior_alpha = 0.001, prior_beta = 999.999,
      grid_id = "site1", main_habitat = "Marine", species = NA, genus = NA,
      family = "Carangidae", order = "Perciformes", stringsAsFactors = FALSE
    ))
  }
  j
}
.fr_priors <- function() {
  sp <- c("Sebastes mystinus", "Trachurus symmetricus", "Decapterus muroadsi",
          "Sebastolobus alascanus", "Lycodes pacificus")
  data.frame(taxon_name = sp, taxon_name_rank = "species", grid_id = "site1",
    main_habitat = "Marine", theta_mean = c(1e-3, 2e-3, 4e-3, 3e-3, 5e-3),
    alpha = c(1, 2, 4, 3, 5), beta = c(999, 998, 996, 997, 995), stringsAsFactors = FALSE)
}
.fr_tax <- function() {
  data.frame(taxon_name = .fr_priors()$taxon_name,
    genus = c("Sebastes", "Trachurus", "Decapterus", "Sebastolobus", "Lycodes"),
    family = c("Sebastidae", "Carangidae", "Carangidae", "Sebastidae", "Zoarcidae"),
    order = "Perciformes", stringsAsFactors = FALSE)
}
.fr_ref <- c("Sebastes mystinus", "Trachurus symmetricus")
.fr_has_withhold <- function() "withhold" %in% names(formals(add_unreferenced_prior_mass))
.fr_add <- function(...) suppressMessages(add_unreferenced_prior_mass(...))

test_that("REVIEW FR: withhold follows the released formals (then registry), default \"finest\", released formals an exact prefix", {
  f <- names(formals(add_unreferenced_prior_mass))
  released <- c("joined", "taxaexpect_priors", "taxonomy", "referenced_names", "grid_id",
                "unreferenced_types", "mismatch_message_fraction", "named_rows")
  expect_identical(f[seq_along(released)], released)
  expect_identical(f[-seq_along(released)], c("withhold", "registry"))
  expect_identical(eval(formals(add_unreferenced_prior_mass)$withhold)[1], "finest")
})

test_that("REVIEW FR: by default a species whose FAMILY is referenced is withheld from an order ring", {
  out <- .fr_add(.fr_joined(), .fr_priors(), .fr_tax(), referenced_names = .fr_ref)
  wh <- attr(out, "unreferenced_withheld")
  expect_setequal(wh$taxon_name, c("Decapterus muroadsi", "Sebastolobus alascanus"))
  expect_true(all(wh$reason == "finer_rank_referenced_unmatched"))
  expect_true(all(wh$scope == "Perciformes"))
  mem <- attr(out, "unreferenced_scope_members")
  expect_identical(mem$taxon_name, "Lycodes pacificus")
  ring <- out[out$taxon_name == "Perciformes", ]
  expect_equal(ring$unreferenced_mass, 5e-3)
  expect_equal(ring$prior_mean, 1e-6 + 5e-3)
})

test_that("a species with no referenced taxon at any finer rank still joins the order ring", {
  out <- .fr_add(.fr_joined(), .fr_priors(), .fr_tax(), referenced_names = .fr_ref)
  expect_false("Lycodes pacificus" %in% attr(out, "unreferenced_withheld")$taxon_name)
  expect_true("Lycodes pacificus" %in% attr(out, "unreferenced_scope_members")$taxon_name)
})

test_that("a family-referenced species is claimed by its own family ring when the unit has one", {
  out <- .fr_add(.fr_joined(family_ring = TRUE), .fr_priors(), .fr_tax(), referenced_names = .fr_ref)
  mem <- attr(out, "unreferenced_scope_members")
  expect_identical(mem$scope[mem$taxon_name == "Decapterus muroadsi"], "Carangidae")
  expect_false("Decapterus muroadsi" %in% attr(out, "unreferenced_withheld")$taxon_name)
  expect_equal(out$unreferenced_mass[out$taxon_name == "Carangidae"], 4e-3)
})

test_that("withhold = \"genus\" reproduces the genus-only rule: the order ring claims all three", {
  skip_if_not(.fr_has_withhold())
  out <- .fr_add(.fr_joined(), .fr_priors(), .fr_tax(), referenced_names = .fr_ref, withhold = "genus")
  expect_identical(nrow(attr(out, "unreferenced_withheld")), 0L)
  expect_setequal(attr(out, "unreferenced_scope_members")$taxon_name,
                  c("Decapterus muroadsi", "Sebastolobus alascanus", "Lycodes pacificus"))
  expect_equal(out$unreferenced_mass[out$taxon_name == "Perciformes"], 4e-3 + 3e-3 + 5e-3)
})

test_that("the two rules agree exactly where no finer rank is referenced", {
  skip_if_not(.fr_has_withhold())
  ref <- "Sebastes mystinus"
  pr <- .fr_priors()[.fr_priors()$taxon_name != "Sebastolobus alascanus", ]
  tx <- .fr_tax()[.fr_tax()$taxon_name != "Sebastolobus alascanus", ]
  pr <- pr[pr$taxon_name != "Trachurus symmetricus", ]
  a <- .fr_add(.fr_joined(), pr, tx, referenced_names = ref, withhold = "genus")
  b <- .fr_add(.fr_joined(), pr, tx, referenced_names = ref, withhold = "finest")
  expect_identical(a, b)
})

test_that("withhold must be one of the two rules", {
  skip_if_not(.fr_has_withhold())
  expect_error(.fr_add(.fr_joined(), .fr_priors(), .fr_tax(), referenced_names = .fr_ref, withhold = "order"))
})
