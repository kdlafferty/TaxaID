# ==============================================================================
# extra_functions_review_inputs.R
# TaxaExpect -- small, ready-to-run inputs for internal functions written
# after this package's formal code review (see inst/taxaexpect_review.Rmd
# / inst/taxaexpect_review_response.md for that review's own coverage)
#
# PURPOSE
# -------
# Closes the reviewer-facing runnable-example gap for two internal helpers
# that postdate the formal review:
#   .beta_mean()              -- R/utils_internal.R
#   .beta_sd()                -- R/utils_internal.R
# in the same style/convention as TaxaLikely/inst/review_function_inputs.R
# (this ecosystem's established reference for reviewer-facing runnable
# examples).
#
# BOTH ARE INTERNAL (dot-prefixed, @noRd, not exported). They are called
# below via the triple-colon form, e.g. TaxaExpect:::.beta_mean(...). This is
# EXPECTED and FINE for a dev-facing review script: a normal source install
# (devtools::install()/devtools::load_all()) exposes every internal function
# to ::: the same way it exposes exported functions to ::  -- ::: is simply
# the accessor for a package's unexported namespace, not a hack or a sign of
# a packaging problem. Neither is exported and neither should be;
# see each function's own @noRd tag in R/utils_internal.R.
#
# Inputs are new small synthetic values (matching TaxaLikely's own
# review_function_inputs.R convention for this input-source category):
# grepping tests/testthat/ for both names found zero existing coverage
# (confirmed via `grep -rn "\.beta_mean\|\.beta_sd" tests/testthat/`,
# 0 hits) and neither has a roxygen @examples block, so there was nothing
# small/existing to reuse.
#
# REQUIRES tags (read before running a section):
#   OFFLINE -- pure function or fully self-contained input; no network, no
#              Bioconductor packages, no interactive/Shiny session
# The section below is OFFLINE. It needs no DECIPHER/Biostrings,
# network access, or credentials -- these are small internal arithmetic
# helpers, not I/O-performing functions.
# ==============================================================================

# devtools::load_all()   # or: library(TaxaExpect)
library(TaxaExpect)


# ==============================================================================
# SECTION 1 -- Beta-distribution moment helpers (R/utils_internal.R)
# .beta_mean() / .beta_sd()
# ==============================================================================

## ---- .beta_mean() ---- OFFLINE, new small synthetic input -------------------
# No existing testthat coverage found for this name (grepped tests/testthat/
# first, per this file's own header). .beta_mean(a, b) is just a/(a+b) --
# consolidated here (code review response, 2026-08-04) from three places that
# each reimplemented it identically: generate_full_priors.R,
# generate_undetected_diversity.R, generate_domestic_food_priors.R. A small
# hand-picked (a, b) pair with an obvious expected answer (Beta(2, 8) has
# mean 0.2) is the clearest possible input for a reviewer to hand-verify.
mean_val <- TaxaExpect:::.beta_mean(a = 2, b = 8)
mean_val # 0.2 = 2 / (2 + 8)

# Vectorised over a/b pairs, exactly as every real caller uses it (one alpha/
# beta pair per prior row) -- shown here with the same Beta(2, 8) case plus a
# symmetric Beta(5, 5) (mean 0.5) alongside it.
TaxaExpect:::.beta_mean(a = c(2, 5), b = c(8, 5)) # c(0.2, 0.5)

## ---- .beta_sd() ---- OFFLINE, new small synthetic input ----------------------
# Same Beta(2, 8) input as .beta_mean() above, for direct side-by-side
# comparison -- both helpers are always called together on the same (a, b)
# pair by every real caller (mean and SD of the same fitted Beta prior).
sd_val <- TaxaExpect:::.beta_sd(a = 2, b = 8)
sd_val # sqrt((2*8) / ((2+8)^2 * (2+8+1))) ~= 0.1206

TaxaExpect:::.beta_sd(a = c(2, 5), b = c(8, 5)) # c(~0.1206, ~0.1508)
