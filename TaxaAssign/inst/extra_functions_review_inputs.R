# ==============================================================================
# extra_functions_review_inputs.R
# TaxaAssign -- small, ready-to-run inputs for 3 internal (@noRd) helpers
# written AFTER this package's formal code review (reviewed 2026-08-04/
# 2026-08-07, see inst/taxaassign_review.Rmd / inst/taxaassign_review_response.md)
# and so never had a reviewer-facing runnable example.
#
# PURPOSE
# -------
# Companion to inst/taxaassign_review.Rmd's own review coverage: gives a
# reviewer a concrete, small input for each of these 3 functions so they can
# actually be run and inspected, rather than only read as source. Modeled on
# TaxaLikely/inst/review_function_inputs.R (same monorepo, same conventions:
# REQUIRES tags, section banners, per-function subheaders explaining WHY each
# input was chosen).
#
# Functions covered:
#   .beta_mean()               R/site_utils.R
#   .check_rank_system_order() R/site_utils.R
#   .row_col_or()               R/posterior_consensus.R
#
# All three are internal, dot-prefixed, @noRd helpers -- never exported, so
# this file calls them via triple-colon (TaxaAssign:::.fn(...)). That is
# EXPECTED and FINE for a dev/reviewer session working from a normal source
# install: `:::` reaches into a package's internal namespace regardless of
# what NAMESPACE exports, which is exactly what a code reviewer working from
# the source tree wants. It is not a bug or a workaround for a missing
# export -- none of these three is a candidate for exporting (each is a
# small, package-internal utility with no standalone use case outside the
# functions that already call it).
#
# Inputs are pulled from two sources, cheapest first:
#   1. Existing testthat fixtures reused verbatim -- .beta_mean() and
#      .check_rank_system_order() already have dedicated coverage in
#      tests/testthat/test-site_utils.R (added the same 2026-08 review this
#      file follows up on); both sections below reuse those exact values.
#   2. A new, small synthetic input for .row_col_or() -- it had NO existing
#      test coverage at all (confirmed by grepping tests/testthat/ for the
#      name before writing this section), so a small one-row data frame
#      matching this function's real production shape (a `winner_row` slice
#      of posterior_consensus()'s per-observation posterior_df, see
#      R/posterior_consensus.R lines ~591-629 for the real call sites) was
#      built fresh for this file.
#
# REQUIRES tags (read before running a section):
#   OFFLINE -- pure function, no network, no Suggests packages needed.
# All three sections below are OFFLINE -- there is nothing else to gate.
#
# ==============================================================================

# devtools::load_all()   # or: library(TaxaAssign)
library(TaxaAssign)


# ==============================================================================
# SECTION 1 -- .beta_mean() -- R/site_utils.R
# ==============================================================================

## ---- .beta_mean() ---- OFFLINE -----------------------------------------------
# Fixture reused verbatim from tests/testthat/test-site_utils.R (the function's
# own existing test coverage, added the same review session this file follows
# up on). Plain Beta-distribution mean, a / (a + b); duplicated (not shared via
# a dependency) from TaxaExpect:::.beta_mean() since TaxaAssign does not depend
# on TaxaExpect and this is a one-line formula used in only one caller
# (adjust_inat_range_priors()) -- see this function's own roxygen for the full
# "why duplicated, not shared" reasoning.
TaxaAssign:::.beta_mean(3, 7) # 0.3
TaxaAssign:::.beta_mean(c(1, 9), c(1, 1)) # c(0.5, 0.9) -- vectorized over a/b


# ==============================================================================
# SECTION 2 -- .check_rank_system_order() -- R/site_utils.R
# ==============================================================================

## ---- .check_rank_system_order() ---- OFFLINE ---------------------------------
# Two fixtures reused verbatim from tests/testthat/test-site_utils.R, chosen to
# show BOTH branches: a correctly-ordered rank_system (silent, no output) and a
# reversed one (a real cli::cli_warn(), printed below when this file is run via
# Rscript -- expected output, not an error). Several functions in this package
# (join_priors(), posterior_consensus(), score_consensus()) infer coarsest/
# finest rank from a rank_system vector's POSITION, so a caller who accidentally
# reverses a hand-typed vector (e.g. species-to-family instead of family-to-
# species) silently swaps "coarsest" and "finest" everywhere downstream --
# this check exists to catch exactly that class of mistake early.

# Correctly ordered coarse-to-fine -- silent, no warning.
TaxaAssign:::.check_rank_system_order(c("family", "genus", "species"), "review demo")

# Reversed (fine-to-coarse) -- produces a real warning, printed below.
TaxaAssign:::.check_rank_system_order(c("species", "genus", "family"), "review demo")

# Fewer than 2 names overlap with TaxaTools::standard_ranks -- also silent,
# since there's nothing to compare an order against (custom rank names, a
# single-element rank_system, or NULL all take this early-return path).
TaxaAssign:::.check_rank_system_order(c("custom_rank_a", "custom_rank_b"), "review demo")
TaxaAssign:::.check_rank_system_order(NULL, "review demo")


# ==============================================================================
# SECTION 3 -- .row_col_or() -- R/posterior_consensus.R
# ==============================================================================

## ---- .row_col_or() ---- OFFLINE -----------------------------------------------
# No existing test coverage (confirmed via grep across tests/testthat/ before
# writing this section) -- new small synthetic input built to match this
# function's real production shape: a single-row slice of a posterior_df
# (posterior_consensus()'s `winner_row`, see R/posterior_consensus.R's own
# ~8 real call sites, e.g. winner_prior <- .row_col_or(winner_row, "prior_mean")).
# Consolidates a "read this column if present, else use a default" pattern
# needed because several of those columns (e.g. score_likelihood_cov,
# species_confusion_risk) are OPTIONAL upstream outputs -- present only when
# the caller's posterior_df came from a TaxaLikely version/pathway that
# populates them, absent otherwise (e.g. assign_taxa_llm() input).
winner_row <- data.frame(
  taxon_name           = "Sardinops sagax",
  hypothesis_type      = "specific_candidate",
  prior_mean           = 0.62,
  score_likelihood     = 0.87,
  stringsAsFactors     = FALSE
)

# Column present -- returns the real value.
TaxaAssign:::.row_col_or(winner_row, "prior_mean")
# 0.62

TaxaAssign:::.row_col_or(winner_row, "hypothesis_type", NA_character_)
# "specific_candidate" -- default is ignored since the column IS present

# Column absent (e.g. an optional upstream diagnostic never attached to this
# particular posterior_df) -- falls back to the default instead of erroring.
TaxaAssign:::.row_col_or(winner_row, "score_likelihood_cov")
# NA_real_ (the function's own default default)

TaxaAssign:::.row_col_or(winner_row, "winner_hypothesis_type_missing_col", NA_character_)
# NA_character_ -- caller-supplied default used when the column is absent
