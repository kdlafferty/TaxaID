# test-reference-support.R
# Tests for annotate_reference_support()

.ars_model <- function(keys = c("Girella nigricans", "Sarda chiliensis",
                                "Scomber japonicus"),
                       n_obs = c(3L, 12L, 20L),
                       w = c(0.72, 0.91, 0.94),
                       rank = "species") {
  structure(
    list(
      H1_Lookup = data.frame(
        lookup_key = keys,
        rank = rep(rank, length(keys)),
        mu_score = seq_along(keys) / 10,
        mu_gap = seq_along(keys) / 20,
        sigma_score = rep(0.5, length(keys)),
        n_obs_species = n_obs,
        shrink_w_score = w,
        shrink_w_gap = w,
        stringsAsFactors = FALSE
      ),
      Stats = list(prior_weight = 10, shrinkage = "empirical_bayes")
    ),
    class = "taxa_model_params"
  )
}


test_that("a direct species match reports that species' own count and weight", {
  x <- data.frame(
    consensus_taxon = c("Girella nigricans", "Sarda chiliensis"),
    consensus_rank = c("species", "species"),
    stringsAsFactors = FALSE
  )
  out <- annotate_reference_support(x, .ars_model())

  expect_equal(out$winner_n_references, c(3L, 12L))
  expect_equal(out$winner_reference_weight, c(0.72, 0.91))
  expect_equal(out$winner_reference_basis, rep("model_species_row", 2L))
  # 12 is not the model maximum (20 is), so neither row is at the ceiling.
  expect_equal(out$winner_at_model_max, c(FALSE, FALSE))
  # The annotation is additive: nothing about the input changes.
  expect_identical(out[, names(x)], x)
})


test_that("the model maximum is marked, because that is where the build censors", {
  x <- data.frame(
    consensus_taxon = "Scomber japonicus", consensus_rank = "species",
    stringsAsFactors = FALSE
  )
  out <- annotate_reference_support(x, .ars_model())
  expect_equal(out$winner_n_references, 20L)
  expect_true(out$winner_at_model_max)
})


test_that("a call coarser than the model's rank is reported as such, not as a miss", {
  # A genus-level consensus and a rank-ring hypothesis both land here. The
  # distinction from "no_model_row" is the whole point: this row has no
  # per-species count because of its RANK, not because the reference set is
  # thin.
  x <- data.frame(
    consensus_taxon = c("Mytilus", "Mytilidae"),
    consensus_rank = c("genus", "family"),
    stringsAsFactors = FALSE
  )
  out <- annotate_reference_support(x, .ars_model())
  expect_equal(out$winner_reference_basis, rep("rank_not_in_model", 2L))
  expect_true(all(is.na(out$winner_n_references)))
  expect_true(all(is.na(out$winner_at_model_max)))
})


test_that("a species the model has no row for is 'no_model_row', not 'rank_not_in_model'", {
  x <- data.frame(
    consensus_taxon = "Fundulus parvipinnis", consensus_rank = "species",
    stringsAsFactors = FALSE
  )
  out <- annotate_reference_support(x, .ars_model())
  expect_equal(out$winner_reference_basis, "no_model_row")
  expect_true(is.na(out$winner_n_references))
})


test_that("H2 and H3 hypotheses are settled by hypothesis_type, before any name lookup", {
  # "unreferenced_species" rows can carry a name that IS a lookup key (the
  # genus of a referenced congener, say). Matching the name first would
  # attribute a referenced species' count to a hypothesis explicitly about
  # an UNreferenced one.
  x <- data.frame(
    taxon_name = c("Girella nigricans", "Girella"),
    taxon_name_rank = c("species", "genus"),
    hypothesis_type = c("unreferenced_species", "unreferenced_genus"),
    stringsAsFactors = FALSE
  )
  out <- annotate_reference_support(
    x, .ars_model(),
    taxon_col = "taxon_name", rank_col = "taxon_name_rank",
    hypothesis_type_col = "hypothesis_type"
  )
  expect_equal(out$winner_reference_basis, rep("unreferenced_hypothesis", 2L))
  expect_true(all(is.na(out$winner_n_references)))
})


test_that("suppressed_candidate is looked up like any other candidate", {
  x <- data.frame(
    taxon_name = "Girella nigricans", taxon_name_rank = "species",
    hypothesis_type = "suppressed_candidate", stringsAsFactors = FALSE
  )
  out <- annotate_reference_support(
    x, .ars_model(),
    taxon_col = "taxon_name", rank_col = "taxon_name_rank",
    hypothesis_type_col = "hypothesis_type"
  )
  expect_equal(out$winner_reference_basis, "model_species_row")
  expect_equal(out$winner_n_references, 3L)
})


test_that("the ancestor fallback reproduces evaluate_likelihoods' finest-first walk", {
  # A lookup whose keys are an ancestor name rather than the binomial: the
  # fallback must take the FINEST matching ancestor, and must label the row
  # so the count is not read as the called taxon's own.
  mdl <- .ars_model(
    keys = c("Hyale", "Hyalidae"), n_obs = c(4L, 30L), w = c(0.75, 0.96)
  )
  x <- data.frame(
    consensus_taxon = "Protohyale frequens",
    consensus_rank = "species",
    genus = "Hyale",
    family = "Hyalidae",
    stringsAsFactors = FALSE
  )
  out <- annotate_reference_support(
    x, mdl, lineage_cols = c("genus", "family")
  )
  expect_equal(out$winner_reference_basis, "model_row_via_lineage")
  expect_equal(out$winner_n_references, 4L)

  # Reverse the supplied order and the coarser ancestor wins -- the argument
  # is documented as finest-rank-first and is load-bearing.
  out_rev <- annotate_reference_support(
    x, mdl, lineage_cols = c("family", "genus")
  )
  expect_equal(out_rev$winner_n_references, 30L)

  # Without lineage_cols there is no fallback at all.
  out_none <- annotate_reference_support(x, mdl)
  expect_equal(out_none$winner_reference_basis, "no_model_row")
})


test_that("a direct match beats the ancestor fallback", {
  mdl <- .ars_model(
    keys = c("Girella nigricans", "Girella"), n_obs = c(3L, 40L),
    w = c(0.72, 0.97)
  )
  x <- data.frame(
    consensus_taxon = "Girella nigricans", consensus_rank = "species",
    genus = "Girella", stringsAsFactors = FALSE
  )
  out <- annotate_reference_support(x, mdl, lineage_cols = "genus")
  expect_equal(out$winner_reference_basis, "model_species_row")
  expect_equal(out$winner_n_references, 3L)
})


test_that("an NA or empty taxon name is its own basis value", {
  x <- data.frame(
    consensus_taxon = c(NA_character_, ""), consensus_rank = c("species", "species"),
    stringsAsFactors = FALSE
  )
  out <- annotate_reference_support(x, .ars_model())
  expect_equal(out$winner_reference_basis, rep("no_taxon", 2L))
})


test_that("each platform's rows are annotated from that platform's own model", {
  # The hazard this argument exists for: two models, and every row silently
  # taking the first one's numbers.
  mdls <- list(
    illumina = .ars_model(n_obs = c(3L, 12L, 20L)),
    nanopore = .ars_model(n_obs = c(7L, 9L, 20L), w = c(0.85, 0.88, 0.94))
  )
  x <- data.frame(
    consensus_taxon = rep("Girella nigricans", 3L),
    consensus_rank = rep("species", 3L),
    platform = c("illumina", "nanopore", "illumina"),
    stringsAsFactors = FALSE
  )
  out <- annotate_reference_support(x, mdls, platform_col = "platform")
  expect_equal(out$winner_n_references, c(3L, 7L, 3L))
  expect_equal(out$winner_reference_weight, c(0.72, 0.85, 0.72))
})


test_that("one model cannot cover two platforms, and a missing platform model errors", {
  x <- data.frame(
    consensus_taxon = rep("Girella nigricans", 2L),
    consensus_rank = rep("species", 2L),
    platform = c("illumina", "nanopore"), stringsAsFactors = FALSE
  )
  expect_error(
    annotate_reference_support(x, .ars_model(), platform_col = "platform"),
    "spans 2 platforms"
  )
  expect_error(
    annotate_reference_support(
      x, list(illumina = .ars_model()), platform_col = "platform"
    ),
    "no model supplied for platform"
  )
  # A single platform and a single model is unambiguous, so it is allowed.
  x1 <- x[1L, , drop = FALSE]
  out <- annotate_reference_support(x1, .ars_model(), platform_col = "platform")
  expect_equal(out$winner_n_references, 3L)
})


test_that("an NA platform errors rather than silently losing those rows", {
  x <- data.frame(
    consensus_taxon = "Girella nigricans", consensus_rank = "species",
    platform = NA_character_, stringsAsFactors = FALSE
  )
  expect_error(
    annotate_reference_support(
      x, list(illumina = .ars_model()), platform_col = "platform"
    ),
    "NA value"
  )
})


test_that("prefix renames all four columns and allows annotating two taxon columns", {
  x <- data.frame(
    consensus_taxon = "Girella nigricans",
    primary_taxon = "Sarda chiliensis",
    consensus_rank = "species",
    primary_rank = "species",
    stringsAsFactors = FALSE
  )
  out <- annotate_reference_support(x, .ars_model())
  out <- annotate_reference_support(
    out, .ars_model(),
    taxon_col = "primary_taxon", rank_col = "primary_rank", prefix = "primary"
  )
  expect_equal(out$winner_n_references, 3L)
  expect_equal(out$primary_n_references, 12L)
  expect_true(all(c(
    "winner_reference_basis", "primary_reference_basis",
    "winner_at_model_max", "primary_at_model_max"
  ) %in% names(out)))
})


test_that("an existing output column is an error, never an overwrite", {
  x <- data.frame(
    consensus_taxon = "Girella nigricans", consensus_rank = "species",
    winner_n_references = 99L, stringsAsFactors = FALSE
  )
  expect_error(
    annotate_reference_support(x, .ars_model()),
    "already has winner_n_references"
  )
})


test_that("rank_col and hypothesis_type_col are optional refinements, taxon_col is not", {
  x <- data.frame(
    consensus_taxon = c("Girella nigricans", "Mytilus"), stringsAsFactors = FALSE
  )
  # No rank column: the genus falls back to the name lookup, which misses.
  # Reported as "no_model_row" because without a rank there is no evidence
  # the row is coarser -- the reason the rank column is worth supplying.
  out <- annotate_reference_support(x, .ars_model())
  expect_equal(out$winner_reference_basis, c("model_species_row", "no_model_row"))

  expect_error(
    annotate_reference_support(x, .ars_model(), taxon_col = "nope"),
    "no column 'nope'"
  )
})


test_that("an empty H1_Lookup annotates every row rather than erroring", {
  mdl <- .ars_model()
  mdl$H1_Lookup <- mdl$H1_Lookup[0L, ]
  x <- data.frame(
    consensus_taxon = "Girella nigricans", consensus_rank = "species",
    stringsAsFactors = FALSE
  )
  out <- annotate_reference_support(x, mdl)
  expect_equal(out$winner_reference_basis, "no_model_row")
  expect_true(is.na(out$winner_n_references))
})


test_that("a zero-row input returns zero rows with all four columns present", {
  x <- data.frame(
    consensus_taxon = character(0L), consensus_rank = character(0L),
    stringsAsFactors = FALSE
  )
  out <- annotate_reference_support(x, .ars_model())
  expect_equal(nrow(out), 0L)
  expect_true(all(c(
    "winner_n_references", "winner_reference_weight",
    "winner_reference_basis", "winner_at_model_max"
  ) %in% names(out)))
  expect_type(out$winner_n_references, "integer")
  expect_type(out$winner_reference_weight, "double")
  expect_type(out$winner_reference_basis, "character")
  expect_type(out$winner_at_model_max, "logical")
})


test_that("a model with no shrinkage columns names the missing column", {
  # shrinkage = "fixed", or a model predating these columns, cannot report
  # reference support -- and must say so rather than annotate NA silently.
  mdl <- .ars_model()
  mdl$H1_Lookup$shrink_w_score <- NULL
  x <- data.frame(
    consensus_taxon = "Girella nigricans", consensus_rank = "species",
    stringsAsFactors = FALSE
  )
  expect_error(
    annotate_reference_support(x, mdl), "shrink_w_score"
  )

  expect_error(
    annotate_reference_support(x, list(a = 1)), "must be a taxa_model_params"
  )
  expect_error(annotate_reference_support("not a df", .ars_model()), "data frame")
})


.ars_eval_model <- function(keys, mu, n_obs, w) {
  sigma <- matrix(c(2.0, 0.2, 0.2, 1.0), nrow = 2L, dimnames = list(
    c("score_logit", "gap_logit"), c("score_logit", "gap_logit")
  ))
  h <- diag(2)
  rownames(h) <- colnames(h) <- c("score_logit", "gap_logit")
  structure(list(
    H1_Lookup = data.frame(
      lookup_key = keys, rank = "species", mu_score = mu,
      mu_gap = rep(2.0, length(keys)), sigma_score = rep(2.0, length(keys)),
      n_obs_species = n_obs, shrink_w_score = w, shrink_w_gap = w,
      stringsAsFactors = FALSE
    ),
    H1_Global_Mu = c(score_logit = 3.5, gap_logit = 1.5),
    H1_Sigma = sigma,
    H2 = list(delta = 3.0, sigma = h),
    H3 = list(delta = 5.0, sigma = h),
    Stats = list(n_species = length(keys), n_singletons = 0L, prior_weight = 10),
    Score_Transform = "logit"
  ), class = "taxa_model_params")
}

.ars_eval_raw <- function(mdl, md) {
  ev <- TaxaLikely:::.evaluate_one_query(md, mdl, c("genus", "species"))
  ev <- as.data.frame(ev)
  ev <- ev[ev$hypothesis_type == "specific_candidate", ]
  stats::setNames(ev$raw_likelihood, ev$taxon_name)
}


test_that("the annotated row is the row the evaluator actually scored with", {
  # The column's claim is "this is the row that scored your call". Checking
  # the annotation against the lookup table it reads would agree by
  # construction, and the evaluator exposes no "mean I used" column. So
  # perturb ONE lookup row's mean and see which hypothesis's likelihood
  # moves: that is the evaluator's own answer to "which row scored this
  # row?", obtained without reimplementing any of its arithmetic.
  skip_if_not_installed("TaxaTools")
  md <- data.frame(
    observation_id = "ESV_001",
    score = c(95.0, 80.0),
    taxon_name = c("Aaa bbb", "Ccc ddd"),
    taxon_name_rank = "species",
    genus = c("Aaa", "Ccc"),
    species = c("Aaa bbb", "Ccc ddd"),
    stringsAsFactors = FALSE
  )
  keys <- c("Aaa bbb", "Ccc ddd")
  base <- .ars_eval_model(keys, c(4.5, 2.5), c(2L, 20L), c(0.63, 0.94))
  moved <- .ars_eval_model(keys, c(1.5, 2.5), c(2L, 20L), c(0.63, 0.94))

  rb <- .ars_eval_raw(base, md)
  rm_ <- .ars_eval_raw(moved, md)
  changed <- names(rb)[abs(rb - rm_[names(rb)]) > 1e-12]
  expect_equal(changed, "Aaa bbb") # only row 1's own hypothesis moved

  ann <- annotate_reference_support(
    data.frame(
      taxon_name = keys, taxon_name_rank = "species",
      hypothesis_type = "specific_candidate", stringsAsFactors = FALSE
    ),
    base, taxon_col = "taxon_name", rank_col = "taxon_name_rank",
    hypothesis_type_col = "hypothesis_type"
  )
  expect_equal(ann$winner_reference_basis, rep("model_species_row", 2L))
  # The hypothesis the evaluator scored from lookup row 1 must be the one the
  # annotation gives lookup row 1's count to.
  expect_equal(
    ann$taxon_name[ann$winner_n_references == base$H1_Lookup$n_obs_species[1L]],
    changed
  )
})


test_that("the ancestor fallback points at the same row the evaluator fell back to", {
  # The hardest branch, so check it the same way: a model whose only key is a
  # GENUS name. Moving that row's mean must move the species whose genus
  # matches it, and leave the unrelated species -- scored from the global
  # mean, which is what "no_model_row" is documented to mean -- untouched.
  skip_if_not_installed("TaxaTools")
  md <- data.frame(
    observation_id = "ESV_001",
    score = c(95.0, 80.0),
    taxon_name = c("Aaa bbb", "Zzz yyy"),
    taxon_name_rank = "species",
    genus = c("Aaa", "Zzz"),
    species = c("Aaa bbb", "Zzz yyy"),
    stringsAsFactors = FALSE
  )
  base <- .ars_eval_model("Aaa", 4.5, 7L, 0.85)
  moved <- .ars_eval_model("Aaa", 1.5, 7L, 0.85)
  rb <- .ars_eval_raw(base, md)
  rm_ <- .ars_eval_raw(moved, md)
  expect_true(abs(rb[["Aaa bbb"]] - rm_[["Aaa bbb"]]) > 1e-12)
  expect_equal(rb[["Zzz yyy"]], rm_[["Zzz yyy"]])

  ann <- annotate_reference_support(
    md[, c("taxon_name", "taxon_name_rank", "genus")],
    base, taxon_col = "taxon_name", rank_col = "taxon_name_rank",
    lineage_cols = "genus"
  )
  i <- match("Aaa bbb", ann$taxon_name)
  j <- match("Zzz yyy", ann$taxon_name)
  expect_equal(ann$winner_reference_basis[i], "model_row_via_lineage")
  expect_equal(ann$winner_n_references[i], 7L)
  expect_equal(ann$winner_reference_weight[i], 0.85)
  expect_equal(ann$winner_reference_basis[j], "no_model_row")
  expect_true(is.na(ann$winner_n_references[j]))
})


test_that("every unreferenced_ hypothesis level is recognised, not a fixed list", {
  # Real output carries unreferenced_species/genus/family/order/class. A
  # closed list of two silently reports the others as "no_model_row", which
  # claims a thin reference set for a taxon that by construction has none.
  # The species-rank case is the one that matters most: most
  # unreferenced_species rows carry a real binomial at species rank, so the
  # rank check cannot catch them.
  x <- data.frame(
    taxon_name = c("Aaa bbb", "Ccc", "Ddd", "Eee", "Fff"),
    taxon_name_rank = c("species", "genus", "family", "order", "class"),
    hypothesis_type = c(
      "unreferenced_species", "unreferenced_genus", "unreferenced_family",
      "unreferenced_order", "unreferenced_class"
    ),
    stringsAsFactors = FALSE
  )
  out <- annotate_reference_support(
    x, .ars_model(),
    taxon_col = "taxon_name", rank_col = "taxon_name_rank",
    hypothesis_type_col = "hypothesis_type"
  )
  expect_equal(out$winner_reference_basis, rep("unreferenced_hypothesis", 5L))

  # Without the column, the species-rank one is mislabelled -- which is why
  # the argument's documentation says to supply it whenever it exists.
  bare <- annotate_reference_support(
    x, .ars_model(), taxon_col = "taxon_name", rank_col = "taxon_name_rank"
  )
  expect_equal(bare$winner_reference_basis[1L], "no_model_row")
})


test_that("an unknown count or ceiling leaves at_model_max NA, not FALSE", {
  # FALSE would assert the row sits below a ceiling nobody established.
  mdl <- .ars_model()
  mdl$H1_Lookup$n_obs_species <- rep(NA_integer_, nrow(mdl$H1_Lookup))
  x <- data.frame(
    consensus_taxon = "Girella nigricans", consensus_rank = "species",
    stringsAsFactors = FALSE
  )
  out <- annotate_reference_support(x, mdl)
  expect_equal(out$winner_reference_basis, "model_species_row")
  expect_true(is.na(out$winner_n_references))
  expect_true(is.na(out$winner_at_model_max))
})
