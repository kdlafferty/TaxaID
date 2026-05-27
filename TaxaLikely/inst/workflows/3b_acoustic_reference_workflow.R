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
# DNA sequences:    build_sequence_matrix()    -- pairwise DECIPHER alignment
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
# vs. calls. If you mix types and train one model, the within-species
# distribution is artificially broadened and the model loses discrimination.
#
# The solution mirrors eDNA practice exactly:
#   - eDNA: train one model per barcode marker (12S, 16S, COI)
#   - Acoustics: train one model per recording type (song, call, etc.)
#
# Xeno-canto recording types are often multi-valued (e.g., "call, song",
# "song, growl song"). At Step 6, filter to exact matches (testid == "song")
# to keep only pure recordings of each type.
#
# --- H1, H2, H3 IN ACOUSTIC CONTEXT ---
#
#   H1: BirdNET detected the correct species. High confidence, clear gap
#       between the top candidate and the runner-up.
#
#   H2: BirdNET detected a wrong species from the same genus. Low-to-moderate
#       confidence, small gap.
#
#   H3: BirdNET detected a species from a different genus entirely.
#       Very low confidence, negligible gap.
#
# --- COMPLETE PIPELINE ---
#
#   STEP 1  Fetch reference recordings from Xeno-canto
#   STEP 2  Download audio files
#   STEP 3  Run BirdNET-Analyzer (Python, in Terminal)
#   STEP 4  Read BirdNET results into R
#   STEP 5  Build acoustic reference dataset
#   STEP 6  Train one model per recording type
#   STEP 7  Inspect and save models
#
# --- WORKING DIRECTORY ---
#
# Run this workflow from the TaxaID root directory (the parent of TaxaLikely),
# not from within TaxaLikely. All paths below are relative to TaxaID/.
# Set your working directory before starting:
#   setwd("/path/to/TaxaID")   # adjust to your actual path
#
# --- PYTHON SETUP (one-time) ---
#
# BirdNET-Analyzer requires Python 3.9+. Install dependencies once:
#   pip3 install birdnetlib librosa resampy tensorflow
#   brew install ffmpeg
#
# Verify the install worked:
#   python3 -c "import birdnetlib; print('ok')"
#
# ==============================================================================

library(TaxaLikely)
library(TaxaMatch)

# Set working directory to TaxaID root (adjust path as needed)
# setwd("/Users/lafferty/My Drive/Rscripts/projects/TaxaID")

# ---- STEP 1: Fetch reference recordings from Xeno-canto ---------------------
# Requires a free API key from xeno-canto.org/account.
# Set it once in ~/.Renviron:   XC_API_KEY=your_key_here
# Then restart R.
#
# First run with download = FALSE to confirm counts before downloading.

recs_song <- fetch_reference_recordings(
  species         = c("Turdus migratorius", "Setophaga petechia",
                      "Melospiza melodia", "Zenaida macroura"),
  quality         = c("A", "B"),
  type            = "song",
  max_per_species = 30L,
  download        = FALSE,
  download_dir    = "TaxaLikely/reference_audio/song/"
)

cat("Song recordings found:", nrow(recs_song), "\n")
print(table(recs_song$species, recs_song$quality))

# ---- STEP 2: Download audio files -------------------------------------------
# Re-run with download = TRUE once you are happy with the counts.
# Files (~5-15 MB each) are saved to download_dir.

recs_song <- fetch_reference_recordings(
  species         = c("Turdus migratorius", "Setophaga petechia",
                      "Melospiza melodia", "Zenaida macroura"),
  quality         = c("A", "B"),
  type            = "song",
  max_per_species = 30L,
  download        = TRUE,
  download_dir    = "TaxaLikely/reference_audio/song/"
)

# Drop recordings where the download failed (NA local_path).
# These will have no audio and no BirdNET results; keeping them causes
# an error in build_acoustic_reference().
n_failed <- sum(is.na(recs_song$local_path))
if (n_failed > 0L) {
  message(sprintf("Dropping %d recording(s) with failed downloads.", n_failed))
  recs_song <- recs_song[!is.na(recs_song$local_path), ]
}

cat("Downloaded:", nrow(recs_song), "recordings\n")
saveRDS(recs_song, "TaxaLikely/recs_song.rds")

# ---- STEP 3: Run BirdNET-Analyzer (Python, in Terminal) ---------------------
# BirdNET-Analyzer processes audio files and outputs one CSV per file with
# columns: Start (s), End (s), Scientific name, Common name, Confidence.
#
# Write the Python script from R, then run it from a Terminal window.
# Do NOT use system() -- R's working directory and the terminal's working
# directory can differ, causing confusing path errors.
#
# Step 3a: Write the script
writeLines(
  c(
    "from birdnetlib import Recording",
    "from birdnetlib.analyzer import Analyzer",
    "import os, csv",
    "",
    'audio_dir  = "TaxaLikely/reference_audio/song/"',
    'result_dir = "TaxaLikely/birdnet_results/song/"',
    "os.makedirs(result_dir, exist_ok=True)",
    "",
    "analyzer = Analyzer()",
    "files = [f for f in os.listdir(audio_dir)",
    '         if f.lower().endswith((".mp3", ".wav", ".flac", ".ogg"))]',
    'print(f"Processing {len(files)} files...")',
    "for i, fname in enumerate(files, 1):",
    '    print(f"  [{i}/{len(files)}] {fname}")',
    "    rec = Recording(analyzer, os.path.join(audio_dir, fname),",
    "                    lat=37.5, lon=-122.0, min_conf=0.0)",
    "    rec.analyze()",
    "    out = os.path.join(result_dir,",
    "                       os.path.splitext(fname)[0] + '.BirdNET.results.csv')",
    '    with open(out, "w", newline="") as f:',
    "        w = csv.writer(f)",
    '        w.writerow(["Start (s)", "End (s)", "Scientific name",',
    '                    "Common name", "Confidence"])',
    "        for d in rec.detections:",
    '            w.writerow([d["start_time"], d["end_time"],',
    '                        d["scientific_name"], d["common_name"],',
    '                        d["confidence"]])',
    'print("Done.")'
  ),
  "run_birdnet.py"   # written to TaxaID root (current working directory)
)
message("run_birdnet.py written. Now open a Terminal, cd to TaxaID, and run:")
message("  python3 run_birdnet.py")

# Step 3b: Run in Terminal (not from R):
#   cd "/path/to/TaxaID"
#   python3 run_birdnet.py
#
# The script prints progress ([1/120], [2/120], ...) and takes a few minutes.
# On first run it downloads the BirdNET neural network model (~100 MB).

# ---- STORAGE NOTE: delete audio files after BirdNET processing --------------
# Once BirdNET has processed the audio, the .mp3 files are no longer needed.
# Verify the CSV output is complete first:
# length(list.files("TaxaLikely/birdnet_results/song/", pattern = "\\.csv$"))
#
# Then delete:
# audio_files <- list.files("TaxaLikely/reference_audio/song/",
#                            full.names = TRUE,
#                            pattern = "\\.(mp3|wav|flac|ogg)$")
# file.remove(audio_files)
# message("Deleted ", length(audio_files), " audio files.")
#
# Keep TaxaLikely/recs_song.rds -- build_acoustic_reference() uses only the
# file stem as the join key, so stale local_path values are not a problem.

# ---- STEP 4: Read BirdNET detections into R ---------------------------------
# top_n >= 2 is required for gap computation in train_likelihood_model().

birdnet_song <- read_birdnet_output(
  "TaxaLikely/birdnet_results/song/",
  min_confidence = 0.0,
  top_n          = 3L
)
# Note: recordings with no detections produce an informational message and
# are skipped; this is normal for short or quiet recordings.

cat("BirdNET detections:", nrow(birdnet_song), "\n")
cat("Time windows:", length(unique(birdnet_song$observation_id)), "\n")
cat("Files processed:", length(unique(birdnet_song$source_file)), "\n")

# ---- STEP 5: Build acoustic reference dataset -------------------------------
# Joins BirdNET detections to Xeno-canto ground truth. Produces pair-format
# data frame (.x/.y suffixes) compatible with train_likelihood_model().
#
# exclude_background = TRUE drops detections of species listed in
# recs_song$also_species (background species audible in the recording).
# These are not H2/H3 errors -- they are correctly identified background birds.

ref_pairs_song <- build_acoustic_reference(
  birdnet_df         = birdnet_song,
  recordings_meta    = recs_song,
  rank_system        = c("genus", "species"),
  min_confidence     = 0.0,
  exclude_background = TRUE
)

cat("\n--- Reference pair dataset ---\n")
cat("Total pairs:", nrow(ref_pairs_song), "\n")
n_h1 <- sum(ref_pairs_song$species.x == ref_pairs_song$species.y, na.rm = TRUE)
cat("H1 (correct species):", n_h1, "\n")
cat("H2/H3 (wrong species):", nrow(ref_pairs_song) - n_h1, "\n")

# Inspect recording type breakdown.
# Xeno-canto types are often multi-valued (e.g., "call, song", "song, growl song").
# Pure "song" recordings are the cleanest training set for a song model.
cat("\nRecording type breakdown:\n")
print(sort(table(ref_pairs_song$testid), decreasing = TRUE))

saveRDS(ref_pairs_song, "TaxaLikely/ref_pairs_song.rds")

# ---- STEP 6: Train one model per recording type -----------------------------
# Filter to exact type matches before training. This keeps the within-species
# score distribution tight, giving the model maximum discrimination power.

song_pairs <- subset(ref_pairs_song, testid == "song")
cat("\nPure song training pairs:", nrow(song_pairs), "\n")
cat("H1:", sum(song_pairs$species.x == song_pairs$species.y, na.rm = TRUE), "\n")
cat("H2/H3:", sum(song_pairs$species.x != song_pairs$species.y, na.rm = TRUE), "\n")

model_song <- train_likelihood_model(
  raw_df        = song_pairs,
  rank_system   = c("genus", "species"),
  prior_weight  = 10.0,
  use_hierarchy = TRUE
)

interp_song <- interpret_model(model_song)

# ---- STEP 7: Inspect and save models ----------------------------------------
cat("\n--- Song model stats ---\n")
cat("Species in model:", model_song$Stats$n_species, "\n")
cat("Singletons:", model_song$Stats$n_singletons, "\n")
cat("Anchor rows:", model_song$Stats$n_anchors, "\n")

cat("\n--- Song model: hypothesis baselines ---\n")
print(interp_song$hypothesis_baselines)

# Interpretation notes:
#
# expected_match_pct is on a logit-transformed scale, not raw BirdNET
# confidence. The key diagnostic is the GAP metric:
#
#   - H1 gap >> H2 gap: the model can reliably distinguish a correct
#     detection (large gap between top and runner-up) from a wrong detection
#     (small gap). This is good even if the absolute confidence values are low.
#
#   - If H1 expected_gap_pct is near zero, BirdNET rarely produces a clear
#     winner for this species -- consider more training recordings.
#
# mu_score on the logit scale: values below 0 correspond to raw confidence
# below 50%, which indicates BirdNET struggles with this species' song.
# The gap (mu_gap) compensates: a species with modest absolute confidence
# but a consistently large gap is still reliably identified.

low_quality <- model_song$H1_Lookup[
  model_song$H1_Lookup$rank == "species" &
    model_song$H1_Lookup$mu_score < 0.0, ]
if (nrow(low_quality) > 0L) {
  cat("\nSpecies with low expected H1 logit score (<0); consider more recordings:\n")
  print(low_quality[, c("lookup_key", "mu_score", "mu_gap")])
}

saveRDS(model_song, "TaxaLikely/model_song.rds")
message("Saved TaxaLikely/model_song.rds")

# ---- (Optional) Additional type models --------------------------------------
# Repeat Steps 6-7 for other types if needed. For example, to train a
# model on "call, song" recordings (mixed but common in Xeno-canto):
#
# mixed_pairs <- subset(ref_pairs_song, testid == "call, song")
# model_mixed <- train_likelihood_model(
#   raw_df        = mixed_pairs,
#   rank_system   = c("genus", "species"),
#   prior_weight  = 10.0
# )
# saveRDS(model_mixed, "TaxaLikely/model_mixed.rds")

# ---- STEP 8: Apply to field recordings --------------------------------------
# Once trained, apply the song model to real field recordings via Workflow 4.
#
#   1. Run BirdNET-Analyzer on your field audio (same Python script, different
#      audio_dir and result_dir).
#
#   2. Read results:
#      field_birdnet <- TaxaMatch::read_birdnet_output(
#        "field_birdnet_results/",
#        min_confidence = 0.1,
#        top_n          = 3L
#      )
#
#   3. Standardize:
#      field_match <- TaxaMatch::standardize_match_data(
#        field_birdnet,
#        observation_id_col = "observation_id",
#        score_col          = "score"
#      )
#
#   4. Evaluate likelihoods:
#      result <- evaluate_likelihoods(
#        match_df     = field_match,
#        model_params = model_song
#      )
#      likelihoods <- result$likelihoods
#
# See inst/workflows/4_score_to_likelihood_workflow.R for the full Workflow 4.

message("\nWorkflow 3b complete.")
message("Next: Workflow 4 (convert BirdNET scores to likelihoods for field data)")
