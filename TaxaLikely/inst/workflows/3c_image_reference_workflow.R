# ==============================================================================
# WORKFLOW 3c: TRAIN AN IMAGE-CLASSIFIER LIKELIHOOD MODEL
# ==============================================================================
# Purpose: Build an image reference dataset from labeled reference images +
#   classifier output, then train a likelihood model for converting classifier
#   confidence scores into calibrated likelihoods.
#
# QUICK TEST (offline, no real images):
#   Before running this workflow on real data, try the interactive test script:
#   TaxaMatch::system.file("test_image_functions.R", package = "TaxaMatch")
#   -- or source it directly from the TaxaMatch inst/ directory.
#   It creates synthetic camera trap data and runs all reader functions +
#   build_image_reference() without internet access or actual images.
#
# This is the image analog of Workflow 3b (acoustic). The core idea is the
# same: compare within-species scores to cross-species scores to learn what a
# "correct classification" looks like vs. a "wrong classification" or an
# "absent species."
#
# --- HOW IMAGE TRAINING DIFFERS FROM SEQUENCE / ACOUSTIC TRAINING ---
#
# DNA sequences:    build_sequence_matrix()    -- pairwise DECIPHER alignment
# Acoustic:         build_acoustic_reference() -- BirdNET detections vs.
#                     Xeno-canto ground truth labels
# Image:            build_image_reference()    -- classifier detections vs.
#                     user-supplied ground truth labels
#
# DNA reference:    NCBI (fetch_reference_sequences)
# Acoustic ref:     Xeno-canto (fetch_reference_recordings)
# Image reference:  User-curated labeled images (no fetch function yet;
#                   see Step 1 below for acquisition options)
#
# DNA match unit:   ESV/ASV sequence  -->  reference accession
# Acoustic match:   time window (3s)  -->  BirdNET detection
# Image match:      image file         -->  classifier detection
#
# DNA barcode type: testid column (12S, COI, MiFish, etc.)
# Acoustic type:    testid column (song, call, flight call, etc.)
# Image type:       testid column (classifier name, camera model, etc.)
#
# --- THE IMAGE TYPE PROBLEM ---
#
# This mirrors the recording-type problem in acoustics. A species photographed
# at a camera trap (flash, dark background, motion blur) will produce different
# classifier scores than the same species photographed by hand at close range.
# If you mix image types and train one model, the within-species distribution
# is artificially broadened and the model loses discrimination.
#
# Solution (same as acoustic):
#   - Assign a `testid` to each reference image (e.g., "camera_trap")
#   - Train one model per testid
#   - Use the appropriate model when evaluating field images
#
# --- H1, H2, H3 IN IMAGE CONTEXT ---
#
#   H1: Classifier detected the correct species. High confidence, clear gap
#       between the top candidate and the runner-up.
#
#   H2: Classifier detected a wrong species from the same genus. Low-to-
#       moderate confidence, small gap.
#
#   H3: Classifier detected a species from a different genus entirely.
#       Very low confidence, negligible gap.
#
# --- COVERAGE IN IMAGE CONTEXT ---
#
# Coverage = bounding box area (width x height, normalized 0-1). A small bbox
# fraction means the animal is distant or partially visible, producing weaker
# classification evidence. Analogous to DNA alignment coverage and Xeno-canto
# quality grade. Supply bbox_cols to read_animl_output() to enable it.
#
# --- COMPLETE PIPELINE ---
#
#   STEP 1  Acquire labeled reference images
#   STEP 2  Run classifier on reference images
#   STEP 3  Read classifier results into R
#   STEP 4  Prepare ground-truth metadata table
#   STEP 5  Build image reference dataset
#   STEP 6  (Optional) Calibrate coverage filter
#   STEP 7  Train one model per image type
#   STEP 8  Inspect and save models
#   STEP 9  Validate model on reference images
#
# --- WORKING DIRECTORY ---
#
# All paths below are relative to TaxaID/ (the monorepo root).
# The script auto-detects whether you are running from TaxaID/ or from
# TaxaLikely/ and sets .taxa_root accordingly.
#
# ==============================================================================

library(TaxaLikely)
library(TaxaMatch)

# Auto-detect TaxaID root
.taxa_root <- normalizePath(
  if (basename(getwd()) == "TaxaLikely") ".." else ".",
  mustWork = FALSE
)

# ---- STEP 1: Acquire labeled reference images --------------------------------
# Unlike acoustic (Xeno-canto) or eDNA (NCBI), there is no dedicated API for
# bulk downloading camera-trap reference images. Acquisition options:
#
# OPTION A: iNaturalist research-grade observations
#   - Download from iNaturalist using the API or inaturalist.org bulk download
#   - Research-grade = community-verified species ID
#   - Example R package: rinat::get_inat_obs()
#   - Save images to reference_images/<species>/
#
# OPTION B: GBIF multimedia
#   - GBIF occurrence data often includes image URLs
#   - TaxaFetch::fetch_gbif_occurrences() returns multimedia_url when available
#   - Filter to records with images; download with download.file()
#
# OPTION C: CamtrapDP / Wildlife Insights exports
#   - Export labeled camera trap datasets from Wildlife Insights platform
#   - Sequence images are pre-labeled by expert review
#
# OPTION D: Your own labeled field images
#   - Images you have labeled from previous surveys
#   - CSV mapping image_path -> species is the required format
#
# Recommended minimum: 20 images per species, ideally 50+.
# Include confusable species pairs (same genus, similar appearance).
# Use the same camera model / image conditions as your field deployment
# to make training representative.
#
# For this workflow we assume images are already in:
#   reference_images/
# organized as flat files OR with species in subdirectory names.

ref_image_dir <- file.path(.taxa_root, "TaxaLikely/reference_images/")
message("Reference image directory: ", ref_image_dir)
message("Images found: ", length(list.files(ref_image_dir,
  pattern = "\\.(jpg|jpeg|png|tif|tiff)$", recursive = TRUE,
  ignore.case = TRUE)))

# ---- STEP 2: Run classifier on reference images ------------------------------
# The workflow shown here uses Animl (MegaDetector + SpeciesNet) via R.
# See Workflow 4 in the Score-to-Likelihood workflow for alternative classifiers
# (read_inaturalist_cv_output(), read_wildlife_insights_output()).
#
# OPTION A: Run Animl from R (CRAN package)
#   install.packages("animl")
#   library(animl)
#   animl_results <- classifyImages(
#     path          = ref_image_dir,
#     outfile       = file.path(.taxa_root, "TaxaLikely/animl_ref_results.csv"),
#     speciesModel  = "SpeciesNet"
#   )
#
# OPTION B: Run SpeciesNet directly from Python
#   pip install speciesnet
#   python -m speciesnet.scripts.run_model \
#     --folders TaxaLikely/reference_images/ \
#     --predictions_json TaxaLikely/speciesnet_ref_output.json
#   (Then use read_wildlife_insights_output() at Step 3)
#
# For demonstration, we assume Animl CSV output:
animl_ref_csv <- file.path(.taxa_root, "TaxaLikely/animl_ref_results.csv")
message("Expected classifier output: ", animl_ref_csv)

# ---- STEP 3: Read classifier results into R ----------------------------------
# top_n >= 2 required for gap computation in train_likelihood_model().
# bbox_cols enables coverage (bounding box area fraction, 0-1).

image_df <- read_animl_output(
  animl_ref_csv,
  min_confidence = 0.0,
  top_n          = 3L,
  bbox_cols      = c(w = "bbox_w", h = "bbox_h")   # adjust to your column names
)

# Filter out non-wildlife detections
image_df <- image_df[!image_df$species %in% c("empty", "blank", "human", "vehicle"), ]

cat("Classifier detections:", nrow(image_df), "\n")
cat("Images processed:", length(unique(image_df$observation_id)), "\n")
cat("Species detected:", length(unique(image_df$species)), "\n")

# Note: for iNaturalist CV or SpeciesNet JSON output, use instead:
#   image_df <- read_inaturalist_cv_output("inat_ref_results/", top_n = 3L)
#   image_df <- read_wildlife_insights_output("speciesnet_ref_output.json", top_n = 3L)

# ---- STEP 4: Prepare ground-truth metadata table ----------------------------
# images_meta must map each reference image to its true species label.
#
# OPTION A: Build from directory structure (species/image.jpg layout)
# If images are organized as ref_images/<species>/img001.jpg:
#
# img_files <- list.files(ref_image_dir, pattern = "\\.(jpg|jpeg|png)$",
#                         full.names = TRUE, recursive = TRUE, ignore.case = TRUE)
# images_meta <- data.frame(
#   image_path = img_files,
#   species    = basename(dirname(img_files)),          # parent dir = species
#   genus      = sub(" .*", "", basename(dirname(img_files))),
#   testid     = "camera_trap",
#   stringsAsFactors = FALSE
# )
#
# OPTION B: Load from a CSV you prepared manually
# images_meta <- read.csv("reference_labels.csv", stringsAsFactors = FALSE)
# Required columns: image_path, species, genus
# Optional columns: testid, quality (numeric 0-1)
#
# For demonstration, build synthetic metadata from image_df detections
# (assumes all reference images in image_df are correctly labeled):

images_meta <- data.frame(
  image_path = paste0(ref_image_dir, image_df$observation_id[
    !duplicated(image_df$observation_id)], ".jpg"),
  species    = image_df$species[!duplicated(image_df$observation_id)],
  genus      = image_df$genus[!duplicated(image_df$observation_id)],
  testid     = "camera_trap",
  stringsAsFactors = FALSE
)
# NOTE: Replace this block with your actual ground-truth labels.
# The synthetic metadata above is for illustration only.

cat("\nGround-truth images:", nrow(images_meta), "\n")
cat("Ground-truth species:", length(unique(images_meta$species)), "\n")
print(sort(table(images_meta$species), decreasing = TRUE))

# ---- STEP 5: Build image reference dataset -----------------------------------
# Joins classifier detections to ground truth. Produces pair-format data frame
# (.x/.y suffixes) compatible with train_likelihood_model().

ref_pairs <- build_image_reference(
  image_df    = image_df,
  images_meta = images_meta,
  rank_system = c("genus", "species"),
  min_confidence = 0.0
)

cat("\n--- Reference pair dataset ---\n")
cat("Total pairs:", nrow(ref_pairs), "\n")
n_h1 <- sum(ref_pairs$species.x == ref_pairs$species.y, na.rm = TRUE)
cat("H1 (correct species):", n_h1, "\n")
cat("H2/H3 (wrong species):", nrow(ref_pairs) - n_h1, "\n")

# Inspect testid breakdown.
cat("\nImage type breakdown:\n")
print(sort(table(ref_pairs$testid), decreasing = TRUE))

saveRDS(ref_pairs, file.path(.taxa_root, "TaxaLikely/ref_pairs_image.rds"))

# ---- STEP 6: (Optional) Calibrate coverage filter ---------------------------
# Coverage = bbox area fraction (from read_animl_output bbox_cols).
# Small values = distant/partial animal = weaker evidence.
# Use calibrate_coverage_filter() to find the optimal threshold.
#
# For image data the coverage is continuous (0-1), unlike acoustic grades.
# The Youden J statistic peaks where filtering low-coverage images most
# improves H1 retention relative to H2 retention.

if (any(!is.na(ref_pairs$coverage))) {
  calib <- calibrate_coverage_filter(
    pair_df    = ref_pairs,
    rank_system = c("genus", "species")
  )
  cat("\nCoverage calibration results:\n")
  print(calib[order(-calib$youden_j), ][1:5, ])

  # Quick-select threshold retaining 90% of pairs
  thresh_90 <- coverage_threshold(ref_pairs$coverage, keep_frac = 0.90)
  cat(sprintf("\n90%% retention threshold: %.3f\n", thresh_90))

  # Apply threshold before training (optional -- omit if coverage is all NA)
  # ref_pairs_filtered <- subset(ref_pairs, is.na(coverage) | coverage >= thresh_90)
  # cat("Pairs after coverage filter:", nrow(ref_pairs_filtered), "\n")
}

# ---- STEP 7: Train one model per image type ----------------------------------
# Filter to a single testid before training. This keeps the within-species
# score distribution tight, giving the model maximum discrimination power.
#
# If you have multiple image types (e.g., "camera_trap" and "hand_held"),
# train a separate model for each and apply the matching model to field data.

camera_pairs <- subset(ref_pairs, testid == "camera_trap")
cat("\nCamera trap training pairs:", nrow(camera_pairs), "\n")
cat("H1:", sum(camera_pairs$species.x == camera_pairs$species.y, na.rm = TRUE), "\n")
cat("H2/H3:", sum(camera_pairs$species.x != camera_pairs$species.y, na.rm = TRUE), "\n")

model_camera <- train_likelihood_model(
  raw_df        = camera_pairs,
  rank_system   = c("genus", "species"),
  prior_weight  = 10.0,
  use_hierarchy = TRUE
)

interp_camera <- interpret_model(model_camera)

# ---- STEP 8: Inspect and save models -----------------------------------------
cat("\n--- Camera trap model stats ---\n")
cat("Species in model:", model_camera$Stats$n_species, "\n")
cat("Singletons:", model_camera$Stats$n_singletons, "\n")
cat("Anchor rows:", model_camera$Stats$n_anchors, "\n")

cat("\n--- Model: hypothesis baselines ---\n")
print(interp_camera$hypothesis_baselines)

# Interpretation notes:
#
# expected_match_pct is on a logit-transformed scale, not raw classifier
# confidence. The key diagnostic is the GAP metric:
#
#   - H1 gap >> H2 gap: the model can reliably distinguish a correct
#     detection (large gap between top and runner-up) from a wrong detection
#     (small gap).
#
#   - If H1 expected_gap_pct is near zero, the classifier rarely produces a
#     clear winner for this species -- consider more training images.
#
# Species with low H1 scores may be visually similar to other species;
# the gap metric compensates for modest absolute confidence when the
# top prediction is consistently unambiguous.

low_quality <- model_camera$H1_Lookup[
  model_camera$H1_Lookup$rank == "species" &
    model_camera$H1_Lookup$mu_score < 0.0, ]
if (nrow(low_quality) > 0L) {
  cat("\nSpecies with low expected H1 logit score; consider more reference images:\n")
  print(low_quality[, c("lookup_key", "mu_score", "mu_gap")])
}

saveRDS(model_camera, file.path(.taxa_root, "TaxaLikely/model_camera.rds"))
message("Saved: TaxaLikely/model_camera.rds")

# ---- STEP 9: Validate model on reference images ------------------------------
# Apply the trained model back to the same images used for training.
# This is an in-sample sanity check -- not a held-out test. Its purpose is to
# confirm that the model has learned a sensible score-likelihood mapping before
# applying it to new field images.

library(TaxaMatch)
library(ggplot2)

match_df_ref <- standardize_match_data(
  image_df,
  observation_id_col = "observation_id",
  score_col          = "score",
  rank_system        = c("genus", "species")
)

model_img <- readRDS(file.path(.taxa_root, "TaxaLikely/model_camera.rds"))

lik_result <- evaluate_likelihoods(
  match_df     = match_df_ref,
  model_params = model_img,
  rank_system  = c("genus", "species"),
  n_sims       = 200L
)

likelihoods <- lik_result$likelihoods
cat("Likelihood rows:", nrow(likelihoods), "\n")
cat("Hypothesis types:\n")
print(table(likelihoods$hypothesis_type))

# Score-vs-likelihood plot
top_h1 <- likelihoods[likelihoods$hypothesis_type == "specific_candidate", ]
top_h1 <- merge(top_h1, match_df_ref[, c("observation_id", "taxon_name", "score")],
                by = c("observation_id", "taxon_name"))

# Ground-truth for colouring (correct vs wrong)
gt <- unique(ref_pairs[, c("id_x", "species.x")])
names(gt) <- c("observation_id", "true_species")
top_h1 <- merge(top_h1, gt, by = "observation_id", all.x = TRUE)
top_h1$correct <- !is.na(top_h1$true_species) &
                  (top_h1$taxon_name == top_h1$true_species)

if (nrow(top_h1) > 0L) {
  lik_hi <- 0.90
  lik_lo <- 0.50
  ticks_raw <- c(0, 0.25, 0.50, 0.75, 0.90, 0.95, 0.99)
  ticks_tr  <- asin(ticks_raw)
  top_h1$lik_tr   <- asin(top_h1$likelihood_mean)
  top_h1$score_tr <- asin(top_h1$score)
  top_h1$conf     <- pmax(0, 1 - top_h1$likelihood_sd /
                               pmax(top_h1$likelihood_mean, 0.01))
  top_h1$label <- factor(
    ifelse(is.na(top_h1$correct), "Unknown",
           ifelse(top_h1$correct, "Correct", "Wrong")),
    levels = c("Correct", "Wrong", "Unknown"))

  p1 <- ggplot(top_h1,
               aes(x = score_tr, y = lik_tr, colour = label, size = conf)) +
    geom_point(shape = 21, fill = NA, alpha = 0.85) +
    geom_hline(yintercept = asin(lik_hi), linetype = "dashed",
               colour = "grey35", linewidth = 0.6) +
    geom_hline(yintercept = asin(lik_lo), linetype = "dotted",
               colour = "grey55") +
    scale_colour_manual(
      values = c("Correct" = "steelblue", "Wrong" = "red2", "Unknown" = "grey70"),
      name = NULL) +
    scale_size_continuous(range = c(0.4, 4), name = "Confidence\n(1 \u2212 CV)") +
    scale_y_continuous(breaks = ticks_tr, labels = ticks_raw,
                       name = "H1 likelihood (mean)") +
    scale_x_continuous(breaks = ticks_tr, labels = ticks_raw,
                       name = "Classifier confidence (arcsine scale)") +
    labs(title    = "Score vs H1 likelihood",
         subtitle = "Point size = confidence (1 \u2212 CV); both axes on arcsine scale") +
    theme_bw(base_size = 11) +
    theme(legend.position = "right")
  print(p1)

  n_hi_tot   <- sum(top_h1$likelihood_mean >= lik_hi, na.rm = TRUE)
  n_hi_wrong <- sum(top_h1$label == "Wrong" &
                    top_h1$likelihood_mean >= lik_hi, na.rm = TRUE)
  cat(sprintf(
    "\nAbove %.0f%% likelihood: %d detections, %d wrong (%.1f%%)\n",
    lik_hi * 100, n_hi_tot, n_hi_wrong,
    if (n_hi_tot > 0L) 100 * n_hi_wrong / n_hi_tot else 0
  ))
}

# ---- (Optional) Add family ranks for richer H2/H3 discrimination ------------
# See Workflow 3b, Steps A-D for the analogous acoustic procedure.
# The steps are identical for image data: verify_taxon_names() on species
# column, extract family from classification_path, merge back, rebuild pairs,
# retrain at c("family", "genus", "species").

# ---- Next step ---------------------------------------------------------------
# For field images, run Workflow 4 directly.
# Pass match_df (built from your field classifier output) and model_camera.
# Skip Section 2 of Workflow 4 (remove_flagged_references -- DNA only).
# Use rank_system = c("genus", "species") throughout.
#
# Use read_animl_output(), read_inaturalist_cv_output(), or
# read_wildlife_insights_output() to ingest field classifier results.

message("\nWorkflow 3c complete.")
message("Next: Workflow 4 (convert classifier scores to likelihoods for field data)")
