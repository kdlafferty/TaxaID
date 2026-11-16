# Reference-consistency table at training time: attr(model, "reference_consistency"), built with the
# existing TaxaMatch screen's own functions, plus the one stated pair rule. Fixtures in
# helper-reference_consistency.R; v1.0 training golden in fixtures/reference_consistency_v1_golden.R.

.rc_strip <- function(m) {
  attr(m, "reference_consistency") <- NULL
  m
}

test_that("exclude_reference_suspects is the LAST formal of train_likelihood_model() and defaults to TRUE", {
  # default flipped to TRUE on 2026-11-15 (maintainer decision after held-out non-inferiority)
  f <- formals(train_likelihood_model)
  expect_identical(utils::tail(names(f), 1L), "exclude_reference_suspects")
  expect_identical(f$exclude_reference_suspects, TRUE)
})

test_that("the default excludes the suspects: omitting the argument is exclude_reference_suspects = TRUE", {
  df <- .rc_raw_df()
  m <- .rc_train(df)
  expect_identical(m, .rc_train(df, exclude_reference_suspects = TRUE))
  # and it differs from the report-only fit on this fixture, which has two suspects
  expect_false(identical(.rc_strip(m), .rc_strip(.rc_train(df, exclude_reference_suspects = FALSE))))
  expect_setequal(attr(m, "reference_consistency")$accession[attr(m, "reference_consistency")$excluded],
                  c("AF488489", "MT999001"))
})

test_that("the TaxaMatch internal helper the table reuses still exists with the arguments passed to it", {
  ns <- asNamespace("TaxaMatch")
  expect_true(exists(".compute_hierarchy_congruence", envir = ns, inherits = FALSE))
  expect_true(all(c("seq_matrix", "reference_df", "rank_system", "top_n", "min_congruent_rank",
                    "submission_window", "min_coverage", "require_species_resolved_partner") %in%
                    names(formals(get(".compute_hierarchy_congruence", envir = ns)))))
  # the hierarchy_flag thresholds are read from the screen's own defaults
  fe <- formals(TaxaMatch::evaluate_reference_accessions)
  expect_true(all(c("min_independent_partners", "hierarchy_incongruent_threshold") %in% names(fe)))
})

test_that("exclude_reference_suspects = FALSE (report only): the returned model is v1.0's exactly, with the table attached", {
  g <- eval(parse(test_path("fixtures", "reference_consistency_v1_golden.R")))
  expect_identical(g$commit, "3e563f29")
  m <- .rc_train(.rc_raw_df(), exclude_reference_suspects = FALSE)
  # cross-platform golden: floating-point arithmetic can differ in the last bits (~1e-16) between platforms
  expect_equal(.rc_strip(m), g$model, tolerance = 1e-12)
  rc <- attr(m, "reference_consistency")
  expect_s3_class(rc, "data.frame")
  expect_setequal(rc$accession, .rc_refs()$id)
  expect_true(all(c("species", "n_references", "local_tier", "hierarchy_flag", "label_confidence",
                    "reference_action", "best_disagreeing_pident_species", "best_disagreeing_taxon_species",
                    "pair_rule_support", "pair_rule_suspect", "suspect", "excluded") %in% names(rc)))
  expect_false(any(rc$excluded))
})

test_that("the existing screen's columns are what the screen's own functions give", {
  m <- .rc_train(.rc_raw_df())
  rc <- attr(m, "reference_consistency")
  lc <- TaxaMatch::corroborate_references_locally(.rc_raw_df(), data.frame(composite_id = .rc_refs()$id))
  k <- match(rc$accession, lc$accession)
  expect_identical(rc$local_tier, lc$local_tier[k])
  expect_identical(rc$local_tier[rc$accession %in% c("AF488489", "OQ846368")], c("disagree", "disagree"))
  # the family-rank "remove": a Sebastidae label with only Pleuronectidae neighbours
  expect_identical(rc$reference_action[rc$accession == "MT999001"], "remove")
})

test_that("the pair rule picks the mislabelled member of a two-reference species, and only it", {
  rc <- attr(.rc_train(.rc_raw_df()), "reference_consistency")
  r <- function(id, col) rc[[col]][rc$accession == id]
  expect_identical(r("AF488489", "n_references"), 2L)
  expect_identical(r("AF488489", "best_disagreeing_taxon_species"), "Pleuro coenosus")
  expect_identical(r("AF488489", "pair_rule_support"), 5L)
  expect_true(r("AF488489", "pair_rule_suspect"))
  expect_false(r("OQ846368", "pair_rule_suspect"))
  # the rule applies to two-reference species only
  expect_false(any(rc$pair_rule_suspect[rc$n_references != 2L]))
  expect_setequal(rc$accession[rc$suspect], c("AF488489", "MT999001"))
})

test_that("with fewer than 2 independent supporting references the pair stays unresolved", {
  rc <- attr(.rc_train(.rc_raw_df(drop_coenosus_support = TRUE)), "reference_consistency")
  expect_identical(rc$pair_rule_support[rc$accession == "AF488489"], 1L)
  expect_false(any(rc$pair_rule_suspect[rc$accession %in% c("AF488489", "OQ846368")]))
})

test_that("exclude_reference_suspects = TRUE trains without the suspects and records them", {
  df <- .rc_raw_df()
  m <- .rc_train(df, exclude_reference_suspects = TRUE)
  rc <- attr(m, "reference_consistency")
  expect_setequal(rc$accession[rc$excluded], c("AF488489", "MT999001"))
  expect_identical(rc$excluded, rc$suspect)
  keep <- !(df$id_x %in% c("AF488489", "MT999001") | df$id_y %in% c("AF488489", "MT999001"))
  expect_identical(.rc_strip(m), .rc_strip(.rc_train(df[keep, , drop = FALSE], exclude_reference_suspects = FALSE)))
  # P. verticalis is left with one reference, so it has no within-species H1 row
  expect_false("Pleuro verticalis" %in% m$H1_Lookup$lookup_key[m$H1_Lookup$n_obs_species > 0])
})

test_that("exclusion with no suspects trains exactly as the report-only fit", {
  df <- .rc_raw_df()
  df <- df[!(df$id_x %in% c("AF488489", "MT999001") | df$id_y %in% c("AF488489", "MT999001")), ]
  m0 <- .rc_train(df, exclude_reference_suspects = FALSE)
  m1 <- .rc_train(df, exclude_reference_suspects = TRUE)
  expect_false(any(attr(m1, "reference_consistency")$suspect))
  expect_identical(m1, m0)
})

test_that("exclude_reference_suspects must be a single TRUE or FALSE", {
  expect_error(train_likelihood_model(.rc_raw_df(), .rc_rs, exclude_reference_suspects = NA), "exclude_reference_suspects")
})

test_that("processing references in chunks gives exactly the one-pass table", {
  df <- .rc_raw_df()
  one <- TaxaLikely:::.reference_consistency(df, .rc_rs, chunk_rows = 1e9)
  many <- TaxaLikely:::.reference_consistency(df, .rc_rs, chunk_rows = 5)
  expect_identical(many, one)
})

test_that("a raw_df without coverage gets an empty table that says why, and training is unchanged", {
  df <- .rc_raw_df()
  df$coverage <- NULL
  m <- .rc_train(df)
  rc <- attr(m, "reference_consistency")
  expect_identical(nrow(rc), 0L)
  expect_match(attr(rc, "status"), "coverage")
  expect_identical(.rc_strip(.rc_train(df, exclude_reference_suspects = TRUE)), .rc_strip(m))
})
