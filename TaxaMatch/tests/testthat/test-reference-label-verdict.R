# Tests for score_reference_labels() / refine_reference_verdicts()
# (Threads 1-2 of ecosystem_docs/REENTRY_PROMPT_reference_quality_verdicts_
# and_downstream_use.md). Everything here is offline -- both functions are
# pure derivations over columns evaluate_reference_accessions() has already
# cached, which is the whole point of computing them post-hoc.

.verdict_eval_fixture <- function() {
  data.frame(
    accession = c("KEEP1", "SPARED1", "SPARED2", "REMOVE1", "INSUF1", "OVER1"),
    listed_taxon = c("Genus congruentus", "Scorpaenichthys marmoratus",
                     "Oxylebius pictus", "Cryptacanthodes maculatus",
                     "Askoldia variegata", "Oversized specius"),
    # KEEP1  : ordinary congruent row -- vote clean, nothing disagrees
    # SPARED1: cabezon shape -- vote says incongruent, but agreeing 100 beats
    #          disagreeing 96.79 (the real OK172573 numbers)
    # SPARED2: Oxylebius shape -- no agreeing hit in top_n, corroboration only
    #          outside it, and it LOSES to the disagreement (real KM057978)
    # REMOVE1: no corroboration anywhere + something contradicts (real OP056918)
    # INSUF1 : Askoldia shape -- too few partners, but a clean 100% agreeing hit
    # OVER1  : never submitted to BLAST at all
    frac_independent_below_min_congruent_rank = c(0.08333, 0.75, 0.91667, 0.875,
                                                  0.16667, NA),
    n_independent_top_matches = c(5L, 5L, 5L, 3L, 2L, NA_integer_),
    best_agreeing_pident        = c(99.5, 100, NA, NA, 100, NA),
    best_disagreeing_pident     = c(NA, 96.79, 94.01, 98.62, NA, NA),
    congruent_evidence_exists_anywhere = c(TRUE, TRUE, TRUE, FALSE, TRUE, FALSE),
    congruent_evidence_best_pident = c(99.5, 100, 93.58, NA, 100, NA),
    hierarchy_flag = c("congruent", "incongruent", "incongruent", "incongruent",
                       "insufficient_independent_evidence",
                       "not_evaluated_oversized"),
    stringsAsFactors = FALSE
  )
}

# ---- score_reference_labels() -----------------------------------------------

test_that("score_reference_labels() adds the three derived columns without touching hierarchy_flag", {
  ev  <- .verdict_eval_fixture()
  out <- score_reference_labels(ev)
  expect_true(all(c("label_confidence", "label_identity_margin", "reference_action")
                  %in% names(out)))
  expect_equal(out$hierarchy_flag, ev$hierarchy_flag)
  expect_equal(nrow(out), nrow(ev))
  expect_equal(out$accession, ev$accession)
})

test_that("score_reference_labels() reproduces the measured PtConception evidence-gate split", {
  out <- score_reference_labels(.verdict_eval_fixture())
  actions <- setNames(out$reference_action, out$accession)
  # Only the no-corroboration-anywhere accession is removable.
  expect_equal(unname(actions["REMOVE1"]), "remove")
  expect_false(any(actions[c("KEEP1", "SPARED1", "SPARED2", "INSUF1", "OVER1")] == "remove"))
  expect_equal(unname(actions["KEEP1"]), "keep")
  expect_equal(unname(actions["OVER1"]), "untested")
})

test_that("corroborating evidence anywhere vetoes removal even at very low confidence", {
  out <- score_reference_labels(.verdict_eval_fixture())
  spared2 <- out[out$accession == "SPARED2", ]
  # Oxylebius sits at 0.056 on the real numbers -- barely above the 0.05
  # remove threshold, i.e. exactly the kind of case whose fate a threshold
  # alone decides by a hair. The veto is what makes the outcome robust.
  expect_lt(spared2$label_confidence, 0.10)
  expect_equal(spared2$reference_action, "inspect")

  # Same evidence, but push the threshold past it: the veto still spares it,
  # while the otherwise-identical uncorroborated accession is still removed.
  strict <- score_reference_labels(.verdict_eval_fixture(),
                                   action_remove_below = 0.20)
  expect_equal(strict$reference_action[strict$accession == "SPARED2"], "inspect")
  expect_equal(strict$reference_action[strict$accession == "REMOVE1"], "remove")
})

test_that("an accession that is not 'incongruent' can never be actioned 'remove'", {
  ev <- .verdict_eval_fixture()
  # Force the insufficient row into the worst possible evidence state.
  ev$frac_independent_below_min_congruent_rank[ev$accession == "INSUF1"] <- 0.99
  ev$best_agreeing_pident[ev$accession == "INSUF1"] <- NA_real_
  ev$best_disagreeing_pident[ev$accession == "INSUF1"] <- 99.9
  ev$congruent_evidence_exists_anywhere[ev$accession == "INSUF1"] <- FALSE
  ev$congruent_evidence_best_pident[ev$accession == "INSUF1"] <- NA_real_
  out <- score_reference_labels(ev)
  insuf <- out[out$accession == "INSUF1", ]
  expect_lt(insuf$label_confidence, 0.05)
  expect_equal(insuf$reference_action, "inspect")
})

test_that("the identity margin shifts log-odds by exactly d / margin_scale", {
  ev <- data.frame(
    accession = c("A", "B"),
    frac_independent_below_min_congruent_rank = c(0.5, 0.5),
    n_independent_top_matches = c(5L, 5L),
    best_agreeing_pident    = c(99, 97),
    best_disagreeing_pident = c(97, 97),
    congruent_evidence_exists_anywhere = TRUE,
    congruent_evidence_best_pident = c(99, 97),
    hierarchy_flag = "congruent",
    stringsAsFactors = FALSE
  )
  out <- score_reference_labels(ev, margin_scale = 1)
  # p_vote = 0.5 for both, so logit(confidence) IS the margin.
  expect_equal(stats::qlogis(out$label_confidence[1]), 2, tolerance = 1e-6)
  expect_equal(stats::qlogis(out$label_confidence[2]), 0, tolerance = 1e-6)
  # Doubling margin_scale halves the shift.
  out2 <- score_reference_labels(ev, margin_scale = 2)
  expect_equal(stats::qlogis(out2$label_confidence[1]), 1, tolerance = 1e-6)
})

test_that("no identity information at all leaves the vote unmodified", {
  ev <- data.frame(
    accession = "A",
    frac_independent_below_min_congruent_rank = 0.25,
    n_independent_top_matches = 5L,
    best_agreeing_pident = NA_real_, best_disagreeing_pident = NA_real_,
    congruent_evidence_exists_anywhere = FALSE,
    congruent_evidence_best_pident = NA_real_,
    hierarchy_flag = "congruent", stringsAsFactors = FALSE
  )
  out <- score_reference_labels(ev)
  expect_equal(out$label_confidence, 0.75, tolerance = 1e-6)
  expect_true(is.na(out$label_identity_margin))
})

test_that("score_reference_labels() refuses to silently recompute over itself", {
  out <- score_reference_labels(.verdict_eval_fixture())
  expect_error(score_reference_labels(out), "already has column")
  expect_silent(score_reference_labels(out, overwrite = TRUE))
})

test_that("score_reference_labels() validates its arguments", {
  ev <- .verdict_eval_fixture()
  expect_error(score_reference_labels("not_a_df"), "must be a data frame")
  expect_error(score_reference_labels(ev[, "accession", drop = FALSE]),
               "missing required columns")
  expect_error(score_reference_labels(ev, margin_scale = 0),
               "must be a single positive number")
  expect_error(score_reference_labels(ev, action_remove_below = 2),
               "must be a single number in")
  expect_error(score_reference_labels(ev, action_remove_below = 0.9),
               "must be ordered")
})

test_that("score_reference_labels() handles a zero-row evaluation", {
  out <- score_reference_labels(.verdict_eval_fixture()[0, ])
  expect_equal(nrow(out), 0L)
  expect_true(all(c("label_confidence", "reference_action") %in% names(out)))
})

test_that("score_reference_labels() defaults match .LABEL_VERDICT_DEFAULTS", {
  # The two must not drift: refine_reference_verdicts() resolves its own ...
  # against the list, score_reference_labels() states them in its signature.
  defaults <- formals(TaxaMatch::score_reference_labels)
  shared   <- TaxaMatch:::.LABEL_VERDICT_DEFAULTS
  for (nm in names(shared))
    expect_equal(eval(defaults[[nm]]), shared[[nm]], info = nm)
})

# ---- remove_incongruent_references(gate=) -----------------------------------

test_that("remove_incongruent_references() defaults to the evidence gate, not the raw flag", {
  ev <- score_reference_labels(.verdict_eval_fixture())
  match_df <- data.frame(
    observation_id = paste0("O", seq_len(6)),
    accession = ev$accession, stringsAsFactors = FALSE
  )
  out_action <- remove_incongruent_references(match_df, ev)
  # Only the genuinely uncorroborated accession goes.
  expect_equal(sort(out_action$accession),
               sort(setdiff(ev$accession, "REMOVE1")))

  out_flag <- remove_incongruent_references(match_df, ev, gate = "flag")
  # The old behaviour takes all three "incongruent" accessions with it.
  expect_false(any(c("SPARED1", "SPARED2", "REMOVE1") %in% out_flag$accession))
})

test_that("remove_incongruent_references(gate = 'action') derives the action when it is absent", {
  ev <- .verdict_eval_fixture()   # no reference_action column
  match_df <- data.frame(observation_id = paste0("O", seq_len(6)),
                         accession = ev$accession, stringsAsFactors = FALSE)
  out <- remove_incongruent_references(match_df, ev)
  expect_false("REMOVE1" %in% out$accession)
  expect_true("SPARED1" %in% out$accession)
})

test_that("remove_incongruent_references(gate = 'action') errors usefully on a minimal evaluation", {
  minimal <- data.frame(accession = "A1", hierarchy_flag = "incongruent",
                        stringsAsFactors = FALSE)
  match_df <- data.frame(observation_id = "O1", accession = "A1",
                         stringsAsFactors = FALSE)
  expect_error(remove_incongruent_references(match_df, minimal),
               'gate = "flag"')
})

test_that("remove_insufficient_evidence still works under the action gate", {
  ev <- score_reference_labels(.verdict_eval_fixture())
  match_df <- data.frame(observation_id = paste0("O", seq_len(6)),
                         accession = ev$accession, stringsAsFactors = FALSE)
  out <- remove_incongruent_references(match_df, ev,
                                       remove_insufficient_evidence = TRUE)
  expect_false(any(c("REMOVE1", "INSUF1") %in% out$accession))
})

# ---- refine_reference_verdicts() --------------------------------------------

.verdict_pair_fixture <- function() {
  # X1 is voted on by four partners, one of which (REMOVE1) is itself a
  # confident removal and one of which (INSUF1) is merely under-evaluated.
  data.frame(
    id_x = rep("X1", 4L),
    id_y = c("REMOVE1", "INSUF1", "KEEP1", "SPARED1"),
    p_match = c(0.99, 0.98, 0.97, 0.96),
    pair_finest_common_rank = c("order", "order", "species", "species"),
    stringsAsFactors = FALSE
  )
}

.verdict_eval_with_x1 <- function() {
  ev <- .verdict_eval_fixture()
  x1 <- ev[1, ]
  x1$accession <- "X1"
  x1$listed_taxon <- "Query specius"
  x1$frac_independent_below_min_congruent_rank <- 0.5
  x1$best_agreeing_pident <- 97
  x1$best_disagreeing_pident <- 99
  x1$congruent_evidence_exists_anywhere <- TRUE
  x1$congruent_evidence_best_pident <- 97
  x1$hierarchy_flag <- "incongruent"
  rbind(ev, x1)
}

test_that("refine_reference_verdicts() discounts a confidently-removable partner", {
  ev  <- score_reference_labels(.verdict_eval_with_x1())
  out <- refine_reference_verdicts(ev, pair_table = .verdict_pair_fixture(),
                                   verbose = FALSE)
  x1 <- out[out$accession == "X1", ]
  expect_true(x1$trust_refined)
  # REMOVE1's weight is 0, so it neither counts toward the disagreement nor
  # supplies best_disagreeing_pident -- the vote and the margin both improve.
  expect_gt(x1$label_confidence_trust, x1$label_confidence)
  expect_lt(x1$n_effective_partners, 4)
})

test_that("refine_reference_verdicts() never discounts an under-evaluated partner", {
  ev <- score_reference_labels(.verdict_eval_with_x1())
  w <- TaxaMatch:::.partner_trust_weight(
    flag             = ev$hierarchy_flag,
    action           = ev$reference_action,
    label_confidence = ev$label_confidence,
    min_partner_weight = 0
  )
  names(w) <- ev$accession
  expect_equal(unname(w["INSUF1"]), 1)   # insufficient evidence: full weight
  expect_equal(unname(w["OVER1"]), 1)    # never BLASTed: full weight
  expect_equal(unname(w["KEEP1"]), 1)    # congruent: full weight, no cliff
  expect_equal(unname(w["REMOVE1"]), 0)  # confident removal: silenced
  expect_lt(unname(w["SPARED2"]), 1)     # incongruent: weighted by confidence
})

test_that("refine_reference_verdicts() is order-independent", {
  ev <- score_reference_labels(.verdict_eval_with_x1())
  pairs <- .verdict_pair_fixture()
  a <- refine_reference_verdicts(ev, pair_table = pairs, verbose = FALSE)
  b <- refine_reference_verdicts(ev[rev(seq_len(nrow(ev))), ],
                                 pair_table = pairs[rev(seq_len(nrow(pairs))), ],
                                 verbose = FALSE)
  b <- b[match(a$accession, b$accession), ]
  expect_equal(a$label_confidence_trust, b$label_confidence_trust)
  expect_equal(a$reference_action_trust, b$reference_action_trust)
  expect_equal(a$hierarchy_flag_trust, b$hierarchy_flag_trust)
})

test_that("refine_reference_verdicts() leaves accessions with no pair data unrefined", {
  ev  <- score_reference_labels(.verdict_eval_with_x1())
  out <- refine_reference_verdicts(ev, pair_table = .verdict_pair_fixture(),
                                   verbose = FALSE)
  no_pairs <- out[out$accession != "X1", ]
  expect_false(any(no_pairs$trust_refined))
  expect_equal(no_pairs$label_confidence_trust, no_pairs$label_confidence)
  expect_equal(no_pairs$reference_action_trust, no_pairs$reference_action)
})

test_that("refine_reference_verdicts() reports its own fixpoint behaviour", {
  ev  <- score_reference_labels(.verdict_eval_with_x1())
  out <- refine_reference_verdicts(ev, pair_table = .verdict_pair_fixture(),
                                   verbose = FALSE)
  expect_true(attr(out, "trust_converged"))
  expect_lte(attr(out, "trust_iterations"), 10L)
  out1 <- refine_reference_verdicts(ev, pair_table = .verdict_pair_fixture(),
                                    max_iter = 1L, tol = 0, verbose = FALSE)
  expect_false(attr(out1, "trust_converged"))
  expect_equal(attr(out1, "trust_iterations"), 1L)
})

test_that("refine_reference_verdicts() no-ops loudly when no pair data exists at all", {
  ev <- score_reference_labels(.verdict_eval_fixture())
  expect_message(
    out <- refine_reference_verdicts(
      ev, pair_table = .verdict_pair_fixture()[0, ]),
    "no cached per-partner votes"
  )
  expect_false(any(out$trust_refined))
  expect_equal(out$reference_action_trust, out$reference_action)
})

test_that("refine_reference_verdicts() drops an accession's self-hit", {
  ev <- score_reference_labels(.verdict_eval_with_x1())
  pairs <- .verdict_pair_fixture()
  pairs <- rbind(pairs, data.frame(id_x = "X1", id_y = "X1", p_match = 1,
                                   pair_finest_common_rank = "species",
                                   stringsAsFactors = FALSE))
  out <- refine_reference_verdicts(ev, pair_table = pairs, verbose = FALSE)
  ref <- refine_reference_verdicts(ev, pair_table = .verdict_pair_fixture(),
                                   verbose = FALSE)
  expect_equal(out$label_confidence_trust, ref$label_confidence_trust)
})

test_that("refine_reference_verdicts() validates its arguments", {
  ev <- score_reference_labels(.verdict_eval_fixture())
  expect_error(refine_reference_verdicts(ev), "Supply either cache_dir")
  expect_error(refine_reference_verdicts(ev, pair_table = data.frame(x = 1)),
               "missing required columns")
  expect_error(refine_reference_verdicts(ev, pair_table = .verdict_pair_fixture(),
                                         min_congruent_rank = "nonesuch"),
               "must be one of rank_system")
  expect_error(refine_reference_verdicts(ev, pair_table = .verdict_pair_fixture(),
                                         margin_scal = 2),
               "Unknown label-verdict parameter")
})

# ---- the pair table itself ---------------------------------------------------

test_that(".compute_hierarchy_congruence() carries out the per-partner votes", {
  seq_matrix <- data.frame(
    id_x = rep("Q1", 3L), id_y = c("H1", "H2", "H3"),
    p_match = c(0.99, 0.98, 0.97),
    family.x = "Fam1", family.y = c("Fam1", "Fam2", "Fam1"),
    genus.x = "Gen1", genus.y = c("Gen1", "Gen9", "Gen1"),
    species.x = "Genusone speciesone",
    species.y = c("Genusone speciesone", "Genusnine speciesnine",
                  "Genusone speciestwo"),
    stringsAsFactors = FALSE
  )
  reference_df <- data.frame(
    composite_id = c("Q1", "H1", "H2", "H3"),
    create_date = c("2001/01/01", "2010/01/01", "2011/01/01", "2012/01/01"),
    stringsAsFactors = FALSE
  )
  out <- TaxaMatch:::.compute_hierarchy_congruence(
    seq_matrix, reference_df, rank_system = c("family", "genus", "species")
  )
  pt <- attr(out, "pair_table")
  expect_s3_class(pt, "data.frame")
  expect_setequal(names(pt), c("id_x", "id_y", "p_match",
                               "pair_finest_common_rank", "species_y"))
  expect_equal(nrow(pt), 3L)
  expect_equal(pt$pair_finest_common_rank[pt$id_y == "H1"], "species")
  expect_true(is.na(pt$pair_finest_common_rank[pt$id_y == "H2"]))
  expect_equal(pt$pair_finest_common_rank[pt$id_y == "H3"], "genus")
})

test_that("the pair cache round-trips and rejects a foreign schema", {
  dir <- withr::local_tempdir()
  pairs <- .verdict_pair_fixture()
  pairs$species_y <- paste("Genus", c("alpha", "beta", "gamma", "delta"))
  pairs$params_key <- "k1"
  pairs$evaluated_at <- Sys.time()
  TaxaMatch:::.save_reference_pair_cache(dir, pairs)
  back <- TaxaMatch:::.load_reference_pair_cache(dir)
  expect_equal(nrow(back), nrow(pairs))
  expect_equal(back$id_y, pairs$id_y)

  saveRDS(data.frame(nonsense = 1), file.path(dir, "reference_pair_cache.rds"))
  expect_warning(bad <- TaxaMatch:::.load_reference_pair_cache(dir),
                 "unexpected schema")
  expect_equal(nrow(bad), 0L)
})

test_that("a cache_dir with no pair file is not an error", {
  dir <- withr::local_tempdir()
  expect_equal(nrow(TaxaMatch:::.load_reference_pair_cache(dir)), 0L)
  expect_equal(nrow(TaxaMatch:::.load_reference_pair_cache(NULL)), 0L)
})
