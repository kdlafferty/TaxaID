# ==============================================================================
# WORKFLOW: CAMERA-TRAP MAMMAL POSTERIORS (TaxaAssign)
# ==============================================================================
# Purpose: Take the real image likelihood object already built by
#   TaxaMatch::score_image_workflow.R + TaxaLikely::image_acoustic_likelihood_
#   workflow.R (Session 124/128) and, for the FIRST time, feed it real
#   occurrence-based priors instead of stopping at the likelihood object (see
#   score_image_workflow.R's own header for why it stopped there originally).
#   Same real site (34.41 N / -119.86 W, Central California coastal scrub).
#   EXPANDED from an original 5-species/6-photo set to 8 species/52 photos --
#   Bobcat (Lynx rufus, Felidae), Coyote (Canis latrans, Canidae), Brush
#   Rabbit (Sylvilagus bachmani, Leporidae), Western Spotted Skunk (Spilogale
#   gracilis, Mephitidae), Striped Skunk (Mephitis mephitis, Mephitidae),
#   Raccoon (Procyon lotor, Procyonidae), California Ground Squirrel
#   (Otospermophilus beecheyi, Sciuridae), Virginia Opossum (Didelphis
#   virginiana, Didelphidae) -- to get enough replicate photos per species to
#   move past the original n=6 result.
#
# THIS IS A NEW REAL-SPECIES RUN THROUGH EXISTING, ALREADY-TESTED MACHINERY --
# not new TaxaAssign/TaxaExpect/TaxaHabitat code. Every function call below
# already exists and is already exercised by the five-package Gadus/GBIF chain
# and by TaxaMatch/TaxaLikely's own image tutorial.
#
# RESOLVED (Session 129), superseding the original open question: at n=6,
# ecosystem_docs/REENTRY_PROMPT_session128... found correct_training_bias()
# at tau=1.0 flipped this exact photo set's brush rabbit call wrong
# (Sylvilagus bachmani -> Megascops kennicottii, a screech owl). Expanding to
# 51-52 photos surfaced two real, unrelated bugs (iNaturalist returning
# off-scope plant/bird candidates a mammal study can never actually be;
# `assign_scores()` forcing iNaturalist's unbounded `combined_score` through
# a fixed 0-100 divisor, collapsing likelihoods to near-uniform independent
# of tau) -- both now fixed (see score_image_workflow.R's TARGET_ICONIC_TAXA
# filter and TaxaLikely::assign_scores()'s score-scale auto-detection). Once
# fixed, jointly calibrating tau and score_sharpness by log-loss on real,
# clean data (TaxaLikely/inst/workflows/calibrate_training_bias_tau.R) gave
# an unambiguous, monotonic answer: tau=0/score_sharpness=10 clearly beats
# the old tau=1/sharpness=0.1 default on both log-loss and accuracy (82% vs
# 63%). CONFIG's CALIBRATED_TAU/CALIBRATED_SCORE_SHARPNESS below use that
# result; Section 5 still builds the old-default object too, purely so
# Section 7's comparison shows the resolution concretely rather than
# asserting it.
#
# STATUS: run and working end-to-end at both n=6 and the current n=51/52,
# 8-species set, with the calibrated (not old-default) parameters as the
# primary result. Follows the ecosystem's own explicit-checkpoint convention
# (tempdir(), OUT_PREFIX) so any step can be skipped on a subsequent run by
# pasting the readRDS() line it prints. tempdir() is scoped to ONE R session
# -- if TaxaMatch's/TaxaLikely's raw checkpoint from an earlier session is
# not present, Section 1 regenerates it by sourcing TaxaMatch::
# score_image_workflow.R directly (a real, live iNaturalist CV API call --
# requires INAT_API_TOKEN).
# ==============================================================================

# --- Namespaces used in this script (loaded, never attached) ----------------
# TaxaMatch::, TaxaLikely::, TaxaHabitat::, TaxaFetch::, TaxaExpect::,
# TaxaAssign::, TaxaTools::, dplyr::, tibble::

# ==============================================================================
# CONFIG
# ==============================================================================

SITE_LAT <- 34.41
SITE_LNG <- -119.86

# The package's default 3-category scheme (Marine/Freshwater/Terrestrial) --
# every one of these 8 species is expected to classify Terrestrial. Not
# hardcoded blindly: Section 2 runs the real LLM classification and this
# constant is only used to pick the focal grid cell/habitat afterward (Step 8
# pattern from generate_priors_workflow.R) -- if the LLM disagrees, that will
# surface as a mismatch when SITE_GRID_ID lookup fails, not be silently masked.
SITE_HABITAT <- "Terrestrial"

# Real species list -- exactly the 8 species score_image_workflow.R scores
# (expanded from an original 5-species/6-photo set to get enough replicate
# photos per species to move past a small-n result -- see that script's own
# header for the per-species photo counts).
CAMERA_SPECIES <- tibble::tibble(
  species = c("Lynx rufus", "Canis latrans", "Sylvilagus bachmani",
              "Spilogale gracilis", "Mephitis mephitis",
              "Procyon lotor", "Otospermophilus beecheyi", "Didelphis virginiana"),
  genus   = c("Lynx", "Canis", "Sylvilagus", "Spilogale", "Mephitis",
              "Procyon", "Otospermophilus", "Didelphis"),
  family  = c("Felidae", "Canidae", "Leporidae", "Mephitidae", "Mephitidae",
              "Procyonidae", "Sciuridae", "Didelphidae")
)

RANK_SYSTEM <- c("family", "genus", "species")

# Empirically calibrated on this exact real 51-photo image dataset (8
# species, taxonomic-scope-filtered) via TaxaLikely::correct_training_bias()
# + assign_scores() log-loss minimization -- see TaxaLikely/inst/workflows/
# calibrate_training_bias_tau.R and TaxaLikely/CLAUDE.md's Session 129 note.
# tau = 0 (no correction) and score_sharpness = 10 (vs the package default
# 0.1) both clearly beat the old tau = 1.0/sharpness = 0.1 combination on
# log-loss AND accuracy (82% vs 63%), monotonically across the tau range --
# not a close call. The continuous optimum was tau = 0.085, sharpness =
# 15.24 (nearly identical accuracy); tau = 0/sharpness = 10 is used here as
# the more interpretable, still near-optimal choice. Re-calibrate if this
# photo set changes meaningfully (more photos, new species) -- these are
# NOT assumed to transfer to other data types (acoustic needs its own run).
CALIBRATED_TAU             <- 0
CALIBRATED_SCORE_SHARPNESS <- 10

# GBIF fetch box for real occurrence-based priors. 3-degree radius matches the
# real PtConceptionWorkflow_12S.R production convention (a similarly-sized
# real study); these are common, wide-ranging North American mammals, so this
# should return plenty of location + count breadth for optimize_grid_size()'s
# real thresholds (min_distinct_locs = 20 default) without becoming a
# multi-thousand-key bulk download.
FETCH_RADIUS_DEG <- 3.0
FETCH_YEAR_RANGE <- "2000,2024"
FETCH_LIMIT      <- 5000L

OUT_DIR    <- tempdir()
OUT_PREFIX <- "camtrap"

# ==============================================================================
# 1.  LOAD (OR REGENERATE) THE RAW TaxaMatch CHECKPOINT
# ==============================================================================
# Deliberately loads the RAW (pre-correction) checkpoint, not TaxaLikely's
# already-corrected one -- Section 5 below builds BOTH the calibrated and
# old-default likelihood objects from this single raw starting point, mirroring
# exactly what image_acoustic_likelihood_workflow.R Section 1 already does
# in-memory for its own honesty check.
# ==============================================================================

message("\n--- Step 1: Loading (or regenerating) TaxaMatch's raw image checkpoint ---")

RAW_CHECKPOINT_PATH <- file.path(tempdir(), "tutorial_camtrap_taxamatch_image_match_obj.rds")

if (!file.exists(RAW_CHECKPOINT_PATH)) {
  message("  Raw checkpoint not found -- sourcing TaxaMatch::score_image_workflow.R ",
          "to regenerate it (LIVE iNaturalist CV API call; requires INAT_API_TOKEN).")
  .score_image_script <- system.file(
    "workflows", "score_image_workflow.R", package = "TaxaMatch"
  )
  if (!nzchar(.score_image_script)) {
    stop("Could not locate score_image_workflow.R in the installed TaxaMatch ",
         "package. Run devtools::install() on TaxaMatch first.")
  }
  source(.score_image_script)
}

taxamatch_image_match_obj <- readRDS(RAW_CHECKPOINT_PATH)
message(sprintf("  Loaded: %s (%d row(s), %d photo(s)).",
                RAW_CHECKPOINT_PATH, nrow(taxamatch_image_match_obj),
                length(unique(taxamatch_image_match_obj$observation_id))))

# ==============================================================================
# 2.  REAL HABITAT CLASSIFICATION (TaxaHabitat) -- NOT the "Marine" tutorial
#     shortcut. This camera-trap set is terrestrial, and a real workflow must
#     run the actual LLM classification chain rather than hardcode main_habitat.
# ==============================================================================
# Requires ANTHROPIC_API_KEY (or getOption("TaxaID.llm_fn")) -- real network
# call. llm_fn passed EXPLICITLY per TaxaID/CLAUDE.md's .resolve_llm_fn()
# footgun (fully-namespaced TaxaTools::prompt_api() calls never trigger
# TaxaTools::.onAttach()'s auto-detection).
# ==============================================================================

message("\n--- Step 2: Classifying species habitat via TaxaHabitat (real LLM call) ---")

habitat_prompt <- TaxaHabitat::build_habitat_prompt(
  taxon_list     = CAMERA_SPECIES$species,
  habitat_scheme = NULL   # package default: Marine / Freshwater / Terrestrial
)

llm_response <- TaxaTools::prompt_api(
  habitat_prompt,
  llm_fn = getOption("TaxaID.llm_fn", TaxaTools::call_anthropic_api)
)

habitat_weights <- TaxaHabitat::parse_hierarchical_habitat_response(
  raw_text       = llm_response,
  taxon_list     = habitat_prompt$taxa,
  habitat_scheme = habitat_prompt
)

message("  Species x habitat weight table:")
print(habitat_weights)

habitat_weights_path <- file.path(OUT_DIR, paste0(OUT_PREFIX, "_habitat_weights.rds"))
saveRDS(habitat_weights, habitat_weights_path)
message(sprintf("  Saved: %s", habitat_weights_path))

# ==============================================================================
# 3.  REAL GBIF OCCURRENCES FOR THE 5 SPECIES NEAR THE REAL SITE
# ==============================================================================

message("\n--- Step 3: Fetching real GBIF occurrences (8 species, 3-degree box) ---")

bbox <- TaxaFetch::make_bbox_wkt(
  lat = SITE_LAT, lon = SITE_LNG, radius_deg = FETCH_RADIUS_DEG
)

keys <- TaxaFetch::get_keys_from_context(CAMERA_SPECIES)
valid_keys <- keys$usageKey[!is.na(keys$usageKey)]
if (length(valid_keys) == 0) {
  stop("No valid GBIF usageKey resolved for any of the 8 camera-trap species -- ",
       "check network access / rgbif availability.")
}
message(sprintf("  Resolved %d/%d species to a valid GBIF usageKey.",
                length(valid_keys), nrow(CAMERA_SPECIES)))

raw_occ <- TaxaFetch::fetch_gbif_occurrences(
  keys       = valid_keys,
  geometry   = bbox,
  year_range = FETCH_YEAR_RANGE,
  limit      = FETCH_LIMIT
)

filtered_occ <- TaxaFetch::filter_gbif_quality(
  raw_occ,
  max_coord_uncertainty    = 500,
  max_coord_decimal_places = 2,
  require_species          = TRUE
)
if (nrow(filtered_occ) == 0) {
  stop("No GBIF records survived quality filtering -- widen FETCH_RADIUS_DEG ",
       "or FETCH_YEAR_RANGE.")
}

all_occurrences <- TaxaFetch::stack_occurrences(filtered_occ)
all_occurrences <- TaxaFetch::dedupe_occurrences(all_occurrences)
if (!"taxon_name" %in% names(all_occurrences)) {
  all_occurrences <- TaxaTools::create_taxon_names(all_occurrences)
}

n_locs    <- dplyr::n_distinct(all_occurrences$decimalLatitude, all_occurrences$decimalLongitude)
n_species <- dplyr::n_distinct(all_occurrences$taxon_name)
message(sprintf("  %d occurrence record(s), %d distinct location(s), %d distinct species.",
                nrow(all_occurrences), n_locs, n_species))

all_occurrences_path <- file.path(OUT_DIR, paste0(OUT_PREFIX, "_all_occurrences.rds"))
saveRDS(all_occurrences, all_occurrences_path)
message(sprintf("  Saved: %s", all_occurrences_path))

# ---- Join habitat weights onto occurrence points, then spatial QAQC --------
# Mirrors TaxaHabitat::assign_habitat_workflow.R Steps 4-6 exactly.

occurrences_with_habitat <- TaxaHabitat::assign_habitat_biological(
  data         = all_occurrences,
  habitats_df  = habitat_weights,
  point_id_col = "point_id",
  taxon_col    = "taxon_name",
  threshold    = 0.5
)

occurrences_flagged <- TaxaHabitat::flag_habitat_inconsistencies(
  occurrences_with_habitat,
  habitat_col = "main_habitat"
)

occurrences_clean <- dplyr::filter(occurrences_flagged, spatial_flag == "likely")
message(sprintf("  %d of %d occurrence row(s) retained (spatial_flag == \"likely\").",
                nrow(occurrences_clean), nrow(occurrences_flagged)))
message("  For a real analysis, review \"questionable\" points interactively via ",
        "TaxaHabitat::review_spatial_flags() instead of dropping them here.")

occurrences_clean_path <- file.path(OUT_DIR, paste0(OUT_PREFIX, "_occurrences_clean.rds"))
saveRDS(occurrences_clean, occurrences_clean_path)
message(sprintf("  Saved: %s", occurrences_clean_path))

# ==============================================================================
# 4.  TaxaExpect: GRID, MODEL, AND GENERATE REAL PRIORS
# ==============================================================================
# Exact same call sequence as TaxaExpect::generate_priors_workflow.R Sections
# 1-9 (grid optimize -> snap -> Moran basis -> prepare model df -> screen
# formula -> fit -> undetected diversity -> derive focal site -> full priors),
# applied to occurrences_clean from Step 3 instead of the Gadus tutorial data.
# ==============================================================================

message("\n--- Step 4: TaxaExpect prior pipeline ---")

grid_opt <- TaxaExpect::optimize_grid_size(
  observation_data = occurrences_clean,
  n_covariates     = 2L
)
message(sprintf("  best_grid = %.2f degrees (fallback_level = \"%s\")",
                grid_opt$best_grid, grid_opt$fallback_level))

sites <- TaxaExpect::create_sites_from_grid(
  data      = occurrences_clean,
  grid_size = grid_opt$best_grid
)
message(sprintf("  %d row(s) assigned to %d distinct grid cell(s).",
                nrow(sites), length(unique(sites$grid_id))))

.n_grid_cells <- dplyr::n_distinct(sites$grid_id)
.moran_k      <- min(10L, .n_grid_cells - 1L)
.moran_basis  <- if (.moran_k >= 1L) {
  tryCatch(
    TaxaExpect::compute_moran_basis(grid_ids = unique(sites$grid_id), k = .moran_k),
    error = function(e) {
      message(sprintf("  compute_moran_basis() failed (%s) -- skipping.",
                      conditionMessage(e)))
      NULL
    }
  )
} else NULL

if (!is.null(.moran_basis)) {
  sites <- dplyr::left_join(sites, .moran_basis, by = "grid_id")
  message(sprintf("  Moran basis joined: %d MEM column(s) (k = %d).",
                  sum(grepl("^B[0-9]+$", names(.moran_basis))), .moran_k))
} else {
  message("  No Moran eigenvector basis available -- omitting spatial-",
          "autocorrelation terms from the formula below.")
}

model_data <- TaxaExpect::prepare_model_dataframe(
  data        = sites,
  covariates  = c("lat_r", "lon_r"),
  habitat_col = "main_habitat"
)
message(sprintf("  model_data: %d row(s) (taxon x site x habitat).", nrow(model_data)))

.n_moran_cols <- sum(grepl("^B[0-9]+$", names(model_data)))
.moran_terms  <- if (.n_moran_cols > 0L) {
  sprintf("(0 + B%d | taxon_name)", seq_len(min(10L, .n_moran_cols)))
} else character(0)

.n_habitat_levels <- dplyr::n_distinct(model_data$main_habitat)
.habitat_term <- if (.n_habitat_levels >= 2L) "main_habitat" else {
  message(sprintf("  Only %d distinct main_habitat value(s) -- omitting the ",
                  .n_habitat_levels), "main_habitat fixed effect.")
  character(0)
}

.rhs_terms <- c(
  .habitat_term, "(1 | taxon_name)", .moran_terms,
  "(0 + lat_r_s | taxon_name)", "(0 + lon_r_s | taxon_name)",
  "(1 | taxon_name:grid_id)"
)
full_formula <- stats::as.formula(
  paste("cbind(n_species, n_other) ~", paste(.rhs_terms, collapse = " + "))
)
message(sprintf("  Full formula: %s", deparse(full_formula)))

screened <- TaxaExpect::screen_spatial_formula(
  data             = model_data,
  formula_full     = full_formula,
  effort_threshold = 10L
)
recommended_formula <- stats::as.formula(screened$model_selection$recommended_formula)
message(sprintf("  Recommended formula: %s", deparse(recommended_formula)))

mod <- TaxaExpect::train_biodiversity_model(
  data    = model_data,
  formula = recommended_formula
)
print(mod)

priors_undetected <- TaxaExpect::generate_undetected_diversity(
  model_obj = mod,
  taxonomy  = occurrences_clean
)
message(sprintf("  %d proxy prior row(s) (singleton mirrors + global floor).",
                nrow(priors_undetected)))

# ---- Derive focal SITE_GRID_ID dynamically (NEVER hardcode -- grid_id format
# depends on grid_opt$best_grid, which varies run to run).
SITE_GRID_ID <- sites |>
  dplyr::filter(main_habitat == SITE_HABITAT) |>
  dplyr::count(grid_id) |>
  dplyr::slice_max(n, n = 1, with_ties = FALSE) |>
  dplyr::pull(grid_id)

if (length(SITE_GRID_ID) == 0) {
  stop("No grid_id found for SITE_HABITAT = \"", SITE_HABITAT, "\" in sites. ",
       "Check Step 2's habitat_weights -- did the LLM classify these species ",
       "as something other than \"Terrestrial\"? If so, update SITE_HABITAT ",
       "in CONFIG to match.")
}
message(sprintf("  SITE_GRID_ID = \"%s\".", SITE_GRID_ID))

.moran_cols <- grep("^B[0-9]+$", names(sites), value = TRUE)
new_sites_focal <- sites |>
  dplyr::filter(grid_id == SITE_GRID_ID) |>
  dplyr::distinct(grid_id, lat_r, lon_r, main_habitat,
                  dplyr::across(dplyr::all_of(.moran_cols)))

taxaexpect_priors <- TaxaExpect::generate_full_priors(
  model_obj  = mod,
  new_sites  = new_sites_focal,
  undetected = priors_undetected
)
message(sprintf("  %d prior row(s) generated for SITE_GRID_ID = \"%s\".",
                nrow(taxaexpect_priors), SITE_GRID_ID))

# REQUIRED: generate_full_priors() does not add taxon_name_rank, but
# join_priors() requires it (see TaxaExpect/TaxaAssign CLAUDE.md, and the
# same one-liner in compute_posteriors_workflow.R).
taxaexpect_priors$taxon_name_rank <- ifelse(
  is.na(taxaexpect_priors$taxon_name), NA_character_, "species"
)

taxaexpect_priors_path <- file.path(OUT_DIR, paste0(OUT_PREFIX, "_taxaexpect_priors.rds"))
saveRDS(taxaexpect_priors, taxaexpect_priors_path)
message(sprintf("  Saved: %s", taxaexpect_priors_path))

# ==============================================================================
# 5.  BUILD BOTH LIKELIHOOD OBJECTS -- CALIBRATED AND OLD DEFAULT
# ==============================================================================
# Same unreferenced_candidates() -> assign_scores() pathway
# image_acoustic_likelihood_workflow.R Section 1 uses, run twice from the same
# raw taxamatch_image_match_obj: once with the CALIBRATED (tau, score_
# sharpness) from CONFIG above, once with the OLD Session 127 theoretical
# default (tau = 1.0, score_sharpness = 0.1) kept only for comparison --
# it is now a known-worse choice on this data, not a live candidate.
# likelihoods_calibrated is the one that should feed real analysis;
# likelihoods_old_default exists so the comparison in Step 7 below still
# shows concretely how much the calibration changed the final answer.
# ==============================================================================

message("\n--- Step 5: Building calibrated and old-default likelihood objects ---")

calibrated_match_obj <- TaxaLikely::correct_training_bias(
  taxamatch_image_match_obj, count_col = "n_observations", tau = CALIBRATED_TAU
)
calibrated_hyp <- TaxaLikely::unreferenced_candidates(
  calibrated_match_obj, rank_system = RANK_SYSTEM
)
likelihoods_calibrated <- TaxaLikely::assign_scores(
  calibrated_hyp, score_type = "similarity_softmax",
  score_sharpness = CALIBRATED_SCORE_SHARPNESS
)

old_default_match_obj <- TaxaLikely::correct_training_bias(
  taxamatch_image_match_obj, count_col = "n_observations", tau = 1.0
)
old_default_hyp <- TaxaLikely::unreferenced_candidates(
  old_default_match_obj, rank_system = RANK_SYSTEM
)
likelihoods_old_default <- TaxaLikely::assign_scores(
  old_default_hyp, score_type = "similarity_softmax", score_sharpness = 0.1
)

# compute_posterior() requires score_likelihood_mean/score_likelihood_sd --
# this pathway (pre-trained classifier, no Monte Carlo model fit) has no
# uncertainty estimate to propagate, so these are point estimates with sd = 0
# (NOT NA -- compute_posterior() replaces NA sd with 0 anyway but also warns;
# setting it explicitly here documents the choice instead of relying on that
# fallback).
likelihoods_calibrated$score_likelihood_mean  <- likelihoods_calibrated$score_likelihood
likelihoods_calibrated$score_likelihood_sd    <- 0
likelihoods_old_default$score_likelihood_mean <- likelihoods_old_default$score_likelihood
likelihoods_old_default$score_likelihood_sd   <- 0

message(sprintf("  likelihoods_calibrated:  %d row(s), %d photo(s).",
                nrow(likelihoods_calibrated),
                dplyr::n_distinct(likelihoods_calibrated$observation_id)))
message(sprintf("  likelihoods_old_default: %d row(s), %d photo(s).",
                nrow(likelihoods_old_default),
                dplyr::n_distinct(likelihoods_old_default$observation_id)))

saveRDS(likelihoods_calibrated,
        file.path(OUT_DIR, paste0(OUT_PREFIX, "_likelihoods_calibrated.rds")))
saveRDS(likelihoods_old_default,
        file.path(OUT_DIR, paste0(OUT_PREFIX, "_likelihoods_old_default.rds")))

# ==============================================================================
# 6.  JOIN PRIORS -> COMPUTE POSTERIOR -> CONSENSUS -> SLASH TAXON, TWICE
# ==============================================================================

.run_bayesian_chain <- function(likelihoods, label) {
  message(sprintf("\n--- Step 6 [%s]: join_priors -> compute_posterior -> consensus ---", label))

  taxonomy_lookup <- likelihoods |>
    dplyr::distinct(taxon_name, taxon_name_rank, genus, family)

  likelihoods_w_prior <- TaxaAssign::join_priors(
    likelihoods       = likelihoods,
    taxaexpect_priors = taxaexpect_priors,
    site              = list(grid_id = SITE_GRID_ID, main_habitat = SITE_HABITAT),
    taxonomy_lookup   = taxonomy_lookup,
    rank_system       = RANK_SYSTEM,
    backbone_id       = 11L  # GBIF; match whichever backbone your input taxonomy used
  )

  posterior_df <- TaxaAssign::compute_posterior(
    likelihood_w_prior = likelihoods_w_prior,
    n_sims             = 1000
  )

  consensus_df <- TaxaAssign::posterior_consensus(
    posterior_df = posterior_df,
    rank_system  = RANK_SYSTEM
  )

  taxaassign_consensus <- TaxaAssign::add_slash_taxon(consensus_df)

  message(sprintf("  [%s] %d consensus row(s); %d resolved.",
                  label, nrow(taxaassign_consensus),
                  sum(taxaassign_consensus$is_resolved, na.rm = TRUE)))

  taxaassign_consensus
}

consensus_calibrated  <- .run_bayesian_chain(likelihoods_calibrated,  "CALIBRATED")
consensus_old_default <- .run_bayesian_chain(likelihoods_old_default, "OLD_DEFAULT")

saveRDS(consensus_calibrated,
        file.path(OUT_DIR, paste0(OUT_PREFIX, "_consensus_calibrated.rds")))
saveRDS(consensus_old_default,
        file.path(OUT_DIR, paste0(OUT_PREFIX, "_consensus_old_default.rds")))

# ==============================================================================
# 7.  COMPARE -- HOW MUCH DID CALIBRATION ACTUALLY CHANGE THE FINAL POSTERIOR?
# ==============================================================================
# The open question ecosystem_docs/REENTRY_PROMPT_session128... originally
# posed (does a real prior recover a likelihood-stage flip?) is now resolved
# -- see TaxaLikely/CLAUDE.md's Session 129 note: tau=0/score_sharpness=10
# clearly beats the old tau=1/sharpness=0.1 default on this real image data,
# monotonically, on both log-loss and accuracy. This comparison is kept as a
# concrete before/after record of that resolution, not an open experiment.
# Ground truth carried through from TaxaMatch's checkpoint's own honesty-
# check column.
# ==============================================================================

message("\n--- Step 7: Calibrated vs. old-default posterior comparison ---")

# Ground truth derived from taxamatch_image_match_obj$true_species (Step 1's
# checkpoint) rather than a second hardcoded list here -- score_image_
# workflow.R already derives this from each photo's folder_1 subfolder name
# (filenames are camera-generated sequence numbers, not species identifiers,
# now that photos are organized into per-species subfolders). One row per
# observation_id x true_species is enough; posterior_consensus() does not
# carry true_species through itself.
TRUE_SPECIES <- taxamatch_image_match_obj |>
  dplyr::distinct(observation_id, true_species) |>
  tibble::deframe()

comparison <- dplyr::full_join(
  consensus_calibrated  |> dplyr::select(observation_id,
                                          consensus_taxon_calibrated   = consensus_taxon,
                                          primary_taxon_calibrated     = primary_taxon,
                                          consensus_posterior_calibrated = consensus_posterior),
  consensus_old_default |> dplyr::select(observation_id,
                                          consensus_taxon_old_default   = consensus_taxon,
                                          primary_taxon_old_default   = primary_taxon,
                                          consensus_posterior_old_default = consensus_posterior),
  by = "observation_id"
) |>
  dplyr::mutate(
    true_species = TRUE_SPECIES[observation_id],
    calibrated_correct  = primary_taxon_calibrated  == true_species,
    old_default_correct = primary_taxon_old_default == true_species,
    calibration_changed_it = calibrated_correct != old_default_correct
  )

print(comparison)

message(sprintf(
  "\n  Top-consensus accuracy WITH real priors -- calibrated: %d/%d, old default: %d/%d.",
  sum(comparison$calibrated_correct, na.rm = TRUE), nrow(comparison),
  sum(comparison$old_default_correct, na.rm = TRUE), nrow(comparison)
))

.rabbit_row <- dplyr::filter(comparison, true_species == "Sylvilagus bachmani")
if (nrow(.rabbit_row) > 0) {
  message("\n  Brush rabbit photo(s) specifically (the original Session 128 flip case):")
  print(.rabbit_row)
}

message("\nWorkflow complete -- consensus_calibrated is the recommended result;",
        " consensus_old_default is kept only for comparison.")

# ==============================================================================
# Output
# ==============================================================================
# Two parallel taxaassign_consensus-shaped objects (see TaxaAssign::add_slash_
# taxon() docs for the full column contract): consensus_calibrated (the
# recommended result, tau=0/score_sharpness=10) and consensus_old_default
# (tau=1/score_sharpness=0.1, kept for comparison only). `comparison`
# (Section 7) puts them side by side against TRUE_SPECIES ground truth, with a
# `calibration_changed_it` flag marking any observation where the two
# parameter choices disagree on the final answer once real priors are applied.
# ==============================================================================
