# ==============================================================================
# extra_functions_review_inputs.R
# TaxaLikely -- small, ready-to-run inputs for 3 internal functions written
# AFTER the package's formal code review (reviewed 2026-07-30 / human review
# 2026-08-08) that have never had a reviewer-facing runnable example.
#
# PURPOSE
# -------
# Companion to inst/review_function_inputs.R (which covers all 35 EXPORTED
# functions). This file covers the 3 internal (dot-prefixed, @noRd) functions
# an audit found postdate that review:
#   - .audit_barcode_coverage_impl()   (R/coverage.R)  -- backs audit_barcode_coverage()
#   - .check_score_ratio_monotonicity() (R/train.R)     -- runs inside train_likelihood_model()
#   - .compute_reference_qc_stats()     (R/train.R)     -- backs flag_reference_errors() /
#                                                           audit_reference_database()
#
# ON CALLING INTERNALS VIA `TaxaLikely:::` -- expected, not a bug:
# All three are unexported (@noRd) implementation details, not part of the
# package's public API. A normal source install (devtools::install(), which
# this package's own DESCRIPTION-driven build produces) exposes every
# internal via the triple-colon `:::` operator exactly like this -- there is
# no special build flag or debug mode involved. This is the documented,
# unremarkable way to reach an internal for direct review/testing; it is not
# evidence of a packaging problem, and calling these three functions this way
# below is not working around anything.
#
# Inputs are pulled from three sources, cheapest first (same convention as
# review_function_inputs.R's own header):
#   1. Existing testthat fixtures reused verbatim -- Sections 2 and 3 below
#      (test-train.R's own .make_raw_df() and its 4 hand-built
#      .check_score_ratio_monotonicity() fixtures, purpose-built by that
#      file's own author to demonstrate exactly what each check does).
#   2. Existing roxygen @examples -- none of the three has any (that's the
#      whole reason this file exists).
#   3. New small synthetic input as a last resort -- not needed; testthat
#      fixtures already existed for all three.
#
# REQUIRES tags (read before running a section):
#   OFFLINE   -- pure function or fully self-contained input; no network
#   NETWORK   -- hits a public API (NCBI via rentrez), no credentials needed;
#                small/fast by construction here (Section 1 only)
#
# Run all sections freely -- none need credentials. Section 1 makes a real,
# small, live NCBI call (same Fundulus/12S convention as review_function_
# inputs.R's own audit_barcode_coverage() section, chosen there and reused
# here specifically to stay fast and because it is already a proven-working
# small real genus for this exact NCBI query shape).
#
# .audit_barcode_coverage_impl() has no default argument values of its own
# (all validation/defaulting happens in the exported audit_barcode_coverage()
# wrapper that calls it) -- every argument is therefore supplied explicitly
# below, mirroring exactly what audit_barcode_coverage()'s own default
# arguments would resolve to.
# ==============================================================================

#devtools::load_all()   # or: library(TaxaLikely)
library(TaxaLikely)


# ==============================================================================
# SECTION 1 -- .audit_barcode_coverage_impl()  ---- NETWORK, small real genus --
# Internal scaffold backing the exported audit_barcode_coverage() (validation,
# checkpoint/resume, progress bar, output assembly -- audit_barcode_coverage()
# itself is just a thin pass-through of its own documented arguments into this
# function). No existing testthat fixture or roxygen @example exists for it
# (it needs a live NCBI call, which offline unit tests avoid) -- reusing
# review_function_inputs.R's own small-real-genus convention (Fundulus) here
# to keep this section fast and because it is already known to return a real,
# small, non-empty result for this exact query shape.
# ==============================================================================

## ---- .audit_barcode_coverage_impl() ---- NETWORK, real small genus ---------
ref_species_extra <- data.frame(
  genus   = "Fundulus",
  species = c("Fundulus heteroclitus", "Fundulus parvipinnis"),
  stringsAsFactors = FALSE
)

# Every argument supplied explicitly -- this internal has no defaults of its
# own; these values are exactly what audit_barcode_coverage(match_df =
# ref_species_extra, barcode_term = "12S", target_rank = "genus",
# max_nuccore = 200L) would pass through to it.
coverage_impl <- TaxaLikely:::.audit_barcode_coverage_impl(
  match_df          = ref_species_extra,
  barcode_term      = "12S",
  species_list      = NULL,
  min_len           = NULL,
  max_len           = NULL,
  max_date          = NULL,
  target_rank       = "genus",
  cache_dir         = tools::R_user_dir("TaxaLikely", "cache"),
  ncbi_api_key      = NULL,
  max_nuccore       = 200L,
  exclude_predicted = TRUE
)
coverage_impl$census
length(coverage_impl$unreferenced)


# ==============================================================================
# SECTION 2 -- .compute_reference_qc_stats()  ---- OFFLINE ---------------------
# Backs flag_reference_errors() (which calls it directly, then dplyr::select()s
# back down to that function's own smaller documented @return contract) and
# audit_reference_database()'s per-accession QC stats. Fixture reused verbatim
# from tests/testthat/test-train.R's own .make_raw_df() -- 3 sequences, 2
# species (A1/A2 = "Aa", B1 = "Bb"), chosen by that file's own author
# specifically to exercise both a real within-species (self) comparison and a
# real cross-species (foreign) comparison.
# ==============================================================================

## ---- .compute_reference_qc_stats() ---- OFFLINE -----------------------------
make_raw_df_extra <- function() {
  data.frame(
    id_x      = c("A1", "A1", "A1", "A2", "A2", "A2", "B1", "B1", "B1"),
    id_y      = c("A1", "A2", "B1", "A1", "A2", "B1", "A1", "A2", "B1"),
    species.x = c("Aa", "Aa", "Aa", "Aa", "Aa", "Aa", "Bb", "Bb", "Bb"),
    species.y = c("Aa", "Aa", "Bb", "Aa", "Aa", "Bb", "Aa", "Aa", "Bb"),
    genus.x   = c("A", "A", "A", "A", "A", "A", "B", "B", "B"),
    genus.y   = c("A", "A", "B", "A", "A", "B", "A", "A", "B"),
    p_match   = c(1.00, 0.95, 0.70, 0.95, 1.00, 0.68, 0.70, 0.68, 1.00),
    stringsAsFactors = FALSE
  )
}
qc_stats_no_floor <- TaxaLikely:::.compute_reference_qc_stats(make_raw_df_extra())
qc_stats_no_floor[, c("id_x", "species_x", "median_self_match", "max_foreign_match",
                       "n_self_neighbors", "n_foreign_pairs", "n_foreign_taxa",
                       "integrity_gap")]

# min_coverage: a permissive pairwise-overlap floor (NOT the same as the
# calibrated trust threshold flag_reference_errors()/classify_reference_
# accessions() apply downstream -- see this function's own roxygen). Add a
# coverage column and show A1's one foreign comparison (A1-B1) dropping out
# once its coverage is too thin to trust, same pattern as that test file's
# own "min_coverage excludes low-coverage pairs" regression test.
raw_df_with_coverage <- make_raw_df_extra()
raw_df_with_coverage$coverage <- 1.0
raw_df_with_coverage$coverage[raw_df_with_coverage$id_x == "A1" &
                                 raw_df_with_coverage$id_y == "B1"] <- 0.1
qc_stats_floored <- TaxaLikely:::.compute_reference_qc_stats(
  raw_df_with_coverage, min_coverage = 0.5
)
qc_stats_floored[qc_stats_floored$id_x == "A1",
                  c("id_x", "max_foreign_match", "n_foreign_pairs")]
# max_foreign_match falls back to 0 (not 0.70) -- A1's only foreign pair was
# excluded by the coverage floor, leaving zero foreign comparisons.


# ==============================================================================
# SECTION 3 -- .check_score_ratio_monotonicity()  ---- OFFLINE -----------------
# Runs automatically at the end of train_likelihood_model() (see that
# function's own "Non-monotonic score->likelihood shape" @section and
# TaxaLikely/CLAUDE.md's 2026-08-06 note on Stats$mlr_violations/
# max_ceiling_z). Checks the monotone-likelihood-ratio (MLR) property that
# actually matters for a Bayesian classifier: whether H1's evidence for the
# known-species hypothesis, relative to its genus's H2 alternative, keeps
# strengthening all the way to a perfect (100%) match -- NOT whether H1's own
# density peaks there (it need not; a Gaussian peaks at its fitted mean, which
# real reference data can sit below). All 3 fixtures below are reused verbatim
# from tests/testthat/test-train.R, purpose-built by that file's own author to
# make this exact distinction concrete with hand-computed numbers.
# ==============================================================================

## ---- .check_score_ratio_monotonicity() ---- OFFLINE, flags a violation -----
# sqrt_mismatch scale: a perfect match transforms to exactly 0. H1 is very
# tight (sigma=0.001) around mu=-0.05 -- 0 sits ~50 SD away, so H1's density
# has already collapsed by the ceiling. H2 (pooled, delta=0.05 -> mu2=-0.10,
# sigma=0.05) is much wider/looser -- 0 sits only ~2 SD from mu2, so H2
# remains comparatively substantial there. A tighter H1 than its H2
# alternative is exactly the condition that can make the ratio turn over
# before the ceiling.
h1_tight <- data.frame(lookup_key = "Sp1", rank = "species",
                        mu_score = -0.05, mu_gap = 0, sigma_score = 0.001,
                        stringsAsFactors = FALSE)
h2_pooled <- list(delta = 0.05,
                   sigma = matrix(c(0.05, 0, 0, 1), nrow = 2,
                                  dimnames = list(c("score_logit", "gap_logit"),
                                                  c("score_logit", "gap_logit"))))
mlr_violation <- TaxaLikely:::.check_score_ratio_monotonicity(
  H1_Lookup = h1_tight, global_sigma1 = 0.0005, H2 = h2_pooled, H2_Lookup = NULL,
  species_genus = NULL, score_transform = "sqrt_mismatch", logit_epsilon = 1e-4
)
mlr_violation$violations   # "Sp1" -- H1 tighter than H2, ratio turns over

## ---- .check_score_ratio_monotonicity() ---- OFFLINE, no violation ----------
# Same shape, but H1 is now at least as wide as H2 -- the typical current-
# production case (see train_likelihood_model()'s own @section) -- so the
# ratio keeps strengthening all the way to the ceiling and nothing is flagged.
h1_wide <- data.frame(lookup_key = "Sp1", rank = "species",
                       mu_score = -0.05, mu_gap = 0, sigma_score = 0.05,
                       stringsAsFactors = FALSE)
h2_pooled_2 <- list(delta = 0.03,
                     sigma = matrix(c(0.02, 0, 0, 1), nrow = 2,
                                    dimnames = list(c("score_logit", "gap_logit"),
                                                    c("score_logit", "gap_logit"))))
mlr_clean <- TaxaLikely:::.check_score_ratio_monotonicity(
  H1_Lookup = h1_wide, global_sigma1 = 0.01, H2 = h2_pooled_2, H2_Lookup = NULL,
  species_genus = NULL, score_transform = "sqrt_mismatch", logit_epsilon = 1e-4
)
mlr_clean$violations       # character(0) -- no violation

## ---- .check_score_ratio_monotonicity() ---- OFFLINE, genus-specific H2 -----
# H2_Lookup (a real per-genus shrunk delta/variance, see train_likelihood_
# model()'s Session 151/158 notes) is preferred over the pooled H2 list when
# the species' own genus has an entry -- here the pooled list alone is set to
# a SAFE (non-violating) shape, so a flagged violation confirms the
# genus-specific row is what actually drove the result, not an unused pooled
# fallback.
h2_lookup_extra <- data.frame(genus = "G1", n_pairs = 5L,
                               delta_shrunk = 0.05, var_shrunk = 0.05,
                               stringsAsFactors = FALSE)
mlr_genus_specific <- TaxaLikely:::.check_score_ratio_monotonicity(
  H1_Lookup = h1_tight,
  global_sigma1 = 0.0005,
  H2 = list(delta = 0.01,
            sigma = matrix(c(0.0005, 0, 0, 1), nrow = 2,
                           dimnames = list(c("score_logit", "gap_logit"),
                                           c("score_logit", "gap_logit")))),
  H2_Lookup = h2_lookup_extra,
  species_genus = c(Sp1 = "G1"),
  score_transform = "sqrt_mismatch", logit_epsilon = 1e-4
)
mlr_genus_specific$violations   # "Sp1" -- driven by H2_Lookup's G1 row, not the (safe) pooled H2
