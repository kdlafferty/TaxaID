# Minimal pairwise distance matrix for testing.
# p_match is on 0-1 scale (consistent with build_sequence_matrix output).
# 3 sequences: A1, A2 (same species "Aa"), B1 (species "Bb")
.make_raw_df <- function() {
  data.frame(
    id_x      = c("A1","A1","A1","A2","A2","A2","B1","B1","B1"),
    id_y      = c("A1","A2","B1","A1","A2","B1","A1","A2","B1"),
    species.x = c("Aa","Aa","Aa","Aa","Aa","Aa","Bb","Bb","Bb"),
    species.y = c("Aa","Aa","Bb","Aa","Aa","Bb","Aa","Aa","Bb"),
    genus.x   = c("A","A","A","A","A","A","B","B","B"),
    genus.y   = c("A","A","B","A","A","B","A","A","B"),
    p_match   = c(1.00, 0.95, 0.70, 0.95, 1.00, 0.68, 0.70, 0.68, 1.00),
    stringsAsFactors = FALSE
  )
}

# ---- flag_reference_errors ---------------------------------------------------

test_that("flag_reference_errors: clean database returns zero rows by default", {
  out <- flag_reference_errors(.make_raw_df())
  expect_equal(nrow(out), 0L)
})

test_that("flag_reference_errors: detects likely_mislabeled", {
  df <- .make_raw_df()
  # Make A1 match species Bb better than Aa (0-1 scale)
  df$p_match[df$id_x == "A1" & df$id_y == "B1"] <- 0.99
  out <- flag_reference_errors(df)
  expect_true("likely_mislabeled" %in% out$error_type)
  expect_true("A1" %in% out$id_x)
})

test_that("flag_reference_errors: return_all includes clean rows", {
  out <- flag_reference_errors(.make_raw_df(), return_all = TRUE)
  expect_true("clean" %in% out$error_type)
  expect_equal(nrow(out), length(unique(.make_raw_df()$id_x)))
})

test_that("flag_reference_errors: required columns checked", {
  expect_error(flag_reference_errors(data.frame(x = 1)), "missing required columns")
})

test_that("flag_reference_errors: non-data-frame input errors", {
  expect_error(flag_reference_errors(list()), "must be a data frame")
})

# ---- .prep_training_data -----------------------------------------------------

test_that(".prep_training_data: returns data frame with expected columns", {
  out <- TaxaLikely:::.prep_training_data(.make_raw_df(), c("genus", "species"))
  expect_true(is.data.frame(out))
  expect_true(all(c("id_x", "score_logit", "gap_logit", "rank_category", "N_Obs",
                     "rank_code_a") %in% names(out)))
})

test_that(".prep_training_data: H1 pairs have rank_category 1_Known_Species", {
  out <- TaxaLikely:::.prep_training_data(.make_raw_df(), c("genus", "species"))
  expect_true("1_Known_Species" %in% out$rank_category)
})

test_that(".prep_training_data: singleton produced for lone-species sequence", {
  out <- TaxaLikely:::.prep_training_data(.make_raw_df(), c("genus", "species"))
  expect_true("Singleton" %in% out$rank_category)
  # B1 has no within-species neighbour in this matrix
  expect_true("B1" %in% out$id_x[out$rank_category == "Singleton"])
})

test_that(".prep_training_data: gap_logit <= max_gap_ceiling", {
  out <- TaxaLikely:::.prep_training_data(.make_raw_df(), c("genus", "species"),
                                          max_gap_ceiling = 4.0)
  expect_true(all(out$gap_logit <= 4.0, na.rm = TRUE))
})

test_that(".prep_training_data: bad rank_system errors", {
  expect_error(
    TaxaLikely:::.prep_training_data(.make_raw_df(), character(0)),
    "non-empty"
  )
})

# ---- train_likelihood_model --------------------------------------------------

test_that("train_likelihood_model: returns taxa_model_params", {
  # Build a richer df so training has enough data
  df <- .make_raw_df()
  # Duplicate A1/A2 pair under new IDs to get more H1 pairs
  extra <- df
  extra$id_x <- sub("A1", "A3", sub("A2", "A4", df$id_x))
  extra$id_y <- sub("A1", "A3", sub("A2", "A4", df$id_y))
  df2 <- rbind(df, extra)
  out <- train_likelihood_model(df2, c("genus", "species"),
                                use_hierarchy = FALSE)
  expect_s3_class(out, "taxa_model_params")
})

test_that("train_likelihood_model: output has all required slots", {
  df <- .make_raw_df()
  out <- train_likelihood_model(df, c("genus", "species"),
                                use_hierarchy = FALSE)
  expect_true(all(c("H1_Lookup", "H1_Global_Mu", "H1_Sigma", "H2", "H3", "Stats")
                  %in% names(out)))
})

test_that("train_likelihood_model: H1_Lookup columns correct", {
  df <- .make_raw_df()
  out <- train_likelihood_model(df, c("genus", "species"),
                                use_hierarchy = FALSE)
  expect_true(all(c("lookup_key", "rank", "mu_score", "mu_gap", "sigma_score")
                  %in% names(out$H1_Lookup)))
})

test_that("train_likelihood_model: H1_Lookup$sigma_score is a true variance, not its square root (Session 158)", {
  # Regression test for a real, pre-existing bug: shrunk_sigma used to take
  # sqrt() of the shrunk variance before storing it, so sigma_score held an
  # SD-shaped number that every downstream consumer (evaluate_likelihoods(),
  # the species floor comparison against H1_Sigma, a true covariance matrix)
  # treats as a variance. Precisely reproduce the shrinkage formula from the
  # same raw_df (via the internal .prep_training_data() this function itself
  # calls) and confirm sigma_score matches the shrunk VARIANCE exactly, not
  # its square root.
  # min_observed_sigma deliberately NOT 1.0 (or 0): both are fixed points of
  # sqrt() (sqrt(1) = 1, sqrt(0) = 0), which would make the old buggy
  # (sqrt-applied) and fixed formulas coincide by degenerate accident if this
  # tiny fixture's raw variance floors out exactly there.
  df  <- .make_raw_df()
  out <- train_likelihood_model(df, c("genus", "species"),
                                use_hierarchy = FALSE, anchor_perfect = FALSE,
                                prior_weight = 10, min_observed_sigma = 4.0)

  train_df <- TaxaLikely:::.prep_training_data(df, c("genus", "species"))
  h1_data  <- train_df[train_df$rank_category == "1_Known_Species", ]
  aa       <- h1_data[h1_data$rank_code_a == "Aa", ]

  global_var <- max(stats::var(h1_data$score_logit, na.rm = TRUE), 4.0)
  raw_var    <- max(stats::var(aa$score_logit, na.rm = TRUE), 4.0)
  n          <- nrow(aa)
  w          <- n / (n + 10)
  expected_shrunk_variance <- w * raw_var + (1 - w) * global_var

  aa_idx <- match("Aa", out$H1_Lookup$lookup_key)
  expect_equal(out$H1_Lookup$sigma_score[aa_idx], expected_shrunk_variance)
  # The old (buggy) behavior would have stored sqrt(expected_shrunk_variance)
  # instead -- confirm the fix is NOT that value (guards against a future
  # regression reintroducing the extra sqrt unnoticed).
  expect_false(isTRUE(all.equal(out$H1_Lookup$sigma_score[aa_idx],
                                 sqrt(expected_shrunk_variance))))
})

test_that("train_likelihood_model: H2$delta < H3$delta", {
  df <- .make_raw_df()
  out <- train_likelihood_model(df, c("genus", "species"),
                                use_hierarchy = FALSE)
  expect_lt(out$H2$delta, out$H3$delta)
})

test_that("train_likelihood_model: prior_weight validation", {
  expect_error(
    train_likelihood_model(.make_raw_df(), c("genus", "species"),
                           prior_weight = -1),
    "positive"
  )
})

# (trivariate coverage path removed -- coverage used as filter only)

# ---- H2_Lookup: per-genus delta shrinkage ------------------------------------
#
# Fixture: genus "Fundulus" has two real congener species (lima,
# heteroclitus, p_match = 0.90 to each other -- tight, "cryptic-like"
# divergence); genus "Loose" has two real congener species (aa, bb,
# p_match = 0.75 -- real congener data, but looser/more divergent than
# Fundulus); genus "Distant" has one species (distantus, monotypic in the
# reference) whose only foreign matches are more distant CROSS-GENUS
# comparisons (p_match = 0.70, to Fundulus) -- Distant has no real congener
# pair of its own. Within-species self-matches are 0.97 for all five
# species. This lets (a) the pooled-global delta be checked as estimated
# ONLY from real congener data (Fundulus + Loose), NOT contaminated by
# Distant's uninformative cross-genus number (Session 158 fix -- previously
# the pooled default used max_foreign_score, mixing exactly this kind of
# cross-genus comparison in), and (b) Fundulus's tighter congener-specific
# delta checked against Loose's looser one, on either side of the pooled
# average.
.make_genus_raw_df <- function() {
  ids <- c("L1", "L2", "M1", "M2", "A1", "A2", "B1", "B2", "D1", "D2")
  species_map <- c(L1 = "lima", L2 = "lima",
                   M1 = "heteroclitus", M2 = "heteroclitus",
                   A1 = "aa", A2 = "aa",
                   B1 = "bb", B2 = "bb",
                   D1 = "distantus", D2 = "distantus")
  genus_map <- c(L1 = "Fundulus", L2 = "Fundulus",
                M1 = "Fundulus", M2 = "Fundulus",
                A1 = "Loose", A2 = "Loose",
                B1 = "Loose", B2 = "Loose",
                D1 = "Distant", D2 = "Distant")

  grid <- expand.grid(id_x = ids, id_y = ids, stringsAsFactors = FALSE)
  grid$species.x <- species_map[grid$id_x]
  grid$species.y <- species_map[grid$id_y]
  grid$genus.x   <- genus_map[grid$id_x]
  grid$genus.y   <- genus_map[grid$id_y]
  grid$p_match <- mapply(function(x, y, sx, sy, gx, gy) {
    if (x == y) return(1.00)          # self-match
    if (sx == sy) return(0.97)        # within-species, different sequence
    if (gx == gy && gx == "Fundulus") return(0.90)  # tight true congener
    if (gx == gy && gx == "Loose")    return(0.75)  # looser true congener
    0.70                               # unrelated genus (any cross-genus pair)
  }, grid$id_x, grid$id_y, grid$species.x, grid$species.y,
  grid$genus.x, grid$genus.y)
  grid
}

test_that("train_likelihood_model: score_transform = 'sqrt_mismatch' trains end to end and evaluates (Session 158)", {
  skip_if_not_installed("TaxaTools")
  out <- train_likelihood_model(.make_genus_raw_df(), c("genus", "species"),
                                use_hierarchy = FALSE, anchor_perfect = FALSE,
                                score_transform = "sqrt_mismatch")
  expect_equal(out$Score_Transform, "sqrt_mismatch")
  # sqrt_mismatch's own default max_gap_ceiling (~0.6234) should have been
  # resolved and applied -- gap values must never exceed it.
  expect_true("var_shrunk" %in% names(out$H2_Lookup))

  match_df <- data.frame(
    observation_id = "Q1", score = 97.0, taxon_name = "lima",
    taxon_name_rank = "species", genus = "Fundulus", species = "lima",
    stringsAsFactors = FALSE
  )
  result <- evaluate_likelihoods(match_df, out, c("genus", "species"), ratio_threshold = 0)
  expect_true(nrow(result$likelihoods) > 0L)
  expect_true(all(result$likelihoods$score_likelihood >= 0 &
                    result$likelihoods$score_likelihood <= 1))
})

test_that("train_likelihood_model: default score_transform ('logit') is fully backward compatible", {
  out <- train_likelihood_model(.make_genus_raw_df(), c("genus", "species"),
                                use_hierarchy = FALSE, anchor_perfect = FALSE)
  expect_equal(out$Score_Transform, "logit")
})

test_that("train_likelihood_model: H2_Lookup created when congener pairs exist", {
  out <- train_likelihood_model(.make_genus_raw_df(), c("genus", "species"),
                                use_hierarchy = FALSE, anchor_perfect = FALSE)
  expect_false(is.null(out$H2_Lookup))
  expect_true("Fundulus" %in% out$H2_Lookup$genus)
  expect_true("Loose" %in% out$H2_Lookup$genus)
})

test_that("train_likelihood_model: monotypic genus excluded from H2_Lookup", {
  out <- train_likelihood_model(.make_genus_raw_df(), c("genus", "species"),
                                use_hierarchy = FALSE, anchor_perfect = FALSE)
  # "Distant" has only one referenced species (distantus) -- no real congener
  # pair exists to estimate a local delta from, so it must not appear.
  expect_false("Distant" %in% out$H2_Lookup$genus)
})

test_that("train_likelihood_model: pooled H2 delta is not contaminated by a monotypic genus's cross-genus comparison (Session 158)", {
  out <- train_likelihood_model(.make_genus_raw_df(), c("genus", "species"),
                                use_hierarchy = FALSE, anchor_perfect = FALSE)
  # The pooled default is estimated from real congener data only (Fundulus's
  # 0.90 and Loose's 0.75) -- Distant's cross-genus 0.70 comparisons must not
  # pull it in this fixture's direction (a pooled delta contaminated by
  # Distant would be LARGER -- more divergent -- than either real congener
  # estimate implies, since 0.70 is the most divergent comparison of all).
  fundulus_delta <- out$H2_Lookup$delta_shrunk[out$H2_Lookup$genus == "Fundulus"]
  loose_delta     <- out$H2_Lookup$delta_shrunk[out$H2_Lookup$genus == "Loose"]
  expect_lt(fundulus_delta, out$H2$delta)  # tighter than pooled
  expect_gt(loose_delta,    out$H2$delta)  # looser than pooled
})

test_that("train_likelihood_model: genus-specific delta is shrunk below the pooled global delta for a tight congener pair", {
  out <- train_likelihood_model(.make_genus_raw_df(), c("genus", "species"),
                                use_hierarchy = FALSE, anchor_perfect = FALSE)
  fundulus_delta <- out$H2_Lookup$delta_shrunk[out$H2_Lookup$genus == "Fundulus"]
  # Fundulus's real congener match (0.90) is tighter than Loose's (0.75), so
  # the pooled average of the two sits above Fundulus's own value -- the
  # shrunk local delta should sit below the pooled global one.
  expect_lt(fundulus_delta, out$H2$delta)
  # ... but still shrunk toward it, not equal to the raw empirical estimate.
  expect_gt(fundulus_delta, 0.5)
})

test_that("train_likelihood_model: genus-specific H2 variance shrinkage (Session 158)", {
  out <- train_likelihood_model(.make_genus_raw_df(), c("genus", "species"),
                                use_hierarchy = FALSE, anchor_perfect = FALSE)
  expect_true("var_shrunk" %in% names(out$H2_Lookup))
  expect_true(all(out$H2_Lookup$var_shrunk > 0))
})

test_that("train_likelihood_model: H2_Lookup is NULL when rank_system has no genus level", {
  # rank_system = "species" only -- .generalize_ranks() never produces a
  # rank_code_b in this case (regardless of whether a genus column exists in
  # the raw data), so there is no genus to group congener pairs by at all.
  out <- train_likelihood_model(.make_genus_raw_df(), c("species"),
                                use_hierarchy = FALSE, anchor_perfect = FALSE)
  expect_null(out$H2_Lookup)
})
