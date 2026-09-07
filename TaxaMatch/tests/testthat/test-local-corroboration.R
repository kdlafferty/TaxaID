# Local corroboration + primer-stripped screen query (2026-09-03) --
# ecosystem_docs/REENTRY_PROMPT_local_corroboration_and_primer_stripped_screen.md.
# Everything here is offline. The fixtures are the three REAL PtConception
# cases the design was built on (Zaniolepis, Jordania, Fundulus), with the
# real identities, overlaps, dates and accession prefixes.

# ------------------------------------------------------------------------------
# Fixtures
# ------------------------------------------------------------------------------

# One row per (id_x, id_y); the function symmetrises, so one direction is enough.
.local_seq_matrix_fixture <- function() {
  data.frame(
    id_x = c("KM057996", "KM057967", rep("MN883227", 6L), "KM057996"),
    id_y = c(
      "OQ846041", "LC126244",
      "MN883226", "OR380114", "OR380115", "OR380116", "OR380117", "OR380118",
      "OQ846089"
    ),
    p_match = c(1.0, 1.0, 1.0, 0.9814, 0.9814, 0.9814, 0.9814, 0.9814, 1.0),
    coverage = c(0.97, 0.056, 1.0, 0.958, 0.958, 0.958, 0.958, 0.958, 1.0),
    species.x = c(
      "Zaniolepis frenata", "Jordania zonope", rep("Fundulus luciae", 6L),
      "Zaniolepis frenata"
    ),
    species.y = c(
      "Zaniolepis frenata", "Jordania zonope", rep("Fundulus luciae", 6L),
      "Zaniolepis latipinnis"
    ), # congener, never counts
    stringsAsFactors = FALSE
  )
}

.local_reference_meta_fixture <- function() {
  data.frame(
    composite_id = c(
      "KM057996", "OQ846041", "KM057967", "LC126244",
      "MN883227", "MN883226",
      "OR380114", "OR380115", "OR380116", "OR380117", "OR380118",
      "OQ846089"
    ),
    species = c(
      "Zaniolepis frenata", "Zaniolepis frenata", "Jordania zonope", "Jordania zonope",
      "Fundulus luciae", "Fundulus luciae",
      rep("Fundulus luciae", 5L), "Zaniolepis latipinnis"
    ),
    create_date = c(
      "2014/08/04", "2023/04/24", "2014/08/04", "2019/02/14",
      "2020/01/04", "2020/01/04",
      rep("2023/08/15", 5L), "2023/04/24"
    ),
    stringsAsFactors = FALSE
  )
}

.tier_of <- function(out, acc) out$local_tier[out$accession == acc]

# ------------------------------------------------------------------------------
# corroborate_references_locally()
# ------------------------------------------------------------------------------

test_that("Zaniolepis: KM057996 is corroborated by the independent 2023 deposit OQ846041", {
  out <- corroborate_references_locally(
    .local_seq_matrix_fixture(),
    .local_reference_meta_fixture()
  )
  expect_equal(.tier_of(out, "KM057996"), "corroborated")
  row <- out[out$accession == "KM057996", ]
  expect_equal(row$n_conspecific, 1L)
  expect_equal(row$n_independent_conspecific, 1L)
  expect_equal(row$best_independent_pident, 1.0)
  expect_equal(row$best_independent_partner, "OQ846041")
  # The congener OQ846089 at 100% is not a conspecific and never counts.
  expect_false("OQ846089" %in% row$best_independent_partner)
  # Symmetry: the partner is corroborated by KM057996 in turn.
  expect_equal(.tier_of(out, "OQ846041"), "corroborated")
})

test_that("Jordania: a 100% match over 5.6% overlap is excluded by min_overlap, so KM057967 is a singleton", {
  out <- corroborate_references_locally(
    .local_seq_matrix_fixture(),
    .local_reference_meta_fixture()
  )
  expect_equal(.tier_of(out, "KM057967"), "singleton")
  row <- out[out$accession == "KM057967", ]
  expect_equal(row$n_conspecific, 0L)
  expect_true(is.na(row$best_independent_pident))
  # Lower the overlap floor below 5.6% and the pair counts -- pinning that
  # the filter, not something else, is what excludes it.
  loose <- corroborate_references_locally(.local_seq_matrix_fixture(),
    .local_reference_meta_fixture(),
    min_overlap = 0.05
  )
  expect_equal(.tier_of(loose, "KM057967"), "corroborated")
})

test_that("Fundulus: the same-day sibling at 1.0 must not count; five independent 0.9814 partners read 'disagree' at 0.99 and 'corroborated' at 0.98", {
  strict <- corroborate_references_locally(
    .local_seq_matrix_fixture(),
    .local_reference_meta_fixture()
  )
  row <- strict[strict$accession == "MN883227", ]
  expect_equal(row$n_conspecific, 6L)
  expect_equal(row$n_independent_conspecific, 5L) # MN883226 is same batch
  expect_equal(row$best_independent_pident, 0.9814)
  expect_match(row$best_independent_partner, "^OR3801")
  expect_equal(row$local_tier, "disagree")

  loose <- corroborate_references_locally(.local_seq_matrix_fixture(),
    .local_reference_meta_fixture(),
    min_pident = 0.98
  )
  expect_equal(.tier_of(loose, "MN883227"), "corroborated")
})

test_that("same_batch_only: a conspecific from the same batch is counted but never corroborates", {
  sm <- data.frame(
    id_x = "MN883227", id_y = "MN883226", p_match = 1, coverage = 1,
    species.x = "Fundulus luciae", species.y = "Fundulus luciae",
    stringsAsFactors = FALSE
  )
  out <- corroborate_references_locally(sm, .local_reference_meta_fixture())
  row <- out[out$accession == "MN883227", ]
  expect_equal(row$n_conspecific, 1L)
  expect_equal(row$n_independent_conspecific, 0L)
  expect_equal(row$local_tier, "same_batch_only")
})

test_that("independence reuses the screen's own batch rule: accession-number proximity fires without dates", {
  meta_no_dates <- .local_reference_meta_fixture()[, c("composite_id", "species")]
  out <- corroborate_references_locally(.local_seq_matrix_fixture(), meta_no_dates)
  # MN883226 vs MN883227: same prefix, numbers 1 apart -> same batch by the
  # accession heuristic alone.
  row <- out[out$accession == "MN883227", ]
  expect_equal(row$n_independent_conspecific, 5L)
  # KM057996 vs OQ846041: different prefix, no dates -> independent.
  expect_equal(.tier_of(out, "KM057996"), "corroborated")
})

test_that("version suffixes are stripped on both sides and the output is one row per accession", {
  sm <- .local_seq_matrix_fixture()
  sm$id_x[1] <- "KM057996.1"
  meta <- .local_reference_meta_fixture()
  meta$composite_id[meta$composite_id == "OQ846041"] <- "OQ846041.2"
  out <- corroborate_references_locally(sm, meta)
  expect_false(any(grepl("\\.[0-9]+$", out$accession)))
  expect_equal(sum(out$accession == "KM057996"), 1L)
  expect_equal(.tier_of(out, "KM057996"), "corroborated")
  expect_equal(nrow(out), length(unique(out$accession)))
  expect_true(all(c(
    "accession", "species", "n_conspecific", "n_independent_conspecific",
    "best_independent_pident", "best_independent_partner", "local_tier"
  )
  %in% names(out)))
  expect_equal(attr(out, "local_corroboration_params")$min_pident, 0.99)
})

test_that("corroborate_references_locally() accepts an accession column and ISO dates", {
  meta <- .local_reference_meta_fixture()
  names(meta)[names(meta) == "composite_id"] <- "accession"
  meta$create_date <- gsub("/", "-", meta$create_date)
  out <- corroborate_references_locally(.local_seq_matrix_fixture(), meta)
  expect_equal(.tier_of(out, "MN883227"), "disagree") # dates still parsed: MN883226 same day
  expect_equal(.tier_of(out, "KM057996"), "corroborated")
})

test_that("corroborate_references_locally() validates inputs", {
  sm <- .local_seq_matrix_fixture()
  meta <- .local_reference_meta_fixture()
  expect_error(corroborate_references_locally(sm[, -4], meta), "coverage")
  expect_error(
    corroborate_references_locally(sm, meta[, "species", drop = FALSE]),
    "composite_id or accession"
  )
  expect_error(corroborate_references_locally(sm, meta, min_overlap = 1.5), "min_overlap")
  expect_error(corroborate_references_locally(sm, meta, min_pident = 0), "min_pident")
  expect_error(corroborate_references_locally(list(), meta), "data frame")
})

test_that("corroborate_references_locally() on a matrix with no conspecific pairs returns all singletons", {
  sm <- data.frame(
    id_x = "A1", id_y = "B1", p_match = 1, coverage = 1,
    species.x = "Genus a", species.y = "Genus b", stringsAsFactors = FALSE
  )
  meta <- data.frame(composite_id = c("A1", "B1"), stringsAsFactors = FALSE)
  out <- corroborate_references_locally(sm, meta)
  expect_equal(out$local_tier, c("singleton", "singleton"))
  expect_equal(out$n_conspecific, c(0L, 0L))
})

# ------------------------------------------------------------------------------
# match_driving_accessions()
# ------------------------------------------------------------------------------

.driving_match_fixture <- function() {
  data.frame(
    observation_id = c("O1", "O1", "O1", "O2", "O2", "O3", "O3"),
    species = c("Sp a", "Sp a", "Sp b", "Sp a", "Sp a", "Sp c", "Sp c"),
    accession = c("A1", "A2", "B1", "A2", "A3", "RESTORED_C1", "C2"),
    score_original = c(99, 98, 97, 95, 99, 100, 90),
    stringsAsFactors = FALSE
  )
}

test_that("match_driving_accessions() keeps the per-(observation, species) best accession, ties kept", {
  out <- match_driving_accessions(.driving_match_fixture())
  # A1 best for O1/Sp a; B1 for O1/Sp b; A3 for O2/Sp a; C2 for O3/Sp c.
  expect_setequal(out, c("A1", "B1", "A3", "C2"))
  expect_false("A2" %in% out) # second-best everywhere: never drives a likelihood

  tied <- .driving_match_fixture()
  tied$score_original[2] <- 99 # A2 ties A1 for O1/Sp a
  expect_true(all(c("A1", "A2") %in% match_driving_accessions(tied)))
})

test_that("match_driving_accessions() drops RESTORED_* provenance accessions and NA accessions", {
  m <- .driving_match_fixture()
  m$accession[4] <- NA_character_
  out <- match_driving_accessions(m)
  expect_false(any(grepl("^RESTORED_", out)))
  expect_false(any(is.na(out)))
  # C2 now drives O3/Sp c because the RESTORED_ row is out of the race.
  expect_true("C2" %in% out)
})

test_that("match_driving_accessions() returns accessions exactly as they appear (version suffixes kept)", {
  m <- .driving_match_fixture()
  m$accession[1] <- "A1.1"
  expect_true("A1.1" %in% match_driving_accessions(m))
})

test_that("match_driving_accessions() honours renamed columns and validates", {
  m <- .driving_match_fixture()
  names(m) <- c("obs", "sp", "acc", "sc")
  out <- match_driving_accessions(m,
    score_col = "sc", obs_col = "obs",
    species_col = "sp", accession_col = "acc"
  )
  expect_setequal(out, c("A1", "B1", "A3", "C2"))
  expect_error(match_driving_accessions(m), "missing required column")
  expect_error(match_driving_accessions(list()), "data frame")
})

# ------------------------------------------------------------------------------
# score_reference_labels(local_corroboration=) -- provenance + veto
# ------------------------------------------------------------------------------

.veto_eval_fixture <- function() {
  data.frame(
    accession = c("KM057996", "KM057967", "OK172573", "SKIP1", "OVER1"),
    listed_taxon = c(
      "Zaniolepis frenata", "Jordania zonope", "Scorpaenichthys marmoratus",
      "Skippus localis", "Oversized specius"
    ),
    # KM057996 / KM057967: the real "remove" shape -- incongruent, nothing
    # corroborating anywhere in nt, something contradicting.
    frac_independent_below_min_congruent_rank = c(0.875, 0.875, 0.75, NA, NA),
    n_independent_top_matches = c(3L, 3L, 5L, 1L, NA_integer_),
    best_agreeing_pident = c(NA, NA, 100, 100, NA),
    best_disagreeing_pident = c(98.6, 98.6, 96.79, NA, NA),
    congruent_evidence_exists_anywhere = c(FALSE, FALSE, TRUE, TRUE, FALSE),
    congruent_evidence_best_pident = c(NA, NA, 100, NA, NA),
    hierarchy_flag = c(
      "incongruent", "incongruent", "incongruent",
      "locally_corroborated", "not_evaluated_oversized"
    ),
    stringsAsFactors = FALSE
  )
}

test_that("the local-corroboration columns are always present, NA/'none'-filled without a table", {
  out <- score_reference_labels(.veto_eval_fixture())
  expect_true(all(c(
    "corroboration_source", "local_best_independent_pident",
    "local_n_independent_conspecific", "action_reason"
  ) %in% names(out)))
  src <- setNames(out$corroboration_source, out$accession)
  expect_equal(unname(src["KM057996"]), "none")
  expect_equal(unname(src["OK172573"]), "blast")
  expect_true(is.na(out$local_best_independent_pident[out$accession == "KM057996"]))
  expect_true(is.na(out$action_reason[out$accession == "KM057996"]))
  # Without a table the BLAST verdict stands: both Zaniolepis and Jordania
  # are "remove" here, exactly as the real screen said.
  expect_equal(out$reference_action[out$accession == "KM057996"], "remove")
  expect_equal(out$reference_action[out$accession == "KM057967"], "remove")
})

test_that("Zaniolepis: a BLAST 'remove' that the local set corroborates is vetoed to 'inspect'; Jordania's 'remove' stands", {
  local <- corroborate_references_locally(
    .local_seq_matrix_fixture(),
    .local_reference_meta_fixture()
  )
  out <- score_reference_labels(.veto_eval_fixture(), local_corroboration = local)
  z <- out[out$accession == "KM057996", ]
  expect_equal(z$reference_action, "inspect")
  expect_equal(z$action_reason, "vetoed_by_local_corroboration")
  expect_equal(z$corroboration_source, "local")
  expect_equal(z$local_best_independent_pident, 100)
  expect_equal(z$local_n_independent_conspecific, 1L)

  j <- out[out$accession == "KM057967", ]
  expect_equal(j$reference_action, "remove")
  expect_true(is.na(j$action_reason))
  expect_equal(j$corroboration_source, "none")
})

test_that("label_confidence stays BLAST-only: the veto changes reference_action, not the probability", {
  local <- corroborate_references_locally(
    .local_seq_matrix_fixture(),
    .local_reference_meta_fixture()
  )
  without <- score_reference_labels(.veto_eval_fixture())
  with <- score_reference_labels(.veto_eval_fixture(), local_corroboration = local)
  expect_equal(with$label_confidence, without$label_confidence)
  expect_equal(with$label_identity_margin, without$label_identity_margin)
  expect_equal(with$hierarchy_flag, without$hierarchy_flag)
})

test_that("corroboration_source reads 'both' when BLAST and the local set agree", {
  local <- data.frame(
    accession = "OK172573", local_tier = "corroborated",
    n_independent_conspecific = 2L, best_independent_pident = 0.995,
    stringsAsFactors = FALSE
  )
  out <- score_reference_labels(.veto_eval_fixture(), local_corroboration = local)
  expect_equal(out$corroboration_source[out$accession == "OK172573"], "both")
  expect_equal(out$local_best_independent_pident[out$accession == "OK172573"], 99.5)
})

test_that("a skipped 'locally_corroborated' row reads keep / source local / NA confidence, with its local numbers filled from the row", {
  out <- score_reference_labels(.veto_eval_fixture())
  s <- out[out$accession == "SKIP1", ]
  expect_equal(s$reference_action, "keep")
  expect_equal(s$corroboration_source, "local")
  expect_equal(s$action_reason, "locally_corroborated_not_blasted")
  expect_true(is.na(s$label_confidence))
  expect_equal(s$local_best_independent_pident, 100)
  expect_equal(s$local_n_independent_conspecific, 1L)
  # And the never-evaluated row is still "untested".
  expect_equal(out$reference_action[out$accession == "OVER1"], "untested")
})

test_that("score_reference_labels(overwrite=) covers the new columns too", {
  out <- score_reference_labels(.veto_eval_fixture())
  expect_error(score_reference_labels(out), "overwrite = TRUE")
  out2 <- score_reference_labels(out, overwrite = TRUE)
  expect_equal(out2$reference_action, out$reference_action)
  expect_error(
    score_reference_labels(.veto_eval_fixture(), local_corroboration = list()),
    "local_corroboration"
  )
})

test_that("refine_reference_verdicts() forwards local_corroboration and applies the veto to the trust action", {
  ev <- .veto_eval_fixture()
  local <- corroborate_references_locally(
    .local_seq_matrix_fixture(),
    .local_reference_meta_fixture()
  )
  # Pair votes for the two removable rows: three disagreeing partners each.
  pairs <- data.frame(
    id_x = rep(c("KM057996", "KM057967"), each = 3L),
    id_y = c("P1", "P2", "P3", "P4", "P5", "P6"),
    p_match = 0.986, pair_finest_common_rank = "order",
    stringsAsFactors = FALSE
  )
  out <- refine_reference_verdicts(ev,
    pair_table = pairs, verbose = FALSE,
    local_corroboration = local
  )
  expect_equal(out$reference_action[out$accession == "KM057996"], "inspect")
  expect_equal(out$reference_action_trust[out$accession == "KM057996"], "inspect")
  expect_equal(out$reference_action_trust[out$accession == "KM057967"], "remove")
  expect_true("corroboration_source" %in% names(out))
})

# ------------------------------------------------------------------------------
# evaluate_reference_accessions(local_corroboration=): the skip
# ------------------------------------------------------------------------------

.skip_mock_fetch <- function(accessions, want_sequence = TRUE, ncbi_api_key = NULL,
                             verbose = TRUE) {
  data.frame(
    accession = accessions,
    sequence = rep("ACGTACGTACGTACGT", length(accessions)),
    organism = rep("Testus fishus", length(accessions)),
    create_date = rep("2020/01/01", length(accessions)),
    stringsAsFactors = FALSE
  )
}
.skip_mock_blast <- function(seq_df, ...) {
  data.frame(
    observation_id = character(0), accession = character(0), score = numeric(0),
    stringsAsFactors = FALSE
  )
}
.skip_mock_tax <- function(accessions, ncbi_api_key = NULL, verbose = TRUE) {
  data.frame(accession = character(0), stringsAsFactors = FALSE)
}
.skip_local_table <- function() {
  data.frame(
    accession = c("KM057996", "KM057967"),
    species = c("Zaniolepis frenata", "Jordania zonope"),
    n_conspecific = c(1L, 0L), n_independent_conspecific = c(1L, 0L),
    best_independent_pident = c(1.0, NA), best_independent_partner = c("OQ846041", NA),
    local_tier = c("corroborated", "singleton"),
    stringsAsFactors = FALSE
  )
}

test_that("a locally corroborated accession is never fetched or BLASTed; it gets a 'locally_corroborated' row with the corroboration's numbers", {
  fetched <- character(0)
  counting_fetch <- function(accessions, ...) {
    fetched <<- c(fetched, accessions)
    .skip_mock_fetch(accessions, ...)
  }
  local_mocked_bindings(
    .fetch_reference_accession_records = counting_fetch,
    blast_sequences = .skip_mock_blast, .resolve_taxonomy_by_acc = .skip_mock_tax,
    .package = "TaxaMatch"
  )
  expect_message(
    out <- suppressWarnings(evaluate_reference_accessions(
      c("KM057996", "KM057967"),
      cache_dir = NULL, verbose = TRUE,
      local_corroboration = .skip_local_table()
    )),
    "1 skipped: independently corroborated in the local reference set"
  )
  expect_false("KM057996" %in% fetched)
  expect_true("KM057967" %in% fetched)

  z <- out[out$accession == "KM057996", ]
  expect_equal(z$hierarchy_flag, "locally_corroborated")
  expect_equal(z$n_independent_top_matches, 1L)
  expect_equal(z$best_agreeing_pident, 100)
  expect_true(z$congruent_evidence_exists_anywhere)
  expect_equal(z$finest_common_rank, "species")
  expect_equal(z$listed_taxon, "Zaniolepis frenata")
  expect_true(is.na(z$frac_independent_below_min_congruent_rank))
  expect_true(is.na(z$best_disagreeing_pident))
  expect_false(z$cache_hit)
  expect_equal(z$reference_action, "keep")
  expect_equal(z$corroboration_source, "local")
  expect_equal(attr(out, "run_summary")$n_skipped_locally_corroborated, 1L)
  expect_equal(attr(out, "run_summary")$pct_complete, 100)
  # 2026-09-05 critical-fix-review finding B5: the corroborating accession
  # itself is now visible, not just its numbers -- so its own label can be
  # checked/re-evaluated independently rather than trusted forever unnamed.
  expect_equal(z$local_corroborator_accession, "OQ846041")

  # The uncorroborated one went through the ordinary path -- no local
  # corroborator to name.
  j <- out[out$accession == "KM057967", ]
  expect_equal(j$hierarchy_flag, "insufficient_independent_evidence")
  expect_true(is.na(j$local_corroborator_accession))
})

test_that("the skipped row is cached with TTL Inf, and skip_locally_corroborated = FALSE sends it to BLAST after all", {
  skip_if_not_installed("withr")
  cache_dir <- withr::local_tempdir()
  fetched <- character(0)
  counting_fetch <- function(accessions, ...) {
    fetched <<- c(fetched, accessions)
    .skip_mock_fetch(accessions, ...)
  }
  local_mocked_bindings(
    .fetch_reference_accession_records = counting_fetch,
    blast_sequences = .skip_mock_blast, .resolve_taxonomy_by_acc = .skip_mock_tax,
    .package = "TaxaMatch"
  )
  suppressWarnings(evaluate_reference_accessions(
    "KM057996",
    cache_dir = cache_dir, verbose = FALSE,
    local_corroboration = .skip_local_table()
  ))
  cached <- readRDS(file.path(cache_dir, "reference_accession_cache.rds"))
  expect_equal(cached$hierarchy_flag, "locally_corroborated")

  # Age it far past every TTL: still served from cache, no fetch.
  cached$evaluated_at <- cached$evaluated_at - 10000 * 86400
  saveRDS(cached, file.path(cache_dir, "reference_accession_cache.rds"))
  out2 <- suppressWarnings(evaluate_reference_accessions(
    "KM057996",
    cache_dir = cache_dir, verbose = FALSE
  ))
  expect_true(out2$cache_hit)
  expect_equal(out2$hierarchy_flag, "locally_corroborated")
  expect_equal(length(fetched), 0L)
  # A purely cache-served call still carries the post-hoc columns.
  expect_true(all(c("reference_action", "listed_taxon_is_species", "corroboration_source")
  %in% names(out2)))

  # Opting out of the skip re-evaluates the cached skip row.
  out3 <- suppressWarnings(evaluate_reference_accessions(
    "KM057996",
    cache_dir = cache_dir, verbose = FALSE,
    local_corroboration = .skip_local_table(), skip_locally_corroborated = FALSE
  ))
  expect_equal(fetched, "KM057996")
  expect_equal(out3$hierarchy_flag, "insufficient_independent_evidence")
})

test_that("an accession that already has a BLAST verdict keeps it; the skip only applies to rows needing evaluation", {
  skip_if_not_installed("withr")
  cache_dir <- withr::local_tempdir()
  local_mocked_bindings(
    .fetch_reference_accession_records = .skip_mock_fetch,
    blast_sequences = .skip_mock_blast, .resolve_taxonomy_by_acc = .skip_mock_tax,
    .package = "TaxaMatch"
  )
  first <- suppressWarnings(evaluate_reference_accessions(
    "KM057996",
    cache_dir = cache_dir, verbose = FALSE
  ))
  expect_equal(first$hierarchy_flag, "insufficient_independent_evidence")
  # insufficient has a 180-day TTL; inside it, the BLAST verdict is served.
  second <- suppressWarnings(evaluate_reference_accessions(
    "KM057996",
    cache_dir = cache_dir, verbose = FALSE,
    local_corroboration = .skip_local_table()
  ))
  expect_equal(second$hierarchy_flag, "insufficient_independent_evidence")
  expect_true(second$cache_hit)
})

test_that("evaluate_reference_accessions() validates the new arguments", {
  expect_error(
    evaluate_reference_accessions("A1",
      cache_dir = NULL,
      skip_locally_corroborated = NA
    ),
    "skip_locally_corroborated"
  )
  expect_error(
    evaluate_reference_accessions("A1",
      cache_dir = NULL,
      local_corroboration = data.frame(x = 1)
    ),
    "local_corroboration is missing"
  )
  expect_error(
    evaluate_reference_accessions("A1", cache_dir = NULL, query_span = "bogus"),
    "arg"
  )
})

# ------------------------------------------------------------------------------
# Downstream: "locally_corroborated" is never a flag
# ------------------------------------------------------------------------------

.lc_full_eval <- function() {
  data.frame(
    accession = c("A1", "A2", "A3"),
    hierarchy_flag = c("locally_corroborated", "incongruent", "congruent"),
    finest_common_rank = c("species", "order", "species"),
    frac_independent_below_min_congruent_rank = c(NA, 0.875, 0.083),
    n_independent_top_matches = c(2L, 3L, 5L), n_top_matches_available = c(NA, 3L, 5L),
    best_hit_pident = c(NA, 98.6, 99.9), best_agreeing_pident = c(100, NA, 99.9),
    best_disagreeing_pident = c(NA, 98.6, NA),
    congruent_evidence_exists_anywhere = c(TRUE, FALSE, TRUE),
    congruent_evidence_best_pident = c(NA, NA, 99.9),
    stringsAsFactors = FALSE
  )
}

test_that("remove_incongruent_references() never removes a locally_corroborated accession under either gate", {
  match_df <- data.frame(accession = c("A1", "A2", "A3"), stringsAsFactors = FALSE)
  ev <- .lc_full_eval()
  out_action <- suppressMessages(remove_incongruent_references(match_df, ev))
  expect_setequal(out_action$accession, c("A1", "A3"))
  out_flag <- suppressMessages(remove_incongruent_references(match_df, ev, gate = "flag"))
  expect_setequal(out_flag$accession, c("A1", "A3"))
  out_broad <- suppressMessages(remove_incongruent_references(
    match_df, ev,
    gate = "flag", remove_insufficient_evidence = TRUE
  ))
  expect_true("A1" %in% out_broad$accession)
})

test_that("flag_incongruent_references() carries the new columns when present", {
  match_df <- data.frame(accession = c("A1", "A2"), stringsAsFactors = FALSE)
  ev <- score_reference_labels(.lc_full_eval())
  out <- flag_incongruent_references(match_df, ev)
  expect_equal(out$hierarchy_flag, c("locally_corroborated", "incongruent"))
  expect_equal(out$corroboration_source, c("local", "none"))
  expect_equal(out$reference_action, c("keep", "remove"))
  expect_true("action_reason" %in% names(out))
})

test_that("verify_flagged_references() counts locally_corroborated as verified clean", {
  mock_qc <- data.frame(
    accession = c("A1", "A2"),
    hierarchy_flag = c("locally_corroborated", "incongruent"),
    stringsAsFactors = FALSE
  )
  local_mocked_bindings(
    evaluate_reference_accessions = function(accessions, ...) mock_qc,
    .package = "TaxaMatch"
  )
  result <- suppressMessages(verify_flagged_references(c("A1", "A2")))
  expect_equal(result$verified_clean, "A1")
})

test_that("a locally_corroborated partner is never discounted by the trust weight", {
  w <- .partner_trust_weight(
    flag = c("locally_corroborated", "incongruent", "congruent"),
    action = c("keep", "remove", "keep"),
    label_confidence = c(NA, 0.01, 0.99)
  )
  expect_equal(w, c(1, 0, 1))
})

# ------------------------------------------------------------------------------
# Primer-stripped query (item 1) -- the real KM057996 record
# ------------------------------------------------------------------------------

# GenBank KM057996 (Zaniolepis frenata), the complete 718 bp deposit, verbatim.
.km057996 <- paste0(
  "TGCCCTAATAGTTCCCCGCCCGGGAACAAGGAGCTGGTATCAGGCACAACCCTACTGAGCCCATGACGCCTTGCTTAGCCACACCC",
  "TCAAGGGAACTCAGCAGTGATAAACATTAAGCCATAAGTGAAAACTTGACTTAGTTAAAGCTAAGAGGGCCGGTAAAACTCGTGCC",
  "AGCCACCGCGGTTATACGAGAGACCCAAGTTGATAGCCCCCGGCGTAAAGCGTGGTTAAGTTAAAACTAAAACTAAAGCCGAACAC",
  "CTTCAAGGCTGTTATACGCACCCGAAGACAAGAAGTTCACCCACGAAAGTGGCTTTATTTAATCTGACCCCACGAAAGCTACGGAA",
  "CAAACTGGGATTAGATACCCCACTATGCCTAGCCCTAAACATTGATAGTACACTACGCCCACTATCCGCCTGGGTACTACGAGCCT",
  "CAGCTTAAAACCCAAAGGACTTGGCGGTGCTTTAGATCCACCTAGAGGAGCCTGTTCTAGAACCGATAACCCCCGTTCAACCTCAC",
  "CTTTCCTTGTTTTCCCCGCCTATATACCGCCGTCGTCAGCTTACCCTGTGAAGGACTAATAGTAAGCAAAACTGGTAAAACCCAAA",
  "ACGTCAGGTCGAGGTGTAGCGCATGGGAAGGGAAGAAATGGGCTACATTCGCTACCACAGCGAATACGGATGGTGTACTGAAACGT",
  "ACGCCTGAAGGAGGATTTAGCAGTATGCAG"
)

test_that("the real KM057996 record trims to 217 bp primer-inclusive and 169 bp primer-stripped", {
  skip_if_not_installed("Biostrings")
  expect_equal(nchar(.km057996), 718L)
  inclusive <- .trim_queries_to_amplicon(.km057996, "MiFishU",
    strip_primers = FALSE,
    verbose = FALSE
  )
  stripped <- .trim_queries_to_amplicon(.km057996, "MiFishU",
    strip_primers = TRUE,
    verbose = FALSE
  )
  expect_equal(nchar(inclusive), 217L)
  expect_equal(nchar(stripped), 169L)
  # The stripped span is the interior of the inclusive one: MiFish-U F is
  # 21 bp, R is 27 bp.
  expect_equal(stripped, substr(inclusive, 22L, 217L - 27L))
  # Default is stripped.
  expect_equal(.trim_queries_to_amplicon(.km057996, "MiFishU", verbose = FALSE), stripped)
})

test_that("a 169 bp primer-free input passes through unchanged; a 217 bp inclusive input is stripped", {
  skip_if_not_installed("Biostrings")
  inclusive <- .trim_queries_to_amplicon(.km057996, "MiFishU",
    strip_primers = FALSE,
    verbose = FALSE
  )
  stripped <- .trim_queries_to_amplicon(.km057996, "MiFishU", verbose = FALSE)
  expect_equal(
    as.character(.trim_queries_to_amplicon(stripped, "MiFishU", verbose = FALSE)),
    as.character(stripped)
  )
  expect_equal(
    as.character(.trim_queries_to_amplicon(inclusive, "MiFishU", verbose = FALSE)),
    as.character(stripped)
  )
})

test_that(".resolve_trimmed_span_max(strip_primers = TRUE) is the inclusive bound minus both primer lengths", {
  skip_if_not_installed("TaxaTools")
  pi <- TaxaTools::resolve_barcode_primers("MiFishU")
  expect_equal(
    .resolve_trimmed_span_max("MiFishU", strip_primers = TRUE),
    .resolve_trimmed_span_max("MiFishU") - nchar(pi$fwd) - nchar(pi$rev)
  )
  expect_equal(
    .resolve_trimmed_span_max("MiFishU", strip_primers = TRUE),
    as.numeric(pi$amplicon_range[2])
  )
  # A correctly stripped real query is not "still over-length" under the
  # stripped bound.
  stripped <- .trim_queries_to_amplicon(.km057996, "MiFishU", verbose = FALSE)
  expect_false(nchar(stripped) > .resolve_trimmed_span_max("MiFishU", strip_primers = TRUE))
})

test_that("evaluate_reference_accessions(query_span=) submits the stripped amplicon by default and the inclusive span on request", {
  skip_if_not_installed("Biostrings")
  seen <- NULL
  mock_fetch <- function(accessions, want_sequence = TRUE, ncbi_api_key = NULL, verbose = TRUE) {
    data.frame(
      accession = "KM057996", organism = "Zaniolepis frenata",
      create_date = "2014/08/04", sequence = .km057996, stringsAsFactors = FALSE
    )
  }
  mock_blast <- function(seq_df, ...) {
    seen <<- seq_df$sequence
    .skip_mock_blast(seq_df)
  }
  local_mocked_bindings(
    .fetch_reference_accession_records = mock_fetch, blast_sequences = mock_blast,
    .resolve_taxonomy_by_acc = .skip_mock_tax, .package = "TaxaMatch"
  )
  suppressWarnings(evaluate_reference_accessions(
    "KM057996",
    cache_dir = NULL, barcode_term = "MiFishU", verbose = FALSE
  ))
  expect_equal(nchar(seen), 169L)
  suppressWarnings(evaluate_reference_accessions(
    "KM057996",
    cache_dir = NULL, barcode_term = "MiFishU", verbose = FALSE,
    query_span = "primer_inclusive"
  ))
  expect_equal(nchar(seen), 217L)
})

# ------------------------------------------------------------------------------
# params_key / version bump / migration
# ------------------------------------------------------------------------------

test_that(".EVAL_REF_ACC_VERSION is v5_amplicon_query and query_span is in params_key", {
  expect_equal(.EVAL_REF_ACC_VERSION, "v5_amplicon_query")
  key <- .default_params_key()
  expect_match(key, "\\|amplicon\\|v5_amplicon_query$")
  key_inc <- .build_params_key(
    5L, "family", 5L, 0.5, 3L, 8, 70, 20L, "remote", "nt",
    "primer_inclusive"
  )
  expect_false(identical(key, key_inc))
  expect_match(key_inc, "\\|primer_inclusive\\|v5_amplicon_query$")
})

test_that("changing query_span invalidates a cached row (it is verdict-affecting)", {
  skip_if_not_installed("withr")
  cache_dir <- withr::local_tempdir()
  fetch_calls <- 0L
  counting_fetch <- function(...) {
    fetch_calls <<- fetch_calls + 1L
    .skip_mock_fetch(...)
  }
  local_mocked_bindings(
    .fetch_reference_accession_records = counting_fetch,
    blast_sequences = .skip_mock_blast, .resolve_taxonomy_by_acc = .skip_mock_tax,
    .package = "TaxaMatch"
  )
  suppressWarnings(evaluate_reference_accessions("A1", cache_dir = cache_dir, verbose = FALSE))
  after_first <- fetch_calls
  suppressWarnings(evaluate_reference_accessions("A1",
    cache_dir = cache_dir, verbose = FALSE,
    query_span = "primer_inclusive"
  ))
  expect_gt(fetch_calls, after_first)
  # ...while skip_locally_corroborated is NOT in the key.
  after_second <- fetch_calls
  suppressWarnings(evaluate_reference_accessions("A1",
    cache_dir = cache_dir, verbose = FALSE,
    query_span = "primer_inclusive",
    skip_locally_corroborated = FALSE
  ))
  expect_equal(fetch_calls, after_second)
})

.old_key_cache <- function() {
  old_key <- "5|family|5|0.5|3|8|70|20|remote|nt|v4_hybrid_maternal_proxy"
  data.frame(
    accession = c("C1", "C2", "I1", "S1", "O1"),
    listed_taxon = "Testus fishus",
    n_independent_top_matches = c(5L, 5L, 3L, 1L, NA_integer_),
    n_top_matches_available = c(5L, 5L, 3L, 1L, NA_integer_),
    frac_independent_below_min_congruent_rank = c(0.08, 0.08, 0.875, 0.5, NA),
    finest_common_rank = c("species", "species", "order", NA, NA),
    best_hit_pident = 99, best_agreeing_pident = c(99, 99, NA, 99, NA),
    best_disagreeing_pident = c(NA, NA, 98, NA, NA), best_disagreeing_taxon = NA_character_,
    congruent_evidence_exists_anywhere = c(TRUE, TRUE, FALSE, TRUE, NA),
    congruent_evidence_best_pident = c(99, 99, NA, 99, NA),
    hierarchy_flag = c(
      "congruent", "congruent", "incongruent",
      "insufficient_independent_evidence", "not_evaluated_oversized"
    ),
    evaluated_at = Sys.time(), params_key = old_key,
    taxonomy_resolution_source = "direct",
    stringsAsFactors = FALSE
  )
}

test_that("migrate_reference_cache() carries only congruent rows to the new key, stamps migrated_from, backs up first", {
  skip_if_not_installed("withr")
  cache_dir <- withr::local_tempdir()
  cache_path <- file.path(cache_dir, "reference_accession_cache.rds")
  saveRDS(.old_key_cache(), cache_path)
  old_key <- unique(.old_key_cache()$params_key)

  res <- NULL
  expect_message(res <- migrate_reference_cache(cache_dir), "2 'congruent' row")
  new_key <- .default_params_key()
  expect_equal(res$to_key, new_key)
  expect_equal(res$n_carried_forward, 2L)
  expect_equal(res$n_left_to_reevaluate, 3L)
  expect_equal(as.integer(res$left_by_flag[["incongruent"]]), 1L)

  migrated <- readRDS(cache_path)
  expect_true("migrated_from" %in% names(migrated))
  cong <- migrated[migrated$hierarchy_flag == "congruent", ]
  expect_true(all(cong$params_key == new_key))
  expect_true(all(cong$migrated_from == old_key))
  other <- migrated[migrated$hierarchy_flag != "congruent", ]
  expect_true(all(other$params_key == old_key))
  expect_true(all(is.na(other$migrated_from)))

  backup <- paste0(cache_path, ".bak_pre_v5_amplicon_query")
  expect_true(file.exists(backup))
  expect_equal(readRDS(backup)$params_key, rep(old_key, 5L))

  # Idempotent, and the backup is never overwritten.
  writeLines("sentinel", file.path(cache_dir, "touch"))
  res2 <- suppressMessages(migrate_reference_cache(cache_dir))
  expect_equal(res2$n_carried_forward, 0L)
  expect_equal(res2$n_already_current, 2L)
  expect_equal(readRDS(backup)$params_key, rep(old_key, 5L))
})

test_that("after migration the carried-forward rows are served from cache and the rest re-evaluate; new rows rbind onto the migrated schema", {
  skip_if_not_installed("withr")
  cache_dir <- withr::local_tempdir()
  saveRDS(.old_key_cache(), file.path(cache_dir, "reference_accession_cache.rds"))
  suppressMessages(migrate_reference_cache(cache_dir))

  fetched <- character(0)
  counting_fetch <- function(accessions, ...) {
    fetched <<- c(fetched, accessions)
    .skip_mock_fetch(accessions, ...)
  }
  local_mocked_bindings(
    .fetch_reference_accession_records = counting_fetch,
    blast_sequences = .skip_mock_blast, .resolve_taxonomy_by_acc = .skip_mock_tax,
    .package = "TaxaMatch"
  )
  out <- suppressWarnings(evaluate_reference_accessions(
    c("C1", "C2", "I1", "S1", "O1", "NEW1"),
    cache_dir = cache_dir, verbose = FALSE
  ))
  expect_setequal(fetched, c("I1", "S1", "O1", "NEW1"))
  expect_true(all(out$cache_hit[out$accession %in% c("C1", "C2")]))
  expect_equal(out$hierarchy_flag[out$accession %in% c("C1", "C2")], c("congruent", "congruent"))
  # The cache file has one row per accession under the NEW key (the three
  # re-evaluated rows' old-key copies linger, as any superseded-key row
  # always has) and carries the extra column throughout.
  cached <- readRDS(file.path(cache_dir, "reference_accession_cache.rds"))
  expect_true("migrated_from" %in% names(cached))
  current <- cached[cached$params_key == .default_params_key(), ]
  expect_equal(nrow(current), 6L)
  expect_equal(sort(current$accession), c("C1", "C2", "I1", "NEW1", "O1", "S1"))
  expect_true(all(is.na(current$migrated_from[current$accession %in% c("I1", "S1", "O1", "NEW1")])))
})

test_that("migrate_reference_cache(from_key=, to_key=) restricts the rewrite, and validates", {
  skip_if_not_installed("withr")
  cache_dir <- withr::local_tempdir()
  cache <- .old_key_cache()
  cache$params_key[1] <- "some|other|key"
  saveRDS(cache, file.path(cache_dir, "reference_accession_cache.rds"))
  res <- suppressMessages(migrate_reference_cache(
    cache_dir,
    to_key = "target|key|v9", from_key = "some|other|key"
  ))
  expect_equal(res$n_carried_forward, 1L)
  migrated <- readRDS(file.path(cache_dir, "reference_accession_cache.rds"))
  expect_equal(migrated$params_key[1], "target|key|v9")
  expect_equal(migrated$params_key[2], cache$params_key[2])
  expect_true(file.exists(file.path(cache_dir, "reference_accession_cache.rds.bak_pre_v9")))

  expect_error(migrate_reference_cache(file.path(cache_dir, "nope")), "existing directory")
  empty_dir <- withr::local_tempdir()
  expect_error(migrate_reference_cache(empty_dir), "nothing to migrate")
})

test_that("migrate_reference_cache() migrates the pair-cache sidecar for the same accessions", {
  skip_if_not_installed("withr")
  cache_dir <- withr::local_tempdir()
  saveRDS(.old_key_cache(), file.path(cache_dir, "reference_accession_cache.rds"))
  old_key <- unique(.old_key_cache()$params_key)
  pairs <- data.frame(
    id_x = c("C1", "C1", "I1"), id_y = c("P1", "P2", "P3"), p_match = 0.99,
    pair_finest_common_rank = "species", species_y = "Testus fishus",
    params_key = old_key, evaluated_at = Sys.time(), stringsAsFactors = FALSE
  )
  saveRDS(pairs, file.path(cache_dir, "reference_pair_cache.rds"))
  res <- suppressMessages(migrate_reference_cache(cache_dir))
  expect_equal(res$n_pairs_carried_forward, 2L)
  migrated <- readRDS(file.path(cache_dir, "reference_pair_cache.rds"))
  expect_equal(migrated$params_key[migrated$id_x == "C1"], rep(.default_params_key(), 2L))
  expect_equal(migrated$params_key[migrated$id_x == "I1"], old_key)
  expect_true(file.exists(file.path(cache_dir, "reference_pair_cache.rds.bak_pre_v5_amplicon_query")))
})
