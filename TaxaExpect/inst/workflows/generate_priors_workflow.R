# ==============================================================================
# WORKFLOW: GENERATE PRIORS (TaxaExpect)
# ==============================================================================
# Purpose: Grid occurrence data, fit a binomial GLMM of detection probability
#   (theta) across taxa x site x habitat, generate Tier 3 proxy priors for
#   undetected diversity, and assemble the full prior table consumed by
#   TaxaAssign.
#
# Audience: someone learning TaxaExpect step by step, continuing directly from
#   TaxaHabitat's assign_habitat_workflow.R.
#
# WHY THIS SCRIPT CANNOT BE A SUB-MINUTE TOY EXAMPLE (unlike TaxaFetch's and
# TaxaHabitat's earlier scripts): TaxaExpect::optimize_grid_size() enforces
# real statistical minimum-data thresholds (default min_distinct_locs = 20,
# min_locs_per_habitat = 3, min_N_threshold = 10, min_s_threshold = 5) before
# it will recommend a grid resolution, and train_biodiversity_model() needs
# enough spatial + taxonomic spread across grid cells and habitats to fit a
# binomial GLMM at all. A 3-row toy tibble (as used upstream) satisfies none
# of these thresholds -- it would either silently trip every fallback level in
# optimize_grid_size() or produce a degenerate one-cell grid with a GLMM that
# cannot converge. So DEBUG_MODE = TRUE here first tries to load TaxaHabitat's
# real tutorial checkpoint (which itself depends on a real GBIF fetch having
# happened upstream); if that checkpoint is missing or too thin, it falls back
# to a wider, LIVE GBIF fetch sized to actually have enough breadth for the
# grid search and model to run. DEBUG_MODE = TRUE may therefore take a few
# minutes on a live GBIF fetch, not under a minute like the earlier scripts.
#
# Output: taxaexpect_priors -- a tibble; see "Output" block at the end of this
#   file for the full column contract consumed by TaxaAssign.
# ==============================================================================

# --- Namespaces used in this script (loaded, never attached) ----------------
# TaxaExpect::, TaxaFetch::, TaxaTools::, dplyr::, tibble::

# ==============================================================================
# CONFIG
# ==============================================================================
# Parameters are grouped here so this script's body can become a wrapper
# function's implementation with minimal changes -- each CONFIG value maps
# to a future function argument.

# DEBUG_MODE = TRUE  -> load TaxaHabitat's tutorial checkpoint if present and
#                       sufficiently broad, else fall back to a modest LIVE
#                       GBIF fetch (wider than the upstream tutorial's box) so
#                       the grid search / model actually have enough data.
# DEBUG_MODE = FALSE -> plug in your own occurrences_clean object (see the
#                       "SWAP IN YOUR OWN DATA" block below Section 1)
DEBUG_MODE <- TRUE

# NEEDS_SAMPLING_GROUP mirrors TaxaHabitat's upstream toggle of the same name.
# Only set TRUE if TaxaHabitat's Step B actually ran and occurrences_clean
# carries a sampling_group column (broad-marker workflows, e.g. 18S/COI).
# Narrow-marker (12S) workflows leave this FALSE and use VARIANT A below.
NEEDS_SAMPLING_GROUP <- FALSE

# Minimum distinct grid-able locations required before we trust a checkpoint
# as "broad enough" for optimize_grid_size()'s real thresholds
# (min_distinct_locs defaults to 20 -- see CLAUDE.md). This is just this
# script's own pre-flight sanity check, not a TaxaExpect package parameter.
MIN_LOCS_FOR_TUTORIAL <- 20L

# CONFIRMED BY ACTUALLY RUNNING THIS SCRIPT: location count alone is not
# enough. TaxaExpect's biodiversity model estimates each species' relative
# abundance via cbind(n_species, n_other) -- a single-genus/single-species
# checkpoint (e.g. TaxaFetch/TaxaHabitat's own genus-Gadus tutorial data) has
# n_other = 0 for every row, so there is no co-occurring-species signal to
# model at all. With only 1 species, every taxon falls into Tier 2, no Tier 1
# model is fit, and screen_spatial_formula()/train_biodiversity_model() fail
# deep inside glmmTMB (VarCorr() on a NULL Tier 1 model; contrasts on a
# single-level main_habitat factor). Require real species breadth, not just
# spatial breadth, before trusting a checkpoint.
MIN_SPECIES_FOR_TUTORIAL <- 3L

# The focal habitat for this tutorial run's site-level prior extraction
# (Section 7). "Marine" matches both the Gadus checkpoint path and the
# inline fallback tag below.
SITE_HABITAT <- "Marine"

if (DEBUG_MODE) {

  # ---- Tutorial example: continue from TaxaHabitat's Gadus checkpoint -------
  # This is the exact readRDS() line documented in assign_habitat_workflow.R's
  # Output block (its Section 6 saves occurrences_clean to
  # "<OUT_PREFIX>_occurrences_clean.rds" with OUT_PREFIX = "tutorial_gadus").
  .habitat_checkpoint <- file.path(tempdir(), "tutorial_gadus_occurrences_clean.rds")

  .have_broad_checkpoint <- FALSE
  if (file.exists(.habitat_checkpoint)) {
    occurrences_clean <- readRDS(.habitat_checkpoint)
    n_distinct_locs <- occurrences_clean |>
      dplyr::distinct(decimalLatitude, decimalLongitude) |>
      nrow()
    n_distinct_species <- dplyr::n_distinct(occurrences_clean$taxon_name)
    message("DEBUG_MODE = TRUE -- loaded TaxaHabitat's checkpoint: ",
            .habitat_checkpoint, " (", n_distinct_locs, " distinct location(s), ",
            n_distinct_species, " distinct species).")
    if (n_distinct_locs >= MIN_LOCS_FOR_TUTORIAL &&
        n_distinct_species >= MIN_SPECIES_FOR_TUTORIAL) {
      .have_broad_checkpoint <- TRUE
    } else if (n_distinct_species < MIN_SPECIES_FOR_TUTORIAL) {
      message("  Checkpoint has fewer than MIN_SPECIES_FOR_TUTORIAL (",
              MIN_SPECIES_FOR_TUTORIAL, ") distinct species -- a single-genus ",
              "tutorial checkpoint (e.g. TaxaFetch/TaxaHabitat's genus-Gadus ",
              "run) has no co-occurring-species signal for the biodiversity ",
              "model to use. Falling back to a wider live GBIF fetch instead.")
    } else {
      message("  Checkpoint has fewer than MIN_LOCS_FOR_TUTORIAL (",
              MIN_LOCS_FOR_TUTORIAL, ") distinct locations -- ",
              "optimize_grid_size()'s min_distinct_locs = 20 default would ",
              "very likely fall back or degenerate. Falling back to a wider ",
              "live GBIF fetch instead.")
    }
  } else {
    message("DEBUG_MODE = TRUE -- TaxaHabitat checkpoint not found at ",
            .habitat_checkpoint, "; falling back to a wider live GBIF fetch.")
  }

  if (!.have_broad_checkpoint) {

    # ---- Fallback: modest LIVE GBIF fetch, wider than the upstream tutorial's
    # narrow genus-Gadus box. Family Gadidae (cod family) over a bigger North
    # Atlantic box and a longer year range gives enough spatial + taxonomic
    # spread for optimize_grid_size() and train_biodiversity_model() to have a
    # realistic chance of converging, while staying a "tutorial-sized" query.
    #
    # JUDGMENT CALL: family Gadidae / a 6-degree-radius box / 2000-2024 was
    # chosen as a modest widening from the upstream genus-Gadus / 2-degree
    # tutorial box -- enough species + location breadth to plausibly clear
    # min_distinct_locs = 20 and min_locs_per_habitat = 3, without becoming a
    # multi-thousand-key bulk download. Real studies should size this to their
    # actual sampling domain, not copy these numbers.
    message("\n--- Fallback: live GBIF fetch (family Gadidae, wider North Atlantic box) ---")

    .fallback_taxa   <- tibble::tibble(family = "Gadidae")
    .fallback_lat    <- 60.0
    .fallback_lon    <- 2.0
    .fallback_radius <- 6.0      # degrees -- wider than the upstream 2-degree tutorial box
    .fallback_years  <- "2000,2024"
    .fallback_limit  <- 2000L

    .fallback_bbox <- TaxaFetch::make_bbox_wkt(
      lat        = .fallback_lat,
      lon        = .fallback_lon,
      radius_deg = .fallback_radius
    )

    .fallback_keys <- TaxaFetch::get_keys_from_context(.fallback_taxa)
    .fallback_valid_keys <- .fallback_keys$usageKey[!is.na(.fallback_keys$usageKey)]

    if (length(.fallback_valid_keys) == 0) {
      stop("Fallback GBIF key resolution failed -- no valid usageKey for ",
           "family Gadidae. Check network access / rgbif availability.")
    }

    .fallback_raw <- TaxaFetch::fetch_gbif_occurrences(
      keys       = .fallback_valid_keys,
      geometry   = .fallback_bbox,
      year_range = .fallback_years,
      limit      = .fallback_limit
    )

    .fallback_filtered <- .fallback_raw |>
      TaxaFetch::filter_gbif_quality(
        max_coord_uncertainty    = 500,
        max_coord_decimal_places = 2,
        require_species          = TRUE   # family-level query returns coarser ranks too
      )

    if (nrow(.fallback_filtered) == 0) {
      stop("No GBIF records survived quality filtering in the fallback fetch -- ",
           "widen .fallback_radius or .fallback_years.")
    }

    .fallback_occurrences <- TaxaFetch::stack_occurrences(.fallback_filtered)

    # KNOWN GAP: TaxaFetch::stack_occurrences() on unmodified GBIF columns
    # (species/genus/family/...) does not produce a taxon_name column -- every
    # TaxaExpect step below requires one (optimize_grid_size()'s default
    # species_col = "taxon_name"; prepare_model_dataframe() requires it
    # outright). Derive it via auto-detected rank columns before proceeding.
    if (!"taxon_name" %in% names(.fallback_occurrences)) {
      .fallback_occurrences <- TaxaTools::create_taxon_names(.fallback_occurrences)
    }

    # ---- Inline habitat tag -- TUTORIAL-ONLY SHORTCUT ------------------------
    # Family Gadidae is entirely marine fish, so a deterministic "Marine" tag
    # is defensible here. This is NOT a substitute for TaxaHabitat's real
    # LLM-based habitat classification pipeline (build_habitat_prompt() ->
    # prompt_api() -> parse_hierarchical_habitat_response() ->
    # assign_habitat_biological()) -- real workflows must run that pipeline.
    # We only need a plausible main_habitat column here to bootstrap enough
    # rows for this script's grid/model demo.
    occurrences_clean <- .fallback_occurrences |>
      dplyr::mutate(main_habitat = SITE_HABITAT)

    n_distinct_locs <- occurrences_clean |>
      dplyr::distinct(decimalLatitude, decimalLongitude) |>
      nrow()
    n_distinct_species <- dplyr::n_distinct(occurrences_clean$taxon_name)
    message(sprintf(
      "  Fallback fetch complete: %d occurrence record(s), %d distinct location(s), %d distinct species.",
      nrow(occurrences_clean), n_distinct_locs, n_distinct_species
    ))
    if (n_distinct_species < MIN_SPECIES_FOR_TUTORIAL) {
      warning(sprintf(
        "Fallback fetch returned only %d distinct species (< MIN_SPECIES_FOR_TUTORIAL = %d) -- ",
        n_distinct_species, MIN_SPECIES_FOR_TUTORIAL
      ), "the biodiversity model needs co-occurring species to estimate relative ",
      "abundance. Widen .fallback_taxa/.fallback_radius/.fallback_years above.",
      call. = FALSE)
    }
  }

} else {

  # ==========================================================================
  # >>> SWAP IN YOUR OWN DATA <<<
  # ==========================================================================
  # Replace the block above with your real occurrences_clean object:
  #
  #   occurrences_clean <- readRDS("path/to/your_occurrences_clean.rds")
  #     (the object produced by TaxaHabitat's assign_habitat_workflow.R --
  #     a tibble with point_id, decimalLatitude, decimalLongitude, taxon_name,
  #     main_habitat, and -- for broad-marker workflows -- sampling_group)
  #
  #   SITE_HABITAT <- "Marine"   # the focal habitat for this analysis
  #
  # Set DEBUG_MODE <- FALSE above and fill in the values here.
  # ==========================================================================
  stop("DEBUG_MODE is FALSE but no real occurrences_clean object has been ",
       "supplied. Edit the 'SWAP IN YOUR OWN DATA' block in this script.")
}

# Output location for checkpoint files (see explicit-checkpoint pattern below)
OUT_DIR    <- tempdir()
OUT_PREFIX <- "tutorial_gadus"

message(sprintf("NEEDS_SAMPLING_GROUP = %s -- %s", NEEDS_SAMPLING_GROUP,
                if (NEEDS_SAMPLING_GROUP)
                  "VARIANT B (per-sampling_group modelling) applies"
                else
                  "VARIANT A (single model across all species) applies"))

# ==============================================================================
# 1.  OPTIMIZE GRID SIZE
# ==============================================================================
# Scores candidate grid resolutions on coverage, quality, and stability;
# returns the best resolution plus a fallback level if minimum-data
# thresholds could not be met at any resolution tried.

message("\n--- Step 1: Optimizing grid size ---")

grid_opt <- TaxaExpect::optimize_grid_size(
  observation_data = occurrences_clean,
  n_covariates     = 2L    # lat_r, lon_r (Section 4's covariates)
)

message(sprintf("  best_grid = %.2f degrees (fallback_level = \"%s\")",
                grid_opt$best_grid, grid_opt$fallback_level))
message(grid_opt$explanation)
if (grid_opt$fallback_level != "none") {
  message("  NOTE: fallback_level != \"none\" -- minimum-data thresholds were ",
          "not met at every resolution tried. This is expected for a tutorial-",
          "sized dataset; real analyses should investigate before trusting ",
          "the recommended grid.")
}

# ---- Explicit checkpoint (not automatic) ------------------------------------
# Save now so a future session can skip Step 1 by pasting the readRDS() line
# below -- no file.exists()-gated auto-reload; you decide when to reuse this.
grid_opt_path <- file.path(OUT_DIR, paste0(OUT_PREFIX, "_grid_opt.rds"))
saveRDS(grid_opt, grid_opt_path)
message(sprintf("  Saved: %s", grid_opt_path))
message(sprintf("  To reuse without re-optimizing, paste:\n    grid_opt <- readRDS(\"%s\")",
                grid_opt_path))

# ==============================================================================
# 2.  SNAP OCCURRENCES TO GRID CELLS
# ==============================================================================

message("\n--- Step 2: Snapping occurrences to grid cells ---")

sites <- TaxaExpect::create_sites_from_grid(
  data      = occurrences_clean,
  grid_size = grid_opt$best_grid
)

message(sprintf("  %d occurrence row(s) assigned to %d distinct grid cell(s).",
                nrow(sites), length(unique(sites$grid_id))))

# ---- Explicit checkpoint ----------------------------------------------------
sites_path <- file.path(OUT_DIR, paste0(OUT_PREFIX, "_sites.rds"))
saveRDS(sites, sites_path)
message(sprintf("  Saved: %s", sites_path))
message(sprintf("  To reuse without re-gridding, paste:\n    sites <- readRDS(\"%s\")",
                sites_path))

# ==============================================================================
# 3.  MORAN BASIS -- SPATIAL AUTOCORRELATION COVARIATES
# ==============================================================================
# Two independent ways this can fail on sparse real data (both observed while
# testing this script on the tutorial's own genus-Gadus box): (1) k must be <
# the number of distinct grid cells -- a hardcoded k = 10L errors outright
# once optimize_grid_size() falls back to a coarse grid with few cells; (2)
# even a valid, smaller k can still fail with "no positive eigenvalues found"
# when the resulting cells don't form a well-connected spatial network -- a
# narrow-taxon/modest-radius query can produce exactly this, and there is no
# reliable cell-count threshold that predicts it in advance. Rather than
# chase more preconditions, treat compute_moran_basis() as best-effort:
# derive an adaptive k as a first pass, then wrap the actual call in
# tryCatch() and skip the Moran basis entirely on ANY failure. Step 5's
# formula already tolerates zero B columns (see the empty-.moran_terms case
# there), so skipping here degrades gracefully rather than halting the
# workflow -- mirroring how optimize_grid_size() already degrades gracefully
# via its own fallback levels for sparse data.

message("\n--- Step 3: Computing Moran eigenvector basis ---")

.n_grid_cells <- dplyr::n_distinct(sites$grid_id)
.moran_k      <- min(10L, .n_grid_cells - 1L)

.moran_basis <- if (.moran_k >= 1L) {
  tryCatch(
    TaxaExpect::compute_moran_basis(grid_ids = unique(sites$grid_id), k = .moran_k),
    error = function(e) {
      message(sprintf("  compute_moran_basis() failed (%s) -- skipping Moran basis.",
                      conditionMessage(e)))
      NULL
    }
  )
} else {
  NULL
}

if (!is.null(.moran_basis)) {
  sites <- dplyr::left_join(sites, .moran_basis, by = "grid_id")
  message(sprintf(
    "  Moran basis joined: %d MEM column(s) added (k = %d, adaptive to %d grid cell(s)).",
    sum(grepl("^B[0-9]+$", names(.moran_basis))), .moran_k, .n_grid_cells
  ))
} else {
  message(sprintf(
    "  No Moran eigenvector basis available for %d distinct grid cell(s). ",
    .n_grid_cells
  ))
  message("  Skipping spatial-autocorrelation terms; Step 5's formula will use ",
          "main_habitat/lat_r_s/lon_r_s terms only. This is expected when ",
          "optimize_grid_size() returns a coarse fallback grid (see Step 1's ",
          "fallback_level message) or when cells are too sparse to form a ",
          "connected spatial network.")
}

# ---- Explicit checkpoint ----------------------------------------------------
sites_with_basis_path <- file.path(OUT_DIR, paste0(OUT_PREFIX, "_sites_with_basis.rds"))
saveRDS(sites, sites_with_basis_path)
message(sprintf("  Saved: %s", sites_with_basis_path))
message(sprintf("  To reuse without re-computing the Moran basis, paste:\n    sites <- readRDS(\"%s\")",
                sites_with_basis_path))

# ==============================================================================
# 4.  PREPARE MODEL DATAFRAME
# ==============================================================================
# TWO VARIANTS -- activate one, comment out the other. VARIANT B only applies
# when TaxaHabitat's upstream NEEDS_SAMPLING_GROUP was TRUE (occurrences_clean
# carries a sampling_group column) -- broad-marker (18S/COI) workflows only.
# ==============================================================================

message("\n--- Step 4: Preparing model dataframe ---")

# --- VARIANT A: NARROW MARKER (single model across all species) -------------

model_data <- TaxaExpect::prepare_model_dataframe(
  data        = sites,
  covariates  = c("lat_r", "lon_r"),
  habitat_col = "main_habitat"
)
message(sprintf("  model_data: %d row(s) (taxon x site x habitat).", nrow(model_data)))

# --- END VARIANT A ------------------------------------------------------------


# --- VARIANT B: BROAD MARKER -- uncomment to activate -------------------------
# Replaces VARIANT A above (comment out VARIANT A when using this). Loops over
# each sampling_group, fits one model per group in Sections 5-7, and stacks
# the resulting priors via dplyr::bind_rows() at the end. Only relevant when
# NEEDS_SAMPLING_GROUP was TRUE upstream in TaxaHabitat.
#
# model_data_by_group <- unique(sites$sampling_group) |>
#   stats::setNames(unique(sites$sampling_group)) |>
#   lapply(function(grp) {
#     sites_grp <- dplyr::filter(sites, sampling_group == grp)
#     TaxaExpect::prepare_model_dataframe(
#       data        = sites_grp,
#       covariates  = c("lat_r", "lon_r"),
#       habitat_col = "main_habitat"
#     )
#   })
#
# for (grp in names(model_data_by_group)) {
#   message(sprintf("  sampling_group \"%s\": %d row(s).", grp, nrow(model_data_by_group[[grp]])))
# }
#
# # Sections 5-7 below would then loop over model_data_by_group, e.g.:
# #
# # priors_by_group <- lapply(names(model_data_by_group), function(grp) {
# #   mdf_grp <- model_data_by_group[[grp]]
# #   screened_grp <- TaxaExpect::screen_spatial_formula(mdf_grp, full_formula, effort_threshold = 10L)
# #   mod_grp       <- TaxaExpect::train_biodiversity_model(mdf_grp, screened_grp$model_selection$recommended_formula)
# #   undet_grp     <- TaxaExpect::generate_undetected_diversity(mod_grp, taxonomy = occurrences_clean)
# #   TaxaExpect::generate_full_priors(mod_grp, new_sites = mdf_grp, undetected = undet_grp)
# # })
# # taxaexpect_priors <- dplyr::bind_rows(priors_by_group)

# --- END VARIANT B -------------------------------------------------------------

# ---- Explicit checkpoint ----------------------------------------------------
model_data_path <- file.path(OUT_DIR, paste0(OUT_PREFIX, "_model_data.rds"))
saveRDS(model_data, model_data_path)
message(sprintf("  Saved: %s", model_data_path))
message(sprintf("  To reuse without re-preparing, paste:\n    model_data <- readRDS(\"%s\")",
                model_data_path))

# ==============================================================================
# 5.  SCREEN SPATIAL FORMULA FOR PARSIMONY
# ==============================================================================
# Fits the full spatial model, screens Moran/gradient slopes by VarCorr SD,
# and selects a parsimonious formula by AIC. Returns a biofreq_model object
# directly usable for Section 6, plus $model_selection diagnostics.

message("\n--- Step 5: Screening spatial formula ---")

# Both terms below are CONDITIONAL on what the actual data supports -- found
# by actually running this script against sparse/degenerate real data, not by
# reading alone. Assembled as a character vector and joined with " + " so
# omitted terms are structurally absent (c(if (FALSE) "x", "y") drops the
# omitted element entirely), rather than built via string paste0()/collapse
# tricks on possibly-empty pieces, which silently produced malformed terms
# (e.g. a literal "(0 + B | taxon_name)" referencing a nonexistent column "B"
# when zero Moran columns existed) in an earlier version of this script.

.n_moran_cols <- sum(grepl("^B[0-9]+$", names(model_data)))
.moran_terms  <- if (.n_moran_cols > 0L) {
  sprintf("(0 + B%d | taxon_name)", seq_len(min(10L, .n_moran_cols)))
} else {
  message("  0 Moran eigenvector columns in model_data -- omitting spatial-",
          "autocorrelation terms (see Step 3's message for why).")
  character(0)
}

# main_habitat requires >= 2 distinct values to be a fittable factor term (R's
# contrasts error on a single-level factor). This tutorial's live-fallback
# path tags every row with one hardcoded SITE_HABITAT value (a deliberate
# simplification -- see the "TUTORIAL-ONLY SHORTCUT" comment above), so a
# single-family query like Gadidae (all realistically "Marine") will hit this
# every time; a real multi-habitat community would not.
.n_habitat_levels <- dplyr::n_distinct(model_data$main_habitat)
.habitat_term <- if (.n_habitat_levels >= 2L) {
  "main_habitat"
} else {
  message(sprintf(
    "  Only %d distinct main_habitat value(s) in model_data -- omitting the ",
    .n_habitat_levels
  ), "main_habitat fixed effect (R cannot fit contrasts on a single-level ",
  "factor). Expected for this tutorial's single-family fallback data; a real ",
  "multi-habitat community survey would retain this term -- see TaxaExpect/",
  "CLAUDE.md's recommended formula.")
  character(0)
}

.rhs_terms <- c(
  .habitat_term,
  "(1 | taxon_name)",
  .moran_terms,
  "(0 + lat_r_s | taxon_name)",
  "(0 + lon_r_s | taxon_name)",
  "(1 | taxon_name:grid_id)"
)

full_formula <- stats::as.formula(
  paste("cbind(n_species, n_other) ~", paste(.rhs_terms, collapse = " + "))
)
message(sprintf("  Full formula: %s", deparse(full_formula)))

screened <- TaxaExpect::screen_spatial_formula(
  data          = model_data,
  formula_full  = full_formula,
  effort_threshold = 10L
)

# CONFIRMED BY ACTUALLY RUNNING THIS SCRIPT: screen_spatial_formula()'s docs
# (R/screen_spatial_formula.R, roxygen @return) state recommended_formula is
# Character, not a formula object -- passing it straight to
# train_biodiversity_model() in Step 6 errors ("'formula' must be a formula
# object"). Convert once here and reuse the converted object everywhere below.
recommended_formula <- stats::as.formula(screened$model_selection$recommended_formula)

message(sprintf("  Recommended formula: %s", deparse(recommended_formula)))

# ---- Explicit checkpoint ----------------------------------------------------
screened_path <- file.path(OUT_DIR, paste0(OUT_PREFIX, "_screened.rds"))
saveRDS(screened, screened_path)
message(sprintf("  Saved: %s", screened_path))
message(sprintf("  To reuse without re-screening, paste:\n    screened <- readRDS(\"%s\")",
                screened_path))

# ==============================================================================
# 6.  FIT THE FINAL BIODIVERSITY MODEL
# ==============================================================================
# screened is already a biofreq_model fit with the recommended formula, so
# this step is a deliberate, explicit re-fit using recommended_formula (the
# formula object converted above from screened$model_selection$
# recommended_formula's character output) -- keeps the "fit the final model"
# step visible as its own named object (mod) rather than silently reusing
# screened, matching this ecosystem's convention of one object per stage.

message("\n--- Step 6: Fitting final biodiversity model ---")

mod <- TaxaExpect::train_biodiversity_model(
  data    = model_data,
  formula = recommended_formula
)

print(mod)

# ---- Explicit checkpoint ----------------------------------------------------
mod_path <- file.path(OUT_DIR, paste0(OUT_PREFIX, "_mod.rds"))
saveRDS(mod, mod_path)
message(sprintf("  Saved: %s", mod_path))
message(sprintf("  To reuse without re-fitting, paste:\n    mod <- readRDS(\"%s\")",
                mod_path))

# ==============================================================================
# 7.  UNDETECTED DIVERSITY -- TIER 3 PROXY PRIORS
# ==============================================================================
# taxonomy = occurrences_clean (Session 117 fix): joins taxonomy columns onto
# singleton-mirror rows by taxon_name so that TaxaAssign::join_priors()'s
# hierarchical group priors can descend the taxonomy tree for singleton rows.
# Do not omit this argument.

message("\n--- Step 7: Generating undetected-diversity proxy priors ---")

priors_undetected <- TaxaExpect::generate_undetected_diversity(
  model_obj = mod,
  taxonomy  = occurrences_clean
)

message(sprintf("  %d proxy prior row(s) generated (singleton mirrors + global floor).",
                nrow(priors_undetected)))

# ---- Explicit checkpoint ----------------------------------------------------
priors_undetected_path <- file.path(OUT_DIR, paste0(OUT_PREFIX, "_priors_undetected.rds"))
saveRDS(priors_undetected, priors_undetected_path)
message(sprintf("  Saved: %s", priors_undetected_path))
message(sprintf("  To reuse without re-generating, paste:\n    priors_undetected <- readRDS(\"%s\")",
                priors_undetected_path))

# ==============================================================================
# 8.  DERIVE THE FOCAL SITE'S GRID_ID (DYNAMIC -- DO NOT HARDCODE)
# ==============================================================================
# KNOWN FOOTGUN: grid_id's format depends on the chosen grid resolution
# (Step 1's grid_opt$best_grid), which varies by dataset -- a hardcoded
# SITE_GRID_ID config constant breaks the moment grid_size changes. Instead,
# derive it as the most-frequent grid_id at the focal habitat -- from `sites`
# (Step 2/3's raw gridded occurrences), NOT model_data (see the note above
# new_sites_focal below for why model_data is the wrong object here).
# ==============================================================================

message("\n--- Step 8: Deriving focal SITE_GRID_ID dynamically ---")

SITE_GRID_ID <- sites |>
  dplyr::filter(main_habitat == SITE_HABITAT) |>
  dplyr::count(grid_id) |>
  dplyr::slice_max(n, n = 1, with_ties = FALSE) |>
  dplyr::pull(grid_id)

if (length(SITE_GRID_ID) == 0) {
  stop("No grid_id found for SITE_HABITAT = \"", SITE_HABITAT, "\" in sites. ",
       "Check that SITE_HABITAT matches a value actually present in main_habitat.")
}
message(sprintf("  SITE_GRID_ID = \"%s\" (most-frequent grid cell at habitat \"%s\").",
                SITE_GRID_ID, SITE_HABITAT))

# KNOWN FOOTGUN (distinct from the undetected-diversity one below): new_sites
# for generate_full_priors() must be SITE-level -- one row per grid_id x
# habitat combination, with NO taxon_name column. The function internally
# crosses each new_sites row against the model's FULL taxon set (see
# ?generate_full_priors: "Does NOT need taxon_name or count columns" and its
# message "Predicting N Tier 1 + M Tier 2 taxa at K site-habitat rows").
# model_data (Step 4's output) is already taxon-expanded -- one row PER TAXON
# per site-habitat, from prepare_model_dataframe(). Filtering model_data by
# grid_id and passing it as new_sites would pass one row per
# already-observed taxon at that site, and generate_full_priors() would cross
# EACH of those against the full taxon set again -- silently multiplying the
# output by however many taxa were originally observed at that grid cell.
# Use `sites` (Step 2/3's output; one row per raw occurrence, pre-aggregation)
# reduced to distinct site-habitat combinations instead.
.moran_cols <- grep("^B[0-9]+$", names(sites), value = TRUE)

new_sites_focal <- sites |>
  dplyr::filter(grid_id == SITE_GRID_ID) |>
  dplyr::distinct(grid_id, lat_r, lon_r, main_habitat,
                  dplyr::across(dplyr::all_of(.moran_cols)))

message(sprintf("  new_sites_focal: %d distinct site-habitat row(s) (not taxon-expanded).",
                nrow(new_sites_focal)))

# ==============================================================================
# 9.  GENERATE FULL PRIOR TABLE
# ==============================================================================
# undetected = priors_undetected is ALWAYS passed (never omitted): its
# singleton-mirror rows drive generate_full_priors()'s theta_epsilon
# auto-raise (Session 108), which keeps Tier 2 sparse-species priors above
# the dark-diversity floor computed downstream in TaxaAssign::join_priors().

message("\n--- Step 9: Generating full prior table ---")

taxaexpect_priors <- TaxaExpect::generate_full_priors(
  model_obj  = mod,
  new_sites  = new_sites_focal,
  undetected = priors_undetected
)

message(sprintf("  %d prior row(s) generated for SITE_GRID_ID = \"%s\".",
                nrow(taxaexpect_priors), SITE_GRID_ID))

# ---- KNOWN FOOTGUN: filter the undetected/global-floor rows by HABITAT ONLY,
# never by grid_id. generate_undetected_diversity()'s singleton-mirror rows
# carry the grid_id of wherever that singleton was ACTUALLY OBSERVED, not the
# focal site's grid_id -- a grid_id == SITE_GRID_ID filter would silently drop
# every singleton mirror (and the global-floor row, whose main_habitat is NA).
# taxaexpect_priors already reflects this correctly because generate_full_priors()
# appends `undetected` as-is (it does not re-filter by grid_id); the check
# below is a defensive sanity check, not a re-filter -- do not "fix" this by
# adding a grid_id filter here.
n_singleton_mirrors <- sum(taxaexpect_priors$undetected_type == "singleton_mirror",
                           na.rm = TRUE)
n_global_floor <- sum(taxaexpect_priors$undetected_type == "global_floor",
                      na.rm = TRUE)
message(sprintf(
  "  Sanity check -- undetected rows present: %d singleton_mirror, %d global_floor.",
  n_singleton_mirrors, n_global_floor
))
# CONFIRMED FALSE POSITIVE (found by actually running this script): the
# global-floor row is generated whenever undetected diversity runs at all --
# nrow(priors_undetected) > 0 does NOT imply singleton mirrors ever existed
# (generate_undetected_diversity() prints "no singletons found... only the
# global floor prior will be generated" when the training data simply has no
# species detected exactly once, which is a normal outcome, not a bug). Only
# warn when singleton mirrors existed in priors_undetected to begin with and
# then failed to survive into taxaexpect_priors -- that combination is the
# actual signature of the grid_id footgun recurring.
n_singleton_mirrors_upstream <- sum(priors_undetected$undetected_type == "singleton_mirror",
                                    na.rm = TRUE)
if (n_singleton_mirrors == 0 && n_singleton_mirrors_upstream > 0) {
  warning("priors_undetected had ", n_singleton_mirrors_upstream, " singleton_mirror ",
          "row(s), but none survived into taxaexpect_priors -- if you changed this ",
          "script to re-filter by grid_id anywhere downstream, that is almost ",
          "certainly the cause. Filter by main_habitat only (main_habitat == ",
          "SITE_HABITAT | is.na(main_habitat)), never by grid_id.")
}

# Example of the CORRECT downstream filter pattern (for TaxaAssign::join_priors()
# callers subsetting taxaexpect_priors themselves): habitat-only, OR NA main_habitat
# (the global-floor row has main_habitat = NA and must always be retained --
# see TaxaID/CLAUDE.md Session 108 changelog entry).
#
#   taxaexpect_priors |>
#     dplyr::filter(main_habitat == SITE_HABITAT | is.na(main_habitat))

# ---- Explicit checkpoint ----------------------------------------------------
taxaexpect_priors_path <- file.path(OUT_DIR, paste0(OUT_PREFIX, "_taxaexpect_priors.rds"))
saveRDS(taxaexpect_priors, taxaexpect_priors_path)
message(sprintf("  Saved: %s", taxaexpect_priors_path))
message(sprintf("  To reuse without re-running this workflow, paste:\n    taxaexpect_priors <- readRDS(\"%s\")",
                taxaexpect_priors_path))

# ---- Interactive exploration (run by hand -- NOT via source()) -------------
# plot_theta_map_interactive() opens a Shiny/leaflet gadget: a heatmap of
# theta_mean over the grid with occurrence points overlaid. @return NULL
# invisibly -- for exploration only, not part of the pipeline. Must be run
# interactively; uncomment and run this line yourself in the R console (not
# by sourcing this file):
#
#   TaxaExpect::plot_theta_map_interactive(
#     priors               = taxaexpect_priors,
#     occurrences          = occurrences_clean,
#     occurrence_habitat_col = "main_habitat",
#     tile                 = "Esri.OceanBasemap"
#   )

message("\nWorkflow complete.")
message("Next: pass taxaexpect_priors to TaxaAssign::join_priors() for posterior computation.")

# ==============================================================================
# Output
# ==============================================================================
# This workflow produces one primary object: taxaexpect_priors (a tibble).
# One row per taxon x site x habitat, plus Tier 3 undetected-diversity proxy
# rows (singleton mirrors + one global-floor row).
#
# Columns:
#   taxon_name             -- character; taxon identifier (NA for the
#                             global-floor undetected proxy row)
#   grid_id                -- character; spatial cell identifier
#   main_habitat            -- character; site-level habitat category (column
#                             name follows habitat_col used at training time;
#                             default "main_habitat"). NA for the global-floor
#                             row -- always retain NA rows in any downstream
#                             habitat filter (see Step 9's footgun note).
#   alpha                  -- numeric; Beta prior alpha parameter
#   beta                   -- numeric; Beta prior beta parameter
#   theta_mean             -- numeric; alpha / (alpha + beta)
#   theta_sd               -- numeric; SD of Beta(alpha, beta)
#   n_obs                  -- integer; n_total_at_site if supplied in
#                             new_sites, else NA
#   model_tier             -- character; "tier1", "tier2", or
#                             "tier3_undetected"
#   effort_flag            -- logical; TRUE if N < effort_threshold; NA if N
#                             not supplied
#   observed_in_habitat     -- logical; TRUE if taxon ever recorded in this
#                             habitat in training data
#   extrapolation_warning   -- logical; TRUE if any covariate |z| > 3 at this
#                             site
#   undetected_type         -- character; NA (modelled); "singleton_mirror";
#                             "global_floor"
#   jeffreys_fallback       -- logical; TRUE if Jeffreys Beta(0.5, 0.5) used
#   source_taxon_name       -- character; for singleton-mirror rows, the
#                             observed species the proxy was derived from
#                             (Session 117); NA for modelled rows and the
#                             global-floor row
#   (taxonomy columns)      -- genus/family/order/class/phylum, when present
#                             in occurrences_clean; joined onto singleton-
#                             mirror rows via generate_undetected_diversity(
#                             taxonomy = occurrences_clean); used by
#                             TaxaAssign::join_priors(singleton_taxonomy=) for
#                             hierarchical group priors
#
# Consumer: TaxaAssign, primarily join_priors(), which joins taxaexpect_priors
#   onto match/candidate data by taxon_name (with rank-expansion / hierarchical
#   group-prior fallback for unmodelled taxa) to compute posteriors.
# ==============================================================================
