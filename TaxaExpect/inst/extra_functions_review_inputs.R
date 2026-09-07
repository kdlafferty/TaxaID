# ==============================================================================
# extra_functions_review_inputs.R
# TaxaExpect -- small, ready-to-run inputs for functions written AFTER this
# package's formal code review (reviewed 2026-07-31; see inst/taxaexpect_review.Rmd
# / inst/taxaexpect_review_response.md for that review's own coverage)
#
# PURPOSE
# -------
# A 2026-08-11 audit found 4 functions in TaxaExpect were written after the
# 2026-07-31 review and so never had a reviewer-facing runnable example:
#   .beta_mean()             -- R/utils_internal.R
#   .beta_sd()                -- R/utils_internal.R
#   .parse_grid_id_coords()   -- R/utils_internal.R
#   .prepare_one_group()      -- R/prepare_model_dataframe.R
# This file closes that gap, one small section per function, in the same
# style/convention as TaxaLikely/inst/review_function_inputs.R (this
# ecosystem's established reference for reviewer-facing runnable examples).
#
# ALL FOUR ARE INTERNAL (dot-prefixed, @noRd, not exported). They are called
# below via the triple-colon form, e.g. TaxaExpect:::.beta_mean(...). This is
# EXPECTED and FINE for a dev-facing review script: a normal source install
# (devtools::install()/devtools::load_all()) exposes every internal function
# to ::: the same way it exposes exported functions to ::  -- ::: is simply
# the accessor for a package's unexported namespace, not a hack or a sign of
# a packaging problem. None of these four is exported and none should be;
# see each function's own @noRd tag in R/utils_internal.R / R/prepare_model_dataframe.R.
#
# Inputs are pulled from three sources, cheapest first (matching TaxaLikely's
# own review_function_inputs.R convention):
#   1. Existing testthat fixtures reused verbatim -- .parse_grid_id_coords()
#      below (from tests/testthat/test-plot_theta_map_interactive.R) and
#      .prepare_one_group() below (a single-group slice of the fixture in
#      tests/testthat/test-prepare_model_dataframe.R's
#      .make_grouped_input(), grepped for first and confirmed present)
#   2. Existing roxygen @examples -- not used here; neither .beta_mean()/
#      .beta_sd() (no @examples, internal @noRd helpers) nor
#      .prepare_one_group() (no @examples of its own) has one to reuse
#   3. New small synthetic inputs -- .beta_mean()/.beta_sd() below, since
#      grepping tests/testthat/ for both names found zero existing coverage
#      (confirmed via `grep -rn "\.beta_mean\|\.beta_sd" tests/testthat/`,
#      0 hits) and there was nothing small/existing to reuse
#
# REQUIRES tags (read before running a section):
#   OFFLINE -- pure function or fully self-contained input; no network, no
#              Bioconductor packages, no interactive/Shiny session
# All four sections below are OFFLINE. None needs DECIPHER/Biostrings,
# network access, or credentials -- these are small internal arithmetic/
# string/data-reshaping helpers, not I/O-performing functions.
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


# ==============================================================================
# SECTION 2 -- grid_id string parser (R/utils_internal.R)
# .parse_grid_id_coords()
# ==============================================================================

## ---- .parse_grid_id_coords() ---- OFFLINE -------------------------------------
# Fixture reused verbatim from tests/testthat/test-plot_theta_map_interactive.R
# (grepped tests/testthat/ first and found this exact case already covered --
# cheapest-first per this file's own header). Consolidated (code review
# response, 2026-08-04) from two independently-reimplemented parsers in
# compute_moran_basis.R and plot_theta_map_interactive.R. Format:
# "Grid_{lat_int}p{lat_dec}_{m}{lon_int}p{lon_dec}", where "p" encodes a
# decimal point and a leading "m" on the longitude half encodes a negative
# sign (see create_sites_from_grid()).
TaxaExpect:::.parse_grid_id_coords("Grid_33p1_m118p5")
# lat = 33.1, lon = -118.5 (the leading "m" makes lon negative)

# Vectorised, and NA-safe (sub()-based rather than regmatches(regexpr(...)),
# specifically so a malformed/NA grid_id degrades to a same-length NA row
# instead of silently shrinking the output -- shown here with one well-formed
# id, one NA, and one malformed (non-"Grid_"-prefixed) id all in one call.
ids <- c("Grid_33p1_m118p5", NA_character_, "not_a_grid_id")
TaxaExpect:::.parse_grid_id_coords(ids)
# row 1: lat=33.1, lon=-118.5 (parsed correctly)
# rows 2-3: lat=NA, lon=NA (NA/malformed input -- 3 rows out for 3 ids in,
#            never dropped)


# ==============================================================================
# SECTION 3 -- Single-group occurrence aggregation (R/prepare_model_dataframe.R)
# .prepare_one_group()
# ==============================================================================

## ---- .prepare_one_group() ---- OFFLINE ----------------------------------------
# .prepare_one_group(data, covariates, habitat_col) is the single-group
# aggregation logic behind prepare_model_dataframe() -- extracted to a
# top-level helper (code review response, 2026-08-04) so it reads at its own
# indentation level and so it can be called identically whether or not
# prepare_model_dataframe(sampling_group_col=) split the input into several
# groups first (Session 149's group-aware effort-denominator feature, see
# TaxaExpect/CLAUDE.md's top session note and prepare_model_dataframe()'s own
# "Group-aware effort denominators" @section for the full design).
#
# What "one group" of input data looks like: prepare_model_dataframe() itself
# calls .prepare_one_group() once directly when sampling_group_col = NULL (no
# grouping -- the whole input IS "one group"), or once PER GROUP (after
# splitting on sampling_group_col) when grouping is requested. To show a
# real, non-trivial one-group slice rather than inventing a fresh fixture,
# this reuses the "vertebrate" half of tests/testthat/test-prepare_model_dataframe.R's
# own .make_grouped_input() fixture (grepped for first -- that test file
# already exercises .prepare_one_group() indirectly, via
# prepare_model_dataframe(sampling_group_col = "sampling_group"), by calling
# it once per group and recombining; here it is called directly on just the
# vertebrate slice to show its own standalone input/output shape). The
# original two-group fixture is one site (g1) with a vertebrate group (V1 x3,
# V2 x2 = 5 records) and a phytoplankton group (P1 x10 records) -- pulling out
# just the vertebrate rows below is exactly what prepare_model_dataframe()'s
# internal split(data, sampling_group_col) does before calling
# .prepare_one_group() on each piece.
one_group_data <- data.frame(
  grid_id = "g1",
  lat_r = 34,
  lon_r = -120,
  main_habitat = "Kelp",
  taxon_name = c(rep("V1", 3), rep("V2", 2)),
  stringsAsFactors = FALSE
)

one_group_out <- TaxaExpect:::.prepare_one_group(
  data        = one_group_data,
  covariates  = c("lat_r", "lon_r"),
  habitat_col = "main_habitat"
)
one_group_out[, c(
  "grid_id", "taxon_name", "n_species", "n_total_at_site",
  "n_other", "is_present", "observed_in_habitat"
)]
# n_total_at_site = 5 for both V1 and V2 -- this group's own total (3+2),
# NOT contaminated by the phytoplankton group's 10 records (which
# .prepare_one_group() never sees when called this way, since the split
# already happened one level up in prepare_model_dataframe()).

# habitat_col = NULL: the "no habitat classification available" path
# (TaxaExpect/CLAUDE.md's habitat_col = NULL design, 2026-07-03) -- the
# internal ".habitat" placeholder is used and then dropped, so the output has
# no habitat column at all rather than one hardcoded constant category.
one_group_out_nohab <- TaxaExpect:::.prepare_one_group(
  data        = one_group_data,
  covariates  = c("lat_r", "lon_r"),
  habitat_col = NULL
)
names(one_group_out_nohab) # no "main_habitat" column present
