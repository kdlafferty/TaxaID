# tests/testthat/test-unreferenced_prior_mass.R

.upm_joined <- function() {
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
    grid_id = "site1",
    main_habitat = "Marine",
    stringsAsFactors = FALSE
  )
}
.upm_priors <- function() {
  sp <- c(
    "Littorina littorea", "Littorina keenae", "Littorina scutulata",
    "Lacuna vincta", "Lacuna unifasciata", "Tegula funebralis"
  )
  data.frame(
    taxon_name = sp,
    taxon_name_rank = "species",
    grid_id = "site1",
    main_habitat = "Marine",
    theta_mean = c(1e-5, 4e-3, 2e-3, 1e-3, 5e-4, 2e-2),
    alpha = c(0.01, 4, 2, 1, 0.5, 20),
    beta = c(999.99, 996, 998, 999, 999.5, 980),
    stringsAsFactors = FALSE
  )
}
.upm_tax <- function() {
  data.frame(
    taxon_name = .upm_priors()$taxon_name,
    genus = c("Littorina", "Littorina", "Littorina", "Lacuna", "Lacuna", "Tegula"),
    family = c(rep("Littorinidae", 5), "Tegulidae"),
    stringsAsFactors = FALSE
  )
}
.upm_run <- function(ref = c("Littorina littorea", "Littorina scutulata"), ...) {
  suppressMessages(add_unreferenced_prior_mass(
    .upm_joined(), .upm_priors(), .upm_tax(),
    referenced_names = ref, ...
  ))
}

test_that("genus scope adds only unreferenced, un-named congeners", {
  out <- .upm_run()
  g <- out[out$taxon_name == "Littorina", ]
  # L. littorea is named (and referenced); L. scutulata is referenced;
  # only L. keenae (4e-3) is an unreferenced local congener
  expect_equal(g$unreferenced_mass, 4e-3)
  expect_equal(g$unreferenced_n_species, 1L)
  expect_equal(g$prior_mean, 3e-6 + 4e-3)
  expect_equal(g$prior_mean_floor, 3e-6)
})

test_that("coarse prior rows labelled as species are not summed", {
  p <- rbind(.upm_priors(), data.frame(
    taxon_name = c("Littorinidae", "Lacuna"), taxon_name_rank = "species",
    grid_id = "site1", main_habitat = "Marine", theta_mean = c(0.05, 0.01),
    alpha = c(50, 10), beta = c(950, 990), stringsAsFactors = FALSE
  ))
  tx <- rbind(.upm_tax(), data.frame(
    taxon_name = c("Littorinidae", "Lacuna"), genus = c(NA, "Lacuna"),
    family = "Littorinidae", stringsAsFactors = FALSE
  ))
  out <- suppressMessages(add_unreferenced_prior_mass(.upm_joined(), p, tx,
    referenced_names = c("Littorina littorea", "Littorina scutulata")
  ))
  expect_equal(out$unreferenced_mass[out$taxon_name == "Littorinidae"], 1e-3 + 5e-4)
  expect_equal(attr(out, "unreferenced_mass_check")$n_coarse_prior_rows_excluded, 2L)
})

test_that("the species behind each added mass are listed", {
  out <- .upm_run()
  mem <- attr(out, "unreferenced_scope_members")
  expect_equal(sort(mem$taxon_name[mem$scope == "Littorina"]), "Littorina keenae")
  expect_equal(sort(mem$taxon_name[mem$scope == "Littorinidae"]), c("Lacuna unifasciata", "Lacuna vincta"))
  g <- out[out$taxon_name == "Littorinidae", ]
  expect_equal(sum(mem$theta_mean[mem$scope == "Littorinidae"]), g$unreferenced_mass)
})

test_that("family scope excludes the genus already covered by the finer scope", {
  out <- .upm_run()
  f <- out[out$taxon_name == "Littorinidae", ]
  # Lacuna vincta + Lacuna unifasciata; Littorina spp. are claimed by the
  # genus row; Tegula is another family
  expect_equal(f$unreferenced_mass, 1e-3 + 5e-4)
  expect_equal(f$unreferenced_n_species, 2L)
})

test_that("without a genus row, the family scope takes the congeners too", {
  j <- .upm_joined()[c(1, 3), ]
  out <- suppressMessages(add_unreferenced_prior_mass(j, .upm_priors(), .upm_tax(),
    referenced_names = c("Littorina littorea", "Littorina scutulata")
  ))
  expect_equal(out$unreferenced_mass[out$taxon_name == "Littorinidae"], 4e-3 + 1e-3 + 5e-4)
})

test_that("specific candidates are untouched and carry NA diagnostics", {
  out <- .upm_run()
  c1 <- out[out$hypothesis_type == "specific_candidate", ]
  expect_equal(c1$prior_mean, 1e-5)
  expect_true(is.na(c1$unreferenced_mass))
})

test_that("updated rows keep a valid Beta whose mean equals prior_mean", {
  out <- .upm_run()
  ch <- out[!is.na(out$unreferenced_mass) & out$unreferenced_mass > 0, ]
  expect_true(all(ch$prior_alpha > 0 & ch$prior_beta > 0))
  expect_equal(ch$prior_alpha / (ch$prior_alpha + ch$prior_beta), ch$prior_mean)
})

test_that("a scope with no unreferenced local relatives is left unchanged", {
  out <- .upm_run(ref = .upm_priors()$taxon_name) # everything referenced
  g <- out[out$hypothesis_type != "specific_candidate", ]
  expect_equal(g$unreferenced_mass, c(0, 0))
  expect_equal(g$prior_mean, c(3e-6, 3e-6))
  expect_equal(g$prior_alpha, c(0.003, 0.003))
})

test_that("placeholder scopes absent from the taxonomy gain nothing", {
  j <- .upm_joined()
  j$taxon_name[3] <- "unk_family"
  out <- suppressMessages(add_unreferenced_prior_mass(j, .upm_priors(), .upm_tax(),
    referenced_names = "Littorina littorea"
  ))
  expect_equal(out$unreferenced_mass[out$taxon_name == "unk_family"], 0)
  expect_equal(out$prior_mean[out$taxon_name == "unk_family"], 3e-6)
})

test_that("other habitats and other sites do not contribute", {
  p <- .upm_priors()
  p <- rbind(p, transform(p[2, ], main_habitat = "Terrestrial", theta_mean = 0.5))
  p <- rbind(p, transform(p[2, ], grid_id = "site2", theta_mean = 0.5))
  out <- suppressMessages(add_unreferenced_prior_mass(.upm_joined(), p, .upm_tax(),
    referenced_names = c("Littorina littorea", "Littorina scutulata")
  ))
  expect_equal(out$unreferenced_mass[out$taxon_name == "Littorina"], 4e-3)
})

test_that("backbone check messages when named candidates are missing from referenced_names", {
  expect_message(
    out <- add_unreferenced_prior_mass(.upm_joined(), .upm_priors(), .upm_tax(),
      referenced_names = "Littorina scutulata" # L. littorea (a candidate) missing
    ),
    "different backbone"
  )
  chk <- attr(out, "unreferenced_mass_check")
  expect_equal(chk$n_candidates, 1L)
  expect_equal(chk$n_candidates_not_referenced, 1L)
})

test_that("more than one site in joined is refused", {
  j <- rbind(.upm_joined(), transform(.upm_joined(), grid_id = "site2"))
  expect_error(
    add_unreferenced_prior_mass(j, .upm_priors(), .upm_tax(), "Littorina littorea"),
    "one site at a time"
  )
})

test_that("presence-mixture columns are cleared on rows that gain mass", {
  j <- .upm_joined()
  j$prior_mix_w <- c(NA, 0.2, NA)
  j$prior_mix_theta_present <- c(NA, 1e-4, NA)
  j$prior_mix_theta_absent <- c(NA, 0, NA)
  out <- suppressMessages(add_unreferenced_prior_mass(j, .upm_priors(), .upm_tax(),
    referenced_names = c("Littorina littorea", "Littorina scutulata")
  ))
  expect_true(is.na(out$prior_mix_w[out$taxon_name == "Littorina"]))
})

test_that("smoke: an implausible candidate no longer wins once relatives carry their mass", {
  set.seed(1) # may simulate (n_sims defaults to 1000): seeded so other tests cannot shift its stream
  j <- .upm_joined()
  before <- suppressMessages(compute_posterior(j, n_sims = 0))
  after <- suppressMessages(compute_posterior(
    .upm_run()[, names(j)],
    n_sims = 0
  ))
  p_before <- before$posterior_point_est[before$taxon_name == "Littorina littorea"]
  p_after <- after$posterior_point_est[after$taxon_name == "Littorina littorea"]
  # before: 1e-5 vs floors of 3e-6 -> the out-of-range species wins
  expect_gt(p_before, 0.5)
  # after: the unreferenced local congener hypothesis carries 4e-3
  expect_lt(p_after, 0.05)
  expect_equal(
    after$taxon_name[which.max(after$posterior_point_est)], "Littorina"
  )
})
