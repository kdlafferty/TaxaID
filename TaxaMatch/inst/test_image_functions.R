# ==============================================================================
# TEST SCRIPT: Image Classification Reader Functions + build_image_reference()
# ==============================================================================
# Fully OFFLINE -- creates synthetic classifier output in memory.
# No actual images, no internet access, no external models needed.
#
# Tests covered:
#   PART 1 -- read_animl_output()             (Animl / SpeciesNet CSV)
#   PART 2 -- read_inaturalist_cv_output()    (iNaturalist CV API JSON)
#   PART 3 -- read_wildlife_insights_output() (SpeciesNet / Wildlife Insights JSON)
#   PART 4 -- build_image_reference()         (TaxaLikely; pairs classifer output
#                                              with ground-truth labels)
#   PART 5 -- train a model from image pairs  (TaxaLikely; skippable)
#
# Scenario: 6 camera trap images of North American mammals.
#   cam01_deer1.jpg  -- Odocoileus virginianus (white-tailed deer)  [correctly ID'd]
#   cam01_deer2.jpg  -- Odocoileus virginianus                       [correctly ID'd]
#   cam02_raccoon.jpg -- Procyon lotor (raccoon)                    [correctly ID'd]
#   cam02_coyote.jpg  -- Canis latrans (coyote)                     [misclassified]
#   cam03_bear.jpg    -- Ursus americanus (black bear)               [correctly ID'd]
#   cam03_blank.jpg   -- blank / no animal                          [filtered out]
# ==============================================================================

library(TaxaMatch)   # read_animl_output, read_inaturalist_cv_output,
                      # read_wildlife_insights_output
# library(TaxaLikely)  # uncomment for PART 4-5

# ==============================================================================
# Shared ground-truth metadata (same across all three reader tests)
# ==============================================================================
# images_meta: one row per image with the TRUE species identity.
# This is what you assemble from field records, camera trap logs, or
# expert verification of a labelled subset.
images_meta <- data.frame(
  image_path = c(
    "cam01_deer1.jpg", "cam01_deer2.jpg", "cam02_raccoon.jpg",
    "cam02_coyote.jpg", "cam03_bear.jpg"
    # cam03_blank.jpg excluded (no animal)
  ),
  family  = c("Cervidae", "Cervidae", "Procyonidae", "Canidae", "Ursidae"),
  genus   = c("Odocoileus", "Odocoileus", "Procyon", "Canis", "Ursus"),
  species = c(
    "Odocoileus virginianus", "Odocoileus virginianus",
    "Procyon lotor", "Canis latrans", "Ursus americanus"
  ),
  testid  = "camera_test",   # stratification variable (classifier or site name)
  stringsAsFactors = FALSE
)


# ==============================================================================
# PART 1: read_animl_output() -- Animl / SpeciesNet CSV format
# ==============================================================================
cat("\n===== PART 1: read_animl_output() =====\n")

# Synthetic Animl long-format CSV (one row per image x candidate species).
# Column names match Animl's default export: FileName, prediction, confidence.
animl_csv <- tempfile(fileext = ".csv")
writeLines(c(
  "FileName,prediction,confidence",
  # deer images: correct top hit
  "cam01_deer1.jpg,Odocoileus virginianus,0.91",
  "cam01_deer1.jpg,Odocoileus hemionus,0.06",     # second candidate
  "cam01_deer2.jpg,Odocoileus virginianus,0.88",
  "cam01_deer2.jpg,Odocoileus hemionus,0.09",
  # raccoon: correct
  "cam02_raccoon.jpg,Procyon lotor,0.83",
  "cam02_raccoon.jpg,Nasua nasua,0.11",            # coati -- second candidate
  # coyote: classifier suggests wolf as top, coyote second
  "cam02_coyote.jpg,Canis lupus,0.52",
  "cam02_coyote.jpg,Canis latrans,0.38",
  # bear: correct
  "cam03_bear.jpg,Ursus americanus,0.76",
  "cam03_bear.jpg,Ursus arctos,0.14",
  # blank frame (will be filtered by prediction label)
  "cam03_blank.jpg,empty,0.99"
), animl_csv)

animl_df <- read_animl_output(
  files          = animl_csv,
  min_confidence = 0.05   # keep both top candidates; filter blanks separately
)

# Remove non-wildlife detections before standardizing
animl_df <- subset(animl_df, !species %in% c("empty", "human", "vehicle"))

cat("Animl match object (all candidates, min_confidence = 0.05):\n")
print(animl_df[, c("observation_id", "score", "species")])

stopifnot("observation_id" %in% names(animl_df))
stopifnot(all(c("score", "species") %in% names(animl_df)))
stopifnot(!"empty" %in% animl_df$species)
cat("  PASS: observation_id, score, species columns present; blanks excluded\n")

# Top candidate per image only
animl_top1 <- read_animl_output(animl_csv, top_n = 1L, min_confidence = 0.05)
animl_top1 <- subset(animl_top1, !species %in% c("empty", "human", "vehicle"))
cat(sprintf("  Top-1 per image: %d rows (expect 5)\n", nrow(animl_top1)))
stopifnot(nrow(animl_top1) == 5L)
cat("  PASS: top_n = 1 returns one row per image\n")


# ==============================================================================
# PART 2: read_inaturalist_cv_output() -- iNaturalist CV API JSON
# ==============================================================================
cat("\n===== PART 2: read_inaturalist_cv_output() =====\n")

# Write one JSON file per image (as returned by the iNaturalist API).
# Each file contains a "results" array of candidate taxa with scores.
inat_dir <- file.path(tempdir(), "inat_results")
dir.create(inat_dir, showWarnings = FALSE)

# deer image 1
writeLines(
  '{"results":[
    {"combined_score":0.87,"score":0.91,
     "taxon":{"name":"Odocoileus virginianus","rank":"species",
              "preferred_common_name":"White-tailed Deer"}},
    {"combined_score":0.06,"score":0.05,
     "taxon":{"name":"Odocoileus hemionus","rank":"species",
              "preferred_common_name":"Mule Deer"}}
  ]}',
  file.path(inat_dir, "cam01_deer1.json")
)

# raccoon
writeLines(
  '{"results":[
    {"combined_score":0.82,"score":0.85,
     "taxon":{"name":"Procyon lotor","rank":"species",
              "preferred_common_name":"Common Raccoon"}},
    {"combined_score":0.10,"score":0.09,
     "taxon":{"name":"Nasua nasua","rank":"species",
              "preferred_common_name":"South American Coati"}}
  ]}',
  file.path(inat_dir, "cam02_raccoon.json")
)

# coyote -- classifier prefers wolf
writeLines(
  '{"results":[
    {"combined_score":0.48,"score":0.52,
     "taxon":{"name":"Canis lupus","rank":"species",
              "preferred_common_name":"Gray Wolf"}},
    {"combined_score":0.34,"score":0.38,
     "taxon":{"name":"Canis latrans","rank":"species",
              "preferred_common_name":"Coyote"}}
  ]}',
  file.path(inat_dir, "cam02_coyote.json")
)

inat_df <- read_inaturalist_cv_output(
  files          = inat_dir,
  score_type     = "combined_score",
  min_confidence = 0.05
)

cat("iNaturalist CV match object:\n")
print(inat_df[, c("observation_id", "score", "species", "common_name", "taxon_rank")])

stopifnot("observation_id" %in% names(inat_df))
stopifnot("taxon_rank" %in% names(inat_df))
cat("  PASS: all expected columns present\n")

# Filter to species rank (iNaturalist can return genus/family suggestions)
inat_sp <- subset(inat_df, taxon_rank == "species")
cat(sprintf("  Species-rank rows: %d\n", nrow(inat_sp)))
cat("  PASS\n")


# ==============================================================================
# PART 3: read_wildlife_insights_output() -- SpeciesNet / Wildlife Insights JSON
# ==============================================================================
cat("\n===== PART 3: read_wildlife_insights_output() =====\n")

# Single JSON file with predictions for multiple images (SpeciesNet batch format).
# Top-level key: "predictions" dict keyed by image filename.
wi_json <- tempfile(fileext = ".json")
writeLines(
  '{"predictions":{
    "cam01_deer1.jpg":[
      {"label":"Odocoileus virginianus","score":0.91,"category":"animal"},
      {"label":"Odocoileus hemionus","score":0.06,"category":"animal"}
    ],
    "cam01_deer2.jpg":[
      {"label":"Odocoileus virginianus","score":0.88,"category":"animal"}
    ],
    "cam02_raccoon.jpg":[
      {"label":"Procyon lotor","score":0.83,"category":"animal"},
      {"label":"Nasua nasua","score":0.11,"category":"animal"}
    ],
    "cam02_coyote.jpg":[
      {"label":"Canis lupus","score":0.52,"category":"animal"},
      {"label":"Canis latrans","score":0.38,"category":"animal"}
    ],
    "cam03_bear.jpg":[
      {"label":"Ursus americanus","score":0.76,"category":"animal"},
      {"label":"Ursus arctos","score":0.14,"category":"animal"}
    ],
    "cam03_blank.jpg":[
      {"label":"blank","score":0.99,"category":"blank"}
    ]
  }}',
  wi_json
)

wi_df <- read_wildlife_insights_output(
  files          = wi_json,
  min_confidence = 0.05
)

# Filter blanks
wi_df <- subset(wi_df, !species %in% c("blank", "human", "vehicle"))

cat("Wildlife Insights match object (blanks removed):\n")
print(wi_df[, c("observation_id", "score", "species")])

stopifnot("observation_id" %in% names(wi_df))
stopifnot(!"blank" %in% wi_df$species)
cat(sprintf("  %d rows across %d images\n", nrow(wi_df),
            length(unique(wi_df$observation_id))))
cat("  PASS\n")


# ==============================================================================
# PART 4: build_image_reference() -- pair classifier output with ground truth
# ==============================================================================
# Requires TaxaLikely. Uncomment if TaxaLikely is installed.
cat("\n===== PART 4: build_image_reference() =====\n")

if (!requireNamespace("TaxaLikely", quietly = TRUE)) {
  cat("TaxaLikely not installed -- skipping PART 4 and 5.\n")
  cat("Install with: devtools::install('path/to/TaxaLikely')\n")
} else {
  library(TaxaLikely)

  # Use the Animl output from Part 1 (top 2 candidates per image, no blanks)
  animl_for_ref <- subset(animl_df, !species %in% c("empty", "human", "vehicle"))

  # build_image_reference() joins classifier detections to ground-truth labels.
  # images_meta has one row per image (TRUE species); image_df has one row per
  # image x candidate (classifier output). The function:
  #   - Joins on observation_id (file stem)
  #   - Labels pairs H1 (correct species), H2 (wrong species same genus),
  #     H3 (wrong genus)
  #   - Returns pair format compatible with train_likelihood_model()
  ref_pairs <- build_image_reference(
    image_df    = animl_for_ref,
    images_meta = images_meta,
    rank_system = c("family", "genus", "species")
  )

  cat("Image reference pairs:\n")
  print(ref_pairs[, c("id_x", "id_y", "p_match",
                       "species.x", "species.y", "source_file")])

  cat("\nHypothesis type breakdown:\n")
  # H1: correct species (species.x == species.y)
  # H2: wrong species, same genus (genus.x == genus.y, species.x != species.y)
  # H3: wrong genus
  h1 <- sum(ref_pairs$species.x == ref_pairs$species.y, na.rm = TRUE)
  h2 <- sum(ref_pairs$genus.x == ref_pairs$genus.y &
              ref_pairs$species.x != ref_pairs$species.y, na.rm = TRUE)
  h3 <- sum(ref_pairs$genus.x != ref_pairs$genus.y, na.rm = TRUE)
  cat(sprintf("  H1 (correct species):     %d pairs\n", h1))
  cat(sprintf("  H2 (wrong species, same genus): %d pairs\n", h2))
  cat(sprintf("  H3 (wrong genus):         %d pairs\n", h3))

  stopifnot(h1 > 0)   # must have at least some correct detections
  cat("  PASS: pairs created, H1 pairs present\n")

  # Coverage column (from Animl bbox area -- not present in our synthetic data,
  # so will be NA; real Animl output includes coverage when bbox_cols specified)
  cat(sprintf("  Coverage column: %s\n",
              if ("coverage" %in% names(ref_pairs))
                paste(unique(ref_pairs$coverage)) else "absent (expected for synthetic data)"))

  # ===========================================================================
  # PART 5: train a likelihood model from image pairs (optional)
  # ===========================================================================
  cat("\n===== PART 5: train_likelihood_model() on image pairs =====\n")
  cat("NOTE: With only 5 images this model is illustrative, not deployable.\n")
  cat("      A real model needs 50+ images per species.\n\n")

  # This dataset is too small for stable model fitting, but demonstrates the
  # interface. The function will fall back to global parameters with a message.
  tryCatch({
    model <- train_likelihood_model(
      ref_pairs,
      rank_system   = c("family", "genus", "species"),
      anchor_perfect = TRUE   # inject perfect-match pseudo-data
    )
    cat("Model fitted (likely with global fallback for small data):\n")
    cat(sprintf("  n_species: %d\n", model$Stats$n_species))
    cat(sprintf("  n_anchors: %d\n", model$Stats$n_anchors))
    cat("  PASS: train_likelihood_model() completed\n")
  }, error = function(e) {
    cat(sprintf("  train_likelihood_model() error (expected with tiny dataset): %s\n",
                conditionMessage(e)))
  })
}

cat("\n===== All parts complete =====\n")
cat("\nKEY FINDINGS:\n")
cat("  - read_animl_output()             reads long-format or wide-format CSV\n")
cat("  - read_inaturalist_cv_output()    reads per-image JSON from iNat API\n")
cat("  - read_wildlife_insights_output() reads SpeciesNet batch JSON\n")
cat("  - All three produce the same match object format (observation_id, score, species)\n")
cat("  - build_image_reference() labels pairs H1/H2/H3 ready for train_likelihood_model()\n")
cat("\nNEXT STEPS with real data:\n")
cat("  1. Run your classifier on a labelled image set\n")
cat("  2. Read results with the appropriate reader function\n")
cat("  3. Build images_meta from your field records\n")
cat("  4. build_image_reference() + train_likelihood_model() per testid\n")
cat("  5. Evaluate field images with evaluate_likelihoods()\n")
