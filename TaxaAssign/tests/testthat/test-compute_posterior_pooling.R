# Pooling of named unreferenced rows inside compute_posterior().

# One observation: a candidate, one ring, and named rows sharing the ring's
# likelihood. Likelihoods are all 1, so a row's posterior is its prior share.
.pool_df <- function(named_prior, named_genus = NULL, ring_name = "Fam",
                     ring_prior = 0.001, ring_type = "unreferenced_genus",
                     ring_rank = "family", named_type = "unreferenced_genus",
                     obs = "U1", named_lik = 1, with_ab = TRUE, scope = FALSE) {
  k <- length(named_prior)
  if (is.null(named_genus)) named_genus <- paste0("Gen", seq_len(k))
  cand_prior <- 1 - sum(named_prior) - ring_prior
  d <- data.frame(
    observation_id = obs,
    taxon_name = c("Cand one", ring_name, paste(named_genus, "sp")),
    taxon_name_rank = c("species", ring_rank, rep("species", k)),
    hypothesis_type = c("specific_candidate", ring_type, rep(named_type, k)),
    genus = c("Cand", NA, named_genus),
    family = "Fam",
    score_likelihood = c(1, 1, rep(named_lik, k)),
    score_likelihood_mean = c(1, 1, rep(named_lik, k)),
    score_likelihood_sd = 0.05,
    prior_mean = c(cand_prior, ring_prior, named_prior),
    stringsAsFactors = FALSE
  )
  if (with_ab) {
    d$prior_alpha <- 2 * d$prior_mean / 0.01 + 0.5
    d$prior_beta <- 2 * (1 - d$prior_mean) / 0.01 + 0.5
  }
  if (scope) {
    d$genus <- NULL; d$family <- NULL
    d$unreferenced_scope <- c(NA, ring_name, rep(ring_name, k))
    d$unreferenced_scope_rank <- c(NA, ring_rank, rep(ring_rank, k))
  }
  d
}

test_that("sub-ring guard: a genus summing to 0.05 or more stays, the rest pool", {
  d <- .pool_df(c(rep(0.02, 3), rep(0.001, 27)),
    named_genus = c(rep("G", 3), paste0("H", 1:27)))
  o <- suppressMessages(compute_posterior(d, n_sims = 0))
  expect_equal(nrow(o), 5L)
  expect_equal(sort(o$taxon_name), sort(c("Cand one", "Fam", rep("G sp", 3))))
  ring <- o[o$taxon_name == "Fam", ]
  expect_equal(ring$pooled_n, 27L)
  expect_equal(ring$prior_mean, 0.001 + 27 * 0.001)
  expect_equal(ring$pooled_prior_mass, 27 * 0.001)
  expect_equal(nrow(attr(o, "pooled_rows")), 27L)
  expect_equal(attr(o, "pooled_min_posterior"), 0.05)
  expect_true(all(is.na(o$pooled_n[o$taxon_name != "Fam"])))
  # exactness
  base <- suppressMessages(.compute_posterior_impl(d, n_sims = 0, pool = FALSE))
  expect_equal(ring$posterior_point_est,
    sum(base$posterior_point_est[base$taxon_name == "Fam" | grepl("^H", base$taxon_name)]),
    tolerance = 1e-12)
})

test_that("a genus below 0.05 in total pools too", {
  d <- .pool_df(c(rep(0.01, 3), rep(0.001, 5)), named_genus = c(rep("G", 3), paste0("H", 1:5)))
  o <- suppressMessages(compute_posterior(d, n_sims = 0))
  expect_equal(nrow(o), 2L)
})

test_that("a named row with no ring row in its unit is kept", {
  d <- .pool_df(c(0.01, 0.01))
  d <- d[d$taxon_name != "Fam", ]
  o <- suppressMessages(compute_posterior(d, n_sims = 0))
  expect_equal(nrow(o), nrow(d))
  expect_equal(nrow(attr(o, "pooled_rows")), 0L)
  # fixed schema: the column is present, NA on these non-ring rows
  expect_true(all(is.na(o$pooled_n)))
})

test_that("a named row whose likelihood differs from its ring's is kept", {
  d <- .pool_df(c(0.01, 0.01))
  d$score_likelihood[3] <- 0.9
  o <- suppressMessages(compute_posterior(d, n_sims = 0))
  expect_equal(nrow(o), 3L)
  expect_equal(o$pooled_n[o$taxon_name == "Fam"], 1L)
  expect_true("Gen1 sp" %in% o$taxon_name)
  expect_false("Gen2 sp" %in% o$taxon_name)
})

test_that("unreferenced_species named rows pool into the genus ring", {
  d <- .pool_df(c(0.01, 0.01), named_genus = c("Gen", "Gen"), ring_name = "Gen",
    ring_type = "unreferenced_species", ring_rank = "genus",
    named_type = "unreferenced_species")
  d$taxon_name[3:4] <- c("Gen a", "Gen b")
  o <- suppressMessages(compute_posterior(d, n_sims = 0))
  expect_equal(nrow(o), 2L)
  expect_equal(o$pooled_taxa[o$taxon_name == "Gen"], "Gen a; Gen b")
})

test_that("Monte Carlo on a pooled table", {
  d <- dplyr::bind_rows(.pool_df(c(rep(0.01, 4)), obs = "U1"),
    .pool_df(c(0.02, 0.02), obs = "U2"))
  set.seed(1)
  o <- suppressMessages(compute_posterior(d, n_sims = 200))
  expect_equal(as.vector(tapply(o$posterior_mean, o$observation_id, sum)), c(1, 1), tolerance = 1e-9)
  ring <- o[!is.na(o$pooled_n) & o$pooled_n > 0, ]
  expect_equal(nrow(ring), 2L)
  expect_true(all(is.finite(ring$prior_alpha) & ring$prior_alpha > 0))
  expect_true(all(is.finite(ring$prior_beta) & ring$prior_beta > 0))
  expect_equal(ring$prior_mean, c(0.001 + 0.04, 0.001 + 0.04))
  # moment matching: mean preserved by alpha/(alpha+beta)
  expect_equal(ring$prior_alpha / (ring$prior_alpha + ring$prior_beta), ring$prior_mean,
    tolerance = 1e-9)
})

test_that("nothing to pool: identical to the unpooled path, attributes present", {
  d <- .pool_df(c(0.3, 0.3), ring_prior = 0.1)
  o <- suppressMessages(compute_posterior(d, n_sims = 0))
  b <- suppressMessages(.compute_posterior_impl(d, n_sims = 0, pool = FALSE))
  pc <- c("pooled_n", "pooled_prior_mass", "pooled_taxa")
  expect_true(all(pc %in% names(o)))
  core <- setdiff(names(o), pc)
  expect_identical(
    as.data.frame(o)[, core], as.data.frame(b)[, core]
  )
  expect_equal(nrow(attr(o, "pooled_rows")), 0L)
  expect_equal(attr(o, "pooled_min_posterior"), 0.05)
})

test_that("presence-mixture rows are never pooled, nor pooled into", {
  d <- .pool_df(c(0.01, 0.01))
  d$prior_mix_w <- NA_real_; d$prior_mix_theta_present <- NA_real_
  d$prior_mix_theta_absent <- NA_real_
  d[3, c("prior_mix_w", "prior_mix_theta_present", "prior_mix_theta_absent")] <-
    list(0.5, 0.019, 0.001)
  o <- suppressMessages(compute_posterior(d, n_sims = 0))
  expect_true("Gen1 sp" %in% o$taxon_name)
  expect_false("Gen2 sp" %in% o$taxon_name)
  d2 <- .pool_df(c(0.01, 0.01))
  d2$prior_mix_w <- NA_real_; d2$prior_mix_theta_present <- NA_real_
  d2$prior_mix_theta_absent <- NA_real_
  d2[2, c("prior_mix_w", "prior_mix_theta_present", "prior_mix_theta_absent")] <-
    list(0.5, 0.0015, 0.0005)
  o2 <- suppressMessages(compute_posterior(d2, n_sims = 0))
  expect_equal(nrow(o2), nrow(d2))
})

test_that("scope columns pool into the scope's ring", {
  d <- .pool_df(c(0.01, 0.01, 0.01), scope = TRUE)
  o <- suppressMessages(compute_posterior(d, n_sims = 0))
  expect_equal(nrow(o), 2L)
  expect_equal(o$pooled_n[o$taxon_name == "Fam"], 3L)
  # a scope naming no ring row: kept
  d$unreferenced_scope[3] <- "Nowhere"
  o2 <- suppressMessages(compute_posterior(d, n_sims = 0))
  expect_equal(nrow(o2), 3L)
})

test_that("re-running on a pooled table accumulates", {
  d <- .pool_df(c(0.01, 0.01, 0.01, 0.01))
  o1 <- suppressMessages(compute_posterior(d, n_sims = 0))
  o2 <- suppressMessages(compute_posterior(
    o1[, setdiff(names(o1), c("posterior_point_est", "posterior_mean", "posterior_sd", "confidence_score"))],
    n_sims = 0))
  expect_equal(o2$pooled_n[o2$taxon_name == "Fam"], 4L)
  expect_equal(o2$posterior_point_est, o1$posterior_point_est)
})

test_that("posterior_consensus warns below the pooling threshold only", {
  d <- .pool_df(c(0.01, 0.01))
  o <- suppressMessages(compute_posterior(d, n_sims = 0))
  expect_warning(suppressMessages(posterior_consensus(o, min_posterior = 0.01)),
    "pooling threshold")
  expect_no_warning(suppressMessages(posterior_consensus(o, min_posterior = 0.05)))
  expect_no_warning(suppressMessages(posterior_consensus(o)))
})

# ---------------------------------------------------------------------------
# Exactness on real tables
# ---------------------------------------------------------------------------

.real_cases <- list(
  Mugu = c(
    "/Users/lafferty/My Drive/Rscripts/eDNA/SepulvedaMugu/MuguWilderFish_blast_parts_all_posteriors_r2.rds",
    "/Users/lafferty/My Drive/Rscripts/eDNA/SepulvedaMugu/MuguWilderFish_blast_parts_consensus_final.rds"
  ),
  GreatLakes = c(
    "/Users/lafferty/My Drive/Stats and Data/GreatLakes data/GreatLakes2023BurnsHarbor_v103finalb_posteriors_updated.rds",
    "/Users/lafferty/My Drive/Stats and Data/GreatLakes data/GreatLakes2023BurnsHarbor_v103finalb_consensus_final.rds"
  )
)

for (nm in names(.real_cases)) {
  local({
    nm <- nm
    paths <- .real_cases[[nm]]
    test_that(paste0("pooling is exact on the real ", nm, " table"), {
      skip_if_not(all(file.exists(paths)), paste("saved", nm, "tables not reachable"))
      p <- readRDS(paths[1])
      cons <- readRDS(paths[2])
      cs <- attr(cons, "consensus_settings")
      skip_if(is.null(cs), "no consensus_settings on the saved consensus")
      pc <- c("posterior_point_est", "posterior_mean", "posterior_sd", "confidence_score")
      p <- p[, setdiff(names(p), pc)]
      set.seed(1)
      a <- suppressMessages(compute_posterior(p, n_sims = 0))
      b <- suppressMessages(.compute_posterior_impl(p, n_sims = 0, pool = FALSE))
      pooled <- attr(a, "pooled_rows")
      message(sprintf("%s: rows before %d, after pooling %d (%d pooled)", nm, nrow(b), nrow(a), nrow(pooled)))
      expect_equal(nrow(a), nrow(b) - nrow(pooled))
      expect_gt(nrow(pooled), 0L)
      # every surviving non-ring row matches; rings equal own + pooled sum
      kb <- paste(b$observation_id, b$hypothesis_type, b$taxon_name_rank, b$taxon_name, sep = "\r")
      ka <- paste(a$observation_id, a$hypothesis_type, a$taxon_name_rank, a$taxon_name, sep = "\r")
      expect_false(anyDuplicated(kb) > 0L)
      m <- match(ka, kb)
      expect_false(anyNA(m))
      expect_equal(a$posterior_point_est[is.na(a$pooled_n) | a$pooled_n == 0],
        b$posterior_point_est[m[is.na(a$pooled_n) | a$pooled_n == 0]], tolerance = 1e-10)
      add <- tapply(pooled$posterior_point_est, paste(pooled$observation_id, pooled$ring_taxon, sep = "\r"), sum)
      ringrows <- which(!is.na(a$pooled_n) & a$pooled_n > 0)
      rk <- paste(a$observation_id, a$taxon_name, sep = "\r")[ringrows]
      expect_equal(a$posterior_point_est[ringrows],
        b$posterior_point_est[m[ringrows]] + as.vector(add[rk]), tolerance = 1e-10)
      expect_equal(sum(a$pooled_n, na.rm = TRUE), nrow(pooled))
      # calls
      args <- function(t) do.call(posterior_consensus, c(list(t), cs))
      ca <- suppressMessages(suppressWarnings(args(a)))
      cb <- suppressMessages(suppressWarnings(args(b)))
      ca <- ca[order(ca$observation_id), ]; cb <- cb[order(cb$observation_id), ]
      expect_identical(as.character(ca$observation_id), as.character(cb$observation_id))
      expect_identical(ca$consensus_taxon, cb$consensus_taxon)
      expect_identical(ca$consensus_rank, cb$consensus_rank)
      message(sprintf("%s: call changes %d of %d", nm,
        sum(!(ca$consensus_taxon %in% cb$consensus_taxon) | ca$consensus_taxon != cb$consensus_taxon, na.rm = TRUE), nrow(ca)))
    })
  })
}


test_that("fixed schema: a nothing-to-pool table still carries the three pooled columns", {
  # A unit with a candidate, a genus ring and NO named rows: nothing can pool.
  d <- data.frame(
    observation_id = "u1",
    taxon_name = c("Atherinops affinis", "Atherinops"),
    taxon_name_rank = c("species", "genus"),
    hypothesis_type = c("specific_candidate", "unreferenced_species"),
    genus = "Atherinops", family = "Atherinopsidae",
    score_likelihood = c(1, 0.5), score_likelihood_mean = c(1, 0.5),
    score_likelihood_sd = 0, prior_mean = c(0.01, 1e-6),
    prior_alpha = c(1, 1e-3), prior_beta = c(99, 999),
    stringsAsFactors = FALSE
  )
  o <- suppressMessages(compute_posterior(d, n_sims = 0))
  expect_true(all(c("pooled_n", "pooled_prior_mass", "pooled_taxa") %in% names(o)))
  ring <- o$hypothesis_type == "unreferenced_species"
  expect_identical(o$pooled_n[ring], 0L)
  expect_identical(o$pooled_prior_mass[ring], 0)
  expect_true(is.na(o$pooled_taxa[ring]))
  expect_true(is.na(o$pooled_n[!ring]) && is.na(o$pooled_prior_mass[!ring]))
  expect_s3_class(attr(o, "pooled_rows"), "data.frame")
  expect_equal(nrow(attr(o, "pooled_rows")), 0L)
  expect_equal(attr(o, "pooled_min_posterior"), 0.05)
  # Two such tables bind with the same columns as a pooled one would carry.
  b2 <- dplyr::bind_rows(o, o)
  expect_identical(names(b2), names(o))
  # Grouped input (pooling skipped) also carries the schema.
  g <- suppressMessages(compute_posterior(dplyr::group_by(d, observation_id), n_sims = 0))
  expect_true(all(c("pooled_n", "pooled_prior_mass", "pooled_taxa") %in% names(g)))
})
