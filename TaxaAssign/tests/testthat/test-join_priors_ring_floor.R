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
