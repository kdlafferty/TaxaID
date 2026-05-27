# ==============================================================================
# WORKFLOW 3b: TRAIN AN ACOUSTIC LIKELIHOOD MODEL
# ==============================================================================
# Purpose: Build an acoustic reference dataset from Xeno-canto recordings +
#   BirdNET-Analyzer output, then train a likelihood model for converting
#   BirdNET confidence scores into calibrated likelihoods.
#
# This is the acoustic analog of Workflow 3 (DNA sequences). The core idea
# is the same: compare within-species scores to cross-species scores to
# learn what a "correct match" looks like vs. a "wrong match" or an
# "absent species."
#
# --- HOW ACOUSTIC TRAINING DIFFERS FROM SEQUENCE TRAINING ---
#
# DNA sequences:    build_sequence_matrix()  -- pairwise DECIPHER alignment
# Acoustic:         build_acoustic_reference() -- BirdNET detections vs.
#                     Xeno-canto ground truth labels
#
# DNA reference:    NCBI (fetch_reference_sequences)
# Acoustic ref:     Xeno-canto (fetch_reference_recordings)
#
# DNA match unit:   ESV/ASV sequence  -->  reference accession
# Acoustic match:   time window (3s)  -->  BirdNET detection
#
# DNA barcode type: testid column (12S, COI, MiFish, etc.)
# Acoustic type:    testid column (song, call, flight call, etc.)
#
# --- THE RECORDING TYPE PROBLEM ---
#
# This is the most important design decision in acoustic likelihood modelling.
# A species' song and its call are acoustically very different signals.
# BirdNET confidence scores for a correct match are not the same for songs
# vs. calls -- songs are usually longer and more distinctive, so a
# confident song detection tends to score higher than a confident call
# detection for the same species. If you mix types and train one model,
# the within-species distribution is artificially broadened and the model
# loses discrimination power.
#
# The solution mirrors eDNA practice exactly:
#   - eDNA: train one model per barcode marker (12S, 16S, COI)
#   - Acoustics: train one model per recording type (song, call, etc.)
#
# Then at inference time, apply the matching model to each query recording.
# If you don't know a recording's type (field recordings have mixed content),
# use the model trained on the type most relevant to your target species, or
# train a pooled model and accept reduced discrimination.
#
# --- H1, H2, H3 IN ACOUSTIC CONTEXT ---
#
#   H1: BirdNET detected the correct species (the species that sings in the
#       recording). High confidence, clear gap between the top candidate and
#       the runner-up.
#
#   H2: BirdNET detected a wrong species from the same genus. For example,
#       a recording of Setophaga petechia (Yellow Warbler) and BirdNET
#       returns Setophaga coronata (Yellow-rumped Warbler). Low-to-moderate
#       confidence, small gap. This trains the model on what a "close but
#       wrong" detection looks like.
#
#   H3: BirdNET detected a species from a different genus entirely.
#       Very low confidence, negligible gap.
#
# The model learns these three distributions. At inference time, given a
# BirdNET confidence score and a gap score from a field recording, the model
# returns likelihoods for each hypothesis type.
#
# --- COMPLETE PIPELINE ---
#
#   STEP 1  Fetch reference recordings from Xeno-canto
#   STEP 2  Download audio files
#   STEP 3  Run BirdNET-Analyzer (Python, outside R)
#   STEP 4  Read BirdNET results into R
#   STEP 5  Build acoustic reference dataset (join detections to ground truth)
#   STEP 6  Train one model per recording type
#   STEP 7  Inspect and save models
#
# ==============================================================================

library(TaxaLikely)
library(TaxaMatch)

# ---- STEP 1: Fetch reference recordings from Xeno-canto ---------------------
# Xeno-canto (xeno-canto.org) is the standard open-access repository of
# bird sound recordings with species labels and quality grades. It is the
# acoustic analog of NCBI for DNA sequences.
#
# Requires a free API key from xeno-canto.org/account.
# Set it once in ~/.Renviron:   XC_API_KEY=your_key_here
# Then restart R and proceed.
#
# quality grades: A (best) to E (worst). A and B are typically sufficient.
# type: filter by recording type to avoid mixing incompatible types in one
#   fetch. Fetch separately for each type you want to model.

# --- 1a. Song model ---
recs_song <- fetch_reference_recordings(
  species         = c("Turdus migratorius", "Setophaga petechia",
                      "Melospiza melodia", "Zenaida macroura"),
  quality         = c("A", "B"),
  type            = "song",
  max_per_species = 30L,
  download        = FALSE,     # set TRUE below after confirming counts
  download_dir    = "reference_audio/song/"
)

# Inspect counts before downloading
cat("Song recordings found:", nrow(recs_song), "\n")
print(table(recs_song$species, recs_song$quality))

# --- 1b. Call model (optional) ---
# Uncomment and repeat for call recordings if you want a call model.
# recs_call <- fetch_reference_recordings(
#   species         = c("Turdus migratorius", "Setophaga petechia",
#                       "Melospiza melodia", "Zenaida macroura"),
#   quality         = c("A", "B"),
#   type            = "call",
#   max_per_species = 30L,
#   download        = FALSE,
#   download_dir    = "reference_audio/call/"
# )

# ---- STEP 2: Download audio files -------------------------------------------
# After confirming counts, re-run with download = TRUE.
# Files are named {recording_id}_{species_underscored}.mp3 and saved to
# download_dir. The local_path column in the returned data frame gives the
# full path to each downloaded file; this is the join key used later.

recs_song <- fetch_reference_recordings(
  species         = c("Turdus migratorius", "Setophaga petechia",
                      "Melospiza melodia", "Zenaida macroura"),
  quality         = c("A", "B"),
  type            = "song",
  max_per_species = 30L,
  download        = TRUE,
  download_dir    = "reference_audio/song/"
)

saveRDS(recs_song, "recs_song.rds")
message("Downloaded ", nrow(recs_song), " song recordings.")

# ---- STEP 3: Run BirdNET-Analyzer (Python, outside R) ----------------------
# BirdNET-Analyzer classifies bird vocalizations in audio files and outputs
# one CSV per audio file listing detections (species, confidence, time window).
#
# Install birdnetlib (requires Python 3.9+):
#   pip3 install birdnetlib
#
# The script below processes all .mp3 files in reference_audio/song/ and
# writes results to birdnet_results/song/. Each output file is named
# {original_name}.BirdNET.results.csv with columns:
#   Start (s), End (s), Scientific name, Common name, Confidence
#
# --- Python script (run from terminal or via system()) ---
#
# python_script <- '
# from birdnetlib import Recording
# from birdnetlib.analyzer import Analyzer
# import os, csv
#
# audio_dir  = "reference_audio/song/"
# result_dir = "birdnet_results/song/"
# os.makedirs(result_dir, exist_ok=True)
#
# analyzer = Analyzer()
# for fname in os.listdir(audio_dir):
#     if not fname.lower().endswith((".mp3", ".wav", ".flac", ".ogg")):
#         continue
#     rec = Recording(
#         analyzer,
#         os.path.join(audio_dir, fname),
#         lat     = 37.5,    # recording latitude (used for species range filter)
#         lon     = -122.0,  # recording longitude
#         min_conf= 0.1
#     )
#     rec.analyze()
#     out_path = os.path.join(result_dir, fname.replace(".mp3", ".BirdNET.results.csv"))
#     with open(out_path, "w", newline="") as f:
#         w = csv.writer(f)
#         w.writerow(["Start (s)", "End (s)", "Scientific name",
#                     "Common name", "Confidence"])
#         for d in rec.detections:
#             w.writerow([d["start_time"], d["end_time"],
#                         d["scientific_name"], d["common_name"],
#                         d["confidence"]])
# print("Done.")
# '
# writeLines(python_script, "/tmp/run_birdnet.py")
# system("python3 /tmp/run_birdnet.py")

# Alternatively, use BirdNET-GUI (desktop app) or the BirdNET command-line
# tool; any tool that produces the standard .BirdNET.results.csv format works.

# ---- STEP 4: Read BirdNET detections into R ---------------------------------
# read_birdnet_output() reads one or more BirdNET CSV files and returns a
# standardised data frame with columns:
#   observation_id  -- "{file_stem}_{start_s}-{end_s}" (unique per time window)
#   score           -- BirdNET confidence (0-1)
#   species, genus  -- resolved from Scientific name
#   source_file     -- basename of the BirdNET CSV (used as join key)
#   start_s, end_s  -- time window boundaries (seconds)
#
# top_n >= 2 is required for gap computation in train_likelihood_model().
# Setting top_n = 3 or 5 gives the model more alternatives per window to
# learn from when estimating H2/H3 parameters.

birdnet_song <- read_birdnet_output(
  "birdnet_results/song/",
  min_confidence = 0.0,    # keep all detections; filter later if needed
  top_n          = 3L      # top 3 detections per 3-second window
)

cat("BirdNET detections (song):", nrow(birdnet_song), "\n")
cat("Time windows:", length(unique(birdnet_song$observation_id)), "\n")

# ---- STEP 5: Build acoustic reference dataset -------------------------------
# build_acoustic_reference() joins BirdNET detections to the Xeno-canto
# ground-truth labels (recs_song) and produces a pair-format data frame
# that train_likelihood_model() can consume directly.
#
# Join key:
#   birdnet_song$source_file  e.g. "XC123_Turdus_migratorius.BirdNET.results.csv"
#   recs_song$local_path      e.g. "reference_audio/song/XC123_Turdus_migratorius.mp3"
#   Both reduce to file stem:   "XC123_Turdus_migratorius"
#
# Output columns:
#   id_x           -- observation_id (the time window, the query)
#   id_y           -- "{observation_id}_det{rank}" (unique per detection)
#   p_match        -- BirdNET confidence score
#   species.x      -- ground-truth species (from recs_song)
#   species.y      -- BirdNET-detected species
#   genus.x/.y     -- same pattern for genus
#   testid         -- Xeno-canto type ("song") -- the training partition key
#   recording_id   -- Xeno-canto recording ID
#   start_s, end_s -- time window boundaries
#
# The .x/.y suffix convention matches build_sequence_matrix() output, so
# train_likelihood_model() and flag_reference_errors() accept this directly.
#
# exclude_background: recordings often contain background species audible
# in the distance (listed in recs_song$also_species). BirdNET may correctly
# detect these, but labelling them as H2/H3 "errors" is wrong -- they
# really are present. exclude_background = TRUE (default) drops these rows.

ref_pairs_song <- build_acoustic_reference(
  birdnet_df      = birdnet_song,
  recordings_meta = recs_song,
  rank_system     = c("genus", "species"),
  min_confidence  = 0.0,
  exclude_background = TRUE
)

# Inspect the training dataset
cat("\n--- Reference pair dataset ---\n")
cat("Total pairs:", nrow(ref_pairs_song), "\n")

n_h1 <- sum(ref_pairs_song$species.x == ref_pairs_song$species.y,
             na.rm = TRUE)
cat("H1 (correct species):", n_h1, "\n")
cat("H2/H3 (wrong species):", nrow(ref_pairs_song) - n_h1, "\n")
cat("Unique recording types:", paste(unique(ref_pairs_song$testid), collapse = ", "), "\n")

# H1 rate per species: should be >50% for well-represented species.
# If a species has a very low H1 rate, BirdNET struggles with it --
# consider adding more recordings or lowering min_confidence.
h1_by_species <- tapply(
  ref_pairs_song$species.x == ref_pairs_song$species.y,
  ref_pairs_song$species.x,
  mean, na.rm = TRUE
)
print(round(sort(h1_by_species), 2))

saveRDS(ref_pairs_song, "ref_pairs_song.rds")

# ---- STEP 6: Train one model per recording type -----------------------------
# Train a separate model for each recording type (song, call, etc.).
# Filter by testid before passing to train_likelihood_model().
#
# This mirrors the eDNA practice of training one model per barcode marker.
# Mixing types artificially broadens the within-species score distribution
# and weakens the model's discrimination power.
#
# If your field recordings have unknown or mixed content, you can:
#   Option A: Train only on songs and apply the song model to all queries
#             (works well if most field detections are songs)
#   Option B: Train a pooled model (no filter) as a fallback
#   Option C: Train separate models and select by recording-level metadata

song_pairs <- subset(ref_pairs_song, testid == "song")
cat("\nSong training pairs:", nrow(song_pairs), "\n")

model_song <- train_likelihood_model(
  raw_df        = song_pairs,
  rank_system   = c("genus", "species"),
  prior_weight  = 10.0,
  use_hierarchy = TRUE
)

# Interpret the model
interp_song <- interpret_model(model_song)

# Check hypothesis separation:
# H1 expected confidence should be substantially higher than H2.
# If they are close (e.g., both ~0.6), the marker (song type) has limited
# power to distinguish known from unreferenced species.
cat("\n--- Song model: hypothesis baselines ---\n")
print(interp_song$hypothesis_baselines)

# ---- STEP 7: Inspect and save models ----------------------------------------
cat("\n--- Song model stats ---\n")
cat("Species in model:", model_song$Stats$n_species, "\n")
cat("Singletons:", model_song$Stats$n_singletons, "\n")
cat("Anchor rows:", model_song$Stats$n_anchors, "\n")

# Per-species expected match rate (H1 lookup table)
# Species with very low mu_score may need more training recordings.
low_quality <- model_song$H1_Lookup[
  model_song$H1_Lookup$rank == "species" &
    model_song$H1_Lookup$mu_score < 0.5, ]
if (nrow(low_quality) > 0L) {
  cat("\nSpecies with low expected H1 score (<0.5); consider more recordings:\n")
  print(low_quality[, c("lookup_key", "mu_score", "mu_gap")])
}

saveRDS(model_song, "model_song.rds")
message("Saved model_song.rds")

# ---- (Optional) Call model --------------------------------------------------
# Uncomment if you collected and processed call recordings above.
#
# call_pairs <- subset(ref_pairs_song, testid == "call")
# # Or if you built a separate ref_pairs_call object:
# # call_pairs <- ref_pairs_call
#
# model_call <- train_likelihood_model(
#   raw_df        = call_pairs,
#   rank_system   = c("genus", "species"),
#   prior_weight  = 10.0
# )
# interp_call <- interpret_model(model_call)
# saveRDS(model_call, "model_call.rds")

# ---- STEP 8: Apply to field recordings --------------------------------------
# Once trained, apply the song model to real field recordings using the
# standard TaxaLikely inference pipeline:
#
#   1. Run BirdNET-Analyzer on your field recordings (same Python script as
#      Step 3, pointing at your field audio directory).
#
#   2. Read results:
#      field_birdnet <- TaxaMatch::read_birdnet_output(
#        "field_birdnet_results/",
#        min_confidence = 0.1,
#        top_n          = 3L
#      )
#
#   3. Standardize to match object format:
#      field_match <- TaxaMatch::standardize_match_data(
#        field_birdnet,
#        observation_id_col = "observation_id",
#        score_col          = "score"
#      )
#
#   4. Evaluate likelihoods (Workflow 4):
#      result <- evaluate_likelihoods(
#        match_df    = field_match,
#        model_params = model_song    # or model_call
#      )
#      likelihoods <- result$likelihoods
#
# See inst/workflows/4_score_to_likelihood_workflow.R for the full Workflow 4.

message("\nWorkflow 3b complete.")
message("Next: Workflow 4 (convert BirdNET scores to likelihoods for field data)")
