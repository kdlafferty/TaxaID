# Per-genus (H2) and per-family (H3) unreferenced rings, each valued and named
# at one anchor chosen by .pick_anchor().

.pg_params <- function(h2_lookup = NULL, rings = NULL) {
  nm <- c("score_logit", "gap_logit")
  sig <- matrix(c(2.0, 0.2, 0.2, 1.0), 2L, dimnames = list(nm, nm))
  h2s <- diag(c(1.0, 1.0)); dimnames(h2s) <- list(nm, nm)
  h3s <- diag(c(1.5, 1.0)); dimnames(h3s) <- list(nm, nm)
  p <- list(
    H1_Lookup = data.frame(
      lookup_key = "Hypsoblennius sordidus", rank = "species",
      mu_score = 3.9, mu_gap = 2.0, sigma_score = 2.0, n_obs_species = 5L,
      stringsAsFactors = FALSE
    ),
    H1_Global_Mu = c(score_logit = 3.5, gap_logit = 1.5),
    H1_Sigma = sig,
    H2 = list(delta = 3.0, sigma = h2s),
    H3 = list(delta = 5.0, sigma = h3s),
    Stats = list(n_species = 1L, n_singletons = 0L),
    Score_Transform = "logit"
  )
  if (!is.null(h2_lookup)) p$H2_Lookup <- h2_lookup
  if (!is.null(rings)) p$Rings <- rings
  structure(p, class = "taxa_model_params")
}

.pg_lookup <- function() {
  data.frame(
    genus = c("Hypsoblennius", "Parablennius"),
    n_pairs = c(20L, 20L), delta_shrunk = c(2.0, 3.5),
    stringsAsFactors = FALSE
  )
}

# ASV_606 shape
.pg_asv606 <- function() {
  data.frame(
    observation_id = "ASV_606",
    taxon_name = c(
      "Hypsoblennius sordidus", "Parablennius sanguinolentus",
      "Parablennius incognitus", "Parablennius parvicornis",
      "Hypsoblennius hentz", "Hypsoblennius brevipinnis", "Hypsoblennius invemar"
    ),
    score = c(86.08, 86.08, 84.81, 84.81, 86.08, 86.08, 86.08),
    taxon_name_rank = "species",
    family = "Blenniidae",
    genus = c(rep("Hypsoblennius", 1), rep("Parablennius", 3), rep("Hypsoblennius", 3)),
    is_restored = c(FALSE, FALSE, FALSE, FALSE, TRUE, TRUE, TRUE),
    stringsAsFactors = FALSE
  ) |> transform(species = taxon_name)
}

.pg_eval <- function(df, p, ...) {
  TaxaLikely:::.evaluate_one_query(df, p, c("family", "genus", "species"),
    ratio_threshold = 0, ...)
}

# Expected H2 density for a given anchor (no q_identical): hand calculation
# from the model parameters at the anchor's own (score, gap) point.
.pg_expected_ring <- function(df, anchor_name, p, delta, sigma, offset = 0) {
  s <- TaxaLikely:::.transform_p(
    TaxaLikely:::.normalize_scores(df$score), "logit", 1e-4
  )
  names(s) <- df$taxon_name
  srt <- sort(s, decreasing = TRUE)
  gap <- ifelse(s >= srt[1L] - 1e-12, s - srt[2L], s - srt[1L])
  a <- anchor_name
  mu1 <- if (a %in% p$H1_Lookup$lookup_key) {
    p$H1_Lookup$mu_score[match(a, p$H1_Lookup$lookup_key)]
  } else {
    p$H1_Global_Mu[[1L]]
  }
  mvtnorm::dmvnorm(c(s[[a]], gap[[a]]), mean = c(mu1 - delta - offset, 0), sigma = sigma)
}

test_that("ASV_606: genus rings anchor on the real hit, each genus named by its own anchor", {
  skip_if_not_installed("TaxaTools")
  p <- .pg_params(.pg_lookup())
  df <- .pg_asv606()
  out <- .pg_eval(df, p)
  h2 <- out[out$hypothesis_type == "unreferenced_species", ]
  expect_equal(sort(h2$taxon_name), c("Hypsoblennius", "Parablennius"))
  expect_true(all(h2$h2_delta_source == "genus_specific"))

  raw_h <- .pg_expected_ring(df, "Hypsoblennius sordidus", p, delta = 2.0, sigma = p$H2$sigma)
  raw_p <- .pg_expected_ring(df, "Parablennius sanguinolentus", p, delta = 3.5, sigma = p$H2$sigma)
  # sordidus (mu_score 3.9, a real hit) beats the restored tie-mates, whose
  # global mean 3.5 would have given a different density; the restored ones
  # are alphabetically FIRST (brevipinnis), so this also rules out the old
  # first-row tie-break.
  expect_equal(h2$raw_likelihood[h2$taxon_name == "Hypsoblennius"], raw_h, tolerance = 1e-9)
  expect_equal(h2$raw_likelihood[h2$taxon_name == "Parablennius"], raw_p, tolerance = 1e-9)
  wrong <- .pg_expected_ring(df, "Hypsoblennius brevipinnis", p, delta = 2.0, sigma = p$H2$sigma)
  expect_false(isTRUE(all.equal(raw_h, wrong)))

  # No ring named after a restored tie-mate's genus by accident: exactly two.
  expect_equal(nrow(h2), 2L)
})

test_that("ASV_606: ONE family ring, valued and named at the unit anchor", {
  skip_if_not_installed("TaxaTools")
  p <- .pg_params(.pg_lookup())
  df <- .pg_asv606()
  out <- .pg_eval(df, p)
  h3 <- out[out$hypothesis_type == "unreferenced_genus", ]
  expect_equal(nrow(h3), 1L)
  expect_equal(h3$taxon_name, "Blenniidae")
  # Fixture: sordidus (mu 3.9) and sanguinolentus (global mu 3.5) tie on score
  # and both are real; sanguinolentus's score (logit ~1.82) is closer to the
  # global mean, so it has the higher H1 density and is the family anchor. Its
  # genus delta (Parablennius, 3.5) plus the H3 offset (5.0 - 3.0) applies.
  raw3 <- .pg_expected_ring(df, "Parablennius sanguinolentus", p,
    delta = 3.5, sigma = p$H3$sigma, offset = 5.0 - 3.0)
  expect_equal(h3$raw_likelihood, raw3, tolerance = 1e-9)
})

test_that("candidates spanning two families: one family ring each, at its own anchor", {
  skip_if_not_installed("TaxaTools")
  nm <- c("score_logit", "gap_logit")
  rg <- list(Order = list(
    rank = "order", hypothesis_type = "unreferenced_family", delta = 7.0,
    sigma = matrix(c(3, 0, 0, 1), 2L, dimnames = list(nm, nm))
  ))
  lk <- data.frame(genus = c("Alpha", "Beta"), n_pairs = 20L,
    delta_shrunk = c(1.5, 2.5), stringsAsFactors = FALSE)
  p <- .pg_params(lk, rg)
  df <- data.frame(
    observation_id = "Q1",
    taxon_name = c("Alpha one", "Beta two", "Beta three"),
    score = c(92, 90, 85), taxon_name_rank = "species",
    order = "Ord", family = c("Famx", "Famy", "Famy"),
    genus = c("Alpha", "Beta", "Beta"),
    stringsAsFactors = FALSE
  )
  df$species <- df$taxon_name
  out <- TaxaLikely:::.evaluate_one_query(df, p,
    c("order", "family", "genus", "species"), ratio_threshold = 0)
  h3 <- out[out$hypothesis_type == "unreferenced_genus", ]
  expect_equal(sort(h3$taxon_name), c("Famx", "Famy"))
  # coarser ring: one per unit
  expect_equal(sum(out$hypothesis_type == "unreferenced_family"), 1L)
  # Famy is valued at ITS anchor (Beta two, the higher of its candidates)
  s <- TaxaLikely:::.transform_p(TaxaLikely:::.normalize_scores(df$score), "logit", 1e-4)
  gap <- c(s[1] - s[2], s[2] - s[1], s[3] - s[1])
  famy <- mvtnorm::dmvnorm(c(s[2], gap[2]),
    mean = c(p$H1_Global_Mu[[1L]] - 2.5 - 2.0, 0), sigma = p$H3$sigma)
  famx <- mvtnorm::dmvnorm(c(s[1], gap[1]),
    mean = c(p$H1_Global_Mu[[1L]] - 1.5 - 2.0, 0), sigma = p$H3$sigma)
  expect_equal(h3$raw_likelihood[h3$taxon_name == "Famy"], famy, tolerance = 1e-9)
  expect_equal(h3$raw_likelihood[h3$taxon_name == "Famx"], famx, tolerance = 1e-9)
  # the order ring is anchored on the unit anchor (Alpha one, highest score)
  rr <- out[out$hypothesis_type == "unreferenced_family", ]
  expect_equal(rr$taxon_name, "Ord")
  expect_equal(rr$raw_likelihood,
    mvtnorm::dmvnorm(c(s[1], gap[1]),
      mean = c(p$H1_Global_Mu[[1L]] - (1.5 + (7.0 - 3.0)), 0), sigma = rg$Order$sigma),
    tolerance = 1e-9)
})

test_that("a genus whose candidates are all restored still gets a ring", {
  skip_if_not_installed("TaxaTools")
  df <- data.frame(
    observation_id = "Q1",
    taxon_name = c("Gadus morhua", "Arctogadus one", "Arctogadus two"),
    score = c(95, 90, 90), taxon_name_rank = "species", family = "Gadidae",
    genus = c("Gadus", "Arctogadus", "Arctogadus"),
    is_restored = c(FALSE, TRUE, TRUE), stringsAsFactors = FALSE
  )
  df$species <- df$taxon_name
  out <- .pg_eval(df, .pg_params())
  h2 <- out[out$hypothesis_type == "unreferenced_species", ]
  expect_equal(sort(h2$taxon_name), c("Arctogadus", "Gadus"))
  expect_true(all(h2$raw_likelihood > 0))
})

test_that("a lone candidate keeps the 1-D path: one genus ring, one family ring", {
  skip_if_not_installed("TaxaTools")
  df <- .pg_asv606()[1L, ]
  out <- .pg_eval(df, .pg_params(.pg_lookup()))
  expect_equal(sum(out$hypothesis_type == "unreferenced_species"), 1L)
  expect_equal(sum(out$hypothesis_type == "unreferenced_genus"), 1L)
  s <- TaxaLikely:::.transform_p(TaxaLikely:::.normalize_scores(86.08), "logit", 1e-4)
  p <- .pg_params(.pg_lookup())
  expect_equal(
    out$raw_likelihood[out$hypothesis_type == "unreferenced_species"],
    stats::dnorm(s, mean = 3.9 - 2.0, sd = sqrt(p$H2$sigma[1, 1])),
    tolerance = 1e-9
  )
})

test_that("placeholder / blank / NA genus never forms a ring; family-only unit keeps the fallback", {
  skip_if_not_installed("TaxaTools")
  df <- data.frame(
    observation_id = "Q1",
    taxon_name = c("Gadus morhua", "Foo bar", "Baz qux", "Quux one"),
    score = c(88, 92, 91, 90), taxon_name_rank = "species", family = "Gadidae",
    genus = c("Gadus", "unclassified", NA, ""), stringsAsFactors = FALSE
  )
  df$species <- df$taxon_name
  out <- .pg_eval(df, .pg_params())
  h2 <- out[out$hypothesis_type == "unreferenced_species", ]
  expect_equal(h2$taxon_name, "Gadus")

  # A unit whose only candidate is at family rank: today's single-ring fallback
  fam <- data.frame(
    observation_id = "Q1", taxon_name = c("Gadidae", "Gadidae x"),
    score = c(90, 89), taxon_name_rank = c("family", "family"),
    family = "Gadidae", genus = NA_character_, species = NA_character_,
    stringsAsFactors = FALSE
  )
  out2 <- .pg_eval(fam, .pg_params())
  expect_equal(sum(out2$hypothesis_type == "unreferenced_species"), 1L)
  expect_equal(sum(out2$hypothesis_type == "unreferenced_genus"), 1L)
})

test_that("n_sims > 0: per-genus deltas resampled separately; point values unchanged", {
  skip_if_not_installed("TaxaTools")
  p <- .pg_params(.pg_lookup())
  df <- .pg_asv606()
  base <- .pg_eval(df, p)
  set.seed(11)
  sim <- .pg_eval(df, p, n_sims = 200L)
  expect_true(all(is.finite(sim$score_likelihood_mean)))
  expect_true(all(is.finite(sim$score_likelihood_sd)))
  h2 <- sim[sim$hypothesis_type == "unreferenced_species", ]
  expect_equal(nrow(h2), 2L)
  # different deltas -> different resampled draws -> different mean or sd
  expect_false(isTRUE(all.equal(h2$score_likelihood_sd[1], h2$score_likelihood_sd[2])))
  key <- function(d) paste(d$hypothesis_type, d$taxon_name)
  expect_equal(sim$raw_likelihood[match(key(base), key(sim))], base$raw_likelihood)
  expect_equal(sim$score_likelihood[match(key(base), key(sim))], base$score_likelihood)
  # (the ring that is the unit maximum in every draw normalises to 1, sd 0)
  expect_true(any(h2$score_likelihood_sd > 0))
})

test_that("n_sims > 0 without H1_Lookup: runs and every row carries mean/sd", {
  skip_if_not_installed("TaxaTools")
  p <- .pg_params(.pg_lookup())
  p$H1_Lookup <- NULL
  set.seed(3)
  sim <- .pg_eval(.pg_asv606(), p, n_sims = 30L)
  expect_false(anyNA(sim$score_likelihood_mean))
  expect_false(anyNA(sim$score_likelihood_sd))
  expect_equal(sum(sim$hypothesis_type == "unreferenced_species"), 2L)
})

test_that(".pick_anchor tie-break order: score, real over restored, H1 density, raw identity, first", {
  skip_if_not_installed("TaxaTools")
  # Identical scores everywhere; two real rows and two restored. H1 densities
  # differ through the species-specific means, so the density decides among
  # the real rows, and never a restored row.
  p <- .pg_params(.pg_lookup())
  p$H1_Lookup <- data.frame(
    lookup_key = c("Aa one", "Aa two"), rank = "species",
    mu_score = c(5.0, 2.0), mu_gap = 2.0, sigma_score = 2.0, n_obs_species = 5L,
    stringsAsFactors = FALSE
  )
  df <- data.frame(
    observation_id = "Q", taxon_name = c("Aa one", "Aa two", "Aa three", "Aa four"),
    score = 90, taxon_name_rank = "species", family = "F", genus = "Aa",
    is_restored = c(FALSE, FALSE, TRUE, TRUE), stringsAsFactors = FALSE
  )
  df$species <- df$taxon_name
  out <- .pg_eval(df, p)
  s <- TaxaLikely:::.transform_p(TaxaLikely:::.normalize_scores(90), "logit", 1e-4)
  # logit(0.9) = 2.197; mu 2.0 is closer than 5.0 -> "Aa two" wins on density
  want <- mvtnorm::dmvnorm(c(s, 0), mean = c(2.0 - 3.0, 0), sigma = p$H2$sigma)
  expect_equal(out$raw_likelihood[out$hypothesis_type == "unreferenced_species"],
    want, tolerance = 1e-9)
})

test_that("a genus whose lookup row has an NA delta, NA variance or zero variance falls back to pooled values; no NA or NaN reaches the unit", {
  df <- .pg_asv606()
  base <- .pg_eval(df, .pg_params(.pg_lookup()))
  for (bad in list(
    list(delta_shrunk = c(NA, 3.5)),
    list(var_shrunk = c(NA_real_, 1.2)),
    list(var_shrunk = c(0, 1.2)),
    list(var_shrunk = c(-1, 1.2))
  )) {
    lk <- .pg_lookup()
    if (is.null(lk$var_shrunk)) lk$var_shrunk <- c(1.1, 1.2)
    for (nm in names(bad)) lk[[nm]] <- bad[[nm]]
    out <- .pg_eval(df, .pg_params(lk))
    expect_false(anyNA(out$score_likelihood), info = names(bad))
    expect_true(all(is.finite(out$score_likelihood)), info = names(bad))
    h <- out[out$taxon_name == "Hypsoblennius" & out$hypothesis_type == "unreferenced_species", ]
    expect_identical(h$h2_delta_source, "global_fallback", info = names(bad))
    # the healthy genus keeps its own genus-specific values
    pr <- out[out$taxon_name == "Parablennius" & out$hypothesis_type == "unreferenced_species", ]
    expect_identical(pr$h2_delta_source, "genus_specific", info = names(bad))
  }
  # a fully valid lookup is unchanged by the guard
  lk <- .pg_lookup(); lk$var_shrunk <- c(1.1, 1.2)
  ok1 <- .pg_eval(df, .pg_params(lk))
  expect_true(all(is.finite(ok1$score_likelihood)))
  expect_identical(ok1$h2_delta_source[ok1$hypothesis_type == "unreferenced_species"],
                   rep("genus_specific", 2L))
})
