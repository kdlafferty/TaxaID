# tests/testthat/test-unreferenced_prior_mass_withheld.R
#
# Withheld species in add_unreferenced_prior_mass(): a local unreferenced
# species whose genus has a reference (the first word of `referenced_names`)
# may be claimed only by its own genus ring. Fully offline. Fixture helpers
# .upm_joined(), .upm_priors(), .upm_tax() come from
# test-unreferenced_prior_mass.R (testthat sources all helper-/test- files in
# one environment per file, so they are redefined here under distinct names).

.wh_cols <- c("observation_id", "taxon_name", "scope", "scope_rank", "reason")

.wh_littorina_joined <- function() {
  data.frame(
    observation_id = "E1",
    taxon_name = c("Littorina littorea", "Littorina", "Littorinidae"),
    taxon_name_rank = c("species", "genus", "family"),
    hypothesis_type = c("specific_candidate", "unreferenced_species", "unreferenced_genus"),
    score_likelihood = c(1, 0.3, 0.05),
    score_likelihood_mean = c(1, 0.3, 0.05),
    score_likelihood_sd = 0,
    prior_mean = c(1e-5, 3e-6, 3e-6),
    prior_alpha = c(0.01, 0.003, 0.003),
    prior_beta = c(999.99, 999.997, 999.997),
    grid_id = "site1", main_habitat = "Marine", stringsAsFactors = FALSE
  )
}
.wh_littorina_priors <- function() {
  sp <- c("Littorina littorea", "Littorina keenae", "Littorina scutulata",
          "Lacuna vincta", "Lacuna unifasciata", "Tegula funebralis")
  data.frame(taxon_name = sp, taxon_name_rank = "species", grid_id = "site1",
    main_habitat = "Marine", theta_mean = c(1e-5, 4e-3, 2e-3, 1e-3, 5e-4, 2e-2),
    alpha = c(0.01, 4, 2, 1, 0.5, 20), beta = c(999.99, 996, 998, 999, 999.5, 980),
    stringsAsFactors = FALSE)
}
.wh_littorina_tax <- function() {
  data.frame(taxon_name = .wh_littorina_priors()$taxon_name,
    genus = c("Littorina", "Littorina", "Littorina", "Lacuna", "Lacuna", "Tegula"),
    family = c(rep("Littorinidae", 5), "Tegulidae"), stringsAsFactors = FALSE)
}

# ---- 1. Punta Baja shape ------------------------------------------------------

.pb_joined <- function() {
  data.frame(
    observation_id = "12S_ESV_144804",
    taxon_name = c("Clinocottus analis", "Cottidae"),
    taxon_name_rank = c("species", "family"),
    hypothesis_type = c("specific_candidate", "unreferenced_genus"),
    score_likelihood = c(0.3, 1.0),
    score_likelihood_mean = c(0.3, 1.0),
    score_likelihood_sd = 0,
    prior_mean = c(1e-4, 1e-6),
    prior_alpha = c(0.1, 0.001),
    prior_beta = c(999.9, 999.999),
    grid_id = "site1", main_habitat = "Marine",
    species = c("Clinocottus analis", NA),
    genus = c("Clinocottus", NA),
    family = "Cottidae",
    stringsAsFactors = FALSE
  )
}
.pb_priors <- function() {
  data.frame(
    taxon_name = c("Oligocottus rubellio", "Oligocottus rimensis", "Clinocottus analis"),
    taxon_name_rank = "species", grid_id = "site1", main_habitat = "Marine",
    theta_mean = c(0.02, 0.005, 1e-4),
    alpha = c(20, 5, 0.1), beta = c(980, 995, 999.9),
    stringsAsFactors = FALSE
  )
}
.pb_tax <- function() {
  data.frame(
    taxon_name = .pb_priors()$taxon_name,
    genus = c("Oligocottus", "Oligocottus", "Clinocottus"),
    family = "Cottidae", stringsAsFactors = FALSE
  )
}
.pb_run <- function(ref, ...) {
  suppressMessages(add_unreferenced_prior_mass(.pb_joined(), .pb_priors(), .pb_tax(),
    referenced_names = ref, ...))
}
.pb_call <- function(out) {
  post <- suppressMessages(compute_posterior(out, n_sims = 0))
  suppressMessages(posterior_consensus(post, rank_system = c("family", "genus", "species"),
    posterior_col = "posterior_point_est", consensus_method = "credible_node",
    likelihood_consensus = FALSE, robust_prior_s = 0))
}

test_that("Punta Baja: species of a referenced genus with no genus ring are not named from the family ring", {
  out <- .pb_run(c("Oligocottus snyderi", "Clinocottus analis"), named_rows = TRUE)
  expect_false(any(c("Oligocottus rubellio", "Oligocottus rimensis") %in% out$taxon_name))
  w <- attr(out, "unreferenced_withheld")
  expect_s3_class(w, "data.frame")
  expect_named(w, .wh_cols)
  expect_setequal(w$taxon_name, c("Oligocottus rubellio", "Oligocottus rimensis"))
  expect_true(all(w$scope == "Cottidae"))
  expect_true(all(w$scope_rank == "family"))
  expect_true(all(w$reason == "genus_referenced_unmatched"))
  expect_true(all(w$observation_id == "12S_ESV_144804"))
  # the family ring's mass excludes both withheld thetas (nothing else is local
  # and unreferenced), and no species is listed as its member
  ring <- out[out$taxon_name == "Cottidae", ]
  expect_equal(ring$unreferenced_mass, 0)
  expect_equal(ring$prior_mean, 1e-6)
  expect_equal(nrow(attr(out, "unreferenced_scope_members")), 0L)
})

test_that("Punta Baja: the withheld species is not the call", {
  out <- .pb_run(c("Oligocottus snyderi", "Clinocottus analis"), named_rows = TRUE)
  cons <- .pb_call(out)
  expect_false(identical(cons$consensus_taxon, "Oligocottus rubellio"))
  expect_false(grepl("^Oligocottus", cons$consensus_taxon))
  # Only the specific candidate (likelihood 0.3, prior 1e-4) and the family ring
  # (likelihood 1.0, prior 1e-6) remain, so the call is one of the two.
  # The numbers give the species: the 0.3 likelihood x 1e-4 prior outweighs the
  # family ring's 1.0 x 1e-6 (no withheld mass is added to it).
  expect_identical(cons$consensus_taxon, "Clinocottus analis")
})

test_that("Punta Baja: the same inputs with Oligocottus UNreferenced name Oligocottus rubellio from the family ring", {
  out <- .pb_run("Clinocottus analis", named_rows = TRUE)
  expect_true(all(c("Oligocottus rubellio", "Oligocottus rimensis") %in% out$taxon_name))
  w <- attr(out, "unreferenced_withheld")
  expect_equal(nrow(w), 0L)
  expect_named(w, .wh_cols)
  nr <- out[out$taxon_name %in% c("Oligocottus rubellio", "Oligocottus rimensis"), ]
  expect_true(all(nr$score_likelihood == 1.0)) # the family ring's likelihood
  expect_equal(out$unreferenced_n_species[out$taxon_name == "Cottidae"], 2L)
  cons <- .pb_call(out)
  # the family ring's likelihood (1.0) times the 0.02 / 0.005 priors beats the
  # candidate, so the call is an Oligocottus; with two Oligocottus species
  # sharing the mass the credible node is the genus, and the genus it names is
  # exactly the one the rule withholds above.
  expect_identical(cons$consensus_taxon, "Oligocottus")
  expect_true(grepl("^Oligocottus", cons$consensus_taxon))
})

test_that("Punta Baja: without named_rows the withheld thetas are also left out of the family ring mass", {
  held <- .pb_run(c("Oligocottus snyderi", "Clinocottus analis"))
  open <- .pb_run("Clinocottus analis")
  expect_equal(held$unreferenced_mass[held$taxon_name == "Cottidae"], 0)
  expect_equal(open$unreferenced_mass[open$taxon_name == "Cottidae"], 0.02 + 0.005)
  expect_equal(nrow(attr(held, "unreferenced_withheld")), 2L)
})

# ---- 2. Genus ring present ----------------------------------------------------

test_that("a species of a referenced genus is claimed by its genus ring, not withheld", {
  out <- suppressMessages(add_unreferenced_prior_mass(.wh_littorina_joined(),
    .wh_littorina_priors(), .wh_littorina_tax(),
    referenced_names = c("Littorina littorea", "Littorina scutulata"), named_rows = TRUE))
  w <- attr(out, "unreferenced_withheld")
  expect_equal(nrow(w), 0L)
  k <- out[out$taxon_name == "Littorina keenae", ]
  expect_equal(nrow(k), 1L)
  expect_identical(k$unreferenced_scope, "Littorina")
  expect_identical(k$unreferenced_scope_rank, "genus")
  expect_equal(k$score_likelihood, 0.3)
  # and the family ring does not also take it
  mem <- attr(out, "unreferenced_scope_members")
  expect_identical(mem$scope[mem$taxon_name == "Littorina keenae"], "Littorina")
})

# ---- 3. Coarser rings ---------------------------------------------------------

test_that("a species of a referenced genus is withheld from the order and class rings; an unreferenced genus joins the finest", {
  base <- .wh_littorina_joined()[1, ]
  j <- rbind(base,
    transform(base, taxon_name = "Littorinimorpha", taxon_name_rank = "order",
      hypothesis_type = "unreferenced_family", score_likelihood = 0.1, score_likelihood_mean = 0.1),
    transform(base, taxon_name = "Gastropoda", taxon_name_rank = "class",
      hypothesis_type = "unreferenced_order", score_likelihood = 0.02, score_likelihood_mean = 0.02))
  j$hypothesis_type[1] <- "specific_candidate"
  tax <- .wh_littorina_tax()
  tax$order <- c(rep("Littorinimorpha", 5), "Trochida")
  tax$class <- "Gastropoda"
  out <- suppressMessages(add_unreferenced_prior_mass(j, .wh_littorina_priors(), tax,
    referenced_names = c("Littorina littorea", "Littorina scutulata"), named_rows = TRUE))
  w <- attr(out, "unreferenced_withheld")
  expect_named(w, .wh_cols)
  # Littorina keenae: genus referenced, no genus ring -> withheld ONCE, at the
  # order ring (the finest containing it), and not again at the class ring
  expect_identical(w$taxon_name, "Littorina keenae")
  expect_identical(w$scope, "Littorinimorpha")
  expect_identical(w$scope_rank, "order")
  expect_false("Littorina keenae" %in% out$taxon_name)
  # Lacuna (no reference in the genus): the finest ring containing it, the order
  lac <- out[out$taxon_name %in% c("Lacuna vincta", "Lacuna unifasciata"), ]
  expect_equal(nrow(lac), 2L)
  expect_true(all(lac$unreferenced_scope == "Littorinimorpha"))
  expect_true(all(lac$score_likelihood == 0.1))
  # Tegula (Trochida, same class): only the class ring contains it
  teg <- out[out$taxon_name == "Tegula funebralis", ]
  expect_equal(nrow(teg), 1L)
  expect_identical(teg$unreferenced_scope, "Gastropoda")
  expect_equal(teg$score_likelihood, 0.02)
})

test_that("a referenced-genus species not contained in a finer ring is withheld at the coarser ring that does contain it", {
  # No order ring covers Trochida; make Tegula a referenced genus.
  base <- .wh_littorina_joined()[1, ]
  j <- rbind(base,
    transform(base, taxon_name = "Littorinimorpha", taxon_name_rank = "order",
      hypothesis_type = "unreferenced_family", score_likelihood = 0.1, score_likelihood_mean = 0.1),
    transform(base, taxon_name = "Gastropoda", taxon_name_rank = "class",
      hypothesis_type = "unreferenced_order", score_likelihood = 0.02, score_likelihood_mean = 0.02))
  tax <- .wh_littorina_tax()
  tax$order <- c(rep("Littorinimorpha", 5), "Trochida")
  tax$class <- "Gastropoda"
  out <- suppressMessages(add_unreferenced_prior_mass(j, .wh_littorina_priors(), tax,
    referenced_names = c("Littorina littorea", "Tegula gallina"), named_rows = TRUE))
  w <- attr(out, "unreferenced_withheld")
  tg <- w[w$taxon_name == "Tegula funebralis", ]
  expect_identical(tg$scope, "Gastropoda")
  expect_identical(tg$scope_rank, "class")
  expect_false("Tegula funebralis" %in% out$taxon_name)
})

# ---- 4. Empty attribute on early return and when nothing is withheld ------------

test_that("the withheld attribute is a 0-row data frame with five columns on the early-return path", {
  j <- .wh_littorina_joined()[1, ] # no generic rows at all
  out <- suppressMessages(add_unreferenced_prior_mass(j, .wh_littorina_priors(),
    .wh_littorina_tax(), referenced_names = "Littorina littorea"))
  w <- attr(out, "unreferenced_withheld")
  expect_s3_class(w, "data.frame")
  expect_equal(nrow(w), 0L)
  expect_named(w, .wh_cols)
})

test_that("the withheld attribute is a 0-row data frame with five columns when nothing is withheld", {
  for (nr in c(TRUE, FALSE)) {
    out <- suppressMessages(add_unreferenced_prior_mass(.wh_littorina_joined(),
      .wh_littorina_priors(), .wh_littorina_tax(),
      referenced_names = "Littorina littorea", named_rows = nr))
    w <- attr(out, "unreferenced_withheld")
    expect_s3_class(w, "data.frame")
    expect_equal(nrow(w), 0L)
    expect_named(w, .wh_cols)
  }
})

# ---- 5. Input-shape grid ------------------------------------------------------

.wh_ref_shapes <- list(
  empty = character(0),
  one = "Littorina littorea",
  duplicate = c("Littorina littorea", "Littorina littorea", "Littorina scutulata"),
  with_na = c("Littorina littorea", NA_character_)
)
.wh_prior_shapes <- list(
  plain = function() list(p = .wh_littorina_priors(), t = .wh_littorina_tax()),
  duplicated_species_row = function() {
    p <- .wh_littorina_priors()
    list(p = rbind(p, p[2, ]), t = .wh_littorina_tax())
  },
  na_genus = function() {
    t <- .wh_littorina_tax()
    t$genus[2] <- NA # Littorina keenae
    list(p = .wh_littorina_priors(), t = t)
  }
)

for (nr in c(TRUE, FALSE)) {
  for (rs in names(.wh_ref_shapes)) {
    for (ps in names(.wh_prior_shapes)) {
      local({
        nr <- nr; rs <- rs; ps <- ps
        test_that(sprintf("input shape: named_rows=%s, referenced_names=%s, priors=%s", nr, rs, ps), {
          sh <- .wh_prior_shapes[[ps]]()
          ref <- .wh_ref_shapes[[rs]]
          # referenced_names = character(0) and NA entries are accepted by the
          # function's own validation (only is.character() is checked), so the
          # normal contract is asserted here, not an error.
          out <- NULL
          expect_no_error(out <- suppressMessages(add_unreferenced_prior_mass(
            .wh_littorina_joined(), sh$p, sh$t, referenced_names = ref, named_rows = nr)))
          w <- attr(out, "unreferenced_withheld")
          expect_s3_class(w, "data.frame")
          expect_named(w, .wh_cols)
          sp <- out[out$taxon_name_rank == "species" & !is.na(out$taxon_name), ]
          expect_false(anyDuplicated(paste(sp$observation_id, sp$taxon_name, sep = "\r")) > 0L)
          expect_false(anyDuplicated(w[, c("observation_id", "taxon_name")]) > 0L)
          if (nr && nrow(w)) expect_false(any(w$taxon_name %in% out$taxon_name[out$hypothesis_type == "unreferenced_species" & !is.na(out$unreferenced_scope) & out$taxon_name_rank == "species"]))
        })
      })
    }
  }
}

test_that("a non-character referenced_names is rejected by the function's own validation", {
  expect_error(suppressMessages(add_unreferenced_prior_mass(.wh_littorina_joined(),
    .wh_littorina_priors(), .wh_littorina_tax(), referenced_names = NA)), "character vector")
})
