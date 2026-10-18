mk <- function(taxon = "Fundulus parvipinnis", rank = "species", poor = FALSE,
               geo = "likely", hab = "likely", scp = "likely", bir = "species", ...) {
  data.frame(observation_id = paste0("o", seq_along(taxon)), consensus_taxon = taxon,
             consensus_rank = rank, best_identity_rank = bir, poor_absolute_fit = poor,
             llm_geographic_plausibility = geo, llm_habitat_plausibility = hab,
             llm_scope_plausibility = scp, stringsAsFactors = FALSE, ...)
}
post <- function(obs = "o1", name = c("Fundulus parvipinnis", "Fundulus heteroclitus"),
                 rank = "species", type = c("specific_candidate", "specific_candidate"),
                 genus = "Fundulus", family = "Fundulidae", score = c(1, 0.8),
                 theta = c(NA, 0.2), branch = c("none", "kernel_estimated")) {
  data.frame(observation_id = obs, taxon_name = name, taxon_name_rank = rank,
             hypothesis_type = type, genus = genus, family = family,
             score_likelihood = score, theta_mean = theta, prior_branch = branch,
             stringsAsFactors = FALSE)
}
scr <- function(...) suppressMessages(screen_assignments(...))

test_that("I1 keeps good fit with plausible geography", {
  for (g in c("likely", "possible")) {
    r <- scr(mk(geo = g))
    expect_equal(r$identity_action, "keep")
    expect_equal(r$suggested_action, "keep")
  }
  r <- scr(mk())
  expect_equal(r$identity_taxon_after, "Fundulus parvipinnis")
  expect_match(r$identity_reason, "I1")
})

test_that("I2 without posterior_df is always review", {
  r <- scr(mk(geo = "unlikely"))
  expect_equal(r$identity_action, "review")
  expect_equal(r$suggested_action, "exclude")
  expect_equal(r$identity_taxon_after, "Fundulus parvipinnis")
})

test_that("I2 moves up to genus for a qualifying local referenced congener", {
  r <- scr(mk(geo = "unlikely"), post())
  expect_equal(r$identity_action, "move_up")
  expect_equal(r$identity_taxon_after, "Fundulus")
  expect_equal(r$identity_rank_after, "genus")
  expect_equal(r$suggested_action, "move_up")
})

test_that("I2 score gap boundary is inclusive at 0.25", {
  inside <- scr(mk(geo = "unlikely"), post(score = c(1, 0.76)))
  outside <- scr(mk(geo = "unlikely"), post(score = c(1, 0.74)))
  expect_equal(inside$identity_action, "move_up")
  expect_equal(outside$identity_action, "review")
  wide <- scr(mk(geo = "unlikely"), post(score = c(1, 0.5)), relative_score_gap = 0.5)
  expect_equal(wide$identity_action, "move_up")
})

test_that("I2 relative must be local and referenced (Fundulus-like score 0 stays review)", {
  expect_equal(scr(mk(geo = "unlikely"), post(score = c(1, 0)))$identity_action, "review")
  notlocal <- scr(mk(geo = "unlikely"), post(theta = c(NA, NA), branch = c("none", "none")))
  expect_equal(notlocal$identity_action, "review")
  notref <- scr(mk(geo = "unlikely"), post(type = c("specific_candidate", "unreferenced_species")))
  expect_equal(notref$identity_action, "review")
  resident <- scr(mk(geo = "unlikely"), post(theta = c(NA, NA), branch = c("none", "resident_observed")))
  expect_equal(resident$identity_action, "move_up")
  theta_only <- scr(mk(geo = "unlikely"), post(branch = c("none", "none")))
  expect_equal(theta_only$identity_action, "move_up")
})

test_that("I2 uses relatives of the same observation only and falls back to family", {
  other <- scr(mk(geo = "unlikely"), post(obs = "oX"))
  expect_equal(other$identity_action, "review")
  fam <- scr(mk(geo = "unlikely"),
             post(name = c("Fundulus parvipinnis", "Lucania parva"), genus = c("Fundulus", "Lucania")))
  expect_equal(fam$identity_action, "move_up")
  expect_equal(fam$identity_taxon_after, "Fundulidae")
  expect_equal(fam$identity_rank_after, "family")
})

test_that("I2 Hemilepidotus-like genus-level move-up", {
  p <- post(name = c("Hemilepidotus hemilepidotus", "Hemilepidotus spinosus"),
            genus = "Hemilepidotus", family = "Cottidae", score = c(0.9, 0.85))
  r <- scr(mk("Hemilepidotus hemilepidotus", geo = "unlikely"), p)
  expect_equal(r$identity_action, "move_up")
  expect_equal(r$identity_taxon_after, "Hemilepidotus")
})

test_that("I3 moves up at the genus boundary and flags coarser calls", {
  sp <- scr(mk(poor = TRUE), post())
  expect_equal(sp$identity_action, "move_up")
  expect_equal(sp$identity_rank_after, "genus")
  expect_equal(sp$identity_taxon_after, "Fundulus")
  ge <- scr(mk("Fundulus", "genus", poor = TRUE, bir = "genus"), post())
  expect_equal(ge$identity_action, "move_up")
  expect_equal(ge$identity_rank_after, "family")
  expect_equal(ge$identity_taxon_after, "Fundulidae")
  fa <- scr(mk("Fundulidae", "family", poor = TRUE, bir = "family"), post())
  expect_equal(fa$identity_action, "keep")
  expect_true(fa$poor_fit_flag)
  expect_equal(sp$poor_fit_flag, FALSE)
  wide <- scr(mk("Fundulidae", "family", poor = TRUE, bir = "family"), post(), move_up_max_rank = "family")
  expect_equal(wide$identity_action, "move_up")
  expect_equal(wide$identity_rank_after, "order")
})

test_that("I3 uses best_identity_rank when coarser than the call", {
  r <- scr(mk(poor = TRUE, bir = "family"), post())
  expect_equal(r$identity_rank_after, "family")
  expect_equal(r$identity_taxon_after, "Fundulidae")
})

test_that("unreferenced exception needs unreferenced winner, species, geography likely", {
  d <- mk(poor = TRUE, winner_hypothesis_type = "unreferenced_species")
  expect_equal(scr(d)$identity_action, "keep")
  expect_false(scr(d)$poor_fit_flag)
  expect_equal(scr(transform(d, llm_geographic_plausibility = "possible"))$identity_action, "move_up")
  expect_equal(scr(transform(d, winner_hypothesis_type = "specific_candidate"))$identity_action, "move_up")
})

test_that("habitat exclusion applies at family or finer, after the exception", {
  expect_equal(scr(mk(poor = TRUE, hab = "unlikely"))$identity_action, "exclude")
  expect_equal(scr(mk("Fundulidae", "family", poor = TRUE, hab = "unlikely"))$identity_action, "exclude")
  o <- scr(mk("Fundulales", "order", poor = TRUE, hab = "unlikely"))
  expect_equal(o$identity_action, "keep")
  expect_true(o$poor_fit_flag)
  o2 <- scr(mk("Fundulales", "order", poor = TRUE, hab = "unlikely"), poor_fit_habitat_exclude_max_rank = "order")
  expect_equal(o2$identity_action, "exclude")
  ex <- scr(mk(poor = TRUE, hab = "unlikely", winner_hypothesis_type = "unreferenced_species"))
  expect_equal(ex$identity_action, "keep")
  good <- scr(mk(hab = "unlikely"))
  expect_equal(good$identity_action, "keep")
})

test_that("I4 excludes poor fit with unlikely geography and clears the taxon", {
  r <- scr(mk(poor = TRUE, geo = "unlikely"))
  expect_equal(r$identity_action, "exclude")
  expect_equal(r$suggested_action, "exclude")
  expect_true(is.na(r$identity_taxon_after))
  expect_true(is.na(r$identity_rank_after))
  expect_true(is.na(r$presence))
})

test_that("presence precedence: scope wins, then habitat, else resident", {
  expect_equal(scr(mk(scp = "unlikely", hab = "unlikely"))$presence, "out_of_scope")
  expect_equal(scr(mk(hab = "unlikely"))$presence, "off_habitat")
  expect_equal(scr(mk())$presence, "resident")
  expect_equal(scr(mk(hab = "possible"))$presence, "resident")
  r <- scr(mk(scp = "unlikely", hab = "unlikely"))
  expect_equal(r$suggested_action, "keep")
})

test_that("blank_flag_col forces suggested exclude only when TRUE", {
  d <- mk(taxon = c("A a", "B b", "C c"), blank = c(TRUE, FALSE, NA))
  r <- scr(d, blank_flag_col = "blank")
  expect_equal(r$suggested_action, c("exclude", "keep", "keep"))
  expect_equal(r$identity_action, c("keep", "keep", "keep"))
  expect_match(r$identity_reason[1], "blank evidence")
  expect_no_match(r$identity_reason[2], "blank evidence")
  n <- scr(d)
  expect_equal(n$suggested_action, rep("keep", 3))
  expect_error(scr(d, blank_flag_col = "nope"), "blank_flag_col")
})

test_that("isolated_geography_unlikely is TRUE, FALSE or NA", {
  d <- mk(taxon = c("A a", "A a", "B b", "C c"), geo = c("unlikely", "unlikely", "unlikely", "likely"),
          n_tubes = c(1, 2, 4, 1))
  d$observation_id <- paste0("o", 1:4)
  r <- scr(d)
  expect_equal(r$isolated_geography_unlikely, c(TRUE, TRUE, FALSE, FALSE))
  d2 <- d; d2$n_tubes[3] <- NA
  expect_true(is.na(scr(d2)$isolated_geography_unlikely[3]))
  expect_true(all(is.na(scr(mk(geo = "unlikely"))$isolated_geography_unlikely)))
  expect_equal(scr(d)$suggested_action[1], "exclude") # review row; flag itself never acts
  e <- scr(mk(geo = "likely", n_tubes = 1))
  expect_equal(e$suggested_action, "keep")
})

test_that("NA verdicts trigger no rule", {
  expect_equal(scr(mk(geo = NA_character_))$identity_action, "keep")
  expect_equal(scr(mk(poor = NA))$identity_action, "keep")
  r <- scr(mk(hab = NA_character_, scp = NA_character_))
  expect_true(is.na(r$presence))
  expect_equal(r$suggested_action, "keep")
  p <- scr(mk(poor = TRUE, geo = NA_character_, hab = NA_character_))
  expect_equal(p$identity_action, "move_up")
})

test_that("missing optional columns skip their rules with a message", {
  d <- mk(poor = TRUE, hab = "unlikely", scp = "unlikely")
  d$llm_habitat_plausibility <- NULL
  expect_message(r <- screen_assignments(d), "habitat")
  expect_equal(r$identity_action, "move_up")
  d$llm_scope_plausibility <- NULL
  expect_message(r2 <- screen_assignments(d), "scope")
  expect_true(is.na(r2$presence))
})

test_that("required columns and arguments are validated", {
  d <- mk()
  expect_error(screen_assignments(d[, setdiff(names(d), "poor_absolute_fit")]), "poor_absolute_fit")
  expect_error(screen_assignments(d[, setdiff(names(d), "observation_id")]), "observation_id")
  expect_error(screen_assignments("x"), "data frame")
  expect_error(scr(d, move_up_max_rank = "tribe"), "move_up_max_rank")
  expect_error(scr(d, relative_score_gap = -1), "relative_score_gap")
  expect_error(scr(d, posterior_df = post()[, c("observation_id", "taxon_name")]), "posterior_df")
})

test_that("rows are never dropped and order is preserved", {
  d <- mk(taxon = c("A a", "B b", "C c", "D d"), poor = c(TRUE, FALSE, TRUE, FALSE),
          geo = c("unlikely", "unlikely", "likely", "likely"))
  r <- scr(d)
  expect_equal(nrow(r), 4L)
  expect_equal(r$consensus_taxon, d$consensus_taxon)
  expect_equal(r$observation_id, d$observation_id)
  expect_true(all(names(d) %in% names(r)))
  expect_true(all(c("identity_action", "identity_taxon_after", "identity_rank_after",
                    "identity_reason", "suggested_action", "presence", "poor_fit_flag",
                    "isolated_geography_unlikely") %in% names(r)))
  expect_equal(nrow(scr(d[0, ])), 0L)
})

test_that("custom column names and a per-site geography column work", {
  d <- mk(geo = "likely")
  d$geo_site <- "unlikely"; d$pf <- TRUE
  r <- scr(d, geography_col = "geo_site", poor_fit_col = "pf")
  expect_equal(r$identity_action, "exclude")
})

test_that("output keeps every input row, its order and all original column values", {
  d <- mk(taxon = c("A a", "B b", "C c", "D d", "E e"), poor = c(TRUE, FALSE, TRUE, FALSE, TRUE),
          geo = c("unlikely", "unlikely", "likely", "likely", "unlikely"),
          hab = c("likely", "likely", "unlikely", "likely", "likely"))
  d$extra <- letters[1:5]
  r <- scr(d)
  expect_equal(nrow(r), nrow(d))
  expect_true("exclude" %in% r$suggested_action)
  expect_identical(r[names(d)], d)
})
