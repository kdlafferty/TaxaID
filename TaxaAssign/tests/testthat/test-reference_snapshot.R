# tests/testthat/test-reference_snapshot.R
# posterior_consensus(reference_snapshot = ) and the mixed-snapshot check in
# update_prior_from_consensus(), plus a worked example of the partial-update
# recipe in vignettes/taxonomic-assignment.Rmd ("Updating assignments after new
# reference data").

library(dplyr)

.snap_posterior <- function() {
  bind_rows(
    tibble(
      observation_id = "S1",
      taxon_name = c("Sp_A", "Sp_B"),
      taxon_name_rank = "species",
      hypothesis_type = "specific_candidate",
      genus = c("GenA", "GenB"),
      family = c("FamA", "FamB"),
      species = c("Sp_A", "Sp_B"),
      posterior_mean = c(0.95, 0.05),
      posterior_point_est = c(0.95, 0.05)
    ),
    tibble(
      observation_id = "S2",
      taxon_name = c("Sp_A", "Sp_C"),
      taxon_name_rank = "species",
      hypothesis_type = "specific_candidate",
      genus = c("GenA", "GenC"),
      family = c("FamA", "FamC"),
      species = c("Sp_A", "Sp_C"),
      posterior_mean = c(0.5, 0.5),
      posterior_point_est = c(0.5, 0.5)
    )
  )
}

.snap_consensus <- function(...) {
  posterior_consensus(.snap_posterior(),
    rank_system = c("family", "genus", "species"),
    cumulative_threshold = 0.9, min_posterior = 0.05, ...
  )
}

# ---- the argument -------------------------------------------------------------

test_that("reference_snapshot is the LAST formal and defaults to NULL", {
  f <- formals(posterior_consensus)
  expect_identical(utils::tail(names(f), 1L), "reference_snapshot")
  expect_null(f$reference_snapshot)
})

test_that("reference_snapshot = NULL leaves the result exactly as without it", {
  plain <- .snap_consensus()
  expect_false("reference_snapshot" %in% names(plain))
  expect_null(attr(plain, "reference_snapshot", exact = TRUE))
  # the only difference from an explicit NULL is nothing at all
  expect_identical(.snap_consensus(reference_snapshot = NULL), plain)
})

test_that("a set reference_snapshot is recorded as an attribute and on every row", {
  con <- .snap_consensus(reference_snapshot = "refs_A")
  expect_identical(attr(con, "reference_snapshot", exact = TRUE), "refs_A")
  expect_identical(con$reference_snapshot, rep("refs_A", nrow(con)))
  expect_identical(attr(con, "consensus_settings")$reference_snapshot, "refs_A")
  # it changes no call
  plain <- .snap_consensus()
  keep <- setdiff(names(plain), "reference_snapshot")
  expect_identical(as.data.frame(con)[keep], as.data.frame(plain)[keep])
})

test_that("reference_snapshot rejects anything but one non-empty string", {
  for (bad in list(1, c("a", "b"), NA_character_, "", TRUE)) {
    expect_error(.snap_consensus(reference_snapshot = bad), "reference_snapshot")
  }
})

test_that("the label survives rbind row by row, where the attribute cannot", {
  a <- .snap_consensus(reference_snapshot = "refs_A")
  b <- .snap_consensus(reference_snapshot = "refs_B")
  merged <- rbind(a[a$observation_id == "S1", ], b[b$observation_id == "S2", ])
  # rbind keeps only the first piece's attribute: it names ONE snapshot for both
  expect_identical(attr(merged, "reference_snapshot", exact = TRUE), "refs_A")
  # the column still says which row came from which
  expect_identical(merged$reference_snapshot, c("refs_A", "refs_B"))
})

# ---- the mixed-snapshot check -------------------------------------------------

test_that("the check is silent on a table without the column", {
  con <- suppressMessages(.snap_consensus())
  expect_silent(TaxaAssign:::.report_reference_snapshots(con))
})

test_that("the check is silent on one labelled snapshot", {
  con <- suppressMessages(.snap_consensus(reference_snapshot = "refs_A"))
  expect_silent(TaxaAssign:::.report_reference_snapshots(con))
})

test_that("several labelled snapshots are reported with their counts, not warned", {
  a <- .snap_consensus(reference_snapshot = "refs_A")
  b <- .snap_consensus(reference_snapshot = "refs_B")
  merged <- rbind(a[a$observation_id == "S1", ], b[b$observation_id == "S2", ])
  expect_no_warning(
    expect_message(TaxaAssign:::.report_reference_snapshots(merged),
      "2 reference snapshots: refs_A \\(1 rows\\), refs_B \\(1 rows\\)")
  )
})

test_that("labelled rows beside unlabelled rows warn, with both counts", {
  old <- .snap_consensus()
  new <- .snap_consensus(reference_snapshot = "refs_B")
  merged <- dplyr::bind_rows(old[old$observation_id == "S1", ], new[new$observation_id == "S2", ])
  expect_true(is.na(merged$reference_snapshot[1]))
  w <- expect_warning(TaxaAssign:::.report_reference_snapshots(merged), "reference_snapshot")
  expect_match(conditionMessage(w), "1 row with no")
  expect_match(conditionMessage(w), "1 labelled row")
})

test_that("update_prior_from_consensus() runs the check on its consensus", {
  set.seed(1)
  post <- .snap_posterior() |>
    mutate(
      score_likelihood = posterior_mean, score_likelihood_mean = posterior_mean,
      score_likelihood_sd = 0.05, prior_mean = 0.5, prior_alpha = 5, prior_beta = 5
    )
  result <- compute_posterior(post, n_sims = 0)
  old <- posterior_consensus(result, rank_system = c("family", "genus", "species"),
    cumulative_threshold = 0.9, min_posterior = 0.05)
  new <- posterior_consensus(result, rank_system = c("family", "genus", "species"),
    cumulative_threshold = 0.9, min_posterior = 0.05, reference_snapshot = "refs_B")
  merged <- dplyr::bind_rows(old[old$observation_id == "S1", ], new[new$observation_id == "S2", ])
  attr(merged, "consensus_settings") <- attr(old, "consensus_settings")
  expect_warning(
    suppressMessages(update_prior_from_consensus(result, merged,
      n_sims = 0, require_support_columns = FALSE)),
    "reference_snapshot"
  )
})

# ---- worked example: the partial-update recipe on fixture data ----------------
# A trained model is reused (not retrained); new references add a candidate for
# ONE observation. Only that observation is re-evaluated, its posterior and
# consensus recomputed under a new snapshot label, and the untouched rows are
# merged back. The test checks the recipe's central promise: the recomputed
# subset equals what a FULL rerun gives for those observations, and the
# untouched rows equal the full rerun's too.

.recipe_model <- function() {
  sigma <- matrix(c(2.0, 0.2, 0.2, 1.0), nrow = 2L,
    dimnames = list(c("score_logit", "gap_logit"), c("score_logit", "gap_logit")))
  h <- diag(2)
  rownames(h) <- colnames(h) <- c("score_logit", "gap_logit")
  structure(list(
    H1_Lookup = data.frame(lookup_key = "Hybognathus nuchalis", rank = "species",
      mu_score = 4.5, mu_gap = 2.0, sigma_score = 2.0, n_obs_species = 5L),
    H1_Global_Mu = c(score_logit = 3.5, gap_logit = 1.5),
    H1_Sigma = sigma,
    H2 = list(delta = 3.0, sigma = h),
    H3 = list(delta = 5.0, sigma = h),
    Stats = list(n_species = 1L, n_singletons = 0L),
    Score_Transform = "logit"
  ), class = "taxa_model_params")
}

.recipe_matches <- function(with_new_reference) {
  m <- data.frame(
    observation_id = rep(c("ESV_001", "ESV_002"), each = 2),
    score = c(99.0, 85.0, 93.0, 88.0),
    taxon_name = c("Hybognathus nuchalis", "Rhinichthys obtusus",
      "Rhinichthys obtusus", "Campostoma anomalum"),
    taxon_name_rank = "species",
    family = "Leuciscidae",
    genus = c("Hybognathus", "Rhinichthys", "Rhinichthys", "Campostoma"),
    species = c("Hybognathus nuchalis", "Rhinichthys obtusus",
      "Rhinichthys obtusus", "Campostoma anomalum")
  )
  if (with_new_reference) {
    # the new reference: a newly sequenced species ESV_002 matches better
    m <- rbind(m, data.frame(observation_id = "ESV_002", score = 99.5,
      taxon_name = "Rhinichthys cataractae", taxon_name_rank = "species",
      family = "Leuciscidae", genus = "Rhinichthys", species = "Rhinichthys cataractae"))
  }
  m
}

.recipe_prior <- function(lik) {
  lik$prior_mean <- 0.5
  lik$prior_alpha <- 2
  lik$prior_beta <- 2
  lik
}

.recipe_run <- function(match_df, snapshot) {
  ranks <- c("family", "genus", "species")
  lik <- TaxaLikely::evaluate_likelihoods(match_df, .recipe_model(), ranks)$likelihoods
  post <- compute_posterior(.recipe_prior(lik), n_sims = 0)
  posterior_consensus(post, rank_system = ranks, cumulative_threshold = 0.9,
    min_posterior = 0.05, reference_snapshot = snapshot)
}

test_that("worked example: a subset update equals a full rerun, and the merge is labelled", {
  skip_if_not_installed("TaxaLikely")
  skip_if_not_installed("TaxaTools")

  old_refs <- .recipe_matches(FALSE)
  new_refs <- .recipe_matches(TRUE)

  # 1. the original run
  con_old <- .recipe_run(old_refs, "refs_2026_10")

  # 2. which observations the new references touch: those with a hit to them
  new_hits <- dplyr::anti_join(new_refs, old_refs,
    by = c("observation_id", "taxon_name"))
  affected <- unique(new_hits$observation_id)
  expect_identical(affected, "ESV_002")

  # 3. re-evaluate ONLY the affected observations, with the EXISTING model,
  #    then posterior and consensus on that subset under a new label
  con_sub <- .recipe_run(new_refs[new_refs$observation_id %in% affected, ],
    "refs_2026_11")

  # 4. merge the untouched rows back
  con_merged <- rbind(con_old[!con_old$observation_id %in% affected, ], con_sub)
  con_merged <- con_merged[order(con_merged$observation_id), ]

  # the promise: identical calls to a full rerun on the new references
  con_full <- .recipe_run(new_refs, "refs_2026_11")
  cols <- c("observation_id", "consensus_taxon", "consensus_rank", "consensus_posterior")
  expect_equal(as.data.frame(con_merged)[cols], as.data.frame(con_full)[cols],
    ignore_attr = TRUE)
  # ...and the merged table says which row was computed against which snapshot
  expect_identical(con_merged$reference_snapshot, c("refs_2026_10", "refs_2026_11"))
  expect_message(TaxaAssign:::.report_reference_snapshots(con_merged),
    "2 reference snapshots")
})
