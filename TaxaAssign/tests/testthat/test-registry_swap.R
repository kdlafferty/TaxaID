# SWAP TEST (design section 7): every name rewritten to a synonym gives identical results by taxon id. Its limit: the
# synonyms come from the same registry the resolver reads, so it proves consistency, not correctness.
# Fixtures in helper-registry.R; the synonym pairs are Hypsurus caryi / Embiotoca caryi and Oxyjulis californica /
# Halichoeres californicus.

.sw_syn <- c("Hypsurus caryi" = "Embiotoca caryi", "Oxyjulis californica" = "Halichoeres californicus")
.sw_swap <- function(v) { i <- match(v, names(.sw_syn)); v[!is.na(i)] <- .sw_syn[i[!is.na(i)]]; v }
.sw_lik <- function(swap) {
  nm <- c("Hypsurus caryi", "Embiotoca jacksoni", "Embiotocidae", "Oxyjulis californica", "Halichoeres semicinctus", "Labridae")
  d <- data.frame(observation_id = rep(c("E1", "E2"), each = 3), taxon_name = nm,
                  taxon_name_rank = rep(c("species", "species", "family"), 2),
                  hypothesis_type = rep(c("specific_candidate", "specific_candidate", "unreferenced_genus"), 2),
                  score_likelihood = c(0.9, 0.4, 0.1, 0.8, 0.5, 0.1), stringsAsFactors = FALSE)
  d$score_likelihood_mean <- d$score_likelihood; d$score_likelihood_sd <- 0.01
  if (swap) d$taxon_name <- .sw_swap(d$taxon_name)
  # the call's own lineage, from the names' text (the registry path replaces it)
  d$genus <- ifelse(d$taxon_name_rank == "species", sub(" .*$", "", d$taxon_name), NA)
  d$family <- rep(c("Embiotocidae", "Labridae"), each = 3)
  d
}
.sw_pri <- function(swap) {
  nm <- c("Hypsurus caryi", "Embiotoca jacksoni", "Oxyjulis californica", "Halichoeres semicinctus")
  d <- data.frame(taxon_name = c(nm, NA), taxon_name_rank = "species", grid_id = "s1", main_habitat = "Rocky",
                  alpha = c(20, 5, 10, 2, 0.5), beta = c(80, 95, 90, 98, 99.5), undetected_type = c(rep(NA, 4), "tier3"),
                  stringsAsFactors = FALSE)
  if (swap) d$taxon_name <- .sw_swap(d$taxon_name)
  d
}
.sw_run <- function(swap, reg) {
  jp <- suppressWarnings(suppressMessages(join_priors(.rg_stamp(.sw_lik(swap), reg, "joined"), .rg_stamp(.sw_pri(swap), reg, "priors"),
          site = list(grid_id = "s1", main_habitat = "Rocky"), rank_system = c("family", "genus", "species"), backbone_id = 11L, registry = reg)))
  set.seed(7); post <- suppressMessages(compute_posterior(jp, n_sims = 100L))
  cons <- suppressWarnings(suppressMessages(posterior_consensus(post, rank_system = c("family", "genus", "species"),
            lookup_missing_taxonomy = TRUE, registry = reg)))
  list(jp = jp, post = post, cons = cons)
}

test_that("SWAP: every name rewritten to its synonym gives identical priors, posteriors and calls by taxon id", {
  .rg_skip(); reg <- .rg_registry()
  a <- .sw_run(FALSE, reg); b <- .sw_run(TRUE, reg)
  key <- function(d) d[order(d$observation_id, d$taxon_id, d$hypothesis_type), , drop = FALSE]
  ja <- key(as.data.frame(a$jp)); jb <- key(as.data.frame(b$jp))
  expect_identical(ja$taxon_id, jb$taxon_id)
  expect_identical(ja$taxon_name, jb$taxon_name)            # output names derive from the id
  expect_equal(ja$prior_mean, jb$prior_mean, tolerance = 0)
  pa <- key(as.data.frame(a$post)); pb <- key(as.data.frame(b$post))
  expect_equal(pa$posterior_point_est, pb$posterior_point_est, tolerance = 0)
  ca <- a$cons[order(a$cons$observation_id), c("observation_id", "consensus_taxon", "consensus_rank")]
  cb <- b$cons[order(b$cons$observation_id), c("observation_id", "consensus_taxon", "consensus_rank")]
  expect_identical(ca, cb)
  # and the swap was real: the verbatim names differ
  expect_false(identical(sort(unique(ja$taxon_name_verbatim)), sort(unique(jb$taxon_name_verbatim))))
})
