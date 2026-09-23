# ==============================================================================
# WORKFLOW: BUILD OCCURRENCE-BASED PRIORS (TaxaExpect)
# ==============================================================================
# Purpose: Calibrate the kernel bandwidth, estimate site-centered kernel
#   priors, add dark-diversity rows for species never locally recorded, and
#   assemble the prior table TaxaAssign consumes. This is the README's own
#   Quick Start (calibrate_kernel_bandwidth() -> estimate_kernel_priors() ->
#   generate_undetected_diversity() -> bind_rows() -> plot_theta_surface()),
#   run end to end as an executable script rather than left as prose.
#
# Audience: someone learning TaxaExpect's kernel pathway step by step,
#   continuing directly from TaxaHabitat's assign_habitat_workflow.R. With
#   DEBUG_MODE = TRUE (the default) this script loads that script's
#   occurrences_clean checkpoint (Gadus + Pollachius, North Atlantic tutorial
#   run, same site TaxaFetch's own tutorial used) -- no separate example
#   dataset.
#
# NOTE ON INPUT: estimate_kernel_priors()/calibrate_kernel_bandwidth() both
#   require a habitat column (habitat_col = "main_habitat" by default,
#   REQUIRED, not optional -- see either function's own validation). That
#   only exists on TaxaHabitat's occurrences_clean output, not TaxaFetch's
#   own all_occurrences checkpoint (raw GBIF columns, no habitat), so this
#   script reads occurrences_clean, one step further down the tutorial chain
#   than all_occurrences.
#
# Output: taxaexpect_priors -- see the "Output" block at the end of this file
#   for the full column contract passed to TaxaAssign.
# ==============================================================================

# --- Namespaces used in this script (loaded, never attached) ----------------
# TaxaExpect::, dplyr::

# ==============================================================================
# CONFIG
# ==============================================================================
# Parameters are grouped here so this script's body can become a wrapper
# function's implementation with minimal changes -- each CONFIG value maps to
# a future function argument.

# DEBUG_MODE = TRUE  -> load TaxaHabitat's tutorial checkpoint (Gadus +
#                       Pollachius, North Atlantic) if present, else stop --
#                       there is no
#                       sensible fallback for a spatial prior model, unlike
#                       TaxaHabitat's own tiny 3-row inline fallback.
# DEBUG_MODE = FALSE -> plug in your own habitat-labelled occurrence table
#                       (see the "SWAP IN YOUR OWN DATA" block below)
DEBUG_MODE <- TRUE

# Same site TaxaFetch's own tutorial fetched around (fetch_occurrences_
# workflow.R: STUDY_LAT/STUDY_LON, North Sea/Norwegian Sea).
SITE_LAT <- 60.0
SITE_LON <- 2.0

# Leave-one-block-out calibration grid. block_size_deg/min_block_records are
# lowered from calibrate_kernel_bandwidth()'s own defaults (0.5 deg / 20
# records) -- this tutorial's ~85-record Gadus/Pollachius fetch, spread
# across a 4-deg search box, cannot form 3 default-sized blocks with 20
# records apiece; fewer, larger blocks with a lower per-block floor is the
# same tradeoff a small real dataset would need, not a tutorial-only
# shortcut.
LAMBDA_GRID <- c(25, 50, 100, 200, 400) # km
BLOCK_SIZE_DEG <- 2.0
MIN_BLOCK_RECORDS <- 5L

if (DEBUG_MODE) {
  # ---- Tutorial example: continue from TaxaHabitat's Gadus checkpoint -------
  # This is the exact readRDS() line documented in assign_habitat_workflow.R's
  # Output block. If that script was never run (or tempdir() was cleared
  # since), there is nothing meaningful to demonstrate -- a spatial prior
  # model needs real occurrence spread, not a 3-row inline stand-in.
  .habitat_checkpoint <- file.path(tempdir(), "tutorial_gadus_occurrences_clean.rds")

  if (!file.exists(.habitat_checkpoint)) {
    stop(
      "DEBUG_MODE = TRUE but TaxaHabitat's checkpoint was not found at ",
      .habitat_checkpoint, ". Run TaxaHabitat's assign_habitat_workflow.R ",
      "first (in the SAME R session if tempdir() has not been reused -- ",
      "tempdir() is scoped to one R session, exactly as documented for the ",
      "five-package Gadus chain)."
    )
  }

  occurrences <- readRDS(.habitat_checkpoint)
  message(
    "DEBUG_MODE = TRUE -- loaded TaxaHabitat's checkpoint: ", .habitat_checkpoint,
    " (", nrow(occurrences), " row(s))."
  )

  SITE_HABITAT <- unique(stats::na.omit(occurrences$main_habitat))
  if (length(SITE_HABITAT) != 1L) {
    stop(
      "Expected exactly one main_habitat in occurrences_clean (this ",
      "tutorial fetch's taxa are all Marine), but found ",
      length(SITE_HABITAT), ": ", paste(SITE_HABITAT, collapse = ", "),
      ". Check the upstream TaxaHabitat checkpoint."
    )
  }
  message(sprintf("  SITE_HABITAT = \"%s\" (derived from occurrences_clean).", SITE_HABITAT))
} else {
  # ==========================================================================
  # >>> SWAP IN YOUR OWN DATA <<<
  # ==========================================================================
  # Replace the block above with your own habitat-labelled occurrence table:
  #
  #   occurrences <- readRDS("path/to/your_occurrences_clean.rds")
  #     (the object produced by TaxaHabitat::assign_habitat_workflow.R, or
  #     any data frame with taxon_name, decimalLatitude, decimalLongitude,
  #     and main_habitat columns)
  #
  #   SITE_LAT     <- 34.45      # your site's centre latitude
  #   SITE_LON     <- -120.47    # your site's centre longitude
  #   SITE_HABITAT <- "Marine"   # must match a value in occurrences$main_habitat
  #
  # Set DEBUG_MODE <- FALSE above and fill in the values here.
  # ==========================================================================
  stop(
    "DEBUG_MODE is FALSE but no real occurrence data has been supplied. ",
    "Edit the 'SWAP IN YOUR OWN DATA' block in this script."
  )
}

# Output location for checkpoint files (see explicit-checkpoint pattern below)
OUT_DIR <- tempdir()
OUT_PREFIX <- "tutorial_gadus"

# ==============================================================================
# 1.  CALIBRATE THE KERNEL BANDWIDTH
# ==============================================================================
# Leave-one-block-out composition prediction chooses lambda_km (and the
# regional back-off m) empirically -- never hand-set. See calib$results for
# every candidate scored, alongside the regional/nearest_block references.
#
# A single-species occurrence table has no compositional variation for this
# calibration to predict -- every block is 100% that one species regardless
# of lambda, so mean_logloss is 0 for every candidate and the function warns
# that the smallest lambda_grid value won. That is a real, honest property of
# a single-species input, not a bandwidth genuinely near the grid's edge; a
# real multi-species dataset (like this tutorial's own Gadus/Pollachius
# fetch) shows real separation between candidates instead -- confirmed by
# actually running this script both ways, single-genus and two-genus.
# ==============================================================================

message("\n--- Step 1: Calibrating the kernel bandwidth ---")

calib <- TaxaExpect::calibrate_kernel_bandwidth(
  occurrence_data   = occurrences,
  site_habitat      = SITE_HABITAT,
  lambda_grid       = LAMBDA_GRID,
  block_size_deg    = BLOCK_SIZE_DEG,
  min_block_records = MIN_BLOCK_RECORDS
)

lambda_km <- calib$best$lambda_km

message(sprintf(
  "  Best lambda_km = %s (m = %s). %d candidate bandwidth(s) scored.",
  lambda_km, calib$best$m, nrow(calib$results)
))
print(calib$results)

# ---- Explicit checkpoint (not automatic) ------------------------------------
calib_path <- file.path(OUT_DIR, paste0(OUT_PREFIX, "_kernel_calibration.rds"))
saveRDS(calib, calib_path)
message(sprintf("  Saved: %s", calib_path))

# ==============================================================================
# 2.  ESTIMATE KERNEL PRIORS AT THE SITE
# ==============================================================================
# Site-centered kernel estimation of kernel_estimated priors: each species'
# kernel-weighted share of nearby occurrence records, shrunk toward the
# surrounding region's own composition.
# ==============================================================================

message("\n--- Step 2: Estimating kernel priors ---")

kernel_fit <- TaxaExpect::estimate_kernel_priors(
  occurrence_data = occurrences,
  site_lat        = SITE_LAT,
  site_lon        = SITE_LON,
  site_habitat    = SITE_HABITAT,
  lambda_km       = lambda_km,
  m               = calib$best$m
)

print(kernel_fit)
message(sprintf("  %d taxa in kernel_fit$priors.", nrow(kernel_fit$priors)))

# ==============================================================================
# 3.  DARK DIVERSITY FOR SPECIES NEVER LOCALLY RECORDED
# ==============================================================================
# generate_undetected_diversity() builds singleton-mirror and global-floor
# resident_undetected rows from the same kernel fit, so unrecorded diversity
# still gets a usable (not zero) prior.
# ==============================================================================

message("\n--- Step 3: Generating undetected-diversity rows ---")

undetected <- TaxaExpect::generate_undetected_diversity(kernel_fit)

message(sprintf("  %d resident_undetected row(s) generated.", nrow(undetected)))

# ==============================================================================
# 4.  ASSEMBLE THE PRIOR TABLE
# ==============================================================================
# Compositional order TaxaExpect uses throughout: species with real local
# evidence, then dark diversity. (Named-evidence and domestic/food branches
# are separate, optional steps -- see the README's "Optional" sections --
# not part of this Quick Start.)
# ==============================================================================

message("\n--- Step 4: Assembling the prior table ---")

taxaexpect_priors <- dplyr::bind_rows(kernel_fit$priors, undetected)

message(sprintf(
  "  %d prior row(s) assembled (%s).",
  nrow(taxaexpect_priors),
  paste(sprintf("%s = %d", names(table(taxaexpect_priors$prior_branch)), table(taxaexpect_priors$prior_branch)), collapse = ", ")
))

# ---- Explicit checkpoint (not automatic) ------------------------------------
# Save now so TaxaAssign's compute_posteriors_workflow.R can pick this up
# without re-running Steps 1-4 -- this is the exact readRDS() path documented
# in that script's own DEBUG_MODE block.
taxaexpect_priors_path <- file.path(OUT_DIR, paste0(OUT_PREFIX, "_taxaexpect_priors.rds"))
saveRDS(taxaexpect_priors, taxaexpect_priors_path)
message(sprintf("\n  Saved: %s", taxaexpect_priors_path))
message(sprintf(
  "  To reuse without re-running this workflow, paste:\n    taxaexpect_priors <- readRDS(\"%s\")",
  taxaexpect_priors_path
))

# ==============================================================================
# 5.  EXPLORE THE PRIOR FIELD
# ==============================================================================
# plot_theta_surface() evaluates the same kernel estimator continuously
# across a lattice, so the field can be inspected beyond the single focal
# site -- the surface's value at the site's own coordinates reproduces
# kernel_fit$priors$theta_mean exactly.
# ==============================================================================

message("\n--- Step 5: Plotting the prior field ---")

.plot_taxon <- kernel_fit$priors$taxon_name[
  which.max(kernel_fit$priors$effective_records)
]
message(sprintf("  Plotting theta surface for \"%s\" (most locally supported taxon).", .plot_taxon))

theta_surface <- TaxaExpect::plot_theta_surface(
  kernel_fit,
  occurrence_data = occurrences,
  taxon           = .plot_taxon
)

theta_surface_path <- file.path(OUT_DIR, paste0(OUT_PREFIX, "_theta_surface.rds"))
saveRDS(theta_surface, theta_surface_path)
message(sprintf("  Saved: %s", theta_surface_path))

message(
  "\nWorkflow complete. Continue with TaxaAssign's compute_posteriors_",
  "workflow.R, which reads this script's taxaexpect_priors checkpoint."
)

# ==============================================================================
# Output
# ==============================================================================
# taxaexpect_priors -- one row per taxon x prior_branch, REAL kernel-fit
#   output for the real Gadus/Pollachius, North Atlantic tutorial occurrences:
#
#   taxon_name          -- character; NA for the anonymous global-floor row
#   grid_id             -- character; site identifier (auto-generated from
#                         site_lat/site_lon when site_id is not supplied)
#   main_habitat        -- character; SITE_HABITAT, as passed to
#                         estimate_kernel_priors()
#   alpha, beta          -- numeric; Beta-distribution prior parameters
#                         TaxaAssign consumes directly
#   theta_mean, theta_sd  -- numeric; the prior probability itself and its
#                         uncertainty
#   effective_records     -- numeric; how many effectively independent nearby
#                         records support that estimate (Kish n_eff)
#   prior_branch         -- character; "kernel_estimated" or
#                         "resident_undetected" (this Quick Start does not
#                         run the optional named-evidence or domestic/food
#                         steps, so no "transport" rows here)
#
# Consumer: TaxaAssign::inst/workflows/compute_posteriors_workflow.R, which
#   reads this script's tutorial_gadus_taxaexpect_priors.rds checkpoint
#   directly (documented in that script's own DEBUG_MODE block).
# ==============================================================================
