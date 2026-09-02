# ==============================================================================
# Tests for evaluate_reference_accessions() / remove_incongruent_references()
# and their internal helpers (.build_submission_batch_lookup(),
# .same_submission_batch(), .compute_hierarchy_congruence()).
#
# Fully offline: .fetch_reference_accession_records(), blast_sequences(), and
# .resolve_taxonomy_by_acc() are all mocked via local_mocked_bindings(),
# matching this package's own established pattern (test-blast.R's
# asNamespace() wrappers for direct internal-function tests). All three are
# internal to TaxaMatch itself (no cross-package mocking needed here, unlike
# an earlier version of this file that mocked TaxaTools::fill_higher_ranks()
# before evaluate_reference_accessions() was rewritten to resolve query-side
# taxonomy via TaxaMatch's own NCBI-taxonomy-DB mechanism instead).
# ==============================================================================

.build_submission_batch_lookup_int <- function(...)
  get(".build_submission_batch_lookup", envir = asNamespace("TaxaMatch"))(...)
.same_submission_batch_int <- function(...)
  get(".same_submission_batch", envir = asNamespace("TaxaMatch"))(...)
.compute_hierarchy_congruence_int <- function(...)
  get(".compute_hierarchy_congruence", envir = asNamespace("TaxaMatch"))(...)

# ------------------------------------------------------------------------------
# .build_submission_batch_lookup() / .same_submission_batch()
# ------------------------------------------------------------------------------

test_that(".build_submission_batch_lookup() parses dates and accession components", {
  ref_df <- data.frame(
    composite_id = c("MH538728", "MH538729", "XYZ_weird", "MH538728"),
    create_date  = c("2020/01/10", "2020/01/12", NA, "2020/01/10"),
    stringsAsFactors = FALSE
  )
  out <- .build_submission_batch_lookup_int(ref_df)

  expect_equal(nrow(out), 3L)  # de-duplicated by composite_id
  expect_equal(out$acc_date[out$composite_id == "MH538728"], as.Date("2020-01-10"))
  expect_equal(out$acc_prefix[out$composite_id == "MH538728"], "MH")
  expect_equal(out$acc_num[out$composite_id == "MH538728"], 538728)
  expect_true(is.na(out$acc_date[out$composite_id == "XYZ_weird"]))
  expect_true(is.na(out$acc_prefix[out$composite_id == "XYZ_weird"]))
})

test_that(".build_submission_batch_lookup() handles a missing create_date column", {
  ref_df <- data.frame(composite_id = c("AB123", "AB124"), stringsAsFactors = FALSE)
  out <- .build_submission_batch_lookup_int(ref_df)
  expect_true(all(is.na(out$acc_date)))
})

test_that(".same_submission_batch() fires on date proximity", {
  out <- .same_submission_batch_int(
    x_date = as.Date("2020-01-10"), x_prefix = "AB", x_num = 100,
    y_date = as.Date("2020-01-12"), y_prefix = "CD", y_num = 999,
    submission_window = 5L
  )
  expect_true(out)
})

test_that(".same_submission_batch() fires on accession-number proximity", {
  out <- .same_submission_batch_int(
    x_date = as.Date(NA), x_prefix = "AB", x_num = 100,
    y_date = as.Date(NA), y_prefix = "AB", y_num = 102,
    submission_window = 5L
  )
  expect_true(out)
})

test_that(".same_submission_batch() is FALSE when neither signal fires", {
  out <- .same_submission_batch_int(
    x_date = as.Date("2020-01-10"), x_prefix = "AB", x_num = 100,
    y_date = as.Date("2021-06-01"), y_prefix = "CD", y_num = 999,
    submission_window = 5L
  )
  expect_false(out)
})

# ------------------------------------------------------------------------------
# .compute_hierarchy_congruence() -- BLAST-hit-shaped pair table
# ------------------------------------------------------------------------------

test_that(".compute_hierarchy_congruence() flags a congruent accession correctly", {
  sm <- data.frame(
    id_x = rep("ACC001", 3), id_y = c("HIT_B", "HIT_C", "HIT_D"),
    p_match = c(0.99, 0.98, 0.85),
    family.x = "Atherinopsidae", genus.x = "Menidia", species.x = "Menidia beryllina",
    family.y = c("Atherinopsidae", "Atherinopsidae", "Sparidae"),
    genus.y  = c("Menidia", "Menidia", "Sparus"),
    species.y = c("Menidia beryllina", "Menidia beryllina", "Sparus aurata"),
    stringsAsFactors = FALSE
  )
  ref_df <- data.frame(
    composite_id = c("ACC001", "HIT_B", "HIT_C", "HIT_D"),
    create_date  = c("2020/01/10", "2021/06/01", "2019/03/15", "2018/11/20"),
    stringsAsFactors = FALSE
  )
  out <- .compute_hierarchy_congruence_int(
    sm, ref_df, rank_system = c("family", "genus", "species"),
    top_n = 5L, min_congruent_rank = "family", submission_window = 5L
  )
  expect_equal(nrow(out), 1L)
  expect_equal(out$n_independent_top_matches, 3L)
  expect_lt(out$frac_independent_below_min_congruent_rank, 0.5)
})

test_that(".compute_hierarchy_congruence() excludes same-submission-batch partners", {
  sm <- data.frame(
    id_x = rep("ACC001", 2), id_y = c("HIT_SAMEBATCH", "HIT_INDEP"),
    p_match = c(0.999, 0.98),
    family.x = "Atherinopsidae", genus.x = "Menidia", species.x = "Menidia beryllina",
    family.y = c("Atherinopsidae", "Atherinopsidae"),
    genus.y  = c("Menidia", "Menidia"),
    species.y = c("Menidia beryllina", "Menidia beryllina"),
    stringsAsFactors = FALSE
  )
  ref_df <- data.frame(
    composite_id = c("ACC001", "HIT_SAMEBATCH", "HIT_INDEP"),
    create_date  = c("2020/01/10", "2020/01/12", "2021/06/01"),
    stringsAsFactors = FALSE
  )
  out <- .compute_hierarchy_congruence_int(
    sm, ref_df, rank_system = c("family", "genus", "species"), submission_window = 5L
  )
  # Only HIT_INDEP is independent -- HIT_SAMEBATCH is within 2 days.
  expect_equal(out$n_independent_top_matches, 1L)
  expect_equal(out$n_top_matches_available, 2L)
})

test_that(".compute_hierarchy_congruence() flags an incongruent accession correctly", {
  sm <- data.frame(
    id_x = rep("ACC002", 3), id_y = c("HIT_E", "HIT_F", "HIT_G"),
    p_match = c(0.95, 0.93, 0.9),
    family.x = "Cottidae", genus.x = "Cottus", species.x = "Cottus asper",
    family.y = "Salmonidae", genus.y = "Salmo", species.y = "Salmo salar",
    stringsAsFactors = FALSE
  )
  ref_df <- data.frame(
    composite_id = c("ACC002", "HIT_E", "HIT_F", "HIT_G"),
    create_date  = c("2020/01/10", "2021/06/01", "2019/03/15", "2018/11/20"),
    stringsAsFactors = FALSE
  )
  out <- .compute_hierarchy_congruence_int(
    sm, ref_df, rank_system = c("family", "genus", "species")
  )
  expect_equal(out$n_independent_top_matches, 3L)
  expect_gte(out$frac_independent_below_min_congruent_rank, 0.5)
})

test_that(".compute_hierarchy_congruence() reports best_disagreeing_taxon consistently with best_disagreeing_pident (2026-08-13)", {
  sm <- data.frame(
    id_x = rep("ACC002", 3), id_y = c("HIT_E", "HIT_F", "HIT_G"),
    p_match = c(0.95, 0.93, 0.9),
    family.x = "Cottidae", genus.x = "Cottus", species.x = "Cottus asper",
    family.y = c("Salmonidae", "Salmonidae", "Salmonidae"),
    genus.y = c("Salmo", "Salmo", "Salmo"),
    species.y = c("Salmo salar", "Salmo trutta", "Salmo obtusirostris"),
    stringsAsFactors = FALSE
  )
  ref_df <- data.frame(
    composite_id = c("ACC002", "HIT_E", "HIT_F", "HIT_G"),
    create_date  = c("2020/01/10", "2021/06/01", "2019/03/15", "2018/11/20"),
    stringsAsFactors = FALSE
  )
  out <- .compute_hierarchy_congruence_int(
    sm, ref_df, rank_system = c("family", "genus", "species")
  )
  # HIT_E (p_match=0.95) is the highest-identity disagreeing hit -- its
  # species.y ("Salmo salar") should be the reported best_disagreeing_taxon,
  # matching best_disagreeing_pident's own value (95).
  expect_equal(out$best_disagreeing_pident, 95)
  expect_equal(out$best_disagreeing_taxon, "Salmo salar")
})

test_that(".compute_hierarchy_congruence() reports best_disagreeing_taxon = NA when nothing disagrees", {
  sm <- data.frame(
    id_x = rep("ACC001", 2), id_y = c("HIT_A", "HIT_B"),
    p_match = c(0.98, 0.96),
    family.x = "Atherinopsidae", genus.x = "Menidia", species.x = "Menidia beryllina",
    family.y = c("Atherinopsidae", "Atherinopsidae"),
    genus.y = c("Menidia", "Menidia"),
    species.y = c("Menidia beryllina", "Menidia beryllina"),
    stringsAsFactors = FALSE
  )
  ref_df <- data.frame(
    composite_id = c("ACC001", "HIT_A", "HIT_B"),
    create_date  = c("2020/01/01", "2021/05/01", "2019/07/01"),
    stringsAsFactors = FALSE
  )
  out <- .compute_hierarchy_congruence_int(
    sm, ref_df, rank_system = c("family", "genus", "species")
  )
  expect_true(is.na(out$best_disagreeing_taxon))
})

test_that(".compute_hierarchy_congruence() excludes a non-species-resolved comparison partner from the vote (2026-08-13)", {
  # Real GreatLakes Stereolepis doederleini case: the only real independent
  # hit found was itself never resolved to species ("Serranidae sp.
  # JL-2015" -- family used in place of a genus, informal specimen code).
  # Its own agree/disagree status shouldn't count as a real vote.
  sm <- data.frame(
    id_x = rep("ACC_STEREO", 1), id_y = "HIT_UNRESOLVED",
    p_match = 0.9963,
    family.x = "Polyprionidae", genus.x = "Stereolepis",
    species.x = "Stereolepis doederleini",
    family.y = "Serranidae", genus.y = NA_character_,
    species.y = "Serranidae sp. JL-2015",
    stringsAsFactors = FALSE
  )
  ref_df <- data.frame(
    composite_id = c("ACC_STEREO", "HIT_UNRESOLVED"),
    create_date  = c("2022/01/18", "2015/11/01"),
    stringsAsFactors = FALSE
  )
  out <- .compute_hierarchy_congruence_int(
    sm, ref_df, rank_system = c("family", "genus", "species")
  )
  expect_equal(out$n_independent_top_matches, 0L)   # the only hit is excluded
  expect_equal(out$n_top_matches_available, 1L)      # still counted here -- pre-exclusion diagnostic
})

test_that(".compute_hierarchy_congruence() still counts a real, species-resolved disagreeing partner (genuine mislabel evidence preserved)", {
  # Regression guard: this fix must NOT suppress a genuine mislabel signal
  # -- a disagreeing partner that IS itself resolved to species (a real,
  # named, different species) still counts as a real vote.
  sm <- data.frame(
    id_x = rep("ACC002", 3), id_y = c("HIT_E", "HIT_F", "HIT_G"),
    p_match = c(0.95, 0.93, 0.9),
    family.x = "Cottidae", genus.x = "Cottus", species.x = "Cottus asper",
    family.y = "Salmonidae", genus.y = "Salmo", species.y = "Salmo salar",
    stringsAsFactors = FALSE
  )
  ref_df <- data.frame(
    composite_id = c("ACC002", "HIT_E", "HIT_F", "HIT_G"),
    create_date  = c("2020/01/10", "2021/06/01", "2019/03/15", "2018/11/20"),
    stringsAsFactors = FALSE
  )
  out <- .compute_hierarchy_congruence_int(
    sm, ref_df, rank_system = c("family", "genus", "species")
  )
  expect_equal(out$n_independent_top_matches, 3L)  # unchanged from the pre-fix test above
  expect_gte(out$frac_independent_below_min_congruent_rank, 0.5)
})

test_that(".compute_hierarchy_congruence(require_species_resolved_partner = FALSE) restores the old, unfiltered vote count", {
  sm <- data.frame(
    id_x = rep("ACC_STEREO", 1), id_y = "HIT_UNRESOLVED",
    p_match = 0.9963,
    family.x = "Polyprionidae", genus.x = "Stereolepis",
    species.x = "Stereolepis doederleini",
    family.y = "Serranidae", genus.y = NA_character_,
    species.y = "Serranidae sp. JL-2015",
    stringsAsFactors = FALSE
  )
  ref_df <- data.frame(
    composite_id = c("ACC_STEREO", "HIT_UNRESOLVED"),
    create_date  = c("2022/01/18", "2015/11/01"),
    stringsAsFactors = FALSE
  )
  out <- .compute_hierarchy_congruence_int(
    sm, ref_df, rank_system = c("family", "genus", "species"),
    require_species_resolved_partner = FALSE
  )
  expect_equal(out$n_independent_top_matches, 1L)  # counted again, old behavior
})

# ------------------------------------------------------------------------------
# evaluate_reference_accessions() -- full offline integration
# ------------------------------------------------------------------------------

.records_fixture <- function() {
  data.frame(
    accession = c("ACC001", "ACC002", "ACC003",
                 "HIT_A", "HIT_B", "HIT_C", "HIT_D", "HIT_E", "HIT_F", "HIT_G"),
    sequence = c("ACGTACGTACGTACGT", "TTTTGGGGCCCCAAAA", "GATTACAGATTACAGA",
                rep("NNNNNNNNNNNNNNNN", 7)),
    organism = c("Menidia beryllina", "Cottus asper", "Novataxon unicum",
                rep(NA_character_, 7)),
    create_date = c("2020/01/10", "2020/02/01", "2020/03/01",
                    "2020/01/12", "2021/06/01", "2019/03/15", "2018/11/20",
                    "2021/06/01", "2019/03/15", "2018/11/20"),
    stringsAsFactors = FALSE
  )
}

.mock_fetch_records <- function(accessions, want_sequence = TRUE, ncbi_api_key = NULL,
                                verbose = TRUE) {
  fx <- .records_fixture()
  out <- fx[fx$accession %in% accessions, , drop = FALSE]
  if (!want_sequence) out$sequence <- NA_character_
  rownames(out) <- NULL
  out
}

.hits_fixture <- function() {
  # ACC002's HIT_E/F/G deliberately share ACC002's own ORDER
  # (Scorpaeniformes) while disagreeing at FAMILY (Salmonidae vs Cottidae)
  # -- mirrors the real live-tested case that motivated extending
  # rank_system to the full ladder (a real PtConception 18S accession,
  # Abylopsis eschscholtzii, whose top BLAST hits were consistently a
  # SISTER family within the same order, not an unrelated organism; see
  # this function's own @section Coarse-rank diagnostic). This is the
  # regression guard for that fix: hierarchy_flag stays "incongruent"
  # (family-level threshold unchanged) but finest_common_rank should now
  # resolve to "order" instead of collapsing to NA.
  data.frame(
    observation_id = c(rep("ACC001", 5), rep("ACC002", 3)),
    accession       = c("ACC001", "HIT_A", "HIT_B", "HIT_C", "HIT_D",
                       "HIT_E", "HIT_F", "HIT_G"),
    score           = c(100, 99.9, 99, 98, 85, 95, 93, 90),
    query_coverage  = 95,
    kingdom         = "Animalia",
    phylum          = "Chordata",
    class           = "Actinopteri",
    order           = c("Atheriniformes", "Atheriniformes", "Atheriniformes",
                       "Atheriniformes", "Beloniformes",
                       "Scorpaeniformes", "Scorpaeniformes", "Scorpaeniformes"),
    family          = c("Atherinopsidae", "Atherinopsidae", "Atherinopsidae",
                       "Atherinopsidae", "Sparidae",
                       "Salmonidae", "Salmonidae", "Salmonidae"),
    genus           = c("Menidia", "Menidia", "Menidia", "Menidia", "Sparus",
                       "Salmo", "Salmo", "Salmo"),
    species         = c("Menidia beryllina", "Menidia beryllina", "Menidia beryllina",
                       "Menidia beryllina", "Sparus aurata",
                       "Salmo salar", "Salmo salar", "Salmo salar"),
    stringsAsFactors = FALSE
  )
}

.mock_blast_sequences <- function(seq_df, ...) {
  fx <- .hits_fixture()
  fx[fx$observation_id %in% seq_df$asv_id, , drop = FALSE]
}

.query_taxonomy_fixture <- function() {
  data.frame(
    accession = c("ACC001", "ACC002", "ACC003"),
    kingdom = "Animalia", phylum = "Chordata", class = "Actinopteri",
    order   = c("Atheriniformes", "Scorpaeniformes", "Testiformes"),
    family  = c("Atherinopsidae", "Cottidae", "Testifamilia"),
    genus   = c("Menidia", "Cottus", "Novataxon"),
    species = c("Menidia beryllina", "Cottus asper", "Novataxon unicum"),
    stringsAsFactors = FALSE
  )
}

.mock_resolve_taxonomy_by_acc <- function(accessions, ncbi_api_key = NULL, verbose = TRUE) {
  fx <- .query_taxonomy_fixture()
  out <- fx[fx$accession %in% accessions, , drop = FALSE]
  rownames(out) <- NULL
  out
}

.mock_all <- function(expr) {
  local_mocked_bindings(
    .fetch_reference_accession_records = .mock_fetch_records, .package = "TaxaMatch"
  )
  local_mocked_bindings(
    blast_sequences = .mock_blast_sequences, .package = "TaxaMatch"
  )
  local_mocked_bindings(
    .resolve_taxonomy_by_acc = .mock_resolve_taxonomy_by_acc, .package = "TaxaMatch"
  )
  force(expr)
}

test_that("evaluate_reference_accessions() classifies congruent/incongruent/insufficient correctly", {
  .mock_all({
    out <- evaluate_reference_accessions(
      c("ACC001", "ACC002", "ACC003"), cache_dir = NULL, verbose = FALSE
    )
  })

  expect_equal(nrow(out), 3L)
  expect_setequal(out$accession, c("ACC001", "ACC002", "ACC003"))

  acc1 <- out[out$accession == "ACC001", ]
  expect_equal(acc1$hierarchy_flag, "congruent")
  expect_equal(acc1$n_independent_top_matches, 3L)  # HIT_A excluded (same batch)
  expect_equal(acc1$listed_taxon, "Menidia beryllina")
  # Identity diagnostics: HIT_B (99%, agrees) beats HIT_C (98%, agrees) beats
  # HIT_D (85%, disagrees, Sparidae).
  expect_equal(acc1$best_hit_pident, 99)
  expect_equal(acc1$best_agreeing_pident, 99)
  expect_equal(acc1$best_disagreeing_pident, 85)
  expect_true(acc1$congruent_evidence_exists_anywhere)
  expect_equal(acc1$congruent_evidence_best_pident, 99)

  acc2 <- out[out$accession == "ACC002", ]
  expect_equal(acc2$hierarchy_flag, "incongruent")
  # The regression guard for the full-rank-ladder fix: ACC002's top
  # independent hits (Salmonidae) disagree at family but share ACC002's own
  # order (Scorpaeniformes, per the fixture) -- finest_common_rank should
  # report that real coarser agreement, not collapse to NA the way a
  # family/genus/species-only rank_system would.
  expect_equal(acc2$finest_common_rank, "order")
  # Identity diagnostics: NONE of ACC002's 3 independent hits agree at
  # family -- congruent_evidence_exists_anywhere should be FALSE (a
  # stronger statement than "not in the top_n", since top_n already covers
  # all 3 of ACC002's real hits here) and best_agreeing_pident NA.
  expect_equal(acc2$best_hit_pident, 95)
  expect_true(is.na(acc2$best_agreeing_pident))
  expect_equal(acc2$best_disagreeing_pident, 95)
  expect_false(acc2$congruent_evidence_exists_anywhere)
  expect_true(is.na(acc2$congruent_evidence_best_pident))

  # ACC003 has ZERO BLAST hits at all -- this is the real regression this
  # test guards: a zero-hit accession must still produce a row, not
  # silently vanish from the output.
  acc3 <- out[out$accession == "ACC003", ]
  expect_equal(acc3$hierarchy_flag, "insufficient_independent_evidence")
  expect_equal(acc3$n_independent_top_matches, 0L)
  expect_true(is.na(acc3$best_hit_pident))
  expect_false(acc3$congruent_evidence_exists_anywhere)
})

test_that("evaluate_reference_accessions() excludes self-hits from evidence", {
  .mock_all({
    out <- evaluate_reference_accessions("ACC001", cache_dir = NULL, verbose = FALSE)
  })
  # If the self-hit (ACC001 matching itself at score=100) were NOT excluded,
  # n_top_matches_available would be 5, not 4.
  expect_equal(out$n_top_matches_available, 4L)
})

test_that("evaluate_reference_accessions() does not cache an accession whose BLAST search timed out as insufficient_independent_evidence", {
  # Regression test for the 2026-08-09 fix: a real, large (1,183-accession)
  # remote-BLAST run found sustained NCBI queue congestion caused most
  # batches to time out at blast_sequences()'s old hardcoded poll ceiling --
  # and every affected accession was silently cached as a false
  # "insufficient_independent_evidence" verdict, indistinguishable from a
  # real zero-hit case. blast_sequences() now reports timed-out accessions
  # via attr(result, "failed_query_ids"); this confirms
  # evaluate_reference_accessions() reads that and excludes them from both
  # the computed hierarchy_flag AND the cache write.
  mock_blast_with_timeout <- function(seq_df, ...) {
    fx <- .hits_fixture()
    out <- fx[fx$observation_id %in% setdiff(seq_df$asv_id, "ACC003"), , drop = FALSE]
    attr(out, "failed_query_ids") <- "ACC003"
    out
  }

  cache_dir <- withr::local_tempdir()

  local_mocked_bindings(
    .fetch_reference_accession_records = .mock_fetch_records, .package = "TaxaMatch"
  )
  local_mocked_bindings(
    .resolve_taxonomy_by_acc = .mock_resolve_taxonomy_by_acc, .package = "TaxaMatch"
  )
  local_mocked_bindings(
    blast_sequences = mock_blast_with_timeout, .package = "TaxaMatch"
  )

  expect_warning(
    out <- evaluate_reference_accessions(
      c("ACC001", "ACC003"), cache_dir = cache_dir, verbose = FALSE
    ),
    "queue timeout"
  )

  acc3 <- out[out$accession == "ACC003", ]
  expect_equal(nrow(acc3), 1L)
  expect_true(is.na(acc3$hierarchy_flag))
  expect_false(acc3$cache_hit)

  # Confirm it was genuinely NOT written to cache: a second call, with
  # blast_sequences() now mocked to succeed for ACC003, must still show a
  # fresh (non-cache-hit) evaluation, not a stale cached row.
  local_mocked_bindings(
    blast_sequences = .mock_blast_sequences, .package = "TaxaMatch"
  )
  out2 <- evaluate_reference_accessions(
    "ACC003", cache_dir = cache_dir, verbose = FALSE
  )
  expect_false(out2$cache_hit)
  expect_equal(out2$hierarchy_flag, "insufficient_independent_evidence")
})

test_that("evaluate_reference_accessions() does not crash when EVERY accession in the call fails BLAST", {
  # Regression test, 2026-08-10: a real, sustained NCBI server-side CPU-
  # budget rejection wave affected 100% of a real 414-accession call (not
  # just some, unlike the timeout test above). query_meta was filtered down
  # to 0 rows (every accession excluded via failed_query_ids), so congruence
  # ended up 0 rows too -- and building computed_rows unconditionally then
  # crashed the ENTIRE call with "arguments imply differing number of rows:
  # 0, 1" (data.frame() does not recycle scalar columns like
  # evaluated_at/cache_hit/params_key down to 0 rows the way it recycles
  # into a longer common length). This silently destroyed every accession
  # successfully evaluated earlier in the SAME call, since the persistent
  # cache only writes once, at the very end.
  mock_blast_all_fail <- function(seq_df, ...) {
    out <- data.frame(observation_id = character(0), accession = character(0),
                      score = numeric(0), stringsAsFactors = FALSE)
    attr(out, "failed_query_ids") <- seq_df$asv_id
    out
  }

  local_mocked_bindings(
    .fetch_reference_accession_records = .mock_fetch_records, .package = "TaxaMatch"
  )
  local_mocked_bindings(
    .resolve_taxonomy_by_acc = .mock_resolve_taxonomy_by_acc, .package = "TaxaMatch"
  )
  local_mocked_bindings(blast_sequences = mock_blast_all_fail, .package = "TaxaMatch")

  expect_warning(
    out <- evaluate_reference_accessions(
      c("ACC001", "ACC002"), cache_dir = NULL, verbose = FALSE
    ),
    "queue timeout"
  )

  expect_equal(nrow(out), 2L)
  expect_true(all(is.na(out$hierarchy_flag)))
  expect_false(any(out$cache_hit))
})

test_that("evaluate_reference_accessions() dedupes input accessions", {
  .mock_all({
    out <- evaluate_reference_accessions(
      c("ACC001", "ACC001", "ACC001"), cache_dir = NULL, verbose = FALSE
    )
  })
  expect_equal(nrow(out), 1L)
})

# ------------------------------------------------------------------------------
# Chunked evaluation + circuit-breaker interaction (2026-08-14)
# ------------------------------------------------------------------------------

test_that("evaluate_reference_accessions(chunk_size = 1) gives the same verdicts as an unchunked call", {
  .mock_all({
    out_chunked <- evaluate_reference_accessions(
      c("ACC001", "ACC002", "ACC003"), cache_dir = NULL, verbose = FALSE, chunk_size = 1L
    )
  })
  .mock_all({
    out_unchunked <- evaluate_reference_accessions(
      c("ACC001", "ACC002", "ACC003"), cache_dir = NULL, verbose = FALSE, chunk_size = Inf
    )
  })
  out_chunked   <- out_chunked[order(out_chunked$accession), ]
  out_unchunked <- out_unchunked[order(out_unchunked$accession), ]
  rownames(out_chunked) <- NULL
  rownames(out_unchunked) <- NULL
  expect_equal(out_chunked$hierarchy_flag, out_unchunked$hierarchy_flag)
  expect_equal(out_chunked$best_disagreeing_taxon, out_unchunked$best_disagreeing_taxon)
  expect_equal(out_chunked$finest_common_rank, out_unchunked$finest_common_rank)
})

test_that("evaluate_reference_accessions() writes the persistent cache once per chunk, not once for the whole call", {
  save_calls <- 0L
  save_row_counts <- integer(0)
  mock_save <- function(cache_dir, cache_df) {
    save_calls <<- save_calls + 1L
    save_row_counts <<- c(save_row_counts, nrow(cache_df))
    invisible(NULL)
  }
  cache_dir_path <- withr::local_tempdir()
  local_mocked_bindings(
    .fetch_reference_accession_records = .mock_fetch_records,
    blast_sequences = .mock_blast_sequences,
    .resolve_taxonomy_by_acc = .mock_resolve_taxonomy_by_acc,
    .save_reference_accession_cache = mock_save,
    .package = "TaxaMatch"
  )
  evaluate_reference_accessions(
    c("ACC001", "ACC002", "ACC003"), cache_dir = cache_dir_path, verbose = FALSE,
    chunk_size = 1L
  )
  # Once per chunk (all 3 accessions get a real verdict, including ACC003's
  # genuine zero-hit "insufficient_independent_evidence") -- NOT once for
  # the whole call. Cache grows monotonically as each chunk's own accession
  # is added to the running accumulated cache before the next chunk writes.
  expect_equal(save_calls, 3L)
  expect_equal(save_row_counts, c(1L, 2L, 3L))
})

test_that("evaluate_reference_accessions() stops at a circuit-breaker trip: earlier chunks stay cached, later chunks are left pending", {
  # 3 accessions, chunk_size = 1 (3 chunks): ACC001 succeeds (real fixture,
  # congruent), ACC_TRIP's own blast_sequences() call reports a circuit-
  # breaker trip, ACC_NEVER (the un-reached 3rd chunk) must never even be
  # fetched or BLASTed.
  trip_records <- rbind(
    # ACC001's own row PLUS the HIT_* rows its real fixture BLAST hits point
    # at (needed for the hit_meta/create_date lookup inside the chunk
    # helper) -- only ACC_TRIP/ACC_NEVER are genuinely new here.
    .records_fixture(),
    data.frame(
      accession = c("ACC_TRIP", "ACC_NEVER"),
      sequence = c("GGGGCCCCAAAATTTT", "AAAACCCCGGGGTTTT"),
      organism = c("Trippus interruptus", "Neverus reachedus"),
      create_date = c("2021/01/01", "2021/02/01"),
      stringsAsFactors = FALSE
    )
  )
  fetch_log <- character(0)
  mock_fetch <- function(accessions, want_sequence = TRUE, ncbi_api_key = NULL, verbose = TRUE) {
    fetch_log <<- c(fetch_log, accessions)
    out <- trip_records[trip_records$accession %in% accessions, , drop = FALSE]
    if (!want_sequence) out$sequence <- NA_character_
    rownames(out) <- NULL
    out
  }
  mock_tax <- function(accessions, ncbi_api_key = NULL, verbose = TRUE) {
    fx <- .query_taxonomy_fixture()
    extra <- data.frame(
      accession = "ACC_TRIP", kingdom = "Animalia", phylum = "Chordata",
      class = "Actinopteri", order = "Testiformes", family = "Testifamilia",
      genus = "Trippus", species = "Trippus interruptus",
      stringsAsFactors = FALSE
    )
    fx <- rbind(fx, extra)
    out <- fx[fx$accession %in% accessions, , drop = FALSE]
    rownames(out) <- NULL
    out
  }
  blast_log <- character(0)
  mock_blast <- function(seq_df, ...) {
    blast_log <<- c(blast_log, seq_df$asv_id)
    if (identical(seq_df$asv_id, "ACC_TRIP")) {
      res <- data.frame(observation_id = character(0), accession = character(0),
                        score = numeric(0), query_coverage = numeric(0),
                        stringsAsFactors = FALSE)
      attr(res, "circuit_breaker_tripped") <- TRUE
      attr(res, "failed_query_ids") <- "ACC_TRIP"
      return(res)
    }
    fx <- .hits_fixture()
    fx[fx$observation_id %in% seq_df$asv_id, , drop = FALSE]
  }

  cache_dir_path <- withr::local_tempdir()
  local_mocked_bindings(
    .fetch_reference_accession_records = mock_fetch,
    blast_sequences = mock_blast,
    .resolve_taxonomy_by_acc = mock_tax,
    .package = "TaxaMatch"
  )

  out <- suppressWarnings(suppressMessages(evaluate_reference_accessions(
    c("ACC001", "ACC_TRIP", "ACC_NEVER"), cache_dir = cache_dir_path,
    verbose = FALSE, chunk_size = 1L
  )))

  expect_false("ACC_NEVER" %in% fetch_log)
  expect_false("ACC_NEVER" %in% blast_log)

  acc1 <- out[out$accession == "ACC001", ]
  expect_equal(acc1$hierarchy_flag, "congruent")
  trip <- out[out$accession == "ACC_TRIP", ]
  expect_true(is.na(trip$hierarchy_flag))
  never <- out[out$accession == "ACC_NEVER", ]
  expect_true(is.na(never$hierarchy_flag))

  summary <- attr(out, "run_summary")
  expect_true(summary$circuit_breaker_tripped)
  expect_equal(summary$n_evaluated_this_call, 1L)
  expect_equal(summary$n_pending, 2L)

  # ACC001's real verdict from the completed first chunk must have survived
  # to disk even though the call as a whole stopped early on chunk 2.
  reloaded <- TaxaMatch:::.load_reference_accession_cache(cache_dir_path)
  expect_true("ACC001" %in% reloaded$accession)
  expect_false("ACC_TRIP" %in% reloaded$accession)
})

test_that("evaluate_reference_accessions() run_summary reports 100% complete and no trip on an ordinary successful call", {
  .mock_all({
    out <- evaluate_reference_accessions(
      c("ACC001", "ACC002"), cache_dir = NULL, verbose = FALSE
    )
  })
  summary <- attr(out, "run_summary")
  expect_false(summary$circuit_breaker_tripped)
  expect_equal(summary$pct_complete, 100)
  expect_equal(summary$n_pending, 0L)
  expect_true(is.na(summary$recommended_pause_minutes))
})

# ------------------------------------------------------------------------------
# Hybrid-labeled accessions -- maternal parent species proxy (2026-08-10)
# ------------------------------------------------------------------------------
# Reproduces the real GreatLakes case directly: NCBI's own taxonomy for a
# hybrid-cross-labeled accession is genuinely incomplete (family/genus/
# species all NA, lineage stops at an "unclassified ..." rank) -- confirmed
# live against real records, see this function's own @section Hybrid-labeled
# accessions. Cross-package mock (TaxaTools::verify_taxon_names) needed here
# specifically because the maternal-proxy path is the one place this
# function reaches outside its own NCBI-taxonomy-DB mechanism -- matches
# this file's own documented earlier precedent (see the top-of-file note).

test_that("evaluate_reference_accessions() resolves a hybrid-labeled accession via its maternal parent species", {
  hybrid_records <- data.frame(
    accession = c("ACC_HYBRID", "HIT_H1", "HIT_H2", "HIT_H3"),
    sequence = rep("ACGTACGTACGTACGT", 4L),
    organism = c("Ctenopharyngodon idella x Megalobrama amblycephala",
                rep(NA_character_, 3L)),
    create_date = c("2020/01/10", "2021/06/01", "2019/03/15", "2018/11/20"),
    stringsAsFactors = FALSE
  )
  mock_fetch_hybrid <- function(accessions, want_sequence = TRUE, ncbi_api_key = NULL,
                                verbose = TRUE) {
    out <- hybrid_records[hybrid_records$accession %in% accessions, , drop = FALSE]
    if (!want_sequence) out$sequence <- NA_character_
    rownames(out) <- NULL
    out
  }

  # NCBI's own taxonomy for the hybrid accession itself -- genuinely
  # truncated, exactly as confirmed live: order populated, nothing finer.
  mock_resolve_taxonomy_hybrid <- function(accessions, ncbi_api_key = NULL, verbose = TRUE) {
    fx <- data.frame(
      accession = "ACC_HYBRID", kingdom = "Metazoa", phylum = "Chordata",
      class = "Actinopteri", order = "Cypriniformes",
      family = NA_character_, genus = NA_character_, species = NA_character_,
      stringsAsFactors = FALSE
    )
    fx[fx$accession %in% accessions, , drop = FALSE]
  }

  # Independent BLAST hits, all genuinely agreeing with the MATERNAL
  # PARENT's real lineage (Xenocyprididae / Ctenopharyngodon) -- never
  # agreeing with the hybrid's own (nonexistent) family/genus, since no
  # such taxon exists to agree with in the first place.
  mock_blast_hybrid <- function(seq_df, ...) {
    data.frame(
      observation_id = "ACC_HYBRID", accession = c("HIT_H1", "HIT_H2", "HIT_H3"),
      score = c(99, 98, 97), query_coverage = 95,
      kingdom = "Metazoa", phylum = "Chordata", class = "Actinopteri",
      order = "Cypriniformes", family = "Xenocyprididae",
      genus = "Ctenopharyngodon", species = "Ctenopharyngodon idella",
      stringsAsFactors = FALSE
    )
  }

  # TaxaTools::verify_taxon_names(backbone_id = 4L) for the maternal proxy
  # name -- shape matches the real live response (classification_path/
  # classification_ranks pipe-delimited, verified 2026-08-10).
  mock_verify_ncbi <- function(name_list, backbone_id, ...) {
    tibble::tibble(
      user_supplied_name = "Ctenopharyngodon idella",
      matched_name = "Ctenopharyngodon idella",
      matched_rank = "species",
      classification_path =
        "Metazoa|Chordata|Actinopteri|Cypriniformes|Xenocyprididae|Ctenopharyngodon|Ctenopharyngodon idella",
      classification_ranks = "kingdom|phylum|class|order|family|genus|species"
    )
  }

  local_mocked_bindings(
    .fetch_reference_accession_records = mock_fetch_hybrid, .package = "TaxaMatch"
  )
  local_mocked_bindings(blast_sequences = mock_blast_hybrid, .package = "TaxaMatch")
  local_mocked_bindings(
    .resolve_taxonomy_by_acc = mock_resolve_taxonomy_hybrid, .package = "TaxaMatch"
  )
  local_mocked_bindings(verify_taxon_names = mock_verify_ncbi, .package = "TaxaTools")

  out <- evaluate_reference_accessions("ACC_HYBRID", cache_dir = NULL, verbose = FALSE)

  expect_equal(out$taxonomy_resolution_source, "hybrid_maternal_proxy")
  # Without the proxy, this would read "incongruent" (no family/genus on the
  # query side to ever agree with) -- the real, confirmed false-positive
  # mode this fix closes.
  expect_equal(out$hierarchy_flag, "congruent")
  expect_equal(out$finest_common_rank, "genus")
})

test_that("evaluate_reference_accessions() resolves a real breeding/ploidy-modifier-prefixed hybrid label (2026-08-11)", {
  # Regression test: found live against the real GreatLakes population --
  # "androgenetic"/"autodiploid"/"autotetraploid" all precede the maternal
  # parent's real name with a lowercase modifier word, which the ORIGINAL
  # hybrid-proxy fix (2026-08-10) could not parse (clean_taxon_names()
  # correctly refuses a non-capital-first string), silently falling back
  # to "hybrid_unresolved" for all 3 real accessions. Fixed by stripping a
  # single leading lowercase word before clean_taxon_names() runs -- the
  # maternal-inheritance argument still holds (these are nuclear-genome
  # manipulation techniques, not a different maternal cytoplasm source).
  hybrid_records <- data.frame(
    accession = c("ACC_ANDROGENETIC", "HIT_1", "HIT_2", "HIT_3"),
    sequence = rep("ACGTACGTACGTACGT", 4L),
    organism = c("androgenetic Carassius auratus red var. x Megalobrama amblycephala",
                rep(NA_character_, 3L)),
    create_date = c("2020/01/10", "2021/06/01", "2019/03/15", "2018/11/20"),
    stringsAsFactors = FALSE
  )
  mock_fetch <- function(accessions, want_sequence = TRUE, ncbi_api_key = NULL, verbose = TRUE) {
    out <- hybrid_records[hybrid_records$accession %in% accessions, , drop = FALSE]
    if (!want_sequence) out$sequence <- rep(NA_character_, nrow(out))
    rownames(out) <- NULL
    out
  }
  mock_resolve_taxonomy <- function(accessions, ncbi_api_key = NULL, verbose = TRUE) {
    fx <- data.frame(
      accession = "ACC_ANDROGENETIC", kingdom = "Metazoa", phylum = "Chordata",
      class = "Actinopteri", order = "Cypriniformes",
      family = NA_character_, genus = NA_character_, species = NA_character_,
      stringsAsFactors = FALSE
    )
    fx[fx$accession %in% accessions, , drop = FALSE]
  }
  mock_blast <- function(seq_df, ...) {
    data.frame(
      observation_id = "ACC_ANDROGENETIC", accession = c("HIT_1", "HIT_2", "HIT_3"),
      score = c(99, 98, 97), query_coverage = 95,
      kingdom = "Metazoa", phylum = "Chordata",
      class = "Actinopteri", order = "Cypriniformes", family = "Cyprinidae",
      genus = "Carassius", species = "Carassius auratus",
      stringsAsFactors = FALSE
    )
  }
  mock_verify_ncbi <- function(name_list, backbone_id, ...) {
    tibble::tibble(
      user_supplied_name = "Carassius auratus",
      matched_name = "Carassius auratus", matched_rank = "species",
      classification_path = "Metazoa|Chordata|Actinopteri|Cypriniformes|Cyprinidae|Carassius|Carassius auratus",
      classification_ranks = "kingdom|phylum|class|order|family|genus|species"
    )
  }

  local_mocked_bindings(
    .fetch_reference_accession_records = mock_fetch, .package = "TaxaMatch"
  )
  local_mocked_bindings(blast_sequences = mock_blast, .package = "TaxaMatch")
  local_mocked_bindings(
    .resolve_taxonomy_by_acc = mock_resolve_taxonomy, .package = "TaxaMatch"
  )
  local_mocked_bindings(verify_taxon_names = mock_verify_ncbi, .package = "TaxaTools")

  out <- evaluate_reference_accessions("ACC_ANDROGENETIC", cache_dir = NULL, verbose = FALSE)
  expect_equal(out$taxonomy_resolution_source, "hybrid_maternal_proxy")
  expect_equal(out$hierarchy_flag, "congruent")
})

test_that("evaluate_reference_accessions() falls back to 'hybrid_unresolved' when no parent name can be extracted even after stripping one modifier word", {
  hybrid_records <- data.frame(
    accession = "ACC_HYBRID_UNPARSEABLE",
    sequence = "ACGTACGTACGTACGT",
    # TWO leading lowercase words -- stripping only one (the deliberate,
    # safety-motivated choice, see the production code's own comment on
    # why a repeated strip is NOT used) still leaves a lowercase start, so
    # no proxy name can be extracted. Also a regression guard against a
    # real failure mode found before shipping: a repeated-word strip would
    # have consumed "hybrid" too, silently misattributing "Megalobrama
    # amblycephala" (the SECOND-listed taxon, and an entirely different
    # unrelated genus) as the maternal parent.
    organism = "unidentified hybrid x Megalobrama amblycephala",
    create_date = "2020/01/10",
    stringsAsFactors = FALSE
  )
  mock_fetch <- function(accessions, want_sequence = TRUE, ncbi_api_key = NULL, verbose = TRUE) {
    out <- hybrid_records[hybrid_records$accession %in% accessions, , drop = FALSE]
    if (!want_sequence) out$sequence <- NA_character_
    rownames(out) <- NULL
    out
  }
  mock_resolve_taxonomy <- function(accessions, ncbi_api_key = NULL, verbose = TRUE) {
    fx <- data.frame(
      accession = "ACC_HYBRID_UNPARSEABLE", kingdom = "Metazoa", phylum = "Chordata",
      class = "Actinopteri", order = "Cypriniformes",
      family = NA_character_, genus = NA_character_, species = NA_character_,
      stringsAsFactors = FALSE
    )
    fx[fx$accession %in% accessions, , drop = FALSE]
  }
  mock_blast_empty <- function(seq_df, ...) {
    data.frame(observation_id = character(0), accession = character(0),
              score = numeric(0), stringsAsFactors = FALSE)
  }

  local_mocked_bindings(
    .fetch_reference_accession_records = mock_fetch, .package = "TaxaMatch"
  )
  local_mocked_bindings(blast_sequences = mock_blast_empty, .package = "TaxaMatch")
  local_mocked_bindings(
    .resolve_taxonomy_by_acc = mock_resolve_taxonomy, .package = "TaxaMatch"
  )

  out <- evaluate_reference_accessions("ACC_HYBRID_UNPARSEABLE", cache_dir = NULL, verbose = FALSE)
  expect_equal(out$taxonomy_resolution_source, "hybrid_unresolved")
})

test_that("evaluate_reference_accessions() does not apply the hybrid proxy to a non-hybrid accession with an incomplete lineage", {
  # Same symptom (family.x is NA) but NO hybrid marker in the name -- the
  # maternal-parent substitution must never fire here, since there is no
  # hybrid biology to justify it.
  odd_records <- data.frame(
    accession = "ACC_UNCLASSIFIED", sequence = "ACGTACGTACGTACGT",
    organism = "Unclassified fish sp.", create_date = "2020/01/10",
    stringsAsFactors = FALSE
  )
  mock_fetch <- function(accessions, want_sequence = TRUE, ncbi_api_key = NULL, verbose = TRUE) {
    out <- odd_records[odd_records$accession %in% accessions, , drop = FALSE]
    if (!want_sequence) out$sequence <- NA_character_
    rownames(out) <- NULL
    out
  }
  mock_resolve_taxonomy <- function(accessions, ncbi_api_key = NULL, verbose = TRUE) {
    fx <- data.frame(
      accession = "ACC_UNCLASSIFIED", kingdom = "Metazoa", phylum = "Chordata",
      class = "Actinopteri", order = "Perciformes",
      family = NA_character_, genus = NA_character_, species = NA_character_,
      stringsAsFactors = FALSE
    )
    fx[fx$accession %in% accessions, , drop = FALSE]
  }
  mock_blast_empty <- function(seq_df, ...) {
    data.frame(observation_id = character(0), accession = character(0),
              score = numeric(0), stringsAsFactors = FALSE)
  }
  verify_called <- FALSE
  mock_verify_should_not_fire <- function(name_list, backbone_id, ...) {
    verify_called <<- TRUE
    stop("should not be called")
  }

  local_mocked_bindings(
    .fetch_reference_accession_records = mock_fetch, .package = "TaxaMatch"
  )
  local_mocked_bindings(blast_sequences = mock_blast_empty, .package = "TaxaMatch")
  local_mocked_bindings(
    .resolve_taxonomy_by_acc = mock_resolve_taxonomy, .package = "TaxaMatch"
  )
  local_mocked_bindings(verify_taxon_names = mock_verify_should_not_fire, .package = "TaxaTools")

  out <- evaluate_reference_accessions("ACC_UNCLASSIFIED", cache_dir = NULL, verbose = FALSE)
  expect_equal(out$taxonomy_resolution_source, "direct")
  expect_false(verify_called)
})

# ------------------------------------------------------------------------------
# Species-resolved comparison partners -- end to end (2026-08-13)
# ------------------------------------------------------------------------------

test_that("evaluate_reference_accessions() reads 'insufficient_independent_evidence' (not 'incongruent') for an isolated species whose only disagreeing hit is non-species-resolved", {
  # Reproduces the real GreatLakes Stereolepis doederleini case end to end:
  # a genuinely isolated species (only 1 real conspecific in all of NCBI)
  # whose sole other independent hit is itself never resolved to species.
  # Before this fix: that non-species-resolved hit counted as a real
  # "disagreeing" vote, outnumbering the 1 real agreeing vote ->
  # "incongruent". After: it's excluded, leaving 1 real vote -- correctly
  # below min_independent_partners (default 3), so the HONEST answer is
  # "insufficient_independent_evidence", not a false "incongruent" or an
  # overclaiming "congruent".
  records <- data.frame(
    accession = c("ACC_STEREO", "HIT_CONSPECIFIC", "HIT_UNRESOLVED"),
    sequence = rep("ACGTACGTACGTACGT", 3L),
    organism = c("Stereolepis doederleini", rep(NA_character_, 2L)),
    create_date = c("2022/01/18", "2021/07/19", "2015/11/01"),
    stringsAsFactors = FALSE
  )
  mock_fetch <- function(accessions, want_sequence = TRUE, ncbi_api_key = NULL, verbose = TRUE) {
    out <- records[records$accession %in% accessions, , drop = FALSE]
    if (!want_sequence) out$sequence <- rep(NA_character_, nrow(out))
    rownames(out) <- NULL
    out
  }
  mock_resolve_taxonomy <- function(accessions, ncbi_api_key = NULL, verbose = TRUE) {
    fx <- data.frame(
      accession = "ACC_STEREO", kingdom = "Metazoa", phylum = "Chordata",
      class = "Actinopteri", order = "Acropomatiformes", family = "Polyprionidae",
      genus = "Stereolepis", species = "Stereolepis doederleini",
      stringsAsFactors = FALSE
    )
    fx[fx$accession %in% accessions, , drop = FALSE]
  }
  mock_blast <- function(seq_df, ...) {
    data.frame(
      observation_id = "ACC_STEREO", accession = c("HIT_CONSPECIFIC", "HIT_UNRESOLVED"),
      score = c(99.99, 99.63), query_coverage = 95,
      kingdom = "Metazoa", phylum = "Chordata", class = "Actinopteri",
      order = c("Acropomatiformes", "Perciformes"),
      family = c("Polyprionidae", "Serranidae"),
      genus = c("Stereolepis", NA_character_),
      species = c("Stereolepis doederleini", "Serranidae sp. JL-2015"),
      stringsAsFactors = FALSE
    )
  }

  local_mocked_bindings(.fetch_reference_accession_records = mock_fetch, .package = "TaxaMatch")
  local_mocked_bindings(blast_sequences = mock_blast, .package = "TaxaMatch")
  local_mocked_bindings(.resolve_taxonomy_by_acc = mock_resolve_taxonomy, .package = "TaxaMatch")

  out <- evaluate_reference_accessions("ACC_STEREO", cache_dir = NULL, verbose = FALSE)
  expect_equal(out$hierarchy_flag, "insufficient_independent_evidence")
  expect_equal(out$n_independent_top_matches, 1L)
})

# ------------------------------------------------------------------------------
# listed_taxon_is_species (2026-08-11)
# ------------------------------------------------------------------------------

test_that("evaluate_reference_accessions() flags a family-level-only listed taxon as not species-resolved", {
  # Real GreatLakes case: "Serranidae sp. JL-2015" -- a family name used in
  # place of a genus, plus an informal specimen code. Not a mislabel, not a
  # hybrid -- just never identified to species. hierarchy_flag can read
  # "congruent" here (nothing contradicts the label); listed_taxon_is_species
  # is the SEPARATE, orthogonal signal that catches this.
  records <- data.frame(
    accession = c("ACC_FAM", "HIT_A", "HIT_B", "HIT_C"),
    sequence = rep("ACGTACGTACGTACGT", 4L),
    organism = c("Serranidae sp. JL-2015", rep(NA_character_, 3L)),
    create_date = c("2020/01/10", "2021/06/01", "2019/03/15", "2018/11/20"),
    stringsAsFactors = FALSE
  )
  mock_fetch <- function(accessions, want_sequence = TRUE, ncbi_api_key = NULL, verbose = TRUE) {
    out <- records[records$accession %in% accessions, , drop = FALSE]
    if (!want_sequence) out$sequence <- rep(NA_character_, nrow(out))
    rownames(out) <- NULL
    out
  }
  mock_resolve_taxonomy <- function(accessions, ncbi_api_key = NULL, verbose = TRUE) {
    fx <- data.frame(
      accession = "ACC_FAM", kingdom = "Metazoa", phylum = "Chordata",
      class = "Actinopteri", order = "Perciformes", family = "Serranidae",
      genus = NA_character_, species = NA_character_,
      stringsAsFactors = FALSE
    )
    fx[fx$accession %in% accessions, , drop = FALSE]
  }
  mock_blast <- function(seq_df, ...) {
    # Real, clean species binomials -- these ARE meaningful, species-
    # resolved corroborating evidence (this test is about listed_taxon_
    # is_species being a signal orthogonal to hierarchy_flag, not about
    # the require_species_resolved_partner filter, which has its own
    # dedicated tests above).
    data.frame(
      observation_id = "ACC_FAM", accession = c("HIT_A", "HIT_B", "HIT_C"),
      score = c(99, 98, 97), query_coverage = 95,
      kingdom = "Metazoa", phylum = "Chordata", class = "Actinopteri",
      order = "Perciformes", family = "Serranidae", genus = "Epinephelus",
      species = "Epinephelus coioides",
      stringsAsFactors = FALSE
    )
  }

  local_mocked_bindings(.fetch_reference_accession_records = mock_fetch, .package = "TaxaMatch")
  local_mocked_bindings(blast_sequences = mock_blast, .package = "TaxaMatch")
  local_mocked_bindings(.resolve_taxonomy_by_acc = mock_resolve_taxonomy, .package = "TaxaMatch")

  out <- evaluate_reference_accessions("ACC_FAM", cache_dir = NULL, verbose = FALSE)
  expect_false(out$listed_taxon_is_species)
  expect_equal(out$hierarchy_flag, "congruent")  # nothing contradicts the label
})

test_that("evaluate_reference_accessions() reads listed_taxon_is_species = TRUE for a genuine species binomial", {
  .mock_all({
    out <- evaluate_reference_accessions("ACC001", cache_dir = NULL, verbose = FALSE)
  })
  expect_true(out$listed_taxon_is_species)
})

test_that("evaluate_reference_accessions() reads listed_taxon_is_species = NA (not FALSE) for a fetch failure", {
  .mock_all({
    suppressWarnings(
      out <- evaluate_reference_accessions("GHOST999", cache_dir = NULL, verbose = FALSE)
    )
  })
  expect_true(is.na(out$listed_taxon_is_species))
})

test_that("evaluate_reference_accessions() validates inputs", {
  expect_error(evaluate_reference_accessions(123), "character vector")
  expect_error(evaluate_reference_accessions(character(0)), "non-empty")
  expect_error(evaluate_reference_accessions(c(NA, "")), "No valid")
})

test_that("evaluate_reference_accessions() reports accessions NCBI cannot find, without crashing", {
  .mock_all({
    expect_warning(
      out <- evaluate_reference_accessions(c("ACC001", "GHOST999"), cache_dir = NULL,
                                           verbose = FALSE),
      "could not be evaluated"
    )
  })
  expect_true("GHOST999" %in% out$accession)
  expect_true(is.na(out$hierarchy_flag[out$accession == "GHOST999"]))
  expect_false(out$cache_hit[out$accession == "GHOST999"])
})

test_that("evaluate_reference_accessions() caches congruent/incongruent verdicts across calls", {
  skip_if_not_installed("withr")
  cache_dir <- withr::local_tempdir()

  fetch_calls <- 0L
  counting_fetch <- function(...) { fetch_calls <<- fetch_calls + 1L; .mock_fetch_records(...) }

  local_mocked_bindings(
    .fetch_reference_accession_records = counting_fetch, .package = "TaxaMatch"
  )
  local_mocked_bindings(blast_sequences = .mock_blast_sequences, .package = "TaxaMatch")
  local_mocked_bindings(.resolve_taxonomy_by_acc = .mock_resolve_taxonomy_by_acc, .package = "TaxaMatch")

  out1 <- evaluate_reference_accessions(c("ACC001", "ACC002"), cache_dir = cache_dir,
                                        verbose = FALSE)
  expect_true(fetch_calls > 0L)
  calls_after_first <- fetch_calls

  out2 <- evaluate_reference_accessions(c("ACC001", "ACC002"), cache_dir = cache_dir,
                                        verbose = FALSE)
  expect_equal(fetch_calls, calls_after_first)  # no new fetches -- pure cache hit
  expect_true(all(out2$cache_hit))
  expect_equal(out1$hierarchy_flag, out2$hierarchy_flag)
})

test_that("evaluate_reference_accessions() gracefully discards an old-schema cache file instead of erroring", {
  # Real bug found live (2026-08-07): a cache file written before the
  # identity-diagnostics columns existed has fewer columns than the current
  # out_cols list. params_key alone invalidates stale ROWS, but can't
  # rescue a file whose COLUMN SCHEMA doesn't match -- cache_hit_rows[,
  # out_cols] errored ("undefined columns selected") even with zero
  # matching rows, because the missing columns don't exist at all.
  skip_if_not_installed("withr")
  cache_dir <- withr::local_tempdir()
  dir.create(cache_dir, showWarnings = FALSE)
  old_schema_cache <- data.frame(
    accession = "ACC001", listed_taxon = "Menidia beryllina",
    n_independent_top_matches = 3L, n_top_matches_available = 4L,
    frac_independent_below_min_congruent_rank = 0.375,
    finest_common_rank = "species", hierarchy_flag = "congruent",
    evaluated_at = Sys.time(), params_key = "stale|schema|from|an|old|version",
    stringsAsFactors = FALSE
  )
  saveRDS(old_schema_cache, file.path(cache_dir, "reference_accession_cache.rds"))

  .mock_all({
    expect_warning(
      out <- evaluate_reference_accessions("ACC001", cache_dir = cache_dir, verbose = FALSE),
      "predates this package version"
    )
  })
  expect_equal(out$hierarchy_flag, "congruent")
  expect_false(out$cache_hit)  # recomputed, not read from the discarded old-schema file
  expect_true("best_agreeing_pident" %in% names(out))
})

test_that("evaluate_reference_accessions() re-evaluates when parameters change", {
  skip_if_not_installed("withr")
  cache_dir <- withr::local_tempdir()

  fetch_calls <- 0L
  counting_fetch <- function(...) { fetch_calls <<- fetch_calls + 1L; .mock_fetch_records(...) }

  local_mocked_bindings(
    .fetch_reference_accession_records = counting_fetch, .package = "TaxaMatch"
  )
  local_mocked_bindings(blast_sequences = .mock_blast_sequences, .package = "TaxaMatch")
  local_mocked_bindings(.resolve_taxonomy_by_acc = .mock_resolve_taxonomy_by_acc, .package = "TaxaMatch")

  evaluate_reference_accessions("ACC001", cache_dir = cache_dir, verbose = FALSE)
  calls_after_first <- fetch_calls

  evaluate_reference_accessions("ACC001", cache_dir = cache_dir, verbose = FALSE,
                                min_congruent_rank = "family", top_n = 3L)
  expect_true(fetch_calls > calls_after_first)
})

test_that("evaluate_reference_accessions() retries insufficient_independent_evidence past its TTL", {
  skip_if_not_installed("withr")
  cache_dir <- withr::local_tempdir()

  fetch_calls <- 0L
  counting_fetch <- function(...) { fetch_calls <<- fetch_calls + 1L; .mock_fetch_records(...) }

  local_mocked_bindings(
    .fetch_reference_accession_records = counting_fetch, .package = "TaxaMatch"
  )
  local_mocked_bindings(blast_sequences = .mock_blast_sequences, .package = "TaxaMatch")
  local_mocked_bindings(.resolve_taxonomy_by_acc = .mock_resolve_taxonomy_by_acc, .package = "TaxaMatch")

  evaluate_reference_accessions("ACC003", cache_dir = cache_dir, verbose = FALSE)
  calls_after_first <- fetch_calls

  # Immediately re-calling stays a cache hit (well within the default 180-day TTL).
  evaluate_reference_accessions("ACC003", cache_dir = cache_dir, verbose = FALSE)
  expect_equal(fetch_calls, calls_after_first)

  # Backdate the cached evaluated_at past a short TTL and confirm it's retried.
  cache_path <- file.path(cache_dir, "reference_accession_cache.rds")
  cached <- readRDS(cache_path)
  cached$evaluated_at <- cached$evaluated_at - 1000
  saveRDS(cached, cache_path)

  evaluate_reference_accessions("ACC003", cache_dir = cache_dir, verbose = FALSE,
                                insufficient_evidence_ttl_days = 0.001)
  expect_true(fetch_calls > calls_after_first)
})

# ------------------------------------------------------------------------------
# Mechanism 2: max_query_len hard submission cap -- "not_evaluated_oversized"
# (ecosystem_docs/REENTRY_PROMPT_eval_ref_accessions_long_sequence_robustness.md)
# ------------------------------------------------------------------------------

test_that("evaluate_reference_accessions(max_query_len=) defers an unrescuable over-length query as not_evaluated_oversized, never BLASTed", {
  long_seq <- strrep("ACGT", 50L)  # 200bp, no barcode_term supplied at all
  mock_fetch <- function(accessions, want_sequence = TRUE, ncbi_api_key = NULL, verbose = TRUE) {
    data.frame(accession = "ACC_LONG", organism = "Longus fishus",
              create_date = "2020/01/01", sequence = long_seq, stringsAsFactors = FALSE)
  }
  blast_called <- FALSE
  mock_blast <- function(seq_df, ...) { blast_called <<- TRUE; stop("must never be reached") }
  local_mocked_bindings(
    .fetch_reference_accession_records = mock_fetch, blast_sequences = mock_blast,
    .package = "TaxaMatch"
  )

  out <- suppressMessages(evaluate_reference_accessions(
    "ACC_LONG", cache_dir = NULL, verbose = FALSE, max_query_len = 50L
  ))

  expect_false(blast_called)
  expect_equal(out$hierarchy_flag, "not_evaluated_oversized")
  expect_equal(out$listed_taxon, "Longus fishus")
  expect_true(is.na(out$best_hit_pident))
  expect_true(is.na(out$n_independent_top_matches))
  expect_true(is.na(out$taxonomy_resolution_source))
  expect_false(out$cache_hit)
})

test_that("evaluate_reference_accessions(max_query_len = Inf) disables the cap entirely (pre-2026-09-01 behavior)", {
  long_seq <- strrep("ACGT", 50L)
  mock_fetch <- function(accessions, want_sequence = TRUE, ncbi_api_key = NULL, verbose = TRUE) {
    data.frame(accession = "ACC_LONG", organism = "Longus fishus",
              create_date = "2020/01/01", sequence = long_seq, stringsAsFactors = FALSE)
  }
  seen_sequence <- NULL
  mock_blast <- function(seq_df, ...) {
    seen_sequence <<- seq_df$sequence
    data.frame(observation_id = character(0), accession = character(0), score = numeric(0),
              stringsAsFactors = FALSE)
  }
  mock_tax <- function(accessions, ncbi_api_key = NULL, verbose = TRUE) {
    data.frame(accession = character(0), stringsAsFactors = FALSE)
  }
  local_mocked_bindings(
    .fetch_reference_accession_records = mock_fetch, blast_sequences = mock_blast,
    .resolve_taxonomy_by_acc = mock_tax, .package = "TaxaMatch"
  )

  out <- evaluate_reference_accessions(
    "ACC_LONG", cache_dir = NULL, verbose = FALSE, max_query_len = Inf
  )
  expect_equal(seen_sequence, long_seq)
  expect_equal(out$hierarchy_flag, "insufficient_independent_evidence")
})

test_that("evaluate_reference_accessions() a not_evaluated_oversized row survives a cache round-trip with TTL semantics like insufficient_independent_evidence", {
  skip_if_not_installed("withr")
  cache_dir <- withr::local_tempdir()
  long_seq <- strrep("ACGT", 50L)
  fetch_calls <- 0L
  mock_fetch <- function(accessions, want_sequence = TRUE, ncbi_api_key = NULL, verbose = TRUE) {
    fetch_calls <<- fetch_calls + 1L
    data.frame(accession = "ACC_LONG", organism = "Longus fishus",
              create_date = "2020/01/01", sequence = long_seq, stringsAsFactors = FALSE)
  }
  local_mocked_bindings(.fetch_reference_accession_records = mock_fetch, .package = "TaxaMatch")

  out1 <- suppressMessages(evaluate_reference_accessions(
    "ACC_LONG", cache_dir = cache_dir, verbose = FALSE, max_query_len = 50L
  ))
  expect_equal(out1$hierarchy_flag, "not_evaluated_oversized")
  expect_false(out1$cache_hit)
  calls_after_first <- fetch_calls

  # Immediately re-calling stays a cache hit (well within the default 180-day TTL).
  out2 <- evaluate_reference_accessions(
    "ACC_LONG", cache_dir = cache_dir, verbose = FALSE, max_query_len = 50L
  )
  expect_equal(fetch_calls, calls_after_first)
  expect_true(out2$cache_hit)
  expect_equal(out2$hierarchy_flag, "not_evaluated_oversized")

  # Backdate past a short TTL -- retried, same as insufficient_independent_evidence.
  cache_path <- file.path(cache_dir, "reference_accession_cache.rds")
  cached <- readRDS(cache_path)
  cached$evaluated_at <- cached$evaluated_at - 1000
  saveRDS(cached, cache_path)

  suppressMessages(evaluate_reference_accessions(
    "ACC_LONG", cache_dir = cache_dir, verbose = FALSE, max_query_len = 50L,
    insufficient_evidence_ttl_days = 0.001
  ))
  expect_true(fetch_calls > calls_after_first)
})

test_that("flag_incongruent_references()/remove_incongruent_references() never treat not_evaluated_oversized as a flag", {
  match_df <- data.frame(accession = c("A1", "A2"), stringsAsFactors = FALSE)
  full_eval <- data.frame(
    accession = c("A1", "A2"),
    hierarchy_flag = c("not_evaluated_oversized", "congruent"),
    finest_common_rank = NA_character_,
    frac_independent_below_min_congruent_rank = NA_real_,
    n_independent_top_matches = NA_integer_, n_top_matches_available = NA_integer_,
    best_hit_pident = NA_real_, best_agreeing_pident = NA_real_,
    best_disagreeing_pident = NA_real_,
    congruent_evidence_exists_anywhere = NA, congruent_evidence_best_pident = NA_real_,
    stringsAsFactors = FALSE
  )

  flagged <- flag_incongruent_references(match_df, full_eval)
  expect_equal(flagged$hierarchy_flag, c("not_evaluated_oversized", "congruent"))

  # Never removed by default...
  removed_default <- remove_incongruent_references(match_df, full_eval)
  expect_equal(nrow(removed_default), 2L)
  # ...and never removed even with remove_insufficient_evidence = TRUE (that
  # flag only ever adds "insufficient_independent_evidence", never the new
  # oversized verdict -- see remove_incongruent_references()'s own roxygen).
  removed_broad <- remove_incongruent_references(
    match_df, full_eval, remove_insufficient_evidence = TRUE
  )
  expect_equal(nrow(removed_broad), 2L)
})

# ------------------------------------------------------------------------------
# Mechanism 4: prioritize_uncached / retry_insufficient
# ------------------------------------------------------------------------------

.priority_records <- function(accessions) {
  data.frame(
    accession = accessions,
    sequence = rep("ACGTACGTACGTACGT", length(accessions)),
    organism = rep("Priorus testus", length(accessions)),
    create_date = rep("2020/01/01", length(accessions)),
    stringsAsFactors = FALSE
  )
}
.priority_mock_fetch <- function(accessions, want_sequence = TRUE, ncbi_api_key = NULL,
                                 verbose = TRUE) .priority_records(accessions)
.priority_mock_blast <- function(seq_df, ...) {
  data.frame(observation_id = character(0), accession = character(0), score = numeric(0),
            stringsAsFactors = FALSE)
}
.priority_mock_tax <- function(accessions, ncbi_api_key = NULL, verbose = TRUE) {
  data.frame(accession = character(0), stringsAsFactors = FALSE)
}

test_that("evaluate_reference_accessions(prioritize_uncached = TRUE, default) evaluates never-cached accessions before an expired retry", {
  skip_if_not_installed("withr")
  cache_dir <- withr::local_tempdir()

  local_mocked_bindings(
    .fetch_reference_accession_records = .priority_mock_fetch,
    blast_sequences = .priority_mock_blast, .resolve_taxonomy_by_acc = .priority_mock_tax,
    .package = "TaxaMatch"
  )
  # Seed ACC_OLD as a genuine "insufficient_independent_evidence" verdict
  # (zero BLAST hits, matches .priority_mock_blast()).
  evaluate_reference_accessions("ACC_OLD", cache_dir = cache_dir, verbose = FALSE)

  # Backdate it past a short TTL.
  cache_path <- file.path(cache_dir, "reference_accession_cache.rds")
  cached <- readRDS(cache_path)
  cached$evaluated_at <- cached$evaluated_at - 1e6
  saveRDS(cached, cache_path)

  fetch_order <- character(0)
  order_fetch <- function(accessions, want_sequence = TRUE, ncbi_api_key = NULL, verbose = TRUE) {
    fetch_order <<- c(fetch_order, accessions)
    .priority_records(accessions)
  }
  local_mocked_bindings(
    .fetch_reference_accession_records = order_fetch,
    blast_sequences = .priority_mock_blast, .resolve_taxonomy_by_acc = .priority_mock_tax,
    .package = "TaxaMatch"
  )

  suppressMessages(evaluate_reference_accessions(
    c("ACC_OLD", "ACC_NEW"), cache_dir = cache_dir, verbose = FALSE,
    chunk_size = 1L, insufficient_evidence_ttl_days = 0.0001
  ))

  # ACC_NEW (never cached) is evaluated before ACC_OLD (an expired retry),
  # even though the caller supplied ACC_OLD first.
  expect_equal(fetch_order, c("ACC_NEW", "ACC_OLD"))
})

test_that("evaluate_reference_accessions(prioritize_uncached = FALSE) preserves the caller's own supplied order", {
  skip_if_not_installed("withr")
  cache_dir <- withr::local_tempdir()

  local_mocked_bindings(
    .fetch_reference_accession_records = .priority_mock_fetch,
    blast_sequences = .priority_mock_blast, .resolve_taxonomy_by_acc = .priority_mock_tax,
    .package = "TaxaMatch"
  )
  evaluate_reference_accessions("ACC_OLD", cache_dir = cache_dir, verbose = FALSE)

  cache_path <- file.path(cache_dir, "reference_accession_cache.rds")
  cached <- readRDS(cache_path)
  cached$evaluated_at <- cached$evaluated_at - 1e6
  saveRDS(cached, cache_path)

  fetch_order <- character(0)
  order_fetch <- function(accessions, want_sequence = TRUE, ncbi_api_key = NULL, verbose = TRUE) {
    fetch_order <<- c(fetch_order, accessions)
    .priority_records(accessions)
  }
  local_mocked_bindings(
    .fetch_reference_accession_records = order_fetch,
    blast_sequences = .priority_mock_blast, .resolve_taxonomy_by_acc = .priority_mock_tax,
    .package = "TaxaMatch"
  )

  suppressMessages(evaluate_reference_accessions(
    c("ACC_OLD", "ACC_NEW"), cache_dir = cache_dir, verbose = FALSE,
    chunk_size = 1L, insufficient_evidence_ttl_days = 0.0001,
    prioritize_uncached = FALSE
  ))

  expect_equal(fetch_order, c("ACC_OLD", "ACC_NEW"))
})

test_that("evaluate_reference_accessions(retry_insufficient = FALSE) serves an expired insufficient row from cache without any new NCBI call", {
  skip_if_not_installed("withr")
  cache_dir <- withr::local_tempdir()

  local_mocked_bindings(
    .fetch_reference_accession_records = .priority_mock_fetch,
    blast_sequences = .priority_mock_blast, .resolve_taxonomy_by_acc = .priority_mock_tax,
    .package = "TaxaMatch"
  )
  evaluate_reference_accessions("ACC_OLD", cache_dir = cache_dir, verbose = FALSE)

  cache_path <- file.path(cache_dir, "reference_accession_cache.rds")
  cached <- readRDS(cache_path)
  cached$evaluated_at <- cached$evaluated_at - 1e6
  saveRDS(cached, cache_path)

  fetch_calls <- 0L
  counting_fetch <- function(accessions, ...) {
    fetch_calls <<- fetch_calls + 1L
    .priority_records(accessions)
  }
  local_mocked_bindings(
    .fetch_reference_accession_records = counting_fetch,
    blast_sequences = .priority_mock_blast, .resolve_taxonomy_by_acc = .priority_mock_tax,
    .package = "TaxaMatch"
  )

  out <- evaluate_reference_accessions(
    "ACC_OLD", cache_dir = cache_dir, verbose = FALSE,
    insufficient_evidence_ttl_days = 0.0001, retry_insufficient = FALSE
  )

  expect_equal(fetch_calls, 0L)
  expect_true(out$cache_hit)
  expect_equal(out$hierarchy_flag, "insufficient_independent_evidence")
})

test_that("evaluate_reference_accessions(retry_insufficient = FALSE) still evaluates a genuinely never-cached accession", {
  skip_if_not_installed("withr")
  cache_dir <- withr::local_tempdir()
  local_mocked_bindings(
    .fetch_reference_accession_records = .priority_mock_fetch,
    blast_sequences = .priority_mock_blast, .resolve_taxonomy_by_acc = .priority_mock_tax,
    .package = "TaxaMatch"
  )
  out <- evaluate_reference_accessions(
    "ACC_BRAND_NEW", cache_dir = cache_dir, verbose = FALSE, retry_insufficient = FALSE
  )
  expect_false(out$cache_hit)
  expect_equal(out$hierarchy_flag, "insufficient_independent_evidence")
})

test_that("evaluate_reference_accessions() cached rows are unaffected by changing max_query_len/max_batch_bp/prioritize_uncached/retry_insufficient (excluded from params_key)", {
  skip_if_not_installed("withr")
  cache_dir <- withr::local_tempdir()
  fetch_calls <- 0L
  counting_fetch <- function(...) { fetch_calls <<- fetch_calls + 1L; .mock_fetch_records(...) }
  local_mocked_bindings(
    .fetch_reference_accession_records = counting_fetch, blast_sequences = .mock_blast_sequences,
    .resolve_taxonomy_by_acc = .mock_resolve_taxonomy_by_acc, .package = "TaxaMatch"
  )
  evaluate_reference_accessions("ACC001", cache_dir = cache_dir, verbose = FALSE)
  calls_after_first <- fetch_calls

  out2 <- evaluate_reference_accessions(
    "ACC001", cache_dir = cache_dir, verbose = FALSE,
    max_query_len = 999999L, max_batch_bp = 5000L,
    prioritize_uncached = FALSE, retry_insufficient = FALSE
  )
  expect_equal(fetch_calls, calls_after_first)
  expect_true(out2$cache_hit)
  expect_equal(out2$hierarchy_flag, "congruent")
})

# ------------------------------------------------------------------------------
# flag_incongruent_references() / remove_incongruent_references()
# ------------------------------------------------------------------------------

.match_df_fixture <- function() {
  data.frame(
    observation_id = c("O1", "O1", "O2", "O3"),
    accession = c("ACC001", "ACC002.1", "ACC002", "ACC003"),
    stringsAsFactors = FALSE
  )
}

.evaluation_fixture <- function() {
  data.frame(
    accession = c("ACC001", "ACC002", "ACC003"),
    hierarchy_flag = c("congruent", "incongruent", "insufficient_independent_evidence"),
    stringsAsFactors = FALSE
  )
}

.full_evaluation_fixture <- function() {
  data.frame(
    accession = c("ACC001", "ACC002", "ACC003"),
    hierarchy_flag = c("congruent", "incongruent", "insufficient_independent_evidence"),
    finest_common_rank = c("species", "order", NA_character_),
    frac_independent_below_min_congruent_rank = c(0.083, 0.917, 0.5),
    n_independent_top_matches = c(5L, 5L, 0L),
    n_top_matches_available = c(19L, 19L, 0L),
    best_hit_pident = c(99.9, 95, NA_real_),
    best_agreeing_pident = c(99.9, NA_real_, NA_real_),
    best_disagreeing_pident = c(NA_real_, 95, NA_real_),
    congruent_evidence_exists_anywhere = c(TRUE, FALSE, FALSE),
    congruent_evidence_best_pident = c(99.9, NA_real_, NA_real_),
    stringsAsFactors = FALSE
  )
}

test_that("flag_incongruent_references() annotates without removing any rows", {
  out <- flag_incongruent_references(.match_df_fixture(), .full_evaluation_fixture())
  expect_equal(nrow(out), 4L)  # every row from match_df retained
  expect_equal(out$accession, .match_df_fixture()$accession)  # order unchanged
})

test_that("flag_incongruent_references() joins the right verdict per row, version-stripped", {
  out <- flag_incongruent_references(.match_df_fixture(), .full_evaluation_fixture())
  expect_equal(out$hierarchy_flag, c("congruent", "incongruent", "incongruent",
                                    "insufficient_independent_evidence"))
  expect_equal(out$finest_common_rank[out$accession == "ACC002.1"], "order")
  expect_equal(out$best_disagreeing_pident[out$accession == "ACC002.1"], 95)
})

test_that("flag_incongruent_references() gives NA for an accession not in evaluation", {
  match_df <- rbind(.match_df_fixture(), data.frame(
    observation_id = "O4", accession = "ACC999", stringsAsFactors = FALSE
  ))
  out <- flag_incongruent_references(match_df, .full_evaluation_fixture())
  expect_true(is.na(out$hierarchy_flag[out$accession == "ACC999"]))
})

test_that("flag_incongruent_references() warns and returns unchanged with no accession column", {
  match_df <- data.frame(observation_id = "O1", stringsAsFactors = FALSE)
  expect_warning(
    out <- flag_incongruent_references(match_df, .full_evaluation_fixture()),
    "no 'accession' column"
  )
  expect_equal(out, match_df)
})

test_that("flag_incongruent_references() errors on a column-name collision", {
  match_df <- .match_df_fixture()
  match_df$hierarchy_flag <- "already_here"
  expect_error(
    flag_incongruent_references(match_df, .full_evaluation_fixture()),
    "already has column"
  )
})

test_that("flag_incongruent_references() validates inputs", {
  expect_error(flag_incongruent_references("not_a_df", .full_evaluation_fixture()),
              "match_df must be a data frame")
  expect_error(flag_incongruent_references(.match_df_fixture(), "not_a_df"),
              "evaluation must be a data frame")
  expect_error(
    flag_incongruent_references(.match_df_fixture(), .evaluation_fixture()),
    "missing required columns"
  )
})

test_that("remove_incongruent_references() removes only incongruent accessions by default", {
  out <- remove_incongruent_references(.match_df_fixture(), .evaluation_fixture(),
                                       gate = "flag")
  expect_equal(nrow(out), 2L)
  expect_false(any(out$accession %in% c("ACC002", "ACC002.1")))
  expect_true("ACC003" %in% out$accession)  # insufficient evidence retained by default
})

test_that("remove_incongruent_references() strips version suffixes before matching", {
  out <- remove_incongruent_references(.match_df_fixture(), .evaluation_fixture(),
                                       gate = "flag")
  expect_false("ACC002.1" %in% out$accession)
})

test_that("remove_incongruent_references(remove_insufficient_evidence = TRUE) also drops insufficient evidence", {
  out <- remove_incongruent_references(.match_df_fixture(), .evaluation_fixture(),
                                       remove_insufficient_evidence = TRUE, gate = "flag")
  expect_equal(nrow(out), 1L)
  expect_equal(out$accession, "ACC001")
})

test_that("remove_incongruent_references() warns and returns unchanged with no accession column", {
  match_df <- data.frame(observation_id = "O1", stringsAsFactors = FALSE)
  expect_warning(
    out <- remove_incongruent_references(match_df, .evaluation_fixture(), gate = "flag"),
    "no 'accession' column"
  )
  expect_equal(out, match_df)
})

test_that("remove_incongruent_references() is a no-op when nothing is flagged", {
  clean_eval <- data.frame(accession = "ACC999", hierarchy_flag = "congruent",
                           stringsAsFactors = FALSE)
  out <- remove_incongruent_references(.match_df_fixture(), clean_eval, gate = "flag")
  expect_equal(nrow(out), 4L)
})

test_that("remove_incongruent_references() validates inputs", {
  expect_error(remove_incongruent_references("not_a_df", .evaluation_fixture(), gate = "flag"),
              "match_df must be a data frame")
  expect_error(remove_incongruent_references(.match_df_fixture(), "not_a_df"),
              "evaluation must be a data frame")
  expect_error(
    remove_incongruent_references(.match_df_fixture(), data.frame(x = 1)),
    "missing required columns"
  )
  expect_error(
    remove_incongruent_references(.match_df_fixture(), .evaluation_fixture(),
                                  override_accessions = 123),
    "override_accessions must be NULL"
  )
})

test_that("remove_incongruent_references(override_accessions=) keeps a specific flagged accession", {
  out_default <- remove_incongruent_references(.match_df_fixture(), .evaluation_fixture(),
                                               gate = "flag")
  expect_false(any(out_default$accession %in% c("ACC002", "ACC002.1")))

  out_overridden <- remove_incongruent_references(.match_df_fixture(), .evaluation_fixture(),
                                                   override_accessions = "ACC002",
                                                   gate = "flag")
  expect_true(any(out_overridden$accession %in% c("ACC002", "ACC002.1")))
  # ACC001 (congruent, never flagged) is untouched either way
  expect_true("ACC001" %in% out_overridden$accession)
})

test_that("remove_incongruent_references(override_accessions=) strips version suffixes", {
  out <- remove_incongruent_references(.match_df_fixture(), .evaluation_fixture(),
                                       override_accessions = "ACC002.1", gate = "flag")
  expect_true(any(out$accession %in% c("ACC002", "ACC002.1")))
})

test_that("remove_incongruent_references(override_accessions=) never removes an accession hierarchy_flag would have kept", {
  # ACC001 is "congruent" -- listing it in override_accessions changes nothing
  out <- remove_incongruent_references(.match_df_fixture(), .evaluation_fixture(),
                                       override_accessions = "ACC001", gate = "flag")
  expect_equal(nrow(out), 2L)
  expect_false(any(out$accession %in% c("ACC002", "ACC002.1")))
})
