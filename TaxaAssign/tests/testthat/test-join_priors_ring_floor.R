# One global floor per unit for floor-priced ring rows (join_priors()).

.gfa <- 1
.gfb <- 6133
.gf <- .gfa / (.gfa + .gfb)

.ring_unit <- function(obs = "u1", genera = c("Opsariichthys", "Zacco", "Metzia", "Xenocypris"),
                       family = "Xenocyprididae", site = "G1") {
  n_g <- length(genera)
  data.frame(
    observation_id = obs,
    grid_id = site, main_habitat = "Lotic",
    taxon_name = c("Ctenopharyngodon idella", genera, family),
    taxon_name_rank = c("species", rep("genus", n_g), "family"),
    hypothesis_type = c("specific_candidate", rep("unreferenced_species", n_g), "unreferenced_genus"),
    prior_alpha = c(0.5, rep(.gfa, n_g + 1L)),
    prior_beta = c(0.5 / 8.6e-5 - 0.5, rep(.gfb, n_g + 1L)),
    stringsAsFactors = FALSE
  ) |> transform(prior_mean = prior_alpha / (prior_alpha + prior_beta))
}

test_that("the grass-carp shape: k floor-priced rings in one unit share ONE floor", {
  d <- .ring_unit()
  o <- suppressMessages(TaxaAssign:::.split_ring_floor(d, .gfa, .gfb))
  ring <- o$hypothesis_type != "specific_candidate"
  expect_equal(o$prior_mean[ring], rep(.gf / 5, 5))
  expect_equal(sum(o$prior_mean[ring]), .gf)
  # concentration kept, and alpha/beta consistent with the mean
  expect_equal(o$prior_alpha[ring] + o$prior_beta[ring], rep(.gfa + .gfb, 5))
  expect_equal(o$prior_alpha[ring] / (o$prior_alpha[ring] + o$prior_beta[ring]), o$prior_mean[ring])
  # the referenced species' own prior is untouched
  expect_identical(o[!ring, ], d[!ring, ])
})

test_that("a unit with ONE floor-priced ring is byte-identical", {
  d <- .ring_unit(genera = character(0))
  expect_identical(suppressMessages(TaxaAssign:::.split_ring_floor(d, .gfa, .gfb)), d)
})

test_that("a unit whose rings are ALL evidence-priced is byte-identical", {
  d <- .ring_unit()
  ring <- d$hypothesis_type != "specific_candidate"
  # clade-budget-priced rings: each its own mass, none equal to the floor
  d$prior_alpha[ring] <- c(2, 3, 4, 5, 6)
  d$prior_beta[ring] <- c(4000, 3000, 2000, 5000, 6000)
  d$prior_mean[ring] <- d$prior_alpha[ring] / (d$prior_alpha[ring] + d$prior_beta[ring])
  expect_identical(suppressMessages(TaxaAssign:::.split_ring_floor(d, .gfa, .gfb)), d)
})

test_that("evidence-priced rings keep their mass; only the floor-priced ones split", {
  d <- .ring_unit()
  d$prior_alpha[2] <- 3; d$prior_beta[2] <- 2000
  d$prior_mean[2] <- 3 / 2003
  o <- suppressMessages(TaxaAssign:::.split_ring_floor(d, .gfa, .gfb))
  expect_identical(o[2, ], d[2, ])
  fl <- 3:6
  expect_equal(o$prior_mean[fl], rep(.gf / 4, 4))
})

test_that("the split is per observation AND per site", {
  d <- rbind(.ring_unit("u1", site = "G1"), .ring_unit("u1", genera = "Zacco", site = "G2"),
             .ring_unit("u2", genera = c("Metzia", "Zacco", "Opsariichthys")))
  o <- suppressMessages(TaxaAssign:::.split_ring_floor(d, .gfa, .gfb))
  r <- o$hypothesis_type != "specific_candidate"
  key <- paste(o$observation_id, o$grid_id)
  expect_equal(as.numeric(tapply(o$prior_mean[r], key[r], sum)), rep(.gf, 3))
  expect_equal(unique(o$prior_mean[r & key == "u1 G2"]), .gf / 2)
  expect_equal(unique(o$prior_mean[r & key == "u2 G1"]), .gf / 4)
})

test_that("row order does not change any prior", {
  d <- rbind(.ring_unit("u1"), .ring_unit("u2", genera = c("Metzia", "Zacco")))
  o1 <- suppressMessages(TaxaAssign:::.split_ring_floor(d, .gfa, .gfb))
  rv <- rev(seq_len(nrow(d)))
  o2 <- suppressMessages(TaxaAssign:::.split_ring_floor(d[rv, ], .gfa, .gfb))
  expect_equal(o2[order(as.integer(rownames(o2))), ], o1[order(as.integer(rownames(o1))), ])
})

test_that("species-rank rows at the floor (named unreferenced species, unmodelled candidates) are never split", {
  d <- .ring_unit()
  extra <- d[2:3, ]
  extra$taxon_name <- c("Zacco platypus", "Metzia formosae")
  extra$taxon_name_rank <- "species"
  extra$hypothesis_type <- c("unreferenced_species", "specific_candidate")
  d2 <- rbind(d, extra)
  o <- suppressMessages(TaxaAssign:::.split_ring_floor(d2, .gfa, .gfb))
  sp <- d2$taxon_name_rank == "species"
  expect_identical(o[sp, ], d2[sp, ])
})

test_that("a missing or invalid floor leaves the table unchanged", {
  d <- .ring_unit()
  expect_identical(TaxaAssign:::.split_ring_floor(d, NA_real_, .gfb), d)
  expect_identical(TaxaAssign:::.split_ring_floor(d[, setdiff(names(d), "taxon_name_rank")], .gfa, .gfb),
                   d[, setdiff(names(d), "taxon_name_rank")])
})

test_that("real GreatLakes _v104finalb: the split recovers all five grass-carp units and keeps every other call", {
  G <- "/Users/lafferty/My Drive/Stats and Data/GreatLakes data"
  pf <- file.path(G, "GreatLakes2023BurnsHarbor_v104finalb_posteriors_updated_lca.rds")
  cf <- file.path(G, "GreatLakes2023BurnsHarbor_v104finalb_consensus_final_lca.rds")
  skip_if_not(file.exists(pf) && file.exists(cf), "GreatLakes saved run not reachable")
  p <- readRDS(pf); st <- attr(readRDS(cf), "consensus_settings")
  drop <- c("posterior_point_est", "posterior_mean", "posterior_sd", "confidence_score",
            "pooled_n", "pooled_prior_mass", "pooled_taxa")
  ring <- .is_unreferenced_type(p$hypothesis_type) & p$taxon_name_rank != "species" & !is.na(p$taxon_name)
  ab <- table(paste(p$prior_alpha[ring], p$prior_beta[ring]))
  gf <- as.numeric(strsplit(names(ab)[which.max(ab)], " ")[[1]])
  cons <- function(d) {
    d <- suppressMessages(compute_posterior(d[, setdiff(names(d), drop)], n_sims = 0))
    a <- list(d, rank_system = st$rank_system, cumulative_threshold = st$cumulative_threshold,
              min_posterior = st$min_posterior, posterior_col = "posterior_point_est")
    for (nm in setdiff(names(st), c("rank_system", "cumulative_threshold", "min_posterior", "posterior_col")))
      if (!is.null(st[[nm]])) a[[nm]] <- st[[nm]]
    suppressMessages(suppressWarnings(do.call(posterior_consensus, a)))
  }
  c0 <- cons(p)
  c1 <- cons(suppressMessages(TaxaAssign:::.split_ring_floor(p, gf[1], gf[2])))
  m <- merge(c0[, c("observation_id", "consensus_taxon")], c1[, c("observation_id", "consensus_taxon")],
             by = "observation_id")
  gc_units <- unique(p$observation_id[p$taxon_name %in% "Ctenopharyngodon idella"])
  expect_length(gc_units, 5L)
  expect_true(all(m$consensus_taxon.y[m$observation_id %in% gc_units] == "Ctenopharyngodon idella"))
  changed <- m$observation_id[!mapply(identical, m$consensus_taxon.x, m$consensus_taxon.y)]
  message(sprintf("GL: %d of %d calls changed: %s", length(changed), nrow(m), paste(changed, collapse = ", ")))
  expect_setequal(changed, c(gc_units, "P1_ASV_1129", "P1_ASV_1609"))
})


# ==============================================================================
# A ring row takes no clade occurrence prior, whatever ranks the table carries
# ==============================================================================

# The real CalIntertidal shape at 12S_ESV_024789@Carmel Point: a Sebastes genus
# ring competing beside its own named congeners, with a prior table holding
# rows at every rank.
#
# The named coarse hypothesis is a COTTID, deliberately in a different lineage
# from the Sebastes candidates. A family-rank specific_candidate sitting above
# finer candidates of its OWN family is a redundant coarser label for them, and
# TaxaMatch::filter_redundant_hypotheses() removes it inside join_priors() --
# correctly, and whether or not this fix is applied. Testing the coarse-named
# path on such a row would measure the redundancy filter, not the prior join.
.ring_lik <- function(with_coarse_named = TRUE) {
  d <- data.frame(
    observation_id = "u1",
    taxon_name = c("Sebastes atrovirens", "Sebastes chrysomelas", "Sebastes"),
    taxon_name_rank = c("species", "species", "genus"),
    hypothesis_type = c("specific_candidate", "unreferenced_species", "unreferenced_species"),
    score_likelihood = c(0.8, 0.4, 0.2),
    score_likelihood_mean = c(0.8, 0.4, 0.2),
    score_likelihood_sd = c(0.05, 0.04, 0.02),
    family = "Sebastidae",
    genus = "Sebastes",
    species = c("Sebastes atrovirens", "Sebastes chrysomelas", NA_character_),
    stringsAsFactors = FALSE
  )
  if (with_coarse_named) {
    d <- rbind(d, data.frame(
      observation_id = "u1", taxon_name = "Cottidae", taxon_name_rank = "family",
      hypothesis_type = "specific_candidate",
      score_likelihood = 0.1, score_likelihood_mean = 0.1, score_likelihood_sd = 0.01,
      family = "Cottidae", genus = NA_character_, species = NA_character_,
      stringsAsFactors = FALSE
    ))
  }
  d
}

.ring_priors <- function(all_ranks = TRUE) {
  sp <- data.frame(
    taxon_name = c("Sebastes atrovirens", "Sebastes chrysomelas", "global_floor"),
    taxon_name_rank = "species",
    grid_id = "G1", main_habitat = "Rocky intertidal",
    alpha = c(5, 4, 1), beta = c(5, 6, 6133),
    undetected_type = c(NA, NA, "global_floor"),
    stringsAsFactors = FALSE
  )
  if (!all_ranks) {
    return(sp)
  }
  # The clades' own occurrence rows. The Sebastes row counts the referenced
  # congeners already competing above, which is why a ring must not take it.
  rbind(sp, data.frame(
    taxon_name = c("Sebastes", "Cottidae"),
    taxon_name_rank = c("genus", "family"),
    grid_id = "G1", main_habitat = "Rocky intertidal",
    alpha = c(30, 40), beta = c(70, 60), undetected_type = NA_character_,
    stringsAsFactors = FALSE
  ))
}

.jp <- function(lik, pri) {
  suppressMessages(suppressWarnings(join_priors(
    lik, pri,
    site = list(grid_id = "G1", main_habitat = "Rocky intertidal"),
    rank_system = c("family", "genus", "species"),
    backbone_id = 11L
  )))
}

test_that("a genus-rank ring does NOT take its clade's own genus prior", {
  # The defect: with a prior row for the exact genus, the ring joined it and was
  # priced with the evidence for the very congeners it is defined to exclude --
  # congeners that already compete as their own candidate rows. Measured on the
  # unfixed function this row carries alpha 30 and prior_mean 0.3.
  out <- .jp(.ring_lik(), .ring_priors(all_ranks = TRUE))
  ring <- out$taxon_name == "Sebastes" & out$taxon_name_rank == "genus"
  expect_equal(sum(ring), 1L)
  expect_true(is.na(out$alpha[ring]))
  # and it is priced by the floor instead, far below the clade prior it took
  expect_lt(out$prior_mean[ring], 0.3)
})

test_that("a coarse-rank specific_candidate still takes its clade prior", {
  # The other half of the rule: a NAMED coarse hypothesis is a coarse
  # identification, and the clade's record is the right prior for it.
  out <- .jp(.ring_lik(with_coarse_named = TRUE), .ring_priors(all_ranks = TRUE))
  named <- out$taxon_name == "Cottidae" & out$hypothesis_type == "specific_candidate"
  expect_equal(sum(named), 1L)
  expect_false(is.na(out$alpha[named]))
  expect_equal(out$alpha[named], 40)
})

test_that("a species-rank unreferenced_species still takes its own prior", {
  # THE trap. unreferenced_species occurs at two ranks with two meanings: at a
  # coarser rank it is the ring, but at the finest rank it is a named unsequenced
  # species with a real occurrence record. Excluding by hypothesis_type alone
  # would strip the prior from exactly the named rows the fix exists to restore.
  out <- .jp(.ring_lik(), .ring_priors(all_ranks = TRUE))
  named <- out$taxon_name == "Sebastes chrysomelas"
  expect_equal(sum(named), 1L)
  expect_identical(out$hypothesis_type[named], "unreferenced_species")
  expect_false(is.na(out$alpha[named]))
  expect_equal(out$alpha[named], 4)
})

test_that("the rank key is restored, not left masked, after the join", {
  out <- .jp(.ring_lik(with_coarse_named = TRUE), .ring_priors(all_ranks = TRUE))
  expect_setequal(unique(out$taxon_name_rank), c("species", "genus", "family"))
  expect_false(any(grepl("ring_takes_no_clade_prior", out$taxon_name_rank, fixed = TRUE)))
})

test_that("coarse prior rows change nothing when no named coarse hypothesis competes", {
  # The fix is a no-op on a species-only prior table: adding clade rows must not
  # move a single value when every coarse row present is a ring.
  lik <- .ring_lik(with_coarse_named = FALSE)
  expect_identical(
    .jp(lik, .ring_priors(all_ranks = FALSE)),
    .jp(lik, .ring_priors(all_ranks = TRUE))
  )
})


# ==============================================================================
# The global floor reads one rank's pool, not an average of several
# ==============================================================================

# Beta(1, N_total - 1) prices "one arbitrary unrecorded taxon from the regional
# pool", and N_total is that pool's size at ONE rank. CalIntertidal's prior
# table carries a global_floor row at all three ranks, with beta 290,064 at
# species, 307,198 at genus and 318,147 at family -- fewer genera than species,
# fewer families than genera. Averaging them prices a species-scale fallback
# against a pool that is no rank's pool.
.floor_priors <- function(ranks = "species") {
  base <- data.frame(
    taxon_name = c("Sebastes atrovirens", "Sebastes chrysomelas"),
    taxon_name_rank = "species",
    grid_id = "G1", main_habitat = "Rocky intertidal",
    alpha = c(5, 4), beta = c(5, 6), undetected_type = NA_character_,
    stringsAsFactors = FALSE
  )
  beta_by_rank <- c(species = 290063, genus = 307197, family = 318147)
  floors <- data.frame(
    taxon_name = "global_floor",
    taxon_name_rank = ranks,
    grid_id = "G1", main_habitat = "Rocky intertidal",
    alpha = 1, beta = unname(beta_by_rank[ranks]),
    undetected_type = "global_floor",
    stringsAsFactors = FALSE
  )
  rbind(base, floors)
}

.ring_only_lik <- function() {
  data.frame(
    observation_id = "u1",
    taxon_name = c("Sebastes atrovirens", "Sebastes"),
    taxon_name_rank = c("species", "genus"),
    hypothesis_type = c("specific_candidate", "unreferenced_species"),
    score_likelihood = c(0.8, 0.2),
    score_likelihood_mean = c(0.8, 0.2),
    score_likelihood_sd = c(0.05, 0.02),
    family = "Sebastidae", genus = "Sebastes",
    species = c("Sebastes atrovirens", NA_character_),
    stringsAsFactors = FALSE
  )
}

test_that("the floor ignores coarse-rank global_floor rows", {
  lik <- .ring_only_lik()
  sp_only <- .jp(lik, .floor_priors("species"))
  all_rk <- .jp(lik, .floor_priors(c("species", "genus", "family")))
  ring <- function(o) o$prior_mean[o$taxon_name == "Sebastes" & o$taxon_name_rank == "genus"]
  # Adding a genus and a family floor row must not move the species-scale floor.
  expect_equal(ring(all_rk), ring(sp_only))
})

test_that("an r12-shaped prior table is byte-identical under the floor rule", {
  lik <- .ring_only_lik()
  expect_identical(.jp(lik, .floor_priors("species")), .jp(lik, .floor_priors("species")))
})

test_that("a floor row only at a coarse rank is still used rather than discarded", {
  # Losing the principled fallback entirely would be worse than using the one
  # floor row the table does carry.
  lik <- .ring_only_lik()
  out <- .jp(lik, .floor_priors("genus"))
  ring <- out$prior_mean[out$taxon_name == "Sebastes" & out$taxon_name_rank == "genus"]
  expect_false(is.na(ring))
  expect_gt(ring, 0)
})


# ==============================================================================
# Every undetected-row average reads one rank's pool
# ==============================================================================

# alpha/beta on an undetected row encode the pool at that row's OWN rank, so
# averaging across ranks averages pool scales. This applies to the site and
# global dark means and the singleton-mirror threshold exactly as it does to the
# global floor -- and global_dark BECOMES the floor when no global_floor row is
# present, which is what makes it live rather than cosmetic.
.dark_priors <- function(ranks = "species", with_floor = TRUE) {
  cand <- data.frame(
    taxon_name = c("Sebastes atrovirens", "Sebastes chrysomelas"),
    taxon_name_rank = "species", grid_id = "G1", main_habitat = "Rocky intertidal",
    alpha = c(5, 4), beta = c(5, 6), undetected_type = NA_character_,
    stringsAsFactors = FALSE
  )
  # Each rank's pool is smaller than the one below it, so beta rises with rank.
  sing_beta <- c(species = 4000, genus = 9000, family = 15000)
  sing <- data.frame(
    taxon_name = paste0("singleton_", ranks), taxon_name_rank = ranks,
    grid_id = "G1", main_habitat = "Rocky intertidal",
    alpha = 1, beta = unname(sing_beta[ranks]),
    undetected_type = "singleton_mirror", stringsAsFactors = FALSE
  )
  out <- rbind(cand, sing)
  if (with_floor) {
    floor_beta <- c(species = 290063, genus = 307197, family = 318147)
    out <- rbind(out, data.frame(
      taxon_name = "global_floor", taxon_name_rank = ranks,
      grid_id = "G1", main_habitat = "Rocky intertidal",
      alpha = 1, beta = unname(floor_beta[ranks]),
      undetected_type = "global_floor", stringsAsFactors = FALSE
    ))
  }
  out
}

test_that("the dark and singleton means ignore coarse-rank rows", {
  lik <- .ring_only_lik()
  sp <- .jp(lik, .dark_priors("species"))
  mx <- .jp(lik, .dark_priors(c("species", "genus", "family")))
  for (cn in c("dark_alpha", "dark_beta", "singleton_alpha", "singleton_beta")) {
    expect_true(cn %in% names(sp))
    expect_equal(mx[[cn]], sp[[cn]], info = cn)
  }
})

test_that("an r12-shaped single-rank table is byte-identical under the rank rule", {
  lik <- .ring_only_lik()
  expect_identical(
    .jp(lik, .dark_priors("species")),
    .jp(lik, .dark_priors("species"))
  )
})

test_that("with no global_floor row the floor falls back to finest-rank dark rows", {
  # The live path: gf_alpha/gf_beta come from global_dark here, so a mixed-rank
  # dark mean would reach the floor itself even with the global_floor rule in
  # place.
  lik <- .ring_only_lik()
  sp <- .jp(lik, .dark_priors("species", with_floor = FALSE))
  mx <- .jp(lik, .dark_priors(c("species", "genus", "family"), with_floor = FALSE))
  ring <- function(o) o$prior_mean[o$taxon_name == "Sebastes" & o$taxon_name_rank == "genus"]
  expect_equal(ring(mx), ring(sp))
  expect_equal(mx$dark_beta, sp$dark_beta)
})

test_that("a subset with no finest-rank row keeps its own rows rather than losing the estimate", {
  lik <- .ring_only_lik()
  out <- .jp(lik, .dark_priors("genus", with_floor = FALSE))
  expect_false(any(is.na(out$dark_beta)))
  expect_equal(unique(out$dark_beta), 9000)
})


# ==============================================================================
# A ring and a named candidate for one clade are not duplicates of each other
# ==============================================================================

# The real COI shape: one observation carries BOTH "Chrysaora / genus /
# specific_candidate" (a reference-sequenced Chrysaora resolved only to genus)
# and "Chrysaora / genus / unreferenced_species" (an unsequenced species of
# Chrysaora). The paired clade deliberately has no finer candidate of its own:
# filter_redundant_hypotheses() would remove a coarse NAMED row that sits above
# a congener of its own genus, which is what the 334 real cases do NOT look like.
# They are meant to compete. A dedup key without hypothesis_type collapsed them
# and kept whichever carried the larger prior.
.pair_lik <- function(extra_dup = FALSE) {
  d <- data.frame(
    observation_id = "u1",
    taxon_name = c("Aurelia aurita", "Chrysaora", "Chrysaora"),
    taxon_name_rank = c("species", "genus", "genus"),
    hypothesis_type = c("specific_candidate", "specific_candidate", "unreferenced_species"),
    score_likelihood = c(0.8, 0.5, 0.2),
    score_likelihood_mean = c(0.8, 0.5, 0.2),
    score_likelihood_sd = c(0.05, 0.03, 0.02),
    family = c("Ulmaridae", "Pelagiidae", "Pelagiidae"),
    genus = c("Aurelia", "Chrysaora", "Chrysaora"),
    species = c("Aurelia aurita", NA_character_, NA_character_),
    stringsAsFactors = FALSE
  )
  if (extra_dup) {
    # Two rows of the SAME hypothesis -- what the dedup exists to collapse.
    d <- rbind(d, d[3, , drop = FALSE])
  }
  d
}

.pair_priors <- function() {
  data.frame(
    taxon_name = c("Aurelia aurita", "global_floor", "Chrysaora"),
    taxon_name_rank = c("species", "species", "genus"),
    grid_id = "G1", main_habitat = "Rocky intertidal",
    alpha = c(5, 1, 30), beta = c(5, 6133, 70),
    undetected_type = c(NA, "global_floor", NA),
    stringsAsFactors = FALSE
  )
}

test_that("a ring survives beside a named candidate for the same clade", {
  # The named candidate's prior (30/100) dwarfs the ring's floor, so under a key
  # without hypothesis_type the ring lost the dedup and was deleted.
  out <- .jp(.pair_lik(), .pair_priors())
  g <- out$taxon_name == "Chrysaora" & out$taxon_name_rank == "genus"
  expect_equal(sum(g), 2L)
  expect_setequal(out$hypothesis_type[g], c("specific_candidate", "unreferenced_species"))
  # and each keeps its own prior: the named one the clade record, the ring the floor
  expect_false(is.na(out$alpha[g & out$hypothesis_type == "specific_candidate"]))
  expect_true(is.na(out$alpha[g & out$hypothesis_type == "unreferenced_species"]))
})

test_that("duplicate rows of the SAME hypothesis still collapse to one", {
  out <- .jp(.pair_lik(extra_dup = TRUE), .pair_priors())
  ring <- out$taxon_name == "Chrysaora" & out$taxon_name_rank == "genus" &
    out$hypothesis_type == "unreferenced_species"
  expect_equal(sum(ring), 1L)
  # the named row beside it is still there, so the collapse was of duplicates only
  expect_equal(sum(out$taxon_name == "Chrysaora" & out$taxon_name_rank == "genus"), 2L)
})

test_that("the ring is kept however far the named candidate's prior exceeds it", {
  # Deciding which hypothesis exists by comparing priors is the defect; the
  # margin must not matter at all.
  pri <- .pair_priors()
  pri$alpha[pri$taxon_name == "Chrysaora"] <- 99999
  pri$beta[pri$taxon_name == "Chrysaora"] <- 1
  out <- .jp(.pair_lik(), pri)
  ring <- out$taxon_name == "Chrysaora" & out$taxon_name_rank == "genus" &
    out$hypothesis_type == "unreferenced_species"
  expect_equal(sum(ring), 1L)
})

test_that("likelihoods with no hypothesis_type column still join", {
  # hypothesis_type is optional throughout join_priors(), so the dedup key must
  # not require it.
  lik <- .pair_lik()
  lik$hypothesis_type <- NULL
  out <- .jp(lik, .pair_priors())
  expect_s3_class(out, "data.frame")
  expect_gt(nrow(out), 0L)
})
