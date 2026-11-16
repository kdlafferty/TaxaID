# A tied-anchor ring (TaxaLikely names it at the lowest common rank of the candidates tied with its anchor and lists
# their clades at the ring's own rank in ring_member_clades) collects the prior of the UNION of its member clades --
# never everything under the common rank. A row with ring_member_clades NA is unchanged.

.lca_joined <- function(members = "Littorinimorpha|Trochida", named = "Lottia gigantea") {
  data.frame(
    observation_id = "E1",
    taxon_name = c(named, "Gastropoda"),
    taxon_name_rank = c("species", "class"),
    hypothesis_type = c("specific_candidate", "unreferenced_family"),   # the order ring, named at the class LCA
    ring_member_clades = c(NA, members),
    score_likelihood = c(1, 0.4), score_likelihood_mean = c(1, 0.4), score_likelihood_sd = 0,
    prior_mean = c(1e-5, 3e-6), prior_alpha = c(0.01, 0.003), prior_beta = c(999.99, 999.997),
    grid_id = "site1", main_habitat = "Marine", stringsAsFactors = FALSE
  )
}
.lca_priors <- function() {
  data.frame(
    taxon_name = c("Littorina littorea", "Littorina keenae", "Lacuna vincta", "Tegula funebralis", "Nucella emarginata"),
    taxon_name_rank = "species", grid_id = "site1", main_habitat = "Marine",
    theta_mean = c(1e-5, 4e-3, 1e-3, 2e-2, 5e-3),
    alpha = c(0.01, 4, 1, 20, 5), beta = c(999.99, 996, 999, 980, 995), stringsAsFactors = FALSE
  )
}
.lca_tax <- function() {
  data.frame(
    taxon_name = .lca_priors()$taxon_name,
    genus = c("Littorina", "Littorina", "Lacuna", "Tegula", "Nucella"),
    family = c("Littorinidae", "Littorinidae", "Littorinidae", "Tegulidae", "Muricidae"),
    order = c("Littorinimorpha", "Littorinimorpha", "Littorinimorpha", "Trochida", "Neogastropoda"),
    class = "Gastropoda", stringsAsFactors = FALSE
  )
}
# the named candidate (referenced) sits OUTSIDE the member clades, so no floor-rule withholding touches the union sum
.lca_run <- function(j = .lca_joined(), ref = "Lottia gigantea", ...) {
  suppressMessages(add_unreferenced_prior_mass(j, .lca_priors(), .lca_tax(), referenced_names = ref, ...))
}
# registry fixtures (helper-registry.R) with local table builders
.lj <- function(rows) data.frame(observation_id = "E1", grid_id = "s1", rows, prior_mean = 1e-4, prior_alpha = 0.01, prior_beta = 99.99,
                                 stringsAsFactors = FALSE)
.lp <- function(names, theta) data.frame(taxon_name = names, taxon_name_rank = "species", grid_id = "s1", theta_mean = theta,
                                         alpha = theta * 1000, beta = (1 - theta) * 1000, stringsAsFactors = FALSE)
.la <- function(...) suppressMessages(add_unreferenced_prior_mass(...))

test_that("a tied-anchor ring sums the UNION of its member clades, not everything under the common rank", {
  out <- .lca_run()
  r <- out[out$hypothesis_type == "unreferenced_family", ]
  # Littorinimorpha: L. keenae 4e-3 + Lacuna vincta 1e-3 (L. littorea's theta is 1e-5 and it is unreferenced here, so it
  # counts too); Trochida: Tegula 2e-2.
  # NOT Nucella (Neogastropoda), which is a gastropod outside the member clades.
  expect_equal(r$unreferenced_mass, 1e-5 + 4e-3 + 1e-3 + 2e-2)
  expect_identical(r$unreferenced_n_species, 4L)
  expect_equal(r$prior_mean, 3e-6 + 1e-5 + 4e-3 + 1e-3 + 2e-2)
  expect_identical(r$unreferenced_scope, "Littorinimorpha|Trochida")
  expect_identical(r$unreferenced_scope_rank, "order")
  mem <- attr(out, "unreferenced_scope_members")
  expect_setequal(mem$taxon_name, c("Littorina littorea", "Littorina keenae", "Lacuna vincta", "Tegula funebralis"))
  expect_false("Nucella emarginata" %in% mem$taxon_name)
  expect_identical(anyDuplicated(mem$taxon_name), 0L)   # each species once
})

test_that("the floor rule still applies per member clade: a referenced Littorina withholds its congener and confamilial", {
  out <- .lca_run(.lca_joined(named = "Littorina littorea"), ref = "Littorina littorea")
  r <- out[out$hypothesis_type == "unreferenced_family", ]
  expect_equal(r$unreferenced_mass, 2e-2)   # Tegula only
  w <- attr(out, "unreferenced_withheld")
  expect_setequal(w$taxon_name, c("Littorina keenae", "Lacuna vincta"))
})

test_that("a single member clade gives that clade's mass alone", {
  r <- .lca_run(.lca_joined("Trochida"))
  expect_equal(r$unreferenced_mass[2], 2e-2)
})

test_that("ring_member_clades NA: the class-named ring keeps its floor, exactly as without the column", {
  j <- .lca_joined(NA_character_)
  with_col <- .lca_run(j)
  without <- .lca_run(j[, setdiff(names(j), "ring_member_clades")])
  expect_identical(with_col$prior_mean, without$prior_mean)
  expect_identical(with_col$unreferenced_mass, without$unreferenced_mass)
  expect_identical(with_col$prior_mean[2], 3e-6)   # class != the order ring's rank: no scope, floor kept
  expect_identical(nrow(attr(with_col, "ring_member_clades_withheld")), 0L)
})

test_that("registry path: member clades are mapped to ids; a clade with no id is withheld and reported", {
  .rg_skip(); reg <- .rg_registry()
  # the family ring (unreferenced_genus) named at the order its tied anchors share, members Labridae | Embiotocidae
  # the fixture registry holds no order, and attach_taxon_ids() refuses an unregistered name, so the ring row carries a
  # registered name here; the union reads only ring_member_clades, never the row's own name
  j <- .lj(data.frame(taxon_name = c("Embiotoca jacksoni", "Embiotocidae"), taxon_name_rank = c("species", "family"),
                             hypothesis_type = c("specific_candidate", "unreferenced_genus"),
                             ring_member_clades = c(NA, "Embiotocidae|Labridae"), stringsAsFactors = FALSE))
  p <- .lp(c("Oxyjulis californica", "Hypsurus caryi", "Halichoeres semicinctus"), c(0.02, 0.03, 0.01))
  by_id <- .la(.rg_stamp(j, reg, "joined"), .rg_stamp(p, reg, "priors"), NULL,
                 referenced_names = .rg_id(reg, "Embiotoca jacksoni"), registry = reg)
  expect_equal(by_id$unreferenced_mass[2], 0.02 + 0.03 + 0.01)
  expect_identical(by_id$unreferenced_scope[2], "Embiotocidae|Labridae")
  expect_identical(by_id$taxon_name, j$taxon_name)              # names put back
  # one member clade the registry does not hold: withheld, the other still counts
  j2 <- j; j2$ring_member_clades[2] <- "Embiotocidae|Notaclade"
  by2 <- .la(.rg_stamp(j2, reg, "joined"), .rg_stamp(p, reg, "priors"), NULL,
               referenced_names = .rg_id(reg, "Embiotoca jacksoni"), registry = reg)
  expect_equal(by2$unreferenced_mass[2], 0.03)
  w <- attr(by2, "ring_member_clades_withheld")
  expect_identical(w$member_clade, "Notaclade"); expect_identical(w$reason, "member_clade_no_registry_id")
})
